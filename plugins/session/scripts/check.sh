#!/usr/bin/env bash
# Claude が作業を終える前に、変更がシークレット (gitleaks)、依存の脆弱性・IaC の設定ミス (trivy)、コードの脆弱性 (semgrep) を含まないか確かめる。
# 見つかれば exit 2 で結果 (stderr) を Claude に返し、作業を続けて直させる。
# session プラグインの Stop hook (hooks/hooks.json) から実行する。gitleaks・trivy・uvx (semgrep を動かす) が無ければ確かめない
set -uo pipefail

# この hook で作業を続けさせた直後は確かめない (直せないときに終わらなくなるのを防ぐ)。
# jq が無い環境でも判定できるよう、入力の JSON は grep で見る
grep -Eq '"stop_hook_active" *: *true' && exit 0

top=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --show-toplevel 2> /dev/null) || exit 0
cd "$top" || exit 0

# コミットしていない変更 (新しいファイルを含み、消したファイルを除く)。質問に答えただけのときは何もしない
changed=$({ git diff --name-only --diff-filter=d HEAD 2> /dev/null; git ls-files --others --exclude-standard; } | sort -u)
[ -n "$changed" ] || exit 0

# CLAUDE_ENV_FILE の PATH は Bash にしか効かないため、Web で session-start.sh が mise で入れた gitleaks・trivy をここで使えるようにする
export PATH="${MISE_DATA_DIR:-${HOME}/.local/share/mise}/shims:${HOME}/.local/bin:${PATH}"

report=$(mktemp)
out=$(mktemp)
index=$(mktemp)
trap 'rm -f "$report" "$out" "$index"' EXIT

# 依存の脆弱性と IaC の設定ミス: trivy。lock ファイルか IaC を変えた dir だけを確かめる (元からある問題まで直させない)。
# 検知レベルは org の必須ワークフロー (github-workflows の trivy.yml) にそろえる。抑制は .trivyignore だけで行う
if command -v trivy > /dev/null; then
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    # 脆弱性 DB の取得が止まっても待ち続けないよう、300 秒で打ち切る。打ち切ったときは直させない
    timeout 300 trivy fs --quiet --scanners vuln,misconfig --severity MEDIUM,HIGH,CRITICAL --ignore-unfixed --exit-code 1 \
      --skip-dirs '**/.venv' --skip-dirs '**/node_modules' "$dir" > "$out" 2>&1
    case $? in
      0) ;;
      124) echo "⚠️ check: trivy が 300 秒で終わらなかったため、${dir} を確かめません" >&2 ;;
      *) { echo "### ${dir}: trivy fs"; head -n 100 "$out"; echo; } >> "$report" ;;
    esac
  done < <(grep -E '(^|/)(bun\.lockb?|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|uv\.lock|poetry\.lock|requirements[^/]*\.txt|go\.sum|Cargo\.lock|Gemfile\.lock|Dockerfile[^/]*|[^/]*\.tf|(docker-)?compose[^/]*\.ya?ml)$' <<< "$changed" |
    while IFS= read -r f; do dirname "$f"; done | sort -u)
fi

# コードの脆弱性 (SAST): semgrep。変更したファイルだけを確かめる。版は Renovate が上げる (renovate.json)。
# 検知レベルは org の必須ワークフローにそろえる。抑制は .semgrepignore だけで行い、インラインの nosemgrep は効かせない
if command -v uvx > /dev/null; then
  files=()
  while IFS= read -r f; do files+=("$f"); done <<< "$changed"
  # ルールの取得が止まっても待ち続けないよう、300 秒で打ち切る。打ち切ったときと、検出以外で失敗したとき (ルールを取得できない など) は直させない
  timeout 300 uvx semgrep@1.181.0 scan --config p/default --severity ERROR --error --metrics off --disable-version-check \
    --disable-nosem --quiet "${files[@]}" > "$out" 2>&1
  case $? in
    0) ;;
    1) { echo "### semgrep scan"; head -n 100 "$out"; echo; } >> "$report" ;;
    124) echo "⚠️ check: semgrep が 300 秒で終わらなかったため、確かめません" >&2 ;;
    *) { echo "⚠️ check: semgrep を実行できなかったため、確かめません"; tail -n 5 "$out"; } >&2 ;;
  esac
fi

# シークレット: gitleaks。gitleaks はステージした内容だけを検査するため、ステージしていない変更や新しいファイルも載せた
# 一時的なインデックスを使う (本物のインデックスは変えない)。抑制は .gitleaksignore だけで行い、インラインの gitleaks:allow は効かせない
if command -v gitleaks > /dev/null && cp "$(git rev-parse --git-path index)" "$index" 2> /dev/null; then
  export GIT_INDEX_FILE="$index"
  if git add -A > /dev/null 2>&1 &&
    ! gitleaks git --pre-commit --staged --redact --verbose --no-banner --no-color --ignore-gitleaks-allow > "$out" 2>&1; then
    { echo "### gitleaks git"; head -n 100 "$out"; echo; } >> "$report"
  fi
fi

[ -s "$report" ] || exit 0
{
  echo "変更がシークレット・脆弱性の検査を通りません。直してから終えてください。"
  echo "シークレットはファイルから消してください。.gitleaksignore・.trivyignore・.semgrepignore に書いてよいのは、ユーザーが誤検知だと確かめたものだけです"
  echo
  head -n 200 "$report"
} >&2
exit 2

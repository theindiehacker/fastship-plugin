#!/usr/bin/env bash
# Claude が作業を終える前に、変更がシークレット (gitleaks)、依存の脆弱性・IaC の設定ミス (trivy)、コードの脆弱性 (semgrep) を含まないか確かめる。
# 見つかれば exit 2 で結果 (stderr) を Claude に返し、作業を続けて直させる。
# session プラグインの Stop hook (hooks/hooks.json) から実行する。gitleaks・trivy・uvx (semgrep を動かす) が動かなければ確かめない
set -uo pipefail

input=$(cat)

# 作業を続けさせた直後 (stop_hook_active) でも、続けさせたのが別の hook (stack の lint など) なら確かめる。
# この hook 自身が一度止めた後は確かめない (直せないときに終わらなくなるのを防ぐ)。jq が無い環境でも判定できるよう、JSON は grep で見る
sid=$(grep -o '"session_id" *: *"[^"]*"' <<< "$input" | sed 's/.*"\([^"]*\)"$/\1/')
mark="${TMPDIR:-/tmp}/claude-session-check-blocked-${sid:-unknown}"
if grep -Eq '"stop_hook_active" *: *true' <<< "$input"; then
  [ -e "$mark" ] && exit 0
else
  rm -f "$mark"
fi

top=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --show-toplevel 2> /dev/null) || exit 0
cd "$top" || exit 0

# Claude がセッション中にコミット・push したものも確かめるよう、デフォルトブランチから分かれた点 (base) からの変更を見る
base=""
for ref in refs/remotes/origin/HEAD refs/remotes/origin/main refs/remotes/origin/master; do
  if git rev-parse -q --verify "$ref" > /dev/null; then
    base=$(git merge-base HEAD "$ref" 2> /dev/null)
    break
  fi
done
commits=""
[ -n "$base" ] && [ "$base" != "$(git rev-parse HEAD 2> /dev/null)" ] && commits="$base..HEAD"

# base (無ければ HEAD) からの変更と、新しいファイル (消したファイルを除く)。質問に答えただけのときは何もしない。
# 日本語などのパスがエスケープされないよう、core.quotePath を切る
changed=$({
  git -c core.quotePath=false diff --name-only --diff-filter=d "${base:-HEAD}" 2> /dev/null
  git -c core.quotePath=false ls-files --others --exclude-standard
} | sort -u)
[ -n "$changed" ] || exit 0

# 前回この検査を通ってから、コミットも作業ツリーも変わっていなければ確かめない (質問に答えただけの返事で待たせない)
state=$({
  git rev-parse HEAD 2> /dev/null
  git diff HEAD 2> /dev/null
  git ls-files --others --exclude-standard -z | xargs -0 -r sha256sum 2> /dev/null
} | sha256sum | cut -d' ' -f1)
passed="${TMPDIR:-/tmp}/claude-session-check-passed-${sid:-unknown}"
[ "$(cat "$passed" 2> /dev/null)" = "$state" ] && exit 0

# CLAUDE_ENV_FILE の PATH は Bash にしか効かないため、Web で session-start.sh が mise で入れた道具をここで使えるようにする
export PATH="${MISE_DATA_DIR:-${HOME}/.local/share/mise}/shims:${HOME}/.local/bin:${PATH}"

# Stop の hook の上限 (600 秒) より前に終えるよう、全体の締め切りを決め、各検査には残りの時間だけを渡す
DEADLINE=$(($(date +%s) + 540))
left() { echo $((DEADLINE - $(date +%s))); }
warn() { echo "⚠️ check: $*" >&2; }

report=$(mktemp)
out=$(mktemp)
index=$(mktemp)
trap 'rm -f "$report" "$out" "$index"' EXIT

# 検出したときの終了コード。道具そのものの失敗 (1 など) と分け、失敗では直させない
FOUND=3

# 依存の脆弱性と IaC の設定ミス: trivy。変更した lock ファイルと IaC のファイルだけを確かめる (元からある問題まで直させない)。
# 検知レベルは org の必須ワークフロー (github-workflows の trivy.yml) にそろえる。抑制は .trivyignore だけで行う。
# mise の shim は、そのリポジトリで設定されていないと失敗するため、実際に動くかを確かめてから使う
targets=$(grep -E '(^|/)(bun\.lockb?|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|uv\.lock|poetry\.lock|requirements[^/]*\.txt|go\.sum|Cargo\.lock|Gemfile\.lock|Dockerfile[^/]*|[^/]*\.tf|(docker-)?compose[^/]*\.ya?ml)$' <<< "$changed")
if [ -n "$targets" ] && trivy --version > /dev/null 2>&1; then
  # 脆弱性 DB は 1 回だけ取得し、各ファイルでは取得しない
  if timeout -k 10 "$(left)" trivy fs --download-db-only --quiet > "$out" 2>&1; then
    while IFS= read -r f; do
      sec=$(left)
      if [ "$sec" -le 0 ]; then
        warn "時間が足りないため、trivy で残りのファイルを確かめません"
        break
      fi
      timeout -k 10 "$sec" trivy fs --quiet --skip-db-update --scanners vuln,misconfig --severity MEDIUM,HIGH,CRITICAL \
        --ignore-unfixed --exit-code "$FOUND" "$f" > "$out" 2>&1
      case $? in
        0) ;;
        "$FOUND") { echo "### ${f}: trivy fs"; head -n 100 "$out"; echo; } >> "$report" ;;
        *) warn "trivy で ${f} を確かめられませんでした: $(tail -n 1 "$out")" ;;
      esac
    done <<< "$targets"
  else
    warn "trivy の脆弱性 DB を取得できなかったため、確かめません: $(tail -n 1 "$out")"
  fi
fi

# コードの脆弱性 (SAST): semgrep。変更したファイルだけを確かめる。版は Renovate が上げる (renovate.json)。
# 検知レベルは org の必須ワークフローにそろえる。抑制は .semgrepignore だけで行い、インラインの nosemgrep は効かせない
if uvx --version > /dev/null 2>&1 && [ "$(left)" -gt 0 ]; then
  files=()
  while IFS= read -r f; do files+=("$f"); done <<< "$changed"
  # semgrep は --error のとき、検出で 1 を返し、ルールを取得できないなどの失敗では 2 以上を返す
  timeout -k 10 "$(left)" uvx semgrep@1.181.0 scan --config p/default --severity ERROR --error --metrics off --disable-version-check \
    --disable-nosem --quiet "${files[@]}" > "$out" 2>&1
  case $? in
    0) ;;
    1) { echo "### semgrep scan"; head -n 100 "$out"; echo; } >> "$report" ;;
    *) warn "semgrep で確かめられませんでした: $(tail -n 1 "$out")" ;;
  esac
fi

# シークレット: gitleaks。コミットしていない変更と、base からのコミットを確かめる。
# gitleaks はステージした内容だけを検査するため、ステージしていない変更や新しいファイルも載せた一時的なインデックスを使う (本物のインデックスは変えない)。
# 抑制は .gitleaksignore だけで行い、インラインの gitleaks:allow は効かせない
if gitleaks version > /dev/null 2>&1 && [ "$(left)" -gt 0 ]; then
  if cp "$(git rev-parse --git-path index)" "$index" 2> /dev/null && GIT_INDEX_FILE="$index" git add -A > /dev/null 2>&1; then
    GIT_INDEX_FILE="$index" timeout -k 10 "$(left)" gitleaks git --pre-commit --staged --redact --verbose --no-banner --no-color \
      --ignore-gitleaks-allow --exit-code "$FOUND" > "$out" 2>&1
    case $? in
      0) ;;
      "$FOUND") { echo "### gitleaks git (コミットしていない変更)"; head -n 100 "$out"; echo; } >> "$report" ;;
      *) warn "gitleaks でコミットしていない変更を確かめられませんでした: $(tail -n 1 "$out")" ;;
    esac
  fi
  if [ -n "$commits" ]; then
    timeout -k 10 "$(left)" gitleaks git --log-opts="$commits" --redact --verbose --no-banner --no-color \
      --ignore-gitleaks-allow --exit-code "$FOUND" > "$out" 2>&1
    case $? in
      0) ;;
      "$FOUND") { echo "### gitleaks git (コミット済み: ${commits})"; head -n 100 "$out"; echo; } >> "$report" ;;
      *) warn "gitleaks でコミット済みの変更を確かめられませんでした: $(tail -n 1 "$out")" ;;
    esac
  fi
fi

if [ ! -s "$report" ]; then
  rm -f "$mark"
  echo "$state" > "$passed"
  exit 0
fi
touch "$mark"
{
  echo "変更がシークレット・脆弱性の検査を通りません。直してから終えてください。"
  echo "シークレットはファイルから消してください。コミット済みのものは、キーを無効にして履歴から消す必要があるため、ユーザーに伝えてください。"
  echo ".gitleaksignore・.trivyignore・.semgrepignore に書いてよいのは、ユーザーが誤検知だと確かめたものだけです"
  echo
  head -n 200 "$report"
} >&2
exit 2

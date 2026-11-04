#!/usr/bin/env bash
# Claude が作業を終える前に、変更がシークレット (gitleaks)、依存の脆弱性・IaC の設定ミス (trivy)、コードの脆弱性 (semgrep) を含まないか確かめる。
# 見つかれば exit 2 で結果 (stderr) を Claude に返し、作業を続けて直させる。
# session プラグインの Stop hook (hooks/hooks.json) から実行する。gitleaks・trivy・uvx (semgrep を動かす) が動かなければ確かめない
set -uo pipefail

input=$(cat)

top=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --show-toplevel 2> /dev/null) || exit 0
cd "$top" || exit 0

# 止めた印と、前回通った状態を、セッションごとに覚える。ほかのユーザーが書き換えられないよう、/tmp ではなく .git の中 (0700) に置く。
# session_id が無いか想定外の文字を含むときは覚えない。jq が無い環境でも読めるよう、JSON は grep で見る
sid=$(grep -o '"session_id" *: *"[^"]*"' <<< "$input" | sed 's/.*"\([^"]*\)"$/\1/')
case $sid in '' | *[!A-Za-z0-9_-]*) sid="" ;; esac
mark=""
passed=""
state_dir=$(git rev-parse --git-path claude-hooks 2> /dev/null)
# session と stack の Stop は同時に動くため、片方の mkdir が負けても、できた dir を使う
if [ -n "$sid" ] && [ -n "$state_dir" ] && { mkdir -m 700 "$state_dir" 2> /dev/null || [ -d "$state_dir" ]; }; then
  find "$state_dir" -type f -mtime +7 -delete 2> /dev/null
  mark="$state_dir/session-check-blocked-$sid"
  passed="$state_dir/session-check-passed-$sid"
fi

# 作業を続けさせた直後 (stop_hook_active) でも、続けさせたのが別の hook (stack の lint など) なら確かめる。
# この hook 自身が一度止めた後は確かめない (直せないときに終わらなくなるのを防ぐ)。印を使えないときは、続けさせた直後はいつも確かめない
if grep -Eq '"stop_hook_active" *: *true' <<< "$input"; then
  { [ -z "$mark" ] || [ -e "$mark" ]; } && exit 0
elif [ -n "$mark" ]; then
  rm -f "$mark"
fi

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
[ -n "$passed" ] && [ "$(cat "$passed" 2> /dev/null)" = "$state" ] && exit 0

# CLAUDE_ENV_FILE の PATH は Bash にしか効かないため、Web で session-start.sh が mise で入れた道具をここで使えるようにする
export PATH="${MISE_DATA_DIR:-${HOME}/.local/share/mise}/shims:${HOME}/.local/bin:${PATH}"

# Stop の hook の上限 (600 秒) より前に終えるよう、全体の締め切りを決め、各検査には残りの時間だけを渡す
DEADLINE=$(($(date +%s) + 540))
left() { echo $((DEADLINE - $(date +%s))); }
# 道具の失敗や時間切れで確かめきれなかったときは、通ったと覚えない (次の Stop で確かめ直す)
incomplete=""
warn() {
  incomplete=1
  echo "⚠️ check: $*" >&2
}

report=$(mktemp)
out=$(mktemp)
index=$(mktemp)
trap 'rm -f "$report" "$out" "$index"' EXIT

# 検出したときの終了コード。道具そのものの失敗 (1 など) と分け、失敗では直させない
FOUND=3

# 依存の脆弱性と IaC の設定ミス: trivy。変更した lock ファイルと IaC のファイルだけを確かめる (元からある問題まで直させない)。
# 検知レベルは org の必須ワークフロー (github-workflows の trivy.yml) にそろえる。抑制は .trivyignore だけで行う。
# mise の shim は、そのリポジトリで設定されていないと失敗するため、実際に動くかを確かめてから使う
targets=$(grep -E '(^|/)(bun\.lockb?|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|uv\.lock|poetry\.lock|requirements[^/]*\.txt|go\.mod|go\.sum|Cargo\.lock|Gemfile\.lock|Dockerfile[^/]*|[^/]*\.tf|(docker-)?compose[^/]*\.ya?ml)$' <<< "$changed")
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
# 検知レベルは org の必須ワークフローにそろえる。抑制は .semgrepignore だけで行い、インラインの nosemgrep は効かせない。
# 起動とルールの取得に時間がかかるため、コード以外 (文書・画像・lock など) だけを変えたときは動かさない
code=$(grep -Ev '\.(md|mdx|txt|rst|png|jpe?g|gif|svg|ico|webp|pdf|csv|lock|lockb|woff2?|ttf|eot|mp4|mov|zip|gz)$' <<< "$changed")
if [ -n "$code" ] && uvx --version > /dev/null 2>&1 && [ "$(left)" -gt 0 ]; then
  files=()
  while IFS= read -r f; do files+=("$f"); done <<< "$code"
  # semgrep は --error のとき、検出で 1 を返し、ルールを取得できないなどの失敗では 2 以上を返す
  timeout -k 10 "$(left)" uvx semgrep@1.182.1 scan --config p/default --severity ERROR --error --metrics off --disable-version-check \
    --disable-nosem --quiet "${files[@]}" > "$out" 2>&1
  case $? in
    0) ;;
    1) { echo "### semgrep scan"; head -n 100 "$out"; echo; } >> "$report" ;;
    *) warn "semgrep で確かめられませんでした: $(tail -n 1 "$out")" ;;
  esac
fi

# シークレット: gitleaks。コミットしていない変更と、base からのコミットを確かめる。
# HEAD だけを載せた一時的なインデックスに、新しいファイル (ステージ済みを含む) を intent-to-add で足し、作業ツリーとの差分 (ステージ済み・新しいファイルを含む) を調べる。
# 本物のインデックスは変えず、新しいファイルの中身を .git に書き込まない。抑制は .gitleaksignore だけで行い、インラインの gitleaks:allow は効かせない
if gitleaks version > /dev/null 2>&1 && [ "$(left)" -gt 0 ]; then
  if GIT_INDEX_FILE="$index" git read-tree HEAD 2> /dev/null &&
    { git ls-files --others --exclude-standard -z; git diff --cached --name-only --diff-filter=A -z HEAD; } |
    GIT_INDEX_FILE="$index" xargs -0 -r git add -N -- > /dev/null 2>&1; then
    GIT_INDEX_FILE="$index" timeout -k 10 "$(left)" gitleaks git --pre-commit --redact --verbose --no-banner --no-color \
      --ignore-gitleaks-allow --exit-code "$FOUND" > "$out" 2>&1
    case $? in
      0) ;;
      "$FOUND") { echo "### gitleaks git (コミットしていない変更)"; head -n 100 "$out"; echo; } >> "$report" ;;
      *) warn "gitleaks でコミットしていない変更を確かめられませんでした: $(tail -n 1 "$out")" ;;
    esac
  fi
  # コミット済みのものは、履歴を書き換えるまで毎回見つかる。同じものでは止めないよう、このセッションで伝えた fingerprint を覚え、新しいものだけで止める
  if [ -n "$commits" ]; then
    timeout -k 10 "$(left)" gitleaks git --log-opts="$commits" --redact --verbose --no-banner --no-color \
      --ignore-gitleaks-allow --exit-code "$FOUND" > "$out" 2>&1
    case $? in
      0) ;;
      "$FOUND")
        reported="${state_dir}/session-check-reported-${sid}"
        found=$(sed -n 's/^Fingerprint: *//p' "$out" | sort -u)
        new=$found
        [ -z "$sid" ] || new=$(comm -23 <(echo "$found") <(sort -u "$reported" 2> /dev/null))
        if [ -n "$new" ]; then
          { echo "### gitleaks git (コミット済み: ${commits})"; head -n 100 "$out"; echo; } >> "$report"
          [ -z "$sid" ] || echo "$new" >> "$reported"
        else
          echo "⚠️ check: コミット済みのシークレット (このセッションで伝え済み) が、まだ履歴に残っています" >&2
        fi
        ;;
      *) warn "gitleaks でコミット済みの変更を確かめられませんでした: $(tail -n 1 "$out")" ;;
    esac
  fi
fi

if [ ! -s "$report" ]; then
  [ -z "$mark" ] || rm -f "$mark"
  [ -z "$passed" ] || [ -n "$incomplete" ] || echo "$state" > "$passed"
  exit 0
fi
[ -z "$mark" ] || touch "$mark"
{
  echo "変更がシークレット・脆弱性の検査を通りません。直してから終えてください。"
  echo "シークレットはファイルから消してください。コミット済みのものは、キーを無効にして履歴から消す必要があるため、ユーザーに伝えてください。"
  echo ".gitleaksignore・.trivyignore・.semgrepignore に書いてよいのは、ユーザーが誤検知だと確かめたものだけです"
  echo
  head -n 200 "$report"
} >&2
exit 2

#!/usr/bin/env bash
# Claude Code on the web のセッション開始時に、mise・ツール・lefthook のフックと、リポジトリの依存を入れ、最後に compose のサービスを起動する。
# session プラグインの SessionStart hook (hooks/hooks.json) から実行する。
# compose のビルドが、入れている途中の node_modules・.venv を読まないよう、起動 (start-services.sh) はこの後に順に行う
# stdout は Claude のコンテキストに入るため、進捗の出力は stderr に回す
set -uo pipefail

# ローカルでは何もしない（ローカルは task init などでセットアップする）
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

# Web の既定のネットワークでは mise.run が通らないため、GitHub Releases から入れる。版と SHA-256 は Renovate が更新する (renovate.json)
# renovate: datasource=github-release-attachments depName=jdx/mise
MISE_VERSION="v2026.10.19"
MISE_SHA256="3162760f40b6b5f706c60641e4ef5ee7322bc6c54f72fc26a7111b337aa18d9d"

BIN_DIR="${HOME}/.local/bin"
SHIMS_DIR="${MISE_DATA_DIR:-${HOME}/.local/share/mise}/shims"
PATH_LINE="export PATH=\"${SHIMS_DIR}:${BIN_DIR}:\$PATH\""

# 通信が止まると、コマンドは hook の上限 (600 秒) まで待ち続け、セッションが始まらない。
# 全体の締め切りを上限より前に決め、各手順には残りの時間だけを渡す。compose の起動の時間を残すため、この script の手順は締め切りの 180 秒前までにする
DEADLINE=$(($(date +%s) + 570))
left() { echo $((DEADLINE - 180 - $(date +%s))); }

# <秒> と残りの時間の短い方で打ち切る。打ち切ったときだけ 1 回やり直す (やり直しは、途中まで取得したキャッシュを使うため速い)。
# 打ち切り以外の失敗 (lock の食い違い・ビルドの失敗など) は、やり直しても同じなので、やり直さない
retry() { # <秒> <コマンド>...
  local max=$1 sec status=124 try
  shift
  for try in 1 2; do
    sec=$(left)
    [ "$sec" -lt "$max" ] || sec=$max
    if [ "$sec" -le 0 ]; then
      echo "⚠️ session-start: 時間が足りないため、実行しません: $*" >&2
      return 124
    fi
    timeout -k 10 "$sec" "$@"
    status=$?
    case $status in
      124 | 137) [ "$try" = 1 ] && echo "⚠️ session-start: ${sec} 秒で終わらなかったため、やり直します: $*" >&2 ;;
      *) return "$status" ;;
    esac
  done
  return "$status"
}

install_mise() {
  [ "$("${BIN_DIR}/mise" --version 2>/dev/null | cut -d' ' -f1)" = "${MISE_VERSION#v}" ] && return 0
  local tmp status sec
  sec=$(left)
  [ "$sec" -gt 0 ] || return 1
  tmp=$(mktemp) &&
    # 30 秒の間 1 KB/s を下回ったら止まったとみなし、打ち切ってやり直す (遅いだけなら打ち切らない)。
    # curl の --max-time は 1 回ごとの上限なので、やり直しを含めた全体は timeout で残りの時間に収める
    timeout -k 10 "$sec" curl -fsSL --connect-timeout 10 --speed-limit 1024 --speed-time 30 --retry 3 -o "$tmp" \
      "https://github.com/jdx/mise/releases/download/${MISE_VERSION}/mise-${MISE_VERSION}-linux-x64" &&
    echo "${MISE_SHA256}  ${tmp}" | sha256sum -c --quiet - &&
    mkdir -p "$BIN_DIR" &&
    install -m 755 "$tmp" "${BIN_DIR}/mise"
  status=$?
  rm -f "$tmp"
  return "$status"
}

setup_mise() {
  [ -f mise.toml ] || return 0

  # mise の postinstall（lefthook install）からツールを呼べるようにする
  export PATH="${SHIMS_DIR}:${BIN_DIR}:${PATH}"

  # ツールは mise.lock の直接ダウンロードの URL から入る（api.github.com はセッション外のリポジトリで 403 になる）
  if install_mise && mise trust . > /dev/null && retry 300 mise install --yes >&2; then
    # Claude が実行する git commit から lefthook と task を呼べるよう、後続の Bash に PATH を渡す。
    # セッションの再開でも実行されるため、同じ行を重ねて書かない
    if [ -n "${CLAUDE_ENV_FILE:-}" ] && ! grep -qxF "$PATH_LINE" "$CLAUDE_ENV_FILE" 2>/dev/null; then
      echo "$PATH_LINE" >> "$CLAUDE_ENV_FILE"
    fi
  else
    # 失敗してもセッションは止めない（最後の砦は CI の必須チェック）
    echo "⚠️ session-start: mise のセットアップに失敗しました。pre-commit は動きませんが、PR の CI では必須チェックが動きます" >&2
  fi
}

# stack プラグインの PostToolUse・Stop の hook が使う Biome・Ruff・Pyright などを、lock ファイルの版で入れる
install_deps() {
  local lock dir
  while IFS= read -r lock; do
    dir=$(dirname "$lock")
    case "$lock" in
      *uv.lock)
        # pyright (PyPI) は初回の実行で本体を取得するため、ここで済ませておく
        retry 180 uv sync --frozen --directory "$dir" >&2 &&
          { [ ! -x "$dir/.venv/bin/pyright" ] || retry 120 "$dir/.venv/bin/pyright" --version >&2; } ;;
      *)
        retry 180 bun install --frozen-lockfile --cwd "$dir" >&2 ;;
    esac || echo "⚠️ session-start: ${lock} の依存を入れられませんでした。lint・型チェックの hook はこの dir を確かめません" >&2
  done < <(git ls-files -- '*bun.lock' '*bun.lockb' '*uv.lock' 2>/dev/null)
}

setup_mise
install_deps
SESSION_DEADLINE=$DEADLINE bash "$(dirname "${BASH_SOURCE[0]}")/start-services.sh"
exit 0

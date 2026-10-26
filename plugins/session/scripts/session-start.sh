#!/usr/bin/env bash
# Claude Code on the web のセッション開始時に、mise・ツール・lefthook のフックと、リポジトリの依存を入れる。
# session プラグインの SessionStart hook (hooks/hooks.json) から実行する。
# stdout は Claude のコンテキストに入るため、進捗の出力は stderr に回す
set -uo pipefail

# ローカルでは何もしない（ローカルは task init などでセットアップする）
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

# Web の既定のネットワークでは mise.run が通らないため、GitHub Releases から入れる。版と SHA-256 は Renovate が更新する (renovate.json)
# renovate: datasource=github-release-attachments depName=jdx/mise
MISE_VERSION="v2026.10.17"
MISE_SHA256="fe6dd17e68e09682b31d2e7bb7bb755d22636ac1af5d94621e300f2ca9e9fe8a"

BIN_DIR="${HOME}/.local/bin"
SHIMS_DIR="${MISE_DATA_DIR:-${HOME}/.local/share/mise}/shims"
PATH_LINE="export PATH=\"${SHIMS_DIR}:${BIN_DIR}:\$PATH\""

# 通信が止まると、コマンドは hook の上限 (600 秒) まで待ち続け、セッションが始まらない。
# <秒> で打ち切り、1 回だけやり直す (やり直しは、途中まで取得したキャッシュを使うため速い)
retry() { # <秒> <コマンド>...
  local sec=$1
  shift
  timeout -k 10 "$sec" "$@" && return 0
  echo "⚠️ session-start: やり直します: $*" >&2
  timeout -k 10 "$sec" "$@"
}

install_mise() {
  [ "$("${BIN_DIR}/mise" --version 2>/dev/null | cut -d' ' -f1)" = "${MISE_VERSION#v}" ] && return 0
  local tmp status
  tmp=$(mktemp) &&
    # 30 秒の間 100 KB/s を下回ったら止まったとみなし、打ち切ってやり直す
    curl -fsSL --connect-timeout 10 --speed-limit 102400 --speed-time 30 --retry 3 -o "$tmp" \
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
exit 0

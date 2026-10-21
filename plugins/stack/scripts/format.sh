#!/usr/bin/env bash
# Claude が編集したファイルを、リポジトリに入っている Biome・Ruff で整形する。
# lint の自動修正はしない (次の編集で使う予定の import などを消してしまうため)。lint は Stop の hook (check.sh) で確かめる。
# stack プラグインの PostToolUse hook (hooks/hooks.json) から実行する。道具が無ければ何もしない
set -uo pipefail

command -v jq > /dev/null || exit 0
file=$(jq -r '.tool_input.file_path // empty')
root="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$file" ] || exit 0
case "$file" in "$root"/*) ;; *) exit 0 ;; esac

find_up() { # <ファイル> <相対パス>  ファイルの dir から root までさかのぼり、<相対パス> がある dir を出力する
  local dir
  dir=$(dirname "$1")
  while :; do
    if [ -e "$dir/$2" ]; then
      echo "$dir"
      return 0
    fi
    if [ "$dir" = "$root" ] || [ "$dir" = / ]; then
      return 1
    fi
    dir=$(dirname "$dir")
  done
}

case "$file" in
  *.js | *.jsx | *.ts | *.tsx | *.mjs | *.cjs | *.mts | *.cts | *.json | *.jsonc | *.css | *.graphql)
    dir=$(find_up "$file" node_modules/.bin/biome) || exit 0
    (cd "$dir" && node_modules/.bin/biome format --write --no-errors-on-unmatched "$file") > /dev/null 2>&1
    ;;
  *.py | *.pyi)
    dir=$(find_up "$file" .venv/bin/ruff) || exit 0
    # --force-exclude: 設定で除外したファイル (マイグレーションなど) は、パスを渡しても整形しない
    (cd "$dir" && .venv/bin/ruff format --force-exclude --quiet "$file") > /dev/null 2>&1
    ;;
esac
exit 0

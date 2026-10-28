#!/usr/bin/env bash
# shadcn の CLI を、公開から 7 日たった版 (shadcn が使う依存も) で動かす。
# stack プラグインの MCP (.mcp.json) と、スキル (/stack:ui・/stack:setup) から実行する。
# 使い方: bash shadcn.sh <shadcn の版 (latest など)> <shadcn の引数>...
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "使い方: bash shadcn.sh <shadcn の版 (latest など)> <shadcn の引数>..." >&2
  exit 2
fi
version=$1
shift

# MCP は shadcn/ui を入れたリポジトリでだけ起動する。UI の無いリポジトリで取得・常駐しないため
if [ "${1:-}" = mcp ]; then
  root="${CLAUDE_PROJECT_DIR:-$PWD}"
  # components.json を 4 階層 (apps/web/components.json など) まで探す。commit 前のもの (init した直後) も数え、.gitignore で外したもの (node_modules など) は数えない
  if top=$(git -C "$root" rev-parse --show-toplevel 2> /dev/null); then
    # Claude Code をサブ dir で開いても、リポジトリ全体を探す。glob では * が / をまたがない
    pathspec=(':(glob)components.json' ':(glob)*/components.json' ':(glob)*/*/components.json' ':(glob)*/*/*/components.json')
    list=$(git -C "$top" ls-files -- "${pathspec[@]}" 2> /dev/null || true)
    # commit 前のものは、commit 済みのものが無いときだけ探す (未追跡のファイルを毎回たどらないため)
    [ -n "$list" ] || list=$(git -C "$top" ls-files --others --exclude-standard -- "${pathspec[@]}" 2> /dev/null || true)
  else
    top=$root
    list=$(find "$root" -maxdepth 4 -name node_modules -prune -o -name components.json -print 2> /dev/null || true)
  fi
  # shadcn/ui (React) のものだけを数える。shadcn-vue・shadcn-svelte も同じ名前のファイルを使うため、$schema で見分ける
  found=
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    case "$file" in /*) ;; *) file="$top/$file" ;; esac
    if grep -q 'ui\.shadcn\.com/schema' "$file" 2> /dev/null; then
      found=$file
      break
    fi
  done <<< "$list"
  if [ -z "$found" ]; then
    echo "shadcn/ui の components.json が無いので、shadcn の MCP は起動しません (shadcn/ui を入れたリポジトリでだけ起動します)" >&2
    exit 1
  fi
fi

# --minimum-release-age は bun 1.4.4 から。古い bun はこの flag を無視し、7 日待たずに動くため使わない
new_enough() { # <bun のパス>
  local v
  v=$("$1" --version 2> /dev/null) || return 1
  [[ $v =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]] || return 1
  local major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}
  # 1.4.4 の正式版より前の canary (1.4.4-canary.*) も古いものとして扱う
  ((major > 1 || (major == 1 && (minor > 4 || (minor == 4 && patch >= 4))))) && [[ $v != 1.4.4-* ]]
}

# この dir の mise.toml の bun、PATH の bun の順に、1.4.4 以上のものを使う。どちらかが古くても、もう一方で動かせるようにする
bun=
tried=
for candidate in "$(mise which bun 2> /dev/null || true)" "$(command -v bun || true)"; do
  [ -n "$candidate" ] || continue
  if new_enough "$candidate"; then
    bun=$candidate
    break
  fi
  tried="$tried $candidate ($("$candidate" --version 2>&1 | tail -n 1))"
done
if [ -z "$bun" ]; then
  if [ -z "$tried" ]; then
    echo "bun が見つかりません。bun 1.4.4 以上を入れてください" >&2
  else
    echo "bun 1.4.4 以上が見つかりません (見つかった bun:$tried)。公開から 7 日待つ設定 (--minimum-release-age) は bun 1.4.4 からなので、bun を上げてください" >&2
  fi
  exit 1
fi

# 7 日 (renovate の minimumReleaseAge と同じ)。古い bun が値をパッケージ名と読まないよう、= でつないで 1 語で渡す
exec "$bun" x --bun --minimum-release-age=604800 "shadcn@$version" "$@"

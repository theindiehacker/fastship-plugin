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
root="${CLAUDE_PROJECT_DIR:-$PWD}"

# MCP は shadcn/ui を入れたリポジトリ (components.json がある) でだけ起動する。UI の無いリポジトリで取得・常駐しないため
if [ "${1:-}" = mcp ]; then
  # 4 階層 (apps/web/components.json など) まで探す。commit 前のもの (init した直後) も数え、.gitignore で外したもの (node_modules など) は数えない
  if git -C "$root" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    # :(top) で、Claude Code をサブ dir で開いてもリポジトリ全体を探す。glob では * が / をまたがない
    pathspec=(':(top,glob)components.json' ':(top,glob)*/components.json' ':(top,glob)*/*/components.json' ':(top,glob)*/*/*/components.json')
    found=$(git -C "$root" ls-files -- "${pathspec[@]}" 2> /dev/null || true)
    # commit 前のものは、commit 済みのものが無いときだけ探す (未追跡のファイルを毎回たどらないため)
    [ -n "$found" ] || found=$(git -C "$root" ls-files --others --exclude-standard -- "${pathspec[@]}" 2> /dev/null || true)
  else
    found=$(find "$root" -maxdepth 4 -name node_modules -prune -o -name components.json -print -quit 2> /dev/null || true)
  fi
  if [ -z "$found" ]; then
    echo "components.json が無いので、shadcn の MCP は起動しません (shadcn/ui を入れたリポジトリでだけ起動します)" >&2
    exit 1
  fi
fi

# リポジトリの mise.toml の bun を先に使う。Claude Code の PATH には、mise で切り替える前の bun があることがあるため
bun=$(cd "$root" && mise which bun 2> /dev/null) || bun=$(command -v bun) || {
  echo "bun が見つかりません。bun 1.4.4 以上を入れてください" >&2
  exit 1
}

# --minimum-release-age は bun 1.4.4 から。古い bun はこの flag を無視し、7 日待たずに動くため止める
if ! bun_version=$("$bun" --version 2> /dev/null); then
  echo "bun --version が失敗しました: $("$bun" --version 2>&1 | tail -n 1)" >&2
  exit 1
fi
if ! [[ $bun_version =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
  echo "bun の版 ($bun_version) を読めません。bun 1.4.4 以上を入れてください" >&2
  exit 1
fi
major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}
# 1.4.4 の正式版より前の canary (1.4.4-canary.*) も古いものとして扱う
if ((major < 1 || (major == 1 && (minor < 4 || (minor == 4 && patch < 4))))) || [[ $bun_version == 1.4.4-* ]]; then
  echo "bun $bun_version ($bun) は古く、公開から 7 日待つ設定 (--minimum-release-age) が効きません。bun 1.4.4 以上に上げてください" >&2
  exit 1
fi

# 7 日 (renovate の minimumReleaseAge と同じ)。古い bun が値をパッケージ名と読まないよう、= でつないで 1 語で渡す
exec "$bun" x --bun --minimum-release-age=604800 "shadcn@$version" "$@"

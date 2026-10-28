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

# MCP は shadcn/ui を入れたリポジトリ (components.json がある) でだけ起動する。UI の無いリポジトリで取得・常駐しないため
if [ "${1:-}" = mcp ]; then
  root="${CLAUDE_PROJECT_DIR:-$PWD}"
  if git -C "$root" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    found=$(git -C "$root" ls-files -- '*components.json' | head -n 1)
  else
    found=$([ -f "$root/components.json" ] && echo components.json || true)
  fi
  if [ -z "$found" ]; then
    echo "components.json が無いので、shadcn の MCP は起動しません (shadcn/ui を入れたリポジトリでだけ起動します)" >&2
    exit 1
  fi
fi

# --minimum-release-age は bun 1.4.4 から。古い bun はこの flag を無視し、7 日待たずに動くため止める
if ! bun_version=$(bun --version 2> /dev/null); then
  echo "bun が見つかりません。bun 1.4.4 以上を入れてください" >&2
  exit 1
fi
if ! [[ $bun_version =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
  echo "bun の版 ($bun_version) を読めません。bun 1.4.4 以上を入れてください" >&2
  exit 1
fi
major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}
if ((major < 1 || (major == 1 && (minor < 4 || (minor == 4 && patch < 4))))); then
  echo "bun $bun_version は古く、公開から 7 日待つ設定 (--minimum-release-age) が効きません。bun 1.4.4 以上に上げてください" >&2
  exit 1
fi

# 7 日 (renovate の minimumReleaseAge と同じ)。古い bun が値をパッケージ名と読まないよう、= でつないで 1 語で渡す
exec bunx --bun --minimum-release-age=604800 "shadcn@$version" "$@"

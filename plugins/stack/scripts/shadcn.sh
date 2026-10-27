#!/usr/bin/env bash
# shadcn の CLI を、公開から 7 日たった版 (shadcn が使う依存も) で動かす。
# stack プラグインの MCP (.mcp.json) と、スキル (/stack:ui・/stack:setup) から実行する。
# 使い方: bash shadcn.sh <shadcn の版 (latest など)> <shadcn の引数>...
set -euo pipefail

version=$1
shift

# --minimum-release-age は bun 1.4.4 から。古い bun はこの flag を無視し、7 日待たずに動くため止める
if ! bun_version=$(bun --version 2> /dev/null); then
  echo "bun が見つかりません。bun 1.4.4 以上を入れてください" >&2
  exit 1
fi
IFS=. read -r major minor patch <<< "${bun_version%%-*}"
if ((major < 1 || (major == 1 && (minor < 4 || (minor == 4 && patch < 4))))); then
  echo "bun $bun_version は古く、公開から 7 日待つ設定 (--minimum-release-age) が効きません。bun 1.4.4 以上に上げてください" >&2
  exit 1
fi

# 7 日 (renovate の minimumReleaseAge と同じ)。古い bun が値をパッケージ名と読まないよう、= でつないで 1 語で渡す
exec bunx --bun --minimum-release-age=604800 "shadcn@$version" "$@"

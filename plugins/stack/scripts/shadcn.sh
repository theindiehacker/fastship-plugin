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

# 数える components.json か。shadcn/ui の $schema か、$schema が無ければ React の印 (tsx・rsc) がある (shadcn-vue・shadcn-svelte なども同じ名前のファイルを使うため)
is_shadcn_ui() { # <パス>
  [ -f "$1" ] || return 1
  if grep -q '"[$]schema"' "$1"; then
    grep -q 'ui\.shadcn\.com/schema' "$1"
  else
    grep -Eq '"(tsx|rsc)"' "$1"
  fi
}

# 標準入力の NUL 区切りのパス (dir からの相対か絶対) から、数える components.json を探し、その dir を found_dir に入れる
find_shadcn_ui() { # <dir>
  local file
  while IFS= read -r -d '' file; do
    case "$file" in /*) ;; *) file="$1/$file" ;; esac
    if is_shadcn_ui "$file"; then
      found_dir=$(dirname "$file")
      return 0
    fi
  done
  return 1
}

# git で dir の下の components.json を、浅い順 (dir 直下、1 階層下…) に探す
git_search() { # <dir> [--others --exclude-standard]
  local dir=$1 depth
  shift
  # glob では * が / をまたがない
  for depth in '' '*/' '*/*/' '*/*/*/'; do
    find_shadcn_ui "$dir" < <(git -C "$dir" ls-files -z "$@" -- ":(glob)${depth}components.json" 2> /dev/null || true) && return 0
  done
  return 1
}

# MCP は shadcn/ui を入れたリポジトリでだけ起動する。UI の無いリポジトリで取得・常駐しないため
if [ "${1:-}" = mcp ]; then
  root="${CLAUDE_PROJECT_DIR:-$PWD}"
  found_dir=
  # components.json を、Claude Code を開いた dir、リポジトリ全体の順に、3 階層下 (packages/apps/web/components.json など) まで探す。.gitignore で外したもの (node_modules など) は数えない
  if top=$(git -C "$root" rev-parse --show-toplevel 2> /dev/null); then
    # commit 前のもの (init した直後) は、commit 済みのものに無いときだけ探す (未追跡のファイルを毎回たどらないため)
    git_search "$root" || git_search "$top" || git_search "$root" --others --exclude-standard || git_search "$top" --others --exclude-standard || true
  else
    # git の外 (ホームなど) では、隠し dir (.cache・.venv など) と node_modules に潜らない (開いた dir 自体は隠し dir でも探す)
    find_shadcn_ui "$root" < <(find "$root" -maxdepth 4 \( -name node_modules -o -name '.?*' \) ! -path "$root" -prune -o -name components.json -print0 2> /dev/null || true) || true
  fi
  if [ -z "$found_dir" ]; then
    echo "shadcn/ui の components.json が無いので、shadcn の MCP は起動しません (shadcn/ui を入れたリポジトリでだけ起動します)" >&2
    exit 1
  fi
  # shadcn の MCP は、起動した dir の components.json (レジストリ・設定) を読む。見つけた dir で起動する
  cd "$found_dir"
fi

# --minimum-release-age は bun 1.4.4 から。古い bun はこの flag を無視し、7 日待たずに動くため使わない
# 1.4.4 以上なら 0。読んだ版 (読めなければ失敗の理由) を bun_version に入れる
new_enough() { # <bun のパス>
  if ! bun_version=$("$1" --version 2>&1); then
    bun_version=$(tail -n 1 <<< "$bun_version")
    return 1
  fi
  [[ $bun_version =~ ([0-9]+)\.([0-9]+)\.([0-9]+)(-[^[:space:]]*)?$ ]] || return 1
  local major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]} pre=${BASH_REMATCH[4]}
  # 1.4.4 の正式版より前の canary (1.4.4-canary.*) も古いものとして扱う
  ((major > 1 || (major == 1 && (minor > 4 || (minor == 4 && patch >= 4))))) && ! [[ $major.$minor.$patch == 1.4.4 && -n $pre ]]
}

# この dir の mise.toml の bun、PATH の bun の順に、1.4.4 以上のものを使う。どちらかが古くても、もう一方で動かせるようにする
bun=
tried=
for candidate in "$(mise which bun 2> /dev/null || true)" "$(command -v bun || true)"; do
  [ -n "$candidate" ] || continue
  case "$tried" in *" $candidate ("*) continue ;; esac
  if new_enough "$candidate"; then
    bun=$candidate
    break
  fi
  tried="$tried $candidate ($bun_version)"
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

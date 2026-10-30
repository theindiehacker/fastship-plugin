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

# 数える components.json か。shadcn/ui の $schema (手元のコピーも含む) か、$schema が無ければ React の印 (tsx・rsc) がある (shadcn-vue・shadcn-svelte なども同じ名前のファイルを使うため)
is_shadcn_ui() { # <パス>
  [ -f "$1" ] || return 1
  if grep -q '"[$]schema"' "$1"; then
    grep -Eq 'ui\.shadcn\.com/schema|node_modules/shadcn/' "$1"
  else
    grep -Eq '"(tsx|rsc)"' "$1"
  fi
}

# 標準入力の NUL 区切りのパス (dir からの相対か絶対) のうち、数える components.json でいちばん浅いものの dir を found_dir に入れる
find_shadcn_ui() { # <dir>
  local file depth best='' best_depth=''
  while IFS= read -r -d '' file; do
    case "$file" in /*) ;; *) file="$1/$file" ;; esac
    case "$file" in */node_modules/*) continue ;; esac
    is_shadcn_ui "$file" || continue
    depth=$(tr -cd / <<< "$file" | wc -c)
    if [ -z "$best" ] || ((depth < best_depth)); then
      best=$file
      best_depth=$depth
    fi
  done
  [ -n "$best" ] || return 1
  found_dir=$(dirname "$best")
}

# dir の下の components.json を、3 階層下 (packages/apps/web/components.json など) まで NUL 区切りで出す
list_components_json() { # <dir> [--others --exclude-standard]
  local dir=$1
  shift
  if [ -n "${top:-}" ]; then
    # glob では * が / をまたがない。.gitignore で外したもの (node_modules など) は出さない
    git -C "$dir" ls-files -z "$@" -- ':(glob)components.json' ':(glob)*/components.json' ':(glob)*/*/components.json' ':(glob)*/*/*/components.json' 2> /dev/null || true
  else
    # git の外 (ホームなど) では bash の glob で探す。隠し dir (.cache・.venv など) には入らない
    local file
    for file in "$dir"/components.json "$dir"/*/components.json "$dir"/*/*/components.json "$dir"/*/*/*/components.json; do
      if [ -f "$file" ]; then printf '%s\0' "$file"; fi
    done
  fi
}

# MCP (引数が mcp だけ) は shadcn/ui を入れたリポジトリでだけ起動する。UI の無いリポジトリで取得・常駐しないため。mcp init などの CLI は除く
if [ "${1:-}" = mcp ] && [ $# -eq 1 ]; then
  root="${CLAUDE_PROJECT_DIR:-$PWD}"
  top=$(git -C "$root" rev-parse --show-toplevel 2> /dev/null || true)
  found_dir=
  # Claude Code を開いた dir、リポジトリ全体の順に探す。commit 前のもの (init した直後) は、commit 済みのものに無いときだけ探す (未追跡のファイルを毎回たどらないため)
  find_shadcn_ui "$root" < <(list_components_json "$root") ||
    { [ -n "$top" ] && [ "$top" != "$root" ] && find_shadcn_ui "$top" < <(list_components_json "$top"); } ||
    { [ -n "$top" ] && find_shadcn_ui "$root" < <(list_components_json "$root" --others --exclude-standard); } ||
    { [ -n "$top" ] && [ "$top" != "$root" ] && find_shadcn_ui "$top" < <(list_components_json "$top" --others --exclude-standard); } ||
    true
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

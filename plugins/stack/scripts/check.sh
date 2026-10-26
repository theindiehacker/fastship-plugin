#!/usr/bin/env bash
# Claude が作業を終える前に、変更したファイルが lint・整形・型チェックを通るか、使っていないコード・依存や import の規約の違反が無いか確かめる。
# 通らなければ exit 2 で結果 (stderr) を Claude に返し、作業を続けて直させる。
# stack プラグインの Stop hook (hooks/hooks.json) から実行する。道具 (node_modules・.venv) が無い dir は確かめない
set -uo pipefail

# この hook で作業を続けさせた直後は確かめない (直せないときに終わらなくなるのを防ぐ)。
# jq が無い環境でも判定できるよう、入力の JSON は grep で見る
grep -Eq '"stop_hook_active" *: *true' && exit 0

top=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --show-toplevel 2> /dev/null) || exit 0
cd "$top" || exit 0

# コミットしていない変更 (新しいファイルを含み、消したファイルを除く)。質問に答えただけのときは何もしない
changed=$({ git diff --name-only --diff-filter=d HEAD 2> /dev/null; git ls-files --others --exclude-standard; } | sort -u)
[ -n "$changed" ] || exit 0

# pyright (PyPI) が実行のたびに新しい版を PyPI に問い合わせ、警告を出すのを止める (版はリポジトリが固定する)
export PYRIGHT_PYTHON_IGNORE_WARNINGS=1

report=$(mktemp)
out=$(mktemp)
trap 'rm -f "$report" "$out"' EXIT

find_up() { # <ファイル> <相対パス>  ファイルの dir からリポジトリ直下までさかのぼり、<相対パス> がある dir を出力する
  local dir
  dir=$(dirname "$1")
  while :; do
    if [ -e "$dir/$2" ]; then
      echo "$dir"
      return 0
    fi
    [ "$dir" = . ] && return 1
    dir=$(dirname "$dir")
  done
}

group() { # <道具の相対パス> <拡張子の正規表現>  変更したファイルを、道具がある dir ごとに "<dir>\t<dir からのパス>" で出力する
  local file dir
  grep -E "$2" <<< "$changed" | while IFS= read -r file; do
    dir=$(find_up "$file" "$1") && printf '%s\t%s\n' "$dir" "${file#"$dir"/}"
  done | sort
}

files_in() { # <group の出力> <dir>
  awk -F '\t' -v d="$2" '$1 == d { print $2 }' <<< "$1"
}

run() { # <dir> <コマンド>...  失敗したら、出力を report に足す
  local dir=$1
  shift
  (cd "$dir" && "$@") > "$out" 2>&1 && return 0
  { echo "### ${dir}: ${1##*/} ${2:-}"; head -n 100 "$out"; echo; } >> "$report"
}

# JavaScript / TypeScript: Biome・knip・tsc
pairs=$(group node_modules/.bin/biome '\.(jsx?|tsx?|[cm][jt]s|jsonc?|css|graphql)$')
while IFS= read -r dir <&3; do
  [ -n "$dir" ] || continue
  files=()
  while IFS= read -r f; do files+=("$f"); done < <(files_in "$pairs" "$dir")
  run "$dir" node_modules/.bin/biome check --no-errors-on-unmatched "${files[@]}"
  # 使っていないファイル・export・依存: knip。プロジェクト全体を確かめる (CI でも確かめるため、元からの違反は無い前提)
  [ -x "$dir/node_modules/.bin/knip" ] && run "$dir" node_modules/.bin/knip

  [ -f "$dir/tsconfig.json" ] && [ -x "$dir/node_modules/.bin/tsc" ] || continue
  # Next.js のルートの型 (next-env.d.ts など) は gitignore されていることが多いため、型チェックの前に作る
  [ -x "$dir/node_modules/.bin/next" ] && (cd "$dir" && node_modules/.bin/next typegen) > /dev/null 2>&1
  # tsc はプロジェクト全体を確かめるため、変更したファイルのエラーだけを返す (元からあるエラーまで直させない)
  (cd "$dir" && node_modules/.bin/tsc --noEmit --pretty false) > "$out" 2>&1 && continue
  errors=$(grep -F -f <(printf '%s(\n' "${files[@]}") "$out")
  [ -z "$errors" ] || printf '### %s: tsc --noEmit\n%s\n\n' "$dir" "$(head -n 100 <<< "$errors")" >> "$report"
done 3< <(cut -f1 <<< "$pairs" | uniq)

# Python: Ruff・Pyright・deptry・lint-imports
pairs=$(group .venv/bin/ruff '\.pyi?$')
while IFS= read -r dir <&3; do
  [ -n "$dir" ] || continue
  files=()
  while IFS= read -r f; do files+=("$f"); done < <(files_in "$pairs" "$dir")
  # --force-exclude: 設定で除外したファイル (マイグレーションなど) は、パスを渡しても確かめない
  run "$dir" .venv/bin/ruff check --force-exclude "${files[@]}"
  run "$dir" .venv/bin/ruff format --check --force-exclude "${files[@]}"
  [ -x "$dir/.venv/bin/pyright" ] && run "$dir" .venv/bin/pyright "${files[@]}"
  # 依存の過不足 (deptry) と import の規約 (lint-imports、設定があるときだけ)。プロジェクト全体を確かめる (CI でも確かめるため、元からの違反は無い前提)
  [ -x "$dir/.venv/bin/deptry" ] && run "$dir" .venv/bin/deptry .
  if [ -x "$dir/.venv/bin/lint-imports" ] &&
    { grep -q '^\[tool\.importlinter' "$dir/pyproject.toml" 2> /dev/null || [ -f "$dir/.importlinter" ]; }; then
    run "$dir" .venv/bin/lint-imports
  fi
done 3< <(cut -f1 <<< "$pairs" | uniq)

[ -s "$report" ] || exit 0
{
  echo "変更したファイルが lint・整形・型チェック・使っていないコードと依存 (knip・deptry)・import の規約 (lint-imports) の検査を通りません。直してから終えてください。"
  echo "自動で直せるもの: Biome は biome check --write、Ruff は ruff check --fix と ruff format"
  echo
  head -n 200 "$report"
} >&2
exit 2

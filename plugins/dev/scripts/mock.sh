#!/usr/bin/env bash
# Issue 本文の「## 見本」から、見本の PR と承認した commit を読む。手順は skills/analysis/SKILL.md・skills/refine/SKILL.md・skills/implement/SKILL.md・skills/review/SKILL.md を参照。
#   mock.sh show  <Issue の番号>  「<PR の番号> <sha>」を出力する。見本が無ければ (欄が無い・- なし) 何も出さない
#   mock.sh fetch <Issue の番号>  show と同じものを出力し、見本の PR を refs/remotes/origin/mock/<PR の番号> に fetch する
# 見本の欄には、課題分析が「見本の PR: #<PR の番号> (<40 桁の sha>)」の 1 行を書く。
# claude.ai/code では GraphQL が 403 になるため、gh api (REST) だけを使う。
set -euo pipefail

REPO='repos/{owner}/{repo}'

# 「## 見本」から次の「## 」までの間で、最初の「見本の PR: #N (sha)」の行を読む
MOCK_FILTER='
  .body // "" | split("\n") | map(rtrimstr("\r"))
  | (index("## 見本") // empty) as $start | .[$start + 1:]
  | .[:(map(startswith("## ")) | index(true))]
  | map(capture("^見本の PR: #(?<pr>[0-9]+) \\((?<sha>[0-9a-f]{40})\\)\\s*$")) | first // empty
  | "\(.pr) \(.sha)"'

show() { # <Issue の番号>
  gh api "$REPO/issues/$1" | jq -r "$MOCK_FILTER"
}

fetch() { # <Issue の番号>
  local found pr sha
  found=$(show "$1")
  [ -n "$found" ] || return 0
  read -r pr sha <<< "$found"
  # ブランチを消しても取れるよう、PR の ref から取る
  git fetch origin "+refs/pull/$pr/head:refs/remotes/origin/mock/$pr" >&2
  if ! git cat-file -e "$sha^{commit}" 2> /dev/null; then
    echo "見本の commit $sha が #$pr にありません" >&2
    exit 1
  fi
  echo "$found"
}

case "${1:-}" in
  show | fetch)
    if [[ ! ${2:-} =~ ^[0-9]+$ ]]; then
      echo "使い方: $0 show|fetch <Issue の番号>" >&2
      exit 1
    fi
    "$1" "$2"
    ;;
  *)
    echo "使い方: $0 show|fetch <Issue の番号>" >&2
    exit 1
    ;;
esac

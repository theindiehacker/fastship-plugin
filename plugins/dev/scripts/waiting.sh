#!/usr/bin/env bash
# 人の判断待ちのラベル (claude:analyzed) を、Issue の状態から決めて付け外しする。手順は skills/analysis/SKILL.md・skills/refine/SKILL.md を参照。
#   waiting.sh sync <Issue の番号>
#   claude:analyzed (④ 承認待ち): 課題分析が、最後の承認 (claude:refine を付けた) より後に終わっている
# 進行中ラベルか claude:blocked が付いている間は外す。付いた Issue にラベルを足すと、そのルーティンがもう一度起動するためでもある。
# 状態から決めるので、何度・どの順で実行しても同じ結果になる。並んで動くと古い状態で書くことがあるが、次の sync で直る。
# claude.ai/code では GraphQL が 403 になるため、gh api (REST) だけを使う。
set -euo pipefail

ANALYZED='claude:analyzed'
BUSY_LABELS=(claude:analysis claude:refine claude:implement claude:under-review claude:blocked)
ANALYSIS_MARK='<!-- fastship:analysis -->'
REPO='repos/{owner}/{repo}'

latest() { # <API のパス> <jq の条件>  条件に合うものの created_at のうち、最も新しいものを出力する
  gh api --paginate "$REPO/$1" --jq ".[] | select($2) | .created_at" | sort | tail -1
}

set_label() { # <ラベル> <yes|no>  今のラベル ($labels) と違うときだけ付け外しする
  if [ "$2" = yes ] && ! grep -qxF "$1" <<< "$labels"; then
    gh api --method POST "$REPO/issues/$number/labels" -f "labels[]=$1" > /dev/null
  elif [ "$2" = no ] && grep -qxF "$1" <<< "$labels"; then
    gh api --method DELETE "$REPO/issues/$number/labels/$1" > /dev/null
  fi
}

sync() { # <Issue の番号>
  local number=$1 issue labels busy reason='' analyzed=no done_at ok_at
  issue=$(gh api "$REPO/issues/$number")
  labels=$(jq -r '.labels[].name' <<< "$issue")

  # 閉じた Issue のラベルは、何を確かめたかの記録として残す
  if [ "$(jq -r .state <<< "$issue")" = closed ]; then
    echo "SKIP: #$number は閉じています"
    return
  fi

  for busy in "${BUSY_LABELS[@]}"; do
    if grep -qxF "$busy" <<< "$labels"; then
      reason="$busy が付いています"
      break
    fi
  done

  if [ -z "$reason" ]; then
    # 完了コメントのマーカーは誰でも書けるため、リポジトリのメンバーのコメントだけを数える。ルーティンは開発者のアカウントで書く
    done_at=$(latest "issues/$number/comments" \
      "((.body // \"\") | startswith(\"$ANALYSIS_MARK\")) and (.author_association | test(\"^(OWNER|MEMBER|COLLABORATOR)$\"))")
    ok_at=$(latest "issues/$number/events" '.event == "labeled" and .label.name == "claude:refine"')
    if [ -n "$done_at" ] && [[ $done_at > $ok_at ]]; then
      analyzed=yes
    else
      reason='最後の承認より後に終わった課題分析がありません'
    fi
  fi

  set_label "$ANALYZED" "$analyzed"
  echo "#$number $ANALYZED=$analyzed${reason:+ ($reason)}"
}

case "${1:-}" in
  sync)
    if [[ ! ${2:-} =~ ^[0-9]+$ ]]; then
      echo "使い方: $0 sync <Issue の番号>" >&2
      exit 1
    fi
    sync "$2"
    ;;
  *)
    echo "使い方: $0 sync <Issue の番号>" >&2
    exit 1
    ;;
esac

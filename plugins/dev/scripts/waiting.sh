#!/usr/bin/env bash
# 人の判断待ちのラベルを、Issue の状態から決めて付け外しする。手順は skills/analysis/SKILL.md・skills/refine/SKILL.md を参照。
#   waiting.sh sync <Issue の番号>
#   claude:analyzed (④ 承認待ち): 課題分析が、最後の承認 (claude:refine を付けた) より後に終わっている
#   claude:shipped (⑫ 成功指標の確認待ち): 承認待ちではなく、Sub Issue がすべて閉じて 1 つ以上が完了し、成功指標 が書いてある
# どちらも、進行中ラベルか claude:blocked が付いている間は外す。付いた Issue にラベルを足すと、そのルーティンがもう一度起動するためでもある。
# 状態から決めるので、何度・どの順で実行しても同じ結果になる。並んで動くと古い状態で書くことがあるが、次の sync (遅くとも週 1 回の振り返り) で直る。
# claude.ai/code では GraphQL が 403 になるため、gh api (REST) だけを使う。
set -euo pipefail

ANALYZED='claude:analyzed'
SHIPPED='claude:shipped'
BUSY_LABELS=(claude:analysis claude:refine claude:implement claude:under-review claude:blocked)
ANALYSIS_MARK='<!-- fastship:analysis -->'
REPO='repos/{owner}/{repo}'

metrics() { # 本文 (標準入力) の 成功指標 の欄から、中身のある行を出力する。HTML コメントと、中身の無い箇条書き・チェックボックスは除く
  jq -rRs 'gsub("\r"; "") | gsub("<!--[\\s\\S]*?-->"; "") | split("\n")
    | (map(test("^##\\s*成功指標\\s*$")) | index(true)) as $i
    | if $i == null then empty else .[$i + 1:] end
    | .[:(map(startswith("## ")) | index(true)) // length][]
    | select(test("^\\s*([-*+]\\s*)?(\\[[ xX]?\\]\\s*)?$") | not)'
}

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
  local number=$1 issue labels busy reason='' analyzed=no shipped=no done_at ok_at subs
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
      reason='承認待ちです'
    fi
  fi

  if [ -z "$reason" ]; then
    subs=$(gh api --paginate "$REPO/issues/$number/sub_issues" --jq '.[] | "\(.state) \(.state_reason)"')
    if [ -z "$subs" ]; then
      reason='Sub Issue がありません'
    elif grep -q '^open ' <<< "$subs"; then
      reason='open の Sub Issue があります'
    elif ! grep -qxF 'closed completed' <<< "$subs"; then
      reason='完了した Sub Issue がありません (すべて見送り)'
    elif [ -z "$(jq -r '.body // ""' <<< "$issue" | metrics)" ]; then
      reason='成功指標 が空です'
    else
      shipped=yes
    fi
  fi

  set_label "$ANALYZED" "$analyzed"
  set_label "$SHIPPED" "$shipped"
  echo "#$number $ANALYZED=$analyzed $SHIPPED=$shipped${reason:+ ($reason)}"
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

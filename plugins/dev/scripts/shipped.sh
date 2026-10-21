#!/usr/bin/env bash
# 親 Issue の claude:shipped (⑫ 成功指標の確認待ち) を、Sub Issue の状態に合わせる。手順は skills/refine/SKILL.md を参照。
#   shipped.sh sync <親 Issue の番号>
# 付け外しの直前に読み直すため、並んで動いても後に動いたセッションの結果が残る。
# claude.ai/code では GraphQL が 403 になるため、gh api (REST) だけを使う。
set -euo pipefail

LABEL='claude:shipped'
BUSY_LABELS=(claude:analysis claude:refine claude:implement claude:blocked)
REPO='repos/{owner}/{repo}'

metrics() { # 本文 (標準入力) の 成功指標 の欄から、中身のある行を出力する。HTML コメントと空のチェックボックスは除く
  jq -rRs 'gsub("\r"; "") | gsub("<!--[\\s\\S]*?-->"; "") | split("\n")
    | (map(test("^##\\s*成功指標\\s*$")) | index(true)) as $i
    | if $i == null then empty else .[$i + 1:] end
    | .[:(map(startswith("## ")) | index(true)) // length][]
    | select(test("\\S") and (test("^\\s*-\\s*\\[\\s*\\]\\s*$") | not))'
}

sync() { # <親 Issue の番号>
  local number=$1 issue labels busy subs reason=''
  issue=$(gh api "$REPO/issues/$number")
  labels=$(jq -r '.labels[].name' <<< "$issue")

  # 開発者が成功指標を報告して閉じた後に、残りの Sub Issue が閉じることがある
  if [ "$(jq -r .state <<< "$issue")" = closed ]; then
    echo "SKIP: #$number は閉じています"
    return
  fi

  # 進行中のラベルが付いた Issue にラベルを足すと、そのルーティンがもう一度起動する。そのルーティンが終わるときに合わせ直す
  for busy in "${BUSY_LABELS[@]}"; do
    if grep -qxF "$busy" <<< "$labels"; then
      echo "SKIP: #$number に $busy が付いています"
      return
    fi
  done

  subs=$(gh api --paginate "$REPO/issues/$number/sub_issues" --jq '.[] | "\(.state) \(.state_reason)"')
  # 差し戻して分析し直した Issue は、承認されるまで成功指標の確認に回さない
  if grep -qxF claude:analyzed <<< "$labels"; then
    reason='承認待ちです'
  elif [ -z "$subs" ]; then
    reason='Sub Issue がありません'
  elif grep -q '^open ' <<< "$subs"; then
    reason='open の Sub Issue があります'
  elif ! grep -qxF 'closed completed' <<< "$subs"; then
    reason='完了した Sub Issue がありません (すべて見送り)'
  elif [ -z "$(jq -r '.body // ""' <<< "$issue" | metrics)" ]; then
    reason='成功指標が空です'
  fi

  if [ -n "$reason" ]; then
    if grep -qxF "$LABEL" <<< "$labels"; then
      gh api --method DELETE "$REPO/issues/$number/labels/$LABEL" > /dev/null
    fi
    echo "NOT SHIPPED: #$number $reason"
    return
  fi

  if ! grep -qxF "$LABEL" <<< "$labels"; then
    gh api --method POST "$REPO/issues/$number/labels" -f "labels[]=$LABEL" > /dev/null
  fi
  echo "SHIPPED: #$number"
}

case "${1:-}" in
  sync) shift; sync "$@" ;;
  *)
    echo "使い方: $0 sync <親 Issue の番号>" >&2
    exit 1
    ;;
esac

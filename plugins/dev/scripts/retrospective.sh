#!/usr/bin/env bash
# 振り返りの開始。手順は skills/retrospective/SKILL.md を参照。
#   retrospective.sh start
# 振り返り Issue を先に起票して着手を示し、期間を本文の先頭のマーカーに残す。次回はその until から始める。
# claude.ai/code では GraphQL と search が 403 になるため、gh api (REST) だけを使う。BSD の date でも動くよう、時刻は jq で扱う。
set -euo pipefail

LABEL='claude:retrospective'
MARK='<!-- fastship:retrospective'
REPO='repos/{owner}/{repo}'
INTERVAL=$((6 * 86400)) # 前回の until からこれより短ければ振り返らない
STALE=$((2 * 3600))     # open のまま、これより古い振り返り Issue は途中で止まったとみなす

retros() { # 振り返り Issue を新しい順に「番号 state created_at since until」で出力する。見送ったものは除く
  gh api "$REPO/issues?labels=$LABEL&state=all&per_page=20" --jq '.[]
    | select(.state_reason != "not_planned")
    | "\(.number) \(.state) \(.created_at) "
      + (.body // "" | capture("since=(?<s>\\S+) until=(?<u>\\S+)") // {s: "-", u: "-"} | "\(.s) \(.u)")'
}

age() { # <時刻>  今からの経過秒
  jq -nr --arg t "$1" 'now - ($t | fromdate) | floor'
}

close_issue() { # <番号> <state_reason>
  gh api --method PATCH "$REPO/issues/$1" -f state=closed -f "state_reason=$2" > /dev/null
}

previous() { # <番号>  その番号を除き、閉じた振り返り Issue の本文を新しい順に 4 件出力する
  gh api "$REPO/issues?labels=$LABEL&state=closed&per_page=20" \
    --jq '[.[] | select(.state_reason != "not_planned" and .number != '"$1"')][:4][]
      | "--- 前回までの振り返り #\(.number) ---\n\(.body)\n"'
}

start() {
  local now latest number='' state created since='-' until='-' title out mine first
  now=$(jq -nr 'now | todate')
  latest=$(retros | sed -n 1p)

  if [ -n "$latest" ]; then
    read -r number state created since until <<< "$latest"
    if [ "$state" = open ]; then
      if [ "$(age "$created")" -lt "$STALE" ]; then
        echo "STOP: 別のセッションが振り返っています (#$number)"
        return
      fi
      # 前のセッションが途中で止まっている。同じ Issue と期間で続ける
      echo "CONTINUE: #$number since=$since until=$until (再開)"
      gh api "$REPO/issues/$number" --jq '"--- 途中の本文 ---\n\(.body)\n"'
      previous "$number"
      return
    fi
    if [ "$until" != - ] && [ "$(age "$until")" -lt "$INTERVAL" ]; then
      echo "STOP: 前回の振り返り (#$number) から 6 日経っていません"
      return
    fi
  fi

  if [ "$until" != - ]; then
    since=$until
  else
    since=$(jq -nr 'now - 7 * 86400 | todate')
  fi
  until=$now

  title=$(jq -nr --arg s "$since" --arg u "$until" \
    'def jst: fromdate + 9 * 3600 | strftime("%m/%d"); "♻️ 振り返り \($s | jst)〜\($u | jst)"')
  out=$(jq -n --arg title "$title" --arg body "$MARK since=$since until=$until -->
集計中です。" --arg label "$LABEL" '{title:$title, body:$body, labels:[$label]}' \
    | gh api --method POST "$REPO/issues" --input - --jq '.number, .labels[].name')
  mine=$(sed -n 1p <<< "$out")

  # push 権限が無いとラベルは黙って外れる。外れると次回に見つけられない
  if ! grep -qxF "$LABEL" <<< "$out"; then
    close_issue "$mine" not_planned
    echo "STOP: #$mine に $LABEL を付けられませんでした。push 権限を確かめてください"
    return
  fi

  # 同時に起動したときは、番号が最も小さいセッションだけが続ける
  first=$({ retros | awk -v prev="${number:-0}" '$2 == "open" && $1 > prev {print $1}'; echo "$mine"; } | sort -n | sed -n 1p)
  if [ "$first" != "$mine" ]; then
    close_issue "$mine" not_planned
    echo "STOP: 同時に起動した別のセッションが振り返っています (#$first)"
    return
  fi

  echo "CONTINUE: #$mine since=$since until=$until"
  previous "$mine"
}

case "${1:-}" in
  start) shift; start "$@" ;;
  *)
    echo "使い方: $0 start" >&2
    exit 1
    ;;
esac

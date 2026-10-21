#!/usr/bin/env bash
# ルーティンの開始と、claude:blocked で人間に返す処理。手順は skills/blocked/SKILL.md を参照。
#   blocked.sh start <番号> <進行中ラベル>
#   blocked.sh stop  <番号> <進行中ラベル> <質問の本文ファイル> [<Sub Issue の番号>]
# claude.ai/code では GraphQL が 403 になるため、gh api (REST) だけを使う。PR も Issue の API で扱える。
set -euo pipefail

START_MARK='<!-- fastship:start -->'
BLOCKED_MARK='<!-- fastship:blocked -->'
RETRO_MARK='<!-- fastship:retrospective'
BLOCKED_LABEL='claude:blocked'
REPO='repos/{owner}/{repo}'

has_label() { # <番号> <ラベル>
  local names
  names=$(gh api "$REPO/issues/$1" --jq '.labels[].name')
  grep -qxF "$2" <<< "$names"
}

add_label() { # <番号> <ラベル>
  gh api --method POST "$REPO/issues/$1/labels" -f "labels[]=$2" > /dev/null
}

remove_label() { # <番号> <ラベル>  付いていなければ何もしない
  if has_label "$1" "$2"; then
    gh api --method DELETE "$REPO/issues/$1/labels/$2" > /dev/null
  fi
}

comment() { # <番号> <本文>  投稿したコメントの ID を出力する
  jq -n --arg body "$2" '{body:$body}' \
    | gh api --method POST "$REPO/issues/$1/comments" --input - --jq .id
}

start_ids() { # <番号> <時刻>  その時刻以降の着手コメントの ID を古い順に出力する
  gh api --paginate "$REPO/issues/$1/comments${2:+?since=$2}" \
    --jq ".[] | select(.created_at >= \"$2\" and (.body | startswith(\"$START_MARK\"))) | .id" \
    | sort -n
}

previous() { # <番号>  最新の質問と、それ以降のコメントを出力する。着手と振り返りのコメントは除く
  gh api --paginate "$REPO/issues/$1/comments" --jq '.[] | {user: .user.login, created_at, body}' \
    | jq -rs --arg mark "$BLOCKED_MARK" --arg start "$START_MARK" --arg retro "$RETRO_MARK" '
        (map(.body | startswith($mark)) | rindex(true)) as $i
        | if $i == null then empty
          else "--- 前回の質問と回答 ---",
            (.[$i:][] | select(.body | startswith($start) or startswith($retro) | not)
              | "### \(.user) (\(.created_at))\n\(.body)\n")
          end'
}

start() { # <番号> <進行中ラベル>
  local number=$1 label=$2 since mine
  if ! has_label "$number" "$label"; then
    echo "STOP: #$number に $label が付いていません"
    return
  fi

  # 進行中ラベルが最後に付いてから着手したセッションがあれば、そちらに任せる
  since=$(gh api --paginate "$REPO/issues/$number/events" \
    --jq ".[] | select(.event == \"labeled\" and .label.name == \"$label\") | .created_at" \
    | sort | tail -1)
  if [ -n "$(start_ids "$number" "$since")" ]; then
    echo "STOP: 別のセッションが着手しています"
    return
  fi

  # 同時に起動したときは、着手コメントが最も古いセッションだけが続ける
  mine=$(comment "$number" "$START_MARK
🤖 \`$label\` の処理を始めました。")
  if [ "$(start_ids "$number" "$since" | sed -n 1p)" != "$mine" ]; then
    gh api --method DELETE "$REPO/issues/comments/$mine" > /dev/null
    echo "STOP: 同時に起動した別のセッションが着手しています"
    return
  fi

  remove_label "$number" "$BLOCKED_LABEL"
  echo "CONTINUE"
  previous "$number"
}

stop() { # <番号> <進行中ラベル> <質問の本文ファイル> [<Sub Issue の番号>]
  local number=$1 label=$2 file=$3 sub=${4:-}
  comment "$number" "$BLOCKED_MARK
$(cat "$file")" > /dev/null

  # 進行中ラベルを先に外す。付いたまま claude:blocked を足すと、ルーティンがもう一度起動する
  remove_label "$number" "$label"
  if [ -n "$sub" ]; then
    remove_label "$sub" "$label"
  fi
  add_label "$number" "$BLOCKED_LABEL"
  echo "BLOCKED: #$number"
}

case "${1:-}" in
  start) shift; start "$@" ;;
  stop) shift; stop "$@" ;;
  *)
    echo "使い方: $0 start <番号> <進行中ラベル>" >&2
    echo "        $0 stop <番号> <進行中ラベル> <質問の本文ファイル> [<Sub Issue の番号>]" >&2
    exit 1
    ;;
esac

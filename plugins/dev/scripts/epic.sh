#!/usr/bin/env bash
# Sub Issue に分けた Issue の epic ブランチ (epic/<親 Issue の番号>) を扱う。手順は skills/refine/SKILL.md・skills/implement/SKILL.md を参照。
#   epic.sh base   <Sub Issue の番号>  PR のベースを出力する。親 Issue の epic ブランチがあればそれ、無ければデフォルトブランチ
#   epic.sh create <親 Issue の番号>   デフォルトブランチの先頭から epic ブランチを作る。あれば何もしない
#   epic.sh sync   <親 Issue の番号>   デフォルトブランチを epic ブランチに取り込む
#   epic.sh merge  <PR の番号>         ⑨ の ✅ と CI がそろった PR を epic ブランチにマージし、Sub Issue を閉じる
# epic ブランチが無い Issue (この版より前に分けた Issue など) は、今までどおりデフォルトブランチに向ける。
# claude.ai/code では GraphQL が 403 になるため、gh api (REST) だけを使う。
set -euo pipefail

REVIEW_MARK='<!-- fastship:review -->'
REPO='repos/{owner}/{repo}'

default_branch() {
  gh api "$REPO" --jq .default_branch
}

has_branch() { # <ブランチ>  あれば 0、無ければ 1。404 以外のエラーは止める (無いと誤って、デフォルトブランチに向けないため)
  local err
  if err=$(gh api "$REPO/git/ref/heads/$1" --jq .ref 2>&1 > /dev/null); then
    return 0
  elif grep -q 'HTTP 404' <<< "$err"; then
    return 1
  fi
  echo "$err" >&2
  exit 1
}

parent_of() { # <Issue の番号>  同じリポジトリの親 Issue の番号を出力する。無ければ何も出さない
  gh api "$REPO/issues/$1" \
    --jq '.repository_url as $repo | .parent_issue_url // empty | select(startswith($repo + "/issues/")) | split("/") | last'
}

close_issue() { # <Issue の番号>  open なら完了として閉じる。issues.closed で、リファインメントが後続に着手する
  if [ "$(gh api "$REPO/issues/$1" --jq .state)" = open ]; then
    gh api --method PATCH "$REPO/issues/$1" -f state=closed -f state_reason=completed > /dev/null
  fi
}

base() { # <Sub Issue の番号>
  local parent
  parent=$(parent_of "$1")
  if [ -n "$parent" ] && has_branch "epic/$parent"; then
    echo "epic/$parent"
  else
    default_branch
  fi
}

create() { # <親 Issue の番号>
  local branch="epic/$1" sha
  if has_branch "$branch"; then
    echo "EXISTS: $branch"
    return
  fi
  sha=$(gh api "$REPO/git/ref/heads/$(default_branch)" --jq .object.sha)
  gh api --method POST "$REPO/git/refs" -f ref="refs/heads/$branch" -f sha="$sha" > /dev/null
  echo "CREATED: $branch"
}

sync() { # <親 Issue の番号>
  local branch="epic/$1" default err
  if ! has_branch "$branch"; then
    echo "SKIP: $branch がありません"
    return
  fi
  default=$(default_branch)
  # 取り込むものが無ければ 204 が返り、成功として扱う
  if err=$(gh api --method POST "$REPO/merges" -f base="$branch" -f head="$default" 2>&1 > /dev/null); then
    echo "SYNCED: $default → $branch"
  elif grep -q 'HTTP 409' <<< "$err"; then
    echo "CONFLICT: $default を $branch に取り込めません (コンフリクト)"
  else
    echo "$err" >&2
    exit 1
  fi
}

merge() { # <PR の番号>
  local number=$1 pr base sub sha review checks statuses method err
  pr=$(gh api "$REPO/pulls/$number")
  base=$(jq -r .base.ref <<< "$pr")
  if [[ $base != epic/* ]]; then
    echo "SKIP: ベースが epic ブランチではありません ($base)。マージは開発者が行います"
    return
  fi

  sub=$(jq -r '.body // "" | split("\n") | map(rtrimstr("\r") | capture("^Closes #(?<n>[0-9]+)$").n) | first // empty' <<< "$pr")
  if [ -z "$sub" ]; then
    echo "FAILED: 本文に Closes #<Sub Issue> がありません"
    return
  fi
  if [ "epic/$(parent_of "$sub")" != "$base" ]; then
    echo "FAILED: #$sub は $base の Sub Issue ではありません"
    return
  fi

  if [ "$(jq -r .merged <<< "$pr")" = true ]; then
    close_issue "$sub"
    echo "MERGED: #$number は $base にマージ済みです (#$sub を閉じました)"
    return
  fi
  if [ "$(jq -r .state <<< "$pr")" != open ]; then
    echo "SKIP: #$number は閉じています"
    return
  fi
  if [ "$(jq -r .draft <<< "$pr")" = true ]; then
    echo "WAIT: Draft です"
    return
  fi
  if jq -e '.labels | map(.name) | index("claude:under-review")' <<< "$pr" > /dev/null; then
    echo "WAIT: レビュー中です (claude:under-review)"
    return
  fi
  if jq -e '.labels | map(.name) | index("claude:blocked")' <<< "$pr" > /dev/null; then
    echo "WAIT: 回答待ちです (claude:blocked)"
    return
  fi

  # レビューのマーカーは誰でも書けるため、リポジトリのメンバーのレビューだけを数える。ルーティンは開発者のアカウントで書く
  sha=$(jq -r .head.sha <<< "$pr")
  review=$(gh api --paginate "$REPO/pulls/$number/reviews" \
    --jq ".[] | select((.body // \"\" | startswith(\"$REVIEW_MARK\")) and (.author_association | test(\"^(OWNER|MEMBER|COLLABORATOR)$\")))
          | {commit_id, submitted_at, ok: (.body | split(\"\n\") | map(rtrimstr(\"\r\")) | .[1] // \"\" | startswith(\"## ✅\"))}" \
    | jq -s 'sort_by(.submitted_at) | last')
  if [ "$(jq -r '.commit_id // ""' <<< "$review")" != "$sha" ] || [ "$(jq -r '.ok // false' <<< "$review")" != true ]; then
    echo "WAIT: head ($sha) への ⑨ の ✅ がありません"
    return
  fi

  # 終わっていないもの・成功していないものを出す。CI が無いリポジトリでは何も出ない
  # 取得に失敗したら止める (成功と誤って、CI を確かめずにマージしないため)。1 つずつ代入するのはそのため
  checks=$(gh api --paginate "$REPO/commits/$sha/check-runs?per_page=100" \
    --jq '.check_runs[] | select(.status != "completed" or (.conclusion | IN("success", "neutral", "skipped") | not)) | "\(.name): \(.conclusion // .status)"')
  statuses=$(gh api "$REPO/commits/$sha/status" --jq '.statuses[] | select(.state != "success") | "\(.context): \(.state)"')
  if [ -n "$checks$statuses" ]; then
    echo "WAIT: CI が成功していません"
    [ -z "$checks" ] || echo "$checks"
    [ -z "$statuses" ] || echo "$statuses"
    return
  fi

  if [ "$(jq -r .mergeable <<< "$pr")" = false ]; then
    echo "CONFLICT: $base とコンフリクトしています"
    return
  fi

  # squash が使えれば squash にする。epic の履歴が Sub Issue ごとに 1 コミットになり、最後のレビューで読みやすいため
  method=$(gh api "$REPO" \
    --jq 'if .allow_squash_merge != false then "squash" elif .allow_merge_commit != false then "merge" else "rebase" end')
  if err=$(gh api --method PUT "$REPO/pulls/$number/merge" -f sha="$sha" -f merge_method="$method" 2>&1 > /dev/null); then
    close_issue "$sub"
    echo "MERGED: #$number を $base にマージし、#$sub を閉じました"
    return
  fi
  pr=$(gh api "$REPO/pulls/$number")
  if [ "$(jq -r .merged <<< "$pr")" = true ]; then
    # 同時に動いた別のセッションがマージした
    close_issue "$sub"
    echo "MERGED: #$number は $base にマージ済みです (#$sub を閉じました)"
  elif grep -q 'HTTP 409' <<< "$err"; then
    echo "WAIT: head が変わりました"
  elif [ "$(jq -r .mergeable <<< "$pr")" = false ]; then
    # 確かめた時点では、GitHub がまだコンフリクトを調べ終えていなかった
    echo "CONFLICT: $base とコンフリクトしています"
  else
    echo "FAILED: マージできません"
    echo "$err"
  fi
}

usage() {
  echo "使い方: $0 base <Sub Issue の番号>" >&2
  echo "        $0 create|sync <親 Issue の番号>" >&2
  echo "        $0 merge <PR の番号>" >&2
  exit 1
}

case "${1:-}" in
  base | create | sync | merge)
    [[ ${2:-} =~ ^[0-9]+$ ]] || usage
    "$1" "$2"
    ;;
  *) usage ;;
esac

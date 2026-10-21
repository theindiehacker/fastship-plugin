---
name: review
description: FastShip の ⑨⑩ レビュー。claude:under-review が付いた PR を、Claude Code 同梱の /code-review と /security-review、Sub Issue の完了条件でレビューし、結果を ✅ / 🛑 で PR に返す。✅ なら claude:approved を付ける。🛑 の指摘は実装のセッションが直し、再レビューを頼む。判断できないときは claude:blocked で人間に返す。レビュールーティンから使う。使い方: /dev:review {PR の番号}
argument-hint: "{PR の番号}"
---

# ✔️ レビュー

`claude:under-review` が付いた PR をレビューし、✅ / 🛑 を返してください。🛑 の指摘は、PR を作った実装のセッションが直し、`claude:under-review` を付け直して再レビューを頼みます。開発者は `claude:approved` が付いた PR をマージします。

GitHub は `gh api` (REST) で操作します。コマンドの `123` は PR の番号、`<base>` / `<head>` / `<sha>` は 1 で出た値、`<Sub Issue>` は Sub Issue の番号に置き換えてください。

## 1. 始める
1. `/dev:blocked` の「1. 始める」を、進行中ラベル `claude:under-review` で行ってください。`STOP` と出たら、何もせずに終えてください。
2. `claude:approved` を外し、PR を取得してください。前の ✅ を、レビューが終わるまで残さないためです。

```bash
gh api --method DELETE "repos/{owner}/{repo}/issues/123/labels/claude:approved" > /dev/null 2>&1 || true
gh api "repos/{owner}/{repo}/pulls/123" --jq '.state, .base.ref, .head.ref, .head.sha'
```

 - `open` でなければ、`claude:under-review` を外して終えてください (下の 1 つ目のコマンド)。
 - `open` なら、head を checkout してください (下の 2 つ目のコマンド)。出た sha を控えてください。4 で、レビューした commit を示すのに使います。

```bash
gh api --method DELETE "repos/{owner}/{repo}/issues/123/labels/claude:under-review" > /dev/null
git fetch origin "+refs/heads/<base>:refs/remotes/origin/<base>" "+refs/heads/<head>:refs/remotes/origin/<head>" \
  && git checkout --detach "origin/<head>" && git rev-parse HEAD
```

## 2. 読む
PR の本文と、紐付いた Sub Issue・親 Issue を読んでください。PR の本文の `Closes #N` の N が Sub Issue です。2 つ目のコマンドの最後の行が親 Issue の番号です。空なら親は無いので、3 つ目は飛ばしてください。

```bash
gh api "repos/{owner}/{repo}/pulls/123" --jq '.title, .body'
gh api "repos/{owner}/{repo}/issues/<Sub Issue>" --jq '.title, .body, (.parent_issue_url // "" | split("/") | last)'
gh api "repos/{owner}/{repo}/issues/<親 Issue>" --jq '.title, .body'
```

 - Sub Issue の 完了条件 / やらないこと が、PR の範囲です。Sub Issue が無い PR は、💡 概要 を範囲としてください。
 - リポジトリの規約 (`CLAUDE.md` など) のうち、変更ファイルに当たるものを読んでください。
 - 前の ⑨ のレビュー (本文が `<!-- fastship:review -->` で始まる) があれば、再レビューです。前の指摘と、実装の返信 (本文が `<!-- fastship:reply -->` で始まる) を読んでください。

```bash
gh api --paginate "repos/{owner}/{repo}/pulls/123/reviews" \
  --jq '.[] | select(.body | startswith("<!-- fastship:review -->")) | "### \(.commit_id) (\(.submitted_at))\n\(.body)\n"'
gh api --paginate "repos/{owner}/{repo}/pulls/123/comments" \
  --jq '.[] | "### id=\(.id) reply_to=\(.in_reply_to_id // "-") \(.path):\(.line // .original_line) (\(.created_at))\n\(.body)\n"'
```

## 3. レビューする
1. Claude Code に同梱のスキルで、PR の差分をレビューしてください。結果が届くまで待ってから次に進んでください。
   - コードレビュー: `/code-review origin/<base>...HEAD`。`--comment` / `--fix` は付けないでください。投稿は 4 で行い、修正は実装が行います。
   - セキュリティレビュー: `/security-review`
   - スキルが使えなければ、同じ観点 (バグ・脆弱性) で差分を自分で読んでください。
2. 同梱のスキルが見ない、次の観点で差分を読んでください。
   - 完了条件を 1 つずつ満たしているか。満たすことを確かめるテストがあるか。自動テストで確かめられない条件は、PR の ✔️ 動作確認 に方法と結果があるか
   - やらないこと にあるものを作っていないか
   - リポジトリの規約に反していないか
3. 指摘ごとに、実際の入力から失敗までの道筋を確かめてください。辿れない指摘は捨ててください。
4. 指摘に、次のどれかを付けてください。
   - `[must]`: 直さないとマージできない。バグ・脆弱性・完了条件の未達・完了条件のテストが無い・やらないこと を作った・規約違反
   - `[imo]` / `[nits]`: 直すと良いが、マージは止めない
   - `[ask]`: 意図の確認。マージは止めない

### 再レビューのとき
 - 前の `[must]` が直ったかを確かめてください。採用しない理由が返信されていて、理由が妥当なら、`[must]` に数えないでください。
 - 新しく `[must]` にするのは、前回の後の push で入った問題か、前回見落としたバグ・脆弱性だけにしてください。前回出さなかった好みの指摘を `[must]` にすると、再レビューが終わらなくなるためです。

## 4. 返す (⑩)
`[must]` が 0 件なら ✅、1 件以上なら 🛑 です。

1. 下の形式で `/tmp/review.json` を書き、PR にレビューを投稿してください。
   - `event` は `COMMENT` にしてください。Approve / Request changes は、PR の作成者と同じアカウントでは使えません。
   - `commit_id` は、1 で控えた sha にしてください。
   - 指摘は、差分の行に行コメントで付けてください (`side` は追加・変更行なら `RIGHT`、削除行なら `LEFT`)。差分の行に付けられない指摘は、本文に書いてください。
   - 本文と行コメントの先頭に `<!-- fastship:review -->` と改行を付けてください。実装は、このマーカーで ⑨ のレビューを見分けます。

```bash
gh api --method POST "repos/{owner}/{repo}/pulls/123/reviews" --input /tmp/review.json > /dev/null
```

```json
{
  "commit_id": "<sha>",
  "event": "COMMENT",
  "body": "<!-- fastship:review -->\n<本文>",
  "comments": [
    {"path": "<ファイル>", "line": 42, "side": "RIGHT", "body": "<!-- fastship:review -->\n[must] <指摘と、失敗する入力・直し方>"}
  ]
}
```

本文:

```markdown
## ✅ レビュー: マージできます
<🛑 のときは「## 🛑 レビュー: 直してほしい点があります」>

- コードレビュー: `[must]` <件数> / そのほか <件数>
- セキュリティレビュー: `[must]` <件数> / そのほか <件数>
- 完了条件: <テストか動作確認で確かめられた数> / <全体の数>

<再レビューのときは、前の `[must]` がどうなったかを 1 行ずつ書く>
<差分の行に付けられない指摘>
```

2. PR の head が、1 で控えた sha のままかを確かめてください。
   - 同じなら、✅ のときは `claude:approved` を付け、✅ / 🛑 どちらも `claude:under-review` を外してください。
   - 違えば、ラベルは変えずに終えてください。新しい push は、実装が `claude:under-review` を付け直して再レビューを頼みます。

```bash
gh api "repos/{owner}/{repo}/pulls/123" --jq .head.sha
gh api --method POST "repos/{owner}/{repo}/issues/123/labels" -f "labels[]=claude:approved" > /dev/null
gh api --method DELETE "repos/{owner}/{repo}/issues/123/labels/claude:under-review" > /dev/null
```

## 判断できないとき
次のように Claude だけで判断できないときは、推測で ✅ / 🛑 を付けず、`/dev:blocked` の「2. 止める」を PR の番号で行ってください。

 - PR の目的が、本文・Sub Issue から読み取れず、正しいかを判断できない
 - 指摘が Sub Issue・親 Issue の決定と食い違い、直すかどうかが仕様の判断になる (例: 完了条件どおりに作ると脆弱性になる)
 - PR の head を checkout できない (403 など)

好みや小さな設計の選択は止めずに、`[imo]` で書いてください。

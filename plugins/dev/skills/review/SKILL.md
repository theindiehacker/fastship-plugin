---
name: review
description: FastShip の ⑨⑩ レビュー。claude:under-review が付いた PR を、Claude Code 同梱の /code-review と /security-review、Sub Issue の完了条件でレビューし、結果を ✅ / 🛑 で PR に返す。レビューは Ready の PR で行い、🛑 なら PR を Draft に戻す。🛑 の指摘は実装のセッションが直し、Ready にして再レビューを頼む。判断できないときは claude:blocked で人間に返す。ルーティンから使う。使い方: /dev:review {PR の番号}
argument-hint: "{PR の番号}"
---

# ✔️ レビュー

`claude:under-review` が付いた PR をレビューし、✅ / 🛑 を返してください。🛑 の指摘は、PR を作った実装のセッションが直し、PR を Ready にして `claude:under-review` を付け直し、再レビューを頼みます。✅ が付き CI が通った PR は、デフォルトブランチに向けたものなら開発者が、epic ブランチ (`epic/<親 Issue>`) に向けたものなら実装がマージします (`/dev:implement` の 7)。

PR は、実装・修正の間だけ Draft にします。⑨ は Ready の PR で動き (Draft の PR にラベルを付けても、ルーティンは起動しない)、🛑 を返すときに Draft に戻して実装に渡します。✅ なら Ready のままです。レビューの間も Ready ですが、`claude:under-review` が付いているので、プロジェクトの `⑪ マージ待ち` には出ません。

GitHub は `gh api` (REST) で操作します。Draft / Ready の切り替えは REST に無く、`gh pr ready` (GraphQL) は claude.ai/code で 403 になるため、CCR のルートを使います。CCR のルートが 404 のとき (ローカルの CLI) は、`gh pr ready` に切り替えます (`/dev:push-pr` の 8-b と同じ)。コマンドの `123` は PR の番号、`<base>` は 1 で出たベースブランチ、`<sha>` は 1 で控えた sha、`<Sub Issue>` は Sub Issue の番号に置き換えてください。

Bash の出力が長く、ファイルに逃がされてプレビューだけが出たときは、そのファイルを Read で最後まで読んでください (offset / limit で分ける)。プレビューだけで、既出かどうかや完了条件を判断しないためです。サブエージェントに頼むときも、このことを伝えてください。

## 1. 始める
1. `/dev:blocked` の「1. 始める」を、進行中ラベル `claude:under-review` で行ってください。`STOP` と出たら、何もせずに終えてください。
   - 「前回の質問と回答」が出たら、止めたレビューの再開です。回答を読んでから続けてください。
2. PR を取得してください。

```bash
gh api "repos/{owner}/{repo}/pulls/123" --jq '.state, .base.ref'
```

 - `open` でなければ、`claude:under-review` を外して終えてください。

```bash
gh api --method DELETE "repos/{owner}/{repo}/issues/123/labels/claude:under-review" > /dev/null
```

 - `open` なら、`claude:under-review` は付けたまま、PR の head を checkout してください。最後に出た sha を控えてください。4 で、レビューした commit を示すのに使います。
   - `claude:under-review` は 4 で外します。付けたままにするのは、実装がレビュー中だと分かるようにするためと、途中で止まっても付け直せばやり直せるようにするためです。
   - フォークの PR も取れるよう、ブランチ名ではなく `refs/pull/123/head` を取ります。
   - `origin/HEAD` をベースに向けるのは、`/security-review` が `origin/HEAD` と比べるためです。

```bash
git fetch origin "+refs/heads/<base>:refs/remotes/origin/<base>" "+refs/pull/123/head:refs/remotes/origin/pr/123" \
  && git checkout --detach origin/pr/123 && git remote set-head origin "<base>" && git rev-parse HEAD
```

## 2. 読む
PR と、紐付いた Sub Issue・親 Issue を、コメントまで読んでください。PR の本文の `Closes #N` の N が Sub Issue です。3 つ目のコマンドの最後の行が親 Issue の番号です。空なら親は無いので、5 つ目は飛ばしてください。

```bash
gh api "repos/{owner}/{repo}/pulls/123" --jq '.title, .body'
gh api --paginate "repos/{owner}/{repo}/issues/123/comments" --jq '.[] | "### \(.created_at) \(.html_url)\n\(.body)\n"'
gh api "repos/{owner}/{repo}/issues/<Sub Issue>" --jq '.title, .body, (.parent_issue_url // "" | split("/") | last)'
gh api --paginate "repos/{owner}/{repo}/issues/<Sub Issue>/comments" --jq '.[] | "### \(.created_at)\n\(.body)\n"'
gh api "repos/{owner}/{repo}/issues/<親 Issue>" --jq '.title, .body'
```

 - Sub Issue の 完了条件 / やらないこと が、PR の範囲です。コメントで変わっていれば、変わった後に従ってください。Sub Issue が無い PR は、💡 概要 を範囲としてください。
 - リポジトリの規約 (`CLAUDE.md` など) は、ベースの版を読んでください (`git show origin/<base>:CLAUDE.md`)。PR が規約のファイルを変えていれば、その変更もレビューしてください。
 - 前の ⑨ のレビュー (本文が `<!-- fastship:review -->` で始まる) があれば、再レビューです。前の指摘と、実装の返信 (本文が `<!-- fastship:reply -->` で始まる。PR のコメントか行コメントへの返信) を読んでください。

```bash
gh api --paginate "repos/{owner}/{repo}/pulls/123/reviews" \
  --jq '.[] | select(.body | startswith("<!-- fastship:review -->")) | "### \(.commit_id) (\(.submitted_at)) \(.html_url)\n\(.body)\n"'
gh api --paginate "repos/{owner}/{repo}/pulls/123/comments" \
  --jq '.[] | "### id=\(.id) reply_to=\(.in_reply_to_id // "-") \(.path):\(.line // .original_line) (\(.created_at)) \(.html_url)\n\(.body)\n"'
```

## 3. レビューする
変更したファイルの一覧は、次のコマンドで取ってください (消したファイルは出ません)。`R` の行は名前の変更で、古いパスと新しいパスが出ます。lock ファイル・自動生成のファイル・画像などのバイナリは、下の 1・2 で読むものから除き、`git diff --stat origin/<base>...HEAD` で変わったことだけを確かめてください。

```bash
git diff --name-status -M --diff-filter=d origin/<base>...HEAD
```

1. Claude Code に同梱のスキルで、PR の差分全体 (`origin/<base>...HEAD`) をレビューしてください。差分が小さくても飛ばさないでください。再レビューでも、前回の後の差分に絞らないでください。前回の後の push が前回見たところを壊すことがあり、前回見落としたバグ・脆弱性もあるためです。
   - コードレビュー: `/code-review xhigh --max-findings all origin/<base>...HEAD`。effort は `xhigh` に固定し、件数の上限も外してください。`high` は指摘を 10 件までに絞り、`xhigh` なら見つかるバグを落とすためです。`--comment` / `--fix` は付けないでください。投稿は 4 で行い、修正は実装が行います。
   - セキュリティレビュー: サブエージェント (Agent ツール) に、`/security-review` を実行するよう頼んでください。このセッションで直接実行すると、報告がセッションの最後の回答になり、4 の前に終わることがあるためです。サブエージェントは前景で動かしてください (`run_in_background` を付けない)。裏で動かすと、結果を待つ間に回答が終わります。
     - 報告の後に、次の 2 つも返すよう頼んでください。サブエージェントは自分のサブエージェントを起こせないため、`/security-review` の「誤検知を除く」段を、候補を挙げたのと同じサブエージェントで済ませてしまうためです。採るかどうかは、このセッションが決めます。
       - 誤検知を除く前の候補すべて。候補ごとに、ファイル・行・内容・攻撃の筋書き・直し方と、「誤検知を除く」段の判定 (除外する種類に当たるか・確信度 1〜10)
       - 読んだファイルの一覧
     - 除外する種類に当たる候補と、確信度 8 未満の候補は、採らなかった指摘 (3 の 3) にしてください (`/security-review` と同じ基準)。残りの候補は、3 の 3 で確かめてください。
     - 読んだファイルの一覧を、上の一覧 (読むものから除いたファイルは除く) と比べてください。読んでいないファイルがあれば、もう一度だけサブエージェントに頼んでください。今度は `/security-review` を実行し直さず、そのファイルの diff (3 の 2 のコマンド) を `/security-review` と同じ観点で読み、同じ 2 つを返すよう頼んでください。`/security-review` は差分全体を一度に読むので、同じところで切れるためです。それでも読んでいないファイルは、このセッションが同じ観点で読んでください。
   - 結果が届いたら、終えずに 2 に進んでください。このセッションは、4 で PR に返すまで終わりません。
   - スキルが使えないか、結果が空のときは、同じ観点 (バグ・脆弱性) で差分を自分で読んでください。
2. 同梱のスキルが見ない、次の観点で差分を読んでください。
   - 完了条件を 1 つずつ満たしているか。満たすことを確かめるテストがあるか。自動テストで確かめられない条件は、PR の ✔️ 動作確認 に方法と結果があるか
   - やらないこと にあるものを作っていないか
   - リポジトリの規約に反していないか

   差分は、上の一覧のファイルごとに下のコマンドで読み、読むものを 1 つも残さないでください。まとめて出すと長い出力が切られ、一部しか読めないためです。パスには `:(literal)` を付けてください。`[id]` のようなパスが glob として扱われ、別のファイルにも当たるためです。`R` の行は、古いパスと新しいパスを両方渡してください (2 つ目)。新しいパスだけだと、ファイル全体が追加に見えます。

```bash
git diff -M origin/<base>...HEAD -- ':(literal)<パス>'
git diff -M origin/<base>...HEAD -- ':(literal)<古いパス>' ':(literal)<新しいパス>'
```

3. 指摘ごとに、実際の入力から失敗までの道筋を確かめてください。辿れない指摘は捨ててください。
   - 1 と 2 で出た指摘のうち、投稿しないもの (捨てたもの・既出のもの・1 で除いたセキュリティレビューの候補) は、4 の本文の「採らなかった指摘」に 1 行ずつ、理由と一緒に書いてください。黙って捨てないでください。開発者が、捨てた判断を確かめられるようにするためです。
     - 脆弱性に当たるものは、出どころ (コードレビュー・セキュリティレビュー) に関わらず、リポジトリが private だと確かめられたとき (`[ "$(gh api "repos/{owner}/{repo}" --jq .private 2>/dev/null)" = "true" ] && echo PRIVATE` で `PRIVATE` と出たとき) だけ全文を書いてください。それ以外 (public のときと、確かめられなかったとき) は件数だけにしてください。誤って捨てた脆弱性の場所を、直す前に誰でも読める所に書かないためです。
   - 既出として投稿しないのは、前のレビューやスレッドに指摘として投稿されているもの (行コメントか、レビューの本文の `[must]` / `[imo]` / `[nits]` / `[ask]`) と同じときだけです。そのスレッドへのリンク (「2. 読む」で出た `html_url`) を付けてください。前回の「採らなかった指摘」に載っているだけのものは既出ではないので、改めて判断してください。返信が「後の Issue で直す」なのに Issue の番号が無いときも、改めて判断してください。
4. 指摘に、次のどれかを付けてください。
   - `[must]`: 直さないとマージできない。バグ・脆弱性・完了条件の未達・完了条件のテストが無い・やらないこと を作った・規約違反
   - `[imo]` / `[nits]`: 直すと良いが、マージは止めない
   - `[ask]`: 意図の確認。マージは止めない

### 再レビューのとき
 - 3 の 1・2 は、前回の後の差分ではなく、PR 全体の差分で行ってください。絞るのは、下の 3 つ目・4 つ目のとおり、新しく指摘するものだけです。
 - 前の `[must]` が直ったかを確かめてください。採用しない理由が返信されていて、理由が妥当なら、`[must]` に数えないでください。
 - 新しく指摘するのは、前回の後の push で変わったところと、前回見落としたバグ・脆弱性だけにしてください。前回出さなかった好みの指摘を足すと、再レビューが終わらなくなるためです。
 - 前回の後の push で変わっていないところに、新しく `[must]` を付けるのは、失敗する具体的な入力と、そのときの誤った結果を書けるものだけにしてください。書けないものは `[imo]` にしてください。`xhigh` は確かでない候補も出すので、再レビューが終わらなくならないためです。

## 4. 返す (⑩)
`[must]` が 0 件なら ✅、1 件以上なら 🛑 です。

1. 下の形式で `/tmp/review.json` を書き、`jq . /tmp/review.json > /dev/null` で JSON として正しいかを確かめてください。
   - `event` は `COMMENT` にしてください。Approve / Request changes は、PR の作成者と同じアカウントでは使えません。
   - `commit_id` は、1 で控えた sha にしてください。
   - 指摘は、差分の行に行コメントで付けてください (`side` は追加・変更行なら `RIGHT`、削除行なら `LEFT`)。差分の行に付けられない指摘は、本文に書いてください。422 で行を解決できないと出たら、その指摘を本文に移して投稿し直してください。422 のメッセージを読み、行を解決できない失敗と、本文が長すぎる失敗を分けてください。長すぎるときは、指摘を本文に移さず、下の長さの手順をしてください。
   - 本文と行コメントの先頭に `<!-- fastship:review -->` と改行を付けてください。実装は、このマーカーで ⑨ のレビューを見分けます。
   - 採らなかった指摘 (3 の 3) が 0 件なら、本文の `<details>` は省いてください。本文は 65,536 文字までです。投稿する前と、投稿し直す前に確かめ、超えそうなら、採らなかった指摘は件数だけにしてください。

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
## ✅ レビュー: 問題ありません
<🛑 のときは「## 🛑 レビュー: 直してほしい点があります」>

- コードレビュー: `[must]` <件数> / そのほか <件数> / 採らなかった <件数>
- セキュリティレビュー: `[must]` <件数> / そのほか <件数> / 採らなかった <件数>
- 完了条件: <テストか動作確認で確かめられた数> / <全体の数>

<再レビューのときは、前の `[must]` がどうなったかを 1 行ずつ書く>
<差分の行に付けられない指摘>

<details><summary>採らなかった指摘。対応は要りません</summary>

- `<ファイル>:<行>` <指摘の要約>: <採らなかった理由。既出ならスレッドのリンク>
- <件数だけにしたとき> 脆弱性に当たる候補 <件数> 件 (場所と内容は書きません)

</details>
```

2. PR の head が 1 で控えた sha のままなら、レビューを投稿してください。`MOVED` と出たら、レビューの間に新しい push があったので、投稿せずに 3 に進んでください。古い commit への指摘で、実装を起こさないためです。

```bash
if [ "$(gh api "repos/{owner}/{repo}/pulls/123" --jq .head.sha)" = "<sha>" ]; then
  gh api --method POST "repos/{owner}/{repo}/pulls/123/reviews" --input /tmp/review.json > /dev/null && echo POSTED
else
  echo MOVED
fi
```

3. 次を 1 回の Bash で実行し、`claude:under-review` を外して、🛑 なら PR を Draft に戻してください。`<判定>` は `✅` か `🛑` にしてください。
   - 🛑 では Draft に戻します。実装が直す間は Draft にし、直したら実装が Ready にして再レビューを頼みます。
   - ✅ では Ready のままにします (Draft なら Ready にします)。`MOVED` も Ready のまま `claude:under-review` を付け直し、新しい head のレビューを頼み直します。
   - `claude:under-review` を外してから head を確かめるのは、実装の push と行き違わないためです。外す前の push はここで `claude:under-review` を付け直して頼み直し (`MOVED`)、外した後の push は実装が Ready にして付け直します。

```bash
gh api --method DELETE "repos/{owner}/{repo}/issues/123/labels/claude:under-review" > /dev/null 2>&1 || true
if [ "$(gh api "repos/{owner}/{repo}/pulls/123" --jq .head.sha)" != "<sha>" ]; then
  gh api --method POST "repos/{owner}/{repo}/issues/123/labels" -f "labels[]=claude:under-review" > /dev/null && echo MOVED
elif [ "<判定>" = "✅" ]; then
  { [ "$(gh api "repos/{owner}/{repo}/pulls/123" --jq .draft)" = "false" ] \
    || gh api --method POST "repos/{owner}/{repo}/pulls/123/ccr/ready_for_review" > /dev/null 2>&1 \
    || gh pr ready 123; } && echo APPROVED
else
  { [ "$(gh api "repos/{owner}/{repo}/pulls/123" --jq .draft)" = "true" ] \
    || gh api --method POST "repos/{owner}/{repo}/pulls/123/ccr/convert_to_draft" > /dev/null 2>&1 \
    || gh pr ready --undo 123; } && echo CHANGES
fi
```

4. `APPROVED` と出て、ベースが epic ブランチ (`epic/` で始まる) なら、続けて下のコマンドを 1 回の Bash で実行してください。CI が既に通っていれば、PR を epic ブランチにマージし、Sub Issue を閉じます。
   - ここでも実行するのは、実装が ⑨ のレビューで起こされたときに、まだ `claude:under-review` が外れていないことがあるためです。
   - `WAIT` なら何もしません。実装が、CI の結果で起こされたときにマージします (`/dev:implement` の 7)。
   - `CONFLICT` / `FAILED` なら、結果を PR にコメントします (`<!-- fastship:merge -->`)。実装がこのコメントで起こされ、コンフリクトを解消するか、人間に返します。

```bash
out=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic.sh" merge 123) || out="FAILED: epic.sh がエラーで終わりました"
echo "$out"
case "$out" in
  CONFLICT* | FAILED*)
    jq -n --arg out "$out" '{body: ("<!-- fastship:merge -->\n🔀 ✅ ですが、epic ブランチにマージできませんでした。\n\n```text\n" + $out + "\n```")}' \
      | gh api --method POST "repos/{owner}/{repo}/issues/123/comments" --input - > /dev/null && echo NOTIFIED
    ;;
esac
```

## 判断できないとき
次のように Claude だけで判断できないときは、推測で ✅ / 🛑 を付けず、`/dev:blocked` の「2. 止める」を PR の番号で行ってください。

 - PR の目的が、本文・Sub Issue から読み取れず、正しいかを判断できない
 - 指摘が Sub Issue・親 Issue の決定と食い違い、直すかどうかが仕様の判断になる (例: 完了条件どおりに作ると脆弱性になる)
 - PR の head を checkout できない (403 など)
 - PR を Draft / Ready に切り替えられない (CCR のルートも `gh pr ready` も失敗する)。4 で投稿した後なら、切り替えられなかったことを質問に書いてください

好みや小さな設計の選択は止めずに、`[imo]` で書いてください。

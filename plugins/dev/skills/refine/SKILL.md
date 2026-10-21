---
name: refine
description: FastShip の ⑤⑥ リファインメント。claude:refine が付いた (承認済みの) Issue を、1 PR で終わる Sub Issue に分解して起票し、親 Issue に紐付ける。依存の無い Sub Issue に claude:implement を付けて実装を始める。Sub Issue が閉じたときは、依存が解けた Sub Issue に claude:implement を付け、判断待ちのラベル (claude:analyzed / claude:shipped) を合わせる。Sub Issue がすべて閉じると、親 Issue に claude:shipped (成功指標の確認待ち) が付く。リファインメントルーティンから使う。使い方: /dev:refine {Issue の番号}
argument-hint: "{Issue の番号}"
---

# ✂️ リファインメント

`claude:refine` が付いた Issue を Sub Issue に分解し、実装を始めてください。Sub Issue が閉じて起動したときは、1 で見分けて 6 だけを行います。

GitHub は `gh api` (REST) で操作します。コマンドの `123` は、トリガーになった Issue の番号に置き換えてください。

依存 (先に終わっている必要がある Issue) は、GitHub の Relationships の Blocked by で表します。Sub Issue の本文には書きません。

## 1. 始める
Issue の状態を確かめてください。

```bash
gh api "repos/{owner}/{repo}/issues/123" --jq .state
```

 - `closed` なら、Sub Issue が閉じて起動しています。6 に進んでください。
 - `open` なら、`/dev:blocked` の「1. 始める」を、進行中ラベル `claude:refine` で行ってください。`STOP` と出たら、何もせずに終えてください。
   - `CONTINUE` と出たら、判断待ちのラベルを合わせてください (下のコマンド)。`claude:refine` が付いているので、`claude:analyzed` と `claude:shipped` が外れます。承認されたので承認待ちから外し、やり直しで Sub Issue を足す間は成功指標の確認待ちに載せないためです。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/waiting.sh" sync 123
```

## 2. 読む
Issue の本文とコメント、既にある Sub Issue をすべて読んでください。

```bash
gh api "repos/{owner}/{repo}/issues/123" --jq '.title, .body'
gh api --paginate "repos/{owner}/{repo}/issues/123/comments" --jq '.[] | "### \(.user.login) (\(.created_at))\n\(.body)\n"'
gh api --paginate "repos/{owner}/{repo}/issues/123/sub_issues" --jq '.[] | "#\(.number) \(.state) [\([.labels[].name] | join(", "))] \(.title)"'
```

 - 課題 / 解決策 / 成功指標 が分解の元です。リポジトリのコードとドキュメントも読み、どこを変えるかを確かめてください。
 - リファインメントの完了コメント (`<!-- fastship:refine -->` で始まる) があれば、やり直しです。それ以降の開発者のコメントを反映してください。
 - 完了コメントが無いのに Sub Issue があれば、前のセッションが途中で止まっています。同じ作業の Sub Issue を重複して作らないでください。
 - 既にある Sub Issue の依存は、下のコマンドで確かめてください。

```bash
gh api --paginate "repos/{owner}/{repo}/issues/<Sub Issue の番号>/dependencies/blocked_by" --jq '.[] | "#\(.number) id=\(.id) \(.state) \(.title)"'
```

## 3. 分解する
 - 1 つの Sub Issue は 1 PR で終わる大きさにしてください。目的が 1 つで、レビューで読み切れる量が目安です。
 - 単独でマージしても壊れず、テストが通る単位にしてください。層 (DB / API / UI) ではなく、確かめられる振る舞いで分けてください。
 - 解決策 全体が 1 PR で終わるなら、分けずに Sub Issue を 1 つにしてください。分けるのは 1 PR に収まらないときだけです。
 - 解決策 に無いことは Sub Issue にしないでください。
 - 成功指標を測る仕組み (ログ・計測など) が要るなら、それも Sub Issue にしてください。
 - 依存 は、前の Sub Issue のコードが無いと作れないときだけ付けてください。依存の無い Sub Issue は、同時に実装が始まります。

### やり直しのとき
 - 着手前の Sub Issue (5 の条件のうち、依存 以外を満たすもの) は、本文と依存を直すか、不要なら閉じてください。
 - 着手済みの Sub Issue は変えないでください。足りない作業は、新しい Sub Issue にしてください。
 - Sub Issue を閉じる前に、それに依存している Sub Issue を下の 2 つ目のコマンドで確かめてください。代わりの依存が要れば、閉じる前に足してください。閉じた Issue への依存は解けた扱いになり、5 や 6 で実装が始まってしまうためです。閉じた後に、閉じた Issue への依存を外してください。
 - 依存を足すときは 4 の 3 のコマンドを、外すときは外す依存の `id` (2 のコマンドで出ます) で下の 4 つ目のコマンドを使ってください。

```bash
jq -n --rawfile body /tmp/sub_issue.md '{body:$body}' \
  | gh api --method PATCH "repos/{owner}/{repo}/issues/<Sub Issue の番号>" --input - > /dev/null
gh api --paginate "repos/{owner}/{repo}/issues/<閉じる Sub Issue の番号>/dependencies/blocking" --jq '.[] | "#\(.number) \(.state) \(.title)"'
gh api --method PATCH "repos/{owner}/{repo}/issues/<Sub Issue の番号>" -f state=closed -f state_reason=not_planned > /dev/null
gh api --method DELETE "repos/{owner}/{repo}/issues/<Sub Issue の番号>/dependencies/blocked_by/<依存の id>" > /dev/null
```

### 判断できないとき
次のように Claude だけで判断できないときは、推測で分けず、`/dev:blocked` の「2. 止める」で人間に返してください。

 - 解決策 が空で、課題分析が済んでいない
 - 解決策 がリポジトリの今の作りと合わず、どう分けるかで結果が大きく変わる

## 4. 起票する
着手順 (依存される側が先) に、1 つずつ起票し、依存を登録してから親 Issue に紐付けてください。先に起票した Sub Issue を、後の Sub Issue の依存にできます。

1. `${CLAUDE_PLUGIN_ROOT}/templates/ISSUE_TEMPLATE/todo.md` の欄に沿って、`/tmp/sub_issue.md` に本文を書いてください。
   - 先頭の YAML frontmatter は含めないでください。HTML コメントは残し、その下に書いてください。
   - タイトルは、何を変えるかが分かる短い文にしてください。
2. 起票して、出力された `number` と `id` を控えてください。

```bash
jq -n --arg title "<タイトル>" --rawfile body /tmp/sub_issue.md '{title:$title, body:$body}' \
  | gh api --method POST "repos/{owner}/{repo}/issues" --input - --jq '"number=\(.number) id=\(.id)"'
```

3. 依存があれば、依存先ごとに Blocked by に登録してください。依存先は番号ではなく `id` で指定します。先に起票した Sub Issue の `id` は 2 の出力にあります。ほかの Issue の `id` は、下の 2 つ目のコマンドで取れます。別のリポジトリの Issue なら、`{owner}/{repo}` をそのリポジトリにしてください。

```bash
gh api --method POST "repos/{owner}/{repo}/issues/<Sub Issue の番号>/dependencies/blocked_by" -F issue_id=<依存の id> > /dev/null
gh api "repos/{owner}/{repo}/issues/<依存の番号>" --jq .id
```

4. 2 の `id` で親 Issue に紐付けてください。紐付けは依存を登録した後に行い、ラベルはまだ付けません。親 Issue に紐付くと、ほかの Sub Issue が閉じたときに 6 で実装が始まることがあるためです。

```bash
gh api --method POST "repos/{owner}/{repo}/issues/123/sub_issues" -F sub_issue_id=<id> > /dev/null
```

## 5. 着手する
1. 次の条件をすべて満たす Sub Issue に、`claude:implement` を付けてください。実装ルーティンが始まります。
   - open である
   - `claude:implement` / `claude:blocked` が付いていない
   - 着手コメント (`<!-- fastship:start -->` で始まる) が無い。実装を始めた後に止まった Sub Issue に付け直さないためです
   - 依存 (Blocked by) の Issue がすべて closed である (依存が無い場合を含む)

   open かどうかとラベルは、2 の Sub Issue の一覧で確かめてください。依存は下の 1 つ目のコマンドで確かめ、エラーが無く何も出なければ満たしています。エラーが出たら、満たしていないものとして扱ってください。親 Issue の外の Issue への依存も含まれます。

```bash
gh api --paginate "repos/{owner}/{repo}/issues/<Sub Issue の番号>/dependencies/blocked_by" --jq '.[] | select(.state == "open") | "#\(.number)"'
gh api --paginate "repos/{owner}/{repo}/issues/<Sub Issue の番号>/comments" --jq '.[] | select(.body | startswith("<!-- fastship:start -->")) | .id'
gh api --method POST "repos/{owner}/{repo}/issues/<Sub Issue の番号>/labels" -f "labels[]=claude:implement" > /dev/null
```

2. 下の形式で `/tmp/refine_done.md` を書き、次を 1 回の Bash で実行してください。親 Issue にコメントしてから `claude:refine` を外し、判断待ちのラベルを合わせます。
   - `claude:refine` を外しておくと、やり直すときに開発者が付け直せます。
   - リファインメントの間に差し戻されて課題分析が終わっていれば、`claude:analyzed` が付きます (承認待ち)。やり直しで残りの Sub Issue を閉じて、すべて閉じていれば `claude:shipped` が付きます。

```bash
jq -n --rawfile body /tmp/refine_done.md '{body:$body}' \
  | gh api --method POST "repos/{owner}/{repo}/issues/123/comments" --input - > /dev/null
gh api --method DELETE "repos/{owner}/{repo}/issues/123/labels/claude:refine" > /dev/null
bash "${CLAUDE_PLUGIN_ROOT}/scripts/waiting.sh" sync 123
```

```markdown
<!-- fastship:refine -->
## ✂️ リファインメントが終わりました

Sub Issue に分けました。上から着手順です。

1. #<番号> (依存: なし) 🧑‍💻 着手しました
2. #<番号> (依存: #<番号>)

<やり直しのときだけ、前回から変えたことを 1〜3 行で書く>

依存の無い Sub Issue から実装を始めました。残りは、依存する Sub Issue が閉じると始まります。始まらないときは、その Sub Issue に `claude:implement` を付けてください。

**やり直すには**: 直してほしい点をコメントし、`claude:refine` を付け直してください。着手前の Sub Issue を直します。
```

## 6. 後続に着手する (Sub Issue が閉じたとき)
閉じた Sub Issue には `claude:refine` が無いため、`/dev:blocked` の「1. 始める」は行いません。コメントもしません。

1. 親 Issue の番号を取得してください。何も出なければ、Sub Issue ではないか、親 Issue が別のリポジトリにあります。何もせずに終えてください。以降のコマンドは、このリポジトリの番号として扱うためです。

```bash
gh api "repos/{owner}/{repo}/issues/123" \
  --jq '.repository_url as $repo | .parent_issue_url // empty | select(startswith($repo + "/issues/")) | split("/") | last'
```

2. 親 Issue の Sub Issue を読み、5 の条件をすべて満たすものに `claude:implement` を付けてください。確かめ方は 5 と同じです。

```bash
gh api --paginate "repos/{owner}/{repo}/issues/<親 Issue の番号>/sub_issues" --jq '.[] | "#\(.number) \(.state) [\([.labels[].name] | join(", "))] \(.title)"'
```

3. 親 Issue の判断待ちのラベルを合わせてください。Sub Issue がすべて閉じていれば `claude:shipped=yes` と出て、親 Issue に `claude:shipped` が付きます。FastShip プロジェクトの成功指標の確認待ちに載り、開発者が ⑫ で確かめます。付かないときは、理由が括弧の中に出ます。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/waiting.sh" sync <親 Issue の番号>
```

同時に閉じた Sub Issue のセッションが並んで動くと、古い状態でラベルを付け外しすることがあります。`waiting.sh` は状態からラベルを決めるので、次に実行したとき (遅くとも週 1 回の振り返り) に直ります。

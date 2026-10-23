---
name: refine
description: FastShip の ⑤⑥ リファインメント。claude:refine が付いた (承認済みの) Issue を、1 PR で終わる Sub Issue に分解して起票し、親 Issue に紐付ける。1 PR で済む Issue は分けず、完了条件・やらないことを書き足して Issue に claude:implement を付ける。Sub Issue の PR は epic ブランチ (epic/<親 Issue の番号>) に向ける。依存の無い Sub Issue に claude:implement を付けて実装を始める。Sub Issue が閉じたときは、依存が解けた Sub Issue に claude:implement を付け、すべて閉じていれば epic ブランチをデフォルトブランチに入れる PR を作る。ルーティンから使う。使い方: /dev:refine {Issue の番号}
argument-hint: "{Issue の番号}"
---

# ✂️ リファインメント

`claude:refine` が付いた Issue を Sub Issue に分解し、実装を始めてください。1 PR で済む Issue は分けずに、Issue をそのまま実装に回します (3 の「1 PR で済むとき」)。Sub Issue が閉じて起動したときは、1 で見分けて 6 だけを行います (すべて閉じていれば、epic ブランチをデフォルトブランチに入れる PR を作ります)。

GitHub は `gh api` (REST) で操作します。コマンドの `123` は、トリガーになった Issue の番号に置き換えてください。

依存 (先に終わっている必要がある Issue) は、GitHub の Relationships の Blocked by で表します。Sub Issue の本文には書きません。

## 1. 始める
Issue の状態を確かめてください。

```bash
gh api "repos/{owner}/{repo}/issues/123" --jq .state
```

 - `closed` なら、`claude:implement` の付いた Issue (Sub Issue か、そのまま実装した Issue) が閉じて起動しています。6 に進んでください。
 - `open` なら、`/dev:blocked` の「1. 始める」を、進行中ラベル `claude:refine` で行ってください。`STOP` と出たら、何もせずに終えてください。
   - `CONTINUE` と出たら、判断待ちのラベルを合わせてください (下のコマンド)。`claude:refine` が付いているので、`claude:analyzed` が外れます。承認されたので承認待ちから外すためです。

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

 - 課題 / 解決策 / 要件 が分解の元です。リポジトリのコードとドキュメントも読み、どこを変えるかを確かめてください。
 - リファインメントの完了コメント (`<!-- fastship:refine -->` で始まる) があれば、やり直しです。それ以降の開発者のコメントを反映してください。
 - 完了コメントが無いのに Sub Issue があれば、前のセッションが途中で止まっています。同じ作業の Sub Issue を重複して作らないでください。
 - 完了コメントがあって Sub Issue が無ければ、前回は 1 PR で済むとして、この Issue をそのまま実装に回しています (3 の「1 PR で済むとき」)。
 - 既にある Sub Issue の依存は、下の 1 つ目のコマンドで確かめてください。
 - この Issue の依存 (Blocked by) も、下の 2 つ目のコマンドで確かめてください。open なものが出たら、3 の「判断できないとき」です。課題分析が大きい Issue を分けたときに付けます。

```bash
gh api --paginate "repos/{owner}/{repo}/issues/<Sub Issue の番号>/dependencies/blocked_by" --jq '.[] | "#\(.number) id=\(.id) \(.state) \(.title)"'
gh api --paginate "repos/{owner}/{repo}/issues/123/dependencies/blocked_by" --jq '.[] | select(.state == "open") | "#\(.number) \(.title)"'
```

## 3. 分解する
 - 1 つの Sub Issue は 1 PR で終わる大きさにしてください。目的が 1 つで、レビューで読み切れる量 (自動生成を除き、テストを含めて差分が 500 行ほど) が目安です。大きい PR は、レビューで差分を読み切れず、指摘が漏れるためです。
 - 単独でマージしても壊れず、テストが通る単位にしてください。層 (DB / API / UI) ではなく、確かめられる振る舞いで分けてください。
 - 解決策 全体が 1 PR で終わるなら、分けずに、Sub Issue を作らずこの Issue をそのまま実装してください (下の「1 PR で済むとき」)。分けるのは 1 PR に収まらないときだけです。
 - 解決策 に無いことは Sub Issue にしないでください。
 - 要件 (機能要件・非機能要件) は、どれも 1 つ以上の Sub Issue の 完了条件 に入れてください。非機能要件は、当てはまる Sub Issue すべての 完了条件 に入れます。⑨ レビューは完了条件で確かめるため、どこにも入らない要件は確かめられません。
 - 依存 は、前の Sub Issue のコードが無いと作れないときだけ付けてください。依存の無い Sub Issue は、同時に実装が始まります。

### 1 PR で済むとき
次をすべて満たすときは、Sub Issue を作らず、この Issue をそのまま実装に回します。Sub Issue を 1 つ作っても親の解決策を写すだけになり、Issue・待ちが増えるためです。4 と 5 の 1 は行わず、下の手順の後に 5 の 2 に進んでください。

 - 解決策 全体 (要件をすべて満たすところまで) が 1 PR で終わる
 - Sub Issue が無い。既にあれば (やり直し)、今までどおり Sub Issue で進めてください

1. この Issue に実装の着手コメント (下の 1 つ目のコマンド) があれば、実装が始まっています。本文を変えず、`/dev:blocked` の「2. 止める」で、どう直すかを人間に聞いてください。
2. 本文 (下の 2 つ目のコマンド) の末尾に、`## やらないこと` と `## 完了条件` を書き足してください。書き方は `${CLAUDE_PLUGIN_ROOT}/templates/ISSUE_TEMPLATE/todo.md` の同じ欄に合わせます。完了条件 には、要件 (機能要件・非機能要件) をすべて入れてください。⑨ レビューは完了条件で確かめるためです。既にあれば (やり直し)、書き足さずに直してください。ほかの欄は変えないでください。書いたら 3 つ目のコマンドで更新します。
3. `claude:implement` が付いていなければ、付けてください (下の 4 つ目のコマンド)。実装が始まります。

```bash
gh api --paginate "repos/{owner}/{repo}/issues/123/comments" --jq '.[] | select(.body | startswith("<!-- fastship:start -->") and contains("`claude:implement`")) | .id'
gh api "repos/{owner}/{repo}/issues/123" --jq .body > /tmp/issue.md
jq -n --rawfile body /tmp/issue.md '{body:$body}' \
  | gh api --method PATCH "repos/{owner}/{repo}/issues/123" --input - > /dev/null
gh api --method POST "repos/{owner}/{repo}/issues/123/labels" -f "labels[]=claude:implement" > /dev/null
```

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
 - この Issue の依存 (Blocked by) に open な Issue がある (2 の 2 つ目のコマンド)。依存のコードがまだデフォルトブランチに無く、それが無いベースで実装が始まってしまうためです。依存が閉じてから `claude:refine` を付け直すよう頼んでください

## 4. 起票する
はじめに、epic ブランチ `epic/123` を作ってください (下のコマンド)。Sub Issue の PR は epic ブランチに向け、⑨ の ✅ と CI の成功で実装がマージします。すべて終わると、6 で epic ブランチをデフォルトブランチに入れる PR を作り、開発者はその PR で全体をレビューします。Sub Issue の PR を 1 つずつ人がマージ・レビューしなくて済むようにするためです。

 - 2 の一覧に Sub Issue があれば、実行しないでください。epic ブランチは Sub Issue より先に作るので、あれば作ってあります。無ければ前の版で分けた Issue なので、今までどおり Sub Issue の PR をデフォルトブランチに向けます。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic.sh" create 123
```

次に、着手順 (依存される側が先) に、1 つずつ起票し、依存を登録してから親 Issue に紐付けてください。先に起票した Sub Issue を、後の Sub Issue の依存にできます。

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
1. 次の条件をすべて満たす Sub Issue に、`claude:implement` を付けてください。実装が始まります。
   - open である
   - `claude:implement` / `claude:blocked` が付いていない
   - 実装の着手コメント (`<!-- fastship:start -->` で始まり、`` `claude:implement` `` を含む) が無い。実装を始めた後に止まった Sub Issue に付け直さないためです
   - 依存 (Blocked by) の Issue がすべて closed である (依存が無い場合を含む)

   open かどうかとラベルは、2 の Sub Issue の一覧で確かめてください。依存は下の 1 つ目のコマンドで確かめ、エラーが無く何も出なければ満たしています。エラーが出たら、満たしていないものとして扱ってください。親 Issue の外の Issue への依存も含まれます。

```bash
gh api --paginate "repos/{owner}/{repo}/issues/<Sub Issue の番号>/dependencies/blocked_by" --jq '.[] | select(.state == "open") | "#\(.number)"'
gh api --paginate "repos/{owner}/{repo}/issues/<Sub Issue の番号>/comments" --jq '.[] | select(.body | startswith("<!-- fastship:start -->") and contains("`claude:implement`")) | .id'
gh api --method POST "repos/{owner}/{repo}/issues/<Sub Issue の番号>/labels" -f "labels[]=claude:implement" > /dev/null
```

2. 下の形式 (1 PR で済むときは 2 つ目) で `/tmp/refine_done.md` を書き、次を 1 回の Bash で実行してください。親 Issue にコメントしてから `claude:refine` を外し、判断待ちのラベルを合わせます。
   - `claude:refine` を外しておくと、やり直すときに開発者が付け直せます。
   - リファインメントの間に差し戻されて課題分析が終わっていれば、`claude:analyzed` が付きます (承認待ち)。

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

<epic ブランチがあるときだけ「Sub Issue の PR は `epic/123` に向け、レビューが ✅ で CI が通るとマージします。すべて終わると `epic/123` を `<デフォルトブランチ>` に入れる PR を作るので、全体はその PR でレビューしてください。」と書く>

**やり直すには**: 直してほしい点をコメントし、`claude:refine` を付け直してください。着手前の Sub Issue を直します。
```

```markdown
<!-- fastship:refine -->
## ✂️ リファインメントが終わりました

1 PR で済むため、Sub Issue に分けず、この Issue をそのまま実装します。本文に やらないこと・完了条件 を書き足しました。🧑‍💻 着手しました

<やり直しのときだけ、前回から変えたことを 1〜3 行で書く>

実装が始まらないときは、この Issue に `claude:implement` を付けてください。

**やり直すには**: 直してほしい点をコメントし、`claude:refine` を付け直してください。実装を始める前なら本文を直します。
```

## 6. 後続に着手する (Sub Issue が閉じたとき)
閉じた Issue には `claude:refine` が無いため、`/dev:blocked` の「1. 始める」は行いません。コメントもしません (5 で PR を作れないときを除く)。

1. 閉じた Issue にリファインメントの完了コメントがあるか確かめてください (下の 1 つ目のコマンド)。何か出たら、1 PR で済むとしてそのまま実装した Issue が閉じています。後続の Sub Issue は無いので、何もせずに終えてください。その Issue に親 Issue があっても、親の Sub Issue には着手しません。親はリファインメントで分けたものではなく、承認されていない Issue の実装が始まってしまうためです。
2. 親 Issue の番号を取得してください (下の 2 つ目のコマンド)。何も出なければ、Sub Issue ではないか、親 Issue が別のリポジトリにあります。何もせずに終えてください。以降のコマンドは、このリポジトリの番号として扱うためです。

```bash
gh api --paginate "repos/{owner}/{repo}/issues/123/comments" \
  --jq '.[] | select((.body | startswith("<!-- fastship:refine -->")) and (.author_association | test("^(OWNER|MEMBER|COLLABORATOR)$"))) | .id'
gh api "repos/{owner}/{repo}/issues/123" \
  --jq '.repository_url as $repo | .parent_issue_url // empty | select(startswith($repo + "/issues/")) | split("/") | last'
```

3. epic ブランチに、デフォルトブランチの最新を取り込んでください (下のコマンド)。後続の Sub Issue を最新のコードから作り、最後の PR でのコンフリクトを減らすためです。
   - `SKIP` と出たら、epic ブランチがありません (前の版で分けた Issue)。5 で、今までどおり親 Issue を閉じます。
   - `CONFLICT` と出ても、止めずに続けてください。5 で作る PR で、開発者が解消します。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic.sh" sync <親 Issue の番号>
```

4. 親 Issue の Sub Issue を読み、5 の条件をすべて満たすものに `claude:implement` を付けてください。確かめ方は 5 と同じです。

```bash
gh api --paginate "repos/{owner}/{repo}/issues/<親 Issue の番号>/sub_issues" --jq '.[] | "#\(.number) \(.state) [\([.labels[].name] | join(", "))] \(.title)"'
```

5. 親 Issue を仕上げるかを決めてください。次をすべて満たせば仕上げます。
   - 4 の一覧の Sub Issue がすべて closed で、1 つ以上が完了 (`state_reason` が `completed`) である。すべて見送り (`not_planned`) なら、開発者が判断できるよう残します
   - 親 Issue に `claude:analysis` / `claude:analyzed` / `claude:refine` / `claude:blocked` が付いていない。差し戻し・やり直し・質問の途中で仕上げないためです

```bash
gh api --paginate "repos/{owner}/{repo}/issues/<親 Issue の番号>/sub_issues" --jq '.[] | "#\(.number) \(.state) \(.state_reason)"'
gh api "repos/{owner}/{repo}/issues/<親 Issue の番号>" --jq '[.labels[].name] | join(", ")'
```

### epic ブランチがあるとき
epic ブランチをデフォルトブランチに入れる PR を、Ready で作ってください。開発者がこの PR で全体をレビューしてマージすると、`Closes` で親 Issue が閉じます。`⑪ マージ待ち` に載ります。

 - 既に open な PR があれば (下の 1 つ目のコマンドで出る)、作らないでください。
 - ⑨ レビューは頼みません。Sub Issue の PR ごとにレビュー済みのためです。開発者が頼むときは、PR に `claude:under-review` を付けます。

1. マージした Sub Issue の PR を読んでください (下の 2 つ目のコマンド)。本文の `Closes #N` が Sub Issue、✔️ 動作確認 が確かめた方法です。
2. `${CLAUDE_PLUGIN_ROOT}/templates/PULL_REQUEST_TEMPLATE.md` の欄に沿って、`/tmp/epic_pr.md` に本文を書いてください。HTML コメントは消してください。
   - 💡 概要: 親 Issue の 課題 と 解決策 を 2〜3 行で書き、`Closes #<親 Issue の番号>` を付けます。3 で `CONFLICT` と出たら、先頭に「⚠️ デフォルトブランチとコンフリクトしています。マージする前に解消してください」と書きます。
   - 🙆‍♂️ やったこと: Sub Issue ごとに 1 行で、何が変わったかと、`#<Sub Issue>` (`#<PR>`) を書きます。
   - 🙅‍♂️ やらないこと: 親 Issue の 課題 の範囲外と、見送った Sub Issue を書きます。
   - ✔️ 動作確認: 親 Issue の 要件 ごとに、確かめた PR (`#<PR>`) を書きます。どの PR でも確かめていない要件は、そう書きます。開発者が確かめる所です。
3. PR を作ってください (下の 3 つ目のコマンド)。作ったら、`unsubscribe_pr_activity` で PR の購読を外してください (ルーティンが PR を作ったセッションに購読させるため)。この PR の CI とレビューは、開発者が見ます。既にあると出たら (Sub Issue が同時に閉じ、別のセッションが作った)、何もせずに終えてください。ほかの理由で作れなければ (差分が無いなど)、出たエラーを親 Issue にコメントして終えてください。

```bash
gh api --paginate "repos/{owner}/{repo}/pulls?state=open&per_page=100" --jq '.[] | select(.head.ref == "epic/<親 Issue の番号>") | .html_url'
gh api --paginate "repos/{owner}/{repo}/pulls?state=closed&base=epic/<親 Issue の番号>&per_page=100" \
  --jq '.[] | select(.merged_at) | "### #\(.number) \(.title)\n\(.body)\n"'
jq -n --arg title "<親 Issue のタイトル>" --arg base "$(gh api "repos/{owner}/{repo}" --jq .default_branch)" --rawfile body /tmp/epic_pr.md \
    '{title:$title, head:"epic/<親 Issue の番号>", base:$base, body:$body}' \
  | gh api --method POST "repos/{owner}/{repo}/pulls" --input - --jq .html_url
```

### epic ブランチが無いとき
下のコマンドで、親 Issue を完了として閉じてください。フローは ⑪ マージで終わるためです (1 PR で済む Issue が PR の `Closes` で閉じるのとそろえます)。親 Issue には `claude:implement` が付かないので、閉じてもリファインメントは起動しません。

```bash
gh api --method PATCH "repos/{owner}/{repo}/issues/<親 Issue の番号>" -f state=closed -f state_reason=completed > /dev/null
```

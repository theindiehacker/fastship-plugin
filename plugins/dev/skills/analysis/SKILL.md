---
name: analysis
description: FastShip の ③ 課題分析。claude:analysis が付いた Issue の課題の解像度と解決策の質を上げ、確かめられる機能要件・非機能要件を決めて、Issue の 課題 / 解決策 / 要件 に書く。画面・API / MCP・インフラ構成が変わるなら、合意するための見本 (モック画面・Mermaid・定義とスタブ) を Draft PR で作り、Issue の 見本 に書く。大きければ Feature Issue に分ける。終わったら開発者に承認 (claude:refine) を依頼し、claude:analyzed (承認待ち) を付ける。差し戻し (コメント + claude:analysis の付け直し) では、コメントを反映して分析し直す。ルーティンから使う。使い方: /dev:analysis {Issue の番号}
argument-hint: "{Issue の番号}"
---

# 🤔 課題分析

`claude:analysis` が付いた Issue を分析し、本文の 課題 / 解決策 / 要件 / 見本 を書いてください。開発者は見本と要件を見て、④ 承認するかを決めます。文章だけでは読み手によって解釈が分かれ、作るものがずれるためです。

GitHub は `gh api` (REST) で操作します。コマンドの `123` は Issue の番号に置き換えてください。

## 1. 始める
`/dev:blocked` の「1. 始める」を、進行中ラベル `claude:analysis` で行ってください。`STOP` と出たら、何もせずに終えてください。

`CONTINUE` と出たら、判断待ちのラベルを合わせてください。`claude:analysis` が付いているので、`claude:analyzed` が外れます。差し戻しで分析し直している間、`④ 承認待ち` の一覧に載せないためです。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/waiting.sh" sync 123
```

## 2. 読む
Issue の本文とコメントをすべて読んでください。

```bash
gh api "repos/{owner}/{repo}/issues/123" --jq '.title, .body'
gh api --paginate "repos/{owner}/{repo}/issues/123/comments" --jq '.[] | "### \(.user.login) (\(.created_at))\n\(.body)\n"'
```

 - 参考資料 にある関連 Issue・URL も読んでください。
 - リポジトリのコードとドキュメントを読み、今の振る舞いを確かめてください。推測で書かないためです。
 - 課題分析の完了コメント (`<!-- fastship:analysis -->` で始まる) があれば、差し戻しです。それ以降の開発者のコメントを反映して、分析し直してください。
 - 見本の PR があれば (下の 1 つ目のコマンドで `<PR の番号> <sha>` が出る)、PR のコメントと行コメントも読んでください (2 つ目・3 つ目)。開発者は、見本への指摘を PR に書くことがあります。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/mock.sh" show 123
gh api --paginate "repos/{owner}/{repo}/issues/<見本の PR>/comments" --jq '.[] | "### \(.user.login) (\(.created_at))\n\(.body)\n"'
gh api --paginate "repos/{owner}/{repo}/pulls/<見本の PR>/comments" --jq '.[] | "### \(.user.login) \(.path):\(.line // .original_line) (\(.created_at))\n\(.body)\n"'
```

## 3. 分析する
開発者が ④ で数分で判断できるよう、課題・解決策・要件はそれぞれ 10 行程度に収めてください。収まらないほど大きければ、Issue を分けてください (下の「分けるか決める」)。

### 課題
 - 背景 から、誰が・どの場面で・何に困っているかを特定してください。要望 (〇〇 がほしい) は解決策の案として扱い、課題と分けてください。
 - 要望に「それは具体的に何か」(What) と「なぜそれが要るのか」(Why) を、それぞれ 5 回を目安に問い、具体的な場面・本当の目的・根本原因を特定してください。目的がこの Issue の範囲を超えたら、そこで止めます。解く範囲が広がるためです。
 - Issue には結論 (目的と根本原因) だけを書き、問いの過程は書かないでください。④ で読む量を増やさないためです。
 - 今回解く範囲を決めてください。範囲外にしたことは、開発者が範囲内だと思いそうなものだけ 1 行ずつ書いてください。

### 解決策
 - 背景 の案を含め、2〜3 案を比べてください。案には次の 2 つを必ず入れてください。要望をそのまま作る大きい案に寄りがちなためです。
   - 作らない案: 運用・設定・既存の機能・外部のサービスやライブラリで済ませる
   - 1/10 の工数案: 要望をそのまま作る案の 1/10 の工数で、課題の大半を解く
 - 課題を解ける最も小さい案を選び、選んだ理由 (効果・コスト・リスク) を書いてください。見送った案は、理由と合わせて 1 行ずつ書いてください。
 - 何が変わるか (利用者から見た振る舞い) は、解決策ではなく 要件 に書いてください。

### 要件
作ったものが満たすことを書いてください。⑥ リファインメントが Sub Issue の完了条件に振り分け、⑨ レビューが確かめます。作り終えたときに確かめられることだけを書きます。

 - 課題を解くのに要るものだけを書いてください。あると良いもの・将来のためのものは書かないでください。要件の 1 行が、実装とテストを増やすためです。
 - 機能要件: 利用者から見た振る舞いを、1 行に 1 つ書いてください。うまくいく場合と、主な失敗の場合 (権限が無い・入力が正しくないなど) を含めます。例: `- 未ログインで API を呼ぶと 401 で断る`
 - 非機能要件: セキュリティ・性能・可用性・運用 (ログ・監視) などのうち、この Issue で守るものだけを書いてください。数値にできるものは数値にします。例: `- 一覧の API は 1,000 件を 500 ms 以内に返す`。当てはまるものが無ければ `- なし` と書きます。
 - どう作るか (変数名・プロセスの構成・設定の方法など) は書かないでください。⑥ と ⑧ で決めます。
 - 「使いやすい」「安全である」のような、確かめられない書き方はしないでください。
 - 画面の見た目・文言や、API の項目の一覧のように見本 (4) で見せるものは、要件に書き並べないでください。文章が長いと、④ で見落とすためです。

### 分けるか決める
次のどちらかに当たれば、この Issue を分け、残りを新しい Issue (Feature Issue) にしてください。Issue が大きいと、④ 承認と、最後に開発者が見る epic の PR (`/dev:refine`) を読み切れなくなるためです。

 - 機能要件に、片方だけ作っても利用者の役に立つまとまりが 2 つ以上ある
 - Sub Issue が 4 つ以上 (テストを含めて差分が 2,000 行ほど) になりそう

ただし、Sub Issue が既にある (リファインメント済み) とき、そろわないと役に立たないときは分けないでください。

分けるときは、この Issue を最初に作るまとまりに絞り、課題 (今回の範囲) / 解決策 / 要件 を書いてください。分けた先は、課題 の範囲外に 1 行ずつ書きます (5 で番号を書く)。背景 は変えないでください。残りのまとまりは、5 で新しい Issue として起票します。

### 判断できないとき
次のように Claude だけで判断できないときは、推測で書かず、`/dev:blocked` の「2. 止める」で人間に返してください。

 - 背景 から、誰の何の課題かが読み取れない
 - 案を選ぶ基準 (優先したいこと・予算・期限など) が Issue やリポジトリから分からず、どの案を選ぶかで結果が大きく変わる

非機能要件の数値など、仮に置けば分析を進められるものは止めずに仮置きし、6 の「確認してほしい点」に書いてください。開発者が ④ で確認します。

## 4. 見本を作る
作るものを ④ で見て決められるよう、見本を作り、Draft PR にしてください。見本は ⑥ リファインメントが完了条件に入れ、⑧ 実装と ⑨ レビューが見本どおりかを確かめます。

### 作るか決める
画面・API / MCP の入出力・インフラ構成のどれかが変わるときだけ作ってください。どれも変わらない (バグ修正・内部の整理・ドキュメントなど) なら作らず、5 で 見本 に `- なし` と書きます。3 で分けたときは、この Issue に残したまとまりの分だけ作ります。

| 変わるもの | 作るもの |
|:--|:--|
| 画面 | 機能要件の場面 (うまくいく場合・主な失敗・空の状態) ごとに、固定のデータで表示するモック画面。本番で画面を置く場所に、リポジトリのコンポーネントで作り、場面ごとにスクリーンショットを撮る |
| API / MCP | 定義 (OpenAPI / MCP のツールの name・description・inputSchema) を本番で置く場所に書き、入出力の例 (うまくいく場合・主な失敗) を固定で返すスタブを作る。呼び出しの流れは Mermaid のシーケンス図にする |
| インフラ | 構成図 (Mermaid) と、追加・変更・削除するリソースの一覧を、設計書に書く。置き場所はリポジトリの設計書の場所で、無ければ `.fastship/mock/123/README.md` |

 - 要件を確かめられる最小限にしてください。見本はマージせず、実装が仕上げるためです。テスト・エラー処理・本物のデータ・見た目の作り込みは要りません。
 - 見本のコードは、本番で置く場所に置いてください。実装が、そのまま出発点として持ってこられるようにするためです。
 - スクリーンショットは、Playwright で撮り (クラウド環境には Chromium が入っています)、`.fastship/mock/123/` に PNG で置いてください。起動の手順は、リポジトリの `CLAUDE.md`・README・CI の準備のステップに従ってください。起動できなければ、同じ画面を単体の HTML で作って撮ってください。
 - 撮ったスクリーンショットを Read で見て、要件どおりかを確かめてください。

### ブランチを用意する
 - 2 で見本の PR が出たら (差し戻し)、その PR のブランチ (下の 1 つ目のコマンドの 2 行目) を checkout して直してください (3 つ目)。PR が閉じていれば (リファインメントが閉じた後の差し戻し)、開き直してください (2 つ目)。
 - 無ければ、セッションの作業ブランチ (指定が無ければ `claude/mock-123`) を、デフォルトブランチの最新から作ってください (4 つ目)。

```bash
gh api "repos/{owner}/{repo}/pulls/<見本の PR>" --jq '.state, .head.ref'
gh api --method PATCH "repos/{owner}/{repo}/pulls/<見本の PR>" -f state=open > /dev/null
git fetch origin "<見本の PR のブランチ>" && git checkout -B "<見本の PR のブランチ>" "origin/<見本の PR のブランチ>"
default=$(gh api "repos/{owner}/{repo}" --jq .default_branch) && git fetch origin "$default" && git checkout -B "<作業ブランチ>" "origin/$default"
```

### PR にする
1. 見本をコミットして push し、push した commit の sha (`git rev-parse HEAD`) を控えてください。5 で Issue に書き、承認する版を固定します。
   - CI が失敗しても直さないでください。見本はマージしないためです。
2. 下の形式で `/tmp/mock_pr.md` を書いてください。
   - `Closes` は書かないでください。マージしない PR なので、実装の PR の見分け (`Closes #<Issue>`) と混ざらないようにするためです。
   - スクリーンショットは、Files changed でも見られます。
3. 見本の PR が無ければ、Draft で作ってください (下の 1 つ目のコマンド)。作ったら、`unsubscribe_pr_activity` で PR の購読を外してください。ルーティンは PR を作ったセッションに購読させるため、外さないと CI の結果でこのセッションが起こされます。見本の PR があれば、本文を更新してください (2 つ目)。

```bash
jq -n --arg title "見本: <Issue のタイトル>" --arg head "<作業ブランチ>" --arg base "$(gh api "repos/{owner}/{repo}" --jq .default_branch)" --rawfile body /tmp/mock_pr.md \
    '{title:$title, head:$head, base:$base, body:$body, draft:true}' \
  | gh api --method POST "repos/{owner}/{repo}/pulls" --input - --jq .number
jq -n --rawfile body /tmp/mock_pr.md '{body:$body}' \
  | gh api --method PATCH "repos/{owner}/{repo}/pulls/<見本の PR>" --input - > /dev/null
```

````markdown
<!-- fastship:mock -->
#123 の見本です。**マージしません**。④ で承認されると、リファインメントが閉じます。

<画面: 場面ごとに「### <場面>」と ![<場面>](https://github.com/<owner>/<repo>/blob/<1 の sha>/.fastship/mock/123/<名前>.png?raw=true)>
<API / MCP: シーケンス図 (```mermaid)、定義の要点、入出力の例 (うまくいく場合・主な失敗)>
<インフラ: 構成図 (```mermaid) と、追加・変更・削除するリソースの一覧>

**直してほしいときは**: この PR に行コメントするか #123 にコメントし、#123 に `claude:analysis` を付け直してください。
````

見本の PR のブランチに push できない (403 など) ときは、`/dev:blocked` の「2. 止める」で人間に返してください。

## 5. 本文に書く
1. 3 で分けると決めたら、残りのまとまりごとに新しい Issue を起票してください (下の 2 つ目のコマンド)。`claude:analysis` を付けるので、それぞれの課題分析が始まります。
   - 既に分けた Issue (下の 1 つ目のコマンドで出る) は、起票し直さないでください。差し戻しや、前のセッションが途中で止まったときに重複させないためです。
   - 本文は `${CLAUDE_PLUGIN_ROOT}/skills/issue/backlog.md` に沿って `/tmp/split_issue.md` に書いてください (先頭の YAML frontmatter は含めない)。背景 には、この Issue の背景のうち、そのまとまりに当たるところを引用し、`#123 から分けました。` と書きます。課題 / 解決策 / 要件 は空のまま残します。参考資料 には `#123` を書きます。
   - この Issue のコードが無いと作れないなら、新しい Issue の Blocked by にこの Issue を登録してください (下の 3 つ目のコマンド)。

```bash
gh api --paginate "repos/{owner}/{repo}/issues/123/timeline?per_page=100" \
  --jq '.[] | select(.event == "cross-referenced" and (.source.issue.pull_request | not) and (.source.issue.body // "" | contains("#123 から分けました"))) | "#\(.source.issue.number) \(.source.issue.state) \(.source.issue.title)"'
jq -n --arg title "<タイトル>" --rawfile body /tmp/split_issue.md '{title:$title, body:$body, labels:["claude:analysis"]}' \
  | gh api --method POST "repos/{owner}/{repo}/issues" --input - --jq .number
gh api --method POST "repos/{owner}/{repo}/issues/<分けた Issue の番号>/dependencies/blocked_by" \
  -F issue_id="$(gh api "repos/{owner}/{repo}/issues/123" --jq .id)" > /dev/null
```

2. 本文を取得し直してください。分析の間に、開発者が本文を編集していることがあるためです。

```bash
gh api "repos/{owner}/{repo}/issues/123" --jq .body > /tmp/issue_body.md
```

3. `/tmp/issue_body.md` の 課題 / 解決策 / 要件 / 見本 の欄を書き換えてください。
   - 各欄の HTML コメントは残し、その下に書いてください。
   - 見本 の 1 行目には、`見本の PR: #<PR の番号> (<4 で控えた 40 桁の sha>)` を、この形のまま書いてください。リファインメント・実装・レビューは、この行 (`scripts/mock.sh`) で見本と承認した版を読みます。続けて、見本で見せたものを 1 行ずつ書きます (例: `- 画面: 一覧 (うまくいく場合・空・権限が無い)`)。作らなかったときは `- なし` とだけ書きます。
   - 背景 は開発者が書く欄なので、書き換えないでください。
   - 参考資料 には、分析で使った資料を追記してください。既にある行は消さないでください。
   - 本文が `${CLAUDE_PLUGIN_ROOT}/skills/issue/backlog.md` の欄に沿っていなければ (GitHub の UI から起票した場合など)、その欄に直し、元の本文を 背景 に移してください。先頭の YAML frontmatter は含めないでください。
   - `## 成功指標` の欄 (前の版で起票した Issue) があれば、`## 要件` の欄に置き換えてください。
   - `## 見本` の欄が無ければ (前の版で起票した Issue)、要件 と 参考資料 の間に足してください。
4. 本文を更新してください。

```bash
jq -n --rawfile body /tmp/issue_body.md '{body:$body}' \
  | gh api --method PATCH "repos/{owner}/{repo}/issues/123" --input - > /dev/null
```

## 6. 承認を依頼する
下の形式で `/tmp/analysis_done.md` を書き、次を 1 回の Bash で実行してください。コメントし、`claude:analysis` を外してから、判断待ちのラベルを合わせます。

 - `claude:analysis` を外しておくと、差し戻しのときに開発者が付け直せます。付いたままラベルを足すと、ルーティンがもう一度起動するため、合わせるのは外した後です。
 - `waiting.sh` は、この完了コメントが最後の承認 (`claude:refine` を付けた) より新しければ、`claude:analyzed` を付けます。`④ 承認待ち` の一覧に載ります。リファインメントが動いている間 (`claude:refine` が付いている) は付けず、リファインメントが終わるときに付けます。

```bash
jq -n --rawfile body /tmp/analysis_done.md '{body:$body}' \
  | gh api --method POST "repos/{owner}/{repo}/issues/123/comments" --input - > /dev/null
gh api --method DELETE "repos/{owner}/{repo}/issues/123/labels/claude:analysis" > /dev/null
bash "${CLAUDE_PLUGIN_ROOT}/scripts/waiting.sh" sync 123
```

```markdown
<!-- fastship:analysis -->
## 🤔 課題分析が終わりました

本文の 課題 / 解決策 / 要件 / 見本 を書きました。<見本を作ったときだけ「まず見本の PR (#<PR の番号>) を見てください。」>

<分けたときだけ「大きいため分けました: #<番号> <タイトル>」を 1 行ずつ書く。差し戻しで前回分けたものも書く。この Issue の後でないと作れないもの (Blocked by を付けたもの) は「(この Issue がマージされてから承認してください)」を付ける>

<差し戻しのときは、前回から変えたことを 1〜3 行で書く>

**確認してほしい点**
- <開発者に決めてほしい仮置き (非機能要件の数値・前提など)。3 つまで。差し戻しのときは、前回から変わったものだけ。無ければこの節を消す>

**承認するには**: `claude:refine` を付けてください。リファインメントが始まります。
**差し戻すには**: 直してほしい点をこの Issue か見本の PR (行コメント) にコメントし、`claude:analysis` を付け直してください。
```

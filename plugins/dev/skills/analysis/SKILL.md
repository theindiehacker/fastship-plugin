---
name: analysis
description: FastShip の ③ 課題分析。claude:analysis が付いた Issue の課題の解像度と解決策の質を上げ、確かめられる機能要件・非機能要件を決めて、Issue の 課題 / 解決策 / 要件 に書く。大きければ Feature Issue に分ける。終わったら開発者に承認 (claude:refine) を依頼し、claude:analyzed (承認待ち) を付ける。差し戻し (コメント + claude:analysis の付け直し) では、コメントを反映して分析し直す。ルーティンから使う。使い方: /dev:analysis {Issue の番号}
argument-hint: "{Issue の番号}"
---

# 🤔 課題分析

`claude:analysis` が付いた Issue を分析し、本文の 課題 / 解決策 / 要件 を書いてください。開発者はこの 3 つの欄を読んで、④ 承認するかを決めます。

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

## 3. 分析する
開発者が ④ で数分で判断できるよう、課題・解決策・要件はそれぞれ 10 行程度に収めてください。収まらないほど大きければ、Issue を分けてください (下の「分けるか決める」)。

### 課題
 - 背景 から、誰が・どの場面で・何に困っているかを特定してください。要望 (〇〇 がほしい) は解決策の案として扱い、課題と分けてください。
 - なぜ困るのかを掘り下げ、根本原因を書いてください。
 - 今回解く範囲を決めてください。範囲外にしたことは、開発者が範囲内だと思いそうなものだけ 1 行ずつ書いてください。

### 解決策
 - 背景 の案を含め、2〜3 案を比べてください。
 - 課題を解ける最も小さい案を選び、選んだ理由 (効果・コスト・リスク) を書いてください。見送った案は、理由と合わせて 1 行ずつ書いてください。
 - 何が変わるか (利用者から見た振る舞い) は、解決策ではなく 要件 に書いてください。

### 要件
作ったものが満たすことを書いてください。⑥ リファインメントが Sub Issue の完了条件に振り分け、⑨ レビューが確かめます。作り終えたときに確かめられることだけを書きます。

 - 機能要件: 利用者から見た振る舞いを、1 行に 1 つ書いてください。うまくいく場合と、主な失敗の場合 (権限が無い・入力が正しくないなど) を含めます。例: `- 未ログインで API を呼ぶと 401 で断る`
 - 非機能要件: セキュリティ・性能・可用性・運用 (ログ・監視) などのうち、この Issue で守るものだけを書いてください。数値にできるものは数値にします。例: `- 一覧の API は 1,000 件を 500 ms 以内に返す`。当てはまるものが無ければ `- なし` と書きます。
 - どう作るか (変数名・プロセスの構成・設定の方法など) は書かないでください。⑥ と ⑧ で決めます。
 - 「使いやすい」「安全である」のような、確かめられない書き方はしないでください。

### 分けるか決める
次のどちらかに当たれば、この Issue を分け、残りを新しい Issue (Feature Issue) にしてください。Issue が大きいと、④ 承認と、最後に開発者が見る epic の PR (`/dev:refine`) を読み切れなくなるためです。

 - 機能要件に、片方だけ作っても利用者の役に立つまとまりが 2 つ以上ある
 - Sub Issue が 4 つ以上 (テストを含めて差分が 2,000 行ほど) になりそう

ただし、Sub Issue が既にある (リファインメント済み) とき、そろわないと役に立たないときは分けないでください。

分けるときは、この Issue を最初に作るまとまりに絞り、課題 (今回の範囲) / 解決策 / 要件 を書いてください。分けた先は、課題 の範囲外に 1 行ずつ書きます (4 で番号を書く)。背景 は変えないでください。残りのまとまりは、4 で新しい Issue として起票します。

### 判断できないとき
次のように Claude だけで判断できないときは、推測で書かず、`/dev:blocked` の「2. 止める」で人間に返してください。

 - 背景 から、誰の何の課題かが読み取れない
 - 案を選ぶ基準 (優先したいこと・予算・期限など) が Issue やリポジトリから分からず、どの案を選ぶかで結果が大きく変わる

非機能要件の数値など、仮に置けば分析を進められるものは止めずに仮置きし、5 の「確認してほしい点」に書いてください。開発者が ④ で確認します。

## 4. 本文に書く
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

3. `/tmp/issue_body.md` の 課題 / 解決策 / 要件 の欄を書き換えてください。
   - 各欄の HTML コメントは残し、その下に書いてください。
   - 背景 は開発者が書く欄なので、書き換えないでください。
   - 参考資料 には、分析で使った資料を追記してください。既にある行は消さないでください。
   - 本文が `${CLAUDE_PLUGIN_ROOT}/skills/issue/backlog.md` の欄に沿っていなければ (GitHub の UI から起票した場合など)、その欄に直し、元の本文を 背景 に移してください。先頭の YAML frontmatter は含めないでください。
   - `## 成功指標` の欄 (前の版で起票した Issue) があれば、`## 要件` の欄に置き換えてください。
4. 本文を更新してください。

```bash
jq -n --rawfile body /tmp/issue_body.md '{body:$body}' \
  | gh api --method PATCH "repos/{owner}/{repo}/issues/123" --input - > /dev/null
```

## 5. 承認を依頼する
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

本文の 課題 / 解決策 / 要件 を書きました。

<分けたときだけ「大きいため分けました: #<番号> <タイトル>」を 1 行ずつ書く。差し戻しで前回分けたものも書く。この Issue の後でないと作れないもの (Blocked by を付けたもの) は「(この Issue がマージされてから承認してください)」を付ける>

<差し戻しのときは、前回から変えたことを 1〜3 行で書く>

**確認してほしい点**
- <開発者に決めてほしい仮置き (非機能要件の数値・前提など)。3 つまで。差し戻しのときは、前回から変わったものだけ。無ければこの節を消す>

**承認するには**: `claude:refine` を付けてください。リファインメントが始まります。
**差し戻すには**: 直してほしい点をコメントし、`claude:analysis` を付け直してください。
```

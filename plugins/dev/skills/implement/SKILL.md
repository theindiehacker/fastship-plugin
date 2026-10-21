---
name: implement
description: FastShip の ⑦⑧ 実装。claude:implement が付いた Sub Issue を、ドメイン駆動設計とテスト駆動開発で実装する。Sub Issue に紐付けた (Closes #N) テスト付きの PR を作り、claude:under-review でレビューに回す。レビューの 🛑 と CI の失敗に対応する。判断できないときは claude:blocked で人間に返す。PR で止めた後の再開 (PR に claude:implement) にも使う。実装ルーティンから使う。使い方: /dev:implement {Sub Issue または PR の番号}
argument-hint: "{Sub Issue または PR の番号}"
---

# 🧑‍💻 実装

`claude:implement` が付いた Sub Issue を実装し、PR を作ってレビューに回してください。レビューで 🛑 が付いたら、このセッションが対応します。

GitHub は `gh api` (REST) で操作します。コマンドの `123` はトリガーになった Issue / PR の番号、`<Sub Issue>` は Sub Issue の番号、`<PR>` は PR の番号に置き換えてください。

## 1. 始める
1. `/dev:blocked` の「1. 始める」を、進行中ラベル `claude:implement` で行ってください。`STOP` と出たら、何もせずに終えてください。
2. トリガーが Issue か PR かを確かめてください。

```bash
gh api "repos/{owner}/{repo}/issues/123" --jq 'if .pull_request then "PR" else "Issue" end'
```

 - `Issue` なら、123 が Sub Issue です。Sub Issue に open な PR が既にあれば、その PR で続けてください (下の 2 つ目のコマンド)。
 - `PR` なら、PR で止めた後の再開です。本文の `Closes #N` の N が Sub Issue です。

```bash
gh api "repos/{owner}/{repo}/pulls/123" --jq '.head.ref, .body'
gh api "repos/{owner}/{repo}/pulls?state=open&per_page=100" \
  --jq '.[] | select((.body // "") | split("\n") | map(rtrimstr("\r")) | index("Closes #<Sub Issue>")) | .number'
```

PR で続けるときは、PR のブランチを checkout し、`subscribe_pr_activity` で PR を購読してください。レビューと CI の結果で、このセッションが起こされるようになります。PR が無いときは、「前回の質問」に作業ブランチがあればそれを checkout してください。無ければ、セッションの作業ブランチ (指定が無ければベースブランチの最新から作る) で作業してください。

## 2. 読む
Sub Issue と親 Issue を読んでください。

```bash
gh api "repos/{owner}/{repo}/issues/<Sub Issue>" --jq '.title, .body, (.parent_issue_url // "" | split("/") | last)'
gh api --paginate "repos/{owner}/{repo}/issues/<Sub Issue>/comments" --jq '.[] | "### \(.user.login) (\(.created_at))\n\(.body)\n"'
gh api "repos/{owner}/{repo}/issues/<親 Issue>" --jq '.title, .body'
```

 - Sub Issue の やること / やらないこと / 完了条件 が、実装する範囲です。
 - 親 Issue の 課題 / 解決策 は、なぜ作るのかと、どんな言葉で呼ぶのかを知るために読んでください。
 - リポジトリの規約 (`CLAUDE.md` など) と、近いコードとそのテストを読み、次を確かめてください: 層の分け方、名前の付け方、テストの書き方、テストと lint の実行方法。

## 3. 設計する (ドメイン駆動設計)
 - Issue の言葉を、そのままクラス・関数・テストの名前に使ってください。同じものに別の名前を付けないでください。リポジトリに用語集があれば、それに従ってください。
 - 業務のルール (計算・状態の変化・制約) は、ドメインのコード (エンティティ・値オブジェクト・ドメインサービスなど) に置いてください。画面・API・DB の処理には書かないでください。
 - 層の分け方はリポジトリの今の作りに合わせ、無い層やフレームワークを足さないでください。
 - やること に無いもの、やらないこと にあるものは作らないでください。

## 4. 実装する (テスト駆動開発)
完了条件を 1 つずつ、次の順で実装してください。テストをまとめて書いてから実装しないでください。

1. 完了条件を確かめるテストを書いて実行し、意図した理由で失敗することを確かめる
2. テストが通る最小のコードを書く
3. テストが通ったまま、重複や名前を整える
4. コミットする

 - テストは公開された振る舞い (関数・API・画面) を通して書き、内部の作りに依存させないでください。
 - 期待値は完了条件から決めてください。実装と同じ計算で期待値を作らないでください。
 - 自動テストで確かめられない完了条件 (見た目・外部サービスなど) は、確かめた方法と結果を PR の ✔️ 動作確認 に書いてください。
 - 最後に、リポジトリにあるテスト・lint・型チェックをすべて通してください。

## 5. PR を作る
1. `/dev:push-pr` で PR を作ってください。
   - 💡 概要 に `Closes #<Sub Issue>` を 1 行で書いてください。マージすると Sub Issue が閉じ、後続の Sub Issue の実装が始まります。
   - Draft ではなく、Ready for review で作ってください。
2. Sub Issue に紐付いたことを確かめてから (出なければ本文を直す)、`claude:under-review` を付けてください。⑨ レビューが始まります。

```bash
gh api "repos/{owner}/{repo}/pulls/<PR>" --jq .body | tr -d '\r' | grep -xF "Closes #<Sub Issue>"
gh api --method POST "repos/{owner}/{repo}/issues/<PR>/labels" -f "labels[]=claude:under-review" > /dev/null
```

3. `subscribe_pr_activity` で PR を購読してください。レビューと CI の結果で、このセッションが起こされるようになります (既に購読していても問題ありません)。

Sub Issue の `claude:implement` は外さないでください。リファインメントは、このラベルが付いた Sub Issue が閉じたときに後続に着手します。

## 6. 🛑 に対応する
PR を作った後は、レビューと CI の結果でこのセッションが起こされます。

 - `claude:blocked` が付いている、またはこのセッションが `/dev:blocked` の「2. 止める」を行った後なら、何もしないでください。再開は新しいセッションが行います。
 - CI が失敗したら、原因を直して push してください。
 - 🛑 (Request changes、または 🛑 を含むレビュー・コメント) が付いたら、指摘をすべて読み、1 つずつ採否を決めてください。
   - 採用するなら直して push してください。バグの指摘は、再現するテストを先に書いてから直してください (4 と同じ)。
   - 採用しないなら、理由を返信してください。
   - どの指摘にも、何をしたかを返信してください。
 - 直したら、`claude:under-review` を付け直してください。再レビューが始まります。付いたままだとイベントが起きないので、外してから付けます。

```bash
gh api --method DELETE "repos/{owner}/{repo}/issues/<PR>/labels/claude:under-review" > /dev/null 2>&1 || true
gh api --method POST "repos/{owner}/{repo}/issues/<PR>/labels" -f "labels[]=claude:under-review" > /dev/null
```

 - ✅ なら何もしないでください。マージは開発者が行います。

## 判断できないとき
次のように Claude だけで判断できないときは、推測で作らず、`/dev:blocked` の「2. 止める」で人間に返してください。PR を作った後は PR の番号で実行して末尾に Sub Issue の番号を足し、`unsubscribe_pr_activity` で PR の購読を外してください。

 - 完了条件 があいまいで、どう作るかで振る舞いが大きく変わる
 - Sub Issue がリポジトリの今の作りと合わない。または 依存 のコードが無くて作れない
 - テストの仕組みが無く、何を入れるかで結果が大きく変わる
 - レビューの指摘が Sub Issue・親 Issue と食い違い、どちらに従うか決められない

名前や小さな設計の選択など、決めれば進められるものは止めずに決め、理由を PR の Diff コメントに書いてください。

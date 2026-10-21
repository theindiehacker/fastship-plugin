---
name: implement
description: FastShip の ⑦⑧ 実装。claude:implement が付いた Sub Issue を、ドメイン駆動設計とテスト駆動開発で実装する。Sub Issue に紐付けた (Closes #N) テスト付きの PR を作り、claude:under-review でレビューに回す。レビューの指摘 (🛑 など) と CI の失敗に対応する。判断できないときは claude:blocked で人間に返す。PR で止めた後の再開 (PR に claude:implement) にも使う。実装ルーティンから使う。使い方: /dev:implement {Sub Issue または PR の番号}
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

 - `PR` なら、PR で止めた後の再開です。本文の `Closes #N` の N が Sub Issue です (下の 1 つ目のコマンド)。PR のブランチを checkout し、`subscribe_pr_activity` で PR を購読してください。2 を読んだら、5 は行わず (PR を作り直さない)、6 から続けてください。
 - `Issue` なら、123 が Sub Issue です。Sub Issue に紐付いた open な PR があるか確かめてください (下の 2 つ目のコマンド)。
   - あれば、PR に `claude:implement` を付けて (付いていれば外してから) 終えてください。PR で起動したセッションが、PR の質問と回答を読んで続けます。
   - 無ければ、「前回の質問」に作業ブランチがあればそれを checkout してください。無ければ、セッションの作業ブランチ (指定が無ければベースブランチの最新から作る) で作業してください。

```bash
gh api "repos/{owner}/{repo}/pulls/123" --jq '.head.ref, .body'
gh api "repos/{owner}/{repo}/issues/<Sub Issue>/timeline?per_page=100" \
  --jq '.[] | select(.event == "cross-referenced" and .source.issue.pull_request and .source.issue.state == "open")
        | select(.source.issue.body // "" | split("\n") | map(rtrimstr("\r")) | index("Closes #<Sub Issue>"))
        | .source.issue.number'
```

## 2. 読む
Sub Issue と親 Issue を読んでください。1 つ目のコマンドの最後の行が親 Issue の番号です。空なら親は無いので、3 つ目は飛ばしてください。

```bash
gh api "repos/{owner}/{repo}/issues/<Sub Issue>" --jq '.title, .body, (.parent_issue_url // "" | split("/") | last)'
gh api "repos/{owner}/{repo}/issues/<Sub Issue>/comments?per_page=100" --jq '.[] | "### \(.user.login) (\(.created_at))\n\(.body)\n"'
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
   - ベースは、リポジトリのデフォルトブランチにしてください。`Closes #N` は、デフォルトブランチへのマージでしか Issue を閉じません。
   - 💡 概要 に `Closes #<Sub Issue>` を 1 行で書いてください。マージすると Sub Issue が閉じ、後続の Sub Issue の実装が始まります。
   - Draft ではなく、Ready for review で作ってください。
   - push-pr のステップ 11 は行わないでください。CI へのレビューの依頼 (`/code-review` / `/security-review` のコメント) もしません。レビューは ⑨ が行い (4)、CI とレビューへの対応は 6 で行います。
2. `subscribe_pr_activity` で PR を購読してください。レビューと CI の結果で、このセッションが起こされるようになります (既に購読していても問題ありません)。
3. Sub Issue に紐付いたことを確かめてください。2 行とも出なければ、本文やベースを直してください。

```bash
gh api "repos/{owner}/{repo}/pulls/<PR>" --jq .body | tr -d '\r' | grep -xF "Closes #<Sub Issue>"
[ "$(gh api "repos/{owner}/{repo}/pulls/<PR>" --jq .base.ref)" = "$(gh api "repos/{owner}/{repo}" --jq .default_branch)" ] && echo "ベースはデフォルトブランチ"
```

4. `claude:under-review` を付けてください。⑨ レビューが始まります。付いたままだとイベントが起きないので、外してから付けます。

```bash
gh api --method DELETE "repos/{owner}/{repo}/issues/<PR>/labels/claude:under-review" > /dev/null 2>&1 || true
gh api --method POST "repos/{owner}/{repo}/issues/<PR>/labels" -f "labels[]=claude:under-review" > /dev/null
```

Sub Issue の `claude:implement` は外さないでください。リファインメントは、このラベルが付いた Sub Issue が閉じたときに後続に着手します。

## 6. レビューと CI に対応する
PR を作った後は、レビュー・コメント・CI の結果でこのセッションが起こされます。

 - 次のときは何もしないでください。
   - `claude:blocked` が付いている、またはこのセッションが `/dev:blocked` の「2. 止める」を行った後 (再開は新しいセッションが行います)
   - 起こされたコメントが、⑨ のレビュー以外の FastShip のコメント (本文が `<!-- fastship:` で始まり、`<!-- fastship:review -->` ではない) である。このセッションの返信や、⑨ の着手・質問のコメントです
 - CI が失敗したら、原因を直して push してください。
 - レビューの指摘 (⑨ のレビュー、bot のレビュー、開発者のコメント) が付いたら、すべて読み、1 つずつ採否を決めてください。⑨ のレビューは本文と行コメントが `<!-- fastship:review -->` で始まり、`[must]` が 🛑 の理由です。`[imo]` / `[nits]` / `[ask]` はマージを止めません。
   - 採用するなら直して push してください。バグの指摘は、再現するテストを先に書いてから直してください (4 と同じ)。
   - PR は作り直さないでください。やったことが変わったときだけ、`/dev:push-pr` の 7-b の手順で本文を部分更新してください。
   - どの指摘にも、何をしたか (採用しないなら理由) を返信してください。返信の先頭には `<!-- fastship:reply -->` と改行を付けてください。
 - push したら、すぐに `claude:approved` を外し (下のコマンド)、`claude:under-review` を付け直して ⑨ に再レビューを頼んでください (5 の 4 と同じ)。⑨ は PR 全体を見直し、✅ / 🛑 を付け直します。

```bash
gh api --method DELETE "repos/{owner}/{repo}/issues/<PR>/labels/claude:approved" > /dev/null 2>&1 || true
```

 - ✅ (`claude:approved` が付いた) のレビューの `[imo]` / `[nits]` / `[ask]` は、返信だけにしてください。それだけのために push すると、再レビューで ✅ が外れるためです。ほかに対応の要る指摘が無ければ何もしないでください。マージは開発者が行います。

## 判断できないとき
次のように Claude だけで判断できないときは、推測で作らず、`/dev:blocked` の「2. 止める」で人間に返してください。PR を作った後は PR の番号で実行し、`unsubscribe_pr_activity` で PR の購読を外してください。Sub Issue の `claude:implement` は残ります (5 を参照)。

 - 完了条件 があいまいで、どう作るかで振る舞いが大きく変わる
 - Sub Issue がリポジトリの今の作りと合わない。または 依存 のコードが無くて作れない
 - テストの仕組みが無く、何を入れるかで結果が大きく変わる
 - Sub Issue を決められない (PR に `Closes #N` が無い)
 - 前のセッションのブランチに push できない (403 など)
 - CI が、変更と関係のない理由 (シークレット・外部サービスなど) で失敗する。または同じ失敗を 2 回直しても通らない
 - 再レビューを 3 回頼んでも 🛑 が続く。またはレビューの指摘が Sub Issue・親 Issue と食い違い、どちらに従うか決められない

名前や小さな設計の選択など、決めれば進められるものは止めずに決め、理由を PR の Diff コメントに書いてください。

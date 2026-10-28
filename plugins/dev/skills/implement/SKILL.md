---
name: implement
description: FastShip の ⑦⑧ 実装。claude:implement が付いた Sub Issue (1 PR で済む Issue はその Issue) を、ドメイン駆動設計とテスト駆動開発で実装する。見本 (③ の Draft PR) があれば、見本どおりに作る。Sub Issue に紐付けた (Closes #N) テスト付きの PR を Draft で作り、Ready にして Actions の Claude レビューに回す。PR は親 Issue の epic ブランチ (無ければデフォルトブランチ) に向け、epic ブランチに向けた PR はコードレビューの Approve と CI の成功でマージして Sub Issue を閉じる。PR は実装・修正の間だけ Draft にする。レビューの指摘 (Request changes など) と CI の失敗に対応する。判断できないときは claude:blocked で人間に返す。PR で止めた後の再開 (PR に claude:implement) にも使う。ルーティンから使う。使い方: /dev:implement {Sub Issue または PR の番号}
argument-hint: "{Sub Issue または PR の番号}"
---

# 🧑‍💻 実装

`claude:implement` が付いた Sub Issue を実装し、PR を作ってレビューに回してください。レビューは、PR を Ready にすると Actions の Claude レビュー (コードレビュー・セキュリティレビュー) が行い、claude[bot] が投稿します。指摘が付いたら、このセッションが対応します。epic ブランチに向けた PR は、コードレビューが Approve して CI が通ったら、このセッションがマージします (7)。

1 PR で済む Issue は、リファインメントが Sub Issue を作らず、Issue そのものに `claude:implement` を付けます。そのときは、この Issue を Sub Issue と読み替えてください (`Closes #<Issue>` で紐付けます)。

GitHub は `gh api` (REST) で操作します。コマンドの `123` はトリガーになった Issue / PR の番号、`<Sub Issue>` は Sub Issue の番号、`<PR>` は PR の番号に置き換えてください。

PR は、実装・修正の間だけ Draft にします。レビューを頼むとき (5 の 4・6) は Ready にします。Draft から Ready にするたびに、Claude のレビューが PR 全体を見直します。人間に返すとき (判断できないとき) も Ready にします。Draft の PR にラベルを付けても、ルーティンは起動しないためです。`claude:blocked` が付いていれば、Ready にしてもレビューは動きません。

Draft / Ready の切り替えは REST に無く、`gh pr ready` (GraphQL) は claude.ai/code で 403 になるため、CCR のルートを使います。CCR のルートが 404 のとき (ローカルの CLI) は、`gh pr ready` に切り替えます (`/dev:push-pr` の 8-b と同じ)。

```bash
# Draft にする
[ "$(gh api "repos/{owner}/{repo}/pulls/<PR>" --jq .draft)" = "true" ] \
  || gh api --method POST "repos/{owner}/{repo}/pulls/<PR>/ccr/convert_to_draft" > /dev/null 2>&1 \
  || gh pr ready --undo <PR>
# Ready にする
[ "$(gh api "repos/{owner}/{repo}/pulls/<PR>" --jq .draft)" = "false" ] \
  || gh api --method POST "repos/{owner}/{repo}/pulls/<PR>/ccr/ready_for_review" > /dev/null 2>&1 \
  || gh pr ready <PR>
```

## 1. 始める
1. `/dev:blocked` の「1. 始める」を、進行中ラベル `claude:implement` で行ってください。`STOP` と出たら、何もせずに終えてください。
2. トリガーが Issue か PR かを確かめてください。

```bash
gh api "repos/{owner}/{repo}/issues/123" --jq 'if .pull_request then "PR" else "Issue" end'
```

 - `PR` なら、PR で止めた後の再開です。本文の `Closes #N` の N が Sub Issue です (下の 1 つ目のコマンド)。PR を Draft にし (冒頭の「Draft にする」)、PR のブランチを checkout して、`subscribe_pr_activity` で PR を購読してください。2 を読んだら、5 は行わず (PR を作り直さない)、6 から続けてください。
   - 直すものが無くても、終える前に 6 の push の後と同じく、Ready にしてください (再レビューが動きます)。Draft のまま終えると、だれの番でもなくなるためです。
 - `Issue` なら、123 が Sub Issue です。Sub Issue に紐付いた open な PR があるか確かめてください (下の 2 つ目のコマンド)。
   - あれば、PR を Ready にしてから (冒頭の「Ready にする」)、PR に `claude:implement` を付けて (付いていれば外してから) 終えてください。PR で起動したセッションが、PR の質問と回答を読んで続けます。PR が Draft のままだと、ラベルを付けても起動しません。
   - 無ければ、PR のベースを下の 3 つ目のコマンドで決めてください。ベースは、親 Issue の epic ブランチ (`epic/<親 Issue>`) があればそれ、無ければデフォルトブランチです。5 で使います。
     - 「前回の質問」に作業ブランチがあれば、それを checkout してください。
     - 無ければ、セッションの作業ブランチ (指定が無ければ `claude/<Sub Issue>` など) を、ベースの最新から作ってください (4 つ目)。

```bash
gh api "repos/{owner}/{repo}/pulls/123" --jq '.head.ref, .body'
gh api "repos/{owner}/{repo}/issues/<Sub Issue>/timeline?per_page=100" \
  --jq '.[] | select(.event == "cross-referenced" and .source.issue.pull_request and .source.issue.state == "open")
        | select(.source.issue.body // "" | split("\n") | map(rtrimstr("\r")) | index("Closes #<Sub Issue>"))
        | .source.issue.number'
bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic.sh" base <Sub Issue>
git fetch origin "<ベース>" && git checkout -B "<作業ブランチ>" "origin/<ベース>"
```

## 2. 読む
Sub Issue と親 Issue を読んでください。1 つ目のコマンドの最後の行が親 Issue の番号です。空なら親は無いので、3 つ目は飛ばしてください。

```bash
gh api "repos/{owner}/{repo}/issues/<Sub Issue>" --jq '.title, .body, (.parent_issue_url // "" | split("/") | last)'
gh api "repos/{owner}/{repo}/issues/<Sub Issue>/comments?per_page=100" --jq '.[] | "### \(.user.login) (\(.created_at))\n\(.body)\n"'
gh api "repos/{owner}/{repo}/issues/<親 Issue>" --jq '.title, .body'
gh api --paginate "repos/{owner}/{repo}/issues/<Sub Issue>/dependencies/blocked_by" --jq '.[] | "#\(.number) \(.state) \(.title)"'
```

 - Sub Issue の やること / やらないこと / 完了条件 が、実装する範囲です。Issue をそのまま実装するときは、解決策 / 要件 と、リファインメントが書き足した やらないこと / 完了条件 が範囲です。
 - 4 つ目のコマンドで出る Issue (Blocked by) は、この Sub Issue の依存です。先に終わった作業なので、そのコードを使ってください。
 - 親 Issue の 課題 / 解決策 / 要件 は、なぜ作るのかと、どんな言葉で呼ぶのかを知るために読んでください。
 - 見本があれば、見本どおりに作ってください。親 Issue (無ければ Sub Issue) で下の 1 つ目のコマンドを実行すると、`<見本の PR> <sha>` が出て、見本を fetch します。見本の PR の本文 (2 つ目) と、sha の版で見本が変えたファイル (3 つ目・4 つ目) を読んでください。何も出なければ、見本はありません。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/mock.sh" fetch <親 Issue>
gh api "repos/{owner}/{repo}/pulls/<見本の PR>" --jq .body
git diff --name-status "$(git merge-base HEAD <sha>)" <sha>
git show "<sha>:<パス>"
```
 - リポジトリの規約 (`CLAUDE.md` など) と、近いコードとそのテストを読み、次を確かめてください: 層の分け方、名前の付け方、テストの書き方。
 - リポジトリの検査 (テスト・lint・整形・型チェック) のコマンドを洗い出してください。`CLAUDE.md`・CI のワークフロー (`.github/workflows/`)・`package.json` の `scripts`・`Makefile` などに書いてあります。CI が PR で実行するコマンドが基準です。

## 3. 設計する (ドメイン駆動設計)
 - 書く前に、書かずに済む方法を探してください。既存のコード・標準ライブラリ・リポジトリが使っているライブラリの機能で済むなら、それを使います。
 - 完了条件を満たす、いちばん短い差分にしてください。新しい抽象 (インターフェース・基底クラス・汎用化・設定項目) は、今の完了条件が 2 か所以上で求めるときだけ作ってください。将来のための拡張・使われない引数は作らないでください。
 - Issue の言葉を、そのままクラス・関数・テストの名前に使ってください。同じものに別の名前を付けないでください。リポジトリに用語集があれば、それに従ってください。
 - 業務のルール (計算・状態の変化・制約) は、ドメインのコード (エンティティ・値オブジェクト・ドメインサービスなど) に置いてください。画面・API・DB の処理には書かないでください。
 - 層の分け方はリポジトリの今の作りに合わせ、無い層やフレームワークを足さないでください。
 - React の Web アプリの画面の UI コンポーネントは、shadcn/ui を使ってください。自作したり、別の UI ライブラリを足したりしないでください。探し方・追加の仕方は `/stack:ui` に従ってください。
   - `components.json` が無い (shadcn/ui を入れていない) パッケージでは、入れずに、今の作り (別の UI ライブラリなど) に合わせてください。init はテーマと基本のスタイルを書き換え、既にある画面の見た目を変えるため、入れるかは人間が決めます (`/stack:setup`)。
   - この Issue で新しく作る Web アプリにだけ、聞かずに入れます (既にある画面が無く、見た目は変わらないため。上の「フレームワークを足さない」の例外)。入れ方は `/stack:setup` の手順のうち、「3. JavaScript / TypeScript」の 2 の init の行と 3 (Biome)、「7. 確かめる」の knip の設定に従ってください。
 - やること に無いもの、やらないこと にあるものは作らないでください。見本のうち、完了条件に入っていないものも作りません (別の Sub Issue の分です)。
 - 見本は ④ で承認された仕様です。見本と違う画面・定義・構成にしないでください。見本どおりに作れなければ、「判断できないとき」です。
 - 見本のコード (モック画面・定義・スタブ) は、`git checkout <sha> -- <パス>` で持ってきて、出発点にしてかまいません。固定のデータとスタブは、本物の処理に置き換えて残さないでください。スクリーンショット (`.fastship/`) は持ってこないでください。

## 4. 実装する (テスト駆動開発)
完了条件を 1 つずつ、次の順で実装してください。テストをまとめて書いてから実装しないでください。

1. 完了条件を確かめるテストを書いて実行し、意図した理由で失敗することを確かめる
2. テストが通る最小のコードを書く
3. テストが通ったまま、重複や名前を整える
4. コミットする

 - PR を作るまで push しないでください。required workflow などの CI は push のたびに全部動き、1 回に数十分かかることがあります。
 - テストは公開された振る舞い (関数・API・画面) を通して書き、内部の作りに依存させないでください。
 - 期待値は完了条件から決めてください。実装と同じ計算で期待値を作らないでください。見本の入出力の例 (API / MCP) は、そのまま期待値にします。
 - 見本の画面は、実装した画面を見本と同じ場面 (同じデータ・状態) で起動してスクリーンショットを撮り、見本のスクリーンショット (`git show "<sha>:<パス>" > /tmp/mock.png` で取り出す) と Read で見比べてください。構成・文言・状態が違えば直します。見比べた結果を、PR の ✔️ 動作確認 に書いてください。起動できなければ、コードで見比べ、そのことを書きます。
 - 自動テストで確かめられない完了条件 (見た目・外部サービスなど) は、確かめた方法と結果を PR の ✔️ 動作確認 に書いてください。
 - PR を作る前に差分を読み返し、消しても完了条件を満たすコードを消してください。
 - PR を作る前に、2 で洗い出した検査をすべて実行して通してください。hook (stack プラグインなど) が入っていても、それに頼らず実行してください。hook が無いリポジトリもあり、あっても変えたファイルしか確かめません。
   - 道具が無ければ、リポジトリの手順 (`CLAUDE.md`・README・CI の準備のステップ) で入れてください。入れられない検査は飛ばし、PR の ✔️ 動作確認 に、実行できなかった検査と理由を書いてください。CI で確かめます。

## 5. PR を作る
1. `/dev:push-pr` で PR を作ってください。
   - ベースは、1 で決めたベースにしてください。push-pr の 1-a の `CALLER_BASE` に入れます。
   - 💡 概要 に `Closes #<Sub Issue>` を 1 行で書いてください。ほかのスキルは、この行で Sub Issue を見分けます。デフォルトブランチに向けた PR は、マージすると `Closes` で Sub Issue が閉じます。epic ブランチに向けた PR は `Closes` では閉じないため、7 でマージするときに閉じます。閉じると、後続の Sub Issue の実装が始まります。
   - Draft で作ってください (push-pr の 6 で `draft` を `true` にする)。push-pr の 8 で Ready にしないでください。Ready にするのは、レビューを頼む 4 です。
   - push-pr のステップ 11 は行わないでください。CI へのレビューの依頼 (`/code-review` / `/security-review` のコメント) もしません。レビューは 4 で Ready にしたときに動き、CI とレビューへの対応は 6 で行います。
2. `subscribe_pr_activity` で PR を購読してください。レビューと CI の結果で、このセッションが起こされるようになります (既に購読していても問題ありません)。
3. Sub Issue に紐付いたことを確かめてください。2 行とも出なければ、本文やベースを直してください。

```bash
gh api "repos/{owner}/{repo}/pulls/<PR>" --jq .body | tr -d '\r' | grep -xF "Closes #<Sub Issue>"
[ "$(gh api "repos/{owner}/{repo}/pulls/<PR>" --jq .base.ref)" = "$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic.sh" base <Sub Issue>)" ] && echo "ベースは正しい"
```

4. PR を Ready にしてください (冒頭の「Ready にする」)。Claude のコードレビューとセキュリティレビューが始まり、PR の Checks に出ます。

Sub Issue の `claude:implement` は外さないでください。リファインメントは、このラベルが付いた Sub Issue が閉じたときに後続に着手します。

## 6. レビューと CI に対応する
PR を作った後は、レビュー・コメント・CI の結果でこのセッションが起こされます。

 - PR が閉じていたら (マージを含む)、7 のコマンドを実行してから、`unsubscribe_pr_activity` で購読を外して終えてください。開発者が epic ブランチに手でマージしたときも、Sub Issue を閉じるためです。
 - 次のときは何もしないでください。
   - `claude:blocked` が付いている、またはこのセッションが `/dev:blocked` の「2. 止める」を行った後 (再開は新しいセッションが行います)
   - 起こされたコメントが、FastShip のコメント (本文が `<!-- fastship:` で始まる) である。このセッションの返信や、着手・質問のコメントです
 - CI とレビューの指摘への修正は、まとめて 1 回で push してください。CI は push のたびに全部動くため、分けて push すると、その回数だけ Actions の時間を使います。
   - head の CI に終わっていないもの (下のコマンドで名前が出る) があれば、まだ直さずに終えてください。Claude のレビュー (`コードレビュー`・`セキュリティレビュー`) も CI に出ます。揃ったときに、また起こされます。直してから待つと、push する前にコンテナが片付けられ、コミットが消えることがあります。
   - 揃ったら、CI の失敗とレビューの指摘をすべて直し、4 の検査を通してから 1 回だけ push してください。

```bash
sha=$(gh api "repos/{owner}/{repo}/pulls/<PR>" --jq .head.sha)
gh api --paginate "repos/{owner}/{repo}/commits/$sha/check-runs?per_page=100" --jq '.check_runs[] | select(.status != "completed") | .name'
```

 - CI が失敗したら、原因を直し、同じ検査が手元で通ることを確かめてください。
   - Claude のレビュー (`コードレビュー`・`セキュリティレビュー`) の失敗は、コードではなくレビューが途中で止まったものです。コードは直さず、PR を Draft にしてから Ready にして、1 回だけ頼み直してください。また失敗したら、「判断できないとき」として止めてください。
 - レビューの指摘 (Claude のレビュー、ほかの bot のレビュー、開発者のコメント) が付いたら、すべて読み、1 つずつ採否を決めてください。
   - Claude のレビューは claude[bot] が投稿します。コードレビューは、行コメントと、判定のレビュー (本文が `🧠 Claude コードレビュー` で始まる Request changes / Approve) です。Request changes なら、本文の理由と、直す必要があるとした行コメントを直してください。セキュリティレビューは行コメントだけで、Approve でも、直すか直さない理由を返信してください。
   - 直し始める前に、PR を Draft にしてください (冒頭の「Draft にする」)。CI の失敗を直すときも同じです。修正中だと分かるようにし、push の後に Ready にしたときに再レビューが動くようにするためです。Approve の後の小さな修正 (下) だけは、Ready のまま直します。
   - 採用するなら直し、4 の検査を通してください。バグの指摘は、再現するテストを先に書いてから直してください (4 と同じ)。
   - PR は作り直さないでください。やったことが変わったときだけ、`/dev:push-pr` の 7-b の手順で本文を部分更新してください。
   - どの指摘にも、何をしたか (採用しないなら理由) を返信してください。返信の先頭には `<!-- fastship:reply -->` と改行を付けてください。
 - push する前に、PR がベースとコンフリクトしていないか確かめてください (`gh api "repos/{owner}/{repo}/pulls/<PR>" --jq .mergeable` が `false` ならコンフリクト)。コンフリクトしていれば、7 の `CONFLICT` と同じく取り込んで解消してから push します。コンフリクトしている PR では、Claude のレビュー (Actions) が動かないためです。
 - push したら (Request changes の指摘に返信だけで対応したときも)、すぐに PR を Ready にしてください (冒頭の「Ready にする」)。Claude のレビューが PR 全体を見直し、Approve / Request changes を付け直します。
   - Approve の後の、下の小さな修正だけの push は、Draft にせず、Ready のまま push してください。再レビューは動きません。小さな修正のために再レビューを回すと、CI とレビューの時間がかかり、Approve が外れることもあるためです。この push は、CI とマージする開発者が確かめます。

 - Approve の後は、行コメントや bot が nit などとした指摘のうち、直すと明らかに良く、小さいものだけを直してください。小さいものとは、PR が変えたファイルの中で、振る舞いを変えない修正 (タイポ・名前・コメント・import・整形・テストの追加など) です。振る舞いが変わるもの・迷うもの・質問は直さず、返信だけにしてください。マージは、デフォルトブランチに向けた PR なら開発者が、epic ブランチに向けた PR なら 7 で行います。
   - 直すときは、上の「揃ったら」と同じく 1 回だけ push し、PR は Ready のままにしてください。
   - 返信には、直した commit と、再レビューをしないことを書いてください。開発者が、Approve の後に何が変わったかを確かめられるようにするためです。
   - ベースが epic ブランチなら、直さずに返信だけにしてください。7 は head への Approve でマージするため、push すると再レビューが終わるまでマージできなくなります。小さな指摘は、開発者が epic ブランチの PR で確かめます。
 - 直すものが無ければ、7 に進んでください。

## 7. epic ブランチにマージする
ベースが epic ブランチのときだけ行います。デフォルトブランチに向けた PR は、開発者がマージします (⑪)。

コードレビューの Approve (head の commit への) と CI の成功がそろったら、PR を epic ブランチにマージし、Sub Issue を閉じます (下のコマンド)。6 で直すものが無ければ、起こされるたびに実行してください。Approve と CI のどちらが先に届いても、後の方で起こされたときにマージできます。

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/epic.sh" merge <PR>
```

 - `MERGED`: マージし、Sub Issue を閉じました。リファインメントが後続に着手します。`unsubscribe_pr_activity` で購読を外して終えてください。
 - `WAIT`: まだそろっていません。何もせずに終えてください。CI の失敗が出ていれば、6 のとおり直してください。
 - `CONFLICT`: 先にマージされた別の Sub Issue と、コンフリクトしています。PR を Draft にし (冒頭の「Draft にする」)、`git fetch origin <ベース> && git merge origin/<ベース>` で取り込んで解消してください。4 の検査を通してから push し、6 と同じく Ready にします (再レビューが動きます)。
 - `SKIP`: ベースが epic ブランチではないか、PR が閉じています。何もしないでください。
 - `FAILED`: 「判断できないとき」として止めてください。出力 (CI が動いていない、など) を質問に書きます。
 - エラーで終わった (上のどれも出ない) ときは、もう一度だけ実行してください。それでも同じなら、`FAILED` と同じく止めてください。マージした後に Sub Issue を閉じられなかったときも、もう一度実行すれば閉じます。

## 判断できないとき
次のように Claude だけで判断できないときは、推測で作らず、`/dev:blocked` の「2. 止める」で人間に返してください。PR を作った後は PR の番号で実行し、続けて PR を Ready にして (冒頭の「Ready にする」)、`unsubscribe_pr_activity` で PR の購読を外してください。Draft のままだと、開発者が PR に `claude:implement` を付けても再開しないためです。Ready にできなければ、そのことを PR にコメントしてください。Sub Issue の `claude:implement` は残ります (5 を参照)。

 - 完了条件 があいまいで、どう作るかで振る舞いが大きく変わる
 - 見本どおりに作れない (リポジトリの今の作りと合わない・見本と完了条件が食い違うなど)
 - Sub Issue がリポジトリの今の作りと合わない。または 依存 (Blocked by) の Issue のコードが無くて作れない
 - テストの仕組みが無く、何を入れるかで結果が大きく変わる
 - Sub Issue を決められない (PR に `Closes #N` が無い)
 - 前のセッションのブランチに push できない (403 など)
 - PR を Draft / Ready に切り替えられない (CCR のルートも `gh pr ready` も失敗する)
 - epic ブランチにマージできない (7 で `FAILED` と出る)
 - CI が、変更と関係のない理由 (シークレット・外部サービスなど) で失敗する。または同じ失敗を 2 回直しても通らない
 - 再レビューを 3 回頼んでも Request changes が続く。またはレビューの指摘が Sub Issue・親 Issue と食い違い、どちらに従うか決められない

名前や小さな設計の選択など、決めれば進められるものは止めずに決め、理由を PR の Diff コメントに書いてください。

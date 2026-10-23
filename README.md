# ➕ FastShip プラグイン

FastShip プラグインは [Claude Code on the Web](https://claude.ai/code) と [スケジュール済みタスク](https://claude.ai/code/routines) を使って、要件整理から開発、レビューまで自動化する Claude プラグインです。開発したアプリは [**fastship.jp**](https://fastship.jp) で公開できます。

 - [➕ **FastShip プラグイン**](https://github.com/theindiehacker/fastship-plugin) ( Claude プラグイン )
 - [📺 **FastShip App リポジトリ**](https://github.com/theindiehacker/fastship-app) ( GitHub テンプレートリポジトリ )

```mermaid
graph LR;
    Human(("🧑")) --> Claude
    
    subgraph Claude ["🧠 Claude"]
        slack.com(["💬 https://slack.com<br/>(= Claude Tag )"])
        claude.ai(["🧠 https://claude.ai"])
    end
    
    subgraph GitHub ["🐙 github.com/org"]
        Repository("📦 〇〇.git")
    end

    subgraph ClaudeCode ["💻 Claude Code on the Web"]
        analysis(["🤔 <b style='font-size: larger;'>〇〇 / 課題分析</b><br/>課題の解像度と解の質を高め、要件を決める<br/>大きければ Issue を分ける"])
        refinement(["✂️ <b  style='font-size: larger;'>〇〇 / リファインメント</b><br/>Sub Issue に分解し、epic ブランチを作る<br/>1 PR で済むなら分けない"])
        implement(["🧑‍💻 <b  style='font-size: larger;'>〇〇 / 実装</b><br/>ドメイン駆動設計 + テスト駆動開発"])
        review(["✔️ <b  style='font-size: larger;'>〇〇 / レビュー</b><br/>コードレビュー / セキュリティレビュー"])
    end

    Claude -->|① Issue を起票<br/>+ 🏷️ <code>claude:analysis</code>| Repository -->|② 起動| analysis
    analysis -->|③ 課題・解決策・要件を<br/>Issue に追記<br/>+ 🏷️ <code>claude:analyzed</code>| Repository
    Developer(("🧑‍💻")) -->|④ 確認・承認<br/>+ 🏷️ <code>claude:refine</code>| Repository
    Repository -->|⑤ 起動| refinement -->|"⑥ Sub Issue を起票する<br/>(1 PR で済むなら Issue のまま)<br/>+ 🏷️ <code>claude:implement</code>"| Repository
    
    Repository -->|⑦ 起動| implement -->|"⑧ PR を作成<br/>✅ と CI の成功で epic にマージ"| Repository
    
    Repository -->|⑨ 起動| review -->|⑩ ✅ / 🛑<br/>🛑 なら Ready → Draft| Repository

    Developer -->|"⑪ epic の PR をレビュー<br/>マージ・リリース"| Repository

    ClaudeCode -.->|❓ 質問・差し戻し<br/>+ 🏷️ <code>claude:blocked</code>| Repository
```

Claude の作業 (課題分析・リファインメント・実装・レビュー) は、すべてルーティン (claude.ai のサブスク) で動かします。GitHub Actions の時間は使いません。Actions の Claude レビュー (claude-code-action) が PR で自動で動くリポジトリでは、⑨ と二重になるため、`/dev:setup` が止めるか確認します。CI (required workflow など) は push のたびに動くため、実装は CI とレビューの指摘への修正をまとめて 1 回で push します。

Sub Issue に分けた Issue は、Sub Issue の PR を epic ブランチにまとめ、開発者は最後の 1 回だけレビュー・マージします ([🌿 ブランチ](#-ブランチ))。

## 🚀 導入

```mermaid
flowchart LR
    plugin["1. プラグインを入れる"] --> setup["2. /dev:setup"] --> env["3. クラウド環境"] --> merge["4. PR をマージ"] --> issue["5. 起票する"]
```

**前提**: claude.ai のアカウント (Pro / Max / Team / Enterprise)、対象リポジトリに [Claude GitHub App](https://github.com/apps/claude)、ローカルに Claude Code (claude.ai でログイン)・`gh`・`jq`

### 1. プラグインを入れる
ローカルの Claude Code で実行します。

```text
/plugin marketplace add anthropics/claude-plugins-official
/plugin marketplace add theindiehacker/fastship-plugin
/plugin install dev@fastship
```

dev は技術スタックに依存しません。bun / Biome・uv / Ruff / Pyright で開発するなら、`/plugin install stack@fastship` も実行します ([🧰 技術スタック](#-技術スタック-stack-プラグイン))。

### 2. `/dev:setup` を実行する
対象リポジトリで `/dev:setup` を実行します (別のリポジトリなら `/dev:setup owner/repo`)。ラベル・ルーティン 1 つ・テンプレートを用意し、PR を作ります。[判断待ちの一覧](#-判断待ちの一覧) のリンクも伝えます。stack を入れていれば、技術スタックも入れるか聞きます。Actions の Claude レビューが PR で自動で動くなら、止めるか聞きます。導入済みなら最新版に更新します ([版を上げたとき](#版を上げたとき))。

3 は API で設定できないため、setup が案内したら画面で設定します。

### 3. クラウド環境
ルーティンが動くクラウド環境に、FastShip プラグインを入れます。環境ごとに 1 回です。

1. https://claude.ai/code の入力欄の下の環境名 → **クラウド** → setup が伝える環境の ⚙️

   ![環境の設定を開く](docs/images/claude-1-env-menu.png)

2. **セットアップスクリプト** に下を貼り、**変更を保存**

   <!-- setup の 4.3 と同じ。変えるときは両方を直す -->
   ```bash
   {
     claude plugin marketplace add anthropics/claude-plugins-official &&
     claude plugin marketplace add theindiehacker/fastship-plugin &&
     claude plugin install dev@fastship
   } || echo "⚠️ dev@fastship を入れられませんでした" >&2
   ```

   ![セットアップスクリプトに貼る](docs/images/claude-2-setup-script.png)

   setup で技術スタックを入れたなら、次の行も足します。stack は dev と一緒には入りません。

   ```bash
   claude plugin install stack@fastship || echo "⚠️ stack@fastship を入れられませんでした" >&2
   ```

### 4. PR をマージする
setup が作った PR をマージします。

### 5. 起票する
GitHub の UI で **New issue** → **🚀 バックログ** を選び、背景と参考資料を書いて起票します。`claude:analysis` が自動で付き、③ 課題分析が始まります。

 - 書き込み権限 (Triage 以上) の無いメンバーが起票すると、ラベルが付かないことがあります (GitHub Docs に記載が無く、[Community の報告](https://github.com/orgs/community/discussions/22510) があります)。付いていなければ、権限のある人が `claude:analysis` を付けてください。

チャットで起票したい人は、`/dev:issue` も使えます (任意)。claude.ai のチャットで `/dev:issue [owner/repo] {やりたいこと}` を実行すると、背景と参考資料を聞かれ、`claude:analysis` 付きで起票されます。使う前に、メンバーそれぞれが 1 回だけ設定します。

1. https://claude.ai/customize/plugins で **追加** → **マーケットプレイスを追加** を押し、`theindiehacker/fastship-plugin` を入れる

   ![マーケットプレイスを追加する](docs/images/claude-3-plugins.png)

2. `dev` と、依存の `security-guidance` を有効にする (一覧に無ければ `anthropics/claude-plugins-official` も追加する)
3. **コネクタ** で GitHub を有効にし、起票先のリポジトリが見えるようにする

Claude Code からも `/dev:issue` で起票できます。Slack (Claude Tag) からは使えません (org のプラグインしか使えず、org の GitHub 同期は private リポジトリしか受け付けないため)。

### 版を上げたとき
その版の節 (`0.15.0 に上げたとき` など) があれば、その手順を行います。節の無い版では、何もしなくて構いません。

#### クラウド環境を作り直す
版の節に書いてあるときだけ行います。クラウド環境は Setup script の結果を約 7 日使い回すため、ほかの版は 7 日以内に入れ替わります。Setup script を変えると、次のセッションで作り直されます。

1. [3. クラウド環境](#3-クラウド環境) の 1 と同じく、環境の ⚙️ を開く
2. **セットアップスクリプト** の末尾に `# dev <版>` を足し (あれば版を書き換え)、**変更を保存**。版は [plugin.json](plugins/dev/.claude-plugin/plugin.json) の `version` です。stack だけ上がったときは `# stack <版>` を足します

   ![末尾に版を足す](docs/images/claude-4-setup-script-version.png)

3. 次にルーティンが動いたら、https://claude.ai/code/routines の `{リポジトリ名} / FastShip` の **履歴** から、そのセッションを開く。`blocked.sh start` を実行した行を開き、パス (`.../fastship/dev/<版>`) が新しい版か確かめる

   ![スキルのパスで版を確かめる](docs/images/claude-5-skill-version.png)

### 0.16.0 に上げたとき
Sub Issue の PR を epic ブランチにまとめ、開発者のレビュー・マージを最後の 1 回にしました ([🌿 ブランチ](#-ブランチ))。課題分析は、成功指標ではなく機能要件・非機能要件を書き、大きい Issue を分けるようにしました。

1. `/dev:setup` を実行し直します。Issue テンプレート (`backlog.md`) を更新し、epic ブランチに向けた PR で CI が動くかを確かめます
2. `⑪ マージ待ち` のブックマークを、setup が伝えるリンクに貼り替えます (`base:` を足しました)

進行中の Issue は、そのままで構いません。前の版で Sub Issue に分けた Issue は、今までどおり Sub Issue の PR をデフォルトブランチに向けます。

### 0.15.0 に上げたとき
FastShip プロジェクト (GitHub Project) をやめ、判断待ちはリポジトリの Issue 一覧で見るようにしました。Auto-add の設定も要らなくなりました。

導入済みのリポジトリでは、[📋 判断待ちの一覧](#-判断待ちの一覧) の 4 つのリンクをブックマークしてください (`/dev:setup` を実行し直しても出ます)。FastShip プロジェクトと Auto-add のワークフローは、残しても害はありません。要らなければ消してください。

## 🧰 スキル

| スキル | 使う人・場面 | すること |
|:--|:--|:--|
| `/dev:setup [owner/repo]` | 🧑‍💻 開発者 (導入・更新) | ラベル・ルーティン・テンプレートを導入し、PR を作る。判断待ちの一覧のリンクを伝える |
| `/dev:issue [owner/repo] {内容}` | 🧑 誰でも (① 起票) | 背景と参考資料を聞き、`claude:analysis` を付けて起票する。目的が複数あれば分けて起票する |
| `/dev:analysis {Issue}` | ルーティン (③ 課題分析) | 課題・解決策・要件 (機能要件・非機能要件) を書き、`claude:analyzed` を付ける。大きければ Issue を分ける |
| `/dev:refine {Issue}` | ルーティン (⑤⑥ リファインメント) | epic ブランチを作り、1 PR で終わる Sub Issue に分解して `claude:implement` を付ける。Sub Issue がすべて閉じると、epic ブランチの PR を作る。1 PR で済むなら分けず、Issue に完了条件を書き足して `claude:implement` を付ける |
| `/dev:implement {Sub Issue / Issue / PR}` | ルーティン (⑦⑧ 実装) | ドメイン駆動設計 + テスト駆動開発で実装し、Draft の PR を作る。Ready にして `claude:under-review` を付ける。epic ブランチに向けた PR は、✅ と CI の成功でマージする |
| `/dev:review {PR}` | ルーティン (⑨⑩ レビュー) | コードレビューとセキュリティレビューをし、✅ / 🛑 を返す。🛑 なら PR を Draft に戻す |
| `/dev:blocked` | ルーティン (課題分析・リファインメント・実装・レビュー) | 多重起動を防ぎ、判断できないときは質問して `claude:blocked` を付ける |
| `/dev:push-pr` | 🧑‍💻 開発者 / ルーティン (⑦⑧ 実装) | PR テンプレートに沿って PR を作成・更新する |

`/dev:implement` は、リポジトリの検査 (`CLAUDE.md`・CI に書かれたテスト・lint・型チェック) を自分で実行してから PR を作ります。技術スタックの hook (stack プラグイン) は要りません。

`/dev:review` は `/code-review` を `xhigh`・`--max-findings all` で使います。`/code-review` は最後に指定した値を覚えるため、手元で `/dev:review` を使うと、以後の `/code-review` も同じ設定になります。戻すには、次の `/code-review` に使いたい effort と `--max-findings default` を付けてください。

## 🏷️ ラベル

| ラベル | 付ける人 | 意味 |
|:--|:--|:--|
| `claude:analysis` | 🧠 Claude | 課題分析を始める |
| `claude:analyzed` | 🧠 Claude | 課題分析が終わり、承認を待っている (ルーティンは起動しない) |
| `claude:refine` | 🧑‍💻 開発者 | 課題分析の結果を承認し、リファインメントを始める |
| `claude:implement` | 🧠 Claude | Sub Issue (1 PR で済むときは Issue) の実装を始める |
| `claude:under-review` | 🧠 Claude | PR のレビューを始める |
| `claude:blocked` | 🧠 Claude | 人間の回答を待っている |

レビューが ✅ になったことは、ラベルではなく、PR が Ready で `claude:under-review` が付いていないことで示します ([📋 判断待ちの一覧](#-判断待ちの一覧))。

## 📋 判断待ちの一覧

開発者は、リポジトリの Issue 一覧を下の 4 つのクエリで絞れば、次に判断することが分かります。クエリはラベルと PR の Draft / Ready で絞り込んでいます。二重枠が、一覧に載る (開発者の番の) 状態です。Claude の番の状態は `⏳ 進行中` に載り、止まっていないかを確かめられます。

```mermaid
flowchart LR
    analysis["🤔 課題分析<br/><code>claude:analysis</code>"] --> analyzed[["④ 承認待ち<br/><code>claude:analyzed</code>"]]
    analyzed -->|🧑‍💻 承認<br/>+ <code>claude:refine</code>| refine["✂️ リファインメント<br/><code>claude:refine</code>"]
    refine --> implement["🧑‍💻 実装<br/><code>claude:implement</code>"] --> review["✔️ レビュー<br/><code>claude:under-review</code>"]
    review -->|"✅ (1 PR で済む Issue)"| merge[["⑪ マージ待ち<br/>Ready の PR"]]
    review -->|"✅ (Sub Issue)"| epic["🌿 実装が epic にマージ<br/>Sub Issue を閉じる"]
    epic -->|"すべて閉じたら<br/>epic の PR を作る"| merge
    review -->|🛑 なら Draft に戻して直す| implement
    merge -->|"🧑‍💻 マージ<br/>Closes で Issue が閉じる"| done(("✅"))
    analysis & refine & implement & review -.-> blocked[["❓ 回答待ち<br/><code>claude:blocked</code>"]]
```

| 一覧 | クエリ | 判断すること |
|:--|:--|:--|
| ④ 承認待ち | `is:issue is:open label:"claude:analyzed"` | 課題・解決策・要件を読み、承認か差し戻しか |
| ❓ 回答待ち | `is:open label:"claude:blocked"` | Claude の質問への回答 |
| ⑪ マージ待ち | `is:pr is:open draft:false base:<デフォルトブランチ> -label:"claude:blocked" -label:"claude:under-review"` | マージ・リリースするか |
| ⏳ 進行中 | `is:open label:"claude:analysis","claude:refine","claude:implement","claude:under-review" -label:"claude:blocked"` | 止まっていないか ([🛟 ルーティンの前提](#-ルーティンの前提)) |

 - リンクは `https://github.com/{owner/repo}/issues?q=<クエリ>` です。リポジトリの Issue 一覧は、Issue と PR を一緒に出します。`/dev:setup` が対象リポジトリのリンクを伝えるので、ブックマークしてください。
 - リポジトリが複数あるときは、リポジトリごとのリンクを使います。`⑪ マージ待ち` はラベルで絞れないため、FastShip を通っていない Ready の PR も載ります。epic ブランチに向けた Sub Issue の PR は、実装がマージするため載りません (`base:`)。

PR は、実装・修正の間だけ Draft にします。

| PR | 状態 | 切り替える所 |
|:--|:--|:--|
| Draft | 🧠 実装・修正中 | 実装は Draft で PR を作る。⑨ が 🛑 を返すときと、止めた実装を再開するときに Draft に戻す |
| Ready + `claude:under-review` | 🧠 レビュー中 | 実装が push を終えたら、Ready にして `claude:under-review` を付ける |
| Ready + `claude:blocked` | 🧑‍💻 回答待ち | 実装・レビューが人に返すとき。実装は Draft なら Ready にする |
| Ready | 🧑‍💻 マージ待ち | ⑨ が ✅ を返したら、そのまま。epic ブランチに向けた PR は、CI が通ると実装がマージする |

 - Draft の PR にラベルを付けても、ルーティンは起動しません。PR の工程 (⑨ レビュー・止めた実装の再開) は、Ready の PR にラベルを付けて動かします。
 - レビューの間も Ready なので、マージボタンは押せます。`⑪ マージ待ち` には出ないため、一覧から ✅ の前にマージすることはありません。CODEOWNERS があると、レビューを頼むたびにレビューの依頼が届きます。
 - Issue の進み具合は、PR の Draft ではなくラベル (`claude:implement` など) で見ます。Issue の検索では、Issue をつながった PR の Draft で絞れないためです。

 - `claude:analyzed` は、課題分析・リファインメントが Issue の状態から決めて付け外しします (`scripts/waiting.sh`)。手で付け外ししても、次にそれらが動いたときに状態に合わせ直されます。
   - 課題分析が、最後の承認 (`claude:refine` を付けた) より後に終わったときに付きます
   - 進行中ラベル (`claude:analysis` / `claude:refine` など) か `claude:blocked` が付いている間は付きません
 - Sub Issue がすべて閉じて 1 つ以上が完了すると、リファインメントが epic ブランチの PR を作ります。親 Issue は、その PR のマージ (`Closes`) で閉じます。すべて見送りなら、作らずに残します。1 PR で済む Issue は、PR の `Closes` で閉じます。

## 🧑‍💻 人間が判断すること

1. **④ 承認** (`④ 承認待ち`): 課題分析で追記された課題・解決策・要件を確認し、解く価値があるか、作るものが合っているかを判断します。大きい Issue は課題分析が分けるので、分けた Issue もそれぞれ承認します。優先順位の高い Issue から `claude:refine` を付けます。方向がずれている場合は、Issue にコメントして `claude:analysis` を付け直します。見送るときは、Issue を閉じます。
2. **⑪ マージ・リリース** (`⑪ マージ待ち`): Ready になり (レビューが ✅)、CI が通った PR を確認し、マージ・リリースします。CI の結果は PR で確かめてください。Sub Issue に分けた Issue は、epic ブランチの PR で全体を確かめます。✔️ 動作確認 に、要件ごとに確かめた Sub Issue の PR が書いてあります。✅ の後に自分で push したとき (コンフリクトの解消など) は、`claude:under-review` を付けるだけで再レビューを受けられます (epic ブランチの PR は除く。⑨ は Sub Issue の PR のためのものです)。✅ の後に、実装が小さな指摘 (`[nits]` など) だけを直して push することがあります。再レビューはせず、直した commit を指摘への返信に書きます (epic ブランチに向けた Sub Issue の PR では直さず、返信だけにします)。

## 🌿 ブランチ
Sub Issue に分けた Issue は、epic ブランチ (`epic/<親 Issue の番号>`) にまとめてから、デフォルトブランチに入れます。

```mermaid
flowchart LR
    main1(["main"]) -->|"⑥ epic ブランチを作る"| epic(["epic/123"])
    sub["Sub Issue の PR"] -->|"⑨ ✅ と CI の成功で<br/>実装がマージ"| epic
    epic -->|"Sub Issue がすべて閉じたら<br/>PR を作る<br/>🧑‍💻 レビュー・マージ"| main2(["main"])
```

| Issue | PR のベース | マージする人 |
|:--|:--|:--|
| Sub Issue に分けた Issue | `epic/<親 Issue の番号>` | Sub Issue の PR は 🧠 実装。epic ブランチの PR は 🧑‍💻 開発者 |
| 1 PR で済む Issue | デフォルトブランチ | 🧑‍💻 開発者 |

 - 実装は、Sub Issue の PR をマージすると、Sub Issue を閉じます。`Closes` はデフォルトブランチへのマージでしか閉じないためです。手で epic ブランチにマージしたときは、Sub Issue も閉じてください。後続の Sub Issue の実装が始まります。
 - ✅ で CI も通ったのにマージされないときは、PR に `claude:implement` を付けてください。実装が再開し、再レビューの後にマージします。
 - リファインメントは、Sub Issue が閉じるたびに、デフォルトブランチを epic ブランチに取り込みます。コンフリクトして取り込めないときは、epic ブランチの PR で開発者が解消します。
 - epic ブランチに向けた PR でも CI が動くようにしてください (`/dev:setup` が確かめます)。動かないと、実装はマージせずに人間に返します。
 - Sub Issue の PR に開発者が Request changes を付けると、解消する (Approve か Dismiss) までマージしません。

## ❓ 質問・差し戻し

Claude だけで判断できないことがあると、ルーティンは処理を止めて人間に返します。手順は `/dev:blocked` スキルにまとめています。

1. Claude が Issue / PR に質問をコメントし、進行中のラベル (`claude:analysis` / `claude:refine` / `claude:implement` / `claude:under-review`) を外して `claude:blocked` を付けます。
2. 開発者は `❓ 回答待ち` の一覧で Issue / PR を確認し、コメントで回答します。
3. 開発者が `claude:blocked` を外して元のラベルを、止まった Issue / PR に付け直すと、処理が再開します。再開したセッションは、前回の質問と回答を読んでから続けます。

同じ Issue / PR で動くセッションは 1 つだけです。後から起動したセッションは何もせずに終わります。進行中のラベルが付いたまま 10 分以上進まないときは、ルーティンが動かなかったか、セッションが途中で止まっています (`⏳ 進行中` に残ります)。そのラベルを外して付け直すと、やり直します。

レビューの 🛑 は実装のセッションが対応します。Claude だけで判断できない指摘は、同じ手順で `claude:blocked` を付けて人間に返します。人が作った PR も、Ready にして `claude:under-review` を付けるとレビューします (Draft の PR では動きません)。🛑 なら Draft に戻すので、直したら Ready にして付け直してください。

## 🛟 ルーティンの前提

ルーティンは、気づかないうちに止まることがあります。

 - ルーティンは、作った人の claude.ai アカウントに属し、チームでは共有されません。作った人の利用枠を使い、その人が抜けると止まります。そのときは、別の人が `/dev:setup` を実行し直して作り直してください。
 - FastShip が使う `issues.labeled`・`issues.closed` のトリガーは、[ルーティンのドキュメント](https://code.claude.com/docs/en/routines) にありません (載っている GitHub イベントは Pull request と Release だけです)。
 - GitHub イベントは、ルーティンごと・アカウントごとの毎時の上限を超えると捨てられます。上限の数値は公開されていません。ルーティンは 1 つなので、すべての工程で 1 つの上限を分け合います。

どの場合も、進行中のラベル (`claude:analysis` / `claude:refine` / `claude:implement` / `claude:under-review`) が付いたまま動きません。`⏳ 進行中` の一覧をときどき見て、10 分以上進まないものはラベルを外して付け直してください。

Sub Issue は、PR がマージされるまで `claude:implement` が付いたままなので、PR がマージを待つ間も `⏳ 進行中` に載ります。止まっているかは、PR を見て確かめてください。PR が Draft のまま 10 分以上進まないときは、Sub Issue の `claude:implement` を外して付け直すと、実装が PR を Ready にして引き継ぎます。

## 🧰 技術スタック (stack プラグイン)

`stack` は、使うリポジトリだけが入れるプラグインです。dev とは別に入れます。bun / Biome・uv / Ruff / Pyright・shadcn/ui・Tailwind CSS で開発するリポジトリに、次を配ります。

| 配るもの | 内容 |
|:--|:--|
| 🚀 SessionStart | Claude Code on the web で、mise のツールと、`bun.lock`・`uv.lock` の依存を入れ、lefthook の Git フック (pre-commit) を設定する |
| 🚫 PreToolUse | bun・uv のリポジトリで npm・pip などを止め、bun・uv を使わせる |
| ✏️ PostToolUse | Claude が編集したファイルを Biome・Ruff で整形する |
| ✔️ Stop | 変更したファイルが Biome・tsc・Ruff・Pyright を通るまで、作業を続けさせる |
| 🎨 `/stack:ui` | shadcn/ui・Tailwind CSS の書き方 |
| 📚 依存 | Context7 (版に合ったドキュメント)・pyright-lsp (編集した直後の型エラー) |

1. ローカルで `/plugin install stack@fastship` を実行してから、`/dev:setup` で技術スタックを入れると答えます。setup が `/stack:setup` で道具と設定を入れ、リポジトリの `.claude/settings.json` で stack を有効にします。
2. クラウド環境のセットアップスクリプトに、`claude plugin install stack@fastship` の行を足します ([3. クラウド環境](#3-クラウド環境))。

hook は、道具と設定 (`mise.toml`・lock ファイル・`node_modules` の Biome・`.venv` の Ruff など) があるリポジトリでだけ動きます。ローカルで pyright-lsp を使うには、`pyright-langserver` を PATH に入れてください (例: `uv tool install pyright`)。

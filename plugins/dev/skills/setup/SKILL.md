---
name: setup
description: 対象リポジトリにラベル駆動開発 (ラベル・ルーティン・FastShip プラグイン・Actions の Claude レビュー) を導入し、コミット・PR 作成まで行う。判断待ちの一覧のリンクを伝える。stack プラグインが入っていれば、技術スタックも入れるか聞く。導入済みなら最新版に更新する。使い方 → /dev:setup [owner/repo]
argument-hint: "[owner/repo]"
---

# セットアップ手順
## 1. 技術スタック (stack プラグインが入っているときだけ)
`/stack:setup` スキルが使えなければ (stack プラグインが入っていなければ)、1 は飛ばしてください。dev は技術スタックに依存しません。

使えるなら、次を行うかをユーザーに聞いてください。技術スタックはリポジトリごとに違うため、勧めずに聞くだけにします。行わないと答えたものは飛ばします。

 - ボイラープレート: Organization のテンプレートリポジトリ (`gh repo list <owner> --limit 1000 --json name,isTemplate --jq '.[] | select(.isTemplate) | .name'`) を対象リポジトリに導入する。無ければ聞きません
 - 技術スタック: `/stack:setup` で、bun / Biome・uv / Ruff / Pyright・lefthook の設定を入れる。ボイラープレートで入ったものは残し、足りないものだけを足します

`/stack:setup` を行ったら、2 の `enabledPlugins` に `"stack@fastship": true` も足してください。stack の hook (整形・lint・型チェック) が、このリポジトリで動くようになります。

## 2. FastShip プラグインの設定 (ローカル)
対象リポジトリの `.claude/settings.json` に次をマージしてください。他のキーは残してください。

```json
{
  "extraKnownMarketplaces": {
    "fastship": {
      "source": { "source": "github", "repo": "theindiehacker/fastship-plugin" }
    }
  },
  "enabledPlugins": {
    "dev@fastship": true,
    "session@fastship": true
  }
}
```

session の Stop の hook は、gitleaks (シークレット)・trivy (依存の脆弱性・IaC の設定ミス)・uv (semgrep を uvx で動かす) を使います。無いと検査しません。技術スタックによらず、対象リポジトリの `mise.toml` の `[tools]` に足してください。

 - `mise.toml` が無ければ作ります。既にあるツールと版は残します。足すツールは `mise latest <ツール>` の版に固定します
 - `[settings]` に `experimental = true` と `lockfile = true` が無ければ足し、`mise install` の後に `mise lock` で `mise.lock` を作ります。Claude Code on the web は、lock の URL からツールを入れます

## 3. Issue / PR テンプレートの配置
FastShip プラグインのテンプレートを、対象リポジトリにコピーしてください。2 の設定と一緒にコミットします。コピーは GitHub の UI で Issue / PR を作るときに使われます。スキルはプラグインのテンプレートを直接読みます。

| コピー元 | コピー先 | 使う工程 |
|:--|:--|:--|
| `${CLAUDE_PLUGIN_ROOT}/skills/issue/backlog.md` | `.github/ISSUE_TEMPLATE/backlog.md` | ① 起票 / ③ 課題分析 |
| `${CLAUDE_PLUGIN_ROOT}/templates/ISSUE_TEMPLATE/todo.md` | `.github/ISSUE_TEMPLATE/todo.md` | ⑥ リファインメント (Sub Issue) |
| `${CLAUDE_PLUGIN_ROOT}/templates/PULL_REQUEST_TEMPLATE.md` | `.github/PULL_REQUEST_TEMPLATE.md` | ⑧ PR 作成 |

 - コピー先が無い場合は作成してください。大文字・小文字だけが違うファイル (例: `pull_request_template.md`) は同じファイルとして扱ってください。
 - 既にあって内容が違う場合は、リポジトリでカスタマイズしている可能性があります。差分を見せて、上書きしてよいかユーザーに確認してください。上書きしない場合はそのまま残してください。
 - それ以外のテンプレートは残してください。
 - 対象リポジトリに `.github/ISSUE_TEMPLATE/` が無い場合、コピーすると org の `<owner>/.github` にある Issue テンプレートと `config.yml` が使われなくなります。org にそれらがあればユーザーに伝え、対象リポジトリにもコピーするか確認してください。

## 4. ラベル駆動開発のセットアップ
リポジトリへのコミットは伴いません。

### 4.1 ラベル

```bash
gh label create claude:analysis --color d97757 --description "🤔 課題分析を始める" --force -R {owner/repo}
gh label create claude:refine --color d97757 --description "✂️ 課題分析の結果を承認し、リファインメントを始める" --force -R {owner/repo}
gh label create claude:implement --color d97757 --description "🧑‍💻 Sub Issue (1 PR で済むときは Issue) の実装を始める" --force -R {owner/repo}
gh label create claude:blocked --color b60205 --description "❓ 人間の回答を待っている" --force -R {owner/repo}
gh label create claude:analyzed --color 0e8a16 --description "🧑‍💻 課題分析が終わり、承認を待っている" --force -R {owner/repo}
```

`claude:analyzed` は、人が見るためのラベルです。4.2 のトリガーには使いません。PR のレビューはラベルを使いません。PR を Ready にすると動き (5)、結果はコードレビューの Approve / Request changes で示します。

### 4.2 ルーティン
RemoteTrigger ツールで、FastShip のルーティンを 1 つ用意し、URL (`https://claude.ai/code/routines/{ID}`) をユーザーに伝えてください。課題分析・リファインメント・実装は、1 つのルーティンが Issue / PR のラベルを見て選びます。PR のレビューは Actions で動きます (5)。

| 項目 | 値 |
|:--|:--|
| 名前 | `{リポジトリ名} / FastShip` |
| リポジトリ | 対象リポジトリのみ |
| 環境 | 既存の ` / FastShip` ルーティンと同じ。無ければユーザーに確認 |
| モデル | `claude-opus-5-5` |
| ツール | claude.ai の既定 (`session_context.allowed_tools` を `["preset:default"]` にする) |
| コネクタ | なし |
| 通知 | プッシュ通知のみ |
| プロンプト | 下記 |

トリガーは次の 3 本です。

| イベント | ラベル (どれかを含む場合) | 使う工程 |
|:--|:--|:--|
| `issues.labeled` | `claude:analysis` / `claude:refine` / `claude:implement` | 課題分析・リファインメント・実装 |
| `issues.closed` | `claude:implement` | リファインメント (Sub Issue が閉じたときに、後続の Sub Issue に着手する。1 PR で済むとしてそのまま実装した Issue が閉じたときも起動するが、何もせずに終わる) |
| `pull_request.labeled` | `claude:implement` | 実装 (PR で止めたときの再開)。Draft の PR では起動しないため、実装は PR を Ready にしてからラベルを付ける |

プロンプト:

```text
GitHub のイベントで起動しました。トリガーになった Issue / PR に、FastShip の工程を 1 つ行ってください。
1. Issue (PR ではない) が closed なら、/dev:refine で行ってください。Sub Issue が閉じたときの後続の着手です。
2. それ以外は、Issue / PR に付いているラベルを見て、次の順に試してください。スキルの「1. 始める」で STOP と出たら、次を試してください。どれも STOP か、ラベルが無ければ、何もせずに終えてください。
   - claude:implement → /dev:implement
   - claude:refine → /dev:refine
   - claude:analysis → /dev:analysis
```

 - 工程は、イベントの種類ではなく Issue / PR の状態とラベルで選びます。セッションに渡るイベントの内容は、ルーティンのドキュメントに書かれていないためです。`issues.closed` で起動するのは closed の Issue だけなので、状態で見分けられます。
 - 「1. 始める」(`blocked.sh start`) は、ラベルが付いた後にまだ着手していなければ `CONTINUE`、それ以外は何も変えずに `STOP` を返します。このため、付いたばかりのラベルの工程だけが動きます (例: `claude:implement` が付いた PR に別のラベルを付けても、実装は着手済みで `STOP` になる)。

```mermaid
flowchart LR
    list["list"] --> exists{"名前が ' / FastShip' で終わり<br/>sources の先頭が対象リポジトリ"}
    exists -->|ある| get["get"] --> update["update<br/>プロンプトとモデルだけ差し替える"]
    exists -->|ない| more{"has_more"}
    more -->|true| ask["ユーザーに確認"]
    ask -->|ある| get
    ask -->|ない| create
    more -->|false| create["create"] --> clear["update<br/>コネクタを外し、プッシュ通知のみにする"] --> trigger["create_webhook_trigger<br/>3 本"]
```

 - `list`: 返るのは 20 件までで、続きは取れない (`next_cursor` を渡しても同じページが返る)。`has_more` が true のときに見つからないルーティンは、無いとみなさない (重複して作らないため)。https://claude.ai/code/routines に `{リポジトリ名} / FastShip` があるかユーザーに確認し、あれば URL の `trig_…` で `get` する。無ければ `create` する
 - 既存の `update`: `get` した `job_config` を丸ごと送り、`ccr.events[0].data.message.content` と `ccr.session_context.model` だけを変える。トリガーは API から見えず重複に気づけないため、追加・変更しない。古いトリガーに `claude:under-review` が残っていても、プロンプトに無いので何もせずに終わる
 - `create`: `/schedule` スキルの書き方に従う。`run_once_at` と `cron_expression` は付けない。実装は PR を作るので、`session_context` に `"autofix_on_pr_create": true` を付ける。課題分析は PR を作らないため、付いていても何も起きない。リファインメントは epic ブランチの PR を作るが、作った後に購読を外す
 - 新規の `update`: `{"clear_mcp_connections": true, "notifications": {"channel": {"email": false, "push": true, "slack": false}}}` を送る (`create` は接続済みのコネクタをすべて付けるため)
 - `create_webhook_trigger`: 上のトリガーの表の行ごとに、下記の body を、`events` をその行のイベントに、`values` をその行のラベルに置き換えて送る。`pull_request.labeled` は `field` を `pr.labels` にする。`pull_request.labels` は `unknown field` で拒否される
 - RemoteTrigger や Claude GitHub App が使えない場合は、上の表の内容で https://claude.ai/code/routines から手動で作るよう案内する

ルーティンの URL と一緒に、次の前提をユーザーに伝えてください (README の「🛟 ルーティンの前提」)。
 - ルーティンは、作った人の claude.ai アカウントに属し、チームでは共有されない。作った人の利用枠を使い、その人が抜けると止まる。そのときは、別の人が `/dev:setup` を実行し直して作り直す
 - `issues.labeled`・`issues.closed` のトリガーは、ルーティンのドキュメントに無い (載っている GitHub イベントは Pull request と Release だけ)
 - GitHub イベントは、ルーティンごと・アカウントごとの毎時の上限を超えると捨てられる (上限の数値は公開されていない)。ルーティンが 1 つなので、課題分析・リファインメント・実装で 1 つの上限を分け合う
 - 動かなかった・途中で止まった Issue / PR は、進行中のラベルが付いたまま 4.4 の `⏳ 進行中` に残る。10 分以上進まないものは、ラベルを外して付け直す

```json
{
  "routine_trigger_id": "{作成したルーティンの ID}",
  "source": "github",
  "hook_type": "app",
  "scope_id": "{owner/repo}",
  "events": ["issues.labeled"],
  "filter": {"clauses": [{"field": "issue.labels", "op": "FILTER_OP_IN", "values": ["claude:analysis", "claude:refine", "claude:implement"]}]}
}
```

### 4.3 クラウド環境
クラウドセッションは 2 の設定を読まないため、4.2 の環境の Setup script (claude.ai の環境設定画面) に次を追加するよう案内してください。環境の名前と、スクショ付きの手順 https://github.com/theindiehacker/fastship-plugin#3-クラウド環境 を伝えます。README にも同じスクリプトがあるため、変えるときは両方を直してください。

```bash
{
  claude plugin marketplace add anthropics/claude-plugins-official &&
  claude plugin marketplace add theindiehacker/fastship-plugin &&
  claude plugin install dev@fastship &&
  claude plugin install session@fastship
} || echo "⚠️ dev@fastship・session@fastship を入れられませんでした" >&2
```

 - 1 行目は依存 (`security-guidance`。stack なら `context7`・`pyright-lsp` も) のためです。無いと `dev` が読み込まれません
 - session は技術スタックによらず入れます。Web のセッションの準備 (ツール・依存・Docker の起動) と、作業を終える前の gitleaks・trivy・semgrep の検査を行います (semgrep は uv の uvx で動くため、uv も要ります)
 - Setup script は 0 以外で終わるとセッションが始まらないため、失敗しても警告だけ出します
 - 1 で `/stack:setup` を行ったら、次の行も足すよう案内してください。stack は dev と一緒には入りません (session は stack の依存として入ります)。環境は他のリポジトリと共有しますが、stack の hook は道具と設定 (`mise.toml`・lock ファイル・`node_modules` の Biome・`.venv` の Ruff など) が無いリポジトリでは何もしません

```bash
claude plugin install stack@fastship || echo "⚠️ stack@fastship を入れられませんでした" >&2
```

4.2 で既存のルーティンを `update` した (導入済みの) ときは、上のスクリプトは入っているはずです。追加は案内せず、README の https://github.com/theindiehacker/fastship-plugin#版を上げたとき を読むよう伝えてください。版ごとの手順と、クラウド環境を作り直すかが書いてあります。クラウド環境は Setup script の結果を約 7 日使い回すため、作り直さなくても、ルーティンは 7 日以内に新しい版に入れ替わります。

### 4.4 判断待ちの一覧
開発者は、リポジトリの Issue 一覧を下のクエリで絞って、次に判断することを確かめます。工程はラベルと PR の Draft / Ready で決まるため、GitHub Project は使いません。

下の表の一覧ごとに、下のコマンドでリンクを作り、一覧の名前と一緒にユーザーに伝えてください。ブックマークするよう伝えます。リポジトリの Issue 一覧は、Issue と PR を一緒に出します。`<デフォルトブランチ>` は、対象リポジトリのデフォルトブランチに置き換えてください。epic ブランチに向けた Sub Issue の PR は実装がマージするため、`⑪ マージ待ち` に出さないためです。`⑪ マージ待ち` には、コードレビューが Approve した PR と、epic ブランチの PR (開発者がレビューする) を出します。

| 一覧 | クエリ |
|:--|:--|
| `④ 承認待ち` | `is:issue is:open label:"claude:analyzed"` |
| `❓ 回答待ち` | `is:open label:"claude:blocked"` |
| `⑪ マージ待ち` | `is:pr is:open draft:false base:<デフォルトブランチ> -label:"claude:blocked" (review:approved OR head:epic/)` |
| `⏳ 進行中` | `is:open label:"claude:analysis","claude:refine","claude:implement" -label:"claude:blocked"` |

```bash
jq -rn --arg q '<クエリ>' '"https://github.com/{owner/repo}/issues?q=\($q | @uri)"'
```

## 5. Actions の Claude レビュー
PR のレビュー (⑨⑩) は、github-workflows の Claude のレビュー (`claude-code-review.yml`・`claude-security-review.yml`) が Actions で行います。実装が PR を Ready にすると動き、claude[bot] が行コメントと、コードレビューの判定 (Approve / Request changes) を投稿します。動いているか・止まったかは、PR の Checks に出ます。ルーティンは開発者のアカウントで動くため、自分の PR に Approve / Request changes を付けられません。

1. Claude の認証情報がリポジトリに渡るか確かめてください。下の 2 つのどちらかに `CLAUDE_CODE_OAUTH_TOKEN` か `ANTHROPIC_API_KEY` が出れば渡ります。

```bash
gh api "repos/{owner/repo}/actions/organization-secrets" --jq '.secrets[].name'
gh api "repos/{owner/repo}/actions/secrets" --jq '.secrets[].name'
```

 - 出なければ、レビューとセキュリティ監査 (下の 2) が何もせずに成功で終わり、epic ブランチへのマージも止まることを伝えてください。登録はユーザーに頼み、このセッションでは行いません。public リポジトリには登録しない方針です (fork の PR からトークンを読まれる恐れがあるため。github-workflows の `docs/SETUP.md` の 4.1)。
2. 呼び出し側のワークフロー `.github/workflows/claude.yml` を、次の形にしてください。2・3 と同じコミットに入れます。
   - 無ければ、github-workflows の最新のリリースの `self-claude.yml` をコピーし、各 job の `uses: ./.github/workflows/<ファイル>` を `uses: theindiehacker/github-workflows/.github/workflows/<ファイル>@<sha>  # <タグ>` に書き換えます (下のコマンドで、タグ・sha・中身が出ます)。
   - あれば、`uses:` が最新のリリースより古ければ上げ、下の `if:` を足します。差分を見せて確認してください。
   - `on:` に `pull_request` の `types: [opened, ready_for_review]` を入れます。
   - `code-review`・`security-review` の job の `if:` を下にします。`security-review` の PR のイベントは、v2.2.0 以降の github-workflows が受け付けます。`claude:blocked` を除くのは、実装が人間に返すときにも PR を Ready にするためです。
   - `on:` に `schedule` (`cron: '17 0 1 * *'`) と `workflow_dispatch:` を入れ、`security-audit` job を足します (最新のリリースの `self-claude.yml` からコピーし、`uses:` を書き換えます)。月 1 回、Claude がリポジトリ全体をセキュリティ監査し、PR のレビューでは見ない前からある問題を `security-audit` ラベルの Issue にします。v2.3.0 以降の github-workflows にあります。public リポジトリでは、指摘が公開されるため動きません。

```bash
tag=$(gh api repos/theindiehacker/github-workflows/releases/latest --jq .tag_name)
gh api "repos/theindiehacker/github-workflows/commits/$tag" --jq .sha
gh api "repos/theindiehacker/github-workflows/contents/.github/workflows/self-claude.yml?ref=$tag" --jq .content | base64 -d
```

```yaml
  code-review:
    if: (github.event_name == 'pull_request' && !github.event.pull_request.draft && !contains(github.event.pull_request.labels.*.name, 'claude:blocked')) || (github.event_name == 'issue_comment' && startsWith(github.event.comment.body, '/code-review'))
  security-review:
    if: (github.event_name == 'pull_request' && !github.event.pull_request.draft && !contains(github.event.pull_request.labels.*.name, 'claude:blocked')) || (github.event_name == 'issue_comment' && startsWith(github.event.comment.body, '/security-review'))
```

 - org の必須の zizmor は、変えたワークフローの `issue_comment` を落とします (`dangerous-triggers`)。`.github/zizmor.yml` の除外に、`claude.yml` の `issue_comment:` の行を `claude.yml:<行>` で書いてください (下)。既にあれば、行がずれていないか確かめて直します。このファイルの変更にはセキュリティチームの承認が要るので、PR が承認待ちになることをユーザーに伝えてください。

```yaml
# zizmor の設定。変えるときは、org のルールセット「✔️ セキュリティ設定変更の承認必須化」でセキュリティチームの承認が要る
rules:
  dangerous-triggers:
    ignore:
      # claude.yml の issue_comment は、コメントでの依頼 (/code-review・/security-review・@claude) に使う。
      # 呼び先 (theindiehacker/github-workflows の claude.yml・claude-code-review.yml・claude-security-review.yml) が、
      # 投稿者を author_association (OWNER / MEMBER / COLLABORATOR など) で絞っている
      - claude.yml:<issue_comment: の行>
```

 - push で `workflow` スコープが無いと出たら、ユーザーに `! gh auth refresh -h github.com -s workflow` を頼んでください。
3. ほかに claude-code-action を使うワークフローが PR で自動で動くと、レビューが二重になります。探して、自動の起動を止めるか確認してください。
   - 探し方: `grep -rlE 'anthropics/claude-code(-base)?-action' .github/workflows/`。他のワークフローを `uses:` で呼ぶもの (reusable workflow) は、呼び先も確かめます。2 の `claude.yml` は除きます。
   - 人が頼まなくても動くトリガー: PR のイベント (`pull_request` / `pull_request_target`。`types` が無ければ `opened`・`synchronize`・`reopened`) と、コメント・レビューのイベントのうち、`if:` で本文 (`/code-review`・`@claude` など) を絞っていないもの
   - 止めるなら、PR のイベントを `on:` から外し、本文を絞っていないコメントのトリガーは `if:` で絞ります。`on:` に何も残らなければ、ワークフローを消すか確認します。変えたら 2・3 と同じコミットに入れます。
   - org の必須ワークフロー (Rulesets) はリポジトリから止められません。下の 1 つ目のコマンドで出し、2 つ目で読んで確かめ、出たら org の管理者に止めてもらうよう伝えてください。読めなければ (404 など)、ユーザーに聞いてください。

```bash
gh api "repos/{owner/repo}/rules/branches/<デフォルトブランチ>" --jq '.[] | select(.type == "workflows") | .parameters.workflows[] | "\(.repository_id) \(.path) \(.ref)"'
gh api "repositories/<repository_id>/contents/<path>?ref=<ref>" --jq .content | base64 -d
```

## 6. epic ブランチの CI
Sub Issue の PR は epic ブランチ (`epic/<親 Issue>`) に向き、実装はコードレビューの Approve と CI の成功でマージします (`/dev:implement` の 7)。epic ブランチに向けた PR で CI が動かないと、実装はマージできずに人間に返します (デフォルトブランチに向けた PR で CI が動いているとき)。

1. `.github/workflows/` で、`pull_request` / `pull_request_target` の `branches` が epic ブランチに当たらない (デフォルトブランチだけなど) ワークフローを探してください。`branches` が無いものと、`branches-ignore` だけのものは、epic ブランチに向けた PR でも動きます。
2. 見つかったら見せて、`branches` に `epic/**` を足すか確認してください。足すなら、2・3 と同じコミットに入れてください。
3. 5 の 3 で org の必須ワークフローが出たら、Ruleset の対象ブランチに `epic/**` が無いと、epic ブランチに向けた PR では動かないことを伝えてください。足すかは org の管理者が決めます。

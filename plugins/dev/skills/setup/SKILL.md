---
name: setup
description: 対象リポジトリに組織推奨の開発スタックとラベル駆動開発 (ラベル・ルーティン・FastShip プラグイン) を導入し、コミット・PR 作成まで行う。導入済みなら最新版に更新する。使い方 → /dev:setup [owner/repo]
argument-hint: "[owner/repo]"
---

# セットアップ手順
## 1. ボイラープレートの導入
Organization のテンプレートリポジトリを対象リポジトリに導入してください。複数あればユーザーに確認し、無ければスキップしてください。

## 2. FastShip プラグインの設定 (ローカル)
対象リポジトリの `.claude/settings.json` に次をマージしてください。他のキーは残してください。

```json
{
  "extraKnownMarketplaces": {
    "fastship": {
      "source": {"source": "github", "repo": "theindiehacker/fastship-plugin"}
    }
  },
  "enabledPlugins": {
    "dev@fastship": true
  }
}
```

## 3. Issue / PR テンプレートの配置
FastShip プラグインのテンプレートを、対象リポジトリにコピーしてください。2 の設定と一緒にコミットします。コピーは GitHub の UI で Issue / PR を作るときに使われます。スキルはプラグインのテンプレートを直接読みます。

| コピー元 | コピー先 | 使う工程 |
|:--|:--|:--|
| `${CLAUDE_PLUGIN_ROOT}/templates/ISSUE_TEMPLATE/backlog.md` | `.github/ISSUE_TEMPLATE/backlog.md` | ① 起票 / ③ 課題分析 |
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
gh label create claude:implement --color d97757 --description "🧑‍💻 Sub Issue の実装を始める" --force -R {owner/repo}
gh label create claude:under-review --color d97757 --description "✔️ PR のレビューを始める" --force -R {owner/repo}
gh label create claude:blocked --color b60205 --description "❓ 人間の回答を待っている" --force -R {owner/repo}
```

### 4.2 ルーティン
RemoteTrigger ツールで次のルーティンを用意し、URL (`https://claude.ai/code/routines/{ID}`) をユーザーに伝えてください。

| 項目 | 値 |
|:--|:--|
| 名前 | `{リポジトリ名} / 実装` |
| リポジトリ | 対象リポジトリのみ |
| 環境 | 既存の ` / 実装` ルーティンと同じ (無ければユーザーに確認) |
| モデル | `claude-opus-5-5` |
| コネクタ | なし |
| 通知 | プッシュ通知のみ |
| トリガー | `issues.labeled` / `pull_request.labeled` で、Issue / PR のラベルに `claude:implement` を含む場合。PR は、PR で止めたときの再開に使う |
| プロンプト | 下記 |

```text
Issue / PR の内容を確認し、着手してください。

 - 最初に /dev:blocked の「1. 始める」を行ってください。判断できないことがあれば、推測で進めず /dev:blocked の「2. 止める」で人間に返してください
 - PR を作成/更新したら、`/code-review`, `/security-review` コメントを投稿し、Claude によるレビューを実施してください
 - Claude からレビューが投稿されたら、コメントを確認し、採否の判断・対応・返信まで行ってください
```

```mermaid
flowchart LR
    list["list"] --> exists{"名前が ' / 実装' で終わり<br/>sources の先頭が対象リポジトリ"}
    exists -->|ある| get["get"] --> update["update<br/>プロンプトとモデルだけ差し替える"]
    exists -->|ない| create["create"] --> clear["update<br/>コネクタを外し、プッシュ通知のみにする"] --> trigger["create_webhook_trigger"]
```

 - 既存の `update`: `get` した `job_config` を丸ごと送り、`ccr.events[0].data.message.content` と `ccr.session_context.model` だけを変える。トリガーは API から見えず重複に気づけないため、追加しない。0.3.0 以前に作ったルーティンには PR のトリガーが無いので、https://claude.ai/code/routines で確認し、無ければ手動で追加するよう案内する
 - `create`: `/schedule` スキルの書き方に従う。`cron_expression` / `run_once_at` は付けず、`session_context` に `"autofix_on_pr_create": true` を付ける
 - 新規の `update`: `{"clear_mcp_connections": true, "notifications": {"channel": {"email": false, "push": true, "slack": false}}}` を送る (`create` は接続済みのコネクタをすべて付けるため)
 - `create_webhook_trigger`: 下記の body を送る。PR 用に、`events` を `["pull_request.labeled"]`、`field` を `pull_request.labels` に変えた body も送る
 - RemoteTrigger や Claude GitHub App が使えない場合は、上の表の内容で https://claude.ai/code/routines から手動で作るよう案内する

```json
{
  "routine_trigger_id": "{作成したルーティンの ID}",
  "source": "github",
  "hook_type": "app",
  "scope_id": "{owner/repo}",
  "events": ["issues.labeled"],
  "filter": {"clauses": [{"field": "issue.labels", "op": "FILTER_OP_IN", "values": ["claude:implement"]}]}
}
```

### 4.3 クラウド環境
クラウドセッションは 2 の設定を読まないため、4.2 の環境の Setup script (claude.ai の環境設定画面) に次を追加するよう案内してください。

```bash
{
  claude plugin marketplace add anthropics/claude-plugins-official &&
  claude plugin marketplace add theindiehacker/fastship-plugin &&
  claude plugin install dev@fastship
} || echo "⚠️ dev@fastship を入れられませんでした" >&2
```

 - 1 行目は依存の `security-guidance` のためです。無いと `dev` が読み込まれません
 - Setup script は 0 以外で終わるとセッションが始まらないため、失敗しても警告だけ出します

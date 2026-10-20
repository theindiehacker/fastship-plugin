---
name: setup
description: 対象リポジトリに組織推奨の開発スタックを導入し、コミット・PR 作成まで行う。Issue のラベルで Claude Code on the web が動くラベル駆動開発 (ラベル・ルーティン・FastShip プラグイン) も用意する。導入済みのリポジトリでは最新版に更新する。使い方 → /dev:setup [owner/repo]
argument-hint: "[owner/repo]"
---

# セットアップ手順
## 1. ボイラープレートの導入
Organization アカウントにあるテンプレートリポジトリを確認し、対象リポジトリに導入してください。

 - テンプレートリポジトリが複数ある場合は、ユーザーに確認・提案してください。
 - テンプレートリポジトリがない場合はスキップしてください。

## 2. FastShip プラグインの設定
対象リポジトリの `.claude/settings.json` に次を追加してください。`extraKnownMarketplaces.fastship` と `enabledPlugins["dev@fastship"]` だけを追加・上書きし、他のキー (他のマーケットプレイス・プラグイン・hooks など) はそのまま残してください。ローカルの Claude Code で、フォルダを信頼するとプラグインのインストールを促されます。クラウドセッションはこの設定を読まないため、4.3 で入れます。

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
FastShip プラグインのテンプレートを、対象リポジトリにコピーしてください。2 の設定と一緒にコミットします。テンプレートの正本はプラグインにあり、各スキルはこの欄に沿って Issue / PR を読み書きします。

| コピー元 | コピー先 | 使う工程 |
|:--|:--|:--|
| `${CLAUDE_PLUGIN_ROOT}/templates/ISSUE_TEMPLATE/backlog.md` | `.github/ISSUE_TEMPLATE/backlog.md` | ① 起票 / ③ 課題分析 |
| `${CLAUDE_PLUGIN_ROOT}/templates/ISSUE_TEMPLATE/todo.md` | `.github/ISSUE_TEMPLATE/todo.md` | ⑥ リファインメント (Sub Issue) |
| `${CLAUDE_PLUGIN_ROOT}/templates/PULL_REQUEST_TEMPLATE.md` | `.github/PULL_REQUEST_TEMPLATE.md` | ⑧ PR 作成 |

 - 同じ名前のファイルは上書きしてください (最新版に更新するため)。それ以外のテンプレートは残してください。

## 4. ラベル駆動開発のセットアップ
Issue のラベルで Claude Code on the web のルーティンが動くように、ラベル・ルーティン・クラウド環境を用意してください。リポジトリへのコミットは伴いません。

### 4.1 ラベル
次のコマンドで 4 ラベルを作成してください (既にある場合は上書き)。

```bash
gh label create claude:analysis --color d97757 --description "🤔 課題分析を始める" --force -R {owner/repo}
gh label create claude:refine --color d97757 --description "✂️ 課題分析の結果を承認し、リファインメントを始める" --force -R {owner/repo}
gh label create claude:implement --color d97757 --description "🧑‍💻 Sub Issue の実装を始める" --force -R {owner/repo}
gh label create claude:blocked --color b60205 --description "❓ 人間の回答を待っている" --force -R {owner/repo}
```

### 4.2 ルーティン
RemoteTrigger ツールで、実行者の claude.ai アカウントに次のルーティンを用意してください。

| 項目 | 値 |
|:--|:--|
| 名前 | `{リポジトリ名} / 実装` |
| リポジトリ | 対象リポジトリのみ |
| 環境 | 既存の ` / 実装` ルーティンと同じ環境 (無ければユーザーに確認) |
| モデル | `claude-opus-5-5` |
| コネクタ | なし |
| 通知 | プッシュ通知のみ |
| トリガー | 対象リポジトリの Issue にラベルが付いたとき (`issues.labeled`)。Issue のラベルに `claude:implement` を含む場合だけ |
| プロンプト | 下記 |

```text
Issue の内容を確認し、着手してください。

 - 不明点や質問がある場合は着手する前にチャットで質問してください
 - PR を作成/更新したら、`/code-review`, `/security-review` コメントを投稿し、Claude によるレビューを実施してください
 - Claude からレビューが投稿されたら、コメントを確認し、採否の判断・対応・返信まで行ってください
```

1. `list` で既存のルーティンを探してください。名前が ` / 実装` で終わり、`job_config.ccr.session_context.sources` の先頭が対象リポジトリのものを既存とみなします (名前がリポジトリ名と違うものもあるため)。
2. 既存のルーティンがある場合は、`get` で取得した `job_config` のプロンプト (`ccr.events[0].data.message.content`) とモデル (`ccr.session_context.model`) だけを差し替えて `update` してください。`job_config` は一部だけ送らず、追加のリポジトリなど他の値も取得したまま送ってください。名前・コネクタ・トリガーは変えないでください。
3. 既存のルーティンがない場合は、次の順に作成してください。
   1. `create`: body の書き方は `/schedule` スキルに従う。ただし `cron_expression` / `run_once_at` は付けず、`session_context` に `"autofix_on_pr_create": true` を付ける (UI で作ったときの既定値)
   2. `update`: `{"clear_mcp_connections": true, "notifications": {"channel": {"email": false, "push": true, "slack": false}}}` を送る (`create` でコネクタを省くと、claude.ai に接続済みのコネクタがすべて付くため)
   3. `create_webhook_trigger`: 次の body で GitHub トリガーを追加する

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

 - 追加済みのトリガーは API から確認できず重複に気づけないため、既存のルーティンにはトリガーを追加しないでください。
 - RemoteTrigger が使えない場合 (claude.ai 以外でログインしているなど) や、Claude GitHub App が未インストールでトリガーを追加できない場合は、4.2 をスキップし、上の表の内容で https://claude.ai/code/routines から手動で作成するよう、ユーザーに案内してください。
 - 作成・更新したルーティンの URL (`https://claude.ai/code/routines/{ID}`) をユーザーに伝えてください。

### 4.3 クラウド環境
クラウドセッションはリポジトリの `enabledPlugins` からプラグインを入れません。4.2 のルーティンが使う環境の Setup script (claude.ai の環境設定画面) に次を追加するよう、ユーザーに案内してください。環境ごとに 1 回で済みます。

```bash
claude plugin marketplace add anthropics/claude-plugins-official || echo "⚠️ claude-plugins-official を追加できませんでした" >&2
claude plugin marketplace add theindiehacker/fastship-plugin || echo "⚠️ fastship を追加できませんでした" >&2
claude plugin install dev@fastship || echo "⚠️ dev@fastship を入れられませんでした" >&2
```

 - 1 行目は依存の `security-guidance@claude-plugins-official` を入れるためです。無いと `dev` が読み込まれません。
 - Setup script は 0 以外で終わるとセッションが始まらないため、失敗しても警告だけ出して続けます。
 - dev プラグインの SessionStart hook が、セッションの開始時に mise・ツール・lefthook のフックを入れます (`mise.toml` があるリポジトリのみ)。

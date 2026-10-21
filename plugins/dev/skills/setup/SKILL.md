---
name: setup
description: 対象リポジトリにラベル駆動開発 (ラベル・ルーティン・FastShip プラグイン・FastShip プロジェクト) を導入し、コミット・PR 作成まで行う。stack プラグインが入っていれば、技術スタックも入れるか聞く。Actions の Claude レビューが PR で自動で動くなら、止めるか聞く。導入済みなら最新版に更新する。使い方 → /dev:setup [owner/repo]
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
    "dev@fastship": true
  }
}
```

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
gh label create claude:under-review --color d97757 --description "✔️ PR のレビューを始める" --force -R {owner/repo}
gh label create claude:approved --color 0e8a16 --description "✅ レビューを通った" --force -R {owner/repo}
gh label create claude:blocked --color b60205 --description "❓ 人間の回答を待っている" --force -R {owner/repo}
gh label create claude:analyzed --color 0e8a16 --description "🧑‍💻 課題分析が終わり、承認を待っている" --force -R {owner/repo}
```

`claude:approved` / `claude:analyzed` は、人が見るためのラベルです。4.2 のトリガーには使いません。

0.13.0 以前に導入したリポジトリには、`claude:retrospective` / `claude:shipped` が残っています (下の 1 つ目のコマンドで出ます)。残っていれば、付いている Issue の数 (2 つ目のコマンド。100 で頭打ち) をユーザーに伝え、消してよいか確認してください。消すと、付いていた Issue からも外れます。消さないと答えたら残してください。

```bash
gh api --paginate "repos/{owner/repo}/labels?per_page=100" --jq '.[].name | select(. == "claude:retrospective" or . == "claude:shipped")'
gh api "repos/{owner/repo}/issues?labels=<ラベル>&state=all&per_page=100" --jq length
gh label delete <ラベル> --yes -R {owner/repo}
```

### 4.2 ルーティン
RemoteTrigger ツールで次のルーティンをそれぞれ用意し、URL (`https://claude.ai/code/routines/{ID}`) をユーザーに伝えてください。

| ルーティン | 名前 | トリガー |
|:--|:--|:--|
| 課題分析 | `{リポジトリ名} / 課題分析` | `issues.labeled` で、Issue のラベルに `claude:analysis` を含む場合 |
| リファインメント | `{リポジトリ名} / リファインメント` | `issues.labeled` で、Issue のラベルに `claude:refine` を含む場合。`issues.closed` で、Issue のラベルに `claude:implement` を含む場合。closed は、Sub Issue が閉じたときに後続の Sub Issue に着手するのに使う。1 PR で済むとしてそのまま実装した Issue が閉じたときも起動するが、何もせずに終わる |
| 実装 | `{リポジトリ名} / 実装` | `issues.labeled` / `pull_request.labeled` で、Issue / PR のラベルに `claude:implement` を含む場合。PR は、PR で止めたときの再開に使う |
| レビュー | `{リポジトリ名} / レビュー` | `pull_request.labeled` で、PR のラベルに `claude:under-review` を含む場合。実装は push を終えてからこのラベルを付けるため、`opened` / `synchronize` は使わない |

どのルーティンも次の設定にしてください。

| 項目 | 値 |
|:--|:--|
| リポジトリ | 対象リポジトリのみ |
| 環境 | 既存の ` / 課題分析` / ` / リファインメント` / ` / 実装` / ` / レビュー` ルーティンと同じ (無ければユーザーに確認) |
| モデル | `claude-opus-5-5` |
| ツール | claude.ai の既定 (`session_context.allowed_tools` を `["preset:default"]` にする) |
| コネクタ | なし |
| 通知 | プッシュ通知のみ |
| プロンプト | 下記 |

課題分析:

```text
Issue の課題分析を /dev:analysis で行ってください。
```

リファインメント:

```text
Issue のリファインメントを /dev:refine で行ってください。
```

実装:

```text
Issue / PR の実装を /dev:implement で行ってください。
```

レビュー:

```text
PR のレビューを /dev:review で行ってください。
```

```mermaid
flowchart LR
    list["list"] --> exists{"名前が ' / {ルーティン}' で終わり<br/>sources の先頭が対象リポジトリ"}
    exists -->|ある| get["get"] --> update["update<br/>プロンプトとモデルだけ差し替える"]
    exists -->|ない| more{"has_more"}
    more -->|true| ask["ユーザーに確認"]
    ask -->|ある| get
    ask -->|ない| create
    more -->|false| create["create"] --> clear["update<br/>コネクタを外し、プッシュ通知のみにする"] --> trigger["create_webhook_trigger"]
```

 - `list`: 返るのは 20 件までで、続きは取れない (`next_cursor` を渡しても同じページが返る)。`has_more` が true のときに見つからないルーティンは、無いとみなさない (重複して作らないため)。https://claude.ai/code/routines に `{リポジトリ名} / {工程}` があるかユーザーに確認し、あれば URL の `trig_…` で `get` する。無ければ `create` する
 - 既存の `update`: `get` した `job_config` を丸ごと送り、`ccr.events[0].data.message.content` と `ccr.session_context.model` だけを変える。トリガーは API から見えず重複に気づけないため、追加しない。次のルーティンには PR のトリガーが無いので、https://claude.ai/code/routines で確認し、無ければ手動で追加するよう案内する
   - 0.3.0 以前に作った実装のルーティン
   - 0.12.1 以前に作った実装・レビューのルーティン (PR のトリガーの field を誤っていて、作れなかった)
 - `create`: `/schedule` スキルの書き方に従う。`run_once_at` と `cron_expression` は付けない。実装は PR を作るので、`session_context` に `"autofix_on_pr_create": true` を付ける
 - 新規の `update`: `{"clear_mcp_connections": true, "notifications": {"channel": {"email": false, "push": true, "slack": false}}}` を送る (`create` は接続済みのコネクタをすべて付けるため)
 - `create_webhook_trigger`: 下記の body を、`{ラベル}` をトリガーのラベルに置き換えて送る。実装は PR 用に、`events` を `["pull_request.labeled"]`、`field` を `pr.labels` に変えた body も送る。レビューは `events` を `["pull_request.labeled"]`、`field` を `pr.labels`、`{ラベル}` を `claude:under-review` にした body だけを送る。PR のラベルの field は `pr.labels` で、`pull_request.labels` は `unknown field` で拒否される。リファインメントは Sub Issue の完了用に、`events` を `["issues.closed"]`、`{ラベル}` を `claude:implement` にした body も送る (実装は `claude:implement` を閉じるまで外さないため、実装した Sub Issue / Issue だけに絞れる)
 - `list` で ` / 振り返り` のルーティン (0.13.0 以前に作ったもの) が見つかったら、https://claude.ai/code/routines で消すようユーザーに案内する。振り返りは 0.14.0 で外した。`has_more` が true なら、あるかもしれないと伝える
 - RemoteTrigger や Claude GitHub App が使えない場合は、上の表の内容で https://claude.ai/code/routines から手動で作るよう案内する

ルーティンの URL と一緒に、次の前提をユーザーに伝えてください (README の「🛟 ルーティンの前提」)。
 - ルーティンは、作った人の claude.ai アカウントに属し、チームでは共有されない。作った人の利用枠を使い、その人が抜けると止まる。そのときは、別の人が `/dev:setup` を実行し直して作り直す
 - `issues.labeled`・`issues.closed` のトリガーは、ルーティンのドキュメントに無い (載っている GitHub イベントは Pull request と Release だけ)
 - GitHub イベントは、毎時の上限を超えると捨てられる (上限の数値は公開されていない)
 - 動かなかった・途中で止まった Issue / PR は、進行中のラベルが付いたまま 4.4 の `⏳ 進行中` に残る。10 分以上進まないものは、ラベルを外して付け直す

```json
{
  "routine_trigger_id": "{作成したルーティンの ID}",
  "source": "github",
  "hook_type": "app",
  "scope_id": "{owner/repo}",
  "events": ["issues.labeled"],
  "filter": {"clauses": [{"field": "issue.labels", "op": "FILTER_OP_IN", "values": ["{ラベル}"]}]}
}
```

### 4.3 クラウド環境
クラウドセッションは 2 の設定を読まないため、4.2 の環境の Setup script (claude.ai の環境設定画面) に次を追加するよう案内してください。環境の名前と、スクショ付きの手順 https://github.com/theindiehacker/fastship-plugin#3-クラウド環境 を伝えます。README にも同じスクリプトがあるため、変えるときは両方を直してください。

```bash
{
  claude plugin marketplace add anthropics/claude-plugins-official &&
  claude plugin marketplace add theindiehacker/fastship-plugin &&
  claude plugin install dev@fastship
} || echo "⚠️ dev@fastship を入れられませんでした" >&2
```

 - 1 行目は依存 (`security-guidance`。stack なら `context7`・`pyright-lsp` も) のためです。無いと `dev` が読み込まれません
 - Setup script は 0 以外で終わるとセッションが始まらないため、失敗しても警告だけ出します
 - 1 で `/stack:setup` を行ったら、次の行も足すよう案内してください。stack は dev と一緒には入りません。環境は他のリポジトリと共有しますが、stack の hook は道具と設定 (`mise.toml`・lock ファイル・`node_modules` の Biome・`.venv` の Ruff など) が無いリポジトリでは何もしません

```bash
claude plugin install stack@fastship || echo "⚠️ stack@fastship を入れられませんでした" >&2
```

### 4.4 FastShip プロジェクト
対象リポジトリを、owner の FastShip プロジェクト (GitHub Project) につなぎます。開発者は、プロジェクトのビューで次に判断することを確かめます。テンプレートは https://github.com/orgs/theindiehacker/projects/6 です。

```mermaid
flowchart LR
    find{"1. owner に<br/>FastShip プロジェクトがある"} -->|ない| copy["2. テンプレートからコピー"] --> views
    find -->|ある| views["3. ビューを揃える"] --> link["4. リポジトリをリンク"] --> auto["5. Auto-add を設定<br/>(ユーザーが UI で)"] --> add["6. 既存の Issue / PR を追加"]
```

 - 4.4 は GraphQL と、owner の Projects の API を使います。下のコマンドが失敗したら (claude.ai/code では 403 になります)、4.4 は行わず、README の「setup を使わずにつなぐ」を案内してください。その際、owner に `FastShip プロジェクト` が既にあるかを先に確かめるよう伝えてください。重複して作らないためです。

```bash
gh api graphql -f query='{ viewer { login } }' --jq .data.viewer.login
```

 - `gh auth status` の Token scopes に `project` が無ければ、`! gh auth refresh -s project` を実行するよう案内してください。
 - コマンドの `<owner>` は対象リポジトリの owner、`<n>` はプロジェクトの番号です。`<kind>` は、owner が org なら `orgs`、ユーザーなら `users` です (`gh api users/<owner> --jq .type` が `Organization` なら org)。ユーザーのビューを作る API は、ドキュメントではパスが数値の user_id ですが、login で動き、user_id では 404 になることを確かめています。

1. owner のプロジェクトから、タイトルが `FastShip プロジェクト` で、テンプレートではないものを探してください。`query` で絞らないのは、絞ると closed のプロジェクトが出ないためです。
   - 1 つなら、それを使います。`closed=true` なら、再開してよいかユーザーに確認し、`gh project close <n> --owner <owner> --undo` で再開してください。
   - 複数あれば、どれを使うかユーザーに確認してください。
   - 何も出なければ、2 でコピーします。コマンドがエラーになったときは、無いとはみなさずに止めてください。重複して作らないためです。

```bash
gh api graphql --paginate -f login=<owner> -f query='query($login: String!, $endCursor: String) { repositoryOwner(login: $login) { ... on ProjectV2Owner { projectsV2(first: 100, after: $endCursor) { pageInfo { hasNextPage endCursor } nodes { number title template closed url } } } } }' \
  --jq '.data.repositoryOwner.projectsV2.nodes[] | select(.title == "FastShip プロジェクト" and (.template | not)) | "\(.number) closed=\(.closed) \(.url)"'
```

2. テンプレートをコピーしてください。ビューと組み込みのワークフロー (Auto-add を除く) が入り、private になります。失敗したら、README の「📋 FastShip プロジェクト」にある手動の手順を案内して、4.4 を終えてください。

```bash
gh project copy 6 --source-owner theindiehacker --target-owner <owner> --title "FastShip プロジェクト" --format json --jq '"\(.number) \(.url)"'
```

3. 下の表のビューがあるかを、名前とフィルタで確かめてください (下の 1 つ目のコマンド)。
   - 無いビューだけ作ってください (3 つ目のコマンド)。`visible_fields` には列の id を入れます。id は 2 つ目のコマンドで、列の名前から引いてください。
   - 同じ名前でフィルタが違えば作らず、UI で直すようユーザーに伝えてください。ビューは API で更新・削除できず、作ると重複が残るためです。
   - `⑫ 成功指標の確認待ち` (0.13.0 以前のビュー) があれば、UI で消すようユーザーに伝えてください。

| ビュー | フィルタ | 列 |
|:--|:--|:--|
| `④ 承認待ち` | `is:issue is:open label:"claude:analyzed"` | Title / Repository / Labels |
| `❓ 回答待ち` | `is:open label:"claude:blocked"` | Title / Repository / Labels / Parent issue |
| `⑪ マージ待ち` | `is:pr is:open label:"claude:approved" -label:"claude:blocked" -label:"claude:under-review"` | Title / Repository / Labels |
| `⏳ 進行中` | `is:open label:"claude:analysis","claude:refine","claude:implement","claude:under-review"` | Title / Repository / Labels |

```bash
gh api graphql -f login=<owner> -F n=<n> -f query='query($login: String!, $n: Int!) { repositoryOwner(login: $login) { ... on ProjectV2Owner { projectV2(number: $n) { views(first: 50) { nodes { name filter } } } } } }' \
  --jq '.data.repositoryOwner.projectV2.views.nodes[] | "\(.name) [\(.filter)]"'
gh api --paginate "<kind>/<owner>/projectsV2/<n>/fields?per_page=100" --jq '.[] | "\(.id) \(.name)"'
jq -n --arg name "<ビュー>" --arg filter '<フィルタ>' '{name:$name, layout:"table", filter:$filter, visible_fields:[<列の id>]}' \
  | gh api --method POST "<kind>/<owner>/projectsV2/<n>/views" --input - --jq .number
```

4. リポジトリをリンクしてください。リポジトリの Projects タブに出るようになります。リンク済みでも問題ありません。

```bash
gh project link <n> --owner <owner> --repo {owner/repo}
```

5. Auto-add workflow は API で作れないため、ユーザーに UI で設定してもらい、終わったと答えてもらってください。下のラベルが付いた Issue / PR が、プロジェクトに自動で入るようになります。手順は文章で説明せず、次の 2 つだけを伝えてください。
   - Workflows の URL: `https://github.com/<kind>/<owner>/projects/<n>/workflows`
   - スクショ付きの手順: https://github.com/theindiehacker/fastship-plugin#4-auto-add
   - Auto-add workflow はリポジトリごとに 1 つ要り、数にはプランごとの上限があります (Free 1 / Pro・Team 5 / Enterprise 20)。リンク済みのリポジトリ (下のコマンド) が上限より多ければ、ユーザーに伝えてください。

```bash
gh api graphql -f login=<owner> -F n=<n> -f query='query($login: String!, $n: Int!) { repositoryOwner(login: $login) { ... on ProjectV2Owner { projectV2(number: $n) { repositories(first: 100) { totalCount nodes { nameWithOwner } } } } } }' \
  --jq '.data.repositoryOwner.projectV2.repositories | "\(.totalCount): \([.nodes[].nameWithOwner] | join(" "))"'
```

6. 5 が終わったら、claude ラベルが付いた open の Issue / PR を追加してください。Auto-add は、有効にする前からある Issue / PR を入れないためです。5 より先に行うと、間にラベルが付いたものが漏れます。何度実行しても重複しません。プロジェクトの一覧に出るまで、1〜2 分かかることがあります。

```bash
gh api --paginate "repos/{owner/repo}/issues?state=open&per_page=100" \
  --jq '.[] | select([.labels[].name] | any(startswith("claude:"))) | .html_url' \
  | while read -r url; do gh project item-add <n> --owner <owner> --url "$url" > /dev/null; done
```

7. プロジェクトの URL をユーザーに伝えてください。

## 5. Actions の Claude レビュー
FastShip の PR は ⑨ がレビューします。PR のイベントで Actions の Claude レビュー (claude-code-action) が自動で動くと、レビューが二重になり、GitHub Actions の時間も使います。FastShip の Claude の作業はルーティン (サブスク) で動かすため、Actions の Claude は人が頼んだときだけ動くようにします。

1. claude-code-action を使うワークフローを探してください。他のワークフローを `uses:` で呼ぶもの (reusable workflow) は、呼び先も確かめてください。

```bash
grep -rlE 'anthropics/claude-code(-base)?-action' .github/workflows/
```

2. 見つかったワークフローの `on:` から、人が頼まなくても動くトリガーを洗い出してください。
   - PR のイベント (`pull_request` / `pull_request_target`)。`types` の `opened`・`ready_for_review`・`synchronize`・`reopened`・`labeled` など、どれもまとめて確かめます。`types` が無ければ `opened`・`synchronize`・`reopened` で動きます。
   - コメント・レビューのイベント (`issue_comment` / `pull_request_review_comment` / `pull_request_review`) のうち、`if:` で本文 (`/code-review`・`@claude` など) を絞っていないもの。⑨ のレビューや実装の返信でも動きます。
3. 2 で出たら、ワークフローとトリガーを見せ、⑨ と二重になり Actions の時間を使うことを伝えて、自動の起動を止めるか確認してください。
   - 止めるなら、PR のイベントを `on:` から外してください。本文を絞っていないコメントのトリガーは、`if:` で本文を絞ってください。コメントでの依頼 (`/code-review` など) は残します。
   - `on:` に何も残らなければ、ワークフローを消すか確認してください。
   - 止めないと答えたら残し、FastShip の PR でも二重に動くことを伝えてください。
   - 変えたら、2・3 と同じコミットに入れてください。
4. org の必須ワークフロー (Rulesets) に claude-code-action があれば、リポジトリからは止められません。下の 1 つ目のコマンドで必須ワークフローを出し、2 つ目で読んで 2 と同じように確かめてください。出たら、org の管理者に止めてもらうよう伝えてください。読めなければ (404 など)、ユーザーに聞いてください。

```bash
gh api "repos/{owner/repo}/rules/branches/<デフォルトブランチ>" --jq '.[] | select(.type == "workflows") | .parameters.workflows[] | "\(.repository_id) \(.path) \(.ref)"'
gh api "repositories/<repository_id>/contents/<path>?ref=<ref>" --jq .content | base64 -d
```

# 🚀 fastship plugin
Organization 共通の Claude Code プラグインのマーケットプレイス（`fastship`）。プラグインの開発方法は [CONTRIBUTING.md](./CONTRIBUTING.md) を参照。

CI / Lefthook / Taskfile などの共通設定は [theindiehacker/devops](https://github.com/theindiehacker/devops) で管理している。

| プラグイン | 内容 |
|:--|:--|
| `dev` | 開発ワークフロー（`/dev:setup`・`/dev:issue`・`/dev:push-pr`）と hooks |
| `ruleset` | 実装ルール。対象ファイルを扱うときに `paths` 付き skill として自動で読み込まれる |

`dev` の hooks は次のことを行う。

| hook | 内容 |
|:--|:--|
| PreToolUse | `.env` と `.env.*` を読み書きさせない |
| Stop | 変更があれば、Taskfile にある `style:check`・`security:check`・`test` を実行し、通らなければ Claude に直させる |

> ⚠️ Claude Code on the web ではプラグインが入らないため、hooks も動かない。

## 🧰 Install
```
/plugin marketplace add https://github.com/theindiehacker/fastship-plugin.git
/plugin install security-guidance@claude-plugins-official
/plugin install dev@fastship  # 依存する ruleset@fastship も有効になる
```

<details><summary><b>devops のマーケットプレイスを追加済みの場合</b></summary>

マーケットプレイス名は同じ `fastship` のため、削除してから追加し直す。

```
/plugin marketplace remove fastship
/plugin marketplace add https://github.com/theindiehacker/fastship-plugin.git
/plugin install dev@fastship
```

</details>

## 🔄 Update
マーケットプレイスを最新化してから、インストール済みプラグインを更新する。

```
/plugin marketplace update fastship
```

以降、`/plugin` コマンドからプラグイン一覧・更新状況を確認できる。

---
name: ui
description: shadcn/ui と Tailwind CSS で画面を作る・直すときの書き方。UI コンポーネントは shadcn/ui を使い、shadcn の MCP で探して例を見て、CLI で追加する。使い方は shadcn docs と Context7 で版に合ったものを確かめる。Tailwind CSS v4 は CSS の @theme で設定する。React のコンポーネント・className・globals.css・components.json を書く・直すときに使う。
---

# 🎨 UI (shadcn/ui・Tailwind CSS)

shadcn/ui を入れたパッケージ (`components.json` がある) では、UI コンポーネントは shadcn/ui を使ってください。ボタン・フォーム・ダイアログなどを自作したり、別の UI ライブラリ (MUI・Chakra UI など) を足したりしないでください。shadcn/ui に無いものだけ、shadcn/ui のコンポーネントを組み合わせて作ります。

shadcn/ui・Tailwind CSS・Base UI は版ごとに書き方が変わり、学習データの書き方は古いことがあります。書く前に、リポジトリの版と、その版のドキュメントを確かめてください。

## shadcn/ui
探す・例を見るのは、このプラグインが配る shadcn の MCP で、追加は CLI で行います。MCP が使えなければ (`components.json` がまだ無い・bun が無い・古いなどで起動しない)、CLI の `search`・`view` で代わりにします。

| やること | 使うもの |
|:--|:--|
| 使えるコンポーネントを探す | MCP の `search_items_in_registries` |
| 使い方の例 (`button-demo` など) を見る | MCP の `get_item_examples_from_registries` |
| 中身 (ファイル・依存) を見る | MCP の `view_items_in_registries` |
| 追加する | `bun shadcn add <名前>` |
| 追加・作成の後に確かめる | MCP の `get_audit_checklist` |
| プロジェクトの設定 (style・base・Tailwind の版) を見る | `bun shadcn info` |
| コンポーネントの API を見る | `bun shadcn docs <名前>` |

 - MCP の検索・一覧には、`registries` に `["@shadcn"]` を渡してください。省くと「No registries are configured」で失敗します。`components.json` に独自のレジストリがあれば、それも足します。MCP は、最初に見つけた shadcn/ui の `components.json` の dir で動きます。別のパッケージの `components.json` のレジストリは、そのファイルの `registries` を読んでください。
 - コマンドは `components.json` のある dir で実行してください。`package.json` に `shadcn` があれば `bun shadcn`、無ければ `bash "${CLAUDE_PLUGIN_ROOT}/scripts/shadcn.sh" latest` を使います (上の例は `bun shadcn`)。このスクリプトは、公開から 7 日たった最新の版で動かします。bun が 1.4.4 より古いと、7 日待てないので止まります。bun を使わないリポジトリでは、`npx --before="$(node -p 'new Date(Date.now() - 7 * 864e5).toISOString()')" shadcn@latest` を使います (7 日前までに公開された最新の版)。MCP が使えなければ、同じ CLI の `search @shadcn -q <キーワード>` で探します。`package.json` の `shadcn` が古くて `search`・`docs` が無ければ、`shadcn.sh` の方を使います。
 - MCP の `get_add_command_for_items` のコマンドは、そのまま使わないでください。リポジトリ直下の lock ファイルで道具を選び (`npx` になると hook が止めます)、版も `@latest` のためです。
 - コンポーネントは手で書かず、`add` で追加してください。既にあるものは作り直さずに使ってください。
 - Biome を入れたパッケージでは、`add` の後に、CLI が書いたファイル (`hooks` など) だけを `bun biome check --write <ファイル>` で整形してください。CLI が書いたファイルは、編集の hook では整形されないためです。パッケージ全体は整形しません (関係の無い差分が入るため)。`bunx biome` は使わないでください。Biome が入っていないと、npm の別のパッケージ `biome` が動きます。
 - 追加したファイル (`components.json` の `aliases.ui`、例: `src/components/ui`) は CLI の生成物です。見た目は使う側の `className` かテーマ (CSS 変数) で変え、生成物を書き換えるのはそれで足りないときだけにしてください。
 - base は Radix UI と Base UI があり、props が違います (例: 要素の差し替えは Radix UI が `asChild`、Base UI が `render`)。`info` で base を確かめ、`docs` の書き方に合わせてください。

## Tailwind CSS
`package.json` の `tailwindcss` の版を確かめてください。v4 では次のように書きます。

 - 設定は CSS に書きます (`@import "tailwindcss";`、`@theme { ... }`)。`tailwind.config.js` は作らないでください。
 - 色や角丸は、テーマの変数 (`bg-background`・`text-muted-foreground`・`border-border` など) を使ってください。`#fff` などの値を直接書かないでください。
 - v3 から名前が変わったユーティリティがあります (例: `shadow-sm` → `shadow-xs`、`rounded-sm` → `rounded-xs`、`outline-none` → `outline-hidden`)。

## ドキュメントを調べる
shadcn の `docs` で足りないとき (Tailwind CSS・Base UI・Radix UI など) は、Context7 で `package.json` の版のドキュメントを引いてください。

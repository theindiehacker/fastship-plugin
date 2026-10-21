---
name: ui
description: shadcn/ui と Tailwind CSS で画面を作る・直すときの書き方。コンポーネントは shadcn の CLI で追加し、使い方は shadcn docs と Context7 で版に合ったものを確かめる。Tailwind CSS v4 は CSS の @theme で設定する。React のコンポーネント・className・globals.css・components.json を書く・直すときに使う。
---

# 🎨 UI (shadcn/ui・Tailwind CSS)

shadcn/ui・Tailwind CSS・Base UI は版ごとに書き方が変わり、学習データの書き方は古いことがあります。書く前に、リポジトリの版と、その版のドキュメントを確かめてください。

## shadcn/ui
コマンドは `components.json` のある dir で実行してください。`package.json` に `shadcn` があれば `bun shadcn`、無ければ `bunx --bun shadcn@latest` を使います (下の例は `bun shadcn`)。

| やること | コマンド |
|:--|:--|
| プロジェクトの設定 (style・base・Tailwind の版) を見る | `bun shadcn info` |
| 使えるコンポーネントを探す | `bun shadcn search -q <キーワード>` |
| コンポーネントの使い方・API を見る | `bun shadcn docs <名前>` |
| コンポーネントを追加する | `bun shadcn add <名前>` |

 - コンポーネントは手で書かず、`add` で追加してください。既にあるものは作り直さずに使ってください。
 - 追加したファイル (`components.json` の `aliases.ui`、例: `src/components/ui`) は CLI の生成物です。見た目は使う側の `className` かテーマ (CSS 変数) で変え、生成物を書き換えるのはそれで足りないときだけにしてください。
 - base は Radix UI と Base UI があり、props が違います (例: 要素の差し替えは Radix UI が `asChild`、Base UI が `render`)。`info` で base を確かめ、`docs` の書き方に合わせてください。

## Tailwind CSS
`package.json` の `tailwindcss` の版を確かめてください。v4 では次のように書きます。

 - 設定は CSS に書きます (`@import "tailwindcss";`、`@theme { ... }`)。`tailwind.config.js` は作らないでください。
 - 色や角丸は、テーマの変数 (`bg-background`・`text-muted-foreground`・`border-border` など) を使ってください。`#fff` などの値を直接書かないでください。
 - v3 から名前が変わったユーティリティがあります (例: `shadow-sm` → `shadow-xs`、`rounded-sm` → `rounded-xs`、`outline-none` → `outline-hidden`)。

## ドキュメントを調べる
shadcn の `docs` で足りないとき (Tailwind CSS・Base UI・Radix UI など) は、Context7 で `package.json` の版のドキュメントを引いてください。

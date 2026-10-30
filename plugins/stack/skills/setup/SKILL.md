---
name: setup
description: 対象リポジトリに技術スタック (bun / Biome・uv / Ruff / Pyright・lefthook・shadcn/ui) の設定を入れる。既にある設定と違うときは、差分を見せて確認してから置き換える。org の必須ワークフローが求めるもの (knip など) があれば足す。/dev:setup から使う。使い方 → /stack:setup
---

# 🧰 技術スタックの導入

stack プラグインの hook (整形・lint・型チェック) は、ここで入れる道具と設定を使います。雛形は `${CLAUDE_PLUGIN_ROOT}/templates/` にあります。ここで入れる道具の版は、導入するときの最新に固定してください。shadcn の init がアプリに足す依存は、init のとおり (caret) にし、lock で固定します。

## 1. 調べる
 - パッケージの dir を洗い出してください。JavaScript / TypeScript は `package.json` のある dir、Python は `pyproject.toml` (または `requirements.txt`・`setup.py`) のある dir です。`node_modules` などの生成物は除きます。
 - 次の置き換えが要るかを確かめ、要るものを一覧にしてユーザーに確認してください。置き換えないと決めたものは、そのまま残します。

| 今あるもの | 置き換え先 |
|:--|:--|
| npm・yarn・pnpm (`package-lock.json`・`yarn.lock`・`pnpm-lock.yaml`) | bun |
| ESLint・Prettier (`eslint.config.*`・`.eslintrc*`・`.prettierrc*`) | Biome |
| pip・Poetry (`requirements.txt`・`poetry.lock`) | uv |
| flake8・black・isort | Ruff |
| mypy (`[tool.mypy]`・`mypy.ini`) | Pyright |
| husky・pre-commit (`.husky/`・`.pre-commit-config.yaml`) | lefthook |

## 2. mise
`mise.toml` に `templates/mise.toml` をマージしてください。既にあるツールと設定は残します。

 - `"latest"` は `mise latest <ツール>` の版に置き換えてください。
 - 使わない言語のツールは消してください。JavaScript / TypeScript が無ければ bun・node です。uv は Python が無くても残します (session の semgrep が uvx で動くため)。node は、Biome・tsc の起動スクリプト (`node_modules/.bin`) を動かすために要ります。無いと、node を入れていないマシンで hook と lefthook が止まります。
 - gitleaks・trivy・uv は、`/dev:setup` が session プラグインのために `mise.toml` に入れます。消さないでください。
 - 既にある bun が 1.4.4 より古ければ、`mise latest bun` の版に上げてください。shadcn の MCP と CLI (`scripts/shadcn.sh`) は、公開から 7 日待つ設定 (bun 1.4.4 から) が効かない bun では止まります。
 - `mise install` の後、`mise lock` で `mise.lock` を作ってください。Claude Code on the web は lock の URL からツールを入れます。

## 3. JavaScript / TypeScript (パッケージの dir ごと)
1. bun に置き換えるなら、`bun install` で `bun.lock` を作り、元の lock ファイルを消してください。
2. React の Web アプリ (Next.js・Vite・React Router など。React Native・Expo とライブラリは除く) で `components.json` が無ければ、shadcn/ui を入れるかユーザーに聞いてください。UI コンポーネントは shadcn/ui に揃えます。
   - 別の UI ライブラリ (MUI・Chakra UI・Ant Design など) を使っていれば、入れません。置き換えは差分が大きいため、別の PR にすると伝えてください。
   - 既にある画面があれば、見た目が変わることも伝えてください。init はテーマと基本のスタイルを書き換えます。Tailwind CSS を新しく入れるなら、そのリセット (Preflight) でも変わります。
   - 入れるなら、`bash "${CLAUDE_PLUGIN_ROOT}/scripts/shadcn.sh" latest init -d` を実行してください。公開から 7 日たった最新の版で動かします。bun が 1.4.4 より古いと止まるので、「2. mise」で上げてください。Tailwind CSS か import alias が無いと止まるので、メッセージに従って入れてから実行し直します。
   - init が足した依存は消さないでください。`shadcn add` は、コンポーネントが使う依存 (`lucide-react` など) を足し直しません。
3. `bun add -d --exact @biomejs/biome` で Biome を入れ、`templates/biome.json` を `biome.json` に置いてください。
   - `files.includes` の `!src/components/ui` は、`components.json` の `aliases.ui` のパスに合わせてください。shadcn/ui を使っていなければ消します。生成したコード (API クライアントなど) の dir があれば、同じように除外してください。
   - その dir に `.gitignore` が無いと Biome が止まります。`vcs.root` にリポジトリ直下への相対パス (例: `"../"`) を書いてください。
   - 2 で shadcn/ui を入れたら、init が書いたファイル (`lib/utils.ts`・CSS など) だけを、ここで入れた Biome で整形してください (`bun biome check --write <ファイル>`)。CLI が書いたファイルは、編集の hook では整形されず、そのままだと lefthook と Stop の検査で止まります。
4. ESLint・Prettier を置き換えるなら、`bun biome migrate eslint --write` と `bun biome migrate prettier --write` で設定を移してから、`bun remove` で外し、設定ファイルを消してください。
5. `package.json` の `scripts` に `"lint": "biome check"` と `"format": "biome check --write"` を足してください。
6. TypeScript のパッケージで `typescript` が devDependencies に無ければ、`bun add -d --exact typescript` で入れてください。hook と lefthook の tsc が使います。

## 4. Python (パッケージの dir ごと)
1. uv に置き換えるなら、Poetry は `uvx migrate-to-uv`、`requirements.txt` は `uv init --bare` と `uv add -r requirements.txt` で移してください。
2. `uv add --dev ruff "pyright[nodejs]"` で入れ、`templates/pyproject.toml` の `[tool.ruff]`・`[tool.pyright]` を `pyproject.toml` にマージしてください。
3. 置き換える道具 (mypy・flake8・black・isort) は、`uv remove --dev` で外し、設定 (`[tool.mypy]` など) を消してください。

## 5. lefthook
`templates/lefthook.yml` を `lefthook.yml` に置いてください。

 - 各ジョブの `root` を 1 のパッケージの dir に書き換えてください。dir が複数あれば、ジョブを dir ごとに複製します。使わない言語のジョブは消します。
 - 既に `lefthook.yml` があれば、ジョブを足してください。husky・pre-commit を置き換えるなら、その設定を消します。
 - `mise install` (postinstall の `lefthook install`) で、git のフックが入ります。

## 6. org の必須ワークフロー
org の Rulesets に必須ワークフローがあれば、それが対象リポジトリに求めるもの (devDependencies など) を足してください。無いと PR をマージできないことがあります。

1 つ目のコマンドで、デフォルトブランチにかかる必須ワークフローが出ます。何も出なければ 6 は飛ばしてください。出たら、2 つ目のコマンドでそれぞれを読み、求めるものを確かめます。読めなければ (404 など)、ユーザーに聞いてください。

```bash
gh api "repos/{owner/repo}/rules/branches/<デフォルトブランチ>" --jq '.[] | select(.type == "workflows") | .parameters.workflows[] | "\(.repository_id) \(.path) \(.ref)"'
gh api "repositories/<repository_id>/contents/<path>?ref=<ref>" --jq .content | base64 -d
```

 - 例: theindiehacker の `🔷 typescript` は、`bun.lock` と、devDependencies の `biome`・`knip`・`typescript` を求めます。knip (使っていない依存を見つける) は `bun add -d --exact knip` で入れます。

## 7. 確かめる
knip があり shadcn/ui も入れたパッケージ (`components.json`) では、先に knip の設定を足してください。生成物を、使っていないと出さないためです。

 - `entry` に `aliases.ui` の dir の glob (例: `src/components/ui/**/*.tsx`)
 - `ignore` に `aliases.utils` のファイル (例: `src/lib/utils.ts`)
 - `ignoreDependencies` に `iconLibrary` のパッケージ (`lucide-react` など)
 - `entry` を初めて書くときは、knip の既定の entry (`src/index.ts` など) も一緒に書く。書くと既定が使われなくなるため

各パッケージの dir で次を実行し、結果をユーザーに伝えてください。

```bash
bun biome check .
bun tsc --noEmit
bun run knip --dependencies  # knip があるとき
uv run ruff check
uv run ruff format --check
uv run pyright
```

 - 既にあるコードのエラーは、ここでは直さないでください。差分が大きくなり、レビューできなくなるためです。件数を伝え、別の PR で直すか確認してください。
 - hook と lefthook は変えたファイルだけを確かめるため、変えていないファイルのエラーでは止まりません。ただし lefthook の tsc はプロジェクト全体を確かめるため、tsc のエラーが既にあるとコミットできません。そのときは tsc のジョブを外し、エラーを直す PR で戻してください。
 - 変更は、`/dev:setup` の 2・3 と一緒にコミットしてください。

#!/usr/bin/env bash
# bun・uv を使うリポジトリで、Claude が npm・pip などを実行しようとしたら止めて、bun・uv での書き方を返す。
# stack プラグインの PreToolUse hook (hooks/hooks.json) から実行する。exit 2 で止めると、stderr が Claude に返る
set -uo pipefail

command -v jq > /dev/null || exit 0
cmd=$(jq -r '.tool_input.command // empty')
[ -n "$cmd" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

# コマンドの先頭か、; & | ( の後に書いたものだけを見る (uv pip や、git commit -m "npm ..." は止めない)
runs() { # <コマンド名の正規表現>
  grep -Eq "(^|[;&|(])[[:space:]]*($1)([[:space:]]|$)" <<< "$cmd"
}

has_lock() { # <パターン>...
  [ -n "$(git ls-files -- "$@" 2>/dev/null | head -n 1)" ]
}

if has_lock '*bun.lock' '*bun.lockb' && runs 'npm|npx|yarn|pnpm|pnpx'; then
  cat >&2 << 'EOF'
このリポジトリは bun を使います。npm・npx・yarn・pnpm ではなく、次のように bun で実行してください。
 - npm install → bun install (lock どおりに入れるなら bun install --frozen-lockfile)
 - npm install <パッケージ> → bun add <パッケージ> (開発用は bun add -d)
 - npm run <スクリプト> → bun run <スクリプト>
 - npx <コマンド> → bunx <コマンド>。パッケージに入っている道具 (biome・tsc など) は bun <コマンド> (bunx は、入っていないと npm の同じ名前の別のパッケージを動かすため)
 - npx shadcn → /stack:ui の scripts/shadcn.sh (公開から 7 日たった版で動かすため)
EOF
  exit 2
fi

if has_lock '*uv.lock' && runs 'pip3?|python3? -m pip|poetry|pipx'; then
  cat >&2 << 'EOF'
このリポジトリは uv を使います。pip・poetry・pipx ではなく、次のように uv で実行してください。
 - pip install <パッケージ> → uv add <パッケージ> (開発用は uv add --dev)
 - pip install -r requirements.txt・poetry install → uv sync
 - python <スクリプト> → uv run python <スクリプト>
 - pipx run <コマンド> → uvx <コマンド>
EOF
  exit 2
fi

exit 0

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

# shadcn の CLI は、公開から 7 日たった版で動かす。7 日待つ指定の無い実行を、コマンドの区切りごとに止める
seven_days() { # <区切った 1 つのコマンド> → 7 日待つ指定があれば 0
  # bun: --minimum-release-age= の値が 7 日 (604800 秒) 以上
  if [[ $1 =~ --minimum-release-age=([0-9]+) ]] && ((10#${BASH_REMATCH[1]} >= 604800)); then
    return 0
  fi
  # npm: /stack:ui の書き方だけを認める (--before の値は、ここでは確かめられないため)
  grep -Fq -- "--before=\"\$(node -p 'new Date(Date.now() - 7 * 864e5).toISOString()')\"" <<< "$1"
}
while IFS= read -r segment; do
  # 前置き (env・command・exec・time・nohup・VAR=値) の後に書いたものも見る
  if grep -Eq '^[[:space:](]*(((env|command|exec|time|nohup)|[[:alnum:]_]+=[^[:space:]]*)[[:space:]]+)*(bunx|bun[[:space:]]+x|npx|npm[[:space:]]+(exec|x)|pnpx|pnpm[[:space:]]+dlx|yarn[[:space:]]+dlx)[[:space:]](.*[[:space:]])?shadcn(@[^[:space:]]*)?([[:space:]]|$)' <<< "$segment" &&
    ! seven_days "$segment"; then
    cat >&2 << EOF
shadcn の CLI は、公開から 7 日たった版で動かしてください (乗っ取られた新しい版を避けるため)。
 - bun: bash "${CLAUDE_PLUGIN_ROOT:-<stack プラグイン>}/scripts/shadcn.sh" latest <引数> (/stack:ui)
 - npm など: npx --before="\$(node -p 'new Date(Date.now() - 7 * 864e5).toISOString()')" shadcn@latest <引数>
EOF
    exit 2
  fi
done < <(sed -E 's/(\|\||&&|[;&|])/\n/g' <<< "$cmd")

if has_lock '*bun.lock' '*bun.lockb' && runs 'npm|npx|yarn|pnpm|pnpx'; then
  cat >&2 << 'EOF'
このリポジトリは bun を使います。npm・npx・yarn・pnpm ではなく、次のように bun で実行してください。
 - npm install → bun install (lock どおりに入れるなら bun install --frozen-lockfile)
 - npm install <パッケージ> → bun add <パッケージ> (開発用は bun add -d)
 - npm run <スクリプト> → bun run <スクリプト>
 - npx <コマンド> → bunx <コマンド>。パッケージに入っている道具 (biome・tsc など) は bun <コマンド> (bunx は、入っていないと npm の同じ名前の別のパッケージを動かすため)
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

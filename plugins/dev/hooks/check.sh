#!/usr/bin/env bash
# Claude が作業を終える前に、変更がスタイルチェック・セキュリティチェック・テストを通るか確かめる。
# Taskfile にある style:check・security:check・test だけを、この順に実行する。
# 通らなければ exit 2 で結果 (stderr) を Claude に返し、作業を続けて直させる
cd "$CLAUDE_PROJECT_DIR" || exit 0

# この hook で作業を続けさせた直後 (直せないときに終わらなくなるのを防ぐ) と、コミットしていない変更がないとき (質問に答えただけなど) は確かめない。
# jq が無い環境でも判定できるよう、入力の JSON は grep で見る
grep -Eq '"stop_hook_active" *: *true' && exit 0
[ -n "$(git status --porcelain 2> /dev/null)" ] || exit 0

# シェルで mise activate していなくても、mise.toml の版の task を使えるようにする
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

# Taskfile が無いリポジトリと、task が入っていない環境 (GitHub Actions の claude-code-action など) では確かめない。
# Taskfile が壊れているときは、確かめられなかったことをユーザーに伝える (exit 1 では Claude は作業を続けない)
compgen -G '[Tt]askfile*.y*ml' > /dev/null && command -v task > /dev/null || exit 0
tasks=$(task --yes --list-all --json) || exit 1
targets=()
for name in style:check security:check test; do
  grep -Eq "\"name\": *\"$name\"" <<< "$tasks" && targets+=("$name")
done
[ ${#targets[@]} -gt 0 ] || exit 0

# gitleaks はステージした内容だけを、Semgrep は git が管理するファイルだけを検査する。
# ステージしていない変更や新しいファイルも検査されるよう、すべての変更を載せた一時的なインデックスを使う (本物のインデックスは変えない)
index=$(mktemp)
trap 'rm -f "$index"' EXIT
cp "$(git rev-parse --git-path index)" "$index"
GIT_INDEX_FILE="$index" git add -A

# devops の lefthook.yml と同じく、インデックスは GIT_INDEX_FILE ではなく SCAN_INDEX_FILE で task に渡す。
# GIT_INDEX_FILE を渡すと、remote の Taskfile を取る git が一時的なインデックスに devops のファイルを書いてしまう
for name in "${targets[@]}"; do
  SCAN_INDEX_FILE="$index" task --yes "$name" >&2 || {
    echo "task $name が通りませんでした。上の結果を見て直してください。" >&2
    exit 2
  }
done

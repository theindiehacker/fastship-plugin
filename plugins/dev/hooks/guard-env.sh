#!/usr/bin/env bash
# シークレットを置く .env と .env.* を、Claude に読ませたり書き換えさせたりしない。
# プラグインでは permissions.deny を配れないため、PreToolUse フックで拒否する (exit 2 で理由を Claude に返す)

# jq が無い環境でも判定できるよう、入力の JSON は grep で見る
path=$(grep -Eo '"file_path" *: *"[^"]*"' | head -n 1 | sed -E 's/.*"([^"]*)"$/\1/')
# macOS のファイルシステムは大文字と小文字を区別しないため、.ENV なども同じファイルとして扱う
name=$(tr '[:upper:]' '[:lower:]' <<< "${path##*/}")

case "$name" in
  .env | .env.*)
    echo "$name はシークレットを置くファイルのため、読み書きできません。必要な値はユーザーに聞いてください。" >&2
    exit 2
    ;;
esac

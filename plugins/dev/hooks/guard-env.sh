#!/usr/bin/env bash
# シークレットを置く .env と .env.* を、Claude に読ませたり書き換えさせたりしない。
# プラグインでは permissions.deny を配れないため、PreToolUse フックで拒否する (exit 2 で理由を Claude に返す)

# jq が無い環境でも判定できるよう、入力の JSON は grep で見る
path=$(grep -Eo '"file_path" *: *"[^"]*"' | head -n 1 | sed -E 's/.*"([^"]*)"$/\1/')
name=${path##*/}

case "$name" in
  .env | .env.*)
    echo "$name はシークレットを置くファイルのため、読み書きできません。必要な値はユーザーに聞いてください。" >&2
    exit 2
    ;;
esac

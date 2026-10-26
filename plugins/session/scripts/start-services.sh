#!/usr/bin/env bash
# Claude Code on the web のセッション開始時に、リポジトリ直下の compose ファイルのサービスを起動する。
# session プラグインの SessionStart hook (hooks/hooks.json) から実行する。compose ファイルか docker が無ければ何もしない。
# stdout は Claude のコンテキストに入るため、ビルドと起動の進捗は stderr に回し、起動できなかったことだけを伝える
set -uo pipefail

# ローカルでは何もしない。プラグインの hook は開いたどのリポジトリでも動くため、信頼していないリポジトリのイメージを
# ビルド・実行しないよう、ローカルでは docker compose up を自分で実行する
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

compose=""
for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
  if [ -f "$f" ]; then
    compose=$f
    break
  fi
done
[ -n "$compose" ] && command -v docker > /dev/null || exit 0

# Web のプロキシは TLS を検査するため、イメージのビルドにプロキシの CA を渡す。
# build のあるサービスに secret の ca-certificates を足す compose ファイルを作り、COMPOSE_FILE で重ねる。
# Dockerfile は RUN --mount=type=secret,id=ca-certificates,... で受け取る (受け取らなければ何も変わらない)。
# Web の Compose はビルドに Bake を使い、Bake は作業ディレクトリの外のファイルを読むときに許可 (--allow=fs.read) を求めて止まる。
# そのため CA をプロジェクトの中 (.claude/session/) にコピーし、git には info/exclude で無視させる。docker compose はリポジトリのルートで実行する
add_proxy_ca() {
  local dir="$PWD/.claude/session" files="$PWD/$compose" override exclude
  if [ -z "${SSL_CERT_FILE:-}" ] || ! command -v jq > /dev/null; then
    echo "⚠️ start-services: SSL_CERT_FILE か jq が無いため、ビルドにプロキシの CA を渡しません" >&2
    return 0
  fi
  mkdir -p "$dir" && cp "$SSL_CERT_FILE" "$dir/proxy-ca.crt" || return 0
  exclude=$(git rev-parse --git-path info/exclude 2> /dev/null) &&
    ! grep -qxF /.claude/session/ "$exclude" 2> /dev/null &&
    mkdir -p "$(dirname "$exclude")" && echo /.claude/session/ >> "$exclude"

  # COMPOSE_FILE を設定すると、compose は override のファイル (compose.override.yaml など) を読まなくなるため、あれば並べる
  override="${compose%.*}.override.${compose##*.}"
  [ -f "$override" ] && files="$files:$PWD/$override"

  # profiles で分けたサービスも、docker compose run で名指ししてビルドするため含める
  COMPOSE_FILE="$files" COMPOSE_PROFILES='*' docker compose config --format json 2> /dev/null |
    jq --arg ca "$dir/proxy-ca.crt" '{
      services: (.services | with_entries(select(.value.build) | .value = {build: {secrets: ["ca-certificates"]}})),
      secrets: {"ca-certificates": {file: $ca}}
    }' > "$dir/compose.proxy-ca.yaml" || return 0

  export COMPOSE_FILE="$files:$dir/compose.proxy-ca.yaml"
  # Claude が実行する docker compose・task にも効くよう、後続の Bash に渡す。セッションの再開でも実行されるため、同じ行を重ねて書かない
  local line="export COMPOSE_FILE=\"$COMPOSE_FILE\""
  if [ -n "${CLAUDE_ENV_FILE:-}" ] && ! grep -qxF "$line" "$CLAUDE_ENV_FILE" 2> /dev/null; then
    echo "$line" >> "$CLAUDE_ENV_FILE"
  fi
}

# Web の VM では Docker デーモンが止まっている。セッションの再開では、デーモンが動いたままのことがある
if ! docker info > /dev/null 2>&1; then
  # Docker Hub の匿名の取得回数の上限 (429) に当たらないよう、Google のミラーから取得する (ミラーに無ければ Docker Hub から取る)
  dockerd --registry-mirror=https://mirror.gcr.io > /tmp/dockerd.log 2>&1 &
fi
add_proxy_ca

# デーモンが応答するまで 30 秒まで待つ
for _ in $(seq 30); do docker info > /dev/null 2>&1 && break; sleep 1; done

docker compose up --build -d --wait >&2 ||
  echo "${compose} のサービスを起動できませんでした。docker compose up --build -d --wait を実行し、エラーを確かめてください。"
exit 0

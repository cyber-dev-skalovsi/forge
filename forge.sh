#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
VOLUME=server_forgedata
CACHE_VOLUME=forge_restic_cache
RESTIC_IMAGE=restic/restic:latest
ALPINE_IMAGE=alpine:3
ENV_FILE=.forge-env
COMPOSE=(docker compose -f server/compose.local.yml --env-file server/.env)
FORGE_PORT=3002

c_ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[1;31m%s\033[0m\n' "$*" >&2; }
say()    { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

restic_run() {
    local mode=$1; shift
    local mount="$VOLUME:/data"
    [ "$mode" = "ro" ] && mount="$mount:ro"
    MSYS_NO_PATHCONV=1 docker run --rm \
        --env-file "$ENV_FILE" \
        -v "$mount" \
        -v "$CACHE_VOLUME:/root/.cache/restic" \
        "$RESTIC_IMAGE" "$@"
}

forge_running() { docker ps --format '{{.Names}}' | grep -qx forgejo-local; }

cmd_start() {
    "${COMPOSE[@]}" up -d
    curl -fsS --retry 60 --retry-delay 2 --retry-connrefused --retry-all-errors \
         "http://127.0.0.1:$FORGE_PORT/api/healthz" >/dev/null 2>&1
    c_ok "forge up at http://127.0.0.1:$FORGE_PORT"
}

cmd_stop() {
    "${COMPOSE[@]}" down
    c_ok "forge stopped"
}

cmd_init() {
    [ -f "$ENV_FILE" ] || { c_err "missing $ENV_FILE"; exit 1; }
    say "creating encrypted repository"
    restic_run ro init
    c_ok "repository created"
}

case "${1:-help}" in
    init)   cmd_init ;;
    start)  cmd_start ;;
    stop)   cmd_stop ;;
    *)      echo "usage: forge.sh {init|start|stop}" ;;
esac

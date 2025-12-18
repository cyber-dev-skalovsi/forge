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

require_env() {
    [ -f "$ENV_FILE" ] || { c_err "missing $ENV_FILE"; exit 1; }
    RESTIC_REPOSITORY=$(grep -E '^RESTIC_REPOSITORY=' "$ENV_FILE" | head -1 | cut -d= -f2-)
    [ -n "$RESTIC_REPOSITORY" ] || { c_err "RESTIC_REPOSITORY not set in $ENV_FILE"; exit 1; }
}

repo_mount_args() {
    case "$RESTIC_REPOSITORY" in
        /repo*) printf '%s\n' -v "forge_local_repo:/repo" ;;
    esac
}

restic_run() {
    local mode=$1; shift
    local mount="$VOLUME:/data"
    [ "$mode" = "ro" ] && mount="$mount:ro"
    MSYS_NO_PATHCONV=1 docker run --rm \
        --env-file "$ENV_FILE" \
        -v "$mount" \
        -v "$CACHE_VOLUME:/root/.cache/restic" \
        $(repo_mount_args) \
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
    require_env
    say "creating encrypted repository"
    restic_run ro init
    c_ok "repository created"
}

cmd_push() {
    require_env
    local was_running=0
    forge_running && was_running=1
    if [ "$was_running" -eq 1 ]; then
        say "stopping forge for a consistent snapshot"
        "${COMPOSE[@]}" down
    fi
    say "encrypting and uploading"
    restic_run ro backup /data --tag forge --host "$(hostname)"
    [ "$was_running" -eq 1 ] && { say "restarting forge"; cmd_start; }
    c_ok "pushed"
}

cmd_pull() {
    require_env
    say "newest snapshot in the repository"
    restic_run ro snapshots --latest 1 --tag forge
    forge_running && { say "stopping forge"; "${COMPOSE[@]}" down; }
    say "restoring and decrypting"
    restic_run rw restore latest --tag forge --target /
    say "starting forge"
    cmd_start
    c_ok "pulled"
}

case "${1:-help}" in
    init)   cmd_init ;;
    start)  cmd_start ;;
    stop)   cmd_stop ;;
    push)   cmd_push ;;
    pull)   cmd_pull ;;
    *)      echo "usage: forge.sh {init|start|stop|push|pull}" ;;
esac

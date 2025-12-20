#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
VOLUME=server_forgedata
CACHE_VOLUME=forge_restic_cache
SCRATCH_VOLUME=forge_restore_drill
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
    [ -f "$ENV_FILE" ] || {
        c_err "missing $ENV_FILE"
        cat <<'HELP'
Create it with (no quotes around values — docker --env-file takes them literally):
  B2_ACCOUNT_ID=<keyID>
  B2_ACCOUNT_KEY=<applicationKey>
  RESTIC_REPOSITORY=b2:<bucket>:forge
  RESTIC_PASSWORD=<long passphrase>
Then: chmod 600 .forge-env
HELP
        exit 1
    }
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

restic_scratch() {
    MSYS_NO_PATHCONV=1 docker run --rm \
        --env-file "$ENV_FILE" \
        -v "$SCRATCH_VOLUME:/restore" \
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
    c_warn "put that passphrase in your password manager NOW. There is no recovery without it."
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
    say "pruning old snapshots"
    restic_run ro forget --tag forge --keep-last 10 --keep-daily 7 --keep-monthly 6 --prune
    [ "$was_running" -eq 1 ] && { say "restarting forge"; cmd_start; }
    c_ok "pushed"
}

cmd_pull() {
    require_env
    say "newest snapshot in the repository"
    restic_run ro snapshots --latest 1 --tag forge
    if [ "${2:-}" != "--yes" ] && [ "${FORGE_ASSUME_YES:-}" != "1" ]; then
        c_warn "This REPLACES all local forge data with the snapshot above."
        printf 'Type yes to continue: '
        read -r reply
        [ "$reply" = "yes" ] || { echo "aborted"; exit 1; }
    fi
    forge_running && { say "stopping forge"; "${COMPOSE[@]}" down; }
    "${COMPOSE[@]}" up --no-start >/dev/null 2>&1 || true
    say "clearing local state"
    MSYS_NO_PATHCONV=1 docker run --rm -v "$VOLUME:/data" "$ALPINE_IMAGE" \
        find /data -mindepth 1 -delete
    say "restoring and decrypting"
    restic_run rw restore latest --tag forge --target /
    say "starting forge"
    cmd_start
    c_ok "pulled"
}

cmd_status() {
    require_env
    say "snapshots"
    restic_run ro snapshots --tag forge || true
    say "repository size on the provider"
    restic_run ro stats --mode raw-data || true
    say "local"
    if forge_running; then c_ok "forge is running on http://127.0.0.1:$FORGE_PORT"
    else c_warn "forge is stopped"; fi
}

cmd_drill() {
    require_env
    say "restoring newest snapshot into a scratch volume (live data untouched)"
    docker volume rm "$SCRATCH_VOLUME" >/dev/null 2>&1 || true
    restic_scratch restore latest --tag forge --target /restore
    say "checking the restored copy contains a real forge"
    local out
    out=$(MSYS_NO_PATHCONV=1 docker run --rm -v "$SCRATCH_VOLUME:/restore" "$ALPINE_IMAGE" sh -c '
        db=/restore/data/gitea/forgejo.db
        repos=/restore/data/git/repositories
        [ -f "$db" ]   && echo "ok   database present ($(du -h "$db" | cut -f1))" || echo "FAIL database missing"
        [ -d "$repos" ] && echo "ok   repositories dir present"                    || echo "FAIL repositories dir missing"
        n=$(find "$repos" -maxdepth 2 -name "*.git" 2>/dev/null | wc -l)
        echo "ok   repositories found: $n"
        find "$repos" -maxdepth 2 -name "*.git" 2>/dev/null | sed "s#$repos/#     - #"
    ')
    echo "$out"
    docker volume rm "$SCRATCH_VOLUME" >/dev/null 2>&1 || true
    echo "$out" | grep -q FAIL && { c_err "DRILL FAILED"; exit 1; }
    c_ok "DRILL PASSED — the snapshot restores to a working forge"
}

case "${1:-help}" in
    init)   cmd_init ;;
    start)  cmd_start ;;
    stop)   cmd_stop ;;
    push)   cmd_push ;;
    pull)   cmd_pull "$@" ;;
    status) cmd_status ;;
    drill)  cmd_drill ;;
    *)      sed -n '3,25p' "$0" | grep '^#' | cut -c3- ;;
esac

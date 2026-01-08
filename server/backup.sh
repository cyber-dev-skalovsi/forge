#!/usr/bin/env bash
# Nightly encrypted backup of the forge to Cloudflare R2, plus Oracle idle-reclaim keepalive.
#
# restic encrypts client-side, so Cloudflare only ever stores ciphertext.
set -Eeuo pipefail
FORGE_DIR=/opt/forge
DUMP_DIR=/var/backups/forge
RETENTION_DAILY=7
RETENTION_WEEKLY=5
RETENTION_MONTHLY=6
log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
trap 'log "FAILED at line $LINENO"' ERR
set -a; source /etc/forge-backup.env; set +a
mkdir -p "$DUMP_DIR"
rm -f "$DUMP_DIR"/forgejo-dump-*.zip
log "dumping forgejo (db + repos + config + lfs)"
docker compose -f "$FORGE_DIR/compose.yml" exec -T -u git forgejo \
    forgejo dump --type zip --file /tmp/forge-dump.zip --skip-log
docker compose -f "$FORGE_DIR/compose.yml" cp \
    forgejo:/tmp/forge-dump.zip "$DUMP_DIR/forgejo-dump-$(date +%F).zip"
docker compose -f "$FORGE_DIR/compose.yml" exec -T forgejo rm -f /tmp/forge-dump.zip
log "initialising restic repo if absent"
restic snapshots >/dev/null 2>&1 || restic init
log "backing up (encrypted client-side)"
restic backup --tag forge --host forge "$DUMP_DIR"
log "pruning old snapshots"
restic forget --tag forge \
    --keep-daily "$RETENTION_DAILY" \
    --keep-weekly "$RETENTION_WEEKLY" \
    --keep-monthly "$RETENTION_MONTHLY" \
    --prune
log "verifying repository integrity"
restic check
rm -f "$DUMP_DIR"/forgejo-dump-*.zip
log "done"

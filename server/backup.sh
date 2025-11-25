#!/usr/bin/env bash
set -Eeuo pipefail
FORGE_DIR=/opt/forge
DUMP_DIR=/var/backups/forge
log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
trap 'log "FAILED at line $LINENO"' ERR
set -a; source /etc/forge-backup.env; set +a
mkdir -p "$DUMP_DIR"
rm -f "$DUMP_DIR"/forgejo-dump-*.zip
docker compose -f "$FORGE_DIR/compose.yml" exec -T -u git forgejo forgejo dump --type zip --file /tmp/forge-dump.zip --skip-log
docker compose -f "$FORGE_DIR/compose.yml" cp forgejo:/tmp/forge-dump.zip "$DUMP_DIR/forgejo-dump-$(date +%F).zip"
docker compose -f "$FORGE_DIR/compose.yml" exec -T forgejo rm -f /tmp/forge-dump.zip
restic snapshots >/dev/null 2>&1 || restic init
restic backup --tag forge --host forge "$DUMP_DIR"
restic forget --tag forge --keep-daily 7 --keep-weekly 5 --keep-monthly 6 --prune
restic check
rm -f "$DUMP_DIR"/forgejo-dump-*.zip
log "done"

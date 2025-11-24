#!/usr/bin/env bash
# Nightly encrypted backup of the forge to Cloudflare R2, plus Oracle idle-reclaim keepalive.
#
# restic encrypts client-side, so Cloudflare only ever stores ciphertext —
# they cannot read your repositories even though the bytes live on their disks.
#
# Secrets come from /etc/forge-backup.env (chmod 600), which must define:
#   RESTIC_REPOSITORY=s3:https://<ACCOUNT_ID>.r2.cloudflarestorage.com/<BUCKET>
#   RESTIC_PASSWORD=<long passphrase — store in your password manager, you cannot recover without it>
#   AWS_ACCESS_KEY_ID=<R2 token access key id>
#   AWS_SECRET_ACCESS_KEY=<R2 token secret>
set -Eeuo pipefail

FORGE_DIR=/opt/forge
DUMP_DIR=/var/backups/forge
RETENTION_DAILY=7
RETENTION_WEEKLY=5
RETENTION_MONTHLY=6

log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
trap 'log "FAILED at line $LINENO"' ERR

# shellcheck disable=SC1091
set -a; source /etc/forge-backup.env; set +a

mkdir -p "$DUMP_DIR"
# Keep the dump dir clean: a half-written dump from a previous failure must not
# be mistaken for a good backup.
rm -f "$DUMP_DIR"/forgejo-dump-*.zip

log "dumping forgejo (db + repos + config + lfs)"
# `forgejo dump` produces one consistent archive. It must run as the git user
# inside the container, and writes to the container's cwd.
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
    --keep-daily  "$RETENTION_DAILY" \
    --keep-weekly "$RETENTION_WEEKLY" \
    --keep-monthly "$RETENTION_MONTHLY" \
    --prune

log "verifying repository integrity"
restic check

# Local dump is redundant once it is safely in R2, and it is the largest thing
# on a small boot volume.
rm -f "$DUMP_DIR"/forgejo-dump-*.zip

# Oracle reclaims Always Free instances that look idle. The backup itself is
# real CPU + network activity, which is why this doubles as the keepalive.
log "done"

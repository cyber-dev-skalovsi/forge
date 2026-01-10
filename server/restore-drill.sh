#!/usr/bin/env bash
# Prove the backups are real. A backup you have never restored is not a backup.
# Restores the newest snapshot into a scratch dir and lists what came back.
set -Eeuo pipefail
set -a; source /etc/forge-backup.env; set +a
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
echo "restoring latest snapshot -> $SCRATCH"
restic restore latest --target "$SCRATCH"
DUMP=$(find "$SCRATCH" -name 'forgejo-dump-*.zip' | head -1)
[ -n "$DUMP" ] || { echo "FAIL: no dump found in snapshot"; exit 1; }
echo "dump: $DUMP ($(du -h "$DUMP" | cut -f1))"
echo "--- contents (top level) ---"
unzip -l "$DUMP" | head -20
echo "--- repositories in the dump ---"
unzip -l "$DUMP" | grep -c 'repos/' || true
echo "PASS: dump restored and readable"

#!/usr/bin/env bash
set -Eeuo pipefail
set -a; source /etc/forge-backup.env; set +a
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
echo "restoring latest snapshot -> $SCRATCH"
restic restore latest --target "$SCRATCH"
DUMP=$(find "$SCRATCH" -name 'forgejo-dump-*.zip' | head -1)
[ -n "$DUMP" ] || { echo "FAIL: no dump found in snapshot"; exit 1; }
echo "dump: $DUMP ($(du -h "$DUMP" | cut -f1))"
unzip -l "$DUMP" | head -20
echo "PASS: dump restored and readable"

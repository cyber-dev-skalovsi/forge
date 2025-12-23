#!/usr/bin/env bash
# Local backup: one self-contained forgejo dump (db + repos + config) per run,
# keeping the newest KEEP. This same file is what you would restore onto a real
# server, so it doubles as the migration artifact.
set -Eeuo pipefail
cd "$(dirname "$0")"

DEST="${FORGE_BACKUP_DIR:-$HOME/forge-backups}"
CONTAINER=forgejo-local
KEEP=7

mkdir -p "$DEST"
STAMP=$(date +%Y-%m-%d_%H%M)

if command -v cygpath >/dev/null 2>&1; then
    DEST_NATIVE=$(cygpath -w "$DEST")
else
    DEST_NATIVE="$DEST"
fi

echo "dumping..."
MSYS_NO_PATHCONV=1 docker exec -u git "$CONTAINER" \
    forgejo dump --type zip --file /tmp/d.zip --skip-log >/dev/null 2>&1

MSYS_NO_PATHCONV=1 docker cp "$CONTAINER:/tmp/d.zip" "$DEST_NATIVE/forgejo-$STAMP.zip"
MSYS_NO_PATHCONV=1 docker exec -u git "$CONTAINER" rm -f /tmp/d.zip

SIZE=$(du -h "$DEST/forgejo-$STAMP.zip" | cut -f1)
echo "wrote $DEST/forgejo-$STAMP.zip ($SIZE)"

ls -1t "$DEST"/forgejo-*.zip 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
    echo "pruning $(basename "$old")"
    rm -f "$old"
done
echo "backups on disk: $(ls -1 "$DEST"/forgejo-*.zip 2>/dev/null | wc -l)"

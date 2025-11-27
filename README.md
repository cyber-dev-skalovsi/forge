# forge

A self-hosted, single-user Forgejo instance running on an Oracle Always Free
ARM box. Reached over Tailscale; nothing is exposed to the public internet.

## Daily use

```
./forge.sh start
...work...
```

## Backups

`server/backup.sh` runs nightly via cron and sends an encrypted restic snapshot
to cloud storage (R2/B2). `server/restore-drill.sh` proves a restore actually
works — a backup you have never restored is not a backup.

## Layout

- server/compose.yml — Forgejo container
- server/setup.sh — bootstrap a fresh Oracle box
- server/backup.sh — nightly restic backup
- server/restore-drill.sh — prove the backup restores

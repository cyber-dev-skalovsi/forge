# forge

A self-hosted, single-user Forgejo instance running on an Oracle Always Free
ARM box. Reached over Tailscale; nothing is exposed to the public internet.

## Daily use

```
./forge.sh start
...work...
```

## Layout

- server/compose.yml — Forgejo container
- server/setup.sh — bootstrap a fresh Oracle box
- server/backup.sh — nightly restic backup

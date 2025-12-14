# forge

A self-hosted, single-user Forgejo instance. Reachable over Tailscale and — when
you want it public — through a Cloudflare Worker that fronts a quick tunnel.

## Daily use

```
./forge.sh start      # local only, http://127.0.0.1:3002
./forge.sh start --public
...work...
```

## Honest limitations

1. **Not always-on.** Deliberately traded away — availability needs hardware you own
   or a payment method somewhere.
2. **One machine at a time.** Concurrent use diverges irrecoverably.
3. **Push is manual.** Forget it and that session's work exists only on that machine.

## Layout

- server/compose.yml — canonical Forgejo config
- server/compose.local.yml — generated local variant (named volume)
- server/.env — local ports and hostname
- server/setup.sh — bootstrap a fresh Oracle box
- server/backup.sh — nightly restic backup
- server/restore-drill.sh — prove the backup restores
- worker/ — Cloudflare reverse proxy
- start.sh — bring it up, optionally exposing a tunnel

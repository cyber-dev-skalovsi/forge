# forge

A private, single-user git forge that isn't tied to any one machine. It runs
locally in Docker; the entire forge state lives in cloud storage as AES-256
encrypted, compressed, deduplicated blobs. The storage provider holds bytes it
cannot read.

Any machine with Docker and your passphrase can pull the state down and *become*
the forge.

## Daily use

```bash
./forge.sh pull     # get the newest state (start of a session on any machine)
./forge.sh start    # http://127.0.0.1:3002
    ...work...
./forge.sh push     # stop -> snapshot encrypted -> start
```

Only run the forge on one machine at a time. `./forge.sh status` shows which host
pushed last.

| Command | Does |
|---|---|
| `./forge.sh init` | create the encrypted repository (once, ever) |
| `./forge.sh start` / `stop` | bring the forge up / down locally |
| `./forge.sh push` | stop → snapshot encrypted → restart |
| `./forge.sh pull` | stop → replace local state with newest snapshot → restart |
| `./forge.sh status` | snapshots, who pushed last, size on the provider |
| `./forge.sh drill` | prove a restore works, without touching live data |

## Setting up a second machine

1. Install Docker.
2. Copy this `forge/` directory over (or clone it from the forge itself).
3. Drop in `.forge-env` with the same values.
4. `./forge.sh pull`

## Credentials — `.forge-env`

Not in git, `chmod 600`. **No quotes around values** — Docker's `--env-file`
treats quotes as literal characters.

```
B2_ACCOUNT_ID=<keyID>
B2_ACCOUNT_KEY=<applicationKey>
RESTIC_REPOSITORY=b2:<bucket>:forge
RESTIC_PASSWORD=<long passphrase>
```

⚠️ `RESTIC_PASSWORD` in your password manager, now. Lose it and everything in the
cloud is permanently unreadable.

## Layout

- forge.sh — encrypt/restore command
- branding/custom.css — the gold theme
- .forge-env — credentials (gitignored, chmod 600)
- server/compose.yml — canonical Forgejo config
- server/compose.local.yml — generated for Windows — run server/make-local-compose.sh
- server/.env — port 3002, container forgejo-local
- server/backup.sh — nightly restic backup (for the Oracle setup)
- worker/ — Cloudflare reverse proxy
- zeabur/ — Zeabur deploy config, kept for reference

# Talon

A private, single-user git forge (rebranded Forgejo — own logo, name, gold theme) that
isn't tied to any one machine. It runs locally in Docker; the entire forge state lives in
cloud storage as **AES-256 encrypted, compressed, deduplicated blobs**. The storage
provider holds bytes it cannot read.

Any machine with Docker and your passphrase can pull the state down and *become* the forge.

```
  any machine you own
  ┌─────────────────────────────────────────┐
  │  Talon  →  docker volume forgedata      │
  │                    ▲                    │
  │                    │  restic container  │
  │   ENCRYPT + COMPRESS + DEDUPE HAPPENS HERE
  └────────────────────┼────────────────────┘
                       │  only ciphertext crosses this line
                       ▼
              Backblaze B2 (10 GB free, no card)
```

Nothing listens on a public port. There is no Cloudflare in the data path.

## Daily use

```bash
./forge.sh pull     # get the newest state (start of a session on any machine)
./forge.sh start    # http://127.0.0.1:3002 — login: talon
    ...work...
git push            # auto-triggers an encrypted snapshot in the background (see below)
```

You normally never need to run `./forge.sh push` yourself — every `git push` to any repo
on the forge fires a webhook that runs it for you (see **Auto-push on every commit**).

`push` and `pull` stop Forgejo briefly on purpose: SQLite with a live write-ahead log cannot
be copied safely, and a snapshot that restores corrupt is worse than no snapshot. That
means **every auto-push causes a ~15-20s blip** while it happens — expected, not a bug.

Only run the forge on one machine at a time. Two at once diverge, and nothing here can
merge them. `./forge.sh status` shows which host pushed last and when.

| Command | Does |
|---|---|
| `./forge.sh init` | create the encrypted repository (once, ever) |
| `./forge.sh start` / `stop` | bring the forge up / down locally |
| `./forge.sh push` | stop → snapshot encrypted → restart |
| `./forge.sh pull` | stop → **replace** local state with newest snapshot → restart |
| `./forge.sh status` | snapshots, who pushed last, size on the provider |
| `./forge.sh drill` | prove a restore works, without touching live data |

## Auto-push on every commit

`push-listener.js` is a small Node HTTP server that Talon calls via a webhook on every
`git push`, which then runs `./forge.sh push` in the background (concurrent pushes are
coalesced into one follow-up run, not queued up in parallel).

```bash
node push-listener.js &     # start it once per session (or wire it into login/startup)
```

It verifies each webhook's HMAC signature against `WEBHOOK_SECRET` (in `.forge-env`)
before doing anything, and only listens on `127.0.0.1:9988`. Talon reaches it from inside
its container via `host.docker.internal`, which needed adding to
`FORGEJO__webhook__ALLOWED_HOST_LIST` — Forgejo blocks webhooks to loopback/private
targets by default (SSRF guard).

## Credentials — `.forge-env`

Not in git (`.gitignore`d), `chmod 600`. **No quotes around values** — Docker's `--env-file`
treats quotes as literal characters.

```
B2_ACCOUNT_ID=<keyID>
B2_ACCOUNT_KEY=<applicationKey>
RESTIC_REPOSITORY=b2:<bucket>:forge
RESTIC_PASSWORD=<long passphrase>
WEBHOOK_SECRET=<random hex, used to verify push-listener.js requests>
```

⚠️ **`RESTIC_PASSWORD` in your password manager, now.** Lose it and everything in the cloud is
permanently unreadable. That is exactly the property you asked for, and it cuts both ways.

## Verified, not assumed

Measured against the **live Backblaze B2 bucket** (`homelab-uploads`, prefix `forge/`):

| Check | Result |
|---|---|
| **Deleted the forge volume, the local repo AND the restic cache**, leaving B2 as the only copy — then pulled | user `fynn` (since renamed to `talon`), repo HEAD `042fa8ad`, `src/app.py` contents all identical; repo clones cleanly |
| Restore drill into a scratch volume | database + `fynn/hello.git` present |
| **Is what B2 stores actually unreadable?** | downloaded a real stored object: opaque binary, **0 hits** for `fynn`, `hello`, `README`, `app.py`, `print`, `gitea`, `forgejo` |
| Do filenames leak anything? | no — 6 objects, all named by content hash, **0 filename matches** for any of those terms |
| Compression / dedup | **37.4x ratio, 97.3% saving**; 5.3 MiB of state → **135 KiB** uploaded |
| Incremental push | a second push added 20 KiB |
| Nothing exposed | Worker **deleted** (404), no `cloudflared`, Forgejo bound to `127.0.0.1` only |
| `.forge-env` permissions | NTFS ACL restricted to your account only (SYSTEM/Administrators removed) |

Reproduce it yourself any time. With the passphrase, everything is readable:

```bash
docker run --rm --env-file .forge-env restic/restic:latest snapshots
```

Without it, nothing is — temporarily change `RESTIC_PASSWORD` and the same command fails
with `wrong password or no key found`. And in the Backblaze web UI, open any object under
`forge/data/` and you will see opaque binary: no filenames, no code, no repo names.

## Layout

```
forge.sh                 encrypt/restore command
push-listener.js         webhook receiver — auto-runs forge.sh push on every git push
branding/custom.css      Talon's gold theme (injected via server/templates hook, see below)
.forge-env               credentials (gitignored, chmod 600)
server/compose.yml       canonical Forgejo config
server/compose.local.yml GENERATED for Windows — run server/make-local-compose.sh
server/.env              port 3002, container forgejo-local
backup-local.sh          extra local dump to ~/forge-backups (belt and braces)
worker/                  Cloudflare reverse proxy — working, tested, NOT deployed
zeabur/                  Zeabur deploy config — unused, kept for reference
server/setup.sh          bootstraps a real Linux server, for if you ever go always-on
```

## Honest limitations

1. **Not always-on.** Deliberately traded away — availability needs hardware you own or a
   payment method somewhere, and every free option was checked and ruled out (Oracle, Koyeb,
   Render, OpenShift Sandbox, Zeabur, Fly, Railway, Northflank).
2. **One machine at a time.** Concurrent use diverges irrecoverably.
3. **Push is manual.** Forget it and that session's work exists only on that machine.

## Gotchas found while building this

- Docker named volumes live inside the Docker Desktop VM and are invisible to Windows.
- Git Bash rewrites absolute paths before the Docker CLI sees them — `MSYS_NO_PATHCONV`.
- `restic restore` does not delete files missing from the snapshot, so `pull` wipes the
  volume first.
- Forgejo webhooks refuse to call loopback/private-range URLs by default (SSRF guard) — a
  webhook to `host.docker.internal` needs `FORGEJO__webhook__ALLOWED_HOST_LIST` set.

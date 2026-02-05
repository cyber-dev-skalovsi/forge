# Deploying the forge to Zeabur

Zeabur is the only free-tier host I found that needs **no credit card**, runs arbitrary
Docker images, and has real persistent volumes. Everything else fails on one of those
three (Koyeb and Render have no persistent disk on free; OpenShift Sandbox kills pods at
12 hours; Oracle/Fly/Railway/Northflank all want a card).

## The one thing that decides whether this works

**Can the Free plan mount a volume?** Without a volume, Zeabur's filesystem is ephemeral
and your repositories are destroyed on the next restart — exactly the failure that rules
out Koyeb. So do **step 3 first**. If the volume will not mount on the free plan, stop and
stay on the local setup.

## Steps

### 1. Sign up
[zeabur.com](https://zeabur.com) — GitHub or Google login, no card.

### 2. Create the service
Project → **Add Service** → **Docker Images**: image `codeberg.org/forgejo/forgejo:15`,
port name `web`, port `3000`, type `HTTP`.

### 3. Mount the volume — do this before anything else
Service → **Volumes** tab → **Mount Volumes**: volume ID `data`, mount directory `/data`.

**If this is rejected on the Free plan, abandon Zeabur.**

### 4. Environment variables
Paste from [`env.txt`](./env.txt). One line needs editing — `FORGEJO__server__ROOT_URL`
is a placeholder. Set it to your Worker URL, **with the trailing slash**:
`https://forge-proxy.bwz-project.workers.dev/`.

### 5. Deploy, then immediately create your admin
Open the assigned `*.zeabur.app` URL. You get Forgejo's **install wizard** — create your
admin account there. This differs deliberately from the local setup, which uses
`forgejo admin user create` in a shell. Zeabur free may not give you a container shell,
and with registration disabled and no admin account you would be locked out for good.

Then, in Variables: `FORGEJO__security__INSTALL_LOCK=true`. Redeploy, and enable TOTP 2FA.

### 6. Point the Worker at it
Get the hostname from the service's **Domains** tab. Then:
```bash
cd ~/forge/worker
npx wrangler secret put FORGE_ORIGIN     # e.g. https://fynn-forge.zeabur.app  (no trailing slash)
```
Your public URL stays `https://forge-proxy.bwz-project.workers.dev` — that never changes.

### 7. Move your existing repos
```bash
git clone --mirror http://127.0.0.1:3002/fynn/hello.git
# repoint the Worker, create the repo in the new Forgejo UI, then:
cd hello.git
git push --mirror https://<user>:<token>@forge-proxy.bwz-project.workers.dev/fynn/hello.git
```

## Known trade-offs
- **Free-plan services sleep on inactivity** and cold-start on the next request.
- **No automated backups on the free plan.** Keep running `~/forge/backup-local.sh`.
- **Volumes are in public preview** — back up anything you cannot afford to lose.
- **No SLA on the free plan.**

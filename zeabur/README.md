# Deploying the forge to Zeabur

Zeabur is the only free-tier host I found that needs **no credit card**, runs arbitrary
Docker images, and has real persistent volumes. Everything else fails on one of those
three (Koyeb and Render have no persistent disk on free; OpenShift Sandbox kills pods at
12 hours; Oracle/Fly/Railway/Northflank all want a card).

## The one thing that decides whether this works

**Can the Free plan mount a volume?** I could not confirm it from Zeabur's docs, and it
is the whole ballgame. Without a volume, Zeabur's filesystem is ephemeral and your
repositories are destroyed on the next restart — exactly the failure that rules out
Koyeb.

So do **step 3 first**. If the volume will not mount on the free plan, stop and stay on
the local setup; nothing else about Zeabur matters.

## Steps

### 1. Sign up

[zeabur.com](https://zeabur.com) — GitHub or Google login, no card.

### 2. Create the service

Project → **Add Service** → **Docker Images**, then:

| Field | Value |
|---|---|
| Image | `codeberg.org/forgejo/forgejo:15` |
| Port name | `web` |
| Port | `3000` |
| Type | `HTTP` |

### 3. Mount the volume — do this before anything else

Service → **Volumes** tab → **Mount Volumes**:

| Field | Value |
|---|---|
| Volume ID | `data` |
| Mount Directory | `/data` |

Zeabur warns that mounting *clears* the directory. That is fine on a fresh deploy.
Note that with a volume attached the service can no longer do zero-downtime restarts —
irrelevant for one user.

**If this is rejected on the Free plan, abandon Zeabur.**

### 4. Environment variables

Paste from [`env.txt`](./env.txt). One line needs editing — `FORGEJO__server__ROOT_URL`
is a placeholder. Set it to your Worker URL, **with the trailing slash**:

```
FORGEJO__server__ROOT_URL=https://forge-proxy.bwz-project.workers.dev/
```

Forgejo builds every link and redirect from that value, so a wrong one gives you a forge
that redirects you off itself mid-login.

### 5. Deploy, then immediately create your admin

Open the assigned `*.zeabur.app` URL. You get Forgejo's **install wizard** — create your
admin account there.

This differs deliberately from the local setup, which uses
`forgejo admin user create` in a shell. Zeabur free may not give you a container shell,
and with registration disabled and no admin account you would be locked out for good.
So the wizard is the safe path — but it means **anyone who finds the URL before you
finish it can claim your instance.** Do it straight away.

Then, in Variables:

```
FORGEJO__security__INSTALL_LOCK=true
```

Redeploy, and enable TOTP 2FA on your account.

### 6. Point the Worker at it

First get the hostname: the service's **Domains** tab. Zeabur generates one when
you deploy, or you can claim your own subdomain there (e.g. `fynn-forge.zeabur.app`).
There is nothing to fill in until the service exists — that is why the guide writes
it as a placeholder.

```bash
cd ~/forge/worker
npx wrangler secret put FORGE_ORIGIN     # e.g. https://fynn-forge.zeabur.app  (no trailing slash)
```

Your public URL stays `https://forge-proxy.bwz-project.workers.dev` — that never changes,
which is the entire reason the Worker sits in front. At this point you can stop
`start.sh` and shut the local tunnel down.

### 7. Move your existing repos

You have one small repo (`fynn/hello`), so pushing is simpler than restoring a dump:

```bash
# BEFORE repointing the Worker — pull straight from the local instance:
git clone --mirror http://127.0.0.1:3002/fynn/hello.git
# THEN repoint the Worker (step 6), create the repo in the new Forgejo UI, and:
cd hello.git
git push --mirror https://<user>:<token>@forge-proxy.bwz-project.workers.dev/fynn/hello.git
```

For a larger migration later, restore a `~/forge-backups/*.zip` dump instead — that
carries users, settings and every repo in one file.

## Known trade-offs

- **Free-plan services sleep on inactivity** and cold-start on the next request. A few
  seconds when you open the page. Acceptable for a personal forge; the volume survives
  sleep, only the running process stops.
- **No automated backups on the free plan.** Keep running `~/forge/backup-local.sh`
  against whichever instance is live, or mirror-push to a private GitHub/Codeberg repo.
- **Volumes are in public preview**, and Zeabur's own docs say to back up anything you
  cannot afford to lose. Take that literally.
- **No SLA on the free plan.**

## Declarative alternative

[`template.yaml`](./template.yaml) is the same configuration in Zeabur's template format
(`apiVersion: zeabur.com/v1`), if you would rather deploy from code than click through the
dashboard. It is validated and structurally correct, but I could not test-deploy it
without an account — treat the dashboard steps above as the primary path.

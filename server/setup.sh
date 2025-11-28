#!/usr/bin/env bash
set -Eeuo pipefail
FORGE_DIR=/opt/forge
log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

log "base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg restic unzip jq

log "docker engine"
if ! command -v docker >/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker

log "tailscale"
if ! command -v tailscale >/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi

log "forge directory"
mkdir -p "$FORGE_DIR"
cp -n compose.yml "$FORGE_DIR/" 2>/dev/null || true
cp -n .env "$FORGE_DIR/.env" 2>/dev/null || true
mkdir -p "$FORGE_DIR/data"
chown -R 1000:1000 "$FORGE_DIR/data"

[ -f "$FORGE_DIR/.env" ] || { echo "!! $FORGE_DIR/.env missing — copy .env.example and fill it in"; exit 1; }

log "oracle's default iptables drops most inbound; nothing to open (tailscale is outbound-only)"
log "starting forgejo"
cd "$FORGE_DIR"
docker compose pull -q
docker compose up -d

log "waiting for health"
for _ in $(seq 1 60); do
    if curl -fsS http://127.0.0.1:3000/api/healthz >/dev/null 2>&1; then
        echo "forgejo is up"; break
    fi
    sleep 2
done

log "next steps (need your input, so not automated here)"
cat <<'NEXT'
  1. tailscale up --ssh
  2. tailscale serve --bg 3000
  3. tailscale funnel --bg 3000
  4. create your admin account:
       cd /opt/forge && docker compose exec -u git forgejo forgejo admin user create --admin --username YOURNAME --email you@example.com --random-password
  5. install /etc/forge-backup.env and the cron
NEXT

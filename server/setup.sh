#!/usr/bin/env bash
set -Eeuo pipefail
FORGE_DIR=/opt/forge
log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

log "base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg restic

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

log "starting forgejo"
cd "$FORGE_DIR"
docker compose pull -q
docker compose up -d

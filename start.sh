#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
WORKER_URL="https://forge-proxy.bwz-project.workers.dev"
FORGE_PORT=3002
PUBLIC=0
[ "${1:-}" = "--public" ] && PUBLIC=1
say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
say "starting forgejo"
docker compose -f server/compose.local.yml --env-file server/.env up -d
curl -fsS --retry 60 --retry-delay 2 --retry-connrefused --retry-all-errors "http://127.0.0.1:$FORGE_PORT/api/healthz" >/dev/null 2>&1
echo "forgejo healthy"
if [ "$PUBLIC" -eq 0 ]; then
    printf '\n\033[1;32mforge is up at http://127.0.0.1:%s\033[0m\n' "$FORGE_PORT"
    echo "(local only — no public ingress. use --public to expose it.)"
    exit 0
fi
echo "public mode: tunnel + worker"

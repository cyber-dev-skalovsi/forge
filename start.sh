#!/usr/bin/env bash
# Bring the forge up.
#
#   ./start.sh              local only  — http://127.0.0.1:3002   (default)
#   ./start.sh --public     ALSO opens a public tunnel            (see warning)
#
# The tunnel is deliberately NOT the default. It creates an inbound path from
# the public internet to this machine, bypassing the network firewall. On a
# work-managed machine that is a security problem, not a convenience.
set -Eeuo pipefail
cd "$(dirname "$0")"

WORKER_URL="https://forge-proxy.bwz-project.workers.dev"
FORGE_PORT=3002
PUBLIC=0
[ "${1:-}" = "--public" ] && PUBLIC=1

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

say "starting forgejo"
docker compose -f server/compose.local.yml --env-file server/.env up -d
curl -fsS --retry 60 --retry-delay 2 --retry-connrefused --retry-all-errors \
     "http://127.0.0.1:$FORGE_PORT/api/healthz" >/dev/null 2>&1
echo "forgejo healthy"

if [ "$PUBLIC" -eq 0 ]; then
    printf '\n\033[1;32mforge is up at http://127.0.0.1:%s\033[0m\n' "$FORGE_PORT"
    echo "(local only — no public ingress. use --public to expose it.)"
    exit 0
fi

cat <<'WARN'

  ! Opening a PUBLIC inbound path to this machine.
  ! On a work-managed machine this bypasses the corporate firewall and is
  ! very likely a policy violation. Ctrl-C now if this is that machine.

WARN

say "starting cloudflare quick tunnel"
CF=$(cat .cloudflared-path)
pkill -f 'cloudflared.*tunnel.*--url' >/dev/null 2>&1 || true
rm -f tunnel.log
"$CF" tunnel --url "http://localhost:$FORGE_PORT" --no-autoupdate > tunnel.log 2>&1 &

URL=""
for _ in $(seq 1 40); do
    URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' tunnel.log 2>/dev/null | head -1) || true
    [ -n "$URL" ] && break
    sleep 1
done
[ -n "$URL" ] || { echo "FAILED: no tunnel URL after 40s"; tail -20 tunnel.log; exit 1; }
echo "$URL" > .tunnel-url
echo "tunnel: $URL"

say "pointing the worker at it"
(cd worker && printf '%s' "$URL" | npx wrangler secret put FORGE_ORIGIN >/dev/null)

say "verifying end to end"
code=000
for _ in $(seq 1 20); do
    code=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' "$WORKER_URL/api/healthz" 2>/dev/null || echo 000)
    [ "$code" = "200" ] && break
    sleep 3
done
[ "$code" = "200" ] || { echo "FAILED: worker -> forge returned $code"; exit 1; }

printf '\n\033[1;32mforge is public at %s\033[0m\n' "$WORKER_URL"
printf 'stop the tunnel with: pkill -f cloudflared\n'

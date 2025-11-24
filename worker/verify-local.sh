#!/usr/bin/env bash
# Reproduce the local end-to-end validation of the proxy without touching
# Oracle, Cloudflare, or Tailscale. Requires docker + node.
#
#   ./verify-local.sh
#
# Brings up Forgejo 15 LTS on 127.0.0.1:3001, runs `wrangler dev` on :8788,
# then pushes and clones a repo with a 5 MB blob straight through the Worker
# and compares git object IDs on both sides.
set -Eeuo pipefail
cd "$(dirname "$0")"

FORGE_PORT=3001
PROXY_PORT=8788
USER=probeadmin
PASS='Probe-Passw0rd!x9'
PASS_URL='Probe-Passw0rd%21x9'
WORK=$(mktemp -d)

cleanup() {
    docker rm -f forgejo-lean-test >/dev/null 2>&1 || true
    pkill -f 'wrangler.*dev.*'"$PROXY_PORT" >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }

say "starting forgejo $FORGE_PORT"
sed -e '/\/etc\/timezone/d' -e '/\/etc\/localtime/d' \
    -e 's#- \./data:/data#- forgeverify:/data#' \
    -e 's/container_name: forgejo/container_name: forgejo-lean-test/' \
    -e "s#\"127.0.0.1:3000:3000\"#\"127.0.0.1:$FORGE_PORT:3000\"#" \
    ../server/compose.yml > "$WORK/compose.yml"
printf '\nvolumes:\n  forgeverify:\n' >> "$WORK/compose.yml"
cat > "$WORK/.env" <<ENVEOF
FORGE_ROOT_URL=http://localhost:$PROXY_PORT/
FORGE_DOMAIN=localhost
FORGE_COOKIE_SECURE=false
ENVEOF
docker compose -f "$WORK/compose.yml" --env-file "$WORK/.env" up -d
curl -fsS --retry 60 --retry-delay 2 --retry-connrefused --retry-all-errors \
     "http://127.0.0.1:$FORGE_PORT/api/healthz" >/dev/null 2>&1
echo "forgejo healthy"

say "creating admin (only path once registration is disabled)"
docker exec -u git forgejo-lean-test forgejo admin user create --admin \
    --username "$USER" --email probe@local.test --password "$PASS" \
    --must-change-password=false

say "starting wrangler dev on $PROXY_PORT"
WRANGLER_SEND_METRICS=false npx wrangler dev --port "$PROXY_PORT" --ip 127.0.0.1 \
    > "$WORK/wrangler.log" 2>&1 &
curl -fsS --retry 60 --retry-delay 2 --retry-connrefused --retry-all-errors \
     -o /dev/null "http://127.0.0.1:$PROXY_PORT/" 2>/dev/null
echo "proxy up"

say "creating repo via API through the proxy"
curl -fsS -u "$USER:$PASS" -X POST "http://127.0.0.1:$PROXY_PORT/api/v1/user/repos" \
    -H 'Content-Type: application/json' -d '{"name":"probe","private":true}' \
    | node -e 'const r=JSON.parse(require("fs").readFileSync(0,"utf8"));
      const want={has_issues:false,has_wiki:false,has_pull_requests:false,
                  has_projects:false,has_packages:false,has_actions:false,has_releases:true};
      let ok=true;
      for (const [k,v] of Object.entries(want)) {
        const got=r[k]; if(got!==v){ok=false; console.log("  FAIL "+k+" = "+got+" (want "+v+")");}
        else console.log("  ok   "+k+" = "+got);
      }
      if(!r.private){ok=false;console.log("  FAIL repo not private by default");}
      process.exit(ok?0:1)'
echo "lean-UI units verified"

say "git ref advertisement (smart HTTP v2)"
curl -fsS -u "$USER:$PASS" -H 'Git-Protocol: version=2' \
    -o "$WORK/refs" -w '  content-type: %{content_type}\n' \
    "http://127.0.0.1:$PROXY_PORT/$USER/probe.git/info/refs?service=git-upload-pack"
grep -q 'version 2' "$WORK/refs" && echo "  protocol v2 negotiated"

say "push 5 MB through the proxy, clone back, compare object IDs"
mkdir -p "$WORK/probe" && cd "$WORK/probe"
git init -q -b main && git config user.email t@l && git config user.name t
echo readme > README.md
head -c 5000000 /dev/urandom | base64 > big.txt
git add -A && git commit -qm probe
git remote add origin "http://$USER:$PASS_URL@127.0.0.1:$PROXY_PORT/$USER/probe.git"
git push -q -u origin main
cd "$WORK" && git clone -q "http://$USER:$PASS_URL@127.0.0.1:$PROXY_PORT/$USER/probe.git" cloned

A=$(cd "$WORK/probe" && git rev-parse HEAD^{tree})
B=$(cd "$WORK/cloned" && git rev-parse HEAD^{tree})
SA=$(cd "$WORK/probe"  && git cat-file blob HEAD:big.txt | sha256sum | cut -d' ' -f1)
SB=$(cd "$WORK/cloned" && git cat-file blob HEAD:big.txt | sha256sum | cut -d' ' -f1)
echo "  tree  local=$A"
echo "  tree remote=$B"
[ "$A" = "$B" ] || { echo "FAIL: tree mismatch"; exit 1; }
echo "  blob  local=$SA"
echo "  blob remote=$SB"
[ "$SA" = "$SB" ] || { echo "FAIL: blob content mismatch"; exit 1; }
if ! (cd "$WORK/cloned" && git fsck --no-progress) >"$WORK/fsck.log" 2>&1; then
    echo "FAIL: git fsck reported problems"; cat "$WORK/fsck.log"; exit 1
fi
echo "  git fsck clean"
printf '\n\033[1;32mPASS — 5 MB round-tripped through the Worker byte-for-byte\033[0m\n'

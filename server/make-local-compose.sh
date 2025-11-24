#!/usr/bin/env bash
# Derive compose.local.yml from compose.yml for running on a Windows/macOS dev box.
# Differences: named volume instead of a bind mount (avoids host uid/gid issues and
# is much faster than a bind mount through the Docker Desktop VM), and no
# /etc/timezone mounts (those paths do not exist on Windows).
# Re-run this after editing compose.yml.
set -Eeuo pipefail
cd "$(dirname "$0")"
sed -e '/\/etc\/timezone/d' -e '/\/etc\/localtime/d' \
    -e 's#- \./data:/data#- forgedata:/data#' \
    compose.yml > compose.local.yml
printf '\nvolumes:\n  forgedata:\n' >> compose.local.yml
echo "wrote compose.local.yml"

#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
sed -e '/\/etc\/timezone/d' -e '/\/etc\/localtime/d' \
    -e 's#- \./data:/data#- forgedata:/data#' \
    compose.yml > compose.local.yml
printf '\nvolumes:\n  forgedata:\n' >> compose.local.yml
echo "wrote compose.local.yml"

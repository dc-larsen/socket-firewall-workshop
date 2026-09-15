#!/usr/bin/env bash
# Stop the rig and remove generated local state.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
head_ "Socket Firewall demo - stopping"
docker compose --project-directory "$ROOT" down >/dev/null 2>&1 && ok "container removed" || warn "container was not running"
rm -f "${ROOT}/demo/app/.npmrc" "${ROOT}/demo/payments-service/.npmrc" "$CA"
rm -rf "${ROOT}/demo/app/node_modules" "${ROOT}/demo/app/package-lock.json" "${ROOT}/demo/payments-service/node_modules"
reset_app_manifest   # npm rewrites dependencies on install; leave the repo pristine
ok "generated files cleaned, demo/app manifest reset"

#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
head_ "Socket Firewall demo - status"
if docker ps --filter 'name=^packages$' --format '{{.Names}}' | grep -q packages; then
  ok "container up: $(docker inspect -f '{{.Config.Image}}' packages)"
else
  bad "container not running (run scripts/up.sh)"; exit 1
fi
filt=$(grep -A1 '^metadata_filtering:' "${ROOT}/socket.yml" | awk '/enabled:/{print $2}')
printf '  metadata filtering: %s%s%s\n' "$c_bold" "$filt" "$c_off"
[ -f "$CA" ] && ok "CA exported" || warn "CA missing (run scripts/up.sh)"
code=$(curl_fw -m 15 -o /dev/null -w '%{http_code}' "${BASE}/npm/lodash" 2>/dev/null)
[ "$code" = "200" ] && ok "serving package metadata (200)" || bad "metadata request returned $code"

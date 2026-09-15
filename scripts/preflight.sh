#!/usr/bin/env bash
# Verify every demo beat against the live Socket API before you walk into a call.
#
# Live malware is the one thing in this demo that can rot: npm removes packages,
# and a removed package makes `npm install <pkg>` fail at resolution with a
# generic "no matching version" instead of a Socket 403. This script catches that
# while you still have time to swap a package.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# beat | package path on the firewall | expected code | label
BEATS=(
  "allow|lodash/-/lodash-4.17.21.tgz|200|lodash 4.17.21 installs clean"
  "block|aegularjs/-/aegularjs-1.1.2.tgz|403|aegularjs 1.1.2 - angularjs typosquat, malware"
  "block|get-power/-/get-power-1.0.3.tgz|403|get-power 1.0.3 - malware + recently published"
  "block|form-data/-/form-data-2.3.3.tgz|403|form-data 2.3.3 - critical CVE, not malware"
  "block|axios/-/axios-1.14.1.tgz|403|axios 1.14.1 - malicious transitive dependency"
)

fails=0
head_ "Socket Firewall demo - preflight"

docker ps --filter 'name=^packages$' --format '{{.Names}}' | grep -q packages \
  || { bad "container not running - run scripts/up.sh first"; exit 1; }
ok "container up"
[ -f "$CA" ] || { bad "CA missing - run scripts/up.sh"; exit 1; }
ok "CA present"
wait_ready 20 && ok "serving live package metadata" || { bad "firewall not ready"; exit 1; }

head_ "Beats"
for row in "${BEATS[@]}"; do
  IFS='|' read -r kind path want label <<<"$row"
  code="$(probe_code "$path")"
  if [ "$code" != "$want" ]; then
    bad "$label"
    printf '      expected HTTP %s, got %s\n' "$want" "$code"
    if [ "$kind" = "block" ] && [ "$code" = "404" ]; then
      printf '      %slikely removed from npm - swap this package (see README)%s\n' "$c_yel" "$c_off"
    fi
    fails=$((fails+1)); continue
  fi
  if [ "$kind" = "block" ]; then
    notice="$(probe_notice "$path")"
    if [ -z "$notice" ]; then
      bad "$label - blocked but no npm-notice header (developer would see no reason)"
      fails=$((fails+1)); continue
    fi
    ok "$label"
    printf '      %s%s%s\n' "$c_dim" "$(printf '%s' "$notice" | cut -c1-150)…" "$c_off"
  else
    ok "$label"
  fi
done

head_ "Config"
filt=$(grep -A1 '^metadata_filtering:' "${ROOT}/socket.yml" | awk '/enabled:/{print $2}')
if [ "$filt" = "false" ]; then
  ok "metadata filtering off - blocks are loud and carry a reason"
else
  warn "metadata filtering is ON - blocked versions vanish silently, no Socket message"
  warn "run scripts/filtering.sh off before demoing the block message"
fi

echo
if [ "$fails" -eq 0 ]; then
  printf '%s  PREFLIGHT PASS - every beat verified against the live API%s\n\n' "$c_grn" "$c_off"
else
  printf '%s  PREFLIGHT FAIL - %s beat(s) need attention%s\n\n' "$c_red" "$fails" "$c_off"
  exit 1
fi

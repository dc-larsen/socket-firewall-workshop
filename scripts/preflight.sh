#!/usr/bin/env bash
# Verify every demo beat against the live Socket API before you walk into a call.
#
# Two things rot silently and both have burned a demo:
#   1. npm removes a malware package, so the install fails at resolution with a
#      generic "no matching version" instead of a Socket 403.
#   2. The token points at a different org, whose policy has the driving rule at
#      warn/monitor/ignore instead of error, so the package sails through.
# This script names which one happened while you still have time to adjust.
#
# The beat list lives in _common.sh. Both the probed tarball path and the printed
# command are derived from it, so what is verified is what you type.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

fails=0
skip=""
head_ "Socket Firewall demo - preflight"

docker ps --filter 'name=^packages$' --format '{{.Names}}' | grep -q packages \
  || { bad "container not running - run scripts/up.sh first"; exit 1; }
ok "container up"
[ -f "$CA" ] || { bad "CA missing - run scripts/up.sh"; exit 1; }
ok "CA present"

# Which org are we actually enforcing as? Every verdict below depends on it.
slug=""
if load_env; then
  org="$(api_org_slug)"
  if [ -n "$org" ]; then
    slug="${org%% *}"
    ok "token resolves to org: ${c_bold}${org}${c_off}"
  else
    warn "token did not resolve to an org - policy diagnosis will be skipped"
  fi
else
  warn "no token in .env - policy diagnosis will be skipped"
fi

# The bypass guard. A demo command run outside these directories goes straight to
# registry.npmjs.org and nothing is inspected, which looks exactly like "the
# firewall let it through".
for d in app payments-service; do
  if npmrc_ok "${ROOT}/demo/${d}"; then
    ok "demo/${d} wired to the firewall (.npmrc)"
  else
    bad "demo/${d} has no .npmrc pointing at the firewall - run scripts/up.sh"
    fails=$((fails+1))
  fi
done

wait_ready 20 && ok "serving live package metadata" || { bad "firewall not ready"; exit 1; }

head_ "Beats"
for row in "${DEMO_BEATS[@]}"; do
  IFS='|' read -r pkg ver want dir mode rule label <<<"$row"
  path="$(beat_path "$pkg" "$ver")"
  cmd="$(beat_cmd "$pkg" "$ver" "$mode")"
  code="$(probe_code "$path")"

  if [ "$code" != "$want" ]; then
    bad "${pkg} ${ver} - ${label}"
    printf '      expected HTTP %s, got %s   %s(%s)%s\n' "$want" "$code" "$c_dim" "$cmd" "$c_off"
    if [ "$want" = "403" ] && [ "$code" = "404" ]; then
      printf '      %sremoved from npm - swap it: scripts/find-packages.sh%s\n' "$c_yel" "$c_off"
    elif [ "$want" = "403" ] && [ "$code" = "200" ]; then
      # Not blocked. Either the verdict was reversed or this org does not gate on
      # the driving rule. The policy lookup tells you which, and no package swap
      # fixes the second case.
      if [ -n "$slug" ] && [ "$rule" != "-" ]; then
        act="$(api_policy_action "$slug" "$rule")"
        printf '      %sorg policy has %s at "%s" - only "error" blocks%s\n' "$c_yel" "$rule" "$act" "$c_off"
        if [ "$act" != "error" ]; then
          printf '      %sno package swap fixes this; drop the beat or change the policy%s\n' "$c_yel" "$c_off"
        fi
      else
        printf '      %snot blocked - check the verdict, or this org does not gate on %s%s\n' "$c_yel" "$rule" "$c_off"
      fi
    fi
    skip="${skip} ${pkg}:${ver}"
    fails=$((fails+1)); continue
  fi

  if [ "$want" = "403" ]; then
    notice="$(probe_notice "$path")"
    if [ -z "$notice" ]; then
      bad "${pkg} ${ver} - blocked but no npm-notice header (developer sees no reason)"
      warn "metadata filtering is probably on: scripts/filtering.sh off"
      skip="${skip} ${pkg}:${ver}"
      fails=$((fails+1)); continue
    fi
    ok "${pkg} ${ver} - ${label}"
    printf '      %s%s%s\n' "$c_dim" "$(printf '%s' "$notice" | cut -c1-150)…" "$c_off"
    # A block whose reason has decayed to a bare category is a weaker demo even
    # though the status code is right. Say so rather than passing it silently.
    case "$notice" in
      *"--"*) : ;;
      *) warn "      reason is a bare category with no threat-research note - consider swapping" ;;
    esac
  else
    ok "${pkg} ${ver} - ${label}"
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
  printf '%s  PREFLIGHT PASS - every beat verified against the live API%s\n' "$c_grn" "$c_off"
else
  printf '%s  PREFLIGHT FAIL - %s beat(s) need attention%s\n' "$c_red" "$fails" "$c_off"
fi

print_commands "$skip"
[ "$fails" -eq 0 ]

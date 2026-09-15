#!/usr/bin/env bash
# Start the demo rig and leave every demo directory ready to run, so a fresh
# terminal tab needs nothing but the printed commands.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

head_ "Socket Firewall demo - starting"

if ! orb status 2>/dev/null | grep -qi running; then
  bad "OrbStack is not running. Start OrbStack, then re-run."; exit 1
fi
ok "OrbStack running"

if [ ! -f "${ROOT}/.env" ]; then
  bad "No .env file. Copy .env.example to .env and add your Socket API token."; exit 1
fi
if ! load_env; then
  bad "SOCKET_SECURITY_API_TOKEN is empty in .env"; exit 1
fi
org="$(api_org_slug)"
if [ -n "$org" ]; then
  ok "API token valid, org: ${c_bold}${org}${c_off}"
else
  warn "API token present but did not resolve to an org - check it before demoing"
fi

export_ca || exit 1
ok "OrbStack CA exported to ca-orbstack.pem"

docker compose --project-directory "$ROOT" up -d >/dev/null 2>&1 || {
  bad "docker compose up failed"; docker compose --project-directory "$ROOT" logs --tail 20; exit 1; }
ok "firewall container started ($(docker inspect -f '{{.Config.Image}}' packages 2>/dev/null))"

for d in "${ROOT}/demo/app" "${ROOT}/demo/payments-service"; do write_npmrc "$d"; done
rm -rf "${ROOT}/demo/app/node_modules" "${ROOT}/demo/payments-service/node_modules"
rm -f "${ROOT}/demo/app/package-lock.json"
# A demo-local npm cache, wiped on every start. Without this npm can serve a
# tarball from the operator's warm global cache and the beat never traverses the
# firewall at all, which makes the allow beat prove nothing.
rm -rf "$NPM_CACHE"
# npm records whatever it installs into dependencies, so demo/app/package.json is
# reset to pristine on every start. Otherwise the allow beat reports 22 packages
# because a previous run left form-data declared.
reset_app_manifest
ok "demo dirs wired to the firewall, manifest reset, demo npm cache cleared"

printf '  %s… waiting for the firewall to serve real package metadata%s\n' "$c_dim" "$c_off"
if wait_ready; then
  ok "firewall ready (live packument returned 200)"
else
  bad "firewall did not become ready. Check: docker compose logs packages"; exit 1
fi

print_commands

printf '\n  %sscripts/preflight.sh   verify every beat against the live API\n' "$c_dim"
printf '  scripts/talk.sh        print the talk track%s\n\n' "$c_off"

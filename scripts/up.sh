#!/usr/bin/env bash
# Start the demo rig and leave every demo directory ready for a bare `npm install`.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

head_ "Socket Firewall demo - starting"

if ! orb status 2>/dev/null | grep -qi running; then
  bad "OrbStack is not running. Start OrbStack, then re-run."; exit 1
fi
ok "OrbStack running"

if [ ! -f "${ROOT}/.env" ]; then
  bad "No .env file. Copy .env.example to .env and add your Socket API token."; exit 1
fi
# shellcheck disable=SC1091
set -a; source "${ROOT}/.env"; set +a
if [ -z "${SOCKET_SECURITY_API_TOKEN:-}" ]; then
  bad "SOCKET_SECURITY_API_TOKEN is empty in .env"; exit 1
fi
ok "API token present"

export_ca || exit 1
ok "OrbStack CA exported to ca-orbstack.pem"

docker compose --project-directory "$ROOT" up -d >/dev/null 2>&1 || {
  bad "docker compose up failed"; docker compose --project-directory "$ROOT" logs --tail 20; exit 1; }
ok "firewall container started ($(docker inspect -f '{{.Config.Image}}' packages 2>/dev/null))"

for d in "${ROOT}/demo/app" "${ROOT}/demo/payments-service"; do write_npmrc "$d"; done
rm -rf "${ROOT}/demo/app/node_modules" "${ROOT}/demo/payments-service/node_modules"
ok "demo directories configured"

printf '  %s… waiting for the firewall to serve real package metadata%s\n' "$c_dim" "$c_off"
if wait_ready; then
  ok "firewall ready (live packument returned 200)"
else
  bad "firewall did not become ready. Check: docker compose logs packages"; exit 1
fi

head_ "Ready. Run the demo from these directories:"
cat <<TXT
  ${ROOT}/demo/app               npm install lodash          (allowed)
                                 npm install aegularjs       (blocked - malware)
  ${ROOT}/demo/payments-service  npm ci                      (blocked - transitive)

  scripts/preflight.sh   verify every beat before a call
  scripts/talk.sh        print the talk track
TXT

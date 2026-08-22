#!/usr/bin/env bash
# Switch the firewall between manual routes and Nexus auto-discovery.
#   ./switch-config.sh manual  -> socket.manual.yml        (per-ecosystem /npm /maven /pypi)
#   ./switch-config.sh auto    -> socket.autodiscovery.yml (mode: nexus, config_mode: upstream)
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:?usage: switch-config.sh manual|auto}"

case "$MODE" in
  manual)
    cp socket.manual.yml socket.yml
    ;;
  auto)
    cp socket.autodiscovery.yml socket.yml
    # Auto-discovery needs Nexus API credentials. PRIVATE_REGISTRY_KEY takes
    # precedence over any api_key in socket.yml; socket.yml cannot expand env
    # vars itself.
    PASS=$(docker exec nexus-rig-nexus cat /nexus-data/admin.password 2>/dev/null || true)
    PASS="${PASS:-${NEXUS_ADMIN_PASS:-}}"
    if [ -z "$PASS" ]; then
      echo "No Nexus admin password available (set NEXUS_ADMIN_PASS)" >&2
      exit 1
    fi
    grep -v '^PRIVATE_REGISTRY_KEY=' .env.secrets > .env.secrets.tmp || true
    echo "PRIVATE_REGISTRY_KEY=admin:$PASS" >> .env.secrets.tmp
    mv .env.secrets.tmp .env.secrets
    ;;
  *)
    echo "usage: switch-config.sh manual|auto" >&2
    exit 1
    ;;
esac

docker compose up -d --force-recreate firewall
echo "Firewall restarted with $MODE config."

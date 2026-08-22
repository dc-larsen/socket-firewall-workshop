#!/usr/bin/env bash
# Provision Nexus for the Upstream topology test:
#   - wait for Nexus to finish booting (2-3 min on first start)
#   - enable anonymous read access
#   - create npm/maven/pypi proxy repos whose Remote storage URL points at
#     the Socket firewall's per-ecosystem routes
set -euo pipefail

NEXUS_URL="http://localhost:8081"

echo "Waiting for Nexus to come up (first boot takes 2-3 minutes)..."
for i in $(seq 1 90); do
  if curl -sf "$NEXUS_URL/service/rest/v1/status" >/dev/null 2>&1; then
    break
  fi
  sleep 5
  if [ "$i" -eq 90 ]; then
    echo "Nexus did not come up in time" >&2
    exit 1
  fi
done
echo "Nexus is up."

# First-boot admin password lives in the data volume until it is changed.
ADMIN_PASS=$(docker exec nexus-rig-nexus cat /nexus-data/admin.password 2>/dev/null || true)
if [ -z "$ADMIN_PASS" ]; then
  echo "admin.password not found (already changed?). Set NEXUS_ADMIN_PASS and re-run." >&2
  ADMIN_PASS="${NEXUS_ADMIN_PASS:?}"
fi
AUTH="admin:$ADMIN_PASS"
echo "Admin password captured (docker exec nexus-rig-nexus cat /nexus-data/admin.password)."

# Anonymous read so npm/pip/maven clients need no credentials for the test.
curl -sf -u "$AUTH" -X PUT "$NEXUS_URL/service/rest/v1/security/anonymous" \
  -H 'Content-Type: application/json' \
  -d '{"enabled": true, "userId": "anonymous", "realmName": "NexusAuthorizingRealm"}' >/dev/null
echo "Anonymous access enabled."

# Nexus Community Edition refuses to serve proxied content until the EULA
# is accepted (403 on binary fetches). Accept it via REST: the POST must echo
# back the exact disclaimer string the GET returns.
curl -s -u "$AUTH" "$NEXUS_URL/service/rest/v1/system/eula" -o /tmp/nexus-eula.json
python3 -c "import json; d=json.load(open('/tmp/nexus-eula.json')); d['accepted']=True; json.dump(d, open('/tmp/nexus-eula-accept.json','w'))"
curl -sf -u "$AUTH" -X POST "$NEXUS_URL/service/rest/v1/system/eula" \
  -H 'Content-Type: application/json' -d @/tmp/nexus-eula-accept.json
echo "EULA accepted."

# Nexus 3.7x+ SSRF protection rejects proxy remote URLs that resolve to
# private IPs — which the in-network "firewall" hostname does. Allow it.
# (Real deployments with a public firewall hostname never hit this.)
curl -sf -u "$AUTH" -X PUT "$NEXUS_URL/service/rest/v1/security/ssrf-protection" \
  -H 'Content-Type: application/json' \
  -d '{"enabled": true, "allowedIPs": [], "allowedDomains": ["firewall"]}' >/dev/null
echo "SSRF allowlist updated (domain: firewall)."

create_repo() {
  local kind="$1" body="$2" name="$3"
  code=$(curl -s -o /tmp/nexus-repo-resp -w "%{http_code}" -u "$AUTH" -X POST \
    "$NEXUS_URL/service/rest/v1/repositories/$kind/proxy" \
    -H 'Content-Type: application/json' -d "$body")
  if [ "$code" = "201" ]; then
    echo "Created $name."
  elif [ "$code" = "400" ] && grep -q "already exists" /tmp/nexus-repo-resp 2>/dev/null; then
    echo "$name already exists, leaving as-is."
  else
    echo "Failed to create $name (HTTP $code):" >&2
    cat /tmp/nexus-repo-resp >&2
    exit 1
  fi
}

# autoBlock=false: a transient firewall error must not quietly disable the
# repo mid-test. metadataMaxAge=5 min so firewall policy changes surface fast.
create_repo npm '{
  "name": "npm-proxy",
  "online": true,
  "storage": {"blobStoreName": "default", "strictContentTypeValidation": true},
  "proxy": {"remoteUrl": "http://firewall/npm", "contentMaxAge": 1440, "metadataMaxAge": 5},
  "negativeCache": {"enabled": false, "timeToLive": 1440},
  "httpClient": {"blocked": false, "autoBlock": false}
}' npm-proxy

create_repo maven '{
  "name": "maven-central-proxy",
  "online": true,
  "storage": {"blobStoreName": "default", "strictContentTypeValidation": true},
  "proxy": {"remoteUrl": "http://firewall/maven", "contentMaxAge": 1440, "metadataMaxAge": 5},
  "negativeCache": {"enabled": false, "timeToLive": 1440},
  "httpClient": {"blocked": false, "autoBlock": false},
  "maven": {"versionPolicy": "RELEASE", "layoutPolicy": "PERMISSIVE", "contentDisposition": "INLINE"}
}' maven-central-proxy

create_repo pypi '{
  "name": "pypi-proxy",
  "online": true,
  "storage": {"blobStoreName": "default", "strictContentTypeValidation": true},
  "proxy": {"remoteUrl": "http://firewall/pypi", "contentMaxAge": 1440, "metadataMaxAge": 5},
  "negativeCache": {"enabled": false, "timeToLive": 1440},
  "httpClient": {"blocked": false, "autoBlock": false}
}' pypi-proxy

echo
echo "Done. Repos:"
curl -s -u "$AUTH" "$NEXUS_URL/service/rest/v1/repositories" | python3 -c '
import json,sys
for r in json.load(sys.stdin):
    print("  %-24s %-8s %-7s %s" % (r["name"], r["format"], r["type"], r.get("url","")))'

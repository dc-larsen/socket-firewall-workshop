#!/usr/bin/env bash
# Switch the proxy repos to https://firewall remotes with the Nexus truststore.
# Needed because the firewall rewrites tarball/asset URLs in metadata to
# https://firewall/... — Nexus follows those absolute URLs, so it must trust
# the firewall cert. (Hosted tenants have a public CA cert; skip all of this.)
set -euo pipefail
cd "$(dirname "$0")"

NEXUS_URL="http://localhost:8081"
PASS=$(docker exec nexus-rig-nexus cat /nexus-data/admin.password 2>/dev/null || echo "${NEXUS_ADMIN_PASS:?}")
AUTH="admin:$PASS"

# Import the firewall cert (idempotent-ish: 400 "already exists" is fine).
curl -s -o /dev/null -u "$AUTH" -X POST "$NEXUS_URL/service/rest/v1/security/ssl/truststore" \
  -H 'Content-Type: application/json' --data-binary @ssl/fullchain.pem || true

update_repo() {
  local kind="$1" name="$2" body="$3"
  code=$(curl -s -o /tmp/nexus-upd-resp -w "%{http_code}" -u "$AUTH" -X PUT \
    "$NEXUS_URL/service/rest/v1/repositories/$kind/proxy/$name" \
    -H 'Content-Type: application/json' -d "$body")
  if [ "$code" = "204" ]; then
    echo "Updated $name -> https remote + truststore."
  else
    echo "Failed to update $name (HTTP $code):" >&2
    cat /tmp/nexus-upd-resp >&2
    exit 1
  fi
}

update_repo npm npm-proxy '{
  "name": "npm-proxy",
  "online": true,
  "storage": {"blobStoreName": "default", "strictContentTypeValidation": true},
  "proxy": {"remoteUrl": "https://firewall:8443/npm", "contentMaxAge": 1440, "metadataMaxAge": 5},
  "negativeCache": {"enabled": false, "timeToLive": 1440},
  "httpClient": {"blocked": false, "autoBlock": false, "connection": {"useTrustStore": true}}
}'

update_repo maven maven-central-proxy '{
  "name": "maven-central-proxy",
  "online": true,
  "storage": {"blobStoreName": "default", "strictContentTypeValidation": true},
  "proxy": {"remoteUrl": "https://firewall:8443/maven", "contentMaxAge": 1440, "metadataMaxAge": 5},
  "negativeCache": {"enabled": false, "timeToLive": 1440},
  "httpClient": {"blocked": false, "autoBlock": false, "connection": {"useTrustStore": true}},
  "maven": {"versionPolicy": "RELEASE", "layoutPolicy": "PERMISSIVE", "contentDisposition": "INLINE"}
}'

update_repo pypi pypi-proxy '{
  "name": "pypi-proxy",
  "online": true,
  "storage": {"blobStoreName": "default", "strictContentTypeValidation": true},
  "proxy": {"remoteUrl": "https://firewall:8443/pypi", "contentMaxAge": 1440, "metadataMaxAge": 5},
  "negativeCache": {"enabled": false, "timeToLive": 1440},
  "httpClient": {"blocked": false, "autoBlock": false, "connection": {"useTrustStore": true}}
}'

# Drop cached npm metadata so rewritten URLs are refetched fresh.
curl -s -o /dev/null -u "$AUTH" -X POST \
  "$NEXUS_URL/service/rest/v1/repositories/npm-proxy/invalidate-cache" || true
echo "npm-proxy cache invalidated."

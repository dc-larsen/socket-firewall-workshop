#!/usr/bin/env bash
# Stale-pooled-connection test against a RELEASED firewall image.
#
# The middlebox answers request #1 on a TCP connection normally (keep-alive),
# then closes the socket on the reused request #2 -- what an idle keepalive
# connection silently dropped by an LB/NAT looks like to the firewall.
# safe-buffer@5.2.1 is a real, allowed npm package, so the Socket API verdict
# passes and the request reaches the upstream (middlebox) download path.
#
# Usage: FW_TAG=2.3.2 ./run-stale.sh
set -euo pipefail
cd "$(dirname "$0")"

TAG="${FW_TAG:?set FW_TAG (e.g. 2.3.2)}"
echo "=== firewall ${TAG}, config socket.stale.yml ==="
FW_TAG="${TAG}" SOCKET_CONFIG=socket.stale.yml \
  docker compose up -d --force-recreate --wait firewall >/dev/null 2>&1

for i in 1 2 3; do
  code=$(docker exec metlife-client python -c "
import ssl, urllib.request
ctx = ssl._create_unverified_context()
try:
    r = urllib.request.urlopen('https://ossfw.metlife.test/npm/safe-buffer/-/safe-buffer-5.2.1.tgz', context=ctx, timeout=30)
    print(r.status)
except urllib.error.HTTPError as e:
    print(e.code)
except Exception as e:
    print('ERR', type(e).__name__)
" || echo "000")
  echo "download #${i}: HTTP ${code}"
done

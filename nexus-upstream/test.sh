#!/usr/bin/env bash
# End-to-end tests for the Nexus -> Socket Firewall Upstream topology.
# Run after setup-nexus.sh with the manual config active.
set -uo pipefail

NEXUS="http://localhost:8081"
FW="http://localhost:9180"
PASS_COUNT=0
FAIL_COUNT=0

check() {  # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "PASS  $1 ($3)"
    PASS_COUNT=$((PASS_COUNT+1))
  else
    echo "FAIL  $1 (expected $2, got $3)"
    FAIL_COUNT=$((FAIL_COUNT+1))
  fi
}

echo "== Firewall direct =="
# Host header required: path routing binds server_name "firewall". Nexus sends
# it naturally (its remote URL is http://firewall/...); host-side curl must fake it.
check "firewall /health"        200 "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: firewall' $FW/health)"
check "firewall /npm/lodash"    200 "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: firewall' $FW/npm/lodash)"
check "firewall bare /lodash"   404 "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: firewall' $FW/lodash)"

echo
echo "== npm through Nexus (safe package) =="
check "nexus npm-proxy lodash metadata" 200 \
  "$(curl -s -o /dev/null -w '%{http_code}' $NEXUS/repository/npm-proxy/lodash)"
check "nexus npm-proxy lodash tarball" 200 \
  "$(curl -s -o /dev/null -w '%{http_code}' $NEXUS/repository/npm-proxy/lodash/-/lodash-4.17.21.tgz)"

echo
echo "== npm through Nexus (blocked package: jscrambler@8.14.0, known malware) =="
# Metadata filtering checks the NEWEST 100 versions only (bounded work, logged
# as "checking 100 versions (newest first)"). jscrambler@8.14.0 has been pushed
# out of that window by newer releases, so its presence in metadata is expected;
# the download-layer 403 below is the enforcement that blocks the install.
META=$(curl -s $NEXUS/repository/npm-proxy/jscrambler)
if echo "$META" | grep -q '"8.14.0"'; then
  echo "NOTE  8.14.0 present in metadata (outside newest-100 filter window; download layer enforces)"
else
  echo "PASS  blocked version 8.14.0 stripped from metadata (inside filter window)"
  PASS_COUNT=$((PASS_COUNT+1))
fi
if echo "$META" | grep -q '"8.15.0"'; then
  echo "PASS  clean version 8.15.0 still served"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "FAIL  clean version 8.15.0 missing from metadata"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
# Tarball via Nexus: firewall answers 403 (x-socket-decision: blocked,
# x-socket-block-reason: Known malware); Nexus surfaces that to the client as
# 404 {"success":false,"error":"Package 'jscrambler' not found"} — the same
# translation Artifactory does (403 -> 404). A working block therefore looks
# like "package/version not found" to developers, NOT like a security error.
check "blocked tarball via Nexus (403->404 translation)" 404 \
  "$(curl -s -o /dev/null -w '%{http_code}' $NEXUS/repository/npm-proxy/jscrambler/-/jscrambler-8.14.0.tgz)"
# Direct to the firewall the truth is visible:
DECISION=$(curl -s -o /dev/null -D - -H 'Host: firewall' $FW/npm/jscrambler/-/jscrambler-8.14.0.tgz | grep -i x-socket-decision | tr -d '\r' | awk '{print $2}')
check "firewall x-socket-decision header" blocked "${DECISION:-none}"

echo
echo "== maven through Nexus =="
check "junit 4.13.2 pom" 200 \
  "$(curl -s -o /dev/null -w '%{http_code}' $NEXUS/repository/maven-central-proxy/junit/junit/4.13.2/junit-4.13.2.pom)"
check "junit 4.13.2 jar" 200 \
  "$(curl -s -o /dev/null -w '%{http_code}' $NEXUS/repository/maven-central-proxy/junit/junit/4.13.2/junit-4.13.2.jar)"

echo
echo "== pypi through Nexus =="
check "requests simple index" 200 \
  "$(curl -s -o /dev/null -w '%{http_code}' $NEXUS/repository/pypi-proxy/simple/requests/)"

echo
echo "== bypass check: did traffic actually traverse the firewall? =="
# grep -c (not -q): -q closes the pipe early and, with pipefail, docker logs'
# SIGPIPE exit poisons the pipeline status.
LOGFILE=$(mktemp)
docker logs nexus-rig-firewall >"$LOGFILE" 2>&1
if [ "$(grep -c 'lodash' "$LOGFILE")" -gt 0 ]; then
  echo "PASS  firewall logs show lodash traffic"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "FAIL  no lodash entries in firewall logs — Nexus may be bypassing the firewall"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi
if [ "$(grep -c 'Known malware' "$LOGFILE")" -gt 0 ]; then
  echo "PASS  firewall logged the malware block (Known malware)"
  PASS_COUNT=$((PASS_COUNT+1))
else
  echo "WARN  no malware block line found (check docker logs nexus-rig-firewall)"
fi
rm -f "$LOGFILE"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
exit $([ "$FAIL_COUNT" -eq 0 ] && echo 0 || echo 1)

#!/usr/bin/env bash
# Shared helpers for the Socket Firewall demo rig.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="packages.orb.local"
BASE="https://${HOST}"
CA="${ROOT}/ca-orbstack.pem"
ORB_CA_NAME="OrbStack Development Root CA"

c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_dim=$'\033[2m'; c_bold=$'\033[1m'; c_off=$'\033[0m'
ok()   { printf '  %s✓%s %s\n' "$c_grn" "$c_off" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$c_red" "$c_off" "$1"; }
warn() { printf '  %s!%s %s\n' "$c_yel" "$c_off" "$1"; }
head_() { printf '\n%s%s%s\n' "$c_bold" "$1" "$c_off"; }

# Export the OrbStack root CA so Node/npm can verify the TLS OrbStack terminates.
# Node does not read the macOS keychain, so a file is required.
export_ca() {
  security find-certificate -a -c "$ORB_CA_NAME" -p > "$CA" 2>/dev/null
  if ! grep -q "BEGIN CERTIFICATE" "$CA" 2>/dev/null; then
    bad "Could not export '$ORB_CA_NAME' from the macOS keychain."
    echo "     Open OrbStack once so it installs its CA, then re-run."
    return 1
  fi
  return 0
}

# Write the .npmrc that makes the demo command a bare `npm install`.
# cafile must be absolute: npm resolves it relative to the process cwd.
write_npmrc() {
  local dir="$1"
  cat > "${dir}/.npmrc" <<NPMRC
registry=${BASE}/npm/
cafile=${CA}
ignore-scripts=true
audit=false
fund=false
NPMRC
}

curl_fw() { curl -s --cacert "$CA" "$@"; }

# Readiness: /health answers 200 while the Lua workers are still warming, and the
# first real package request then 502s. Probe an actual packument instead.
wait_ready() {
  local tries="${1:-40}" code=""
  for _ in $(seq 1 "$tries"); do
    code="$(curl_fw -m 15 -o /dev/null -w '%{http_code}' "${BASE}/npm/lodash" 2>/dev/null)"
    [ "$code" = "200" ] && return 0
    sleep 3
  done
  return 1
}

# HTTP status for a package tarball, straight through the download gate.
probe_code() { curl_fw -m 40 -o /dev/null -w '%{http_code}' "${BASE}/npm/$1" 2>/dev/null; }
# The npm-notice header is what the npm CLI prints in the developer's terminal.
probe_notice() {
  curl_fw -m 40 -o /dev/null -D - "${BASE}/npm/$1" 2>/dev/null \
    | tr -d '\r' | awk 'tolower($1)=="npm-notice:"{sub(/^[^:]*: /,""); print}'
}

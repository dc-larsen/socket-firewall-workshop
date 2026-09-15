#!/usr/bin/env bash
# Shared helpers for the Socket Firewall demo rig.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="packages.orb.local"
BASE="https://${HOST}"
CA="${ROOT}/ca-orbstack.pem"
NPM_CACHE="${ROOT}/.npm-cache"
ORB_CA_NAME="OrbStack Development Root CA"

# ---------------------------------------------------------------------------
# The beat list: single source of truth for what preflight verifies AND what the
# operator types. Both the tarball path and the printed command are derived from
# the pkg + version fields below, so they cannot drift apart.
#
# EVERY BEAT IS PINNED, deliberately. Block beats are version-specific, and the
# `latest` version of a malware package is usually clean. An unpinned
# `npm install <pkg>` therefore resolves to a clean version, succeeds, and the
# demo shows nothing at all. Verified live 2026-09-14 on firewall 2.6.1:
#   aegularjs 1.1.2  -> 403 with the full threat-research note
#   aegularjs 8.7.6  -> 200, installs  (dist-tag `latest`, no malware alert)
# Never print a bare package name as a demo command.
#
# fields: pkg | version | expect | dir | mode | policy rule | label
DEMO_BEATS=(
  "lodash|4.18.1|200|app|install|-|allow control, installs clean"
  "aegularjs|1.1.2|403|app|install|malware|typosquat of angularjs, confirmed malware"
  "get-power|1.0.3|403|app|install|malware|confirmed malware"
  "form-data|2.3.3|403|app|install|criticalCVE|critical CVE, not malware"
  "axios|1.14.1|403|payments-service|ci|malware|malicious transitive dependency"
)

# Tarball path on the firewall, derived from pkg + version.
beat_path() { printf '%s/-/%s-%s.tgz' "$1" "$1" "$2"; }
# The command the operator types, derived from the same fields.
# `ci` mode installs from the committed lockfile, so its pin lives there.
beat_cmd() {
  if [ "$3" = "ci" ]; then printf 'npm ci'; else printf 'npm install %s@%s' "$1" "$2"; fi
}

c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_dim=$'\033[2m'; c_bold=$'\033[1m'; c_off=$'\033[0m'
ok()   { printf '  %s✓%s %s\n' "$c_grn" "$c_off" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$c_red" "$c_off" "$1"; }
warn() { printf '  %s!%s %s\n' "$c_yel" "$c_off" "$1"; }
head_() { printf '\n%s%s%s\n' "$c_bold" "$1" "$c_off"; }

load_env() {
  # shellcheck disable=SC1091
  [ -f "${ROOT}/.env" ] && { set -a; source "${ROOT}/.env"; set +a; }
  [ -n "${SOCKET_SECURITY_API_TOKEN:-}" ]
}

# Org the token actually resolves to. Blocks are evaluated against THIS org's
# policy, so swapping the token re-rolls every beat.
api_org_slug() {
  curl -s -m 20 -u "${SOCKET_SECURITY_API_TOKEN}:" https://api.socket.dev/v0/organizations 2>/dev/null \
    | python3 -c 'import json,sys
try:
    o=json.load(sys.stdin).get("organizations",{})
    v=next(iter(o.values()))
    print("%s (%s)"%(v.get("slug"),v.get("id")))
except Exception:
    print("")' 2>/dev/null
}

# Action configured for one security-policy rule: error | warn | monitor | ignore.
# Only `error` blocks. This is what turns a mystery 200 into a named cause.
api_policy_action() {
  local slug="$1" rule="$2"
  curl -s -m 20 -u "${SOCKET_SECURITY_API_TOKEN}:" \
    "https://api.socket.dev/v0/orgs/${slug}/settings/security-policy" 2>/dev/null \
    | python3 -c 'import json,sys
rule=sys.argv[1]
try:
    d=json.load(sys.stdin)
    r=d.get("securityPolicyRules",d)
    print(r.get(rule,{}).get("action","unset"))
except Exception:
    print("unknown")' "$rule" 2>/dev/null
}

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

# Write the .npmrc that points npm at the firewall.
# cafile must be absolute: npm resolves it relative to the process cwd.
# prefer-online + a demo-local cache dir mean every beat provably traverses the
# firewall instead of being served from a warm global cache, without touching
# the operator's real ~/.npm.
write_npmrc() {
  local dir="$1"
  cat > "${dir}/.npmrc" <<NPMRC
registry=${BASE}/npm/
cafile=${CA}
cache=${NPM_CACHE}
prefer-online=true
ignore-scripts=true
audit=false
fund=false
NPMRC
}

# True when this directory is wired to the firewall. Guards the failure mode
# where the command is run from \$HOME and silently hits registry.npmjs.org.
npmrc_ok() { grep -q "^registry=${BASE}/npm/\$" "$1/.npmrc" 2>/dev/null; }

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

# demo/app must start with no declared dependencies so the allow beat is
# genuinely one package. npm rewrites this file on every install, so it is
# regenerated rather than trusted.
reset_app_manifest() {
  cat > "${ROOT}/demo/app/package.json" <<'JSON'
{
  "name": "checkout-api",
  "version": "1.0.0",
  "private": true,
  "description": "Demo project. The .npmrc here points npm at the firewall."
}
JSON
}

# The copy-paste block for a fresh terminal tab. The cd is load-bearing: the
# .npmrc is per-directory, so the same command run anywhere else bypasses the
# firewall entirely and inspects nothing.
#
# $1 (optional): space-separated pkg:ver keys that failed verification. Those are
# printed as DO NOT RUN, so the operator never types a beat known to be broken.
print_commands() {
  local skip="${1:-}" pkg ver code dir mode rule label cur="" verdict cmd
  head_ "Run these. Copy the cd too - it is what puts npm behind the firewall."
  for d in app payments-service; do
    for row in "${DEMO_BEATS[@]}"; do
      IFS='|' read -r pkg ver code dir mode rule label <<<"$row"
      [ "$dir" = "$d" ] || continue
      if [ "$cur" != "$d" ]; then
        printf '\n  cd %s/demo/%s\n' "$ROOT" "$d"
        cur="$d"
      fi
      cmd="$(beat_cmd "$pkg" "$ver" "$mode")"
      if [ "$code" = "200" ]; then verdict="allowed"; else verdict="BLOCKED"; fi
      case " $skip " in
        *" ${pkg}:${ver} "*)
          printf '  %s%-32s # DO NOT RUN - failed preflight%s\n' "$c_red" "$cmd" "$c_off" ;;
        *)
          printf '  %-32s %s# %s - %s%s\n' "$cmd" "$c_dim" "$verdict" "$label" "$c_off" ;;
      esac
    done
  done
  printf '\n  %severy version is pinned on purpose: `latest` of a malware package is\n' "$c_dim"
  printf '  usually clean, so a bare `npm install <pkg>` succeeds and shows nothing%s\n' "$c_off"
}

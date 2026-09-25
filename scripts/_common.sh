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
  "aegularjs|1.1.2|403|app|install|malware|confirmed malware, exfiltrates host data to a Discord webhook"
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

# ---------------------------------------------------------------------------
# Side-screen notes
# ---------------------------------------------------------------------------
# notes/golden-demo.md is what the operator keeps beside the shared window. Its
# command block sits between BEATS markers and is regenerated from DEMO_BEATS,
# so the notes can never show a command preflight did not verify. Everything
# outside the markers is hand-written and survives re-rendering.
NOTES="${ROOT}/notes/golden-demo.md"
# preflight records the beats that failed here, so reopening the notes later
# still marks them DO NOT RUN. up.sh clears it: a fresh start is unverified.
PREFLIGHT_SKIP_FILE="${ROOT}/.preflight-skip"

# $1 (optional): space-separated pkg:ver keys that failed verification.
# Defaults to whatever the last preflight recorded.
render_notes() {
  local skip="${1-$(cat "$PREFLIGHT_SKIP_FILE" 2>/dev/null)}"
  [ -f "$NOTES" ] || return 0
  local root_disp="$ROOT" block="" pkg ver code dir mode rule label cmd verdict
  # Render ~ rather than the absolute home path so the tracked file does not
  # churn between machines that share the same layout.
  case "$ROOT" in "$HOME"/*) root_disp="~${ROOT#"$HOME"}" ;; esac
  for d in app payments-service; do
    block+=$'```\n'"cd ${root_disp}/demo/${d}"$'\n'
    for row in "${DEMO_BEATS[@]}"; do
      IFS='|' read -r pkg ver code dir mode rule label <<<"$row"
      [ "$dir" = "$d" ] || continue
      cmd="$(beat_cmd "$pkg" "$ver" "$mode")"
      if [ "$code" = "200" ]; then verdict="allowed"; else verdict="BLOCKED"; fi
      case " $skip " in
        # Commented out so pasting the block can never run a dead beat.
        *" ${pkg}:${ver} "*) block+="$(printf '# %-30s # DO NOT RUN - failed preflight' "$cmd")"$'\n' ;;
        *) block+="$(printf '%-32s # %s - %s' "$cmd" "$verdict" "$label")"$'\n' ;;
      esac
    done
    block+=$'```\n\n'
  done
  NOTES_BLOCK="$block" python3 - "$NOTES" <<'PY'
import os, re, sys
path = sys.argv[1]
text = open(path).read()
block = os.environ["NOTES_BLOCK"].rstrip("\n")
new = re.sub(r"(<!-- BEATS:START[^>]*-->\n).*?(<!-- BEATS:END -->)",
             lambda m: m.group(1) + block + "\n" + m.group(2), text, count=1, flags=re.S)
if new != text:            # write only on change, so a clean tree stays clean
    open(path, "w").write(new)
PY
}

# Open the notes in Obsidian. A file inside a registered vault opens through the
# obsidian:// URI, which lands it in that vault's window. Anything else goes to
# the Obsidian app directly, with a one-line hint to make the notes folder a vault.
open_notes() {
  [ -f "$NOTES" ] || { warn "no notes file at notes/golden-demo.md"; return 0; }
  local vault_uri
  vault_uri="$(python3 - "$NOTES" <<'PY'
import json, os, sys, urllib.parse
f = os.path.realpath(sys.argv[1])
cfg = os.path.expanduser("~/Library/Application Support/obsidian/obsidian.json")
try:
    vaults = json.load(open(cfg)).get("vaults", {}).values()
except Exception:
    vaults = []
for v in vaults:
    p = os.path.realpath(v.get("path", ""))
    if p and f.startswith(p + os.sep):
        print("obsidian://open?path=" + urllib.parse.quote(f, safe=""))
        break
PY
)"
  if [ -n "$vault_uri" ]; then
    open "$vault_uri" && ok "notes opened in Obsidian"
  elif [ -d /Applications/Obsidian.app ]; then
    # Obsidian silently ignores a file outside a vault (verified 2026-09-23:
    # `open -a Obsidian file` focused the app and showed nothing). So register
    # notes/ as a vault once. Obsidian rewrites obsidian.json on quit, so it has
    # to be closed while we edit it; it autosaves, so quitting loses nothing.
    osascript -e 'tell application "Obsidian" to quit' >/dev/null 2>&1
    for _ in $(seq 1 15); do pgrep -x Obsidian >/dev/null || break; sleep 1; done
    python3 - "${ROOT}/notes" <<'PY2'
import json, os, secrets, sys, time
cfg = os.path.expanduser("~/Library/Application Support/obsidian/obsidian.json")
vault = os.path.realpath(sys.argv[1])
try:
    d = json.load(open(cfg))
except Exception:
    d = {}
v = d.setdefault("vaults", {})
if not any(os.path.realpath(x.get("path", "")) == vault for x in v.values()):
    v[secrets.token_hex(8)] = {"path": vault, "ts": int(time.time() * 1000)}
os.makedirs(os.path.dirname(cfg), exist_ok=True)
json.dump(d, open(cfg, "w"))
PY2
    local enc
    enc="$(python3 -c 'import sys,urllib.parse,os;print(urllib.parse.quote(os.path.realpath(sys.argv[1]),safe=""))' "$NOTES")"
    open "obsidian://open?path=${enc}" && ok "registered notes/ as an Obsidian vault and opened the notes"
  else
    open "$NOTES" && ok "notes opened"
  fi
  printf '  %sshare a WINDOW, never the entire screen - the notes are on it%s\n' "$c_yel" "$c_off"
}

#!/usr/bin/env bash
# Find confirmed-malware npm packages that are still live on npm, so a blocked
# beat can be swapped when npm removes the current one.
#
# "Still live" matters: if npm has removed the version, `npm install <pkg>` fails
# at resolution with a generic "no matching version found" and the audience never
# sees a Socket message.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
set -a; [ -f "${ROOT}/.env" ] && source "${ROOT}/.env"; set +a
: "${SOCKET_SECURITY_API_TOKEN:?set SOCKET_SECURITY_API_TOKEN in .env}"

head_ "Confirmed npm malware still installable from npm"
SOCKET_SECURITY_API_TOKEN="$SOCKET_SECURITY_API_TOKEN" python3 - <<'PY'
import base64, json, os, urllib.error, urllib.parse, urllib.request

tok = os.environ["SOCKET_SECURITY_API_TOKEN"]
auth = base64.b64encode((tok + ":").encode()).decode()

def socket_api(path):
    r = urllib.request.Request("https://api.socket.dev" + path,
                               headers={"Authorization": "Basic " + auth})
    return json.loads(urllib.request.urlopen(r, timeout=60).read().decode())

rows = []
for page in range(1, 5):
    qs = urllib.parse.urlencode({"type": "npm", "per_page": 100,
                                 "page": page, "filter": "mal"})
    try:
        rows += socket_api(f"/v0/threat-feed?{qs}").get("results") or []
    except urllib.error.HTTPError as e:
        raise SystemExit(f"threat-feed HTTP {e.code}: {e.read().decode()[:200]}")

seen, cands = set(), []
for r in rows:
    if r.get("threatType") != "malware":
        continue                                  # skip possible_malware: warns, does not block
    purl = (r.get("purl") or "").split("?")[0]
    if not purl.startswith("pkg:npm/"):
        continue
    rest = purl[len("pkg:npm/"):]
    if "@" not in rest:
        continue
    name, _, ver = rest.rpartition("@")
    name = urllib.parse.unquote(name)
    if (name, ver) in seen or ver.endswith("-security"):
        continue                                  # -security is npm's takedown placeholder
    seen.add((name, ver))
    cands.append((name, ver, " ".join((r.get("description") or "").split())))

found = 0
for name, ver, desc in cands:
    try:
        d = json.loads(urllib.request.urlopen(
            "https://registry.npmjs.org/" + urllib.parse.quote(name, safe="@"),
            timeout=20).read().decode())
    except Exception:
        continue
    if ver not in (d.get("versions") or {}):
        continue
    print(f"  {name}@{ver}")
    print(f"      {desc[:150]}")
    found += 1
    if found >= 12:
        break

if not found:
    print("  none found. Widen the page range or use the npm ci beat instead.")
PY
cat <<'TXT'

  Prefer a description naming a concrete behavior (exfiltration, dropper,
  backdoor). Only call a package a typosquat if Socket itself carries a
  didYouMean alert on it; a lookalike name is not a verdict.
  Then update BEATS in scripts/preflight.sh and the table in README.md.
TXT

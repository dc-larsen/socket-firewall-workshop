#!/usr/bin/env bash
# Toggle metadata filtering, the optional "developer experience" beat.
#
# OFF (default): every block goes through the download gate and returns a 403
#   whose npm-notice header the npm CLI prints. The developer sees the reason.
# ON: blocked versions are stripped from the version list. An exact pin fails as
#   "no matching version found" and an unpinned range silently resolves to an
#   older allowed version. Builds stay green; Socket becomes invisible.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

want="${1:-}"
case "$want" in
  on|off) ;;
  *) echo "usage: scripts/filtering.sh on|off"; exit 2 ;;
esac

python3 - "$ROOT" "$want" <<'PY'
import re, sys
root, want = sys.argv[1], sys.argv[2]
p = f"{root}/socket.yml"
s = open(p).read()
new = "true" if want == "on" else "false"
s2 = re.sub(r"(metadata_filtering:\n  enabled: )(true|false)", r"\g<1>" + new, s, count=1)
if s2 == s and f"enabled: {new}" not in s:
    sys.exit("could not rewrite metadata_filtering in socket.yml")
open(p, "w").write(s2)
PY

# socket.yml is a bind mount resolved at container create time, so a restart
# will not pick up the change -- the container has to be recreated.
docker compose --project-directory "$ROOT" up -d --force-recreate >/dev/null 2>&1
ok "metadata filtering set to: $want (container recreated)"
wait_ready && ok "firewall ready" || { bad "firewall did not come back"; exit 1; }

if [ "$want" = "on" ]; then
  cat <<'TXT'

  Now show the tradeoff from demo/app:

    npm install form-data@2.3.3      -> "no matching version found"  (no Socket message)
    npm install form-data@^2.3.3     -> "added 22 packages"          (silently got 2.5.6)

  The build stays green and the developer never learns Socket did anything.
  That is the argument for enforcing known malware on the download path instead.
TXT
else
  cat <<'TXT'

  Blocks are loud again. From demo/app:

    npm install aegularjs            -> 403 with the threat-research note
TXT
fi

set -e
export NODE_EXTRA_CA_CERTS=/certs/sfw.crt
corepack enable >/dev/null 2>&1 || true

DEPS='"express": "4.21.2", "lodash": "4.17.21", "axios": "1.7.9"'

run() {
  name="$1"; reg="$2"
  rm -rf /work/npm-$name; mkdir -p /work/npm-$name; cd /work/npm-$name
  printf '{\n "name": "repro-%s",\n "version": "1.0.0",\n "dependencies": { %s }\n}\n' "$name" "$DEPS" > package.json
  printf 'registry=%s\nstrict-ssl=true\n' "$reg" > .npmrc
  pnpm install --lockfile-only --ignore-scripts >/dev/null 2>&1 || pnpm install --lockfile-only --ignore-scripts 2>&1 | tail -5
  echo "=== $name  (registry: $reg)"
  echo "    pnpm-lock.yaml lines : $(wc -l < pnpm-lock.yaml)"
  echo "    explicit 'tarball:' resolution entries: $(grep -c 'tarball:' pnpm-lock.yaml || true)"
  echo -n "    hosts appearing in lockfile: "
  grep -oE 'https?://[^/]+' pnpm-lock.yaml | sort -u | tr '\n' ' '; echo ""
  echo ""
}

run public   "https://registry.npmjs.org/"
run firewall "https://sfw.mercor.test/npm/"

echo "=== diff: public lockfile vs firewall lockfile"
diff /work/npm-public/pnpm-lock.yaml /work/npm-firewall/pnpm-lock.yaml > /work/npm.diff 2>&1 || true
echo "    changed lines in diff: $(wc -l < /work/npm.diff)"
echo "    first 12 diff lines:"
head -12 /work/npm.diff | sed 's/^/    /'

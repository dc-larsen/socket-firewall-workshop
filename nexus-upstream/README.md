# Nexus → Socket Registry Firewall (Upstream topology)

Local rig proving the deployment Chubb is rolling out: Sonatype Nexus proxy
repositories pull through Socket Registry Firewall on their way to public
registries.

```
Developer / CI  →  Nexus (proxy repo)  →  Socket Registry Firewall  →  npmjs / Maven Central / PyPI
```

All 13 checks in `test.sh` pass: safe packages install through Nexus, known
malware (jscrambler@8.14.0) is blocked by the firewall (403, `x-socket-decision:
blocked`, `x-socket-block-reason: Known malware`), and Nexus surfaces that
block to developers as a 404 "Package not found".

## Quick start

```bash
# 1. Socket API token
echo "SOCKET_SECURITY_API_TOKEN=<your token>" > .env.secrets

# 2. Self-signed cert for the firewall (SAN required — Java rejects CN-only)
mkdir -p ssl
openssl req -x509 -newkey rsa:2048 -nodes -keyout ssl/privkey.pem \
  -out ssl/fullchain.pem -days 365 -subj "/CN=firewall" \
  -addext "subjectAltName=DNS:firewall"

# 3. Start (Nexus first boot takes 2-3 minutes)
cp socket.manual.yml socket.yml
docker compose up -d

# 4. Provision Nexus (EULA, SSRF allowlist, anonymous read, proxy repos)
./setup-nexus.sh

# 5. Switch repos to https remotes + Nexus truststore (self-signed only)
./use-https-remotes.sh

# 6. Test
./test.sh
```

Nexus UI: http://localhost:8081 (admin password:
`docker exec nexus-rig-nexus cat /nexus-data/admin.password`).
Firewall from the host: `curl -H "Host: firewall" http://localhost:9180/...`.

## The remote URL question, answered

The Nexus proxy repo **Remote storage URL must include the ecosystem path**:

| Nexus repo format | Remote storage URL              |
|-------------------|---------------------------------|
| npm               | `https://<firewall-host>/npm`   |
| maven2            | `https://<firewall-host>/maven` |
| pypi              | `https://<firewall-host>/pypi`  |

A bare firewall URL with no suffix returns 404 for every request. Verified
both on this rig and live against the hosted tenant
(`chubb.firewall.socket.dev`): `/npm/lodash` → 200, `/lodash` → 404.

The URL is **per ecosystem, not per repo** — every npm-format proxy repo uses
the same `/npm` URL. Automation for newly created proxy repos is a static
format→URL lookup, nothing dynamic.

Only **proxy** repositories are touched. Hosted and group repos keep working
unchanged (groups aggregate the proxy members, which are already protected).

## Auto-discovery: what it actually builds (verified here)

`path_routing.mode: nexus` polls `GET /service/rest/v1/repositories` and
generates one route per repo at `/repository/<repo-name>` — but every route's
backend is **Nexus itself** (`set $backend "nexus:8081"` in the generated
nginx config), even with `config_mode: upstream` (image 2.3.1). That is the
**Downstream** topology: developers point package managers at the firewall,
which proxies into Nexus. It cannot generate Nexus→firewall→public routes,
so it does not apply to the Upstream rollout. (Same finding as the
Artifactory rig, 2026-08-18.)

`./switch-config.sh auto|manual` flips between the two configs to see this.

## What a block looks like through Nexus

- Firewall answers the tarball fetch with **403** + `x-socket-decision:
  blocked` + `x-socket-block-reason: Known malware` (+ an `npm-notice` header).
- Nexus converts that into a client-side **404**:
  `{"success":false,"error":"Package 'jscrambler' not found"}`.
- Developers therefore see "not found", **not** a security error. Support
  runbooks should treat "version suddenly not found via Nexus" as a possible
  policy block: confirm in the firewall events / Socket dashboard.
- Metadata filtering additionally strips blocked versions from the version
  list, checking the **newest 100 versions** per request (`npm metadata
  filtering: checking 100 versions (newest first)`). Fresh supply-chain
  attacks are by definition newest, so they vanish from metadata AND fail at
  download; older malware deep in the version history is still stopped by the
  download-layer 403.

## Gotchas hit while building this (so you don't)

1. **`rewrite_scheme` also sets the upstream connection scheme.** With
   `rewrite_scheme: http` the firewall contacted `http://registry.npmjs.org`
   and npmjs's Cloudflare edge answered 301 to everything. Must be `https`.
2. **Nexus follows absolute tarball URLs from (rewritten) metadata**, so with
   a self-signed firewall cert you must import it into the Nexus truststore
   (`POST /service/rest/v1/security/ssl/truststore`, raw PEM body) and set
   `httpClient.connection.useTrustStore: true` per repo. Hosted tenants have
   a public CA cert — skip entirely.
3. **Nexus CE requires EULA acceptance via REST** before it will serve
   proxied content (otherwise 403 on binaries).
4. **Nexus SSRF protection** rejects remote URLs resolving to private IPs
   (`/service/rest/v1/security/ssrf-protection` allowlist). Only affects
   rigs/self-hosted firewalls on private addresses.
5. **Certs must be named `fullchain.pem`/`privkey.pem`** — the auto-discovery
   daemon regenerates config with those default names and bricks nginx
   otherwise.
6. **The public Nexus README shows `config_mode` at top level; the config
   tool reads `path_routing.config_mode`** (cli.py:75).

## Files

| File                     | Purpose                                            |
|--------------------------|----------------------------------------------------|
| `docker-compose.yml`     | Nexus 3 (CE) + socket-registry-firewall 2.3.1      |
| `socket.manual.yml`      | Per-ecosystem routes (mirrors the hosted tenant)   |
| `socket.autodiscovery.yml` | `mode: nexus` auto-discovery variant             |
| `setup-nexus.sh`         | EULA, SSRF, anonymous read, create proxy repos     |
| `use-https-remotes.sh`   | Truststore import + https remotes (self-signed)    |
| `switch-config.sh`       | Flip manual ↔ auto-discovery                       |
| `test.sh`                | 13 end-to-end checks                               |

Teardown: `docker compose down -v`

# Registry Firewall: lockfile portability and download-time enforcement

Test rig for the `mode: proxy` vs `mode: rewrite` tradeoff on the Socket Registry
Firewall, built to reproduce a customer report about proxy URLs appearing in
`uv.lock` and `pnpm-lock.yaml`.

- Firewall: `socketdev/socket-registry-firewall:2.3.3`
- Clients: uv 0.9.28, pnpm 11.24.0, npm 11.6.2, pip 25.0.1
- Runtime: OrbStack / Docker 29.4.0

## Rig shape

Two client containers on different Docker networks:

| Container | Network | Stands in for |
|---|---|---|
| `mercor-dev` | shared with firewall | developer laptop on the tailnet |
| `mercor-ci` | isolated | CI / Vercel, cannot resolve the firewall hostname |

The firewall listens on 443 and is reachable as `sfw.mercor.test`. Certs are a
real CA + leaf (`scripts/mkcerts.sh`) so TLS verification is exercised rather
than bypassed — uv's rustls rejects the auto-generated cert with
`CaUsedAsEndEntity`.

## What each mode does

`mode` is a per-route key under `path_routing.routes`. It is not in the public
README. Default is `rewrite`.

| | `mode: rewrite` (default) | `mode: proxy` |
|---|---|---|
| PyPI simple index hrefs | rewritten to firewall host | left on `files.pythonhosted.org` |
| npm `dist.tarball` | rewritten to firewall host | left on `registry.npmjs.org` |
| Downloads traverse firewall | yes | no |

## Results

### 1. uv records the index URL in `uv.lock` regardless of where it is configured

All three produce `source = { registry = "https://sfw.mercor.test/pypi/simple/" }`
for every package (`scripts/run_a.sh`):

- `[[tool.uv.index]]` in `pyproject.toml`
- `UV_INDEX_URL` environment variable, nothing in `pyproject.toml`
- external `uv.toml` via `UV_CONFIG_FILE`, nothing in `pyproject.toml`

Moving the index out of `pyproject.toml` does **not** keep the proxy URL out of
`uv.lock`.

### 2. That registry line does not break CI

From the off-network CI container, against a lock generated in `mode: proxy`
(`scripts/run_b.sh`) — all succeed:

`uv sync --frozen`, `uv sync --locked`, `uv sync`, `uv lock --check`, `uv export`

Download URLs stay on `files.pythonhosted.org`, so installs never contact the
firewall.

### 3. What breaks CI is the index committed in `pyproject.toml`

Forcing a re-resolution in CI (`scripts/run_c.sh`):

| Layout | `uv lock` in CI |
|---|---|
| index in `pyproject.toml` | fails: `Failed to fetch https://sfw.mercor.test/pypi/simple/...` |
| index outside the repo | succeeds, re-sources to `https://pypi.org/simple` |

### 4. `mode: rewrite` pins wheel URLs to the firewall

Locking under rewrite mode writes firewall-hosted wheel URLs
(`scripts/run_d.sh`). Installing that lock from CI reproduces the customer's
original error verbatim (`scripts/run_e.sh`):

```
dns error
failed to lookup address information: Name or service not known
```

### 5. pnpm behaves the opposite way to uv

Three direct dependencies, 79 resolved packages (`scripts/run_npm.sh`):

| npm route mode | `pnpm-lock.yaml` vs public-registry baseline |
|---|---|
| `mode: proxy` | 79 added `tarball: https://registry.npmjs.org/...` lines, 316-line diff |
| `mode: rewrite` | byte-identical, zero diff |

Under rewrite mode the tarball host matches the configured registry, so pnpm
omits the explicit `tarball:` field and the lockfile stays registry-agnostic.
Verified portable: `pnpm install --frozen-lockfile` against the public registry
from the off-network container succeeds.

### 6. `mode: proxy` bypasses download-time policy

With a policy that blocks these packages:

| Client | `mode: proxy` | `mode: rewrite` |
|---|---|---|
| pnpm, `lodahs` (known malware) | installs | 403 `ERR_PNPM_FETCH_403` |
| pip, `urllib3==1.16` | installs | 403 on the wheel |
| npm CLI, `lodahs` | 403 | 403 |

npm CLI is the outlier because it rewrites tarball URLs to the configured
registry host, so its downloads traverse the firewall even in proxy mode. A
smoke test run with npm therefore passes while pnpm and pip are unprotected.

### 7. `metadata_filtering` restores enforcement without leaving proxy mode

```yaml
metadata_filtering:
  enabled: true
  filter_blocked: true
```

In `mode: proxy` with filtering on, blocked versions are stripped from index
responses:

- pip: `urllib3==1.16` no longer appears in the available versions
- pnpm: `ERR_PNPM_NO_VERSIONS: No versions available for lodahs`

Lockfiles keep public URLs.

**Limitation:** filtering acts at resolve time only. Installing a URL already
recorded in a lockfile still succeeds, because that download never reaches the
firewall:

```
pip install https://files.pythonhosted.org/.../urllib3-1.16-py2.py3-none-any.whl
Would install urllib3-1.16
```

## Rig artifact worth reporting upstream

In rewrite mode the firewall drops a non-standard port when rewriting URLs:
serving on 8443 produced `https://sfw.mercor.test/pypi/packages/...` with no
port, and clients then failed with connection refused on 443. Only affects
deployments not on 443.

## Running it

```bash
sh scripts/mkcerts.sh
docker compose up -d
docker exec -e SSL_CERT_FILE=/work/cabundle.pem mercor-dev sh /work/run_a.sh
```

# MetLife pip 502 repro — findings (2026-08-25)

Customer symptom: pip queries resolve through the firewall, installs fail with
`MaxRetryError ... ResponseError('too many 502 error responses')` on
`/pypi/packages/.../six-1.17.0-py2.py3-none-any.whl.metadata`, five fast
retries, every attempt. npm through the same firewall works.

Rig: released `socketdev/socket-registry-firewall` images, path routing in
rewrite mode on TLS 443 (mirrors MetLife's Helm values), python:3.13-slim
client (pip 25.x, matches their pip 25.1.1), dnsmasq as the firewall's
resolver for query logging and selective blocking.

## Results

| Scenario | 2.3.2 | 2.3.3 |
|---|---|---|
| Healthy egress | install OK | install OK |
| Stale pooled upstream conn (middlebox) | 200, **502**, 200 | 200, 200, 200 |
| files.pythonhosted.org blackholed (silent drop) | ReadTimeoutError, no 502s, ~98s | not run |
| files.pythonhosted.org connection refused | **exact customer error, ~8s** | **exact customer error, ~8s** |

## Conclusions

1. A pip install makes the firewall dial `api.socket.dev`, `pypi.org`, AND
   `files.pythonhosted.org` (dnsmasq query log). PyPI's simple index lives on
   pypi.org; the files (.whl, .whl.metadata) live on files.pythonhosted.org.
   An egress allowlist with pypi.org but not files.pythonhosted.org gives
   exactly: queries work, every install fails.
2. The stale-pooled-connection bug (fixed in v2.3.3, PR #347) produces a
   ONE-OFF 502 that the next attempt recovers from. pip retries 5x on its
   own, so that bug cannot explain five consecutive 502s failing every run.
3. Fast-failing upstream connects (refused / rejected / TLS-inspection
   failure) reproduce the customer signature character for character, on both
   versions. v2.3.3's retry covers reused-socket failures only, so upgrading
   does not mask an egress problem.
4. npm works because registry.npmjs.org serves both metadata and tarballs —
   one host, already allowed.

## Gotchas hit while building this (worth remembering)

- The firewall's Lua HTTP client resolves via the configured resolver
  (resolv.conf → docker's 127.0.0.11), NOT /etc/hosts. `extra_hosts` does not
  affect upstream dials; block at the DNS layer.
- 127.x.x.x is a bad "refused" simulant: the firewall's own nginx listens on
  0.0.0.0:443, so the dial loops back into itself.
- `docker compose up <svc>` recreates `depends_on` dependencies when their
  config hash changes — an env-var-parameterized sibling service gets
  silently recreated with empty env. Use `--no-deps` or re-export the var.
- python:3.13's urllib rejects a minimal test CA (no keyUsage extension);
  pip's vendored TLS stack accepts it.

## Reruns

```bash
bash mkcerts.sh
# baseline
FW_TAG=2.3.2 docker compose up -d --wait firewall client dns
docker exec metlife-client python -m pip install six --no-cache-dir --target /tmp/t1
# egress refused (exact customer signature)
export EXTRA_DNSMASQ_ARGS="--address=/files.pythonhosted.org/172.31.99.99 --address=/files.pythonhosted.org/100::1"
docker compose up -d --force-recreate dns
FW_TAG=2.3.2 docker compose up -d --force-recreate --no-deps --wait firewall
docker exec metlife-client python -m pip install six --no-cache-dir --target /tmp/tX
# stale-conn differential
FW_TAG=2.3.2 ./run-stale.sh   # expect 200/502/200
FW_TAG=2.3.3 ./run-stale.sh   # expect 200/200/200
```

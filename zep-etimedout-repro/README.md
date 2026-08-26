# FIRE-150: sfw wrapper mode `AggregateError ETIMEDOUT`

Deterministic repro for the connect-stage failure Zep has hit since 2026-06-30
across Depot, Buildkite, and GitHub Actions runners.

Tracking issue: FIRE-150. Reproduced 2026-08-25 against **sfw v1.15.0**
(`sfw-linux-x86_64`), the build the customer is pinned to and still the newest
published release.

## Run it

Needs `SOCKET_API_KEY` in the repo root `.env.secrets`.

```bash
docker run --rm --platform linux/amd64 \
  --env-file <(grep SOCKET_API_KEY ../.env.secrets) \
  -e SOCKET_API_TOKEN \
  -v "$PWD:/repro" \
  ubuntu:22.04 \
  bash -c 'export SOCKET_API_TOKEN="$SOCKET_API_KEY"; bash /repro/repro.sh'
```

Takes roughly 10 minutes. Three of the cases intentionally wait out a full
OS-level connect timeout (~136s each).

## Which host actually fails in production

This script injects the fault at `proxy.golang.org` because that is a convenient
single-purpose host to blackhole. **The real-world failing endpoint is
`api.socket.dev` on the `purl` route**, confirmed from telemetry rather than
inferred: `socket.telemetry_events` shows 36 `HTTP request aborted` rows on the
`purl` route for org 361327 on 2026-08-25, against 1-6 on an ordinary day, while
p95 latency held at 90ms.

`api.socket.dev` resolves to four addresses (2 A + 2 AAAA), so the
multi-address path below is guaranteed there. `proxy.golang.org` has one A and
one AAAA, so it only gets there on a dual-stack host.

The mechanism is identical either way, which is why the injection point doesn't
change what this demonstrates.

## Method

Blackhole `proxy.golang.org` by pointing it at non-routable RFC1918 addresses
in `/etc/hosts`, then run `sfw go build`. The addresses must **time out**, not
refuse. `ECONNREFUSED` takes a different path in `node:net` and will not
reproduce this.

The number of addresses you point the host at is the whole trick: it selects
which `node:net` code path handles the failure.

## What it demonstrates

### 1. The multi-address path discards the failing host

| Resolved addresses | What sfw prints |
|---|---|
| 1 | `Error: connect ETIMEDOUT 10.255.255.1:443` at `TCPConnectWrap.afterConnect (node:net:1637:16)` |
| 2+ | `AggregateError [ETIMEDOUT]:` at `internalConnectMultiple (node:net:1134:18)`, empty message, no address |

`node:net:1134:18` matches the customer's stack exactly. With two or more
candidate addresses Node uses `internalConnectMultiple` (Happy Eyeballs) and
wraps the per-address errors in an `AggregateError`. The sub-errors in
`.errors[]` still carry `address` and `port`, but only the top-level message
gets surfaced, and an `AggregateError`'s own message is empty.

Net effect: the host is thrown away exactly when there is more than one
candidate address. `api.socket.dev` itself resolves to two A records, so our
own API path is subject to the same masking.

Fix direction: unwrap `AggregateError.errors[]` and log each
`code` / `address` / `port`.

### 2. sfw returns 0 when the wrapped command fails

Identical injected fault, exit code captured directly rather than through a pipe:

| Command | Exit code | Artifact |
|---|---|---|
| `go build -o out ./...` | 1 | none |
| `sfw go build -o out ./...` | **0** | none |

Bare `go` also reports something usable: `dial tcp 10.255.255.1:443: i/o timeout`.
Any pipeline keying off exit status alone goes green with nothing built. Zep
avoids this only because their retry wrapper matches on sfw's fault text
instead of `$?`.

### 3. Node-level knobs do not help (negative results)

Realistic dual-stack shape, one dead address tried ahead of one live address:

| Setting | Result |
|---|---|
| default (250ms attempt budget) | succeeds, ~5s |
| `--network-family-autoselection-attempt-timeout=5000` | succeeds, ~28s. Slower failover. |
| `--no-network-family-autoselection` | fails, ~137s hang, plain `ETIMEDOUT` |

Happy Eyeballs is what keeps these builds alive; disabling it removes the
failover. `NODE_OPTIONS` *is* honored by the SEA (it rejects unknown flags by
name), so the knobs are reachable, they just make things worse. There is no
config workaround to hand the customer.

## Not reproduced

The customer's stack includes `Timeout.internalConnectMultipleTimeout` and
`listOnTimeout`, meaning the Happy Eyeballs per-attempt timer fired rather than
the connect callback. Same throw site, different entry into it. Plausible cause
is event-loop starvation on a CPU-saturated CI runner exceeding the 250ms
attempt budget, but that is untested here.

Both entry paths need the same two fixes (unwrap the `AggregateError`, propagate
the child exit code), so this gap probably doesn't block the work.

## Also checked

`api.socket.dev` blackholed at startup gives a clean
`Unable to reach Socket API at https://api.socket.dev/ / Error: fetch failed`
and exit 1, at any address count. The startup preflight is handled correctly.
The customer's failure is not the preflight, which is consistent with their
PURL telemetry being healthy through the failure windows.

`SFW_DEBUG=true` does not name the failing host in the multi-address case. It
emits `serviceStarted`, a normal `packageAllowed` event for the module, then the
bare `AggregateError`. The 2026-07-13 request for a `SFW_DEBUG` run would not
have identified the host even if it had arrived.

# Socket Firewall Demo

A one-container local demo of Socket Registry Firewall. The demo command is a plain
`npm install <pkg>@<version>` from a demo directory. No `docker exec`, no `--registry`
flag, no proxy environment variables, no certificate for the audience to look at.

Every version is pinned and every command is printed for you by `scripts/up.sh`. Both
of those are load-bearing; see [Pin every version](#pin-every-version-this-is-not-optional).

## What changed from the old workshop

| Old | Now | Why |
|---|---|---|
| `sfw` binary as an HTTP/HTTPS proxy (v1.5.3) | Registry Firewall `2.6.1` in registry mode | Registry mode is the common customer topology and gives the richer block message |
| `docker exec sfw-node-client npm install x` | `npm install x` | Docker in the command distracts; the audience should see what a developer runs |
| Hand-built OpenSSL CA, `NODE_EXTRA_CA_CERTS` | OrbStack terminates TLS with a CA macOS already trusts | Removes four setup steps and the whole MITM conversation |
| 3 containers | 1 container | Less to break |
| `form-data@2.3.3` billed as malware | Malware and CVE beats separated | `form-data@2.3.3` is a critical CVE, not malware. Calling it malware is a claim that does not survive a question |
| No verification | `scripts/preflight.sh` | Live malware gets removed from npm. Find out before the call, not during it |

## Requirements

- OrbStack (running). The demo depends on its container hostnames and its trusted CA.
- A Socket API token with `packages:list` and `entitlements:list`.

## Setup

```bash
cp .env.example .env     # add your token
./scripts/up.sh
```

`up.sh` does everything needed so a fresh terminal tab runs the demo with no setup:
validates the token and prints which org it resolves to, exports the OrbStack CA,
starts the firewall, writes the `.npmrc` into each demo directory, resets
`demo/app/package.json`, clears the demo-local npm cache, waits until the firewall
serves real package metadata, then prints the exact commands to run.

It finishes by printing the command block. Copy the `cd` lines with it.

Before a call:

```bash
./scripts/preflight.sh
```

## The beats

`up.sh` and `preflight.sh` both print this list with absolute paths. The list itself
lives in one place, `DEMO_BEATS` in `scripts/_common.sh`, and both the tarball path
preflight probes and the command printed for you are derived from it, so what gets
verified is always what you type.

From `demo/app`:

| # | Command | Result |
|---|---|---|
| 1 | `npm install lodash@4.18.1` | `added 1 package`, the allow control |
| 2 | `npm install aegularjs@1.1.2` | 403, `Known malware` plus the exfiltration note |
| 3 | `npm install get-power@1.0.3` | 403, `Known malware` |
| 4 | `npm install form-data@2.3.3` | 403, `Critical CVE` (needs `criticalCVE` at `error`) |

From `demo/payments-service`:

| # | Command | Result |
|---|---|---|
| 5 | `npm ci` | 403 naming the malicious transitive dependency |
| 6 | `./scripts/filtering.sh on` | optional: blocks go silent, builds stay green |

### Pin every version. This is not optional.

A block beat is version-specific, and the `latest` version of a malware package is
usually clean. Verified live on `2.6.1`:

| Request | Firewall |
|---|---|
| `aegularjs@1.1.2` | **403** with the full threat-research note |
| `aegularjs@8.7.6` (dist-tag `latest`) | **200, installs** |

So a bare `npm install aegularjs` resolves to `latest`, succeeds, and the demo shows
nothing. `8.7.6` carries `gptSecurity`, `installScripts` and `emptyPackage` but no
confirmed `malware` alert, so there is nothing for a `malware: error` policy to catch.
Never put a bare package name in a demo command.

### Run them from the demo directories

The `.npmrc` that points npm at the firewall is per-directory. The same command run
from `$HOME` goes straight to `registry.npmjs.org`, inspects nothing, and looks exactly
like the firewall letting malware through. `preflight.sh` checks both demo directories
are wired, and the printed block always includes the `cd`.

### Beats are per-org, not absolute

Blocks are evaluated against the policy of the org that the token in `.env` belongs to,
so swapping the token re-rolls the whole demo. `up.sh` and `preflight.sh` both print the
resolved org for that reason. Only a rule at `error` blocks:

| Rule at | Effect on a beat |
|---|---|
| `malware: error` | beats 2, 3 and 5 block |
| `criticalCVE: warn` | **beat 4 returns 200.** No package swap fixes it |
| `recentlyPublished: ignore` | a two-reason block drops to one reason |
| `gptMalware: warn` | AI-detected malware does not block. Do not claim it does |

When a block beat returns 200, `preflight.sh` reads the org's security policy and names
the rule and its action, so you get the cause rather than a mystery.

Beat 2 is the headline. `aegularjs` is a typosquat of `angularjs`, and the one-character
difference does the teaching before you say anything:

```
npm notice Access denied: Your download has been blocked by the Socket Security Policy.
Reason: Known malware -- This code is malicious. It performs unauthorized data
exfiltration of system network interface IP addresses and hostname to an
attacker-controlled Discord webhook. ... Request ID: <id>
```

That text is the `npm-notice` response header, which the npm CLI prints itself. For
malware, the reason carries the threat-research note, so the developer gets the actual
finding rather than a category. `preflight.sh` warns when a reason has decayed to a bare
category with no note, because that is a weaker demo even though the status code is right.

## Block messages and metadata filtering

Metadata filtering is off in `socket.yml`, deliberately. It changes what the developer
sees, and not in the direction you want for a demo:

| Filtering | `npm install form-data@2.3.3` | What the developer learns |
|---|---|---|
| **off** | 403 + `Reason: Critical CVE` + Request ID | Blocked, why, and what to quote to the security team |
| on | `npm error notarget No matching version found` | Nothing. No Socket branding at all |
| on, unpinned `^2.3.3` | `added 22 packages in 3s`, silently resolved to `2.5.6` | Nothing. The build is green |

All three verified on `2.6.1`, on an org with `criticalCVE` at `error`. Metadata filtering removes blocked versions from the
version list, so the client never requests them and there is no 403 to carry a message.
The download gate is what produces the reason.

The honest framing for a customer: metadata filtering keeps builds green and makes
blocks invisible; download-path enforcement makes blocks loud and attributable at the
cost of a failed build. Split it by alert type. Nobody legitimately pins malware, so
silent removal is fine there. Developers pin brand-new releases all the time, so
`recentlyPublished` is better enforced loudly.

If you enable metadata filtering for a customer at any real scale, Redis is required,
not recommended. Without it the verdict cache is a per-instance nginx dict that is wiped
on restart and never shared across replicas.

## When a blocked package stops blocking

Beats 2 and 3 use real malware that is live on npm today. npm removes packages, and a
removed package fails at resolution with a generic "no matching version" instead of a
Socket 403. `preflight.sh` reports a `404` for that case.

To swap one, find a confirmed-malware package still live on npm:

```bash
./scripts/find-packages.sh
```

Then update `DEMO_BEATS` in `scripts/_common.sh` and the README table. That array is the
only place a beat is defined; preflight and the printed commands both read it.

Beat 5 does not have this problem. `npm ci` requests the tarball URL directly and the
firewall decides before it contacts npm, so it works even though the version is gone.

## Talk track

Carl's ordering, September 2026. Roughly 12 minutes without questions.

### 1. Agenda (30s)

Name exactly what you will cover, and cover exactly that. Three things, not six.

> Three things today: how Socket decides a package is malicious, what a block looks like
> in a developer's terminal, and how an admin manages this. Stop me anywhere.

### 2. The threat engine (3 min)

Lead with the **signals**, not the verdicts. Typosquat and AI-detected malware are the
output; the signals are the input.

> We download the source of every version published to the registries we support and we
> read it. Static analysis, behavior analysis, maintainer and package metadata, then LLMs
> for context. Over 85 signals. What we are looking for is capability: does this package
> want shell access, network access, environment variables, filesystem access. Does the
> metadata look like a package that earned its download count.
>
> Then a human confirms it. That is the part that keeps the precision up.

On precision, use the number, not an adjective. Known Malware reversal is under 1% on
npm and PyPI. Do not claim a low false-positive rate across the board; AI-detected
potential malware is noisier, and anyone who has run the product knows it.

### 3. Axios, as a story (2 min)

This is the engine beat paying off. Get the details right.

> End of March, an attacker compromised an npm maintainer account. They published a
> package called plain-crypto-js. New maintainer, no history. Socket flagged it as
> malicious **six and a half minutes** after it was published.
>
> **Sixteen minutes later**, axios shipped a new version that pulled that package in as
> a transitive dependency. We had already blocked the payload, so we flagged that axios
> version immediately.
>
> The public advisory landed **five hours and twenty-two minutes** after we did.

That last number is the one that matters, because their current tooling *is* the advisory
feed. Six minutes is trivia. Five hours is the gap they are living in.

Compromised versions are `1.14.1` and `0.30.4`. `1.14.0` is clean and still on npm.
Socket's own internal timeline doc had this wrong, so do not repeat it.

Then run beat 5 (`npm ci` in `demo/payments-service`) and let the terminal say it:

```
Reason: Known malware -- Has malicious plain-crypto-js@4.2.1 dependency.
```

### 4. Worms (1 min)

> Axios was one package. Shai Hulud was a self-propagating worm: over 2,000 packages, and
> it jumped ecosystems. Because we are scanning continuously rather than reacting to a
> disclosure, every new version carrying the payload gets caught and added to the
> campaign as it propagates.

This is the differentiator against an OSV feed, which cannot keep up with a worm.

### 5. The terminal (2 min)

`demo/app`. Beat 1, then beat 2.

Say nothing about NGINX, ports, the Socket API call, or upstream versus downstream. Every
detail you volunteer is a thread someone can pull on, and the latency question is the one
that derails this demo. Wait to be asked.

### 6. The dashboard (2 min)

Events page. Expand a row.

**Expand the row every time.** The Machine ID / Client IP column in the events table has
been blank for firewall events since July 2026 (a regression in depscan #22962, still
unfixed). The values are there in the row detail. Do not promise the column.

Mention the webhook integration for SIEM delivery, briefly. Do not promise a named
native integration you have not checked.

### 7. Close (30s)

Summarize the three things you promised, then ask for the next step. Not "thanks for
coming to the demo."

> So: signals plus human confirmation, a block the developer can act on, and one page for
> the admin. Anything you want to go deeper on?
>
> Usually the next step is a short POC against your own registry. Two or three policies,
> known malware plus a cooldown window, in your own CI. Who else should be in that
> conversation?

## Held back until asked

Ready, not volunteered:

- Upstream versus downstream deployment. Use the deployment slide in the approved deck.
- The Socket API call, the verdict cache, latency.
- Metadata filtering. The verbal version is usually enough: "three versions, version
  three is malicious, we return one and two." Run `scripts/filtering.sh on` only for a
  technical audience that asks.

## Scripts

| Script | Does |
|---|---|
| `up.sh` | Start, export CA, write `.npmrc`, reset manifest, clear demo cache, wait for real readiness, print the commands |
| `preflight.sh` | Verify every beat against the live API, diagnose failures against org policy, print the commands |
| `talk.sh` | Print the talk track |
| `notes.sh` | Open the side-screen notes (`notes/firewall.md`) in Obsidian, command block regenerated from `DEMO_BEATS` |
| `filtering.sh on\|off` | Toggle metadata filtering and recreate the container |
| `find-packages.sh` | Find confirmed malware still live on npm, to swap a beat |
| `status.sh` | Container, filtering state, readiness |
| `down.sh` | Stop and clean generated files |

## Notes for whoever maintains this

- `path_routing.domain` must be a single hostname. Multiple whitespace-separated names
  produce invalid tarball URLs and npm fails with `ERR_INVALID_URL`.
- Leave `path_routing.rewrite_scheme` at its `https` default. Forcing `http` makes the
  firewall rewrite upstream redirects back to `http` on an HTTPS-only server, and npm
  dies with `EMAXREDIRECT`.
- `/health` returns 200 before the Lua workers are warm, and the first real package
  request then 502s. Always gate readiness on a live packument, which is what
  `wait_ready` does.
- `socket.yml` is a bind mount resolved when the container is created, so a restart does
  not pick up an edit. Recreate the container.
- npm caches packuments. The demo `.npmrc` sets `prefer-online=true` and a demo-local
  `cache=` directory that `up.sh` wipes on every start, so beats provably traverse the
  firewall without touching the operator's real `~/.npm`. If you change the registry URL
  or rewrite scheme outside the demo dirs, `npm cache clean --force`.
- Every demo command is pinned and every beat is defined once, in `DEMO_BEATS` in
  `scripts/_common.sh`. Do not hand-write a command into this README or into `up.sh`;
  derive it, or the printed command and the verified path will drift apart. They did
  once, and the result was a demo command that could not block.

# FIREWALL DEMO NOTES

## FOCUS
- **Pace.** Slow down. Say it once.
- **Numbers, not adjectives.** No "really," no "essentially," no "kind of a quick story."
- **Stop at the checkpoints.** Ask the question and wait for the answer.
- **Agenda = delivery.** Promise 3 things, deliver 3 things.
- **Don't volunteer:** NGINX, the API call, cache, latency, upstream vs downstream.

---

## THREAT ENGINE (in order)

**1. Ingestion**
Every version of every package, as it's published. We pull the source and read it.

**2. Signals (the input, not the verdict)**
- shell access
- network access
- env vars
- filesystem
- install scripts
- maintainer and metadata

That's ~85 signals, analyzed with static and behavioral analysis plus LLMs.
Typosquat and malware are the OUTPUT.

**3. Speed + human confirm**
- AI flags new malware in minutes: **6.3 min median**, **97% within an hour**
- A researcher then confirms it as known malware
- Known malware reversed **under 1%** (npm, PyPI)

**4. Axios story** (numbers below)

**5. Worms**
Shai Hulud: 2,000+ packages, crossed ecosystems. Each new version got caught as it spread. A disclosure-based feed can't keep up.

**6. ASK:** "How does that compare to what you've been seeing?"

---

## AXIOS NUMBERS

| | |
|---|---|
| Attack | npm maintainer account compromised, end of March 2026 |
| Payload | `plain-crypto-js` 4.2.1, new package, no history |
| Socket flags it | **6 min 29 sec** after publish |
| Axios ships it | **16 min** later, as a transitive dependency |
| Public advisory | **5 hr 22 min** after Socket |
| Bad versions | **1.14.1** and **0.30.4** |
| NOT bad | **1.14.0** is clean |

The 6.5 minutes is **plain-crypto-js**, not axios.

**Close:** "If your answer today is an advisory feed, that 5 hours is your window."

---

## TERMINAL

<!-- BEATS:START (generated from DEMO_BEATS by scripts/notes.sh; edits here are overwritten) -->
```
cd ~/Desktop/projects/socket-firewall-workshop/demo/app
npm install lodash@4.18.1        # allowed - allow control, installs clean
npm install aegularjs@1.1.2      # BLOCKED - typosquat of angularjs, confirmed malware
npm install get-power@1.0.3      # BLOCKED - confirmed malware
npm install form-data@2.3.3      # BLOCKED - critical CVE, not malware
```

```
cd ~/Desktop/projects/socket-firewall-workshop/demo/payments-service
npm ci                           # BLOCKED - malicious transitive dependency
```
<!-- BEATS:END -->

- **Always pin the version.** The `latest` version of a malware package is usually clean, so a bare install succeeds and shows nothing.
- **Always `cd` into the demo dir first.** From anywhere else, npm skips the firewall.
- Run `/demo-firewall check` before every call.

---

## DASHBOARD
- **Events: expand the row.** The Machine ID column is blank (bug). The details are in the row itself.
- SIEM delivery: webhooks. Don't promise a named integration.

---

## CLOSE
Recap the 3 things, then ask for the next step:
> "Next step is usually a short POC in your CI: known malware plus a cooldown window. Who else should be in that conversation?"

Don't end on "thanks for coming."

---

## IF THEY ASK

- **"Why you?"**
  We found and named Shai Hulud, GlassWorm, axios, Laravel. That's our own data, not a feed we subscribe to.
- **"What % do you catch?"**
  We're often first, so there's no list to measure against. Show them the detection types and the block/warn policy.
- **"Isn't this OSV?"**
  OSV mostly moves when a registry takes a package down. Small packages often never get taken down.
- **"How many alert types?"**
  ~85 signals go in. Policy is set per alert type.
- **"Ecosystems?"**
  npm, PyPI, Go, Maven, NuGet, RubyGems, Cargo, Composer, Swift. Plus Chrome extensions, Open VSX, Hugging Face, GitHub Actions.

---

## DO NOT SAY
- "our data is the best"
- "extremely low false positive rate" (true only for known malware)
- "researchers confirm within minutes" (median is **22.6 hrs**; the AI flag is the fast part)
- "we block AI-detected malware" (depends on their policy)
- "VS Code extensions" (it's Open VSX; no VS Code Marketplace)
- "we block Chrome extensions" (we scan them; there's no in-browser blocking)
- "under 5 minutes" for npm (there's a deliberate 5-min ingest hold)
- "anything related to supply chain"
- axios **1.14.0**

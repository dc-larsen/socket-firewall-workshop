# DEMO NOTES

> [!warning] Every section
> **Slow down. Say it once.** Ask the question, then **stop talking** until they answer.

---

## 0. OPEN (1 min)
**Agenda:** threat engine, firewall, SCA. Deliver exactly those three.

> [!question] ASK
> "Walk me through what happens today when someone on your team pulls in a new package."
>
> *Technical room:* "What's sitting between someone typing `npm install` and that package landing on their laptop?"
>
> *Short answer?* "Is that on laptops, in CI, or both?"

| They say | You say | Lean on |
|---|---|---|
| Nothing / not sure | "Let me show you what that looks like at install time." | 1, 2 |
| Our EDR | "EDR reacts once it's on the machine and the install script has run. We stop the download." | 2 |
| Artifactory / Nexus | "Does anything check what it pulls, or does it cache whatever's requested?" | 1 (Axios), 2 |
| Snyk / our SCA | "That runs once it's in a repo, after the install. And it waits on advisories." | 1 (5 hr 22 min) |
| We pin / cooldown | "Pinning covers what you have, not a new package. We set one cooldown for every ecosystem." | 2, policy |
| Approval / allowlist | "Does that cover the transitive dependencies too?" | 4 |
| **We had an incident** | **Stop. "What happened?"** Anchor the demo on it. | all |

Don't correct them. Name the section you'll show because of what they said.
---

## 1. THREAT ENGINE (3 min)
1. **Ingest:** every version of every package, as it's published. We read the source.
2. **Signals:** shell, network, env vars, filesystem, install scripts, maintainer data.
3. **Speed:** the AI flags new malware at a **6.3 min median**.
4. **Accuracy:** researchers confirm it as known malware. Reversed **under 1%** (npm, PyPI).
5. **Axios** (below)
6. **Worms:** Shai Hulud hit 2,000+ packages and crossed ecosystems. We caught every new version as it spread.

> [!question] ASK
> "How does that compare to what you're seeing from your tools today?"

### AXIOS
- Malicious package: **plain-crypto-js**. It was brand new, with no history.
- **6 min 29 sec:** Socket flags it.
- **+16 min:** axios ships it as a transitive dependency.
- **5 hr 22 min:** the public advisory lands, after Socket.
- Bad versions: **1.14.1, 0.30.4**. **1.14.0 is clean.**

**Line:** "If you rely on an advisory feed, that five hours is your exposure."

> [!question] ASK
> "If that axios version hit your CI tomorrow, what would catch it?"

---

## 2. FIREWALL TERMINAL (3 min)
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

- Run **lodash**, then **aegularjs**, then **npm ci** (the axios beat).
- Skip get-power. Its block reason shows only "Known malware," with no behavior described.
- Point at three things in the block message: **why** it was blocked, the **threat note**, and the **request ID**.
- **Line:** "It's network-based, so it covers agents and vibe coders, not just developers."

> [!question] ASK
> "Where do installs happen for you that security can't see today?"

---

## 3. DASHBOARD EVENTS (2 min)
- Show the block you just triggered. Match its **request ID** to the terminal.
- **Expand the row.** The Machine ID column is blank because of a bug; the data is in the row details.
- Events go to your SIEM through **webhooks**.

> [!question] ASK
> "When something gets blocked today, who finds out, and how?"

---

## 4. SCA (5 min)
1. **Alerts page** (org-wide, skip individual scans): "Every repo, one list. Still a lot of CVEs."
2. **Reachability:** precomputed comes with the install. Full application reachability runs in CI.
3. **Show the drop on screen.** Say the count you see, not a percentage.
4. **Open the fly-out** to show the proof that a CVE is reachable.
5. **Remediation:** socket fix bumps versions. Mention Patches as a concept only.

> [!question] ASK
> "How are you deciding which CVEs to fix today?"

> [!question] ASK
> "Who owns the fix today: security or the dev team?"

---

## 5. CLOSE (2 min)
Recap the three sections. Then:
> "The usual next step is a short POC in your CI: known malware plus a cooldown window."

> [!question] ASK
> "What would you need to see in a POC to make a decision? Who else should be there?"

---

## IF THEY PUSH
- **"Does human review slow you down?"**
  No. Blocking doesn't wait for the human. You can block on the AI flag at 6 minutes. The researcher confirms afterward, which is what makes it known malware.
- **"What's your false positive rate?"** (never give a number)
  Some customers block on AI-detected malware because they want protection as early as possible. Others block only on known malware and add a cooldown to cover the gap.
- **"Why not our EDR?"**
  EDR sees it after it's on the machine. We stop the download.
- **"Isn't this just OSV?"**
  OSV mostly updates when a registry takes a package down. Small packages often never get taken down.
- **"How many alert types?"**
  Every alert type can be set to block, warn, or ignore individually. Don't give a count.
- **"Latency?"** (don't volunteer it)
  Decisions are cached, so repeat installs don't wait on us. We'll measure it in the POC.
- **"Why you?"**
  We found and named Shai Hulud, GlassWorm, axios, and Laravel.
- **"Ecosystems?"**
  npm, PyPI, Go, Maven, NuGet, RubyGems, Cargo, Composer, Swift. Plus Chrome extensions, Open VSX, Hugging Face, and GitHub Actions.

---

## NEVER SAY
- "confirmed within the hour" (the median is **22.6 hrs**)
- any false positive %
- "86 categories"
- "Tier 1 / Tier 2"
- "our data is the best"
- VS Code Marketplace (say **Open VSX**)
- "we block Chrome extensions"
- "under 5 minutes" for npm
- axios **1.14.0**
- "first day on the job"

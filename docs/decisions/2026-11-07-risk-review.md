# Risk-scaled review before /ship merges

Goal: score each change for risk and spend review effort to match, so changes
ship at quality the owner does not have to worry about later.

## Round 1 · 2026-11-07

**Shown first:** `/ship` goes gate → walk → merge with no review step. The
built-in `/code-review` already takes an effort level (low…max) and verifies
findings before reporting. Matt Pocock's `/implement` ends by calling his
two-axis `/code-review`.

### Q0 · Why
**Owner's words:** "i want quality changes and not be worried later"

### Q1 · Where it lives
**Chosen:** a model-invoked `risk-review` skill, called by `/ship` between the gate and the merge, callable on its own. *(my recommendation)*
**Why:** `/ship` is already 151 lines; other skills can call a separate one.
**Rejected:** inline in `/ship` (grows the route, not reusable).

### Q2 · Engine
**Chosen:** the built-in `/code-review` at an effort set by the lane (L→low, M→medium, H→high), plus `/security-review`. *(my recommendation)*
**Why:** reviewers plus verification already exist and are maintained upstream.
**Rejected:** an own reviewer + checker swarm per lane (full model control, but prompts to maintain, ~500k tokens per M ship).

### Q3 · Deterministic score
**Chosen:** `risk.sh`, bash 3.2, scores the diff 0-10 from size and risky paths; repos add paths in `.claude/ship.json` `riskPaths`. *(my recommendation)*
**Why:** same diff, same score, zero tokens.

### Q4 · Agent estimate
**Chosen:** the implementing agent writes `Risk: N/10` in the commit body; final = max(script, agent). *(my recommendation)*
**Why:** the agent can raise the score, never lower it.

### Q5 · Thresholds
**Chosen:** 0-3 L, 4-6 M, 7-10 H. *(my recommendation)*

### Q6 · Manual override
**Chosen:** `/ship l|m|h` as a lone first word; lowering below the computed lane needs a reason logged in the PR body. *(my recommendation)*

### Q7 · Fix rounds
**Chosen:** review → fix → re-review, cap L 1, M 3, H min 2 max 3; blocking findings left at the cap stop the ship. *(my recommendation)*

### Q8 · H waits for the owner
**Chosen:** on H, open the PR labelled `needs-owner-read` and stop before merging. *(my recommendation)*
**Why:** breaks "invoking /ship is the permission" only for the riskiest changes.

### Q9 · What blocks
**Chosen:** only verified correctness and security findings block; the rest is listed in the PR body. *(my recommendation)*

### Q10 · Quiet lane
**Chosen:** a docs-only diff (`/ship` quiet lane) skips review. *(my recommendation)*

### Q11 · Log line
**Chosen:** `Risk 5/10 (script 4, agent 5) → M · code-review medium · 2 rounds · 3 fixed, 1 noted` in the PR body and the report. *(my recommendation)*

### Q12 · Own swarm
**Status:** dropped, Q2 went yes.

### Default taken: security review on any lane
**Chosen:** `/security-review` runs on every lane when the diff touches a security path (auth, env, secrets, payments), and always on H. *my call*, from the Q0 why.

## Design · 2026-11-07

- `skills/risk-review/risk.sh <base> [--lane l|m|h --reason "<why>"]`, bash 3.2. Scores `git diff <base>...HEAD`: size (lines, files) plus risky-path categories (migrations, auth/secrets/env, payments, CI/infra, dependency manifests and lockfiles, public schemas), each category counted once, plus `riskPaths` globs from `.claude/ship.json`. Takes max with the highest `Risk: N/10` trailer in `<base>..HEAD`. Caps at 10, maps to L/M/H, applies `--lane`, exits non-zero if the lane is lowered without `--reason`. Prints `key=value` lines: `script`, `agent`, `score`, `lane`, `security` (yes when a security path was touched), `reasons`.
- `skills/risk-review/SKILL.md` (model-invoked): 0. no `Risk:` trailer on HEAD → estimate and amend one in. 1. run `risk.sh`. 2. per lane: Skill `code-review` at low/medium/high on the branch; Skill `security-review` when `security=yes` or lane H. 3. fix verified correctness/security findings, amend, re-run the repo gate, re-review, until clean or the cap (L 1, M 3, H min 2 max 3); blocking left at the cap → stop. 4. return the log line and the non-blocking findings.
- `/ship`: step 0 parses a lone first-word `l|m|h` as the lane override; new step 3b calls `risk-review` on code and full lanes only (quiet lane skips); step 5 on lane H opens the PR labelled `needs-owner-read` and stops before the lock; PR body and report carry the log line.
- Rejected: the agent computes max and enforces the override from prose (a rule in prose is skipped by whoever forgets it).

## Builder check · 2026-11-07

A fresh agent read this file, `/ship` and `clean.sh` cold. Ten questions; none already answered.

### Minor (*my call*)
- **Squash keeps the trailer:** `/ship` step 1 copies the highest `Risk:` trailer on the branch into the squash message, so the shipping agent cannot lower the implementing agent's estimate.
- **Override syntax:** `/ship --lane l|m|h --reason "<why>" <title>`. Flags, so a title starting with a lone "H" is not misread.
- **Formula** (in `risk.sh`, tunable; reasons logged): lines changed excluding lockfiles and generated files <100 → 0, <400 → 1, <1000 → 2, else 3; >15 files +1. Categories, once each: migrations +4, auth/secrets/env +3 (security), payments +3 (security), CI/infra +2, public schemas +2, dependency manifests or lockfiles +1, any `riskPaths` match +3. Cap 10.
- **Round:** one review plus its fixes; caps count reviews. H always runs a second review, even after a clean first. After fixes the score is recomputed: the lane can rise, never fall.
- **Upstream moved:** re-review only after a rebase whose conflicts were resolved by hand; a clean rebase re-runs the gates only.
- **What blocks:** `code-review` correctness findings (it verifies before reporting); its cleanups are noted. `security-review` findings of medium severity and up. Fixes are made by hand, never `--fix`, so cleanups are not applied silently.
- **Standalone gate:** `/ship` passes its gate command in; on its own, `risk-review` uses `.claude/ship.json` `gates`, or reports that no gate was re-run.
- **Stop at the cap:** fixes are kept and pushed, a draft PR is opened labelled `needs-owner-read` with the open findings, nothing merges. Added to `/ship`'s stop list.

### Owner's (asked in round 2)
- Q13: how an H ship finishes. Q14: quiet lane and risky paths.

## Round 2 · 2026-11-07

### Q13 · How an H ship finishes (first framing)
**Rejected by the owner:** stop before merge, PR labelled `needs-owner-read`, owner removes the label and re-runs `/ship`.
**Owner's words:** "it is ok to answer something when invoke ship, but if it stops me and asks permissions on each step - this would not be good"
**Status:** re-asked in round 3 as one question at the end of the same run.

### Q14 · Quiet lane and risky paths
**Chosen:** `risk.sh` runs on quiet-lane diffs too; review is skipped only at score 0-3; `--lane` forces review on any diff. *(my recommendation)*
**Why:** hooks and scripts that `/ship`'s config marks quiet can break as much as app code.

## Round 3 · 2026-11-07

### Q13 · How an H ship finishes
**Chosen:** on H, `/ship` runs every review round, fix and gate and opens the PR, then asks the owner one question in the same run: what changed, what was found and fixed, the PR link, "merge?". Yes merges under the lock; no leaves the PR open. L and M never ask. *(my recommendation, reframed)*
**Rejected:** stop, label `needs-owner-read`, re-run `/ship` (owner: a permission stop per step is not acceptable).

### Q15 · Blocking findings left at the cap
**Chosen:** one question: "N blocking findings remain after M rounds: fix another round / merge anyway / stop?". Without an answer it waits; it never merges a known blocking finding on its own. Replaces the draft-PR stop in the builder-check pile. *(my recommendation)*

The frontier is empty: acceptance criteria can be written without guessing.

## Status · 2026-11-07

Q1-Q11, Q13-Q15, the security default and the builder-check calls: **built** in `skills/risk-review/` and `skills/ship/`. Q12: superseded by Q2. Not yet run end to end on a real `/ship`; the first real H and M ships are the test.

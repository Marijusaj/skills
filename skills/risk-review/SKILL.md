---
name: risk-review
description: Score a branch's risk 0-10 and review it with effort to match (low, medium, high lanes), fixing what blocks before it merges. Use when /ship reaches its review step, when the owner says "review this branch" or "how risky is this", and before merging work an agent implemented.
---

# Risk review

Review effort should follow what a change can break, not habit. A script scores
the diff, the implementing agent's own estimate can raise it, and the lane
decides how hard and how often to look.

```
Risk: N/10 trailer ─┐
risk.sh on the diff ┼─▶ max() ─▶ 0-10 ─▶ L / M / H ─▶ review rounds ─▶ log line
--lane override ────┘                                (fix, re-gate, re-review)
```

Inputs: the base ref (`origin/<default>`), and from `/ship` the gate command
and any `--lane`/`--reason`. On its own, take the gate from `.claude/ship.json`
`gates`; without one, say in the log line that no gate was re-run.

## 0. The agent's estimate

`git log --format=%B <base>..HEAD | grep '^Risk:'` prints nothing: estimate
the risk yourself (what breaks for users or data if this is wrong) and amend a
`Risk: N/10` trailer into HEAD. A trailer already there is never lowered.
**Done when** the grep prints a line.

## 1. Score

```bash
bash <this skill's dir>/risk.sh <base> [--lane l|m|h --reason "<why>"]
```

Exit 2 means a lane was lowered without a reason: ask the owner for one.
**Done when** you have `score`, `lane`, `security` and `reasons`.

## 2. Review in rounds

| Lane | Score | Review | Rounds |
|---|---|---|---|
| L | 0-3 | Skill `code-review`, args `low <branch>` | 1 |
| M | 4-6 | Skill `code-review`, args `medium <branch>` | up to 3 |
| H | 7-10 | Skill `code-review`, args `high <branch>` | at least 2, up to 3 |

Also call the Skill tool with "security-review" in round 1 when
`security=yes` or the lane is H. A round is one review plus its fixes.

**What blocks:** correctness findings from `code-review` (it verifies before
reporting) and `security-review` findings of medium severity or higher.
Everything else is *noted*, not fixed. Fix blocking findings by hand (never
`--fix`, which also applies cleanups), amend, re-run the gate. Red gate: fix it
before the next round. Re-run `risk.sh` after fixes: the lane may rise, never
fall. Stop when a round finds nothing blocking and the lane's minimum is met.

**Blocking findings left after the last round:** ask the owner once, listing
them: "fix another round / merge anyway / stop?". Wait for the answer; a known
blocking finding never merges without it.

## 3. Report

Return one log line, then the noted findings as a short list:

```
Risk 5/10 (script 4, agent 5) → M · code-review medium · 2 rounds · 3 fixed, 1 noted
```

Add `· security-review` when it ran and `· override m->l (<reason>)` when the
lane was overridden. **Done when** the line is printed and every blocking
finding is fixed or the owner chose to merge anyway or stop.

Why these weights and lanes, and how to tune them: [`reference.md`](reference.md),
read when the owner asks why a change got its lane or wants it changed.

---
name: ship
description: Take the current branch all the way out. Commit, squash, rebase, run the repo's gates, walk it if it is user-visible, then push and merge under a remote lock so parallel agents cannot collide. Any git repo; reads .claude/ship.json when present.
argument-hint: "[optional PR title]"
disable-model-invocation: true
---

# /ship

Invoking `/ship` **is** the permission. Stop only for a red gate, a conflict
that needs a judgement about intent, a secret or data-dropping migration in the
diff, or a lock you would have to break.

`$ARGUMENTS` is the PR title if given; otherwise derive it from the diff.

## 0. Resolve the repo

`.claude/ship.json` wins over every heuristic; its keys and the shell that
detects `DEF` when it is absent are in `reference.md` § *Resolving the repo*.
Absent a key, detect it:

- **gates**: the repo's `gates` or `ci` script, else chain whatever of
  `lint`/`typecheck`/`build`/`test` exists; outside npm, `make ci`,
  `cargo clippy && cargo test`, `ruff check && pytest`, whatever the repo has.
  **No gate found: say so in the report, never invent one.**
- **runtime version**: honour `.nvmrc`, `engines`, `.tool-versions` or the
  equivalent, activated in the *same* shell command as the gate.
- **uiPaths**: the directories holding rendered UI. Empty for a library or
  CLI: nothing to walk.

Also read the repo's `CLAUDE.md` for what counts as done, where walk evidence
goes, and whether a doc must change with the code. Those override this file.

**Done when** `DEF`, the gate command and the lane paths are printed.

## 1. Commit, then squash to one commit

```bash
git status --short --branch
git add -A && git commit -m "<what changed and why>"
BASE=$(git merge-base HEAD "origin/${DEF}")
git reset --soft "$BASE" && git commit -m "<title>"
```

Glance at what you stage: no build output, no `.env*`, nothing with a key.
Squash **before** rebasing so a conflict is resolved once, against a real
tree. Only squash a branch you own; re-push with `--force-with-lease`, never
bare `--force`.

**The squash message replaces every message on the branch.** A gate that reads
commit messages for an escape trailer (`Docs: n/a - <reason>` and the like)
loses it here. Copy each trailer the branch relied on into the new message, in
the exact form the gate's pattern matches; grep the gate script for that
pattern rather than paraphrasing it. **Done when** `git log -1 --format=%B`
shows every trailer the old commits carried.

## 2. Rebase onto fresh upstream, read the lane

```bash
git fetch origin && git rebase "origin/${DEF}"
git diff --name-only "origin/${DEF}...HEAD"
```

Rebase before gating; gates on a pre-rebase tree prove nothing. A conflict you
cannot resolve cleanly: read `reference.md` § *Cherry-pick*.

| Diff touches | Lane | Route |
|---|---|---|
| only `quietPaths` | **quiet** | gates → merge |
| code, nothing in `uiPaths` | **code** | gates → PR → merge |
| anything in `uiPaths` | **full** | gates → walk → PR → merge |

### 2a. Prune the docs, in this commit

If the repo keeps a doc that must move with the code (a surface doc with a
*Next* or *TODO* list, a changelog, a status section), update it **now**, before
the gate. For every listed item this branch delivers: **delete the line** and
rewrite the present-tense section. Never tick, strike or annotate "(done)".
Leave what this branch does not deliver untouched. Unsure whether an item is
covered: it stays, and the report says which.

**Done when** `git diff --name-only "origin/${DEF}...HEAD" -- '*.md'` lists the
doc, or the repo has none and the report says so.

## 3. Gate

Run the gate as one chained command. Red stops the ship: fix, re-run. Never
`--no-verify` or weaken a check. **Never gate while holding the lock.**

## 4. Walk (full lane only)

Boot the app and drive the real UI. Screenshot each step **straight into
`walkEvidence`** and attach them to the PR. Honour the repo's viewport rule (a
mobile-first surface is walked at phone width). Skipping the walk on the quiet
or code lane is fine: **say so in the PR body**. Never claim a walk you did not
do. Write screenshots to their final path from the start; a stray file in the
repo root blocks worktree removal later, and `rm` sits behind a prompt. In a
**private** repo a `raw.githubusercontent.com` image 404s for every reader, and
a squash deletes the commit it names: link the host's blob view on the default
branch (`/blob/<DEF>/<path>?raw=true`) once merged.

## 5. Merge under the lock

Two agents that both rebased onto the same `${DEF}` will both merge, and the
second one's gates proved nothing. Without branch protection, nothing stops
this except a lock: one remote ref holding an orphan commit, so the second
push is always rejected as non-fast-forward. `refs/ship-lock/*` triggers no CI
and no deploy. Why an orphan, and not a branch tip: `reference.md` Part 1.

The lock's shell code (`acquire`, `release`, the zsh refspec trap) and the
procedure for a lock someone else holds are in `reference.md` § *The lock, step
by step*. **Read it before your first `acquire`.** The loop:

```
for attempt in 1 2 3:
    fetch; rebase onto origin/$DEF; run gates          # slow, unlocked
    acquire()  (retry ~10 s apart, up to ~5 min)
    fetch origin
    if HEAD is not a descendant of origin/$DEF:        # someone merged mid-gate
        release(); continue
    push --force-with-lease; open or ready the PR; gh pr merge --squash
    release(); break
```

**Release on every exit path**, including failure. A held lock under ~15
minutes old: wait. Older than ~30: follow the reference, and **report whose
lock you broke**. **Done when** `gh pr view --json state` says MERGED and
`git ls-remote origin | grep ship-lock` prints nothing.

## 6. Confirm the deploy

If the repo deploys on push to `${DEF}`, the merge is the deploy: `gh run watch`
once, no polling, no provider CLI deploy (they double-build and breed stray
projects from worktrees). The walk in step 4 is the acceptance; hand the owner a
link only for what only they can judge (how it looks, how the copy reads).

## 7. Close out

- `git show --stat HEAD -- '*.md'` lists the pruned doc, or the report names
  the miss. Never a follow-up PR for docs.
- Once `gh pr view --json state` says MERGED: `ExitWorktree` (remove), and
  `git push origin --delete <branch>` if GitHub did not.
- Stop every process and close every browser tab the walk started.
- `git ls-remote origin | grep ship-lock` prints nothing.
- **Report**, one block: what shipped · gates · walk (done, or skipped and why)
  · docs pruned (file, items deleted, items left and why) · PR and merge state
  · deploy · lock contention · workspace.

Something bit you (a rebase you cannot resolve, a lock nobody owns, a change
that must move to a different base)? It is in [`reference.md`](reference.md).
Read it when it happens, not before.

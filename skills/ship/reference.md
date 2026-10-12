# /ship: the traps, and why the steps are the shape they are

Read this **when something bites**, not before; the one exception is § *The
lock, step by step*, which every merge needs. `SKILL.md` is the route; this is
the reasoning behind it. Every entry is a trap that is easy to walk into in
any git repo with more than one agent landing on the default branch.

---

# Part 1: Parallel agents

## The lock, step by step

```bash
LOCKREF="refs/ship-lock/${DEF}"
HOLDER="${AGENT_LABEL:-$(git config user.email)}@$(basename "$PWD")"
acquire() {
  local T C
  T=$(git hash-object -w -t tree /dev/null)
  C=$(git commit-tree "$T" -m "ship-lock ${HOLDER} $(date +%s)")
  git push origin "${C}:${LOCKREF}" 2>/dev/null     # rc 0 acquired, 1 held
}
release() { git push origin ":${LOCKREF}" 2>/dev/null; }
```

Brace every variable in the refspec (`"${C}:refs/..."`); see the zsh trap below.

**In a session that refuses compound shell commands** (an isolated worktree
whose guard rejects `$(...)` next to `git`), put `acquire`/`release` in a
script file outside the repo with an `acquire|release|show` switch and run it
as `bash <file> acquire`. The guard passes a plain script call; it refuses the
functions typed inline.

Inside the lock: `git push -u origin HEAD --force-with-lease`, then
`gh pr create` (or `gh pr ready` on a draft), then `gh pr merge --squash
--delete-branch`. A quiet lane may `git push origin HEAD:${DEF}` instead, if
the repo allows it, still inside the lock. `gh pr merge` from a worktree can
print nothing or error on the branch delete after merging fine: read
`gh pr view --json state,mergedAt` before deciding it failed.

**A lock already held:** read the holder.

```bash
git fetch -q origin "+${LOCKREF}:refs/remotes/shiplock/${DEF}"
git log -1 --format='%s | %cr' "refs/remotes/shiplock/${DEF}"
```

Under ~15 minutes old: wait and retry. Over ~30: confirm no PR is mid-merge
(`gh pr list --state open`), break it with `release()`, and report whose lock
you broke.

## Why a lock, and not "just be careful"

Two agents, both branched off the same base, both rebase onto it, both gate
green, both merge. The second merge lands a tree **no gate ever ran on**.
Nothing in git prevents this: `git push` is a fast-forward check on *that
branch*, and a PR squash-merge is a server-side commit that ignores what your
local ever saw.

The platform answers are branch protection with "require branches to be up to
date" and a merge queue. On plans where those are unavailable there is no
platform-side serialisation at all, and the lock in step 5 is the only thing
there.

## Why an orphan commit specifically

The obvious lock is "push your branch tip to a ref, first one wins". It leaks:
if agent B's branch descends from agent A's tip (B branched off A, or A merged
and B rebased onto it), B's push is a legal fast-forward and **B silently
steals a held lock**. Rare, silent, and exactly the scenario the lock exists
for.

An orphan commit (empty tree, no parents, unique message) can never be an
ancestor or descendant of another one, so every contending push is rejected as
non-fast-forward. The holder's identity and acquisition time ride in the commit
message, which is what makes stale-lock detection possible without a side
channel. `refs/ship-lock/*` is neither a branch nor a tag, so CI does not fire
on it and a connected host does not deploy it.

## zsh mangles `$VAR:refs/...` inside double quotes

```
git push origin "$C:refs/ship-lock/main"
error: src refspec <sha>...efs/ship-lock/main does not match any
```

zsh applies the `:r` history modifier ("strip extension") to `$C` even inside
double quotes, eating the `r` of `refs`. The error looks almost right, which is
why it is slow to spot. Brace every variable in a refspec: `"${C}:refs/..."`.

## Never hold the lock while gating

Gates take seconds on a small repo and minutes on a real one. Holding the lock
across them serialises every agent behind the slowest build. Hold it only
across `fetch → descendant check → push → merge`.

The price is the re-check inside the lock: the default branch may have moved
while you gated, so you release, rebase, re-gate, retry. **Three attempts,
then stop and report.** Losing the race three times means the repo is busier
than a lock can paper over, and a human should decide the order.

## A lock nobody owns

`git ls-remote origin | grep ship-lock` shows a held lock; its commit message
shows who and when. Before breaking one, check `gh pr list --state open`. A
merge-able PR from the holder means the agent is alive and slow. Nothing in
flight and the lock older than ~30 minutes: break it and **name the holder in
your report**. A silently broken lock is worse than none, because the next
agent trusts it.

## Worktrees are the other half

The lock stops two agents merging at once. It does nothing about two agents
editing the same checkout. One worktree per front, one branch per worktree.

---

# Part 2: Cherry-pick, and getting unstuck

Cherry-pick is the **escape hatch from a rebase**, never an alternative road to
the default branch. Whatever you salvage still goes through gates, PR and lock.

## When the rebase is worse than starting over

Symptoms: conflicts in files you never touched, the same hunk conflicting on
commit after commit, a resolution you cannot justify because the intermediate
tree is fictional.

```bash
git rebase --abort
git rev-parse HEAD                       # your squashed commit; write it down
git switch -c <branch>-v2 "origin/${DEF}"
git cherry-pick <that-sha>               # one commit, one conflict, real trees
```

This is why step 1 squashes first: with N commits there is no single commit
that represents your change, so there is nothing clean to pick.

If even that conflicts badly and your change is confined to files nobody else
touched, take the files wholesale and read the diff before committing:

```bash
git checkout <that-sha> -- path/to/file path/to/other
git diff --cached "origin/${DEF}"
```

Only for files you own end-to-end. On a file another agent also edited, this
throws their work away silently.

## When another agent merged an overlapping change

A judgement call, and one of the few things `/ship` may stop for.

- **Resolve toward *their* merged version**, then re-apply your intent on top.
  Theirs is already gated and possibly deployed.
- **Never `-X ours` / `-X theirs` on a whole file.** Both sides were somebody's
  intended change; a strategy flag picks a winner without reading either.
- Re-run gates after any non-trivial resolution. A resolution is new code no
  gate has seen.
- If their change made yours unnecessary, say so and drop it.

## Salvaging from a tangled branch

```bash
git log --oneline "origin/${DEF}"..<branch>
git switch -c salvage "origin/${DEF}"
git cherry-pick <sha>                     # the one commit worth keeping
git cherry-pick -n <sha>                  # stage without committing, to edit first
```

A commit lost to a bad reset or force-push is still in `git reflog` for the gc
window, including on a branch you rewrote.

## A rebase invalidates the walk, not just the gates

Rebase first, walk second. Screenshots taken before a rebase document a tree
that is not the one you merge.

---

# Part 3: Everything else that bites

## Rebase early; the drift curve is not linear

A branch a few commits behind merges cleanly. A branch a hundred behind, even
with little work on it, turns into a fight over files it never touched, and the
usual outcomes are a change re-applied by hand or a PR closed with its work
abandoned. Nothing about the work was unmergeable on the day it was written.

## The delete that parks the ship

`rm` usually sits behind a permission prompt, so every delete blocks until a
human clicks, and a ship run mid-walk can sit for hours on one. Do not create
the mess: screenshots go straight to their final path, scratch goes outside
the repo, and `git clean -fd <path>` handles the rest without a prompt.

Image files in a repo root are often gitignored, so a stray screenshot is
invisible to `git status` yet still dirties the worktree enough to block its
removal.

## Provider CLIs breed stray projects from a worktree

A provider's local link file is typically gitignored, so **a worktree never has
it**. Any provider command run there sees an unlinked directory and links a
*new* project named after the cwd, and a `--yes` flag auto-confirms. Do not use
the provider CLI for deploy state at all: `gh run watch` blocks on the real
run, and provider MCP tools query by project name with no local link involved.

## Waiting on CI: block once, never poll

A polling loop (`gh pr checks` every few seconds, `sleep` in a `for`) spends
dozens of tool calls on one question. `gh run watch` blocks until the run
resolves and costs one.

## Merge and workspace aftermath

- **`--delete-branch` from a worktree errors "already checked out" *after*
  the merge succeeded.** A cleanup failure, not a merge failure. Verify with
  `gh pr view --json state,mergedAt`; do not retry the merge or revert.
- **A squash merge hides the merge from git.** `git branch --merged` will not
  list the branch and `git log origin/main..HEAD` still shows its commits,
  because the work landed as one new commit. Ask the host:
  `gh pr list --head <branch> --state merged`.
- **A branch checked out in any worktree cannot be deleted.** Remove the
  worktree first. A locked worktree cannot be removed at all until unlocked.

## The walk

**A green build proves nothing about a browser.** Content-security headers,
workers missing from a serverless bundle, a width class truncating a label:
all invisible to the type checker, linter and build, all found by driving it.

**Browser automation fails in recognisable ways.** "Target page, context or
browser has been closed" and "browser is already in use" mean close the
browser, wait for the process to exit, reconnect. Neither is a bug in the
change you are shipping.

**From a worktree the dev server usually needs the local env file linked in.**
`node_modules` resolves upward on its own; a `.env.local` does not.

## Scope creep is the other tail

A walk genuinely finds bugs, and that is the process working. A bug that makes
the thing you are shipping wrong is fixed in this PR. Anything else becomes a
new slice. The doc prune from step 2a is never a second PR.

## Know what the gates cost before you "optimise" one

Measure each gate once, warm, before removing any. A type check duplicated
inside the build is real waste; a lint step that the build no longer runs is
not. The gates people skip by hand are usually the cheapest ones, which is why
a single `gates` script exists: so they cannot be.

---

# Part 4: Reasoning behind two steps

## Why squash before the rebase

The intermediate commits are discarded at squash-merge time anyway. But
rebasing N commits means resolving conflicts N times, each against a tree that
never existed and never will again. One commit means one resolution, against
the tree you intend to merge, and it is what makes the cherry-pick escape in
Part 2 possible.

## Docs pruning: the full rule

A *Next* list is a list of things not yet done. A completed item in it is
noise, and ticks accumulate into the stale pile the step exists to prevent.
For every item this branch delivers:

- Delete the line. Do not tick, strike or annotate it "(done)".
- Move what is now true into the doc's present-tense section, rewriting the
  existing line rather than appending a second.
- Add one dated line to a *Decisions* section only if you decided something.
- An item made moot by another merge or by the design moving on is deleted
  too, and the report says so.
- Leave anything this branch does not deliver exactly as it is. Pruning is not
  tidying.

Find the docs without being handed them: the file the session worked from, the
repo's surface doc with a *Next* list, and
`git diff --name-only "origin/${DEF}...HEAD" -- '*.md'`.

Over-deleting loses work; under-deleting costs one line. Pre-merge, every lane,
never a follow-up PR: a follow-up for docs is how the prune gets skipped.

## Resolving the repo

`.claude/ship.json`, every key optional:

```json
{
  "defaultBranch": "main",
  "gates": "npm run gates",
  "walk": "npm run dev",
  "walkEvidence": "docs/walks/<date>-<topic>/",
  "uiPaths": ["src/app/", "src/components/"],
  "quietPaths": ["docs/", ".claude/", "scripts/"],
  "lock": true
}
```

Absent a key, detect it:

```bash
ROOT=$(git rev-parse --show-toplevel)
DEF=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
DEF=${DEF:-$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)}
DEF=${DEF:-main}
```

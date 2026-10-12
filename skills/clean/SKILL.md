---
name: clean
description: Retire what this session and the sessions it launched left behind. Child sessions, the dev servers and browsers they started, their merged worktrees and branches. Never touches other sessions' work. Invoke with /clean once the work is merged; /clean-all for strays anywhere on the machine.
disable-model-invocation: true
---

# /clean

The owner runs this in a session whose work they believe is merged, and wants
**nothing it left behind** still running or lying around: a forgotten dev
server, a browser launched to walk the app, a child session. Invoking `/clean`
**is** the permission to retire every row the survey marks `ACT`.

**Scope: this session and its children only.** Other sessions on the machine,
their servers, worktrees and branches, are not this session's business even if
they look idle. That is `/clean-all`, which the owner runs on purpose.

What counts as this session's is decided by `clean.sh`, not by you:

- **child sessions**: launched by this one with `claude --bg`, and theirs.
  Agent-tool subagents run inside this session and are covered with it.
- **processes**: dev servers and browsers in this session's or a child's
  process tree, plus orphans whose folder is one of this session's worktrees.
  MCP servers are left alone.
- **repo things**: worktrees this session entered, their branches, and the head
  branches of this session's PRs. The main checkout only if it is parked on
  one of those branches.

| Verdict | Meaning | What you do |
|---|---|---|
| `ACT`  | provably finished: merged on GitHub, nothing unique, nothing running | retire it |
| `ASK`  | probably finished, but something could be lost | one question to the owner |
| `KEEP` | in use, or unfinished work | leave it; say why in one line |

"Merged" comes from `gh`, never `git branch --merged`: a squash merge makes
every merged branch look unmerged to git forever.

## 1. Survey and retire

```bash
<skill-dir>/clean.sh --apply        # <skill-dir> is the folder this SKILL.md is in
```

One command: works out the scope, prints the ACT / ASK / KEEP table (first
line `Scope: this session + N session(s) it launched`), retires the ACT rows
in a safe order (sessions → servers → browsers → worktrees → main checkout →
local branches → remote branches), prints `ok` or `FAIL` per row and free RAM
before and after. Without `--apply` it only surveys. `--as <pid>` surveys
another session's view, never with `--apply`.

`$ARGUMENTS` of `all` means the owner wants the machine-wide sweep: follow
`/clean-all` instead.

A `FAIL`: read its message, fix a mechanical cause (`git worktree unlock`, a
branch still checked out elsewhere), re-run. Never `--force` or `rm -rf` past
one.

**Done when** the table has been printed and every ACT row shows `ok`.

## 2. The ASK rows: one question, not a conversation

Ask **once** with `AskUserQuestion` (multiSelect, one option per row, grouped
by kind above four). Recommendation first:

- **uncommitted files in a merged worktree**: name the files. Scratch, build
  output, screenshots → remove. Anything that looks like work → keep.
- **PR closed without merging** → delete; the commits stay on the closed PR.
- **commits after the merge** → keep; show `git log --oneline <pr-head>..<branch>`.
- **main checkout with edited tracked files** → keep; show the file names.
- **a server started from a terminal** → name port and folder; stop unless the
  owner is using it.
- **a viewer attached to a stopped session** → close.
- **`STALE:` rows** (untouched 60+ days, no open PR) → delete, as one grouped
  option. Still ask: it may hold unshipped work.

Then run exactly the commands printed under `── ASK commands ──` for the rows
chosen. Nothing else.

## 3. Browser tabs

`clean.sh` sees separate browser processes only. A walk done through Claude in
Chrome leaves tabs in the owner's own browser. If the `mcp__claude-in-chrome__*`
tools are available, call `tabs_context_mcp` and close tabs in the MCP tab
group that **this session opened** and that point at `localhost`, `127.0.0.1`
or a preview deployment. Never touch the owner's other tabs or windows.

## 4. Yourself

Inside a worktree whose work is merged: finish with `ExitWorktree` (remove);
the script leaves the worktree you are sitting in alone. This session's own
process is always KEEP; tell the owner it can be closed.

## 5. Report, in plain language

- RAM free: before → after.
- Retired, as counts per kind ("stopped 2 child sessions and 1 dev server,
  removed 2 worktrees, deleted 3 merged branches locally and on GitHub").
- Each ASK decision and what you did.
- Kept: one line per session or worktree with why; branches as a count.
- If the owner expects more to go, point at `/clean-all` rather than widening.

## Never

- Touch a session that is not this one or one it launched. That is `/clean-all`.
- Stop a session that is busy or waiting, or this one.
- Stop a Remote Control server (`claude rc`) or its sessions; the owner ends
  those from their device.
- Delete the default branch, or remove a dirty worktree without a yes.
- `rm -rf` a worktree (use `git worktree remove`), `git push --force`, or
  `git clean` anything.
- Kill an app; only runtimes the survey lists.
- Re-decide what the script decided. A wrong verdict: say so and fix `clean.sh`
  so it is right next time.

If the permission classifier refuses a stop or kill, show the owner the exact
command and ask them to allow it.

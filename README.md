# Skills

Agent skills I use every day with Claude Code, written for parallel agents
landing on one default branch. Each one is the route; the reasoning sits in a
`reference.md` beside it, read only when something bites.

| Skill | Invoked by | What it does |
|---|---|---|
| [design-check](skills/design-check/SKILL.md) | the model | Checks a design before code is written: deep vs shallow modules, the red flags, facts vs stored conclusions, and a four-line output block the owner reads instead of the code. |
| [ship](skills/ship/SKILL.md) | you, `/ship` | Takes the current branch all the way out: commit, squash, rebase, gates, walk the UI if it changed, then push and merge under a remote lock so two agents cannot land unverified trees. |
| [clean](skills/clean/SKILL.md) | you, `/clean` | Retires what this session and its child sessions left behind: dev servers, browsers, merged worktrees and branches. Never touches other sessions. |
| [clean-all](skills/clean-all/SKILL.md) | you, `/clean-all` | The same sweep across the whole machine and every repo under `$CLEAN_REPOS` (default `~/Code`). |

## Install

Symlink the skills into Claude Code's skill directory. A `git pull` then keeps
them current.

```bash
git clone https://github.com/Marijusaj/skills ~/Code/skills
for s in ~/Code/skills/skills/*/; do ln -sfn "$s" ~/.claude/skills/$(basename "$s"); done
```

Or install as a plugin, which namespaces the skills (`marijusaj-skills:ship`)
so they cannot clash with a `ship` you already have:

```bash
claude plugin marketplace add Marijusaj/skills
claude plugin install marijusaj-skills@marijusaj
```

## Per-repo configuration

`ship` reads `.claude/ship.json` in the repo when present; every key is
optional and detected otherwise. See the top of
[ship/SKILL.md](skills/ship/SKILL.md).

`clean` and `clean-all` run `clean.sh`, a bash 3.2 script for macOS that
surveys sessions, servers, browsers, worktrees and branches and prints an
ACT / ASK / KEEP table. Run it without `--apply` to look first. "Merged" is
asked of GitHub through `gh`, never `git branch --merged`, because a squash
merge makes every merged branch look unmerged to git.

## Writing style

Skills state the trap, the rule and the check. No war stories, no dates, no
repo names: a reader in another codebase should recognise every line. SKILL.md
is the route and stays short; the why lives in `reference.md`.

## Licence

MIT.

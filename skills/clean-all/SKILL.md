---
name: clean-all
description: Hunt for strays anywhere on the machine. Idle sessions from any project, dev servers and browsers nobody owns, orphaned helpers, viewers of dead sessions, merged worktrees and branches in every repo under the code directory. Invoke with /clean-all when RAM is tight; /clean covers only the current session.
disable-model-invocation: true
---

# /clean-all

Machine-wide `/clean`. Idle sessions from other projects, forgotten dev servers
and browsers add up, and the owner should not have to track them. Invoking
`/clean-all` **is** the permission to retire every `ACT` row.

```bash
<skill-dir>/../clean/clean.sh --apply --all   # <skill-dir> is the folder this SKILL.md is in
```

Same script, same table, first line `Scope: the whole machine`. It surveys
every session, listening runtime, browser and orphaned helper on the machine,
plus every git repo under `$CLEAN_REPOS` (default `~/Code`). Without `--apply`
it only surveys.

Machine-wide verdicts, decided by the script:

| Kind | ACT | ASK | KEEP |
|---|---|---|---|
| sessions | idle 60+ min, or idle 15+ min and never given a task | | busy, waiting, interactive, or this one |
| servers, browsers | their session is being stopped, or orphaned | no session owns them (started from a terminal) | a kept session started them |
| viewers | | a `claude attach` tab whose session is gone | |
| Remote Control | | | always; the row says what archiving its idle sessions would free |
| repos | same rules as `/clean`, every repo under `$CLEAN_REPOS` | | |

Stopped sessions keep their conversation: `claude attach <id>` reopens one.

## Then

Follow `/clean` sections 2 to 5 and its **Never** list
(`../clean/SKILL.md`, beside this skill): one question for the ASK rows with your
recommendation first, close walk tabs in the MCP tab group (here: any pointing
at `localhost`, `127.0.0.1` or a preview deployment, not only this session's),
leave yourself, report in plain language. The one difference: other sessions'
leftovers **are** in scope; the script decides which are finished.

## Why sessions pile up (if the owner asks)

Each `claude` is three processes: the session, its `bg-pty-host` wrapper, and
the terminal window showing it. The supervisor frees an idle session after
about an hour **only while no window is attached**; an open terminal tab keeps
it alive forever. Closing a tab never kills work. `clean.sh` cannot tell which
session a plain `claude` window shows, so it never closes one: if RAM is tight,
suggest closing tabs the owner is not watching. One pre-warmed spare
(`bg-spare` with no session) is normal and cannot be turned off.

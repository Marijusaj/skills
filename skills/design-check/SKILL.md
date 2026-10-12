---
name: design-check
description: Check a design before writing code. Use before adding a module, class, table, column, API or server action; before fixing a bug in code touched in the last two weeks; before spawning implementation subagents; and when the owner asks "how should I structure this", "where should this live", "why does this keep breaking". Small changes too: complexity arrives one small decision at a time.
---

# Design check

From Ousterhout's *A Philosophy of Software Design*, plus the chapter he did
not write (stored state), plus a fixed output block so the owner can review a
design without reading the code.

**Complexity has two causes**, and every rule below reduces to one of them:

- **Dependencies**: code that cannot be understood or changed alone. Symptom: a
  small change means edits in many places (*change amplification*).
- **Obscurity**: important information that is not visible. Symptom: you cannot
  tell what you need to change (*unknown unknowns*).

**Skip it** for typos, renames, version bumps, copy, config values, formatting
and docs-only changes. A check that appears on every turn stops being read.

## 1. Modules should be deep

A module is anything with an interface and an implementation: function, class,
file, service, table, API.

```
DEEP (aim for this)              SHALLOW (a smell)
  ┌──────────┐  small interface    ┌────────────────────┐  interface as wide
  │  call()  │                     │ a() b() c() d() e()│  as the thing itself
  ├──────────┤                     ├────────────────────┤
  │ hides a  │  rich body          │ thin passthrough   │  every caller must
  │ lot      │                     └────────────────────┘  know the internals
  └──────────┘
```

**Sketch two interfaces before you pick one.** Compare on the caller's
experience, not the implementation. **Write the interface comment before the
body**: if it needs "and", the boundary is wrong.

**Pull complexity downward.** Retries, defaults, edge cases, ordering: one
implementer suffers so N callers do not. **Define errors out of existence**: a
default that removes an argument, an idempotent operation so "already done" is
not an error, several error types collapsed into one the caller can act on.

## 2. The red flags: stop on a hit

| Red flag | The test |
|---|---|
| **Shallow module** | interface nearly as complex as the implementation |
| **Information leakage** | two modules must both change when one format changes |
| **Temporal decomposition** | structure mirrors *when* things happen, not *what they know* |
| **Overexposure** | common use forces awareness of a rare feature |
| **Pass-through method** | calls another with the same signature |
| **Repetition** | the same snippet or rule appears again and again |
| **Special-general mixture** | a special case entangled with the general mechanism |
| **Conjoined methods** | you cannot understand one without reading the other |
| **Comment repeats code** | adds nothing the code lacks |
| **Impl. docs in the interface** | callers told internals they do not need |
| **Vague name** | `data`, `process`, `handle` |
| **Hard to pick a name** | no clear name exists, so the boundary is wrong |
| **Hard to describe** | the interface needs a long comment |
| **Nonobvious code** | behaviour cannot be guessed from reading it |

Frameworks push you into temporal decomposition (by route, screen, step,
request lifecycle), which is how one rule ends up implemented differently in
dozens of files. Decompose by *knowledge*, not by *chronology*.

## 3. Facts and conclusions

> **Store facts. Derive conclusions. Never store a conclusion you can compute.**

| Fact: store it | Conclusion: derive it |
|---|---|
| rows in a `payments` table | "this invoice is paid" |
| rows in a points ledger | a `balance` column |
| notifications with a `read_at` | an `unread_count` |
| the server's response | the copy held in component state |
| a `deleted_at` timestamp | an `is_active` boolean beside it |
| the events that occurred | a `status` enum summarising them |

Anything in the right column, *stored*, is a second home for a truth that
already lives on the left. It will drift and nothing will announce it.

**A rule is only as strong as the layer it lives in:**

| Where the rule lives | Who can ignore it |
|---|---|
| a comment, a doc, a convention | anyone, silently |
| a type | anyone at runtime |
| a helper you must remember to call | **anyone who does not call it** |
| the only available path to the data | nobody, if there is no other path |
| a database constraint, view or generated column | **nobody** |

**The one exception.** When deriving is too expensive (a hot path, a huge
table), cache the conclusion, maintained by the layer that owns the data (a
trigger, a materialised view, a generated column), never by application code
remembering to update it. Say which one you built and why the read cost
justified it.

## 4. The output: four answers, every time

End any non-trivial change with this block, unprompted, so the design can be
reviewed by someone who does not read the code. Answer honestly, including
when the answer is bad; a block that always says "1 file" is decoration.

```
Design check
  Fact or conclusion?   <what is stored, what is derived, and why>
  Computed elsewhere?   <N sites found → N fixed / N remain, named>
  Strongest layer?      <where the rule lives, and what can still bypass it>
  Change amplification? <if this rule changes next month: N files>
```

If "computed elsewhere" is more than one and you fixed one, list the rest.
**A named unfixed duplicate is a decision; a silent one is the next bug.**

When a flag fires and the fix cuts against instinct (one long method, fewer
classes, consistency versus correctness), or you want the incident behind the
layer rule, read [`reference.md`](reference.md).

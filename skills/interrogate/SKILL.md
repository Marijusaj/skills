---
name: interrogate
description: Interrogate the owner until you know what to build, in rounds of questions that each carry your recommended answer, then capture the answers, check the design with a cold reader, plan and build. Use when the owner says "interrogate me", "grill me", "ask me questions until you know what to build" or "give me your recommended answer"; when a non-trivial feature or fix starts from a goal not yet pinned to decisions; and before spawning implementation subagents.
---

# Interrogate

The owner decides fast when handed a recommendation and the trade-off behind
it, and slowly when handed an open question. The answers are the design, so
the job is to get the decisions, **write them where they survive the session**,
and prove the result is buildable by someone who was not in the room.

```
research ─▶ premise ─▶ round ─▶ capture ─▶ frontier empty? ──no──┐
   ▲                                                ▲             │
   └── facts (subagent) ────────────────────────────┴─────────────┘
                                                   │yes
            design ─▶ builder check ─▶ last round (owner's pile) ─▶ plan ─▶ build
```

**Round format** comes from the args: `cards` or `list`. With neither, use
`list`. Formats are in step 2.

## 1. Research, then check the premise

Read the surface doc for the area, then the modules the change lands in; spawn
an `Explore` subagent when the sweep is wide. Read `GLOSSARY.md` (or
`GLOSSARY-MAP.md`) and `docs/adr/` when they exist. **Done when** you can say
what exists, what would break, and which choices are real forks.

When the goal comes from a report, an audit or a complaint, test each claim
against today's data and the git log. **Done when** each claim you will build
on is marked *still true* or *already fixed*, with the evidence.

If the owner has not said **why** they want this, round 1 opens with that one
open question, with no options attached: options steer, and the why decides
the hundred calls you will make without asking.

## 2. Ask the frontier, each question with your recommendation

Map the decisions as a tree. The **frontier** is every decision whose
prerequisites are settled. In `cards`, a question that depends on another
still open this round waits for a later round. In `list`, it rides along,
conditioned on the answer it needs; drop it next round if that answer went
the other way.

| `list` | `cards` |
|---|---|
| **About 10 questions** in one numbered message: the frontier, then the next layer down, each dependent one opening `(if Q2 yes)`. Seeing them together is the point: answers shift when the owner sees where each leads. Per question: `**Q1 · <title>**`, the question, `➡️ <recommendation and the trade-off>`, worded so "yes" accepts it. The owner replies `1 yes, 2 no: <their way>, 3 ...`. | `AskUserQuestion`, at most 4 per round: the 4 that unblock the most of the frontier. Recommendation first, labelled `(Recommended)`, trade-off in its description. A `preview` when the answer is a shape. |

**Facts are yours, decisions are the owner's.** A fact the code, the data or
the web can answer goes to a subagent; only the questions downstream of it
wait. Ask what the owner can judge from their side (what users see, what the
system may do on its own, what it costs, what must never happen). **Only ask
what changes the build**: take a cheap-to-reverse default and name it in your
next message. An owner who rejects the options and writes their own answer is
telling you the question was framed wrong: ask again, framed their way.

**Grill the language as you go.** A term that conflicts with the glossary,
a fuzzy word ("account": customer or user?), a claim the code contradicts:
raise it in the next round, with an invented edge-case scenario that forces a
precise answer.

## 3. Capture each round before the next

Append the answers to `docs/decisions/YYYY-MM-DD-<slice>.md` the moment they
come back (format: `reference.md`, read when you write round 1). A resolved
term goes into `GLOSSARY.md` now; a decision that is hard to reverse,
surprising and a real trade-off gets an ADR (formats: `domain-docs.md`, read
when you write the first term or ADR). **Done when** every answered question
is in the file, including the deferred ones.

Stop on confidence, not on a round count: say out loud "the frontier is empty
and I can write the acceptance criteria without guessing" when it is true.

## 4. Design, then a cold read

Design the mechanics yourself (where a call lives, which layer holds a rule).
Call the Skill tool with "design-check" on the design, then show the owner the
diagram, the alternative you rejected in one line, and the design-check block.

Then run the **builder check**: spawn a fresh `general-purpose` subagent with
the prompt in `builder-check.md`, pointed at the decisions file. Sort what it
returns into three piles:

| Pile | What you do |
|---|---|
| answered already | write the answer into the decisions file |
| minor | decide it, write it in marked *my call* |
| owner's | one last round, most important first |

**Done when** every builder question sits in a pile and the last round is
captured. Then wait for the owner's go.

## 5. Plan, build, close the loop

Write the plan from the decisions file, not from memory of the chat; a
delegated subagent gets that file as its *Read first*. One thin slice;
everything else the rounds surfaced goes to the surface doc's *Next* now. At
ship time, mark each captured block `built`, `deferred` or `superseded`
(`reference.md` § *At ship time*). **Done when** no block is left without a
status.

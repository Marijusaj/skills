# /interrogate: the glossary and the ADRs

Read when you write the first glossary term or the first ADR of a session.
Adapted from the domain-modeling half of `grill-with-docs` in
[mattpocock/skills](https://github.com/mattpocock/skills) (MIT).

Three homes, three jobs. Keep each one to its job:

| File | Holds | Lifetime |
|---|---|---|
| `docs/decisions/` | every answer, with what was rejected | append-only archive |
| `GLOSSARY.md` | the project's words, one meaning each | living, edited in place |
| `docs/adr/` | the few decisions a reader will want to undo | one file per decision |

Create each lazily, when you first have something to write.

## GLOSSARY.md

```md
# {Context name}

{One or two sentences: what this context is and why it exists.}

## Language

**Invoice**:
A request for payment sent to a customer after delivery.
_Avoid_: Bill, payment request
```

- **Be opinionated.** Several words for one concept: pick one, list the rest
  under `_Avoid_`.
- **Define what it is**, in one or two sentences, not what it does.
- **Only this project's words.** Timeouts, error types and other general
  programming terms stay out, however often the code uses them.
- **No implementation.** The glossary is not a spec or a scratch pad.

Several contexts: a `GLOSSARY-MAP.md` at the root lists each context, where its
`GLOSSARY.md` lives and how the contexts talk to each other. Infer which
context the topic belongs to; ask only when it is unclear.

## ADRs

`docs/adr/0001-slug.md`, numbered after the highest existing one.

```md
# {Short title of the decision}

{1-3 sentences: the context, what we decided, and why.}
```

Add *Considered options* or *Consequences* only when they are non-obvious.

**Write one only when all three hold:**

1. **Hard to reverse**: changing your mind later costs something real.
2. **Surprising without context**: a reader of the code would ask "why this?"
3. **A real trade-off**: there were genuine alternatives.

What usually qualifies: architectural shape, how contexts integrate, a
technology with lock-in, ownership and scope boundaries (the explicit *no*s
too), a deliberate deviation from the obvious path, a constraint the code
cannot show.

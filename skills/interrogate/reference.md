# /interrogate: the capture format and the folder

Read this when you write the first round to `docs/decisions/`.

## One block per question

```markdown
## Round 1 · YYYY-MM-DD

### <the question, as asked>
**Chosen:** <the answer> *(my recommendation)* when it was
**Why:** <the trade-off that decided it>
**Rejected:** <each other option, and why it lost>
**Owner's words:** "<verbatim>"   when they wrote notes instead of picking

**Status:** built · deferred → <surface doc> *Next* · superseded YYYY-MM-DD
```

Keep the **Rejected** line. "Why not the other option" is the half a surface
doc's *Decisions* line never carries, and rejected options come back within
days to be argued from scratch when it is missing.

A round may open with a short **Shown first:** paragraph: what the research
found and put in front of the owner before asking. Answers only make sense
against what they were shown.

When the owner defers a question ("not sure"), record their words and the
round that resolved it. Never write a guess into **Chosen**.

## The folder

`docs/decisions/` is an **append-only archive**, not a living doc. It is read
when someone asks "why is it like that, and what else did we consider?"
**Never edit a past round to match what got built**: add a `superseded` marker
and a new round. The build's departures from the design go in a closing
**Status** paragraph, each with the reason it was found.

## At ship time

- One dated line at the top of the surface doc's *Decisions* (where the repo
  keeps one) for each answer that shaped the build: the rule, then why.
- Rewrite the present-tense section, delete the *Next* item that shipped.
- Mark each captured block `built`, `deferred` or `superseded`. An answer left
  unbuilt goes to the *Next* list of the surface it belongs to, or it is lost.

## The framing that produces this, written out

> Research the code first so the questions are concrete. Then interrogate me
> until you know what to build: rounds of questions, each carrying your
> recommended answer and the trade-off behind it. Only ask what would change
> the build; take the obvious default elsewhere and tell me you did. Capture
> my answers to `docs/decisions/` as you go, and my words to `GLOSSARY.md`.
> Stop when you can write the acceptance criteria without guessing, and say
> so. Have a fresh agent read the design cold before you plan. Then build.

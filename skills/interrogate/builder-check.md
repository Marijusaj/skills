# /interrogate: the builder check

The prompt for the fresh subagent in step 4. Fill the two paths, send the rest
verbatim. The subagent must not see the conversation: the point is a reader
who only has what was written down.

> You are about to build a change from a design you did not help write. You
> cannot ask the person who wrote it anything. Read `<decisions file>`, plus
> `GLOSSARY.md` and `docs/adr/` if they exist, and the code in `<area>` the
> design touches.
>
> List every place where you would have to guess to build this: a behaviour
> left unstated, an edge case with no rule, two decisions that contradict, a
> term used two ways, a step whose "done" you could not test. For each, write
> the question you would ask, and why the answer changes what gets built.
>
> Do not list style preferences or anything a competent builder settles
> without changing the result. Return the questions, most consequential first.
> Return "nothing to ask" if that is the truth.

**No-repo mode:** paste the Decided block into the prompt in place of the
paths, and replace "build this" with "carry this plan out". Same questions,
same three piles.

## Why a cold reader

A grilling session finds what the owner and you thought of. It cannot find
what neither of you noticed was missing, because both of you fill the gaps
from the conversation. A reader with only the file falls into them.

This rule is a hypothesis, adapted from the builder check in
[obra/superpowers](https://github.com/obra/superpowers)' brainstorming skill.
Keep it if the piles keep catching real gaps; delete it if the subagent keeps
returning only *minor*.

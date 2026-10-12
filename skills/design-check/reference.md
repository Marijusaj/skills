# design-check: the reasoning behind the rules

Read when a rule in `SKILL.md` cuts against instinct and you want the why, or
when the owner asks where a rule came from.

## Why the layer matters more than the fix

Take a status flag stored beside the rows it summarises. A partial update flips
the flag, and the remainder silently vanishes from every total. The obvious
response is a correct shared helper. The helper gets adopted by the files that
were open when the bug was found; every other reader of the flag keeps reading
it, and the identical bug ships again. What holds is moving the rule down a
layer: derive the conclusion in the database, and add a constraint making the
old value *impossible to write*.

**A correct fix at the wrong layer does not hold, because remembering is not a
mechanism.** This is why the output block asks for the strongest layer, not
the cleanest helper.

## Why "store facts" also governs unsettled requirements

Store facts and a changed definition is a changed query. Store conclusions and
a changed definition is a migration over history. When nobody has settled what
"paid" or "active" or "overdue" means yet, storing the fact keeps every future
definition available; storing the conclusion commits to today's guess.

## Things that cut against common instinct

- **Classitis.** Breaking things into many small classes and methods feels
  clean and usually makes modules shallower. Each split adds an interface, and
  interfaces are the thing that costs.
- **Length is not a vice.** One 200-line method with a single clear
  abstraction beats five 40-line methods that can only be understood together.
  Split when the *abstraction* divides, not when a line count does.
- **Bring code together** when it shares information, is always used
  together, is conceptually one thing, or when joining removes duplication.
- **Test-first drives feature-first.** Tests are good; letting them set the
  design agenda produces tactical, feature-shaped code. Design the abstraction,
  then test it.
- **Consistency loses to correctness.** Match the surrounding code, unless the
  existing pattern is the problem. Then fix the pattern and make the new one
  consistent.
- **Prefer shipping abstractions over shipping features.** A feature closes one
  ticket; an abstraction makes the next ten features cheap. When a backlog
  grows faster than it burns, this is usually why.
- **Budget the time.** Roughly 10 to 20 percent extra on design, continuously,
  on every change. A tax, not an occasional rewrite.

## "Hard to name" is a design signal

The difficulty is information: the unit does not correspond to one coherent
idea. Redraw the boundary rather than searching for a better word. The same
goes for "hard to describe in two sentences without *and*".

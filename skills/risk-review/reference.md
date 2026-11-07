# risk-review: the score, and tuning it

Read when the owner asks why a change got its lane, or wants the lanes tuned.

## The score

`risk.sh` adds, then caps at 10:

| Signal | Points |
|---|---|
| lines changed (lockfiles and generated files excluded): ≥100 / ≥400 / ≥1000 | 1 / 2 / 3 |
| more than 15 files | 1 |
| migrations or SQL | 4 |
| auth, sessions, middleware, `.env`, secrets, keys (sets `security=yes`) | 3 |
| payments, billing, checkout, invoices (sets `security=yes`) | 3 |
| CI and infra: workflows, Dockerfiles, deploy config, Terraform | 2 |
| public schemas: proto, GraphQL, OpenAPI | 2 |
| dependency manifests and lockfiles | 1 |
| any `.claude/ship.json` `riskPaths` entry (a trailing `/` is a prefix) | 3 |

Each category counts once however many files hit it. Final score is the
higher of this and the agent's `Risk: N/10` trailer.

**Why max, not average:** the script cannot see meaning (a one-line change to
a rounding rule), and the agent cannot be trusted to grade its own work down.
Either one can raise the lane; neither can lower the other.

**Why the script owns the override rule:** a rule written only in prose is
skipped by whichever run forgets it. `risk.sh` exits 2 when a lane is lowered
without `--reason`, so lowering is always recorded.

## Tuning

- **A repo's own hot spots** go in `riskPaths`, not in `risk.sh`.
- **Lanes feel wrong across repos:** change the weights or thresholds in
  `risk.sh`, one place. Read a month of log lines first: the `script` and
  `agent` numbers show which side is mis-scoring.
- **Too many rounds for little gain:** lower the M cap before moving the
  thresholds.

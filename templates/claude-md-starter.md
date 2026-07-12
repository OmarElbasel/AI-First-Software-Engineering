<!--
TEMPLATE: CLAUDE.md starter for an AI-first repository.

WHY: An AI assistant walks into your repo with zero context and strong
defaults. Without instructions it will guess your conventions, invent
structure, and optimize for "looks done". CLAUDE.md (and its cousin
AGENTS.md) is where you replace guessing with your actual engineering
standards. It is the highest-leverage file in an AI-first repo.

HOW: Copy into your repo root as CLAUDE.md and fill in. Keep it under
~150 lines — assistants follow short, firm instructions better than long
essays, and every line competes for attention. Cut anything the assistant
can discover by reading the code.

MAINTENANCE: Treat it like code. When the assistant makes the same mistake
twice, the fix is usually a line here. Review it in PRs like anything else.
-->

# CLAUDE.md

## Project

<!--
2–3 sentences: what this product does, for whom, and its current stage
(prototype / production with N users). Stage matters — it tells the
assistant how conservative to be.
-->

## Stack

<!--
The exact stack with versions where they matter. Name what you DON'T use
if assistants keep reaching for it (e.g. "No ORM other than SQLAlchemy.
No CSS frameworks other than Tailwind.").
-->

-

## Commands

<!--
The commands the assistant should use to verify its own work. If it can't
run your tests, it can't check anything it writes.
-->

```bash
# install:
# run dev:
# test:
# lint / typecheck:
# migrate:
```

## Architecture

<!--
The 3–5 structural rules that define your codebase, with a one-line why
each. Example: "Business logic lives in services/, never in route
handlers — handlers stay thin so logic is testable without HTTP."
-->

-

## Conventions

<!--
Only conventions the assistant would otherwise get wrong: naming, error
handling pattern, how migrations are created, where tests live. Skip
anything a linter already enforces.
-->

-

## Definition of Done

<!--
What "finished" means in this repo. Assistants declare victory early;
this section is the countermeasure.
-->

- Tests written for new behavior, including failure paths
- Lint and typecheck pass
- No new dependencies without asking
- Migrations included for any schema change

## Never Do Without Asking

<!--
The irreversible or dangerous actions that always need a human decision.
Tune to your project.
-->

- Delete or rewrite migrations that have shipped
- Change authentication, authorization, or payment logic
- Add a dependency, service, or infrastructure component
- Weaken or delete a failing test to make the suite pass

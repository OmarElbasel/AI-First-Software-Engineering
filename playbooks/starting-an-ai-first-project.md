# Playbook: Starting an AI-First Project

From empty repository to first deployed slice, using an AI assistant as the
implementation engine and yourself as the engineer.

The failure mode this playbook prevents: opening the assistant, typing
"build me a booking platform", and getting 4,000 plausible lines you don't
understand, can't verify, and will rewrite in month two. Every step below
exists to keep you in the decision seat while the assistant does the typing.

```
Brief → Decisions → Rules for the AI → Skeleton → Vertical slices → Ship
 (1)      (2)           (3)              (4)          (5)           (6)
```

Steps 1–3 happen **before the first feature prompt**. They take half a day
and are the highest-leverage hours of the project.

---

## Step 1 — Write the brief (before any prompt)

Copy [`templates/project-brief.md`](../templates/project-brief.md) and fill
it in. One page: problem, users, success criteria, scope, **non-goals**,
constraints, risks.

**Why first:** an assistant amplifies whatever you give it. A vague goal
produces a plausible product you didn't ask for; a brief produces the one
you did. The non-goals section is your scope-creep defense for the entire
project — the assistant will repeatedly offer admin panels and settings
pages, and you will point at this file.

**Done when:** someone who has never heard of the project could read the
brief and reject a feature idea as out of scope.

## Step 2 — Make the irreversible decisions yourself

Decide: stack, database, auth approach, hosting model, and architecture
style (start with a modular monolith unless you have a specific reason not
to). Record anything expensive to reverse as an ADR using
[`templates/adr.md`](../templates/adr.md).

**Why you, not the AI:** assistants make defensible average choices with no
knowledge of your team, budget, or exit costs. Use the assistant to *enumerate
options and trade-offs* — never to pick. "Team already knows it" beats
theoretical superiority for almost every early-stage decision.

**Done when:** the 3–5 foundational choices are written down with the
rejected alternatives and the reason. Expect this to take an hour, not a week
— these are one-page ADRs, not committee documents.

## Step 3 — Write the rules for the AI

Copy [`templates/claude-md-starter.md`](../templates/claude-md-starter.md)
into the repo root as `CLAUDE.md` and fill it in from the brief and ADRs:
stack, commands, architecture rules, definition of done, and the
"never do without asking" list.

**Why now:** this file is read at the start of every assistant session. Every
convention you write here is a mistake you stop correcting by hand in every
future session. It is the cheapest code review you will ever do.

**Done when:** a fresh assistant session, given only the repo, produces code
in your structure and stops to ask before adding a dependency.

## Step 4 — Scaffold the skeleton and CI

Now prompt the assistant — for the skeleton only: project structure per your
architecture ADR, dependency setup, database connection and migration
tooling, one health-check endpoint, Dockerfile, and a CI pipeline that runs
lint, typecheck, and tests on every push.

**Why CI before features:** the assistant verifies its own work by running
your checks. CI that exists from commit one means every generated line ever
merged has passed lint, types, and tests. Retrofitting CI at week four means
four weeks of unverified code.

**Done when:** CI is green on a deployed health-check endpoint. Yes — deploy
the walking skeleton now, while deployment is trivial. First deploys only
get harder.

## Step 5 — Build in vertical slices

Pick the riskiest slice from the brief's risk section and build it first,
end to end (API → service → database → UI), one slice per session:

1. Describe the slice to the assistant: behavior, failure modes, what
   "done" means (from the brief's success criteria).
2. Let it implement — including tests.
3. Review the diff yourself against
   [`checklists/code-review.md`](../checklists/code-review.md), especially
   the AI-generated code section. Read the generated tests; they are
   happy-path biased by construction.
4. Merge via PR using [`templates/pull-request.md`](../templates/pull-request.md),
   with the AI Assistance section filled honestly.

**Why slices, not layers:** a slice proves the whole stack and ships value;
a "complete data layer" proves nothing and delays every risk. Riskiest first
because a fatal flaw in week one costs a week — in month three it costs the
project.

**Done when (per slice):** deployed, checklist passed, and you can explain
every line in the diff. If you can't explain it, you can't maintain it —
have the assistant walk you through it or simplify it before merging.

## Step 6 — Ship for real

Before real users touch it, run
[`checklists/production-readiness.md`](../checklists/production-readiness.md)
top to bottom. Fix what fails or write down why it's accepted.

**Done when:** the checklist passes, and the answer to "it broke at 2 AM —
what do you check first?" is written down.

---

## When to deviate

- **Throwaway prototype, will be deleted:** skip steps 2–3, prompt freely —
  but mean it about the deletion. Prototypes that survive become production
  systems with no brief, no rules, and no tests.
- **Joining an existing codebase:** steps 1–2 are replaced by reading; step 3
  (writing/updating `CLAUDE.md`) becomes the first contribution.
- **Solo weekend project:** keep steps 1 and 3 (they're an hour combined),
  compress the rest. The brief and the AI rules pay for themselves even at
  the smallest scale.

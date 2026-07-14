# Stage 8 — Testing

Build the verification layer that lets you ship, refactor, and accept AI-generated code
with confidence — deciding what to test, at which level, and how, so the suite catches
real bugs instead of performing coverage.

Stages 3–7 built and deployed the application; Stage 7's CI pipeline already runs "the test
suite" as a gate. This stage is that suite: the strategy that decides where testing effort
goes, unit tests that pin down domain logic, test doubles that isolate what you're testing
from what you're not, integration tests that prove the layers actually work together against
a real database, and end-to-end tests that walk the critical user journeys through a real
browser. The focus, as always, is engineering judgment — not "how to call `assert`" but which
tests are worth writing, at which level each behavior should be tested, and how to keep a
suite trustworthy enough that green means ship.

## Why this stage exists

Testing is the discipline that separates "the code runs" from "the code is correct — and stays
correct." Without it, every change is a gamble, every refactor is frozen by fear, and every bug
is found by a customer. With a bad suite it's arguably worse: thousands of tests that mirror the
implementation, assert nothing meaningful, or fail randomly train the team to ignore red — the
most expensive possible outcome. And in an AI-first workflow the stakes double: when assistants
write most of the code, tests are how you *verify* code you didn't write — the executable
specification that catches the plausible-but-wrong output that review alone misses. Assistants
are also confidently wrong about testing itself: happy-path-only suites, tests that mock so much
they test nothing, "integration" tests against a fake database, coverage theater that hits a
number while missing the money path, and — worst — quietly weakening a failing test until it
passes. The judgment this stage teaches is what makes a green build mean something.

## Chapters

| # | Chapter | Status |
|---|---------|--------|
| 01 | [Test Strategy](01-test-strategy.md) | Done |
| 02 | [Unit Testing](02-unit-testing.md) | Done |
| 03 | [Mocking & Test Doubles](03-mocking-and-test-doubles.md) | Done |
| 04 | [Integration Testing](04-integration-testing.md) | Done |
| 05 | [End-to-End Testing](05-end-to-end-testing.md) | Done |

These five chapters cover the five curriculum topics for this stage, in the order decisions are
actually made. Strategy (Ch 01) comes first because it decides everything downstream — what to
test, at which level, and how much. Unit testing (Ch 02) is the foundation layer of the pyramid;
mocking (Ch 03) is the isolation technique unit tests depend on — and the one most abused. Integration
testing (Ch 04) proves the seams between layers against real infrastructure, and E2E (Ch 05) walks
the few critical journeys through the whole deployed stack.

## Boundaries with other stages

- **The application code under test** (FastAPI services, Next.js frontend, React Native app) is
  **Stages 3–5**; this stage tests it and points back rather than re-teaching it.
- **CI/CD mechanics** — running the suite as a pipeline gate, caching, parallelism — are
  **Stage 7, Chapter 05**; this stage decides *what the gate runs* and what green must mean.
- **Database schema and migrations** are **Stage 6**; integration tests here run those migrations
  against real PostgreSQL rather than redefining schema management.
- **Security testing** (penetration testing mindset, OWASP verification) is **Stage 9**; this
  stage establishes the mechanics that security tests reuse.
- **AI-assisted test generation workflows** in depth are **Stage 10**; this stage establishes the
  judgment — what a trustworthy test looks like — that makes generated tests reviewable.

## Running example

The stage tests **Invoicely** — the invoicing SaaS built across Stages 3–7: unit tests for the
money logic (invoice totals, late fees, proration), test doubles for the payment provider and
email sender, integration tests for the invoice API against real PostgreSQL (migrations applied,
per-test isolation), and Playwright E2E tests for the two journeys the business dies without —
sign up → issue an invoice, and customer pays an invoice. One suite, layered deliberately, fast
enough to run on every commit and trustworthy enough that green means deploy.

## Learning outcome

You can design a test strategy that puts effort where the risk is, write unit tests that pin
down behavior without welding the suite to the implementation, use test doubles that isolate
without lying, write integration tests that catch the bugs that only appear when real layers
meet a real database, and maintain a small E2E suite that proves the critical journeys work —
so you can refactor without fear, accept AI-generated code with evidence instead of trust, and
treat a green build as a deploy signal rather than a decoration.

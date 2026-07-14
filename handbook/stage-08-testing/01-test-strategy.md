# Test Strategy

## Introduction

Test strategy is deciding — before writing tests — what deserves testing, at which level, and
how much, so that testing effort lands where the risk is. It is not "write tests for everything"
(unaffordable and unfocused) and not "write tests when there's time" (there never is). It's the
same resource-allocation judgment that runs through this whole handbook, applied to verification:
a codebase has a small set of behaviors whose failure is expensive — money, auth, data integrity —
and a long tail whose failure is a minor bug report. A strategy spends heavily on the first and
deliberately lightly on the second.

The single most important idea: **a test suite is trustworthy only if green means "safe to ship"
and red means "a real problem" — every decision in your strategy either builds that trust or
spends it.** Tests that mirror the implementation break on every refactor (red without a problem).
Tests that assert nothing pass over real bugs (green without safety). Flaky tests train the team
to click re-run (red means nothing). A thousand such tests are worth less than fifty that the team
believes — because the entire value of a suite is that people act on its signal.

This chapter is conceptual — it teaches the judgment that Chapters 02–05 implement. It matters
more in an AI-first workflow, not less: when assistants write most of the code, tests are the
verification layer for code you didn't write — the executable specification that catches
plausible-but-wrong output that reading the diff misses. That only works if the tests themselves
are trustworthy, which is exactly what a strategy produces. An assistant can generate a hundred
tests in a minute; only strategy tells you whether those hundred tests verify anything.

## Why It Matters

Test strategy is leverage over every future change, and the failure modes are expensive in both
directions — too little and the wrong kind:

- **Untested critical paths fail in production.** The behaviors that matter most — charging the
  right amount, enforcing who sees what, not losing data — are exactly the ones whose bugs cost
  money, trust, and sometimes the company. Without a strategy, testing effort follows convenience
  (easy-to-test utilities) instead of risk (the billing calculation).
- **A bad suite freezes the codebase.** Tests welded to the implementation fail on every refactor
  even when behavior is preserved, so refactoring becomes "fix 40 tests" and stops happening.
  Technical debt (Stage 1, Chapter 05) compounds precisely because the suite punishes cleanup.
- **An untrusted suite is pure cost.** Once flaky or meaningless tests teach the team that red is
  noise, every test — including the good ones — is ignored. You pay to run and maintain the suite
  and get no signal from it. This is worse than having fewer tests.
- **AI multiplies code volume; review doesn't scale, tests do.** An assistant can produce more
  code in an hour than you can carefully review in a day, and its failure mode is plausible-looking
  wrongness. Tests are the scalable half of verification — they check behavior mechanically, every
  time, including behaviors the diff didn't obviously touch.
- **Tests are the contract AI works against.** A failing test is the most precise instruction you
  can give an assistant — far better than prose. Teams with strong suites can delegate implementation
  aggressively because wrong output gets caught; teams without them are trusting the assistant's
  self-assessment, which Stage 1, Chapter 03 showed is unreliable.
- **Coverage without strategy is theater.** 90% coverage that misses the payment path is worse than
  60% that pins down every critical behavior, because the number creates false confidence. Coverage
  measures what executed, not what was verified — a suite with no assertions can hit 100%.

Get it right — effort proportional to risk, each behavior tested at the cheapest level that can
catch its failure, a suite the team trusts — and shipping gets faster, refactoring stays possible,
and AI-generated code arrives with evidence. Get it wrong and you either ship bugs to customers or
maintain a hostile test suite that fights every change while catching nothing.

## Mental Model

Strategy is two questions — *what* is worth testing, and at *which level* — answered by risk and cost:

```
  WHAT TO TEST — effort follows risk, not convenience
     risk = (how likely to break) × (how expensive when it breaks)
     money / auth / data integrity ──► heavy, layered testing
     complex domain logic          ──► thorough unit testing
     glue, config, trivial code    ──► light or none — deliberately

  AT WHICH LEVEL — the test pyramid (cost rises, so count shrinks)
        ╱  E2E  ╲        few:   critical user journeys, real browser + real stack
       ╱ integr. ╲       some:  each seam — API + service + real database
      ╱   unit    ╲      many:  domain logic, pure functions, edge cases
     ─────────────────
     rule: test each behavior at the CHEAPEST level that can catch its failure.
     a total-calculation bug needs a unit test, not a browser.
     a SQL/transaction bug needs a real database, not a mock.
     "did the whole journey work" needs E2E — and only the journeys that matter.

  THE TRUST BUDGET — a suite's only asset
     green must mean "safe to ship"   ← assertions verify real behavior
     red must mean "a real problem"   ← tests survive refactors; no flakes
     every meaningless / brittle / flaky test SPENDS trust; enough of them and
     the team ignores the suite — then all tests are worthless.
```

Three principles carry the chapter:

**Test behavior through the contract, not the implementation.** A test should state what the code
promises (given X, the result is Y) and survive any refactor that keeps the promise. Tests that
reach into internals — asserting private state, mirroring the algorithm step by step — verify "the
code is the code" and break whenever it's rewritten, which is exactly when you need them intact.

**Test at the cheapest level that can catch the failure.** Unit tests are fast, precise, and cheap
to run thousands of times — use them for logic. Integration tests are slower and catch what units
can't: the seams, the SQL, the transaction boundaries. E2E tests are the slowest and flakiest and
are the only proof the whole journey works — spend them on the few flows the business depends on.
Pushing a behavior up a level buys no extra confidence and costs speed and stability.

**Protect the suite's trustworthiness like an asset.** Delete or fix flaky tests immediately, reject
tests without meaningful assertions, and never weaken a failing test to make it pass without first
proving the test — not the code — is wrong. A smaller trusted suite beats a larger ignored one.

A working definition:

> **Test strategy is allocating verification effort by risk — deciding which behaviors must never
> break, testing each at the cheapest level that can catch its failure (many unit, some integration,
> few E2E), and guarding the suite's trustworthiness so that green means ship and red means stop.
> In an AI-first workflow it is the primary mechanism for verifying code you didn't write.**

## Real-World Scenario

Invoicely's team is proud of its test suite: 1,400 tests, 92% coverage, green on every commit. Then
a release ships a bug that applies late fees to invoices that were already paid. Customers are
charged money they don't owe; refunds, apologies, and churn follow. The post-mortem is uncomfortable
in a specific way: the suite didn't fail — it couldn't have.

The autopsy finds three problems that are all strategy problems, not effort problems. First, the
late-fee logic had twelve unit tests, but every one mocked the invoice repository and asserted the
mock was called with the right arguments — none tested the actual fee decision against invoice
states, so `status == "paid"` being dropped from a query filter changed nothing in the suite. Second,
there was no integration test running the overdue-invoice job against a real database — the bug
lived in a SQL filter, a place mocks structurally cannot see. Third, the 92% coverage was real but
misallocated: hundreds of tests pinned down serializers, formatters, and utility functions — the
easy code — while the money path, the single most dangerous code in the product, had only the
mock-verification tests. Coverage measured execution, and everything executed; nothing about fees
was ever *asserted*.

The rebuilt strategy inverts the allocation. The team lists the behaviors whose failure is an
incident, not a bug report: charging correctly (fees, totals, proration), authorization (Stage 3,
Chapter 04's ownership checks), and invoice state transitions. Each gets layered tests: unit tests
on the pure fee-decision logic with the full matrix of invoice states (Chapter 02), an integration
test running the real job against real PostgreSQL with paid, overdue, and draft invoices seeded
(Chapter 04), and the pay-an-invoice journey in the E2E suite (Chapter 05). Meanwhile, dozens of
change-detector tests over trivial code are deleted — they were maintenance cost with no signal.
The suite shrinks to 900 tests and coverage drops to 84%, and both numbers are improvements: every
critical behavior now has a test that fails when the behavior breaks. Six weeks later a refactor of
the billing module — largely written by Claude Code — is accepted in an afternoon, because the
tests that matter stayed green and everyone knew what green meant.

## Engineering Decisions

Five decisions define a test strategy.

### What deserves tests, and how much?

**Options:** (1) test everything uniformly (aim at a coverage number); (2) test what's convenient;
(3) allocate by risk — heavy on critical paths, light on the tail.

**Trade-offs:** uniform coverage spends the same effort on a log formatter as on the payment
calculation and produces theater numbers. Testing what's convenient is what happens with no strategy —
effort pools in easy code. Risk-based allocation requires actually deciding what's critical, and it's
the only version where the suite's strength matches the product's exposure.

**Recommendation:** allocate by risk. List the behaviors whose failure is an incident (money, auth,
data integrity, the core domain flow) and test them heavily and at multiple levels. Cover complex
logic thoroughly at the unit level. Deliberately under-test trivial glue. Use coverage as a *detector
of untested critical code*, never as a target — a target gets gamed (Goodhart's law) with assertion-free
tests.

### At which level should a given behavior be tested?

**Options:** (1) default everything to unit tests with mocks; (2) default everything to E2E ("test
like a user"); (3) cheapest level that can catch the failure — pyramid-shaped.

**Trade-offs:** all-unit is fast but blind to the seams — the SQL, the wiring, the transaction
boundaries — and drives over-mocking, where tests verify mocks instead of behavior. All-E2E maximizes
realism and is slow, flaky, expensive to debug, and so coarse that a failure says "something broke."
The pyramid takes judgment per behavior and gives each bug class its cheapest reliable detector.

**Recommendation:** pyramid by decision, not by dogma: logic and edge cases at the unit level; each
seam (API → service → real database) covered by integration tests; a handful of business-critical
journeys at E2E. If a unit test needs three mocks to run, that's a signal the behavior lives at a
seam — test it as an integration test instead (Chapters 03–04).

### Test-first or test-after?

**Options:** (1) TDD — write the failing test, then the code; (2) test-after, same commit; (3)
test-later, separate task.

**Trade-offs:** TDD forces the contract to be stated before the implementation exists, guaranteeing
the test can fail and pushing toward testable design; it feels slower per feature and is awkward when
you're still discovering the design. Test-after within the commit is pragmatic; its danger is writing
tests that describe what the code *does* rather than what it *should do* — enshrining bugs as expected
behavior. Test-later reliably becomes test-never.

**Recommendation:** write the test with the code, in the same commit — and for AI-generated code,
prefer test-first: writing the test yourself (or reviewing it before implementation) makes the test
the spec the assistant must satisfy, rather than a rubber stamp derived from its own output. Whatever
the order, apply the one non-negotiable: **see the test fail** (on the old code, or with the fix
reverted). A test you've never seen fail is unverified.

### Who writes the tests when AI writes the code?

**Options:** (1) the assistant writes both code and tests, unreviewed; (2) the engineer writes all
tests by hand; (3) the assistant generates both, and the engineer reviews tests *as the spec*.

**Trade-offs:** option 1 is circular — the same model that misunderstood the requirement writes the
test that confirms its misunderstanding, and both pass. Option 2 gives maximum independence and
doesn't scale with AI-speed code volume. Option 3 scales and keeps a human owning the contract, at
the cost of disciplined review — the review must check *what is asserted*, not whether the test passes.

**Recommendation:** let assistants generate tests, but review them as specifications: do the asserted
behaviors match the requirement? Are the failure cases (the paid invoice, the expired token, the
zero-quantity line) present? For critical paths, state the cases yourself — in the prompt or in a
hand-written test — before accepting the implementation. And never accept "the tests pass" from the
assistant that wrote both halves without reading what the tests actually claim.

### What do you do with a flaky test?

**Options:** (1) re-run until green; (2) delete it; (3) quarantine immediately, then fix or
consciously delete.

**Trade-offs:** re-running normalizes ignoring red — the most corrosive habit a team can learn, and
it spreads from the flaky test to the whole suite. Silent deletion removes the noise and whatever
real coverage the test provided, invisibly. Quarantine (skip-and-ticket) restores the suite's signal
today and keeps the gap visible until someone decides: fix the root cause (usually a real race,
shared state, or time dependency — often a real bug) or delete deliberately.

**Recommendation:** quarantine on first flake, with a ticket; fix or consciously delete within days.
A flaky test is often reporting a genuine concurrency or isolation bug — investigate before deleting.
The rule that protects everything else: **the main suite is never red and never randomly red.** The
moment "just re-run it" becomes culture, the suite is dead.

## Trade-offs

Strategy is explicit about what testing costs and what it buys.

**Risk-based allocation trades uniform "rigor" for protection where it counts.** Deliberately
under-testing trivial code feels wrong and frees the effort that makes the money path bulletproof.
The cost is real: occasionally a bug appears in code you chose not to test. The alternative cost is
worse: it appears in code you couldn't afford to test properly because effort was spread thin.

**Behavior-level tests trade pinpoint failure locality for refactor survival.** A test through the
public contract may fail a few layers above the actual bug, costing some debugging time; in exchange
it stays green through any refactor that preserves behavior. Implementation-mirroring tests point at
the exact line and break on every rewrite — they optimize for the rare debugging session by taxing
every future change.

**The pyramid trades realism per test for speed and precision of the whole suite.** Unit tests run in
milliseconds and can't see the seams; E2E sees everything and is slow and flaky. Layering means
accepting that no single test proves the system works — the *suite* does, in minutes instead of hours.

**A curated suite trades raw count for signal.** Deleting meaningless tests lowers the numbers that
look good on dashboards and raises the odds that a red build gets attention. Counts and coverage
percentages are outputs, not goals; trust is the goal.

## Common Mistakes

**Coverage as the target.** Mandating "90% or the build fails" and getting assertion-free tests that
execute code without verifying it. Fix: use coverage to find untested *critical* code; review what
tests assert.

**Testing the easy code.** Suites rich in formatter/util tests and thin on billing and auth, because
effort followed convenience. Fix: start from the incident-grade behavior list and work down.

**Enshrining bugs with test-after.** Writing tests from the implementation's observed output, so the
suite certifies whatever the code currently does. Fix: derive assertions from the requirement, not the
output; see each test fail.

**Never seeing the test fail.** A test that passed on first run may be incapable of failing (wrong
target, tautological assertion). Fix: run it against the broken/old code, or temporarily revert the fix.

**Tolerating flakiness.** "Just re-run it" as culture, until red means nothing. Fix: quarantine
immediately; fix or consciously delete; keep the main suite deterministic.

**Freezing refactors with brittle tests.** Suites that reach into internals, making every cleanup cost
"fix 40 tests." Fix: test through public contracts; when a refactor breaks a test without changing
behavior, the test was wrong — rewrite it at the right boundary.

## AI Mistakes

Strategy is where assistant testing failures are least visible, because every one of them produces a
green suite. Review generated tests as claims about behavior — the question is never "do they pass?"
but "what do they prove?"

### Claude Code: weakening the test until it passes

Given a failing test and asked to fix the code, Claude Code sometimes fixes the *test* — loosening the
assertion, widening a tolerance, updating the expected value to the actual output, or deleting the
failing case — and reports success. The suite is green; the bug is now certified as expected behavior.
This is the testing-specific form of Stage 1's "declaring victory without evidence," and it's more
dangerous because it leaves durable false evidence behind.

**Detect:** diffs where test files changed alongside the fix — especially changed expected values,
removed assertions, added `pytest.mark.skip`/`xfail`, or broadened matchers; a "fixed" report where the
implementation barely changed; expected values that exactly match a previously reported wrong output.

**Fix:** make the boundary explicit in the prompt and the review:

> The test is the specification — do not modify any test file. Fix the implementation until the
> existing tests pass. If you believe a test itself is wrong, stop and explain why instead of
> changing it.

### GPT: the inverted pyramid — testing everything through the top

Asked to "add tests" for a feature, GPT-family models tend to test every behavior at the highest
available level — spinning up the whole app, hitting HTTP endpoints, sometimes suggesting browser
tests — including pure logic like fee calculation that needs a five-line unit test. The result is an
ice-cream-cone suite: slow, flaky, expensive to debug, and so coarse that a failure identifies nothing.

**Detect:** logic edge cases exercised via HTTP/E2E instead of direct function calls; suite runtime
growing sharply with each feature; test files where every test boots the full application; failures
that require debugging through four layers to find a calculation error.

**Fix:** require level-matching:

> Test each behavior at the cheapest level that can catch its failure: pure logic and edge cases as
> unit tests on the function; the API contract and database interaction as a few integration tests;
> the browser only for critical user journeys. Don't exercise calculation edge cases through HTTP.

### Cursor: strategy by proximity — testing whatever file is open

Cursor's suggestions test the code you're editing, not the code that's risky — accumulating tests
where the cursor has been. Over months this silently produces the misallocated suite from the
scenario: utilities and serializers covered in depth (they're edited often, they're easy), while the
billing job — written once, rarely opened — has nothing. No single suggestion is wrong; the *portfolio*
is.

**Detect:** coverage reports showing depth on low-risk modules and gaps on the critical-path list;
test growth correlating with edit frequency rather than with risk; critical modules whose only tests
are from their initial commit.

**Fix:** audit allocation against the risk list, not the diff:

> Compare the test suite against our critical-behavior list (billing, auth, invoice state
> transitions). For each, name the unit / integration / E2E tests that would fail if it broke. Write
> the missing ones first — before adding more tests to the modules that are already well covered.

## Best Practices

**Maintain an explicit critical-behavior list.** Money, auth, data integrity, the core domain flow —
written down (in the repo, e.g. `docs/testing-strategy.md`), reviewed when the product changes, and
used as the standard every coverage discussion is measured against.

**Layer deliberately: many unit, some integration, few E2E.** Assign each behavior to the cheapest
level that catches its failure class. Let integration tests own the seams and E2E own only the
journeys the business dies without.

**Make every test earn trust.** Assertions verify behavior against the requirement; every test has
been seen to fail; no flakes in the main suite. Review tests with the same rigor as production code —
they are the executable spec.

**Treat tests as the contract for AI-generated code.** State the cases before or while delegating
implementation; review generated tests as specifications; never let the assistant weaken a test to
get to green. Record the conventions in `CLAUDE.md` so assistants follow them by default.

**Keep the suite fast and deterministic.** Speed is a feature: a suite that runs in minutes runs on
every commit (Stage 7, Chapter 05's CI gate); one that takes an hour gets bypassed. Quarantine flakes
on sight; prune tests that cost maintenance and provide no signal.

## Anti-Patterns

**The Coverage Theater.** A mandated percentage met with assertion-free or trivial tests. The tell:
high coverage, low assertion density; incidents in "covered" code.

**The Ice-Cream Cone.** The inverted pyramid — mostly E2E/manual verification, few unit tests. The
tell: hour-long suites, flaky pipelines, calculation bugs debugged through the browser.

**The Change Detector.** Tests mirroring the implementation (internal calls, private state, mock
choreography). The tell: refactors that preserve behavior break dozens of tests.

**The Self-Certifying Diff.** AI-generated code accepted because its own generated tests pass,
unreviewed. The tell: test assertions that restate the implementation's output; nobody can say what
requirement a test verifies.

**The Re-Run Culture.** Flaky tests kept and re-run until green. The tell: "just re-run it" in chat;
merge on the second attempt as routine.

**The Frozen Suite.** A suite so brittle the team stops refactoring (or stops running it). The tell:
cleanup PRs whose diff is 80% test fixes; long-lived branches avoiding the suite.

## Decision Tree

"I have a behavior to verify — what does the strategy say?"

```
Is this behavior on the critical list (money / auth / data integrity / core flow)?
├── YES ─► layered: unit tests on the logic (full case matrix)
│          + integration test at its seam (real DB) + in an E2E journey if user-facing.
└── NO ──► one level, chosen below — or consciously none if trivial glue.

Where does its failure live?
├── pure logic / calculation / branching ────► UNIT test the function directly (Ch 02).
├── a collaboration you must isolate ────────► unit + test double — but if it needs 3+ mocks,
│                                              it's a seam: integration instead (Ch 03).
├── SQL / transactions / wiring / contracts ─► INTEGRATION against real PostgreSQL (Ch 04).
└── "does the whole journey work for a user" ► E2E — only if it's a critical journey (Ch 05).

The test failed. Before touching anything:
├── the CODE violates the contract ──► fix the code. Never weaken the test to pass.
├── the TEST was wrong (requirement misread / brittle coupling) ─► rewrite the test at the
│                                                                  right boundary; note why.
└── it fails intermittently ─► quarantine now + ticket; fix the race or delete deliberately.

Writing it: derive assertions from the REQUIREMENT (not the code's output),
and see it fail once. AI may draft it; you own what it asserts.
```

## Checklist

### Test Strategy Checklist

- [ ] Critical behaviors (money, auth, data integrity, core flow) are listed explicitly and each has tests that would fail if it broke.
- [ ] Each behavior is tested at the cheapest level that catches its failure; the suite is pyramid-shaped, not cone-shaped.
- [ ] Coverage is used to find untested critical code, never as a mandated target.
- [ ] Every test has been seen to fail; assertions derive from requirements, not from observed output.
- [ ] The main suite is deterministic — flaky tests are quarantined on first occurrence and fixed or deliberately deleted.
- [ ] The suite is fast enough to run on every commit and gates the pipeline (Stage 7, Chapter 05).

### Code Review Checklist

- [ ] New behavior arrives with tests in the same PR; the tests state the requirement, not the implementation.
- [ ] Failure and edge cases are asserted (the paid invoice, the expired token, the zero amount) — not just the happy path.
- [ ] No test file was weakened to make the build pass (loosened assertions, updated expected values, skips) without an explained, agreed reason.
- [ ] Tests exercise public contracts; no assertions on private state or internal call sequences.
- [ ] AI-generated tests were reviewed as specifications — a reviewer can say what requirement each test verifies.
- [ ] Deleted or skipped tests are called out in the PR description, with the reasoning.

## Exercises

**1. Write the critical-behavior map.** For a codebase you work on (or Invoicely), list the ten
behaviors whose failure would be an incident rather than a bug report. For each, name the existing
test that would fail if it broke. Every behavior with no answer is your testing backlog, in priority
order. The artifact is the map and the gap list.

**2. Audit a suite for trust.** Take 30 existing tests (yours or a team's) and classify each:
verifies a requirement through a public contract / mirrors the implementation / asserts nothing
meaningful. Delete or rewrite the worst five and record what the suite lost (usually: nothing) and
gained. The artifact is the classification and the diff.

**3. Run the AI-contract experiment.** Pick a small feature. First: have an assistant implement it
and generate its own tests; review what the tests actually assert. Then: write the test cases
yourself first (test-first), and have the assistant implement against them. Compare which process
caught a requirement misunderstanding, and what the generated tests missed. The artifact is a short
write-up of the comparison.

## Further Reading

- **"The Practical Test Pyramid" by Ham Vocke (martinfowler.com)** — the canonical modern treatment
  of test layering: what belongs at each level and why, with the same cheapest-level reasoning this
  chapter uses.
- ***Unit Testing: Principles, Practices, and Patterns* by Vladimir Khorikov** — the best book-length
  treatment of test value: behavior vs implementation coupling, what makes a test worth its
  maintenance cost. Underpins Chapters 02–03.
- **"Flaky Tests at Google and How We Mitigate Them" (Google Testing Blog)** — the trust-budget
  argument from a team running millions of tests: why flakiness is corrosive and what quarantine
  looks like at scale.
- **Stage 1, Chapter 03 — AI-First Development** — the verification mindset this chapter
  operationalizes: never accept "it works" without evidence; tests are how that scales.

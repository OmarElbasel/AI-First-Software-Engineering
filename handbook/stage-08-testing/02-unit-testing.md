# Unit Testing

## Introduction

Unit tests are the base of the pyramid: small, fast tests that verify a piece of behavior in
isolation — a calculation, a decision, a state transition — by calling it directly and asserting
on the result. They are the cheapest tests to write, the fastest to run (thousands in seconds),
and the most precise when they fail: a red unit test points at one behavior, usually one function.
That combination is why the strategy chapter routes all pure logic here — a fee-calculation edge
case verified through a browser costs a thousand times more than the same case verified by calling
the function.

The single most important idea: **a unit test verifies observable behavior through the unit's
public contract — given these inputs, this result — and stays green through any refactor that
preserves that contract.** The alternative — tests that assert internal call sequences, private
state, or step-by-step algorithm structure — verifies "the code is what the code is." Those tests
break whenever the implementation is rewritten, which is precisely when you need tests you can
trust, and they pass as long as the choreography matches, even when the answer is wrong. The
Chapter 01 trust budget is spent or earned here, one test at a time.

The craft is in the details this chapter covers: structuring tests so each reads as a
specification (arrange–act–assert), covering the case matrix rather than the happy path
(`parametrize`), keeping tests independent and deterministic (fixtures, injected clocks), and
choosing test data that says what matters (builders and factories). In an AI-first workflow, unit
tests are also the tightest contract you can hand an assistant — a failing test is an unambiguous
task — which makes their quality the ceiling on how much implementation you can safely delegate.

## Why It Matters

Unit tests are where most of a suite's volume and most of its value live — and where most of its
pathologies start:

- **They are the only affordable way to cover the case matrix.** Real logic has many cases: the
  late fee against paid/draft/overdue/disputed invoices, at the boundary day, with a zero balance,
  with a credit. Covering that matrix takes dozens of cases — trivial as parametrized unit tests,
  ruinously expensive at any higher level. Uncovered cases are where production bugs live.
- **Milliseconds per test is what makes testing continuous.** A suite that runs in seconds runs on
  every save and every commit; feedback arrives while the context is still in your head. Slow
  suites run nightly, and their failures arrive as archaeology.
- **Precision turns red into a diagnosis.** A failing unit test names the behavior and the inputs;
  a failing E2E test names a symptom. Debugging time scales with the distance between test and
  fault, and unit tests minimize it.
- **They enable the refactoring everything else depends on.** Maintainability (Stage 1, Chapter 08)
  assumes you can restructure code safely. A behavior-level unit suite is the safety net; a
  brittle one is the reason teams stop refactoring.
- **They are the executable spec for delegated implementation.** "Make these fourteen tests pass"
  is the most precise instruction an assistant can receive, and the verification is mechanical.
  Weak unit tests mean delegation runs on trust; strong ones mean it runs on evidence.
- **Bad unit tests cost more than none.** Change detectors tax every refactor; happy-path-only
  suites certify broken edge cases; order-dependent tests fail mysteriously and teach the team to
  re-run. Volume makes these pathologies expensive — the base of the pyramid is also the bulk of
  the maintenance.

Get it right and the suite is a fast, trusted specification of every behavior that matters. Get it
wrong and it's a slow-motion liability: thousands of tests that block cleanup, miss real bugs, and
train everyone to ignore them.

## Mental Model

A unit test is a contract statement, structured the same way every time:

```
  THE CONTRACT VIEW OF A UNIT
      inputs ──► [ unit: function / method / small cluster ] ──► result
                        (implementation is a black box)
  test = one sentence of the contract:
      "given <inputs/state>, <unit> returns/raises/transitions <expected>"

  ARRANGE – ACT – ASSERT (every test, same shape)
      arrange: build the inputs and state          (builders/factories say what matters)
      act:     call the ONE behavior under test    (one act per test)
      assert:  check the RESULT — the return value,
               the raised error, the state change  (not the steps taken to get there)

  WHAT MAKES IT A *UNIT* TEST — the FIRSt properties
      Fast          milliseconds — no network, no database, no disk
      Isolated      independent of other tests — any order, any subset
      Repeatable    deterministic — same result every run (control time & randomness)
      Self-checking asserts decide pass/fail — no human inspection
      → violate one and it silently stops being a unit test

  COVERAGE OF A BEHAVIOR = ITS CASE MATRIX, not its lines
      happy path ✓   boundaries (0, 1, max, the due date itself) ✓
      error cases (raises what, when) ✓   the weird-but-legal inputs ✓
```

Three principles carry the chapter:

**Assert results, not steps.** The test may know what the unit returns, raises, or how state
changed — never which private methods ran in which order. If the implementation could be rewritten
from scratch against the same contract and the test would break, the test is welded to the wrong
thing.

**One behavior per test, named as a specification.** `test_no_late_fee_on_paid_invoice` failing
tells you the bug before you open the file. Tests that act three times and assert twelve things
fail as a shrug. The test list should read as the unit's documentation — because it is.

**Determinism is non-negotiable.** Anything a test touches that varies — the clock, randomness,
ordering, leftover state from another test — will eventually flake. Inject time, seed or inject
randomness, build fresh state per test. The main suite's determinism (Chapter 01) is won here.

A working definition:

> **A unit test verifies one behavior of one unit through its public contract — arrange, act,
> assert on the result — and is fast, isolated, repeatable, and self-checking. A good unit suite
> covers each behavior's case matrix, reads as its specification, and survives any refactor that
> preserves the contract.**

## Production Example

**Invoicely's** late-fee policy is the money logic from Chapter 01's incident, now tested properly.
The rule sounds simple — overdue invoices accrue a 2% monthly late fee — and the case matrix is
where the money is: paid and draft invoices must never accrue fees (the incident); the fee applies
only after the due date, not on it; fees compound monthly but cap at 10% of the invoice total;
amounts are `Decimal`, rounded half-up to the cent (Stage 6, Chapter 01's money rules); a disputed
invoice pauses accrual. Every one of those clauses is a production bug if wrong, and every one is a
two-line parametrized case.

The design makes the logic testable in the first place: the fee decision is a pure function in the
domain layer (Stage 2's service/domain separation) that takes an invoice's state and a reference
date and returns a `Money` fee — no database, no ORM, no `datetime.now()` inside. The test suite
covers the matrix with `pytest.mark.parametrize`, builds invoices with a factory so each test
states only the fields that matter (`make_invoice(status="paid")`), and passes the reference date
explicitly so "the day before the due date" is a value, not a race against the wall clock.

In this chapter we build that suite: the pure function, the parametrized case matrix, the invoice
factory, and the failure cases (`InvalidStateError` for fee accrual on a voided invoice). We
contrast it with the assistant-default version — three happy-path tests that mock the repository
and assert it was called — which is green today and was green during the incident.

## Folder Structure

```
api/
├── app/features/invoices/
│   ├── domain.py                  # pure logic: late_fee(), totals — the code under test here
│   └── service.py                 # orchestration — tested at the seam in Ch 04, not here
└── tests/
    ├── conftest.py                # shared fixtures: frozen clock, factory registration
    ├── factories.py               # make_invoice(), make_line() — builders with safe defaults
    └── unit/
        └── invoices/
            ├── test_late_fee.py   # the fee case matrix (this chapter's core example)
            └── test_totals.py     # totals, rounding, currency edge cases
```

Why this shape: `tests/unit/` mirrors `app/features/` so a module's tests are findable by path —
`domain.py`'s contract lives in one obvious place, which is also what lets an assistant told
"tests live in `tests/unit/<feature>/`" put them there. `factories.py` centralizes test-data
construction so each test states only what matters and a schema change is one edit, not three
hundred. `conftest.py` holds the fixtures every unit test shares — notably the frozen clock —
keeping determinism a default rather than a per-test effort. The unit tree contains no database
or network fixtures at all; if a test needs one, it's not a unit test and belongs in Chapter 04's
tree.

## Implementation

**The unit under test — pure, injectable, decidable.** The fee logic takes everything it needs as
values; nothing inside reaches for the clock or the database.

```python
# app/features/invoices/domain.py
LATE_FEE_MONTHLY_RATE = Decimal("0.02")
LATE_FEE_CAP_RATE = Decimal("0.10")

def late_fee(invoice: Invoice, as_of: date) -> Money:
    if invoice.status in {InvoiceStatus.PAID, InvoiceStatus.DRAFT, InvoiceStatus.VOID}:
        return Money.zero(invoice.currency)          # the Ch 01 incident, as one guard clause
    if invoice.status is InvoiceStatus.DISPUTED or as_of <= invoice.due_date:
        return Money.zero(invoice.currency)
    months_overdue = _full_months_between(invoice.due_date, as_of)
    fee = invoice.total * LATE_FEE_MONTHLY_RATE * months_overdue
    return min(fee, invoice.total * LATE_FEE_CAP_RATE).round_half_up()
```

**The case matrix as parametrized tests.** One behavior per case, named so failures read as bug
reports; the matrix costs one line per clause of the policy.

```python
# tests/unit/invoices/test_late_fee.py
@pytest.mark.parametrize(
    ("status", "days_overdue", "expected_fee"),
    [
        ("paid",     45, "0.00"),    # paid never accrues — the incident case
        ("draft",    45, "0.00"),
        ("disputed", 45, "0.00"),    # dispute pauses accrual
        ("overdue",   0, "0.00"),    # due date itself is not overdue
        ("overdue",  31, "24.00"),   # one full month: 1200.00 * 2%
        ("overdue",  62, "48.00"),   # two months compound... up to
        ("overdue", 400, "120.00"),  # ...the 10% cap
    ],
)
def test_late_fee_matrix(status, days_overdue, expected_fee):
    invoice = make_invoice(status=status, total="1200.00", due=date(2026, 3, 1))   # arrange
    fee = late_fee(invoice, as_of=date(2026, 3, 1) + timedelta(days=days_overdue)) # act
    assert fee == Money(expected_fee, "USD")                                       # assert
```

**Error cases are part of the contract.** What the unit raises, and when, is behavior — assert it.

```python
def test_accruing_fee_on_void_invoice_raises():
    invoice = make_invoice(status="void")
    with pytest.raises(InvalidStateError, match="void"):
        accrue_late_fee(invoice, as_of=date(2026, 4, 1))
```

**Factories: state only what matters.** Safe defaults for everything else, so tests don't break
when an unrelated field is added — and don't bury the relevant field in noise.

```python
# tests/factories.py
def make_invoice(*, status="open", total="1200.00", due=date(2026, 3, 1), **overrides) -> Invoice:
    defaults = dict(
        id=uuid4(), status=InvoiceStatus(status), currency="USD",
        total=Money(total, "USD"), due_date=due, customer_id=uuid4(),
    )
    return Invoice(**{**defaults, **overrides})
```

**Determinism: time is an argument (or a frozen fixture).** Nothing in the unit tree reads the real
clock; where code can't take `as_of` directly, freeze it.

```python
# tests/conftest.py
@pytest.fixture
def frozen_now():
    with freeze_time("2026-03-15T12:00:00Z") as clock:   # freezegun; or inject a Clock port
        yield clock
```

**The anti-example — what not to accept.** Green during the incident, worthless as a spec:

```python
# ANTI-PATTERN: asserts the choreography, not the fee. Survives the paid-invoice bug;
# breaks the moment the implementation is refactored. The inverse of what a test is for.
def test_late_fee_calls_repository(mocker):
    repo = mocker.Mock()
    service = InvoiceService(repo)
    service.apply_late_fees()
    repo.get_overdue.assert_called_once()
```

The difference is the whole chapter: the good suite states the policy as a case matrix against a
pure function — every clause asserted, deterministic, refactor-proof. The bad one asserts that some
methods were called, which is true of correct and incorrect implementations alike.

## Engineering Decisions

Five decisions shape a unit suite.

### What is the "unit" — a class, a function, or a behavior?

**Options:** (1) one test file per class, one test per method; (2) unit = a behavior, tested through
whatever public entry point owns it, even if several objects collaborate underneath.

**Trade-offs:** class-per-file symmetry is easy to enforce and welds the suite to the current object
structure — extract a helper class and tests must move or be rewritten, though behavior never changed.
Behavior-oriented units survive restructuring and require judgment about where the public contract is.

**Recommendation:** the unit is a behavior with a public entry point — `late_fee()` and its policy,
not each private helper it calls. Test private helpers only through the public function; if a helper
grows a contract of its own worth naming, promote it and test it directly. Structure tests around
what the code *promises*, and refactors of *how* stop costing test rewrites.

### Solitary or sociable — mock the collaborators or use the real ones?

**Options:** (1) solitary — replace every collaborator with a test double; (2) sociable — let the
unit use its real in-process collaborators (`Money`, `Invoice`, pure helpers), doubling only what's
slow or nondeterministic.

**Trade-offs:** solitary style isolates failures to one class and, taken as a default, produces the
mock-choreography suite — tests that pass while integration is broken and break on every refactor.
Sociable tests catch real interaction bugs between domain objects and can fail a few classes below
the entry point (mildly less precise), which in a fast suite costs minutes.

**Recommendation:** sociable by default: real value objects and domain collaborators, doubles only
at the boundaries that are slow, nondeterministic, or external (the clock, the database, the payment
API — Chapter 03's subject). A unit test that needs three mocks to arrange is a signal the behavior
lives at a seam and belongs in Chapter 04.

### How do you structure and name tests?

**Options:** (1) free-form (`test_late_fee_2`); (2) enforced AAA with specification names
(`test_<behavior>_<condition>_<outcome>`); (3) BDD frameworks with given/when/then DSLs.

**Trade-offs:** free-form is fastest to write and unreadable in failure output — the test list says
nothing. AAA-with-spec-names costs a naming pause per test and makes the suite double as
documentation; failure output reads as a bug report. BDD DSLs add tooling and ceremony that pays off
mainly when non-engineers read the specs; for an engineering-facing suite it's usually overhead.

**Recommendation:** AAA structure, one act per test, names that state condition and outcome. Enforce
it in review and record it in `CLAUDE.md` — naming is a convention assistants follow well once
stated, and never adopt spontaneously. Skip BDD frameworks unless the specs have a non-engineer
audience.

### Test data: inline literals, fixtures, or factories?

**Options:** (1) inline construction in every test; (2) shared fixture objects (`the_invoice`);
(3) factories/builders with safe defaults and per-test overrides.

**Trade-offs:** inline construction shows everything and buries the one field that matters in eight
that don't, and every schema change touches every test. A shared fixture object couples dozens of
tests to one blob — change a field for one test and unrelated tests fail. Factories cost a small
module and give tests that state only what matters and absorb schema churn in one place.

**Recommendation:** factories with safe defaults (`make_invoice(status="paid")`), keyword-only
overrides for what the test is about. Keep fixtures (the pytest kind) for *infrastructure* — the
frozen clock, a temp directory — not for domain data. The readability rule: a reviewer should learn
which fields matter to the behavior by reading the arrange block.

### How do you handle time and randomness?

**Options:** (1) let code call `datetime.now()`/`random` and hope; (2) freeze/patch globally in tests
(freezegun, seeded `random`); (3) design it out — time and randomness enter as parameters or injected
ports.

**Trade-offs:** hoping produces the classic flakes — the test that fails at midnight, on the 31st, in
CI's timezone. Freezing works without changing production code and patches globals (order-sensitive,
easy to leak). Injection (`as_of: date`, a `Clock`/`IdGenerator` port) makes determinism structural
and costs a parameter on the API.

**Recommendation:** design it out where you own the code — domain logic takes `as_of` as an argument
(as `late_fee` does), services take a clock port (Stage 2, Chapter 06's dependency injection doing
double duty). Freeze time only at boundaries you can't redesign. Either way the rule from the mental
model stands: no unit test reads the real clock or unseeded randomness, ever.

## Trade-offs

Unit testing trades authoring discipline for a suite that stays cheap to live with.

**Contract-level tests trade failure locality for refactor survival.** A sociable, behavior-level
test may fail one abstraction above the actual fault, costing minutes of debugging; a mock-welded
test points at the line and taxes every restructuring. In a suite that runs in seconds, debugging
locality is cheap and refactor freedom is not — the trade goes one way.

**The case matrix trades authoring time for edge-case coverage.** Enumerating boundaries and error
cases takes deliberate effort per behavior (parametrize makes it cheap, not free). The alternative —
happy-path-only — defers the cost to production, with interest.

**Designing for testability trades API surface for determinism.** `as_of` parameters, injected
clocks, and factory modules are real (small) additions to the codebase. What they buy is structural:
tests that cannot flake and logic that is honest about its inputs — which tends to be better design
independent of testing.

**Purity has a scope limit.** Keeping logic pure and testable pushes I/O to the edges — but the
edges still exist, and unit tests cannot see them. The suite's speed is bought by excluding exactly
the bugs (SQL, wiring, transactions) that Chapter 04 exists to catch; a unit suite alone is a false
comfort.

## Common Mistakes

**Testing private internals.** Reaching past the public contract to assert helper calls or private
state. Fix: test through the entry point; if a helper deserves direct tests, promote it to a public
contract first.

**Happy path only.** One test proving the feature works, zero proving it fails correctly. Fix:
parametrize the matrix — boundaries, error cases, the weird-but-legal inputs are where bugs live.

**Multiple behaviors per test.** Three acts and twelve asserts; failure output is a shrug. Fix: one
act per test; split until each name states one fact.

**Hidden clock and randomness.** `datetime.now()` deep in the logic; tests pass until month-end.
Fix: time as a parameter or injected clock; seed or inject randomness.

**Shared mutable test state.** Module-level objects mutated across tests; the suite passes in order
and fails shuffled. Fix: fresh state per test via factories/fixtures; run with randomized order in CI
to flush violations.

**Asserting too loosely.** `assert result is not None`, `assert len(items) > 0` — tests that a wrong
answer still passes. Fix: assert the exact expected value; if the exact value is awkward, the unit's
contract is probably underspecified.

## AI Mistakes

Unit tests are the artifact assistants generate most readily — and volume without judgment produces
exactly the pathologies above, at scale. Review generated tests as specifications: what do they
assert, and would they fail if the behavior broke?

### Claude Code: the change-detector suite — tests derived from the implementation

Asked to "add unit tests" for existing code, Claude Code reads the implementation and generates
tests that restate it — asserting internal call order, patching private helpers, and pinning
current outputs (including buggy ones) as expected values. Coverage jumps; specification value is
zero. The suite now certifies the code against itself and breaks on the next refactor.

**Detect:** expected values suspiciously equal to current output with no reference to a requirement;
`mocker.patch` on the module's own private functions; assertions on call sequences of internal
collaborators; generated tests that all pass first try against code you suspect is buggy.

**Fix:** feed the contract, not the code:

> Write the tests from this behavior specification, not from the implementation: [the policy /
> docstring / requirement]. Assert return values, raised errors, and state changes through the
> public function only — do not patch or assert on anything private to the module. Include the
> boundary and error cases the spec implies.

### GPT: three green tests and no matrix — the happy-path suite

GPT-family models default to a small set of demonstrative tests: the feature works for a normal
input, maybe one obvious error. The boundaries — the due date itself, the zero amount, the cap, the
already-paid invoice — are exactly what's missing, and they're where the incidents live. The suite
looks done and verifies a fraction of the contract.

**Detect:** no `parametrize` where the behavior clearly has a matrix; no boundary values (0, 1, max,
the threshold itself) in any test; no `pytest.raises` anywhere; test count per behavior of one.

**Fix:** demand the matrix explicitly:

> Enumerate the case matrix for this behavior first — happy path, each boundary (including the
> threshold values themselves), each error case and what it raises, and the weird-but-legal inputs.
> Then implement it as parametrized tests. I'll review the case list before the tests.

### Cursor: tests coupled by leftover state

Cursor's inline completions reuse whatever pattern is nearby — a module-level `invoice = ...`
mutated across tests, a fixture with the wrong scope, an append to a shared list — producing tests
that pass in file order and fail when run alone, shuffled, or in parallel. The flake appears weeks
later in CI and gets blamed on infrastructure.

**Detect:** module- or class-level mutable objects in test files; fixtures scoped `session`/`module`
returning mutable domain objects; tests that fail with `pytest -p randomly` or `pytest path::test`
alone but pass in the full run.

**Fix:** make isolation structural:

> Each test must build its own state — construct via factories inside the test or function-scoped
> fixtures; no module-level mutable objects, no fixture wider than function scope for domain data.
> Run the suite with randomized order and confirm it passes before finishing.

## Best Practices

**Write each test as a contract sentence.** Arrange–act–assert, one behavior, named as
`test_<behavior>_<condition>_<outcome>`. The test list is the unit's documentation; failure output
is a bug report.

**Cover the matrix, cheaply.** Parametrize the cases — boundaries, error paths, weird-but-legal
inputs — and derive them from the requirement, not the code. See every new test fail once (against
old code or with the fix reverted).

**Keep unit tests hermetic.** No network, database, disk, real clock, or unseeded randomness — time
and randomness enter as parameters or injected ports. Run with randomized order in CI to keep
isolation honest.

**Build state with factories; keep fixtures for infrastructure.** Safe defaults plus keyword
overrides, so tests state only what matters and schema churn lands in one file.

**Prefer sociable tests; treat mock-count as a design signal.** Real in-process collaborators by
default; doubles only at slow/nondeterministic/external boundaries (Chapter 03). Three mocks in the
arrange block means the test wants to be an integration test.

**Encode the conventions in `CLAUDE.md`.** Test location, naming scheme, factory usage, hermeticity
rules, and "never modify a test to make it pass" — assistants follow stated conventions and violate
unstated ones.

## Anti-Patterns

**The Change Detector.** Tests asserting internal choreography or pinning current output as truth.
The tell: refactors that preserve behavior break tests; expected values match known-buggy output.

**The Happy-Path Suite.** One demonstrative test per feature, no boundaries, no error cases. The
tell: zero `pytest.raises`, zero threshold values, incidents in "tested" code.

**The Tautology.** Assertions a wrong answer satisfies — `is not None`, `>= 0`, or recomputing the
expected value with the same logic under test. The tell: mutate the implementation and the test
stays green.

**The Ordered Suite.** Tests coupled through shared mutable state, passing only in file order. The
tell: fails under `pytest -p randomly`, in parallel, or run alone.

**The Clock Bomb.** Logic reading the real clock; tests that fail at month-end, midnight, or in CI's
timezone. The tell: `datetime.now()`/`date.today()` inside domain logic; flakes that correlate with
the calendar.

**The Mock Choreography.** Every collaborator doubled, assertions on `assert_called_once_with` —
the test proves wiring, not behavior. The tell: green suite, broken feature; more mock setup than
assertions.

## Decision Tree

"I'm about to unit-test a behavior — how?"

```
Is the logic reachable as a pure call (inputs → result, no I/O inside)?
├── YES ─► test it directly. This is the cheap path — protect it.
└── NO ──► can you extract/parameterize it (as_of arg, injected clock/port)?
           ├── YES ─► refactor first (testability = design), then test the pure core.
           └── NO ──► it lives at a seam → Chapter 04 (integration), not a mock pile here.

For the behavior: enumerate the case matrix BEFORE writing tests
    happy path · each boundary (0/1/max/threshold itself) · each error (raises what?)
    └─► parametrize; name each case; assert exact values.

Arranging takes 3+ mocks, or asserts want to check calls not results?
└──► wrong level or wrong boundary — sociable test with real collaborators,
     doubles only for slow/nondeterministic/external (Ch 03), or move to Ch 04.

New test written?
└──► see it FAIL once (revert fix / break the code) · run shuffled · then commit.
```

## Checklist

### Implementation Checklist

- [ ] Every behavior's case matrix is covered: happy path, boundaries (including thresholds themselves), error cases with exact exception types.
- [ ] Tests follow arrange–act–assert with one act per test; names state behavior, condition, and outcome.
- [ ] Assertions check exact results (values, raised errors, state changes) — no tautological or existence-only asserts.
- [ ] No unit test touches network, database, disk, the real clock, or unseeded randomness.
- [ ] Test data comes from factories with safe defaults; tests state only the fields that matter.
- [ ] Every new test has been seen to fail once.

### Architecture Checklist

- [ ] Domain logic is pure and directly callable — time, IDs, and randomness enter as parameters or injected ports.
- [ ] The unit test tree mirrors the feature structure and contains no infrastructure fixtures.
- [ ] Tests are sociable by default; doubles appear only at external/slow/nondeterministic boundaries.
- [ ] The suite passes with randomized test order and in parallel.
- [ ] Testing conventions (location, naming, factories, hermeticity) are recorded in `CLAUDE.md`.

### Code Review Checklist

- [ ] New tests assert requirements, not current implementation output — a reviewer can name the rule each test verifies.
- [ ] No assertions on private helpers, internal call order, or mock choreography where a result assert is possible.
- [ ] Boundary and error cases are present, not just the happy path (watch AI-generated suites closely here).
- [ ] No shared mutable state between tests; no fixture wider than function scope holding domain data.
- [ ] No test was weakened (loosened assert, updated expected value, skip) to make the build pass without an agreed reason.

## Exercises

**1. Test the fee matrix — then mutate.** Implement `late_fee` (or take your own money logic) and
write the parametrized case matrix. Then verify the suite's strength by mutation: introduce five
single-line bugs (drop the paid-status guard, `<` → `<=` on the due date, remove the cap, round the
wrong way, wrong rate) and confirm at least one test fails for each. Every surviving mutant is a
missing case. The artifact is the suite plus the mutation log.

**2. Rescue a change-detector suite.** Take (or generate with an assistant, unreviewed) a test file
full of mock-choreography tests for a service. Rewrite it: extract the pure decision logic, test it
through its contract, and delete the choreography asserts. Then perform a refactor that preserves
behavior and show the old suite would have broken while the new one stays green. The artifact is the
before/after suites and the refactor diff.

**3. Flush the nondeterminism.** Add `pytest-randomly` (or `-p randomly`) and parallel execution to
an existing suite and run it ten times. For each failure, diagnose the coupling — shared state, clock,
ordering — and fix it structurally (factories, injected time, function-scoped fixtures). The artifact
is the failure list and the fixes.

## Further Reading

- ***Unit Testing: Principles, Practices, and Patterns* by Vladimir Khorikov** — the definitive
  treatment of observable-behavior vs implementation-detail coupling, and of when a unit test's
  maintenance cost exceeds its value.
- **pytest documentation — "How to parametrize fixtures and test functions" and "Fixtures"**
  (docs.pytest.org) — the mechanics this chapter leans on: parametrized case matrices, fixture
  scopes, and `conftest.py` organization.
- **"Test Desiderata" by Kent Beck (kentbeck.github.io/TestDesiderata)** — twelve properties of good
  tests and the trade-offs between them; a compact vocabulary for arguing about what a suite should
  optimize.
- **Stage 8, Chapter 03 — Mocking & Test Doubles** — the boundary discipline this chapter defers:
  which collaborators to double, which kind of double, and how to avoid testing the mocks.

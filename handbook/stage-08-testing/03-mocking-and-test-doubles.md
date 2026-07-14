# Mocking & Test Doubles

## Introduction

A test double is a stand-in for something your code depends on — the payment provider, the email
sender, the clock — so a test can run fast, deterministically, and without side effects. Doubles
are what make unit testing possible at the boundaries: you cannot charge a real card in a test, you
should not send real email, and you must not depend on a third-party sandbox being up for your
suite to pass. Chapter 02 kept doubles at arm's length ("sociable by default"); this chapter is
about the boundaries where they're the right tool, and the discipline that keeps them honest.

The single most important idea: **a double replaces a dependency so you can test *your* code — the
moment the test mostly verifies the double, it verifies nothing.** Mocking is the most abused
technique in testing. Used at the right boundary, a double removes nondeterminism and cost while
your logic is exercised for real. Used everywhere, it hollows the suite out: every collaborator
faked, assertions reduced to "the mock was called," and a green suite that proves only that the
mocks agree with each other. The failure mode isn't loud — it's a suite that passes while the
integrated system is broken, which is precisely the false confidence Chapter 01 warned about.

There's a second, quieter failure: drift. A hand-configured mock encodes your *belief* about the
real dependency — the method name, the arguments, the return shape. When the real thing changes,
the mock doesn't, and the suite keeps passing against an API that no longer exists. The discipline
this chapter teaches — double only at owned boundaries, prefer fakes and stubs over
interaction-asserting mocks, keep every double spec-bound to a real interface, and back doubles
with contract/integration tests — is what separates isolation from self-deception.

## Why It Matters

Doubles sit at the point where a unit suite either isolates or lies, and the stakes compound with
suite size:

- **Some dependencies cannot be real in tests.** Charging cards, sending email, calling
  rate-limited third-party APIs — correctness aside, these are side effects with real-world cost.
  Doubles are not optional at these boundaries; the only question is whether they're honest.
- **Determinism and speed are bought here.** The network, the clock, and other services are the
  main sources of slowness and flakes. Doubling them is how a thousand-test suite runs in seconds
  and never fails randomly — the trust budget from Chapter 01 depends on it.
- **Over-mocking is the leading cause of worthless suites.** When every collaborator is a mock,
  the test asserts choreography between fakes. Refactors break it (wrong-way brittleness), real
  bugs pass through it (wrong-way confidence). Teams discover this only when production breaks
  behind a green build.
- **Unspecced mocks drift silently.** `MagicMock` accepts any method, any arguments, and returns
  a truthy mock — so a typo'd method name, a renamed parameter, or a changed return shape all pass.
  Every unspecced mock is a place your suite has opted out of noticing change.
- **Doubles define your architecture's seams.** Deciding what to double forces the question Stage 2
  kept asking: where are the boundaries? Code that's hard to double (dependencies constructed
  inline, I/O woven through logic) is code with missing seams — the test pain is a design signal.
- **AI assistants mock reflexively.** Asked for tests, assistants reach for `patch` as the default
  tool — doubling domain objects, patching internals, generating exactly the over-mocked suites
  above, at generation speed. Without a stated boundary discipline, mock sprawl is the default
  outcome.

Get it right — doubles only at real boundaries, spec-bound, mostly fakes and stubs, backed by
integration tests — and the unit suite is fast, deterministic, and still means something. Get it
wrong and the suite becomes an elaborate mirror: it reflects your assumptions back at you and
calls them verified.

## Mental Model

Doubles come in kinds — and the kind you reach for shapes what the test can lie about:

```
  WHERE DOUBLES BELONG — the boundary rule
      [ your domain logic ] ── real collaborators, no doubles (Ch 02: sociable)
      [ your ports/seams  ] ── DOUBLE HERE: payment gateway, email, clock, storage
      [ the outside world ] ── never called in unit tests; covered by Ch 04/05 + contract tests

  THE KINDS (weakest claim → strongest coupling)
      dummy   fills a parameter; never used
      stub    returns canned answers        "when charge() is called, return success"
      fake    working lightweight impl      in-memory repository, fake payment gateway w/ state
      spy     records calls for later check "what was sent?" — assert on recorded facts
      mock    pre-programmed expectations   asserts HOW it was called (interaction testing)
      ↑ prefer the weakest kind that can catch the failure — state over interaction

  TWO WAYS A DOUBLED TEST LIES
      over-mocking : doubles inside the unit → test asserts mock↔mock choreography
      drift        : double's shape ≠ real dependency → suite passes against a dead API
      defenses     : double only at seams · spec/autospec every mock ·
                     a contract/integration test covers each faked boundary (Ch 04)

  ASSERT STATE, NOT INTERACTION (when you can)
      good:  fake_gateway.charges == [Charge(invoice_id, amount)]     ← observable outcome
      risky: mock.charge.assert_called_once_with(invoice_id, amount)  ← implementation detail
      interaction asserts are for genuine commands (side effects) with no observable state.
```

Three principles carry the chapter:

**Double at the seams you own, nothing inside them.** The unit's own collaborators — value objects,
domain helpers, pure functions — stay real. Doubles replace the ports at the edge: payment, email,
storage, time. If you're patching something defined in the module under test, you're testing around
your own code.

**Prefer the weakest double: stub or fake over mock.** A stub or fake lets the test assert
*outcomes* (what ended up in the fake, what the function returned); a mock asserts *interactions*
(which methods were called, how). Interaction assertions couple the test to the implementation's
choreography — justified for genuine fire-and-forget commands, a liability everywhere else.

**Keep every double honest.** Spec it against the real interface (`autospec`), so renamed methods
and changed signatures fail the test instead of passing silently — and pair every faked boundary
with a real test (integration or contract) somewhere in the suite, so the fake's assumptions are
checked against reality.

A working definition:

> **Test doubles replace slow, nondeterministic, or external dependencies at owned boundaries so
> unit tests stay fast and deterministic. Prefer stubs and fakes that let you assert outcomes;
> reserve interaction-asserting mocks for genuine commands; spec every double against the real
> interface; and back every faked boundary with an integration or contract test. A test that
> mostly verifies its mocks verifies nothing.**

## Production Example

**Invoicely's** "send invoice" flow is the boundary showcase: when an invoice is issued, the system
charges the customer's saved payment method via the payment provider and emails the invoice PDF.
Neither can be real in a unit test — one moves money, the other spams customers — and both are
exactly the kind of dependency that makes untested-in-CI code rot.

The architecture makes doubling clean because the seams already exist (Stage 2, Chapters 05–06):
the service depends on a `PaymentGateway` port and an `EmailSender` port, injected via FastAPI's
dependency injection; Stripe and the SMTP provider live in adapters behind those ports. The test
suite doubles at the ports: a `FakePaymentGateway` — twenty lines of real behavior (records
charges, returns declines when told to, raises on double-charge of the same idempotency key) — and
a spy-style `FakeEmailSender` that records what would have been sent. Tests assert *outcomes*: the
charge appears in the fake with the right amount, a declined payment moves the invoice to
`payment_failed` and sends no email, a duplicate issue attempt doesn't double-charge. No
`assert_called_once_with` anywhere except one genuine command case.

Two honesty mechanisms back the fakes. Every ad-hoc mock in the suite is created with
`autospec`/`spec_set` against the port, so signature drift fails loudly. And the Stripe adapter
itself — the code the fake stands in for — has its own thin integration test against Stripe's test
mode (Chapter 04), so the fake's assumptions about decline codes and idempotency behavior are
checked against the real API, not just believed. In this chapter we build the ports, the fakes, and
the tests — and contrast them with the assistant-default version: `patch("app...stripe.Charge.create")`
three layers deep, asserting call choreography against an unspecced `MagicMock`.

## Folder Structure

```
api/
├── app/
│   ├── ports/
│   │   ├── payments.py            # PaymentGateway protocol — the seam doubles stand in for
│   │   └── email.py               # EmailSender protocol
│   ├── adapters/
│   │   ├── stripe_payments.py     # real implementation; covered by Ch 04 adapter test
│   │   └── smtp_email.py
│   └── features/invoices/
│       └── service.py             # issue_invoice(): depends on ports, never on adapters
└── tests/
    ├── fakes/
    │   ├── payments.py            # FakePaymentGateway — stateful fake, reused suite-wide
    │   └── email.py               # FakeEmailSender — spy: records sent messages
    ├── unit/invoices/
    │   └── test_issue_invoice.py  # service tests using the fakes; outcome assertions
    └── integration/adapters/
        └── test_stripe_adapter.py # keeps the fake honest against Stripe test mode (Ch 04)
```

Why this shape: `ports/` makes the doubling boundary a first-class, importable contract — fakes and
adapters implement the same protocol, and `autospec` has a real interface to check against.
`tests/fakes/` centralizes the fakes so every test doubles the boundary the same way (one honest
fake beats thirty ad-hoc mocks of the same port), and improving the fake — adding decline
behavior, idempotency — upgrades the whole suite at once. The adapter integration test lives apart
because it needs credentials and network; its job is to verify the assumptions the fake encodes.
The structure *is* the discipline: doubles exist for `ports/`, never for things inside `features/`.

## Implementation

**The seam — a port the service depends on.** Small, owned, and shaped by what the domain needs
(not by Stripe's API surface).

```python
# app/ports/payments.py
class PaymentGateway(Protocol):
    def charge(self, *, customer_id: str, amount: Money, idempotency_key: str) -> ChargeResult: ...

# app/features/invoices/service.py
class InvoiceService:
    def __init__(self, gateway: PaymentGateway, email: EmailSender, invoices: InvoiceRepository):
        self._gateway, self._email, self._invoices = gateway, email, invoices

    def issue_invoice(self, invoice_id: UUID) -> Invoice:
        invoice = self._invoices.get(invoice_id)
        result = self._gateway.charge(
            customer_id=invoice.customer_id, amount=invoice.total,
            idempotency_key=f"invoice-{invoice.id}",
        )
        if not result.succeeded:
            return self._invoices.save(invoice.mark_payment_failed(result.decline_reason))
        self._email.send(invoice_paid_email(invoice))
        return self._invoices.save(invoice.mark_paid(result.charge_id))
```

**The fake — a tiny real implementation, not a scripted mock.** It has behavior, so tests assert
outcomes against it.

```python
# tests/fakes/payments.py
class FakePaymentGateway:
    def __init__(self, *, decline_with: str | None = None):
        self.charges: list[dict] = []
        self._decline_with = decline_with
        self._seen_keys: set[str] = set()

    def charge(self, *, customer_id: str, amount: Money, idempotency_key: str) -> ChargeResult:
        if idempotency_key in self._seen_keys:                 # real gateways dedupe; so does the fake
            return ChargeResult.duplicate(idempotency_key)
        self._seen_keys.add(idempotency_key)
        if self._decline_with:
            return ChargeResult.declined(self._decline_with)
        self.charges.append({"customer_id": customer_id, "amount": amount})
        return ChargeResult.succeeded_with(charge_id=f"ch_{len(self.charges)}")
```

**Tests assert outcomes — state in the fakes, state in the domain.** No interaction choreography.

```python
# tests/unit/invoices/test_issue_invoice.py
def test_issuing_charges_the_invoice_total_once():
    gateway, email = FakePaymentGateway(), FakeEmailSender()
    service = InvoiceService(gateway, email, InMemoryInvoiceRepository([make_invoice(total="450.00")]))

    invoice = service.issue_invoice(INVOICE_ID)

    assert invoice.status is InvoiceStatus.PAID
    assert [c["amount"] for c in gateway.charges] == [Money("450.00", "USD")]   # outcome, not calls
    assert email.sent[0].template == "invoice_paid"

def test_declined_payment_marks_failed_and_sends_nothing():
    gateway = FakePaymentGateway(decline_with="card_declined")
    email = FakeEmailSender()
    service = InvoiceService(gateway, email, InMemoryInvoiceRepository([make_invoice()]))

    invoice = service.issue_invoice(INVOICE_ID)

    assert invoice.status is InvoiceStatus.PAYMENT_FAILED
    assert email.sent == []                                    # the failure path, asserted exactly

def test_reissuing_does_not_double_charge():
    gateway = FakePaymentGateway()
    service = InvoiceService(gateway, FakeEmailSender(), InMemoryInvoiceRepository([make_invoice()]))

    service.issue_invoice(INVOICE_ID)
    service.issue_invoice(INVOICE_ID)                          # retry / double-click / job re-run

    assert len(gateway.charges) == 1                           # idempotency as an observable outcome
```

**When you must mock ad hoc: spec it.** An unspecced `MagicMock` passes typos and drift; `autospec`
fails them.

```python
def test_email_failure_does_not_lose_the_paid_status(mocker):
    email = mocker.create_autospec(EmailSender, instance=True)   # spec-bound: wrong signature = failure
    email.send.side_effect = EmailDeliveryError("smtp timeout")
    service = InvoiceService(FakePaymentGateway(), email, InMemoryInvoiceRepository([make_invoice()]))

    invoice = service.issue_invoice(INVOICE_ID)

    assert invoice.status is InvoiceStatus.PAID                  # charge happened; email failing must not undo it
```

**The anti-example — patching internals, asserting choreography.** Everything this chapter exists
to prevent:

```python
# ANTI-PATTERN: patches a third-party call 3 layers deep, asserts choreography on an
# unspecced mock. Passes when the code is wrong; breaks when the code is refactored.
def test_issue_invoice(mocker):
    charge = mocker.patch("app.adapters.stripe_payments.stripe.Charge.create")
    mocker.patch("app.features.invoices.service.invoice_paid_email")   # patching our own module!
    service.issue_invoice(INVOICE_ID)
    charge.assert_called_once()
```

The difference is the whole chapter: the good tests exercise the real service logic against small
honest fakes and assert what *happened* — charged once, right amount, right status, email or no
email. The bad test patches through the seams, asserts that calls occurred, and would pass with the
amount wrong, the status wrong, and the email sent to the wrong customer.

## Engineering Decisions

Five decisions define how a codebase uses doubles.

### Which dependencies get doubled at all?

**Options:** (1) everything except the class under test (solitary style); (2) nothing — real
dependencies everywhere, containers for infrastructure; (3) only the boundary ports: external
services, I/O, time, randomness.

**Trade-offs:** doubling everything produces choreography suites that are brittle and blind — the
integration between your own classes is exactly what never gets tested. Doubling nothing makes
every test an integration test: honest but slow, and unusable for the case-matrix work of
Chapter 02. Boundary-only doubling keeps logic real and removes precisely the slow/nondeterministic/
external pieces — at the cost of needing actual boundaries in the design.

**Recommendation:** boundary-only. Real value objects, real domain collaborators, real in-memory
repositories; doubles for payment, email, external HTTP, storage, clock. The heuristic from
Chapter 02 stands: needing three-plus doubles to arrange a test means the code has missing seams or
the test belongs at integration level — fix the design or move the test, don't pile on mocks.

### Stub, fake, spy, or mock — which kind?

**Options:** (1) scripted mocks with interaction assertions everywhere (`assert_called_once_with`);
(2) stubs for queries, spies/outcome-recording for commands; (3) stateful fakes shared across the
suite.

**Trade-offs:** interaction mocks are quick to write and assert the implementation's choreography —
maximum brittleness, minimum behavioral claim. Stubs and spies keep assertions on outcomes but
each test re-scripts the boundary's behavior. A shared fake costs a small real implementation
(with its own subtle risk: the fake can diverge from reality) and gives the whole suite one honest,
improvable model of the dependency.

**Recommendation:** stateful fakes for the boundaries you double often (payment, email, repository)
— they centralize the model of the dependency and enable outcome assertions everywhere. Stubs for
one-off query boundaries. Reserve interaction assertions (`assert_called_*`) for genuine
fire-and-forget commands with no observable outcome — and treat each one as a small debt. Keep
fakes honest with the contract tests below.

### Inject the dependency or `patch()` it?

**Options:** (1) `unittest.mock.patch` the name where it's used; (2) constructor/dependency
injection — pass the double in; (3) FastAPI `dependency_overrides` at the app boundary.

**Trade-offs:** `patch` needs no design change and couples the test to module paths and import
mechanics ("patch where it's *used*, not where it's defined" — the classic trap), breaks on file
moves, and hides the dependency from readers. Injection requires the seam to exist (Stage 2,
Chapter 06 built exactly this) and makes tests trivial: construct with the fake, done. Dependency
overrides are injection for route-level tests.

**Recommendation:** injection first — if a test wants to `patch`, ask why the dependency isn't
injectable; the answer usually improves the design. Use `patch` only at boundaries you genuinely
can't restructure (third-party module internals during a transition), and `dependency_overrides`
for FastAPI route tests in Chapter 04. A codebase where doubles arrive by constructor needs no
patching machinery at all.

### How do you keep doubles from drifting off the real interface?

**Options:** (1) bare `MagicMock` and discipline; (2) `autospec`/`spec_set` against the port
everywhere; (3) spec-bound doubles *plus* a contract test asserting fake and real adapter behave
alike.

**Trade-offs:** bare mocks accept everything — renamed methods, wrong signatures, changed return
shapes all pass; discipline doesn't survive team growth or AI generation. Autospec catches
signature drift for free but not behavioral drift (the fake returning shapes the real API never
would). Contract tests — one parametrized suite run against both the fake and the real adapter —
catch behavioral drift too, at the cost of maintaining that suite and test-mode credentials.

**Recommendation:** `autospec`/`spec_set` as a hard rule for every ad-hoc mock (enforce in review
and `CLAUDE.md`), and a contract test for the boundaries where drift is expensive — payments above
all. The fake is a claim about how Stripe behaves; the contract test is what makes it a *checked*
claim.

### Do you mock what you don't own?

**Options:** (1) mock the third-party SDK directly in tests (`patch("stripe.Charge.create")`);
(2) wrap the dependency in an owned port and double the port; (3) use the vendor's test
mode/sandbox in integration tests.

**Trade-offs:** mocking the SDK couples dozens of tests to an interface you can't control — SDK
upgrades silently invalidate every mock, and the mocks encode your possibly-wrong reading of the
API. An owned port costs an adapter layer and shrinks the third-party surface to one place, doubled
one way. Sandboxes are the truth and are slow, networked, and rate-limited — wrong for unit tests,
right for the adapter's own test.

**Recommendation:** the classic rule — **don't mock what you don't own.** Wrap the vendor in a port
shaped by your domain, double the port in unit tests, and test the real adapter against the vendor's
test mode in Chapter 04's integration suite. When the SDK changes, one adapter and one contract test
change; the unit suite doesn't notice.

## Trade-offs

Doubles buy isolation with assumptions — every one is a small loan against reality.

**Faking a boundary trades realism for speed and determinism.** The fake gateway answers in
microseconds and never has an outage; it also only declines the ways you taught it to. The unit
suite's speed is real, and so is its blindness past the port — which is why every doubled boundary
must be paid for with an integration or contract test (Chapter 04).

**Stateful fakes trade upfront implementation for suite-wide honesty.** Twenty lines of fake with
real dedupe behavior costs more than `MagicMock()` — once. In exchange, every test asserts outcomes
against one consistent model, and improving that model upgrades the entire suite. The residual risk
(the fake diverging from the vendor) is bounded by the contract test.

**Outcome assertions trade a little directness for refactor survival.** `assert_called_once_with`
states exactly what the implementation did; asserting on `gateway.charges` states what the world
looks like afterwards. The second survives reordering, extraction, and rewrites; the first is a
tripwire on the current choreography.

**Ports and injection trade architecture for testability.** The seams that make doubling clean are
real code — protocols, adapters, wiring (Stage 2, Chapters 05–06). For boundaries like payments and
email, that architecture pays for itself in the first incident it prevents; for a dependency used
once in a script, a `patch` and a comment is the proportionate choice. Boundary discipline, like
every discipline in this handbook, is applied by judgment rather than reflex.

## Common Mistakes

**Mocking inside the unit.** Patching the module's own helpers or domain objects, so the test
verifies choreography between fakes. Fix: doubles only at ports; everything in-process stays real.

**Asserting interactions when outcomes exist.** `assert_called_once_with` where the result or the
fake's state could be asserted. Fix: assert what happened, not how; reserve call assertions for
genuine void commands.

**Unspecced mocks.** `MagicMock()` accepting typo'd methods and drifted signatures forever. Fix:
`autospec=True`/`spec_set` against the port, no exceptions.

**Patching where it's defined, not where it's used.** `patch("app.adapters.stripe...")` while the
service imported the name into its own namespace — the mock never gets hit, and the test passes
for the wrong reason. Fix: prefer injection; when patching, patch the *using* module's name.

**Faked boundary, no real test anywhere.** The suite's entire knowledge of Stripe is the fake. Fix:
each doubled boundary gets an adapter integration test or contract test (Chapter 04).

**Mock behavior leaking between tests.** Module-scoped mocks accumulating state or `side_effect`
scripts across tests. Fix: fresh doubles per test — same isolation rule as Chapter 02's factories.

## AI Mistakes

Mocking is where assistant-generated tests go wrong most confidently: `patch` is the hammer every
generated test reaches for, and every resulting suite is green. Review the *boundary choices*, not
the pass rate.

### Claude Code: mock sprawl — doubling the unit's own internals

Asked to test a service, Claude Code tends to patch everything the service touches — its own
helpers, the domain email builder, the repository, sometimes functions in the same file — then
assert the calls happened. The test is hermetic and verifies nothing: all logic between the patches
is unexercised, and the assertions restate the implementation. It will also happily patch a
function *where it's defined* rather than where it's used, producing tests that pass without the
mock ever being invoked.

**Detect:** `mocker.patch`/`@patch` targeting the module under test or sibling domain modules;
more patch lines than assert lines; assertions that are all `assert_called*`; patch targets that
don't match the importing module's namespace.

**Fix:** state the boundary rule in the prompt:

> Double only the injected ports (PaymentGateway, EmailSender, repository) — pass fakes through the
> constructor; do not patch anything, and do not double any value object, helper, or function
> belonging to the application. Assert outcomes (returned values, invoice status, the fake's
> recorded state), not which methods were called.

### GPT: the ever-agreeable MagicMock — doubles with no spec and no failure modes

GPT-family models default to bare `MagicMock()` stubs scripted for success: the gateway always
approves, the email always sends, every method accepts anything and returns something truthy. Two
things go untested as a result: the failure paths (declines, timeouts, duplicates — where the real
bugs are), and the interface itself (a renamed port method passes forever, since the mock accepts
any call).

**Detect:** no `spec`/`autospec` on any mock; no test where the double is configured to fail
(`side_effect`, decline results); return values left as default mocks and only truthiness-checked
downstream.

**Fix:** require specs and failure scripting:

> Every mock must be created with `autospec` against the port protocol. For each doubled boundary,
> include the failure cases: a declined charge, a raised timeout, a duplicate idempotency key — and
> assert the system's behavior in each (status transitions, no email sent, no double charge).

### Cursor: welding tests to the vendor SDK

Completing tests in a file that imports the SDK, Cursor patches the vendor's internals directly —
`patch("stripe.Charge.create")`, mocked `requests.post` with hand-built response JSON — encoding a
guess about the vendor's API shapes into dozens of tests. The suite now breaks on SDK upgrades,
passes on wrong assumptions about the API, and couples every test file to a dependency the team
doesn't control.

**Detect:** patch targets in third-party namespaces (`stripe.*`, `requests.*`, `boto3.*`) inside
feature tests; hand-constructed vendor response dicts duplicated across test files; test failures
appearing after a dependency version bump.

**Fix:** route the double through the owned port:

> Don't mock the vendor SDK — the service depends on our PaymentGateway port; use the shared
> FakePaymentGateway from tests/fakes. Vendor API behavior is verified once, in the adapter's
> integration test against test mode, not re-mocked per test.

## Best Practices

**Double at owned seams only.** Ports for payment, email, storage, time, external HTTP; everything
in-process stays real. If doubling is hard, treat it as the design feedback it is.

**Prefer fakes and outcome assertions.** One shared, stateful fake per hot boundary in
`tests/fakes/`; assert results and recorded state, and keep `assert_called_*` for genuine void
commands.

**Spec everything, script the failures.** `autospec`/`spec_set` on every ad-hoc mock; every doubled
boundary has tests where it declines, times out, and duplicates — failure paths are the point of
the exercise.

**Pay for every fake with a real test.** Each doubled boundary is backed by an adapter integration
test or a contract test run against both fake and real implementation (Chapter 04) — the fake is a
checked claim, not a belief.

**Inject, don't patch.** Doubles arrive by constructor or `dependency_overrides`; `patch` is the
exception with a reason attached, targeting the using module's namespace.

**Write the rules into `CLAUDE.md`.** "Fakes from `tests/fakes/`, autospec always, no patching
application modules, no mocking vendor SDKs, assert outcomes" — assistants respect boundary
discipline exactly as far as it's stated.

## Anti-Patterns

**The Hall of Mirrors.** Every collaborator mocked; assertions verify mocks against mocks. The
tell: green suite, broken integration; tests with more patch setup than logic exercised.

**The Agreeable Mock.** Bare `MagicMock` accepting any call, any signature, forever. The tell: a
renamed port method breaks production and zero tests; `spec` appears nowhere in the suite.

**The Choreography Assert.** Interaction assertions where outcomes were available. The tell:
refactors that preserve behavior break tests; suites reading as a call-log transcript.

**The Unbacked Fake.** A doubled boundary no test ever exercises for real. The tell: the fake
encodes decline codes and idempotency semantics nobody has verified against the vendor.

**The Vendor Weld.** Third-party SDK internals patched throughout feature tests. The tell:
`patch("stripe.` outside the adapter's own tests; suite failures on dependency bumps.

**The Patch Maze.** Tests coupled to module paths via deep `patch` strings. The tell: moving a
file breaks thirty tests; patch targets that no longer match any import.

## Decision Tree

"This test has a dependency I can't (or shouldn't) use for real — what do I do?"

```
Is the dependency in-process and deterministic (value object, domain helper, pure fn)?
└── YES ─► use the real thing. No double. (Ch 02: sociable.)

Is it slow, nondeterministic, external, or side-effecting (payment, email, HTTP, clock, disk)?
├── time / randomness ─► inject as parameter or port (Ch 02). No mock needed.
├── owned infrastructure (your DB, your queue) ─► unit tests: in-memory fake;
│                                                 the seam itself: Ch 04 against the real thing.
└── third-party service ─► do you own a port for it?
       ├── NO ──► create one (adapter wraps the SDK). Don't mock what you don't own.
       └── YES ─► double the port:
              used across many tests ────► shared stateful FAKE in tests/fakes/
              one-off query ─────────────► STUB (autospec'd) with canned returns
              void command, no outcome ──► spy / call assertion — sparingly

Writing the double:
    spec it (autospec/spec_set) · script its FAILURE modes, not just success ·
    assert outcomes (state, results), not choreography.

Zoom out: does this boundary have a real test anywhere (adapter/contract, Ch 04)?
└── NO ─► add it. A fake nobody checks is a belief, not a test.
```

## Checklist

### Implementation Checklist

- [ ] Doubles exist only for boundary ports (payment, email, external HTTP, storage, time) — nothing in-process is mocked.
- [ ] Every ad-hoc mock is created with `autospec`/`spec_set` against the port protocol.
- [ ] Hot boundaries use shared stateful fakes from `tests/fakes/`; tests assert outcomes and recorded state.
- [ ] Failure modes are scripted and asserted per boundary: declines, timeouts, duplicates.
- [ ] Doubles arrive by injection (constructor / `dependency_overrides`); any `patch` targets the using module and carries a reason.
- [ ] No test patches third-party SDK internals outside the adapter's own tests.

### Architecture Checklist

- [ ] External dependencies are wrapped in owned ports shaped by the domain, with adapters at the edge (Stage 2, Chapters 05–06).
- [ ] Each doubled boundary is backed by an adapter integration test or a fake-vs-real contract test (Chapter 04).
- [ ] The fake implementations model the behaviors the domain relies on (idempotency, decline reasons), and those claims trace to a verified source.
- [ ] Interaction assertions are rare, deliberate, and confined to genuine void commands.
- [ ] Doubling rules (fakes location, autospec, no vendor mocks, outcome assertions) are recorded in `CLAUDE.md`.

### Code Review Checklist

- [ ] No new mocks of application-internal code — patch targets and doubled objects are boundary ports only.
- [ ] No bare `MagicMock` — every double is spec-bound (watch AI-generated tests closely here).
- [ ] Assertions are on outcomes; any `assert_called_*` has a justification a reviewer can see.
- [ ] New doubled boundaries come with (or link to) their real-side test.
- [ ] Mock setup is per-test — no doubles shared mutably across tests.

## Exercises

**1. Build the fake, break the choreography.** Take a service that charges and emails (or build
Invoicely's `issue_invoice`). Write the suite twice: once with `patch` + interaction assertions,
once with a stateful `FakePaymentGateway` + outcome assertions. Then (a) introduce a bug — charge
the wrong amount — and record which suite catches it; (b) refactor the service's internals and
record which suite breaks. The artifact is the two suites and the 2×2 result.

**2. Hunt the drift.** In an existing suite (or one an assistant generates), find every unspecced
mock. Rename a method on the real interface and count how many tests still pass. Convert the mocks
to `autospec` and repeat. The artifact is the before/after count and the conversion diff.

**3. Write a contract test.** For one boundary with a fake (payments or email), write a single
parametrized test suite that runs against both the fake and the real adapter (vendor test
mode/sandbox): successful call, decline/failure, duplicate request. Every case where they disagree
is a bug in the fake — fix it. The artifact is the contract suite and the divergence list.

## Further Reading

- **"Mocks Aren't Stubs" by Martin Fowler (martinfowler.com)** — the classic taxonomy (dummy, stub,
  fake, spy, mock) and the classicist-vs-mockist distinction underlying this chapter's
  outcomes-over-interactions stance.
- ***Growing Object-Oriented Software, Guided by Tests* by Freeman & Pryce** — the origin of "only
  mock types you own" and of listening to test pain as design feedback; the deepest treatment of
  interaction testing done responsibly.
- **`unittest.mock` documentation — "autospeccing" and "where to patch" (docs.python.org)** — the
  two mechanics that prevent the silent failure modes in this chapter: spec-bound mocks and
  patching the name where it's used.
- **Stage 8, Chapter 04 — Integration Testing** — the other half of every fake: testing the real
  adapters, the real database, and the seams the unit suite deliberately doesn't see.

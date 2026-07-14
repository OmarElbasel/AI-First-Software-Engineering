# Integration Testing

## Introduction

Integration tests verify the seams — the places where your code meets real infrastructure and where
units meet each other: the API route through its middleware to the service, the service through the
ORM to actual PostgreSQL, the job that runs a real query, the adapter that calls the vendor's test
mode. They are the middle of the pyramid: slower than unit tests (real database, real app wiring),
far cheaper than E2E, and the only tests that can catch an entire class of production bugs that unit
tests are structurally blind to.

The single most important idea: **the bugs integration tests exist to catch live in the parts unit
tests replace — so an integration test only counts if the parts are real.** Chapter 01's incident
was a SQL filter: no unit test could see it, because unit tests double the repository. The same is
true of transaction boundaries, constraint violations, JSONB queries, migration mistakes, dependency
wiring, serialization shapes, and auth middleware — all invisible to a suite that mocks the
database, all first-class citizens here. Which is why the cardinal sin of integration testing is
substituting fake infrastructure for real: an "integration" test against SQLite in-memory tests
integration with a database you don't run. Containers made real PostgreSQL in tests cheap (Stage 7,
Chapter 02); there is no longer a good excuse.

The craft is in the harness: standing up a real database per suite (containers), applying the real
migrations to it (not a parallel schema), isolating tests from each other (transactions or
truncation) so a thousand tests share one database without sharing state, and driving the system
the way its clients do — through the HTTP API. Built once in `conftest.py`, the harness makes each
individual test as short as a unit test; built wrong, it produces the slowest, flakiest, most
order-dependent part of the suite.

## Why It Matters

The seams are where systems actually break — and where AI-generated code breaks most:

- **SQL is unfalsifiable from unit tests.** Query filters, joins, constraint interactions,
  `ON DELETE` behavior, transaction isolation — the repository layer's correctness only exists
  against a real database. The Chapter 01 incident (a dropped status filter) is the canonical
  example: twelve unit tests green, production charging paid invoices.
- **Wiring is a bug class of its own.** Dependency injection misconfiguration, middleware order,
  routers not mounted, settings not loaded — each layer can be unit-perfect while the assembled app
  returns 500 on every request. Only a test that boots the real app catches assembly errors.
- **The API contract is what clients actually consume.** Status codes, response shapes, validation
  errors, pagination headers — Stage 3's contract decisions are promises to the frontend and mobile
  apps. Integration tests through HTTP are those promises, executable; unit tests on handlers
  don't serialize, don't validate, and don't run middleware.
- **Migrations only prove themselves by running.** A migration that diverges from the models, or a
  test schema built by `create_all` that never exercises the migration chain, means the first true
  test of your migrations is production deploy night (Stage 6, Chapter 06's nightmare). A harness
  that migrates the test database verifies the chain on every CI run.
- **Dialects differ where it hurts.** SQLite accepts what PostgreSQL rejects and lacks what your
  code depends on — JSONB operators, real constraint enforcement, concurrent transaction semantics,
  case-sensitive `LIKE`. Tests against a substitute database certify behavior your production
  database doesn't have.
- **This is where doubled boundaries get repaid.** Every fake from Chapter 03 is a loan; the
  adapter tests here (Stripe test mode, real SMTP sandbox) are the repayment. Skip them and the
  suite's model of the outside world is unverified belief.

Get it right — real PostgreSQL, real migrations, real app, isolated tests — and green means the
layers actually work together, which is most of what "the system works" means. Get it wrong and
the seams ship untested behind a green suite, surfacing as production incidents that "couldn't
happen — the tests pass."

## Mental Model

Integration tests drive the assembled system through its real entry points, against real
infrastructure, with per-test isolation:

```
  WHAT'S REAL vs DOUBLED — the integration contract
      test ──HTTP──► [ FastAPI app: middleware → routes → DI → services → ORM ]──► PostgreSQL
                                REAL: everything you deploy                        REAL (container)
      doubled: only what leaves your system — payment API, email, third parties
               (their adapters get their own tests against vendor test mode)

  THE HARNESS (built once, in conftest.py)
      1. one real PostgreSQL per suite ─── testcontainers / compose service (Stage 7)
      2. real migrations applied ───────── alembic upgrade head  (never create_all)
      3. isolation per test ────────────── each test in a transaction, rolled back
                                           (or truncate between tests)  → any order, parallel
      4. app with test wiring ──────────── dependency_overrides: auth principal, fakes for
                                           external ports · client = httpx.AsyncClient(app)

  WHAT TO TEST AT THIS LEVEL (the seams, not the matrix)
      per endpoint: the CONTRACT — happy path, authz (401/403/404), validation (422),
                    the response SHAPE clients depend on
      per repository/job: the SQL that has behavior — filters, joins, constraints, transactions
      per adapter:  once, against the vendor's test mode (repays Ch 03's fakes)
      NOT here: logic case matrices — those stay unit tests (Ch 02). one seam test per seam
                behavior, not one per input combination.
```

Three principles carry the chapter:

**Real infrastructure or it isn't integration.** The database is PostgreSQL — the version you run
in production — with your real migration chain applied. The app is the real app object with its
real wiring. The only substitutions are external boundaries you don't deploy, and those are repaid
by adapter tests.

**Isolation is the harness's job, not the test's.** Every test must be able to run alone, in any
order, in parallel — which means no test sees another's rows. Solve it once (transaction-per-test
rollback, or truncation) in fixtures; tests then just create their data and assert.

**Test the seam's behavior, not the logic's matrix.** The fee calculation's thirty cases were
covered in Chapter 02 for microseconds each; here you need the *few* tests that prove the seam —
the endpoint honors its contract, the query filters correctly, the transaction rolls back on
failure. Duplicating the unit matrix at this level buys nothing and costs minutes per run.

A working definition:

> **Integration tests verify the seams — routes, wiring, SQL, transactions, contracts — by driving
> the real assembled application against real infrastructure (actual PostgreSQL, actual
> migrations), with per-test isolation provided by the harness. They double only external
> boundaries, repay those doubles with adapter tests, and leave logic matrices to unit tests.**

## Production Example

**Invoicely's** integration suite is built around the two seams that have already burned the team:
the invoice API contract and the overdue-fee job. The harness boots one PostgreSQL 16 container for
the suite (the production version), applies the real Alembic chain — so a broken migration fails CI
before it fails deploy night — and wraps every test in a rolled-back transaction, so five hundred
tests share the database without ever seeing each other's rows.

The API tests drive the real app through `httpx.AsyncClient`: creating an invoice returns `201`
with the documented shape; a request without a token gets `401`; another tenant's invoice returns
`404` — not `403` — per the Stage 3, Chapter 04 decision not to leak existence; a negative line
quantity gets a `422` with a field-level error the frontend can render. Authentication is handled
at the seam it lives in: `dependency_overrides` swaps the token-validation dependency for a test
principal, because these tests verify the invoice contract, not the JWT parser — the auth
dependency has its own contract tests where real tokens matter.

The job test is the one the Chapter 01 incident demanded: seed one paid, one draft, one disputed,
and two overdue invoices — through the public creation path, not raw inserts — run the real
overdue-fee job against the real database, and assert fees accrued only on the two overdue ones.
That test fails on the dropped `status` filter that all twelve unit mocks missed. Alongside it, the
suite repays Chapter 03's loans: the Stripe adapter runs a handful of tests against Stripe's test
mode (charge, decline, duplicate idempotency key), verifying the assumptions `FakePaymentGateway`
encodes. In this chapter we build the harness and these tests — and contrast them with the
assistant-default version: SQLite in-memory, `create_all`, shared state, green forever.

## Folder Structure

```
api/
├── alembic/                          # the real migration chain — tests run THIS (Stage 6 Ch 06)
├── app/ ...                          # the application under test, unchanged
└── tests/
    ├── integration/
    │   ├── conftest.py               # the harness: pg container, migrations, session-per-test
    │   │                             #   rollback, app client with dependency overrides
    │   ├── api/
    │   │   └── test_invoices_api.py  # the HTTP contract: status codes, authz, shapes, validation
    │   ├── jobs/
    │   │   └── test_overdue_fees_job.py   # the incident test: real query, real states
    │   └── adapters/
    │       └── test_stripe_adapter.py     # vendor test mode — repays the Ch 03 fake (marked/optional)
    └── unit/ ...                     # Ch 02 — no infrastructure fixtures cross this line
```

Why this shape: `integration/` has its own `conftest.py` because the harness *is* the product of
this chapter — container lifecycle, migrations, and isolation live in one place, and no unit test
can accidentally inherit a database fixture. Subfolders follow the seam types (API contract, jobs,
adapters) rather than mirroring every feature, because this level tests seams, not modules. Adapter
tests sit apart and are marked (`@pytest.mark.external`) so the core suite runs with no credentials
and no network, while CI runs the external ring on a schedule — a failing vendor sandbox shouldn't
block every merge.

## Implementation

**The harness: one container, real migrations, per-test rollback.** Built once; every test after
this is short.

```python
# tests/integration/conftest.py
@pytest.fixture(scope="session")
def pg_url() -> str:
    with PostgresContainer("postgres:16") as pg:          # the version production runs
        yield pg.get_connection_url()

@pytest.fixture(scope="session")
def engine(pg_url):
    run_alembic_upgrade(pg_url, "head")                   # the REAL chain — never create_all
    return create_engine(pg_url)

@pytest.fixture
def db_session(engine):
    with engine.connect() as conn:
        outer = conn.begin()                              # everything a test does...
        session = Session(bind=conn, join_transaction_mode="create_savepoint")
        yield session
        session.close()
        outer.rollback()                                  # ...vanishes here. isolation by structure.
```

**The client: the real app, with test wiring at the right seams.** Auth is overridden; external
ports get Chapter 03's fakes; everything else is what you deploy.

```python
@pytest.fixture
def client(db_session) -> Iterator[TestClient]:
    app.dependency_overrides[get_db_session] = lambda: db_session
    app.dependency_overrides[get_current_user] = lambda: TEST_PRINCIPAL          # seam: authn
    app.dependency_overrides[get_payment_gateway] = lambda: FakePaymentGateway() # seam: external
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
```

**API tests: the contract, as a client sees it.** Status codes, shapes, and the authz decisions
Stage 3 made.

```python
# tests/integration/api/test_invoices_api.py
def test_creating_an_invoice_returns_the_documented_shape(client):
    resp = client.post("/api/v1/invoices", json=valid_invoice_payload())

    assert resp.status_code == 201
    body = resp.json()
    assert body["status"] == "draft"
    assert body["total"] == "450.00"                       # money as string — the contract, pinned
    assert resp.headers["Location"] == f"/api/v1/invoices/{body['id']}"

def test_another_tenants_invoice_is_a_404_not_a_403(client, other_tenant_invoice):
    resp = client.get(f"/api/v1/invoices/{other_tenant_invoice.id}")
    assert resp.status_code == 404                         # don't leak existence (Stage 3 Ch 04)

def test_negative_quantity_is_rejected_with_a_field_error(client):
    resp = client.post("/api/v1/invoices", json=invoice_payload(quantity=-1))
    assert resp.status_code == 422
    assert resp.json()["errors"][0]["field"] == "lines.0.quantity"
```

**The job test: the one the incident demanded.** Real states, real query, real database — the test
no mock could be.

```python
# tests/integration/jobs/test_overdue_fees_job.py
def test_fees_accrue_only_on_overdue_invoices(db_session):
    seeded = {
        status: create_invoice(db_session, status=status, due=date(2026, 1, 1))
        for status in ["paid", "draft", "disputed", "overdue", "overdue2"]
    }

    run_overdue_fees_job(db_session, as_of=date(2026, 3, 15))

    with_fees = {k for k, inv in seeded.items() if refresh(db_session, inv).late_fee > 0}
    assert with_fees == {"overdue", "overdue2"}            # fails on the dropped-status-filter bug
```

**The adapter test: repaying the fake.** Marked external; run on schedule, not on every merge.

```python
# tests/integration/adapters/test_stripe_adapter.py
@pytest.mark.external
def test_duplicate_idempotency_key_does_not_double_charge(stripe_test_gateway):
    first = stripe_test_gateway.charge(customer_id=TEST_CUSTOMER, amount=Money("10.00", "USD"),
                                       idempotency_key="itest-dup-1")
    second = stripe_test_gateway.charge(customer_id=TEST_CUSTOMER, amount=Money("10.00", "USD"),
                                        idempotency_key="itest-dup-1")
    assert second.charge_id == first.charge_id             # the behavior FakePaymentGateway claims
```

The suite this produces is small and dense: a contract file per API resource, one test per seam
behavior, the job tests that touch real SQL, and a thin external ring keeping the fakes honest —
minutes to run, and every test proving something no unit test could.

## Engineering Decisions

Five decisions define an integration harness.

### Real PostgreSQL or a lighter substitute?

**Options:** (1) SQLite in-memory; (2) real PostgreSQL in a container (testcontainers / compose
service); (3) a shared long-lived test database.

**Trade-offs:** SQLite is instant and free — and it's a different database: constraint enforcement,
JSONB, transaction semantics, case sensitivity, and type coercion all differ, so tests certify
behavior production doesn't have and miss behavior it does. Containers cost seconds of startup per
suite and give you the exact engine and version you deploy. A shared test database avoids startup
cost and accumulates state, drifts, and couples every developer and CI run to one mutable instance.

**Recommendation:** real PostgreSQL, production's major version, in a container started by the
suite (session-scoped fixture locally, a service container in CI — Stage 7, Chapter 05). The
startup seconds are amortized over the whole suite. SQLite is acceptable only when it's your
production database, which for this handbook's stack it never is.

### How do tests stay isolated from each other?

**Options:** (1) transaction-per-test — run each test inside a transaction and roll back;
(2) truncate all tables between tests; (3) fresh database/schema per test; (4) nothing — shared
state and hope.

**Trade-offs:** rollback is the fastest (nothing to clean) and is structural — state *cannot* leak —
but it can't test code that itself commits or must observe another connection's commits. Truncation
is slightly slower, works with real commits, and needs the table list maintained. Fresh-DB-per-test
is bulletproof and far too slow as a default. Shared state is the flaky, order-dependent suite of
Chapter 01.

**Recommendation:** transaction-per-test rollback (the savepoint pattern above) as the default —
fast and impossible to leak. Fall back to truncation for the handful of tests that genuinely
exercise commit behavior or cross-connection visibility. Never share state: any test that depends
on another test's rows is a bug, and running the suite in random order enforces that.

### Where does the test schema come from?

**Options:** (1) `Base.metadata.create_all()` from the models; (2) the real Alembic migration
chain; (3) a maintained SQL dump restored per suite.

**Trade-offs:** `create_all` is fast and convenient and tests a schema production never has — the
migration chain itself goes unverified, and models-vs-migrations drift ships silently until deploy.
Running migrations tests the artifact that actually runs in production and costs a few seconds per
suite (more as the chain grows). A dump is fast to restore and is a third artifact that itself
drifts.

**Recommendation:** run the real migration chain (`alembic upgrade head`) in the session fixture.
This makes every CI run a rehearsal of deploy night (Stage 6, Chapter 06) and catches
models-vs-migrations drift for free — add the cheap guard that compares metadata after upgrade.
When the chain grows long enough to hurt, snapshot a migrated dump *derived from the chain* and
keep one job that still runs the chain from zero.

### How is authentication handled in API tests?

**Options:** (1) run the real auth path with real signed tokens per test; (2) override the auth
dependency with a test principal; (3) disable auth in a test setting.

**Trade-offs:** real tokens exercise the most and make every invoice test also a JWT test — slow,
noisy failures, and fixture ceremony everywhere. Overriding the dependency keeps each test focused
on its own contract and leaves the auth path untested *if you stop there*. A global auth-off
setting is a config divergence between test and production, and a terrifying flag to have exist.

**Recommendation:** override the authentication dependency with a test principal for resource
tests — authorization (tenancy, ownership, roles) stays real and tested, because it lives below the
override. Then test the authentication seam itself, directly and thoroughly, in its own file with
real tokens: valid, expired, tampered, wrong audience. Never ship a setting that disables auth;
overrides exist only in the test process.

### What belongs at this level — and through which entry point?

**Options:** (1) drive everything through HTTP; (2) test services/repositories directly through
their Python interfaces; (3) both, chosen by what the seam is.

**Trade-offs:** HTTP-only exercises the full stack including serialization and middleware, and gets
slow and awkward for jobs, repository edge cases, and error injection. Service-level tests are
faster and skip the contract layer — which is where a class of bugs lives. Testing both
indiscriminately duplicates coverage and doubles maintenance.

**Recommendation:** choose the entry point by what the test proves. Contracts (status codes,
shapes, authz responses, validation) go through HTTP — that's what a contract is. SQL behavior
(repositories, jobs, transactions) goes through the owning service or job entry point — HTTP adds
nothing to a query-filter test. Keep one smoke test that boots the whole app and hits a health
endpoint, so pure assembly errors fail fast and unambiguously.

## Trade-offs

Integration tests buy reality; the currency is time and machinery.

**Real infrastructure trades suite speed for a class of bugs nothing else catches.** A container
boot and a migration run cost tens of seconds once, and each test costs milliseconds-to-tens more
than a unit test. What that buys — SQL, wiring, contracts, migrations verified on every commit — is
the exact bug class behind most "how did the tests pass?" incidents. The mitigation is scope
discipline: seams here, matrices in Chapter 02.

**The harness trades upfront complexity for per-test simplicity.** Containers, migration hooks,
savepoint rollbacks, and override wiring are genuinely fiddly to build — once. Afterward each test
is five lines. Teams that skip the investment pay per-test instead: hand-rolled cleanup, shared
fixtures, and the flaky suite that follows.

**Rollback isolation trades a blind spot for structural safety.** Transaction-per-test cannot
observe real commit behavior — a small, known hole covered deliberately by a few truncation-based
tests — in exchange for making state leakage impossible rather than merely discouraged.

**The external ring trades merge-blocking coverage for stability.** Keeping vendor-sandbox tests
out of the per-merge suite means a Stripe assumption could drift for hours before the scheduled run
catches it; putting them in means every merge inherits the sandbox's uptime and latency. Scheduled
is the right default — drift is measured in days, merges in minutes.

## Common Mistakes

**Integration tests against a different database.** SQLite standing in for PostgreSQL; green tests,
untested production behavior. Fix: containerized PostgreSQL, production's version — the cost
argument died with testcontainers.

**`create_all` instead of migrations.** The test schema is born from models; the migration chain —
the thing that actually runs against production — is never executed. Fix: `alembic upgrade head` in
the harness; assert models and migrated schema agree.

**Shared state between tests.** Seed data mutated across tests; the suite passes in order and
collapses shuffled or parallel. Fix: per-test rollback or truncation in fixtures; random order in CI.

**Re-testing the unit matrix over HTTP.** Thirty fee cases driven through the API at 50ms each,
duplicating Chapter 02. Fix: seams here, matrices there; one contract test per behavior.

**Seeding through raw inserts.** Test data written straight to tables, bypassing validation and
defaults — testing states the application can't produce. Fix: seed through the public creation
path (API or service), dropping to inserts only to construct legacy/corrupt states deliberately.

**Asserting on incidental response detail.** Pinning field order, timestamps, or entire JSON bodies,
so every additive change breaks tests. Fix: assert the fields that are the contract; tolerate
additions unless the contract forbids them.

## AI Mistakes

Integration harnesses are where assistants cut the corners that matter most, because the shortcuts
all *run*: a fake database runs, `create_all` runs, shared state runs. Review the harness — the
`conftest`, not the tests — hardest.

### Claude Code: quietly substituting SQLite for the real database

Asked to "add integration tests," Claude Code frequently generates the classic pytest recipe: a
`sqlite:///:memory:` engine, `create_all`, and a session fixture. It runs anywhere with zero setup —
and it silently un-integrates the tests: PostgreSQL constraints, JSONB operators, transaction
semantics, and dialect behavior are all untested, while the suite reports green integration
coverage the codebase doesn't have.

**Detect:** `sqlite` in any connection string under `tests/integration/`; conditional
"TESTING" engine URLs in app config; tests passing without Docker available when the harness
supposedly uses containers; JSONB/array/constraint-dependent code with green "integration" tests.

**Fix:** pin the infrastructure in the prompt and the review:

> Integration tests must run against real PostgreSQL 16 via testcontainers (session-scoped
> fixture) — no SQLite anywhere under tests/integration/. Apply the real Alembic chain, not
> create_all. If Docker isn't available, the tests should fail loudly, not fall back to a
> different database.

### GPT: `create_all` and a parallel schema — the migration chain never runs

GPT-family models default to building the test schema from the models (`Base.metadata.create_all`)
and often add test-only fixture tables or columns — producing a schema that resembles production
but wasn't produced the way production's is. The migration chain, the artifact that will actually
run at deploy, is never executed by any test; models-vs-migrations drift accumulates invisibly
until deploy night.

**Detect:** `create_all` in integration fixtures; no `alembic` invocation anywhere in the test
tree; migrations that fail when run from zero on a fresh database even though CI is green; schema
elements present in tests that no migration creates.

**Fix:** make migrations the only source of schema:

> The test database schema must come from `alembic upgrade head` — the same chain production runs.
> No `create_all`, no test-only DDL. Add an assertion that the migrated schema matches the model
> metadata, so drift fails the build.

### Cursor: state leaking through the harness — tests coupled by database residue

Completing tests in an existing file, Cursor follows local patterns without the isolation the
harness assumed: committing inside tests that the rollback fixture can't undo, module-scoped
sessions reused across tests, seed helpers that check-then-create ("get or create") so later tests
silently depend on earlier tests' rows. The suite passes in file order today; three weeks later a
reordering or parallelization makes it fail in ways nobody can reproduce locally.

**Detect:** `session.commit()` inside tests using the rollback fixture; fixtures scoped
`module`/`session` yielding database sessions or created rows; get-or-create seed helpers;
failures that appear only with `-p randomly`, `-n auto`, or when running a file alone.

**Fix:** make isolation structural and verified:

> Every test gets its own transaction-wrapped session from the harness fixture and creates its own
> data — no module-scoped sessions, no get-or-create seeding, no commits the fixture can't roll
> back. Run the suite with randomized order and parallel workers and confirm it passes before
> finishing.

## Best Practices

**Make the harness real: containerized PostgreSQL, real migrations.** Production's engine and
version, `alembic upgrade head`, a drift check between models and migrated schema — every CI run
rehearses deploy.

**Isolate structurally.** Transaction-per-test rollback as the default, truncation for genuine
commit-behavior tests, randomized order and parallel workers in CI to keep everyone honest.

**Test contracts through HTTP, SQL through its owner.** Status codes, shapes, authz, and validation
via the real client; repository and job behavior via their entry points; one boot-and-health smoke
test for assembly.

**Seed through the front door.** Create test data via the API or service layer so it's data the
application can actually produce; reserve raw inserts for deliberately constructing legacy states.

**Ring-fence the external tests.** Adapter tests against vendor test modes are marked, credentialed,
and scheduled — they repay Chapter 03's fakes without putting a vendor sandbox on your merge path.

**Write the harness rules into `CLAUDE.md`.** "Real Postgres via testcontainers, migrations not
create_all, rollback isolation, no SQLite, seed via the API" — the assistant shortcuts are known;
name them before they're taken.

## Anti-Patterns

**The Fake Integration.** "Integration" tests against SQLite or mocked sessions. The tell:
`sqlite:///:memory:` in the integration tree; tests pass without Docker; JSONB code, green suite.

**The Parallel Schema.** Test schema from `create_all` while production's comes from migrations.
The tell: no alembic call in the test tree; a fresh-database migration run fails while CI is green.

**The Residue Suite.** Tests coupled through leftover rows and shared sessions. The tell: passes in
order, fails shuffled or parallel; get-or-create seed helpers.

**The HTTP Matrix.** Unit-level case matrices re-run through the API. The tell: dozens of
input-variation tests per endpoint; suite runtime growing with logic complexity, not seam count.

**The Backdoor Seed.** Fixtures inserting raw rows that bypass validation. The tell: tests
exercising states no API call can create; column defaults and constraints untested.

**The Sandbox on the Merge Path.** Vendor-dependent tests gating every PR. The tell: merges blocked
by third-party sandbox outages; retries normalized for "the Stripe tests."

## Decision Tree

"I need to verify a behavior at a seam — how do I test it here?"

```
What kind of seam is it?
├── the HTTP contract (codes, shapes, authz, validation)
│      └─► through the real client (httpx/TestClient), real app wiring.
│          auth: override the authn dependency; authz stays real.
│          one test per contract behavior — the input matrix lives in Ch 02.
├── SQL behavior (query filters, joins, constraints, transactions, jobs)
│      └─► through the owning service/job entry point, against container Postgres.
│          needs real commit / cross-connection visibility?
│          ├── NO ──► default rollback isolation.
│          └── YES ─► truncation-based test, explicitly marked.
├── the wiring itself (app boots, DI resolves, middleware ordered)
│      └─► one smoke test: boot app, hit /health, assert 200.
└── a third-party adapter (Stripe, SMTP, S3)
       └─► vendor test mode, @pytest.mark.external, scheduled in CI —
           this is what keeps the Ch 03 fake honest.

Harness checkpoints (before writing any test):
    real PostgreSQL, prod version? · schema via alembic upgrade head?
    per-test isolation structural? · suite passes shuffled AND parallel?
    └── any NO ─► fix the harness first. Tests on a broken harness are debt.
```

## Checklist

### Implementation Checklist

- [ ] Integration tests run against containerized PostgreSQL matching production's major version — no SQLite, no shared mutable test database.
- [ ] The test schema is produced by `alembic upgrade head`; a drift check asserts models and migrated schema agree.
- [ ] Every test is isolated (rollback or truncation via fixtures) and the suite passes with randomized order and parallel workers.
- [ ] Each endpoint's contract is tested through HTTP: success shape, 401/403/404 behavior, validation errors clients can render.
- [ ] SQL-bearing code (repositories, jobs) has tests seeding realistic states through the public creation path.
- [ ] Each Chapter 03 fake is repaid by an adapter test against the vendor's test mode, marked external.

### Architecture Checklist

- [ ] Authn is overridden at its dependency seam in resource tests; the auth seam itself has dedicated real-token tests; no auth-disabling setting exists.
- [ ] External ports are overridden with the shared fakes; nothing else in the app is doubled.
- [ ] Entry points match the seam: contracts via HTTP, SQL via owning services, assembly via a smoke test — no duplicated unit matrices.
- [ ] The external test ring is credentialed, marked, and scheduled off the merge path.
- [ ] Harness rules (real Postgres, migrations, isolation, seeding) are recorded in `CLAUDE.md`.

### Code Review Checklist

- [ ] No new test depends on another test's data, commits outside the fixture's control, or widens a fixture's scope past function.
- [ ] New/changed endpoints arrive with contract tests including the failure statuses, not just 200s.
- [ ] Changed queries and jobs have integration tests covering the states the query must include *and exclude* (watch AI diffs for dropped filters).
- [ ] Response assertions pin the contract fields, not incidental body detail.
- [ ] No SQLite, `create_all`, or raw-insert seeding slipped into the integration tree (the three AI shortcuts — check the conftest diff).

### Deployment Checklist

- [ ] CI runs the integration suite against a PostgreSQL service container of the production version on every merge (Stage 7, Chapter 05).
- [ ] The migration chain runs from zero in CI, so a broken chain fails the pipeline, not the deploy.
- [ ] The external adapter ring runs on a schedule with alerting, using vendor test-mode credentials stored as CI secrets.
- [ ] Integration suite runtime is tracked; parallelism is added before the suite becomes slow enough to skip.

## Exercises

**1. Build the harness, then prove the isolation.** Stand up the full harness for a FastAPI + SQLAlchemy
app: PostgreSQL container, Alembic migrations, rollback-per-test, overridden auth. Then prove it:
run the suite shuffled (`-p randomly`) and parallel (`-n auto`), and write one deliberately leaking
test (module-scoped session, committed row) to watch the failure mode before deleting it. The
artifact is the conftest and the shuffled/parallel run logs.

**2. Write the incident test.** Take the overdue-fee job (or any state-filtered bulk query in your
codebase). Seed every state through the public path, run the job, and assert the exact
include/exclude sets. Then reintroduce the Chapter 01 bug — drop the status filter — and confirm
this test fails while the unit suite stays green. The artifact is the test and the two runs.

**3. Repay a fake.** Pick one boundary you double (payments or email). Write the external adapter
test against the vendor's test mode covering success, failure, and duplicate/idempotent calls, and
run it against both the real adapter and the fake (Chapter 03's contract pattern). Fix every
divergence in the fake. The artifact is the test and the divergence list.

## Further Reading

- **Testcontainers for Python documentation (testcontainers-python.readthedocs.io)** — the
  container-per-suite pattern this chapter's harness is built on; modules for PostgreSQL, Redis,
  and the rest of the Stage 7 stack.
- **FastAPI documentation — "Testing" and "Testing Dependencies with Overrides"
  (fastapi.tiangolo.com)** — the official mechanics for the client and the dependency-override
  seams used throughout this chapter.
- **SQLAlchemy documentation — "Joining a Session into an External Transaction"
  (docs.sqlalchemy.org)** — the savepoint/rollback isolation recipe, with the details that make it
  work when application code itself commits.
- **Stage 6, Chapter 06 — Migrations & Schema Evolution** — why the migration chain is the artifact
  worth testing, and the deploy-night failure modes this harness turns into CI failures.

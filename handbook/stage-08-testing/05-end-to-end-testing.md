# End-to-End Testing

## Introduction

End-to-end tests drive the whole system the way a user does: a real browser, the real frontend,
the real API, the real database — a complete journey from click to persisted outcome. They sit at
the top of the pyramid and they are the only tests that answer the question every other level
assembles toward: *does the product actually work?* A unit suite proves the fee math; the
integration suite proves the API contract; neither proves that a customer can open the app, click
"Pay," and end up with a paid invoice. E2E does.

The single most important idea: **E2E coverage is expensive real estate — spend it on the few
journeys the business cannot survive breaking, and make those tests boringly stable.** Every E2E
test costs seconds-to-minutes per run, a full environment to exist in, and a standing flake risk
(browsers, rendering, and networks are the least deterministic layer you will ever test). Those
costs don't argue against E2E — they argue against *indiscriminate* E2E. A suite of eight rock-solid
journey tests that gate every deploy is one of the highest-value assets a product team owns. A
suite of three hundred brittle page tests, red half the time for reasons nobody investigates, is
how Chapter 01's trust budget goes bankrupt fastest.

The craft is stability engineering: selecting by what the user sees (roles and labels) instead of
how the DOM happens to be shaped, waiting on conditions instead of on clocks, giving every test its
own data and its own authenticated session instead of inheriting a shared environment's residue,
and treating every flake as a defect. Playwright — this chapter's tool — was built around exactly
these disciplines; the failures come from not using them.

## Why It Matters

E2E is where the system is finally tested as the thing users experience — and where careless suites
do the most damage:

- **Whole classes of failure exist only end-to-end.** The frontend calling a renamed field, a CORS
  or cookie misconfiguration, a broken build artifact, an environment variable missing in the
  deployed stack, a redirect loop after login — every layer's tests pass while the *product* is
  down. Only a test that uses the product can see it.
- **The frontend–backend contract needs one live proof.** Stage 4's client and Stage 3's API each
  test their own side of the contract; E2E is where a mismatch — a date serialized differently, a
  pagination shape misread — actually surfaces before a user finds it.
- **Deploys need a go/no-go signal.** Stage 7's pipeline can build, migrate, and deploy — and the
  most valuable minutes in that pipeline are the E2E journeys running against the freshly deployed
  stack. "Sign up, issue an invoice, pay it" passing is a deploy verdict no dashboard equals.
- **Flaky E2E is the leading cause of ignored suites.** Browser tests are the flakiest layer by
  nature, and re-run culture starts here before it spreads. The trust budget argument from
  Chapter 01 applies with the highest stakes and the least slack.
- **Cost scales with count, brutally.** At three minutes per journey, thirty journeys is a
  ninety-minute gate — which gets parallelized, then sampled, then skipped. Selection discipline
  isn't a preference; it's what keeps E2E in the merge path at all.
- **AI-generated E2E is brittle by default.** Assistants write selectors from the DOM they can see
  (classes, structure), wait with sleeps, and chain tests into serial stories — the exact trio of
  failure modes this chapter's discipline exists to prevent.

Get it right — few journeys, user-facing selectors, condition-based waits, isolated data, zero
tolerated flakes — and E2E is the deploy gate that lets everything else move fast. Get it wrong
and it's the slowest, least trusted part of the pipeline, teaching the team that red means re-run.

## Mental Model

E2E is a small portfolio of user journeys, engineered for stability:

```
  WHAT ONE E2E TEST IS
      real browser ──► real frontend ──► real API ──► real DB    (the deployed compose stack)
      driving a JOURNEY: signup → create customer → issue invoice → see it paid
      asserting what the USER can see — and, where money moved, what the system persisted

  SELECTION — the only journeys that earn a slot
      "if this breaks, the business stops":  sign up / log in · the core value loop
      (issue an invoice) · the money path (pay an invoice)
      everything else ─► push DOWN the pyramid (Ch 02–04). when in doubt: no.

  STABILITY ENGINEERING (what separates an asset from a flake farm)
      selectors  role/label/testid — what the user perceives   (never CSS chains / nth-child)
      waiting    web-first assertions that auto-retry           (never sleep(3000))
      data       each test SEEDS ITS OWN via the API            (never environment residue)
      auth       login once per worker → storageState           (never UI login in every test)
      isolation  any test runs alone, in parallel, repeatedly   (never test B needs test A)

  FLAKE POLICY (the trust budget, enforced)
      flake = defect. trace/video → diagnose → fix root cause, or quarantine + ticket.
      retries exist to CLASSIFY (pass-on-retry = flaky = investigate), not to tolerate.
```

Three principles carry the chapter:

**Test journeys, not pages.** An E2E slot is earned by a business-critical *flow* with an outcome —
an invoice exists, a payment settled — not by a page rendering. Page-level behavior (validation
messages, component states) belongs to cheaper levels; the journey test passes through those
surfaces without re-testing them.

**Interact like a user, assert like a user.** Locate elements by role, label, and visible text —
the things a user perceives — and assert on visible outcomes with auto-retrying assertions. A test
written this way survives redesigns that preserve the experience and fails when the experience
breaks: exactly the sensitivity profile you want.

**Own your state.** Every test creates its own tenant, customer, and invoice through the API in
seconds, and authenticates through a shared saved session. Tests that borrow state — from other
tests, from a shared staging database, from "the demo account" — inherit every other borrower's
bugs and schedule.

A working definition:

> **E2E tests drive the few business-critical user journeys through the real deployed stack in a
> real browser, asserting user-visible outcomes. They earn their cost through selection (journeys
> the business dies without), stability (semantic selectors, condition-based waits, per-test data
> and auth), and policy (every flake is a defect). They are the deploy gate, not the pyramid.**

## Production Example

**Invoicely's** E2E suite is eight tests covering the three journeys the business cannot survive
breaking: onboarding (sign up, land in an empty dashboard), the value loop (create a customer,
issue an invoice, see it in the list with the right total), and the money path (open the payment
link as the customer, pay with a test card, watch the invoice flip to paid — and verify via the API
that the charge was recorded once). Every other flow the product has — filtering, settings, PDF
downloads, reminders — is deliberately *not* here; each is covered at the level its failures live
(Chapters 02–04), and the temptation to add "just one more journey" is treated as a budget request.

The suite runs against the same Compose stack Stage 7 deploys — frontend, API, PostgreSQL, and the
fake payment gateway wired in at the API's port seam (Chapter 03), so "pay" exercises the real UI
and the real API without a vendor sandbox on the merge path. Stability is engineered, not hoped
for: a setup project signs up once per worker and saves `storageState`, so tests start
authenticated without repeating the login UI; each test creates its own customer and invoice
through the API in a fixture (two seconds) rather than clicking through creation forms it isn't
testing; every locator is `getByRole`/`getByLabel`/`getByTestId`; every assertion is web-first and
auto-retrying — the suite contains no `waitForTimeout` at all.

In CI (Stage 7, Chapter 05) the journeys run on every merge against the freshly built stack, with
traces and videos retained on failure; a pass-on-retry is reported as a flake and ticketed, not
celebrated. In this chapter we build this suite — config, auth setup, seeding fixtures, and the
payment journey — and contrast it with the assistant-default version: CSS-chain selectors,
`sleep(3000)` between steps, and a test file that only passes when run top to bottom.

## Folder Structure

```
e2e/
├── playwright.config.ts          # projects (setup → chromium), retries, trace-on-failure, baseURL
├── setup/
│   └── auth.setup.ts             # signs up / logs in ONCE per worker → .auth/user.json
├── fixtures/
│   └── seeded.ts                 # test fixtures: apiClient + per-test tenant/customer/invoice via API
├── journeys/
│   ├── onboarding.spec.ts        # sign up → empty dashboard
│   ├── invoicing.spec.ts         # create customer → issue invoice → visible, correct total
│   └── payment.spec.ts           # open payment link → pay → invoice paid, charged exactly once
└── .auth/                        # saved storageState (gitignored)
```

Why this shape: `e2e/` lives at the repo root, not inside the frontend — these tests exercise the
whole product, and the CI job that runs them boots the whole stack. `setup/` and `fixtures/` are
where the stability engineering is concentrated: auth state and data seeding are solved once, so
journey specs contain only journey. `journeys/` is deliberately flat and small — the folder listing
*is* the E2E budget, and a PR adding a ninth file should read as a budget decision. The `.auth/`
directory holds per-run session state and never enters version control.

## Implementation

**The config: stability policy as code.** Retries classify flakes; traces make them debuggable;
projects run auth setup before journeys.

```typescript
// e2e/playwright.config.ts
export default defineConfig({
  testDir: "./journeys",
  retries: process.env.CI ? 1 : 0,          // a pass-on-retry is REPORTED as flaky, then ticketed
  use: {
    baseURL: process.env.E2E_BASE_URL ?? "http://localhost:3000",
    trace: "retain-on-failure",             // full trace for every failure — no "works on my machine"
    video: "retain-on-failure",
  },
  projects: [
    { name: "setup", testDir: "./setup", testMatch: /auth\.setup\.ts/ },
    { name: "chromium", use: { ...devices["Desktop Chrome"], storageState: ".auth/user.json" },
      dependencies: ["setup"] },
  ],
});
```

**Auth once, not per test.** The setup project logs in through the real UI a single time — that
*is* the onboarding journey — and every other test starts already authenticated.

```typescript
// e2e/setup/auth.setup.ts
setup("sign up and persist session", async ({ page }) => {
  await page.goto("/signup");
  await page.getByLabel("Work email").fill(workerEmail());
  await page.getByLabel("Password").fill(TEST_PASSWORD);
  await page.getByRole("button", { name: "Create account" }).click();
  await expect(page.getByRole("heading", { name: "Dashboard" })).toBeVisible(); // journey asserted
  await page.context().storageState({ path: ".auth/user.json" });
});
```

**Seed through the API, not the UI.** A fixture gives every test its own data in seconds; the UI is
only driven where the UI is the thing under test.

```typescript
// e2e/fixtures/seeded.ts
export const test = base.extend<{ seededInvoice: Invoice }>({
  seededInvoice: async ({ request }, use) => {
    const customer = await api(request).createCustomer({ name: "Acme GmbH" });
    const invoice = await api(request).createInvoice({
      customerId: customer.id,
      lines: [{ description: "Consulting — March", quantity: 10, unitPrice: "120.00" }],
    });
    await use(invoice);                      // per-test data: no residue, parallel-safe
  },
});
```

**The money journey: user-visible steps, user-visible asserts — plus one system-level check.**
Web-first assertions auto-retry until the condition holds; there is nothing to sleep for.

```typescript
// e2e/journeys/payment.spec.ts
test("customer pays an invoice and it settles exactly once", async ({ page, request, seededInvoice }) => {
  await page.goto(`/pay/${seededInvoice.paymentLinkToken}`);

  await expect(page.getByText("Acme GmbH")).toBeVisible();
  await expect(page.getByTestId("amount-due")).toHaveText("€1,200.00");   // testid where text is dynamic

  await page.getByLabel("Card number").fill("4242 4242 4242 4242");
  await page.getByLabel("Expiry").fill("12/28");
  await page.getByLabel("CVC").fill("123");
  await page.getByRole("button", { name: "Pay €1,200.00" }).click();

  await expect(page.getByRole("status")).toHaveText("Payment received");  // auto-waits — no sleep
  await page.goto(`/invoices/${seededInvoice.id}`);
  await expect(page.getByTestId("invoice-status")).toHaveText("Paid");

  const charges = await api(request).chargesFor(seededInvoice.id);        // the money assertion:
  expect(charges).toHaveLength(1);                                        // paid once, not twice
});
```

**The anti-example — every stability sin in twelve lines.** This is what "it works when I run it"
looks like:

```typescript
// ANTI-PATTERN: structural selectors, hard sleeps, and dependence on the previous test's data.
test("pay", async ({ page }) => {
  await page.goto("/invoices");
  await page.waitForTimeout(3000);                                   // hope the list loaded
  await page.click("div.list > div:nth-child(1) > button.btn-blue"); // whatever is first, whatever blue is
  await page.waitForTimeout(5000);                                   // hope payment finished
  expect(await page.$(".success")).not.toBeNull();                   // no retry, no message check
});  // passes only after "create invoice" ran first — and randomly even then
```

The difference is the whole chapter: the good journey reads as the user's experience — labels,
buttons, visible outcomes — owns its data, waits on conditions, and adds one system-level assertion
where money is involved. The bad one encodes the current DOM, the current timing, and the previous
test — three dependencies the product never promised to keep.

## Engineering Decisions

Five decisions define an E2E suite.

### Which journeys get an E2E test?

**Options:** (1) every user-facing flow ("test like a user" taken literally); (2) only a smoke test
(login and a health page); (3) the business-critical journeys, capped and curated.

**Trade-offs:** everything-E2E duplicates the lower pyramid at hundreds of times the cost and
produces the ninety-minute flaky gate that eventually gets skipped. Smoke-only is cheap and misses
the money path — the one journey whose breakage is an incident by definition. The curated set costs
a real selection argument (and the discipline to say no) and keeps E2E fast enough to gate every
deploy.

**Recommendation:** derive the list from Chapter 01's critical-behavior map: the journeys whose
failure stops the business — onboarding, the core value loop, the money path. Cap the suite
(Invoicely: eight tests) and treat additions as budget decisions requiring a removal or a
justification. Everything else is pushed down the pyramid by default.

### What stack do the tests run against?

**Options:** (1) the local/CI Compose stack, built from the branch; (2) a shared staging
environment; (3) production (as post-deploy smoke).

**Trade-offs:** the branch-built stack is hermetic and parallel-safe and doesn't prove the deployed
environment (DNS, TLS, real config). Shared staging adds environment realism and inherits shared
mutable state, other teams' deploys, and scheduling conflicts — the classic source of "not our
test's fault" failures. Production smoke proves the thing itself and must be read-only-ish and
minimal (test tenant, no destructive flows).

**Recommendation:** layered: the full journey suite runs on every merge against the Compose stack
CI builds from the branch (same images Stage 7 deploys — Chapter 05's pipeline), and a two-test
smoke (login, issue-and-void a test-tenant invoice) runs against production after every deploy.
Avoid parking the suite on a shared staging environment; hermeticity is worth more than its extra
realism.

### How do tests find elements?

**Options:** (1) CSS/XPath structural selectors; (2) user-facing locators — role, label, text;
(3) `data-testid` everywhere.

**Trade-offs:** structural selectors require no app changes and weld tests to today's DOM — any
refactor, restyle, or library upgrade breaks them without breaking the product. Role/label locators
track what users perceive, survive markup changes, and double as an accessibility check (if
`getByRole` can't find your button, neither can a screen reader — Stage 4, Chapter 06). Test IDs
are fully decoupled from both structure and copy, and they're invisible to users — a test passing
via testids can't tell you the label is gone.

**Recommendation:** `getByRole`/`getByLabel`/`getByText` first — the test then asserts the
accessible, visible experience. Add `data-testid` for elements with no stable semantic handle
(dynamic totals, status chips). Never accept structural selectors in review; they are the single
largest source of E2E brittleness.

### How do tests get authentication and data?

**Options:** (1) each test drives signup/login and creates its data through the UI; (2) auth once
per worker via `storageState`, data seeded per test through the API; (3) a pre-seeded shared
account everyone borrows.

**Trade-offs:** all-through-the-UI re-tests login and creation forms hundreds of times, multiplies
runtime, and puts every journey downstream of the signup form's stability. StorageState + API
seeding starts every test authenticated with its own data in seconds; the login UI itself is still
covered — once, in the setup/onboarding journey. The shared account is the residue suite:
parallel-unsafe, order-dependent, and polluted by every previous run.

**Recommendation:** option 2, structurally: a setup project that performs the real signup/login
journey and saves `storageState`; fixtures that seed per-test tenants and invoices through the API.
The UI is driven exactly where the UI is under test. No test ever depends on data it didn't create.

### What is the policy when a test flakes?

**Options:** (1) retry until green and move on; (2) delete flaky tests on sight; (3) retries as
detection, plus mandatory diagnosis — fix or quarantine with a ticket.

**Trade-offs:** silent retries convert flakes into invisible noise and train the re-run culture —
and they hide real intermittent bugs (races in the app flake first, fail-for-users second).
Deletion keeps the suite green by shrinking what it proves. Detection-plus-diagnosis costs
engineering time per flake and is the only option under which the suite's signal survives; traces
and videos make the diagnosis affordable.

**Recommendation:** CI retries of exactly one, with pass-on-retry *reported* — Playwright flags
flaky results — and a standing rule: every flaky result gets a ticket, and the test is quarantined
(skipped, visibly) until root-caused. Budget real time for it; a meaningful share of E2E flakes are
application bugs (unawaited updates, race conditions) caught early. The main suite stays at zero
tolerated flakes, per Chapter 01.

## Trade-offs

E2E buys the highest confidence per test and charges for it in every dimension.

**Whole-system confidence trades against everything else.** One journey test proves more of the
product than a hundred unit tests — and costs minutes, an environment, and standing flake risk. The
resolution is the pyramid's, applied at the top: buy this confidence only for the journeys that
justify the price, and keep buying the cheap kind below for everything else.

**Hermetic stacks trade environment realism for determinism.** Running against the branch-built
Compose stack means DNS, TLS, CDN, and production config are out of frame — covered only by the
thin post-deploy smoke. The alternative (staging) trades that gap for shared-state flakiness, which
costs more, more often.

**User-facing locators trade precision for meaning.** `getByRole("button", { name: "Pay" })` can
match a redesigned button that a pixel-perfect selector would miss — the test is asserting the
experience, not the markup. Occasionally that means adding a testid where semantics are ambiguous;
that cost is the accessibility signal working as intended.

**The fake gateway on the merge path trades payment realism for reliability.** Paying with
Chapter 03's fake keeps vendor sandboxes off every merge; the real Stripe integration is covered by
the adapter ring (Chapter 04) and the production smoke's test-mode transaction. The seam is
deliberate: realism where it's cheap and scheduled, determinism where it gates.

## Common Mistakes

**Structural selectors.** CSS chains and `nth-child` welded to today's DOM. Fix: role/label/text
locators, testids for the rest; treat selector brittleness as a review blocker.

**Sleeping instead of waiting.** `waitForTimeout` guessing at load times — too short flakes, too
long accumulates into the slow suite. Fix: web-first auto-retrying assertions on visible
conditions; zero fixed sleeps.

**Journeys chained into a story.** Test 3 pays the invoice test 2 issued for the customer test 1
created; nothing runs alone or in parallel. Fix: per-test seeding through the API; any test runs in
isolation, in any order.

**Testing everything through the browser.** Validation matrices and component states re-verified at
minutes per case. Fix: push down the pyramid; E2E slots are for journeys with business-critical
outcomes.

**UI-driving all setup.** Every test signing up and clicking through creation forms it isn't
testing. Fix: `storageState` auth, API seeding; drive the UI only where the UI is under test.

**Asserting only the happy pixel.** Checking a success toast but not the outcome — the invoice
paid, the charge recorded once. Fix: assert the user-visible result *and*, for money paths, the
persisted state via the API.

## AI Mistakes

E2E is where assistant-generated tests look most convincing — the script visibly drives a browser —
while embedding the three classic instabilities. Every one runs green on the machine that generated
it; review for how it will fail, not whether it passes.

### Claude Code: selectors welded to today's DOM

Asked to write a Playwright test, Claude Code inspects the rendered page and emits what it finds:
`.css-1kj0d3 > div:nth-child(2) button.primary`, XPath chains, class names from the component
library. The test passes today and breaks on the next restyle, refactor, or library upgrade —
failing without the product failing, the exact wrong-way sensitivity that drains the trust budget.

**Detect:** CSS class chains, `nth-child`/`nth-of-type`, XPath, or framework-generated class names
(`css-*`, `sc-*`) in locators; zero `getByRole`/`getByLabel` in a generated spec; tests that break
on a PR that changed only styling.

**Fix:** constrain the locator vocabulary:

> Locate elements only by user-facing attributes — getByRole with the accessible name, getByLabel,
> getByText — and by data-testid where no semantic handle exists (add the testid to the component).
> No CSS selectors, no XPath, no structural chains. If getByRole can't find it, flag the
> accessibility gap instead of working around it.

### GPT: sleeping through the race

GPT-family models pace their scripts with fixed waits — `waitForTimeout(3000)` after navigation,
after clicks, before assertions — encoding one machine's timing into the test. On a slower CI
runner it flakes; on a faster one it wastes minutes; either way the suite inherits a race condition
per sleep. The same instinct produces non-retrying assertions (`expect(await page.$(...))`) that
sample the page once instead of waiting for it.

**Detect:** any `waitForTimeout`/`sleep` in specs; assertions on one-shot queries instead of
web-first `expect(locator)` forms; `networkidle` waits used as a synchronization crutch; tests
whose failure rate correlates with runner load.

**Fix:** ban the clock, require conditions:

> No fixed timeouts anywhere. Synchronize with web-first assertions that auto-retry —
> expect(page.getByRole(...)).toBeVisible() / toHaveText() — on the condition the user would see.
> If there is nothing visible to wait on, that's a UX gap (no loading/success state) to raise, not
> a sleep to add.

### Cursor: the serial story — tests that only work in order

Completing a spec file, Cursor continues the narrative of the tests above: reusing the invoice the
previous test created, assuming the logged-in state a prior test established, numbering tests to
enforce order. The file reads like a coherent user story and is a single fragile chain — nothing
runs alone, nothing runs in parallel, and one early failure cascades into a wall of misleading red.

**Detect:** `test.describe.serial` or numbered test names; specs referencing variables mutated by
earlier tests; a test failing when run alone (`--grep`) but passing in the file; cascading failures
where only the first is real.

**Fix:** make every test self-sufficient:

> Every test must run alone and in parallel: it creates its own data via the seeding fixtures,
> starts from storageState auth, and asserts an outcome it caused. No test.describe.serial, no
> shared mutable variables between tests, no reliance on earlier tests' side effects. Verify with
> --fully-parallel and by running each test in isolation.

## Best Practices

**Curate the portfolio.** Derive journeys from the critical-behavior map, cap the suite, and treat
every addition as a budget decision. The E2E folder listing should fit in one glance.

**Engineer stability structurally.** Role/label/testid locators, web-first assertions, zero fixed
sleeps, per-test API seeding, `storageState` auth — solved once in config, setup, and fixtures, so
specs contain only journey.

**Assert outcomes, including the persisted one.** Every journey ends on what the user sees; money
paths add one API-level assertion (charged exactly once) so the test can't pass on a lying UI.

**Gate deploys with it.** Run the journeys on every merge against the branch-built stack, and a
minimal smoke against production after deploy (Stage 7, Chapter 05's pipeline stages). Retain
traces and videos on failure.

**Hold the zero-flake line.** One CI retry as a flake detector, every flaky result ticketed and
quarantined visibly, root causes fixed — a meaningful share will be real application races worth
finding.

**Write the discipline into `CLAUDE.md`.** Locator vocabulary, no-sleep rule, seeding fixtures,
isolation requirements — the three AI failure modes above are the defaults; the conventions file is
what overrides them.

## Anti-Patterns

**The Flake Farm.** A large E2E suite red somewhere on every run, re-run until green. The tell:
merge threads saying "just re-run e2e"; nobody investigates which test failed.

**The DOM Weld.** Structural selectors breaking on every restyle. The tell: E2E failures on
CSS-only PRs; selector strings full of generated class names.

**The Sleep Script.** Fixed timeouts pacing every step. The tell: `waitForTimeout` throughout;
suite minutes dominated by waiting; failures correlate with runner load.

**The Serial Story.** Tests consuming earlier tests' state, enforced by order. The tell:
`describe.serial`, numbered tests, cascading failures, nothing runs alone.

**The Browser Pyramid.** The whole test strategy executed through E2E — validation, permissions,
edge cases. The tell: hundreds of specs, hour-plus gates, and Chapter 01's ice-cream cone.

**The Borrowed Environment.** Tests sharing a mutable staging database and demo accounts. The tell:
failures caused by other teams' data; "it was fine yesterday" with no code change.

## Decision Tree

"Should this be an E2E test — and if so, how do I keep it stable?"

```
Does the flow's failure stop the business (onboarding · core value loop · money path)?
├── NO ──► push down: logic → Ch 02 · seam/SQL → Ch 04 · component behavior → Stage 4's tests.
└── YES ─► does it need the real browser+frontend+API together to prove?
       ├── NO ──► it's a contract test (Ch 04) wearing a journey costume. Push down.
       └── YES ─► it earns a slot. Budget check: what does the suite drop or accept in runtime?

Writing it:
    locate ─► getByRole/getByLabel/getByText; testid only where semantics are ambiguous.
    wait ───► web-first assertions on visible conditions. A sleep = a missing condition.
    data ───► seed via API fixture, own everything you touch. Auth from storageState.
    assert ─► the user-visible outcome + (money paths) the persisted state via API.
    verify ─► runs alone · runs parallel · runs 10× without a flake. Then it merges.

It flaked in CI:
    trace/video → root cause. App race? ─► real bug: fix the app.
    test race? ─► fix the wait/isolation. Can't yet? ─► quarantine VISIBLY + ticket.
    never: raise retries and move on.

Where does it run?
    every merge ─► branch-built Compose stack (fake gateway at the port seam).
    post-deploy ─► 2-test production smoke (test tenant, non-destructive).
```

## Checklist

### Implementation Checklist

- [ ] Every E2E test maps to a named business-critical journey; the suite is capped and each addition displaces or justifies.
- [ ] All locators are role/label/text or `data-testid` — no CSS chains, XPath, or generated class names.
- [ ] Zero fixed sleeps; all synchronization is web-first auto-retrying assertions on visible conditions.
- [ ] Every test seeds its own data through the API and starts from `storageState` auth; each runs alone and fully parallel.
- [ ] Journeys assert user-visible outcomes; money paths also assert persisted state (charged exactly once) via the API.
- [ ] Traces and videos are retained on failure; the suite passes ten consecutive runs without a flake before merging.

### Architecture Checklist

- [ ] The merge-path suite runs against the branch-built Compose stack with the fake gateway at the port seam; vendor realism lives in the adapter ring and production smoke.
- [ ] Auth setup is a project dependency performing the real login journey once per worker; the login UI is covered there, not re-driven per test.
- [ ] A minimal, non-destructive production smoke runs after every deploy against a test tenant.
- [ ] Flake policy is enforced: one retry as detector, flaky results ticketed and quarantined visibly, zero tolerated flakes in main.
- [ ] E2E conventions (locator vocabulary, no-sleep, seeding, isolation) are recorded in `CLAUDE.md`.

### Code Review Checklist

- [ ] New E2E tests justify their slot against the critical-journey list — page-level behavior is pushed down the pyramid.
- [ ] No structural selectors, fixed timeouts, or one-shot non-retrying assertions (the three AI defaults — check generated specs hardest).
- [ ] No test depends on another test's state, `describe.serial`, or shared mutable variables.
- [ ] Setup that isn't under test goes through fixtures/API, not the UI.
- [ ] A quarantined or deleted E2E test is called out in the PR with its ticket.

### Deployment Checklist

- [ ] CI boots the full stack from branch-built images and runs the journey suite on every merge, gating deploy (Stage 7, Chapter 05).
- [ ] Browsers are installed/cached in CI (`playwright install --with-deps`); traces, videos, and reports are uploaded as artifacts on failure.
- [ ] The post-deploy production smoke runs automatically and pages on failure — it is the deploy verdict.
- [ ] Suite runtime and flake rate are tracked; parallel workers are added before runtime erodes the gate.

## Exercises

**1. Build the money journey.** Implement the pay-an-invoice journey for Invoicely (or your own
product's money path): storageState auth setup, API-seeded invoice, role/label locators, web-first
assertions, and the final API-level charged-exactly-once check. Prove stability: run it twenty
times in a row and in parallel with itself against fresh seeds. The artifact is the spec and the
twenty-run log.

**2. Stabilize a generated suite.** Have an assistant generate E2E tests for a flow without extra
instructions, then audit against this chapter: count structural selectors, fixed sleeps, and
inter-test dependencies. Rewrite it to the discipline and compare — runtime, lines, and behavior
under `--fully-parallel`. The artifact is the before/after specs and the audit table.

**3. Run the flake autopsy.** Take one genuinely flaky E2E test (or induce one: remove an await on
a state update in the app). Use retained traces to find the root cause, classify it (app race vs
test race), fix it at the root, and write the one-paragraph incident note. The artifact is the
trace analysis and the fix — and the habit.

## Further Reading

- **Playwright documentation — "Best Practices" (playwright.dev/docs/best-practices)** — the
  official casebook for this chapter's discipline: user-facing locators, web-first assertions,
  isolation, and auth reuse.
- **"Just Say No to More End-to-End Tests" (Google Testing Blog)** — the canonical argument for
  spending E2E slots sparingly, from the team that ran the largest flaky-suite experiment in the
  industry.
- **Playwright documentation — "Authentication" and "Test fixtures"** (playwright.dev) — the
  mechanics behind the two biggest stability wins here: `storageState` reuse and per-test seeded
  fixtures.
- **Stage 7, Chapter 05 — CI/CD with GitHub Actions** — the pipeline these journeys gate: where the
  stack is built, where the suite runs, and where the post-deploy smoke fits.

# Payments

## Introduction

Payments is the integration where every abstraction you've been taught to distrust earns its
keep, and every shortcut you've been taught to avoid collects its bill. The naive mental
model — "call the payment API, get money" — is wrong in a specific, instructive way: a
subscription business does not process payments, it *synchronizes state with a financial
system it does not control*. The payment provider knows whether the card charged. Your
database decides whether the customer gets in. Those two systems drift — webhooks arrive
twice, out of order, or not at all; retries fire during deploys; a card expires mid-cycle —
and the whole engineering discipline of billing is keeping that drift short-lived and
detectable.

The stakes are asymmetric in both directions. Grant access without payment and the leak is
silent — nobody emails to report they're not being charged. Deny access to a paying customer
and the failure is loud, public, and trust-destroying in a way ordinary bugs are not: people
forgive a broken dashboard and remember a wrong charge forever.

This chapter builds Invoicely's subscription billing on Stripe: hosted checkout, a
webhook-driven subscription state machine, idempotent event processing on the Celery
machinery from Stage 3, dunning for failed payments, and the nightly reconciliation that
catches everything else. Chapter 02 defined what customers are promised; this chapter keeps
the provider, the database, and the customer's access telling the same story about who paid
for it. One rule precedes everything: **you do not handle card data**. That is not a
build-vs-buy trade-off to weigh; PCI DSS compliance for raw card handling is a
company-sized project, and hosted payment pages exist so that it can be someone else's.

## Why It Matters

- **Money bugs are trust bugs, and trust doesn't regress-test.** A double charge, a
  post-cancellation charge, or a paying customer locked out mid-month does damage no
  changelog apology undoes — and screenshots of billing errors travel further than any
  feature announcement. The tolerance for defects here is effectively zero, which is why
  the design leans on invariants (idempotency, single source of truth, reconciliation)
  rather than carefulness.
- **Webhooks are the exam on everything Stages 3 and 11 taught about distributed work.**
  At-least-once delivery, no ordering guarantee, an unauthenticated public endpoint, and a
  sender that retries on slow responses: payment webhooks are the canonical case for
  signature verification (Stage 9), idempotent handlers (Stage 3 Ch 06), and
  fetch-the-truth-don't-trust-the-message. Teams that wing it here get the full curriculum
  as incidents.
- **Involuntary churn is a top-three revenue leak, and it's an engineering problem.**
  Expired cards, insufficient funds, and bank declines silently end 5–10% of subscriptions
  in a typical SaaS year. Dunning — retries, grace periods, update-your-card flows — is
  churn reduction implemented in code, and it routinely outperforms whole marketing
  initiatives per engineering hour spent.
- **The provider decision is quietly a tax decision.** Selling software across borders
  means VAT, GST, and US sales tax obligations that accrue whether or not you noticed. The
  merchant-of-record question (below) is not vendor preference — it decides whether tax
  compliance is your engineering-and-accounting problem or a line item in someone's fee.
- **Billing state feeds everything downstream.** Entitlements (Ch 02) read it, MRR and
  churn (Ch 06) are computed from it, dunning emails and upgrade funnels (Chs 04, 07) key
  off its transitions. A billing layer that misstates subscription state poisons every
  number the business runs on.

## Mental Model

Three ideas carry the chapter: two sources of truth with a synchronization contract, a
subscription state machine, and webhooks as untrusted at-least-once messages.

**1. Two systems, each authoritative for a different fact.** The provider owns money facts;
your database owns access facts. Webhooks are how money facts become access facts;
reconciliation is the audit that catches every webhook that didn't:

```
   STRIPE (truth: money)              INVOICELY DB (truth: access)
   customer, subscription,            Subscription row:
   invoices, charges, cards           (plan, version, status, seats)
        │                                     ▲
        │  webhooks: "a money fact changed"   │ entitlements
        ├────────────────────────────────────►│ resolve from
        │  at-least-once, unordered,          │ THIS, only
        │  signed, retried                    │
        │                                     │
        └──── nightly reconciliation ─────────┘
              list both sides, diff status,
              alert + heal on drift

   RULE: application code never asks Stripe "may this tenant
   do X?" (latency, coupling, outages) and never tells the DB
   "the card charged" (that's Stripe's fact to announce).
```

**2. A subscription is a state machine, and every transition has a business consequence.**
Enumerate the states and transitions before writing any handler — the happy path is five of
maybe twenty transitions:

```
                    checkout completed
   (none) ──► trialing ────────────► active ◄─────────────┐
                 │   trial ended,        │                 │
                 │   no card             │ payment fails   │ payment
                 ▼                       ▼                 │ succeeds
              canceled ◄─────────── past_due ──────────────┘
                 ▲     retries exhausted │
                 │     (dunning: N days, │  grace period:
                 │      M retries)       │  access KEPT
                 └───────────────────────┘
                 + cancel_at_period_end (active, ending) — access
                   until period end, then canceled
                 + plan changes (upgrade now w/ proration;
                   downgrade at period end)

   Each transition answers three questions:
   what does the customer see? what can they access (Ch 02)?
   what email do they get (Ch 04 wires it)?
```

**3. A webhook is an unauthenticated, at-least-once, unordered message — treat it like
one.** The handler contract, in order: *verify* the signature (it's a public endpoint;
anything unsigned is noise or attack); *dedupe* by event ID (delivery is at-least-once —
processing must be at-most-once); *acknowledge fast* (record and enqueue; the sender times
out slow endpoints and retries, creating the very duplicates you fear); *process from
truth* (fetch current object state from the API instead of trusting the possibly-stale
payload — two events processed in swapped order then converge on truth instead of ping-
ponging); *be idempotent* (the same event replayed tomorrow must be a no-op). Outbound
calls carry idempotency keys for the same reason in reverse: your retry must not create two
subscriptions.

A working definition:

> **Subscription billing is the discipline of synchronizing an access state machine you own
> with a money system you don't: hosted payment surfaces so card data never touches you,
> signed and deduplicated webhooks driving idempotent state transitions, access granted
> only by webhook-confirmed fact, and a scheduled reconciliation that assumes some webhooks
> will be lost and finds the drift before customers do.**

## Production Example

Invoicely sells the Chapter 02 catalog — Free, Professional ($19→$24), Business ($49) —
with monthly and yearly billing, a 14-day Business trial without a card, and the EU VAT
obligations that come with selling to European agencies (a third of trial signups, per
Chapter 01's hard lesson).

Decisions on the table, resolved in Engineering Decisions below: Stripe Billing direct
(with Stripe Tax) rather than a merchant of record — Invoicely already runs Stripe Checkout
for its *other* money flow, invoice payment links, and one provider relationship wins; the
hosted Checkout page and customer portal rather than custom card UI — zero card data
exposure, and the portal ships update-card/cancel/invoice-history flows Invoicely would
otherwise build and maintain; a 14-day past-due grace period with access retained, because
locking an agency out of *their* invoicing during a card hiccup makes Invoicely the reason
their cash flow broke.

The mapping between the two systems is deliberately thin: one Stripe Product per plan, one
Price per (plan version, interval), and a `stripe_price_id` column added to the Chapter 02
catalog so checkout sessions are created from the same data that resolves entitlements.
Stripe's subscription status maps onto the internal state machine; the only writer of
`Subscription.status` is the webhook-driven sync, and the only writer of `plan/plan_version`
on upgrade is the same sync — the seam Chapter 02 promised.

## Folder Structure

Billing grows a payments side, still one module — the entitlement files from Chapter 02
are unchanged consumers of the `Subscription` row this side maintains:

```
app/
├── billing/
│   ├── catalog.py            # Ch 02, + stripe_price_id per (version, interval)
│   ├── models.py             # Ch 02 models + ProcessedStripeEvent, BillingAuditLog
│   ├── entitlements.py       # Ch 02 — unchanged
│   ├── dependencies.py       # Ch 02 — unchanged
│   ├── stripe_client.py      # configured client: api key, pinned API version,
│   │                         #   idempotency-key helper — the ONLY import site
│   ├── checkout.py           # create checkout sessions + portal sessions
│   ├── webhooks.py           # POST /webhooks/stripe: verify, dedupe, enqueue, 200
│   ├── sync.py               # Celery task: fetch truth, run the state machine,
│   │                         #   write Subscription, invalidate entitlement cache
│   ├── dunning.py            # past_due lifecycle: grace timer, emails, final cutoff
│   ├── reconcile.py          # nightly: diff Stripe vs DB, heal + alert
│   └── router.py             # Ch 02 endpoints + checkout/portal endpoints
└── ...
```

Why the new files exist: `stripe_client.py` pins the API version and centralizes
configuration so an SDK upgrade is one diff, not a grep (and so no other module ever
imports `stripe` directly). `checkout.py` and `webhooks.py` split the two directions of the
integration — requests you initiate versus events that arrive. `sync.py` isolates the state
machine: webhooks, reconciliation, and support tooling all converge on the same transition
logic instead of three interpretations of it. `dunning.py` owns the one flow with a clock
in it. `reconcile.py` exists because the design *assumes* lost webhooks — it is the
difference between "we think we sync" and "we measure our drift."

## Implementation

Checkout: the client asks for a plan; the server creates the session from the catalog and
never trusts a price from the browser:

```python
# app/billing/checkout.py
async def create_checkout_session(tenant: Tenant, plan: str, interval: str) -> str:
    version = CURRENT_VERSIONS[plan]
    price_id = CATALOG[(plan, version)].stripe_price_id[interval]

    session = stripe.checkout.Session.create(
        customer=await get_or_create_stripe_customer(tenant),
        mode="subscription",
        line_items=[{"price": price_id, "quantity": 1}],
        automatic_tax={"enabled": True},
        success_url=f"{settings.APP_URL}/settings/billing?checkout=success",
        cancel_url=f"{settings.APP_URL}/settings/billing",
        metadata={"tenant_id": str(tenant.id), "plan": plan, "version": version},
        idempotency_key=f"checkout:{tenant.id}:{plan}:{version}:{interval}",
    )
    return session.url
```

The success URL shows a "finalizing your subscription…" state — **it grants nothing**. A
redirect is a browser navigation, spoofable and droppable; access is granted only when the
webhook-confirmed fact arrives seconds later.

The webhook endpoint does four things and nothing else — verify, dedupe, enqueue,
acknowledge:

```python
# app/billing/webhooks.py
@router.post("/webhooks/stripe", include_in_schema=False)
async def stripe_webhook(request: Request, session: AsyncSession = Depends(get_session)):
    try:
        event = stripe.Webhook.construct_event(
            payload=await request.body(),
            sig_header=request.headers.get("stripe-signature", ""),
            secret=settings.STRIPE_WEBHOOK_SECRET,
        )
    except (ValueError, stripe.error.SignatureVerificationError):
        raise HTTPException(400, "invalid signature")

    session.add(ProcessedStripeEvent(id=event.id, type=event.type))
    try:
        await session.commit()                    # unique PK on event id
    except IntegrityError:
        return {"status": "duplicate"}            # at-least-once → at-most-once

    if event.type in HANDLED_EVENTS:
        sync_from_stripe.delay(event_id=event.id,
                               subscription_id=extract_subscription_id(event))
    return {"status": "ok"}                       # fast 200 — work happens in Celery
```

The sync task is the single writer of billing state. It fetches the current object from
Stripe rather than trusting the event payload — which makes event *ordering* irrelevant,
because every event is just a hint to converge on present truth:

```python
# app/billing/sync.py
STATUS_MAP = {
    "trialing": "trialing", "active": "active",
    "past_due": "past_due", "unpaid": "past_due",
    "canceled": "canceled", "incomplete_expired": "canceled",
}

@celery_app.task(autoretry_for=(stripe.error.APIConnectionError,),
                 retry_backoff=True, max_retries=8)
def sync_from_stripe(event_id: str, subscription_id: str) -> None:
    remote = stripe.Subscription.retrieve(subscription_id)      # the truth, now
    tenant_id = UUID(remote.metadata["tenant_id"])

    with session_scope() as session:
        sub = session.get(Subscription, tenant_id, with_for_update=True)
        new_status = STATUS_MAP[remote.status]
        new_plan, new_version = plan_from_price(remote["items"].data[0].price.id)

        if (sub.status, sub.plan, sub.plan_version) == (new_status, new_plan, new_version):
            return                                              # idempotent replay → no-op

        session.add(BillingAuditLog(
            tenant_id=tenant_id, event_id=event_id,
            from_state=(sub.status, sub.plan, sub.plan_version),
            to_state=(new_status, new_plan, new_version),
        ))
        sub.status, sub.plan, sub.plan_version = new_status, new_plan, new_version
        sub.current_period_end = from_ts(remote.current_period_end)

    entitlements_cache.invalidate(tenant_id)                    # Ch 02 reads fresh
    emit_transition_events(tenant_id, new_status)               # dunning + lifecycle email
```

Dunning rides Stripe's smart retries and adds Invoicely's policy on top — grace with
access, then a humane cutoff:

```python
# app/billing/dunning.py — driven by emit_transition_events + a daily beat task
# on → past_due:  keep access; email "payment failed, we'll retry" + portal link
# day 7 past_due: email + in-app banner "update your card to keep reminders running"
# day 14:         status stays Stripe-owned; if Stripe exhausts retries →
#                 subscription canceled webhook → sync → Free-tier terms (Ch 02:
#                 data intact, creation gated). Email: "your data is safe, here's
#                 the one-click way back."
```

Reconciliation assumes the above still leaks — deploys drop webhooks, queues misbehave —
and measures it:

```python
# app/billing/reconcile.py — Celery beat, nightly
def reconcile() -> None:
    drift = []
    for remote in stripe.Subscription.list(status="all", limit=100).auto_paging_iter():
        local = get_subscription(UUID(remote.metadata["tenant_id"]))
        if local.status != STATUS_MAP[remote.status]:
            drift.append((local.tenant_id, local.status, remote.status))
            sync_from_stripe.delay(event_id="reconcile", subscription_id=remote.id)
    if drift:
        alert(f"billing reconciliation healed {len(drift)} drifted subscriptions",
              drift)          # drift >0 occasionally is normal; drift GROWING is a bug
```

## Engineering Decisions

### Stripe direct, or a merchant of record?

The real question is who is legally the seller — which decides who owes the world's tax
authorities. A merchant of record (Paddle, Lemon Squeezy) resells your software: they owe
the VAT/GST/sales tax everywhere, at the price of higher fees (~5% vs ~3%), less control
over checkout, and your revenue arriving as their payout. Stripe direct keeps control and
margin but makes tax *your* problem — softened by Stripe Tax (calculation and collection)
while registration and filing remain yours or your accountant's. The honest heuristic: a
solo founder selling globally on day one is well served by MoR; a funded team with an
accountant, or any product that also *moves* money (Invoicely's payment links), outgrows it
quickly. Invoicely chooses Stripe direct: the Connect relationship for payment links
already exists, and B2B invoicing means many customers are VAT-reverse-charge anyway. This
is Stage 1's build-vs-buy applied twice — never build card handling; probably don't build
tax handling.

### Hosted checkout, or embedded card fields?

Hosted Checkout and the hosted customer portal, until a measured conversion problem says
otherwise. Hosted surfaces mean the strictest PCI scope you can have (none), a payment page
Stripe A/B-tests harder than you ever will, and free maintenance of card-update, invoice-
history, and cancellation flows. Embedded Elements buys pixel control at the cost of owning
those flows forever. The upgrade-with-proration path stays server-side either way — prices
come from the catalog, never from the client.

### Webhook-driven sync, or poll/fetch on demand?

Webhooks as the trigger, API fetch as the truth, reconciliation as the backstop — the
combination, not any one alone. Pure polling adds latency to every state change and burns
rate limits; trusting webhook *payloads* alone inherits their staleness and ordering
hazards; fetch-on-request (asking Stripe during authorization) couples every request's
latency and availability to a third party. The chosen shape — event says "look," fetch
says "here's now," nightly diff says "you missed one" — is the only corner of this design
space where every failure mode has a catcher.

### How long is the past-due grace period, and what does it gate?

Fourteen days with full access, matching Stripe's default retry schedule, then the
Free-tier downgrade (never data deletion). The trade is explicit: some free-riding (a
customer enjoying two unpaid weeks) against never locking a legitimate customer out of
*their* invoicing over a card reissue. For Invoicely the asymmetry is extreme — the
customer's own cash flow runs through the product — so grace is generous and the cutoff
lands on `creation gated, data readable`, per Chapter 02's downgrade rule. Products whose
marginal serving cost is high (compute-heavy tiers) reasonably choose shorter grace or
degraded service instead.

### Upgrades now or at period end — and who computes proration?

Upgrades apply immediately with Stripe-computed proration (the customer asked for more;
give it to them while the intent is hot); downgrades and cancellations apply at period end
(they paid for the month; honor it — and `cancel_at_period_end` gives the save-flow a
window, Ch 07). Never compute proration yourself: it is calendar math across billing
cycles, tax rates, and currency rounding, owned by the system that will invoice it. Your
code's job is only to *pin the plan version* when the sync sees the new price.

## Trade-offs

| Choice | You gain | You pay |
|---|---|---|
| Stripe direct + Stripe Tax | Control, ~2% lower fees, one provider for billing + payment links | Tax registration/filing is yours; more integration surface to own |
| Merchant of record | Tax liability outsourced; simplest global selling | ~2% higher fees; their checkout, their payout schedule, their brand in the flow |
| Hosted checkout/portal | Zero PCI scope; battle-tested flows; card-update UX for free | Limited branding; a redirect in the purchase path |
| Embedded Elements | Native-feeling checkout; full funnel control | You own card-flow UX, SCA edge cases, and every portal flow forever |
| Access granted on webhook only | Unspoofable; single consistent path | Seconds of "finalizing…" after checkout — a UX cost you must design for |
| Access granted on redirect | Instant gratification | Spoofable URL grants; dropped redirects strand paid users; two grant paths to reconcile |
| Fetch-truth-per-event | Ordering-proof; stale-payload-proof | One extra API call per event; rate-limit budget |
| Trust event payloads | Fewer API calls; slightly faster sync | Out-of-order events corrupt state in ways only reconciliation catches |
| 14-day grace w/ access | Involuntary churn recovered; no wrongful lockouts | Free service to true deadbeats for two weeks |
| Immediate past-due cutoff | Zero revenue leakage | Card-reissue customers locked out; support fires; churn you caused |
| Stripe-computed proration | Correct invoices, always | Their proration policy is your policy; less pricing-page creativity |

The grant-path trade-off deserves its sharp edge: **the redirect is marketing; the webhook
is law.** Any access granted on the success URL eventually diverges from money truth, and
the divergence is always discovered by the accounting, never by the tests.

## Common Mistakes

- **Granting access in the success-URL handler.** The classic. It double-grants alongside
  the webhook path, grants on spoofed URLs, and strands users whose redirect never fired.
  The success page renders optimism; the webhook writes state.
- **Skipping signature verification.** A public endpoint that mutates billing state,
  trusting anything shaped like JSON. `construct_event` with the webhook secret, or the
  endpoint is an unauthenticated admin API for your revenue.
- **No event dedupe.** At-least-once delivery meets a non-idempotent handler: double
  emails, double audit rows, double plan changes. The unique-PK insert is two lines;
  the incident it prevents is a weekend.
- **Order-dependent handlers.** `invoice.paid` then `customer.subscription.updated`
  arriving swapped, each handler writing payload state → the DB ends on the stale one.
  Fetch-current-truth makes order irrelevant; payload-writing handlers make it fatal.
- **Handling three event types and calling billing done.** Checkout completed, invoice
  paid, subscription deleted — and nothing for `past_due`, trial expiry, plan changes, or
  refunds. The state machine diagram is the requirements list; every arrow needs a handler
  or an explicit "Stripe handles this."
- **Testing without test clocks.** Subscription bugs live in *time* — renewals, trial
  expiries, retry schedules. Stripe test clocks simulate months in seconds; a billing test
  suite without them tests the 20% of the system that was never going to break.
- **Floats anywhere near money.** `$19.99 * 100` is `1998.9999999999998`. Integer cents in
  the DB (Ch 02's schema), integer cents in every computation, formatting only at the
  display edge — Stage 6's data-type discipline, with money as the highest-stakes case.
- **Test-mode keys in production (or vice versa).** The integration "works," no money
  moves, and the reconciliation alert is the first to notice. Separate environments,
  separate secrets (Stage 9 Ch 04), and a startup assertion that the key mode matches the
  environment.

## AI Mistakes

The three tools fail differently here, and this is the chapter where their failures cost
actual money.

### Claude Code: the happy-path billing system

Asked to "integrate Stripe subscriptions," Claude Code delivers a competent happy path —
checkout session, `checkout.session.completed` handler, an `is_subscribed` flag — and
declares victory. What's missing is everything this chapter is about: no `past_due`
handling (failed renewals silently keep full access forever), no `subscription.updated`
(plan changes never sync), no dedupe, no reconciliation. The gap is invisible in review
because the code present is *good*; the defect is the code absent, and no diff shows
absent code.

**Detect:** count the event types handled versus the arrows on the state-machine diagram;
grep for `past_due` — its absence is the tell. Run a test-clock renewal with a failing
card and watch nothing happen. **Fix:** hand the assistant the state machine as the spec
("implement a handler or an explicit no-op decision for every transition"), and gate the
PR on test-clock scenarios for the unhappy arrows: failed renewal, trial expiry without
card, mid-cycle upgrade, cancellation at period end.

### GPT: confidently stale API shapes, verification optional

GPT's Stripe code is a time capsule: API patterns from whichever era dominates its
training data — deprecated parameter names, resource shapes that have since changed,
occasionally the pre-SCA charge flow — delivered with current-looking confidence. And its
webhook examples routinely parse `request.json()` directly, mentioning signature
verification as a comment if at all. The code often *runs* against the current API (Stripe
maintains compatibility heroically), which makes the staleness harder to spot until a
field is missing or a payment path 400s in production.

**Detect:** compare generated parameter names against the current API reference for the
pinned version; any webhook handler that reads the body without `construct_event`;
`stripe.Charge.create` in a subscription context. **Fix:** pin the API version explicitly
in `stripe_client.py`, treat generated integration code as a draft to verify page-by-page
against current docs, and make "no unverified webhook body is ever parsed" a review rule
backed by a test that posts an unsigned payload and expects 400.

### Cursor: money math that rounds wrong

Mid-file, Cursor completes money like it completes everything — locally plausible:
`amount = plan.price * 1.2  # add VAT` on a float, `refund = (days_left / 30) * 19.99`,
`total_cents = int(price * 100)` (which floors `19.995 * 100` to 1999). Each compiles,
passes the eyeball test, and is wrong by a cent in ways that surface as invoice
mismatches, reconciliation noise, and — the worst case — customer-visible off-by-a-cent
charges that read as fraud. It also happily re-implements proration inline, the
calculation this chapter explicitly assigns to Stripe.

**Detect:** any float literal or division in a file that touches money; `* 100` or
`/ 100` outside the display/formatting edge; homegrown proration. **Fix:** integer cents
as the only money type (enforce with a type alias and a lint rule), all derived amounts
(tax, proration, refunds) fetched from the provider that will invoice them, and
property-based tests (Stage 8) asserting sums of line items equal totals in integer space.

## Best Practices

- **One writer for billing state.** Every path — webhook, reconciliation, support tools —
  converges on `sync_from_stripe`'s transition logic. Two writers is two state machines
  that will eventually disagree.
- **The webhook endpoint does four things.** Verify, dedupe, enqueue, 200 — in under a
  second. Every piece of real work lives in the idempotent Celery task where it can retry
  without making Stripe retry.
- **Audit-log every transition.** The `BillingAuditLog` row per state change — from, to,
  event ID, timestamp — is the answer to every "why was this customer charged/locked out?"
  ticket, and the raw material for Chapter 06's churn analysis. Money state changes are
  the one place logging is never too verbose.
- **Reconcile nightly; alert on the trend, page on the spike.** A handful of healed drifts
  a month is webhook weather; drift growing week over week is a bug in the sync; a
  double-digit spike is an incident. The reconciliation job is also your migration tool
  and your disaster-recovery answer.
- **Test with test clocks, in CI.** The five scenarios that matter: successful renewal,
  failed renewal → dunning → recovery, failed renewal → cancellation, trial expiry with
  and without a card, mid-cycle upgrade with proration. Each is minutes with test clocks
  and impossible without them.
- **Design the dunning emails like product, not like collections.** "Your card was
  declined — here's a one-click fix, your data and reminders are safe" recovers customers;
  "FINAL NOTICE" churns them. The grace period is a retention feature; write it like one.
- **Keep the entitlement seam clean.** Payments writes `(plan, version, status)`;
  entitlements reads it; the cache is invalidated in the sync task and nowhere else.
  Every temptation to peek at Stripe from application code is a coupling bug in waiting.
- **Rotate and scope the secrets.** Webhook secret and API keys per environment, in the
  secret store (Stage 9 Ch 04), restricted keys where Stripe supports them, and the
  startup assertion that key mode matches deploy environment.

## Anti-Patterns

- **Building your own card form.** Raw card fields posting to your server puts you in PCI
  scope that requires audits, network segmentation, and a compliance program. Hosted
  fields/checkout exist precisely so this is never your problem. There is no scale of
  company where this trade flips for a SaaS.
- **The billing mega-handler.** One 600-line webhook function, `if/elif` over thirty event
  types, payload-writing each. Unreviewable, untestable, and order-sensitive. The
  architecture is: thin endpoint, one sync task, one state machine.
- **Asking Stripe per-request.** `stripe.Subscription.retrieve()` inside the auth
  dependency — every request now pays a third-party round trip, and a Stripe outage is
  your outage. Stripe is the truth webhooks *sync from*, not a database you query online.
- **Homegrown recurring billing.** A cron that charges cards monthly with `PaymentIntent`s
  — quietly reinventing retries, proration, invoicing, SCA re-authentication, and dunning.
  Stripe Billing's fee is the price of not owning that machine; pay it.
- **Deleting on cancellation.** Canceled → `DELETE FROM tenants` — destroying the data of
  the customers most likely to return, and in an invoicing product, destroying *legal
  records*. Cancellation is an access change (Ch 02's downgrade rules), never a data
  event; deletion is a separate, explicit, compliance-shaped flow.
- **Ignoring tax until the letter arrives.** VAT obligations start accruing at the first
  EU sale, noticed or not. The decision — Stripe Tax + registrations, or MoR — is made at
  integration time, deliberately; "later" is how the back-tax bill funds a consultancy.
- **The bespoke billing platform, pre-revenue.** Usage metering pipelines, custom invoice
  renderers, a plan-builder admin UI — built before customer #100. Chapter 01's judgment
  applies to internal systems too: Stripe's primitives, a thin sync, and this chapter's
  files are the MVP of billing.

## Decision Tree

```
Payments decisions, in the order they arrive:
│
├─ Who is the merchant of record?
│   ├─ Solo/tiny team, global B2C-ish sales, no accountant,
│   │  no other money flows → MoR (Paddle/Lemon Squeezy):
│   │  tax outsourced, fees higher, control lower
│   └─ Team with accounting support, B2B-heavy, or the product
│      itself moves money (Invoicely) → Stripe direct
│      + Stripe Tax, register where thresholds demand
│
├─ Checkout surface?
│   ├─ Default → hosted Checkout + customer portal
│   │            (zero PCI scope, flows maintained for you)
│   └─ Measured conversion loss at the redirect, team to own
│      the flows → embedded Elements (never raw card fields)
│
├─ A webhook arrived —
│   ├─ signature invalid → 400, log, done (it's the internet)
│   ├─ event id seen before → 200 "duplicate", done
│   ├─ type not in HANDLED_EVENTS → 200, done (decided no-op)
│   └─ else → record, enqueue sync, 200 within a second
│       └─ sync: fetch truth → map status → same? no-op
│                 : different? audit log + write + invalidate
│                   entitlement cache + emit transition events
│
├─ Renewal payment failed —
│   → past_due: keep access, start dunning (email + banner,
│     Stripe smart retries, portal link)
│     ├─ card updated / retry succeeds → active (audit log)
│     └─ retries exhausted (~day 14) → canceled → Free-tier
│        terms: data intact, creation gated, way-back email
│
└─ Nightly reconciliation —
    ├─ drift = 0 → normal
    ├─ small, stable → heal, log (webhook weather)
    └─ growing or spiking → heal, ALERT: the sync has a bug
       or webhooks are failing (check endpoint health first)
```

## Checklist

### Implementation Checklist

- [ ] No card data ever touches your servers: hosted checkout/portal, or hosted fields —
      verified by grepping for card-number handling, not by assumption.
- [ ] Webhook endpoint: signature verified, event ID deduped via unique constraint, work
      enqueued, 200 in under a second.
- [ ] Sync task fetches current state from the API, is idempotent (replay = no-op), takes
      a row lock, and is the *only* writer of subscription state.
- [ ] Every state-machine transition has a handler or a written no-op decision — checked
      against the diagram, not memory.
- [ ] Outbound creates carry idempotency keys.
- [ ] Money is integer cents end to end; proration and tax are computed by the provider.
- [ ] Dunning implemented: grace period with access, escalating emails, portal link,
      Free-tier landing (data intact) on exhaustion.
- [ ] Nightly reconciliation diffs both sides, heals via the sync task, and alerts on
      drift trend.
- [ ] Entitlement cache invalidated on every sync write.

### Architecture Checklist

- [ ] The seam holds: payments writes `(plan, version, status)`; entitlements (Ch 02)
      reads; application code imports neither `stripe` nor `stripe_client`.
- [ ] Provider/MoR decision recorded as an ADR including the tax rationale.
- [ ] Grace-period length and cutoff behavior chosen against *your* product's lockout
      asymmetry, and written down.
- [ ] Price IDs live in the catalog beside the plan versions they bill for — one mapping,
      no literals elsewhere.
- [ ] Billing state transitions emit events consumed by email/analytics (Ch 04) — no
      direct email sends from the sync task.
- [ ] The Stripe API version is pinned in one place; SDK upgrades are deliberate diffs.

### Code Review Checklist

- [ ] No access granted anywhere in a success-URL/redirect path.
- [ ] No webhook body parsed before `construct_event`; a test posts an unsigned payload
      and expects 400.
- [ ] No float touches money; no `* 100` outside formatting; no homegrown proration —
      especially in AI-generated diffs.
- [ ] New event handling routes through the single sync task, not a new writer.
- [ ] Test-clock scenarios cover the unhappy arrows the diff touches (failed renewal,
      trial expiry, downgrade at period end).
- [ ] Generated integration code verified against current API docs for the pinned
      version — parameter names, resource shapes, flow (no pre-SCA patterns).

### Deployment Checklist

- [ ] Live and test keys in separate secret-store entries per environment; startup asserts
      key mode matches environment.
- [ ] Webhook endpoint registered per environment with its own signing secret; delivery
      failures visible in monitoring (Stripe dashboard alerts + your own 4xx/5xx alarms).
- [ ] Webhook route excluded from auth middleware but rate-limit-protected (Stage 9
      Ch 08) against garbage traffic.
- [ ] Reconciliation and dunning beat tasks scheduled and monitored (Stage 7 Ch 07) — a
      silently dead reconciliation job is drift with no smoke detector.
- [ ] Deploy story for webhook gaps rehearsed: endpoint down during deploy → Stripe
      retries + reconciliation heal; verified once on staging, on purpose.

## Exercises

1. **Build the loop end to end.** On the Chapter 02 codebase: checkout session → hosted
   checkout (test card) → webhook → sync → entitlements flip. Use the Stripe CLI to
   forward webhooks locally. Verify the redirect grants nothing by completing checkout
   with webhook forwarding *off*, then turning it on and watching state converge.
2. **Run the clock.** With test clocks, simulate: a successful renewal, a failed renewal
   through the full dunning ladder to cancellation, and a trial expiring without a card.
   For each, assert the subscription row, the audit log, the entitlement resolution, and
   which email events fired. Wire the three scenarios into CI.
3. **Attack your own endpoint.** Post an unsigned payload, a tampered payload, the same
   valid event five times, and two events for the same subscription in reversed order.
   The correct outcomes: 400, 400, one processing + four duplicates, converged-on-truth
   state. Fix whatever disagrees.
4. **Break it, then let reconciliation catch it.** Manually corrupt a subscription row
   (set an active customer to `canceled`), run the reconciliation job, and verify heal +
   alert. Then disable the webhook endpoint for an hour of test-clock activity and watch
   reconciliation find every missed transition. Measure your drift-detection latency.
5. **Audit an AI billing integration.** Prompt an assistant to "add Stripe subscriptions"
   to a scaffold app, unconstrained. Review its output against this chapter: grant path,
   verification, dedupe, event coverage vs. the state machine, money types, tax. Write
   the review as PR comments, then re-prompt with the state machine as spec and diff the
   two attempts.

## Further Reading

- Stripe documentation — *Webhooks* (best practices: verification, idempotent handling,
  event ordering), *Billing* (subscription lifecycle and statuses), and *Test clocks* —
  the primary sources this chapter's patterns compress; the lifecycle page is the state
  machine's authoritative edition.
- Patrick McKenzie — *Bits about Money* — how payments actually work as a system of
  promises between institutions; the best available intuition-builder for why money code
  is different code.
- PCI Security Standards Council — *PCI DSS Quick Reference* — read enough to understand
  what scope is and why hosted fields keep you out of it; that's the entire assignment.
- Paddle — *Merchant of record explained* — the MoR case argued by an MoR; read
  critically alongside Stripe Tax's docs for the direct-integration counterargument.
- Stripe — *Designing APIs for humans: idempotency keys* (engineering blog) — the
  provider-side view of the retry problem, applicable to every API you'll ever build.
- Stage 3, Chapter [06 (Background Jobs)](../stage-03-backend-engineering/06-background-jobs.md) —
  the idempotency and retry machinery the sync task runs on.
- Stage 9, Chapters [04 (Secrets Management)](../stage-09-security/04-secrets-management.md)
  and [08 (Rate Limiting)](../stage-09-security/08-rate-limiting-and-abuse-prevention.md) —
  the key handling and endpoint protection this chapter assumes.

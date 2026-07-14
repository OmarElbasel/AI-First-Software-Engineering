# Analytics

## Introduction

Everything in this stage after the MVP runs on knowing what users actually do. Pricing
review needs to know which limits get hit; the payments funnel needs to know where checkout
stalls; the metrics chapter needs activation and retention events to compute anything at
all. Analytics is the system that produces that knowledge — and it is a *system*, with a
schema, a trust model, and failure modes, not a snippet pasted into the page footer.

The engineering problem is easy to underestimate because the vendor SDKs make the first
step trivial: call `track()`, see a dot on a dashboard. What the SDK cannot supply is
everything that makes the dots mean something. Which events exist and what they're named.
Whether `invoice_sent` fires when the user clicked send or when the email actually left.
Whether the same user counts once or three times across devices. Whether a customer's
email address is now replicated into a third-party's storage you'll need to scrub for a
GDPR erasure request. Bad instrumentation is worse than none: no data leaves you honestly
uncertain, while wrong data manufactures confidence — Chapter 01's Invoicely team nearly
shipped a reporting feature because a `dashboard_viewed` event fired on every page load
and read as engagement.

This chapter builds Invoicely's instrumentation: a tracking plan maintained as typed code,
server-side events emitted where facts become true, a thin consent-gated client wrapper,
opaque identity so no PII leaves the building, and delivery that can never slow down or
take down the product. Chapter 06 will compute the business's numbers from what this
chapter records — which is exactly why this chapter's standard is "trustworthy," not
"present."

## Why It Matters

- **Every downstream decision inherits instrumentation quality.** Activation, retention,
  funnel conversion, the pricing review, the growth experiments of Chapter 07 — all are
  arithmetic over these events. An event that fires on failure paths, or double-fires, or
  quietly stopped firing in March, corrupts every number computed from it, and nobody
  audits upstream when the dashboard looks plausible.
- **Tracking-on-click is the canonical false confidence machine.** The gap between "user
  clicked send" and "invoice actually sent" contains validation failures, network errors,
  and rate limits. Instrument the click and your funnel reports intent; instrument the
  outcome and it reports reality. Teams have celebrated conversion improvements that were
  actually error-rate increases.
- **Privacy is a design constraint, not a legal afterthought.** GDPR's erasure and access
  rights apply to event data; consent rules apply to non-essential client-side tracking of
  EU visitors. An event schema that embeds emails and names into properties turns every
  deletion request into an archaeology project across vendor storage. Opaque IDs and
  property discipline cost nothing on day one and are nearly unretrofittable later.
- **Events outlive features.** The dashboard gets rebuilt; the `invoice_sent` events from
  three years ago are still the retention baseline. Schema decisions here have the
  longevity of database schema decisions (Stage 6) with less tooling to fix mistakes —
  historical events cannot be re-fired.
- **The build-vs-buy stakes are asymmetric.** An analytics pipeline — ingestion, identity
  resolution, sessionization, a query UI — is a real product company's whole product.
  Building one pre-scale is Chapter 01's anti-pattern wearing a data-engineering costume;
  the buy option costs less than the meeting to discuss building.

## Mental Model

Three ideas carry the chapter: events describe intent, facts are tracked at their source
of truth, and the tracking plan is a schema.

**1. An event is a business fact, named by intent, not by implementation.** The unit of
analytics is "actor did action to object, in context":

```
EVENT ANATOMY
  who        distinct_id: opaque user id     (never email)
  tenant     group id: opaque tenant id      (B2B: the account acts)
  what       "invoice_sent"                  object_verb, past tense —
                                             a fact that happened
  properties {invoice_total_cents: 45000,    facts ABOUT the fact:
              currency: "EUR",               enums, numbers, booleans —
              recipient_count: 1,            never free text, never PII,
              has_payment_link: true}        never the invoice contents
  when       server timestamp

  NAMED BY INTENT             NOT BY IMPLEMENTATION
  invoice_sent                send_button_clicked
  trial_started               modal_shown_v2
  reminder_scheduled          POST /reminders 200

  Implementation names churn with every redesign and mean
  nothing to the person reading the funnel. Intent names
  survive the redesign — the analytics of a UI that no longer
  exists still answer today's questions.
```

**2. Track the fact where it becomes true.** Every fact has a source of truth, and the
event fires there — which almost always means server-side, after success:

```
                          the click        the outcome
  browser ──► API ──► service layer ──► commit/side-effect
     │                                        │
     │ client event:                          │ server event:
     │ "user tried"                           │ "it happened"
     │ (UI behavior, funnels                  │ (the business fact —
     │  of intent, consent-                   │  fires AFTER the commit,
     │  gated, ad-blocked                     │  in the service layer,
     │  ~25–40% of the time)                  │  blocked by nothing)
     ▼                                        ▼
  use for: UX questions               use for: everything that
  (did they find the button?)         matters (funnels, activation,
                                      retention, revenue events)
```

Client events are still worth having — they answer interface questions and capture the
intent that *didn't* convert — but they are lossy (ad blockers, consent declines) and
optimistic (they fire on attempts). Any number the business will act on stands on server
events.

**3. The tracking plan is a schema, and it lives in the repo.** Uncontrolled tracking
produces event sprawl — `invoice_sent`, `InvoiceSent`, `sent_invoice`, each with different
properties, none documented — which is schema drift by another name. The fix is the same
as Stage 6's: one authoritative, versioned, reviewed definition of every event and its
properties, in code, so the type checker enforces what convention alone cannot. Every
event in the plan carries one more field the SDK doesn't ask for: *the question it
answers*. An event no decision would consume is noise being stored at a fee.

A working definition:

> **Product analytics is a schema of business facts — events named by intent, emitted
> server-side where each fact becomes true, carrying typed PII-free properties and opaque
> identities, delivered off the request path through a queue, defined in one reviewed
> tracking plan — so that every number computed downstream inherits trust from the
> instrumentation instead of laundering doubt through a dashboard.**

## Production Example

Invoicely instruments three families of events, each tied to the decision it feeds. The
*activation funnel* — `signed_up → first_invoice_created → first_invoice_sent →
first_invoice_paid` — because Chapter 01 learned that "sent an invoice that got paid" is
the moment users become retainers, and Chapter 06 needs that funnel measured weekly. The
*monetization surface* — Chapter 02's entitlement denials (`limit_reached`,
`feature_denied`) and Chapter 03's billing transitions (`trial_started`,
`subscription_activated`, `payment_failed`, `subscription_canceled`) — because pricing
review and dunning tuning are blind without them. And *feature reach* — `reminder_scheduled`,
`recurring_invoice_created`, `payment_link_viewed` — because the roadmap debate "does
anyone use this?" should be a query, not a fight.

Two privacy lines are drawn before the first event fires. Invoice *contents* — line items,
client names, amounts owed by whom — are never tracked; they are Invoicely's customers'
customers' data, present in events only as aggregates (`invoice_total_cents`, counts).
And invoice *recipients* — people who never signed up for anything — generate exactly one
event class (`payment_link_viewed`, keyed to the invoice, not the person), because
"your invoice was viewed" is product functionality the sender expects, while building
behavioral profiles of non-users is surveillance with a dashboard.

The vendor decision: PostHog, self-hosted on Invoicely's infrastructure (Stage 7's Docker
Compose grows one service). SaaS-hosted analytics was the default until the EU-agency
segment's data-processing questionnaires made "event data never leaves our
infrastructure" the cheaper answer — a data-residency argument, not a cost one.

## Folder Structure

Analytics is a small module with one loud rule: nothing outside it names the vendor.

```
app/
├── analytics/
│   ├── __init__.py           # exports track(), identify_tenant() — the whole API
│   ├── events.py             # THE TRACKING PLAN: every event, typed, documented
│   ├── track.py              # emit → Celery task → PostHog client; fire-and-forget
│   └── consent.py            # per-tenant/user analytics preferences
├── invoicing/service.py      # calls track(InvoiceSent(...)) after commit
├── billing/sync.py           # Ch 03's transition events emit through here
└── ...
frontend/
└── lib/
    └── analytics.ts          # thin wrapper: consent-gated, typed event names
                              #   shared with the plan, opaque ids only
```

Why each file exists: `events.py` is the tracking plan as code — the single reviewable
place where an event can be born, so that sprawl requires a visible PR instead of a
one-line SDK call in a router. `track.py` isolates delivery mechanics (queueing, batching,
the vendor SDK) so swapping PostHog for anything else is one file. `consent.py` keeps the
consent decision queryable in one place instead of scattered as boolean checks. The
frontend wrapper mirrors the same plan so client and server cannot disagree about event
names — the drift Chapter 02 taught you to fear in limit constants applies to event names
identically.

## Implementation

The tracking plan: every event is a frozen dataclass — the name, the typed properties, and
the question it exists to answer. Nothing else can be tracked, by construction:

```python
# app/analytics/events.py
@dataclass(frozen=True)
class AnalyticsEvent:
    name: ClassVar[str]

    def properties(self) -> dict[str, str | int | bool]:
        return asdict(self)

@dataclass(frozen=True)
class InvoiceSent(AnalyticsEvent):
    """Answers: activation funnel step 3; feature reach of payment links.
    Fires: invoicing/service.py, after the send transaction commits."""
    name: ClassVar[str] = "invoice_sent"

    invoice_total_cents: int
    currency: str                  # ISO 4217 — enum-like, never free text
    recipient_count: int
    has_payment_link: bool
    is_first_invoice: bool         # denormalized so the funnel is one query

@dataclass(frozen=True)
class LimitReached(AnalyticsEvent):
    """Answers: which caps drive upgrades — Ch 02's quarterly packaging review.
    Fires: billing/dependencies.py, log_denial()."""
    name: ClassVar[str] = "limit_reached"

    limit: str                     # "invoices_per_month" | "seats"
    cap: int
    plan: str                      # display tier — fine here; it's an aggregate
```

Emission is fire-and-forget: the request enqueues, a Celery task delivers, and no failure
in analytics is ever allowed to become a failure in the product:

```python
# app/analytics/track.py
def track(user_id: UUID, tenant_id: UUID, event: AnalyticsEvent) -> None:
    """Never raises, never blocks. Analytics is an observer, not a participant."""
    try:
        deliver_event.delay(
            distinct_id=str(user_id),          # opaque UUIDs — identity stays home
            groups={"tenant": str(tenant_id)},
            name=event.name,
            properties=event.properties(),
            timestamp=utcnow().isoformat(),
        )
    except Exception:
        logger.warning("analytics enqueue failed", event=event.name)  # and move on

@celery_app.task(queue="low_priority", autoretry_for=(RequestException,),
                 retry_backoff=True, max_retries=5, ignore_result=True)
def deliver_event(**payload) -> None:
    posthog_client.capture(**payload)
```

The emission *point* is the discipline the code cannot fully enforce: service layer, after
the fact is durable. SQLAlchemy's after-commit hook makes it structural for the transaction
cases:

```python
# app/invoicing/service.py
async def send_invoice(session: AsyncSession, user: User, invoice: Invoice) -> None:
    ...                                        # validate, render, dispatch email task
    invoice.status = InvoiceStatus.SENT
    is_first = not await tenant_has_sent_before(session, invoice.tenant_id)

    def _emit() -> None:                       # runs only if the commit succeeds
        track(user.id, invoice.tenant_id, InvoiceSent(
            invoice_total_cents=invoice.total_cents,
            currency=invoice.currency,
            recipient_count=len(invoice.recipients),
            has_payment_link=invoice.payment_link_id is not None,
            is_first_invoice=is_first,
        ))
    on_commit(session, _emit)
```

The client wrapper is deliberately thin — consent first, plan names only, no identity
beyond the opaque ID the server issued:

```typescript
// frontend/lib/analytics.ts
import posthog from "posthog-js";
import type { ClientEventName } from "./analytics-events";  // generated from events.py

export function initAnalytics(consent: ConsentState, userId?: string) {
  if (!consent.analytics) return;              // no consent → no SDK init at all
  posthog.init(env.POSTHOG_KEY, {
    api_host: "/ph",                           // reverse-proxied via Nginx: first-party
    autocapture: false,                        // the plan defines events, not the DOM
    capture_pageview: false,
  });
  if (userId) posthog.identify(userId);        // opaque UUID — never email
}

export function trackClient(name: ClientEventName,
                            props: Record<string, string | number | boolean>) {
  posthog.capture(name, props);                // no-op if never initialized
}
```

Group analytics ties it together for B2B truth: `distinct_id` answers "what did this user
do," the `tenant` group answers "what did this *account* do" — and Chapter 06's
activation and retention are computed over tenants, because in B2B it is accounts that
pay, churn, and renew, not individuals.

## Engineering Decisions

### Build, buy, or self-host?

Buy the product, choose where it runs. Homegrown pipelines (events table + hand-rolled
dashboards) are the analytics version of homegrown billing — you will re-implement
identity merging, funnels, retention cohorts, and a query UI, badly, while the roadmap
waits. The live decision is SaaS-hosted versus self-hosted: SaaS wins on zero operations;
self-hosting wins when data residency is a sales requirement (Invoicely's case), when
event volume makes per-event pricing hostile, or when "no third-party processors for
product data" simplifies the compliance story. Note what self-hosting does *not* buy:
exemption from privacy law — consent and erasure obligations apply to your ClickHouse
exactly as they applied to the vendor's. When event volume eventually outgrows direct
delivery, the pipe becomes Stage 11 Chapter 07's stream — the *transport* changes, the
tracking plan survives.

### Server events, client events, or both?

Server for facts, client for interface behavior, and never a business number on a client
event. The asymmetry is measurement infrastructure 101: client events silently lose the
ad-blocking, consent-declining, flaky-network fraction of reality (routinely 25–40% of
B2B traffic), and they fire on *attempts*. Proxying the client SDK through your own domain
(the `/ph` reverse-proxy above, Stage 7 Ch 04's Nginx) recovers some blocking loss
honestly; it does not change the rule. If a funnel mixes client and server steps, expect
the client steps to undercount and annotate the dashboard accordingly — the alternative
is a "conversion improvement" every time an ad blocker updates.

### What is deliberately not tracked?

Decide by data class, in writing, before the first event. Invoicely's exclusions: invoice
contents and client PII (their customers' customers' data — present only as aggregates);
recipient behavior beyond the single product-functional `payment_link_viewed`; free-text
anything (a `notes` property will eventually contain someone's phone number); and
precise geolocation. The heuristic: track what the *product* did and what *segment* of
account did it — never what a human wrote or who a non-user is. Every exclusion is one
sentence in the tracking plan so future engineers inherit the line, not just the absence.

### How is identity modeled?

Opaque UUIDs end to end: the `distinct_id` is the user's UUID, the group ID is the
tenant's UUID, and the mapping to names and emails lives only in Invoicely's own
database. Erasure requests become trivial (delete the mapping row; vendor-side events
are orphaned pseudonyms), cross-device identity is handled by `identify()` on login
stitching the pre-login anonymous ID, and no email ever appears in a vendor's storage.
The cost is honest: exploring data *inside* the analytics tool shows UUIDs, and looking
up "what did Acme do" takes one join in your own DB first. That cost is the feature.

### Where do events fire — and who reviews them?

In the service layer, after durability: after-commit hooks for transactional facts, at
task success for async facts (the email actually sent), never in routers (too early —
validation hasn't run), never in the frontend for business facts. New events enter
through a PR to `events.py` that names the question the event answers and the decision
that will consume it; review rejects events with no consumer the way schema review
rejects columns with no reader. This is 15 minutes of process that prevents the 400-event
junk drawer every unreviewed analytics setup becomes.

## Trade-offs

| Choice | You gain | You pay |
|---|---|---|
| Buy (SaaS-hosted analytics) | Zero ops; funnels/cohorts/dashboards on day one | Per-event pricing at volume; product data at a third-party processor; residency questions in every security review |
| Self-host the bought product | Data stays home; flat infra cost; residency answer | You operate ClickHouse now (Stage 7 duties); upgrades are yours; still bound by privacy law |
| Homegrown events table | Total control; no new vendor | You rebuild identity, funnels, cohorts, and a query UI — a product team's product, as a side quest |
| Server-side facts | Complete, honest, fire-after-success | UI-behavior questions invisible; slightly more plumbing than an SDK snippet |
| Client-side tracking | Sees intent, UI friction, pre-signup behavior | Lossy (blockers, consent), optimistic (attempts), and the numbers drift with browser politics |
| Tracking plan as typed code | Sprawl impossible; review gate; type-checked properties | Every new event is a PR — friction by design |
| Autocapture ("track everything") | Instant coverage, no plumbing | Implementation-named noise; PII vacuumed indiscriminately; answers no question on purpose |
| Opaque IDs | Erasure is one row; vendor breach exposes pseudonyms | Analyst ergonomics: UUIDs in the UI, joins for names |
| Emails/names in properties | Convenient exploration | Every vendor copy is now a GDPR erasure surface; one breach is a notification event |
| Queue-buffered delivery | Product immune to analytics failures | Events lag by seconds; a dead low-priority queue drops data silently (monitor it) |

The autocapture trade-off deserves its sharp edge: **"track everything, decide later" is
deciding later with worse data** — implementation-named events full of accidental PII,
collected without a question, are not raw material for future insight; they are storage
costs wearing its costume.

## Common Mistakes

- **Tracking the click instead of the outcome.** `invoice_sent` firing in the button
  handler, before validation, before the commit. The funnel now counts failures as
  conversions. Every business-fact event fires after durability, or it is fiction.
- **PII in properties.** `{"recipient_email": ...}` because it was convenient for
  debugging. Now erasure requests span vendor storage, and the "analytics" dataset is a
  breach-notification surface. Typed events make this a compile-time impossibility;
  untyped dicts make it a certainty.
- **No naming convention.** Three spellings of the same fact, each half-populated. Pick
  `object_verb`, past tense, snake_case — the convention matters less than its
  enforcement, which is what the plan-as-code gives you.
- **Analytics in the request path.** A synchronous `posthog.capture()` (or worse, an
  HTTP call) inside the handler: p99 inherits the vendor's latency, and a vendor outage
  becomes your outage. Enqueue always; deliver from the worker.
- **Dev and prod in one project.** Local testing and CI runs polluting production funnels
  — the activation rate improved because a test loop signed up 400 times. Separate
  projects/keys per environment, asserted at startup like Chapter 03's key-mode check.
- **Orphaned anonymous users.** Client events pre-login never stitched to the user ID —
  every returning visitor is a new person, and "new user activation" is inflated by your
  own logged-out customers. Call `identify()` on login/signup, test the stitch.
- **Events without consumers.** Instrumenting speculatively "so we have it" — 300 events,
  12 queried, and nobody can say which. The plan's "answers:" field is the immune system;
  an event that answers nothing is deleted, not stored.
- **Silent instrumentation death.** A refactor renames a service function and the
  `track()` call goes with it; the dashboard just shows a gentle decline. Alert on event
  *absence* (an activation-funnel event at zero for a day is an incident), and contract-
  test that core flows emit their events (Stage 8's integration layer).

## AI Mistakes

The three tools fail differently here, and the common thread is that instrumentation code
looks trivially correct while being semantically wrong.

### Claude Code: instrumentation at the wrong altitude

Asked to "add analytics to the invoice flow," Claude Code adds `track()` calls where the
code is most legible — the router, top of the handler, before validation and commit. The
events fire, dashboards populate, and every number is optimistic: failed sends counted as
sends, rejected payloads counted as invoices. It will also, helpfully, wrap the call in
the request transaction, so a tracking hiccup can roll back — or be rolled back by — the
business operation. The code reviews clean because each line is fine; the defect is
placement.

**Detect:** `track(` appearing in routers or before `commit`/`await` of the operation it
describes; events for operations that can still fail below the call site. Compare event
counts to database truth: `invoice_sent` events versus rows with `status='sent'` should
match within queue lag. **Fix:** state the emission rule in CLAUDE.md ("business events
fire in the service layer via `on_commit`; never in routers"), and let the after-commit
helper be the only sanctioned idiom — assistants imitate the pattern the codebase
demonstrates.

### GPT: the taxonomy of widgets

Asked to design an event schema, GPT produces the taxonomy of a UI, not a business:
`button_clicked` with a `button_name` property, `page_viewed`, `modal_dismissed`,
`form_submitted` — forty properties of viewport and referrer, none of intent. It is the
average of every analytics tutorial, and it answers only questions about widgets. Six
months later "how many invoices convert to paid?" requires archaeologically reconstructing
intent from `button_name` values that no longer exist in the redesigned UI.

**Detect:** event names containing UI nouns (button, modal, page, form); schemas where
the property list is longer than the event list; no event that names a domain object.
**Fix:** give the model the domain vocabulary and the funnel questions first ("events
must be object_verb over: invoice, reminder, subscription, payment_link"), and have it
derive events from *decisions to inform*, not screens to cover. It is genuinely good at
that inversion once forced.

### Cursor: the property dict that swallows the model

Completing a `properties={...}` dict, Cursor reaches for what's in scope:
`"user": user.__dict__`, `"invoice": invoice.to_dict()`, `"email": user.email` — the
whole ORM object, hashed password field and recipient PII included, serialized into a
third-party's storage. It compiles, it ships, and it is invisible until someone reads the
vendor-side event and finds a customer's client list in it. The same reflex duplicates
event-name strings inline (`"invoice_send"` — close, wrong) instead of importing the
plan.

**Detect:** model objects, `__dict__`, `.to_dict()`, or email/name/address fields inside
any `properties` dict; event-name string literals outside `events.py`. **Fix:** the typed
event dataclasses make both impossible — properties are declared fields with scalar
types, names are `ClassVar`s — so the review rule is simply "no raw `capture()`/dict
tracking outside `analytics/`," enforced with the same CI grep discipline as Chapter 02's
plan names.

## Best Practices

- **Maintain the tracking plan like schema.** Typed definitions in `events.py`, each with
  the question it answers, the decision that consumes it, and where it fires. New events
  arrive by PR; events without consumers get deleted. The plan *is* the documentation.
- **Emit after durability, deliver off-path.** After-commit hooks in the service layer;
  Celery delivery on a low-priority queue; `track()` that never raises. Analytics
  observes the system; it never participates in it.
- **Keep identity opaque and at home.** UUIDs to the vendor, the name/email mapping only
  in your database, `identify()` on login to stitch anonymous history. Erasure becomes a
  row delete; the vendor dataset becomes pseudonymous by construction.
- **Draw the not-tracked lines in writing.** Data classes excluded on purpose — customer
  content, non-user profiles, free text — listed in the plan with one sentence each. The
  absence of an event should be legible as a decision, not an oversight.
- **Separate environments absolutely.** Distinct projects and keys per environment, a
  startup assertion, and CI running against a throwaway project. One polluted production
  dataset costs more analysis time than the setup ever did.
- **Monitor the instrumentation itself.** Alert on core events flatlining, on the
  delivery queue's depth, and on event-versus-database drift for the facts that feed
  Chapter 06. Instrumentation that can die silently, will.
- **Respect consent structurally, not decoratively.** No consent → the client SDK never
  initializes (not "initializes and drops events"). Server-side operational events keyed
  to opaque IDs are your legitimate-interest lane — document that reasoning in the plan
  and stay inside it.
- **Version events forward.** When semantics must change, add `invoice_sent_v2` (or a
  `schema_version` property) rather than silently redefining — dashboards and Chapter
  06's queries pin to semantics, and a redefined event corrupts every historical
  comparison crossing the change.

## Anti-Patterns

- **Autocapture as strategy.** Turning on capture-everything and calling instrumentation
  done. What arrives is widget noise named by the DOM, PII vacuumed from form fields,
  and no event that answers a business question — plus a compliance surface nobody
  scoped. Autocapture is at best a temporary UX-debugging aid, never the plan.
- **The 40-property event.** One `app_event` with a `type` property and everything
  denormalized into it — the God-object anti-pattern (Stage 2) arriving in analytics.
  Unqueryable, undocumentable, and every consumer parses it differently.
- **The analytics database as application database.** Reading PostHog to decide *product
  behavior* — "has this user sent an invoice? query the events" — puts a lossy,
  eventually-consistent observer in the request path. The application's truth is
  PostgreSQL; analytics is derived, never authoritative.
- **Dark-pattern consent.** The cookie banner with a bright "accept" and a maze for
  "decline," or consent recorded before the choice renders. Beyond the legal exposure:
  the numbers it buys are inflated by exactly the users who wanted out, which is the
  wrong data to grow on. Make decline one click and let the server events carry the
  business truth.
- **The pre-PMF data warehouse.** dbt, a warehouse, reverse ETL, and a "data platform"
  for a product with 60 tenants — Chapter 01's over-building, data edition. A bought
  analytics product and SQL against the production replica answer every question this
  stage asks; the warehouse earns its place when the questions outgrow them (Ch 06 notes
  the threshold).
- **Tracking as surveillance.** Session-replaying non-consenting users, profiling invoice
  recipients, buying enrichment data to append to opaque IDs. Besides being wrong and in
  much of the world illegal, it poisons the well this whole stage drinks from: users who
  feel watched behave differently, and B2B customers who find out leave loudly.

## Decision Tree

```
Instrumenting a new fact — the questions in order:
│
├─ What decision will consume this event?
│   ├─ None nameable → don't track it. Storage is not strategy.
│   └─ Named ↓  (write it in the plan's "answers:" field)
│
├─ Is it a business fact or interface behavior?
│   ├─ BUSINESS FACT (order placed, invoice sent, limit hit)
│   │   → server-side, service layer, after durability
│   │     (on_commit / task success). Never the router.
│   │     ├─ Does it involve customer content or non-user
│   │     │  PII? → aggregates only (counts, cents, enums);
│   │     │        the content itself is on the not-list
│   │     └─ Typed event in events.py → PR → review
│   └─ INTERFACE BEHAVIOR (found the button? abandoned the
│       form?) → client wrapper, consent-gated, expect loss;
│       never feed it to a business metric
│
├─ Identity for this event?
│   ├─ Logged-in user → opaque user UUID + tenant group
│   ├─ Pre-signup visitor → anonymous id; stitch via
│   │   identify() at signup (test the stitch)
│   └─ Non-user (invoice recipient) → key to the OBJECT
│       (invoice id), not the person — or don't track it
│
└─ Choosing the platform (once):
    ├─ Default → buy, SaaS-hosted
    ├─ Data residency in sales conversations / volume pricing
    │   hostile → self-host the same product (you now operate
    │   it — Stage 7 duties apply)
    ├─ Event volume outgrows direct delivery → keep the plan,
    │   move transport to the stream (Stage 11 Ch 07)
    └─ "Let's build our own pipeline" → Chapter 01's decision
        tree, which says no
```

## Checklist

### Implementation Checklist

- [ ] Tracking plan exists as typed code; every event has a name (object_verb, past
      tense), typed scalar properties, the question it answers, and its emission point.
- [ ] Business events emit in the service layer after durability (after-commit /
      task-success); no `track()` in routers.
- [ ] Delivery is queue-buffered, fire-and-forget, retried with backoff; `track()` cannot
      raise or block.
- [ ] Identity is opaque UUIDs; `identify()` stitches anonymous → known on login; the
      PII mapping lives only in your database.
- [ ] Client wrapper is consent-gated at SDK-init level; autocapture off; event names
      imported from the shared plan.
- [ ] Environments use separate projects/keys with a startup assertion.
- [ ] Core-flow events are contract-tested (the flow runs → the event is emitted with
      the planned properties).
- [ ] Erasure path implemented and tested: deleting a user severs the vendor-side
      pseudonym.

### Architecture Checklist

- [ ] Vendor SDK is imported in exactly one module; everything else calls `track()`.
- [ ] The buy/self-host decision is an ADR recording the residency/volume reasoning.
- [ ] The not-tracked list (customer content, non-user profiles, free text) is written
      into the plan.
- [ ] Business metrics consume server events only; client events are annotated as lossy
      wherever dashboards mix them.
- [ ] Analytics data is never read on the application's request path — PostgreSQL is
      truth, analytics is derived.
- [ ] Instrumentation health is monitored: flatline alerts on funnel events, queue-depth
      alarms, event-vs-database drift checks for Ch 06's inputs.
- [ ] Event semantics changes are versioned forward, never redefined in place.

### Code Review Checklist

- [ ] New events arrived via `events.py` with the "answers:" field filled — no inline
      event-name strings or raw `capture()` calls outside `analytics/`.
- [ ] No PII, model objects, `__dict__`/`to_dict()`, or free text in any properties dict
      — especially in AI-generated diffs.
- [ ] Emission point is after the fact is durable; nothing tracks inside the transaction
      or before validation.
- [ ] Refactors that touch instrumented services keep the events firing (the contract
      test proves it).
- [ ] Funnels mixing client and server steps carry the undercount annotation.

## Exercises

1. **Write Invoicely's tracking plan.** Fifteen events maximum, covering the activation
   funnel, monetization surface, and feature reach. For each: name, typed properties,
   the question it answers, the decision that consumes it, and the emission point. Then
   defend three things you chose *not* to track and why.
2. **Instrument the funnel end to end.** On the Stage 3 codebase (or your own), implement
   the typed-events module, the after-commit emission for one business fact, and the
   queue-buffered delivery. Prove the placement: make the operation fail after the
   `track()` call site would have fired in a naive implementation, and show no event was
   emitted.
3. **Audit an autocapture dataset.** Turn autocapture on against a staging app, click
   around for ten minutes, then export the events. Count: events named by implementation,
   properties containing PII or free text, events that answer no nameable question.
   Write the one-paragraph case to your team for plan-based tracking, using your own
   numbers.
4. **Run the erasure drill.** For your instrumented app: a user requests deletion.
   Execute it — application rows, the identity mapping, and whatever the vendor-side
   process is. Time it. If any step required reading event properties to find the user,
   you have PII in properties; fix the schema and re-run.
5. **Review an AI's instrumentation.** Ask an assistant to "add analytics" to a flow,
   unconstrained. Review against this chapter: emission altitude, PII in properties,
   naming, consent handling. Then re-prompt with your tracking plan and emission rules
   in context, diff the two results, and note which failures the constraints eliminated
   — and which survived and still need review.

## Further Reading

- Segment — *The Analytics Academy* and the *Tracking Plan* guides — the clearest
  vendor-neutral treatment of event naming, tracking plans, and the client/server split;
  the discipline transfers to any platform.
- Amplitude — *The North Star Playbook* and taxonomy guides — how event taxonomies connect
  to the metric trees Chapter 06 builds; strong on "what decision consumes this."
- PostHog documentation — *Event tracking guide* and *self-hosting* docs — the concrete
  platform this chapter deploys, including group analytics and the reverse-proxy pattern.
- ICO (UK Information Commissioner's Office) — guidance on cookies, consent, and
  legitimate interests — readable regulator-grade grounding for the consent architecture;
  pairs with your counsel, replaces neither.
- Abhi Sivasailam — "Metrics layers and semantic consistency" (talks/essays) — why event
  semantics drift destroys trust, from the analytics-engineering side.
- Stage 11, Chapter [07 (Event Streaming)](../stage-11-system-design/07-event-streaming.md)
  — the transport this chapter's events graduate to at volume, and the schema-governance
  discipline shared between them.
- Stage 9, Chapter [01 (Security Mindset)](../stage-09-security/01-security-mindset-and-owasp-top-10.md)
  — the data-classification thinking behind the not-tracked list.

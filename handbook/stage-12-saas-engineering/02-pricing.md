# Pricing

## Introduction

Pricing looks like a business decision that engineering merely implements. That framing has
ruined more codebases than bad architecture, because the implementation *is* an architecture
decision: how plans, features, and limits are modeled determines whether the business can
change its mind. A company whose code asks `if tenant.plan == "pro"` in a hundred places has
hard-coded its current pricing page into its application layer — and the day marketing wants
a new tier, a price test, or one custom enterprise deal, that day becomes a migration
project. Pricing changes are supposed to be the cheapest experiment a SaaS can run; bad
modeling makes them the most expensive.

This chapter teaches both halves, because in an AI-first team the same engineer handles
both. The judgment half: what a value metric is, how tiers segment customers, and why the
price on the page should be downstream of how value accrues. The systems half: a
plan-and-entitlement model for Invoicely in which plans are data, features are named
capabilities, limits are enforced in exactly one layer, and a price change is a new row —
not a pull request.

The boundary matters as much as the content. This chapter decides *what customers are
promised and how the code enforces it*. Chapter 03 decides *how the money for those
promises is collected* — subscriptions, webhooks, and the payment provider. The seam between
them, deliberately, is a single field: the tenant's current plan, owned by billing, read by
entitlements.

## Why It Matters

- **Pricing is the highest-leverage number in the business, and engineers control whether
  it's adjustable.** Improving price/packaging moves profit more than the equivalent
  improvement in acquisition or retention — that is the consistent finding of every pricing
  study worth reading — yet most teams change pricing roughly never, because the model is
  calcified in code. An entitlement layer converts pricing from surgery into configuration.
- **Plan checks are the fastest-metastasizing hard-coding in SaaS.** The first
  `if plan == "pro"` takes thirty seconds and works. Two years later plan names are load-
  bearing strings in endpoints, templates, mobile apps, and email jobs — and renaming a tier
  breaks invoice reminders. This is Stage 1's technical-debt chapter running at compound
  interest.
- **Entitlement enforcement is a correctness and security boundary.** A limit checked only
  in the frontend is a suggestion; a paid feature gated only by a hidden button is free for
  anyone with `curl`. Enforcement belongs in the API layer with the same seriousness as
  authorization — Stage 3 Chapter 04's discipline, applied to money.
- **Grandfathering is a data-modeling problem you solve on day one or regret.** The moment
  the first price change ships, some customers are on the old terms. If the schema cannot
  represent "the Pro that existed in March," the choice becomes: break promises to early
  customers, or freeze pricing forever. Both are expensive; the schema fix costs one table.
- **Every mispriced month compounds.** Underpricing doesn't just lose margin — it selects
  for customers who churn at the first price correction, and it starves the business of the
  revenue that funds the roadmap. The cure is cheap experiments; the prerequisite for cheap
  experiments is this chapter's model.

## Mental Model

Three ideas carry the chapter: price follows a value metric, tiers are segmentation, and
plans are data resolved through one entitlement layer.

**1. The value metric is the unit the price scales with — choose it before choosing
numbers.** A good value metric grows as the customer's value grows, is legible to the buyer,
is measurable by you, and is hard to game:

```
CANDIDATE VALUE METRICS (Invoicely's deliberation)
                     grows w/    legible to   measurable   hard to
                     value?      buyer?       cleanly?     game?
  per user/seat      weak(1)     yes          yes          no(2)
  invoices sent      YES         yes          yes          mostly
  clients billed     yes         yes          yes          no(3)
  revenue collected  YES         yes          yes(Stripe)  yes(4)

  (1) a 2-person agency billing $2M and a 2-person freelancer
      duo billing $40k pay the same — value decoupled
  (2) login sharing is the oldest trick in SaaS
  (3) merge two client records, halve your bill
  (4) but: feels like a tax on success; % pricing is a
      psychological cliff for SMBs → rejected on legibility
      of TRUST, not measurability
  CHOSEN: invoices sent (limits) + light seats (collab tiers)
```

**2. Tiers are segmentation, not generosity levels.** Each tier exists to capture one
customer segment at the price that segment bears; features are assigned to tiers by *who
needs them*, not by how hard they were to build. The free tier is not a small paid tier —
it is an acquisition channel with a job (Chapter 07 gives it its growth role) and a budget
(its limits are its cost control). The top tier's job is often just to make the middle tier
look reasonable (anchoring). Fence features — the ones a segment cannot live without (API
access for the integrating business, multiple seats for the team) — are what make a segment
upgrade; cosmetic differences don't move anyone.

**3. Plans are data; code asks about capabilities, never about plan names.** The layering
that keeps pricing changeable:

```
  PRICE            what the tier costs        marketing/billing owns
    │                                         (a number in the catalog)
  PLAN             a named bundle w/ version  data: plan_versions table
    │              ("professional v2")        NOT an enum, NOT code
  ENTITLEMENTS     resolved capabilities of   {custom_branding: true,
    │              ONE tenant right now        invoices_per_month: ∞,
    │              (plan + overrides)          seats: 2, api: false}
  ENFORCEMENT      the ONLY layer that        require_feature(...)
                   answers can/cannot         enforce_limit(...)
                                              in API dependencies

  Application code NEVER sees plan names.
  It asks: "may tenant T use capability C?"
           "how many X may tenant T have — and how many do they have?"
  Renaming a tier, adding one, or cutting a custom deal
  touches DATA and the resolver — zero endpoints.
```

A working definition:

> **Pricing is a hypothesis about value, expressed as a value metric and a set of tiers —
> and a pricing system is the data model that lets that hypothesis change cheaply: plans as
> versioned data, entitlements resolved per tenant through one layer, limits enforced at the
> API boundary, and no plan name ever appearing in application code.**

## Production Example

Invoicely, post-validation (Chapter 01), needs its first real pricing. Usage data from the
MVP shows two populations: solo freelancers sending 4–15 invoices/month who care about
looking professional, and small agencies sending 30–200 who care about reminders, team
access, and their own branding. The partnership (Stage 11's scenario) is about to add
accounting-firm referrals with API needs.

The pricing that falls out of the value-metric analysis:

```
              FREE            PROFESSIONAL      BUSINESS
  price       $0              $19/mo            $49/mo
              ($190/yr)       ($490/yr)
  job         acquisition +   the freelancer/   the agency/
              invoice-footer  solo agency       integrator
              growth loop
  invoices    5 / month       unlimited         unlimited
  seats       1               1                 5 (then +$8/seat)
  reminders   —               automatic         automatic + custom
                                                schedules
  branding    "via Invoicely" custom logo,      white-label
              footer          no footer
  recurring   —               yes               yes
  API access  —               —                 yes
  support     community       email             priority email
```

Three deliberate calls, each defended in Engineering Decisions below: the free tier's limit
is *invoices per month* (the value metric, so upgrade pressure tracks value received); the
fence between Pro and Business is *seats + API* (things agencies structurally need, not
arbitrary feature confiscation); and reminders — the MVP's killer feature — sit in Pro, not
Free, because they are the "get paid faster" value the price message is anchored to. When
Pro later moves from $19 to $24, existing subscribers keep $19 as a *grandfathered plan
version* — which is why everything below is versioned.

## Folder Structure

The entitlement system is one feature module in Invoicely's modular monolith (Stage 2's
feature-based layout), beside `invoicing/` and `auth/`:

```
app/
├── billing/
│   ├── __init__.py
│   ├── catalog.py          # plan catalog: versions, prices, entitlements — DATA
│   ├── models.py           # Subscription, PlanOverride ORM models
│   ├── entitlements.py     # resolution: tenant → entitlements (+ cache)
│   ├── limits.py           # usage counting for metered limits
│   ├── dependencies.py     # require_feature / enforce_limit FastAPI deps
│   ├── router.py           # GET /billing/entitlements, usage endpoints
│   └── schemas.py          # Pydantic: Entitlements, UsageStatus
├── invoicing/              # consumes billing.dependencies — never plan names
└── ...
```

Why each file exists: `catalog.py` isolates the one thing marketing changes — plan
definitions live in exactly one importable, reviewable, versioned place (and can later move
to a table without touching consumers). `entitlements.py` is the single resolver — the only
code allowed to know how plan + version + overrides combine. `limits.py` separates *counting
usage* (a query problem with performance implications) from *deciding* (the resolver's job).
`dependencies.py` is the enforcement boundary — endpoints declare requirements the way they
declare auth (Stage 3 Ch 01's dependency idiom), so enforcement is visible in signatures and
impossible to scatter. `router.py` exposes entitlements to the frontend so the UI gates from
the same source of truth the API enforces — the alternative is two definitions that drift.

## Implementation

The catalog: plans are frozen data with explicit versions. A price change is a new version
appended, never an edit — editing history is how grandfathering breaks silently.

```python
# app/billing/catalog.py
from dataclasses import dataclass, field

UNLIMITED = -1

@dataclass(frozen=True)
class PlanVersion:
    plan: str                 # "free" | "professional" | "business"
    version: int
    monthly_price_cents: int
    yearly_price_cents: int
    features: frozenset[str]
    limits: dict[str, int] = field(default_factory=dict)

CATALOG: dict[tuple[str, int], PlanVersion] = {
    ("free", 1): PlanVersion(
        plan="free", version=1,
        monthly_price_cents=0, yearly_price_cents=0,
        features=frozenset(),
        limits={"invoices_per_month": 5, "seats": 1},
    ),
    ("professional", 1): PlanVersion(
        plan="professional", version=1,
        monthly_price_cents=1_900, yearly_price_cents=19_000,
        features=frozenset({"reminders", "custom_branding", "recurring_invoices"}),
        limits={"invoices_per_month": UNLIMITED, "seats": 1},
    ),
    ("business", 1): PlanVersion(
        plan="business", version=1,
        monthly_price_cents=4_900, yearly_price_cents=49_000,
        features=frozenset({"reminders", "custom_branding", "recurring_invoices",
                            "custom_reminder_schedules", "white_label", "api_access"}),
        limits={"invoices_per_month": UNLIMITED, "seats": 5},
    ),
    # price change 2026-09: Pro v2 at $24. v1 subscribers keep v1 terms.
    ("professional", 2): PlanVersion(
        plan="professional", version=2,
        monthly_price_cents=2_400, yearly_price_cents=24_000,
        features=frozenset({"reminders", "custom_branding", "recurring_invoices"}),
        limits={"invoices_per_month": UNLIMITED, "seats": 1},
    ),
}

CURRENT_VERSIONS = {"free": 1, "professional": 2, "business": 1}
```

The subscription row pins a tenant to a plan *version*; overrides express custom deals
without new code paths:

```python
# app/billing/models.py
class Subscription(Base):
    __tablename__ = "subscriptions"

    tenant_id: Mapped[UUID] = mapped_column(
        ForeignKey("tenants.id"), primary_key=True)
    plan: Mapped[str]
    plan_version: Mapped[int]
    status: Mapped[str]        # owned by Ch 03: active|trialing|past_due|canceled
    seats_purchased: Mapped[int] = mapped_column(default=1)

class PlanOverride(Base):
    """One-off deal terms: extra seats, a raised limit, an unlocked feature.
    The audit trail for every 'just for this customer' promise sales makes."""
    __tablename__ = "plan_overrides"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    tenant_id: Mapped[UUID] = mapped_column(ForeignKey("tenants.id"), index=True)
    kind: Mapped[str]          # "feature" | "limit"
    key: Mapped[str]           # e.g. "api_access", "seats"
    value: Mapped[int]         # 1 for feature grants; the number for limits
    reason: Mapped[str]        # "2026-03 renewal negotiation, approved by CEO"
    expires_at: Mapped[datetime | None]
```

Resolution merges catalog and overrides in one place, cached briefly — entitlements are read
on nearly every request, change rarely, and tolerate seconds of staleness:

```python
# app/billing/entitlements.py
@dataclass(frozen=True)
class Entitlements:
    features: frozenset[str]
    limits: dict[str, int]
    plan: str                  # for display and analytics only — never branch on it

async def resolve(session: AsyncSession, tenant_id: UUID) -> Entitlements:
    if cached := await entitlements_cache.get(tenant_id):   # Redis, 60s TTL
        return cached

    sub = await session.get(Subscription, tenant_id)
    base = CATALOG[(sub.plan, sub.plan_version)] if sub and sub.status in ACTIVE_STATUSES \
        else CATALOG[("free", CURRENT_VERSIONS["free"])]    # lapsed billing → free terms

    features, limits = set(base.features), dict(base.limits)
    if sub:
        limits["seats"] = max(limits["seats"], sub.seats_purchased)
    for ov in await active_overrides(session, tenant_id):
        if ov.kind == "feature":
            features.add(ov.key)
        else:
            limits[ov.key] = max(limits.get(ov.key, 0), ov.value)

    ent = Entitlements(frozenset(features), limits, base.plan)
    await entitlements_cache.set(tenant_id, ent)
    return ent
```

Enforcement is a dependency, so an endpoint's requirements read like its auth requirements —
and denials return a machine-readable upgrade path, because a `403` that just says "no" is a
support ticket, while one that names the capability is an upgrade prompt:

```python
# app/billing/dependencies.py
def require_feature(feature: str):
    async def dep(tenant: Tenant = Depends(current_tenant),
                  session: AsyncSession = Depends(get_session)) -> None:
        ent = await resolve(session, tenant.id)
        if feature not in ent.features:
            log_denial(tenant.id, feature=feature)          # purchase-intent signal, Ch 04
            raise HTTPException(403, detail={
                "error": "feature_not_in_plan",
                "feature": feature,
                "upgrade_url": "/settings/billing",
            })
    return Depends(dep)

def enforce_limit(limit: str):
    async def dep(tenant: Tenant = Depends(current_tenant),
                  session: AsyncSession = Depends(get_session)) -> None:
        ent = await resolve(session, tenant.id)
        cap = ent.limits.get(limit, 0)
        if cap == UNLIMITED:
            return
        used = await usage.count(session, tenant.id, limit)  # limits.py
        if used >= cap:
            log_denial(tenant.id, limit=limit)
            raise HTTPException(403, detail={
                "error": "limit_reached", "limit": limit,
                "used": used, "cap": cap,
                "upgrade_url": "/settings/billing",
            })
    return Depends(dep)

# app/invoicing/router.py — consumption reads like this:
@router.post("/invoices", dependencies=[enforce_limit("invoices_per_month")])
async def create_invoice(...): ...

@router.post("/invoices/{id}/reminders", dependencies=[require_feature("reminders")])
async def schedule_reminder(...): ...
```

Finally, the same truth is exported once for every UI:

```python
# app/billing/router.py
@router.get("/billing/entitlements", response_model=EntitlementsOut)
async def get_entitlements(tenant=Depends(current_tenant),
                           session=Depends(get_session)):
    ent = await resolve(session, tenant.id)
    usage_now = await usage.snapshot(session, tenant.id, ent.limits)
    return EntitlementsOut.from_domain(ent, usage_now)
```

The Next.js frontend fetches this once per session (React Query, Stage 4 Ch 04) and gates
buttons, menus, and upsell banners from it. No limit number exists in frontend code; the
pricing page itself renders from the catalog. One definition, three consumers: API
enforcement, UI gating, marketing display.

## Engineering Decisions

### Which value metric?

Score candidates against the four properties in the Mental Model, using real usage data —
this is why even the MVP instrumented its core loop. Invoicely rejected seats-only (value
decoupled, login-sharing), rejected percentage-of-revenue (measurable but trust-hostile for
SMBs), and chose invoices/month as the metered axis with seats as a secondary fence. The
general rule: meter the thing customers already think of as "using the product more," and
never meter the thing you want them to do *more* of for growth reasons — Invoicely meters
invoices on Free but would never meter *payment links clicked*, because every link click
recruits the next customer (Chapter 07).

### Plans in code or in the database?

Start in code, as `catalog.py`: reviewable in PRs, versioned in git, deployable, impossible
to edit in a panic at 2am. Move the catalog to a table only when a non-engineer must change
it without a deploy, or plans multiply into regional/experimental variants — and keep the
resolver interface identical so consumers never notice. What must be in the database from
day one regardless: the *subscription* (which tenant is on what) and the *overrides* —
because those change at customer speed, not deploy speed. The hybrid is the point: catalog
changes are engineering events; who-is-on-what is runtime data.

### Grandfather or migrate on price changes?

Grandfather by default — it is one appended catalog version and it honors the promise early
customers took a risk on; forced migrations are the classic trigger for churn spikes and
public anger. Migrate (with generous notice and a discount bridge) only when the old terms
are genuinely unsustainable or the plan structure itself is being retired. The schema makes
both cheap; the *policy* should be written down before the first change, because deciding it
during the change means deciding under revenue pressure. Sunset grandfathered versions by
attrition, not eviction.

### Hard limits or soft limits?

Match the limit's failure mode to the customer's moment. Invoicely's Free invoice cap is
*hard* — the sixth invoice is exactly the upgrade moment, and the denial payload sells the
upgrade. But a *Business* customer hitting a seat cap mid-onboarding, or an API integration
hitting a rate ceiling during the customer's month-end run, gets *soft* treatment: warn at
80% (email + banner, wired in Chapter 04's events), allow brief overage, notify, then block.
Blocking a paying customer from serving *their* customers converts a pricing mechanism into
an outage. Hard limits guard acquisition tiers; soft limits guard relationships.

### Where does enforcement live?

In the API layer, as dependencies, and nowhere else — with two deliberate exceptions.
Frontend gating exists for *experience* (don't show buttons that will 403) but is never the
control; anything enforced only in React is free via curl. And one class of limit gets a
database backstop: seats, where a unique-count constraint protects against the race of two
parallel invites — the same defense-in-depth logic as Stage 6's constraint discipline.
Background jobs and the public API route through the same dependencies; the reminder worker
checks `reminders` the same way the endpoint does, or canceled customers keep getting
service.

### What does the trial trial?

A 14-day full-featured Business trial, card optional — the goal is for the user to *hit
value* (first invoice paid) before the paywall, and trial-to-paid conversion is the number
that arbitrates (Chapter 06). Trials are a subscription `status`, not a plan — `trialing`
resolves to Business entitlements; expiry flips the status and the resolver's lapsed-billing
branch lands the tenant on Free terms with their data intact but gated. Never delete data on
downgrade; gate *creation*, keep *access* read-only — hostage data is churn with a grudge.

## Trade-offs

| Choice | You gain | You pay |
|---|---|---|
| Usage-based (value metric) pricing | Price tracks value; small customers start cheap | Revenue less predictable; buyers fear surprise bills; requires metering you must build |
| Per-seat pricing | Legible, predictable, industry-default | Decoupled from value; punishes collaboration; invites login-sharing |
| Flat tiers only | Simplest to sell, bill, and build | Big customers subsidized by design; money left on the table at the top |
| Free tier | Acquisition channel; growth-loop fuel (Ch 07) | Real serving cost; support load; must be limit-budgeted or it's an unbounded liability |
| Trial instead of free tier | Everyone evaluates the full product; cleaner demand signal | Smaller top-of-funnel; time pressure can precede value for slow-adopting users |
| Grandfathering price changes | Keeps promises; smooth changes; low churn risk | Version sprawl to support; old terms linger for years; revenue uplift arrives slowly |
| Migrating everyone | Immediate uniform revenue; one live version | Churn spike; trust damage; the announcement everyone screenshots |
| Plans as code (`catalog.py`) | Reviewed, versioned, testable, deploy-gated | Marketing waits on a deploy for every experiment |
| Plans as database rows | Runtime changes, experiments, regional variants | Editable in a panic; needs its own audit trail and admin UI |
| Overrides table for custom deals | Sales flexibility with an audit trail; zero new code paths | Every override is revenue complexity; expiring ones need reaping; sprawl must be reviewed |
| Hard limits everywhere | Simple; costs perfectly controlled | Blocks paying customers at their worst moment; support fires |

The metric trade-off deserves its sharp edge: **the best pricing model for the spreadsheet
is rarely the best one for trust** — percentage-of-revenue scored highest on Invoicely's
value alignment and lost anyway, because a price the buyer experiences as a tax on success
poisons the relationship the rest of this stage depends on.

## Common Mistakes

- **Branching on plan names.** `if ent.plan == "professional"` is the same bug as
  `if plan == "pro"` with extra steps — the `plan` field on `Entitlements` exists for
  display and analytics. The moment code branches on it, tier renames and custom deals
  break behavior. Branch on capabilities, always.
- **Enforcing in the frontend only.** The hidden "API keys" tab whose endpoint never checks
  `api_access`. Every entitlement the UI gates, the API must gate independently — the UI is
  UX, the dependency is the control.
- **Two sources of truth for limits.** The backend enforces 5 invoices; the frontend's
  hard-coded banner says 3; the pricing page says "up to 10." All three must render from
  the catalog — drift here is a refund conversation.
- **Metering without an index plan.** `usage.count()` runs on every gated request; a
  `COUNT(*)` over an unindexed month of invoices is Chapter 05-of-Stage-6 homework left
  undone. Metered limits need either a covering index or a counter (Redis, reconciled
  nightly) from day one.
- **Forgetting the downgrade path.** Downgrade drops seats from 5 to 1 — and the code that
  assumed `seats_purchased` only grows strands four users, or worse, deletes them. Every
  limit needs an answer for "what happens to existing usage above the new cap" (Invoicely:
  read-only access, block creation).
- **Free tier without a budget.** No caps on storage, email sends, or PDF renders because
  "free users are small" — until one script-runner isn't. Free-tier limits are cost
  controls first, upgrade prompts second; both jobs need numbers.
- **Silent denials.** Returning a bare 403 and logging nothing. Every denial is a user
  telling you what they'd pay for — `log_denial` feeds the upgrade funnel (Ch 04) and the
  packaging review (Ch 06). Discarding it is discarding purchase intent.
- **Letting overrides rot.** Two years of expired trials, lapsed deals, and "temporary"
  limit raises nobody reaps. Overrides need `expires_at` honored by the resolver and a
  quarterly review — they are contractual promises, not settings.

## AI Mistakes

The three tools converge on the same wreck from different directions: pricing logic
scattered where it cannot be changed.

### Claude Code: gating by plan name, everywhere it edits

Asked to "make reminders a Pro feature," Claude Code does exactly that — locally, per file:
`if subscription.plan in ("professional", "business")` in the reminders endpoint, a similar
check in the reminder worker, a third in the email template renderer. Each is correct today.
Collectively they hard-code the tier structure into three layers, and the next request —
"add a Starter tier with reminders" — silently misses one of them, shipping a tier whose
paid feature works in the API but not in the worker. The model reaches for the check that
is visible in the file it's editing, not the layer the architecture wants.

**Detect:** `grep -rn '"professional"\|"business"\|plan ==' app/ | grep -v billing/` — plan
literals outside the billing module are the finding, whoever authored them. **Fix:** the
entitlement layer must exist *before* the first gating request, and CLAUDE.md must state
the rule ("gate features via `require_feature`; plan names never appear outside
`app/billing/`"). Then the assistant's local instinct lands on the right abstraction,
because it's the one the codebase demonstrates.

### GPT: textbook packaging, unmoored from the value metric

Asked to design pricing, GPT produces the archetype: three tiers, $9/$29/$99, per-seat,
"Most Popular" badge on the middle one, feature matrix included. It is the *median* SaaS
pricing page — which is exactly the problem, because it is pattern-completion over pricing
pages, not reasoning over *your* value metric. Per-seat pricing for Invoicely decouples
price from value (the deliberation table in the Mental Model), and $9 anchors the product
as a utility when the message is "get paid faster." Teams ship it because it looks like
what pricing is supposed to look like.

**Detect:** proposed packaging that never references how value accrues in your usage data;
prices in the 9/29/99 pattern with no stated reasoning; seat pricing for single-player
products. **Fix:** run the value-metric scoring first, with your data, and hand the model
the chosen metric and segments as constraints — it is genuinely useful for enumerating
fence features and stress-testing tier boundaries *within* a metric it didn't choose.

### Cursor: the limit constant, duplicated into drift

Autocompleting the React usage banner, Cursor helpfully inlines `const FREE_INVOICE_LIMIT =
5` — copied from the backend value it saw in context. It compiles, renders, ships. Six
months later the Free cap moves to 3 in `catalog.py`, and the frontend now promises 5,
blocks at 3, and generates a support thread with screenshots. The same completion pattern
plants limit numbers in emails, marketing components, and mobile code — every one a fork of
the catalog that will not follow it.

**Detect:** numeric literals matching catalog values anywhere outside `catalog.py`; any
frontend constant whose name contains `LIMIT`, `MAX`, or a plan name. **Fix:** the
entitlements endpoint is the only limit source clients may read; add a lint/grep CI check
for catalog numbers in frontend code, and review autocomplete diffs for constants with
suspicious specificity.

## Best Practices

- **One resolver, one enforcement idiom, zero plan names outside billing.** The three-rule
  summary of the whole system. Enforce the third rule mechanically (CI grep) — conventions
  that depend on memory lose to autocomplete.
- **Version plans immutably; append, never edit.** A price change is a new `PlanVersion`
  plus a `CURRENT_VERSIONS` bump. Existing subscriptions keep their pinned version until a
  deliberate migration moves them. Git history plus immutable versions equals a complete
  audit trail of every promise ever on the pricing page.
- **Make every denial a doorway.** Structured error payloads with the capability name,
  current usage, and an upgrade URL; UI that renders them as an upgrade moment, not a dead
  end; `log_denial` on every path. The pricing system doubles as the top of the upgrade
  funnel.
- **Warn before you wall.** 80%-of-limit events drive a banner and an email (Chapter 04
  wires them); nobody should discover a cap by hitting it mid-task. For paying tiers,
  prefer soft limits with notification over hard stops.
- **Render the pricing page from the catalog.** The marketing site imports (or fetches) the
  same data the enforcer uses. If that's impractical across repos, a contract test pinning
  page numbers to catalog numbers is the minimum — drift between promise and enforcement is
  the most public bug pricing can have.
- **Give sales the overrides table, not a fork.** Every custom deal is a row with a reason
  and an expiry — reviewable, reapable, and invisible to application code. The alternative
  is the bespoke-deal shantytown (below).
- **Review packaging quarterly against denial and usage data.** Which limits are hit, which
  features go unused per tier, where trials stall — Chapter 06's metrics turn this from
  opinion exchange into a working session. Pricing is a hypothesis; schedule its review.
- **Test entitlements as behavior.** The permission matrix — tier × capability × over/under
  limit — is a parametrized test suite (Stage 8 Ch 02), not a manual QA pass. It is the
  spec of what every tier buys; run it on every catalog change.

## Anti-Patterns

- **The plan enum.** `class Plan(Enum): FREE, PRO, BUSINESS` imported by forty files. It
  feels type-safe; it is the hard-coding with compiler assistance. Adding a tier now
  touches every consumer; a custom deal cannot exist at all. Capabilities are the type
  boundary, not tiers.
- **The bespoke-deal shantytown.** Enterprise deal #1 lands as `if tenant_id ==
  ACME_CORP_ID` — deal #7 makes the codebase a contract archive nobody can safely refactor.
  The overrides table exists so that sales flexibility costs rows, not branches.
- **Entitlements resolved everywhere.** Every module querying `Subscription` directly and
  applying its own interpretation of what "business" includes — the resolver logic,
  copy-pasted into inconsistency. One function resolves; everyone else consumes its output.
- **The pricing page as fiction.** Marketing edits the page; engineering edits the catalog;
  quarterly, someone notices "unlimited" means 1,000. The page renders from the catalog or
  gets contract-tested against it — there is no acceptable third state.
- **Punitive downgrades.** Deleting data, breaking links, or holding exports hostage when a
  customer drops tiers — churn converted into reputational damage. Gate creation, preserve
  access, make leaving safe; the customers who return (and they do) return because leaving
  was safe.
- **Metering the growth loop.** Charging for — or capping — the actions that acquire the
  next customer: Invoicely capping payment-link views, a referral product capping invites.
  The value metric and the growth loop (Ch 07) must be different axes, or the pricing
  system strangles distribution.

## Decision Tree

```
Designing (or reworking) pricing — in order:
│
├─ 1. VALUE METRIC: what unit does customer value scale with?
│     Score candidates: grows with value / legible to buyer /
│     cleanly measurable / hard to game — against USAGE DATA
│     (Ch 04), not intuition. Never meter the growth loop.
│
├─ 2. SEGMENTS → TIERS: who are the 2–4 distinct customer
│     populations, and what FENCE feature does each structurally
│     need (seats, API, white-label)? One tier per segment;
│     the top tier may exist partly to anchor the middle.
│
├─ 3. FREE TIER OR TRIAL?
│     ├─ Product has a growth loop free users fuel (Ch 07),
│     │  and serving cost per free user is budgetable
│     │      → free tier, with limits sized as cost controls
│     └─ Value needs full features to demonstrate, or free
│        users cost real money → time-boxed full trial instead
│
├─ 4. MODEL IT:
│     plans = versioned data (code first, table when a
│     non-engineer must change it) · subscription pins
│     (plan, version) · custom deals = overrides w/ expiry
│     · resolver is the only reader · enforcement = API
│     dependencies · UI + pricing page read the same source
│
├─ 5. PER LIMIT: hard or soft?
│     ├─ Acquisition tier, limit IS the upgrade prompt → hard,
│     │  with a denial payload that sells the next tier
│     └─ Paying tier, limit guards cost/abuse → warn at 80%,
│        brief overage, notify, then block
│
└─ 6. PRICE CHANGE LATER?
      ├─ Terms sustainable → append new version, grandfather
      │  existing, sunset by attrition
      └─ Terms unsustainable / structure retired → migrate
         with long notice + bridge discount, and measure the
         churn you chose to buy
```

## Checklist

### Implementation Checklist

- [ ] Plan catalog exists in exactly one place, with immutable versions and integer-cent
      prices; a price change is an appended version.
- [ ] Subscriptions pin `(plan, plan_version)`; lapsed/canceled status resolves to free-tier
      terms without deleting data.
- [ ] Custom deals are `PlanOverride` rows with `reason` and `expires_at` — and the
      resolver honors expiry.
- [ ] One resolver function produces `Entitlements`; results are cached with a short TTL
      and invalidated on subscription/override writes.
- [ ] Enforcement is FastAPI dependencies (`require_feature` / `enforce_limit`) on every
      gated endpoint, worker, and public-API route.
- [ ] Metered limits have a performant count: covering index or reconciled counter.
- [ ] Denials return structured payloads (capability, usage, cap, upgrade URL) and are
      logged as events.
- [ ] `GET /billing/entitlements` serves UI gating and usage display; no limit constant
      exists in frontend code.

### Architecture Checklist

- [ ] No plan name appears outside `app/billing/` — enforced by a CI grep, not convention.
- [ ] Application code branches on capabilities, never on tiers; `Entitlements.plan` is
      display/analytics only.
- [ ] The value metric is chosen from usage data, documented in an ADR with the rejected
      candidates and why.
- [ ] The grandfathering policy is written down before the first price change.
- [ ] Downgrade behavior is defined per limit (typically: gate creation, preserve read
      access); no path deletes customer data on tier change.
- [ ] Free-tier limits have a cost budget attached, not just an upgrade rationale.
- [ ] The pricing page renders from the catalog or is contract-tested against it.
- [ ] The seam with billing (Ch 03) is the subscription row: payments writes
      `plan/version/status`, entitlements reads — nothing else crosses.

### Code Review Checklist

- [ ] New gated functionality declares its requirement in the endpoint signature — no
      inline plan/entitlement checks in handler bodies.
- [ ] No numeric limit or plan-name literal outside the catalog (check generated frontend
      code especially).
- [ ] New limits ship with: the 80% warning event, the denial payload, the downgrade
      answer, and a usage-count query that was EXPLAINed at realistic volume.
- [ ] Changes to the catalog include a matching change to the entitlement test matrix.
- [ ] Background jobs and API-key routes touched by the diff enforce the same entitlements
      as their interactive equivalents.
- [ ] AI-generated diffs checked for the three signatures: plan-name branches, duplicated
      limit constants, textbook tiers nobody chose.

## Exercises

1. **Score the value metric.** For a product you know well, list four candidate value
   metrics and score each against the four properties (grows with value, legible,
   measurable, hard to game) using whatever real usage data you have. Write the one-page
   ADR: chosen metric, scores, and the strongest argument *against* your choice.
2. **Build the entitlement layer.** Implement `catalog.py`, the resolver, and both
   dependencies for a service you have (or the Stage 3 Invoicely codebase): two tiers, one
   feature gate, one metered limit. Write the parametrized test matrix — tier × capability
   × over/under limit — before the implementation, per Stage 8's discipline.
3. **Hunt the hard-coding.** On a codebase you work with (or an assistant-generated SaaS
   scaffold): `grep` for plan-name literals, tier enums, and numeric limits outside any
   billing module. For each hit, trace what breaks when a tier is renamed and a custom
   deal is cut. Estimate the refactor; compare it to the cost of Exercise 2.
4. **Run the price change.** Take Exercise 2's system and ship a price increase on the paid
   tier: append the version, bump `CURRENT_VERSIONS`, verify existing test subscriptions
   keep old terms and new signups get new ones — all without touching a consumer. Then
   write the customer-facing announcement, including what grandfathered customers keep.
5. **Audit an AI's pricing proposal.** Prompt an assistant to design pricing for your
   product with no constraints; then re-prompt with your value metric, segments, and fence
   features from Exercise 1. Diff the two proposals against this chapter's decision tree:
   which tier boundaries survived, and what did the unconstrained version get structurally
   wrong?

## Further Reading

- Madhavan Ramanujam, Georg Tacke — *Monetizing Innovation* — the strongest book-length
  case for designing the product around the price (and the value metric) instead of the
  reverse; the source of the "willingness to pay comes first" discipline.
- Neil Davidson — *Don't Just Roll the Dice* — short, free, and written for software
  founders: pricing psychology, anchoring, and versioning without the MBA scaffolding.
- Patrick Campbell / Paddle (formerly ProfitWell) — the recurring pricing-benchmark essays —
  the empirical base for "pricing outleverages acquisition," value-metric selection, and
  freemium economics; read the methodology, not just the charts.
- Stripe documentation — *Entitlements* and *Usage-based billing* — how the largest
  billing platform models features and metering; useful as a sanity check on your own
  entitlement schema even if you never use theirs.
- Kyle Poyar — *Growth Unhinged* essays on usage-based pricing — when metered pricing
  works, when it terrifies buyers, and hybrid models that hedge both.
- Stage 1, Chapter [06 (Build vs Buy)](../stage-01-engineering-mindset/06-build-vs-buy.md) —
  the framework behind "Stripe Checkout, not card forms" and every vendor decision this
  stage makes.
- Stage 3, Chapters [04 (Authorization)](../stage-03-backend-engineering/04-authorization.md)
  and [07 (Caching)](../stage-03-backend-engineering/07-caching.md) — the enforcement
  idiom and the cache discipline the resolver builds on.

# Product Metrics

## Introduction

A SaaS business is legible through a handful of numbers — recurring revenue and its
movements, churn, activation, retention — and every one of them is a *computed* artifact.
Nobody observes MRR; someone writes a query that defines it, and every strategic decision
downstream inherits that query's choices. Does MRR include the customer whose card failed
yesterday? Is the annual plan twelve units of revenue in January or one unit in each month?
Did the tenant who canceled on the 20th churn this month or when their paid period ends?
Each question has multiple defensible answers, and a team that hasn't chosen one has
several — one per dashboard, disagreeing quietly until a board meeting makes it loud.

This is why product metrics is an engineering chapter and not a business-school appendix.
The failure mode is not ignorance of what churn means; it is a metrics layer that computes
it three ways, from the wrong source tables, with edge cases resolved by whoever wrote
each query. The craft is the same one Stage 6 taught for schemas: explicit definitions,
one source of truth per fact, history that can be queried, and tests that pin the
computation to known answers.

This chapter builds Invoicely's metrics layer on the data the stage has produced: revenue
metrics computed from the billing tables Chapter 03 keeps synchronized (never from
analytics events), behavioral metrics from the application database and Chapter 04's
instrumentation, a monthly snapshot table because mutable rows cannot answer historical
questions, SQL views as the single vocabulary every dashboard reads, and fixture tests
that make "what does churn mean here?" a fact of the codebase. Chapter 05 supplied the
qualitative half of steering; this chapter supplies the quantitative half — and Chapter 07
spends both.

## Why It Matters

- **Every steering decision compounds on these numbers.** Pricing reviews (Ch 02), dunning
  tuning (Ch 03), the roadmap arbitration Chapter 05 promised, the growth bets of Chapter
  07, hiring plans, fundraising — all downstream of MRR, churn, and retention. An 11%
  error in MRR (Invoicely's, below) is not an 11% error in decisions; it is a wrong-sign
  error in whichever decision sat near the threshold.
- **Disagreeing dashboards destroy more than accuracy — they destroy the habit of looking.**
  The first time two reports give two MRRs, every number acquires an asterisk, and the
  team reverts to steering by anecdote (the failure Chapter 04 spent a chapter preventing).
  Trust in metrics is binary and expensive to rebuild; a single metrics layer is its
  insurance premium.
- **Definitions are where metric lies live.** "Churn improved" can mean the business got
  better — or that someone moved past-due tenants out of the denominator. Undocumented
  definitions make metrics ungameable in the worst way: not deliberately falsified, just
  silently redefined until they flatter. A written contract per metric is the difference
  between measurement and mood.
- **History is not reconstructable after the fact.** The `Subscription` row is mutable —
  Chapter 03's sync overwrites status and plan in place. The question "what was our MRR on
  March 1?" cannot be answered by any query over current rows; it requires having
  *snapshotted* March. Teams discover this the week an investor asks for the growth chart,
  which is the most expensive possible time.
- **AI assistants make plausible metrics effortless — and plausible is the hazard.** Ask
  for a churn query and you'll get one: syntactically clean, reasonable-looking, and
  wrong in one of the four standard ways (denominator, cohort, window, edge case) that
  only a fixture test or a hand-count catches. Metrics code looks like the easiest SQL in
  the company and carries the highest cost per silent defect.

## Mental Model

Three ideas carry the chapter: metrics form a tree with value at the root, a metric is a
written contract, and every metric is computed once, from its source of truth.

**1. The metric tree: one North Star, decomposed into drivers you can act on.** The North
Star measures *value delivered to customers* — chosen so that moving it is good for both
sides. Revenue follows value; a tree rooted directly in revenue optimizes extraction.

```
  NORTH STAR: invoice value PAID through Invoicely per month
  (customers got paid; Invoicely's promise, measured)
        │
  ├── ACQUISITION  signups/wk, by source          (Ch 07 feeds this)
  ├── ACTIVATION   % of new tenants with a PAID   ← the moment the
  │                invoice within 14 days           promise lands
  ├── RETENTION    week-4 tenant retention;        ← compounds; the
  │                logo & revenue churn /mo          tree's true trunk
  ├── REVENUE      MRR + movements: new /
  │                expansion / contraction /
  │                churned / reactivation; NRR
  └── REFERRAL     invites & recipient signups    (the Ch 07 loop)

  Each node: a LAGGING truth (churn) paired with a LEADING
  signal you can act on this week (reminders configured in
  week 1 predicts week-4 retention). Lagging numbers judge;
  leading numbers steer.
```

**2. A metric is a contract: numerator, denominator, window, cohort, edge cases, owner.**
"Churn rate" is not a metric; it is a family of metrics. The contract makes one member of
the family official:

```
  METRIC: logo churn (monthly)
  numerator    tenants whose PAID PERIOD ENDED in month M
               without renewal (status → canceled, per Ch 03's
               state machine — cancel-at-period-end counts in
               the month the period ends, not when clicked)
  denominator  paying tenants at the START of month M
               (mid-month joiners excluded — they can't churn
               from a base they weren't in)
  window       calendar month, UTC
  excludes     trialing (never paid → can't churn; that's
               trial conversion's job), free tier
  edge cases   past_due ≠ churned until dunning exhausts;
               reactivation within same month nets to zero
  owner        whoever must explain it to the board
```

Every choice above has a defensible alternative — that is exactly why it must be written
down. The contract turns "our churn is 2.1%" from a claim into a computation anyone can
re-run.

**3. One computation per metric, reading its source of truth.** Facts have homes:
revenue facts live in the billing tables Chapter 03 reconciles against Stripe nightly;
product-behavior facts live in the application database; engagement texture lives in
Chapter 04's events. The cardinal sins are crossing sources (revenue from lossy analytics
events) and duplicating computations (each dashboard with its own MRR `SELECT`). The
architecture that prevents both is boring and correct: a metrics layer — SQL views over
snapshots — that every consumer reads and none re-derive.

A working definition:

> **Product metrics are the computed contracts a business steers by: a North Star
> measuring value delivered, decomposed into acquisition, activation, retention, and
> revenue drivers — each defined in writing (numerator, denominator, window, edge cases,
> owner), computed exactly once from its source-of-truth tables over immutable snapshots,
> exposed through one metrics layer that every dashboard reads, and pinned by tests to
> known answers so that a change in the number means the business changed, not the SQL.**

## Production Example

The trigger is the classic one. Invoicely's founder pulls MRR for a partner review from
the admin dashboard: **$61,400**. The ops spreadsheet, fed by a Stripe export, says
**$55,200**. The 11% gap decomposes into three definition drifts, none of them a "bug":
the dashboard counted `trialing` tenants at full price (Business trials — $49 of MRR per
tenant that never agreed to pay); it divided annual plans by their *discounted* monthly
equivalent in one query and by 12 in another; and the spreadsheet had silently dropped
`past_due` tenants that the dashboard kept. Three reasonable choices, made by three
authors, never written down.

The fix is this chapter's system, built in a week. A definitions document —
`metrics/DEFINITIONS.md` — makes the calls: MRR counts `active` and `past_due` (they owe;
dunning is still working), excludes `trialing`; annual normalizes to `yearly_price / 12`;
churn is recognized at period end. A nightly job snapshots every paying subscription into
an append-only table. Views compute MRR, movements, churn, NRR, activation, and week-4
retention from the snapshots and the application tables. The two dashboards are rebuilt to
read the views — the spreadsheet is retired in favor of a monthly reconciliation check
against Stripe's own reporting (drift > 1% alerts, echoing Chapter 03's reconciliation
discipline). And the numbers get a weekly ritual: thirty minutes, the tree from the Mental
Model on one screen, Chapter 05's synthesis on the other.

The payoff arrives in the same quarter: with trustworthy movements, the team can finally
see that gross MRR churn (2.8%) is dominated not by cancellations but by *contraction* —
Business tenants downgrading to Professional after their accounting-firm contracts end —
which reframes the retention conversation entirely (the Chapter 05 Xero finding suddenly
has a number attached), and hands Chapter 07 its first properly-instrumented growth
target: activation, stuck at 34%.

## Folder Structure

The metrics layer lives with the code because it *is* code — reviewed, versioned, tested:

```
app/
├── metrics/
│   ├── DEFINITIONS.md        # the contracts: one section per metric —
│   │                         #   numerator/denominator/window/edges/owner
│   ├── snapshots.py          # nightly Celery task: append-only monthly
│   │                         #   subscription snapshots
│   ├── views/                # the metrics layer — plain SQL, one file per view
│   │   ├── mrr.sql
│   │   ├── mrr_movements.sql
│   │   ├── churn.sql
│   │   ├── activation.sql
│   │   └── retention.sql
│   ├── apply_views.py        # migration-style: create or replace views (Alembic
│   │                         #   owns tables; this owns the derived layer)
│   └── router.py             # GET /internal/metrics/* for the admin dashboard
└── ...
tests/
└── metrics/
    ├── conftest.py           # fixture tenants with known lifecycles
    └── test_metrics.py       # known-answer tests: THIS data → THAT number
```

Why each piece exists: `DEFINITIONS.md` is the contract document — the PR that changes a
definition changes this file, visibly, or the change didn't happen. `snapshots.py` exists
because Chapter 03's `Subscription` row is mutable by design; history must be captured,
not reconstructed. `views/` is the single vocabulary — dashboards, the internal API, and
ad-hoc analysis all `SELECT` from the same names, so a definition change propagates
everywhere or nowhere. `apply_views.py` keeps the derived layer in migrations' spirit
(reviewed, ordered, reproducible) without pretending views are tables. The tests direct
this chapter's whole argument: metrics whose SQL isn't pinned to known answers are
opinions with a `GROUP BY`.

## Implementation

The snapshot — the append-only fact that makes history queryable. One row per paying
tenant per month, written by a Celery beat task on the 1st (and backfillable from
Chapter 03's `BillingAuditLog` if adopted late):

```python
# app/metrics/snapshots.py
class SubscriptionSnapshot(Base):
    """Append-only. What each paying tenant looked like at month start.
    Written once, never updated — the mutable Subscription row is for NOW;
    this table is for EVER."""
    __tablename__ = "subscription_snapshots"

    month: Mapped[date] = mapped_column(primary_key=True)      # first of month
    tenant_id: Mapped[UUID] = mapped_column(primary_key=True)
    plan: Mapped[str]
    plan_version: Mapped[int]
    status: Mapped[str]                                        # active | past_due
    mrr_cents: Mapped[int]           # normalized at write: monthly price, or
                                     # yearly/12 — from the Ch 02 catalog, so the
                                     # normalization rule lives in ONE place

@celery_app.task
def snapshot_subscriptions() -> None:
    month = utcnow().date().replace(day=1)
    with session_scope() as session:
        for sub in paying_subscriptions(session):              # active + past_due
            session.add(SubscriptionSnapshot(
                month=month, tenant_id=sub.tenant_id,
                plan=sub.plan, plan_version=sub.plan_version, status=sub.status,
                mrr_cents=normalized_mrr_cents(sub),           # catalog-driven
            ))
```

MRR and its movements — the month-over-month join that classifies every dollar's story.
The `FULL OUTER JOIN` is the whole trick: a tenant present last month and absent now is
churn; the reverse is new (or reactivation); present in both with a different amount is
expansion or contraction:

```sql
-- app/metrics/views/mrr_movements.sql
CREATE OR REPLACE VIEW mrr_movements AS
WITH paired AS (
    SELECT COALESCE(curr.month, prev.month + INTERVAL '1 month')::date AS month,
           COALESCE(curr.tenant_id, prev.tenant_id)                    AS tenant_id,
           COALESCE(prev.mrr_cents, 0)                                 AS prev_cents,
           COALESCE(curr.mrr_cents, 0)                                 AS curr_cents
    FROM subscription_snapshots curr
    FULL OUTER JOIN subscription_snapshots prev
      ON prev.tenant_id = curr.tenant_id
     AND prev.month = curr.month - INTERVAL '1 month'
)
SELECT month,
       SUM(curr_cents) FILTER (WHERE prev_cents = 0
           AND NOT was_ever_paying_before(tenant_id, month))   AS new_cents,
       SUM(curr_cents) FILTER (WHERE prev_cents = 0
           AND was_ever_paying_before(tenant_id, month))       AS reactivation_cents,
       SUM(curr_cents - prev_cents) FILTER
           (WHERE prev_cents > 0 AND curr_cents > prev_cents)  AS expansion_cents,
       SUM(prev_cents - curr_cents) FILTER
           (WHERE curr_cents > 0 AND curr_cents < prev_cents)  AS contraction_cents,
       SUM(prev_cents) FILTER (WHERE curr_cents = 0)           AS churned_cents
FROM paired
GROUP BY month;

-- Net new MRR = new + reactivation + expansion − contraction − churned.
-- NRR (month) = (start + expansion − contraction − churned) / start,
--   computed over the same pairs — one source, both numbers.
```

Churn, per the contract (period-end recognition, start-of-month denominator):

```sql
-- app/metrics/views/churn.sql
CREATE OR REPLACE VIEW monthly_churn AS
SELECT prev.month + INTERVAL '1 month'          AS month,
       COUNT(*) FILTER (WHERE curr.tenant_id IS NULL)::numeric
           / NULLIF(COUNT(*), 0)                AS logo_churn_rate,
       SUM(prev.mrr_cents) FILTER (WHERE curr.tenant_id IS NULL)::numeric
           / NULLIF(SUM(prev.mrr_cents), 0)     AS gross_mrr_churn_rate
FROM subscription_snapshots prev
LEFT JOIN subscription_snapshots curr
  ON curr.tenant_id = prev.tenant_id
 AND curr.month = prev.month + INTERVAL '1 month'
GROUP BY prev.month;
```

Activation — computed from the application's own tables, because "a paid invoice exists"
is an application fact (Chapter 04's events are for exploring the funnel's *shape*, not
for computing its official number):

```sql
-- app/metrics/views/activation.sql
CREATE OR REPLACE VIEW weekly_activation AS
SELECT date_trunc('week', t.created_at)::date                  AS cohort_week,
       COUNT(*)                                                AS signups,
       COUNT(*) FILTER (WHERE EXISTS (
           SELECT 1 FROM invoices i
           WHERE i.tenant_id = t.id
             AND i.status = 'paid'
             AND i.paid_at < t.created_at + INTERVAL '14 days'
       ))::numeric / NULLIF(COUNT(*), 0)                       AS activation_rate
FROM tenants t
GROUP BY 1;
```

And the tests that make the definitions real — fixture tenants with hand-computable
lifecycles, asserting exact answers:

```python
# tests/metrics/test_metrics.py
async def test_mrr_movements_classify_every_story(metrics_fixture):
    """Fixture: A pays $19 both months (no movement). B upgrades 19→49
    (expansion 30). C cancels (churn 19). D joins at 49 (new). E was a
    March customer, gone since, returns (reactivation). F is trialing
    (appears NOWHERE — trials are not MRR)."""
    row = await fetch_one("SELECT * FROM mrr_movements WHERE month = '2026-05-01'")
    assert row.new_cents == 4_900
    assert row.expansion_cents == 3_000
    assert row.churned_cents == 1_900
    assert row.reactivation_cents == 4_900
    assert row.contraction_cents == 0

async def test_annual_plan_normalizes_to_one_twelfth(metrics_fixture):
    """$490/yr Professional → 4_083 cents of MRR, in EVERY month of the
    term — not 49_000 in the purchase month."""
    ...
```

The admin dashboard's `router.py` serves these views; Chapter 03's monthly reconciliation
gains one more check (view MRR vs. Stripe's reported MRR, alert at >1% drift); and no
other `SELECT SUM` of money exists anywhere in the codebase.

## Engineering Decisions

### What is the North Star — and why not revenue?

Choose the number that measures *customers succeeding at the thing they hired you for* —
for Invoicely, invoice value paid through the platform. Revenue is the tree's fruit, not
its root: rooted in MRR, every driver conversation bends toward extraction (raise prices,
gate harder); rooted in value delivered, the drivers are the product getting better at its
job, and revenue follows through the pricing that Chapter 02 aligned with the same value
metric — the deliberate rhyme between those chapters. The test for a candidate North Star:
if it doubled while the business somehow got worse, would you notice? "Signups" fails that
test; "invoice value paid" does not.

### Where do metrics get computed?

SQL views over snapshots, on the read replica, until real limits force more. This is the
capability the team already has (Stage 6), zero new infrastructure, and one vocabulary.
The warehouse-and-dbt step is justified when the *joins cross systems* (product data +
support + marketing spend), when analysts outnumber the replica's patience, or when the
metrics layer needs its own release cycle — genuine thresholds, usually crossed well after
PMF, and Chapter 04's pre-PMF-warehouse warning applies verbatim. What does *not* move the
threshold: dashboard aesthetics. Grafana or Metabase reading the views covers years.

### Snapshot, or reconstruct from audit history?

Snapshot. Reconstruction from `BillingAuditLog` is possible (it's the backfill path) but
as the *primary* mechanism it makes every metric query re-derive state-at-time — complex,
slow, and re-implementing temporal logic per query. The snapshot trades a small append-only
table (thousands of rows per month, trivially indexed) for queries a junior engineer can
verify by hand — and hand-verifiability is a design goal here, because the metrics layer
is precisely the code where subtle wrongness costs the most. Monthly granularity matches
the business's rhythm; teams with mid-month repricing add a daily snapshot for the handful
of metrics that need it.

### When does churn count — cancel click or period end?

Period end. The customer who cancels on the 3rd has paid through the 30th; recognizing
churn at the click overstates this month, understates next, and — decisively — misclassifies
everyone the save-flow (Ch 07) wins back before expiry. Period-end recognition also aligns
logo churn with revenue churn (the dollars leave when the period ends) and with Chapter
03's state machine, where `cancel_at_period_end` is a flag on an *active* subscription,
not a terminal state. The cost: churn is a lagging indicator by up to a month — which is
what the leading signals in the tree (cancellation *requests*, dunning entries) are for.

### What counts as activated — and who decides?

The candidate definitions get tested against retention, not debated in a meeting. Take
three plausible activation events (created an invoice / sent one / got one *paid*, each
within 14 days), cohort last quarter's signups by each, and compare week-12 retention
curves. Invoicely's data makes it unambiguous: paid-invoice tenants retain at 3× the
merely-sent — so activation = first invoice *paid* within 14 days, and the onboarding
work of Chapter 07 aims at exactly that moment. Revisit annually: activation definitions
rot as the product and its users change.

### MRR is a management metric — where's the line against accounting?

MRR normalizes commitments into a monthly run-rate for *steering*; it is not revenue
recognition, not GAAP, and not what the accountant files. Annual prepay: cash today,
MRR of one-twelfth per month, recognized revenue per accounting rules — three different
numbers, all correct, for three different questions. The engineering obligation is
labeling: the definitions doc says what MRR is and is not, dashboards say "MRR" and never
"revenue," and the one metric investors will recompute (NRR) carries its cohort and
formula in a footnote. Blurring these lines is how the same company reports three
different "revenues" and gets all three doubted.

## Trade-offs

| Choice | You gain | You pay |
|---|---|---|
| North Star = value delivered | Aligned incentives; drivers = product improvements | One hop removed from money; needs the revenue tree beside it |
| North Star = revenue | Direct, board-legible | Every driver conversation bends toward extraction; gameable by pricing alone |
| Views over replica | Zero new infra; one vocabulary; SQL the team knows | Replica load from analysts; cross-system joins impossible |
| Warehouse + dbt | Cross-source joins; analyst autonomy; lineage tooling | A data platform to operate; pre-PMF it's Ch 01's over-building |
| Monthly snapshots | Hand-verifiable queries; tiny storage; matches business rhythm | Mid-month movements invisible; intra-month questions need the audit log |
| Reconstruct from audit log | No snapshot job; perfect granularity | Every query re-derives temporal state; unverifiable by hand; slow |
| Churn at period end | Matches money and the Ch 03 state machine; save-flow wins counted | Lags the cancel decision by up to a month |
| Churn at cancel click | Immediate signal | Overstates now, understates later; miscounts saves; diverges from revenue churn |
| Strict activation (paid invoice) | Predicts retention; aims onboarding at real value | Smaller number; slower to move; demoralizing if misread as failure |
| Loose activation (created invoice) | Flattering, fast-moving | Predicts little; onboarding optimizes a non-event |
| Small metric set, weekly ritual | Every number has attention and an owner | Some questions wait for ad-hoc analysis |
| The 40-KPI dashboard | Everything visible | Nothing watched; drift unnoticed; Goodhart's playground |

The snapshot trade-off deserves its sharp edge: **a metrics layer a junior engineer can
verify by hand beats a cleverer one nobody checks** — the entire value of these numbers is
trust, and trust is built by verifiability, not sophistication.

## Common Mistakes

- **Trials in MRR.** `trialing` tenants at full price — revenue from people who haven't
  agreed to pay. The 11% incident's biggest slice. MRR counts commitments: `active` and
  `past_due`, per the written contract.
- **Annual plans mangled.** Counted as 12× MRR in the purchase month (a growth spike that
  churns mathematically a year later), or divided by the wrong price (list vs. discounted).
  Normalize once, at snapshot write, from the catalog — the rule lives where the prices
  live.
- **Denominator drift.** Churn computed over "tenants at month end" or "all tenants ever"
  instead of paying-at-month-start; mid-month joiners polluting the base. The denominator
  is half the definition; write it down and test it.
- **Averaging ratios.** Q1 churn as `AVG(jan, feb, mar)` — three months of 2%, 2%, 8% on
  shrinking bases is not 4%. Aggregate numerators and denominators, then divide; or
  compound: quarterly retention = product of monthly retentions.
- **Revenue from analytics events.** MRR summed from `subscription_activated` events —
  lossy transport (Ch 04 said 25–40% client loss; even server events lag and drop) now
  determines the company's headline number. Money facts come from billing tables that
  reconcile against Stripe. No exceptions.
- **Cumulative charts as progress.** Total signups, total invoices ever — monotonically
  up-and-to-the-right by construction, information-free by the same construction. Plot
  rates and cohorts; reserve cumulative for capacity planning.
- **Cohort comparisons across incompatible windows.** January's week-4 retention (mature)
  against last week's (impossible) on the same chart, "trending down" by arithmetic
  necessity. Retention triangles exist precisely to keep maturity visible.
- **Definition drift as improvement.** Churn "improved" the month past-due handling
  changed; activation "doubled" when the window went from 7 days to 30. Any definition
  change gets: a `DEFINITIONS.md` diff, a backfilled restatement of history, and an
  annotation on every chart that crosses the boundary.

## AI Mistakes

The three tools produce the same artifact here — confident SQL over your own schema — and
three different ways for it to be quietly wrong.

### Claude Code: revenue computed from whatever's most visible

Asked to "add an MRR chart to the admin dashboard," Claude Code computes it from the most
discoverable source in context — the analytics events if Chapter 04's module is open, the
live Stripe API if `stripe_client.py` is, the mutable `Subscription` table (no history, so
it invents "MRR over time" by... plotting today's number) if neither. Each choice produces
a plausible chart; none matches the definitions contract; and the Stripe-API variant adds
a third-party call to an admin page that will be screenshotted into a board deck. The
failure is source selection, and it's invisible in the diff because every source *looks*
authoritative.

**Detect:** money aggregation reading anything other than the snapshot/billing tables —
`grep` for `SUM` near `mrr|price|amount` outside `app/metrics/`; an "MRR trend" with no
snapshot table behind it. **Fix:** the metrics layer must exist before the dashboards do,
and CLAUDE.md carries the rule ("revenue metrics read `metrics/views/*` only; dashboards
never aggregate money"). Then the assistant's discoverability instinct finds the right
source, because it's the one with the paved road.

### GPT: the textbook formula, misapplied with confidence

Asked for churn SQL, GPT produces the formula from every SaaS blog post — and misapplies
it to your schema in one of the standard ways: `status = 'canceled'` as the churn test
(counting all-time churn every month), `COUNT(*)` over all tenants as the denominator
(free and trialing included), cancel-click recognition against your period-end contract,
or `AVG()` over monthly rates for the quarter. The SQL is clean, the formula is nameable,
and the number is wrong by a factor that varies month to month — the worst kind of wrong,
because it correlates loosely with truth and survives eyeballing.

**Detect:** never eyeball metric SQL into production — run it against the fixture tenants
whose right answer is hand-computed; disagreement is the detection. Red flags for review:
status-based churn tests, denominators without a time anchor, any `AVG` of a ratio.
**Fix:** the known-answer test suite *is* the fix — write the fixture lifecycles first
(they're the definitions contract, executable), then let the model write SQL against
them; it is genuinely good at iterating to green once wrongness is visible.

### Cursor: the silent filter that redefines the metric

Autocompleting a dashboard query, Cursor adds the clause the surrounding code suggests:
`WHERE status = 'active'` (dropping `past_due` — there goes the contract),
`AND deleted_at IS NULL` (a soft-delete hygiene reflex that silently excludes churned
tenants from *historical* snapshots), `LIMIT 1000` (a habit from list endpoints, now
truncating an aggregate). Each is one autocompleted line inside a working query; each
quietly forks the definition; and the dashboard now disagrees with the view by 3% in a
way nobody can name. This is Chapter 02's constant-drift failure recurring at the query
layer.

**Detect:** dashboards writing their own aggregates instead of `SELECT`ing from the
views; any diff touching a `WHERE` clause in `metrics/views/`; unexplained small
disagreements between two renderings of "the same" number. **Fix:** structural — consumers
read views, only views, and the views directory is the single place metric `WHERE` clauses
may exist; plus the fixture tests, which fail on the dropped `past_due` the moment the
clause lands.

## Best Practices

- **Write `DEFINITIONS.md` before the first view.** One section per metric: numerator,
  denominator, window, cohort rules, edge cases, owner, and what the metric is *not* (MRR
  ≠ revenue). Changes to the file are changes to the business's language — review them
  like schema migrations.
- **Snapshot immutably, on a schedule, with a backfill path.** The beat task writes
  month-start rows; nothing updates them; `BillingAuditLog` can regenerate them if
  adopted late or corrected. Append-only is what makes every historical chart
  reproducible.
- **One metrics layer, all consumers.** Views (or, later, the warehouse's marts) are the
  only place metric logic lives. Dashboards, internal APIs, board decks, and ad-hoc
  analyses `SELECT` from the same names. A number that didn't come from the layer isn't
  the metric — it's a homonym.
- **Pin every metric with known-answer tests.** Fixture tenants whose lifecycles cover the
  edge cases (trial, annual, upgrade, downgrade, cancel, reactivate, past-due), asserted
  to exact cents and rates. The suite runs in CI; a definition change that doesn't touch
  a test didn't happen.
- **Reconcile the headline number against the outside world.** View-MRR vs. Stripe's
  reported MRR, monthly, alert at 1% — Chapter 03's discipline extended one layer up.
  Internal consistency is necessary; external agreement is what survives due diligence.
- **Pair every lagging metric with a leading one, and review weekly.** Churn ← cancellation
  requests and dunning entries; activation ← day-1 funnel steps; NRR ← seat growth. The
  weekly ritual reads the tree top-down, beside Chapter 05's synthesis — thirty minutes,
  owners named, one decision or a deliberate none.
- **Restate history when definitions change.** New activation window → backfill the cohort
  chart under the new contract and annotate the boundary. Mixed-definition charts are how
  teams gaslight themselves about progress.
- **Label the management/accounting boundary.** MRR, NRR, and churn are steering
  instruments; recognized revenue is the accountant's. Dashboards carry the right word,
  and nobody presents run-rate as revenue to anyone who files things.

## Anti-Patterns

- **The vanity dashboard.** Cumulative everything, all-time highs, a wall of green
  deltas — engineered (usually unconsciously) to reassure rather than inform. Its tell:
  no number on it has ever changed a decision. Kill it before it teaches the team that
  dashboards are decoration.
- **Metric sprawl.** Forty KPIs, each with a constituency, none with an owner — the
  numeric edition of Chapter 04's 400-event junk drawer. Attention is the scarce input to
  steering; a metric that gets no weekly attention should be an ad-hoc query, not a
  dashboard tile.
- **Dashboard-defined metrics.** Every chart shipping its own `SELECT`, definitions
  living in Grafana panels, Metabase questions, and one analyst's notebook — guaranteeing
  the 11% incident on a rolling basis. The layer exists so this can't.
- **Goodhart engineering.** Activation redefined looser the quarter it became an OKR;
  past-due reclassified the month churn hit the board deck; support pushing annual plans
  to juice "MRR growth" before the definition catches up. When a measure becomes a
  target, the *contract and its test suite* are the defense — definition changes get
  diffs, restatements, and review, or the numbers are negotiating instruments.
- **Revenue metrics from the analytics pipeline.** The event stream as MRR source —
  Chapter 04 built that pipeline lossy *on purpose* (fire-and-forget, never blocks the
  product). Using it for money inverts every design decision it was built on.
- **The metrics rewrite as procrastination.** Migrating views → dbt → semantic layer →
  metrics platform while activation sits at 34% and nobody has run the onboarding
  experiment. The layer is infrastructure for decisions; polishing it *instead of
  deciding* is Stage 1's rewrite trap with better branding.

## Decision Tree

```
"We need a metric for X" — in order:
│
├─ What decision will it steer, and who owns it?
│   ├─ None nameable → ad-hoc query, not a metric. Stop.
│   └─ Named ↓
│
├─ Write the contract FIRST (DEFINITIONS.md):
│   numerator / denominator / window / cohort / edge cases /
│   owner / what it is NOT. Defensible alternatives exist —
│   that's WHY it's written.
│
├─ What kind of fact is it?
│   ├─ MONEY (MRR, churn $, NRR, LTV) → billing tables +
│   │    snapshots. NEVER analytics events. Reconcile
│   │    externally (Stripe reports) monthly.
│   ├─ PRODUCT BEHAVIOR, official number (activation,
│   │    retention) → application DB over tenant/invoice
│   │    truth; events (Ch 04) explore the shape, DB
│   │    computes the number.
│   └─ ENGAGEMENT TEXTURE (funnel steps, feature reach)
│        → Ch 04's events, in the analytics tool, labeled
│          as directional.
│
├─ Does it need history?
│   ├─ YES (any trend) → compute over snapshots. If the
│   │    snapshot doesn't exist yet: create it NOW, backfill
│   │    from the audit log — history starts when capture does.
│   └─ NO (point-in-time) → current tables, but ask again
│        in a quarter; everything becomes a trend.
│
├─ Build: one view in metrics/views/ + fixture tenants +
│   known-answer tests. Consumers SELECT the view — no
│   dashboard writes its own aggregate.
│
└─ Operate: pair with a leading indicator; weekly review
    with an owner; definition changes = file diff + backfill
    restatement + chart annotation; retire metrics whose
    decisions retired.
```

## Checklist

### Implementation Checklist

- [ ] `DEFINITIONS.md` exists with the full contract per metric — numerator, denominator,
      window, cohort, edge cases, owner, and explicit non-meanings.
- [ ] Monthly subscription snapshots are append-only, written by a monitored scheduled
      task, with a documented backfill path from the billing audit log.
- [ ] MRR normalization (annual → /12, from the catalog) happens once, at snapshot write.
- [ ] Every metric is one view in `metrics/views/`; no consumer computes its own
      aggregate; the admin API serves the views.
- [ ] Known-answer fixture tests cover trial, annual, upgrade, downgrade, cancel,
      reactivation, and past-due lifecycles — asserted to exact values, running in CI.
- [ ] Trials are excluded from MRR; past-due handling matches the written contract;
      churn recognizes at period end.
- [ ] View-MRR reconciles against the provider's reported MRR monthly, with a drift
      alert.

### Architecture Checklist

- [ ] The North Star measures value delivered, sits in a written tree of drivers, and
      each lagging metric has a leading partner.
- [ ] Source-of-truth boundaries hold: money from billing tables, official behavior from
      the application DB, texture from events — enforced in review, checked by grep.
- [ ] Metrics run on the replica; the warehouse decision is deferred until cross-system
      joins or analyst load demand it, recorded as an ADR when taken.
- [ ] Definition changes require: the file diff, historical restatement, chart
      annotations, and updated tests — as a documented procedure.
- [ ] The weekly metrics review exists, reads the tree beside Ch 05's synthesis, and
      names owners for movements.
- [ ] Management metrics are labeled against accounting metrics everywhere both appear.

### Code Review Checklist

- [ ] New dashboards/reports `SELECT` from the metrics views — any inline money
      aggregation outside `app/metrics/` is a finding, whoever wrote it.
- [ ] Metric SQL changes come with fixture-test changes; a green suite on a definition
      change means the tests were wrong.
- [ ] No `AVG` of ratios; no status-based churn tests; denominators are time-anchored —
      the GPT-formula red flags, checked explicitly on generated SQL.
- [ ] Autocompleted `WHERE` clauses in metric queries (`status='active'`, soft-delete
      filters, `LIMIT`s) are verified against the contract, not the surrounding code's
      habits.
- [ ] Charts crossing a definition boundary carry the annotation.

## Exercises

1. **Write the contracts.** For your product (or Invoicely), write `DEFINITIONS.md` for
   five metrics: MRR, logo churn, gross revenue churn, activation, week-4 retention.
   For each, note one defensible alternative definition you rejected and what it would
   have flattered. Trade documents with a colleague and find where your "same" metrics
   disagree.
2. **Build the movement engine.** Implement the snapshot table and the `mrr_movements`
   view against the Chapter 03 schema. Write the fixture: seven tenants covering new,
   flat, expansion, contraction, churn, reactivation, and trial. Assert exact cents.
   Then break the view three subtle ways (drop past-due, mis-normalize annual, count
   trials) and confirm every break fails a test.
3. **Reproduce the 11% incident.** Compute MRR from a seeded dataset three ways: trials
   included, annual as 12× in month one, past-due dropped. Chart all three beside the
   contract number over six simulated months. Note which wrong variant *looks most
   like* the true one — that's the one that would have survived longest in production.
4. **Choose activation empirically.** With your own data (or the stage's event fixtures),
   cohort last quarter's signups by three candidate activation events and plot week-12
   retention per cohort. Pick the definition with the strongest separation, write its
   contract, and state the onboarding change it implies (you'll want it in Chapter 07).
5. **Audit the machine's SQL.** Ask an assistant for monthly churn and MRR queries
   against your schema, unconstrained. Run them against your fixture suite and catalog
   the failures using this chapter's taxonomy (source, denominator, window, edge case,
   silent filter). Then re-prompt with `DEFINITIONS.md` and the fixtures, and record
   how many iterations to green — that's your team's calibration for trusting generated
   metrics code.

## Further Reading

- David Skok — "SaaS Metrics 2.0" (forEntrepreneurs) — the canonical reference for MRR
  movements, churn, NRR, and unit economics; the vocabulary this chapter implements.
- Alistair Croll, Benjamin Yoskovitz — *Lean Analytics* — one metric that matters,
  vanity vs. actionable, and stage-appropriate metrics; the judgment layer over the
  formulas.
- Amplitude — *The North Star Playbook* — the metric-tree method in full: choosing a
  North Star, decomposing into inputs, and pairing leading with lagging (cited in
  Chapter 04 for taxonomy; read here for the tree).
- a16z — "16 Startup Metrics" and "16 More" — the investor-side reading of these
  numbers, including every way founders accidentally (or not) redefine them; useful as
  the audit your definitions must survive.
- ChartMogul — *The Ultimate SaaS Metrics Guide* — practitioner-grade edge-case handling
  for MRR movements (reactivation, plan changes mid-month, multi-currency); a good
  cross-check for your `DEFINITIONS.md`.
- Stage 6, Chapter [05 (Query Optimization)](../stage-06-database-engineering/05-query-optimization.md)
  — the craft the views depend on once snapshots span years.
- Chapter [03 (Payments)](03-payments.md) and Chapter [04 (Analytics)](04-analytics.md) —
  the two source-of-truth systems this layer computes over, and the reconciliation
  discipline it extends.

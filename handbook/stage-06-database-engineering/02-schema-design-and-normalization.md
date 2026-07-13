# Schema Design & Normalization

## Introduction

Chapter 01 established *what* to model — entities, relationships, keys, constraints.
This chapter is about *how well* to structure it: normalization, the discipline of
organizing columns so each fact lives in exactly one place, and its deliberate
counterpart, denormalization, the measured decision to duplicate a fact for
performance. Together they are the core of schema design — the difference between a
schema where updating a customer's name is one write and one where it's a hunt-and-
replace across thousands of rows you'll inevitably miss.

The single most important idea: **normalization is about eliminating redundancy so
that every fact has a single source of truth, and the update anomalies that redundancy
causes are the real enemy — not the abstract "normal forms."** When the same fact is
stored in multiple places (a customer's name copied onto every invoice row), the copies
drift: you update one and miss others, and now the database disagrees with itself. A
normalized schema stores each fact once and references it, so there's nothing to drift.
The normal forms (1NF, 2NF, 3NF) are just a systematic way to reach that state; the
goal you actually care about is "no fact is duplicated, so no fact can become
inconsistent."

The second idea, and the judgment that separates a database engineer from someone who
memorized normal forms: **denormalization is a valid, sometimes necessary tool — but
only as a deliberate, measured trade of write-complexity and consistency-risk for
read-performance, never as a default or an accident.** Normalize by default (it's
correct and it's what the relational model is for), and denormalize specific, measured
hotspots where the join cost is proven to matter — accepting that you now own keeping
the duplicated data in sync. The mistake in both directions is real: never normalizing
(a wide, redundant, anomaly-prone table) and over-denormalizing (duplication everywhere
for performance you never measured) are both failures of judgment.

## Why It Matters

Schema structure determines whether your data stays consistent as it changes, and the
failures are the quiet, corrupting kind:

- **Redundancy causes update anomalies.** If a fact is stored in many rows, updating it
  means updating all of them — and you will miss some. The customer renamed themselves;
  now half their invoices show the old name and half the new. The database contradicts
  itself, and no query can tell you which copy is right.
- **Redundancy causes insertion and deletion anomalies too.** With a poorly structured
  table you may be unable to record a fact without inventing unrelated data (can't add a
  product category until a product exists in it), or lose a fact by deleting a row (delete
  the last invoice for a customer and lose the customer's address, if the address only
  lived on invoices).
- **Inconsistent data is worse than missing data.** A `NULL` is honestly absent; two
  conflicting copies of the same fact are actively misleading. Reports reconcile wrong,
  decisions are made on the stale copy, and the bug is nearly invisible until someone
  notices the numbers don't add up.
- **Over-denormalization creates a synchronization burden you'll fail.** Duplicating data
  for read speed means every write must now update every copy, in sync, forever. Miss one
  update path (a background job, a bulk import) and the copies drift — you've traded a
  join for a consistency bug.
- **The wrong default costs either way.** Under-normalizing bakes in anomalies from day
  one; over-normalizing everything can make common reads join a dozen tables; over-
  denormalizing scatters truth across duplicates. Schema design is choosing the right
  point deliberately, per the actual access patterns.

Get it right — normalized by default so each fact lives once, denormalized only at
measured hotspots with the sync burden acknowledged — and the schema stays consistent
under change and performs where it needs to. Get it wrong and you either fight update
anomalies and self-contradicting data (too little normalization) or drown in
synchronization bugs (too much denormalization).

The AI dimension: assistants tend to two opposite failures. They generate wide,
denormalized tables that duplicate data (because it's simpler to produce and reads well in
a single query), introducing anomalies; or, prompted about "normalization," they normalize
dogmatically to a degree that harms real access patterns. Both miss the actual skill:
normalize by default, denormalize by measurement.

## Mental Model

Redundancy is the enemy; normalization removes it; denormalization reintroduces it on
purpose, with a cost:

```
   THE DISEASE: REDUNDANCY → ANOMALIES
     same fact in many rows ──► update one, miss others ──► DB contradicts itself
       update anomaly:   rename customer → half the invoices still say the old name
       insertion anomaly: can't record a fact without unrelated data
       deletion anomaly:  delete a row → lose an unrelated fact stored on it

   THE CURE: NORMALIZATION (each fact lives ONCE, referenced by key)
     1NF ── atomic columns, no repeating groups (no "phone1, phone2, phone3")
     2NF ── no partial dependency on part of a composite key
     3NF ── no non-key column depending on another non-key column
     (goal, not ceremony: "every non-key fact depends on THE key, the WHOLE key,
      and NOTHING BUT the key" — 3NF in one sentence)

   THE DELIBERATE EXCEPTION: DENORMALIZATION (duplicate a fact for read speed)
     normalized: SELECT ... JOIN customers ...        ← correct default
     denormalized: store customer_name on invoice     ← faster read, but:
        ⚠ now EVERY write must keep the copy in sync, forever. miss one → drift.
     ONLY when: the join cost is MEASURED to matter AND you own the sync.

   THE RULE:  normalize by DEFAULT.  denormalize by MEASUREMENT, never by reflex.
```

Four principles carry the chapter:

**Redundancy is the enemy; a single source of truth is the goal.** Every fact should live
in exactly one place and be referenced elsewhere by key. The normal forms are a method for
achieving that; the outcome you want is "nothing is duplicated, so nothing can drift."

**Normalize by default (to 3NF).** For transactional data, a normalized schema — atomic
columns, no partial or transitive dependencies — is the correct default: it's consistent
under change and it's what foreign keys and joins are designed for. 3NF ("depends on the
key, the whole key, and nothing but the key") is the practical target for most schemas.

**Denormalize deliberately, by measurement, owning the sync.** Duplicating data for read
performance is a legitimate tool at proven hotspots — but it trades write-complexity and
consistency-risk for read-speed, and you must keep the copies in sync across every write
path. Never denormalize by default or by reflex.

**Match the structure to the access patterns.** The right amount of normalization depends
on how the data is actually read and written. Transactional, write-heavy data wants
normalization; some read-heavy, join-expensive paths justify targeted denormalization (or a
cache, or a materialized view). Design for the real workload, not dogma in either direction.

A working definition:

> **Schema design is organizing columns so each fact has a single source of truth
> (normalization) to eliminate the update, insertion, and deletion anomalies that redundancy
> causes — normalizing to 3NF by default, and denormalizing only specific, measured hotspots
> as a deliberate trade of write-complexity and consistency-risk for read-performance, with
> the synchronization burden owned. Redundancy is the enemy; measurement, not dogma, sets the
> exception.**

## Production Example

**Invoicely** shows both the disease and the cure cleanly. Consider the tempting shortcut:
store the customer's name, email, and address directly on every invoice row. It reads
beautifully — one query returns the invoice with all its customer details, no join. Then the
customer updates their address. Now every past invoice still shows the old address, the new
invoice shows the new one, and there is no single answer to "what is this customer's address?"
The redundancy has produced an update anomaly and self-contradicting data. The normalized cure:
customer facts live in `customers`, the invoice references `customer_id`, and the name/address
exist in exactly one place.

But Invoicely also has a legitimate denormalization case, and it illustrates the judgment. The
invoice `total` is, in principle, derivable — it's the sum of the line items. Storing it on the
invoice duplicates information that already exists in `line_items`. Yet an invoice is a *financial
record*: the total at the time it was issued must be preserved even if a line item is later
corrected, and recomputing the total by summing line items on every list query is measurably
expensive at scale. So `total` is deliberately stored (denormalized) on the invoice — with the
explicit obligation that it's recomputed and kept in sync whenever line items change. This is
denormalization done right: a measured, justified duplication with the sync burden owned, not a
reflex.

In this chapter we normalize the Invoicely schema (customer facts in one place, no repeating
groups, no transitive dependencies) and then make one deliberate, documented denormalization (the
invoice total), showing the sync obligation it creates. We contrast it with the assistant-default
wide table (customer details copied onto every invoice) that reads well and corrupts under the
first update.

## Folder Structure

```
api/app/
├── models/
│   ├── customer.py            # customer facts live HERE, once (name, email, address)
│   ├── invoice.py             # references customer_id; deliberately stores `total` (denormalized)
│   └── line_item.py           # the source of truth for line amounts (total is derived from these)
├── services/
│   └── invoice_totals.py      # the ONE place that recomputes/syncs the denormalized total
├── migrations/versions/       # normalization/denormalization changes ship as reviewed migrations
└── db/
    └── views.sql              # materialized views for read-heavy reporting (denormalize for reads)
```

Why this shape: the model files reflect where each fact's single source of truth lives —
customer facts in `customer.py`, line amounts in `line_item.py`. The one deliberate denormalization
(the invoice total) is paired with a single service (`invoice_totals.py`) responsible for keeping it
in sync, so the sync burden has an explicit owner rather than being scattered across every write
path (the number-one way denormalized data drifts). `views.sql` is where read-heavy denormalization
lives as materialized views — a controlled way to trade freshness for read speed without
duplicating truth in the transactional tables. The structure encodes the rule: normalize the core,
denormalize deliberately and with an owner.

## Implementation

**The redundancy problem, concretely.** The wide table that reads well and corrupts:

```sql
-- ANTI-PATTERN: customer facts duplicated onto every invoice → update anomalies
CREATE TABLE invoices (
  id             BIGINT PRIMARY KEY,
  customer_name  TEXT,      -- duplicated on every invoice for this customer
  customer_email TEXT,      -- duplicated
  customer_address TEXT,    -- duplicated → customer moves → which invoices are right?
  total          NUMERIC(12,2)
);
-- Renaming a customer requires updating N invoice rows. Miss one → the DB contradicts itself.
```

**The normalized cure.** Each customer fact lives once; the invoice references it. Updating a
customer is one write.

```sql
CREATE TABLE customers (                       -- customer facts: single source of truth
  id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name     TEXT NOT NULL,
  email    TEXT NOT NULL UNIQUE,
  address  TEXT
);

CREATE TABLE invoices (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id  BIGINT NOT NULL REFERENCES customers (id),   -- reference, don't duplicate
  total        NUMERIC(12,2) NOT NULL CHECK (total >= 0)     -- (deliberately denormalized — see below)
);
-- Rename a customer: ONE update. No copies to drift. No anomaly possible.
```

**1NF in action — no repeating groups.** Atomic columns instead of `phone1, phone2, phone3`.

```sql
-- ANTI-PATTERN (violates 1NF): repeating group
--   customers(id, name, phone1, phone2, phone3)   ← can't add a 4th; can't query "who has phone X?"

-- 1NF: a phone is its own row, referencing the customer (a one-to-many)
CREATE TABLE customer_phones (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id  BIGINT NOT NULL REFERENCES customers (id) ON DELETE CASCADE,
  phone        TEXT NOT NULL,
  label        TEXT                              -- 'mobile', 'office', ...
);
```

**The deliberate denormalization, with an owner.** The invoice `total` is stored (not summed on
every read) because an invoice is a financial record and the recompute is measurably costly at
scale — and a single service owns keeping it in sync.

```python
# services/invoice_totals.py — the ONE place responsible for the denormalized total's consistency.
def recompute_invoice_total(session: Session, invoice_id: int) -> None:
    """Recompute and persist invoice.total from its line items.

    invoice.total is DELIBERATELY denormalized (derivable from line_items) for read
    performance and as a preserved financial record. This function MUST be called from
    every path that changes line items, or the stored total drifts from the truth.
    """
    total = session.scalar(
        select(func.coalesce(func.sum(LineItem.quantity * LineItem.unit_price), 0))
        .where(LineItem.invoice_id == invoice_id)
    )
    session.execute(update(Invoice).where(Invoice.id == invoice_id).values(total=total))
```

**Denormalizing for reads without corrupting truth — a materialized view.** Read-heavy reporting
gets a fast, denormalized shape without duplicating facts into the transactional tables; it's
refreshed on a schedule, trading freshness for read speed explicitly.

```sql
-- Read-heavy dashboard query, denormalized into a materialized view (refreshed periodically).
CREATE MATERIALIZED VIEW customer_revenue AS
SELECT c.id AS customer_id, c.name, COUNT(i.id) AS invoice_count, SUM(i.total) AS revenue
FROM customers c LEFT JOIN invoices i ON i.customer_id = c.id
GROUP BY c.id, c.name;
-- REFRESH MATERIALIZED VIEW customer_revenue;  ← explicit freshness trade, truth still lives in base tables
```

The difference is the whole chapter: the normalized schema keeps each fact in one place (no
anomalies), the one denormalization is deliberate, justified, and owned by a single sync point, and
read-side denormalization uses a view that leaves the source of truth intact. The wide-table
anti-pattern duplicates customer facts everywhere and corrupts on the first update — readable in a
demo, self-contradicting in production.

## Engineering Decisions

Five decisions define schema structure.

### How far do you normalize by default?

**Options:** (1) minimal normalization (wide tables); (2) 3NF as the default; (3) higher normal
forms (BCNF/4NF) everywhere.

**Trade-offs:** minimal normalization reads simply and bakes in redundancy and anomalies. 3NF
eliminates the common anomalies (partial and transitive dependencies) while keeping the schema
practical, at the cost of joins for related data. Higher normal forms remove rarer anomalies at the
cost of more tables and joins that most schemas never benefit from.

**Recommendation:** normalize to 3NF by default — it removes the anomalies that actually bite while
keeping the schema workable. Go beyond 3NF only for a specific anomaly you've identified. "Depends on
the key, the whole key, and nothing but the key" is the target; don't under-normalize into wide
redundant tables, and don't chase higher normal forms as an end in themselves.

### When do you denormalize?

**Options:** (1) never (pure normalization); (2) denormalize measured hotspots deliberately; (3)
denormalize freely for read simplicity.

**Trade-offs:** never denormalizing keeps perfect consistency and can make hot read paths join many
tables. Deliberate, measured denormalization speeds proven-slow reads at the cost of write-complexity
and a sync obligation. Free denormalization reads well and scatters truth into duplicates that drift —
trading joins for consistency bugs everywhere.

**Recommendation:** denormalize only when the join/aggregation cost is *measured* to matter, the read
pattern is hot, and you can own the synchronization — and prefer alternatives first (better indexes in
Chapter 03, a cache from Stage 3 Chapter 07, or a materialized view) before duplicating into
transactional tables. Denormalization is a scalpel, not a default.

### Where does the synchronization of denormalized data live?

**Options:** (1) update copies ad hoc wherever a write happens; (2) a single owning code path (or DB
trigger) responsible for the sync; (3) periodic recomputation.

**Trade-offs:** ad hoc updates guarantee that some path (a background job, a bulk import) eventually
forgets, and the copies drift. A single owner (one service function, or a database trigger) centralizes
the obligation so it can't be forgotten, at the cost of routing all relevant writes through it. Periodic
recomputation (a job, or a materialized view refresh) tolerates temporary staleness for simplicity.

**Recommendation:** give every piece of denormalized data one explicit sync owner — a single service
function or a database trigger — never scattered ad hoc updates. For read-side denormalization, a
materialized view with a scheduled refresh makes the staleness explicit and keeps the truth in the base
tables. Denormalization without a clear sync owner is a drift bug waiting to happen.

### Denormalize into base tables or into a read model (view/cache)?

**Options:** (1) duplicate columns into the transactional tables; (2) a materialized view; (3) a cache
(Stage 3, Chapter 07); (4) a separate read model.

**Trade-offs:** duplicating into base tables speeds reads and writes-complexity and mixes derived data
into the source of truth. A materialized view keeps base tables clean and trades freshness (refresh
cadence) for read speed. A cache is fast and adds invalidation concerns. A separate read model (CQRS-ish)
is powerful and heavy.

**Recommendation:** prefer keeping the transactional tables normalized and pushing read-optimizations
into a *separate* layer — a materialized view or a cache — so the source of truth stays clean. Duplicate
into base tables only when the value must be preserved as a record (like the invoice total) or the
read-model layer genuinely can't serve the pattern. Keep truth and read-optimization separate where you
can.

### Design for the access patterns or for purity?

**Options:** (1) design by normalization rules alone; (2) design from the real read/write patterns; (3)
design for the current query only.

**Trade-offs:** designing by rules alone can produce a "correct" schema that joins a dozen tables for a
common read. Designing from real access patterns balances normalization against the actual workload.
Designing for the current query risks a shape the next query fights.

**Recommendation:** normalize by default, then let *measured* access patterns justify specific
denormalizations — design for the real workload, not for normal-form purity and not for a single query.
The workload, revealed by measurement (Chapter 05's `EXPLAIN`), is what tells you where the default
normalized schema needs a deliberate exception.

## Trade-offs

Schema structure is a trade between consistency and read performance, and both extremes are failures.

**Normalization trades read joins for guaranteed consistency.** A normalized schema stores each fact
once — so updates are single-writes and nothing can drift — and reads related data by joining. You gain
consistency-under-change (the thing that's hardest to recover once lost) and pay a join cost that indexes
(Chapter 03) usually make negligible. For transactional data this trade is almost always right.

**Denormalization trades consistency-risk and write-complexity for read speed.** Duplicating a fact makes
a hot read faster and obligates every write to keep the copies in sync — a burden you now own forever. The
trade is worth it at measured hotspots with a clear sync owner; it's a net loss when applied by reflex,
because you've bought speed you didn't need with consistency bugs you can't easily find.

**Materialized views trade freshness for read speed without corrupting truth.** A view denormalizes the
read shape while leaving the source of truth in the base tables, at the cost of the data being as fresh as
the last refresh. For reporting and dashboards that tolerate minutes of staleness, this is often the best
denormalization — read speed with the truth intact.

**The default has asymmetric risk.** Under-normalizing bakes in anomalies that silently corrupt data;
over-denormalizing scatters sync bugs. Normalizing by default fails safe (correct, maybe a join too many);
denormalizing by default fails dangerous (fast, quietly inconsistent). When unsure, normalize — the
failure mode is cheaper.

## Common Mistakes

**Duplicating facts into wide tables.** Copying customer details onto every invoice, causing update
anomalies and self-contradiction. Fix: normalize — each fact once, referenced by key.

**Repeating groups (1NF violation).** `phone1, phone2, phone3` columns that can't extend or be queried.
Fix: a related table, one row per value.

**Transitive dependencies (3NF violation).** A non-key column depending on another non-key column
(storing a derived or looked-up value that belongs in another table). Fix: move it to where its key lives.

**Denormalizing without measurement.** Duplicating data for a join cost you never proved mattered. Fix:
measure first (Chapter 05); prefer indexes/caches/views before duplicating.

**Denormalized data with no sync owner.** Copies updated ad hoc, so some path forgets and they drift. Fix:
one explicit sync owner (a service function or trigger).

**Dogmatic over-normalization.** Splitting to higher normal forms so common reads join a dozen tables. Fix:
3NF by default; go further only for a real anomaly.

## AI Mistakes

Assistants fail schema design in both directions — usually toward redundancy (simpler to generate, reads
well) and occasionally toward dogmatic normalization when prompted. Review generated schemas for where each
fact lives and whether any duplication has a sync owner.

### Claude Code: wide, denormalized tables that duplicate facts

Asked to design tables for a feature, Claude Code often produces a wide table that inlines related data
(customer name/email on the invoice) because it's fewer tables and a single query returns everything. It
reads well in the demo and introduces update anomalies the moment the duplicated fact changes.

**Detect:** the same fact (customer name, product price, category) appearing as columns on multiple tables;
tables that inline data belonging to a related entity; no foreign key where a reference should replace a
copy; "denormalized for convenience" with no measurement or sync plan.

**Fix:** require normalization by default:

> Normalize this — each fact should live in one place and be referenced by foreign key, not duplicated onto
> related rows. Don't inline customer/product/category data onto other tables; reference it. Only denormalize
> a specific value if the join cost is measured to matter, and then name the single code path that keeps it
> in sync.

### GPT: repeating groups and transitive dependencies

GPT-family models frequently produce 1NF/3NF violations that pass a quick look — repeating columns
(`option1, option2, option3`), or storing a derived/looked-up value that transitively depends on a non-key
column — because they mirror how the data is displayed rather than how it should be stored.

**Detect:** numbered repeating columns (`phoneN`, `itemN`); columns that are functions of another non-key
column (a `city` stored alongside a `zip` that determines it); derived values stored with no sync mechanism;
tables shaped like a form/spreadsheet.

**Fix:** require proper normal form:

> Remove the repeating group — model those as rows in a related table (1NF). Remove the transitive dependency
> — a non-key column must depend on the key, not on another non-key column (3NF); move it to the table where
> its key lives, or derive it. Model how the data should be stored, not how it's displayed.

### Cursor: denormalizing for the current query with no sync owner

Editing to make one read faster, Cursor tends to add a duplicated column to an existing table so the current
query avoids a join — a local optimization with no measurement and, critically, no owner for keeping the copy
in sync, so it drifts as soon as another write path touches the source.

**Detect:** a duplicated/derived column added to speed one query; no evidence the join was actually slow; no
single place responsible for updating the copy when the source changes; other write paths that don't update
the duplicate.

**Fix:** require measured, owned denormalization (or an alternative):

> Before duplicating this column, confirm the join is actually the bottleneck (`EXPLAIN`, Chapter 05) and
> prefer an index, cache, or materialized view first. If you do denormalize, route every write that affects it
> through one sync owner so the copy can't drift. A denormalized column with no sync owner is a consistency bug.

## Best Practices

**Normalize to 3NF by default.** Each fact in one place, atomic columns, no partial or transitive
dependencies — the correct, consistency-preserving default for transactional data. "Depends on the key, the
whole key, and nothing but the key."

**Treat redundancy as the enemy and update anomalies as the symptom.** When you see the same fact in multiple
places, ask what happens when it changes — if the answer is "update many rows and hope," normalize it.

**Denormalize only by measurement, and own the sync.** Duplicate data only at proven hotspots, prefer
indexes/caches/materialized views first, and give every denormalization a single explicit sync owner. Never
denormalize by reflex.

**Keep truth and read-optimization separate where possible.** Push read-side denormalization into materialized
views or caches so the transactional tables stay the clean source of truth; duplicate into base tables only to
preserve a record or when no separate layer works.

**Design from real access patterns and document the exceptions.** Let the measured workload justify
denormalizations, and document each one (why, and who syncs it) in `CLAUDE.md`/the schema so it's understood
and maintained, not mistaken for an accident.

## Anti-Patterns

**The Wide Duplicating Table.** Related facts inlined and duplicated across rows, causing update anomalies. The
tell: customer/product data copied onto every invoice/order.

**The Repeating Group.** Numbered columns (`phone1..3`) instead of a related table. The tell: `thingN` columns
that can't extend or be queried.

**The Transitive Dependency.** A non-key column determined by another non-key column, stored redundantly. The
tell: a value you could derive from another non-key column sitting alongside it.

**The Unmeasured Denormalization.** Data duplicated for a join cost never proven to matter. The tell:
denormalized columns with no `EXPLAIN` evidence and no alternative tried.

**The Ownerless Copy.** Denormalized data updated ad hoc, drifting over time. The tell: a duplicated value
updated in some write paths but not others.

**The Dogma Schema.** Over-normalized to the point that common reads join a dozen tables for no anomaly-driven
reason. The tell: normalization pursued as an end, not to prevent a real anomaly.

## Decision Tree

"I'm structuring a schema (or tempted to duplicate a column) — normalize or denormalize?"

```
Default: NORMALIZE to 3NF.
  Is the same fact stored in more than one place?
  ├── YES ──► redundancy. What happens when it changes? "update many rows" = update anomaly ──► normalize:
  │           one source of truth, referenced by foreign key.
  └── Repeating columns (phone1,2,3)? ──► 1NF violation ──► a related table, one row per value.
      Non-key column depends on another non-key column? ──► 3NF violation ──► move it to its key's table.

Tempted to DENORMALIZE (duplicate for read speed)?
  Is the read actually slow? (measure — EXPLAIN, Ch 05)
  ├── NO / unmeasured ──► don't. Normalize.
  └── YES ──► try cheaper fixes first: index (Ch 03) → cache (Stage 3 Ch 07) → materialized view.
       Still need to duplicate?
       ├── value must be preserved as a record (e.g., invoice total) ──► denormalize into the base table,
       │     with ONE sync owner (a service fn or trigger).
       └── read-only reporting shape ──► materialized view (truth stays in base tables; refresh = freshness trade).

When unsure ──► NORMALIZE. Under-normalizing corrupts silently; over-denormalizing scatters sync bugs.
```

## Checklist

### Implementation Checklist

- [ ] The schema is normalized to 3NF by default; no fact is duplicated across rows/tables.
- [ ] No repeating groups (1NF) — multi-valued attributes are related tables.
- [ ] No transitive dependencies (3NF) — non-key columns depend only on the key.
- [ ] Every denormalization is measurement-justified and has cheaper alternatives (index/cache/view) ruled out.
- [ ] Every denormalized value has a single explicit sync owner (service function or trigger).
- [ ] Read-side denormalization uses materialized views/caches, keeping base tables as the source of truth.

### Architecture Checklist

- [ ] Structure is driven by real access patterns, not normal-form dogma or a single query.
- [ ] Truth (transactional tables) and read-optimization (views/caches) are separated where possible.
- [ ] Each deliberate denormalization is documented (why, and who syncs it).
- [ ] The consistency-vs-read-performance trade is made deliberately per hotspot, not by reflex.
- [ ] Normalization conventions are documented in `CLAUDE.md`.

### Code Review Checklist

- [ ] No fact duplicated across tables without a documented, measured reason and a sync owner (watch AI diffs).
- [ ] No repeating groups or transitive dependencies.
- [ ] No denormalization without measurement and a cheaper-alternative check.
- [ ] No denormalized column lacking a single sync owner.
- [ ] No over-normalization forcing common reads to join excessively.

*(A Deployment Checklist is not applicable to this chapter; structural changes ship as migrations — Chapter 06.)*

## Exercises

**1. Normalize a wide table.** Take a denormalized `invoices` table that inlines customer name/email/address,
identify the update/insertion/deletion anomalies concretely, and normalize it (customers in their own table,
referenced by key). The artifact is the before/after schema and the specific anomaly each change removes.

**2. Justify (or reject) a denormalization.** For Invoicely's invoice `total`, argue whether to store it or
derive it: measure the recompute cost, consider the "financial record" requirement, and decide. If you store it,
implement the single sync owner. The artifact is the decision with its measurement and the sync mechanism.

**3. Build a read model instead of duplicating.** Take a slow reporting query (revenue per customer) and, instead
of duplicating totals into base tables, serve it with a materialized view. Note the freshness trade and the
refresh strategy. The artifact is the view and a comparison to the base-table-duplication alternative.

## Further Reading

- **PostgreSQL documentation — "Materialized Views" and "The Rule System"** (postgresql.org/docs) — the
  mechanics of read-side denormalization that keeps truth in base tables; the tool behind this chapter's preferred
  denormalization.
- **"Database Design for Mere Mortals" by Michael Hernandez** — a practical, non-academic treatment of
  normalization and when to bend it; pairs with Chapter 01 for the modeling-through-design arc.
- **C. J. Date — "Database Design and Relational Theory"** — the rigorous grounding for normal forms and why they
  prevent specific anomalies; background for the "3NF in one sentence" heuristic used here.
- **Stage 3, Chapter 07 — Caching** — the read-performance tool to reach for *before* denormalizing into base
  tables; this chapter's "try cheaper fixes first" points here.
</content>

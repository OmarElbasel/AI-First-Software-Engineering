# Indexing

## Introduction

An index is the single highest-leverage performance tool in a database, and the one
most often applied by superstition. Add the right index and a query that scanned a
million rows now touches a few — a thousandfold speedup from one line of DDL. Add the
wrong indexes and you slow every write, waste storage, and still don't fix the slow
query. This chapter is about indexing with judgment: understanding what an index
actually is, reading the query plan to know whether one is being used, choosing the
right index for the access pattern, and resisting the two opposite failures —
under-indexing (slow reads) and over-indexing (slow writes, wasted space).

The single most important idea: **an index is a trade — faster reads for slower writes
and more storage — and it only pays off when it matches how the data is actually
queried.** An index is a secondary data structure (usually a B-tree) that lets the
database find rows by a column's value without scanning the whole table. That lookup
speed isn't free: every `INSERT`, `UPDATE`, and `DELETE` must also update every index
on the table, and every index consumes storage and memory. So indexing is not "add
indexes to go fast" — it's "add the specific indexes that serve your real read patterns,
and no more." An index that no query uses is pure cost.

The judgment this chapter teaches is driven by one habit: **read the query plan.**
PostgreSQL's `EXPLAIN (ANALYZE)` tells you exactly whether a query uses an index or
scans the table, and how long each step takes — it turns indexing from guesswork into
measurement. You'll learn to spot the sequential scan that should be an index scan,
choose between index types (B-tree for most things, GIN for full-text/JSONB, and so
on), build composite indexes whose column order matches the query, and recognize when
an index can't help (low selectivity, a function on the column, a leading wildcard).
This is the performance foundation Chapter 05 (query optimization) builds on, and the
reason the schema from Chapters 01–02 performs.

## Why It Matters

Indexing decides whether a database stays fast as it grows, and both directions of
getting it wrong are expensive:

- **The difference is asymptotic, not marginal.** Without an index, finding rows by a
  value is a sequential scan — O(n), reading every row. With a B-tree index it's roughly
  O(log n). On a thousand rows nobody notices; on ten million, the unindexed query takes
  seconds (or minutes) while the indexed one takes milliseconds. Performance problems
  that appear "suddenly in production" are usually a missing index meeting real data
  volume.
- **Every index taxes every write.** An index speeds reads and slows writes: each
  insert/update/delete must maintain every index on the table. A table with fifteen
  indexes writes far slower than one with three. Over-indexing turns a write-heavy table
  into a bottleneck — the opposite of the intended fix.
- **Indexes cost storage and memory.** Indexes can collectively exceed the size of the
  table they serve, consuming disk and, more importantly, the memory (buffer cache) that
  would otherwise hold data. Unused indexes waste both.
- **The wrong index doesn't help.** A composite index in the wrong column order, an index
  on a low-selectivity column (a boolean), or an index defeated by a function or leading
  wildcard sits there costing writes and storage while the query still scans. Indexing
  without reading the plan produces exactly these — indexes that look reasonable and do
  nothing.
- **You can't reason about it without measuring.** Whether an index helps depends on
  selectivity, data distribution, and the query shape — things you observe with `EXPLAIN`,
  not intuit. Teams that guess at indexes both miss the ones they need and add ones they
  don't.

Get it right — indexes chosen from real query plans, matched to access patterns, covering
the hot reads without over-indexing the writes — and the database stays fast at scale with
minimal write overhead. Get it wrong and you either watch queries degrade as data grows
(under-indexing) or choke writes and waste resources on indexes nothing uses
(over-indexing).

The AI dimension: assistants index by pattern-matching, not measurement. They under-index
(generate schemas and queries with no indexes, so it's fast in the demo and slow in
production), over-index (add an index on every column "to be safe," taxing writes), get
composite column order wrong, and never suggest reading the query plan. Indexing is
precisely where their confident, plausible output is most often wrong in ways only
`EXPLAIN` reveals.

## Mental Model

An index is a read-speed-for-write-cost trade, useful only when it matches the query — and
the plan is how you know:

```
   WHAT AN INDEX IS
     a secondary structure (usually a B-TREE) mapping column value → row location
     so the DB FINDS rows by value instead of SCANNING the table.
        seq scan  = read every row      O(n)      ← no useful index
        index scan = walk the B-tree    O(log n)  ← matching index

   THE TRADE (an index is never free)
     + faster reads (lookups, ranges, sorts, joins on the indexed column)
     − slower writes (every INSERT/UPDATE/DELETE maintains every index)
     − storage + memory (indexes can exceed the table's size)
        ⇒ add indexes that serve REAL read patterns. an unused index is pure cost.

   READ THE PLAN (measurement, not superstition)
     EXPLAIN (ANALYZE, BUFFERS) <query>
        "Seq Scan on invoices"      ← scanning; an index may help
        "Index Scan using ix_..."   ← using the index (good)
        actual time / rows          ← where the cost really is

   CHOOSING THE INDEX (match the access pattern)
     equality / range / sort / join ─► B-TREE (the default, ~90% of cases)
     composite (multi-column)        ─► column ORDER matters: match the query's filter order
     full-text / JSONB / arrays      ─► GIN         geometric / ranges ─► GiST
     tiny hot subset of a big table  ─► PARTIAL index (WHERE status='overdue')
     read served entirely from index ─► COVERING index (INCLUDE the selected columns)

   WHEN AN INDEX CAN'T HELP
     low selectivity (boolean) · function on the column (WHERE lower(email)=) ·
     leading wildcard (LIKE '%x') · tiny table
```

Four principles carry the chapter:

**An index trades write cost and storage for read speed.** Add indexes deliberately to
serve real read patterns; every index taxes every write and consumes resources. Under-
indexing is slow reads; over-indexing is slow writes and waste — both are failures.

**Read the query plan.** `EXPLAIN (ANALYZE)` is the ground truth for whether an index is
used and where time goes. Index from measured plans, not from intuition — the plan turns
indexing into engineering.

**Match the index to the access pattern.** B-tree for equality/range/sort/join (most
cases); GIN for full-text/JSONB/arrays; composite indexes with column order matching the
query's filters; partial and covering indexes for specific hot patterns. The right index
depends on how the query reads.

**Know when an index can't help.** Low selectivity, a function wrapping the column, a
leading wildcard, or a tiny table all defeat indexing. Recognizing these saves you from
adding indexes that cost writes and do nothing — and points you at the real fix (rewrite
the query, an expression index, a different type).

A working definition:

> **An index is a secondary structure that trades slower writes and more storage for
> faster reads, and it pays off only when it matches how the data is actually queried.
> Index from real query plans (`EXPLAIN ANALYZE`), match the index type and column order to
> the access pattern, avoid both under-indexing (slow reads) and over-indexing (slow
> writes), and recognize the cases where no index can help. Measurement, not superstition,
> drives indexing.**

## Production Example

**Invoicely's** query patterns make the indexing decisions concrete, and they span the
common cases. The hottest read is the invoice list for a user, filtered by status and
sorted by date: `WHERE customer_id = ? AND status = ? ORDER BY issued_at DESC`. On a table
with millions of invoices, this without an index is a sequential scan that gets slower every
month; with the right **composite index** (`customer_id, status, issued_at`) in an order
matching the filter-then-sort, it's a fast index scan. A second pattern: looking up a
customer by email (`WHERE email = ?`) — a textbook single-column B-tree, already implied by
the `UNIQUE(email)` constraint from Chapter 01. A third: full-text search over invoice
descriptions — a job for a **GIN** index, not a B-tree. A fourth: the "overdue invoices"
dashboard touches a tiny fraction of rows (`WHERE status = 'overdue'`) — a **partial index**
serves it without indexing the whole table.

And the over-indexing temptation is just as real: an assistant asked to "make Invoicely fast"
will add an index on every column of `invoices` — `status` (a low-selectivity enum), `total`,
`created_at`, `updated_at` — most of which no query uses, each taxing every invoice write and
consuming storage. The engineering is choosing the few indexes that serve the measured read
patterns and rejecting the rest.

In this chapter we index Invoicely's real query patterns from their query plans: the composite
index for the list, the email lookup, a GIN index for search, and a partial index for the
overdue dashboard — reading `EXPLAIN ANALYZE` before and after each to prove the win. We
contrast it with the two anti-patterns: the unindexed schema that scans (under-indexing) and
the index-everything schema that chokes writes (over-indexing).

## Folder Structure

```
api/app/
├── models/
│   └── invoice.py             # Index() declarations colocated with the model they serve
├── migrations/versions/       # indexes are added via migrations (use CONCURRENTLY in prod — Ch 06)
│   └── 0007_add_invoice_indexes.py
└── db/
    ├── indexes.sql            # index definitions with a COMMENT on each: which query it serves
    └── explain/               # saved EXPLAIN ANALYZE output: before/after evidence per index
        └── invoice_list.md
```

Why this shape: indexes are declared with the model they serve so their purpose is visible
where the entity is defined, and shipped as migrations (Chapter 06) — in production, built
`CONCURRENTLY` so creating them doesn't lock the table. `indexes.sql` documents *which query
each index serves*, because the most common indexing failure is an index nobody remembers the
reason for (and therefore can't safely drop). The `explain/` directory keeps the
before/after `EXPLAIN ANALYZE` evidence for each index — indexing decisions are backed by
measurement, and the measurement is kept so the decision can be revisited. The structure
encodes the chapter's rule: every index has a query it serves and a plan that proves it.

## Implementation

**Read the plan first — the sequential scan.** Before adding an index, prove the problem.
`EXPLAIN ANALYZE` shows the query scanning the whole table.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM invoices WHERE customer_id = 42 AND status = 'sent' ORDER BY issued_at DESC;

-- Seq Scan on invoices  (cost=0.00..24500 rows=180 width=...) (actual time=0.3..320 ms)
--   Filter: (customer_id = 42 AND status = 'sent')
--   Rows Removed by Filter: 1_999_820        ← scanned 2M rows to return 180. This is the problem.
-- Execution Time: 320 ms
```

**The composite index matching the access pattern.** Column order matters: equality filters
first (`customer_id`, `status`), then the sort column (`issued_at`). This order lets one index
serve the filter *and* the sort.

```sql
-- Order: equality columns first, then the ORDER BY column. Matches WHERE ... ORDER BY.
CREATE INDEX ix_invoices_customer_status_issued
  ON invoices (customer_id, status, issued_at DESC);

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM invoices WHERE customer_id = 42 AND status = 'sent' ORDER BY issued_at DESC;

-- Index Scan using ix_invoices_customer_status_issued  (actual time=0.05..0.6 ms)   ← 320ms → <1ms
--   Index Cond: (customer_id = 42 AND status = 'sent')
-- Execution Time: 0.7 ms
```

**A partial index for a tiny hot subset.** The overdue dashboard touches a small fraction of
rows; a partial index covers exactly those, staying small and cheap to maintain.

```sql
-- Only index overdue rows — a fraction of the table. Small index, serves the dashboard query.
CREATE INDEX ix_invoices_overdue ON invoices (customer_id, issued_at)
  WHERE status = 'overdue';
```

**A GIN index for full-text search.** A B-tree can't serve full-text search; GIN can.
Matching the index type to the access pattern.

```sql
-- Full-text search over descriptions → GIN, not B-tree.
CREATE INDEX ix_invoices_description_fts
  ON invoices USING GIN (to_tsvector('english', description));
```

**A covering index (index-only scan).** When a hot query selects only a few columns, `INCLUDE`
them so the read is served entirely from the index without touching the table.

```sql
-- The list only needs number/total/issued_at → include them → index-only scan (no heap fetch).
CREATE INDEX ix_invoices_list_covering
  ON invoices (customer_id, status) INCLUDE (number, total, issued_at);
```

**The anti-patterns — under- and over-indexing.**

```sql
-- ANTI-PATTERN 1: UNDER-INDEXING — no indexes; every filter is a seq scan.
--   Fine on 1k rows in the demo; 320ms → timeouts as the table grows to millions.

-- ANTI-PATTERN 2: OVER-INDEXING — "index everything to be safe"
CREATE INDEX ON invoices (status);       -- low selectivity (few distinct values) — rarely useful alone
CREATE INDEX ON invoices (total);        -- no query filters/sorts by total
CREATE INDEX ON invoices (created_at);   -- unused
CREATE INDEX ON invoices (updated_at);   -- unused
CREATE INDEX ON invoices (currency);     -- unused
-- Every invoice write now maintains 5 extra indexes; storage bloats; the slow list query is STILL slow
-- because none of these match its access pattern. Cost with no benefit.
```

The difference is the whole chapter: the good approach reads the plan, adds the few indexes that
match real access patterns (composite for the list, partial for the dashboard, GIN for search,
covering for the hot read), and proves each with `EXPLAIN`. The under-indexed schema scans and
degrades with growth; the over-indexed schema taxes every write and wastes storage while the
actual slow query stays slow — because indexing was done by superstition, not measurement.

## Engineering Decisions

Five decisions define indexing.

### Which indexes do you create at all?

**Options:** (1) none / minimal (rely on primary keys); (2) indexes for measured read patterns;
(3) index everything.

**Trade-offs:** minimal indexing keeps writes fast and lets reads degrade to sequential scans as
data grows. Indexing measured read patterns speeds the queries that matter at the cost of
maintaining those specific indexes on writes. Indexing everything guarantees some index for any
query and cripples writes, bloats storage, and still leaves many indexes unused.

**Recommendation:** create indexes for your real, measured read patterns — the queries that run
often or on large tables — and nothing more. Start from the query plans (slow `Seq Scan`s on big
tables), add the matching index, verify the improvement, and periodically drop indexes no query
uses. Neither under-index nor index-everything; index the workload.

### What index type fits the access pattern?

**Options:** (1) B-tree (default); (2) GIN; (3) GiST; (4) BRIN / hash / others.

**Trade-offs:** B-tree serves equality, range, sort, and join on ordered data — the ~90% case.
GIN serves multi-valued data (full-text, JSONB, arrays) that B-tree can't. GiST serves geometric
and range/overlap queries. BRIN is tiny and suits naturally-ordered huge tables (time-series).
Using the wrong type means the index isn't used.

**Recommendation:** B-tree by default; GIN for full-text/JSONB/array containment; GiST for
geometric/range-overlap; BRIN for very large, physically-ordered tables. Match the type to the
query shape — a B-tree on a JSONB containment query, or a GIN where a B-tree suffices, is the
wrong tool.

### For a composite index, what column order?

**Options:** (1) equality columns first, then range/sort; (2) arbitrary order; (3) separate
single-column indexes instead.

**Trade-offs:** column order determines whether a composite index serves a query — equality
predicates first, then the range or `ORDER BY` column, lets one index handle filter-and-sort.
Arbitrary order often means the index can't be used for the query's sort or can only use a prefix.
Separate single-column indexes can't serve a multi-column filter as efficiently as one correctly-
ordered composite (the planner may bitmap-combine them, but usually less well).

**Recommendation:** order composite index columns to match the query — equality-filter columns
first, then the range/sort column — following the leftmost-prefix rule (an index on `(a, b, c)`
serves filters on `a`, `a,b`, and `a,b,c`, but not `b` alone). Design the composite around the
actual `WHERE ... ORDER BY`, and reuse one well-ordered composite across queries that share a
prefix.

### Do you use partial or covering indexes?

**Options:** (1) plain indexes only; (2) partial indexes for hot subsets; (3) covering indexes for
hot projections.

**Trade-offs:** a plain index covers the whole column for all rows — simple, sometimes larger and
less targeted than needed. A partial index (`WHERE status = 'overdue'`) indexes only the relevant
subset, staying small and cheap when queries always filter on that condition. A covering index
(`INCLUDE`) serves a query entirely from the index (index-only scan), avoiding the table fetch, at
the cost of a wider index.

**Recommendation:** use a partial index when a hot query always filters to a small subset (status
flags, soft-deletes), and a covering index when a hot query selects only a few columns and the
extra index width is worth eliminating the heap fetch. Both are targeted optimizations for specific
measured patterns — not defaults.

### How do you know an index will (or won't) help?

**Options:** (1) intuition; (2) `EXPLAIN (ANALYZE)` before and after; (3) production index-usage
stats.

**Trade-offs:** intuition adds indexes that look right and don't help (low selectivity, wrong type,
function-wrapped column) and misses ones that would. `EXPLAIN (ANALYZE)` shows the actual plan and
timing for a query. Index-usage statistics (`pg_stat_user_indexes`) show, in production, which
indexes are actually used over time.

**Recommendation:** decide with `EXPLAIN (ANALYZE)` — confirm the scan before adding an index and the
index scan (and speedup) after — and use `pg_stat_user_indexes` in production to find unused indexes to
drop. Never add or keep an index on intuition; whether it helps depends on selectivity and query shape
that only measurement reveals.

## Trade-offs

Indexing trades write cost and storage for read speed, and the discipline is spending that trade only
where it pays.

**Every index trades write throughput for read speed.** An index accelerates matching reads and slows
every write to the table (the index must be maintained) and consumes storage/memory. On read-heavy
tables and hot queries the trade is strongly positive; on write-heavy tables, each additional index is a
real tax — which is why "index everything" backfires. Spend the trade on the reads that matter.

**Composite indexes trade generality for a precise fit.** One well-ordered composite index serves a
specific filter-and-sort pattern far better than several single-column indexes, and it's less reusable
across unrelated queries. You gain a fast, targeted index and give up some generality — worth it for hot,
stable query shapes.

**Partial/covering indexes trade specificity for efficiency.** A partial index is smaller and cheaper but
only serves queries matching its condition; a covering index avoids the heap fetch but is wider. Both are
sharp tools that pay off for the exact pattern they target and add complexity if used speculatively.

**Measurement trades a little upfront effort for correct decisions.** Reading `EXPLAIN` and checking
index-usage stats takes minutes and replaces a guessing game that costs writes and misses reads. The
effort is trivial against the cost of a wrong index set; indexing without it is the expensive path.

## Common Mistakes

**Under-indexing.** No index on columns that filter/sort large tables, so queries seq-scan and degrade
with growth. Fix: index the measured hot read patterns.

**Over-indexing.** An index on every column "to be safe," taxing writes and wasting storage on indexes
nothing uses. Fix: index only real query patterns; drop unused indexes.

**Wrong composite column order.** A multi-column index the query can't use because the order doesn't match
the filter/sort. Fix: equality columns first, then range/sort; follow the leftmost-prefix rule.

**Wrong index type.** A B-tree for full-text/JSONB (unusable) or GIN where B-tree suffices. Fix: match the
type to the access pattern.

**Indexing without the plan.** Adding indexes by intuition, so they don't help (or aren't used). Fix:
`EXPLAIN (ANALYZE)` before and after; `pg_stat_user_indexes` for unused indexes.

**Indexing a column an index can't help.** Low selectivity, a function on the column, a leading wildcard.
Fix: recognize the case — expression index, rewritten query, different type, or no index.

## AI Mistakes

Indexing is where assistants' pattern-matching diverges most from what measurement shows. They produce
plausible index sets that are wrong in both directions and never mention the query plan. Review any
index advice against an actual `EXPLAIN`.

### Claude Code: no indexes (under-indexing)

Asked to build a schema or a query, Claude Code typically adds no indexes beyond the primary key, because
the code is correct and fast on the small demo dataset. In production, the filtering/sorting queries
sequential-scan and slow down as the table grows — a problem invisible until real data volume arrives.

**Detect:** schemas/queries that filter or sort on unindexed columns; foreign key columns with no index (a
common one — Postgres doesn't auto-index FKs); no indexes for the app's hot query patterns; performance
"fine" only because the test data is tiny.

**Fix:** require indexes for real read patterns (from the plan):

> Add indexes for the actual query patterns: any column frequently used in `WHERE`/`ORDER BY`/join on a
> large table needs one (including foreign keys, which Postgres does not auto-index). Confirm with `EXPLAIN
> (ANALYZE)` that the query uses an index scan, not a seq scan, on a realistically-sized table.

### GPT: over-indexing (an index on every column)

Prompted to make things fast or "add appropriate indexes," GPT-family models tend to add an index on nearly
every column — including low-selectivity ones and columns no query touches — reasoning that more indexes
means faster. It cripples write throughput, bloats storage, and often still doesn't fix the actual slow
query.

**Detect:** indexes on most/all columns of a table; indexes on low-selectivity columns (booleans, small
enums) with no partial condition; indexes on columns no query filters/sorts by; many indexes on a
write-heavy table; no query-plan justification for any of them.

**Fix:** require measured, minimal indexing:

> Don't index every column — each index slows writes and consumes storage. Add only indexes that serve a
> real, measured query pattern, justified by an `EXPLAIN` plan. Drop indexes no query uses. For a
> low-selectivity column, an index usually doesn't help unless it's partial or composite.

### Cursor: wrong composite order and ignoring the plan

Editing to speed one query, Cursor tends to add a composite index without matching the column order to the
query's filter-and-sort, or adds single-column indexes where a correctly-ordered composite is needed — and
never checks whether the planner actually uses it.

**Detect:** composite indexes whose column order doesn't match the query's `WHERE`/`ORDER BY`; single-column
indexes for a multi-column filter that needs a composite; an index added with no `EXPLAIN` confirming it's
used; a query still seq-scanning after an index was "added."

**Fix:** require plan-verified composite design:

> Order the composite index to match the query: equality-filter columns first, then the range/`ORDER BY`
> column (leftmost-prefix rule). After creating it, run `EXPLAIN (ANALYZE)` to confirm the planner uses an
> index scan and the query is actually faster — an index that isn't used is pure write cost.

## Best Practices

**Index from real query plans, not intuition.** Confirm the slow `Seq Scan` with `EXPLAIN (ANALYZE)`, add
the matching index, and verify the index scan and speedup. Use `pg_stat_user_indexes` to find and drop
unused indexes.

**Index the workload — neither under nor over.** Add indexes for the queries that run often or on large
tables (including foreign keys), and resist indexing columns no query uses. Every index is a write tax; spend
it on real reads.

**Match type and column order to the access pattern.** B-tree by default, GIN for full-text/JSONB, correct
composite order (equality then range/sort), partial indexes for hot subsets, covering indexes for hot
projections.

**Recognize when an index can't help.** Low selectivity, a function on the column, or a leading wildcard
defeat indexing — reach for an expression index, a rewritten query, or a different type instead of adding a
useless index.

**Ship indexes as documented, concurrent migrations.** Add indexes via migrations built `CONCURRENTLY` in
production (Chapter 06), document which query each serves, and keep the `EXPLAIN` evidence. Record indexing
conventions in `CLAUDE.md` so assistants stop under- and over-indexing.

## Anti-Patterns

**The Unindexed Table.** Large tables filtered/sorted on unindexed columns, seq-scanning and degrading with
growth. The tell: hot queries with no supporting index; unindexed foreign keys.

**The Index-Everything Table.** An index on nearly every column, taxing writes and wasting storage on unused
indexes. The tell: more indexes than the query patterns justify; indexes on low-selectivity/unused columns.

**The Misordered Composite.** A multi-column index the query can't use because the column order doesn't match
the filter/sort. The tell: a composite index and a query that still seq-scans or sorts separately.

**The Wrong-Type Index.** A B-tree where GIN is needed (full-text/JSONB), so the index is unused. The tell: a
full-text/containment query with a plain B-tree and a seq scan.

**The Superstition Index.** Indexes added by intuition with no plan, helping nothing. The tell: no `EXPLAIN`
evidence anywhere; indexes nobody can say which query they serve.

## Decision Tree

"A query is slow, or I'm designing for a read pattern — do I add an index, and which?"

```
FIRST: EXPLAIN (ANALYZE) the query. Is it a Seq Scan on a large table returning few rows?
├── NO (already an index scan / tiny table) ──► don't add an index.
└── YES ──► an index may help. What's the access pattern?

     equality / range / sort / join on ordered data ──► B-TREE (the default)
     full-text / JSONB / array containment ───────────► GIN
     geometric / range-overlap ───────────────────────► GiST
     huge, physically-ordered (time-series) ──────────► BRIN

Multi-column filter (WHERE a AND b ORDER BY c)?
└──► COMPOSITE index, order = equality cols first, then the sort/range col (a, b, c). Leftmost-prefix rule.

Query always filters to a small subset (status='overdue')? ──► PARTIAL index (WHERE ...).
Query selects only a few columns on a hot path? ──► COVERING index (INCLUDE those columns) → index-only scan.

Would an index be defeated?  (low selectivity / function on column / leading wildcard '%x')
└──► an index won't help ──► expression index, rewrite the query, or a different type.

AFTER creating: EXPLAIN (ANALYZE) again — confirm the index is USED and the query is faster.
Periodically: drop indexes pg_stat_user_indexes shows unused.
```

## Checklist

### Implementation Checklist

- [ ] Hot read patterns (frequent or on large tables) have matching indexes, confirmed by `EXPLAIN (ANALYZE)`.
- [ ] Foreign key columns used in joins/filters are indexed (Postgres doesn't auto-index them).
- [ ] Composite indexes order columns to match the query (equality first, then range/sort).
- [ ] Index types match access patterns (B-tree default, GIN for full-text/JSONB, etc.).
- [ ] Partial/covering indexes are used for the specific hot subsets/projections that justify them.
- [ ] No indexes exist on columns no query uses; unused indexes are dropped.

### Architecture Checklist

- [ ] The index set matches the measured workload — neither under- nor over-indexed.
- [ ] Each index is documented with the query it serves, with `EXPLAIN` evidence kept.
- [ ] Write-heavy tables are reviewed for over-indexing (index count vs write cost).
- [ ] Indexes ship as migrations, built `CONCURRENTLY` in production (Chapter 06).
- [ ] Indexing conventions are documented in `CLAUDE.md`.

### Code Review Checklist

- [ ] No hot query left seq-scanning a large table (watch AI diffs for missing indexes).
- [ ] No index-everything / indexes on unused or low-selectivity columns.
- [ ] No misordered composite index; column order matches the query.
- [ ] No wrong-type index (B-tree for full-text/JSONB).
- [ ] Every added index has `EXPLAIN` evidence that it's used and helps.

### Deployment Checklist

- [ ] Indexes on large tables are created `CONCURRENTLY` to avoid locking writes.
- [ ] Index creation on huge tables is scheduled/monitored (it can take significant time and I/O).
- [ ] `pg_stat_user_indexes` is checked post-deploy to confirm new indexes are used and find unused ones.

## Exercises

**1. Turn a seq scan into an index scan.** On a realistically-sized `invoices` table, run the list query
(`WHERE customer_id AND status ORDER BY issued_at`) under `EXPLAIN (ANALYZE)`, observe the seq scan, add the
correctly-ordered composite index, and re-run to prove the index scan and speedup. The artifact is the
before/after plans and timings.

**2. Diagnose an over-indexed table.** Take (or generate) a table with an index on every column, use
`pg_stat_user_indexes` to identify which are actually used, measure write throughput before and after dropping
the unused ones, and confirm the hot query is unaffected. The artifact is the dropped-index list and the
write-throughput difference.

**3. Choose the right specialized index.** Implement full-text search over invoice descriptions with a GIN
index and the overdue-dashboard query with a partial index, proving with `EXPLAIN` that each is used and that a
plain B-tree would not have served the full-text case. The artifact is the two indexes and their plans.

## Further Reading

- **PostgreSQL documentation — "Indexes" (Index Types, Multicolumn Indexes, Partial Indexes, Index-Only Scans)**
  (postgresql.org/docs) — the authoritative reference for every index type and pattern in this chapter.
- **PostgreSQL documentation — "Using EXPLAIN"** (postgresql.org/docs) — how to read query plans; the core skill
  that turns indexing from guesswork into measurement.
- **"Use The Index, Luke!" by Markus Winand** (use-the-index-luke.com) — the best practical guide to B-tree
  indexing, composite column order, and the leftmost-prefix rule; directly reinforces this chapter's composite-
  index judgment.
- **Stage 6, Chapter 05 — Query Optimization** — the next step: reading plans in depth and optimizing queries
  (join strategies, N+1, statistics) once the right indexes exist. Indexing and query optimization are two halves
  of one skill.
</content>

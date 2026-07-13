# Query Optimization

## Introduction

A slow application is, more often than not, a slow query — and a slow query is almost
always a fixable one once you can see what the database is actually doing. Chapter 03
added the right indexes; this chapter is about the broader skill of making queries fast:
reading the execution plan to find where the time goes, recognizing the handful of
patterns that cause most slowness (the N+1 problem above all), and fixing them by
changing the query rather than throwing hardware at the symptom. It's the diagnostic
half of database performance — indexing gives the database a fast path, and query
optimization is making sure your queries take it.

The single most important idea: **the database's query planner already knows how to run
your query efficiently — your job is to read what it decided (`EXPLAIN ANALYZE`) and
remove whatever is forcing a bad plan.** PostgreSQL's planner is a sophisticated,
cost-based optimizer; it chooses join strategies, decides whether to use an index, and
estimates row counts. When a query is slow, it's usually because the planner was forced
into a bad choice — a missing index, a query shape it can't optimize, stale statistics,
or a function that defeats an index. The plan tells you which. Optimizing queries without
reading the plan is guessing; reading the plan turns it into a diagnosis. This is the
same `EXPLAIN`-driven discipline from Chapter 03, applied to the whole query rather than
just its indexes.

The judgment this chapter teaches is pattern recognition plus measurement. The dominant
pattern is the **N+1 query** — fetching a list, then firing one more query per row —
which is invisible in code (each query looks innocent) and devastating at scale (one page
load becomes hundreds of round-trips). It's also the single most common performance bug
in ORM- and AI-generated code, because the natural way to write the code produces it.
Beyond N+1: selecting more than you need, missing the index the plan wanted, join-order
problems, and stale statistics. Throughout, the rule from Stage 4's performance chapter
holds — **measure first, optimize the proven bottleneck** — because the query you *think*
is slow usually isn't the one that is.

## Why It Matters

Query performance is where most application slowness actually lives, and the failures
scale badly and hide well:

- **One query can dominate the whole request.** A page that feels slow is usually waiting
  on one query, not on the framework or the network. Databases are frequently the
  bottleneck, and a single missing index or bad query shape can turn a 5ms endpoint into
  a 5-second one. Optimizing the query is often the entire fix.
- **N+1 turns one operation into hundreds.** Fetch 100 invoices, then load each one's
  customer with a separate query, and one page load is 101 database round-trips. Each
  query is fast; the aggregate is a disaster. N+1 is the most common and most damaging
  query bug, and it's invisible unless you count queries or read the logs.
- **Slowness scales with data, so it hides in development.** A query that scans a table or
  does N+1 is instant on the 50 rows in your dev database and catastrophic on the 5 million
  in production. The bug ships green and detonates as data grows — the worst feedback loop.
- **Guessing wastes effort on the wrong query.** Without the plan, you optimize the query
  you suspect (often wrong) and miss the one actually burning time. `EXPLAIN ANALYZE`
  points at the real bottleneck; intuition points at a plausible one.
- **Fetching too much is a silent tax.** `SELECT *` and over-fetching pull columns and rows
  the app discards — more I/O, more memory, more network, and often a missed index-only
  scan. It's rarely the headline bug and frequently a real, cumulative cost.
- **Throwing hardware at a bad query is expensive and temporary.** Scaling the database to
  paper over an N+1 or a missing index costs money and buys a little time; the query is
  still wrong and will outgrow the bigger machine. Fixing the query is cheaper and
  permanent.

Get it right — plans read, N+1 eliminated, queries selecting only what's needed and using
the indexes that exist — and the database stays fast at scale and the app is responsive.
Get it wrong and you ship queries that are instant in dev, collapse under production data,
and get "fixed" with ever-bigger database instances that only delay the reckoning.

The AI dimension: assistants produce N+1 queries by default (the natural ORM code, a loop
that loads a relation per row), `SELECT *` everywhere, and queries with no awareness of the
plan or the indexes — and, like all query bugs, it looks perfect until real data arrives.
Query optimization is where "it works" and "it works at scale" diverge most.

## Mental Model

The planner already optimizes; you read its plan, spot the pattern, and fix the query:

```
   THE PLANNER (a cost-based optimizer) already picks join strategy, index use, row estimates.
     a slow query = the planner was FORCED into a bad plan. the plan tells you why.

   READ THE PLAN:  EXPLAIN (ANALYZE, BUFFERS) <query>
     Seq Scan on big table returning few rows ─► missing/unusable index (Ch 03)
     actual rows ≫ estimated rows ────────────► stale statistics → ANALYZE
     Nested Loop over many rows ──────────────► maybe a join/row-count problem
     actual time concentrated in one node ────► THAT is your bottleneck

   THE #1 PATTERN — N+1 (invisible in code, devastating at scale)
     for invoice in invoices:            #  1 query for the list
         invoice.customer.name           # +N queries, one per row  → 1 + N round-trips
     FIX: fetch related data in ONE query — JOIN / eager load (selectinload/joinedload) / IN (...)

   OTHER COMMON PATTERNS
     SELECT *  ─────────► select only needed columns (less I/O; enables index-only scans)
     OFFSET pagination ─► keyset/cursor pagination for deep pages (OFFSET 100000 scans 100000 rows)
     function on column ► WHERE lower(email)=  defeats the index → expression index / normalize
     over-fetching rows ► filter/aggregate in the DB, not by pulling rows into the app

   THE RULE (same as Stage 4 perf):  MEASURE first ─► fix the PROVEN bottleneck ─► verify.
     don't optimize by guessing · don't throw hardware at a fixable query.
```

Four principles carry the chapter:

**Read the plan; the planner tells you what's wrong.** `EXPLAIN (ANALYZE)` shows the actual
strategy and where time goes — a seq scan, a bad row estimate, a costly node. Diagnose from
the plan, not from intuition; optimization without the plan is guessing.

**Kill N+1 by fetching related data in one query.** The dominant query bug is one-query-per-
row from a loop or lazy-loaded relation. Fix it with a join or eager loading so related data
comes back in a single (or a constant number of) queries — turn 1+N into 1 or 2.

**Select and fetch only what you need.** Avoid `SELECT *` and over-fetching rows; pull the
columns and rows the app actually uses, and push filtering and aggregation into the database
rather than into application code. Less data moved is less time spent.

**Measure first, fix the proven bottleneck, don't buy hardware for a bad query.** Find the
query actually burning time (logs, plan), fix its shape or its index, and verify the win.
Scaling the database to hide a fixable query is expensive and temporary.

A working definition:

> **Query optimization is reading the planner's execution plan (`EXPLAIN ANALYZE`) to find
> where time goes, recognizing the patterns that force bad plans — N+1 above all, plus
> `SELECT *`, over-fetching, deep `OFFSET` pagination, and index-defeating predicates — and
> fixing the query (one-query eager loading, selecting only what's needed, filtering in the
> database) rather than throwing hardware at it. Measure first, fix the proven bottleneck,
> verify.**

## Production Example

**Invoicely's** invoice list is the textbook N+1 scene. The endpoint fetches the user's
invoices, and for each invoice the response includes the customer name and the count of line
items. Written the natural ORM way — fetch invoices, then access `invoice.customer` and
`invoice.line_items` in a loop — the page issues one query for the list plus two per invoice.
On the 20 invoices in a dev database that's ~40 fast queries and feels fine; on a customer with
2,000 invoices it's ~4,000 round-trips and the endpoint times out. Nothing in the code looks
wrong — each access is a single innocent line — which is exactly why N+1 is so common and so
hard to spot without counting queries.

The fixes are all query-shape changes, not hardware. The customer name comes back in the same
query via an eager load / join; the line-item counts come back via a single aggregated query
(`GROUP BY invoice_id`) rather than one count per invoice. The list also selects only the
columns the response needs (not `SELECT *`), and it paginates with keyset pagination rather than
deep `OFFSET` so page 500 doesn't scan half a million rows. Each change is verified with
`EXPLAIN (ANALYZE)` and by counting the queries the endpoint issues — turning ~4,000 queries
into 2.

In this chapter we optimize that endpoint: reproduce the N+1 by logging query counts, read the
plan, fix it with eager loading and aggregation, trim the columns, and switch to keyset
pagination — measuring at each step. We contrast it with the assistant-default version (the
loop that lazy-loads relations, `SELECT *`, `OFFSET` pagination) that is green in dev and
collapses on real data.

## Folder Structure

```
api/app/
├── features/invoices/
│   ├── queries.py            # list query: eager-loads relations (no N+1); selects needed columns
│   └── repository.py         # data access; keyset pagination; aggregation in the DB
├── db/
│   ├── explain/              # saved EXPLAIN ANALYZE before/after per optimized query
│   └── query_log.md          # how to enable query logging / count queries per request
└── middleware/
    └── query_counter.py      # dev-only: counts DB queries per request → catches N+1 in review
```

Why this shape: the list query and its data access live together so the eager-loading and
pagination decisions are visible where the query is built. The `query_counter` middleware is
the key preventive tool — it counts queries per request in development, so an N+1 (a request
suddenly issuing hundreds of queries) is caught in review rather than in production; N+1 is
invisible in code but obvious in a query count. The `explain/` directory keeps the before/after
plans, so every optimization is backed by measurement and can be revisited. The structure
encodes the chapter's method: measure (count queries, read plans), fix the query, keep the
evidence.

## Implementation

**Reproduce the N+1 — the natural code that's quietly catastrophic.** Each relation access is a
hidden query.

```python
# ANTI-PATTERN: N+1 — 1 query for the list, then 2 more PER invoice
def list_invoices_bad(session, customer_id):
    invoices = session.scalars(select(Invoice).where(Invoice.customer_id == customer_id)).all()  # 1
    return [{
        "number": inv.number,
        "customer": inv.customer.name,           # +1 query per invoice (lazy load)
        "line_count": len(inv.line_items),       # +1 query per invoice (lazy load)
    } for inv in invoices]
    # 2,000 invoices → ~4,001 queries. Green on 20 rows in dev; times out in prod.
```

**Fix N+1 with eager loading — related data in one query.** `selectinload`/`joinedload` fetch
the relations in a constant number of queries, not one per row.

```python
# Eager-load relations: the list + its customers + its line items in a FIXED number of queries.
def list_invoices(session, customer_id):
    invoices = session.scalars(
        select(Invoice)
        .where(Invoice.customer_id == customer_id)
        .options(joinedload(Invoice.customer), selectinload(Invoice.line_items))  # no N+1
    ).unique().all()
    return [{"number": inv.number, "customer": inv.customer.name, "line_count": len(inv.line_items)}
            for inv in invoices]
    # ~4,001 queries → 2. Same result, no lazy-load-per-row.
```

**Aggregate in the database, not the application.** When you only need a count, ask the database
for the count — don't load rows to count them in Python.

```python
# Need line-item counts per invoice → ONE aggregated query, not one count per invoice.
def invoice_line_counts(session, customer_id):
    return session.execute(
        select(Invoice.id, func.count(LineItem.id))
        .join(LineItem, LineItem.invoice_id == Invoice.id)
        .where(Invoice.customer_id == customer_id)
        .group_by(Invoice.id)                                # DB does the counting
    ).all()
```

**Select only what you need, and paginate by keyset.** Trim columns (enabling index-only scans)
and avoid deep-`OFFSET` scans.

```python
# Select needed columns only (not SELECT *), and keyset-paginate (no OFFSET scan of skipped rows).
def list_invoices_page(session, customer_id, after_issued_at):
    return session.execute(
        select(Invoice.id, Invoice.number, Invoice.total, Invoice.issued_at)   # only what the response uses
        .where(Invoice.customer_id == customer_id, Invoice.issued_at < after_issued_at)  # keyset cursor
        .order_by(Invoice.issued_at.desc())
        .limit(50)
    ).all()
    # OFFSET 100000 would scan and discard 100000 rows; keyset jumps straight to the page.
```

**Read the plan and check row estimates.** Confirm the fix, and catch stale statistics (a large
gap between estimated and actual rows).

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, number, total FROM invoices WHERE customer_id = 42 ORDER BY issued_at DESC LIMIT 50;
-- Index Scan ... (actual rows=50)   ← good.
-- If "rows=1 ... actual rows=50000" (estimate way off) → run ANALYZE invoices; (refresh statistics)
```

**Detect N+1 automatically (`query_counter.py`).** The cheapest defense: count queries per request
in dev.

```python
# Dev-only: log a warning when a single request issues an unexpectedly high number of queries.
def query_counter_middleware(request):
    count = count_queries_during(request)          # hook into the DB driver/ORM events
    if count > THRESHOLD:                            # e.g. > 20 queries for one endpoint
        log.warning("Possible N+1: %s issued %d queries", request.path, count)
```

The difference is the whole chapter: the good version fetches related data in a fixed number of
queries (no N+1), aggregates and filters in the database, selects only needed columns, and
paginates by keyset — all verified by plans and query counts. The bad version lazy-loads a
relation per row, `SELECT *`s, and deep-`OFFSET`s — a handful of innocent-looking lines that turn
one page load into thousands of queries the moment real data arrives.

## Engineering Decisions

Five decisions define query performance.

### How do you diagnose a slow query?

**Options:** (1) intuition/reading the code; (2) `EXPLAIN (ANALYZE)` on the query; (3) production
query logs / `pg_stat_statements` to find the worst queries.

**Trade-offs:** intuition optimizes the query you suspect, which is often not the slow one. `EXPLAIN
(ANALYZE)` shows the actual plan and timing for a specific query. `pg_stat_statements` and slow-query
logs surface, across production, which queries actually consume the most time — the ones worth
optimizing.

**Recommendation:** find the real offenders with production query stats (`pg_stat_statements`,
slow-query log), then diagnose each with `EXPLAIN (ANALYZE)`. Optimize the queries measurement proves
are expensive, not the ones you guess are. This is the measure-first discipline from Stage 4,
Chapter 07 applied to SQL.

### How do you fix N+1?

**Options:** (1) leave it (lazy loading per row); (2) eager load (join/`selectinload`/`joinedload`);
(3) a single manual query with `IN`/aggregation.

**Trade-offs:** lazy-per-row is the default that produces N+1 — fine for one object, catastrophic for
a list. Eager loading fetches relations in a fixed number of queries and is the idiomatic ORM fix.
A hand-written query with a join or `IN (...)` gives full control and can be the most efficient for
complex cases, at the cost of writing SQL.

**Recommendation:** eager-load related data for any list (join/`selectinload`), turning 1+N into a
constant number of queries, and drop to a hand-written join/aggregation for complex shapes the ORM
loads inefficiently. Never access a lazy relation inside a loop over a list — that's the N+1. Count
queries per request to catch it.

### How much do you select and fetch?

**Options:** (1) `SELECT *` / fetch whole objects; (2) select only needed columns; (3) fetch and
process in the app vs aggregate in the DB.

**Trade-offs:** `SELECT *` is convenient and moves unneeded columns (more I/O, more memory, can prevent
an index-only scan). Selecting only needed columns is leaner and index-friendlier at the cost of being
explicit. Pulling rows into the app to filter/count/aggregate there moves far more data than asking the
database to do it.

**Recommendation:** select only the columns the code uses (not `SELECT *`), and push filtering,
counting, and aggregation into the database rather than doing them in application code. The database is
built to filter and aggregate close to the data; moving rows into the app to process them is almost
always slower.

### How do you paginate?

**Options:** (1) `LIMIT/OFFSET`; (2) keyset/cursor pagination; (3) no pagination (fetch all).

**Trade-offs:** `OFFSET` is simple and degrades linearly — `OFFSET 100000` scans and discards 100,000
rows before returning any. Keyset pagination (a `WHERE` cursor on an ordered indexed column) jumps
straight to the page in constant time, at the cost of a slightly less flexible API (no arbitrary page
jumps). Fetching everything is fine for tiny sets and a disaster for large ones.

**Recommendation:** use `OFFSET` only for small, shallow result sets; use keyset/cursor pagination for
anything that can be large or deeply paged (feeds, long lists). Never fetch an unbounded set. Deep
`OFFSET` is a common, easily-missed source of slowness that keyset pagination eliminates.

### Fix the query or scale the hardware?

**Options:** (1) scale the database (bigger instance, read replicas); (2) fix the query/schema/index;
(3) cache the result.

**Trade-offs:** scaling hardware papers over a bad query at ongoing cost and buys limited runway — the
query is still wrong. Fixing the query (kill N+1, add the index, reshape) is usually cheap and permanent.
Caching (Stage 3, Chapter 07) avoids the query entirely for repeated reads at the cost of invalidation.

**Recommendation:** fix the query first — most "we need a bigger database" moments are one N+1 or one
missing index. Reach for read replicas and caching for genuine scale after the queries are correct, not
as a substitute for fixing them. Throwing hardware at a fixable query is the expensive, temporary path.

## Trade-offs

Query optimization trades a little explicitness and measurement effort for performance that holds at
scale.

**Eager loading trades a slightly heavier single query for eliminating N+1.** Fetching relations up
front means one larger query (or a couple) instead of many tiny ones, and it removes the round-trip
explosion that makes lists collapse at scale. For any list with related data the trade is decisively
worth it; the only caution is not eager-loading relations you won't use.

**Selecting only what you need trades convenience for less I/O.** Naming columns and pushing aggregation
into the database is more explicit than `SELECT *` and processing in the app, and it moves less data and
enables index-only scans. A small, cumulative win that also tends to make the query's intent clearer.

**Keyset pagination trades API flexibility for constant-time deep pages.** A cursor-based API can't jump
to an arbitrary page number as easily as `OFFSET`, and it keeps deep pagination fast regardless of depth.
For large or infinite lists that's the right trade; for a small admin table with a handful of pages,
`OFFSET` is fine.

**Measurement trades minutes for optimizing the right thing.** Reading plans and query stats takes a
little time and ensures you fix the query that's actually slow rather than a plausible suspect. Against
the cost of optimizing the wrong query — or scaling hardware to hide the real one — the effort is
trivial.

## Common Mistakes

**N+1 queries.** Lazy-loading a relation per row in a loop, turning one operation into hundreds of
queries. Fix: eager load (join/`selectinload`) or a single aggregated query; count queries per request.

**Optimizing without the plan.** Guessing at the slow query and the fix. Fix: `pg_stat_statements`/slow
log to find it, `EXPLAIN (ANALYZE)` to diagnose it.

**`SELECT *` and over-fetching.** Pulling columns and rows the app discards. Fix: select needed columns;
filter/aggregate in the database.

**Processing in the app instead of the database.** Loading rows to count/filter/aggregate in Python. Fix:
let the database do it (`COUNT`, `GROUP BY`, `WHERE`).

**Deep `OFFSET` pagination.** `OFFSET 100000` scanning six figures of rows per page. Fix: keyset/cursor
pagination.

**Scaling hardware to hide a bad query.** Bigger instances papering over N+1 or a missing index. Fix:
fix the query first; scale for real load after.

## AI Mistakes

Query optimization is a place where assistant code is correct and quietly non-scaling — the N+1 in
particular is the natural output of the way ORM code is written. Review generated data access by counting
the queries it will issue on real data, not by whether it returns the right result.

### Claude Code: N+1 by default

Asked to build a list endpoint that includes related data, Claude Code writes the natural ORM code — fetch
the list, then access each item's relations — which lazy-loads one query per row. It returns the correct
data and, on the small dev dataset, runs fine; on production data it's hundreds or thousands of queries per
request.

**Detect:** a loop (or comprehension) over a list that accesses a relationship attribute
(`item.related.x`); no eager loading (`selectinload`/`joinedload`/join) on a query whose results' relations
are used; a request whose query count grows with the number of rows; serializers that touch relations per
item.

**Fix:** require eager loading for lists:

> This lazy-loads a relation per row — an N+1 that will issue one query per result in production. Eager-load
> the relations you use (`selectinload`/`joinedload`, or a join), so the list and its related data come back
> in a fixed number of queries. Never access a lazy relationship inside a loop over a list; count the queries
> the endpoint issues.

### GPT: `SELECT *`, app-side processing, and OFFSET pagination

GPT-family models default to fetching whole rows (`SELECT *`), processing/filtering/counting in application
code, and `LIMIT/OFFSET` pagination — all convenient and all wasteful, moving far more data than needed and
degrading as data and page depth grow.

**Detect:** `SELECT *`/fetching full objects when few columns are used; filtering, counting, or aggregating
in Python over fetched rows; `OFFSET`-based pagination on potentially large sets; unbounded fetches with no
limit.

**Fix:** require lean, DB-side queries:

> Select only the columns you use (not `SELECT *`), and do filtering/counting/aggregation in the database
> (`WHERE`/`COUNT`/`GROUP BY`), not by pulling rows into the app. Use keyset/cursor pagination for large or
> deeply-paged results, not `OFFSET`. Move as little data out of the database as possible.

### Cursor: optimizing without the plan (or scaling to hide it)

Editing a slow query, Cursor tends to tweak it by intuition — or suggest a bigger database / a cache — without
running `EXPLAIN` to see what's actually slow, so it optimizes the wrong thing or hides a fixable query behind
hardware.

**Detect:** query changes with no `EXPLAIN` evidence; a suggestion to scale the instance/add a replica/cache
in response to one slow query without diagnosis; assumptions about which query is slow with no measurement; a
"fix" that doesn't change the plan.

**Fix:** require plan-driven diagnosis:

> Before changing (or scaling around) this, run `EXPLAIN (ANALYZE)` to see the actual plan and where the time
> goes, and check `pg_stat_statements` to confirm this is really the expensive query. Fix the query/index the
> plan points to and verify the plan improved. Don't optimize by intuition or scale hardware to hide a fixable
> query.

## Best Practices

**Diagnose from measurement.** Find the expensive queries with `pg_stat_statements`/slow logs, diagnose each
with `EXPLAIN (ANALYZE)`, fix the proven bottleneck, and verify the plan improved. Don't optimize by
intuition.

**Eliminate N+1 by fetching related data in one query.** Eager-load relations for lists, aggregate in the
database, and count queries per request (a dev query-counter) so N+1 is caught in review. Never lazy-load a
relation per row.

**Fetch lean and process in the database.** Select only needed columns (not `SELECT *`), push filtering,
counting, and aggregation into the database, and paginate large sets by keyset rather than deep `OFFSET`.

**Keep statistics fresh and use the indexes you have.** Watch for large estimate-vs-actual row gaps (run
`ANALYZE`), avoid index-defeating predicates (functions on columns, leading wildcards), and confirm hot
queries use the indexes from Chapter 03.

**Fix the query before scaling the hardware, and document the patterns.** Most "bigger database" moments are a
fixable query; scale and cache for real load after the queries are correct. Document the query conventions
(eager loading, keyset pagination, no `SELECT *`) in `CLAUDE.md` so assistants stop shipping N+1.

## Anti-Patterns

**The N+1.** A relation lazy-loaded per row in a loop — one operation, hundreds of queries. The tell: a loop
over a list touching `item.related`, no eager loading; a request whose query count scales with rows.

**The Blind Optimization.** Query changes made by intuition with no plan. The tell: no `EXPLAIN` evidence; a
"fix" that doesn't change the plan.

**The `SELECT *`.** Whole rows fetched when few columns are used, blocking index-only scans and moving extra
data. The tell: `SELECT *` where the code uses three columns.

**The App-Side Aggregate.** Rows pulled into the application to count/filter/aggregate. The tell: a Python loop
summing/counting what a `GROUP BY` could do.

**The Deep OFFSET.** `OFFSET`-based pagination scanning six figures of rows per deep page. The tell: `OFFSET`
on a large, deeply-paged list.

**The Hardware Band-Aid.** A bigger instance or a replica added to hide an N+1 or missing index. The tell:
scaling in response to one slow query, with no diagnosis.

## Decision Tree

"A query (or endpoint) is slow — how do I find and fix it?"

```
FIRST: is this even the slow query? ── pg_stat_statements / slow log → find the real offenders.
Then EXPLAIN (ANALYZE, BUFFERS) it. Where does the time actually go?

Does the endpoint issue MANY queries (grows with row count)?
└──► N+1. Eager-load relations (selectinload/joinedload/join) or one aggregated query. 1+N → constant.

Is it a Seq Scan on a big table returning few rows?
└──► missing/unusable index ──► Chapter 03 (add the index; avoid function-on-column predicates).

Estimated rows ≫/≪ actual rows in the plan?
└──► stale statistics ──► ANALYZE the table.

Fetching more than needed?
├── SELECT * but few columns used ──► select only needed columns (enables index-only scans).
├── counting/filtering in app code ──► do it in the DB (COUNT/GROUP BY/WHERE).
└── deep OFFSET pagination ──► keyset/cursor pagination.

Query is correct and genuinely at scale?
└──► THEN consider caching (Stage 3 Ch 07) / read replicas — not before fixing the query.

AFTER: EXPLAIN again + recount queries — verify the fix. Don't scale hardware to hide a fixable query.
```

## Checklist

### Implementation Checklist

- [ ] List endpoints eager-load related data (no N+1); query count per request is bounded, not proportional to rows.
- [ ] Aggregation/counting/filtering happens in the database, not in application code.
- [ ] Queries select only needed columns (no `SELECT *`).
- [ ] Large or deeply-paged results use keyset/cursor pagination, not deep `OFFSET`.
- [ ] Slow queries are diagnosed with `EXPLAIN (ANALYZE)` and fixed to use the intended plan/index.
- [ ] Table statistics are fresh (no large estimate-vs-actual gaps); index-defeating predicates are avoided.

### Architecture Checklist

- [ ] Expensive queries are identified from production stats (`pg_stat_statements`/slow log), not guessed.
- [ ] A dev query-counter (or equivalent) catches N+1 before production.
- [ ] Queries are fixed before scaling hardware; caching/replicas are for real load after correctness.
- [ ] Before/after `EXPLAIN` evidence is kept for optimized queries.
- [ ] Query conventions (eager loading, keyset pagination, no `SELECT *`) are documented in `CLAUDE.md`.

### Code Review Checklist

- [ ] No N+1 — no lazy relation access in a loop over a list (watch AI diffs closely).
- [ ] No `SELECT *` or over-fetching where specific columns suffice.
- [ ] No app-side counting/filtering the database should do.
- [ ] No deep `OFFSET` pagination on large sets.
- [ ] No optimization or scaling decision made without a query plan / measurement.

### Deployment Checklist

- [ ] `pg_stat_statements` (or equivalent) and slow-query logging are enabled in production.
- [ ] `autovacuum`/`ANALYZE` keeps statistics current on high-churn tables.
- [ ] Query-latency monitoring is in place to catch regressions as data grows.

## Exercises

**1. Find and fix the N+1.** Instrument the invoice-list endpoint to count queries, observe the count scale
with the number of invoices, then fix it with eager loading and an aggregated count query and show the count
drop to a constant. The artifact is the before/after query counts and the fix.

**2. Read the plan and remove a seq scan.** Take a slow filtered query, run `EXPLAIN (ANALYZE)`, identify why
it seq-scans (missing index, function on the column, or stale stats), fix the root cause, and re-run to confirm
the improved plan. The artifact is the before/after plans and the diagnosis.

**3. Replace OFFSET with keyset pagination.** Measure the latency of `OFFSET`-based pagination at page 1 versus
a deep page on a large table, implement keyset pagination, and show the deep-page latency become constant. The
artifact is the latency comparison and the keyset implementation.

## Further Reading

- **PostgreSQL documentation — "Using EXPLAIN" and "Query Planning"** (postgresql.org/docs) — how to read plans
  and how the planner chooses strategies; the core diagnostic skill of this chapter.
- **`pg_stat_statements` documentation** (postgresql.org/docs) — finding the queries that actually consume the
  most time in production; how to identify the real bottlenecks rather than guessing.
- **"Use The Index, Luke!" by Markus Winand — pagination and joins chapters** (use-the-index-luke.com) — keyset
  pagination and join performance in depth; directly supports this chapter's pagination and N+1 guidance.
- **Stage 6, Chapter 03 — Indexing** — the other half of query performance; many slow queries are fixed by the
  right index, and reading the plan (this chapter) is how you know which. Indexing and query optimization are one
  skill.
</content>

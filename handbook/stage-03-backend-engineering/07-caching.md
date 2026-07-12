# Caching

## Introduction

Caching stores the result of an expensive operation so that future requests can
return it without recomputing — trading a small amount of freshness for a large
amount of speed and load reduction. This chapter is about application-level caching
in the backend, typically with Redis: what to cache, how to keep it correct as the
underlying data changes, and the failure modes that make caching famous as one of the
genuinely hard problems in the field.

The read side of caching is trivial — check the cache, and on a miss, compute and
store. The hard part, the part this chapter is really about, is everything else:
*invalidation* (keeping the cache correct when the source data changes), *key design*
(so the cache returns the right result for the right inputs — including the right
tenant), *lifecycle* (TTLs and eviction so the cache doesn't grow without bound or
serve forever-stale data), and *stampedes* (what happens when a hot key expires and a
thousand requests miss at once). The old joke — that the two hard things in computer
science are cache invalidation and naming things — is about this chapter.

Caching is also where a whole-system property, *consistency*, gets negotiated
explicitly. A cache is a copy; the database is the source of truth; and the gap
between them is staleness you are choosing to accept in exchange for speed. Deciding
*how much* staleness is acceptable, per kind of data, is the core judgment — and it
is a judgment, not a default, because some data can be a minute out of date and some
must never be.

## Why It Matters

Caching is one of the highest-leverage performance tools in a backend: an expensive
aggregation that takes 800ms against the database can return in 2ms from Redis, and
the database load for a hot endpoint can drop by orders of magnitude. For read-heavy
workloads — dashboards, listings, computed reports — caching is often the difference
between a service that scales and one that falls over under load.

But caching introduces a second copy of the truth, and that copy is where the
expensive, subtle bugs live:

- **Stale data from missing invalidation.** The read-side cache is easy to add and
  easy to leave *un-invalidated*, so when the underlying data changes, readers keep
  getting the old value — sometimes forever, if there's no TTL. Users see a balance
  that's wrong, a status that didn't update, a list missing the item they just
  created. This is the hard half of caching, and it is where most cache bugs come
  from.
- **Cross-tenant leaks from bad keys.** A cache key must encode *every* input that
  affects the result — and in a multi-tenant SaaS that includes the tenant. Omit the
  `account_id` and one tenant's cached dashboard is served to another: a data breach
  through the cache, exactly the IDOR class from Chapter 04, one layer over.
- **Unbounded growth and stampedes.** A cache with no TTL and no eviction grows until
  it exhausts memory; a hot key with no stampede protection sends every concurrent
  miss to the database at once when it expires, turning the cache from a shield into
  an amplifier of load.

The AI dimension is the "cache invalidation is hard" truth, automated: an assistant
adds the read-side lookup that makes the demo fast and omits the invalidation (stale
data), the tenant dimension in the key (cross-tenant leak), and the TTL/eviction
(unbounded growth). Each makes the happy path faster and the system subtly, sometimes
dangerously, wrong.

## Mental Model

The dominant pattern is *cache-aside*, and its correctness rests on what happens
around the read:

```
   CACHE-ASIDE (lazy loading) — the common pattern

   READ:  check cache ──hit──► return (fast; data is a COPY, possibly stale)
                    └─miss──► compute from the DB (source of truth)
                              ─► store in cache with a TTL ─► return

   WRITE: update the DB (source of truth)
            └─► INVALIDATE (or update) the cache entry  ← the hard, easy-to-forget half

   THE HARD PARTS (everything except the read):
   · INVALIDATION — on every write that affects a cached value
   · KEY DESIGN   — encodes ALL inputs, including the TENANT
   · LIFECYCLE    — TTL (bound staleness) + eviction (bound memory)
   · STAMPEDE     — protect hot keys so an expiry doesn't flood the DB
```

Four principles keep a cache correct:

**The database is the source of truth; the cache is a disposable copy.** You must be
able to delete the entire cache and lose nothing but speed. Never treat the cache as
authoritative, never store data only in the cache, and design so a cold or flushed
cache is correct (just slower). This framing makes staleness a performance property,
not a correctness one.

**A cache key encodes every input that affects the result — including the tenant.**
If two different inputs could map to the same key, one will get the other's data. In
a multi-tenant system the account/user is an input, so it belongs in the key; omitting
it is a cross-tenant leak. The key is `f"summary:{account_id}:{period}"`, never just
`f"summary:{period}"`.

**Invalidate on write, or bound staleness with a TTL — decide per data type.**
Whenever data changes, either invalidate/update the cached value (precise, but you
must remember every write path) or rely on a TTL to expire it (simple, but accepts
staleness up to the TTL). How much staleness is acceptable is a per-data decision: a
dashboard tolerates a minute; an account balance tolerates none and probably shouldn't
be cached that way at all.

**Bound memory and protect hot keys.** Every cache entry has a TTL and the cache has an
eviction policy (LRU), so it can't grow without bound. Hot keys — ones many requests
want — get stampede protection (single-flight locking, or staggered/early expiry) so
that when one expires, one request recomputes it while the rest wait, instead of a
thousand hammering the database simultaneously.

A working definition:

> **Caching stores expensive results to trade freshness for speed, with the database
> as the source of truth and the cache as a disposable copy. Its difficulty is not the
> read but the invalidation, the tenant-safe key, the TTL-and-eviction lifecycle, and
> stampede protection — the parts that keep the copy correct and bounded.**

## Production Example

**Invoicely's** dashboard shows each account an expensive summary — total outstanding,
overdue count, revenue this month — computed by aggregating across all their invoices
and payments. It is read on every dashboard load, costs a heavy multi-join aggregation
each time, and is tolerably stale (a minute-old figure is fine). That is the textbook
caching candidate: expensive, hot, and staleness-tolerant.

We will cache it with cache-aside in Redis, and use it to demonstrate every hard part:
a tenant-scoped key (so account A never sees account B's summary — the Chapter 04 IDOR
concern at the cache layer), a TTL to bound staleness plus explicit invalidation when
an invoice changes, and single-flight stampede protection because the key is hot. We
will also note what *not* to cache this way — an account balance that must be exact —
because knowing what to leave uncached is as much the skill as knowing what to cache.

## Folder Structure

```
core/
├── cache.py              # Redis client + cache-aside helper (get-or-compute) + stampede lock
modules/dashboard/
├── _service.py           # reads via cache-aside; keys scoped by account
modules/invoicing/
└── _service.py           # invalidates the account's cached summary on invoice writes
```

Why this shape:

- **`core/cache.py`** centralizes the Redis client and a `get-or-compute` helper so the
  cache-aside pattern (with TTL, tenant-safe keys, and stampede protection) is applied
  consistently rather than hand-rolled per call site.
- **`dashboard/_service.py`** reads through the helper, building keys that always
  include the `account_id`.
- **`invoicing/_service.py`** owns invalidation: because writing an invoice changes the
  dashboard summary, the write path invalidates the affected account's cached summary.
  Keeping invalidation with the write that causes it is what stops it being forgotten.

## Implementation

**The cache-aside helper with stampede protection (`core/cache.py`).** One helper does
get-or-compute with a TTL, and single-flights concurrent misses on a hot key so only
one request recomputes.

```python
import json
from collections.abc import Awaitable, Callable
from redis.asyncio import Redis

redis: Redis = Redis.from_url(settings.REDIS_URL, decode_responses=True)


async def get_or_compute[T](
    key: str, ttl: int, compute: Callable[[], Awaitable[T]]
) -> T:
    cached = await redis.get(key)
    if cached is not None:
        return json.loads(cached)                 # HIT — fast; a (possibly stale) copy

    # MISS: single-flight so a hot key's expiry doesn't stampede the database.
    lock = redis.lock(f"lock:{key}", timeout=10, blocking_timeout=5)
    async with lock:
        cached = await redis.get(key)             # re-check: another request may have filled it
        if cached is not None:
            return json.loads(cached)
        value = await compute()                   # exactly ONE request computes
        await redis.set(key, json.dumps(value), ex=ttl)   # TTL bounds staleness + memory
        return value
```

**Reading with a tenant-scoped key (`dashboard/_service.py`).** The key includes the
`account_id`. This one detail is the difference between a fast dashboard and a
cross-tenant data leak.

```python
class DashboardService:
    def __init__(self, repo: DashboardRepository) -> None:
        self._repo = repo

    async def get_summary(self, account_id: int) -> DashboardSummary:
        # Key encodes the TENANT (and would encode any other input). Never omit it.
        key = f"dashboard:summary:{account_id}"
        data = await get_or_compute(
            key, ttl=60,                                   # 60s staleness is acceptable here
            compute=lambda: self._repo.compute_summary(account_id),
        )
        return DashboardSummary(**data)
```

**Invalidating on write (`invoicing/_service.py`).** Writing an invoice changes the
summary, so the write path invalidates the affected account's cached entry. The
invalidation lives with the write that causes it — the only reliable place for it.

```python
class InvoiceService:
    async def create_invoice(self, account_id: int, data: InvoiceCreate) -> Invoice:
        invoice = ...                     # build + persist (Stage 2/3)
        self._repo.add(invoice)
        # The dashboard summary now depends on data that changed → invalidate it.
        await redis.delete(f"dashboard:summary:{account_id}")
        return invoice
```

There is a subtlety even here: the invalidation should happen such that a reader after
the commit sees fresh data — invalidate after (or as part of) the committing write, not
before, or a concurrent read can re-cache the *old* value between your delete and your
commit. For most read-mostly caches a short TTL is the pragmatic backstop that bounds
any such race; for stricter needs, invalidate after commit (mirroring the
enqueue-after-commit rule of Chapter 06).

**What not to cache this way.** An account's exact outstanding balance used to *decide*
whether to allow an action must not be served from a 60-second cache — a stale balance
could permit something it shouldn't. Either don't cache it, or cache with immediate
invalidation and treat the database as authoritative for the decision. The skill is
recognizing that "expensive and hot" is necessary but not sufficient; "tolerant of
staleness" is the third, decisive condition.

The through-line: the read is the easy 2ms win; correctness comes from the tenant in
the key (no leak), the TTL plus write-invalidation (bounded staleness), the
single-flight lock (no stampede), and the discipline to leave must-be-fresh data
uncached. Every one of those is a thing the naive read-only version omits — and every
one is a real bug, from a wrong dashboard number to a cross-tenant breach.

## Engineering Decisions

Five decisions define a correct cache.

### What should be cached?

**Options:** (1) cache aggressively; (2) cache only data that is expensive, frequently
read, and staleness-tolerant; (3) don't cache.

**Trade-offs:** aggressive caching maximizes speed and multiplies invalidation surface,
memory use, and staleness bugs — including caching data that's cheap (no benefit) or
must-be-fresh (correctness risk). Selective caching targets the wins and keeps the
invalidation burden small. Not caching keeps everything simple and correct at the cost
of load and latency on expensive reads.

**Recommendation:** cache only where all three hold — expensive to produce, frequently
read, and tolerant of some staleness. Invoicely's dashboard summary qualifies; an exact
balance used for a decision does not (fails staleness); a rarely-read settings page does
not (fails frequency). Every cached value is invalidation work and a potential stale
bug, so cache deliberately, not by default.

### What is the invalidation strategy?

**Options:** (1) TTL only; (2) explicit invalidation on write; (3) both.

**Trade-offs:** TTL-only is simple and self-healing (stale data corrects itself when the
key expires) but accepts staleness up to the TTL and can't reflect a change sooner.
Explicit invalidation is precise (fresh immediately after a write) but fragile — you
must invalidate on *every* write path, and a missed one serves stale data indefinitely.
Both combines precise updates with a TTL backstop that bounds the damage of a missed
invalidation.

**Recommendation:** both, for most caches — explicit invalidation on writes for
freshness, plus a TTL as a safety net so a forgotten invalidation self-heals rather than
serving stale data forever. Use TTL-only when the write paths are too many to track
reliably and the staleness window is acceptable; use aggressive explicit invalidation
when even brief staleness matters. Never rely on explicit invalidation *alone* — you
will miss a path.

### How much staleness is acceptable — per data type?

**Options:** a single global TTL; or a per-data-type staleness budget.

**Trade-offs:** a global TTL is easy and wrong for a system with mixed data — it makes
some data needlessly stale and other data cached longer than safe. Per-type budgets fit
the freshness need of each kind of data, at the cost of deciding (and documenting) them.

**Recommendation:** set the TTL (and invalidation aggressiveness) per data type from an
explicit staleness budget: a dashboard summary tolerates ~60s; a public listing might
tolerate minutes; a balance used for authorization tolerates zero and shouldn't be
cached this way. Make the staleness a conscious, documented decision — it is the core
trade caching makes, and it differs per datum.

### How are cache keys designed?

**Options:** (1) key on the primary identifier only; (2) key on the complete set of
inputs, including tenant and all parameters.

**Trade-offs:** keying on a partial input is shorter and *wrong* — any input not in the
key means different requests collide on one entry, serving the wrong result (and, with a
missing tenant, another tenant's data). Keying on the full input set is correct at the
cost of longer, structured keys.

**Recommendation:** the key must encode every input that affects the result — the
tenant/account, the user if results are user-specific, and all query parameters (filters,
sort, pagination). In multi-tenant systems, forgetting the tenant is a cross-tenant leak
(Chapter 04's IDOR at the cache layer). Adopt a consistent key convention
(`resource:dimension:...`) and never key on a partial input.

### Do hot keys need stampede protection?

**Options:** (1) plain cache-aside; (2) add single-flight/stampede protection.

**Trade-offs:** plain cache-aside is simpler and, for a hot key, means every concurrent
request that misses (right after an expiry) recomputes simultaneously — a thundering herd
that can overwhelm the database exactly when the cache was supposed to protect it.
Stampede protection (a lock so one request recomputes while others wait, or probabilistic
early recomputation) prevents that, at the cost of a little complexity.

**Recommendation:** add stampede protection for genuinely hot keys (a shared dashboard, a
homepage listing) where a synchronized miss would hurt; plain cache-aside is fine for keys
that aren't hot enough for simultaneous misses to matter. Know which of your keys are hot —
those are the ones where the cache can flip from shield to amplifier.

## Trade-offs

Caching trades freshness, complexity, and memory for speed, and the trade must be made
consciously.

**Speed for staleness.** This is the fundamental trade: a cache is faster because it
serves a copy that may be out of date. Every cached value accepts some staleness window;
the engineering is choosing that window per data type, not eliminating it. Data that
genuinely cannot be stale (balances used for decisions, inventory at checkout) should not
be cached in a way that serves stale reads — the right answer is sometimes "don't cache
this."

**Speed for invalidation complexity.** The read-side win comes bundled with the
obligation to invalidate correctly on every write path — the hard, error-prone part. More
caching means more invalidation surface and more chances to serve stale data. A TTL
backstop reduces the blast radius of a missed invalidation but doesn't eliminate the
work; the complexity is real and grows with cache coverage.

**Speed for memory and a moving part.** A cache is more infrastructure (Redis to run,
monitor, size) and more memory, with an eviction policy to tune. It also adds a
dependency whose failure must degrade gracefully — a cache outage should fall back to the
database (slower), never fail the request. The performance win is real; so is the
operational surface.

**When not to cache.** For a low-traffic app, cheap queries, or data that must be fresh,
caching adds complexity and staleness risk for little benefit — premature optimization
(Stage 1, Chapters 04 and 07). Reach for caching when profiling shows an expensive, hot,
staleness-tolerant read is actually a bottleneck, not preemptively. Measure first; the
cache you don't need is pure downside.

## Common Mistakes

**Caching without invalidation.** Adding a read-side cache and never invalidating on
write, so changes don't appear (stale forever without a TTL). Fix: invalidate on every
write that affects the cached value, and add a TTL backstop for missed paths.

**Tenant-blind (or input-blind) keys.** A key missing the tenant or some input, so
requests collide and one gets another's data — a cross-tenant leak. Fix: encode every
input, including `account_id`, in the key.

**No TTL / no eviction.** Cache entries that never expire and a cache with no eviction
policy, growing until it exhausts memory. Fix: a TTL on every entry and an LRU (or
similar) eviction policy on the cache.

**Treating the cache as source of truth.** Storing data only in the cache, or trusting a
cached value for a correctness-critical decision. Fix: the database is authoritative; the
cache is a disposable copy you can flush without data loss.

**Ignoring stampedes on hot keys.** Plain cache-aside on a hot key, so an expiry sends a
thundering herd to the database. Fix: single-flight/locking or early/probabilistic
recomputation for hot keys.

**Caching the wrong things.** Caching cheap or rarely-read data (no benefit) or
must-be-fresh data (correctness risk). Fix: cache only expensive + hot + staleness-tolerant
data; measure before caching.

## AI Mistakes

Caching is the "hard problem" made concrete: an assistant adds the read that makes the
demo fast and omits the invalidation, the tenant-safe key, and the lifecycle that make it
correct — because none of those are exercised by loading the page once. Review cached code
for what happens on a write, for a second tenant, and over time, not for whether the read
is fast.

### Claude Code: caching without invalidation

Asked to speed up a read, Claude Code adds cache-aside — check cache, compute on miss,
store — and stops there, with no invalidation on the corresponding write, because the read
is what it was asked to optimize and the write path is elsewhere. The result serves stale
data after any change (indefinitely, if it also omitted a TTL).

**Detect:** a cache populated on read with no matching invalidation on the write paths
that affect it; a cached value that a known update operation doesn't clear; no TTL as a
backstop.

**Fix:** require invalidation with the cache:

> Adding a cache means owning its invalidation. Invalidate (or update) this cached value
> on every write path that affects it, and add a TTL as a backstop so a missed
> invalidation self-heals rather than serving stale data forever. Show me where each write
> invalidates it.

### GPT: tenant-blind cache keys

GPT-family models build cache keys from the resource ID or the query parameters and
routinely omit the tenant/account dimension, because the key "uniquely identifies the
thing" in a single-tenant mental model. In a multi-tenant system that collides tenants on
one entry — one account's cached data served to another, a breach through the cache.

**Detect:** a cache key that omits `account_id`/tenant (or user, for user-specific data);
a key two different tenants' requests would produce identically; keys built only from
resource IDs or params.

**Fix:** require complete, tenant-scoped keys:

> The cache key must include every input that affects the result — especially the
> `account_id` (and the user, if results are user-specific), plus all query parameters.
> Omitting the tenant serves one tenant's cached data to another. Use a consistent
> `resource:account_id:...` key convention.

### Cursor: no expiry, no eviction, cache as truth

Wiring a cache inline, Cursor tends to `set` values with no TTL and against a cache with
no eviction policy — unbounded growth — and sometimes writes logic that reads from the
cache as authoritative (with no correct fallback on miss), because the lifecycle and
source-of-truth framing aren't visible from the edit site.

**Detect:** `set` calls with no expiry; no `maxmemory`/eviction configured; code paths
that depend on the cache being present or treat a cached value as the truth rather than a
copy of the database.

**Fix:** require lifecycle and source-of-truth discipline:

> Every cache entry gets a TTL, and the cache must have an eviction policy (LRU) so it
> can't grow without bound. The database is the source of truth; the cache is a disposable
> copy — a cold or flushed cache must be correct (just slower), never a data-loss or wrong
> answer.

## Best Practices

**Cache only expensive, hot, staleness-tolerant data — after measuring.** All three
conditions must hold, and profiling should show the read is a real bottleneck. The cache
you don't need is pure downside (complexity, staleness, memory).

**Own invalidation, backed by a TTL.** Invalidate (or update) on every write that affects a
cached value, and set a TTL as a self-healing backstop for the path you'll inevitably miss.
Choose the TTL from an explicit, documented per-data staleness budget.

**Put every input in the key, especially the tenant.** Encode the account/user and all
parameters in a consistent key convention, so requests never collide and no tenant sees
another's data (Chapter 04, at the cache layer).

**Bound the cache and protect hot keys.** TTLs on every entry, an LRU eviction policy on the
cache, and single-flight/early-recompute stampede protection on genuinely hot keys so an
expiry can't flood the database.

**Keep the database authoritative and fail open.** The cache is a disposable copy — flushing
it loses only speed; a cache outage falls back to the database rather than failing the
request. Document the cache's staleness and invalidation model in `CLAUDE.md`; record
consequential caching decisions in an ADR ([`templates/adr.md`](../../templates/adr.md)).

## Anti-Patterns

**The Never-Invalidated Cache.** A read cache with no invalidation on writes — stale data
served until a TTL expires, or forever if there's none. The tell: a cache populated on read
that no write path ever clears.

**The Tenant-Blind Key.** A cache key missing the tenant (or another input), leaking one
tenant's data to another. The tell: a key built from a resource ID or params with no
`account_id`.

**The Immortal Cache.** Entries with no TTL and a cache with no eviction, growing until it
runs out of memory. The tell: `set` without an expiry, and no `maxmemory` policy.

**The Authoritative Cache.** Data stored only in the cache, or a cached value trusted for a
correctness-critical decision. The tell: a flush would lose data or produce wrong answers,
not just slow ones.

**The Stampede.** Plain cache-aside on a hot key, so an expiry sends a thundering herd to
the database. The tell: a popular shared key with no single-flight or staggered expiry, and
database load spikes on cache expiry.

## Decision Tree

"Should I cache this, and how do I keep it correct?"

```
Is it EXPENSIVE to produce, FREQUENTLY read, AND tolerant of some staleness?
   (measure first — is this read actually a bottleneck?)
│
├── Any "no" ──► Don't cache it.
│     · cheap to compute → no benefit
│     · rarely read → no benefit
│     · must be fresh (a balance used to decide) → correctness risk; leave uncached
│
└── All "yes" ──► Cache-aside it:
     ├─ KEY: include EVERY input — account_id (tenant!), user if relevant, all params.
     ├─ TTL: from an explicit per-data staleness budget (e.g. dashboard ~60s).
     ├─ INVALIDATE: on every write that affects it (with the TTL as a backstop).
     ├─ HOT key? ──► add stampede protection (single-flight / early recompute).
     └─ SOURCE OF TRUTH stays the DB; a flushed/cold cache must be correct, just slower.
```

## Checklist

### Implementation Checklist

- [ ] Only expensive + hot + staleness-tolerant data is cached, and profiling justified it.
- [ ] Every cache key encodes all inputs, including `account_id` (and user where relevant).
- [ ] Cached values are invalidated on every write that affects them, with a TTL backstop.
- [ ] Every entry has a TTL, chosen from an explicit per-data staleness budget.
- [ ] Hot keys have stampede protection (single-flight or staggered/early expiry).
- [ ] The database is authoritative; a cold or flushed cache is correct, just slower.

### Architecture Checklist

- [ ] The cache has an eviction policy (LRU) and bounded memory.
- [ ] A cache/Redis outage degrades to the database (fails open), never fails the request.
- [ ] Staleness budgets and invalidation responsibilities are documented per cached datum.
- [ ] No correctness-critical decision trusts a stale cached value.
- [ ] Caching decisions are recorded (ADR); the cache model is in `CLAUDE.md`.

### Code Review Checklist

- [ ] No cache added without corresponding invalidation on writes (watch AI diffs).
- [ ] No cache key omits the tenant or another input (no cross-tenant collision).
- [ ] No `set` without a TTL; the cache can't grow unbounded.
- [ ] No cached value treated as the source of truth for a critical decision.
- [ ] Hot keys are protected against stampede.

### Deployment Checklist

- [ ] Redis (or the cache) is configured with `maxmemory` and an eviction policy (see [`checklists/production-readiness.md`](../../checklists/production-readiness.md)).
- [ ] Cache hit rate, memory use, and eviction rate are monitored.
- [ ] A cache outage is tested to degrade gracefully to the database.
- [ ] Cache and database are not assumed consistent; staleness windows are understood by operators.

## Exercises

**1. Cache a hot read correctly.** Take Invoicely's dashboard summary (an expensive
aggregation) and add cache-aside: a tenant-scoped key, a TTL from a stated staleness
budget, invalidation on the invoice write paths that affect it, and single-flight stampede
protection. The artifact is the code plus a note on the staleness window you chose and why.

**2. Find the leak and the staleness.** Take a cache implementation that keys on a resource
ID without the tenant and never invalidates (write one, or have an assistant generate "cache
the dashboard query"). Demonstrate the cross-tenant leak and the stale-after-write bug, then
fix both. The artifact is the two demonstrated bugs and the fixes.

**3. Decide what not to cache.** For a set of Invoicely reads — dashboard summary, an
account's exact outstanding balance shown at checkout, a public pricing page, a rarely-viewed
audit log — decide which to cache and which not to, with the staleness budget (or the reason
to leave it uncached) for each. The artifact is the table; the point is that "expensive and
hot" isn't sufficient — staleness tolerance decides.

## Further Reading

- **Redis documentation — Key eviction and client-side caching** (redis.io/docs) — how
  `maxmemory` and eviction policies (LRU/LFU) work, and how to reason about TTLs and memory.
  Essential for the lifecycle half of this chapter.
- **AWS — Caching best practices and cache-aside / lazy loading vs write-through**
  (aws.amazon.com caching whitepapers) — a clear, vendor-neutral-in-substance treatment of
  the caching patterns and their trade-offs, including TTL strategy and cache sizing.
- **"A look at the cache stampede problem" / probabilistic early expiration** (search for the
  Vattani, Chierichetti & Lower paper "Optimal Probabilistic Cache Stampede Prevention," and
  practical write-ups) — the theory and practice behind protecting hot keys, beyond simple
  locking.
- **Designing Data-Intensive Applications** (Martin Kleppmann), the chapters on replication
  and consistency — the deeper framing for why a cache is an eventually-consistent copy and
  what staleness really means, connecting this chapter to system-wide consistency (Stage 11).

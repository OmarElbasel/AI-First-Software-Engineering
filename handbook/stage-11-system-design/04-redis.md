# Redis

## Introduction

Redis has been in Invoicely's stack since Stage 3 — but as an accessory. It cached dashboard
aggregates (Stage 3, Chapter 07), brokered Celery tasks (Chapter 06), and backed the rate
limiter (Stage 9). Then Chapters 02 and 03 of this stage quietly promoted it: the
refresh-token deny list moved in, the shared FX cache moved in, and every instance of a
scaled-out app tier now coordinates through it. Somewhere between "it's just the cache" and
today, Redis became load-bearing — a component whose failure logs every user out, stalls
every background job, and disables every rate limit simultaneously. This chapter is where it
gets engineered like one.

The core tension that organizes everything: Redis is asked to play two contradictory roles.
As a **cache**, its data is disposable — evict freely under memory pressure, lose everything
on restart, nobody is harmed beyond slower requests. As a **state and coordination store** —
deny lists, rate-limit counters, locks, queues — its data is *not* disposable: evicting a
deny-list key un-revokes a stolen token; losing the Celery queue loses jobs. One instance
cannot be configured correctly for both roles at once, because eviction policy, persistence,
and failure response all want opposite settings. Most production Redis incidents trace back
to this unmade decision.

The chapter covers Redis as a component: the single-threaded mental model that explains its
performance and its sharp edges, data structures as the API, memory and eviction as the
budget, persistence and replication as the durability spectrum, and the patterns this stage
needs from it — shared cache, rate limiting, distributed locks, pub/sub backplane — each
with its failure modes. What to cache and how to invalidate remain Stage 3, Chapter 07;
this is the layer beneath that strategy.

## Why It Matters

- **Chapter 03 made Redis the app tier's memory.** Everything evicted from instances landed
  here. A stateless app tier plus an unengineered Redis hasn't removed the single point of
  failure — it has relocated it to a process still running dev-grade defaults.
- **The defaults are wrong for production in both roles.** Out of the box: no memory limit
  (Redis grows until the kernel's OOM killer executes it — taking cache *and* queue *and*
  deny list together), `noeviction` policy (writes start failing when memory fills), and
  snapshot persistence tuned for neither durability nor speed. Every one of these is a
  deliberate decision Redis is waiting for you to make.
- **Single-threaded means one bad command punishes everyone.** A `KEYS *` over ten million
  keys, an `HGETALL` on a monster hash, a `SMEMBERS` on an unbounded set — each blocks the
  event loop, and for those milliseconds (or seconds) *every* instance's every request that
  touches Redis waits in line. The performance model is simple and unforgiving.
- **Coordination bugs are correctness bugs.** A lock that a second worker can acquire while
  the first still holds it doesn't slow anything down — it double-sends the payment
  reminders that Chapter 03 so carefully made singleton. Redis coordination patterns have
  well-known sharp edges, and AI assistants reproduce the naive versions fluently.
- **It fails as one thing.** Postgres degrading is slow queries; Redis dying with mixed
  roles is simultaneously: cold cache (database load spike — a stampede at the worst
  moment), dead queue (background work stops), open rate limits, and mass logout. The
  blast radius is the argument for role separation before the incident demonstrates it.

## Mental Model

**One thread, in-memory structures, a network away.** Redis is (for practical purposes) a
single-threaded event loop executing commands one at a time against in-memory data
structures. Three consequences fall out:

```
            every client, every instance, one queue
   app-1 ─┐
   app-2 ─┤   ┌──────────────────────────────────┐
   app-3 ─┼──►│ cmd cmd cmd cmd cmd cmd cmd cmd  │──► one thread
   worker ─┤   └──────────────────────────────────┘    executes
   worker ─┘        ▲
                    └── an O(N) command here (KEYS, HGETALL on a
                        huge hash, SMEMBERS unbounded) delays
                        EVERYTHING behind it, fleet-wide

   1. Throughput is astonishing (100k+ ops/s) BECAUSE nothing blocks
   2. Latency budget is per-command: keep every command O(1)/O(log N)
      or bounded-N in the request path; O(N)-over-everything commands
      belong to offline tooling (SCAN, in batches)
   3. "Redis is slow" almost always means "someone is running a slow
      command" — the slowlog knows who
```

**Data structures are the API.** Redis is not a key-value store with strings; it is a
server of data structures, and choosing the structure *is* the design act: strings (+
`INCR`, TTL) for cache entries and counters; hashes for objects read field-wise; sets for
membership; sorted sets for rankings and sliding windows; lists for simple queues; streams
for consumer-group messaging (Chapter 07's small-scale sibling). Per-key TTL is the feature
that makes Redis the natural home for *expiring* state — the deny list whose entries
outlive their tokens by exactly zero seconds.

**Memory is the budget; eviction is the policy when it runs out.** `maxmemory` caps the
spend. What happens at the cap is `maxmemory-policy`, and the right answer depends entirely
on the role: a cache wants `allkeys-lru` (silently drop the least-recently-used — that's
what caches *do*); a state store wants `noeviction` (refuse writes loudly — evicting a
deny-list entry or a queued job is data loss wearing a performance costume). One instance,
one policy: this is why mixed roles cannot be configured correctly.

**Durability is a spectrum you place each role on.** None (restart = empty — fine for the
cache role, catastrophic for state); RDB snapshots (periodic point-in-time — loses the last
N minutes); AOF `everysec` (append each write, fsync per second — loses ≤1s, the standard
choice for the state role). Replication adds availability, with a subtlety that matters
for coordination: **Redis replication is asynchronous** — a failover can lose writes the
primary acknowledged, which means even a replicated Redis is not a strongly consistent
store, which bounds what locks built on it may protect (below).

**The availability ladder** mirrors Chapter 01's: single instance (restart tolerance via
AOF; minutes of downtime accepted) → primary + replica + Sentinel (automatic failover in
seconds; async-replication caveat applies) → Redis Cluster (sharded memory + failover —
for when the *dataset* outgrows one machine, not just the availability requirement).
Managed offerings compress the whole ladder into a checkbox; the caveats survive the
checkbox.

A working definition:

> **Production Redis is role-separated Redis: a cache instance (evicting, unpersisted,
> loss-tolerant) and a state instance (noeviction, AOF, monitored like a database), each
> with a memory budget, every key carrying a TTL or a documented owner, every command in
> the request path O(1)-ish, and coordination patterns used within their real guarantees —
> which, on an asynchronously replicated store, are efficiency guarantees, not
> correctness proofs.**

## Production Example

Invoicely's Redis inventory, written down for the first time after Chapter 03's migration:

| Data | Structure | Role | Loss tolerance |
|---|---|---|---|
| Dashboard/cache entries (Stage 3 Ch 07) | strings, TTL 60s | cache | total — recompute |
| FX rates (Ch 03) | hash, refreshed by beat | cache-ish | tolerable — refresher repopulates in ≤15 min |
| Refresh-token deny list (Ch 03) | strings w/ TTL | **state** | none — loss un-revokes tokens |
| Rate-limit counters (Stage 9) | strings, INCR+TTL | **state** | brief — limits reopen until windows rebuild |
| Celery broker queues (Stage 3 Ch 06) | lists | **state** | none — queued jobs vanish |
| Draining locks / beat coordination | SET NX PX | **state** | none during hold |

All of it lives on one instance, config untouched since `apt install`. The incident that
forces the redesign arrives at month-end: cache traffic balloons (every tenant's dashboard,
plus 6,000 PDF jobs enqueuing), memory crosses the host's limit, and the OOM killer takes
the process. Eight minutes of: every request a cache miss (database CPU pinned — the Ch 01
bottleneck, back for revenge), no background jobs moving, logins accepting revoked tokens,
rate limits open. The postmortem's one-line root cause: *six kinds of data with three
different loss tolerances shared one process and one policy.* The fix is this chapter's
implementation: two Redis instances with role-appropriate configs, an inventory with an
owner for every key pattern, and memory budgets derived from the Chapter 01 load model.

## Folder Structure

```
infrastructure/
├── redis/
│   ├── redis-cache.conf        # the disposable role: maxmemory +
│   │                           #   allkeys-lru, persistence OFF —
│   │                           #   losing it costs latency, not data
│   ├── redis-state.conf        # the load-bearing role: noeviction,
│   │                           #   AOF everysec — configured and
│   │                           #   monitored like a small database
│   └── README.md               # the key inventory: every key pattern,
│                               #   its structure, TTL, owner, and loss
│                               #   tolerance — the file the incident
│                               #   review wished existed
├── compose/
│   └── docker-compose.prod.yml # two redis services; app gets TWO urls
app/
└── core/
    └── redis.py                # two clients: cache_redis / state_redis.
                                #   The type system now enforces the
                                #   role decision at every call site —
                                #   "which Redis?" is answered by import
```

Why two config files instead of flags: the configs *are* the design decision, reviewable
in a diff. Why the inventory README sits next to them: key patterns are schema — Redis
just doesn't force you to declare it, so the repo must.

## Implementation

The two roles, as configuration:

```conf
# redis-cache.conf — disposable by design
maxmemory 2gb
maxmemory-policy allkeys-lru
save ""                      # no RDB
appendonly no                # no AOF: restart = cold cache, by contract
```

```conf
# redis-state.conf — a small database
maxmemory 1gb
maxmemory-policy noeviction  # full = writes FAIL LOUDLY (alert fires);
                             # never silently drop a deny-list entry
appendonly yes
appendfsync everysec         # bounded loss: <=1s on power failure
save ""                      # AOF suffices; avoid fork spikes from RDB
```

Two clients, so every call site declares its role:

```python
# app/core/redis.py
from redis.asyncio import Redis, ConnectionPool

from app.core.config import settings

# Cache role: aggressive timeouts — a slow cache is a broken cache;
# callers treat failure as a miss (degrade, don't die).
cache_redis = Redis(
    connection_pool=ConnectionPool.from_url(
        settings.redis_cache_url, max_connections=50
    ),
    socket_timeout=0.1,
    socket_connect_timeout=0.1,
)

# State role: patient timeouts — callers CANNOT treat failure as a
# miss (a deny-list read error must fail closed, not fail open).
state_redis = Redis(
    connection_pool=ConnectionPool.from_url(
        settings.redis_state_url, max_connections=50
    ),
    socket_timeout=1.0,
    socket_connect_timeout=1.0,
)
```

The distributed lock — done with its real guarantees stated, because this is the pattern
assistants get subtly wrong:

```python
# app/core/locks.py
import uuid
from datetime import timedelta

from app.core.redis import state_redis

_RELEASE = """
if redis.call("get", KEYS[1]) == ARGV[1] then
    return redis.call("del", KEYS[1])
else
    return 0
end
"""

class RedisLock:
    """Best-effort mutual exclusion for EFFICIENCY, not correctness.

    Guarantees (single Redis, no failover mid-hold): one holder at a
    time, auto-release on crash via TTL, no cross-release (the token
    + Lua check-and-delete make release atomic and owner-only).

    NOT guaranteed: exclusion across a failover (async replication
    can lose the lock write), or if the holder outlives the TTL.
    Anything where two holders corrupt data needs the database's
    locks (SELECT FOR UPDATE, Stage 6 Ch 04) or an idempotent design
    (Stage 3 Ch 06) — use this to avoid duplicate WORK, never as the
    only guard on money.
    """

    def __init__(self, name: str, ttl: timedelta) -> None:
        self._key = f"lock:{name}"
        self._token = uuid.uuid4().hex
        self._ttl = ttl

    async def acquire(self) -> bool:
        return bool(
            await state_redis.set(
                self._key, self._token, nx=True, px=int(self._ttl.total_seconds() * 1000)
            )
        )

    async def release(self) -> None:
        await state_redis.eval(_RELEASE, 1, self._key, self._token)
```

Cache invalidation at scale — the `SCAN` discipline (the request path never scans;
pattern invalidation happens in bounded batches, off the hot path):

```python
# app/core/cache.py (excerpt)
async def invalidate_tenant(tenant_id: str) -> None:
    """Batch-delete a tenant's cache keys. SCAN is incremental and
    non-blocking; KEYS would freeze every client fleet-wide. Called
    from a worker task, never inline in a request."""
    async for key in cache_redis.scan_iter(f"cache:{tenant_id}:*", count=500):
        await cache_redis.unlink(key)   # unlink frees memory async
```

And the pub/sub backplane that Chapter 03 promised for anything push-shaped — with its
contract stated: pub/sub is fire-and-forget (a disconnected subscriber misses messages
permanently), which is exactly right for "invalidate your local copy" signals and exactly
wrong for anything that must be delivered (that's a queue, Chapter 05, or a stream,
Chapter 07).

## Engineering Decisions

### One Redis or two?

Two, as soon as both roles exist — which for most systems is the day the rate limiter or
the task queue arrives. The forcing argument is that the roles need opposite settings for
eviction (`allkeys-lru` vs `noeviction`), persistence (off vs AOF), timeout/fallback
semantics (fail-as-miss vs fail-closed), and *alerting* (cache full = normal;
state full = incident). Two containers on the same host is a fine start — the separation
that matters is configuration and blast radius, not hardware. What does *not* work as a
substitute: Redis's numbered databases (`SELECT 0..15`) — they share the memory limit,
the eviction policy, the persistence config, and the single thread, which is to say they
share everything the separation exists to separate.

### What belongs in Redis at all?

The test is loss-shaped: Redis holds data that is **expiring** (deny lists, sessions,
windows — TTL is the point), **reconstructible** (caches — the database holds truth), or
**coordination-transient** (locks, queues in flight). The only copy of a business fact —
an invoice, a payment state, an audit event — belongs in PostgreSQL, full stop; Redis's
durability spectrum tops out at "loses at most a second, usually," and its whole design
(memory-bounded, eviction-capable) is hostile to unbounded authoritative data. When
tempted to make Redis primary for speed, re-read Stage 6: it's usually a missing index
wearing an architecture costume.

### Which persistence for the state instance?

AOF `everysec`: bounded, understood loss (≤1s) at negligible steady-state cost. RDB alone
is for the cache role only if warm restarts matter (usually they don't — `save ""`).
The combination (AOF + periodic RDB for faster restarts) becomes worth it when the AOF
grows large enough that replay-on-boot violates the recovery-time budget. Whatever the
choice: *test the restart* — persistence configuration that has never restored is a
backup that has never been tried (Stage 7 Ch 06's rule, verbatim).

### When does the availability ladder climb?

Single AOF instance + monitoring + a rebuild runbook is the right rung while "minutes of
Redis-state downtime" is survivable — Invoicely's is: jobs pause (queue is empty on
recovery — see the queue-durability note in Chapter 05), logins fall back to re-auth,
limits rebuild. Sentinel (primary + replica + 3 sentinels) buys seconds-scale failover
and costs three more processes and the async-loss caveat during failover — climb when the
SLO or the on-call load says so. Cluster is a different question: it shards *memory*, and
its trigger is dataset size, not uptime. Managed Redis rents the whole ladder; the main
things it doesn't rent are the role separation and the key discipline — those stay yours.

### Failure semantics per role — fail open or fail closed?

Decide per consumer, in code, before the outage runs the experiment. Cache down → fail
open (treat as miss; the request slows but succeeds — with the stampede protection from
Stage 3 Ch 07, because "everyone misses at once" is the load spike that killed the
original instance). Rate limiter down → a judgment call: fail open (availability over
enforcement) for product endpoints, fail *closed* for auth-critical ones (Stage 9's
reasoning). Deny list down → fail closed, always: accepting a possibly-revoked token to
keep latency flat is a security incident with good uptime. These three answers are
different, which is the point — "what do we do when Redis is down" is not one question.

## Trade-offs

| Choice | You gain | You pay |
|---|---|---|
| Two role-separated instances | Correct config per role; halved blast radius; honest alerts | Two processes to run; two URLs; the discipline of choosing per call site |
| One instance, mixed roles | One thing to operate | Some data is always under the wrong policy; total blast radius; the month-end incident |
| AOF everysec (state) | ≤1s loss bound at low cost | Larger disk, slower restarts as AOF grows |
| No persistence (cache) | Max speed, no fork/IO spikes | Cold cache on restart — pair with stampede protection |
| Redis locks | Cheap, fast, TTL auto-release | Efficiency-grade only; failover can double-grant; TTL vs long work races |
| Database locks (SELECT FOR UPDATE) | Transactional, correct under failover | Holds a connection; couples lock lifetime to the transaction |
| Sentinel failover | Seconds-scale recovery, no human | 3+ extra processes; async replication can drop acknowledged writes at flip |
| Single instance + runbook | Minimal ops surface | Minutes-scale outages; a human in the loop |
| Managed Redis | Ladder rented; patching gone | Cost; per-command latency often higher; role/key discipline still on you |
| Pub/sub backplane | Simplest push fabric | Fire-and-forget: disconnection = permanent loss — signals only |

## Common Mistakes

- **No `maxmemory`.** Redis grows until the OOM killer chooses violence, taking every
  role at once — the failure that motivated this chapter. Set the budget; alert at 80%
  like any other resource from Chapter 01.
- **`KEYS` in production code.** O(N) over the whole keyspace on the one thread everyone
  shares. It appears innocent in dev (N=200) and freezes the fleet in prod (N=20M).
  `SCAN` in batches, from workers, always.
- **Keys without TTLs in the cache role.** Every TTL-less cache key is a small memory
  leak with a name; eventually `allkeys-lru` starts evicting things you cared about to
  protect things nobody will read again. TTL on every cache write, no exceptions — the
  inventory README documents the few state keys allowed to live forever.
- **Big keys and hot keys.** The 40MB hash that makes every `HGETALL` a fleet-wide pause;
  the one `cache:global:settings` key that every request on every instance hits, turning
  a "distributed" cache into a single hot spot with a network attached. Bound value
  sizes; shard or locally-cache (with the Ch 03 staleness bound) the genuinely hot.
- **Trusting replication like a transaction log.** Writing to the primary, failing over,
  and discovering the last second of deny-list writes never reached the replica. Design
  for it: state writes that cannot be lost even for a second belong in PostgreSQL, with
  Redis as a fast projection of them.
- **The exposed instance.** Redis binds, someone maps the port for "debugging," and now
  an unauthenticated, RCE-adjacent service is on the internet (Stage 9's perimeter
  rules apply to infrastructure too). Private network only, `requirepass`/ACLs anyway,
  TLS when it crosses hosts you don't own.
- **Connection churn.** Creating a client per request instead of sharing the pool —
  latency spent on handshakes and, under load, thousands of connections against
  `maxclients`. One pool per process per role (the Ch 03 multiplication table has a
  Redis row too).

## AI Mistakes

### Claude Code: the only copy lives in Redis

Once a session establishes Redis as "where fast state goes," Claude Code generalizes: asked
to store draft invoices, user preferences, or webhook delivery attempts, it reaches for the
store it was just using — `state_redis.set(f"draft:{id}", payload.json())` — and the data's
*only* home is now a memory-bounded, eviction-capable process with second-grade durability.
It works flawlessly in every demo. It fails at the first eviction pressure, failover, or
restart — as vanished business data users were promised was saved, with no error at write
time and nothing to restore from.

**Detect:** Redis writes with no corresponding PostgreSQL row; business nouns (draft,
preference, attempt, order) in key names; data in the key inventory whose "loss tolerance"
column nobody can fill in with a straight face. **Fix:** enforce the loss-shaped test in
review — expiring, reconstructible, or coordination-transient, and anything else shows its
Postgres home first; Redis may then cache it.

### GPT: the lock that unlocks someone else's work

Ask GPT for a distributed lock and the modal answer has one or more of the classic flaws:
`SET key 1 NX` with no TTL (a crashed holder deadlocks the system forever), a plain `DEL`
release (worker A stalls past its TTL, worker B acquires, A wakes and deletes *B's* lock —
now C acquires while B still runs: two holders, which for Chapter 03's beat coordination
means duplicate reminder sends), and — when pressed about safety — a recommendation of
Redlock delivered as a correctness proof, without the Kleppmann/antirez controversy or the
fencing-token caveat that actually settles what such locks may guard.

**Detect:** lock code without a per-holder token; release via `DEL` instead of an atomic
check-and-delete; any claim that a Redis lock makes an operation "safe" without stating
the failover caveat. **Fix:** require the pattern from this chapter's implementation
(token + Lua release + TTL sized to the work + the docstring stating the guarantee class),
and require every lock's PR to answer one question: *what happens if two holders run
anyway?* If the answer is "data corruption," the lock is the wrong tool — idempotency or
database locks are.

### Cursor: `KEYS` in the request path

Completing a cache-invalidation function, Cursor autocompletes the idiom that dominates
its training data: `for key in redis.keys(f"cache:{tenant_id}:*"): redis.delete(key)` —
inline, in the request handler, right after the update that triggered it. In dev it is
instant and correct. In production it is a full-keyspace O(N) scan on the shared single
thread, executed on every invoice update, at month-end frequency — each call a fleet-wide
pause, arriving precisely with peak load. The code reviews clean because the bug is not in
the logic; it is in the complexity class.

**Detect:** `.keys(` anywhere outside offline tooling; pattern-deletion inline in request
handlers; invalidation latency that grows with total keyspace size. **Fix:** ban `KEYS`
mechanically (a lint rule or a code-review grep — it has no production call site), route
pattern invalidation through the worker-side `SCAN`/`UNLINK` batch helper, and prefer
key designs that make invalidation O(1) — versioned key prefixes bumped on write — over
pattern deletion entirely (Stage 3 Ch 07's key-design discipline).

## Best Practices

- **Maintain the key inventory like schema.** Every key pattern: structure, TTL, owner,
  role, loss tolerance. It is the document that makes role separation enforceable, the
  incident review's first stop, and the reviewer's reference for "which Redis does this
  belong in?"
- **Budget memory from the load model.** Cache-role sizing comes from working-set math
  (entries × size × tenants, Ch 01 style), state-role from bounded growth (deny list ≤
  live tokens; queues ≤ backlog policy). Alert at 80%; treat state-role growth alerts as
  leaks to find, not limits to raise.
- **Keep the request path O(1).** Strings, hash-field reads, bounded sets, `INCR`,
  `ZADD`/`ZRANGEBYSCORE` on trimmed windows. Anything O(N-unbounded) — scans, full-set
  reads, pattern ops — runs in workers, batched, off-peak when possible.
- **Watch four numbers.** `used_memory` vs budget, hit rate (cache role), `evicted_keys`
  (must be ~0 on the state role — any eviction there is data loss), and the slowlog
  (the single-thread's confession booth). All four belong on the Stage 7 dashboards.
- **Drill both failures.** Kill the cache instance under load: requests must slow, not
  fail, and the stampede protection must hold. Kill the state instance: the app must
  fail *the way each consumer decided* (miss/open/closed), alerts must fire, and the
  runbook must bring it back — with AOF actually restoring. Untested degradation plans
  are Chapter 02's health-check theater, relocated.
- **Name keys like an API.** `role:domain:entity:id` (`cache:dash:tenant:42`,
  `auth:denied:{jti}`), versioned when shape changes (`cache:v2:...` — old versions age
  out by TTL). Grep-able, shard-able, inventory-able.
- **Pipeline the chatty paths.** N sequential round trips for one request is N× the
  latency for no reason; `pipeline()` batches them into one. The profiler (Stage 6's
  habit, pointed at Redis) finds the chatty paths.

## Anti-Patterns

- **Redis as the primary database.** The general case of Claude Code's mistake above —
  chosen deliberately for speed. Everything Stage 6 taught (constraints, transactions,
  queries, backups) is abandoned for a store designed to forget things. If reads are the
  problem, cache reads; the truth stays where truth-keeping machinery exists.
- **The numbered-database "separation."** `SELECT 1` for cache, `SELECT 2` for queues —
  shared memory limit, shared eviction policy, shared persistence, shared thread. It
  separates key collisions and nothing else; the incident arrives on schedule.
- **Pub/sub as a delivery mechanism.** Publishing order events to pub/sub and calling it
  the integration bus: any subscriber restart, network blip, or deploy silently drops
  messages forever. Signals and invalidations only; delivery needs a queue (Ch 05) or a
  stream (Ch 07).
- **Hand-rolled reliable queues on lists.** `LPUSH`/`BRPOP` with bespoke retry/ack logic,
  reinventing what Celery (Stage 3 Ch 06) and real brokers (Ch 05) already solved —
  minus visibility timeouts, dead-letters, and monitoring. The primitive existing does
  not make the system trivial.
- **Cache warm-up as a startup side effect.** Every instance pre-filling the shared cache
  on boot (Ch 03's startup-side-effect anti-pattern, Redis edition): N instances × every
  deploy = a write storm that evicts the actually-hot working set.
- **The debugging FLUSHALL.** One command, no confirmation, and both roles' data are
  gone — on the shared prod instance someone port-forwarded to "just check something."
  `rename-command FLUSHALL ""` on the state instance; prod access through the runbook,
  not ad hoc clients.

## Decision Tree

```
Data (or coordination) is heading to Redis — route it:
│
├─ Is it the ONLY copy of a business fact (survives restarts,
│  no TTL makes sense, users were promised it's saved)?
│   └─ YES → PostgreSQL. Redis may cache a projection of it.
├─ Is it expiring, reconstructible, or coordination-transient?
│   ├─ Reconstructible (cache, precomputed views, FX rates)
│   │   → cache instance: allkeys-lru, no persistence, TTL on
│   │     every write, fail-open (miss) + stampede protection
│   ├─ Expiring state (deny list, sessions, rate windows)
│   │   → state instance: noeviction + AOF; decide fail-open vs
│   │     fail-closed PER CONSUMER (deny list: closed. limits:
│   │     depends. sessions: re-auth.)
│   └─ Coordination:
│       ├─ Mutual exclusion, corruption if two holders?
│       │   ├─ YES → DB locks (St.6 Ch 04) or idempotent design
│       │   └─ NO (duplicate-work efficiency) → Redis lock:
│       │       token + Lua release + TTL > work time
│       ├─ Deliver-me-later work → Celery/queues (Ch 05),
│       │   which USE state-Redis but add ack semantics
│       ├─ Fan-out signal, loss OK → pub/sub
│       └─ Fan-out facts, loss NOT OK → streams (Ch 07)
├─ Structure: read whole? string/JSON. Field-wise? hash.
│  Membership? set. Ranked/windowed? sorted set. Ordered
│  consumer-group delivery? stream.
└─ Availability rung: minutes of downtime OK → single + AOF +
   runbook. Seconds required → Sentinel (accept async-loss at
   failover). Dataset > one machine's RAM → Cluster. No ops
   appetite → managed (discipline still yours).
```

## Checklist

### Implementation Checklist

- [ ] Two instances (or managed equivalents) with role-appropriate configs: cache =
      `allkeys-lru` + no persistence; state = `noeviction` + AOF `everysec`.
- [ ] `maxmemory` set on both, derived from written budgets; alerts at 80%.
- [ ] Two clients in code with role-appropriate timeouts and failure semantics; every
      call site imports the role it means.
- [ ] Every cache write carries a TTL; state keys without TTLs are listed in the
      inventory with an owner and a growth bound.
- [ ] Locks use token + atomic Lua release + TTL sized above the work, and their
      docstrings state the guarantee class; nothing corruption-critical is guarded by a
      Redis lock alone.
- [ ] No `KEYS` outside offline tooling (lint/grep enforced); pattern invalidation goes
      through worker-side SCAN batches or versioned prefixes.
- [ ] Auth enabled, private network only, dangerous commands renamed on the state
      instance.

### Architecture Checklist

- [ ] The key inventory exists, is current, and every pattern has role, TTL, owner, and
      loss tolerance filled in.
- [ ] Fail-open/fail-closed decided per consumer (cache, limits, deny list, broker) and
      implemented, not assumed.
- [ ] Availability rung chosen against the SLO with the async-replication caveat
      acknowledged in writing where coordination depends on it.
- [ ] Memory budgets connect to the Ch 01 load model (tenant growth → key growth →
      budget horizon).
- [ ] Restart/recovery runbook exists and the AOF restore has actually been performed.

### Code Review Checklist

- [ ] New Redis data passes the loss-shaped test — or arrives with its PostgreSQL home
      in the same PR.
- [ ] The right client (role) is used; a state write through the cache client is a bug
      even when it works.
- [ ] Command complexity in the request path is O(1)/bounded; new sorted sets and lists
      have trimming; new hashes have a size story.
- [ ] Key names follow the convention and got an inventory row.
- [ ] Every new lock answers "what if two holders run anyway?" in the PR description.

### Deployment Checklist

- [ ] Both failure drills executed under load: cache-kill (slow, not down; stampede
      protection held) and state-kill (per-consumer semantics held; alerts fired;
      restore succeeded within the budgeted time).
- [ ] Dashboards show memory-vs-budget, hit rate, `evicted_keys` (≈0 on state), and
      slowlog; state-instance eviction and memory-80% alert someone.
- [ ] Redis versions and configs are pinned and deployed through the pipeline — no live
      `CONFIG SET` drift (the pet-server rule covers datastores too).
- [ ] Connection counts per role appear in the Ch 03 shared-resource budget.
- [ ] The month-end load test (Ch 01) now includes Redis memory and slowlog observation.

## Exercises

1. **Split the roles and prove the difference.** Stand up the two-instance topology from
   this chapter in docker-compose. Fill both to their memory limits with a write storm.
   Verify: the cache instance evicts silently and keeps serving; the state instance
   refuses writes and your alert fires. Write down what each consumer of the state
   instance did when writes failed — that list is your fail-open/fail-closed homework.
2. **Break the naive lock, then fix it.** Implement the GPT-style lock (`SET NX`, plain
   `DEL` release) and a worker whose job takes longer than the TTL. Run three workers
   and demonstrate two holders running concurrently — log the overlap. Replace it with
   the token + Lua version and show the overlap disappears (and show what *still*
   happens when work exceeds TTL — then fix that by making the job idempotent).
3. **Hunt the slow command.** Seed a few million keys, put a `KEYS cache:*` and an
   `HGETALL` on a deliberately huge hash into an endpoint, and load-test. Use the
   slowlog and latency monitoring to find both from the metrics alone (pretend you
   didn't write them). Fix with SCAN-batching and hash decomposition; measure the p99
   before and after fleet-wide.
4. **Run the two kill drills.** Under mixed load: kill the cache instance (measure the
   database load spike; verify stampede protection bounds it; verify zero 5xx), then
   kill the state instance (verify the deny-list consumer fails closed, the limiter
   does what you decided, Celery producers behave; restore from AOF and verify the deny
   list survived). Time both recoveries against the runbook.
5. **Write the key inventory.** For your own system (or the Invoicely table in this
   chapter), produce the full inventory: pattern, structure, role, TTL, owner, loss
   tolerance, growth bound. Every row you cannot fill in is a finding. Present the two
   worst findings with their remediation cost now vs. during an incident — Chapter 03's
   audit argument, applied to the datastore.

## Further Reading

- Redis documentation — "Memory optimization," "Eviction policies," "Persistence"
  (RDB vs AOF trade-offs, straight from the source), and "Redis latency problems
  troubleshooting" — the operational core of this chapter.
- Martin Kleppmann — "How to do distributed locking" — the canonical analysis of
  Redlock, fencing tokens, and what lock guarantees actually mean; read together with
  antirez's response "Is Redlock safe?" and form your own judgment (the handbook's
  position: efficiency locks in Redis, correctness in the database).
- Redis documentation — "Redis Cluster specification" and "High availability with
  Redis Sentinel" — the two upper rungs of the ladder, including the failover
  semantics this chapter warns about.
- Salvatore Sanfilippo — "Redis persistence demystified" — the classic deep dive on
  what fsync policies really promise.
- *Designing Data-Intensive Applications* — Chapter 5 (replication lag and its
  anomalies) — why asynchronous replication bounds what any Redis pattern can
  guarantee.
- Stage 3, Chapter 07 ([Caching](../stage-03-backend-engineering/07-caching.md)) — the
  strategy layer (what to cache, invalidation, stampedes) that this chapter's
  infrastructure serves.

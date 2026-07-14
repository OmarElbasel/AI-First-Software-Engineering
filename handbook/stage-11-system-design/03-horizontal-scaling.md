# Horizontal Scaling

## Introduction

Chapter 02 made it possible for requests to reach N instances. This chapter is about making
N instances *correct* — and that is not an infrastructure problem. Horizontal scaling is a
property of the application: an app tier scales out cleanly when any instance can serve any
request at any moment, which is true exactly when instances hold nothing that distinguishes
them. Every piece of per-instance state — a session dict, a cached exchange rate, a file in
`/tmp`, a scheduler thread — is a small bet that there will only ever be one instance, and
the second instance calls in all of those bets at once.

The hard step is one to two. Going from two instances to twenty is provisioning; going from
one to two is a phase transition, because it converts every hidden single-instance
assumption from a working design into an intermittent bug: the user logged out on refresh
(session on the other instance), the reminder email sent twice (both instances run the
scheduler), the export that 404s (written to one instance's disk, downloaded from the
other's). None of these fail loudly, and all of them fail *sometimes* — the worst kind of
bug, delivered in a batch.

This chapter is the audit and the refactor: a taxonomy of where state hides in application
tiers, the standard destination for each kind, the shared-resource arithmetic (database
connections multiply with instances; someone has to do that multiplication before the
database does), and the operational contract — graceful shutdown, identical instances,
readiness gates — that makes instances genuinely disposable. Where the state lands in Redis,
the operational side of Redis itself is Chapter 04's subject.

## Why It Matters

- **It is the payoff of the stage so far.** Chapter 01 found the bottleneck and Chapter 02
  built the front door; a stateless app tier is what makes "add another instance" a
  ten-minute act instead of a project. Near-linear capacity growth, N+1 redundancy, and
  invisible deploys all fall out of interchangeability.
- **Statelessness is a one-way-door decision.** Chapter 01 filed it under "cheap now,
  prohibitive later," and this chapter is why: externalizing sessions in week two is an
  afternoon; excavating five kinds of instance state from a mature codebase under a
  traffic deadline is the miserable version of the same work, done at the worst time.
- **The failure modes are silent and probabilistic.** Per-instance state at N=2 doesn't
  error — it flickers. Half of logins persist, some exports vanish, duplicate emails go
  out on a schedule. These bugs read as "flaky" for weeks because they *are* load-balancer
  routing luck, and nothing in a single-instance dev environment ever reproduces them.
- **Shared resources fail by multiplication.** Ten instances × pool size 20 = 200
  database connections before the workers claim theirs — against PostgreSQL's default 100.
  The app tier scaled; the database's connection table did not. Every "scale out" plan
  that skips this arithmetic discovers it as an outage.
- **Duplicated singletons do real-world damage.** A scheduler running in every instance
  doesn't degrade performance — it sends every customer three payment reminders. State
  bugs embarrass the system; singleton bugs embarrass the company.

## Mental Model

The organizing image: instances are cattle, not pets. No names, no identities, no special
members; any can be killed, any can be cloned, and nothing of value lives on one.

**Where state hides.** The audit taxonomy — each row is a bet on N=1, with its standard
destination when the bet is called:

```
PER-INSTANCE STATE          BREAKS AT N=2 AS...         MOVES TO...
─────────────────────────────────────────────────────────────────────
sessions / auth state       random logouts              Redis (Ch 04) or
(in-process dict)                                       stateless JWT (St.9)
in-process caches of        users see different         Redis, or accept +
mutable shared data         values per refresh          short TTL (see below)
local filesystem writes     downloads 404, uploads      object storage
(uploads, exports, tmp      vanish, "works on           (Stage 3 Ch 09);
 that outlives a request)   instance 1"                 tmp = same request only
module-level counters,      wrong numbers (each         metrics scraped per
rate limiters, quotas       instance counts alone)      instance (St.7) /
                                                        Redis for limits (St.9)
scheduler threads inside    every instance fires        ONE scheduler process,
the app (cron, @repeat)     the job: duplicate          or a distributed lock
                            emails, double billing      (Ch 04)
in-memory locks             mutual exclusion that       DB row locks (St.6) or
(threading.Lock on          excludes nothing across     Redis locks (Ch 04)
 shared resources)          instances
websocket/SSE rooms held    messages reach only the     pub/sub backplane
in process memory           clients on THIS instance    (Redis pub/sub, Ch 04)
```

**The interchangeability test.** One question finds all of it: *if this instance were
destroyed right now and a fresh clone started, what would be lost, and who would notice?*
The correct answer is "in-flight requests, and nobody else." Anything else on the list
above is the refactor backlog.

**What may stay per-instance.** Statelessness is about *authoritative* state, not all
state. An instance may keep: derived, re-creatable data (a warmed template cache, compiled
regexes); immutable reference data cached with a TTL you can tolerate staleness on
(country lists, plan definitions); connection pools (they *are* per-instance by nature);
and true request-scoped temp files deleted before the response returns. The test is not
"is there data in memory" but "does correctness anywhere depend on *this* copy."

**Shared resources: the multiplication table.** Scaling the app tier multiplies demand on
everything beneath it:

```
   instances ×  per-instance demand   =  total     vs  shared limit
   ─────────────────────────────────────────────────────────────────
   10        ×  pool_size 20 (DB)     =  200           max_connections 100  ✗
   10        ×  pool_size 5           =   50           + workers 8×2 = 66   ✓
   10        ×  50 Redis conns        =  500           maxclients 10000     ✓
   10        ×  scrape/log volume     =  10× logs      disk/ingest budget ?
```

The pattern generalizes: every scale-out decision needs one pass over the resources all
instances share — database connections (the classic; the fix is small pools plus a pooler
like PgBouncer once instance count grows), Redis connections, outbound API rate limits
(ten instances retrying against a payment API hit its limit ten times faster), and log
volume. The app tier is elastic; the things it points at are not.

**The operational contract.** Interchangeability is also behavioral. Each instance must:
start from the image plus environment only (12-factor config — nothing hand-edited on a
host); signal readiness before receiving traffic (Chapter 02's health gate); and shut down
gracefully — on SIGTERM, stop accepting, finish in-flight work within the drain window,
exit. An instance that loses requests on shutdown makes every deploy and every scale-down
event a small outage.

A working definition:

> **An app tier scales horizontally when instances are interchangeable: any instance can
> serve any request, because authoritative state lives in shared systems (database, Redis,
> object storage), singleton work is explicitly assigned rather than ambiently assumed,
> and each instance honors the contract — born from image + env, ready before traffic,
> graceful on termination. The unit of design is no longer "the server" but "N disposable
> copies plus the shared state they coordinate through."**

## Production Example

Invoicely, the week after Chapter 02: the balancer is live, the second app instance is
about to be. The team runs the interchangeability audit — grep for module-level mutable
globals, filesystem writes, `threading`, and scheduling decorators, then trace each hit —
and finds five bets on N=1:

1. **Refresh-token deny list** in a module-level `set` (Stage 9's logout implementation).
   At N=2: logout revokes the token on one instance; the other keeps accepting it — a
   security bug, not an inconvenience.
2. **A `@repeat_every(seconds=86400)` payment-reminder loop** inside the FastAPI process
   (added in a hurry before Stage 3's Celery beat existed for it). At N=2: every customer
   gets two reminders. At N=6: six.
3. **CSV exports written to `/app/exports/`** and served by a download endpoint. At N=2:
   the download 404s whenever the balancer routes it to the instance that didn't write
   the file.
4. **An in-process dict caching FX rates** for multi-currency invoices, refreshed hourly
   per instance. At N=2: two instances can disagree for up to an hour; an invoice total
   can change between two refreshes of the same page.
5. **The connection math nobody had done:** pool size 20 per instance was fine at N=1.
   The target topology — 4 app instances + 6 workers — demands 4×20 + 6×10 = 140
   connections against `max_connections = 100`.

The fixes are this chapter's Implementation: deny list and FX cache to Redis, the reminder
loop to Celery beat (exactly one of which runs), exports to the Stage 3 object-storage
bucket with presigned URLs, pools resized with headroom math and PgBouncer staged for the
next growth step. Two weeks of deliberate work — at week 90 of the codebase. The same
audit at week 4 would have been two days; that ratio is this chapter's argument.

## Folder Structure

Horizontal scaling changes little structure — it *removes* local-state code and adjusts
configuration. The diff-shaped view:

```
app/
├── core/
│   ├── config.py           # already env-driven (12-factor, Stage 3);
│   │                       #   gains POOL_SIZE, WEB_CONCURRENCY —
│   │                       #   sizing is config, not code
│   ├── redis.py            # NEW: one shared async client/pool —
│   │                       #   every externalized state consumer
│   │                       #   imports from here, not ad hoc clients
│   └── lifecycle.py        # NEW: startup readiness + SIGTERM drain —
│                           #   the operational contract in one place
├── auth/
│   └── token_store.py      # deny list: module-level set → Redis keys
│                           #   with TTL = token lifetime
├── invoicing/
│   └── fx.py               # FX cache: process dict → Redis hash,
│                           #   one refresher (beat), all readers share
├── exports/
│   └── service.py          # writes to object storage, returns
│                           #   presigned URL (Stage 3 Ch 09 pattern) —
│                           #   the download endpoint dies entirely
└── workers/
    └── beat_schedule.py    # ALL periodic work declared here — one
                            #   auditable home for "runs on a schedule",
                            #   run by exactly one beat process
infrastructure/
└── compose/
    └── docker-compose.prod.yml   # app: replicas + no host port;
                                  # beat: replicas: 1, documented WHY;
                                  # pgbouncer: staged for next step
```

The two ideas worth naming: `beat_schedule.py` exists so that "what runs on a schedule?"
has one answer that code review can guard — scheduled work scattered across decorators in
feature modules is how singleton duplication sneaks back in. And `lifecycle.py` exists
because readiness and drain behavior are system contracts (Chapter 02 depends on them),
not incidental server settings.

## Implementation

The deny list — the security-critical one — moves from process memory to Redis:

```python
# app/auth/token_store.py
from datetime import timedelta

from app.core.redis import redis_client

_PREFIX = "auth:denied:"

async def revoke_refresh_token(jti: str, remaining_ttl: timedelta) -> None:
    """Deny across ALL instances. TTL = the token's own remaining
    lifetime: the key expires exactly when the token would anyway,
    so the deny list never grows beyond live-token count."""
    await redis_client.set(f"{_PREFIX}{jti}", "1", ex=remaining_ttl)

async def is_revoked(jti: str) -> bool:
    return await redis_client.exists(f"{_PREFIX}{jti}") == 1
```

The reminder loop leaves the web process entirely — periodic work belongs to the worker
tier, declared in the one schedule file and executed by a *single* beat process:

```python
# app/workers/beat_schedule.py
from celery.schedules import crontab

from app.workers.celery_app import celery_app

celery_app.conf.beat_schedule = {
    "payment-reminders": {
        "task": "invoicing.send_payment_reminders",   # Stage 3 Ch 06 task:
        "schedule": crontab(hour=9, minute=0),         # already idempotent
    },
    "refresh-fx-rates": {
        "task": "invoicing.refresh_fx_rates",          # ONE writer for the
        "schedule": crontab(minute=15),                # shared FX cache
    },
}
```

```yaml
# docker-compose.prod.yml (excerpt)
services:
  app:
    image: invoicely-api:${GIT_SHA}
    deploy: { replicas: 4 }
    environment:
      POOL_SIZE: "5"            # sized by the shared-resource math below
    # no ports: reachable only through the balancer (Ch 02)

  worker:
    image: invoicely-api:${GIT_SHA}
    command: celery -A app.workers worker --concurrency=4
    deploy: { replicas: 6 }

  beat:
    image: invoicely-api:${GIT_SHA}
    command: celery -A app.workers beat
    deploy: { replicas: 1 }     # SINGLETON BY DESIGN. Two beats = every
                                # scheduled task fires twice. If this
                                # process's downtime-between-restarts
                                # ever matters, move to a locked
                                # scheduler (redbeat) — not replicas: 2.
```

The connection arithmetic that produced `POOL_SIZE: "5"` — done as config comments so the
next scaler sees the constraint:

```python
# app/core/config.py (excerpt)
class Settings(BaseSettings):
    # SHARED-RESOURCE BUDGET (update when topology changes):
    #   postgres max_connections = 100, superuser_reserved = 3
    #   app:     4 instances × pool 5 (+5 overflow) = 40 peak
    #   workers: 6 × pool 2                         = 12
    #   beat + migrations + psql headroom           = ~10
    #   total peak ~62 of 97 — headroom for +2 app instances.
    #   Beyond that: PgBouncer (transaction pooling) in front.
    pool_size: int = 5
    max_overflow: int = 5
```

And the operational contract — readiness plus graceful shutdown — in one place:

```python
# app/core/lifecycle.py
import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.core.db import engine
from app.core.redis import redis_client

@asynccontextmanager
async def lifespan(app: FastAPI):
    # READINESS: verify own dependencies are reachable BEFORE the
    # health endpoint can say yes (Ch 02's gate has real meaning).
    async with engine.connect() as conn:
        await conn.exec_driver_sql("SELECT 1")
    await redis_client.ping()

    yield  # serve traffic

    # DRAIN on SIGTERM: uvicorn stops accepting and waits for
    # in-flight requests (bounded by the platform's grace period —
    # keep it above the app's own request timeout, Ch 02 ordering).
    await engine.dispose()
    await redis_client.aclose()
```

Note what did *not* change: no request handler learned anything about instances. That is
the sign the refactor landed — horizontal scaling done right is invisible from inside a
request.

## Engineering Decisions

### Externalize, eliminate, or tolerate — per piece of state?

Three verbs, in preference order. **Eliminate** beats externalizing: the export download
endpoint didn't need Redis — presigned object-storage URLs deleted the state *and* the
endpoint. Stateless JWTs (Stage 9) eliminated sessions before this chapter arrived; only
the deny list needed a store. **Externalize** what must be authoritative and shared:
deny list, FX rates, anything where two instances disagreeing is a bug. **Tolerate**
per-instance copies only for derived, re-creatable data where bounded divergence is
harmless — and write the bound down (a 60-second plan-catalog cache is fine; a 60-minute
FX cache was not, because money).

### How many instances, and what size?

Two inputs, computed separately then combined: *capacity* (Chapter 01's load model: peak
demand ÷ per-instance ceiling, measured by load test) and *redundancy* (N+1: enough
instances that losing one under peak still meets the SLO). Small-and-many beats
big-and-few up to a point — finer-grained failure, smoother autoscaling — but each
instance carries fixed overhead (connection pools, memory baseline, scrape targets), and
the shared-resource multiplication punishes high N. Invoicely's answer: 4 × 2-vCPU
instances (peak needs ~2.5, N+1 says ≥3, connection budget caps ~6 without PgBouncer).

### How is singleton work assigned?

The rule: singletons are *explicit processes*, never *elected instances*. The beat
container is the pattern — one copy of a distinct role, declared in the topology where
review and monitoring can see it. The alternatives rank: (1) a dedicated singleton
process (`replicas: 1`) — simplest, brief downtime on restart, correct for almost
everyone; (2) a lock-coordinated scheduler (redbeat via Redis, Chapter 04's locks) when
that downtime matters; (3) leader election — a distributed-systems tool that a SaaS at
this scale should treat as a smell of over-engineering. Never: "instance 1 runs the
crons" (there is no instance 1 — that's the whole point) or the same schedule declared
inside every web process.

### Pool sizes and when PgBouncer arrives?

Do the multiplication at every topology change: `Σ(instances × pool) + workers + overhead`
must sit comfortably under `max_connections`, *and* under what the database can actually
serve concurrently (connections ≠ capacity — hundreds of active connections on a 4-core
Postgres just queue inside the database; Stage 6's guidance stands). Small per-instance
pools (5–10) are almost always right for web workloads. PgBouncer in transaction-pooling
mode enters when instance count makes even small pools breach the budget — with its costs
read first: no session-level state (prepared statements, advisory locks, `SET` — audit
the app for them before flipping the switch).

### Autoscaling — now?

Not until three prerequisites hold: instances are genuinely stateless (this chapter),
startup-to-ready is fast and gated (readiness), and the shared-resource budget survives
the *maximum* instance count (set an explicit ceiling). Then autoscaling is a convenience
on top of a working system. Before them, it is Chapter 01's warning realized: a machine
that multiplies your pathologies while you sleep — scaling into a saturated database, or
flapping instances that each grab and abandon connection pools.

## Trade-offs

| Choice | You gain | You pay |
|---|---|---|
| Externalizing state to Redis | Correctness at any N; instances disposable | A network hop where a dict lookup was; Redis is now in the critical path (Ch 04's operational bill) |
| Eliminating state (presigned URLs, JWT) | No new dependency; state gone, not moved | Design constraints (URL expiry, token size/revocation nuance — Stage 9) |
| Tolerated per-instance caches | Zero coordination cost, RAM-fast reads | Bounded inconsistency between instances — must be measured and documented |
| Dedicated singleton process | Trivially correct scheduled work | One process's restart window; a distinct role to deploy and monitor |
| Lock-coordinated scheduler | No scheduler downtime | Distributed-lock subtleties (Ch 04); harder to reason about than `replicas: 1` |
| Many small instances | Fine-grained failure, smooth scaling curve | Per-instance overhead × N; connection multiplication; more scrape/log volume |
| Few large instances | Lower coordination overhead | Coarse failure units (losing 1 of 2 halves capacity); lumpy scaling |
| Small pools + PgBouncer | Connection budget scales past instance growth | Transaction pooling forbids session state; one more critical-path component |
| Autoscaling (after prerequisites) | Capacity tracks load without pages | Ceiling must be engineered; failure modes now include the autoscaler itself |

## Common Mistakes

- **Scaling to two without the audit.** The balancer works, the second instance starts,
  and the next month is spent chasing "flaky" bugs that are actually routing luck across
  the five kinds of hidden state. The grep-and-trace audit is two days; run it *before*
  N=2, not during the incident retrospectives.
- **Skipping the connection multiplication.** `FATAL: sorry, too many clients already` —
  in production, at peak, because four instances and six workers each brought their
  single-instance pool size. The budget is arithmetic; do it at every topology change,
  and remember the worker tier multiplies too.
- **Scheduled work in the web process.** Every instance runs the loop; every customer
  gets N reminders. Scheduling belongs in the worker tier, in one declared place, run by
  one process. Related: the "startup task" (`on_startup` seeding, cache warming that
  *writes*) that now executes N times per deploy.
- **`/tmp` as a two-request workflow.** Generate file in request one, serve it in request
  two — a different instance answers request two. Local disk is valid *within* one
  request only; anything that outlives the response goes to object storage.
- **Logs and metrics that stayed single-instance.** Debugging now requires knowing which
  instance served the request — logs without an instance identifier and centralization
  (Stage 7 Ch 07) turn every investigation into an SSH tour. Same for metrics: per-
  instance gauges must be labeled, or they overwrite each other.
- **The graceful-shutdown gap.** Instances killed hard on deploy/scale-down drop their
  in-flight requests — which reads as "deploys cause a small error spike we've learned to
  ignore." SIGTERM handling plus a grace period longer than the request timeout closes
  it; Chapter 02's drain sequence assumes it exists.
- **Divergent instances.** A hotfix applied by hand to one instance, an env var set on
  three of four — now requests behave differently by routing luck, which is the same bug
  class as hidden state, self-inflicted. Instances are built from the image and the
  environment definition, or the whole model breaks (Stage 7's pet-server warning, times N).

## AI Mistakes

### Claude Code: the scheduler that ships inside every instance

Asked for "a daily job that sends payment reminders," Claude Code produces the solution
that is correct at N=1 and shortest to write: an `@repeat_every` decorator or an asyncio
background loop *inside the FastAPI app*. It runs in dev, it runs in staging, it survives
review because the code itself is clean — and the day the app scales to four instances,
reminders go out four times. The mistake compounds silently with every scale-up, and
nothing in the code's own file hints that instance count is a variable.

**Detect:** any scheduling primitive (`@repeat_every`, `asyncio.create_task` of a loop,
APScheduler, `threading.Timer`) inside web-process code; periodic behavior not declared
in the one schedule file. **Fix:** state the topology in the prompt ("this app runs N
replicas; scheduled work must execute exactly once") and enforce the structural rule in
review — periodic work exists only in `beat_schedule.py`, executed by the singleton tier.

### GPT: pool sizing for one instance, deployed to ten

Ask GPT for connection-pool guidance and the answer is tuned for a process, not a fleet:
"set pool_size to 20–30 for good concurrency," sometimes with a formula involving CPU
cores — of the *application* machine. It is not wrong for N=1; it is a latent outage
multiplied by every instance you add, because nothing in the advice mentions that pools
sum across instances and workers against one `max_connections`. The number gets baked
into config, the fleet grows, and the database starts refusing logins at month-end peak.

**Detect:** pool sizes recommended or committed without a total-budget calculation
anywhere in the PR; any per-instance tuning advice that never references instance count.
**Fix:** demand the arithmetic — the config comment block from this chapter's
Implementation is the reviewable artifact. Pool changes without the updated budget math
don't merge.

### Cursor: the per-instance cache that makes every refresh a coin flip

Mid-feature, a slow lookup appears — plan limits, FX rates, a settings row — and Cursor
autocompletes the idiom it has seen most: a module-level dict with a timestamp,
`_cache: dict = {}` and a staleness check. Locally correct, instantly effective, and at
N>1 it quietly forks reality: each instance refreshes on its own clock, so two refreshes
of the same page can disagree about an invoice total depending on which instance answers.
No error is ever thrown; users report that numbers "flicker," and the bug reproduces on
no developer machine, because dev is N=1.

**Detect:** new module-level mutable containers holding cross-request data; any
hand-rolled TTL logic outside the sanctioned cache layer (Stage 3 Ch 07 / Redis).
**Fix:** route caching through the shared cache with the tenant-aware key discipline
already established; where a per-instance copy is genuinely acceptable, it must carry a
written staleness bound — "how far apart may two instances be, and is that harmless for
money, auth, and quotas?"

## Best Practices

- **Run the interchangeability audit before N=2 — and re-run it in review, forever.**
  Grep targets: module-level mutable state, filesystem writes outside request-scoped
  temp, scheduling primitives, `threading`/locks, anything keyed "in memory." The audit
  is cheap; each finding fixed pre-scale is an incident that never happened.
- **Ask the destroy question in design reviews.** "If this instance vanishes right now,
  what is lost?" — applied to every new feature that touches state. It keeps the
  taxonomy from silently growing new rows.
- **Provision N+1 against the measured ceiling.** Capacity math from the load model,
  redundancy math from the SLO, and the shared-resource budget checked at every change
  to either.
- **Make singleton roles structural.** A named process (`beat`) with `replicas: 1` and a
  comment saying why, plus a monitoring check that exactly one is running — both zero
  and two are incidents (zero: reminders silently stop; two: they duplicate).
- **Honor the shutdown contract everywhere instances die.** Deploys (Chapter 02's
  drain), scale-downs, and instance failure drills all assume SIGTERM → finish in-flight
  → exit, with the platform grace period above the request timeout.
- **Keep instances literally identical.** Image + environment definition = instance. No
  SSH fixes, no per-host env drift; configuration changes flow through the pipeline
  (Stage 7 Ch 05) to all instances or none.
- **Label everything with the instance.** Structured logs (Stage 3 Ch 08) gain an
  `instance` field; metrics gain the label; the first question of every multi-instance
  investigation — "same instance?" — becomes a filter instead of a forensic project.
- **Drill the disposability.** Kill a random instance under load monthly (Chapter 02's
  drill, now with state on the line): zero non-in-flight errors, no duplicate scheduled
  work, no lost files is the pass condition. This is the test that the audit stayed done.

## Anti-Patterns

- **The special instance.** "Instance 1 also runs the crons / holds the uploads / is the
  one we deploy last." One pet in the herd re-creates every single-server failure mode
  while adding distributed-system debugging on top. Roles get processes; instances stay
  anonymous.
- **Sticky sessions as a statelessness waiver.** Chapter 02 flagged it at the balancer;
  here is the root: affinity doesn't fix per-instance state, it *hides* it while load
  skews and failover still logs users out. The bridge is acceptable only dated and
  tasked.
- **Hand-sharding users to instances.** "Big customers on instance A and B" — turning an
  interchangeable tier back into named servers, with capacity planning per shard and a
  bespoke routing layer to maintain. If data must be partitioned, partition *data*
  (Chapter 07's world), not the stateless tier.
- **Autoscaling a stateful tier.** The autoscaler adds an instance; the instance brings
  its module-level cache and scheduler thread; the bug rate now scales automatically
  too. Statelessness first is a hard ordering, not a preference.
- **Leader election for a cron job.** Consensus machinery (or a hand-rolled "check if
  I'm the oldest instance" heuristic — worse) where `replicas: 1` on a beat container
  answers the requirement. Complexity must be pulled by need, and a SaaS sending
  reminder emails does not need Raft.
- **The startup side-effect.** Migrations, seeding, cache-warming *writes* executed in
  every instance's startup path — N instances now race the same mutation on every
  deploy. Startup verifies readiness; mutations belong to the pipeline (Stage 6 Ch 06's
  migration step) or the singleton tier.

## Decision Tree

```
A piece of state (or a new feature that holds any) — where does it go?
│
├─ Can the state be ELIMINATED by design?
│   ├─ Sessions → stateless JWT (Stage 9) — only revocation needs a store
│   ├─ Served files → object storage + presigned URLs (Stage 3 Ch 09)
│   └─ YES in general → do that; nothing to operate is the best store
├─ Must all instances agree on it (auth, money, quotas, anything a
│  user can see flicker)?
│   ├─ YES → shared store:
│   │   ├─ durable / transactional → PostgreSQL (it's already there)
│   │   ├─ fast / expiring / coordination → Redis (Ch 04)
│   │   └─ NEVER a per-instance copy, whatever the TTL
│   └─ NO (derived, re-creatable, bounded staleness harmless) →
│       per-instance copy allowed; write the staleness bound down
├─ Is it WORK ON A SCHEDULE (not data)?
│   ├─ Downtime-between-restarts tolerable → dedicated singleton
│   │   process, replicas: 1 (the default answer)
│   └─ Not tolerable → lock-coordinated scheduler (Ch 04 locks);
│       leader election only with a written justification
├─ Is it a LOCK / mutual exclusion?
│   ├─ Guarding DB rows → row locks / SELECT FOR UPDATE (Stage 6 Ch 04)
│   └─ Guarding non-DB work across instances → Redis lock (Ch 04)
└─ Scaling the tier itself:
    ├─ Before N=2 → run the audit; fix findings first
    ├─ At every N change → redo the shared-resource budget
    │   (DB conns, Redis conns, outbound API limits, log volume)
    ├─ Pools breach the budget → PgBouncer (transaction mode;
    │   audit for session-state features first)
    └─ Autoscaling → only after: stateless ✓, fast gated startup ✓,
        budget holds at max N ✓ (set the ceiling explicitly)
```

## Checklist

### Implementation Checklist

- [ ] Interchangeability audit run and clean: no module-level mutable cross-request
      state, no filesystem writes outliving a request, no scheduling primitives in web
      processes, no in-memory locks guarding shared resources.
- [ ] All periodic work declared in the single schedule file, executed by a singleton
      process (`replicas: 1`) with a monitor asserting exactly-one.
- [ ] Sessions/revocation, shared caches, and cross-instance counters live in shared
      stores with TTLs; per-instance caches (if any) have written staleness bounds.
- [ ] Files that outlive a request go to object storage; downloads use presigned URLs.
- [ ] Connection budget computed and committed as config comments:
      `Σ(instances × pool) + workers + overhead < max_connections`, with headroom stated.
- [ ] Readiness verified in the lifespan (own DB + Redis reachable) before the health
      endpoint can pass; SIGTERM drains in-flight work within a grace period longer than
      the request timeout.

### Architecture Checklist

- [ ] Instance count derived from measured capacity **plus** N+1 redundancy against the
      SLO — both calculations written down.
- [ ] Every shared resource the fleet touches has a budget line: DB connections, Redis
      connections, outbound API rate limits, log/metric ingest.
- [ ] PgBouncer decision made deliberately (now / at N=? / never) with the
      session-state audit done if transaction pooling is adopted.
- [ ] Autoscaling prerequisites checked and a maximum instance count set — or
      autoscaling explicitly deferred.
- [ ] No named/special instances anywhere in the topology; singleton roles are distinct
      processes.

### Code Review Checklist

- [ ] New module-level mutable containers, `/tmp` writes crossing requests, or scheduling
      primitives in app code → rejected or redirected per the decision tree.
- [ ] Changes to pool sizes or instance counts include the updated budget arithmetic.
- [ ] New periodic tasks land in the schedule file (never decorators in feature modules)
      and are idempotent per Stage 3 Ch 06 — beat restarts can double-fire.
- [ ] Anything cached per-instance states its staleness bound and why flicker is
      harmless for that data.
- [ ] Logs and metrics from new code carry the instance label.

### Deployment Checklist

- [ ] Deploy pipeline uses the Chapter 02 drain per instance; platform grace period
      exceeds the app request timeout.
- [ ] Kill-an-instance drill passed with state on the line: no duplicate scheduled work,
      no lost files, no auth flicker, errors bounded to in-flight requests.
- [ ] Exactly-one monitoring on the beat/singleton tier alerts on zero *and* on two.
- [ ] All instances built from the same image + environment definition; config drift
      between instances is detectable (and detected: compare env in the pipeline).
- [ ] Logs centralized with instance identifiers before N>1 traffic, not after the first
      multi-instance incident.

## Exercises

1. **Run the audit on a real codebase.** Apply the grep-and-trace audit (module-level
   mutable state, filesystem writes, scheduling primitives, threading/locks) to a
   codebase you work on. Produce the five-column table: finding, what breaks at N=2,
   destination (eliminate/externalize/tolerate), effort now, estimated effort under
   load. The last two columns are the argument you'll take to planning.
2. **Reproduce the flicker, then fix it.** In a two-instance docker-compose of a FastAPI
   app, implement an FX-rate lookup with a module-level TTL dict. Drive traffic through
   the Chapter 02 balancer and script a client that detects value disagreement between
   consecutive requests. Then move the cache to Redis with a single beat refresher and
   re-run the detector. Keep both traces — this is the coin-flip bug made visible.
3. **Do the multiplication before the database does.** For a topology of your choosing
   (≥3 app instances, ≥2 workers), compute the full connection budget against
   `max_connections = 100`. Then load-test until you hit connection exhaustion, observe
   the failure mode from the client side, and fix it twice: once by resizing pools, once
   with PgBouncer in transaction mode. Document what broke under PgBouncer (find the
   session-state feature) and how you resolved it.
4. **Kill the singleton, then duplicate it.** With the beat container running scheduled
   reminders against a test inbox: first scale beat to 0 for a day's schedule (observe
   silent non-delivery — what monitoring would have caught it?), then to 2 (observe
   duplicates — was the task idempotent enough to survive?). Write the exactly-one
   monitor both experiments demand.
5. **Prompt the failure, catch it in review.** Ask an assistant for "a FastAPI endpoint
   that generates a large CSV export for download" and separately for "a daily cleanup
   job for expired tokens" — with no topology context. Review both outputs against this
   chapter's Code Review Checklist and count the N=1 assumptions. Re-prompt with the
   topology stated and compare. This is Stage 10's context discipline applied to
   scale-out correctness.

## Further Reading

- The Twelve-Factor App — factors VI (processes: "share-nothing"), III (config), and IX
  (disposability) — the canonical statement of this chapter's contract.
- Martin Kleppmann — *Designing Data-Intensive Applications*, Chapter 1 (scaling out) and
  Chapter 8 (the troubles that arrive with distribution) — the honest sequel.
- PgBouncer documentation — pooling modes and their feature trade-offs; read
  "transaction pooling" caveats before adopting, not after.
- Celery documentation — periodic tasks (beat), and the redbeat project for
  lock-coordinated scheduling when `replicas: 1` isn't enough.
- Randy Bias — "The History of Pets vs Cattle" — the origin of the metaphor and the
  operational philosophy behind disposable instances.
- Google — *Site Reliability Engineering*, Chapter 22, "Addressing Cascading Failures" —
  what the shared-resource multiplication does at the next order of magnitude, and why
  budgets and ceilings matter.
- Stage 3, Chapter 09 ([file storage](../stage-03-backend-engineering/09-file-storage-and-email.md))
  and Stage 9's JWT chapter — the eliminate-first patterns this chapter leans on.

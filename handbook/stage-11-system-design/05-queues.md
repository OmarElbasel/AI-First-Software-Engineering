# Queues

## Introduction

Stage 3, Chapter 06 taught you to write background jobs: what belongs off the request path,
how to make tasks idempotent, when to enqueue relative to the transaction. This chapter is
about the tier those jobs travel through. At one instance and a few hundred jobs an hour,
the queue is an implementation detail of Celery. At the scale Chapter 01 projected — 6,000
PDF renders queued in an hour, webhook fan-out at 9,000 deliveries an hour, all of it
spiking together at month-end — the queue is a system component with its own design
questions: what guarantees it makes about delivery, what order work happens in, what
happens when producers outrun consumers, and what happens to the message that can never be
processed.

A queue does one thing that nothing else in the architecture does: it decouples *when work
is requested* from *when work is done*. That single property is what flattens the month-end
spike (accept 6,000 jobs in minutes, render them over an hour), what isolates failure (the
email provider being down stops emails, not invoice creation), and what lets the worker
tier scale independently of the web tier (Chapter 03's arithmetic, applied to consumers).
The same property is also the source of every queue pathology: work you accepted but
haven't done is a liability that accumulates silently, and a queue is the easiest place in
a system to hide a capacity deficit until it becomes a 30-hour backlog.

The chapter teaches queues as infrastructure: the producer/consumer rate model that
explains when queues help and when they lie, delivery semantics as a correctness contract,
queue topology (which work shares a lane), retry and dead-letter design, backpressure, and
the broker decision. The job *code* stays Stage 3's; the *tier* is ours.

## Why It Matters

- **Queues absorb variance — and only variance.** A queue in front of enough consumer
  capacity turns a spike into a smooth drain. A queue in front of *insufficient* capacity
  just delays the discovery: if producers outrun consumers on average, the backlog grows
  without bound, and the system is failing in a way no error rate shows. Knowing which
  situation you're in is arithmetic, and most teams don't do it.
- **Delivery semantics decide correctness, not performance.** Whether a message can be
  lost (ack-before-work) or duplicated (ack-after-work) determines what the consumer code
  must guarantee. Teams that never chose get both failure modes: lost work on crashes
  *and* duplicates on retries, each blamed on the other.
- **Topology decides who starves.** One shared queue means one slow work class — webhooks
  waiting 30 seconds on a dead endpoint — starves every fast one behind it. Head-of-line
  blocking is invisible in dev (queues are empty) and dominant in production (queues are
  full exactly when it matters).
- **The dead-letter path is where reliability actually lives.** Every queue eventually
  receives a message that cannot succeed — malformed payload, deleted tenant, a bug. With
  no dead-letter design, that message either loops forever (consuming retries, clogging
  the lane) or vanishes (silent data loss). The DLQ, its alert, and its replay runbook
  are the difference between "we lost some webhooks in March" and a ticket.
- **Queue age is the best leading indicator the system has.** CPU says how hard machines
  work; error rate says what already failed. Oldest-message age says how far behind
  *promises* are — reminders not sent, PDFs not rendered, webhooks not delivered. It
  degrades before users notice, which is exactly what an alert should measure.

## Mental Model

**A queue is a buffer between two rates.** Everything else is commentary:

```
   producers ──► [ ░░░░░░░░ backlog ░░░░░░░░ ] ──► consumers
   rate λ                                          rate μ

   μ > λ on average  → backlog is bounded; queue absorbs bursts.
                       drain time after a burst B: B / (μ - λ)
   λ > μ on average  → backlog grows FOREVER. No queue fixes a
                       rate deficit — only more consumers (scale
                       out, Ch 03), cheaper work, or shed load.

   INVOICELY, MONTH-END: 6,000 PDF jobs arrive in ~60 min (λ spike).
   Workers render at 80/min (μ). Backlog peaks ~high, drains in
   6000/80 = 75 min. Acceptable? That's an SLO question — "PDFs
   within 2h of month-end close" — not a feelings question.
```

The two failure modes of intuition: treating a chronic deficit as "the queue is backed
up" (it isn't backed up, it's under-provisioned — Chapter 01's bottleneck, wearing a
buffer), and panicking at a spike backlog that the drain-time math says clears within SLO.
The queue-age alert should be set from the SLO and the math, not from a round number.

**Delivery is a contract with exactly three honest options.**

```
 ACK TIMING                    GUARANTEE        CONSUMER MUST BE
 ack on receipt, then work  →  at-most-once     ok with LOST work
 work, then ack             →  at-least-once    IDEMPOTENT (duplicates
                                                 arrive on crash/timeout)
 "exactly-once transport"   →  does not exist end-to-end. It is
                               at-least-once + idempotent effects
                               (Stage 3 Ch 06) — the guarantee is
                               built in YOUR code, not the broker.
```

At-least-once is the default for anything that matters, which is why Stage 3 made
idempotency non-negotiable. The subtle clause: *redelivery timing*. A consumer that takes
longer than the broker's visibility timeout (SQS) or holds an unacked message through a
connection drop (RabbitMQ, Redis) gets its message redelivered *while it is still
working* — duplicates arrive not only on crashes but on slowness. Idempotency has to
cover the concurrent-duplicate case, not just the retry case.

**Ordering and parallelism are enemies.** A FIFO queue processed by one consumer is
perfectly ordered and perfectly serial. Add a second consumer and messages complete out
of order — always, by construction. The honest design options: unordered (most work —
PDF renders don't care), per-key ordering (all events for *one invoice* in order, keys
spread across consumers — Chapter 07's partition idea, previewed), or global FIFO
(accept one consumer's throughput). Choosing "ordered and parallel" is choosing to be
surprised.

**Topology is failure isolation.** Queues are lanes; work classes with different latency
profiles, SLAs, and failure modes get different lanes with separately sized consumer
pools:

```
              ┌─ q:pdf      ── workers×4 (CPU-bound, month-end spike)
  producers ──┼─ q:email    ── workers×2 (fast, provider rate-limited)
              ┼─ q:webhooks ── workers×2 (slow, OTHER PEOPLE'S uptime)
              └─ q:default  ── workers×1 (everything else)

  One dead webhook endpoint now delays webhooks — not reminder
  emails, not PDFs. Isolation is the point; the cost is more
  pools to size and watch.
```

**Every message ends in exactly one of three places:** processed, dead-lettered, or
expired. The design isn't done until all three paths exist: bounded retries with
exponential backoff *and jitter* (synchronized retries are a self-inflicted DDoS on a
recovering dependency), a dead-letter destination with an alert and an owner, and — for
time-sensitive work — an expiry (a password-reset email delivered four hours late is
worse than none).

A working definition:

> **A production queue tier is a set of lanes matched to work classes, each with: a
> chosen delivery contract (almost always at-least-once + idempotent consumers), a
> consumer pool sized so drain time meets the SLO, bounded retries with backoff and
> jitter, a dead-letter path with an alert and a replay runbook, and an oldest-message-age
> metric wired to that SLO. The queue absorbs variance; capacity, correctness, and the
> poison-message plan remain your job.**

## Production Example

Invoicely's queue tier, redesigned for the Chapter 01 projections. The workload analysis
that drives the topology:

| Work class | Volume (peak) | Latency need | Failure profile |
|---|---|---|---|
| PDF rendering | 6,000/hr at month-end | SLO: ≤2h after close | CPU-bound; retries safe (idempotent render) |
| Emails (reminders, receipts) | 3,000/hr | minutes | provider rate limit 600/hr/IP; transient 4xx/5xx |
| Webhook deliveries | 9,000/hr | minutes, ordered *per subscription* | depends on customers' servers: slow, flaky, sometimes gone forever |
| Housekeeping (exports, cleanup) | low | hours | don't care, must not interfere |

The decisions that follow: four lanes with dedicated pools (the table's rows *are* the
lanes); at-least-once everywhere (`acks_late`) since every task was already idempotent
per Stage 3; webhook deliveries keyed per subscription for ordering, with bounded retries
over ~24h then dead-letter to a database table the support dashboard reads (a customer
asking "where are my webhooks?" gets an answer, not a shrug); email sends capped at the
provider's rate with expiry on time-sensitive sends; PDF pool sized by drain-time math
(6,000 ÷ 2h SLO → ≥50/min sustained → 4 workers at measured 15/min each, N+1 says 5).
The broker stays Redis (the state instance, Chapter 04 — AOF, noeviction) with eyes open:
it is the pragmatic choice at this scale, and the chapter's broker decision below states
what would force the move.

## Folder Structure

```
app/
└── workers/
    ├── celery_app.py           # broker config: acks_late, prefetch,
    │                           #   time limits — the delivery contract
    │                           #   in one reviewable place
    ├── topology.py             # NEW: queues + routing declared in one
    │                           #   file. "Which lane does work class X
    │                           #   use?" has one auditable answer —
    │                           #   same argument as beat_schedule.py
    ├── beat_schedule.py        # Ch 03: the singleton schedule
    ├── tasks/                  # Stage 3's task modules, unchanged —
    │   ├── pdf.py              #   job CODE is Stage 3's concern;
    │   ├── email.py            #   this chapter routes and bounds it
    │   └── webhooks.py
    └── dead_letter.py          # NEW: the DLQ handler — persist the
                                #   corpse, alert, expose replay
infrastructure/
└── compose/
    └── docker-compose.prod.yml # one worker service PER LANE with its
                                #   own concurrency and replica count —
                                #   pools are sized per work class,
                                #   never one blob of workers
```

The principle repeating from Chapter 03: things that must be *audited* (what lanes
exist, what routes where, what runs on a schedule) live in single declared places, not
scattered across decorators — because the failure mode of scattered configuration is
that review can't see topology changes.

## Implementation

The delivery contract and lane declaration:

```python
# app/workers/celery_app.py
from celery import Celery

from app.core.config import settings

celery_app = Celery("invoicely", broker=settings.redis_state_url)

celery_app.conf.update(
    # DELIVERY CONTRACT: at-least-once. Workers ack AFTER completion,
    # so a crash mid-task redelivers instead of losing work. The other
    # half of the contract is Stage 3's: every task idempotent.
    task_acks_late=True,
    task_reject_on_worker_lost=True,

    # A slow worker must not hoard messages other workers could run:
    worker_prefetch_multiplier=1,

    # No task runs forever: hard kill at 300s, soft exception at 240s
    # (the PDF renderer catches it and exits cleanly).
    task_time_limit=300,
    task_soft_time_limit=240,
)
```

```python
# app/workers/topology.py
CELERY_QUEUES = ("pdf", "email", "webhooks", "default")

celery_app.conf.task_routes = {
    "pdf.*":      {"queue": "pdf"},
    "email.*":    {"queue": "email"},
    "webhooks.*": {"queue": "webhooks"},
    # everything unrouted → "default" — and a CI check fails if a
    # task matches no explicit route, so new work classes are ROUTED
    # deliberately, not defaulted accidentally.
}
```

The webhook delivery task — the one with someone else's uptime in its critical path —
carrying the full retry/dead-letter design:

```python
# app/workers/tasks/webhooks.py
import random

from app.workers.celery_app import celery_app
from app.workers.dead_letter import dead_letter
from app.services import webhook_delivery

@celery_app.task(
    bind=True,
    name="webhooks.deliver",
    max_retries=8,             # ~24h of coverage with the backoff below
    rate_limit="30/s",
)
def deliver(self, delivery_id: str) -> None:
    """Deliver one webhook. Payload is an ID, never the event body
    (Stage 3 Ch 06: the row is the truth; the queue carries a pointer).
    """
    result = webhook_delivery.attempt(delivery_id)

    if result.permanent_failure:
        # 4xx (bad signature config, endpoint gone, tenant deleted):
        # retrying cannot succeed. Straight to the morgue.
        dead_letter(self.name, delivery_id, reason=result.detail)
        return

    if result.transient_failure:
        if self.request.retries >= self.max_retries:
            dead_letter(self.name, delivery_id, reason="retries_exhausted")
            return
        # Exponential backoff WITH JITTER: 30s, 1m, 2m ... capped 4h.
        # Jitter prevents every delivery that failed together from
        # retrying together against a just-recovering endpoint.
        delay = min(30 * (2 ** self.request.retries), 14_400)
        raise self.retry(countdown=delay * random.uniform(0.5, 1.5))
```

The dead-letter path — a database table, because corpses need queries, dashboards, and
replay, none of which a queue is good at:

```python
# app/workers/dead_letter.py
from app.core.db import session_scope
from app.models.ops import DeadLetter
from app.core.alerts import notify_ops

def dead_letter(task_name: str, ref_id: str, reason: str) -> None:
    with session_scope() as db:
        db.add(DeadLetter(task=task_name, ref_id=ref_id, reason=reason))
    notify_ops(f"dead-letter: {task_name} {ref_id} ({reason})")

# Replay is a deliberate human act with the bug fixed first:
#   invoicely-cli dlq replay --task webhooks.deliver --since 2026-07-01
# It re-enqueues by ref_id — safe BECAUSE tasks are idempotent.
```

And the metric that watches the whole tier — age, not just depth:

```python
# app/workers/tasks/ops.py — runs on beat every 30s
@celery_app.task(name="ops.queue_metrics")
def queue_metrics() -> None:
    for queue in CELERY_QUEUES:
        depth = broker_llen(queue)
        oldest = broker_oldest_enqueued_at(queue)   # from task headers
        METRICS.gauge("queue.depth", depth, tags={"queue": queue})
        METRICS.gauge("queue.oldest_age_s",
                      age_seconds(oldest), tags={"queue": queue})
# Alerts (Stage 7 Ch 07) fire on AGE vs each lane's SLO:
#   pdf > 45min, email > 10min, webhooks > 15min — and on ANY
#   dead-letter row. Depth alone can't distinguish "burst draining
#   fine" from "consumer wedged"; age can.
```

Per-lane pools in the topology (sizing from the Production Example's math):

```yaml
# docker-compose.prod.yml (excerpt)
worker-pdf:      { command: celery worker -Q pdf -c 4,      deploy: { replicas: 5 } }
worker-email:    { command: celery worker -Q email -c 8,    deploy: { replicas: 1 } }
worker-webhooks: { command: celery worker -Q webhooks -c 16, deploy: { replicas: 2 } }
worker-default:  { command: celery worker -Q default -c 4,  deploy: { replicas: 1 } }
```

## Engineering Decisions

### One lane or many?

Split lanes when work classes differ on any of: latency SLA (emails in minutes vs
exports in hours), duration profile (30s webhook timeouts vs 200ms sends — the
head-of-line argument), failure independence (external-dependency work must not block
internal work), or spike shape (month-end PDFs must not delay everything else). Don't
split further than that: every lane is a pool to size, a dashboard row, and an alert —
lane sprawl is topology nobody can hold in their head. Invoicely's four lanes map to
four genuinely different profiles; a fifth lane needs a fifth profile, not a fifth
feature.

### Ack early or ack late?

Late (at-least-once), for everything whose loss you'd have to explain — which, plus
Stage 3's idempotency requirement, is the pairing this handbook treats as the default
contract. Early acks (at-most-once) are the niche choice for work where a duplicate is
worse than a loss and idempotency is impossible — rare once you've internalized that
"impossible to make idempotent" usually means "haven't found the natural key yet."
Decide once, tier-wide, and let exceptions carry a comment explaining themselves.

### What bounds the retries, and where do the dead go?

Classify failures first: *permanent* (4xx-shaped: malformed, unauthorized, gone) must
never retry — dead-letter immediately with a reason; *transient* (5xx-shaped: timeouts,
overload) retry with exponential backoff, jitter, and a cap chosen from the work's
meaning (webhooks: ~24h of attempts, because customers fix endpoints on human
timescales; emails: shorter, because a day-late receipt is noise). The dead-letter
destination is a queryable table with an alert and a *replay runbook* — a DLQ nobody
watches is a landfill, and a DLQ without replay tooling guarantees the eventual manual
SQL-and-prayer session.

### Bounded or unbounded queues — and what happens at the bound?

The queue is always bounded — by broker memory (Redis: Chapter 04's budget) if you
refuse to choose. Choosing means deciding the overflow behavior per lane *before* the
spike: block/fail the producer (correct for work that must not be silently dropped —
invoice PDFs; the enqueue failure surfaces as a 503 and Chapter 02's balancer sheds),
drop with a metric (defensible for redundant housekeeping), or degrade the feature
(skip the non-essential enrichment). The unacceptable answer is the default one:
backlog grows until the broker dies and every lane loses everything at once.

### Which broker — and what forces a move?

Redis-as-broker (via Celery) is the right call at Invoicely's scale: it's already
operated (Chapter 04), and Celery supplies the ack/retry semantics Redis lists lack.
Its honest limits: broker durability is Redis durability (≤1s AOF loss window), no
native per-message dead-lettering or bounded-queue policies (we built them in
application code above), and visibility semantics are coarser than a real broker's.
RabbitMQ earns its operational cost when you need broker-enforced guarantees —
publisher confirms, per-queue limits with overflow policy, dead-letter exchanges,
priorities — rather than app-code approximations. Managed queues (SQS) trade all
operations away for provider coupling and per-message latency/cost — often the right
trade at team sizes where nobody should be operating brokers. The move is forced by
*guarantee requirements*, not by volume vanity: most systems exit Redis-as-broker
because they need confirms and DLX, not because Redis ran out of throughput.

## Trade-offs

| Choice | You gain | You pay |
|---|---|---|
| At-least-once + idempotent consumers | No lost work; the industry-standard contract | Duplicates on crash/slowness — idempotency is mandatory, forever |
| At-most-once (ack early) | No duplicates, simplest consumers | Crashes lose work silently — acceptable almost nowhere |
| Per-class lanes | Failure isolation; per-SLA sizing; no head-of-line starvation | More pools to size, monitor, and deploy |
| One shared lane | One pool, trivial ops | Slowest work class sets everyone's latency; one poison spike starves all |
| Backoff with jitter, capped | Recovering dependencies aren't re-killed by their own retries | Slower worst-case delivery; more in-flight bookkeeping |
| Aggressive retries | Fast recovery when blips are short | Retry storms; rate-limit burn; the self-DDoS |
| DLQ as database table | Queryable, dashboardable, replayable corpses | Schema + tooling to maintain |
| Unbounded acceptance | Never reject a producer | Backlog hides deficits until the broker dies; the 30-hour surprise |
| Producer-side bounds/shedding | Failures are loud, early, and small | Requires deciding overflow behavior per lane up front |
| Redis broker | Zero new components at this scale | App-code approximations of DLX/bounds; Redis durability window |
| RabbitMQ / managed broker | Broker-enforced guarantees, real DLX, confirms | A new stateful component (or provider coupling) to operate |

## Common Mistakes

- **The everything-queue.** All work classes in one lane, one worker blob — and the
  month-end PDF spike delays password-reset emails by an hour. Lanes exist because
  latency profiles differ; the queue count should match the *profile* count.
- **Averaging away the deficit.** "We process 5,000 jobs/hour and receive 4,800 — fine"
  hides that receipts arrive 9,000/hour for six hours at month-end. Queue math runs on
  the demand *curve*, not its mean; drain time after each spike is the number to check
  against the SLO.
- **Retries without jitter.** A dependency dies for 60 seconds; 3,000 tasks fail
  together, back off together, and return together — every 60 seconds, forever. The
  fixed-interval retry herd keeps dependencies dead. Jitter is one multiplication and
  it prevents the whole class.
- **Retrying the permanently broken.** The 404 webhook endpoint retried every minute
  for a week — burning worker time, polluting logs, and delaying live deliveries behind
  it. Classify 4xx-shaped failures as permanent; dead-letter them on first sight.
- **Watching depth instead of age.** Depth 10,000 might be a healthy burst draining on
  schedule; depth 40 might be a wedged consumer 3 hours behind. Oldest-message age
  against the lane's SLO distinguishes them; depth alone cannot.
- **Prefetch hoarding.** Default prefetch lets one worker grab dozens of messages, then
  process them slowly while other workers idle — the queue reports empty while work
  sits hostage. `prefetch=1` for long tasks; raise it only for genuinely fast, uniform
  work.
- **Fat payloads.** Serializing the whole invoice into the message — so the queue
  carries stale copies of the database (the row changed after enqueue), hits broker
  memory limits, and leaks tenant data into broker logs. IDs in messages; truth in the
  database (Stage 3 Ch 06 said it; scale makes it load-bearing).
- **Forgetting the broker is Chapter 04's Redis.** The queue inherits the state
  instance's durability (≤1s loss) and its memory budget — queue backlog *is* Redis
  memory. The month-end backlog spike belongs in the Redis capacity plan, or the
  OOM incident returns with a new cause.

## AI Mistakes

### Claude Code: the default lane that starves your emails

Asked to add a new background job, Claude Code writes a correct task — idempotent,
retried, well-logged — and routes it nowhere, which means everywhere: the default queue,
the shared worker pool. Each addition is individually harmless; the accumulation is a
topology where webhook deliveries with 30-second timeouts, PDF renders, and OTP emails
share one lane — and at the first month-end spike, the OTP email waits behind four
thousand renders. No individual diff caused it, so no individual review caught it.

**Detect:** tasks with no entry in the routing table; the default lane's traffic growing
over time; latency-sensitive work discovered sharing a lane with batch work.
**Fix:** make routing structurally mandatory — the CI check that fails any task matching
no explicit route — and require new tasks' PRs to state their work class (latency need,
duration, failure profile), which is the information the lane decision needs.

### GPT: the synchronized retry storm

GPT's retry advice is confident and half-right: it reliably suggests retrying transient
failures, usually with exponential backoff — and almost never with jitter, a cap, or the
permanent/transient split. The generated pattern (`retry in 2^n seconds`, uncapped,
for all exceptions) means every task that failed together retries together in
synchronized waves that re-kill the recovering dependency; meanwhile the uncapped
exponent quietly schedules retries for *next week*, and 4xx failures burn all eight
attempts on an endpoint that was never coming back.

**Detect:** `countdown=2 ** retries` with no `random`, no `min()`, and one except-clause
treating all failures alike. **Fix:** the retry block is a pattern, not a paragraph —
backoff × jitter, capped, with an explicit permanent-failure branch to the dead-letter
path; keep it in one decorator/helper so review checks a reference, not a re-derivation.

### Cursor: the consumer that acknowledges before it works

Completing a consumer against a raw queue client (an SQS poller, an `aio-pika` handler,
a Redis Streams reader — anywhere outside Celery's guardrails), Cursor emits the
tutorial-shaped order: receive, ack/delete, *then* process — because that ordering
dominates quickstart examples. It works in every test where processing succeeds. The
first mid-processing crash after deploy silently discards a message: no error, no retry,
no dead-letter — the work is just *gone*, discovered weeks later as the reminder a
customer never got.

**Detect:** ack/delete calls that precede the processing call in consumer code; consumer
tests that never kill the process mid-task. **Fix:** state the contract in review terms —
"ack is the last line, and the handler is idempotent because redelivery is now
possible" — and add the kill-mid-processing test (Exercise 4) to any hand-rolled
consumer, which turns the silent loss into a red test.

## Best Practices

- **Do the drain-time math and pin it to the SLO.** Per lane: peak burst size ÷
  (pool throughput − steady arrivals) = worst drain time; compare to the promise.
  Re-run at every topology or volume change — it's three lines of arithmetic that
  replaces the 30-hour surprise.
- **Default contract everywhere: at-least-once, idempotent, IDs-not-blobs.** One
  sentence that encodes Stage 3 Ch 06 plus this chapter; exceptions carry comments.
- **One retry helper, used by everyone.** Backoff, jitter, cap, permanent/transient
  split, dead-letter on exhaustion — written once, reviewed once, imported forever.
  Retry logic re-derived per task is where the storm bugs breed.
- **Alert on age per lane, on any dead-letter, and on exactly-one for beat.** The
  three queue alerts that matter. Age thresholds come from lane SLOs; the DLQ alert
  has an owner whose job includes the replay decision.
- **Give every lane an overflow policy in writing.** Block, shed, or degrade — decided
  in daylight. The month-end test (Ch 01's load test, extended to the queue tier)
  verifies the policy actually engages.
- **Keep the topology reviewable.** `topology.py`, per-lane worker services, and the
  routing CI check — the queue tier should be readable from two files and one compose
  section, because that's what gets audited when latency mysteries arrive.
- **Drill the poison message.** Inject a permanently failing task in staging; verify it
  dead-letters (not loops), the alert reaches a human, and the replay CLI restores it
  after "the fix." The DLQ path is code that runs rarely — which is exactly why it
  must be rehearsed (Stage 8's argument for testing the unhappy path, applied to ops).

## Anti-Patterns

- **The queue as a database.** Reading the backlog to answer product questions ("how
  many pending invoices?"), storing state in messages, treating the queue as the record
  of what happened. Queues are in-flight work, opaque and transient by design; state
  lives in PostgreSQL, events that must be queryable history live in Chapter 07's
  streams.
- **Synchronous RPC over a queue.** Enqueue, then block the HTTP request polling for
  the result — the latency of a queue plus the coupling of a call, with a timeout
  cliff. If the caller must wait, call (Stage 2's service seams); if it needn't,
  return 202 with a status URL (Stage 3 Ch 06's pattern).
- **Priority inflation.** A priority field, and within a quarter everything is
  `HIGH`. Priorities inside one lane are a losing game; work that genuinely outranks
  other work gets its own lane and pool — capacity is the only priority mechanism
  that can't be inflated by a keyword argument.
- **The infinite retry as reliability.** `max_retries=None` because "we can't lose
  this" — converting a poison message into a permanent tenant of the lane, consuming
  a worker slot at every backoff expiry until a human notices the smell. Bounded
  retries + dead-letter + replay *is* the can't-lose-this design.
- **The polling-table queue, hand-rolled.** A `jobs` table with `WHERE status =
  'pending' LIMIT 1` and no `FOR UPDATE SKIP LOCKED` — two workers grab the same row;
  with polling intervals as the latency floor and vacuum pressure as the bonus. A
  Postgres-backed queue is legitimate at small scale — but done with `SKIP LOCKED`
  and honest eyes, or done with the broker you already run.
- **Draining by deleting.** The backlog is scary, so someone flushes the queue —
  destroying accepted work with no record (those were customers' PDFs). Backlogs are
  drained by capacity, shed by *policy*, or dead-lettered for replay; never deleted
  raw.

## Decision Tree

```
Work is leaving the request path (Stage 3 Ch 06 said it should) —
now design its lane:
│
├─ Does anyone wait on the result synchronously?
│   └─ YES → not a queue job: call it, or return 202 + status URL
├─ Which existing lane profile does it match?
│   ├─ latency-sensitive + fast        → email-class lane
│   ├─ CPU-bound + spiky               → pdf-class lane
│   ├─ external dependency in the path → webhook-class lane
│   ├─ none / don't care               → default lane
│   └─ genuinely NEW profile (new SLA, duration, or failure
│       independence need) → new lane + pool, with drain-time math
├─ Delivery contract:
│   ├─ Loss unacceptable (nearly everything) → acks_late +
│   │   idempotent task + IDs-not-blobs
│   └─ Duplicate worse than loss AND no natural idempotency key
│       (rare — look harder first) → ack early, document why
├─ Ordering required?
│   ├─ NO → parallel consumers, done
│   ├─ Per-entity → key work to one ordered sub-stream per entity
│   │   (or single consumer per key-class); preview of Ch 07
│   └─ Global → one consumer, accept its throughput, question the
│       requirement
├─ Retry design:
│   ├─ Permanent failure (4xx-shaped) → dead-letter immediately
│   ├─ Transient → backoff × jitter, capped, bounded attempts
│   │   sized to the work's meaning → dead-letter on exhaustion
│   └─ Time-sensitive → add expiry; late delivery = don't deliver
├─ Overflow policy for the lane: block producer / shed with
│   metric / degrade feature — written down, load-tested
└─ Broker still right?
    ├─ Need broker-enforced confirms, DLX, bounded queues →
    │   RabbitMQ (or managed equivalent)
    ├─ No ops appetite for any broker → SQS-class managed
    └─ Otherwise → Redis broker (Ch 04 state instance), with its
        durability window written into the lane's loss budget
```

## Checklist

### Implementation Checklist

- [ ] Lanes declared in one topology file; every task explicitly routed (CI-enforced);
      per-lane worker services with independent sizing.
- [ ] `task_acks_late` + `task_reject_on_worker_lost` on (or the broker's equivalent);
      every task idempotent per Stage 3 Ch 06; payloads carry IDs, not entities.
- [ ] The shared retry helper: exponential backoff, jitter, cap, permanent/transient
      classification, dead-letter on exhaustion — and tasks use it instead of
      hand-rolling.
- [ ] Dead letters persist to a queryable table with reason and timestamps; an alert
      fires on arrival; a replay CLI exists and is documented.
- [ ] Time limits (soft + hard) on every lane; prefetch set per lane's duration
      profile; expiries on time-sensitive work.
- [ ] Queue depth AND oldest-message age exported per lane; age alerts wired to lane
      SLOs.

### Architecture Checklist

- [ ] Each lane maps to a distinct work-class profile (latency, duration, failure
      independence, spike shape) — no lane exists without one, none is missing.
- [ ] Drain-time math done per lane against peak bursts and pinned to written SLOs;
      re-run on topology/volume changes.
- [ ] Overflow policy per lane decided and written (block/shed/degrade), with the
      producer-side behavior implemented.
- [ ] Broker choice justified against required guarantees; the Redis-broker durability
      window appears in the loss budget; backlog memory appears in Ch 04's Redis
      capacity plan.
- [ ] Ordering requirements stated per work class; parallelism matches them.

### Code Review Checklist

- [ ] New tasks: routed explicitly, idempotent (named key or natural dedup), using the
      shared retry helper, payload is IDs.
- [ ] Any ack-early consumer or `max_retries=None` carries a written justification —
      default stance is reject.
- [ ] Failure handling distinguishes permanent from transient; permanent goes straight
      to dead-letter.
- [ ] Hand-rolled consumers (outside Celery) ack after processing and have a
      kill-mid-task test.
- [ ] Enqueues happen after the owning transaction commits (Stage 3 Ch 06's rule —
      still the top queue bug in review).

### Deployment Checklist

- [ ] Month-end-shaped load test run against the full topology: age alerts fired
      correctly, overflow policies engaged as designed, drain times matched the math.
- [ ] Poison-message drill passed: dead-lettered (not looping), alerted, replayed
      successfully after a fix.
- [ ] Worker pools deploy with the Ch 02/03 contract: SIGTERM finishes in-flight tasks
      within the grace period (warm shutdown), `acks_late` covers the hard-kill case.
- [ ] Dashboards per lane: depth, age, processing rate, retry rate, DLQ count — on the
      Stage 7 boards next to Redis memory.
- [ ] The exactly-one beat monitor (Ch 03) and per-lane worker liveness both alert —
      zero consumers on a lane is an incident even with zero errors.

## Exercises

1. **Reproduce head-of-line starvation, then fix it with topology.** One lane, one
   4-worker pool: enqueue 2,000 slow tasks (5s sleeps standing in for webhook
   timeouts) and, thirty seconds later, 50 fast "OTP email" tasks. Measure the OTPs'
   delivery latency. Split into two lanes with dedicated pools and repeat. Graph both
   runs — this is the chapter's central argument in one picture.
2. **Do the drain-time math, then watch it come true.** Design a month-end simulation
   (6,000 tasks arriving over 60 minutes into a pool whose measured throughput you
   know). Predict peak backlog and drain time on paper; run it; compare. Then cut the
   pool to half capacity and watch the deficit regime — backlog that never drains —
   and confirm your age alert fires before the SLO breaks.
3. **Trigger a retry storm, then extinguish it.** Point 1,000 webhook tasks at a mock
   endpoint that returns 503 for exactly 90 seconds. Run once with fixed-interval
   retries (watch the synchronized waves hammer the recovered endpoint), once with
   backoff+jitter+cap (watch them spread). Plot requests-per-second at the mock —
   the two shapes are the lesson.
4. **Kill the consumer mid-task, both ways.** A task that writes a row, sleeps 10s,
   then writes a second row. Kill the worker during the sleep with `acks_late=False`,
   then with `acks_late=True`. Verify: early-ack loses the task silently; late-ack
   redelivers it — and make the redelivered execution safe by fixing the task's
   idempotency (the second run must not duplicate the first row).
5. **Run the poison-message drill end to end.** Deploy a task version with a bug that
   permanently fails for one specific payload. Verify the classification sends it to
   the DLQ (not eight futile retries — adjust your classifier if it loops), the alert
   reaches a human with enough context to act, and the replay CLI successfully
   re-runs it after you ship the fix. Write the runbook page as you go — that page is
   the deliverable.

## Further Reading

- Marc Brooker (AWS Builders' Library) — "Timeouts, retries, and backoff with jitter"
  — the definitive short treatment of why jitter is non-optional.
- RabbitMQ documentation — "Reliability Guide" and "Dead Letter Exchanges" — what
  broker-enforced guarantees look like; the checklist for whether you need them.
- AWS SQS documentation — visibility timeout and dead-letter queue semantics — the
  managed articulation of at-least-once, worth reading even if you never use SQS.
- Gregor Hohpe, Bobby Woolf — *Enterprise Integration Patterns* — the vocabulary of
  messaging (competing consumers, dead letter channel, message expiration) that this
  chapter uses with its modern names.
- Celery documentation — "Routing Tasks" and "Task execution options" (`acks_late`,
  time limits, prefetch) — the mechanics behind this chapter's configuration.
- *Designing Data-Intensive Applications* — Chapter 11's first half (message brokers,
  delivery semantics) — the bridge from this chapter to Chapter 07.
- Stage 3, Chapter 06 ([Background Jobs](../stage-03-backend-engineering/06-background-jobs.md))
  — the job-code contract (idempotency, enqueue-after-commit, IDs-not-blobs) that this
  chapter's tier assumes on every lane.

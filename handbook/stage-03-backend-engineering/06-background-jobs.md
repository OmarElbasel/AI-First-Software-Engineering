# Background Jobs

## Introduction

A background job is work moved off the request/response path to run
asynchronously: sending an email, rendering a PDF, syncing to a third party,
processing an upload, running a scheduled report. The user's request returns
immediately; the slow or unreliable work happens in a separate worker process,
pulling tasks from a queue. This chapter is about doing that correctly — which,
as with events (Stage 2, Chapter 07), means confronting the parts that only bite
in production.

The motivation is simple and the correctness is not. Anything slow (a
multi-second PDF render), unreliable (a third-party API that times out), or
naturally deferred (a nightly report) does not belong in a request handler, where
it holds a connection, risks a timeout, and blocks the event loop (Chapter 01).
Moving it to a worker is straightforward; making it *reliable* is where the real
engineering is — because a job queue delivers **at least once**, jobs fail and
retry, and the moment you enqueue a job you have the same dual-write problem that
events have.

Those correctness concerns are not incidental; they are the chapter. A job that
runs twice and charges a customer twice, a job enqueued for a transaction that
rolled back, a failed job that vanishes with no trace, a poison message that
retries forever — each is a production incident invisible in a happy-path test,
and each is what an assistant generates by default. Background jobs are where "it
worked when I ran it once" and "it works when a million of them run under failure"
diverge most sharply.

## Why It Matters

The request path is a bad place for slow or unreliable work. Users abandon slow
requests; HTTP and load-balancer timeouts kill long ones mid-flight; a synchronous
call to a flaky third party makes your latency hostage to theirs; and CPU-heavy
work in a request blocks other requests (Chapter 01). Background jobs move that work
somewhere it can take the time it needs, retry when it fails, and scale
independently of the web tier (the reconciliation extraction in Stage 2, Chapter 04
is exactly this).

But a queue changes the failure model, and three concerns dominate:

- **At-least-once execution.** Queues redeliver — on worker crash, timeout, or
  retry — so a job can run more than once. Every job with a side effect (charge a
  card, send an email, increment a counter) must be **idempotent**, safe to run
  twice on the same input, or it will double-charge and double-send. This is the
  Stage 1 webhook lesson and the Stage 2 event lesson, now a standing law of the
  worker tier.
- **The enqueue/commit ordering (dual write).** If you enqueue a job before (or
  outside) the database transaction commits, the job can run against data that was
  rolled back — or the transaction commits and the job is lost. Enqueuing is the
  same dual-write problem as event publishing (Stage 2, Chapter 07), and it has the
  same answers: enqueue after commit, or a transactional outbox.
- **Failure handling.** Jobs fail — transiently (retry with backoff) and
  permanently (a poison message that will never succeed). Without bounded retries,
  dead-letter handling, and visibility, a failing job either vanishes silently or
  retries forever, and nobody knows.

The AI dimension is the same shape as events: an assistant produces a worker task
that runs once, in order, with nothing failing — the happy path — and omits
idempotency, gets the enqueue/commit order wrong, and gives failures no bounded
retry or dead-letter path. All three pass a single manual run and fail under the
concurrency, redelivery, and failure that production guarantees.

## Mental Model

A job flows from an enqueue on the request path to execution on a worker, and every
transition is a place correctness is won or lost:

```
   REQUEST PATH (fast)                        WORKER (separate process, scalable)
   ┌──────────────────────┐                  ┌──────────────────────────────────┐
   │ do the DB work        │                  │  pull task ─► run handler          │
   │ COMMIT                │                  │    success ─► ack (remove)          │
   │ THEN enqueue the job ─┼──► [ QUEUE ] ──► │    transient fail ─► RETRY w/ backoff│
   │ return to the user    │   (Redis/broker) │      (bounded attempts)             │
   └──────────────────────┘                  │    permanent fail ─► DEAD-LETTER + alert│
                                              └──────────────────────────────────┘
        enqueue AFTER commit                       delivery is AT-LEAST-ONCE:
        (or a transactional outbox)                 the handler MUST be idempotent
```

Four principles make jobs reliable:

**Every job is idempotent.** Because delivery is at-least-once, running a job twice
on the same input must produce the same result as running it once — deduplicate by a
job/business key before any side effect, or design the operation to be naturally
repeatable (upsert, "set to" rather than "increment by"). Idempotency is not
optional and not per-job discretion; it is the price of using a queue.

**Enqueue after the transaction commits.** The state a job depends on must be durable
before the job can run, so enqueue *after* the database commit (or write the job to a
transactional outbox in the same transaction and relay it). Enqueuing inside or before
the commit risks a job running against rolled-back data, or being lost when the commit
fails — the dual-write problem (Stage 2, Chapter 07).

**Failures are bounded and visible.** Transient failures retry with exponential
backoff, up to a limit; permanent failures (a malformed payload, a deleted resource)
go to a dead-letter queue and raise an alert, rather than retrying forever or
vanishing. A job that fails must end up somewhere a human can see.

**Jobs are small, owned, and observable.** A job does one thing, receives its inputs
by value (an ID, not a live object), and carries a correlation ID so its execution can
be traced back to the request that spawned it (Chapter 08). Large, chatty, or opaque
jobs are hard to retry, scale, and debug.

A working definition:

> **A background job moves slow or unreliable work off the request path to a worker
> pulling from a queue. Because the queue delivers at least once and jobs fail, every
> job must be idempotent, enqueued only after its data commits, and its failures
> bounded by retries and caught by a dead-letter queue. The happy path is the easy
> part.**

## Production Example

**Invoicely** has accumulated work that does not belong in request handlers: sending
an invoice emails a PDF to the customer (slow render + a flaky email provider),
running reconciliation is CPU-heavy (the Stage 2 extraction), and monthly statements
run on a schedule. We will build the "send invoice" job, because it exercises every
concern at once — it is slow, it calls an unreliable third party, it must not send the
same invoice twice, and it must not send at all if the "mark as sent" transaction
rolled back.

The stack is a task queue over Redis (the handbook uses Celery/arq-style workers; the
concepts are queue-agnostic). We will show the enqueue done *after* commit, an
idempotent handler that won't double-send on redelivery, bounded retries with backoff
for the flaky provider, and dead-lettering for a permanently failing job. Each is the
difference between a demo that sends one email and a system that, under load and
failure, doesn't email a customer their invoice five times or not at all.

## Folder Structure

```
core/
├── queue.py              # queue/worker config (broker, result backend, defaults)
└── outbox.py             # optional: transactional outbox for enqueue-with-commit
modules/invoicing/
├── tasks.py              # job definitions (send_invoice_email, ...) — small, idempotent
├── _service.py           # enqueues the job AFTER commit (or via outbox)
└── router.py             # returns immediately; the slow work is queued
workers/
└── main.py               # worker entrypoint (scaled independently of the API)
```

Why this shape:

- **`core/queue.py`** centralizes queue configuration — retry defaults, timeouts,
  the broker connection — so every job inherits sane reliability settings.
- **`tasks.py`** holds job definitions per module: small functions that take inputs by
  value and are idempotent. Jobs live with the feature they serve (Stage 2, Chapter 02).
- **`_service.py`** owns the *enqueue-after-commit* ordering, so a job is scheduled
  only once its data is durable.
- **`workers/main.py`** is a separate process, deployed and scaled apart from the web
  tier — the whole point of moving work off the request path.

## Implementation

**Enqueue after commit (`_service.py` / `router.py`).** The invoice is marked sent and
committed *first*; only then is the email job enqueued. If the commit fails, no job is
scheduled — no email for an invoice that isn't actually sent.

```python
# router.py — the request returns immediately; the slow work is queued
@router.post("/invoices/{invoice_id}/send", status_code=status.HTTP_202_ACCEPTED)
async def send_invoice(
    invoice_id: int, service: InvoiceServiceDep, session: SessionDep, account: CurrentAccountDep
) -> dict:
    await service.mark_sent(account.id, invoice_id)   # stages the state change
    await session.commit()                            # 1) COMMIT first — state is durable
    await send_invoice_email.enqueue(invoice_id)      # 2) THEN enqueue — never before commit
    return {"status": "queued"}                       # 202: accepted, not yet done
```

Enqueuing before the commit would risk the worker running before the row is visible
(or at all, if the commit rolls back). For stricter guarantees — where a lost job is
unacceptable — write the job to a transactional outbox in the same transaction and let
a relay enqueue it (the exact pattern from Stage 2, Chapter 07).

**An idempotent job with bounded retries (`tasks.py`).** The handler dedupes before
sending (at-least-once safety), retries the flaky provider with backoff (transient
failures), and lets a permanent failure fall through to the dead-letter queue.

```python
from app.core.queue import task
from app.core.errors import PermanentJobError

@task(
    max_retries=5,
    retry_backoff=True,          # exponential backoff between attempts
    retry_backoff_max=600,       # cap the wait
    acks_late=True,              # ack only AFTER success → crash mid-job → redelivery
)
async def send_invoice_email(invoice_id: int) -> None:
    # IDEMPOTENT: if this invoice's email was already sent, do nothing.
    # A redelivery (retry, crash recovery) must not send a second email.
    if await email_log.already_sent(invoice_id, kind="invoice"):
        return

    invoice = await invoices.get(invoice_id)
    if invoice is None:
        # Permanent: the invoice is gone; retrying will never help → dead-letter.
        raise PermanentJobError(f"invoice {invoice_id} not found")

    pdf = await render_pdf(invoice)          # slow work, off the request path
    try:
        await email_provider.send(to=invoice.customer_email, pdf=pdf)
    except EmailProviderTimeout as exc:
        # Transient: raise to trigger a bounded retry with backoff.
        raise Retry() from exc

    # Record the send BEFORE acking, so redelivery sees it and skips (idempotency).
    await email_log.record_sent(invoice_id, kind="invoice")
```

**Queue configuration and dead-lettering (`core/queue.py`).** Sensible reliability
defaults, and a dead-letter path so permanently failing jobs are caught and alerted,
not lost or looped forever.

```python
# Reliability defaults every task inherits:
#  - acks_late: a job is acknowledged only after it succeeds, so a worker crash
#    mid-job causes redelivery (which is why handlers must be idempotent).
#  - visibility_timeout: how long before an un-acked job is redelivered.
#  - a dead-letter queue for jobs that exhaust retries or raise PermanentJobError.
task_defaults = {
    "acks_late": True,
    "max_retries": 5,
    "retry_backoff": True,
    "dead_letter_queue": "invoicely.dlq",   # exhausted/poison jobs land here
}
# A monitor on the DLQ alerts on arrival — a failed job must be VISIBLE to a human.
```

**A scheduled job.** Periodic work (monthly statements) is the same machinery on a
timer, and the same rules apply — idempotent (running the schedule twice must not
double-bill) and bounded.

```python
@task(max_retries=3)
async def generate_monthly_statements(period: str) -> None:   # period keys idempotency
    for account_id in await accounts.needing_statement(period):
        # per-account idempotency: skip accounts already generated for this period
        if not await statements.exists(account_id, period):
            await statements.generate(account_id, period)
```

The through-line: the request returns a `202` immediately while the real work happens
on a worker; the job is enqueued only after its data is durable; the handler is safe
to run twice; transient failures retry with backoff and permanent ones dead-letter and
alert. Strip any one of those and the demo still sends the email once — which is
exactly why background-job bugs reach production. The reliability *is* the feature; the
"run the work" part is the easy 20%.

## Engineering Decisions

Five decisions define a reliable background-job system.

### Background job, or keep it in the request?

**Options:** (1) do the work synchronously in the request; (2) move it to a background
job.

**Trade-offs:** synchronous is simpler — no queue, no worker, immediate result and
error to the user — but holds the request open, risks timeouts, couples your latency to
slow dependencies, and can't retry. A job returns instantly and adds reliability
machinery, at the cost of eventual completion (the user doesn't get the result inline)
and a queue and worker to operate.

**Recommendation:** background job when the work is slow (seconds), unreliable (a flaky
dependency), resource-heavy, or naturally deferred (scheduled); synchronous when the
user needs the result immediately and the work is fast and reliable. Sending an email
or rendering a PDF is a job; validating and saving a form is not. If the user must see
the outcome now, it's not a job.

### How is idempotency guaranteed?

**Options:** (1) assume exactly-once delivery; (2) deduplicate by a key before side
effects; (3) design operations to be naturally idempotent.

**Trade-offs:** assuming exactly-once is the double-execution bug — queues redeliver.
Dedup-by-key (a job ID, or a business key like "invoice N email") is explicit and works
for any operation, at the cost of a dedup store and the discipline to check it.
Naturally idempotent operations (upsert, "set status to sent" rather than "send") need
no dedup store but aren't always expressible.

**Recommendation:** make every side-effecting job idempotent — prefer naturally
idempotent operations where possible, and otherwise deduplicate by a business key
before the side effect (recording the send *before* acking, as above). At-least-once is
the delivery reality; idempotency is how you survive it. This is non-negotiable for
jobs that touch money, email, or external systems.

### When is the job enqueued relative to the transaction?

**Options:** (1) enqueue inside/before the DB transaction; (2) enqueue after commit;
(3) transactional outbox.

**Trade-offs:** enqueuing before commit risks the job running against rolled-back data
or being lost — the dual-write bug. Enqueue-after-commit is simple and correct for most
cases, but a crash between commit and enqueue loses the job. The outbox guarantees the
job is enqueued iff the transaction committed, at the cost of an outbox table and relay.

**Recommendation:** enqueue after commit for most jobs; use a transactional outbox when
a lost job is unacceptable (billing, external notifications) — the same expand of the
Stage 2, Chapter 07 pattern. Never enqueue inside the transaction. Match the guarantee
to the cost of a lost or premature job.

### How are failures handled?

**Options:** (1) no retries (fail once, lose the work); (2) unbounded retries; (3)
bounded retries with backoff + dead-letter.

**Trade-offs:** no retries loses work on the first transient blip (which will happen).
Unbounded retries turn a poison message into an infinite loop that can hammer a
downstream and never surface. Bounded retries with backoff and a dead-letter queue
recover from transient failures and quarantine permanent ones, at the cost of
configuring both.

**Recommendation:** bounded retries with exponential backoff for transient failures,
and a dead-letter queue with an alert for jobs that exhaust retries or raise a permanent
error. Distinguish transient (retry) from permanent (dead-letter immediately) in the
handler. A failed job must always end up visible — retried to success or dead-lettered
and alerted, never silently lost or looping forever.

### What gets passed to the job, and how big is it?

**Options:** (1) pass rich objects / large payloads; (2) pass identifiers and re-fetch;
small, single-purpose jobs.

**Trade-offs:** passing rich objects avoids a re-fetch but serializes stale or bloated
data into the queue (the object may have changed by the time the job runs, and large
payloads strain the broker). Passing IDs keeps payloads tiny and data fresh at execution
time, at the cost of a lookup in the job.

**Recommendation:** pass identifiers (an `invoice_id`), not serialized objects, and
re-fetch current state inside the job — the data is fresh and the queue stays light.
Keep jobs small and single-purpose so they're easy to retry, scale, and reason about
(Stage 1, Chapter 07). A job that serializes a whole object graph is fragile and stale
by design.

## Trade-offs

Background jobs buy responsiveness and reliability at real cost, and a few decisions are
contextual.

**Async completion trades immediate results for a responsive request.** Moving work to a
job returns the user instantly and means they don't get the result (or the error) inline —
you need a way to report completion (a status field, a notification, polling, a
websocket). For work the user must see now, that indirection is worse than a short
synchronous wait; for genuinely slow work, it's the only good option. Match to whether
the user needs the answer immediately.

**Reliability machinery is operational weight.** A queue, workers, a result/dead-letter
store, retry policies, and monitoring are infrastructure to run, scale, and observe — real
overhead that a tiny app doing one occasional slow thing may not warrant (a single
`BackgroundTasks` call or a threadpool offload might do). The machinery earns its keep as
the volume and criticality of async work grow; imposing it on a prototype is premature
(Stage 1, Chapter 07).

**Idempotency and outbox guarantees cost design effort.** Making every job idempotent and
adding an outbox is more work than firing a task and hoping — and it is the work that keeps
a queue from double-charging customers or losing their invoices. The stronger the
guarantee, the more machinery (dedup stores, outbox tables, relays); scale the guarantee to
the cost of getting it wrong, and never below idempotency for anything with a real side
effect.

**Exactly-once is a myth; plan for at-least-once.** No mainstream queue gives true
exactly-once delivery of side effects, and pretending otherwise is how double-execution
bugs ship. The honest posture is at-least-once delivery plus idempotent handlers, which
*achieves* effectively-once results — the trade is accepting the reality and paying for
idempotency, rather than trusting a guarantee that doesn't exist.

## Common Mistakes

**Non-idempotent jobs.** Assuming exactly-once delivery, so a redelivered job double-sends
or double-charges. Fix: dedupe by a business key before side effects, or use naturally
idempotent operations; record the effect before acking.

**Enqueuing before commit.** Scheduling a job inside or before the transaction, so it runs
against rolled-back data or is lost. Fix: enqueue after commit, or use a transactional
outbox for guaranteed enqueue-with-commit.

**No retry / unbounded retry / no dead-letter.** Losing work on the first transient
failure, looping forever on a poison message, or silently dropping failed jobs. Fix:
bounded retries with backoff for transient failures, a dead-letter queue with an alert for
permanent ones.

**Passing large or live objects into jobs.** Serializing rich objects that are stale by
execution time and bloat the queue. Fix: pass identifiers and re-fetch current state in the
job.

**Doing user-blocking work as a job (or slow work in the request).** Making the user wait on
an async job's result, or conversely leaving slow/flaky work in the request path. Fix: match
the choice to whether the user needs the result immediately and whether the work is
slow/unreliable.

**Invisible jobs.** No logging, no correlation ID, no monitoring — so a failing or stuck job
is undetectable. Fix: correlation IDs from the request into the job, dead-letter alerts, and
queue/worker monitoring (Chapter 08).

## AI Mistakes

Background jobs share the event-tier property that the hard parts — redelivery, failure,
ordering, the enqueue/commit race — are invisible in a single manual run, so an assistant
produces a task that works once and omits every reliability property. Review generated jobs
for what happens under retry, crash, and rollback, not whether the task runs.

### Claude Code: jobs that assume exactly-once execution

Asked to create a background task with a side effect, Claude Code writes a handler that
does the work directly — send the email, charge the card — with no dedup guard, because it
runs correctly the one time it's tested and "run this task" reads as "run it once." Under
at-least-once delivery it double-executes on any retry or crash recovery.

**Detect:** a job performing a side effect (email, charge, external call, counter update)
with no idempotency key, dedup check, or naturally-idempotent operation; an implicit
assumption the job runs exactly once.

**Fix:** require idempotency:

> Job delivery is at-least-once; this handler must be idempotent. Deduplicate by a business
> key before any side effect (and record the effect before acking), or use a naturally
> idempotent operation, so a redelivered job does not repeat the side effect.

### GPT: enqueuing before the data is committed

GPT-family models frequently enqueue the job in the middle of the request handler, before
(or instead of after) the database commit, because the code reads top-to-bottom and "kick
off the work" naturally precedes "finish up." The worker can then run before the row is
visible, or run against data that rolled back.

**Detect:** an `enqueue`/`delay`/`send_task` call before the `commit`, or inside the
transaction; a job that reads a row the request only just created without commit ordering
being explicit.

**Fix:** require commit-then-enqueue:

> Enqueue the job only after the database transaction commits, so the job's data is durable
> before it can run. If a lost job is unacceptable, write it to a transactional outbox in the
> same transaction and relay it. Never enqueue inside or before the commit.

### Cursor: failures with no bounds or dead-letter

Wiring up a task inline, Cursor tends to define the job with no retry policy and no
dead-letter path — or with a bare retry that loops indefinitely — because the failure
behavior isn't visible from the handler body and the happy path needs none of it. Transient
failures then lose the work, or a poison message retries forever unseen.

**Detect:** a task with no `max_retries`/backoff, no dead-letter configuration, a bare
`while`/retry with no limit, or exceptions swallowed inside the handler; no distinction
between transient and permanent failure.

**Fix:** require bounded, visible failure handling:

> Configure bounded retries with exponential backoff for transient failures and a
> dead-letter queue with an alert for jobs that exhaust retries or fail permanently.
> Distinguish transient failures (retry) from permanent ones (dead-letter immediately). A
> failed job must never loop forever or vanish silently.

## Best Practices

**Make every side-effecting job idempotent.** At-least-once delivery is the reality:
deduplicate by a business key before the side effect, or use naturally idempotent
operations, and record the effect before acking so a redelivery skips it.

**Enqueue after commit (or via an outbox).** Schedule a job only once its data is durable;
for jobs that must not be lost, use a transactional outbox so the job is enqueued exactly
when the transaction commits.

**Bound retries and dead-letter the rest.** Exponential backoff and a retry cap for
transient failures; a dead-letter queue with an alert for permanent failures. Distinguish
transient from permanent in the handler, and make every failure end up visible.

**Keep jobs small, pass IDs, and offload only what belongs off the path.** Single-purpose
jobs that take identifiers and re-fetch fresh state; move slow, unreliable, heavy, or
scheduled work to jobs, and keep fast work the user needs immediately in the request.

**Make jobs observable and record the reliability decisions.** Propagate a correlation ID
from the request into the job, monitor queue depth and dead-letter arrivals (Chapter 08),
and document the job's idempotency and delivery guarantees. Record enqueue-ordering and
outbox decisions in an ADR ([`templates/adr.md`](../../templates/adr.md)); the reconciliation
worker's independent scaling is the Stage 2, Chapter 04 extraction realized.

## Anti-Patterns

**The Exactly-Once Job.** A side-effecting handler with no idempotency, assuming the queue
delivers once. The tell: a job that emails or charges with no dedup key, and a retry policy
that would therefore double the effect.

**The Premature Enqueue.** A job scheduled before its data commits, running against
rolled-back or invisible state. The tell: `enqueue` above `commit` in a handler.

**The Fire-and-Forget Failure.** Jobs with no retries, no dead-letter, and no monitoring —
failures lost or looping unseen. The tell: no `max_retries`/DLQ config, and no alert when a
job fails.

**The Poison-Message Loop.** A permanently failing job retried forever, hammering a
downstream and never surfacing. The tell: unbounded retries, or no distinction between
"retry this" and "this will never succeed."

**The Object-Stuffed Task.** Rich, serialized objects passed as job arguments — stale by
execution time and heavy on the broker. The tell: a whole model (or object graph) in a task
payload instead of an ID.

## Decision Tree

"Should this be a background job, and how do I make it reliable?"

```
Does the user need the result immediately, and is the work fast + reliable?
├── YES ──► Do it synchronously in the request. Not a job.
└── NO (slow / unreliable / heavy / scheduled) ──► BACKGROUND JOB.
     │
     ENQUEUE
     └─► after the DB transaction COMMITS (or via a transactional outbox).
         Never inside/before the commit. Pass IDs, not objects. Return 202 to the user.
     │
     THE HANDLER
     ├─► IDEMPOTENT: dedupe by a business key before any side effect
     │   (delivery is at-least-once — it WILL run more than once).
     ├─► TRANSIENT failure ─► raise to retry (bounded, exponential backoff).
     ├─► PERMANENT failure ─► dead-letter immediately + alert.
     └─► carry a correlation id; the DLQ is monitored and alerts a human.
```

## Checklist

### Implementation Checklist

- [ ] Every side-effecting job is idempotent (dedup by key before the effect, or naturally idempotent); the effect is recorded before acking.
- [ ] Jobs are enqueued after the transaction commits, or via a transactional outbox — never before/inside the commit.
- [ ] Jobs receive identifiers and re-fetch state, not serialized objects.
- [ ] Bounded retries with exponential backoff for transient failures; a dead-letter queue for permanent ones.
- [ ] Transient and permanent failures are distinguished in the handler.
- [ ] The endpoint returns immediately (e.g., 202) and the job carries a correlation ID.

### Architecture Checklist

- [ ] Work is a job only when it's slow/unreliable/heavy/scheduled; user-immediate work stays synchronous.
- [ ] Workers are a separate process, scalable independently of the web tier.
- [ ] Delivery guarantees (at-least-once) and each job's idempotency strategy are explicit and documented.
- [ ] The dead-letter queue is monitored and alerts on arrival.
- [ ] Enqueue-ordering / outbox decisions are recorded (ADR); job conventions are in `CLAUDE.md`.

### Code Review Checklist

- [ ] No job assumes exactly-once execution — every side effect is idempotent (watch AI diffs).
- [ ] No job is enqueued before the commit.
- [ ] No unbounded retry, and no job without a dead-letter/failure path.
- [ ] No large/live object passed as a job argument.
- [ ] New jobs propagate a correlation ID and are single-purpose.

### Deployment Checklist

- [ ] Workers are deployed and scaled separately from the API, with their own health/monitoring (see [`checklists/production-readiness.md`](../../checklists/production-readiness.md)).
- [ ] Queue depth, job latency, retry rate, and dead-letter arrivals are monitored and alerted.
- [ ] The broker (Redis/RabbitMQ) is durable and monitored; a broker outage degrades gracefully (the request still commits).
- [ ] A runbook exists for draining/replaying the dead-letter queue after an incident.
- [ ] Scheduled jobs are idempotent against double-firing (overlapping schedules, retries).

## Exercises

**1. Make a job idempotent.** Take a background task that sends an email or charges a card
with no dedup (write one, or have an assistant generate "send the invoice email in the
background") and make it idempotent by a business key, recording the effect before acking.
Then simulate a redelivery (call it twice) and show only one side effect occurs. The
artifact is the idempotent handler and the double-invocation test.

**2. Fix the enqueue order.** Take a handler that enqueues a job before committing (write it,
or find it in AI-generated code) and fix the ordering to enqueue-after-commit; then describe
the two failures the original could cause (job runs against rolled-back data; job lost on a
failed commit) and when you'd upgrade to a transactional outbox instead.

**3. Design the failure path.** For Invoicely's "send invoice" job against a flaky email
provider, design the full failure handling: which failures are transient vs permanent, the
retry policy and backoff, the dead-letter behavior, and the alert. The artifact is the policy
plus a note on what happens to a customer's invoice email in each failure case.

## Further Reading

- **Celery documentation — Tasks, Retries, and the "Should I use retry or acks_late?"
  guidance** (docs.celeryq.dev) — the reference for the handbook's queue, especially
  idempotency, `acks_late`, retries/backoff, and dead-letter handling. Read the tasks and
  "task cookbook" sections closely.
- **arq documentation** (arq-docs.helpmanual.io) — a lighter, async-native Redis task queue
  well-suited to FastAPI; useful to see the same concepts (retries, job uniqueness, cron) in
  a simpler async form.
- **Enterprise Integration Patterns** (Gregor Hohpe & Bobby Woolf), the messaging-endpoint
  patterns — Idempotent Receiver, Dead Letter Channel, Guaranteed Delivery, Competing
  Consumers. The vocabulary and patterns behind reliable job processing (shared with Stage 2,
  Chapter 07).
- **microservices.io — Transactional Outbox** (Chris Richardson) — the pattern for enqueuing a
  job (or event) atomically with a database transaction, for the jobs where a lost enqueue is
  unacceptable.

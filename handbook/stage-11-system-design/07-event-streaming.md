# Event Streaming

## Introduction

Chapter 05's queues have one defining behavior: a message consumed is a message gone. That
is exactly right for work — a PDF should render once — and exactly wrong for facts. When an
invoice is issued, *four* parts of Invoicely care: the webhook dispatcher must notify the
customer's systems, the analytics aggregates must update, the audit trail must record it,
and the search index must reflect it. Model that with queues and you either enqueue four
messages per fact (the producer now knows every consumer — coupling that grows with each
new feature) or you let consumers query the transactional database (the load Chapter 01
worked so hard to remove, creeping back). A stream solves it structurally: facts are
appended to a durable, ordered log that any number of consumers read *independently, at
their own pace, without consuming anything* — and can re-read from any point.

The log is the last mental model this stage adds, and the most general: partitioned
append-only logs with consumer-tracked offsets are how Kafka works, how Redis Streams
works, how database replication works (Stage 6's WAL is a log; Chapter 04's replication is
log shipping), and how most large-scale data infrastructure is built. It is also — the
stage's README said it up front — **the component most often adopted too early**. A
three-person team operating a Kafka cluster for forty events an hour is the canonical
premature-scaling story, which is why this chapter teaches the log model vendor-neutrally,
implements it on the Redis already in the stack, and states precisely what would force the
move to Kafka — so the decision, whenever it comes, is arithmetic rather than fashion.

Boundaries, sharply: *event-driven architecture as a design style* — events vs commands,
choreography vs orchestration, the dual-write problem and the outbox pattern — is Stage 2,
Chapter 07, and is assumed here. This chapter is the infrastructure those designs run on
at scale: partitions, consumer groups, offsets, retention, replay, schema evolution, and
the judgment of when a log earns its keep.

## Why It Matters

- **Fan-out is the growth pattern queues can't express.** Every maturing product grows
  consumers of the same facts: analytics, audit, search, webhooks, the data warehouse, the
  fraud checker. With a log, adding consumer number six is *zero producer changes* — a new
  group reading the same stream. Without one, each addition either edits the producer or
  adds load to the transactional database.
- **It takes whole workloads off the database.** Chapter 01's endgame: analytics
  aggregation, search indexing, and audit queries running against *projections* fed by the
  stream — not against the PostgreSQL that processes payments. The stream is how read
  workloads leave home without losing touch.
- **Replay converts bug recovery from surgery to arithmetic.** A projection bug (analytics
  double-counted credit notes for a week) is fixed by: fix code, reset the group's offset,
  rebuild. Without replay, it's a forensic reconstruction from the transactional DB —
  if the data still exists in queryable form at all.
- **Ordering is finally available where it matters.** Chapter 05 conceded that parallel
  consumers destroy order. Partitioned logs restore the useful version: strict order
  *per key* (per tenant, per invoice) with parallelism *across* keys — the contract
  webhook consumers and audit trails actually need.
- **The premature version costs real money and attention.** Kafka is a distributed
  stateful system with its own failure modes, capacity planning, and upgrade treadmill.
  Adopted before the fan-out exists, it is pure carrying cost — the stage's central
  warning, now at its sharpest, because streaming is the layer with the most
  conference-driven adoption pressure.

## Mental Model

**The log: append-only, offset-addressed, non-destructive to read.**

```
            THE STREAM (an append-only log)
  offset:   0     1     2     3     4     5     6    ...
          ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┐
          │ evt │ evt │ evt │ evt │ evt │ evt │ evt │ ◄─ producers
          └─────┴─────┴─────┴─────┴─────┴─────┴─────┘    append only
                        ▲                   ▲
        group "analytics"                   group "webhooks"
        is at offset 2                      is at offset 5
        (its own bookmark,                  (independent pace,
         its own pace)                       same events)

  Reading moves YOUR bookmark; it deletes nothing. Retention —
  time- or size-based — is what eventually trims the tail.
  Replay = moving a bookmark backward. That's the whole trick.
```

**Partitions: parallelism and ordering, one mechanism.** A stream is split into P
partitions; each event is routed by its *partition key* (hash of tenant_id, say). Two
guarantees follow: events with the same key land in the same partition in append order
(per-key ordering), and different partitions can be consumed in parallel. Within a
consumer group, each partition is owned by exactly one consumer — so P is the group's
maximum parallelism, and the key choice decides both what is ordered and how evenly load
spreads (a whale tenant = a hot partition; the skew problem is chosen at key-design time).

**Consumer groups: queues and pub/sub, unified.** Within one group, consumers *compete*
(each event processed by one member — queue behavior). Across groups, every group gets
*everything* (pub/sub behavior). Each group tracks only its offsets. This is why adding
the sixth consumer is free, and why one group's slow week (webhooks retrying against dead
endpoints) never delays another's (analytics stays current) — backpressure is per-group,
visible as that group's *lag* (how far its bookmark trails the head), which is the
streaming tier's oldest-message-age: the one number to alert on.

**Delivery is still Chapter 05's contract.** Offset commits after processing =
at-least-once (crash between work and commit → reprocessing); commits before =
at-most-once. "Exactly-once" remains an end-to-end property you build: idempotent
consumers keyed by event ID (projectors: upsert; side-effects: dedup table). Nothing
about a log repeals the idempotency law — replay, in fact, doubles down on it.

**Getting facts in: the dual-write problem, again.** Publishing to the stream *and*
committing to PostgreSQL are two systems — Stage 2's dual-write trap verbatim. The answer
is also Stage 2's: the **outbox** — events written to an outbox table *in the same
transaction* as the state change, relayed to the stream by a separate process. (Its
industrial generalization is CDC — Debezium tailing the database's own WAL — worth
knowing as the destination of the same idea.) The producer-side rule this buys: **the
database commits truth; the stream publishes it; nothing publishes what didn't commit.**

**Two kinds of consumers, one replay policy each.** *Projectors* build state (analytics
tables, search indexes): idempotent by construction (upsert by key), safe to rebuild from
offset zero, replay is their superpower. *Side-effectors* act on the world (send
webhooks, emails): replay must **not** re-fire them — they dedup by event ID and their
groups' offsets are never reset casually. Confusing the two is how a projection rebuild
re-sends a month of webhooks.

A working definition:

> **An event stream is a partitioned, append-only log of facts, fed transactionally via
> an outbox, keyed so that ordering follows the entity that needs it, retained long
> enough to make replay a tool, and read by independent consumer groups — projectors that
> may rebuild from zero and side-effectors that must never re-fire — each monitored by
> its lag. It earns its complexity when several consumers need the same facts
> independently; before that day, Chapter 05's queues are the right tool.**

## Production Example

Invoicely's trigger is concrete: the Chapter 01 load test showed analytics dashboard
aggregation and audit queries contributing ~30% of PostgreSQL load, the webhook
dispatcher reads invoice state on every delivery, and the roadmap adds a search index
and a data-warehouse export — consumers four and five of the same facts. The design:

- **One stream per domain aggregate:** `invoice-events` (issued, sent, viewed, paid,
  voided, reminder-sent...), `payment-events`. Not one giant `events` firehose — streams
  are contracts, and contracts have owners (the Stage 2 module boundaries).
- **Partition key: `tenant_id`.** Per-tenant ordering (a tenant's webhook subscriber
  sees *issued → paid* in order, always), parallelism across Invoicely's thousands of
  tenants, hot-tenant risk accepted and monitored (largest tenant is <2% of volume).
- **Producer side: the outbox** Invoicely already built for Stage 2's in-process events,
  now relayed to the stream by a beat-scheduled task (Chapter 03's singleton tier).
- **Four consumer groups:** `analytics` (projector: upserts into aggregate tables —
  the dashboards leave the transactional DB), `audit` (projector: append-only audit
  store), `search` (projector: index updates), `webhooks` (side-effector: dedups by
  event ID, feeds Chapter 05's webhook *queue* — the stream fans out facts; the queue
  still does the delivery work with its retry/DLQ machinery. Streams and queues
  compose; they don't compete).
- **Technology: Redis Streams** on the Chapter 04 state instance — measured volume is
  ~50k events/day (~0.6/sec average, 20/sec month-end peak), retention 14 days ≈
  700k events ≈ well inside the memory budget. The written Kafka triggers: retention
  needs exceeding memory economics (months of history, or >10GB), sustained throughput
  beyond low thousands/sec, CDC/connector ecosystem needs, or a multi-team org where
  streams become the inter-service contract. None are close; the memo is dated and
  revisited with the load model.

## Folder Structure

```
app/
└── events/
    ├── schemas/
    │   ├── envelope.py         # THE envelope: event_id, type, version,
    │   │                       #   occurred_at, tenant_id, payload —
    │   │                       #   every event, no exceptions
    │   └── invoice_events.py   # typed payloads per event type; the
    │                           #   stream's contract lives in the repo,
    │                           #   evolves additively, and is imported
    │                           #   by producers AND consumers (drift
    │                           #   becomes an import error, not a 3am page)
    ├── outbox.py               # Stage 2's outbox table + the relay:
    │                           #   same-transaction insert, beat-driven
    │                           #   publish — the only door to the stream
    ├── stream.py               # XADD/XREADGROUP/XACK/XAUTOCLAIM wrapped
    │                           #   once: consumer-group mechanics are
    │                           #   infrastructure, not per-feature code
    └── consumers/
        ├── analytics.py        # projector — upserts, rebuildable
        ├── audit.py            # projector — append-only store
        ├── search.py           # projector — index updates
        └── webhook_fanout.py   # side-effector — dedups, enqueues to
                                #   Ch 05's webhook lane; NEVER rebuilt
infrastructure/
└── compose/
    └── docker-compose.prod.yml # one consumer service per group —
                                #   groups scale and deploy independently,
                                #   which was the whole point
```

The structural argument repeats one more time: contracts (schemas), the single door
(outbox), and the mechanics (stream.py) each live in exactly one reviewable place —
because the failure mode of streaming systems is not code that breaks but contracts
that drift.

## Implementation

The envelope — the part of the schema that never changes shape:

```python
# app/events/schemas/envelope.py
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel

class EventEnvelope(BaseModel):
    event_id: UUID          # the idempotency key for every consumer
    event_type: str         # "invoice.paid"
    version: int            # payload schema version — consumers accept
                            # v N and N-1 during migrations (additive
                            # evolution: add fields, never remove/rename)
    occurred_at: datetime   # business time, from the producer
    tenant_id: UUID         # partition key + the multi-tenancy floor
    payload: dict           # validated against the typed schema for
                            # event_type/version at both ends
```

The outbox relay — the single, transactional door onto the stream (the Stage 2 outbox,
grown a destination):

```python
# app/events/outbox.py
from app.core.redis import state_redis
from app.core.db import session_scope
from app.models.ops import OutboxEvent

STREAM_MAXLEN = 1_000_000   # size backstop; retention policy is 14 days,
                            # trimmed by a beat task — BOTH live inside
                            # the Ch 04 state-instance memory budget

async def relay_outbox_batch(batch_size: int = 500) -> int:
    """Beat-scheduled (Ch 03 singleton). Reads committed-but-unpublished
    outbox rows IN COMMIT ORDER, appends to the stream, marks published.
    Crash-safe: re-running re-publishes at most the last batch — which
    is why event_id idempotency is every consumer's law."""
    async with session_scope() as db:
        rows = await OutboxEvent.unpublished(db, limit=batch_size)
        for row in rows:
            await state_redis.xadd(
                f"stream:{row.stream}",
                {"envelope": row.envelope_json},
                maxlen=STREAM_MAXLEN,
                approximate=True,
            )
            row.mark_published()
        return len(rows)
```

The consumer-group mechanics, wrapped once (Redis Streams names in code, Kafka names in
comments — the concepts are the portable part):

```python
# app/events/stream.py
from app.core.redis import state_redis

async def consume(stream: str, group: str, consumer: str, handler) -> None:
    """At-least-once consumer loop.
    XREADGROUP ≈ poll; XACK ≈ offset commit; the PEL (pending entries
    list) ≈ delivered-but-uncommitted; XAUTOCLAIM ≈ partition rebalance
    reclaiming a dead consumer's work."""
    while True:
        # 1) reclaim events a crashed group-member left unacked >5 min
        claimed = await state_redis.xautoclaim(
            stream, group, consumer, min_idle_time=300_000, count=50
        )
        # 2) then read new events
        fresh = await state_redis.xreadgroup(
            group, consumer, {stream: ">"}, count=100, block=5_000
        )
        for msg_id, fields in _entries(claimed, fresh):
            envelope = parse_envelope(fields)
            await handler(envelope)          # idempotent — see consumers
            await state_redis.xack(stream, group, msg_id)   # ACK LAST
```

A projector — idempotent by construction, rebuildable by policy:

```python
# app/events/consumers/analytics.py
async def handle(envelope: EventEnvelope) -> None:
    """Projector: UPSERT keyed on natural keys, so replaying any event
    (crash redelivery or full rebuild) converges instead of double-
    counting. Rebuild = reset THIS group's offset to 0 and let it run;
    the transactional DB is never involved."""
    match envelope.event_type:
        case "invoice.paid":
            await aggregates.upsert_revenue(
                tenant_id=envelope.tenant_id,
                month=envelope.occurred_at.date().replace(day=1),
                invoice_id=envelope.payload["invoice_id"],   # natural key:
                amount=envelope.payload["total"],            # re-apply = no-op
            )
        case _:
            pass   # projectors ignore types they don't project — this
                   # tolerance is what makes ADDING event types free
```

The side-effector — the one that must survive both redelivery *and* human replay
mistakes:

```python
# app/events/consumers/webhook_fanout.py
async def handle(envelope: EventEnvelope) -> None:
    """Side-effector: dedup by event_id BEFORE any effect. The dedup row
    is the guard against redelivery AND against an accidental offset
    reset — a replayed event hits the dedup and dies here, silently,
    instead of re-sending a month of webhooks."""
    if not await dedup.claim(f"wh:{envelope.event_id}", ttl_days=30):
        return
    for sub in await subscriptions.for_event(envelope.tenant_id, envelope.event_type):
        deliveries.enqueue(sub.id, envelope)   # → Ch 05's webhook lane:
                                               # retries/DLQ live there
```

And the tier's one alert, lag per group (the streaming sibling of Chapter 05's age
metric): a beat task reads each group's pending count and head-distance and exports
`stream.lag{group=...}` — alerted against each group's own SLO (analytics: 5 minutes;
webhooks fan-out: 1 minute; search: an hour is fine).

## Engineering Decisions

### Stream, queue, or neither?

The decision that precedes all others. A **queue** (Ch 05) when the message is *work*
for exactly one consumer class and history has no value. A **stream** when the message
is a *fact* that ≥2 independent consumers need, or when per-key ordering or replay is a
requirement. **Neither** — a direct call or Stage 2's in-process events — when there is
one consumer and it's in the same codebase; the fourth consumer, not the first, is when
streams pay. The composition is normal: Invoicely's stream fans facts out to a group
that *enqueues work* — streams for distribution, queues for execution.

### What is the partition key?

The entity whose events must stay ordered — and it's a contract, not a tuning knob:
change it later and per-key ordering breaks across the boundary. `tenant_id` when
consumers think per-tenant (Invoicely's do); `invoice_id` for finer parallelism when
only per-entity order matters; never random (that's choosing chaos for throughput you
don't have), never a constant (that's a single-consumer bottleneck wearing a stream
costume). Check the skew: the biggest key's share of volume is the ceiling on how
unbalanced consumption gets.

### How long is retention — and what pays for it?

Retention = the replay window = the projector-rebuild horizon = the new-consumer
backfill depth. Longer is strictly more capable and strictly more expensive — and on
Redis Streams the currency is Chapter 04's state-instance *memory*, which makes the
budget arithmetic mandatory: events/day × size × days, with the MAXLEN backstop for
spikes. Invoicely's 14 days covers "fix a projector bug discovered within a sprint";
rebuilding *older* projections falls back to a source-of-truth export (the DB is still
the truth — see the event-sourcing boundary below). When retention wants to be months,
that is one of the written Kafka triggers firing.

### How do schemas evolve without breaking five consumers?

Additive-only as the standing law: new optional fields and new event types are free
(projectors ignore unknown types by design); renames, removals, and semantic changes
are a new `version`, with consumers accepting N and N−1 during the migration window.
The schemas live in the repo and both sides import them — producer/consumer drift
becomes a type error at CI time (Stage 8's contract-test argument, applied to events).
The rule that keeps all of this honest: events describe *what happened* in business
terms (`invoice.paid`, amount, tenant) — not row diffs, not "what the consumer needs
this week" (Stage 2's events-not-commands, still the law).

### Redis Streams or Kafka — and what forces the move?

Redis Streams wins at Invoicely's scale on a simple argument: the log semantics this
chapter needs (append, groups, acks, claims, trimming) at zero new components, on an
instance already engineered in Chapter 04. Kafka's genuine advantages — disk-priced
retention (months, terabytes), sustained high throughput with partition-level scaling,
the connector/CDC ecosystem, cross-team topic contracts with ACLs and a schema
registry — are exactly the written triggers in the Production Example, and none is
volume vanity: each names a *capability* Redis can't render, not a number that sounds
big. When the move comes, the concepts (and this chapter's code shape) transfer;
`stream.py` is the only file that speaks Redis. Managed Kafka (MSK, Confluent) is the
default *form* of the move — operating ZooKeeper/KRaft quorums is not where a product
team's attention should go (Chapter 02's managed-LB argument, at higher stakes).

## Trade-offs

| Choice | You gain | You pay |
|---|---|---|
| Stream (vs N queues) for facts | Producer decoupled from consumer count; replay; per-key order | A log to operate; retention budget; consumer-group discipline |
| Queues only | Ch 05 machinery you already run | Producer knows every consumer; no replay; fan-out = N enqueues |
| Outbox relay | No dual-write, commit order preserved | Relay latency (seconds); outbox table churn; one more beat task |
| Publish-direct from request | Lowest latency | The dual-write bug, guaranteed eventually (Stage 2's warning) |
| tenant_id partition key | Ordering where consumers think; even-ish spread | Whale tenants = hot partitions; key change = contract break |
| Long retention | Deeper replay/backfill; lazier ops | Memory (Redis) or disk+ops (Kafka); bigger blast radius on schema bugs |
| Projector/side-effector split | Replay is safe by construction | Two consumer disciplines to enforce in review |
| Redis Streams now | Zero new components; Ch 04 leverage | Memory-priced retention; no ecosystem; a migration in your future *if* triggers fire |
| Kafka now | Never migrate; full ecosystem | The canonical premature bill: a distributed system for 0.6 events/sec |
| Managed Kafka (when forced) | The capability without the quorum ops | Cost; provider coupling; still your schemas, keys, and lag |

## Common Mistakes

- **Adopting the stream before the fan-out.** One consumer, a Kafka cluster, and a
  roadmap slide — the premature-infrastructure pattern this stage has fought since
  Chapter 01, at its most expensive. Count independent consumers; below two, use
  Chapter 05.
- **Publishing outside the outbox.** A "quick" `xadd` right in the request handler,
  next to the DB commit — the dual-write returns: commit succeeds + publish fails
  (consumers never learn) or publish succeeds + commit rolls back (consumers learn a
  lie). One door, transactional, no exceptions; review greps for `xadd` outside
  `outbox.py`.
- **Replaying side effects.** The offset reset that rebuilt analytics *and* re-sent
  four weeks of webhooks, because one group did both jobs. The projector/side-effector
  split plus per-group replay policy is the structural fix; the dedup table is the
  seatbelt.
- **Unmonitored lag.** A consumer group wedged for six days — zero errors anywhere,
  because nothing *failed*; it just stopped. Lag-per-group against per-group SLOs is
  the tier's heartbeat; a group with no lag alert is a group already silently behind.
- **Retention by vibes on a memory-priced store.** "Keep everything, Redis is fine" —
  until month-end volume meets the Chapter 04 memory ceiling and the state instance
  (deny list, queues, *and* stream) hits the OOM story again. Retention is a budget
  line: events × size × days, reviewed with the load model.
- **Breaking the schema because the producer "owns" it.** A renamed field ships;
  three consumer groups start dead-lettering every event simultaneously. Event schemas
  are shared contracts with additive-only evolution and versioned escape hatches —
  the producer is their *steward*, not their owner.
- **Consumers that read the head and skip the bookkeeping.** Plain `XREAD` (no group,
  no ack) in anything beyond a debug script: a restart loses position (skip or
  re-process everything), a second copy double-processes the world. Groups, acks, and
  claim of the crashed — the mechanics exist because every one of them covers a real
  failure.

## AI Mistakes

### Claude Code: a Kafka cluster for forty events an hour

Ask Claude Code to "add event streaming so analytics and webhooks can consume invoice
events," and the architecture arrives fully industrialized: Kafka (three brokers,
replication factor 3), schema registry, Debezium CDC, a topic-naming convention, maybe
Flink for good measure — the reference architecture from the training data, where
streaming content is overwhelmingly written by and for companies at four orders of
magnitude more volume. Every piece is defensible somewhere; the *composition* is a
distributed platform bolted onto a product doing 0.6 events per second, and its carrying
cost lands on a three-person team forever.

**Detect:** the proposal names technologies before volumes; no events-per-second number
appears anywhere; the component list exceeds the consumer list. **Fix:** Chapter 01's
discipline, verbatim — feed the assistant the measured load and the existing stack, and
require the design to state what the simplest sufficient rung is and *what trigger would
force the next one*. "Redis Streams until these three written conditions" is the shape
of a right answer.

### GPT: replay that re-sends every email

GPT writes fluent consumer code in which projection and side effects interleave — update
the aggregate, send the notification, index the document, all in one handler — because
most tutorial consumers demonstrate everything in one function. The code is correct on
first delivery and wrong under the log's defining feature: any replay (crash redelivery,
offset reset, projector rebuild) re-executes the side effects. The failure ships silently
and detonates at the first operational use of replay — the analytics rebuild that
re-notifies every customer of every invoice from March.

**Detect:** external effects (email, webhooks, third-party APIs) and state upserts in
the same handler; no dedup-by-event_id in any effectful path; the PR never states the
group's replay policy. **Fix:** enforce the split structurally — projectors and
side-effectors are different consumers in different groups with different replay rules —
and require the dedup claim as the first line of every effectful handler, so even a
wrong offset reset dies at the guard.

### Cursor: the streaming loop that forgets its bookmark

Completing "read events from the stream," Cursor produces the quickstart idiom: a
`while True` loop over plain `XREAD` (or a Kafka consumer with `enable.auto.commit`
defaults and no thought), tracking its position in a local variable. It demos perfectly.
In production, the first deploy restarts the process and the bookmark evaporates —
depending on the start-offset the loop re-processes days of events or silently skips
everything it missed; scale the consumer to two replicas and both copies now process
every event. No consumer group, no acks, no claim of crashed peers: three mechanics
absent, three failure modes armed, zero test failures.

**Detect:** `XREAD` (not `XREADGROUP`) outside debug tooling; consumer position held in
process memory; consumer services with `replicas > 1` and no group semantics; no
`XAUTOCLAIM`/rebalance handling anywhere. **Fix:** the wrapped loop in `stream.py` is
the only sanctioned consumption path — feature code supplies a handler, never its own
loop — which turns this whole mistake class into "why is this file importing redis
directly?" in review.

## Best Practices

- **Count consumers before adopting; write the triggers before scaling.** The stream
  enters at ≥2 independent consumers of the same facts; the next rung (Kafka) enters
  when a *written, dated* trigger fires — capability triggers, not volume vanity. Both
  memos live in the repo (ADR template) and get revisited with the load model.
- **One door in (outbox), one loop out (the wrapper).** Structural chokepoints beat
  discipline: publishing outside `outbox.py` and consuming outside `stream.py` are
  grep-able review failures, which is what makes the dual-write and bookmark mistakes
  rare instead of recurring.
- **Envelope every event; evolve additively; version the exceptions.** `event_id`,
  `type`, `version`, `occurred_at`, `tenant_id` on everything — the five fields that
  make idempotency, routing, migration, debugging, and multi-tenancy possible. Schema
  changes ship with a contract test run against every consumer.
- **Split projectors from side-effectors, and write each group's replay policy.**
  Projectors: rebuildable, upsert-idempotent, offset resets are routine tooling.
  Side-effectors: dedup-guarded, offsets reset only via runbook with a second person.
  The policy is one line per group in the topology file.
- **Alert on lag per group, against that group's SLO.** Plus the relay's own health
  (unpublished-outbox age — the producer-side lag), and stream memory against the
  Chapter 04 budget. Three numbers; the tier is quiet or it's lying.
- **Rehearse the replay.** Quarterly: break a projector in staging, fix it, reset,
  rebuild, verify convergence and — the real test — verify zero side effects fired.
  Replay is the feature you bought the log for; an unrehearsed superpower is a
  future incident with extra steps.
- **Keep the truth in PostgreSQL.** The stream is a *derived* fact feed with bounded
  retention; the database remains the system of record with backups, constraints, and
  Stage 6's machinery. (Event sourcing — the log *as* the truth — is a real but
  different architecture with different costs; adopting it should be a decision with
  its own ADR, never a drift.)

## Anti-Patterns

- **The résumé cluster.** Kafka + registry + connect + a dashboard of one topic doing
  forty events an hour — Chapter 01's resume-driven scaling, final form. The stage's
  whole spine says: the boring rung that meets the measured need, with written
  triggers for the next.
- **The everything-stream.** One `events` firehose carrying every domain's facts:
  every consumer parses everything, ordering guarantees mean nothing (keys from
  different domains interleave), schema governance is impossible, and retention is
  one budget for unrelated needs. Streams per domain aggregate, owned like the Stage 2
  module boundaries they mirror.
- **The stream as a work queue.** Using the log to distribute retryable jobs —
  hand-rolling visibility timeouts, per-message retries, and DLQs out of PELs and
  claims — reinventing Chapter 05 badly (the mirror of Chapter 04's
  lists-as-reliable-queues anti-pattern). Facts flow through streams; work flows
  through queues; the fan-out consumer that turns one into the other is the
  sanctioned bridge.
- **Event sourcing by accident.** "We have all the events — do we still need the
  invoices table?" — deleting the system of record because a 14-day, memory-bounded,
  additively-evolving fact feed *resembles* an event store. It isn't one: no
  snapshots, no forever-retention, no upcasting machinery, no rebuild-from-genesis
  guarantee. The drift version of a major architecture decision is the worst version.
- **Business logic in the pipe.** Enriching, filtering, and transforming events in
  the relay or a growing "stream processor" until the pipe is an unowned application —
  the enterprise service bus, reborn. Smart endpoints, dumb pipes (Stage 2's
  microservices lesson): logic lives in producers and consumers, where it has tests
  and owners.
- **The analytics query against the raw stream.** Answering product questions by
  scanning the log ("count the paid events this month") — slow, retention-bounded,
  and double-counting every redelivery. The stream *feeds* projections; queries hit
  projections. If a question can't be answered by any projection, that's a new
  projector, not a log scan.

## Decision Tree

```
Facts need to reach consumers — choose the machinery:
│
├─ How many INDEPENDENT consumers of the same facts?
│   ├─ 1, same codebase → direct call / Stage 2 in-process events
│   ├─ 1, needs retry/isolation → a queue lane (Ch 05)
│   └─ ≥2 (or hard need for per-key order / replay) → a stream ↓
├─ Which rung?
│   ├─ Volume fits memory-priced retention (Ch 04 budget math),
│   │  no ecosystem/CDC needs, one team → Redis Streams
│   ├─ A written trigger fired (months/TB retention, sustained
│   │  1000s/sec, connector ecosystem, cross-team contracts)
│   │  → Kafka — managed unless ops IS your product
│   └─ Unsure → the smaller rung + the triggers as an ADR
├─ Producer side:
│   └─ ALWAYS the outbox (same-transaction insert, relayed) —
│      direct publish from request code is the dual-write, rejected
├─ Partition key = the entity whose events must stay ordered
│   (tenant / entity id; never random, never constant; check skew)
├─ Retention = replay window you'll actually use, priced against
│   the store (memory vs disk); MAXLEN backstop for spikes
├─ Each consumer group:
│   ├─ Builds state → PROJECTOR: upsert-idempotent, rebuildable,
│   │   offset reset is routine
│   ├─ Acts on the world → SIDE-EFFECTOR: dedup by event_id first,
│   │   offsets reset only by runbook; heavy work → hand off to a
│   │   Ch 05 queue lane
│   └─ Either way: group + ack-after-processing + claim-the-crashed,
│       via the shared consumption wrapper
└─ Wire the three alerts: lag per group vs its SLO, outbox relay
    age, stream size vs memory budget
```

## Checklist

### Implementation Checklist

- [ ] Every event carries the envelope (event_id, type, version, occurred_at,
      tenant_id); payloads validate against repo-hosted typed schemas at both ends.
- [ ] All publishing goes through the transactional outbox + relay; no `xadd`/produce
      calls exist outside it (grep-enforced).
- [ ] All consumption goes through the shared group/ack/claim wrapper; no bare
      `XREAD` or auto-commit consumers outside debug tooling.
- [ ] Projectors are upsert-idempotent on natural keys; side-effectors claim a dedup
      key before any external effect.
- [ ] Streams are per domain aggregate, partition-keyed by the ordered entity, with
      MAXLEN backstops and a retention-trim task.
- [ ] Lag per group, outbox-relay age, and stream memory are exported and alerted.

### Architecture Checklist

- [ ] Adoption is justified by ≥2 independent consumers (or an explicit ordering/
      replay requirement) — the count appears in the ADR.
- [ ] The next-rung triggers (retention, throughput, ecosystem, org shape) are
      written, dated, and attached to the load model's review cycle.
- [ ] Retention window × event volume fits the Chapter 04 memory budget with
      headroom; the replay horizon it buys is documented.
- [ ] Each group is classified projector or side-effector with its replay policy
      recorded in the topology.
- [ ] PostgreSQL remains the system of record; anything resembling event sourcing has
      its own ADR, not a drift path.

### Code Review Checklist

- [ ] New event types: envelope + typed schema + additive evolution (or a version
      bump with a consumer migration plan) + contract test.
- [ ] New consumers: correct classification (projector/side-effector), idempotency
      mechanism named in the PR, lag SLO declared, uses the shared wrapper.
- [ ] No publishing from request handlers; producer changes touch outbox schemas,
      not transport code.
- [ ] Events describe business facts (what happened), not commands (what someone
      should do) — Stage 2's test, applied at the schema diff.
- [ ] Partition-key changes are treated as breaking contract changes and reviewed as
      such.

### Deployment Checklist

- [ ] The replay drill has passed in staging: projector broken → fixed → offset
      reset → rebuild converges → zero side effects fired (dedup verified).
- [ ] Consumer-group failover tested: kill a consumer mid-batch; verify XAUTOCLAIM
      hands its pending events to a peer, exactly-once effects hold.
- [ ] Month-end load test (the stage's running gauge) includes event-volume spikes;
      lag, relay age, and stream memory all stayed inside alerts.
- [ ] Consumer services deploy per group with the Ch 02/03 drain contract; a
      deploy-time restart never loses acknowledged position.
- [ ] Dashboards: per-group lag, relay backlog, stream size vs budget — living next
      to the Ch 04 Redis and Ch 05 queue boards, because they share an instance and
      a failure story.

## Exercises

1. **Build the spine.** Implement the full pipeline on Redis Streams: outbox table +
   relay, the envelope, one stream (`invoice-events`), and two consumer groups — an
   analytics projector (upserting a revenue-by-month table) and a webhook fan-out
   side-effector (dedup + enqueue to a Ch 05 lane). Drive it with simulated invoice
   traffic and verify both groups converge independently when one is paused.
2. **Run the replay drill.** Ship a deliberate bug in the projector (double-count
   credit notes), let a week of simulated events accumulate, then execute the
   recovery: fix, reset the *projector's* offset only, rebuild. Success criteria:
   aggregates converge to correct values AND the webhook dedup table shows zero
   re-fires. Time the rebuild — that number is your real replay capability.
3. **Kill the consumer, watch the claim.** Run the analytics group with two consumers;
   kill one mid-batch (leaving pending entries unacked). Watch XAUTOCLAIM hand its
   work to the survivor and verify the upserts made the redelivery invisible. Then
   repeat with a bare-XREAD consumer and document the difference — this is Exercise 4
   of Chapter 05, one abstraction up.
4. **Find the hot partition.** Key the stream by tenant_id with one synthetic whale
   tenant at 40% of volume. Measure per-consumer throughput and the whale's ordering
   latency vs the long tail. Then re-key by invoice_id and document what you gained
   (spread) and lost (per-tenant ordering) — the partition-key trade-off, measured.
5. **Write the two memos.** For a system you know: (a) the adoption memo — count the
   actual independent consumers of its core facts today, and conclude stream / queue /
   neither with the arithmetic shown; (b) if the answer was "stream," the trigger
   memo — the written conditions that would force Kafka, each phrased as a measurable
   capability gap, dated for review. These two documents are this chapter — and this
   stage — compressed to their decision-making core.

## Further Reading

- Jay Kreps — "The Log: What every software engineer should know about real-time
  data's unifying abstraction" — the essay this chapter's mental model descends from;
  the single best thing to read on the subject.
- Martin Kleppmann — *Designing Data-Intensive Applications*, Chapter 11 —
  logs vs brokers, exactly-once honesty, and stream processing's real semantics.
- Apache Kafka documentation — the "Design" section — partitions, consumer groups,
  and retention from the system that named them; read even if you deploy none of it.
- Redis documentation — "Redis Streams introduction" (XADD, consumer groups,
  XAUTOCLAIM, PEL) — the mechanics behind this chapter's implementation.
- Debezium documentation — the outbox event router and CDC concepts — where the
  outbox pattern goes when it grows up.
- Martin Fowler — "What do you mean by 'Event-Driven'?" — the taxonomy (notification,
  state transfer, event sourcing, CQRS) that keeps this chapter's scope honest.
- Stage 2, Chapter 07 ([Event-Driven Architecture](../stage-02-software-architecture/07-event-driven-architecture.md))
  — the design style (events vs commands, outbox, choreography) this infrastructure
  exists to run.

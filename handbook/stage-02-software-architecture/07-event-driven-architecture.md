# Event-Driven Architecture

## Introduction

Event-driven architecture (EDA) is a style in which components announce that
something happened and other components react, instead of components calling each
other directly. When an invoice is paid, the payment code does not call the email
service, the reconciliation module, and the analytics pipeline in turn; it
publishes one fact — `InvoicePaid` — and whoever cares reacts on their own. The
producer of the event does not know, and does not need to know, who consumes it.

That inversion is the whole idea, and it is the natural culmination of this stage.
Chapter 04 argued that services should communicate through events rather than
chatty synchronous calls; this chapter is how. Chapter 05's services get a way to
signal what happened without reaching across boundaries. And the idempotency
concern that ran through Stage 1's webhook scenarios reappears here as a
first-class requirement, because event delivery, like webhook delivery, is
at-least-once.

EDA is powerful and, like Clean Architecture and microservices before it, easy to
over-apply. It buys decoupling, extensibility, and resilience at the cost of
eventual consistency, harder debugging, and real operational machinery. The
engineering judgment this chapter teaches is where events genuinely help — async
reactions, fan-out, cross-boundary decoupling — versus where a direct call is
simpler and correct, and how to handle the production concerns (the dual-write
problem, at-least-once delivery, traceability) that separate a real event-driven
system from one that merely passes a happy-path demo.

## Why It Matters

Look at what happens when an invoice is paid in Invoicely: a receipt email goes
out, reconciliation updates, the customer's own system is notified by webhook, and
analytics increments. In a direct-call design, the payment code calls all four —
which means the payment code depends on all four, breaks if any of them is down,
and must be edited every time a fifth reaction is added. The producer has become a
coupling hub, and a slow email server now slows down recording a payment.

Events dissolve that coupling, and the benefits are structural:

- **Decoupling.** The producer publishes a fact and knows nothing about consumers.
  Payment recording no longer depends on email, reconciliation, or analytics.
- **Extensibility.** A new reaction is a new subscriber, added without touching the
  producer — the open/closed principle at the architecture level. "When an invoice
  is paid, also update the loyalty program" becomes one new handler.
- **Resilience.** With a broker between producer and consumer, a consumer being
  down means events queue up and are processed when it recovers, rather than
  failing the original operation.
- **Responsiveness and scale.** The producer emits and returns immediately; slow
  work happens asynchronously in consumers that can be scaled independently.

But these benefits are bought with genuine costs that are invisible in a
happy-path test and brutal in production: **eventual consistency** (consumers
react later, so the system is briefly inconsistent), **implicit flow** (there is no
call stack to follow — "what happens when an invoice is paid?" has no single
answer in the code), **at-least-once delivery** (events can arrive more than once,
so consumers must be idempotent), and **operational overhead** (a broker to run,
monitor, and reason about). EDA is a genuine architectural trade, not a free
upgrade.

The AI dimension is sharp precisely because the hard parts are the invisible ones.
An assistant will generate event code that works in a single-delivery, nothing-
fails test while silently containing the classic production bugs: publishing in a
way that can diverge from the database (the dual-write problem), consumers that
assume exactly-once delivery, and "events" that are really commands in disguise.
The optimistic version is what generation produces; the correct version is what
the engineer must impose.

## Mental Model

The core shift is from directed calls to broadcast facts:

```
   DIRECT CALLS — producer knows and depends on every consumer

     PaymentService ──► EmailService
                   ├──► ReconciliationService      producer coupled to all;
                   ├──► WebhookService              add a 5th → edit the producer;
                   └──► AnalyticsService            one slow/broken consumer
                                                     affects the producer

   EVENT-DRIVEN — producer publishes a fact; consumers react independently

     PaymentService ──► [ InvoicePaid ] ──► (bus/broker) ──┬──► send receipt
                          a past-tense fact                 ├──► reconcile
                          producer knows no consumers        ├──► notify webhook
                                                             └──► update analytics
                                                             (add a 5th → just
                                                              subscribe; producer
                                                              unchanged)
```

Four ideas make EDA correct rather than merely decoupled:

**An event is a past-tense fact; a command is an imperative.** `InvoicePaid` is an
event — it states something that already happened, is broadcast to anyone
interested, and cannot be "rejected." `SendReceipt` is a command — it tells a
specific handler to do something, expects to be handled, and can fail or be
refused. Confusing the two ("emitting" a `SendReceiptEmail` event aimed at one
consumer) reintroduces the coupling EDA exists to remove. Producers emit events and
know nothing about who reacts; commands are a separate concept.

**Delivery is at-least-once, so consumers must be idempotent.** Real brokers
redeliver on timeout, retry, or crash recovery — "exactly-once" is largely a myth.
Every consumer with a side effect (send an email, charge a card, increment a
counter) must therefore be safe to run twice on the same event, deduplicating by
event ID. This is the Stage 1 webhook bug, now a standing law of the architecture.

**Persistence and publishing can diverge — the dual-write problem.** If you write
to the database and separately publish to a broker, either can succeed while the
other fails: an event fires for a payment that rolled back, or a committed payment
emits no event. You cannot make two systems commit atomically by hoping. The
production answer is the *transactional outbox* — write the event to a database
table in the same transaction as the state change, and relay it to the broker
afterward — or, in-process, publish only after the transaction commits.

**Flow is implicit, so it must be made observable.** With no call stack linking
producer to consumer, a request's journey across events is invisible unless you
add correlation IDs and tracing, and failures vanish unless you have dead-letter
queues for messages that cannot be processed. Observability is not optional in EDA;
it is the only way to debug it.

A working definition:

> **Event-driven architecture decouples components by having them publish
> past-tense facts and react to them, rather than calling each other. It buys
> decoupling, extensibility, and resilience — at the cost of eventual consistency,
> implicit flow, and the discipline of idempotent consumers, atomic
> publish-with-persistence, and end-to-end tracing.**

## Production Example

**Invoicely's** "invoice paid" fan-out is the ideal case for events: one fact,
several independent reactions, and a producer that should not depend on any of
them. When a payment settles, the system must send a receipt, trigger
reconciliation, notify the customer's webhook, and update analytics — and the
business keeps wanting to add more reactions.

We will build it as **in-process domain events** first, because Invoicely is a
modular monolith (Chapter 04) and a single deployable unit does not need a broker
to decouple its modules — an in-process event bus decouples them at zero
operational cost. The payment module publishes `InvoicePaid`; the invoicing,
notifications, and reconciliation modules subscribe, without the payment module
importing any of them (which also strengthens the module boundaries from Chapter
04). Then we will handle the two production concerns that a real system cannot skip
— avoiding the dual-write problem and making consumers idempotent — and finally
show what changes when reconciliation becomes a separate service and the same event
must cross a broker.

## Folder Structure

```
app/
├── core/
│   ├── events/
│   │   ├── bus.py            # in-process event bus (publish / subscribe)
│   │   └── base.py           # Event base type
│   └── outbox.py             # transactional outbox: event table + relay
├── modules/
│   ├── payments/
│   │   ├── events.py         # InvoicePaid — a past-tense fact, immutable
│   │   └── _service.py       # writes state + enqueues the event (same txn)
│   ├── notifications/
│   │   └── handlers.py       # subscribes to InvoicePaid → send receipt
│   ├── invoicing/
│   │   └── handlers.py       # subscribes to InvoicePaid → mark paid
│   └── reconciliation/
│       └── handlers.py       # subscribes to InvoicePaid → reconcile
deploy/
└── docker-compose.yml        # adds a broker (Redis/RabbitMQ) once cross-service
```

Why this shape:

- **`core/events/`** holds the bus and the event base type — the in-process
  pub/sub mechanism that any module can publish to or subscribe from, owned by no
  single module.
- **Each module defines its own events** (`payments/events.py`) because the event is
  part of the producing module's public contract — the fact *it* announces.
- **Consumers live with their modules** (`notifications/handlers.py`), subscribing to
  events they care about. The producer never imports them, which keeps the module
  boundaries clean.
- **`core/outbox.py`** implements the transactional outbox — the production-grade
  answer to the dual-write problem — so an event is only ever published if its state
  change committed.
- **The broker enters `deploy/`** only when events must cross a service boundary
  (after the Chapter 04 reconciliation extraction). Until then, none is needed.

## Implementation

**The event — an immutable, past-tense fact (`payments/events.py`).**

```python
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
from app.core.events.base import Event


@dataclass(frozen=True)
class InvoicePaid(Event):
    event_id: str          # unique — the basis for idempotent consumers
    invoice_id: int
    account_id: int
    amount: Decimal
    paid_at: datetime
```

**A simple in-process event bus (`core/events/bus.py`).** Publish/subscribe, no
broker. This is genuinely all a modular monolith needs to decouple its modules.

```python
import asyncio
from collections import defaultdict
from collections.abc import Awaitable, Callable
from app.core.events.base import Event

Handler = Callable[[Event], Awaitable[None]]


class EventBus:
    def __init__(self) -> None:
        self._handlers: dict[type[Event], list[Handler]] = defaultdict(list)

    def subscribe(self, event_type: type[Event], handler: Handler) -> None:
        self._handlers[event_type].append(handler)

    async def publish(self, event: Event) -> None:
        # Handlers are independent; one failing must not stop the others.
        results = await asyncio.gather(
            *(h(event) for h in self._handlers[type(event)]),
            return_exceptions=True,
        )
        for r in results:
            if isinstance(r, Exception):
                logger.exception("event handler failed", exc_info=r)
                # in production: route to a dead-letter store for retry
```

**Avoiding the dual-write problem with a transactional outbox
(`core/outbox.py` + service).** The service does *not* publish to the bus inside
the transaction. It writes the event to an outbox table in the *same* transaction
as the state change, so they commit or roll back together; a relay publishes
committed events afterward.

```python
# payments/_service.py — state change and event are written atomically
class PaymentService:
    def __init__(self, repo: PaymentRepository, outbox: Outbox) -> None:
        self._repo = repo
        self._outbox = outbox

    async def record_payment(self, account_id: int, invoice_id: int, amount: Decimal) -> None:
        payment = Payment(account_id=account_id, invoice_id=invoice_id, amount=amount,
                           status="succeeded")
        self._repo.add(payment)
        # Enqueued in the SAME transaction as the payment — no dual write.
        self._outbox.enqueue(
            InvoicePaid(event_id=str(uuid4()), invoice_id=invoice_id,
                        account_id=account_id, amount=amount, paid_at=datetime.now(UTC))
        )
        # The route commits once; a relay then publishes the committed outbox rows.
```

If instead you publish directly, the only safe moment is *after* commit — never
inside the transaction, because a broker publish cannot be rolled back with the
database.

**An idempotent consumer (`notifications/handlers.py`).** Delivery is at-least-once,
so the handler dedupes by `event_id` before its side effect. Running twice on the
same event sends one receipt, not two.

```python
async def on_invoice_paid(event: InvoicePaid) -> None:
    # Idempotency: record the event id first; skip if already processed.
    if not await processed_events.claim(event.event_id, consumer="send_receipt"):
        return  # already handled a prior delivery of this event
    await email.send_receipt(event.invoice_id, event.amount)
```

**Wiring the subscriptions (composition root).** Producers know none of this; the
bus is wired where the app starts up.

```python
# core/events/wiring.py
def register_handlers(bus: EventBus) -> None:
    bus.subscribe(InvoicePaid, notifications.on_invoice_paid)
    bus.subscribe(InvoicePaid, invoicing.on_invoice_paid)      # mark invoice paid
    bus.subscribe(InvoicePaid, reconciliation.on_invoice_paid) # trigger reconcile
    # Add a fifth reaction here — the payment module never changes.
```

**Crossing a broker after extraction.** When reconciliation becomes its own service
(Chapter 04), its handler moves out of process. The outbox relay publishes
`InvoicePaid` to a broker; the reconciliation service consumes it. The producer's
code is unchanged — it still just enqueues the event — and the *only* new
requirements are the ones EDA imposed all along: the consumer stays idempotent, and
the broker gets a dead-letter queue for messages that repeatedly fail.

```yaml
# deploy/docker-compose.yml — a broker appears only now, for cross-service events
services:
  broker:
    image: rabbitmq:3-management
  outbox-relay:
    build: ../services/invoicely-api      # reads committed outbox rows, publishes them
    command: python -m app.core.outbox.relay
  reconciliation-svc:
    build: ../services/reconciliation-svc  # consumes InvoicePaid, idempotently
    deploy: { replicas: 4 }
```

The progression is the point: the *same* event abstraction served an in-process
monolith at zero operational cost and a distributed system after extraction, and at
both scales the correctness requirements were identical — atomic
persist-and-enqueue, idempotent consumers, and observable flow. The broker is an
implementation detail of *delivery*; the discipline is what makes it work.

## Engineering Decisions

Five decisions determine whether an event-driven design helps or hurts.

### Event or direct call?

**Options:** (1) a direct synchronous call; (2) an event.

**Trade-offs:** a direct call is simpler, gives an immediate result, and keeps
strong consistency — at the cost of coupling the caller to the callee and blocking
on it. An event decouples and enables async fan-out — at the cost of eventual
consistency and no direct response.

**Recommendation:** use a direct call when you need a synchronous answer or the work
must happen atomically now (validating and recording the payment itself); use an
event when the interaction is a decoupled reaction to something that happened,
especially fan-out to multiple consumers (everything that should happen *because* a
payment settled). If you need the result to continue, it is a call, not an event.

### In-process events or a broker?

**Options:** (1) an in-process event bus; (2) a message broker (Redis, RabbitMQ,
Kafka).

**Trade-offs:** an in-process bus has zero operational overhead and decouples
modules within one deployable unit, but offers no durability (a crash loses
in-flight events) and cannot cross services. A broker adds durability, buffering,
retries, and cross-service delivery, at the cost of running and monitoring
infrastructure and reasoning about its delivery semantics.

**Recommendation:** start with in-process domain events in a monolith; introduce a
broker when you genuinely need durability, asynchronous processing that survives
crashes, or cross-service delivery — which, not coincidentally, is the same
threshold as the service extraction in Chapter 04. Do not stand up a broker to
decouple two modules in one process.

### How do you avoid the dual-write problem?

**Options:** (1) publish to the broker inside the transaction; (2) publish after
commit; (3) transactional outbox.

**Trade-offs:** publishing inside the transaction is the bug — the publish cannot
roll back with the database, so state and events diverge. Publishing after commit is
simple and mostly correct, but a crash between commit and publish loses the event.
The outbox writes the event atomically with the state change and relays it reliably,
at the cost of an outbox table and a relay process.

**Recommendation:** for anything where a lost event matters (money, external
notifications), use the transactional outbox — it is the standard, reliable answer.
Publish-after-commit is acceptable for low-stakes, in-process events where an
occasional lost event is tolerable. Never publish inside the transaction. Record the
choice in an ADR ([`templates/adr.md`](../../templates/adr.md)).

### Event notification or event-carried state transfer?

**Options:** (1) a thin event (just IDs) that consumers use to call back for
details; (2) a fat event carrying the data consumers need.

**Trade-offs:** thin events keep the contract small and always-fresh but make
consumers call back to the producer (recoupling, and load). Fat events let consumers
work without calling back (better decoupling and resilience) but grow the event
contract and can carry stale or excessive data, and leak internal state if
careless.

**Recommendation:** carry the state consumers genuinely need to act
(`InvoicePaid` carrying the amount and IDs), keeping the event a deliberate,
minimal, stable contract — not a dump of the producer's internal model. Lean toward
event-carried state transfer for cross-service events (to avoid callback coupling),
and keep the payload curated.

### Choreography or orchestration for multi-step workflows?

**Options:** (1) choreography — services react to each other's events with no
central coordinator; (2) orchestration — a coordinator (a saga orchestrator) directs
the steps.

**Trade-offs:** choreography is maximally decoupled but makes a multi-step business
process an emergent, hard-to-see behavior with no single place describing it.
Orchestration centralizes the workflow (visible, easier to change and monitor) at
the cost of a coordinator that knows the steps.

**Recommendation:** choreography for simple, few-step fan-out; an explicit
orchestration/saga for complex multi-step workflows with compensation
(refund-on-failure), because an implicit process spread across a dozen event
handlers is unmaintainable. Match the coordination to the workflow's complexity.

## Trade-offs

EDA is a genuine architectural trade with a clear domain of usefulness.

**Eventual consistency is the price of decoupling.** Consumers react after the fact,
so the system is briefly inconsistent — the invoice is paid but the receipt hasn't
sent yet, reconciliation hasn't run yet. For reactions where that lag is fine
(receipts, analytics), it is a non-issue; for anything that needs immediate
consistency, events are the wrong tool and a synchronous call is correct.

**Debugging is materially harder.** There is no call stack from producer to
consumer; the flow is implicit and distributed. Without correlation IDs, tracing,
and dead-letter queues, "why didn't the receipt send?" becomes an archaeology
project. The observability cost is real and must be paid up front, not after the
first incident.

**Operational and cognitive overhead.** A broker is infrastructure to run, secure,
monitor, and scale, and at-least-once delivery imposes idempotency on every consumer
forever. The system also becomes harder to reason about — "what happens when X?" no
longer has a single answer in the code, which is a genuine maintainability cost
(Stage 1, Chapter 08).

**When to use it, and when not.** Use events for decoupled asynchronous reactions,
fan-out (one fact, many independent reactions), cross-service communication (Chapter
04), and extensibility (frequent new reactions to existing facts). Avoid them for
synchronous request/response, operations that must be strongly consistent right now,
and simple interactions where a direct call is clearer — and do not adopt a broker,
or event sourcing, before you have the need. As with every chapter in this stage,
match the tool to the force; "event-driven" is not automatically more advanced, it
is differently constrained.

## Common Mistakes

**Event-ing everything.** Using events for synchronous, needs-a-response
interactions that should be direct calls, adding indirection and eventual
consistency where you needed an answer now. Fix: events are for decoupled async
reactions and fan-out; if the caller needs the result to proceed, use a call.

**The dual write.** Publishing to a broker and writing to the database such that one
can succeed while the other fails, leaving events and state divergent. Fix:
transactional outbox, or publish only after commit; never publish inside the
transaction.

**Non-idempotent consumers.** Assuming exactly-once delivery, so a redelivered event
sends two receipts or double-counts. Fix: at-least-once is reality — dedupe by event
ID and make every side-effecting consumer safe to run twice.

**Events that are really commands.** Imperative, single-target "events"
(`SendReceiptEmail`) that a producer emits expecting a specific consumer to act —
coupling disguised as decoupling. Fix: events are past-tense facts (`InvoicePaid`);
producers know no consumers; use explicit commands where you mean "do this."

**No traceability or dead-lettering.** Event flow with no correlation IDs, no
tracing, and no handling for messages that repeatedly fail — an undebuggable system
that silently drops or infinitely retries poison messages. Fix: correlation IDs and
tracing across the flow, and a dead-letter queue for unprocessable messages.

## AI Mistakes

EDA's hard parts are exactly the ones invisible in a happy-path test — delivery
semantics, atomicity of publish-with-persistence, implicit flow — so an assistant
generates event code that runs in the demo and carries the classic production bugs.
The countermeasure is to review specifically for the failure modes that only appear
under redelivery, failure, and concurrency, because the generated code will assume
none of them happen.

### Claude Code: publishing across the transaction boundary (the dual write)

Asked to publish an event when something happens, Claude Code typically publishes to
the bus or broker right where the state changes — inside or before the database
commit — producing the dual-write bug: an event fires for a payment that later rolls
back, or a committed payment emits nothing if the publish fails. It looks correct and
is a data-integrity bug waiting for a partial failure.

**Detect:** a broker/bus publish inside a transaction or before `commit()`; no
outbox and no "publish after commit" boundary. The publish and the commit not being
coordinated is the tell.

**Fix:** require atomic persist-and-enqueue:

> Do not publish inside the database transaction. Either write the event to a
> transactional outbox in the same transaction as the state change and relay it
> after commit, or publish only after the transaction has committed. The event must
> never fire for a change that rolled back.

### GPT: events that are commands in disguise

GPT-family models frequently produce imperative, single-consumer "events" —
`SendReceiptEmail`, `UpdateAnalytics` — that a producer emits expecting a particular
handler to act, which couples the producer to the consumer and defeats the point of
EDA. It has the syntax of events and the semantics of direct calls.

**Detect:** imperative event names (`SendX`, `DoY`), a producer that breaks or
misbehaves if a consumer is absent, or "events" with exactly one intended handler
that the producer clearly depends on.

**Fix:** enforce the event/command distinction:

> Events are past-tense facts (`InvoicePaid`), broadcast to any interested consumer,
> and the producer must not depend on who handles them. If the code means "make a
> specific thing happen," that is a command or a direct call, not an event. Name and
> model events as facts.

### Cursor: consumers with no idempotency

Editing a consumer inline, Cursor adds the side effect — send the email, increment
the counter, call the webhook — without a dedupe guard, because the at-least-once
delivery context is not visible at the cursor. Under redelivery, the consumer
double-processes: two receipts, a double-counted metric, a duplicate external call.

**Detect:** an event handler that performs a side effect with no idempotency/dedup
key, no check of an already-processed store, and an implicit assumption that the
event arrives exactly once.

**Fix:** require idempotency as a property of every consumer:

> Event delivery is at-least-once; this handler must be idempotent. Deduplicate by
> `event_id` — record processed events and skip ones already handled — before
> performing any side effect, so a redelivered event does not repeat it.

## Best Practices

**Model events as immutable past-tense facts; keep commands separate.** `InvoicePaid`,
not `SendReceipt`. Producers publish facts and know nothing about consumers; where
you mean "do this specific thing," use a command or a direct call.

**Start in-process; add a broker only when you need it.** Decouple modules with an
in-process event bus at zero operational cost; introduce a broker for durability,
crash-safe async, or cross-service delivery — the same threshold as service
extraction (Chapter 04).

**Make persistence and publishing atomic.** Use a transactional outbox (or
publish-strictly-after-commit for low-stakes events) so an event never fires for a
change that rolled back and a committed change never loses its event. Never publish
inside the transaction.

**Make every consumer idempotent.** Treat at-least-once delivery as law: dedupe by
event ID before any side effect, so redelivery is harmless. This is not optional and
not per-consumer discretion — it is a property the architecture requires everywhere.

**Make the flow observable, and don't event-everything.** Propagate correlation IDs,
trace across producers and consumers, and dead-letter unprocessable messages — you
cannot debug implicit flow otherwise. And reserve events for decoupled async
reactions and fan-out; use direct calls for synchronous, must-happen-now
interactions. Record delivery and consistency decisions in `CLAUDE.md` and ADRs.

## Anti-Patterns

**Event-Everything.** Using events for synchronous request/response that should be
direct calls, buying indirection and eventual consistency where an immediate answer
was needed. The tell: a consumer the producer then waits on for a result.

**The Dual Write.** Publishing and persisting so they can diverge under partial
failure — the most common data-integrity bug in event systems. The tell: a publish
call sitting inside or immediately before a database transaction, with no outbox.

**Events as Commands.** Imperative, single-target "events" the producer depends on
being handled — distributed coupling wearing an event costume. The tell: an event
named as an instruction, and a producer that breaks if no one consumes it.

**The Non-Idempotent Consumer.** Handlers that assume exactly-once delivery and
double-process on redelivery. The tell: a side effect with no dedup key and no
processed-event check.

**The Untraceable Flow.** Event systems with no correlation IDs, no tracing, and no
dead-letter handling — undebuggable, silently dropping or infinitely retrying poison
messages. The tell: an incident where nobody can reconstruct what an event did.

**Accidental Event Sourcing.** Drifting into events-as-source-of-truth (rebuilding
state by replaying events) without deciding to — a major architectural commitment
adopted by accident. The tell: no current-state tables, only an event log nobody
planned to make authoritative. (Event sourcing is a legitimate pattern; adopt it
deliberately or not at all.)

## Decision Tree

"Should this interaction be an event, and how do I do it right?"

```
Do you need a synchronous result, or must it happen atomically right now?
│
├── YES ──► DIRECT CALL (service/function). Not an event.
│           (Recording the payment itself; anything the caller waits on.)
│
└── NO (a decoupled reaction to something that happened; async; fan-out)
    │
    └──► EVENT — a past-tense fact the producer publishes knowing no consumers.
         │
         In-process or across services?
         ├── Same deployable unit ──► in-process event bus (no broker).
         └── Cross-service / need durability / crash-safe async ──► broker
             (same threshold as service extraction, Chapter 04).
         │
         Publishing (avoid the dual write):
         ├── Lost event matters (money, external) ──► transactional outbox.
         └── Low stakes, in-process ─────────────────► publish AFTER commit.
             (Never publish inside the transaction.)
         │
         Every consumer:
         ├── idempotent (dedupe by event_id — delivery is at-least-once),
         ├── failures go to a dead-letter queue, and
         └── flow carries a correlation ID for tracing.
```

## Checklist

### Implementation Checklist

- [ ] Events are immutable, past-tense facts with a unique `event_id`; commands are modeled separately.
- [ ] Producers publish events without importing or depending on any consumer.
- [ ] State change and event publication are atomic (transactional outbox, or publish strictly after commit) — never a publish inside the transaction.
- [ ] Every side-effecting consumer is idempotent, deduplicating by `event_id`.
- [ ] Handler failures are isolated (one failing consumer does not stop the others) and routed to a dead-letter store.
- [ ] Subscriptions are wired in a composition root, not by producers reaching for consumers.

### Architecture Checklist

- [ ] Events are used for decoupled async reactions and fan-out — not for synchronous, needs-a-response interactions.
- [ ] The transport matches the need: in-process bus within a deployable unit, broker only for durability/cross-service.
- [ ] Event payloads are deliberate, minimal contracts, not dumps of the producer's internal model.
- [ ] Multi-step workflows use explicit orchestration/sagas where choreography would become an invisible process.
- [ ] Delivery-semantics and consistency decisions are recorded in ADRs.

### Code Review Checklist

- [ ] No publish sits inside a database transaction (dual-write risk) — watch AI diffs.
- [ ] No "event" is actually an imperative command coupling the producer to a consumer.
- [ ] Every new consumer deduplicates by `event_id` before its side effect.
- [ ] New consumers handle their own failures and don't assume exactly-once delivery.
- [ ] Event payload changes preserve the contract consumers depend on.

### Deployment Checklist

- [ ] The broker is deployed with durability (persistent queues), monitoring (queue depth, consumer lag), and a dead-letter queue (see [`checklists/production-readiness.md`](../../checklists/production-readiness.md)).
- [ ] The outbox relay is deployed, monitored, and recovers after a crash without losing or duplicating beyond at-least-once.
- [ ] Consumers scale independently of producers, and consumer lag is alerted on.
- [ ] Correlation IDs propagate across producers, the broker, and consumers for end-to-end tracing.
- [ ] Poison-message handling (dead-letter + alert) is in place so a bad message neither blocks the queue nor retries forever.

## Exercises

**1. Decouple a fan-out.** Take a producer that directly calls several services on an
event (write the coupled version, or have an assistant generate "when an invoice is
paid, send an email, reconcile, and notify") and convert it to publish one
`InvoicePaid` event with independent subscribers via an in-process bus. Then add a
fifth reaction *without touching the producer*. The artifact is the before/after plus
the fifth handler — proof of the decoupling and extensibility EDA buys.

**2. Fix the production bugs.** Take an event flow that publishes inside its
transaction and has a non-idempotent consumer (write it, or find it in AI-generated
code) and fix both: introduce a transactional outbox (or publish-after-commit) and
make the consumer idempotent by `event_id`. The artifact is the corrected code plus a
paragraph describing the exact production failure each bug would have caused.

**3. Classify the interactions.** Given a set of interactions in a system —
"record the payment," "send the receipt," "return the updated balance to the caller,"
"update the fraud model" — decide for each whether it should be a direct call, a
command, or an event, and justify. The artifact is the classification; the point is
that events are right for some and badly wrong for others.

## Further Reading

- **What do you mean by "Event-Driven"?** (Martin Fowler, martinfowler.com) — the
  essential disambiguation of the four things people call "event-driven": event
  notification, event-carried state transfer, event sourcing, and CQRS. Read it
  first so you know which one you actually want.
- **Enterprise Integration Patterns** (Gregor Hohpe & Bobby Woolf) — the canonical
  catalog of messaging patterns (publish/subscribe, message channels, dead-letter
  channel, idempotent receiver). The vocabulary and the patterns this chapter is
  built on.
- **microservices.io — Saga, Transactional Outbox, and Domain Event patterns** (Chris
  Richardson) — precise, practical write-ups of the exact patterns that make
  event-driven systems reliable, especially the transactional outbox and sagas for
  multi-step workflows.
- **Designing Data-Intensive Applications** (Martin Kleppmann), Chapter 11 (Stream
  Processing) — the rigorous treatment of delivery semantics, at-least-once
  processing, ordering, and why "exactly-once" is subtler than it sounds. The
  foundation for reasoning about brokers correctly.

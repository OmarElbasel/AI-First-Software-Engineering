# Monolith, Modular Monolith & Microservices

## Introduction

Where the last three chapters were about how to organize code *within* a
deployable unit, this one is about how many deployable units there should be.
It is a single spectrum, from one process to many:

- A **monolith** is one deployable unit: one codebase, one process, usually one
  database. You build it, test it, and ship it as a whole.
- A **modular monolith** is still one deployable unit, but internally divided
  into well-bounded modules that communicate through defined interfaces rather
  than reaching into each other's internals. It keeps the monolith's operational
  simplicity while gaining most of the organizational benefits usually
  attributed to microservices.
- **Microservices** are many independently deployable units, each owning its own
  data, communicating over the network. They enable independent deployment,
  independent scaling, and team autonomy — at the cost of becoming a distributed
  system, with everything that entails.

These three are taught together because teaching one without the others produces
exactly the cargo-cult conclusions the industry spent the last decade regretting.
The overwhelming lesson of that decade is the theme of this chapter: **start on
the left, and move right only when a specific force requires it.** The modular
monolith is the underrated middle that most growing products should live in for
a long time, and microservices are a powerful tool with a large bill that too
many teams paid before they had the revenue for it.

This is also where architecture stops being purely about code and starts being
about operations — the first chapter in this stage whose decisions show up in
your deployment pipeline, your on-call rotation, and your cloud bill.

## Why It Matters

The choice of topology is close to a one-way door (Stage 1, Chapter 04). Merging
services back into a monolith is possible but rare and painful; splitting a
monolith is a project. So the cost of getting this wrong is high, and it is
usually paid in one of two directions.

Distribute too early and you buy a distributed system's entire cost before you
have its benefits: the network fails in ways function calls do not, transactions
that were one `COMMIT` become multi-step sagas, a single logical operation
becomes a chain of remote calls that can each time out, and every service needs
its own deployment, monitoring, logging, and on-call. A three-person team running
eight microservices spends its time on operations and distributed-systems
debugging instead of on the product — a self-inflicted wound that has killed real
companies.

Distribute too late, or never enforce internal boundaries, and a monolith rots
into a big ball of mud: everything imports everything, one team's change breaks
another's, the whole thing must be deployed together and tested together, and
scaling means scaling all of it whether or not the bottleneck is one small part.

The modular monolith exists precisely to defer that choice while staying healthy:
enforced internal boundaries give you maintainability and the *option* to extract
a service later, without paying for distribution until a real force demands it.
This is Stage 1, Chapter 04's reversibility thinking applied at the largest scale
— keep the expensive door closed until you know which way you need to walk
through it.

The AI dimension is unusually strong here. Assistants were trained through the
peak of the microservices hype cycle, so their default instinct is to
*over-distribute* — propose separate services for problems that want function
calls — and, when they do generate services, to produce distributed monoliths
that share databases and make chatty synchronous calls. Left unguided, an
assistant will happily scaffold the worst of both worlds.

## Mental Model

The three options are points on one spectrum, and each step right trades
simplicity for independence:

```
   MONOLITH            MODULAR MONOLITH           MICROSERVICES
   one unit            one unit, hard             many units, each
                       internal boundaries        independently deployable

   ┌───────────┐       ┌───────────────┐          ┌────┐ ┌────┐ ┌────┐
   │ everything│       │ ┌──┐┌──┐┌──┐  │          │svc │ │svc │ │svc │
   │ together  │       │ │M1││M2││M3│  │          │ +DB│ │ +DB│ │ +DB│
   │  one DB   │       │ └──┘└──┘└──┘  │          └────┘ └────┘ └────┘
   └───────────┘       │   one DB      │            └──network──┘
                       └───────────────┘

   simplest            simple to run,             independent deploy/scale/team
   to build & run      modular inside             — but now a DISTRIBUTED SYSTEM

   ◄──────────────  simplicity          independence  ──────────────►
   ◄──────────────  low ops cost        high ops cost ──────────────►

   DEFAULT: start left. Move right only when a specific force requires it.
```

Three ideas make the spectrum usable.

**The deciding question is deployment independence, not code cleanliness.** You
can have beautifully modular code in a monolith (that is a modular monolith) and
a horrible tangle spread across services (that is a distributed monolith). The
thing microservices actually give you is the ability to deploy, scale, and staff
each service independently. If you do not need that independence, you do not need
microservices — no matter how clean the boundaries are.

**A shared database turns microservices into a distributed monolith.** The single
most important rule in the whole chapter: services must own their data. The
moment two services read and write the same tables, they are coupled at the data
layer, must change together, and you have paid the full network-and-operations
cost of distribution while keeping all the coupling of a monolith. This is the
worst quadrant, and it is where under-guided teams (and AI) most often land.

**Boundaries decay without enforcement.** A modular monolith's boundaries are not
protected by the network — nothing stops one module from importing another's
internals except discipline and tooling. Without enforcement (facades,
import-linting, schema separation), a modular monolith degrades into a plain
monolith, and the option value you were preserving evaporates.

A working definition:

> **These are points on a spectrum from one deployable unit to many, trading
> operational simplicity for deployment independence. The default is a monolith
> that grows into a modular monolith; microservices are justified only by a
> specific need for independent deployment, scaling, or team ownership — and only
> if each service owns its data.**

## Production Example

**Invoicely** is now a **modular monolith**. It ships as one FastAPI application
against one PostgreSQL database, but internally it is divided into modules —
`invoicing`, `payments`, `reconciliation`, `notifications` — with the
feature-based boundaries from Chapter 02 promoted into *enforced* module
boundaries. Each module exposes a public interface and hides its internals;
modules never import each other's repositories or query each other's tables.

This is the right place for Invoicely to be. One deployment, one database, one
on-call rotation — the operational simplicity a small team needs — with internal
structure clean enough that the modules can be understood, changed, and tested
independently, and *extracted* later if a real force appears.

And one appears. The reconciliation module is CPU-heavy: large accounts trigger
matching runs that pin a worker for minutes, and during month-end close those
runs starve the rest of the API of capacity. Invoicely needs to scale
reconciliation *independently* of the web tier — a genuine, specific force, not a
fashion. So reconciliation, and only reconciliation, becomes a separate service.
The other modules stay in the monolith, because nothing about them needs
independent deployment or scaling.

The payoff of the earlier chapters lands here: because reconciliation was already
a clean module with a defined interface (Chapters 02 and 03), extraction is a
tractable change rather than an archaeology project. We will look at the module
boundary that makes this possible, and what the boundary becomes when it turns
into a network hop.

## Folder Structure

```
# MODULAR MONOLITH — one deployable unit, hard internal boundaries
app/
├── modules/
│   ├── invoicing/
│   │   ├── public.py         # THE module's public interface (facade)
│   │   ├── _service.py       # internals — underscore-private by convention
│   │   ├── _repository.py
│   │   └── _models.py        # owns the `invoices` tables; no one else touches them
│   ├── payments/
│   │   ├── public.py
│   │   └── _...
│   ├── reconciliation/
│   │   ├── public.py         # the interface that will survive extraction
│   │   └── _...
│   └── notifications/
│       └── ...
├── core/                     # cross-cutting: config, db, auth, errors
└── main.py                   # mounts each module's routes

# AFTER EXTRACTION — reconciliation becomes its own service
deploy/
├── docker-compose.yml        # invoicely-api, reconciliation-svc, postgres, broker
services/
├── invoicely-api/            # the monolith, minus reconciliation internals
│   └── modules/reconciliation/public.py   # now an HTTP CLIENT, same interface
└── reconciliation-svc/       # the extracted service, its OWN database
    ├── app/
    └── Dockerfile
```

Why this shape:

- **`modules/`** replaces `features/` to signal that these boundaries are
  enforced, not just organizational. Each module is a unit that could become a
  service.
- **`public.py`** is the module's entire contract. Everything else in the module
  is internal (the leading underscore is a convention teams enforce with
  import-linting). Other modules import only from `public.py`.
- **Each module owns its tables.** `invoicing` owns the invoice tables;
  `payments` owns the payment tables. No module reads another's tables directly —
  cross-module data goes through the public interface. This is what makes the
  single database safe *and* keeps extraction possible, because a module's data
  can move with it.
- **After extraction**, the module boundary becomes a service boundary: the
  monolith keeps `reconciliation/public.py`, but its implementation changes from
  an in-process call to an HTTP client. Callers do not change, because they only
  ever depended on the interface.

## Implementation

**A module's public interface (`modules/payments/public.py`).** The facade is the
only thing other modules may use. It exposes operations in domain terms and hides
the repository, the models, and the tables behind it.

```python
from dataclasses import dataclass
from decimal import Decimal
from app.modules.payments._repository import PaymentRepository


@dataclass(frozen=True)
class PaymentSummary:
    id: int
    amount: Decimal
    status: str


class PaymentsModule:
    """Public interface of the payments module. Other modules use ONLY this."""

    def __init__(self, repo: PaymentRepository) -> None:
        self._repo = repo

    async def get_summary(self, payment_id: int) -> PaymentSummary | None:
        payment = await self._repo.get(payment_id)
        if payment is None:
            return None
        return PaymentSummary(id=payment.id, amount=payment.amount, status=payment.status)
```

**Crossing a module boundary the right way.** When invoicing needs payment data,
it calls the payments facade — it does not import `payments._repository` or query
the payment tables.

```python
# modules/invoicing/_service.py
from app.modules.payments.public import PaymentsModule  # the interface, not internals


class InvoiceService:
    def __init__(self, payments: PaymentsModule, repo: "InvoiceRepository") -> None:
        self._payments = payments
        self._repo = repo

    async def mark_paid(self, invoice_id: int, payment_id: int) -> None:
        summary = await self._payments.get_summary(payment_id)   # across the boundary
        if summary is None or summary.status != "succeeded":
            raise ValidationError("Payment is not settled.")
        invoice = await self._repo.get(invoice_id)
        invoice.status = "paid"
```

**Enforcing the boundary.** Discipline is not enough; the rule is checked by a
tool. An import-linter contract makes a cross-boundary import into internals a CI
failure:

```ini
# importlinter.ini  — boundaries enforced in CI, not by hope
[importlinter]
root_package = app

[importlinter:contract:module-privacy]
name = Modules may only import each other's public interface
type = forbidden
source_modules =
    app.modules.invoicing
    app.modules.payments
    app.modules.reconciliation
forbidden_modules =
    app.modules.invoicing._repository
    app.modules.payments._repository
    app.modules.reconciliation._repository
```

**Extraction: the boundary becomes a network hop.** Because callers depend only
on `reconciliation/public.py`, extracting the service means swapping the facade's
implementation from an in-process call to an HTTP client that satisfies the *same*
interface. The invoicing and payments modules do not change.

```python
# modules/reconciliation/public.py  — AFTER extraction, now an HTTP client
import httpx
from app.modules.reconciliation.contracts import ReconciliationReport


class ReconciliationModule:
    """Same interface as before; now backed by a remote service instead of
    an in-process handler. Callers are unaffected by the move."""

    def __init__(self, client: httpx.AsyncClient, base_url: str) -> None:
        self._client = client
        self._base_url = base_url

    async def run(self, account_id: int) -> ReconciliationReport:
        resp = await self._client.post(
            f"{self._base_url}/internal/reconcile", json={"account_id": account_id},
            timeout=30.0,   # the network can fail now — timeouts are mandatory
        )
        resp.raise_for_status()
        return ReconciliationReport(**resp.json())
```

**The deployment topology (`deploy/docker-compose.yml`).** Two services, and —
critically — the reconciliation service has *its own database*. It does not share
Invoicely's.

```yaml
services:
  invoicely-api:
    build: ../services/invoicely-api
    environment:
      DATABASE_URL: postgresql+asyncpg://app@main-db/invoicely
      RECONCILIATION_URL: http://reconciliation-svc:8000
    depends_on: [main-db, reconciliation-svc]

  reconciliation-svc:
    build: ../services/reconciliation-svc
    deploy:
      replicas: 4            # scaled INDEPENDENTLY of the API — the whole point
    environment:
      DATABASE_URL: postgresql+asyncpg://recon@recon-db/reconciliation
    depends_on: [recon-db]

  main-db:
    image: postgres:16
  recon-db:                  # SEPARATE database — no shared data, no distributed monolith
    image: postgres:16
```

The extraction bought exactly one thing — the ability to run four reconciliation
workers without quadrupling the whole application — and cost exactly what
distribution always costs: a network call that can now fail (hence the timeout
and `raise_for_status`), a second database and deployment to operate, and
eventual consistency between the two data stores. That trade was worth it *for
reconciliation* because the scaling force was real. Making the same trade for
invoicing or notifications, which have no such force, would have been pure loss.
Note what did *not* happen: the two services do not share a database, and the
call is a single coarse-grained operation, not a chatty back-and-forth. That
restraint is the line between microservices and a distributed monolith.

## Engineering Decisions

Four decisions determine where you land on the spectrum and whether the move is
healthy.

### Where do you start?

**Options:** (1) monolith; (2) modular monolith; (3) microservices.

**Trade-offs:** a monolith is the least work and can rot without discipline.
Microservices-first pays the entire distributed-systems tax before you have the
scale, team, or operational maturity to benefit — and while the domain is still
changing, which is the worst time to freeze boundaries into network contracts.
The modular monolith adds only the cost of internal discipline.

**Recommendation:** start with a monolith and impose modular boundaries as it
grows — i.e., a modular monolith. Never start with microservices unless you are a
large organization with multiple teams and mature operations and a domain you
already understand. Fowler's "MonolithFirst" (Further Reading) is the empirical
observation behind this: almost every successful microservices system was
extracted from a monolith, and almost every microservices-first system struggled.

### How do you draw the boundaries?

**Options:** (1) by technical layer (an "auth service," a "database service");
(2) by business capability / bounded context.

**Trade-offs:** technical boundaries produce services that must all be touched
for any feature and that chatter constantly across the network — the distributed
big ball of mud. Capability boundaries (invoicing, payments, reconciliation)
align each module or service with a cohesive slice of the business, minimizing
cross-boundary chatter, but require real domain understanding to get right.

**Recommendation:** draw boundaries around business capabilities / bounded
contexts (the DDD idea from Chapter 02), never around technical layers. Good
boundaries are the whole game: they determine coupling, and coupling determines
whether extraction is a swap (Invoicely's reconciliation) or a rewrite.

### Shared database, or database per unit?

**Options:** (1) all modules/services share one database and its tables; (2) each
owns its own data.

**Trade-offs:** in a *modular monolith*, a single shared database is fine — and
simpler — *provided each module owns its tables* and no module reads another's
directly (a shared engine, private tables; schema-per-module makes this
explicit). In *microservices*, sharing a database at all is the cardinal sin: it
recouples the services into a distributed monolith. Database-per-service enables
independence but forces eventual consistency and cross-service queries through
APIs or events.

**Recommendation:** modular monolith — one database, one table-owner per module.
Microservices — one database per service, no exceptions, with cross-service data
via API calls or events (Chapter 07). If you are not willing to split the data,
you are not willing to do microservices; stay a modular monolith.

### When do you extract a service?

**Options:** (1) extract modules into services proactively; (2) extract only when
a specific force appears.

**Trade-offs:** proactive extraction distributes before you know the boundaries
are right and pays the tax early. Force-driven extraction keeps the monolith
until a concrete need — independent scaling, independent deploy cadence, team
autonomy, fault isolation — justifies the one module's promotion, at the cost of
doing the extraction work under some pressure.

**Recommendation:** extract only when a specific, named force requires it, and
extract only the module that has the force — as Invoicely extracted
reconciliation for independent scaling and left everything else in the monolith.
"Microservices are more modern" is not a force. Write the force and the decision
into an ADR ([`templates/adr.md`](../../templates/adr.md)); if you cannot name the
force, do not extract.

## Trade-offs

Each point on the spectrum is right for some contexts and wrong for others.

**The monolith** is the simplest thing that works: one build, one deploy, atomic
releases, trivial transactions, one thing to monitor, and the easiest local
development and debugging. Its costs arrive with scale — it scales only as a whole,
locks you to one stack, couples every team's deploys together, and rots into a big
ball of mud without internal discipline. Right for early-stage products, small
teams, and unproven domains; increasingly strained as the team and codebase grow.

**The modular monolith** keeps all of the monolith's operational simplicity while
adding enforced internal boundaries, buying maintainability, team parallelism, and
the option to extract services later. Its cost is discipline: the boundaries are
not enforced by the network, so they require facades, linting, and review to
survive, and it is still a single deploy-and-scale unit. Right for the large
majority of growing products — the default this chapter argues most teams should
sit in far longer than they think.

**Microservices** buy independent deployment, independent scaling, team autonomy,
technology heterogeneity, and fault isolation. The bill is a distributed system:
the network is unreliable and slow (the fallacies of distributed computing, in
Further Reading), there are no easy cross-service transactions (you get eventual
consistency and sagas), every service multiplies operational load (deploy,
monitor, log, trace, secure, discover), local development and testing get much
harder, and end-to-end latency rises. Right for large organizations with multiple
autonomous teams, genuine independent-scaling needs, and the operational maturity
to run distributed systems — and wrong, often ruinously, for teams without those.

The meta-point: **you must be "this tall" to ride microservices.** The height is
measured in team count, operational maturity, and domain stability — not in
ambition. Most teams asking "should we do microservices?" should build a modular
monolith and revisit when a specific force appears.

## Common Mistakes

**Microservices-first.** Starting with distributed services before you have the
scale, team, domain understanding, or operations to support them — paying the
entire tax up front for benefits you cannot yet use. Fix: start with a modular
monolith; extract when a force appears.

**The distributed monolith.** Services so coupled they must be deployed together —
via a shared database, chatty synchronous call chains, or shared internal models —
so you carry all of distribution's cost and none of its independence. Fix: each
service owns its data and exposes a coarse API; if services must deploy together,
they should not be separate services.

**Sharing a database across services.** The most common road to the distributed
monolith: two services reading and writing the same tables. Fix: database per
service; cross-service data through APIs or events (Chapter 07).

**Boundaries on the wrong axis.** Splitting by technical concern (an "auth
service," a "notification-database service") rather than business capability,
producing chatty, deploy-coupled services. Fix: boundaries follow bounded contexts
and business capabilities.

**Letting the modular monolith rot.** Declaring modules but not enforcing their
boundaries, so imports creep across them until it is a plain monolith again and the
extraction option is gone. Fix: enforce boundaries with facades and import-linting
in CI — boundaries you do not enforce do not exist.

## AI Mistakes

Assistants learned architecture during the microservices hype cycle, and it
shows: **their default is to over-distribute, and when they distribute they
produce distributed monoliths.** Both failures give you the costs of distribution
without the benefits. The countermeasure is to make the modular monolith the
stated default and to enforce data and boundary rules mechanically, because the
assistant will not respect them on its own.

### Claude Code: over-distributing by default

Asked to "design the architecture" or add a substantial capability, Claude Code
tends to reach for separate services, message brokers, and a `docker-compose` full
of components — reproducing the microservices-heavy shape of its training data for
a problem that a single application would handle better. It manufactures
distribution nobody needed.

**Detect:** a multi-service design, HTTP or queue calls between things that could
be function calls, or a broker introduced for a small app. If the proposed system
has more services than the team has people, be suspicious.

**Fix:** set the default explicitly:

> Default to a modular monolith — one deployable unit with enforced internal
> module boundaries. Do not propose separate services or a message broker unless I
> state a specific need for independent scaling or deployment, and if you do,
> justify the force.

### GPT: the shared database and the chatty distributed monolith

When GPT-family models do generate microservices, they routinely have the services
share a database, query each other's tables, or make fine-grained synchronous call
chains — producing a distributed monolith. It looks like microservices and couples
like a monolith.

**Detect:** multiple services pointing at the same `DATABASE_URL`, a service
reading another service's tables, or a single request fanning out into many
synchronous inter-service calls.

**Fix:** state the data rule, which is the one that matters:

> Each service must own its own database; no shared tables and no service querying
> another's database. Cross-service data goes through a coarse-grained API or
> events. Avoid chatty synchronous call chains between services.

### Cursor: dissolving module boundaries through the data layer

In a modular monolith, Cursor tends to satisfy a need for another module's data by
querying that module's tables directly or importing its internal repository —
because those symbols are reachable — rather than going through the module's public
interface. Each such shortcut couples the modules at the data layer and quietly
destroys the ability to extract either one.

**Detect:** a query in one module that reads or joins another module's tables, or
an import of another module's `_repository`/`_models` rather than its `public`
interface. Cross-module table access is the fingerprint.

**Fix:** require the interface and enforce it in tooling:

> Never read another module's tables or import its internals. Get the data through
> that module's public interface (`modules/<name>/public.py`). This is enforced by
> the import-linter contract in CI; keep it green.

## Best Practices

**Start with a monolith; grow into a modular monolith.** Adopt microservices only
when a specific force — independent scaling, independent deploy cadence, team
autonomy, fault isolation — demands it and you can afford the operations. For most
products, the modular monolith is the destination, not a waypoint.

**Draw boundaries around business capabilities.** Modules and services follow
bounded contexts (Chapter 02), never technical layers. Good boundaries minimize
cross-boundary chatter and make later extraction a swap instead of a rewrite.

**Give every module (and service) sole ownership of its data.** In a modular
monolith, one table-owner per module and no cross-module table access; in
microservices, one database per service and no sharing. Cross-boundary data flows
through interfaces or events (Chapter 07). A shared database is a distributed
monolith waiting to happen.

**Enforce boundaries mechanically.** Public facades plus import-linting in CI plus
schema separation — because a boundary that depends on discipline alone will decay,
and an assistant will decay it faster. Program to the module interface so a module
can be extracted without changing its callers.

**Write the topology decisions down, and default the AI to a monolith.** Record
extraction decisions and their forces as ADRs
([`templates/adr.md`](../../templates/adr.md)), and state "modular monolith,
single deployable unit" as the default in `CLAUDE.md`
([`templates/claude-md-starter.md`](../../templates/claude-md-starter.md)) so
assistants stop reaching for services you do not need.

## Anti-Patterns

**Microservices-First (Premature Distribution).** Distributing before scale, team,
ops, or domain stability justify it — paying the full tax for unusable benefits.
The tell: more services than engineers, and standups dominated by
infrastructure rather than product.

**The Distributed Monolith.** Services that must deploy together because they share
a database, share models, or chatter synchronously — all the cost of distribution,
none of the independence. The worst quadrant on the spectrum. The tell: you cannot
deploy one service without coordinating the others.

**The Shared Database.** Multiple services reading and writing common tables,
coupling them at the data layer beneath the API. The tell: one `DATABASE_URL`
across services, or a migration in one service breaking another.

**Entity/CRUD Services.** Services split per data entity (a "Customer service"
that is just CRUD on customers) rather than per capability, producing chatty
cross-service calls for every real operation. The tell: doing one business action
requires synchronous calls to three services.

**The Rotting Modular Monolith.** Declared modules with unenforced boundaries, so
cross-module imports accumulate until it is an ordinary big ball of mud and the
extraction option is gone. The tell: `public.py` files that everyone bypasses, and
no import-linter in CI.

## Decision Tree

"Which topology should this system use, and should I split this part out?"

```
Are you early-stage / small team / still learning the domain?
│
├── YES ──► MONOLITH. Keep it modular internally, but one deployable unit.
│           Do not distribute. Full stop.
│
└── NO (growing product, want maintainability + future options)
    │
    └──► MODULAR MONOLITH. Enforce module boundaries (facades, import-linting,
         one table-owner per module). This is the default for most products.
         │
         Is there a SPECIFIC force for a given module?
         (independent scaling · independent deploy cadence · team autonomy ·
          fault isolation)  — AND the ops maturity to run distributed systems?
         │
         ├── NO ──► Stay a modular monolith. "More modern" is not a force.
         │
         └── YES ──► Extract THAT module into a service (not all of them).
             │
             Is its boundary already clean? (public interface, owns its data,
             no other module reads its tables)
             │
             ├── NO ──► Fix the boundary first. You cannot cleanly extract a
             │          tangle; make it a proper module, then extract.
             │
             └── YES ─► Extract it: its own database, a coarse API or events,
                        timeouts on every call. Callers depend on the interface,
                        so they don't change. Record the force in an ADR.
```

## Checklist

### Implementation Checklist

- [ ] Each module exposes a public interface; internals are private and imported by no other module.
- [ ] Cross-module access goes through the public interface, never another module's tables or internals.
- [ ] Each module owns its tables; there is exactly one table-owner per module.
- [ ] Boundary rules are enforced in CI (import-linter or equivalent), not left to discipline.
- [ ] Any extracted service owns its own database and is called with explicit timeouts.
- [ ] Inter-service communication is coarse-grained (few, meaningful calls), not chatty.

### Architecture Checklist

- [ ] Module/service boundaries follow business capabilities, not technical layers.
- [ ] The system is as far left on the spectrum as its actual needs allow (monolith → modular monolith → microservices).
- [ ] No two services share a database or tables.
- [ ] Every service extraction is justified by a named force, recorded in an ADR.
- [ ] Cross-boundary transactions are handled by eventual consistency / sagas, not distributed synchronous transactions.

### Code Review Checklist

- [ ] No new cross-module import of internals or cross-module table access (watch AI diffs).
- [ ] No shared-database or chatty-synchronous coupling introduced between services.
- [ ] New services/modules were justified, not added reflexively (guard against AI over-distribution).
- [ ] Remote calls have timeouts and handle partial failure.
- [ ] The change did not bypass a module's public interface.

### Deployment Checklist

- [ ] Each service has its own deploy pipeline, health check, and rollback path (see [`checklists/production-readiness.md`](../../checklists/production-readiness.md)).
- [ ] Each service's database has independent backups and migration process.
- [ ] Service-to-service calls degrade gracefully when a dependency is down (timeouts, fallbacks).
- [ ] Observability spans service boundaries (correlation IDs / distributed tracing), so a request can be followed across services.
- [ ] The number of deployable units matches the team's operational capacity to run them.

## Exercises

**1. Define and enforce a module boundary.** Take the Invoicely modules and give
one of them (say, `payments`) a proper public interface, making its repository and
models internal. Then add an import-linter contract that fails CI if another module
imports its internals. The artifact is the `public.py`, the config, and a
screenshot or log of the contract catching a deliberate violation — proof the
boundary is enforced, not aspirational.

**2. Plan an extraction as an ADR.** Write the ADR for extracting the
reconciliation module into a service: the force justifying it, the data it owns and
how it moves, the communication mechanism (sync API vs events), the new failure
modes (timeouts, partial failure, eventual consistency), and the rollback. The
artifact is the ADR ([`templates/adr.md`](../../templates/adr.md)) — the point is
that writing it honestly sometimes reveals the force isn't strong enough yet.

**3. Diagnose a distributed monolith.** Given a set of services where some share a
database and some make chatty synchronous call chains (sketch one, or have an
assistant generate a "microservices" design from a naive prompt), identify every
point of hidden coupling and describe how you would fix each — separate the data,
coarsen the APIs, or merge services that should never have been split. The artifact
is the annotated diagnosis.

## Further Reading

- **Building Microservices, 2nd edition** (Sam Newman, O'Reilly) — the definitive,
  refreshingly sober treatment, including extensive material on when *not* to use
  microservices and why to start with a monolith. If you read one book on this
  chapter, this is it.
- **MonolithFirst** and **MicroservicePremium** (Martin Fowler, martinfowler.com) —
  two short essays making the empirical case to start with a monolith and to treat
  microservices as a premium you pay only when the complexity is justified by scale.
- **Modular Monoliths** (Simon Brown — talk and writing) — the clearest argument
  for the underrated middle of the spectrum, and practical guidance on enforcing
  module boundaries so a monolith stays modular.
- **Fallacies of Distributed Computing** (Peter Deutsch, James Gosling, et al.) —
  the eight false assumptions ("the network is reliable," "latency is zero,"
  "bandwidth is infinite," …) that make distributed systems hard. Read this before
  you split anything; it is the cost side of the microservices ledger in one page.

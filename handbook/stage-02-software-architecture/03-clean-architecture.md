# Clean Architecture

## Introduction

Clean Architecture is a way of structuring an application so that its business
rules depend on nothing, and everything else depends on them. Frameworks, the
database, the web, the UI — all the things most codebases treat as the
foundation — become *details* that plug into the outside of a stable domain
core. Its single governing rule, the **Dependency Rule**, is that source-code
dependencies point only inward, toward the domain, and never outward toward
infrastructure.

This is the same family as Hexagonal Architecture (Ports and Adapters) and the
Onion Architecture; they differ in vocabulary and diagrams but share one idea:
invert the usual dependency so the domain does not know about the database — the
database knows about the domain. It is the deliberate opposite of Chapter 01's
layered architecture, where dependencies flow *down* toward the database. Here
they flow *in* toward the business rules.

This chapter comes with a warning written into the handbook's Constitution:
**do not reach for Clean Architecture on every project.** It buys real, valuable
properties — a framework-independent, testable domain — at a real, substantial
cost in indirection and ceremony. For most CRUD-shaped applications that cost
dwarfs the benefit, and layered or feature-based organization is the right
answer. The engineering skill this chapter teaches is therefore two-sided: how
to build it *and* how to know when not to. We will apply it to the one part of
Invoicely that earns it — the reconciliation engine — and explicitly refuse it
for the parts that don't.

## Why It Matters

Consider what a layered application is coupled to. In Chapter 01, the service
layer depended on the repository, which depended on SQLAlchemy and PostgreSQL.
The dependency chain runs from your business logic *down* into infrastructure —
so your business rules import, and are shaped by, your database library. Change
the persistence approach and the ripples travel up; test a business rule and you
drag a database along; the domain and the framework are welded together.

For most applications, that welding is fine — the app *is* mostly CRUD over a
database, and pretending otherwise is over-engineering. But some applications
have a genuinely complex, genuinely valuable core of business logic — the kind
that is the reason the company exists — and for that core, the coupling is a
liability:

- **The valuable logic outlives its infrastructure.** Invoicely's matching
  algorithm is the differentiator; it should be expressible and testable without
  reference to which database or web framework happens to be underneath it this
  year.
- **Complex logic needs isolated testing.** Business rules with many branches and
  invariants are exactly what you want to test exhaustively — and you cannot,
  cheaply, if every test needs a database. A framework-independent core is
  fast-testable by construction.
- **Infrastructure is genuinely a detail for that core.** Whether reconciliation
  reads from Postgres, a queue, or a fake in a test is irrelevant to *how
  matching works*. Clean Architecture makes that irrelevance structural.

The AI dimension is subtle and specific here. An assistant will readily produce
code that *looks* like Clean Architecture — the folders, the interfaces, the
names — while silently violating the Dependency Rule, because the natural pull of
generation is toward the concrete thing in hand (the ORM model, the framework
type) rather than toward an abstraction. "Looks clean" and "obeys the dependency
rule" are different claims, and only the second one is worth anything.

## Mental Model

The entire architecture is one rule about which way dependencies point:

```
   LAYERED (Ch 01): dependencies point DOWN, toward the database

     Service ──► Repository ──► SQLAlchemy ──► PostgreSQL
     (your business rules depend on your infrastructure)


   CLEAN: dependencies point IN, toward the domain

     ┌───────────────────────────────────────────────────┐
     │  FRAMEWORKS & DRIVERS   (FastAPI, SQLAlchemy, PG)   │
     │   ┌─────────────────────────────────────────────┐  │
     │   │  INTERFACE ADAPTERS  (controllers, repos)     │  │
     │   │   ┌─────────────────────────────────────┐    │  │
     │   │   │  APPLICATION  (use cases + PORTS)     │    │  │
     │   │   │    ┌─────────────────────────────┐    │    │  │
     │   │   │    │  DOMAIN (entities + rules)    │    │    │  │
     │   │   │    │  pure Python, knows nothing   │    │    │  │
     │   │   │    └─────────────────────────────┘    │    │  │
     │   │   └─────────────────────────────────────┘    │  │
     │   └─────────────────────────────────────────────┘  │
     └───────────────────────────────────────────────────┘

     Dependencies point INWARD only. The domain knows nothing.
     The database depends on the domain's interface, not vice versa.
```

The mechanism that makes inward-only dependencies possible is **dependency
inversion**, and it is worth seeing concretely because it is the one genuinely
counter-intuitive move:

```
   The use case needs to load payments. But it must not depend on the database.
   So:

   1. The APPLICATION layer defines a PORT — an interface describing what it
      needs:   "give me the unreconciled payments for an account."
   2. The use case depends only on that port (an abstraction it owns).
   3. An ADAPTER in the outer layer IMPLEMENTS the port using SQLAlchemy.

   Result: the arrow is inverted. The SQLAlchemy adapter depends on the
   application's port. The application depends on nothing outward. The database
   is now a plugin to the domain.
```

Two consequences define the discipline:

**The inner layer owns the interface; the outer layer implements it.** The port
(`PaymentRepository`) is defined *with the use case*, not with the database code.
This is what points the dependency inward. If the interface lives in the adapter
layer, you have layered architecture with extra words, and the dependency still
points outward.

**The core speaks only plain Python.** Domain entities are dataclasses, not ORM
models; use cases take and return domain types, not `Request` or Pydantic or
`Session`. The moment a framework type appears in the core's signatures, the core
is no longer framework-independent and the architecture has failed quietly.

A working definition:

> **Clean Architecture inverts dependencies so business rules depend on nothing
> and infrastructure depends on them. Its value is a framework-independent,
> isolately-testable domain core — and its cost is enough indirection that it is
> justified only where that core is complex and valuable.**

## Production Example

**Invoicely's reconciliation engine** is the right — and the *only* — place in
the app to apply this. It is the differentiator (Stage 1, Chapters 02 and 06),
its matching logic is genuinely complex (fuzzy amounts, confidence scoring,
partial payments), and it is the code the team most needs to test exhaustively
and protect from infrastructure churn. Everything Clean Architecture is good at,
reconciliation needs.

The rest of Invoicely does not. Creating an invoice, editing a customer, the
settings page — these are CRUD over a database, and wrapping them in entities,
ports, adapters, and mappers would be pure ceremony (the chapter's central
warning, and Stage 1, Chapter 07's over-engineering). So we apply Clean
Architecture to the reconciliation module and leave the invoices feature as the
feature-folder-with-layers from Chapter 02. A real codebase is allowed to — and
should — use different architectures for parts with different needs.

We will build the "run reconciliation" use case with a pure domain, a port, a
SQLAlchemy adapter, and — the payoff — a test that exercises the whole use case
with no database at all.

## Folder Structure

```
features/reconciliation/
├── domain/                      # INNERMOST — pure business rules, no imports out
│   ├── entities.py              #   Payment, Invoice, Match — plain dataclasses
│   └── matching.py              #   the matching algorithm (the differentiator)
│
├── application/                 # USE CASES + PORTS (interfaces the core owns)
│   ├── ports.py                 #   PaymentRepository, InvoiceRepository (Protocols)
│   └── run_reconciliation.py    #   the use case, depends only on ports
│
├── adapters/                    # OUTER — implement ports, map to infrastructure
│   ├── sqlalchemy_repos.py      #   concrete repos; map ORM <-> domain entities
│   └── api.py                   #   FastAPI controller; wires adapters into the use case
│
└── tests/
    └── test_run_reconciliation.py  # exercises the use case with in-memory fakes
```

Why this shape:

- **`domain/`** is the center and imports nothing from the layers around it —
  not the application layer, not adapters, and above all not SQLAlchemy or
  FastAPI. If you `grep` this folder for `sqlalchemy` or `fastapi` and get a hit,
  the architecture is broken.
- **`application/`** holds the use cases and, critically, the *ports* they depend
  on. The port lives here — with the code that needs it — not in `adapters/`.
  That placement is what inverts the dependency.
- **`adapters/`** is where infrastructure lives: the concrete repositories that
  implement the ports using SQLAlchemy and map between ORM rows and domain
  entities, and the FastAPI controller that assembles a use case and calls it.
  Adapters depend inward (on ports and domain); nothing inward depends on them.
- **`tests/`** can test the use case directly by supplying in-memory
  implementations of the ports — no database, no HTTP. That capability is the
  return on the whole investment.

## Implementation

**The domain (`domain/entities.py`) — pure Python, no framework.** These are not
ORM models. They are the business's concepts, expressed in plain dataclasses that
could run with no database installed.

```python
from dataclasses import dataclass
from decimal import Decimal


@dataclass(frozen=True)
class Payment:
    id: int
    account_id: int
    amount: Decimal
    reference: str


@dataclass(frozen=True)
class Invoice:
    id: int
    account_id: int
    amount: Decimal
    customer_name: str


@dataclass(frozen=True)
class Match:
    invoice_id: int
    payment_id: int
    confidence: float
```

**The ports (`application/ports.py`) — interfaces the core owns.** Python
`Protocol` classes describe *what the use case needs* without naming any
implementation. This is the abstraction the dependency points at.

```python
from typing import Protocol
from app.features.reconciliation.domain.entities import Invoice, Payment


class PaymentRepository(Protocol):
    async def unreconciled_for_account(self, account_id: int) -> list[Payment]: ...
    async def mark_reconciled(self, payment_id: int, invoice_id: int) -> None: ...


class InvoiceRepository(Protocol):
    async def open_for_account(self, account_id: int) -> list[Invoice]: ...
```

**The use case (`application/run_reconciliation.py`) — depends only on ports.**
Note the imports: the domain and the ports, and nothing else. There is no
SQLAlchemy here, no FastAPI, no concrete repository. This code cannot see
infrastructure.

```python
from dataclasses import dataclass
from app.features.reconciliation.application.ports import (
    InvoiceRepository,
    PaymentRepository,
)
from app.features.reconciliation.domain.entities import Match
from app.features.reconciliation.domain.matching import match_payments_to_invoices


@dataclass
class ReconciliationReport:
    matched: int
    needs_review: list[Match]


class RunReconciliation:
    def __init__(
        self, payments: PaymentRepository, invoices: InvoiceRepository
    ) -> None:
        self._payments = payments
        self._invoices = invoices

    async def execute(self, account_id: int) -> ReconciliationReport:
        payments = await self._payments.unreconciled_for_account(account_id)
        invoices = await self._invoices.open_for_account(account_id)

        matches = match_payments_to_invoices(payments, invoices)
        confident = [m for m in matches if m.confidence >= 0.9]
        for m in confident:
            await self._payments.mark_reconciled(m.payment_id, m.invoice_id)

        return ReconciliationReport(
            matched=len(confident),
            needs_review=[m for m in matches if 0.5 <= m.confidence < 0.9],
        )
```

**The adapter (`adapters/sqlalchemy_repos.py`) — implements the port, maps
ORM ↔ domain.** This is where SQLAlchemy is allowed to exist. It implements the
port structurally (no explicit inheritance needed, thanks to `Protocol`) and
translates between database rows and domain entities.

```python
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from app.features.reconciliation.domain.entities import Payment
from app.models.payment import PaymentORM


class SqlAlchemyPaymentRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def unreconciled_for_account(self, account_id: int) -> list[Payment]:
        rows = await self._session.scalars(
            select(PaymentORM).where(
                PaymentORM.account_id == account_id,
                PaymentORM.reconciled_at.is_(None),
            )
        )
        return [
            Payment(id=r.id, account_id=r.account_id, amount=r.amount, reference=r.reference)
            for r in rows
        ]

    async def mark_reconciled(self, payment_id: int, invoice_id: int) -> None:
        await self._session.execute(
            update(PaymentORM)
            .where(PaymentORM.id == payment_id)
            .values(reconciled_at=func.now(), matched_invoice_id=invoice_id)
        )
```

**The controller (`adapters/api.py`) — wires infrastructure into the use case.**
FastAPI lives out here. It constructs the adapters, injects them into the use
case, and translates the domain result into an HTTP response — the only place all
three worlds meet.

```python
from fastapi import APIRouter
from app.core.auth import CurrentAccountDep
from app.core.db import SessionDep
from app.features.reconciliation.adapters.sqlalchemy_repos import (
    SqlAlchemyInvoiceRepository,
    SqlAlchemyPaymentRepository,
)
from app.features.reconciliation.application.run_reconciliation import RunReconciliation

router = APIRouter(prefix="/reconciliation", tags=["reconciliation"])


@router.post("/run")
async def run(session: SessionDep, account: CurrentAccountDep) -> dict:
    use_case = RunReconciliation(
        payments=SqlAlchemyPaymentRepository(session),
        invoices=SqlAlchemyInvoiceRepository(session),
    )
    report = await use_case.execute(account.id)
    await session.commit()
    return {"matched": report.matched, "needs_review": len(report.needs_review)}
```

**The payoff (`tests/test_run_reconciliation.py`) — the whole use case, no
database.** Because the use case depends only on ports, a test supplies
in-memory fakes and exercises the real matching logic at full speed.

```python
from decimal import Decimal
from app.features.reconciliation.application.run_reconciliation import RunReconciliation
from app.features.reconciliation.domain.entities import Invoice, Payment


class InMemoryPayments:
    def __init__(self, payments: list[Payment]) -> None:
        self._payments = payments
        self.reconciled: list[tuple[int, int]] = []

    async def unreconciled_for_account(self, account_id: int) -> list[Payment]:
        return [p for p in self._payments if p.account_id == account_id]

    async def mark_reconciled(self, payment_id: int, invoice_id: int) -> None:
        self.reconciled.append((payment_id, invoice_id))


class InMemoryInvoices:
    def __init__(self, invoices: list[Invoice]) -> None:
        self._invoices = invoices

    async def open_for_account(self, account_id: int) -> list[Invoice]:
        return [i for i in self._invoices if i.account_id == account_id]


async def test_confident_match_is_reconciled() -> None:
    payments = InMemoryPayments([Payment(1, 42, Decimal("100.00"), "INV-1")])
    invoices = InMemoryInvoices([Invoice(9, 42, Decimal("100.00"), "Acme")])

    report = await RunReconciliation(payments, invoices).execute(account_id=42)

    assert report.matched == 1
    assert invoices  # unchanged
    assert payments.reconciled == [(1, 9)]
```

That test runs in microseconds, needs no PostgreSQL, and exercises the actual
business logic. Reproducing this confidence for complex reconciliation rules in
the layered architecture of Chapter 01 would require a database fixture for every
case — which is exactly the friction that makes complex logic under-tested in
practice. *That* is what the indirection bought. If a feature would not benefit
from this kind of test, it does not need this architecture.

## Engineering Decisions

Four decisions govern Clean Architecture, and the first is by far the most
important.

### Does this part of the system warrant Clean Architecture at all?

**Options:** (1) apply it across the whole application; (2) apply it only to the
complex, valuable domain core; (3) don't use it.

**Trade-offs:** applying it everywhere imposes entities, ports, adapters, and
mappers on CRUD that has no business rules to protect — enormous ceremony for no
benefit, and the single most common way this architecture is misused. Applying it
to the core only concentrates the cost where the payoff is. Not using it at all
is correct for genuinely simple applications.

**Recommendation:** apply it surgically, to the complex core, and nowhere else —
reconciliation gets it, invoices do not. The Constitution's rule is not a
suggestion: Clean Architecture on CRUD is over-engineering, and a codebase that
uses it uniformly has almost always applied it where it isn't earned. Decide per
module, using the "would isolated tests and framework-independence actually help
here?" test.

### Where do the ports live?

**Options:** (1) define the port interface in the application/domain layer;
(2) define it in the adapter/infrastructure layer.

**Trade-offs:** the whole architecture depends on this. A port defined with the
use case (option 1) points the dependency inward — the adapter depends on the
core. A port defined in the adapter layer (option 2) leaves the dependency
pointing outward and gives you ordinary layering wearing interface vocabulary.

**Recommendation:** the inner layer owns the port, always. This is the crux of
dependency inversion and the thing most often gotten wrong, including by AI. The
use case declares what it needs; infrastructure conforms.

### Separate domain entities from ORM models?

**Options:** (1) use ORM models as the domain entities; (2) keep plain domain
entities and map to/from ORM in the adapter.

**Trade-offs:** reusing ORM models is less code and immediately couples the
domain to SQLAlchemy — which defeats the entire purpose while still looking like
Clean Architecture. Separate entities cost a mapping layer (the adapter
translates rows to dataclasses and back) but keep the core genuinely
framework-free and testable without a database.

**Recommendation:** separate them — an ORM model as a domain entity is not Clean
Architecture, it is layered architecture with a misleading folder name. The
mapping cost is the price of admission; if you are unwilling to pay it, you did
not need this architecture and should use Chapter 01's approach honestly.

### How many layers, and how strict?

**Options:** (1) the full four Clean circles with presenters, mappers, and
DTO-per-layer; (2) a pragmatic three-part hexagonal core (domain, use
cases + ports, adapters).

**Trade-offs:** the full ceremony is faithful to the diagrams and often more
structure than a web application needs, with DTOs mapped three times on the way
in and out. The pragmatic hexagonal version keeps the essential inversion
(ports and adapters) without the presenter/DTO proliferation.

**Recommendation:** the pragmatic hexagonal core for most applications that need
this at all — domain, use cases with ports, and adapters. Add more structure only
if a concrete pain (e.g. multiple very different delivery mechanisms) demands it.
The goal is the Dependency Rule, not the number of boxes in the diagram.

## Trade-offs

Clean Architecture buys genuine, valuable properties at a genuine, substantial
cost, and the balance tips only for a minority of code.

**The indirection is real and permanent.** Ports, adapters, mappers, and the
separation of domain entities from ORM models mean more files, more types, and
more hops for every change. A one-field addition can touch the entity, the ORM
model, the mapper, and possibly the port. For code without complex rules to
protect, this is dead weight — Stage 1, Chapter 07's accidental complexity,
imposed by architecture.

**The "swap the database" benefit is usually illusory.** Clean Architecture is
often justified by "we could switch from Postgres to MongoDB without touching the
domain." You almost never will, and building for that imagined future is
speculative generality (Chapter 07). Do not justify the architecture on
database-swapping — justify it, if at all, on testability and protecting complex
domain logic, which are benefits you actually collect.

**It has a steep learning curve and is easy to fake.** Teams new to it produce
code that has the folders and the interface names but violates the Dependency
Rule — ORM models as entities, ports in the wrong layer, framework types in the
core. The architecture provides no value unless the rule is actually obeyed, and
obeying it requires understanding *why* the arrows point inward, not just copying
the diagram.

**When to use it, and when not.** Use it for a complex, valuable, long-lived
domain core that you need to test exhaustively in isolation and protect from
infrastructure churn — Invoicely's reconciliation, a pricing engine, a rules
engine, a risk model. Do *not* use it for CRUD applications, simple domains,
short-lived projects, or small teams without the appetite for the ceremony —
which is to say, most software. When unsure, start with layered or feature-based
(Chapters 01–02) and extract a clean core later *if* a genuinely complex domain
emerges; retrofitting the core is cheaper than carrying the ceremony everywhere
from day one.

## Common Mistakes

**Applying it to everything.** Wrapping simple CRUD in the full apparatus of
entities, ports, adapters, and mappers, drowning trivial features in ceremony.
Fix: apply Clean Architecture only to the complex domain core; use simpler
architectures elsewhere in the same codebase.

**ORM models as domain entities.** Using SQLAlchemy models as the "entities," so
the domain imports the ORM and the framework independence — the entire point — is
lost while the folders still say `domain/`. Fix: domain entities are plain
dataclasses; the adapter maps ORM rows to them.

**Ports in the wrong layer.** Defining the repository interface in the adapter
layer, leaving the dependency pointing outward. Fix: the port lives with the use
case that needs it; the adapter implements it. The interface's location *is* the
architecture.

**Framework types in the core.** Passing `Request`, Pydantic models, or the
SQLAlchemy `Session` into use cases or domain code, contaminating the
framework-free center. Fix: convert to domain types at the boundary; the core's
signatures mention only plain Python.

**Anemic use cases.** Use cases that only forward to a repository with no domain
logic — all the ceremony of Clean Architecture with none of the substance, which
means the domain didn't warrant it. Fix: if the use cases are pure pass-throughs,
you have proven this module is CRUD; drop the architecture and use Chapter 01's.

## AI Mistakes

Every failure here is the same failure: **the assistant produces code that looks
like Clean Architecture but violates the Dependency Rule**, because the natural
direction of generation is toward the concrete object in hand — the ORM model, the
framework type, the real repository — not toward the abstraction the rule
demands. The countermeasure is to review for dependency *direction* explicitly,
never trusting that the right folder names mean the right arrows.

### Claude Code: dependencies pointing the wrong way

Asked to implement a use case, Claude Code will often import the concrete
SQLAlchemy repository directly into the use case, or call the database from
within domain code — because wiring to the real thing is the path of least
resistance, and inverting a dependency through a port is a deliberate,
non-obvious move. The result runs and looks structured while the core is coupled
straight to infrastructure.

**Detect:** any import of an adapter, SQLAlchemy, or a concrete repository inside
`domain/` or `application/`. `grep` the inner layers for `sqlalchemy`/`adapters`
— any hit is a violation.

**Fix:** state the rule and the mechanism:

> The use case must depend only on a port (a Protocol) defined in the application
> layer, never on a concrete repository or SQLAlchemy. Define the interface with
> the use case; implement it in an adapter. Dependencies point inward only.

### GPT: the ORM model masquerading as the domain entity

GPT-family models frequently make the "entity" a SQLAlchemy (or Pydantic) model
and build the use case around it — producing something that has `domain/`,
`use_cases/`, and `ports/` folders but whose core is welded to the ORM. It looks
clean and silently breaks the one rule that matters.

**Detect:** the domain "entity" is a SQLAlchemy model or Pydantic model; use
cases manipulate ORM instances; there is no mapping step in the adapter.

**Fix:** require the separation explicitly:

> Domain entities must be plain dataclasses with no SQLAlchemy or Pydantic base.
> The adapter maps between ORM rows and domain entities. The use case must never
> touch an ORM object.

### Cursor: leaking framework types inward

Editing in an adapter or controller and reaching into the use case, Cursor tends
to pass whatever object is in hand across the boundary — the FastAPI `Request`,
a Pydantic body model, the `Session` — into use-case or domain signatures,
because those are the symbols available at the call site. Each leak contaminates
the framework-free core.

**Detect:** framework types (`Request`, `AsyncSession`, Pydantic models)
appearing in the parameters or return types of use cases or domain functions.
The core's signatures should mention only plain Python and domain types.

**Fix:** convert at the boundary, and keep the core clean:

> The controller converts framework objects into domain types before calling the
> use case. Do not pass `Request`, `Session`, or Pydantic models into the
> application or domain layer — those layers see only domain entities and plain
> values.

## Best Practices

**Apply it to the complex core only.** Identify the small part of the system with
genuinely complex, valuable business rules and give *that* the Clean Architecture
treatment; leave the CRUD as layered or feature-based. A codebase with mixed
architectures, matched to each part's needs, is a sign of judgment, not
inconsistency.

**Keep the domain pure Python.** Entities are dataclasses; the domain imports no
framework and no infrastructure. The test is mechanical: the inner layers contain
no `import sqlalchemy`, no `import fastapi`.

**Let the inner layer own the interfaces.** Ports are defined with the use cases
that depend on them; adapters implement them from outside. This placement is what
inverts the dependency — get it wrong and you have layering with extra vocabulary.

**Use Protocols for ports and fakes for tests.** Python's `Protocol` gives you
ports without inheritance coupling, and in-memory implementations let you test use
cases with no database — which is the concrete payoff you should be able to point
to. If you cannot write that database-free test, the architecture is not actually
in place.

**Justify it by testability, not database-swapping.** Adopt it to test complex
logic in isolation and protect a valuable domain, not for a database migration you
will never do. Write the justification down (an ADR,
[`templates/adr.md`](../../templates/adr.md)) so the next engineer knows why the
ceremony exists — and can remove it if the domain turns out to be simpler than
believed.

## Anti-Patterns

**Clean Architecture Everywhere.** The whole app in entities, ports, adapters, and
mappers, including features that are plain CRUD — the Constitution's named
warning. It multiplies every trivial change by the full ceremony. The tell: a
two-field settings entity with its own port, adapter, and mapper.

**The ORM Entity.** Domain "entities" that are SQLAlchemy models, coupling the
core to persistence while displaying Clean Architecture folders. The dependency
rule is violated invisibly. The tell: `domain/entities.py` imports `sqlalchemy`.

**Wrong-Way Ports.** Interfaces defined in the infrastructure layer so the
dependency still points outward — layered architecture cosplaying as hexagonal.
The tell: the repository interface lives next to its SQLAlchemy implementation,
not with the use case.

**The Anemic Use Case.** Use cases that only forward to repositories with no
orchestration or rules — the ceremony without the substance, proving the module
never needed the architecture. The tell: every use case is a one-line delegation.

**Framework Leakage.** Web, ORM, or serialization types appearing in the domain
or application layers, quietly ending the framework independence the architecture
exists to provide. The tell: `Request` or `Session` in a use case signature.

## Decision Tree

"Should I use Clean Architecture for this part of the system?"

```
Does this part have a COMPLEX, VALUABLE domain core — real business rules,
worth testing exhaustively, that should outlive infrastructure choices?
│
├── NO  (CRUD, simple domain, thin logic, short-lived) 
│        └──► Do NOT use Clean Architecture. Use layered (Ch 01) or
│             feature-based (Ch 02). The ceremony would be pure cost.
│
└── YES (e.g. a matching engine, pricing engine, rules/risk model)
     │
     Apply Clean Architecture to THIS module only:
     │
     ├─ Domain entities = plain dataclasses (no ORM, no framework).
     ├─ Use cases depend only on PORTS (Protocols) they own.
     ├─ Adapters implement the ports and map ORM <-> domain, on the outside.
     ├─ Controllers convert framework objects to domain types at the boundary.
     └─ Prove it: a use-case test that runs with in-memory fakes, no database.
     │
     Can you write that database-free test?
     ├── YES ──► The architecture is real. Keep the rest of the app simpler.
     └── NO ───► The Dependency Rule is being violated somewhere. Find the
                 inward-pointing arrow that shouldn't exist and fix it — or
                 conclude this module didn't need Clean Architecture.
```

## Checklist

### Implementation Checklist

- [ ] Domain entities are plain dataclasses; the domain layer imports no framework or ORM.
- [ ] Ports are defined in the application layer, with the use cases that depend on them.
- [ ] Use cases depend only on ports; they import no adapter, no SQLAlchemy, no FastAPI.
- [ ] Adapters implement the ports and perform the ORM ↔ domain mapping.
- [ ] Controllers convert framework objects to domain types before calling a use case.
- [ ] A use-case test runs with in-memory fake adapters and no database.

### Architecture Checklist

- [ ] Every source dependency points inward; nothing in the core references the outer layers.
- [ ] This architecture is applied only to the complex domain core, not to CRUD features.
- [ ] Domain entities and ORM models are separate types.
- [ ] The decision to use Clean Architecture here is recorded (ADR) with its justification.
- [ ] The justification is testability / domain protection — not a hypothetical database swap.

### Code Review Checklist

- [ ] No inner-layer file imports an adapter, SQLAlchemy, or a concrete repository (grep the core).
- [ ] No domain "entity" is secretly an ORM or Pydantic model (watch AI diffs especially).
- [ ] No framework type leaked into a use-case or domain signature.
- [ ] Ports are owned by the inner layer, not the adapter layer.
- [ ] Use cases contain real orchestration/rules, not pure pass-throughs.

*(A Deployment Checklist is not applicable — Clean Architecture is a
code-organization concern. Deployment topology is Chapter 04.)*

## Exercises

**1. Invert a dependency.** Take the reconciliation use case and restructure it
so the use case depends on a `PaymentRepository` port (a Protocol) it owns, with a
SQLAlchemy adapter implementing it. Then write a test that exercises the use case
with an in-memory fake repository and no database. The artifact is the code plus
the passing database-free test — concrete proof the Dependency Rule holds.

**2. Find the wrong-way arrow.** Take a module that claims to be Clean
Architecture (yours, or one an assistant generates from a naive "build this with
Clean Architecture" prompt) and audit it for violations: ORM-as-entity, ports in
the adapter layer, framework types in the core, inner layers importing outward.
The artifact is the list of violations with the inward-pointing arrow each one
breaks and the fix.

**3. The "should we?" call.** Given three parts of a product — a CRUD invoices
feature, a complex reconciliation/matching engine, and a static settings page —
decide for each whether it warrants Clean Architecture, and justify the decision
in two or three sentences each. The artifact is the three decisions; the point is
that the honest answer is "yes" for exactly one of them, which is the judgment
this whole chapter is about.

## Further Reading

- **The Clean Architecture** (Robert C. Martin — the 2012 blog post and the 2017
  book) — the source of the Dependency Rule and the concentric circles. Read the
  blog post first for the rule; read the book for the reasoning and the many
  worked cases.
- **Hexagonal Architecture (Ports and Adapters)** (Alistair Cockburn) — the
  original and, for most web applications, the cleaner formulation of the same
  idea: an application core with ports, and adapters that plug in. Often a better
  mental model than the full four circles.
- **Architecture Patterns with Python** (Harry Percival & Bob Gregory, free at
  cosmicpython.com) — the definitive Python treatment of ports, adapters, and
  dependency inversion, with exactly this stack. The chapters on the repository
  pattern and the service layer show how to build (and how not to over-build) the
  structure in this chapter.
- **The Onion Architecture** (Jeffrey Palermo) — the sibling formulation, worth
  reading to see that Clean, Hexagonal, and Onion are one family with one rule
  (dependencies point inward), so you recognize the pattern under any of its
  names.

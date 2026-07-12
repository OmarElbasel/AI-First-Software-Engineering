# Service Layer & Repository Pattern

## Introduction

The previous chapters kept using two building blocks without examining them: a
*service* that holds business operations, and a *repository* that handles data
access. This chapter is about those two patterns themselves — what genuinely
belongs in each, how to design them well, and, crucially, when a repository is
buying you nothing but ceremony over your ORM.

- The **service layer** defines an application's boundary as a set of
  operations — "create invoice," "void invoice," "run reconciliation" — and
  coordinates the work each one requires: applying rules, orchestrating domain
  objects, calling repositories, and owning the transaction boundary. It is the
  answer to "what can this application *do*?"
- The **repository pattern** provides a collection-like interface for accessing
  domain objects, hiding the details of how they are stored. It lets the rest of
  the code work with `invoices.get(id)` instead of SQL, and it is what makes a
  service testable without a database.

They are taught together because they are two halves of one structure: services
orchestrate, repositories persist, and a *unit of work* (in our stack, the
SQLAlchemy session) ties a set of repository operations into one transaction.
The chapter's sharpest lesson is a warning, though — both patterns are
frequently applied as pure ritual, a generic CRUD repository wrapping an ORM
that already does everything the repository claims to add, or a "service" that is
just a pass-through. Knowing when these patterns earn their place is as important
as knowing how to build them, and it is exactly the judgment an AI assistant will
not supply for you.

## Why It Matters

The service layer and repository together decide where two things live: your
business rules, and your data access. Get that placement right and the codebase
has an obvious home for every change; get it wrong and rules scatter into route
handlers and queries, transactions blur, and the same "can this invoice be
voided?" logic appears in three places and disagrees with itself.

A well-designed service layer gives you:

- **One place for each use case**, reachable from every entry point (the API, a
  background job, a CLI) so business rules cannot drift between them — the exact
  problem that motivated the layered chapter.
- **A clear transaction boundary**: one use case, one unit of work, committed in
  one place, so partial writes and ambiguous "who commits?" bugs disappear.

A well-designed repository gives you:

- **Persistence ignorance** for the code above it, so the service reads like
  business logic, not like database plumbing.
- **Testability**: a fake in-memory repository lets you test the service's rules
  at full speed with no database (the payoff you saw in Chapter 03).
- **A home for complex queries**, so a gnarly "find overdue invoices with unpaid
  reminders" query lives in one named method instead of being copy-pasted.

But — and this is the part most treatments skip — a modern ORM already provides
much of what the repository pattern was invented to give you. SQLAlchemy's
session *is* a unit of work and an identity map; `session.get(Invoice, id)` is
already a persistence abstraction. A repository that only forwards to the session
adds indirection and subtracts nothing. So the pattern's value is real but
conditional, and applying it reflexively is a common way to make a simple app
more complex for no benefit (Stage 1, Chapter 07).

The AI dimension follows directly: assistants reach for the *generic* CRUD
repository and the catch-all service because those shapes saturate their training
data, and they scatter transaction and rule concerns because the patterns'
discipline is not something generation naturally imposes. The patterns pay off
only when they carry domain meaning and a clear boundary — neither of which an
assistant will give you unprompted.

## Mental Model

The three collaborators and their responsibilities:

```
   ┌───────────────────────────────────────────────────────────┐
   │  SERVICE  — the use case                                    │
   │  · applies business rules / orchestrates domain objects     │
   │  · owns the TRANSACTION boundary (one use case = one commit) │
   │  · calls repositories; never writes SQL                     │
   └───────────────────────┬───────────────────────────────────┘
                            │ uses
             ┌──────────────┴──────────────┐
             ▼                             ▼
   ┌─────────────────────┐      ┌─────────────────────┐
   │  REPOSITORY          │      │  REPOSITORY          │   one per AGGREGATE,
   │  (invoices)          │      │  (payments)          │   not per table
   │  · collection-like   │      │  · domain-meaningful │
   │    access to a domain│      │    query methods     │
   │    aggregate         │      │    (find_overdue)    │
   │  · query + persist   │      │  · NO business rules │
   │    ONLY. no commits. │      │  · NO commits        │
   └─────────┬───────────┘      └──────────┬──────────┘
             └──────────── UNIT OF WORK ─────┘
                    (the DB session/transaction —
                     in SQLAlchemy, the Session itself)
```

Three ideas make this precise:

**Each collaborator has exactly one job.** The service decides *what happens* and
*when to commit*. The repository decides *how to load and store* a domain
aggregate. The unit of work decides *what is atomic*. A business rule inside a
repository, or a `commit()` inside a repository, or a query inside a service, is
a job in the wrong place.

**Repositories are per aggregate, not per table, and speak the domain.** A
repository corresponds to an aggregate root (an `Invoice` and its line items
treated as one unit), and its methods express domain questions —
`find_overdue(account_id)` — not database operations — `filter(status='overdue')`.
The moment a repository exposes generic `filter`/`query`, it has stopped hiding
persistence and started leaking it.

**The repository must earn its place over the ORM.** Because SQLAlchemy's session
is already a unit of work with an identity map, a repository justifies itself only
when it adds something the raw session does not: a domain-meaningful interface,
encapsulation of complex queries, a testing seam (fakes), or a Clean Architecture
port (Chapter 03). If it only forwards to `session.get`, it is ceremony.

A working definition:

> **The service layer holds use cases and owns transactions; the repository
> gives collection-like, domain-meaningful access to an aggregate and hides
> persistence. Both are worth adding only when they carry real business meaning —
> a repository that merely wraps the ORM, or a service that merely forwards, is
> cost without benefit.**

## Production Example

**Invoicely's** invoicing module gives us both patterns with genuine substance.
The use cases — create, send, and void an invoice — carry real rules and real
transaction boundaries, so a service earns its place. The repository earns its
place too, because voiding needs a domain query ("is there a settled payment
against this invoice?") and because the team wants to unit-test the voiding rules
without a database.

We will build the invoice repository with domain-meaningful methods (not a
generic CRUD base), a service that owns the transaction boundary and orchestrates
the rules, and a domain method on the `Invoice` model itself — because "can this
invoice be voided?" is a rule intrinsic to an invoice, and belongs on the invoice,
not in the service. That split — intrinsic rules on the model, orchestration in
the service — is the heart of designing these patterns well, and the antidote to
both the anemic-model and god-service failure modes.

## Folder Structure

```
modules/invoicing/
├── public.py               # module facade (Chapter 04)
├── _models.py              # Invoice aggregate — with intrinsic domain methods
├── _repository.py          # InvoiceRepository — per-aggregate, domain queries
├── _service.py             # InvoiceService — use cases + transaction boundary
└── _schemas.py             # DTOs
core/
└── unit_of_work.py         # the transaction boundary abstraction (optional)
```

Why this shape:

- **`_models.py`** holds the aggregate *with behavior* — the `Invoice` knows the
  rules that are intrinsic to being an invoice (which state transitions are
  legal). This keeps the model from being an anemic data bag.
- **`_repository.py`** is one repository for the invoice aggregate, exposing
  domain queries. It is not a generic `BaseRepository[T]`, and it does not exist
  for entities that don't need one.
- **`_service.py`** holds the use cases and owns the transaction boundary. It
  orchestrates; it does not re-implement rules that belong on the model, and it
  is not a god service spanning unrelated aggregates.
- **`core/unit_of_work.py`** is optional. In many SQLAlchemy apps the session
  *is* the unit of work and an explicit UoW class is unnecessary ceremony; it
  earns its place only when you want to make the transaction boundary explicit
  and swappable (e.g., for the Clean Architecture core of Chapter 03).

## Implementation

**Intrinsic rules on the aggregate (`_models.py`).** "Can this invoice be voided?"
depends only on the invoice's own state, so it lives on the invoice. This is what
keeps the model from being anemic.

```python
from datetime import datetime
from decimal import Decimal
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.errors import ConflictError
from app.models.base import Base


class Invoice(Base):
    __tablename__ = "invoices"

    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int] = mapped_column(index=True)
    status: Mapped[str] = mapped_column(default="draft")
    total: Mapped[Decimal]
    voided_at: Mapped[datetime | None] = mapped_column(default=None)

    def can_be_voided(self) -> bool:
        return self.status in {"draft", "sent"}

    def void(self) -> None:
        if not self.can_be_voided():
            raise ConflictError(f"An invoice in status '{self.status}' cannot be voided.")
        self.status = "void"
        self.voided_at = datetime.now(tz=UTC)
```

**A domain-meaningful repository (`_repository.py`).** Its methods answer domain
questions and it hides SQLAlchemy. Note what is absent: no generic `filter`, no
`query()` returning a leaked query object, no `commit()`, and no business rules.

```python
from datetime import date
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.modules.invoicing._models import Invoice


class InvoiceRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    def add(self, invoice: Invoice) -> None:
        self._session.add(invoice)

    async def get(self, invoice_id: int, account_id: int) -> Invoice | None:
        stmt = select(Invoice).where(
            Invoice.id == invoice_id, Invoice.account_id == account_id
        )
        return await self._session.scalar(stmt)

    async def find_overdue(self, account_id: int, as_of: date) -> list[Invoice]:
        stmt = select(Invoice).where(
            Invoice.account_id == account_id,
            Invoice.status == "sent",
            Invoice.due_date < as_of,
        )
        return list(await self._session.scalars(stmt))
```

`find_overdue` is why this repository earns its place: it encapsulates a real
query behind a domain-meaningful name, so the concept "overdue" is defined once. A
repository with only `add` and `get` wrapping `session.get` would not — that would
be the thin-wrapper anti-pattern, and using the session directly would be more
honest.

**The service owns the use case and the transaction boundary (`_service.py`).** It
orchestrates, delegates intrinsic rules to the model, and is the single place a
commit happens for the use case.

```python
from app.core.errors import NotFoundError
from app.modules.invoicing._repository import InvoiceRepository
from app.modules.payments.public import PaymentsModule


class InvoiceService:
    def __init__(self, repo: InvoiceRepository, payments: PaymentsModule) -> None:
        self._repo = repo
        self._payments = payments

    async def void_invoice(self, account_id: int, invoice_id: int) -> None:
        invoice = await self._repo.get(invoice_id, account_id)
        if invoice is None:
            raise NotFoundError("Invoice not found.")

        # An intrinsic rule → asked of the model. Orchestration → in the service.
        invoice.void()  # raises ConflictError if the state transition is illegal
```

```python
# in the route (presentation layer) — the transaction boundary is committed once
@router.post("/invoices/{invoice_id}/void", status_code=204)
async def void_invoice(
    invoice_id: int, service: InvoiceServiceDep, session: SessionDep, account: CurrentAccountDep
) -> None:
    await service.void_invoice(account.id, invoice_id)
    await session.commit()   # ONE commit, at the edge of the use case
```

**Testing the service with a fake repository.** Because the service depends on the
repository interface, its rules test with an in-memory fake and no database — the
concrete payoff of the pattern.

```python
class InMemoryInvoiceRepository:
    def __init__(self, invoices: list[Invoice]) -> None:
        self._by_id = {i.id: i for i in invoices}

    def add(self, invoice: Invoice) -> None:
        self._by_id[invoice.id] = invoice

    async def get(self, invoice_id: int, account_id: int) -> Invoice | None:
        inv = self._by_id.get(invoice_id)
        return inv if inv and inv.account_id == account_id else None


async def test_cannot_void_a_paid_invoice() -> None:
    paid = Invoice(id=1, account_id=42, status="paid", total=Decimal("100"))
    service = InvoiceService(InMemoryInvoiceRepository([paid]), payments=FakePayments())
    with pytest.raises(ConflictError):
        await service.void_invoice(account_id=42, invoice_id=1)
```

Observe the division of labor across the whole example: the *route* owns the
transaction boundary (one commit), the *service* orchestrates the use case, the
*model* enforces the rule intrinsic to an invoice (`can_be_voided`), and the
*repository* answers domain queries and persists — nothing commits but the edge,
nothing holds rules but the model and service, nothing queries but the repository.
Each of the failure modes in the rest of this chapter is a violation of exactly
one of those boundaries.

## Engineering Decisions

Five decisions define how — and whether — to use these patterns.

### Do you need a repository at all?

**Options:** (1) use the ORM/session directly in the service; (2) introduce a
repository.

**Trade-offs:** using the session directly is less code and perfectly honest for
simple CRUD, since the session already provides a unit of work and identity map —
but it couples the service to SQLAlchemy and makes database-free testing harder. A
repository adds a testing seam, a domain-meaningful interface, and a home for
complex queries, at the cost of indirection and a risk of degenerating into a thin
wrapper.

**Recommendation:** add a repository when it earns its place — complex queries to
encapsulate, a real need to test services with fakes, or a Clean Architecture port
(Chapter 03). For simple CRUD with trivial queries, use the ORM directly; wrapping
`session.get` in a repository to satisfy a diagram is ceremony (Stage 1, Chapter
07). Decide per aggregate, not as a blanket rule.

### Repository granularity?

**Options:** (1) a generic `Repository[T]` with `get/list/filter`; (2) one
repository per table; (3) one repository per aggregate root with domain methods.

**Trade-offs:** the generic repository is the least code and the worst design — it
leaks persistence (`filter` is a query concern) and provides no domain meaning.
Per-table repositories fragment aggregates that should be loaded and saved as a
unit. Per-aggregate repositories with domain-meaningful methods align with how the
domain actually thinks, at the cost of writing real methods instead of inheriting
generic ones.

**Recommendation:** one repository per aggregate root, with methods that express
domain questions (`find_overdue`), never a generic base with `filter`. The generic
repository is a named anti-pattern for good reason: it is the ORM, re-exported
through a layer that hides nothing.

### What goes in the service versus the domain model?

**Options:** (1) all logic in services, models as data bags (anemic domain model /
transaction script); (2) intrinsic rules on the model, orchestration in the
service (rich domain model).

**Trade-offs:** the anemic approach is simple and adequate for CRUD-shaped apps,
and it is the pragmatic default much of the industry uses — but for a domain with
real invariants it scatters related rules and leaves the model unable to protect
itself. The rich approach keeps intrinsic rules with the data they govern, which
is powerful for complex domains but easy to overdo (fat models with orchestration
that belongs in a service).

**Recommendation:** put rules *intrinsic to one aggregate* on the model
(`invoice.void()`), and *orchestration across aggregates or external systems* in
the service. Anemic models are acceptable for genuine CRUD; treat them as a smell
only when the domain has invariants worth protecting. This is a real, unsettled
debate (Fowler and Evans in Further Reading); the split above is the pragmatic
middle.

### Who owns the transaction boundary?

**Options:** (1) commit inside repositories; (2) commit inside services; (3) commit
at the edge (route / an explicit unit of work) around a whole use case.

**Trade-offs:** committing in repositories scatters boundaries and causes partial
writes mid-operation — the worst option. Committing in services keeps the boundary
with the use case but can nest awkwardly when one service calls another. Committing
at the edge (or via an explicit UoW) makes one use case exactly one transaction,
cleanly.

**Recommendation:** one use case, one transaction, committed at the edge of the use
case — the route or an explicit unit of work — never inside a repository. Make the
boundary obvious and singular; the most common transaction bug is not knowing where
`commit` happens.

### Service granularity?

**Options:** (1) one god service for the whole app; (2) one service per method;
(3) one service per aggregate/feature.

**Trade-offs:** the god service becomes a thousand-line dumping ground with no
cohesion. A service per method fragments related use cases and multiplies wiring. A
service per aggregate/feature groups cohesive use cases together.

**Recommendation:** one cohesive service per aggregate or feature —
`InvoiceService` handles invoice use cases and nothing else. Split by cohesion
(Chapter 04's boundaries), so a service is the operations on one part of the
domain, neither everything nor a single method.

## Trade-offs

Both patterns are valuable conditionally, and both have a ceremony failure mode.

**The repository can duplicate the ORM.** A modern ORM already gives you a unit of
work, an identity map, and a persistence abstraction. A repository that only
forwards to the session adds a layer and hides nothing — pure indirection. The
pattern pays off only when it carries domain meaning, encapsulates real queries,
or provides a testing/port seam; otherwise using the ORM directly is the simpler,
more honest choice.

**The service layer can become procedural sprawl.** Pushed too far toward
transaction-script, services accumulate every rule as a procedure and the domain
model degrades into anemic data bags. For complex domains this scatters logic that
wants to live together; the cost of the service layer is the ongoing discipline of
deciding what belongs on the model instead.

**Explicit Unit of Work is often unnecessary.** The classic UoW pattern is worth
formalizing when you need an explicit, swappable transaction boundary — but in a
straightforward SQLAlchemy app the session already is a unit of work, and adding a
UoW class on top is ceremony. Add it for the Clean Architecture core or genuine
multi-repository atomicity, not by default.

**When to skip both.** A small CRUD application with trivial queries and no complex
rules is well served by thin routes calling the ORM directly (Chapter 01's simple
end of the spectrum). Introducing services and repositories there is
over-engineering. Add them as business logic and query complexity actually grow —
which, for a real product, they will.

## Common Mistakes

**The generic repository.** A `BaseRepository[T]` with `get/list/filter/create`,
inherited everywhere — it leaks query concerns, provides no domain meaning, and is
just the ORM with extra steps. Fix: per-aggregate repositories with
domain-meaningful methods; no generic `filter`.

**The thin-wrapper repository.** A repository whose methods only forward to
`session.get`/`session.add` with nothing added, existing to satisfy a layer
diagram. Fix: if it adds no query encapsulation, testing seam, or port, use the ORM
directly and drop the wrapper.

**Business logic in the repository.** Query methods that also decide domain
questions — a repository method that determines whether an invoice may be voided.
Fix: repositories only query and persist; rules go on the model or in the service.

**Committing inside repositories.** `session.commit()` buried in a repository
method, scattering transaction boundaries and causing partial writes. Fix: one
commit at the edge of the use case; repositories never commit.

**The god service and the anemic model together.** One giant service holding every
rule while models are pure data bags — logic with no cohesion and a domain that
cannot protect itself. Fix: cohesive per-aggregate services, with intrinsic rules
moved onto the models.

## AI Mistakes

Every failure here is the assistant reaching for the most common training-data
shape — the generic CRUD repository, the catch-all service — and scattering the
transaction and rule boundaries the patterns exist to keep sharp. These patterns
only pay off with domain meaning and a single clear transaction boundary, and an
assistant supplies neither by default. Review for *where the boundaries are*, not
just whether the code works.

### Claude Code: the generic CRUD repository

Asked for a repository, Claude Code very often generates a generic
`BaseRepository[T]` with `get`, `list`, `create`, `update`, `delete`, and a
`filter` method — because generic-repository scaffolding is ubiquitous in its
training data. It looks reusable and it leaks persistence while hiding nothing,
giving you the ORM back with an extra layer.

**Detect:** a generic typed base repository, a `filter(**kwargs)` or `query()`
method, or repositories that expose ORM query objects. Any repository that could
serve any entity is the tell.

**Fix:** require per-aggregate, domain-meaningful repositories:

> Do not create a generic base repository. Write one repository per aggregate with
> methods named for domain questions (e.g. `find_overdue`), that return domain
> objects and never expose queries, filters, or the session. If a repository would
> only wrap `session.get`, use the ORM directly instead.

### GPT: business rules migrating into the repository

GPT-family models tend to put domain decisions inside repository methods — a
`void_invoice` on the repository that checks the status and decides whether the
transition is allowed — blurring the line between "how we store data" and "what the
rules are." The repository stops being about persistence and starts holding
business logic that belongs on the model or in the service.

**Detect:** conditionals with domain meaning inside repository methods; repository
methods named for use cases (`void_invoice`) rather than for access
(`get`, `find_overdue`); a repository that does anything but query and persist.

**Fix:** state the boundary:

> Repositories only query and persist. Business rules — including which state
> transitions are legal — go on the domain model or in the service, never in the
> repository. Keep repository methods about data access only.

### Cursor: commits scattered across the layers

Editing inside a service or repository and needing to persist, Cursor tends to add
a `session.commit()` right there for convenience, because it is the local way to
make the change stick. Over time commits appear in repositories and mid-service,
transaction boundaries blur, and a single logical operation can partially commit
before it fails.

**Detect:** `commit()` calls inside repositories, or multiple commits within one
request/use case, or a service committing partway through an operation. More than
one commit per use case is the fingerprint.

**Fix:** insist on a single boundary:

> There is one transaction boundary per use case, committed at the edge (the route
> or the unit of work). Never call `commit()` inside a repository, and never commit
> partway through a service operation. Stage all changes and commit once.

## Best Practices

**Add a repository only when it earns its place.** Complex queries to encapsulate,
services to test with fakes, or a Clean Architecture port justify it; wrapping a
trivial `session.get` does not. For simple CRUD, using the ORM directly is honest,
not lazy.

**One repository per aggregate, speaking the domain.** Methods answer domain
questions (`find_overdue`), return domain objects, and never expose `filter`,
queries, or the session. No generic base repository.

**Keep repositories to query-and-persist, and never let them commit.** No business
rules, no transaction management. Rules live on the model (if intrinsic) or in the
service (if orchestration); the transaction is committed once, at the edge of the
use case.

**Keep services cohesive and let them own the use case.** One service per
aggregate/feature, holding orchestration and the transaction boundary, delegating
intrinsic rules to the model. Neither a god service nor a service per method.

**Choose the domain-model richness deliberately.** Anemic models with
transaction-script services are fine for CRUD; move intrinsic rules onto the model
for domains with real invariants. Decide on purpose, and write the choice into the
conventions (`CLAUDE.md`) so it — and the AI — stay consistent.

## Anti-Patterns

**The Generic Repository.** `Repository[T]` with `get/list/filter`, reused for
every entity — leaks persistence, carries no domain meaning, and is the ORM with a
wrapper. The tell: a repository that could serve any table equally well.

**The Thin-Wrapper Repository.** Pure pass-through methods over the session, added
to satisfy a layer diagram, hiding nothing. The tell: every repository method is a
one-line forward to `session`.

**Business Logic in the Repository.** Rules and state-transition decisions inside
data-access code. The tell: a repository method named for a use case, or containing
domain conditionals.

**The Committing Repository.** Repositories that call `commit()`, scattering
transaction boundaries and enabling partial writes. The tell: `commit` appears
anywhere but the edge of a use case.

**The God Service + Anemic Model.** One enormous service holding all logic while
models are behavior-free data bags — no cohesion above, no self-protection below.
The tell: an `InvoiceService` that also does payments and reporting, over models
with no methods.

## Decision Tree

"Do I need these patterns here, and how do I design them?"

```
REPOSITORY — do I need one for this aggregate?
│
Complex queries to encapsulate, OR need to test services with fakes,
OR a Clean Architecture port?
│
├── NO  ──► Use the ORM/session directly. A wrapper would be ceremony.
└── YES ──► One repository per AGGREGATE ROOT.
            · methods named for domain questions (find_overdue), return domain objects
            · query + persist ONLY — no rules, no commits, no leaked queries/filters


SERVICE — do I need one for this use case?
│
Business rules, orchestration across aggregates, or a transaction to coordinate?
│
├── NO (trivial CRUD) ──► Thin route → ORM. Skip the service.
└── YES ──► One cohesive service per aggregate/feature.
            · owns the use case; transaction committed ONCE at the edge
            · delegates intrinsic rules to the model


LOGIC PLACEMENT — where does this rule go?
│
├── Intrinsic to one aggregate (can this invoice be voided?) ──► on the MODEL
├── Orchestration / spans aggregates / calls external systems ──► in the SERVICE
└── How to load or store data ──────────────────────────────────► in the REPOSITORY
```

## Checklist

### Implementation Checklist

- [ ] Each repository serves one aggregate and exposes domain-meaningful methods, not generic `filter`/`query`.
- [ ] Repositories only query and persist — no business rules, no `commit()`.
- [ ] Intrinsic rules live on the domain model; orchestration lives in the service.
- [ ] Each use case has exactly one transaction boundary, committed at the edge.
- [ ] Services are cohesive (one per aggregate/feature), not god services or per-method.
- [ ] At least one service is unit-tested with an in-memory fake repository (no database).

### Architecture Checklist

- [ ] Every repository earns its place (complex queries, testing seam, or port) — none is a thin ORM wrapper.
- [ ] No generic base repository exists; the ORM is not re-exported through a hollow layer.
- [ ] The domain-model richness (anemic vs rich) was chosen deliberately and is consistent.
- [ ] An explicit Unit of Work exists only where a plain session is genuinely insufficient.
- [ ] The service/repository/model boundaries are documented in `CLAUDE.md`.

### Code Review Checklist

- [ ] No generic repository or leaked query/filter was introduced (watch AI diffs).
- [ ] No business rule migrated into a repository.
- [ ] No `commit()` appears inside a repository, and there is one commit per use case.
- [ ] New services are cohesive, not additions to a god service.
- [ ] A rule was placed on the model vs the service deliberately, matching its scope.

*(A Deployment Checklist is not applicable — these are code-organization patterns.)*

## Exercises

**1. De-genericize a repository.** Take a generic `BaseRepository[T]` (write one,
or have an assistant generate one from "add a repository") and replace it with a
per-aggregate `InvoiceRepository` exposing domain-meaningful methods, then write a
service test that uses an in-memory fake. The artifact is the before/after plus the
database-free test — proof the repository now hides persistence and enables
testing, which the generic version did not.

**2. Place the rules.** Given a set of invoicing rules — "an invoice needs a line
item," "a paid invoice cannot be voided," "sending an invoice emails the customer
and records an event" — decide for each whether it belongs on the model, in the
service, or in the repository, and justify each placement in one sentence. The
artifact is the mapping; the point is internalizing the model/service/repository
division.

**3. Find the boundary violations.** Take a codebase (yours, or the example
extended by an assistant over several prompts) and find every violation from this
chapter: generic repositories, commits in repositories, rules in repositories, god
services, thin wrappers. The artifact is the annotated list with the fix for each —
the exact review skill the AI Mistakes section requires.

## Further Reading

- **Architecture Patterns with Python** (Harry Percival & Bob Gregory, free at
  cosmicpython.com) — the definitive practical treatment of the repository, service
  layer, and unit of work in this exact stack, including the honest discussion this
  chapter echoes about whether a repository is worth it over an ORM. This chapter's
  primary reference.
- **Patterns of Enterprise Application Architecture** (Martin Fowler) — the source
  definitions of Service Layer, Repository, Unit of Work, Transaction Script, and
  Domain Model, and the trade-off between the transaction-script and rich-domain
  approaches the Engineering Decisions section weighs.
- **Domain-Driven Design** (Eric Evans), the chapters on Repositories and
  Aggregates — why a repository corresponds to an aggregate root rather than a
  table, and how aggregates define what is loaded and saved as a unit. The
  conceptual basis for repository granularity.
- **SQLAlchemy documentation — Session Basics and the Unit of Work** (
  docs.sqlalchemy.org) — read this to understand what your ORM already gives you
  (identity map, unit of work, flushing) before deciding what a repository should
  add on top. The best defense against building a hollow abstraction.

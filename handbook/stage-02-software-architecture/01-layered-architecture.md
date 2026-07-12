# Layered Architecture

## Introduction

Layered architecture organizes code by technical responsibility into
horizontal layers, each depending only on the layer beneath it. For a typical
web backend the layers are: a presentation layer that speaks HTTP, a service
layer that holds business logic, a data-access layer that talks to the
database, and the database itself. A request enters at the top, flows down
through the layers, and the response flows back up.

It is the most common backend architecture in existence and the correct
default for most applications, which is exactly why it is the first chapter of
this stage. Before you can reason about whether to organize by feature
(Chapter 02), adopt Clean Architecture (Chapter 03), or split into services
(Chapter 04), you need the baseline that all of those are reacting to. Most
teams should start here and move away only when a concrete pressure justifies
it.

This is also the first *technical* chapter in the handbook — where Stage 1
taught judgment through scenarios, this stage shows judgment through code. The
examples are real, typed, and production-shaped, drawn from the Invoicely
backend you met in Stage 1. The architecture you choose is the frame every one
of those Stage 1 disciplines operates inside: it decides where simplicity
lives, where debt accumulates, and whether the next change is cheap.

## Why It Matters

The alternative to deliberate layers is not "no architecture" — it is the *big
ball of mud*, where HTTP parsing, business rules, and SQL queries all live
together in route handlers, and every concern is tangled with every other.
Such code works in the demo and collapses under change: you cannot test a
business rule without spinning up an HTTP client and a database, you cannot
change the database without touching the API, and a new engineer cannot find
where anything lives because everything lives everywhere.

Layers buy three things that directly determine the cost of every future
change — the maintainability curve from Stage 1, Chapter 08:

- **Separation of concerns.** Each layer has one reason to change. The API
  layer changes when the HTTP contract changes; the service layer when
  business rules change; the repository when persistence changes. A change to
  one rarely disturbs the others.
- **Testability.** Business logic isolated in a service layer can be tested
  with plain function calls — no HTTP server, no database — which makes tests
  fast enough to actually run and honest enough to actually trust.
- **Replaceability.** Because dependencies point in one direction, you can
  replace an implementation in a lower layer (swap a raw SQL repository for an
  ORM one, change databases) without the layers above knowing.

The AI dimension is immediate and practical. Left to its defaults, an
assistant will generate the ball of mud — a fat route handler with validation,
business logic, and database queries all inline — because that is the shape
that dominates tutorials and therefore its training data. A layered
architecture, written down and enforced, gives the assistant a target: "this
goes in the service, that goes in the repository." Architecture is how you
turn an assistant from a mess-generator into a contributor that lands code in
the right place.

## Mental Model

The whole of layered architecture rests on one rule about the direction of
dependencies:

```
        A REQUEST FLOWS DOWN               DEPENDENCIES POINT DOWN
                                           (a layer knows only the one below)

   ┌─────────────────────────────┐
   │   PRESENTATION / API         │   HTTP, routing, (de)serialization,
   │   (FastAPI routers, schemas) │   status codes. No business rules.
   └──────────────┬──────────────┘
                  │ calls
                  ▼
   ┌─────────────────────────────┐
   │   SERVICE / BUSINESS LOGIC   │   Domain rules, orchestration,
   │   (InvoiceService)           │   transactions. Framework-agnostic.
   └──────────────┬──────────────┘
                  │ calls
                  ▼
   ┌─────────────────────────────┐
   │   DATA ACCESS / REPOSITORY   │   Queries, persistence. Hides the
   │   (InvoiceRepository)        │   database behind a plain interface.
   └──────────────┬──────────────┘
                  │ uses
                  ▼
   ┌─────────────────────────────┐
   │   DATABASE (PostgreSQL)      │
   └─────────────────────────────┘

   The iron rule: dependencies point DOWN. The service never imports the
   API layer; the repository never imports the service. A lower layer must
   never know a higher layer exists.
```

Two consequences follow, and they are the whole discipline:

**Each layer has a single kind of responsibility.** If you find yourself
writing an `if` about a business rule inside a route handler, or building an
HTTP response inside a repository, the code is in the wrong layer. The test is:
"what reason would this code have to change?" — and that reason names its
layer.

**Nothing below knows about anything above.** The service layer is written as
if HTTP does not exist; it takes plain arguments and returns plain values or
raises plain exceptions. This is what makes it testable and reusable — the same
service can be called by an HTTP route, a background job, or a CLI, because it
knows about none of them.

A working definition:

> **Layered architecture separates code by technical responsibility into a
> stack where dependencies flow one way — down. Each layer changes for one
> kind of reason, and no layer knows about the layers above it.**

## Production Example

**Invoicely** needs to create an invoice. It sounds trivial — insert a row —
but a production "create invoice" carries real business rules: an invoice must
belong to a customer who has a billing email (you cannot send an invoice with
nowhere to send it); it must have at least one line item; its total is computed
from the line items, never trusted from the client; and a newly created invoice
starts in `draft` status, not `sent`.

These are business rules, and where they live decides the fate of the codebase.
In the ball-of-mud version they sit in the route handler, get duplicated the
next time an invoice is created from a different entry point (the API, a CSV
import, a recurring-billing job), and drift out of sync. In the layered
version they live in exactly one place — `InvoiceService.create_invoice` — and
every entry point goes through it.

We will build this one flow through all four layers, using FastAPI, SQLAlchemy
2.0 (async), and Pydantic v2 — the Invoicely stack. The point is not the invoice
domain; it is watching each concern land in its own layer.

## Folder Structure

```
app/
├── api/                      # PRESENTATION LAYER — HTTP only
│   ├── routes/
│   │   └── invoices.py       #   FastAPI router: parse, delegate, format
│   └── deps.py               #   dependency wiring (session, services)
│
├── services/                 # BUSINESS LOGIC LAYER
│   └── invoice_service.py    #   the business rules, framework-agnostic
│
├── repositories/             # DATA ACCESS LAYER
│   └── invoice_repository.py #   queries and persistence, hides SQLAlchemy
│
├── models/                   # ORM models — the database's shape
│   └── invoice.py            #   SQLAlchemy tables
│
├── schemas/                  # API contracts (DTOs)
│   └── invoice.py            #   Pydantic request/response models
│
└── core/
    ├── config.py             #   settings
    └── errors.py             #   domain exceptions (layer-agnostic)
```

Why each directory exists:

- **`api/`** isolates everything HTTP. If Invoicely ever added a gRPC or CLI
  entry point, only this directory would need a sibling — the layers below are
  untouched, because they know nothing about HTTP.
- **`services/`** is the heart of the application: the business rules, with no
  dependency on FastAPI or SQLAlchemy in its signatures. This is what you unit
  test, and what you reuse across entry points.
- **`repositories/`** concentrates data access so the service never writes a
  query. Swap the persistence strategy here and nothing above changes.
- **`models/`** (ORM) and **`schemas/`** (Pydantic) are kept separate on
  purpose — the database's shape and the API's contract are different things
  that change for different reasons, and coupling them is a mistake we will
  return to. `models/` belongs to the data layer; `schemas/` belongs to the
  API layer.
- **`core/errors.py`** holds domain exceptions that any layer can raise and the
  API layer translates to HTTP — so the service can signal "this customer has
  no billing email" without knowing what a 422 is.

## Implementation

**The API contracts (`schemas/invoice.py`) — presentation layer.** Pydantic
models define what the HTTP boundary accepts and returns. They are not the
database models.

```python
from datetime import datetime
from decimal import Decimal
from pydantic import BaseModel, ConfigDict


class LineItemCreate(BaseModel):
    description: str
    quantity: int
    unit_price: Decimal


class InvoiceCreate(BaseModel):
    customer_id: int
    line_items: list[LineItemCreate]


class InvoiceRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    customer_id: int
    status: str
    total: Decimal
    created_at: datetime
```

**The ORM models (`models/invoice.py`) — data layer.** SQLAlchemy 2.0 typed
models describe the database. Note there is no business logic here; these
describe *shape*, not *rules*.

```python
from datetime import datetime
from decimal import Decimal
from sqlalchemy import ForeignKey, Numeric, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.models.base import Base


class Invoice(Base):
    __tablename__ = "invoices"

    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int] = mapped_column(index=True)
    customer_id: Mapped[int] = mapped_column(ForeignKey("customers.id"))
    status: Mapped[str] = mapped_column(default="draft")
    total: Mapped[Decimal] = mapped_column(Numeric(12, 2), default=0)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    line_items: Mapped[list["LineItem"]] = relationship(
        back_populates="invoice", cascade="all, delete-orphan"
    )


class LineItem(Base):
    __tablename__ = "line_items"

    id: Mapped[int] = mapped_column(primary_key=True)
    invoice_id: Mapped[int] = mapped_column(ForeignKey("invoices.id"))
    description: Mapped[str]
    quantity: Mapped[int]
    unit_price: Mapped[Decimal] = mapped_column(Numeric(12, 2))

    invoice: Mapped["Invoice"] = relationship(back_populates="line_items")
```

**The repository (`repositories/invoice_repository.py`) — data-access layer.**
It encapsulates queries. The service calls these methods and never writes SQL
or touches the session's query API itself.

```python
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.customer import Customer
from app.models.invoice import Invoice


class InvoiceRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get_customer(self, customer_id: int) -> Customer | None:
        return await self._session.get(Customer, customer_id)

    def add(self, invoice: Invoice) -> None:
        self._session.add(invoice)

    async def get(self, invoice_id: int) -> Invoice | None:
        stmt = select(Invoice).where(Invoice.id == invoice_id)
        return await self._session.scalar(stmt)
```

**The service (`services/invoice_service.py`) — business-logic layer.** This is
where the rules live. Notice what is *absent*: no FastAPI, no HTTP status
codes, no Pydantic. It takes plain data and raises domain exceptions. This is
the layer you unit test.

```python
from decimal import Decimal
from app.core.errors import ValidationError
from app.models.invoice import Invoice, LineItem
from app.repositories.invoice_repository import InvoiceRepository
from app.schemas.invoice import InvoiceCreate


class InvoiceService:
    def __init__(self, repo: InvoiceRepository) -> None:
        self._repo = repo

    async def create_invoice(self, account_id: int, data: InvoiceCreate) -> Invoice:
        customer = await self._repo.get_customer(data.customer_id)
        if customer is None or customer.account_id != account_id:
            raise ValidationError("Customer not found.")
        if not customer.billing_email:
            raise ValidationError("Customer has no billing email; cannot invoice.")
        if not data.line_items:
            raise ValidationError("An invoice needs at least one line item.")

        total = sum(
            (item.unit_price * item.quantity for item in data.line_items),
            start=Decimal("0"),
        )
        invoice = Invoice(
            account_id=account_id,
            customer_id=customer.id,
            status="draft",
            total=total,
            line_items=[
                LineItem(
                    description=i.description,
                    quantity=i.quantity,
                    unit_price=i.unit_price,
                )
                for i in data.line_items
            ],
        )
        self._repo.add(invoice)
        return invoice
```

**The dependency wiring (`api/deps.py`).** FastAPI's dependency injection wires
each layer to the one below. (Chapter 06 covers DI in depth; here it is just
the glue that assembles the stack per request.)

```python
from typing import Annotated
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.db import get_session
from app.repositories.invoice_repository import InvoiceRepository
from app.services.invoice_service import InvoiceService

SessionDep = Annotated[AsyncSession, Depends(get_session)]


def get_invoice_service(session: SessionDep) -> InvoiceService:
    return InvoiceService(InvoiceRepository(session))


InvoiceServiceDep = Annotated[InvoiceService, Depends(get_invoice_service)]
```

**The route (`api/routes/invoices.py`) — presentation layer.** The endpoint is
deliberately thin: it receives a validated request, calls one service method,
commits, and formats the response. All it knows about business rules is how to
translate a domain exception into an HTTP status.

```python
from fastapi import APIRouter, HTTPException, status
from app.api.deps import InvoiceServiceDep, SessionDep, CurrentAccountDep
from app.core.errors import ValidationError
from app.schemas.invoice import InvoiceCreate, InvoiceRead

router = APIRouter(prefix="/invoices", tags=["invoices"])


@router.post("", response_model=InvoiceRead, status_code=status.HTTP_201_CREATED)
async def create_invoice(
    payload: InvoiceCreate,
    service: InvoiceServiceDep,
    session: SessionDep,
    account: CurrentAccountDep,
) -> InvoiceRead:
    try:
        invoice = await service.create_invoice(account.id, payload)
    except ValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)
        )
    await session.commit()
    return InvoiceRead.model_validate(invoice)
```

Trace one request through the stack: FastAPI validates the JSON body into an
`InvoiceCreate` (presentation), the route calls `create_invoice` (delegating to
the service), the service applies the billing-email and line-item rules and
computes the total (business logic), the repository stages the insert (data
access), and the route commits and serializes an `InvoiceRead` back out. Every
concern is in exactly one place — and the business rules can be tested by
constructing an `InvoiceService` with a fake repository and calling one method,
with no HTTP and no database in sight.

## Engineering Decisions

Four decisions define how strictly you apply layering, and each has a right
answer for most Invoicely-sized apps and a defensible alternative.

### Where does business logic live?

**Options:** (1) in the route handler ("fat controller"); (2) in the ORM model
("fat model"); (3) in a dedicated service layer.

**Trade-offs:** logic in the route is fastest to write and impossible to reuse
or test without HTTP — and it duplicates the moment a second entry point needs
the same rule. Logic in the model (the "rich domain model" of DDD) keeps
behavior next to data and can be excellent, but with an ORM it entangles
business rules with persistence concerns and is easy to get wrong. A service
layer keeps rules in one reusable, testable place at the cost of one more layer
to navigate.

**Recommendation:** the service layer for most applications, and especially any
with rules invoked from more than one entry point. It is the choice that keeps
the "create invoice" rules from scattering across the API, the CSV importer,
and the recurring-billing job. (Chapter 05 goes deeper on service design; the
fat-model alternative belongs to the Clean Architecture discussion in Chapter
03.)

### May the API layer call the repository directly?

**Options:** (1) always route through the service, even for a plain read; (2)
allow the API to use the repository directly for simple queries.

**Trade-offs:** always-through-the-service is consistent and keeps one path for
everything, but it litters the service with pass-through methods that add
nothing (`get_invoice` that just calls `repo.get`). Allowing direct reads
removes that boilerplate but creates two paths into the data and tempts logic
to creep into the API layer over time.

**Recommendation:** route writes and anything with rules through the service
without exception; permit direct repository reads only for genuinely
logic-free queries, and the moment a read grows a rule, move it into the
service. Consistency matters, but a layer of pure pass-throughs is the
"lasagna" anti-pattern, and empty indirection is not a virtue.

### What crosses the API boundary — ORM models or DTOs?

**Options:** (1) return ORM models directly from endpoints; (2) map to Pydantic
schemas at the boundary.

**Trade-offs:** returning ORM models is less code today and couples your public
API contract to your database schema — so a column rename becomes a breaking API
change, and internal fields leak to clients by accident. Mapping to schemas
costs a definition and a `model_validate` call and keeps the two free to evolve
independently.

**Recommendation:** map to DTOs at the boundary, always. The database schema and
the API contract change for different reasons and different audiences; coupling
them is a decision you will regret the first time you need to change one without
the other. This is the single most common layering mistake, and the cheapest to
avoid.

### How strict should the layering be?

**Options:** (1) pure, dogmatic layering — every access goes through every
layer; (2) pragmatic layering — clear layers, with sensible exceptions.

**Trade-offs:** dogmatic layering is predictable and can drown a simple app in
ceremony (four files to add one field). Pragmatic layering keeps the app moving
but requires judgment about when an exception is reasonable, which a team has to
share.

**Recommendation:** pragmatic, with the boundaries written into `CLAUDE.md` and
enforced in review. The layers are a tool for managing change cost, not a
religion — keep them where they earn their keep, and skip ceremony where it buys
nothing (Stage 1, Chapter 07). But make the rules explicit, because "use
judgment" is not something an AI assistant can infer.

## Trade-offs

Layered architecture is the right default, not a universal good, and it costs
real things.

**Indirection has a price.** A one-field change can now touch the schema, the
model, the repository, the service, and the route. For a genuinely trivial app
— a handful of CRUD endpoints with no business rules — that ceremony is pure
overhead, and a flatter structure (thin routes calling the ORM directly) is the
simpler, correct choice (Stage 1, Chapter 07's over-engineering warning applies
directly). Layers earn their keep when there is business logic to isolate.

**Layers organize by technical concern, which scatters features.** A single
feature — "add tax to invoices" — is spread across all the layers, so a
feature-shaped change touches every layer and a new feature means editing many
files far apart. This is the central complaint that motivates feature-based and
vertical-slice architectures (Chapter 02): if your dominant axis of change is
*features* rather than *technical concerns*, layering fights you.

**It tends toward an anemic domain model.** Pushing all behavior into services
can leave the models as bare data bags with no behavior — which is fine for
CRUD-heavy apps and a genuine weakness for domains with rich, invariant-heavy
rules, where behavior wants to live with the data it protects. This is a real
debate, not a settled one; Chapter 03 revisits it.

**Strict layering can hide performance problems.** A too-generic repository
interface encourages the service to fetch more than it needs or to trigger N+1
queries across a boundary that makes the inefficiency invisible. The abstraction
that helps maintainability can hurt performance if the boundary is drawn without
regard for how data is actually accessed.

**When to use it, and when not.** Use layered architecture for most CRUD-heavy
web applications, for teams who already know the pattern, and as the safe
default when you are unsure. Reach for something else when the app is trivial
(too much ceremony), when features rather than layers are your main axis of
change (vertical slice), or when the domain is genuinely complex enough to
warrant a rich model and strict dependency inversion (Clean Architecture).

## Common Mistakes

**Business logic in the route handler.** The fat controller — validation,
rules, and queries all inline in the endpoint. It works until the second entry
point needs the same rule, then the logic duplicates and drifts. Fix: routes
parse, delegate to one service call, and format; nothing else.

**Leaking ORM models to the API.** Returning SQLAlchemy models straight from
endpoints, coupling the public contract to the database schema. Fix: define
Pydantic response schemas and map at the boundary, so the two evolve
independently.

**Skipping the service "just this once."** Adding a rule directly to a route
because the endpoint is "simple," after which simple endpoints accumulate rules
until they are the ball of mud. Fix: if it is a business rule, it goes in the
service the first time, not the fifth.

**The thin pass-through repository.** A repository whose methods only forward to
the ORM with no added value, existing purely to satisfy a layer diagram. Fix: a
repository should encapsulate *real* query logic; if it adds nothing, question
whether you need it here (Chapter 05), rather than keeping empty indirection.

**Upward or circular dependencies.** A service importing from the API layer, or
a repository reaching up into a service — which destroys the one-way rule that
makes layers worth having. Fix: dependencies point down only; if a lower layer
needs something from above, pass it in as an argument or invert the dependency
(Chapter 06).

## AI Mistakes

Every failure here traces to one fact: **the shape that dominates an
assistant's training data is the framework tutorial, and framework tutorials
put everything in the route handler.** Left unguided, an assistant reproduces
that shape and quietly dismantles your layers. The countermeasure is to make the
architecture explicit — in `CLAUDE.md`, in a reference file, in the prompt — so
the assistant has a target other than the tutorial.

### Claude Code: the fat route handler by default

Asked to "add an endpoint to create an invoice," Claude Code will readily
produce a single FastAPI function containing the validation, the business
rules, and the SQLAlchemy queries — a complete, working, tutorial-shaped
endpoint that ignores your service and repository layers entirely, because
nothing told it they existed.

**Detect:** business logic (`if`s about domain rules) or database access
(`session.execute`, `select(...)`) living inside a route function. Any query or
rule in `api/routes/` is the tell.

**Fix:** state the architecture and point at an example:

> This project uses layered architecture. Routes in `api/routes/` only parse
> input, call one service method, and format the response. Business rules go in
> `services/`, data access in `repositories/`. Follow the pattern in
> `services/invoice_service.py` and keep the route thin.

### GPT: collapsing the model/DTO separation

GPT-family models tend to return ORM objects directly from endpoints and skip
the Pydantic response schema — or, conversely, use a single class as both the
database model and the API contract. It is less code and it silently couples
your API to your schema, leaking database columns to clients and turning every
migration into a potential API break.

**Detect:** endpoints with no `response_model` and returning ORM instances;
database columns appearing verbatim in API responses; one class doing double
duty as table and contract.

**Fix:** require the boundary mapping explicitly:

> Never return ORM models from the API layer. Define a Pydantic response schema
> in `schemas/` and map to it at the boundary with `model_validate`. The
> database model and the API contract must stay separate types.

### Cursor: logic landing in whichever layer the cursor is in

Because inline assistance follows the file you are editing, Cursor tends to put
new code wherever you happen to be — a validation rule added while you are in
the repository lands in the repository; a query written while you are in the
service lands in the service. Over time the layer boundaries erode, not through
one bad decision but through many locally-convenient ones.

**Detect:** rules in the repository, queries in the service, HTTP concerns in
either — code that is correct but in the wrong layer. Ask of each addition,
"what reason would this have to change, and is that this layer's reason?"

**Fix:** name the destination layer before accepting the edit, and review for
placement, not just correctness:

> This is a business rule — it belongs in `InvoiceService`, not in the
> repository. Add it there and have the repository expose only the data the
> service needs.

## Best Practices

**Keep routes thin.** A route parses and validates input, makes one service
call, translates domain exceptions to HTTP, and serializes the response. If a
route contains an `if` about a business rule or a database query, move it down a
layer.

**Make the service layer framework-agnostic.** Services take plain arguments and
domain objects, return plain values, and raise domain exceptions — no FastAPI,
no HTTP status codes, no request objects in their signatures. This is what makes
them unit-testable without a server and reusable across entry points.

**Separate ORM models from API schemas.** Keep `models/` (persistence shape) and
`schemas/` (API contract) as distinct types that map at the boundary. They serve
different audiences and change for different reasons; never let one class do
both jobs.

**Enforce the one-way dependency rule.** Dependencies point down only; a lower
layer never imports a higher one. When a lower layer needs behavior from above,
inject it (Chapter 06) rather than importing upward.

**Write the architecture into `CLAUDE.md`.** State which layer holds what, with
a reference file per layer
([`templates/claude-md-starter.md`](../../templates/claude-md-starter.md)). This
is the single highest-leverage move for keeping AI-generated code in the right
layer — it replaces the tutorial shape with yours.

## Anti-Patterns

**The Fat Controller (Smart UI).** All logic — rules, orchestration, queries —
concentrated in the presentation layer. It optimizes for writing the first
endpoint and punishes every change and every new entry point afterward. The
tell: route handlers longer than a few lines, containing `if`s about the domain
or raw queries.

**Leaky Layers.** ORM models or raw SQL escaping upward into the API, coupling
the public contract to the database. The tell: a schema migration that forces an
API version bump, or internal columns visible in client responses.

**Lasagna Architecture.** So many layers, each a thin pass-through, that a change
means editing five files that each do almost nothing — indirection with no
benefit (Stage 1, Chapter 07's shallow-module sprawl, applied to layers). The
tell: layers whose methods only forward to the next layer down.

**Layer-Skipping.** The API reaching past the service straight into the
repository for writes, so business rules are applied on some paths and not
others. The tell: the same entity created two ways, one of which bypasses the
validation the other enforces.

**The God Service.** Overcorrecting from fat controllers into a single service
class that holds the logic for everything, thousands of lines long. The tell: an
`InvoiceService` that also handles payments, customers, and reporting. Split by
cohesion (Chapter 05).

## Decision Tree

"I have a piece of backend code — how do I structure it, and where does it go?"

```
Is the application trivial? (a few endpoints, essentially no business rules)
│
├── YES ──► Layers may be overhead. Thin routes calling the ORM directly are
│           fine. Keep routes thin anyway, so logic has somewhere to go later.
│
└── NO ──► Use layers. For each piece of code, ask what it is:
    │
    ├── HTTP / routing / (de)serialization / status codes
    │        └──► PRESENTATION layer (api/). Keep it thin.
    │
    ├── A business rule, a validation with domain meaning, orchestration
    │   of multiple steps, a transaction boundary
    │        └──► SERVICE layer (services/). Framework-agnostic, testable.
    │
    └── A database query, persistence, data mapping
             └──► DATA-ACCESS layer (repositories/). Hide the ORM here.

    Then check the axis of change:
    │
    Is your dominant axis of change FEATURES, not technical layers?
    (every change touches all layers; features are far apart)
    │
    ├── YES ──► Consider feature-based / vertical slice (Chapter 02).
    └── NO ───► Layered is serving you. Stay.
```

## Checklist

### Implementation Checklist

- [ ] Routes only parse input, call one service method, translate errors, and serialize output.
- [ ] All business rules live in the service layer and are reachable by every entry point that needs them.
- [ ] The service layer has no FastAPI/HTTP types in its signatures and is unit-tested without a server or database.
- [ ] Data access is confined to repositories; no queries appear in services or routes.
- [ ] API requests/responses use Pydantic schemas, mapped from ORM models at the boundary.
- [ ] Domain exceptions are raised in the service and translated to HTTP in the API layer.

### Architecture Checklist

- [ ] Dependencies point down only; no lower layer imports a higher one, and there are no cycles.
- [ ] Each layer has a single kind of reason to change, and you can name it.
- [ ] No layer exists purely as a pass-through with no added value.
- [ ] The ORM model and the API contract are separate types.
- [ ] The layer rules are documented in `CLAUDE.md` with a reference file per layer.

### Code Review Checklist

- [ ] No business logic or database query has crept into a route handler.
- [ ] No ORM model is returned across the API boundary.
- [ ] New code landed in the correct layer for its reason-to-change (watch AI-generated diffs especially).
- [ ] The change did not add empty pass-through methods to satisfy the diagram.
- [ ] A rule invoked from multiple entry points lives in the service, not duplicated per entry point.

*(A Deployment Checklist is not applicable to this chapter — layering is a
code-organization concern, not a deployment one. Deployment checklists appear
in chapters where they apply; see also
[`checklists/production-readiness.md`](../../checklists/production-readiness.md).)*

## Exercises

**1. Un-mud a handler.** Take a fat FastAPI route handler that validates input,
enforces two or three business rules, runs several queries, and returns an ORM
model — write one, or generate one with an assistant using a naive prompt. Refactor
it into the four layers: thin route, service holding the rules, repository holding
the queries, Pydantic schema at the boundary. The artifact is the before/after
diff plus a unit test for the service that runs with no HTTP and no database —
proof the separation is real.

**2. Add a feature across the layers.** Extend the Invoicely example with "void
an invoice": a `POST /invoices/{id}/void` endpoint. The business rule — a `paid`
invoice cannot be voided, only a `draft` or `sent` one — must live in the
service, the state change must go through the repository, and the route must stay
thin. The artifact is the code plus a note on which files you touched and why
each change belongs in its layer. (Notice how a feature spreads across layers —
that observation motivates Chapter 02.)

**3. Find the violations.** Take a layered codebase (yours, or the example
extended by an assistant over several prompts) and audit it for layer
violations: logic in routes, ORM models crossing the boundary, queries in
services, upward imports. The artifact is a list of violations, each labeled with
the rule it breaks and the one-line fix — the exact review skill the AI Mistakes
section requires.

## Further Reading

- **Architecture Patterns with Python** (Harry Percival & Bob Gregory, free at
  cosmicpython.com) — the definitive practical treatment of layering, service
  layer, and repository in exactly this stack (Python, SQLAlchemy, Flask/FastAPI
  ideas transfer directly). Read it as the book-length version of this chapter
  and the next few.
- **Patterns of Enterprise Application Architecture** (Martin Fowler) — the
  origin of the vocabulary: Service Layer, Data Mapper, Domain Model, and the
  trade-off between the transaction-script and rich-domain approaches this chapter
  gestures at.
- **Common web application architectures** (Microsoft .NET architecture guide,
  learn.microsoft.com) — despite the .NET framing, the clearest free explanation
  of the traditional N-layer approach and its evolution toward Clean
  Architecture; the concepts are language-neutral and map onto Chapters 01 and
  03.
- **FastAPI documentation — Bigger Applications** (fastapi.tiangolo.com) — the
  framework's own guidance on structuring a project into routers and
  dependencies, which is the mechanical foundation the presentation layer above
  is built on.

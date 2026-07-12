# Building APIs with FastAPI

## Introduction

This chapter is about building the HTTP surface of a backend correctly: the
routes, the request and response models, the validation, the status codes, and
the async behavior that together form the contract clients depend on. We use
FastAPI — the handbook's stack — but the concerns are framework-independent, and
most of them are exactly the concerns an assistant gets wrong by default.

FastAPI has appeared in every Stage 2 chapter as the presentation layer, always
kept deliberately thin. Now we look at that layer directly and ask what
"production-grade" means for it specifically: input that cannot be trusted and
must be validated at the boundary; request and response shapes that are separate,
deliberate contracts rather than a leaked database model; status codes that tell
clients the truth; and endpoints that do not accidentally block the event loop.

The throughline is **the boundary**. The API layer is where the untrusted outside
world meets your system, and its whole job is to be a strict, honest membrane:
validate the shape of what comes in, control the shape of what goes out, and
translate between HTTP and the domain — while leaving business rules to the
service layer (Stage 2, Chapters 01 and 05). Get the boundary right and the rest
of the backend can trust its inputs; get it wrong and every layer behind it
inherits the mess.

## Why It Matters

The API is a contract, and contracts have consequences. Clients — your own
frontend, mobile apps, customers' integrations — build against the shapes and
behaviors your endpoints expose, and every one of those shapes becomes something
you cannot casually change. An API built carelessly leaks internal fields that
become load-bearing, accepts fields it should never trust, returns `200 OK` for
failures so clients cannot tell success from error, and blocks under load because
one endpoint does synchronous I/O on the event loop.

Two failures in particular cause outsized damage:

- **Trusting client input.** Every field from a client is hostile until validated
  — the wrong type, a negative quantity, a `status` the client should not set, a
  `10,000`-item list meant to exhaust memory. Validation at the boundary is the
  difference between a rejected request and corrupt data or a crash.
- **Coupling the API to the database.** Returning ORM models directly (Stage 2,
  Chapter 01's warning) makes your public contract a mirror of your schema, so a
  column rename breaks clients and internal fields leak to the outside. The
  request and response shapes must be deliberate contracts, separate from
  persistence.

The AI dimension is acute here because FastAPI is so productive that the
happy-path version *looks* finished. An assistant will generate an endpoint that
accepts a request, saves it, and returns something — and it will routinely reuse
one model for input and output (leaking and over-accepting fields), return the
wrong status codes, and block the event loop with synchronous calls inside an
`async def`. All three pass a manual click-through and fail under real input and
real load. The API boundary is precisely where "works in the demo" and "works in
production" diverge most sharply.

## Mental Model

The API layer is a strict membrane with three jobs and nothing else:

```
   UNTRUSTED OUTSIDE                        YOUR SYSTEM
   ┌──────────────┐                    ┌──────────────────────────┐
   │  HTTP client  │                    │  service layer (domain)   │
   └──────┬───────┘                    └───────────▲──────────────┘
          │ request (JSON, hostile)                 │ validated domain call
          ▼                                          │
   ┌─────────────────────────────────────────────────────────────┐
   │  API BOUNDARY (FastAPI)                                        │
   │                                                               │
   │  1. VALIDATE INPUT   request model — reject bad shape/type/    │
   │                      range at the door (never trust a client)  │
   │  2. TRANSLATE        HTTP ⇄ domain: call one service method,   │
   │                      map domain errors → status codes          │
   │  3. CONTROL OUTPUT   response model — expose only intended     │
   │                      fields; never leak the ORM/internal state │
   └─────────────────────────────────────────────────────────────┘
          ▲                                          │
          │ response (shape you chose)               │ domain result
          └──────────────────────────────────────────┘

   The boundary validates shape; the SERVICE enforces business rules.
```

Three principles make the membrane trustworthy:

**Validate shape at the boundary; enforce rules in the service.** Pydantic
validates that input is *well-formed* — right types, required fields, values in
range, list not absurdly long. Whether the operation is *allowed* — this customer
can be invoiced, this invoice can be voided — is a business rule and belongs in
the service (Stage 2). Putting domain rules in Pydantic validators couples the
domain to the API; skipping shape validation lets hostile input reach the domain.
Both halves are mandatory, and each belongs in its place.

**Request and response are separate, deliberate contracts.** The shape a client
may *send* to create a resource is not the shape you *store*, and neither is the
shape you *return*. A create request must not accept server-controlled fields
(`id`, `status`, `account_id`) — accepting them is a mass-assignment
vulnerability. A response must expose only intended fields — returning the ORM
model leaks internals and welds the contract to the schema. Model each operation's
input and output explicitly.

**Status codes are part of the contract, and they must be honest.** `201` for a
created resource, `204` for a successful no-content operation, `404` for not
found, `409` for a conflict, `422` for invalid input. Returning `200` for
everything — including errors — forces every client to parse the body to discover
what happened, which is the API equivalent of swallowing exceptions.

A working definition:

> **A production API is a strict, honest boundary: it validates the shape of
> untrusted input, exposes only deliberately chosen output, tells the truth with
> status codes, and translates between HTTP and the domain — leaving business
> rules to the service and never blocking the event loop.**

## Production Example

**Invoicely's** invoices API is the surface we will build: create an invoice,
fetch one, list them with pagination and filtering, and update one. It is
ordinary CRUD on the outside and full of boundary decisions underneath — which
fields a client may set, what a negative quantity should do, how a list endpoint
behaves when an account has 40,000 invoices, and what each operation returns.

The example deliberately reuses the layered structure from Stage 2: the router is
thin, validation lives in the request models, and business rules stay in
`InvoiceService`. What this chapter adds is everything specific to the *boundary*
— the request/response model separation, the Pydantic v2 validation, the correct
status codes, and pagination that survives scale — the parts Stage 2 kept in the
background so it could focus on structure.

## Folder Structure

```
modules/invoicing/
├── router.py            # routes: thin — validate, delegate, format, status codes
├── schemas.py           # request/response models — the API contract (DTOs)
│   #   InvoiceCreate    (what a client may send to create)
│   #   InvoiceUpdate    (what a client may change — all optional)
│   #   InvoiceRead      (what we expose back)
│   #   Page[InvoiceRead](paginated envelope)
├── _service.py          # business rules (Stage 2) — unchanged here
└── _repository.py       # data access (Stage 2) — unchanged here
core/
├── pagination.py        # reusable pagination params + Page envelope
└── errors.py            # domain exceptions, mapped to status codes at the boundary
```

Why this shape:

- **`schemas.py`** holds several models per resource, one per operation, because
  create, update, and read are *different contracts*. Cramming them into one model
  is the most common boundary mistake.
- **`router.py`** stays thin (Stage 2): it wires validated input to a single
  service call and maps the result and any domain error to HTTP. No business rules,
  no queries.
- **`core/pagination.py`** makes pagination a reusable, consistent contract across
  every list endpoint rather than reinvented per route.

## Implementation

**Request and response models — separate contracts (`schemas.py`).** Note what each
model does and does not include: `InvoiceCreate` cannot set `id`, `status`, or
`account_id` (server-controlled); `InvoiceUpdate` is all-optional (partial update);
`InvoiceRead` exposes only intended fields.

```python
from decimal import Decimal
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field, field_validator


class LineItemCreate(BaseModel):
    description: str = Field(min_length=1, max_length=500)
    quantity: int = Field(gt=0, le=100_000)          # positive, bounded
    unit_price: Decimal = Field(ge=0, max_digits=12, decimal_places=2)


class InvoiceCreate(BaseModel):
    # Client may set ONLY these. No id, status, account_id — those are ours.
    customer_id: int
    line_items: list[LineItemCreate] = Field(min_length=1, max_length=1000)

    @field_validator("line_items")
    @classmethod
    def no_duplicate_descriptions(cls, items: list[LineItemCreate]) -> list[LineItemCreate]:
        # Shape/format validation belongs here; business rules do NOT.
        descriptions = [i.description for i in items]
        if len(descriptions) != len(set(descriptions)):
            raise ValueError("Line item descriptions must be unique.")
        return items


class InvoiceUpdate(BaseModel):
    # Partial update: every field optional; absent means "leave unchanged".
    customer_id: int | None = None
    line_items: list[LineItemCreate] | None = Field(default=None, min_length=1)


class InvoiceRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    # Exposes only what clients should see — no internal columns.
    id: int
    customer_id: int
    status: str
    total: Decimal
    created_at: datetime
```

**Reusable pagination (`core/pagination.py`).** A consistent envelope and bounded
page size, so no list endpoint can be asked to return everything.

```python
from typing import Annotated, Generic, TypeVar
from fastapi import Query
from pydantic import BaseModel

T = TypeVar("T")


class PageParams(BaseModel):
    limit: int = 50
    offset: int = 0


def page_params(
    limit: Annotated[int, Query(ge=1, le=100)] = 50,   # bounded: never unbounded
    offset: Annotated[int, Query(ge=0)] = 0,
) -> PageParams:
    return PageParams(limit=limit, offset=offset)


class Page(BaseModel, Generic[T]):
    items: list[T]
    total: int
    limit: int
    offset: int
```

**The router — thin, correct status codes, honest errors (`router.py`).**

```python
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, status
from app.core.auth import CurrentAccountDep
from app.core.db import SessionDep
from app.core.errors import NotFoundError, ValidationError
from app.core.pagination import Page, PageParams, page_params
from app.modules.invoicing.deps import InvoiceServiceDep
from app.modules.invoicing.schemas import InvoiceCreate, InvoiceRead, InvoiceUpdate

router = APIRouter(prefix="/invoices", tags=["invoices"])


@router.post("", response_model=InvoiceRead, status_code=status.HTTP_201_CREATED)
async def create_invoice(
    payload: InvoiceCreate, service: InvoiceServiceDep,
    session: SessionDep, account: CurrentAccountDep,
) -> InvoiceRead:
    try:
        invoice = await service.create_invoice(account.id, payload)
    except ValidationError as exc:                        # domain rule failed
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(exc))
    await session.commit()
    return InvoiceRead.model_validate(invoice)            # 201 + response model


@router.get("/{invoice_id}", response_model=InvoiceRead)
async def get_invoice(
    invoice_id: int, service: InvoiceServiceDep, account: CurrentAccountDep,
) -> InvoiceRead:
    invoice = await service.get_invoice(account.id, invoice_id)
    if invoice is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Invoice not found.")
    return InvoiceRead.model_validate(invoice)


@router.get("", response_model=Page[InvoiceRead])
async def list_invoices(
    service: InvoiceServiceDep, account: CurrentAccountDep,
    params: Annotated[PageParams, Depends(page_params)],
    status_filter: str | None = None,
) -> Page[InvoiceRead]:
    invoices, total = await service.list_invoices(
        account.id, status=status_filter, limit=params.limit, offset=params.offset
    )
    return Page(
        items=[InvoiceRead.model_validate(i) for i in invoices],
        total=total, limit=params.limit, offset=params.offset,
    )
```

**Async correctness — do not block the event loop.** FastAPI runs `async def`
endpoints on one event loop; a synchronous, blocking call inside one stalls *every*
concurrent request, not just the current one. Use async libraries end to end, and
push unavoidable blocking work off the loop.

```python
import anyio

# WRONG — blocks the event loop; every other request stalls while this runs
@router.post("/{invoice_id}/pdf")
async def render_pdf_bad(invoice_id: int) -> Response:
    pdf = heavy_sync_pdf_render(invoice_id)   # CPU-bound, synchronous → blocks all
    return Response(pdf, media_type="application/pdf")

# RIGHT — offload blocking work to a worker thread, keeping the loop free
@router.post("/{invoice_id}/pdf")
async def render_pdf(invoice_id: int) -> Response:
    pdf = await anyio.to_thread.run_sync(heavy_sync_pdf_render, invoice_id)
    return Response(pdf, media_type="application/pdf")
    # For genuinely heavy work, prefer a background job (Chapter 06) over the request.
```

Trace a create request through the membrane: FastAPI parses the body into
`InvoiceCreate`, rejecting anything malformed, over-long, or including a field the
client may not set — before a line of your code runs. The router hands the
validated input to the service, which applies the *business* rules and raises a
domain error if one fails. The router maps that error to `422`, commits, and
returns an `InvoiceRead` that exposes only the fields you chose, with a `201`. At
no point does the client's shape reach the database untranslated, and at no point
does a synchronous call stall the loop. That is the boundary doing its job.

## Engineering Decisions

Five decisions define an API's boundary.

### One model per resource, or one per operation?

**Options:** (1) a single model reused for create, update, read (and maybe the ORM
too); (2) a distinct model per operation.

**Trade-offs:** one model is less code and a security-and-coupling hazard — create
then accepts server-controlled fields (mass assignment) and read exposes internal
ones, and the contract welds to the schema. Per-operation models cost a few
definitions and make each contract explicit and safe.

**Recommendation:** one model per operation — `InvoiceCreate`, `InvoiceUpdate`,
`InvoiceRead` — and never the ORM model as an API model. This is the single
highest-value boundary decision: it closes the mass-assignment hole and decouples
the API from persistence in one move.

### Where does validation live?

**Options:** (1) validate shape and business rules both in Pydantic; (2) shape at
the boundary (Pydantic), business rules in the service.

**Trade-offs:** putting everything in Pydantic centralizes validation but drags
business logic (and often database lookups) into the API schema, coupling the
domain to the transport and making rules untestable without HTTP. Splitting keeps
each concern where it belongs but requires the discipline to know which is which.

**Recommendation:** Pydantic validates *shape and format* — types, required
fields, ranges, lengths, patterns — at the boundary; the service enforces *business
rules* — existence, permissions, state transitions, anything needing data (Stage 2,
Chapters 01 and 05). "Quantity must be positive" is shape; "this customer can be
invoiced" is a rule. Keep the boundary about well-formedness.

### Offset pagination or cursor pagination?

**Options:** (1) limit/offset; (2) cursor (keyset) pagination.

**Trade-offs:** offset is trivial to implement and lets clients jump to any page,
but degrades on large tables (`OFFSET 100000` scans and discards 100,000 rows) and
can skip or duplicate rows when data changes between pages. Cursor pagination is
stable and fast at any depth but only supports next/previous, not arbitrary jumps,
and needs a stable sort key.

**Recommendation:** offset for small, bounded datasets and admin screens where
simplicity wins; cursor pagination for large or fast-changing collections and
anything user-facing at scale. Either way, **bound the page size** — an unbounded
`limit` is a denial-of-service waiting to happen. (Query performance is deepened in
Stage 6.)

### PUT or PATCH for updates?

**Options:** (1) `PUT` — full replacement; (2) `PATCH` — partial update.

**Trade-offs:** `PUT` is simple and unambiguous (send the whole resource) but forces
clients to send every field and risks clobbering fields they didn't mean to touch.
`PATCH` updates only supplied fields, which suits real UIs (editing one field) but
needs a model where "absent" and "explicitly null" are distinguishable.

**Recommendation:** `PATCH` with an all-optional update model for most resources, so
clients change only what they intend; reserve `PUT` for genuine full-replacement
semantics. With Pydantic, use `model_dump(exclude_unset=True)` so an omitted field
means "leave unchanged," not "set to null."

### Sync or async endpoints?

**Options:** (1) `async def` throughout; (2) `def` (threadpool) endpoints; (3)
`async` with blocking work offloaded.

**Trade-offs:** `async def` gives high concurrency for I/O-bound work but blocks the
whole loop if you call anything synchronous inside it. Plain `def` endpoints run in a
threadpool (safe for blocking work) but with lower concurrency and thread overhead.
Mixed — async endpoints that offload blocking calls — gets both, at the cost of being
deliberate about what blocks.

**Recommendation:** `async def` with async libraries (async DB driver, async HTTP
client) as the default, and offload unavoidable blocking/CPU work with
`anyio.to_thread.run_sync` or a background job (Chapter 06). Never call a synchronous
network or CPU-bound function directly inside an `async def` — it stalls every
concurrent request.

## Trade-offs

The boundary discipline has costs, and a few decisions are genuinely contextual.

**Per-operation models are more code.** Three or four models per resource is more to
write and keep in sync than one. The cost is real and worth paying — it buys
mass-assignment safety and API/schema decoupling — but for a truly internal,
low-stakes endpoint, a single model can be a reasonable, conscious shortcut. Make it
a decision, not a default.

**Strict validation can reject the merely-unusual.** Tight constraints (max lengths,
bounded lists, format patterns) stop hostile and malformed input but can also reject
legitimate edge cases you didn't anticipate — a genuinely long description, an
unusual but valid value. Set bounds from real data and treat a wave of `422`s as a
signal to revisit them, not always as clients misbehaving.

**Async is not free concurrency.** `async` helps only I/O-bound work; CPU-bound work
still needs a thread or a job, and the requirement that *nothing* block the loop is a
standing constraint that catches teams out (one synchronous library call degrades the
whole service). The payoff is high I/O concurrency; the price is vigilance about what
blocks.

**When the framework's defaults are enough.** For a small internal tool, FastAPI's
automatic validation and docs may be all the boundary you need, and elaborate
pagination or PATCH semantics would be over-engineering (Stage 1, Chapter 07). Scale
the rigor to the API's exposure and traffic.

## Common Mistakes

**Reusing one model for everything.** A single model for create, update, read, and
persistence — so create accepts server-controlled fields (mass assignment) and read
leaks internal ones. Fix: a distinct model per operation, none of them the ORM
model.

**Trusting client input.** Accepting fields without validating type, range, or
length, or letting clients set `id`/`status`/`account_id`. Fix: validate shape at the
boundary with Pydantic constraints, and never accept server-controlled fields in a
request model.

**Business rules in the schema.** Cramming domain logic (existence checks,
permissions, state rules) into Pydantic validators, coupling the domain to the
transport and often needing database access in a validator. Fix: shape in Pydantic,
rules in the service.

**Dishonest status codes.** Returning `200` for created resources, for errors, or for
"not found," so clients must parse the body to know what happened. Fix: `201`/`204`/
`404`/`409`/`422` as appropriate; the status code is part of the contract.

**Blocking the event loop.** Calling synchronous I/O (`requests`, a sync DB driver,
`time.sleep`) or heavy CPU work inside an `async def`, stalling all concurrent
requests. Fix: async libraries, or offload with `run_sync` / a background job.

**Unbounded list endpoints.** A `limit` with no maximum (or no pagination at all),
letting one request try to return the whole table. Fix: bound the page size and
paginate every collection.

## AI Mistakes

FastAPI's productivity is the trap: the generated happy-path endpoint looks
finished, so the boundary defects — model reuse, blocked loops, wrong status codes —
sail through a manual click-through and surface under real input and load. Review
generated endpoints specifically for what the demo cannot reveal.

### Claude Code: one model for every operation

Asked to build a CRUD resource, Claude Code frequently defines a single Pydantic (or
ORM-derived) model and uses it for create, update, and read alike — so the create
endpoint accepts `id`, `status`, and `account_id` (mass assignment), and the read
endpoint returns internal fields. It is less code and a security-and-coupling bug.

**Detect:** one model across operations; a create request whose fields include
server-controlled ones (`id`, `status`, ownership, timestamps); a response returning
an ORM instance or exposing internal columns.

**Fix:** require per-operation models:

> Define separate request and response models per operation: a create model that
> accepts only client-settable fields (never `id`, `status`, `account_id`), an
> all-optional update model, and a read model exposing only intended fields. Never
> use the ORM model as an API model.

### GPT: blocking the event loop inside async endpoints

GPT-family models routinely put synchronous, blocking calls inside `async def`
endpoints — a `requests.get`, a synchronous database driver, `time.sleep`, a
CPU-heavy loop — because the code reads naturally and runs fine with one user. Under
concurrency it stalls the entire event loop, and the whole service's latency
collapses.

**Detect:** synchronous I/O (`requests`, sync DB calls, blocking file/network) or
heavy CPU work inside an `async def`; a mix of `async def` with a synchronous client
library.

**Fix:** state the async rule:

> This endpoint is `async def`; never call blocking or CPU-bound code directly inside
> it. Use async libraries (async DB driver, `httpx.AsyncClient`), offload unavoidable
> blocking work with `anyio.to_thread.run_sync`, and move heavy work to a background
> job. Nothing may block the event loop.

### Cursor: inconsistent status codes and error shapes

Editing endpoints inline, Cursor tends to return `200` for everything — created
resources, "not found," even errors returned as a `200` body with an `error` field —
and to invent a different error JSON shape per endpoint, because each edit is local
and unaware of the API's overall contract.

**Detect:** created resources returning `200` instead of `201`; errors returned as
`200` with an error field; `404`/`409`/`422` never used; error response bodies that
differ from endpoint to endpoint.

**Fix:** require honest, consistent codes and one error shape:

> Use correct HTTP status codes: `201` for created, `204` for no-content success,
> `404` not found, `409` conflict, `422` invalid input. Never return `200` for an
> error. Use the project's single error response shape for all errors, not an ad-hoc
> one per endpoint.

## Best Practices

**Model each operation's input and output explicitly.** Separate create, update, and
read models; requests accept only client-settable fields; responses expose only
intended fields via `response_model`. Never use the ORM model as an API model.

**Validate shape at the boundary, rules in the service.** Use Pydantic constraints
(types, ranges, lengths, patterns, bounded lists) so malformed input is rejected at
the door, and keep business rules — existence, permissions, state — in the service
where they are testable and reusable.

**Tell the truth with status codes, and keep one error shape.** `201`/`204`/`404`/
`409`/`422` as appropriate, never `200` for failure, and a single consistent error
body across the API (its design is deepened in Chapter 05).

**Paginate every collection, with a bounded page size.** No list endpoint returns
everything; cap the `limit`, and use cursor pagination for large or user-facing
collections.

**Keep the event loop free.** Default to `async def` with async libraries; offload
blocking or CPU-bound work to a thread or a background job (Chapter 06). Treat "does
anything here block?" as a review question for every async endpoint.

## Anti-Patterns

**The God Model.** One model serving request, response, and persistence — the source
of mass-assignment holes and API/schema coupling at once. The tell: a create endpoint
that accepts `id` or `status`, or a response that is an ORM instance.

**Smart Validators.** Pydantic validators that reach into the database or encode
business rules, turning the API schema into a hidden service layer. The tell: a
validator that needs a session or checks permissions.

**The 200-for-Everything API.** Every response is `200`, with success or failure
signaled only in the body. The tell: clients that must inspect a payload field to
know whether their request worked.

**The Blocking Async Endpoint.** `async def` endpoints that call synchronous I/O or
CPU-bound code, stalling the loop under load. The tell: `requests`, a sync DB driver,
or `time.sleep` inside an `async def`.

**The Firehose Endpoint.** A list endpoint with no pagination or an unbounded
`limit`, able to be asked for the entire table. The tell: a query with no `LIMIT`
driven by client input.

## Decision Tree

"I'm building an endpoint — how do I get the boundary right?"

```
INPUT MODELING
├─ Define a request model with ONLY client-settable fields.
│  (never id/status/account_id/timestamps — those are server-controlled)
└─ Validate SHAPE here (types, ranges, lengths, bounded lists) with Pydantic.
   Business rules? ──► NOT here. Put them in the service (Stage 2).

OUTPUT MODELING
└─ Define a response model exposing ONLY intended fields; set response_model.
   Returning the ORM model? ──► No. Map to the response model at the boundary.

STATUS CODES
├─ created a resource ─────► 201       ├─ not found ──────► 404
├─ success, no content ────► 204       ├─ conflict ───────► 409
└─ invalid input ──────────► 422       └─ never 200 for an error

COLLECTIONS
└─ Paginate. Bound the page size.
   Large / fast-changing / user-facing at scale? ──► cursor pagination.
   Small / admin / needs page-jumping? ────────────► offset is fine.

ASYNC
└─ async def + async libraries.
   Any blocking or CPU-bound call inside? ──► offload (run_sync) or a job (Ch 06).
   Never block the event loop.
```

## Checklist

### Implementation Checklist

- [ ] Separate request and response models per operation; the ORM model is never an API model.
- [ ] Request models accept only client-settable fields — never `id`, `status`, ownership, or timestamps.
- [ ] Pydantic validates shape/format (types, ranges, lengths, bounded lists) at the boundary; business rules are in the service.
- [ ] Every endpoint returns a correct, honest status code; no `200` for errors.
- [ ] Every collection endpoint is paginated with a bounded maximum page size.
- [ ] `async def` endpoints call no blocking or CPU-bound code directly; such work is offloaded.

### Architecture Checklist

- [ ] The API layer only validates, translates, and formats; business rules and data access live below it (Stage 2).
- [ ] The public contract is decoupled from the database schema (DTOs, not ORM models).
- [ ] Pagination is a consistent, reusable contract across list endpoints.
- [ ] The error response shape is consistent across the API (see Chapter 05).
- [ ] API conventions (models, status codes, pagination) are documented in `CLAUDE.md`.

### Code Review Checklist

- [ ] No single model is reused across create/update/read, and no request accepts server-controlled fields (watch AI diffs).
- [ ] No business logic or database access sits in a Pydantic validator.
- [ ] No synchronous/blocking call appears inside an `async def` endpoint.
- [ ] Status codes are correct and consistent; no endpoint returns `200` for failure.
- [ ] New list endpoints are paginated with a bounded page size.

*(A Deployment Checklist is light here — an API's deployment concerns live in Stage 7;
the production-readiness checklist covers the service-level items:
[`checklists/production-readiness.md`](../../checklists/production-readiness.md).)*

## Exercises

**1. Split the god model.** Take an endpoint that uses one model for create, update,
read, and persistence (write one, or have an assistant generate a CRUD resource) and
split it into per-operation request/response models, removing every server-controlled
field from the create model. The artifact is the before/after plus a one-line note on
the mass-assignment field you removed and what it would have allowed.

**2. Make it not block.** Take an `async def` endpoint that calls a synchronous
blocking function (a sync HTTP client, a CPU-bound render) and fix it — async library,
thread offload, or a background job — then explain what would happen to concurrent
requests under the original version. The artifact is the fix and the failure
description.

**3. Design a list endpoint at scale.** Design the `GET /invoices` endpoint for an
account with 200,000 invoices: choose offset vs cursor pagination, bound the page
size, and decide the filter and sort contract. The artifact is the endpoint signature,
the response envelope, and a paragraph justifying the pagination choice for this scale.

## Further Reading

- **FastAPI documentation** (fastapi.tiangolo.com) — the official guide, especially
  the sections on request bodies, response models, path/query parameters, and
  handling errors. The authoritative reference for everything mechanical in this
  chapter.
- **Pydantic documentation** (docs.pydantic.dev) — validators, field constraints, and
  model configuration in Pydantic v2. Read the validation and serialization sections
  to use the boundary layer to its full strength.
- **REST API Design Rulebook** (Mark Massé, O'Reilly) — a concise, opinionated guide
  to status codes, resource modeling, and URI design; the vocabulary for making an
  API a coherent contract rather than a pile of endpoints.
- **API Design Patterns** (JJ Geewax, Manning) — a deeper, modern treatment of
  pagination (including cursor/keyset), partial updates, long-running operations, and
  versioning; excellent background for this chapter and Chapter 05.

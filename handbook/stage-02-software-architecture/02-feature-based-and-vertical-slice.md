# Feature-Based & Vertical Slice Architecture

## Introduction

Feature-based architecture organizes code by *what the application does* rather
than by *technical role*. Instead of top-level `api/`, `services/`, and
`repositories/` folders that each hold a slice of every feature, you have
top-level `invoices/`, `customers/`, and `reconciliation/` folders that each
hold everything for one feature. Vertical slice architecture takes the same
idea further: each individual use case — "create invoice," "run
reconciliation" — is a self-contained slice from HTTP down to the database,
sharing as little machinery with its neighbors as possible.

Both are a direct response to the central weakness Chapter 01 named: layered
architecture organizes by technical concern, so a single feature is scattered
across every layer, and a feature-shaped change touches many files far apart.
Since most change requests *are* feature-shaped — "add tax to invoices," not
"rewrite all persistence" — organizing by feature puts what changes together in
the same place. This chapter covers the two together because they are one idea
at two intensities: group by feature (feature-based), then minimize what
features and use cases share (vertical slice).

The stakes are the maintainability curve from Stage 1 again, viewed through a
different lens. Where Chapter 01 optimized each layer for one *kind* of change,
this chapter optimizes each feature for its *own* change — and the choice
between them is one of the most consequential structural decisions you make,
because it determines whether your codebase grows more navigable or less as
features accumulate.

## Why It Matters

Watch what happens to a layered codebase as it grows. Chapter 01's Invoicely
had `api/`, `services/`, and `repositories/`. Add ten more features and each of
those folders holds thirteen files — the `services/` directory contains invoice
logic, payment logic, reconciliation logic, customer logic, and more, all side
by side, none related to the next. To understand the invoicing feature you open
four folders and read one-thirteenth of each. To add a feature you touch four
folders. The technical layers stayed tidy; the *features* dissolved into them.

Feature-based organization inverts this. Everything about invoicing lives in
`invoices/`; to understand the feature you read one folder, and to change it you
touch one folder. This buys several things that compound as the system grows:

- **Cohesion and locality.** What changes together lives together, so a
  feature-shaped change is a feature-shaped diff — low change amplification
  (Stage 1, Chapter 07's complexity symptom, minimized).
- **Navigability.** The folder structure *screams the domain* — a newcomer sees
  `invoices/`, `payments/`, `reconciliation/` and understands what the system
  does, rather than seeing `controllers/`, `services/`, `repositories/` and
  learning only which framework it uses.
- **Extractability.** A cohesive, loosely-coupled feature folder is the natural
  unit to later promote into a module or a service (Chapter 04). Feature-based
  organization is the on-ramp to a modular monolith; layered organization is
  not.

The AI dimension sharpens this and inverts Chapter 01's advice in one specific
way. Assistants are trained overwhelmingly on layer-organized code, so left
unguided they will scatter a new feature across layer folders even in a
feature-based project — and, when they see two similar slices, they will
"helpfully" merge them into a shared abstraction you deliberately kept apart.
Feature and slice boundaries are exactly the kind of structure an assistant
erodes unless it is written down and enforced.

## Mental Model

The whole choice comes down to which axis you optimize for — and both diagrams
describe the *same* four features and the *same* three technical roles, just
grouped differently:

```
   PACKAGE BY LAYER (Chapter 01)          PACKAGE BY FEATURE (this chapter)
   organized by technical role            organized by what it does

   api/                                    invoices/
    ├─ invoices.py                          ├─ router.py       ─┐
    ├─ payments.py                          ├─ service.py       │ everything for
    └─ reconciliation.py                    ├─ repository.py    │ ONE feature,
   services/                                └─ schemas.py      ─┘ together
    ├─ invoices.py                         payments/
    ├─ payments.py                          ├─ router.py
    └─ reconciliation.py                    ├─ service.py
   repositories/                            └─ ...
    ├─ invoices.py                         reconciliation/
    ├─ payments.py                          └─ ...
    └─ reconciliation.py                   core/   (cross-cutting only)

   A FEATURE is spread across folders.     A LAYER is spread across folders.
   Feature change → touch every folder.    Feature change → touch one folder.
   Layer change  → touch one folder.       Layer change  → touch every folder.
```

Neither is free — you are choosing which kind of change is cheap and which is
expensive. Since feature-shaped changes vastly outnumber layer-shaped ones in
practice, packaging by feature is the better default for most applications.

Vertical slice is the same principle pushed down one level, from *feature* to
*use case*:

```
   VERTICAL SLICE — each use case is self-contained, top to bottom

   reconciliation/
    ├─ run_reconciliation/    ← one slice = one use case
    │   ├─ router.py               HTTP for THIS use case
    │   ├─ handler.py              its whole logic, top to bottom
    │   └─ schemas.py              its request/response
    ├─ get_report/            ← another slice, independent of the first
    │   └─ ...
    └─ shared/                ← ONLY what is genuinely shared (the matching
        └─ matching.py            algorithm) — proven, not speculative
```

The governing idea, and the one hard part:

> **Feature-based and vertical slice architectures organize code by what the
> system does, so that what changes together lives together. The recurring
> decision is what to share between slices — and the default answer is "less
> than you think," because the wrong shared abstraction couples things that
> should change independently.**

That last point is Stage 1, Chapter 07's "the wrong abstraction is worse than
duplication," now promoted to an architectural principle. Vertical slice
deliberately tolerates some duplication to keep slices independent — and knowing
when duplication has earned an abstraction (the rule of three) is the skill the
whole style demands.

## Production Example

**Invoicely** has outgrown its layered structure. It now has invoices,
customers, payments, and the reconciliation engine — and reconciliation, the
differentiator, is not one operation but several distinct use cases: *run a
reconciliation* for an account, *get the reconciliation report*, and *manually
match* a stubborn transaction. Each is a different HTTP endpoint, a different
request shape, a different flow — but they share one thing that genuinely
matters: the matching algorithm at the core.

This is the ideal case for the chapter's two ideas. The simple CRUD features
(invoices, customers) become **feature folders** — each with its router,
service, repository, and schemas colocated, keeping the light internal layering
from Chapter 01 but grouped by feature. The complex feature (reconciliation)
becomes **vertical slices** — each use case self-contained, sharing only the
proven matching module. We will build the invoices feature folder and then the
reconciliation slices, and watch where the boundaries fall.

## Folder Structure

```
app/
├── features/
│   ├── invoices/                 # FEATURE FOLDER — simple CRUD, light layering
│   │   ├── router.py             #   HTTP for invoices
│   │   ├── service.py            #   invoice business logic
│   │   ├── repository.py         #   invoice data access
│   │   ├── schemas.py            #   invoice DTOs
│   │   └── models.py             #   invoice ORM models
│   │
│   ├── customers/                # another feature folder
│   │   └── ...
│   │
│   └── reconciliation/           # VERTICAL SLICES — complex, many use cases
│       ├── run_reconciliation/   #   one slice per use case
│       │   ├── router.py
│       │   ├── handler.py
│       │   └── schemas.py
│       ├── get_report/
│       │   ├── router.py
│       │   ├── handler.py
│       │   └── schemas.py
│       └── shared/               #   ONLY genuinely shared logic
│           └── matching.py       #     the matching algorithm (proven shared)
│
├── core/                         # CROSS-CUTTING concerns, owned by no feature
│   ├── config.py
│   ├── db.py                     #   session, engine
│   ├── auth.py                   #   current-account dependency
│   └── errors.py                 #   domain exceptions
│
└── main.py                       # assembles the app, includes feature routers
```

Why this shape:

- **`features/`** is the top level, so the structure announces the domain. A new
  engineer reads the directory and learns what Invoicely *is*, not which web
  framework it uses.
- Each **feature folder** owns its full stack. Everything about invoices is in
  `invoices/`; changing invoicing means opening one folder. Simple features keep
  the internal layers from Chapter 01 — they are just colocated now.
- **`reconciliation/`** uses **vertical slices** because its use cases differ
  enough that forcing them through one shared `ReconciliationService` would
  couple unrelated flows. Each slice is independent; only `shared/matching.py`
  is common, because the matching algorithm is *proven* shared logic (it is the
  differentiator, used by every slice), not a speculative abstraction.
- **`core/`** holds what belongs to no single feature: configuration, the
  database session, authentication, domain error types. The rule that keeps
  `core/` from becoming a junk drawer: something goes here only if it is truly
  cross-cutting, not merely used by two features today.

## Implementation

**The invoices feature folder.** This is Chapter 01's layered code, regrouped:
the same router, service, and repository, now colocated and importing each other
by feature-relative path. Nothing about the layering changed — only where it
lives.

```python
# features/invoices/service.py
from decimal import Decimal
from app.core.errors import ValidationError
from app.features.invoices.models import Invoice, LineItem
from app.features.invoices.repository import InvoiceRepository
from app.features.invoices.schemas import InvoiceCreate


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
            (i.unit_price * i.quantity for i in data.line_items), start=Decimal("0")
        )
        invoice = Invoice(
            account_id=account_id,
            customer_id=customer.id,
            status="draft",
            total=total,
            line_items=[
                LineItem(description=i.description, quantity=i.quantity, unit_price=i.unit_price)
                for i in data.line_items
            ],
        )
        self._repo.add(invoice)
        return invoice
```

```python
# features/invoices/router.py
from fastapi import APIRouter, HTTPException, status
from app.core.auth import CurrentAccountDep
from app.core.db import SessionDep
from app.core.errors import ValidationError
from app.features.invoices.deps import InvoiceServiceDep
from app.features.invoices.schemas import InvoiceCreate, InvoiceRead

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
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc))
    await session.commit()
    return InvoiceRead.model_validate(invoice)
```

**The reconciliation slices.** Here the style changes. Each use case is a
self-contained handler that does its whole job — no shared
`ReconciliationService` that every use case must route through. The handler
fetches exactly the data it needs and calls the one genuinely shared thing, the
matching algorithm.

```python
# features/reconciliation/shared/matching.py
from dataclasses import dataclass
from decimal import Decimal


@dataclass(frozen=True)
class Match:
    invoice_id: int
    payment_id: int
    confidence: float


def match_payments_to_invoices(
    payments: list["PaymentRow"], invoices: list["InvoiceRow"]
) -> list[Match]:
    """The reconciliation matching algorithm — Invoicely's differentiator.

    Genuinely shared across every reconciliation slice, which is why it lives
    in shared/ rather than being duplicated.
    """
    matches: list[Match] = []
    by_amount: dict[Decimal, list[InvoiceRow]] = {}
    for inv in invoices:
        by_amount.setdefault(inv.amount, []).append(inv)
    for pay in payments:
        for inv in by_amount.get(pay.amount, []):
            matches.append(Match(inv.id, pay.id, confidence=_score(pay, inv)))
    return matches
```

```python
# features/reconciliation/run_reconciliation/handler.py
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.features.reconciliation.shared.matching import match_payments_to_invoices
from app.features.reconciliation.run_reconciliation.schemas import ReconciliationResult
from app.models.invoice import Invoice
from app.models.payment import Payment


class RunReconciliationHandler:
    """One vertical slice: the entire 'run reconciliation' use case.

    It owns its own data access — it does not go through a shared repository,
    because it needs a specific query no other slice needs.
    """

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def handle(self, account_id: int) -> ReconciliationResult:
        payments = list(
            await self._session.scalars(
                select(Payment).where(
                    Payment.account_id == account_id, Payment.reconciled_at.is_(None)
                )
            )
        )
        invoices = list(
            await self._session.scalars(
                select(Invoice).where(
                    Invoice.account_id == account_id, Invoice.status == "sent"
                )
            )
        )
        matches = match_payments_to_invoices(payments, invoices)
        for m in matches:
            if m.confidence >= 0.9:
                await self._apply_match(m)
        return ReconciliationResult(
            matched=sum(1 for m in matches if m.confidence >= 0.9),
            needs_review=[m for m in matches if 0.5 <= m.confidence < 0.9],
        )
```

```python
# features/reconciliation/run_reconciliation/router.py
from fastapi import APIRouter
from app.core.auth import CurrentAccountDep
from app.core.db import SessionDep
from app.features.reconciliation.run_reconciliation.handler import RunReconciliationHandler
from app.features.reconciliation.run_reconciliation.schemas import ReconciliationResult

router = APIRouter(prefix="/reconciliation", tags=["reconciliation"])


@router.post("/run", response_model=ReconciliationResult)
async def run_reconciliation(
    session: SessionDep, account: CurrentAccountDep
) -> ReconciliationResult:
    result = await RunReconciliationHandler(session).handle(account.id)
    await session.commit()
    return result
```

The `get_report` slice sits beside `run_reconciliation` with its own handler,
its own query (a read, shaped entirely differently), and its own schemas. The
two slices share nothing except `matching.py` — and crucially, they do *not*
share a repository or a service, because their data needs diverge and forcing
them through a common abstraction would couple two flows that change for
different reasons. That restraint is the whole point of vertical slice: the
`run_reconciliation` handler owning its own query is a feature, not a smell.

Contrast this with the invoices feature, which *does* keep a shared
service and repository — because its use cases (create, void, list) really do
operate on the same data through the same rules. The lesson is not "always
slice" or "always layer within a feature," but *match the internal structure to
how the feature actually changes.*

## Engineering Decisions

Four decisions shape a feature-based or sliced codebase.

### Package by feature or by layer?

**Options:** (1) top-level technical layers (Chapter 01); (2) top-level feature
folders.

**Trade-offs:** layers make layer-shaped changes cheap and feature-shaped
changes expensive, and they hide the domain behind framework vocabulary.
Feature folders make feature-shaped changes cheap and layer-shaped changes
expensive, and they surface the domain — at the cost that cross-cutting concerns
and shared logic need a deliberate home.

**Recommendation:** package by feature for most applications, because
feature-shaped changes dominate and because feature folders are the on-ramp to
modular extraction later (Chapter 04). Keep light internal layering inside each
feature — feature-based and layered are not opposites; the best structure is
usually "layers within features."

### How much do slices share?

**Options:** (1) share aggressively — common base handlers, a shared service per
feature; (2) share minimally — each slice self-contained, extracting only proven
common logic.

**Trade-offs:** aggressive sharing reduces duplication but couples slices, so a
change for one use case risks breaking another, and the shared abstraction
accretes conditionals to fit every caller (Stage 1, Chapter 07's wrong
abstraction). Minimal sharing keeps slices independently changeable but accepts
real duplication, which can itself become debt if the duplicated logic is
genuinely one concept.

**Recommendation:** share minimally, and let duplication earn its abstraction
via the rule of three. Invoicely shares `matching.py` because it is proven,
central, and identical across slices; it does *not* share a reconciliation
service, because the slices' data access legitimately differs. When in doubt,
duplicate — un-sharing a wrong abstraction is far more expensive than extracting
a right one later.

### Feature folders or full vertical slices?

**Options:** (1) feature folders with internal layering everywhere; (2) full
vertical slices (per-use-case) everywhere; (3) mix — folders for simple
features, slices for complex ones.

**Trade-offs:** uniform feature folders are familiar and can force a shared
service onto a feature whose use cases don't fit one. Uniform vertical slices
maximize independence but impose per-use-case ceremony on simple CRUD that
doesn't need it (Stage 1, Chapter 07's over-engineering). The mix requires
judgment about which features warrant slicing.

**Recommendation:** mix, by complexity. Simple CRUD features (invoices,
customers) are feature folders with internal layers; complex features with
several distinct use cases (reconciliation) are vertical slices. Slicing a
two-endpoint CRUD feature is premature; layering a ten-use-case feature into one
god service is the opposite mistake.

### Where do feature boundaries fall?

**Options:** (1) boundaries by technical concept; (2) boundaries by domain
concept / bounded context.

**Trade-offs:** technical boundaries (`features/database/`, `features/api/`)
recreate layers with extra steps and miss the entire point. Domain boundaries
(`invoices/`, `payments/`) align the code with how the business and its changes
are actually organized — but require understanding the domain well enough to
draw them, and drawing them wrong creates features that must constantly reach
into each other.

**Recommendation:** draw boundaries around domain concepts — this is the
bounded-context idea from Domain-Driven Design (Further Reading), and it is what
makes feature-based organization coherent rather than arbitrary. Boundaries that
match the domain minimize cross-feature coupling and set up clean module
extraction in Chapter 04.

## Trade-offs

Feature-based and vertical slice are the better default for most growing
applications, but they cost real things and are not universal.

**Cross-cutting concerns need a deliberate home.** Auth, configuration, database
setup, and error types belong to no feature, and without discipline `core/` (or
`shared/`) becomes a junk drawer that every feature depends on — recreating the
coupling you organized features to avoid. The cost of feature organization is
the ongoing judgment about what is truly cross-cutting versus merely
currently-shared.

**Vertical slice tolerates duplication, and duplication has a cost.** Keeping
slices independent means the same-looking code can appear in several places, and
if that code is genuinely one concept, you have created maintenance debt (Stage
1, Chapter 05) rather than healthy independence. The style demands continuous
judgment about when duplication has become a real shared concept — get it wrong
in one direction and you couple slices, wrong in the other and you duplicate a
concept.

**It cuts against the grain of most training and tooling.** Layer organization
is what most engineers learned and what most tutorials, scaffolds, and AI
assistants default to. A feature-based codebase requires the team — and the
assistant — to be told the convention repeatedly, or code drifts back toward
layers.

**When layered is still the right call.** Small applications where the ceremony
of feature folders outweighs the benefit; applications genuinely dominated by
technical-layer changes rather than feature changes (rare, but they exist —
e.g., a thin API over a fixed schema); and teams so steeped in layering that the
switching cost exceeds the benefit for a short-lived project. As always, match
the structure to the dominant axis of change, not to fashion.

## Common Mistakes

**The package-by-layer masquerade.** Top-level `features/` folders, but with a
fat shared `services/` or `core/` that holds most of the actual logic — layers
wearing a feature costume. Fix: a feature's logic lives *in* the feature; `core/`
holds only what is genuinely cross-cutting, and if it is filling up, your
boundaries are wrong.

**Over-sharing between slices.** Extracting a shared base handler or service from
two slices that merely look alike, coupling flows that should change
independently (Stage 1, Chapter 07). Fix: keep slices independent; extract only
when the shared *concept* is proven across three real cases, not two coincidental
ones.

**Under-sharing genuinely common logic.** Copy-pasting the matching algorithm
into each reconciliation slice because "vertical slice means no sharing" — turning
a real shared concept into duplication debt. Fix: vertical slice means *minimal*
sharing, not *zero*; proven, central, identical logic (the differentiator) is
exactly what belongs in `shared/`.

**Drawing boundaries on the wrong axis.** Feature folders named for technical
concepts (`features/api/`, `features/models/`) rather than domain concepts —
layers with extra nesting. Fix: name features for what they do in the domain
(`invoices/`, `payments/`), so the structure screams the business.

**Cross-feature coupling.** One feature importing another feature's internals
(`invoices/` reaching into `payments/repository.py`), so features can no longer
change independently and can no longer be extracted. Fix: features communicate
through defined, public interfaces, not each other's guts (the discipline
Chapter 04 formalizes).

## AI Mistakes

Two facts drive every failure here: **assistants are trained mostly on
layer-organized code**, so they scatter features back into layers; and
**assistants reflexively remove duplication**, so they merge slices you
deliberately kept apart. Both erode exactly the boundaries this architecture
depends on, and both are invisible unless you look for them.

### Claude Code: reverting to layers inside a feature-based project

Asked to add a feature to a feature-based codebase, Claude Code will often
create or extend top-level `services/` and `repositories/` folders — reproducing
the layer organization from its training data and scattering the new feature
across the very structure you organized to avoid. It produces working code in
the wrong shape.

**Detect:** a new feature whose files landed in layer folders rather than in a
single feature folder; new top-level `services/`/`repositories/` directories
appearing in a project that packages by feature.

**Fix:** state the convention and point at an existing feature:

> This project packages by feature. Everything for a feature lives in
> `features/<feature>/` — router, service, repository, schemas together. Do not
> add top-level layer folders. Follow the structure of `features/invoices/`.

### GPT: DRYing across slice boundaries

Shown two vertical slices with similar-looking code, GPT-family models will
"helpfully" extract a shared base class or common service to remove the
duplication — undoing the deliberate independence of the slices and coupling
flows that were kept separate on purpose. It optimizes for no-duplication, which
is the wrong objective at a slice boundary.

**Detect:** a newly introduced `BaseHandler`, shared service, or common
abstraction extracted from two slices; slices that now import a shared class
holding their core logic rather than just proven utilities.

**Fix:** name the boundary and the rule:

> These are independent vertical slices; keep them independent. Do not extract a
> shared abstraction from two slices that merely look similar — duplication
> between slices is acceptable and intended. Only `shared/` holds proven common
> logic like the matching algorithm.

### Cursor: silent cross-feature coupling

Editing inside one feature and needing data from another, Cursor tends to reach
directly into the other feature's internals — importing `payments/repository.py`
from within `invoices/` — because that is the nearest available symbol, not
because it is the sanctioned path. Each such import couples two features that
were supposed to change independently.

**Detect:** an import that crosses a feature boundary into another feature's
internal modules (its repository, its models, its service) rather than a defined
public interface. Cross-feature imports are the fingerprint.

**Fix:** require features to talk through defined boundaries:

> Features must not import each other's internals. If `invoices` needs payment
> data, call the `payments` feature's public interface, or pass the data in from
> the caller. Never import another feature's repository or models directly.

## Best Practices

**Organize the top level by feature, and let it scream the domain.** A newcomer
reading the directory listing should learn what the application does, not which
framework it uses. `invoices/`, `payments/`, `reconciliation/` — not
`controllers/`, `services/`, `repositories/`.

**Keep what changes together, together.** Colocate a feature's router, logic,
data access, and schemas so a feature-shaped change is a single-folder diff. Use
light internal layering within a feature, or vertical slices for complex
features — matched to how that feature actually changes.

**Share deliberately, and prefer duplication to the wrong abstraction.** Extract
shared logic only when the concept is proven across real cases (the rule of
three); keep slices independent by default. Un-sharing a bad abstraction costs
far more than extracting a good one later (Stage 1, Chapter 07).

**Make features talk through boundaries, not internals.** A feature exposes a
defined public interface and hides the rest; other features use that interface
and never reach into its repository or models. This is what keeps features
independently changeable and later extractable (Chapter 04).

**Write the packaging convention into `CLAUDE.md`.** State that the project
packages by feature, where cross-cutting code goes, and that slices stay
independent — with reference features to imitate
([`templates/claude-md-starter.md`](../../templates/claude-md-starter.md)). This
is the one reliable defense against an assistant's pull back toward layers and
toward over-sharing.

## Anti-Patterns

**The Package-by-Layer Masquerade.** Feature folders on the outside, a fat
shared service/core layer holding the real logic on the inside — layering with
extra directories. The tell: the feature folders are thin and `core/` or a
shared `services/` is where you actually go to change behavior.

**The Shared-Kernel Junk Drawer.** A `shared/`, `common/`, or `core/` that
accumulates everything two or more features touch, until every feature depends on
it and it can never change safely. The tell: a `utils`/`common` module imported
almost everywhere, growing without bound.

**Feature Spaghetti.** Features so mutually entangled — each importing the
others' internals — that none can change or be extracted without the rest. It is
the distributed-monolith failure at the module level. The tell: a dependency
graph between features with cycles in it.

**Premature Slicing.** Applying full per-use-case vertical slices to a simple
CRUD feature, duplicating request/response/handler ceremony for endpoints that
would be three lines in a shared service (Stage 1, Chapter 07's over-engineering,
and Chapter 04's over-splitting). The tell: five nearly-identical slice folders
for basic create/read/update/delete.

**Wrong-Axis Boundaries.** Features named and split by technical role rather than
domain concept, recreating layers under a `features/` prefix. The tell:
`features/api/`, `features/db/` — folders that describe mechanism, not meaning.

## Decision Tree

"How do I organize this codebase, and where does this code go?"

```
What is the dominant axis of change — features or technical layers?
│
├── Technical layers (rare; a thin API over a fixed schema) ──► Layered (Ch 01).
│
└── Features (the common case) ──► Package by FEATURE.
    │
    For a given feature, how complex is it?
    │
    ├── Simple CRUD (a few endpoints, shared data & rules)
    │        └──► FEATURE FOLDER with light internal layering
    │             (router + service + repository + schemas, colocated).
    │
    └── Complex (several distinct use cases with diverging flows)
             └──► VERTICAL SLICES (one self-contained handler per use case),
                  sharing only proven common logic in shared/.

    Now, where does a given piece of code belong?
    │
    ├── Specific to one feature ──────► in that feature's folder.
    ├── Genuinely cross-cutting infra ─► core/ (config, db, auth, errors).
    └── Shared logic
            │
            Proven common across 3+ real cases?
            ├── YES ──► extract to shared/ (or a feature's public interface).
            └── NO ───► duplicate it. Wait for the abstraction to earn itself.
```

## Checklist

### Implementation Checklist

- [ ] The top-level structure is organized by feature/domain, and the folder names describe what the app does.
- [ ] Each feature's router, logic, data access, and schemas are colocated in its folder.
- [ ] Complex features use vertical slices (one handler per use case); simple features use light internal layering.
- [ ] Shared logic in `shared/` is proven and common; nothing was extracted from only two coincidental cases.
- [ ] `core/` holds only genuinely cross-cutting concerns, not feature logic.
- [ ] Feature routers are assembled in `main.py`; no feature reaches into another feature's internals.

### Architecture Checklist

- [ ] Feature boundaries follow domain concepts, not technical roles.
- [ ] The dependency graph between features is acyclic; features communicate through defined interfaces.
- [ ] Each feature is cohesive enough to be extracted into a module later (sets up Chapter 04).
- [ ] The share-vs-duplicate decisions were made by the rule of three, not reflexive DRY.
- [ ] The packaging convention is documented in `CLAUDE.md` with reference features.

### Code Review Checklist

- [ ] New feature code landed in its feature folder, not scattered into layer folders (watch AI diffs).
- [ ] No shared abstraction was extracted from two slices that only look alike.
- [ ] No feature imported another feature's internal modules.
- [ ] `core/`/`shared/` did not grow a new dumping-ground dependency.
- [ ] A simple feature was not over-sliced, and a complex feature was not crammed into one god service.

*(A Deployment Checklist is not applicable here — this is a code-organization
concern. Deployment enters in Chapter 04, where feature boundaries become
deployment boundaries.)*

## Exercises

**1. Reorganize by feature.** Take the layered Invoicely structure from Chapter
01 (`api/`, `services/`, `repositories/`) and reorganize it into feature folders
(`features/invoices/`, `features/customers/`), keeping the internal layering. The
artifact is the before/after tree plus one paragraph on which changes got
*cheaper* (feature-shaped) and which got *more expensive* (layer-shaped) — the
trade-off, made concrete.

**2. Slice a complex feature.** Take the reconciliation feature and split it into
vertical slices (`run_reconciliation/`, `get_report/`, `manual_match/`), deciding
explicitly what belongs in `shared/` and what stays duplicated per slice. The
artifact is the structure plus a justification for each item you shared and each
you duplicated — this is the core judgment of the whole style.

**3. Audit the boundaries.** Take a feature-based codebase (yours, or the example
extended by an assistant over several prompts) and audit for the chapter's
failures: layer masquerade, cross-feature imports, junk-drawer `core/`,
over-shared slices. The artifact is a list of boundary violations, each with the
rule it breaks and the fix — the exact review skill the AI Mistakes section
demands.

## Further Reading

- **Vertical Slice Architecture** (Jimmy Bogard, jimmybogard.com, 2018) — the
  canonical definition of the style and its central argument: minimize coupling
  between slices, maximize coupling *within* a slice. The .NET framing is
  incidental; the ideas transfer directly.
- **Screaming Architecture** (Robert C. Martin, blog.cleancoder.com) — the short,
  sharp case that a system's top-level structure should announce what it *does*,
  not which framework it uses. The one-page justification for packaging by
  feature.
- **Software Architecture for Developers** (Simon Brown, and his talks on
  "package by layer vs. by feature vs. by component") — a leading practitioner's
  treatment of the organization trade-off, including "package by component" as a
  middle path that leads naturally into the modular monolith of Chapter 04.
- **Domain-Driven Design** (Eric Evans), the bounded-context chapters — how to
  draw feature boundaries around domain concepts so they are coherent rather than
  arbitrary. Read the strategic-design parts now; they are the foundation for
  Chapter 04's module boundaries.

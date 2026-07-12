# Dependency Injection

## Introduction

Dependency injection (DI) is a simple idea buried under intimidating vocabulary:
an object receives its dependencies from the outside instead of creating them
itself. Rather than an `InvoiceService` constructing its own repository inside its
constructor, it is *given* one. That single change — "give it to me" instead of
"I'll make it myself" — is what makes the object testable, swappable, and honest
about what it needs.

Every chapter in this stage has already used DI without naming it: services take
repositories, repositories take a session, and FastAPI's `Depends` assembles the
chain per request. This chapter formalizes what was happening and adds the
judgment around it — the forms of injection, where the wiring belongs, when to
depend on an abstraction versus a concrete type, and, importantly for a Python
codebase, how *little* machinery you actually need.

That last point is the chapter's distinctive stance. Dependency injection came to
most engineers through Java and .NET, where heavyweight DI *containers* are
standard, and that baggage is routinely cargo-culted into Python projects that do
not need it. In Python, constructor injection plus a framework's built-in DI (like
FastAPI's `Depends`) plus one composition root covers the overwhelming majority of
cases. DI is essential; DI *containers* usually are not — and telling the two
apart is the engineering judgment this chapter teaches.

## Why It Matters

Consider the alternative to injection. A class that builds its own dependencies —
`self._repo = InvoiceRepository(SessionLocal())` — has welded itself to those
concrete types and their construction. You cannot test its logic without a real
database, because the real repository is baked in. You cannot reuse it against a
different data source. And its constructor lies: it claims to need nothing, while
secretly reaching out to a global session and a concrete repository. The
dependencies are hidden, hard-coded, and untestable.

Injection reverses all three:

- **Testability.** Because dependencies come from outside, a test supplies fakes —
  the in-memory repository from Chapter 05, no database required. This is the
  single biggest practical payoff and the reason DI is non-negotiable for testable
  business logic.
- **Explicit dependencies.** A constructor that takes what it needs *documents*
  what it needs. Reading `InvoiceService(repo, payments)` tells you exactly what
  the service depends on — no hidden globals, no surprises.
- **Substitutability.** Injected dependencies can be swapped: a SQLAlchemy
  repository in production, an in-memory one in tests, a remote client after the
  Chapter 04 extraction. The Clean Architecture of Chapter 03 is *built* on this —
  its ports exist precisely so adapters can be injected.

The technique is also the practical expression of the **Dependency Inversion
Principle** (the "D" in SOLID): depend on abstractions, not concretions. DI is how
you arrange for a high-level policy (the service) to depend on an abstraction (a
repository interface) that a low-level detail (the SQLAlchemy adapter) implements.

The AI dimension is concrete and recurring. Assistants love self-contained classes
that construct their own collaborators — it looks tidy and complete — so they
routinely generate the hard-coded, untestable version. They also reach for a DI
*container* when asked to "set up dependency injection," importing machinery a
Python app rarely needs, and they mishandle dependency *lifecycles* (sharing a
request-scoped session as a global). DI's benefits require the discipline of
injection and a single composition root, and that discipline is exactly what an
assistant will not impose unprompted.

## Mental Model

The whole idea is one reversal of control over who creates what:

```
   WITHOUT DI — the object creates its own dependencies (control is inside)

     class InvoiceService:
         def __init__(self):
             self._repo = InvoiceRepository(SessionLocal())   # hard-coded, hidden,
                                                              # untestable

   WITH DI — the object receives its dependencies (control is inverted, outside)

     class InvoiceService:
         def __init__(self, repo: InvoiceRepository):         # explicit, swappable,
             self._repo = repo                                # testable


   WHO assembles the graph? — the COMPOSITION ROOT (one place, at the entry point)

     request ─► FastAPI Depends ─► InvoiceService(InvoiceRepository(session))
                (the composition root wires session → repo → service per request)
```

Three ideas make this usable:

**Prefer constructor injection.** Of the forms — constructor, method, and
setter/property injection — constructor injection is the default: dependencies are
supplied at creation, so the object is always in a valid, complete state, and its
requirements are visible in one signature. Reach for method injection only when a
dependency genuinely varies per call, and avoid setter injection (it allows
half-constructed objects) unless a framework forces it.

**Wire in one composition root.** There should be a single place — the application
entry point, expressed through FastAPI's `Depends` in a web app — where the object
graph is assembled. Classes never reach out to fetch their own dependencies from a
global; they receive them, and the composition root does all the reaching. A
dependency pulled from a global registry *inside* a class is the Service Locator
anti-pattern, which looks like DI but reintroduces hidden dependencies.

**Inject abstractions only where you need substitutability.** Depend on a
`Protocol` (a port) when you actually need to swap implementations or inject a fake
— the repository, an email sender, a payment gateway. For stable collaborators that
will never be mocked or swapped (a pure function, a value object, a constant), inject
the concrete thing, or just use it directly. Abstracting everything is
over-engineering (Stage 1, Chapter 07); abstract at the seams that move.

A working definition:

> **Dependency injection means an object receives its collaborators from the
> outside rather than creating them, assembled in one composition root. It buys
> testability, explicit dependencies, and substitutability — and in Python it
> needs constructor injection and a framework's DI, not a heavyweight container.**

## Production Example

**Invoicely's** invoice-voiding flow, from Chapter 05, is the graph we will wire.
The dependency chain is: the route needs an `InvoiceService`, which needs an
`InvoiceRepository` and the `PaymentsModule`, and the repository needs a database
`Session`. That is a small object graph — exactly the kind that constructor
injection plus FastAPI `Depends` handles cleanly, and exactly the kind for which a
DI container would be pure overhead.

We will wire it three ways to make the concepts concrete: the classes with
constructor injection (the objects themselves), the FastAPI composition root that
assembles them per request, and — the payoff — a test that overrides the injected
dependencies with fakes and exercises the service with no database and no HTTP.
Then we will look at the hard-coded version to see exactly what injection bought.

## Folder Structure

```
modules/invoicing/
├── _service.py       # receives its dependencies (constructor injection)
├── _repository.py    # receives the session
├── deps.py           # COMPOSITION ROOT for this module (FastAPI Depends wiring)
└── router.py         # declares what it needs via Depends
core/
├── db.py             # session lifecycle (per-request scope)
└── config.py         # settings (singleton, created once at startup)
tests/
└── conftest.py       # dependency_overrides — inject fakes for tests
```

Why this shape:

- **`deps.py`** is the composition root for the module: the `get_*` functions that
  assemble session → repository → service. This is the *one* place wiring lives, so
  the object graph is described in a single readable location rather than scattered
  through the classes.
- **`_service.py` and `_repository.py`** only *receive* dependencies; they contain
  no wiring and reach for no globals. That is what keeps them testable.
- **`core/db.py`** owns the session lifecycle — one session per request — and
  **`core/config.py`** owns settings as a startup singleton. Getting these scopes
  right is a core DI concern, distinct from the graph wiring.
- **`tests/conftest.py`** uses FastAPI's `dependency_overrides` to swap real
  dependencies for fakes — the mechanism that turns injectable code into testable
  code.

## Implementation

**Constructor injection in the classes.** The service and repository receive their
collaborators; neither constructs anything or touches a global. (This is the
Chapter 05 code, now seen as DI.)

```python
# modules/invoicing/_repository.py
from sqlalchemy.ext.asyncio import AsyncSession


class InvoiceRepository:
    def __init__(self, session: AsyncSession) -> None:   # session injected
        self._session = session


# modules/invoicing/_service.py
from app.modules.invoicing._repository import InvoiceRepository
from app.modules.payments.public import PaymentsModule


class InvoiceService:
    def __init__(self, repo: InvoiceRepository, payments: PaymentsModule) -> None:
        self._repo = repo            # dependencies are explicit in the signature
        self._payments = payments
```

**The composition root (`deps.py`).** FastAPI's `Depends` *is* the DI container for
a web app: each `get_*` function declares its own dependencies, and FastAPI
resolves the whole chain per request. This is where session, repository, and
service are assembled — the one place that knows how the graph fits together.

```python
# modules/invoicing/deps.py
from typing import Annotated
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.db import get_session
from app.modules.invoicing._repository import InvoiceRepository
from app.modules.invoicing._service import InvoiceService
from app.modules.payments.deps import get_payments_module
from app.modules.payments.public import PaymentsModule


def get_invoice_repository(
    session: Annotated[AsyncSession, Depends(get_session)],
) -> InvoiceRepository:
    return InvoiceRepository(session)


def get_invoice_service(
    repo: Annotated[InvoiceRepository, Depends(get_invoice_repository)],
    payments: Annotated[PaymentsModule, Depends(get_payments_module)],
) -> InvoiceService:
    return InvoiceService(repo, payments)


InvoiceServiceDep = Annotated[InvoiceService, Depends(get_invoice_service)]
```

The route declares the dependency it needs and stays ignorant of how it is built:

```python
# modules/invoicing/router.py
@router.post("/invoices/{invoice_id}/void", status_code=204)
async def void_invoice(
    invoice_id: int, service: InvoiceServiceDep, session: SessionDep, account: CurrentAccountDep
) -> None:
    await service.void_invoice(account.id, invoice_id)
    await session.commit()
```

**The testing payoff (`conftest.py`).** Because the graph is wired through
overridable `Depends` functions, a test swaps the real repository for an in-memory
fake — no database, no HTTP — and exercises the real service.

```python
# tests/conftest.py
import pytest
from app.main import app
from app.modules.invoicing.deps import get_invoice_repository


@pytest.fixture
def use_fake_invoices(fake_invoices: InMemoryInvoiceRepository):
    app.dependency_overrides[get_invoice_repository] = lambda: fake_invoices
    yield
    app.dependency_overrides.clear()
```

Or, testing the service in complete isolation, injection means you simply *pass the
fakes in* — no framework required at all, which shows DI is a design technique, not
a FastAPI feature:

```python
async def test_void_rules() -> None:
    service = InvoiceService(
        repo=InMemoryInvoiceRepository([...]),   # fakes injected directly
        payments=FakePayments(),
    )
    await service.void_invoice(account_id=42, invoice_id=1)
```

**What injection bought — the contrast.** The hard-coded version cannot do any of
this:

```python
# ANTI-PATTERN: dependencies hard-coded and hidden
class InvoiceService:
    def __init__(self) -> None:
        self._repo = InvoiceRepository(SessionLocal())   # welded to concrete types
        self._payments = PaymentsModule(...)             # reaches out on its own

    # To test void_invoice you now need a real database and a real payments module.
    # The constructor claims to need nothing while secretly depending on everything.
```

The two versions have the same behavior and opposite testability. That difference —
supplied dependencies versus constructed ones — is the entire practical value of
dependency injection, and it cost nothing but moving object creation to the
composition root.

**DI without a framework.** The extracted reconciliation service (Chapter 04) has
no FastAPI request cycle for some entry points, yet the technique is identical — a
small function assembles the graph at the entry point:

```python
# a worker entry point — the composition root is just a function
async def run_reconciliation_job(account_id: int) -> None:
    async with session_scope() as session:
        use_case = RunReconciliation(
            payments=SqlAlchemyPaymentRepository(session),
            invoices=SqlAlchemyInvoiceRepository(session),
        )
        await use_case.execute(account_id)
        await session.commit()
```

No container, no framework magic — just constructor injection and one place that
wires the graph. For the vast majority of Python applications, this is all the DI
you need.

## Engineering Decisions

Five decisions define how you apply DI, and several of them are decisions *not* to
add machinery.

### Which form of injection?

**Options:** (1) constructor injection; (2) method injection; (3) setter/property
injection.

**Trade-offs:** constructor injection makes objects valid on creation and their
dependencies visible in one signature, at the cost of a constructor parameter.
Method injection suits a dependency that genuinely varies per call. Setter
injection permits half-constructed objects (a dependency might be unset), which is
a source of bugs and usually only appears because a framework demands it.

**Recommendation:** constructor injection by default, method injection for
genuinely per-call dependencies, setter injection essentially never. A fully
constructed object should be fully usable — that invariant prevents a whole class
of "dependency was None" errors.

### Manual/framework DI, or a DI container?

**Options:** (1) constructor injection wired by hand or by the framework (FastAPI
`Depends`); (2) a dedicated DI container library.

**Trade-offs:** framework/manual DI is transparent — you can read exactly how the
graph is built — and sufficient for small-to-medium object graphs, which is most
Python web apps. A DI container automates wiring for large graphs and adds
lifecycle management, at the cost of a dependency, a learning curve, and "magic"
that obscures how objects are assembled.

**Recommendation:** use FastAPI's `Depends` (or plain constructor injection at a
function composition root) and skip the container. In Python, a DI container earns
its place only when the object graph is genuinely large and manual wiring has become
painful — a rare situation, and one to reach for deliberately, not by default. This
is the chapter's central restraint: DI containers are the most commonly
cargo-culted machinery in Python architecture.

### Where is the composition root?

**Options:** (1) one composition root at the entry point; (2) objects fetch their
own dependencies from a global registry (service locator); (3) wiring scattered
across classes.

**Trade-offs:** a single composition root keeps all wiring in one readable place and
keeps classes honest about their dependencies. A service locator centralizes access
but hides each class's real dependencies inside its methods — reintroducing the
problem DI solves. Scattered wiring makes the graph impossible to follow.

**Recommendation:** exactly one composition root (FastAPI `Depends`, or the entry
function), and classes that only *receive* dependencies. Never let a class pull from
a global container inside its methods — that is the service locator anti-pattern,
which trades DI's explicitness for hidden coupling.

### Inject a concrete type or an abstraction?

**Options:** (1) inject the concrete class; (2) inject an abstraction (a `Protocol`).

**Trade-offs:** injecting the concrete type is simpler and perfectly testable in
Python (you can pass any duck-typed fake), but it names a specific implementation.
Injecting a `Protocol` states the contract explicitly and is what the Clean
Architecture ports of Chapter 03 require — at the cost of defining the interface.

**Recommendation:** inject an abstraction where you need genuine substitutability or
a defined port (the Clean Architecture core, a swappable gateway); inject the
concrete type for ordinary collaborators. Do not define a `Protocol` for every
dependency — Python's duck typing already lets tests pass fakes to a
concrete-typed parameter, so reserve explicit interfaces for the seams that
actually move.

### What lifecycle/scope does each dependency have?

**Options:** per-request, singleton (application-lifetime), or transient (per use).

**Trade-offs:** getting scope wrong causes real bugs — a database session shared as
a singleton across requests corrupts state and leaks between users; a connection
pool or config recreated per request wastes resources and can exhaust connections.

**Recommendation:** database sessions are per-request (FastAPI's dependency scope
handles this); the engine, connection pool, and configuration are singletons created
once at startup. Make the scope of each dependency deliberate — it is as important as
the wiring, and the source of some of the nastiest DI bugs.

## Trade-offs

DI is close to unconditionally worth it for anything you test, but it has costs and
a well-defined point of diminishing returns.

**Indirection about assembly.** Because objects are wired elsewhere, it is less
immediately obvious what is connected to what — you read the composition root, not
the class, to see the graph. This is a small, worthwhile cost for real code, and a
reason to keep the composition root in one findable place rather than scattering it.

**Framework "magic" can obscure.** FastAPI's `Depends` resolves chains implicitly,
which is convenient until a dependency misbehaves and the resolution is not obvious.
The mitigation is to keep the `Depends` functions simple and readable, so the
"magic" is a thin, inspectable layer rather than a deep one.

**Over-injection and over-abstraction.** Injecting everything — including constants,
pure functions, and collaborators that never vary — adds ceremony without benefit,
as does defining a `Protocol` for every dependency. DI's value is at the seams that
move (things you swap or fake); applying it uniformly is Stage 1, Chapter 07's
over-engineering.

**When you do not need DI.** For a stable collaborator that will never be mocked,
swapped, or independently tested — a pure utility function, a value object — direct
use is fine and injecting it is noise. DI is a tool for managing the dependencies
that vary; it is not a tax to pay on every reference.

## Common Mistakes

**Hard-coded dependencies.** A class that constructs its own collaborators or reads
a global session inside itself — untestable, coupled, and dishonest about what it
needs. Fix: inject via the constructor; move creation to the composition root.

**The service locator.** Classes pulling dependencies from a global registry or
container inside their methods (`container.get(Repo)`), which looks like DI but hides
each class's real dependencies and reintroduces global state. Fix: pass dependencies
in explicitly; the composition root wires them, and classes never reach into a
global.

**Cargo-culting a DI container.** Importing a heavyweight container library and its
configuration where FastAPI `Depends` and constructor injection would do — machinery
a Python app rarely needs. Fix: use the framework's DI; add a container only for a
genuinely large, painful-to-wire graph.

**Wrong scope.** Sharing a request-scoped session as an application singleton (state
corruption across requests) or recreating a singleton (engine, config) per request
(resource waste). Fix: sessions per request, engine and config as startup
singletons; make each dependency's scope deliberate.

**Over-injecting and over-abstracting.** Injecting constants and never-varying
helpers, or defining a `Protocol` for every collaborator. Fix: inject and abstract
only at the seams that move; use concrete types and direct calls for the stable
rest.

## AI Mistakes

Each failure here reflects an assistant's defaults: it favors self-contained classes
that build their own collaborators, it reaches for the heavyweight or global wiring
mechanism, and it does not track dependency lifecycles. DI's payoff — testable,
explicit, correctly-scoped dependencies — requires injection and a single
composition root, which an assistant will not impose on its own.

### Claude Code: classes that construct their own dependencies

Asked for a service, Claude Code frequently generates one that instantiates its own
repository and reaches for a global session inside the constructor, because a
self-contained class looks complete and correct. The result runs and is untestable —
the hard-coded anti-pattern from the Implementation section, generated by default.

**Detect:** a constructor that instantiates its own dependencies
(`self._repo = InvoiceRepository(...)`), imports a global session/engine, or takes no
parameters while clearly needing collaborators.

**Fix:** require injection:

> Do not construct dependencies inside the class or use global sessions. Accept
> collaborators as constructor parameters and wire them in the composition root
> (the FastAPI `Depends` functions in `deps.py`). The class must be constructible
> with fakes for testing.

### GPT: the service locator in disguise

GPT-family models often produce a global container or registry that classes pull
dependencies from — `services.get("invoice_repo")` inside a method — presenting it as
dependency injection. It is the service locator anti-pattern: the dependencies are
hidden inside method bodies, the class still can't be understood from its signature,
and global state is back.

**Detect:** classes calling a global `get_service()`/container/registry inside their
methods rather than receiving dependencies; a module-level singleton container that
code reaches into.

**Fix:** name the anti-pattern and require true injection:

> This is a service locator, not dependency injection. Dependencies must be passed
> into the constructor, not fetched from a global registry inside methods. The
> composition root is the only place that assembles dependencies; classes receive
> them.

### Cursor: dependency-scope errors

Editing inline, Cursor tends to satisfy a need for a session or connection by
storing it at module level or creating a fresh one per call — because the object's
intended lifecycle is not visible at the cursor. The result is a request-scoped
dependency leaked into a singleton, or an engine rebuilt on every request.

**Detect:** a `Session`/connection stored at module scope or created inside a
per-call function; a singleton (engine, config) reconstructed per request. Anything
whose lifetime doesn't match its scope is the tell.

**Fix:** state the intended scope:

> The database session is per-request and comes from `get_session`; do not store it
> at module level or create a new one here. The engine and settings are singletons
> created once at startup; do not rebuild them per call.

## Best Practices

**Prefer constructor injection.** Supply dependencies at construction so objects are
always valid and their requirements are visible in one signature; use method
injection only for genuinely per-call dependencies, and avoid setter injection.

**Keep one composition root, and never a service locator.** Assemble the object graph
in a single place (FastAPI `Depends`, or the entry function); classes receive
dependencies and never fetch them from a global. This keeps dependencies explicit and
the graph findable.

**Use the framework's DI; skip the container.** FastAPI `Depends` plus constructor
injection covers almost every Python app. Reach for a DI container only when a large
graph makes manual wiring genuinely painful — a deliberate, rare choice, not a
default.

**Abstract at the seams that move.** Inject a `Protocol` where you need
substitutability or a defined port (Clean Architecture, swappable gateways); inject
concrete types for stable collaborators, since Python's duck typing already lets
tests supply fakes. Do not abstract everything.

**Get lifecycles right, and document the conventions.** Sessions per request; engine
and config as startup singletons. Record the DI conventions — constructor injection,
the composition root's location, no service locators — in `CLAUDE.md`
([`templates/claude-md-starter.md`](../../templates/claude-md-starter.md)) so the
code and the AI stay consistent.

## Anti-Patterns

**Hard-Coded Dependencies.** Classes that `new` up their own collaborators or read
globals internally — the untestable, dishonest class. The tell: a service you cannot
instantiate in a test without a database.

**The Service Locator.** A global registry or container that classes pull
dependencies from inside their methods, hiding dependencies and restoring global
state. Widely considered an anti-pattern *relative to* DI precisely because it
obscures what a class needs. The tell: `container.get(...)` inside business logic.

**The DI Container Cargo Cult.** A heavyweight container and its configuration
imported into a Python app that FastAPI `Depends` would serve, adding machinery and
magic for no benefit. The tell: a container library in a small app whose graph would
fit in one readable `deps.py`.

**Over-Injection.** Injecting constants, pure functions, and never-varying
collaborators, or defining a `Protocol` for every dependency — ceremony at seams that
never move. The tell: a constructor with ten parameters, half of which are stable
utilities.

**Scope Leak.** Request-scoped dependencies shared as singletons (or singletons
rebuilt per request) — state corruption or resource waste. The tell: one database
session serving many concurrent requests, or a new engine per call.

## Decision Tree

"I have a dependency — how should I provide it?"

```
Does this collaborator ever need to be swapped, faked, or independently tested?
│
├── NO (a pure function, a constant, a stable utility)
│        └──► Use it directly. Injecting it is ceremony (over-injection).
│
└── YES ──► INJECT it, via the CONSTRUCTOR.
     │
     Do you need genuine substitutability or a defined port (Clean Arch)?
     │
     ├── YES ──► Inject an abstraction (a Protocol).
     └── NO ───► Inject the concrete type. (Python duck typing still lets tests
                 pass fakes — no Protocol needed.)

WHO assembles the graph?
   └──► The composition root — FastAPI `Depends`, or the entry function.
        NEVER a global registry the class pulls from (that's a service locator).

DO YOU NEED A DI CONTAINER?
   └──► Almost never in Python. Use FastAPI `Depends` + constructor injection.
        Add a container only if a large graph makes manual wiring genuinely painful.

WHAT SCOPE?
   ├── DB session, request-scoped context ──► per request (framework-scoped).
   └── Engine, connection pool, config ─────► singleton, created once at startup.
```

## Checklist

### Implementation Checklist

- [ ] Classes receive dependencies via the constructor; none constructs its own collaborators or reads globals.
- [ ] The object graph is assembled in one composition root (FastAPI `Depends` / entry function).
- [ ] No class fetches dependencies from a global registry inside its methods (no service locator).
- [ ] Abstractions (`Protocol`) are injected only where substitutability or a port is needed; concrete types elsewhere.
- [ ] Dependency scopes are correct: sessions per request, engine/config as startup singletons.
- [ ] At least one class is tested by injecting fakes, with no database or framework.

### Architecture Checklist

- [ ] Dependency injection is used at the seams that move; stable collaborators are not needlessly injected or abstracted.
- [ ] No DI container was added where FastAPI `Depends` / constructor injection suffices.
- [ ] The composition root is in one findable place, and the graph is readable there.
- [ ] Ports (Protocols) exist where Clean Architecture (Chapter 03) requires them, and not gratuitously elsewhere.
- [ ] The DI conventions are documented in `CLAUDE.md`.

### Code Review Checklist

- [ ] No class hard-codes or self-constructs its dependencies (watch AI diffs).
- [ ] No service-locator / global-registry access was introduced.
- [ ] No dependency-scope error (request-scoped shared as singleton, or vice versa).
- [ ] No heavyweight DI container crept in where the framework's DI would do.
- [ ] New constructors take what they need explicitly, without hidden globals.

*(A Deployment Checklist is not applicable — dependency injection is a
code-structure concern.)*

## Exercises

**1. Inject to test.** Take a class that hard-codes its dependencies (write one, or
have an assistant generate a "self-contained" service) and refactor it to constructor
injection, wiring it in a FastAPI `deps.py`. Then write a test that injects an
in-memory fake and runs with no database. The artifact is the before/after plus the
database-free test — the concrete proof of what injection bought.

**2. Right-size the DI.** Given a scenario where a teammate added a DI-container
library to a mid-sized FastAPI app, argue in writing whether it earns its place
versus FastAPI `Depends` and constructor injection. The artifact is the argument,
with the specific conditions (graph size, wiring pain) that would justify a container
— the judgment this chapter is about.

**3. Fix the scopes.** Take code with dependency-scope bugs — a session stored at
module level, an engine created per request (write them, or find them in
AI-generated code) — and correct each lifecycle, explaining the bug each one would
cause in production. The artifact is the fixes with their failure modes named.

## Further Reading

- **Inversion of Control Containers and the Dependency Injection Pattern** (Martin
  Fowler, martinfowler.com, 2004) — the foundational article that named the pattern,
  distinguished the forms of injection, and drew the crucial contrast with the
  Service Locator. Still the clearest explanation of what DI is and is not.
- **The Dependency Inversion Principle** (Robert C. Martin) — the "D" of SOLID:
  depend on abstractions, not concretions. The principle that DI is the technique for
  achieving, and the conceptual link back to the ports of Chapter 03.
- **FastAPI documentation — Dependencies** (fastapi.tiangolo.com) — the framework's
  built-in DI system, including sub-dependencies and `dependency_overrides` for
  testing. For most Python web apps, this is the only DI machinery you need.
- **Dependency Injection Principles, Practices, and Patterns** (Mark Seemann &
  Steven van Deursen) — the deepest treatment of composition roots, injection forms,
  and why the service locator is an anti-pattern. Read it for the principles, with the
  caveat that its .NET examples use far heavier container machinery than idiomatic
  Python wants.

# Error Handling & API Versioning

## Introduction

This chapter covers two concerns that look unrelated and are in fact the same
concern: keeping the API's contract robust over time. **Error handling** is how the
API behaves when things go wrong — and the shape and codes of errors are part of the
contract clients depend on, every bit as much as the success responses.
**API versioning** is how the contract evolves without breaking the clients already
built against it. Both are about honoring a promise to consumers across time.

Error handling has appeared throughout the handbook as domain exceptions raised in
the service and mapped to HTTP at the boundary (Stage 2; Stage 3, Chapters 01–04).
This chapter makes that systematic: one consistent error contract across the whole
API, a clean separation between *expected* failures (a validation error, a
not-found) and *unexpected* ones (a bug, a downstream outage), and the ironclad rule
that internal details never leak to clients. Versioning then addresses the harder,
slower problem: an API is a contract with consumers you often do not control, so
changing it carelessly breaks them — and the best versioning strategy is mostly
about *not needing to version* by evolving additively.

The connecting insight is that a production API is a long-lived public commitment.
Its errors must be predictable and safe, and its evolution must be backward-
compatible by default, because on the other side of every endpoint is a client — a
frontend, a mobile app, a customer's integration — that breaks when the contract
does.

## Why It Matters

Error handling and versioning are where an API reveals whether it was built for a
demo or for real clients over years.

Bad error handling fails in three expensive ways. It **leaks internals** — stack
traces, SQL errors, exception strings returned to clients — which is both
unprofessional and a security disclosure, handing attackers a map of your stack and
schema. It is **inconsistent** — every endpoint invents its own error shape — so
every client must special-case every endpoint, and no client can handle errors
generically. And it **conflates expected and unexpected failures** — a client's bad
input and a server's own bug look the same — so clients cannot react correctly and
your monitoring cannot tell "user typo" from "the database is down."

Bad versioning fails more slowly and more publicly. An API is a contract, and when
you rename a field, remove one, change a type, or tighten a validation rule, every
consumer built against the old shape breaks — and for a public API those are
customers' integrations you cannot fix. Without a versioning strategy, you are
choosing between never improving the API and breaking your users; with one, you can
evolve while honoring what you already promised.

The AI dimension shows up on both sides. Assistants return `str(exception)` straight
to the client (leaking internals), map every failure to a generic 500 (or worse, a
misleading 4xx), invent a different error shape per endpoint, and — for versioning —
change an existing endpoint's contract in place without realizing the change is
breaking. Each produces a working demo and a fragile, leaky, or contract-breaking
API in production.

## Mental Model

Errors split into two kinds that must be handled differently, and the contract must
be one consistent shape for both:

```
   AN ERROR OCCURS
        │
        ├── EXPECTED (a normal outcome the domain models)
        │     validation failed · not found · conflict · unauthorized · rate-limited
        │     └─► specific 4xx + a stable error CODE + a safe, human message
        │         (the client can react programmatically; this is part of the contract)
        │
        └── UNEXPECTED (a bug, a downstream outage — you did not model this)
              an unhandled exception, a database down, a null you didn't expect
              └─► 500, generic message to the client, FULL detail LOGGED server-side
                  with a request id, and an ALERT. Never leak the detail outward.

   ONE ERROR CONTRACT for both (RFC 9457 problem+json):
     { "type", "title", "status", "detail", "code", "request_id" }
   consistent across every endpoint — clients handle errors generically.
```

```
   API EVOLUTION OVER TIME
        │
        ├── NON-BREAKING (additive): new optional field, new endpoint, looser validation
        │     └─► just ship it. No version bump. (Tolerant clients ignore new fields.)
        │
        └── BREAKING: remove/rename a field, change a type, tighten validation,
            change semantics
              └─► for consumers you don't control: NEW VERSION + deprecate the old
                  (expand → migrate clients → contract — same pattern as DB migrations)
                  for internal-only clients: coordinate and evolve, less ceremony
```

Four principles carry the chapter:

**Distinguish expected from unexpected failures.** Expected failures are part of the
domain — a validation error, a missing resource, a conflict — and get a specific 4xx
with a stable code the client can branch on. Unexpected failures are bugs or outages
you did not model — they get a 500, a generic client message, and full server-side
logging plus an alert. Treating a bug as a 4xx hides it from monitoring; treating an
expected outcome as a 500 confuses clients.

**Never leak internals; always attach a correlation ID.** Clients get a clean
message and a stable code, never a stack trace, SQL, or exception string. The detail
is logged server-side against a `request_id` that is *also* returned to the client,
so a user can quote the ID and support can find the exact failure — diagnosis without
disclosure.

**One error contract across the whole API.** Every error, from every endpoint, has
the same shape (the RFC 9457 `problem+json` standard is the sensible default), so
clients handle errors generically instead of special-casing each endpoint. This is
enforced by *centralized* exception handlers, not per-endpoint `try/except`.

**Evolve additively; version only for unavoidable breaking changes.** Adding an
optional field or a new endpoint breaks no one and needs no version. Removing,
renaming, retyping, or tightening breaks clients — so avoid it when you can (additive
evolution, tolerant readers), and when you cannot, introduce a new version and
deprecate the old on a published timeline. Versioning is the fallback for when
additive evolution is impossible, not the first tool.

A working definition:

> **Error handling makes failure part of a consistent, safe contract — expected
> errors as coded 4xx, unexpected ones as logged-and-alerted 500s, never leaking
> internals. Versioning manages the contract's evolution — additive by default,
> a new version only when a breaking change to consumers you don't control is
> unavoidable. Both keep the API's promise to its clients over time.**

## Production Example

**Invoicely** has two forcing functions for this chapter. Internally, its endpoints
raise domain errors (from Chapters 01–04) that need to become consistent, safe HTTP
responses instead of leaking exceptions. Externally, Invoicely is exposing a
**public API** so customers can build integrations (the QuickBooks-adjacent
integrations from earlier stages imply third-party consumers) — which means its
contract is now something other companies depend on and cannot be broken casually.

We will build a single error contract (`problem+json`) with a domain-exception
hierarchy and centralized handlers that map expected errors to coded 4xx responses
and catch everything unexpected as a logged, alerted, generic 500 with a request ID.
Then we will set up URL-path versioning for the public API and work a real evolution:
renaming `total` to `amount_due` — a breaking change — done the right way through
additive evolution and, where truly necessary, a new version with deprecation. The
example shows both halves of "keep the contract's promise": errors clients can rely
on, and changes that don't break them.

## Folder Structure

```
core/
├── errors.py             # domain-exception hierarchy (AppError + subclasses)
├── error_handlers.py     # centralized handlers → one problem+json contract
├── problem.py            # the RFC 9457 problem+json response model
└── request_id.py         # middleware: assign/propagate a correlation id
app/
├── main.py               # register exception handlers + version routers
└── api/
    ├── v1/               # version 1 routers (the public contract clients built against)
    └── v2/               # version 2 (only when a breaking change forced it)
```

Why this shape:

- **`core/errors.py`** holds one exception hierarchy so the domain raises meaningful
  errors (`NotFoundError`, `ConflictError`) without knowing about HTTP.
- **`core/error_handlers.py`** centralizes the mapping to HTTP in one place, so the
  error contract is uniform and no endpoint hand-rolls it.
- **`core/problem.py`** defines the single response shape every error uses.
- **`api/v1/` and `api/v2/`** make versioning a structural boundary — v1 stays stable
  for existing consumers while v2 carries breaking changes, existing only once a
  breaking change actually forced it.

## Implementation

**The domain-exception hierarchy (`core/errors.py`).** One base, with subclasses that
carry an HTTP status, a stable machine code, and a safe message. The domain raises
these; it never touches HTTP.

```python
class AppError(Exception):
    status_code: int = 500
    code: str = "internal_error"

    def __init__(self, message: str = "An error occurred") -> None:
        self.message = message
        super().__init__(message)


class ValidationError(AppError):
    status_code = 422
    code = "validation_error"


class NotFoundError(AppError):
    status_code = 404
    code = "not_found"


class ConflictError(AppError):
    status_code = 409
    code = "conflict"
```

**The one error contract (`core/problem.py`).** RFC 9457 `problem+json` — a standard
shape every error uses.

```python
from pydantic import BaseModel


class Problem(BaseModel):
    type: str = "about:blank"      # a URI identifying the error type
    title: str                     # short, human, stable
    status: int
    detail: str                    # safe, human message — NEVER internal detail
    code: str                      # stable machine code clients branch on
    request_id: str                # correlation id, also logged server-side
```

**Centralized handlers — expected vs unexpected (`core/error_handlers.py`).** Two
handlers do all the work: one maps known `AppError`s to coded 4xx responses; the
catch-all turns *anything* unexpected into a generic 500 while logging the full detail
and the request ID. No endpoint writes error responses itself.

```python
import logging
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from app.core.errors import AppError
from app.core.problem import Problem

logger = logging.getLogger("app")


def register_error_handlers(app: FastAPI) -> None:

    @app.exception_handler(AppError)
    async def handle_app_error(request: Request, exc: AppError) -> JSONResponse:
        # EXPECTED: a modeled domain error → specific status + stable code + safe message.
        problem = Problem(
            title=exc.code.replace("_", " ").title(),
            status=exc.status_code, detail=exc.message, code=exc.code,
            request_id=request.state.request_id,
        )
        return JSONResponse(problem.model_dump(), status_code=exc.status_code,
                            media_type="application/problem+json")

    @app.exception_handler(Exception)
    async def handle_unexpected(request: Request, exc: Exception) -> JSONResponse:
        # UNEXPECTED: log the FULL detail server-side (with request id) + this fires an alert;
        # return a GENERIC message. The client learns nothing internal.
        logger.exception("unhandled error", extra={"request_id": request.state.request_id})
        problem = Problem(
            title="Internal Server Error", status=500,
            detail="An unexpected error occurred.",   # generic — no stack trace, no SQL
            code="internal_error", request_id=request.state.request_id,
        )
        return JSONResponse(problem.model_dump(), status_code=500,
                            media_type="application/problem+json")
```

**The correlation ID (`core/request_id.py`).** Every request gets an ID, returned to
the client and attached to every log line — diagnosis without disclosure. (Tracing is
deepened in Chapter 08.)

```python
import uuid
from starlette.middleware.base import BaseHTTPMiddleware


class RequestIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        request.state.request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
        response = await call_next(request)
        response.headers["X-Request-ID"] = request.state.request_id   # client can quote it
        return response
```

With this in place, the endpoints from Chapters 01–04 no longer need their own
`try/except` translating domain errors — they just raise `NotFoundError` or
`ValidationError`, and the centralized handlers produce the uniform contract. A bug
they never anticipated becomes a clean 500 (logged, alerted, with an ID), not a leaked
stack trace.

**Versioning — additive evolution, and a version only when forced.** Invoicely's
public API returns an invoice's `total`. Product wants to rename it to `amount_due`.
That rename is **breaking** — every integration reading `total` would break. The
options, cheapest first:

```python
# ADDITIVE (preferred): add the new field, keep the old. Breaks no one.
class InvoiceReadV1(BaseModel):
    id: int
    total: Decimal                      # kept for existing clients
    amount_due: Decimal | None = None   # new; old clients ignore it (tolerant reader)

# Only if the old field MUST go, introduce v2 and deprecate v1.
# app/api/v1/invoices.py  — unchanged contract, plus a deprecation signal
@router_v1.get("/invoices/{id}")
async def get_invoice_v1(...) -> InvoiceReadV1:
    response.headers["Deprecation"] = "true"
    response.headers["Sunset"] = "Wed, 31 Dec 2025 23:59:59 GMT"  # published removal date
    response.headers["Link"] = '</v2/invoices>; rel="successor-version"'
    ...

# app/api/v2/invoices.py — the clean, breaking contract
class InvoiceReadV2(BaseModel):
    id: int
    amount_due: Decimal                 # renamed; v1 clients unaffected because v1 still exists
```

The order of preference is the lesson: first try to make the change **additive** (add
`amount_due` alongside `total`), because a change that breaks no client needs no
version and no ceremony. Only when the old shape genuinely must die do you pay for a
new version — and even then you keep v1 alive with a `Deprecation`/`Sunset` header and
a published timeline, so consumers migrate on notice rather than on a broken morning.
Versioning is the expensive fallback; additive evolution is the default.

## Engineering Decisions

Five decisions define error handling and versioning.

### What error response format?

**Options:** (1) a custom error shape; (2) the RFC 9457 `problem+json` standard; (3)
whatever each endpoint happens to return.

**Trade-offs:** a custom shape is fine if consistent but reinvents a solved problem
and interoperates with nothing. `problem+json` is a published standard clients and
tools understand, with fields for type, title, status, detail, and room for a code.
Per-endpoint shapes are the disaster — no client can handle errors generically.

**Recommendation:** adopt `problem+json` (RFC 9457) as the single contract, extended
with a stable machine `code` and a `request_id`. A standard shape costs nothing over a
custom one and buys interoperability and consistency. Above all, it must be *one*
shape, applied by centralized handlers.

### How are expected and unexpected errors handled?

**Options:** (1) map everything to a generic error; (2) distinguish modeled domain
errors from unexpected exceptions.

**Trade-offs:** one generic handler is simple and destroys information — clients can't
tell a validation failure from an outage, and a real bug looks like a client mistake.
Distinguishing them means a domain-error hierarchy and a catch-all, but yields correct
client behavior (branch on a code) and correct operations (bugs surface as 500s that
alert).

**Recommendation:** distinguish them. Expected domain errors → specific 4xx with a
stable code and safe message; unexpected exceptions → 500, generic message, full
server-side log, and an alert. This split is what lets clients react correctly and
lets you tell "user error" from "our bug" in monitoring.

### How much detail goes to the client?

**Options:** (1) return the exception/stack trace to help debugging; (2) return a
clean message plus a correlation ID, and log the detail server-side.

**Trade-offs:** returning the detail is convenient in development and, in production,
is an information-disclosure vulnerability (stack traces, SQL, internal paths) and
unprofessional. Clean-message-plus-ID gives users something actionable to quote and
keeps the diagnostic detail where only you can see it — at the cost of a logging and
correlation setup.

**Recommendation:** never leak internals to clients; return a safe message, a stable
code, and a `request_id` that is also logged. Support resolves issues from the ID; the
client learns nothing exploitable. Enable verbose errors only in development, never in
production.

### Which versioning strategy?

**Options:** (1) URL path (`/v1/`, `/v2/`); (2) header/content negotiation
(`Accept: application/vnd.api.v2+json`); (3) query parameter; (4) no versioning
(additive evolution only).

**Trade-offs:** URL path is the most visible, cacheable, and easy to route and test,
at the cost of URLs that encode a version. Header negotiation keeps URLs clean and is
more "RESTful" but is harder to test, cache, and discover. Query params are simple but
awkward. No-versioning works only if you can keep every change additive.

**Recommendation:** default to **additive evolution with no version bump**, and when a
breaking change is unavoidable, use **URL-path versioning** for its pragmatism —
visible, cacheable, trivially testable, and obvious to third-party consumers. Reserve
header negotiation for teams that specifically want clean URLs and can absorb the
tooling cost.

### When do you version at all — internal vs public?

**Options:** (1) version everything strictly; (2) version only public APIs, evolve
internal ones with coordination.

**Trade-offs:** versioning everything is safe and heavy — internal clients you deploy
together rarely need the ceremony. Not versioning a public API is reckless — you cannot
coordinate a deploy with customers' integrations. The two audiences have genuinely
different needs.

**Recommendation:** for **internal** APIs (clients you control and deploy together),
evolve additively and coordinate breaking changes with a synchronized deploy — minimal
versioning ceremony. For **public** APIs (third-party consumers you cannot coordinate
with), version strictly and deprecate on a published timeline. Know which kind of
consumer each endpoint has, because it sets how much versioning discipline it needs.

## Trade-offs

These practices trade robustness for effort, and a few are contextual.

**A consistent error contract costs up-front structure.** The exception hierarchy,
the centralized handlers, and the correlation-ID plumbing are setup you pay once —
overkill for a throwaway script, essential for anything with real clients. The payoff
is that every endpoint gets safe, uniform errors for free thereafter; the cost is the
initial scaffolding, which a tiny internal tool may not need.

**Hiding detail from clients trades debugging convenience for safety.** Clean errors
plus a correlation ID mean a developer can't read the failure straight off the
response and must look it up by ID — slightly slower to debug, dramatically safer.
This is the right trade for production always; the mitigation for the friction is good
logging keyed by request ID (Chapter 08).

**Versioning trades agility for stability.** A versioning strategy lets you evolve
without breaking clients, at the cost of maintaining multiple versions — every
supported version is code to keep running, test, and eventually sunset. This is why
additive evolution is preferred: it gives stability *without* the multi-version
maintenance burden. Version only when additive evolution genuinely can't express the
change.

**Additive-only evolution accumulates cruft.** Always adding and never removing keeps
clients working and slowly bloats the API with deprecated fields and compatibility
shims. At some point a new version *is* the right call to shed accumulated weight —
the judgment is that breaking changes are expensive enough to defer, not to avoid
forever. Deprecate and sunset deliberately rather than carrying everything indefinitely.

## Common Mistakes

**Leaking internals in errors.** Returning stack traces, SQL, or exception strings to
clients — an information-disclosure vulnerability and unprofessional. Fix: clean
message + stable code + request ID to the client; full detail logged server-side.

**Inconsistent error shapes.** Every endpoint returning a different error body, so no
client can handle errors generically. Fix: one `problem+json` contract via centralized
handlers, not per-endpoint error construction.

**Conflating expected and unexpected errors.** Mapping everything to a generic 500, or
a real bug to a 4xx, so clients and monitoring can't distinguish user error from server
fault. Fix: modeled domain errors → coded 4xx; unexpected exceptions → 500, logged and
alerted.

**Swallowing exceptions.** Catching broadly and returning success (or continuing in a
corrupt state), hiding failures (Stage 1, Chapter 01). Fix: let unexpected errors reach
the catch-all handler; don't hide them behind a bare `except`.

**Breaking the contract in place.** Renaming, removing, retyping, or tightening a field
on an existing endpoint with no version bump, breaking clients you don't control. Fix:
evolve additively where possible; otherwise a new version with deprecation.

**Versioning everything, or never sunsetting.** Ceremony on internal APIs that could
evolve additively, or public versions kept alive forever because deprecation is never
executed. Fix: additive by default; version public breaking changes; deprecate old
versions on a published, enforced timeline.

## AI Mistakes

Error handling and versioning are contract concerns, and a contract's flaws are
invisible until a *different* client hits them — which the developer testing their own
happy path never does. An assistant optimizes for the working response and leaves the
contract leaky, inconsistent, or quietly broken. Review generated code for what
clients and operators experience when things go wrong or change.

### Claude Code: leaking internal detail to the client

Asked to handle errors, Claude Code frequently returns the exception straight to the
caller — `detail=str(exc)`, or FastAPI's debug traceback, or a database error message
— because it is the most direct way to surface "what went wrong" and it looks helpful
in development. In production it discloses the stack, the schema, and internal paths to
anyone who triggers an error.

**Detect:** `str(exception)` or an exception object in a response body; raw database or
framework error text returned to clients; debug mode / verbose tracebacks reachable in
production.

**Fix:** require safe errors plus server-side detail:

> Never return exception messages, stack traces, or database errors to the client. Map
> expected domain errors to a safe message and a stable code; for unexpected errors
> return a generic message and a `request_id`, and log the full detail server-side.
> Verbose errors are development-only.

### GPT: conflating expected and unexpected failures

GPT-family models tend to funnel every error through one generic handler — often a
blanket 400 or 500 for everything — so a client's validation mistake, a missing
resource, and a genuine server bug are indistinguishable to both the client and the
monitoring. Real bugs hide among expected errors, and clients can't branch on outcome.

**Detect:** a single catch-all mapping all errors to one status; domain errors and
unexpected exceptions handled identically; bugs surfaced as 4xx (so they never alert),
or expected outcomes surfaced as 500 (so they page on-call for a user typo).

**Fix:** require the split:

> Distinguish expected domain errors from unexpected exceptions. Modeled errors
> (validation, not found, conflict) return a specific 4xx with a stable code;
> unexpected exceptions return 500, are logged with full detail, and trigger an alert.
> Never map a bug to a 4xx or an expected outcome to a 500.

### Cursor: silent breaking changes to the contract

Editing an existing endpoint inline, Cursor readily renames a response field, changes a
type, removes a field, or tightens a validation rule — breaking every client built
against the old shape — because from the edit site the change looks like a local
improvement and there is no visible signal that the endpoint is a public contract.

**Detect:** a rename/removal/type-change/newly-required field on an existing endpoint;
tightened validation on a request model; changed semantics — all with no new version and
no deprecation.

**Fix:** treat the contract as fixed:

> This endpoint is a contract clients depend on. Prefer an additive change (add a new
> optional field, keep the old). A breaking change — renaming, removing, retyping, or
> tightening — requires a new API version with the old one kept and deprecated on a
> published timeline. Do not change an existing endpoint's contract in place.

## Best Practices

**One error contract, applied centrally.** Adopt `problem+json` (RFC 9457) with a
stable `code` and `request_id`, produced by centralized exception handlers — never
per-endpoint error bodies — so every client handles errors the same way.

**Split expected from unexpected, and alert on the unexpected.** Modeled domain errors
become coded 4xx responses; unexpected exceptions become 500s that are logged in full
and alerted. This is what makes both clients and monitoring correct.

**Never leak internals; always return a correlation ID.** Clients get a safe message
and a stable code; the stack trace, SQL, and internals are logged server-side against a
`request_id` returned to the client for support to trace (Chapter 08).

**Evolve APIs additively.** Add optional fields and new endpoints freely; treat
removing, renaming, retyping, and tightening as breaking. A change that breaks no client
needs no version — this is the cheapest and best evolution.

**Version public breaking changes, and deprecate on a timeline.** When a breaking
change to consumers you don't control is unavoidable, introduce a new version
(URL-path), keep the old alive with `Deprecation`/`Sunset` headers and communication,
and actually remove it on the published date. Record versioning and deprecation
decisions in an ADR ([`templates/adr.md`](../../templates/adr.md)); document the error
contract in `CLAUDE.md`.

## Anti-Patterns

**The Leaky 500.** Stack traces, SQL, or exception strings returned to clients — an
information-disclosure hole wearing the costume of a helpful error. The tell:
`str(exc)` in a response, or a production traceback reachable by triggering an error.

**The Snowflake Error.** A different error shape per endpoint, so clients special-case
each one and no generic error handling is possible. The tell: `{"error": ...}` here,
`{"message": ...}` there, `{"detail": ...}` elsewhere.

**The Undifferentiated Handler.** All errors funneled to one status, hiding bugs among
expected outcomes and paging on-call for user typos. The tell: a single `except` mapping
everything to 400 or 500.

**Versioning by Breakage.** Changing an existing endpoint's contract in place —
rename, remove, retype, tighten — and breaking every client built against it. The tell:
a field renamed on a live public endpoint with no v2 and no deprecation.

**The Eternal Deprecation.** Old versions kept alive forever because the sunset is never
executed, so the API accumulates versions and compatibility cruft indefinitely. The
tell: a `/v1` marked deprecated three years ago and still fully supported, with no
removal date honored.

## Decision Tree

"Something went wrong, or I'm changing the API — how do I keep the contract?"

```
AN ERROR OCCURRED
│
├─ Is it an EXPECTED domain outcome? (validation / not found / conflict / unauthorized)
│    └─► specific 4xx + stable machine code + safe message (problem+json).
│        The client can branch on the code.
│
└─ Is it UNEXPECTED? (a bug, a downstream outage, an unhandled exception)
     └─► 500 + GENERIC message + request_id to the client.
         LOG the full detail server-side (with request_id) and ALERT.
         Never leak stack traces, SQL, or internals outward.

CHANGING THE API
│
├─ Is the change ADDITIVE? (new optional field, new endpoint, looser validation)
│    └─► ship it. No version bump. Clients tolerate new fields.
│
└─ Is it BREAKING? (remove / rename / retype / tighten / change semantics)
     ├─ Internal clients you deploy together? ─► coordinate a synchronized change.
     └─ Public / third-party consumers? ─► NEW VERSION (URL path). Keep the old,
          add Deprecation + Sunset headers, communicate, and remove on the published date.
```

## Checklist

### Implementation Checklist

- [ ] All errors use one `problem+json` contract with a stable `code` and a `request_id`, produced by centralized handlers.
- [ ] Expected domain errors map to specific 4xx codes; unexpected exceptions map to a logged, alerted 500.
- [ ] No internal detail (stack trace, SQL, exception string) is ever returned to a client.
- [ ] Every request has a correlation ID, returned to the client and attached to logs.
- [ ] API changes are additive where possible; breaking public changes go through a new version.
- [ ] Deprecated versions carry `Deprecation`/`Sunset` headers and a published removal date.

### Architecture Checklist

- [ ] Error handling is centralized (handlers + hierarchy), not scattered as per-endpoint `try/except`.
- [ ] The error contract is documented and consistent across every endpoint.
- [ ] Public vs internal APIs are identified, and versioning rigor matches (strict for public, additive for internal).
- [ ] A deprecation/sunset process exists and is actually executed, not perpetual.
- [ ] Error-contract and versioning conventions are in `CLAUDE.md`.

### Code Review Checklist

- [ ] No exception string / stack trace / SQL is returned to the client (watch AI diffs).
- [ ] Errors use the shared contract, not an ad-hoc per-endpoint shape.
- [ ] Expected and unexpected errors are distinguished (no bug mapped to 4xx, no expected outcome to 500).
- [ ] No breaking change to an existing endpoint's contract without a new version + deprecation.
- [ ] New endpoints emit the standard error contract and a correlation ID.

### Deployment Checklist

- [ ] Verbose/debug errors are disabled in production; only safe messages leave the service (see [`checklists/production-readiness.md`](../../checklists/production-readiness.md)).
- [ ] Unexpected-error alerts are wired to on-call, keyed by request ID.
- [ ] Deprecated API versions have monitored usage, so you know when it's safe to sunset.
- [ ] Sunset dates are tracked and enforced, not indefinitely extended.

## Exercises

**1. Centralize the errors.** Take a set of endpoints that each build their own error
responses (and one that returns `str(exc)`), and replace them with a domain-exception
hierarchy plus centralized handlers producing one `problem+json` contract with a
request ID. The artifact is the before/after plus a triggered 500 showing a generic
client message and the full detail in the logs under the same request ID.

**2. Make a breaking change safely.** Take Invoicely's public `GET /invoices/{id}`
returning `total` and evolve it to `amount_due` two ways: first additively (both
fields), then — supposing `total` must be removed — via a v2 endpoint with v1 kept and
deprecated. The artifact is both approaches and a one-paragraph recommendation on which
to use and why.

**3. Classify the changes.** Given a list of proposed API changes — add an optional
`notes` field, rename `status` to `state`, make `customer_id` required, add a new
endpoint, change `total` from string to number — classify each as breaking or
non-breaking and state how you'd ship it. The artifact is the classification; the point
is internalizing which changes need a version and which don't.

## Further Reading

- **RFC 9457 — Problem Details for HTTP APIs** (rfc-editor.org) — the standard error
  contract this chapter adopts, superseding RFC 7807. Short and worth reading in full;
  it is the shape your errors should take.
- **API Design Patterns** (JJ Geewax, Manning), the chapters on versioning and
  backward compatibility — a rigorous treatment of what counts as a breaking change and
  how to version and deprecate; the deepest reference for the versioning half of this
  chapter.
- **Stripe API versioning** (stripe.com/blog/api-versioning, and the API docs) — the
  canonical case study in evolving a public API without breaking customers, including
  date-based versions and how they maintain compatibility. Read it for how a serious
  public API handles this in practice.
- **Google API Improvement Proposals — Errors (AIP-193)** (google.aip.dev) — a
  practical, opinionated standard for error responses and codes at scale; a useful
  cross-reference to RFC 9457 when designing your error contract.

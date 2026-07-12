# Authorization

## Introduction

Authentication established *who* is making a request; authorization decides *what
they are allowed to do*. This chapter builds authorization correctly: the models
for expressing permissions (ownership, roles, attributes), where to enforce them
(at the endpoint and in the query), and — most importantly for a SaaS — how to keep
one tenant's data completely inaccessible to another.

As with the previous chapter, the scope is *building it correctly*; the adversarial
framing — Broken Access Control as OWASP's number-one risk, privilege escalation,
attack techniques — is **Stage 9 (Security)**. But the line is thin here, because
the most common authorization mistake *is* the most common web vulnerability: the
**Insecure Direct Object Reference (IDOR)**, where an endpoint fetches a resource by
ID without checking that the caller owns it, so any logged-in user can read anyone's
data by changing a number in the URL. This chapter's central mission is to make that
class of bug structurally impossible in your code.

The reason authorization deserves its own chapter, separate from authentication, is
that authenticating correctly buys you nothing if you then hand every authenticated
user access to every resource. Authentication is the lock on the front door;
authorization is who can open which rooms — and a building where any keyholder can
enter any room is not secure just because the front door locks.

## Why It Matters

Authorization bugs are the most damaging and the most easily missed class of
backend defect, and the reason they are missed is structural: **you test as
yourself.** You log in as one user, click through your own data, everything works —
and you never notice that the same endpoint also returns the *next* user's data if
you change the ID, because you never tried. The bug is invisible from the single-user
seat every developer sits in, and it is catastrophic the moment a customer (or an
attacker) discovers it: one tenant reading another tenant's invoices, customers, and
revenue.

For a multi-tenant SaaS like Invoicely, this is the defining security concern:

- **Tenant isolation.** Every piece of data belongs to an account, and no request
  may ever touch another account's data. This must be enforced in the *query* — every
  read and write scoped to the authenticated principal's tenant — not merely hoped for
  at the UI. A single unscoped query is a cross-tenant data breach.
- **Resource ownership (the IDOR class).** Authenticating a user does not authorize
  them to a specific resource. `GET /invoices/42` must verify that invoice 42 belongs
  to *this* caller's account before returning it. Fetching by ID alone — the natural,
  obvious code — is the vulnerability.
- **Role and permission boundaries.** Within a tenant, not everyone can do
  everything: a member views, an admin edits, an owner manages billing. These
  boundaries must be enforced server-side, derived from the authenticated principal,
  never from anything the client sends.

The AI dimension is acute precisely because authorization is invisible in the
happy path. An assistant will authenticate a user correctly and then write the
IDOR: fetch the resource by ID with no ownership check, because that code is
simpler and *works when you test it as the owner*. It will also reach for the
account ID or role in the request body — trusting the client to say who it is — and
scatter inconsistent checks across endpoints. All three produce a green demo and an
open door.

## Mental Model

Authorization is enforced at two levels, and both are mandatory:

```
   AUTHENTICATED PRINCIPAL (from Chapter 03 — the current account + user + role)
        │  identity and role come from HERE, never from client input
        ▼
   LEVEL 1 — THE ENDPOINT (coarse: "may this ROLE do this kind of action?")
        require the role/permission for the operation (deny by default)
        e.g. only admin/owner may DELETE an invoice
        │
        ▼
   LEVEL 2 — THE QUERY (fine: "may this caller touch THIS resource?")
        scope EVERY query to the principal's tenant, and check ownership
        e.g. SELECT ... WHERE id = 42 AND account_id = <caller's account>
        │
        ▼
   (defense in depth) DATABASE ROW-LEVEL SECURITY — a backstop if a query slips

   Miss Level 2 and you have IDOR: any user reads any resource by changing an id.
```

Four principles make authorization sound:

**Deny by default.** Access is forbidden unless explicitly granted. New endpoints,
unrecognized roles, and missing checks must *fail closed* (deny), never fail open
(allow). A permission system whose default is "allow" leaks every access someone
forgot to restrict.

**Identity and permissions come from the authenticated principal, never the
client.** The caller's account, user, and role are derived from the validated token
or session (Chapter 03) — never read from a request body, query parameter, or
client-set header. A client that can say `account_id=7` in a request can read
account 7's data; the account ID must come from *who they authenticated as*, not what
they typed.

**Authorize the specific resource, not just the action.** Passing the endpoint's
role check ("admins may edit invoices") does not authorize editing *this* invoice.
Every access to a specific resource must confirm the resource belongs to the caller's
tenant — enforced in the query (`WHERE id = ? AND account_id = ?`), so an ID that
isn't theirs simply returns nothing. This is the structural cure for IDOR.

**Enforce server-side, and centralize the policy.** Client-side checks (hiding a
button) are UX, not security — the API must enforce everything itself. And the rules
belong in one place (a policy layer, shared dependencies, scoped repository methods),
not scattered as ad-hoc `if` checks that drift out of sync and get forgotten on the
next endpoint.

A working definition:

> **Authorization decides what an authenticated principal may do, enforced at two
> levels — the role/permission for the action at the endpoint, and ownership of the
> specific resource in the query — always deny-by-default, always derived from the
> principal, never trusting the client. Missing the query-level check is IDOR, the
> most common web vulnerability.**

## Production Example

**Invoicely** is multi-tenant: every user belongs to an account, and all data
(invoices, customers, payments) belongs to an account. Within an account, users have
a role — `owner`, `admin`, or `member` — with escalating permissions: members view,
admins manage invoices and customers, owners additionally manage billing and users.

Two authorization jobs run on every request. First, **tenant isolation**: a user in
account A must never, under any circumstance, read or write account B's data — and
this is enforced by scoping every query to the caller's `account_id`. Second,
**role enforcement**: within their account, a member cannot delete an invoice even
though it belongs to their tenant.

We will build both, and center the example on the IDOR contrast — the vulnerable
`GET /invoices/{id}` that fetches by ID alone versus the scoped version that cannot
return another tenant's data — because that single difference is the line between a
secure SaaS and a data breach, and it is exactly the line an assistant crosses by
default.

## Folder Structure

```
core/
├── auth.py               # current principal (Ch 03) + role/permission dependencies
└── authz.py              # policy: role→permission map, require_permission, ownership helpers
modules/invoicing/
├── router.py             # endpoints: require permission (Level 1), pass principal down
├── _repository.py        # queries ALWAYS scoped by account_id (Level 2 — tenant isolation)
└── _service.py           # resource-ownership checks where needed
```

Why this shape:

- **`core/authz.py`** centralizes the policy — the role-to-permission mapping and the
  reusable `require_permission` dependency — so authorization rules live in one place
  and are applied uniformly, not reinvented per endpoint.
- **`_repository.py`** enforces tenant isolation structurally: every method takes the
  caller's `account_id` and filters on it, so a query *cannot* be written that returns
  another tenant's data. This is where IDOR is designed out of existence.
- **`router.py`** applies the coarse role check (Level 1) via a dependency and passes
  the authenticated principal down; it never reads identity from client input.

## Implementation

**The policy and the endpoint-level check (`core/authz.py`).** Roles map to
permissions in one place; a dependency enforces the permission for an operation,
deny-by-default.

```python
from enum import StrEnum
from fastapi import Depends, HTTPException, status
from app.core.auth import CurrentPrincipalDep     # the authenticated user+account+role (Ch 03)


class Permission(StrEnum):
    INVOICE_VIEW = "invoice:view"
    INVOICE_MANAGE = "invoice:manage"
    INVOICE_DELETE = "invoice:delete"
    BILLING_MANAGE = "billing:manage"


ROLE_PERMISSIONS: dict[str, set[Permission]] = {
    "member": {Permission.INVOICE_VIEW},
    "admin":  {Permission.INVOICE_VIEW, Permission.INVOICE_MANAGE, Permission.INVOICE_DELETE},
    "owner":  set(Permission),   # all permissions
}


def require_permission(permission: Permission):
    async def _checker(principal: CurrentPrincipalDep) -> None:
        granted = ROLE_PERMISSIONS.get(principal.role, set())   # unknown role → empty → DENY
        if permission not in granted:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Insufficient permissions")
    return _checker
```

**Tenant-scoped queries — IDOR designed out (`_repository.py`).** Every method takes
`account_id` and filters on it. There is no method to fetch an invoice by ID *without*
the tenant, so the vulnerable query cannot be written by accident.

```python
from sqlalchemy import select
from app.modules.invoicing._models import Invoice


class InvoiceRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    # SCOPED: id AND account_id. An id from another tenant simply returns None.
    async def get(self, invoice_id: int, account_id: int) -> Invoice | None:
        stmt = select(Invoice).where(
            Invoice.id == invoice_id,
            Invoice.account_id == account_id,     # tenant isolation, enforced in SQL
        )
        return await self._session.scalar(stmt)

    async def list_for_account(self, account_id: int, limit: int, offset: int) -> list[Invoice]:
        stmt = (
            select(Invoice).where(Invoice.account_id == account_id)   # never all invoices
            .limit(limit).offset(offset)
        )
        return list(await self._session.scalars(stmt))
```

**The endpoint — both levels, IDOR contrast (`router.py`).**

```python
from fastapi import APIRouter, Depends, HTTPException, status
from app.core.auth import CurrentPrincipalDep
from app.core.authz import Permission, require_permission

router = APIRouter(prefix="/invoices", tags=["invoices"])


# VULNERABLE (do NOT ship): authenticates, then fetches by id with NO ownership check.
# A member of account A reads account B's invoice by guessing the id. This is IDOR.
@router.get("/{invoice_id}/BAD")
async def get_invoice_bad(invoice_id: int, repo: InvoiceRepositoryDep) -> InvoiceRead:
    invoice = await repo.get_by_id_only(invoice_id)        # <-- no account scoping
    if invoice is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    return InvoiceRead.model_validate(invoice)


# CORRECT: Level 1 permission check + Level 2 tenant-scoped query.
@router.get(
    "/{invoice_id}", response_model=InvoiceRead,
    dependencies=[Depends(require_permission(Permission.INVOICE_VIEW))],   # Level 1
)
async def get_invoice(
    invoice_id: int, repo: InvoiceRepositoryDep, principal: CurrentPrincipalDep
) -> InvoiceRead:
    # Level 2: account_id comes from the PRINCIPAL, never from the client.
    invoice = await repo.get(invoice_id, account_id=principal.account_id)
    if invoice is None:
        # Not found AND not-yours are indistinguishable — don't leak existence.
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Invoice not found")
    return InvoiceRead.model_validate(invoice)


@router.delete(
    "/{invoice_id}", status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_permission(Permission.INVOICE_DELETE))],  # members can't delete
)
async def delete_invoice(
    invoice_id: int, service: InvoiceServiceDep, principal: CurrentPrincipalDep, session: SessionDep
) -> None:
    await service.delete_invoice(principal.account_id, invoice_id)  # scoped inside too
    await session.commit()
```

**Defense in depth — PostgreSQL row-level security (optional backstop).** Application
scoping is the primary control; RLS is a safety net so that even a query that *forgets*
the `account_id` filter cannot cross tenants.

```sql
-- Set per request: SET app.current_account = '<caller account id>';
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON invoices
    USING (account_id = current_setting('app.current_account')::int);
-- Now even an unscoped SELECT returns only the current tenant's rows.
```

The through-line is the two levels working together: the `require_permission`
dependency stops a member from deleting anything (Level 1), and the `account_id`
filter in every query stops anyone from touching another tenant's data (Level 2) — with
the account ID always taken from the authenticated principal, never the request. The
vulnerable endpoint differs from the correct one by a single missing filter, and that
one filter is the entire difference between a secure multi-tenant SaaS and a breach.
RLS sits underneath as a backstop for the query someone inevitably forgets to scope.

## Engineering Decisions

Five decisions define an authorization implementation.

### Which authorization model?

**Options:** (1) ownership/tenant scoping only; (2) role-based (RBAC); (3)
attribute/policy-based (ABAC); (4) relationship-based (ReBAC).

**Trade-offs:** ownership-only is the minimum every multi-tenant app needs and is
insufficient once users have different capabilities. RBAC (roles → permissions) covers
the vast majority of SaaS needs simply and understandably. ABAC (policies over
attributes and context) is far more expressive — per-field rules, time/context
conditions — at a large jump in complexity. ReBAC (à la Google Zanzibar) handles deep
sharing graphs and is overkill for most.

**Recommendation:** ownership/tenant scoping (always, non-negotiable) plus RBAC for
capabilities — this covers most SaaS, Invoicely included. Add ABAC only when real
requirements outgrow roles (fine-grained, conditional, per-attribute rules), and treat
ReBAC as a specialist tool for genuine sharing-graph products. Start simple; the model
is easy to make more expressive later and painful to over-build early (Stage 1, Chapter
07).

### Where is authorization enforced?

**Options:** (1) endpoint only (role check); (2) query only (ownership scoping); (3)
both.

**Trade-offs:** endpoint-only checks the role but not the specific resource — it lets a
valid admin of account A act on account B's data (still IDOR). Query-only enforces
tenant isolation but not capability — a member could hit a delete endpoint that only
scopes by tenant. Both levels together check *both* "may this role do this action" and
"does this specific resource belong to this caller."

**Recommendation:** both, always. Level 1 (endpoint/role) and Level 2 (query/ownership)
guard different things and neither substitutes for the other. The most dangerous single
mistake is having Level 1 and skipping Level 2 — it feels authorized (there's a
permission check!) while being wide open to IDOR.

### How is tenant isolation enforced — application scoping or database RLS?

**Options:** (1) application-level query scoping; (2) database row-level security; (3)
both.

**Trade-offs:** application scoping (every query filtered by `account_id`) is explicit,
portable, and testable, but relies on every query being written correctly — one
forgotten filter is a breach. Database RLS enforces isolation in the database itself,
catching forgotten filters, at the cost of setup complexity and a per-request tenant
context. Both gives primary control plus a backstop.

**Recommendation:** application-level scoping as the primary, enforced structurally
(repository methods that *require* `account_id`, so an unscoped query can't be written
casually); add RLS as defense-in-depth for high-stakes multi-tenant data, so a mistake
in the app layer still can't cross tenants. The engineering move that matters most is
making the scoped query the *only easy* query to write.

### Deny by default or allow by default?

**Options:** (1) deny by default (fail closed); (2) allow by default (fail open).

**Trade-offs:** deny-by-default means every access must be explicitly granted, so a
forgotten check blocks access (a visible bug caught in testing) rather than exposing
data (an invisible breach). Allow-by-default is more convenient during development and
turns every omission into a vulnerability.

**Recommendation:** deny by default, without exception. Unknown roles map to no
permissions, new endpoints are unauthorized until a check is added, and any ambiguity
resolves to denial. The failure mode of deny-by-default is a support ticket; the
failure mode of allow-by-default is a disclosure notice.

### Centralized policy or inline checks?

**Options:** (1) a centralized policy layer / shared dependencies; (2) ad-hoc `if`
checks in each endpoint.

**Trade-offs:** centralized policy keeps the rules consistent, auditable, and
uniformly applied, at the cost of an abstraction to design. Inline checks are quick per
endpoint and drift out of sync, get copied inconsistently, and — the real danger — get
forgotten entirely on the next endpoint someone adds.

**Recommendation:** centralize the policy (a role/permission map, reusable
`require_permission` dependencies, repository methods that enforce scoping) so
authorization is applied the same way everywhere and a new endpoint has to *opt out* of
protection rather than *opt in*. Scattered checks are how the one unprotected endpoint
ends up in production.

## Trade-offs

Authorization choices trade security, flexibility, and complexity.

**Model expressiveness trades against simplicity.** RBAC is simple and understandable
and cannot express "a user may edit invoices they created but only before they're
sent." ABAC can express that and much more, at a steep cost in complexity, policy
management, and the difficulty of reasoning about who can actually do what. Reaching for
ABAC before roles genuinely fail you is over-engineering; clinging to RBAC when rules
are truly attribute-dependent is contortion. Match the model to the real rules.

**Database RLS trades setup cost for a safety net.** RLS meaningfully reduces the blast
radius of a forgotten application-level filter, which for multi-tenant data is a
compelling backstop — but it adds setup complexity, a per-request tenant context to
manage, and a second place authorization lives (which can confuse debugging). For
high-stakes tenant data the safety net is worth it; for a low-stakes internal tool the
application layer alone may suffice.

**Fine-grained permissions trade safety for management overhead.** Many narrow
permissions give precise control and a large surface to administer and reason about;
few broad roles are easy to manage and blunt. Most products want a small set of
well-chosen roles and add granularity only where a real need appears, resisting both a
single god-admin role and a sprawling permission matrix nobody understands.

**Server-side enforcement is non-negotiable, but client-side checks still matter.**
The API must enforce everything; client-side checks (hiding a delete button a user
can't use) are pure UX and provide zero security. The trade is only about UX polish —
never treat a client-side check as a control, and never skip the server-side one
because the UI already hides the action.

## Common Mistakes

**IDOR — fetching a resource without an ownership check.** `GET /invoices/{id}` that
looks up by ID alone, so any authenticated user reads any tenant's data by changing the
number. The single most common and most damaging web vulnerability. Fix: scope every
resource query by the authenticated principal's `account_id`; not-yours and not-found
are the same 404.

**Trusting client-supplied identity or role.** Reading `account_id`, `user_id`, or
`role` from the request body, query string, or a client-set header, so a client claims
to be anyone. Fix: derive identity and permissions solely from the authenticated
principal (Chapter 03); never from client input.

**Enforcing only at one level.** Checking the role at the endpoint but not scoping the
query (admin of A acts on B's data), or scoping the query but not checking capability (a
member reaches a delete). Fix: enforce both levels — role at the endpoint, ownership in
the query.

**Allow-by-default / fail-open.** Unrecognized roles or missing checks that grant
access, and new endpoints that ship unprotected. Fix: deny by default; unknown roles get
no permissions; a missing check blocks, not opens.

**Scattered, inconsistent checks.** Ad-hoc authorization copied unevenly across
endpoints, so some are protected and the newest one isn't. Fix: centralize policy in
shared dependencies and scoped repository methods applied uniformly.

**Authorization only in the UI.** Relying on a hidden button or a client-side role check
for security, while the API enforces nothing. Fix: the server enforces everything;
client checks are UX only.

## AI Mistakes

Authorization is invisible in single-user testing — you test as yourself and never try
another tenant's IDs — so an assistant produces access-control code that passes every
test the developer would run and is wide open to anyone who probes it. Review generated
endpoints specifically for the checks that only matter when *someone else* calls them.

### Claude Code: the IDOR — fetching by ID with no ownership check

Asked to build "get a resource by ID," Claude Code writes exactly that: look up the
resource by its ID and return it, with no tenant or ownership filter — because that is
the simplest correct-looking code and it works perfectly when the developer tests it on
their own data. It is the textbook IDOR, and it ships constantly.

**Detect:** a resource fetched by ID alone (`repo.get(id)`, `session.get(Model, id)`)
with no `account_id`/owner filter; an endpoint that authenticates the user but never ties
the resource to them.

**Fix:** require ownership scoping on every resource access:

> Every query for a specific resource must be scoped to the authenticated principal's
> tenant: filter by `account_id` (from the principal, never the request) in the same
> query, so an ID belonging to another tenant returns nothing. Never fetch a resource by
> ID alone. Not-found and not-authorized both return 404.

### GPT: trusting client-supplied identity or role

GPT-family models frequently take the `account_id`, `user_id`, or `role` from the
request — a body field, a query parameter, a header — and authorize against it, because
the endpoint signature reads naturally and works when the client sends its own ID. It
means any client can act as any account by changing a field.

**Detect:** `account_id`/`user_id`/`role` appearing as a request parameter or body field
used for authorization; permission decisions based on anything the client sent rather
than the validated principal.

**Fix:** identity comes only from the principal:

> Never read identity or role from client input (body, query, or headers) for
> authorization. The account, user, and role come exclusively from the authenticated
> principal derived from the token/session (Chapter 03). Client-supplied `account_id` or
> `role` fields must never influence an access decision.

### Cursor: scattered checks and fail-open defaults

Adding endpoints inline, Cursor tends to protect some and forget others, and to write
permission logic that defaults to *allow* when a role is unrecognized or a check is
inconclusive — because each edit is local and the global policy isn't in view. The result
is inconsistent coverage and fail-open gaps.

**Detect:** new endpoints with no permission dependency; role checks that `return True` /
allow on an unrecognized role or a missing mapping; authorization logic that differs
endpoint to endpoint.

**Fix:** centralize and fail closed:

> Apply the shared `require_permission` dependency and tenant-scoped repository methods
> to every endpoint — do not write ad-hoc inline checks. Authorization is deny-by-default:
> an unknown role or missing mapping grants nothing. Every new endpoint must be protected
> the same way as the others.

## Best Practices

**Deny by default and derive identity from the principal.** Access is forbidden unless
explicitly granted; unknown roles get nothing; and the account, user, and role come only
from the authenticated principal, never from client input.

**Enforce at both levels.** Role/permission for the action at the endpoint (Level 1), and
tenant/ownership for the specific resource in the query (Level 2). Neither substitutes
for the other; missing Level 2 is IDOR.

**Make the scoped query the only easy query.** Repository methods that *require*
`account_id`, so tenant isolation is structural and an unscoped query can't be written
casually. For high-stakes data, add database row-level security as a backstop.

**Centralize the policy.** One role→permission map, reusable permission dependencies, and
scoped repositories applied uniformly — so a new endpoint opts *out* of protection rather
than accidentally shipping without it. Never scatter ad-hoc checks.

**Enforce server-side and test with multiple tenants.** Client-side checks are UX only;
the API enforces everything. Write tests that attempt cross-tenant access (user A fetching
B's resource) and expect a 404 — the test the single-user developer never runs. Document
the authorization model in `CLAUDE.md`; attack-side hardening is Stage 9.

## Anti-Patterns

**IDOR (the Missing Ownership Check).** Resources fetched by ID with no tenant/owner
scoping, so any user reads any data by changing the ID — OWASP's number-one risk. The
tell: `get(id)` with no account filter, and tests that only ever act as the resource's
owner.

**The Trusted Client.** Identity or role taken from request input and believed, so a
client authorizes itself. The tell: `account_id`/`role` as a request parameter used in an
access decision.

**Single-Level Enforcement.** Role checked at the endpoint but resources not scoped (or
vice versa), leaving one door open. The tell: a permission dependency with no `account_id`
filter in the query behind it.

**Fail-Open Authorization.** Defaults and unrecognized cases that grant access, and
unprotected new endpoints. The tell: authorization logic that allows on an unknown role,
or an endpoint with no permission check at all.

**Scattered Checks.** Ad-hoc authorization copied unevenly across endpoints until one is
forgotten. The tell: three different ways of checking permissions in three routers, and a
fourth router with none.

**UI-Only Authorization.** Security resting on a hidden button while the API enforces
nothing. The tell: an endpoint that works fine when called directly with a low-privilege
token, because only the frontend was hiding it.

## Decision Tree

"A request wants to act on a resource — is it authorized?"

```
Identity, account, and role ──► take them from the AUTHENTICATED PRINCIPAL only.
    (Never from the request body, query, or a client header.)
        │
LEVEL 1 — ENDPOINT: does this role have permission for this ACTION?
    ├─ NO  ──► 403 Forbidden. (Deny by default; unknown role → no permissions.)
    └─ YES ──►
        │
LEVEL 2 — QUERY: does THIS specific resource belong to the caller's tenant?
    scope the query: WHERE id = ? AND account_id = <principal.account_id>
    ├─ resource not returned (wrong tenant or absent) ──► 404 (don't leak existence)
    └─ returned ──► proceed.
        │
DEFENSE IN DEPTH: is this high-stakes multi-tenant data?
    └─ YES ──► also enable database row-level security as a backstop.

Enforcement location: SERVER-SIDE always. Client-side checks are UX, never security.
Policy location: CENTRALIZED (shared dependency + scoped repos), never ad-hoc per endpoint.
```

## Checklist

### Implementation Checklist

- [ ] Every resource query is scoped by the authenticated principal's `account_id`; no fetch-by-ID-alone (no IDOR).
- [ ] Identity, account, and role are derived from the principal — never read from request input.
- [ ] Both levels enforced: role/permission at the endpoint and tenant/ownership in the query.
- [ ] Authorization is deny-by-default; unknown roles and missing mappings grant nothing.
- [ ] Policy is centralized (role→permission map + shared dependencies + scoped repositories), not inline.
- [ ] Not-found and not-authorized both return 404 (existence isn't leaked).

### Architecture Checklist

- [ ] The authorization model (ownership + RBAC, or beyond) fits the real rules and isn't over-built.
- [ ] Tenant isolation is structural — repository methods require `account_id`, so unscoped queries aren't easy to write.
- [ ] High-stakes tenant data has database row-level security as a backstop.
- [ ] New endpoints are protected by default (opt out, not opt in).
- [ ] The authorization model is documented in `CLAUDE.md`; attack-side hardening is tracked for Stage 9.

### Code Review Checklist

- [ ] No resource fetched by ID without a tenant/ownership filter (watch AI diffs — this is the #1 thing to catch).
- [ ] No `account_id`/`user_id`/`role` read from the request and used for authorization.
- [ ] Every new endpoint has both an endpoint-level permission check and a scoped query.
- [ ] No fail-open logic; unknown roles/permissions deny.
- [ ] A cross-tenant access test exists (user A cannot reach B's resource) and passes.

### Deployment Checklist

- [ ] If using database row-level security, the per-request tenant context is set reliably on every connection (see [`checklists/production-readiness.md`](../../checklists/production-readiness.md)).
- [ ] Authorization failures are logged (with principal and resource) for audit and incident response.
- [ ] Role/permission changes take effect promptly (consider token TTL / refresh interactions from Chapter 03).

## Exercises

**1. Exploit and fix an IDOR.** Take an endpoint that fetches a resource by ID with no
ownership check (write it, or have an assistant generate "get an invoice by id"). As a
second tenant's user, fetch the first tenant's resource to demonstrate the breach, then
fix it by scoping the query to the principal's account. The artifact is the exploit
request, the fix, and a cross-tenant test that now returns 404.

**2. Build the two-level check.** Implement `DELETE /invoices/{id}` for Invoicely so that
a `member` is refused (403) regardless of tenant, a non-owner tenant gets 404, and an
`admin` of the owning tenant succeeds (204). The artifact is the endpoint plus three tests
— one per case — proving both levels are enforced.

**3. Design the isolation strategy.** For Invoicely, decide how tenant isolation is
enforced: application-level scoping, database RLS, or both, and justify it for
invoice/payment data. The artifact is the decision with its reasoning, plus the concrete
mechanism (how `account_id` reaches every query, or how the RLS tenant context is set per
request).

## Further Reading

- **OWASP Top 10 — A01: Broken Access Control** and the **Authorization Cheat Sheet**
  (owasp.org, cheatsheetseries.owasp.org) — the authoritative treatment of the risk this
  chapter defends against, including IDOR, and a checklist for correct enforcement. The
  reference to audit any implementation against. (The full attack catalog is Stage 9.)
- **PostgreSQL documentation — Row Security Policies** (postgresql.org/docs) — how to
  implement row-level security as a tenant-isolation backstop, including the per-session
  tenant context the policy reads.
- **Google Zanzibar: Google's Consistent, Global Authorization System** (the paper, and
  its open-source descendants such as OpenFGA/SpiceDB) — background on relationship-based
  authorization for products with genuine sharing graphs; read it to know what problem
  ReBAC solves and when RBAC/ABAC are enough without it.
- **API Design Patterns** (JJ Geewax, Manning), the chapters on access control — how
  authorization interacts with API design, resource hierarchies, and multi-tenancy;
  complements this chapter's enforcement focus with contract-design considerations.

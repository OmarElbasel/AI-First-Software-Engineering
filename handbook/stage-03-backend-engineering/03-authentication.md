# Authentication

## Introduction

Authentication answers one question — *who is making this request?* — and it is the
question everything else in a backend depends on. This chapter builds authentication
correctly: how to store passwords, how to represent a logged-in session (server-side
sessions versus stateless tokens), how to issue and verify access and refresh
tokens, and how to expose the authenticated principal to the rest of the app as a
dependency.

Two boundaries frame the chapter. First, it teaches how to *build* authentication
correctly; the adversarial side — brute force, credential stuffing, token theft,
rate limiting, the OWASP catalog — is **Stage 9 (Security)**, which this chapter
references but does not duplicate. Second, and just as important: for a real
production product, the soundest engineering decision is often *not* to build
authentication at all but to buy it (Stage 1, Chapter 06's "afternoon auth
prototype" is exactly this trap — an AI-generated login that looks done and is
missing the ninety percent that matters). This chapter teaches how authentication
works and how to implement it correctly *when you must* — and treats "use a managed
provider" as a first-class option, not a cop-out.

The reason to understand it deeply even if you buy it: you still have to integrate
it, reason about its tokens, protect your endpoints with it, and debug it at 2 AM.
Authentication is the highest-consequence code most backends contain — a mistake
here is not a bug, it is a breach — and it is a domain where "the login works" hides
almost every failure that matters.

## Why It Matters

Authentication failures are categorically different from other bugs. A broken
feature inconveniences users; broken authentication exposes every user's data,
becomes a disclosure obligation, and ends trust in the product. And its failures are
almost entirely invisible in the demo: login works, the happy path is green, and the
system is simultaneously storing passwords reversibly, issuing tokens that never
expire, and putting them where any script on the page can steal them.

The concerns that decide whether authentication is sound:

- **Password storage.** Passwords must be hashed with a slow, salted,
  purpose-built algorithm (argon2id or bcrypt) — never stored in plaintext, never
  "encrypted" (reversible), and never run through a fast hash (MD5, SHA-256) that a
  GPU cracks by the billion per second. This one decision separates "a leaked
  database is a scramble to rotate" from "every user's password is now public."
- **Session representation.** A logged-in user is represented either by a
  server-side session (an opaque ID in a cookie, state in a store) or a stateless
  token (a signed JWT the client holds). The choice governs revocation, scaling, and
  attack surface, and it is routinely made by accident.
- **Token design and handling.** Tokens must expire, be revocable in practice,
  carry only non-sensitive claims (a JWT is *signed, not encrypted* — anyone can read
  it), and be stored where hostile JavaScript cannot reach them. Each of these is a
  default an assistant gets wrong.

The AI dimension is at its most dangerous here, because authentication is the
archetypal "looks finished, is a breach" domain. An assistant will generate a login
system that authenticates correctly and simultaneously hashes with SHA-256, issues
non-expiring tokens, packs the user's role and email into a JWT as if it were
secret, and tells the frontend to keep the token in `localStorage`. Every one of
those passes a functional test. This is precisely why Stage 1, Chapter 06 argued that
buying authentication is often the right call — and why, if you build it, you review
it against the security properties, not the happy path.

## Mental Model

Authentication is two phases — proving identity once, then carrying it on every
subsequent request:

```
   PHASE 1 — LOGIN (prove identity, once)
   client ──credentials──► server
                            verify password against a SLOW SALTED HASH (argon2/bcrypt)
                            issue a credential:
                              · server-side session  → opaque id in a cookie, state in a store
                              · stateless token (JWT) → signed token the client holds
                            ◄──credential──

   PHASE 2 — EVERY SUBSEQUENT REQUEST (carry identity)
   client ──credential (cookie / Authorization: Bearer)──► server
                            validate it → load the principal (the current user/account)
                            ──► hand the principal to the rest of the app

   ACCESS + REFRESH (for tokens)
   short-lived access token (minutes) ── expires ──► use the refresh token (days,
     revocable, rotated on use) to get a new access token ──► re-auth only when
     the refresh token expires or is revoked
```

Four principles keep it sound:

**Hash passwords with a slow, salted, purpose-built algorithm.** argon2id (preferred)
or bcrypt, with a work factor tuned so hashing takes ~100ms. The slowness is the
feature — it is what makes a leaked database expensive to crack. Fast hashes and
plaintext are not weaker versions of this; they are the absence of it.

**Sessions and tokens trade revocation for statelessness.** A server-side session is
trivially revocable (delete it from the store) and requires that store; a stateless
JWT scales without shared state and *cannot be revoked* before it expires without
reintroducing state (a denylist or a refresh-token store). This trade — not
familiarity or fashion — should drive the choice.

**A JWT is signed, not encrypted.** Its payload is base64, readable by anyone
holding the token. It proves *integrity* (the server signed it), not *confidentiality*.
Never put anything sensitive in it, and never treat it as a secret store. Put a user
ID and coarse, non-sensitive claims; look up everything else server-side.

**Tokens must expire and be revocable, and live out of reach of XSS.** Short access
tokens plus a longer, rotating, revocable refresh token bound the damage of theft.
On the web, the credential belongs in an `HttpOnly`, `Secure`, `SameSite` cookie so
page JavaScript cannot read it — `localStorage` is readable by any XSS and is the
wrong place for a token.

A working definition:

> **Authentication proves who is calling and carries that identity across requests.
> Build it — if you don't buy it — on slow salted password hashing, a deliberate
> choice between revocable sessions and stateless tokens, tokens that expire and
> carry no secrets, and credentials stored out of reach of hostile scripts. The
> attacks against it are Stage 9.**

## Production Example

**Invoicely** needs authentication: register an account, log in, stay logged in
across requests, refresh without re-entering a password, log out, and reset a
forgotten password. We will build it token-based (access + rotating refresh),
because Invoicely has a web app and a planned mobile app and wants a stateless API —
while noting exactly where a server-side session would be the better call, and where
buying auth outright (the Chapter 06 recommendation) would be better still.

The concrete deliverables are the pieces every Stage 2 chapter assumed: the password
hashing, the token issue/verify logic, the auth service, and — finally built — the
`CurrentAccountDep` dependency that every protected endpoint has been using. Along the
way, each of the three AI-classic failures (weak hashing, non-expiring tokens,
readable/exposed tokens) is closed deliberately, because the functional version would
contain all three.

## Folder Structure

```
modules/auth/
├── router.py             # /register /login /refresh /logout /password-reset
├── schemas.py            # request/response models (never echo the password back)
├── _service.py           # AuthService: register, authenticate, refresh, reset
├── _password.py          # hashing/verification (argon2id) — one place, vetted lib
├── _tokens.py            # JWT create/verify (access) + refresh-token issuing
├── _models.py            # User, RefreshToken (for rotation + revocation)
core/
├── auth.py               # get_current_account dependency (the boundary principal)
└── config.py             # JWT secret/keys, token TTLs — from the environment
```

Why this shape:

- **`_password.py`** isolates hashing behind one module using a vetted library, so
  the algorithm and work factor are set once and never hand-rolled per call.
- **`_tokens.py`** isolates token creation/verification, so expiry, signing, and
  claims are consistent and correct in one place.
- **`_models.py`** includes a `RefreshToken` table — the state that makes stateless
  access tokens practically revocable (revoke the refresh token, and access ends at
  the next short expiry).
- **`core/auth.py`** holds the `get_current_account` dependency: the single boundary
  that turns a credential into a validated principal for the rest of the app (the
  `CurrentAccountDep` used since Stage 2).

## Implementation

**Password hashing (`_password.py`).** One module, a vetted library, a slow algorithm.
Never hand-rolled, never a fast hash.

```python
from pwdlib import PasswordHash

# argon2id with sensible defaults; the hash is slow and self-describing (salt + params embedded)
_hasher = PasswordHash.recommended()


def hash_password(plaintext: str) -> str:
    return _hasher.hash(plaintext)


def verify_password(plaintext: str, stored_hash: str) -> bool:
    return _hasher.verify(plaintext, stored_hash)
```

**Token creation and verification (`_tokens.py`).** Access tokens are short-lived and
signed; the secret comes from the environment. Claims are minimal and non-sensitive.

```python
from datetime import datetime, timedelta, UTC
import jwt
from app.core.config import settings


def create_access_token(account_id: int) -> str:
    now = datetime.now(UTC)
    payload = {
        "sub": str(account_id),               # non-sensitive identifier only
        "iat": now,
        "exp": now + timedelta(minutes=15),   # SHORT-lived: theft window is bounded
        "type": "access",
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm="HS256")


def decode_access_token(token: str) -> int:
    try:
        payload = jwt.decode(token, settings.JWT_SECRET, algorithms=["HS256"])
    except jwt.ExpiredSignatureError:
        raise TokenExpired()
    except jwt.InvalidTokenError:
        raise TokenInvalid()
    if payload.get("type") != "access":
        raise TokenInvalid()
    return int(payload["sub"])
```

**Refresh tokens with rotation and revocation (`_models.py` + service).** The refresh
token is opaque, stored hashed, single-use (rotated on each refresh), and revocable —
this is the state that makes the stateless access token safe.

```python
# _models.py
class RefreshToken(Base):
    __tablename__ = "refresh_tokens"
    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int] = mapped_column(index=True)
    token_hash: Mapped[str] = mapped_column(unique=True)   # store the HASH, not the token
    expires_at: Mapped[datetime]
    revoked_at: Mapped[datetime | None] = mapped_column(default=None)
```

```python
# _service.py — authenticate and issue; refresh with rotation
class AuthService:
    def __init__(self, users: UserRepository, tokens: RefreshTokenRepository) -> None:
        self._users = users
        self._tokens = tokens

    async def authenticate(self, email: str, password: str) -> TokenPair:
        user = await self._users.get_by_email(email)
        # Verify even when the user is missing, to avoid leaking which emails exist
        # via timing (a real concern — hardening details are Stage 9).
        if user is None or not verify_password(password, user.password_hash):
            raise InvalidCredentials()
        return await self._issue_pair(user.account_id)

    async def refresh(self, presented_refresh: str) -> TokenPair:
        record = await self._tokens.get_active_by_hash(hash_token(presented_refresh))
        if record is None:
            raise InvalidCredentials()
        await self._tokens.revoke(record.id)          # ROTATE: old refresh is now dead
        return await self._issue_pair(record.account_id)
```

**The current-account dependency (`core/auth.py`).** The single boundary that turns a
bearer token into a validated principal. Every protected endpoint depends on this;
this is the `CurrentAccountDep` used since Stage 2.

```python
from typing import Annotated
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from app.modules.auth._tokens import decode_access_token, TokenExpired, TokenInvalid

_bearer = HTTPBearer()


async def get_current_account(
    creds: Annotated[HTTPAuthorizationCredentials, Depends(_bearer)],
    accounts: AccountRepositoryDep,
) -> Account:
    try:
        account_id = decode_access_token(creds.credentials)
    except (TokenExpired, TokenInvalid):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or expired token")
    account = await accounts.get(account_id)
    if account is None or not account.is_active:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Account not found or inactive")
    return account


CurrentAccountDep = Annotated[Account, Depends(get_current_account)]
```

**The login endpoint and web cookie handling (`router.py`).** For a browser client,
the refresh token goes in an `HttpOnly`, `Secure`, `SameSite` cookie — out of reach of
XSS — not into a response body the frontend stashes in `localStorage`.

```python
@router.post("/login", response_model=AccessTokenOut)
async def login(payload: LoginIn, service: AuthServiceDep, response: Response) -> AccessTokenOut:
    try:
        pair = await service.authenticate(payload.email, payload.password)
    except InvalidCredentials:
        # One generic message: don't reveal whether the email or the password was wrong.
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid email or password")
    response.set_cookie(
        "refresh_token", pair.refresh_token,
        httponly=True, secure=True, samesite="strict",   # unreadable by page JS
        max_age=60 * 60 * 24 * 14, path="/auth/refresh",
    )
    return AccessTokenOut(access_token=pair.access_token)  # short-lived; held in memory
```

The through-line: the password is verified against a deliberately slow hash; the
access token is short-lived and carries only an account ID; the refresh token is
opaque, stored hashed, rotated on use, and revocable; and on the web it lives in a
cookie no script can read. Strip any one of those and the login still "works" in the
demo — which is exactly why authentication is reviewed against its security
properties, and why, for a real product, handing all of this to a managed provider
(Chapter 06) is frequently the better engineering decision.

## Engineering Decisions

Five decisions define an authentication implementation — starting with whether to
write one at all.

### Build authentication, or buy it?

**Options:** (1) build it in-house; (2) use a managed provider (Clerk, Auth0,
Supabase Auth, Better Auth, and the like).

**Trade-offs:** building gives full control and no per-user vendor cost, at the price
of owning a large, high-consequence security surface *forever* — password reset, MFA,
social login, session management, breach response, and the constant arrival of new
attack classes (Stage 1, Chapter 06's ownership cost, at its most acute). Buying
offloads that surface and its liability to specialists, at the cost of a dependency,
a per-user fee, and some lock-in.

**Recommendation:** for most production products, **buy it** — authentication is
commodity, undifferentiated, security-critical infrastructure, and a managed provider
owns the ninety percent an in-house build omits. Build it in-house only when a hard
constraint forces it (data residency, an offline environment, a genuinely unusual
model) or the product's economics justify owning it. This chapter teaches the
mechanics because you must understand and integrate auth regardless of who provides
it — and because "understand it" is a prerequisite to buying it wisely.

### Server-side sessions or stateless tokens?

**Options:** (1) server-side sessions (opaque cookie + session store); (2) stateless
JWTs.

**Trade-offs:** sessions are trivially revocable (delete from the store), keep no
secrets on the client, and are simple to reason about — but require a shared session
store and are less natural for non-browser clients. JWTs scale without shared state
and suit mobile and service-to-service, but cannot be revoked before expiry without
reintroducing state, and tempt developers to over-stuff and mis-store them.

**Recommendation:** server-side sessions are underrated and the better default for a
**browser-only** app — simpler, safely revocable, fewer footguns. Reach for JWTs when
you have non-browser clients (mobile, third-party API consumers) or genuine stateless
cross-service needs — and then pair them with a refresh-token store so they are
revocable in practice. Choose on revocation and client mix, not on which feels
modern.

### How are access and refresh tokens designed?

**Options:** (1) one long-lived token; (2) short access token + long refresh token
with rotation.

**Trade-offs:** a single long-lived token is simple and means a stolen token is valid
for a long time with no way to cut it off. Short-access-plus-refresh bounds the theft
window (the access token expires in minutes) and makes revocation practical (revoke
the refresh token), at the cost of the refresh machinery and a token store.

**Recommendation:** short-lived access tokens (minutes) plus a longer, single-use,
**rotating**, revocable refresh token stored server-side (hashed). Rotation means each
refresh invalidates the previous refresh token, so a stolen refresh token is detectable
(it will have already been used) and the blast radius of any theft is bounded.

### Which password-hashing algorithm and work factor?

**Options:** (1) a fast hash (MD5/SHA-256); (2) bcrypt; (3) argon2id.

**Trade-offs:** fast hashes are cryptographically wrong for passwords — a leaked
database is cracked at billions of guesses per second. bcrypt is battle-tested and
fine. argon2id is the current recommendation, memory-hard and resistant to
GPU/ASIC attacks, tunable across time and memory cost.

**Recommendation:** argon2id (or bcrypt if argon2 is unavailable), via a vetted
library, with the work factor tuned so a single hash takes on the order of 100ms on
your hardware. Never a fast hash, never unsalted (the library salts for you), never
hand-rolled. Re-tune the work factor as hardware improves.

### Where does the client store the token?

**Options:** (1) `localStorage`/`sessionStorage`; (2) an `HttpOnly` `Secure`
`SameSite` cookie; (3) in-memory (access token) + `HttpOnly` cookie (refresh).

**Trade-offs:** `localStorage` is trivial to use and readable by any injected script,
so a single XSS steals every token — the wrong place for a credential. An `HttpOnly`
cookie is unreadable by page JavaScript (defeating XSS token theft) but must be
paired with CSRF defenses (Stage 9). In-memory access tokens vanish on reload but
can't be stolen from storage.

**Recommendation:** on the web, keep the refresh token in an `HttpOnly`, `Secure`,
`SameSite` cookie and the short-lived access token in memory; never put a token in
`localStorage`. On mobile, use the platform secure storage (Keychain/Keystore). The
CSRF implications of cookies are Stage 9.

## Trade-offs

Authentication decisions trade security, complexity, and control, and the honest ones
are uncomfortable.

**Building trades a fee for a permanent liability.** Rolling your own avoids a
per-user cost and buys total control — and makes you the owner of a security surface
that grows forever and whose failures are breaches, not bugs. For most teams that
trade is bad, which is why "buy it" is the default recommendation; the cases where
building wins are real but narrower than engineers' instinct to build suggests.

**Stateless tokens trade revocability for scale.** JWTs remove the shared session
store and, in exchange, remove easy revocation — a fired employee's token, or a
stolen one, is valid until it expires. The refresh-token store you add to fix this is
*state*, which is the very thing statelessness promised to avoid; you have chosen
where to keep the state, not eliminated it. Sessions make the opposite trade, and for
a browser-only app that trade is usually better.

**Short token lifetimes trade user friction for a smaller theft window.** Very short
access tokens minimize the damage of theft but increase refresh frequency and the
consequences of a refresh outage; very long ones do the reverse. The refresh-token
pattern exists to get most of the security of short access tokens without making users
log in constantly — at the cost of the machinery to run it.

**Security and convenience are in genuine tension.** `HttpOnly` cookies defeat XSS
token theft but require CSRF defense; MFA hardens accounts but adds friction; strict
session expiry protects but annoys. These are real trade-offs to set deliberately for
the product's risk profile — a bank and a hobby tool land in different places — not
defaults to accept unthinkingly. The attack side that informs where to land is Stage
9.

## Common Mistakes

**Weak or reversible password storage.** Plaintext, "encryption" (reversible), or a
fast hash (MD5/SHA-256) — so a database leak exposes every password. Fix: argon2id or
bcrypt via a vetted library, tuned to ~100ms; never fast, never reversible.

**Non-expiring, non-revocable tokens.** A long-lived JWT with no refresh and no
revocation path, valid forever once issued or stolen. Fix: short access token + a
rotating, revocable refresh token stored server-side.

**Treating a JWT as secret.** Putting PII, roles that matter, or secrets in a JWT
payload as if it were hidden — it is base64, readable by anyone holding it. Fix: only
a non-sensitive identifier and coarse claims; look up sensitive data server-side.

**Storing tokens in `localStorage`.** Credentials readable by any injected script, so
one XSS steals them all. Fix: `HttpOnly`/`Secure`/`SameSite` cookie for the refresh
token (web), platform secure storage (mobile), access token in memory.

**Leaking which accounts exist.** Different responses/timings for "unknown email"
versus "wrong password," letting attackers enumerate users. Fix: one generic "invalid
email or password," and verify a hash even when the user is missing to equalize
timing (deeper defenses in Stage 9).

**Rolling your own crypto or auth primitives.** Hand-written hashing, token signing,
or "clever" schemes that are subtly broken. Fix: vetted libraries for hashing and
JWT; better yet, a managed provider (Chapter 06).

## AI Mistakes

Authentication is the archetypal domain where "it works" hides "it's a breach": the
login succeeds in every functional test while the security properties are absent. An
assistant, optimizing for the working happy path, produces exactly that — so review
generated auth against the security properties, never against whether login works.

### Claude Code: treating the JWT as a secret store

Asked to issue a token carrying user info, Claude Code routinely packs the email,
role, permissions, and sometimes more into the JWT payload — treating it as
confidential, when a JWT is *signed, not encrypted* and its payload is trivially
readable by anyone holding it. Sensitive data leaks to the client, and code starts
trusting client-readable claims as authoritative.

**Detect:** JWT payloads containing PII, roles/permissions relied on for
authorization, or anything sensitive; comments or code implying the token contents are
hidden.

**Fix:** state what a JWT is:

> A JWT is signed, not encrypted — its payload is readable by anyone with the token.
> Put only a non-sensitive identifier (the account ID) and coarse claims in it. Never
> put PII or secrets in the token, and look up roles/permissions and sensitive data
> server-side rather than trusting token claims.

### GPT: tokens that never expire and cannot be revoked

GPT-family models frequently issue a single JWT with no expiry (or a very long one)
and no refresh or revocation mechanism, because it is simpler and logs the user in
successfully. A stolen or stale token is then valid indefinitely, with no way to cut
it off.

**Detect:** tokens created without an `exp` claim or with a multi-day/multi-month
expiry; no refresh-token flow; no server-side record enabling revocation.

**Fix:** require expiry and revocability:

> Access tokens must be short-lived (minutes) with an `exp` claim, paired with a
> longer, single-use, rotating refresh token stored server-side (hashed) so tokens
> are revocable in practice. A stolen token must stop working quickly, and we must be
> able to revoke a session.

### Cursor: insecure token storage and missing cookie flags

Wiring up the client or the login response inline, Cursor tends to store the token in
`localStorage` (readable by any XSS) or set an auth cookie without `HttpOnly`,
`Secure`, and `SameSite`, because those are the shortest working versions and the
security flags aren't visible from the edit site.

**Detect:** `localStorage.setItem('token', ...)`; `set_cookie` without `httponly`/
`secure`/`samesite`; a token returned in a response body that the frontend persists
to storage.

**Fix:** require secure storage and cookie flags:

> Do not store tokens in `localStorage` — it is readable by any injected script. On
> the web, put the refresh token in an `HttpOnly`, `Secure`, `SameSite` cookie and
> keep the short-lived access token in memory; on mobile use platform secure storage.
> Every auth cookie sets all three flags.

## Best Practices

**Prefer buying authentication; if you build it, review it against security
properties.** For most products a managed provider (Chapter 06) is the right call.
When you build, judge the implementation by its security properties — hashing,
expiry, claims, storage — not by whether login works.

**Hash passwords slowly and with a vetted library.** argon2id (or bcrypt), tuned to
~100ms, via a maintained library — never plaintext, never reversible, never a fast
hash, never hand-rolled.

**Choose sessions vs tokens on revocation and clients, and design tokens to expire.**
Server-side sessions for browser-only apps (simple, revocable); stateless tokens for
mobile/API/cross-service, always short-access-plus-rotating-refresh with a
server-side store for revocation.

**Keep tokens minimal and out of reach.** A JWT carries only a non-sensitive
identifier (it is readable); the credential lives in an `HttpOnly`/`Secure`/`SameSite`
cookie (web) or platform secure storage (mobile), never `localStorage`.

**Isolate auth, load config from the environment, and defer hardening to Stage 9.**
Keep hashing and token logic in dedicated modules; JWT secrets and TTLs come from the
environment, never code; document the auth model in `CLAUDE.md`. Attack-side hardening
(rate limiting, brute-force/credential-stuffing defense, CSRF, MFA) is Stage 9.

## Anti-Patterns

**Home-Grown Auth on a Real Product.** Building the full authentication surface
in-house when a managed provider would do — owning a growing, breach-prone liability
for no differentiating benefit (Stage 1, Chapter 06). The tell: a hand-built auth
system in a product whose value has nothing to do with identity.

**The Fast Hash.** Passwords stored with MD5/SHA-256 (or plaintext, or reversible
encryption). The tell: `hashlib.sha256(password)` anywhere near a password, or a
password column you could read.

**The Immortal Token.** A JWT with no or very long expiry and no revocation path,
valid forever once issued. The tell: token creation with no `exp`, and no
refresh/revocation mechanism.

**The Secret-Stuffed Token.** A JWT payload packed with PII, roles, or secrets, treated
as confidential though it is readable. The tell: sensitive claims in the token, and
authorization decisions trusting them without server-side checks.

**The localStorage Vault.** Tokens kept in `localStorage`/`sessionStorage`, one XSS
away from total theft. The tell: `localStorage` holding a token, or auth cookies
missing `HttpOnly`/`Secure`/`SameSite`.

## Decision Tree

"I need authentication — how do I do it right?"

```
Should you BUILD auth at all?
│
├─ Is there a hard constraint (data residency, offline, truly unusual model) OR
│  economics that justify owning it?
│  ├─ NO  ──► BUY IT (Clerk / Auth0 / Supabase / Better Auth). Default for most products.
│  └─ YES ──► Build it, and review against security properties (below).
│
BUILDING — choose the credential
├─ Browser-only app? ──► server-side SESSION (revocable, simple). Reasonable default.
└─ Mobile / API / cross-service? ──► stateless TOKEN, and then:
     ├─ short-lived access token (minutes, has exp)
     └─ + rotating, revocable refresh token stored HASHED server-side

PASSWORDS
└─ argon2id (or bcrypt), vetted library, ~100ms work factor. Never fast/plaintext/reversible.

TOKEN CONTENTS & STORAGE
├─ Contents ─► only a non-sensitive id + coarse claims (JWT is readable). No PII/secrets.
└─ Storage ──► web: HttpOnly+Secure+SameSite cookie (refresh) + access in memory.
              mobile: platform secure storage. NEVER localStorage.

HARDENING (rate limits, brute force, CSRF, MFA) ──► Stage 9.
```

## Checklist

### Implementation Checklist

- [ ] Passwords hashed with argon2id/bcrypt via a vetted library, tuned to ~100ms; never fast/plaintext/reversible.
- [ ] Access tokens are short-lived with an `exp` claim; refresh tokens are rotating, revocable, and stored hashed.
- [ ] JWT payloads carry only a non-sensitive identifier and coarse claims — no PII, no secrets.
- [ ] Web credentials are in `HttpOnly`/`Secure`/`SameSite` cookies (refresh) with access in memory; nothing in `localStorage`.
- [ ] Login returns one generic error and does not reveal whether the email exists.
- [ ] JWT secret/keys and token TTLs come from the environment, not code.

### Architecture Checklist

- [ ] The build-vs-buy decision was made deliberately and recorded (ADR); buying was seriously considered (Chapter 06).
- [ ] Session-vs-token choice is justified by revocation needs and client mix, not fashion.
- [ ] Hashing and token logic are isolated in dedicated modules behind vetted libraries.
- [ ] The current-user dependency is the single boundary that turns a credential into a principal.
- [ ] Auth model and conventions are documented in `CLAUDE.md`; hardening is tracked for Stage 9.

### Code Review Checklist

- [ ] No fast hash, plaintext, or reversible password storage (watch AI diffs).
- [ ] No non-expiring token and no missing revocation path.
- [ ] No sensitive data in a JWT payload, and no authorization trusting token claims without a server-side check.
- [ ] No token in `localStorage`; all auth cookies set `HttpOnly`/`Secure`/`SameSite`.
- [ ] No hand-rolled crypto; vetted libraries only.

### Deployment Checklist

- [ ] JWT secret/signing keys are managed as secrets, rotatable without a code change (see [`checklists/production-readiness.md`](../../checklists/production-readiness.md)).
- [ ] Password-hash work factor is tuned for production hardware and revisited over time.
- [ ] Auth cookies are `Secure` and served only over HTTPS in production.
- [ ] A key/secret rotation procedure exists and has been tested.

## Exercises

**1. Make the build-vs-buy call.** For Invoicely, write the two-paragraph decision:
build authentication in-house or use a managed provider, with the specific factors
(security surface, cost, control, constraints) and a recommendation. Then do the same
for a hypothetical air-gapped on-premise product. The artifact is the two decisions —
the point is that the honest answer differs by context (Stage 1, Chapter 06).

**2. Close the three holes.** Take a functional login system that hashes with SHA-256,
issues a non-expiring JWT containing the user's email and role, and returns it for the
frontend to store in `localStorage` (write it, or have an assistant generate "add
login to my FastAPI app"). Fix all three: slow salted hashing, short access + rotating
refresh, and secure cookie storage carrying only an ID. The artifact is the diff and a
line on the breach each hole enabled.

**3. Design revocation.** Design how Invoicely revokes a session immediately (a user
clicks "log out everywhere," or an account is compromised) given short access tokens
and rotating refresh tokens. The artifact is the mechanism — what is stored, what is
checked, and the worst-case delay before access actually ends — and a note on why pure
stateless JWTs make this hard.

## Further Reading

- **OWASP Authentication Cheat Sheet** and **Password Storage Cheat Sheet**
  (cheatsheetseries.owasp.org) — the authoritative, current guidance on hashing
  algorithms, work factors, session management, and account-enumeration defenses. The
  reference to check any implementation against. (The broader OWASP threat catalog is
  Stage 9.)
- **NIST SP 800-63B, Digital Identity Guidelines** (pages.nist.gov/800-63-3) — the
  modern, evidence-based standard for password and authenticator requirements (and a
  useful corrective to outdated "rotate every 90 days / force symbols" folklore).
- **Managed auth provider documentation** (Clerk, Auth0, Supabase Auth, Better Auth) —
  read at least one provider's model end to end; understanding what they handle (MFA,
  social login, session management, breach response) is the clearest argument for the
  buy option in Chapter 06.
- **The Copenhagen Book** (thecopenhagenbook.com) — a free, practical, framework-neutral
  guide to implementing sessions, tokens, password reset, and related flows correctly;
  an excellent build-it-right companion when buying is not an option.

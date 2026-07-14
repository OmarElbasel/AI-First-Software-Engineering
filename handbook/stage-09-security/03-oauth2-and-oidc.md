# OAuth 2.0 & OpenID Connect

## Introduction

"Sign in with Google" looks like a feature you add in an afternoon: register an app, drop in a
client ID, redirect, get a token back, log the user in. The library does most of it. And that
afternoon version is where a specific, well-documented family of vulnerabilities lives — because
OAuth is not a login protocol, it is an *authorization delegation* protocol that has been widely
repurposed for login, and the gap between what it actually proves and what people assume it proves
is exactly where the attacks are.

This chapter is about integrating third-party identity — OAuth 2.0 for delegated authorization and
OpenID Connect (OIDC) for authentication — *securely*. It covers the flows and why one of them is
the only safe default (Authorization Code with PKCE), the parameters that are load-bearing security
controls rather than boilerplate (`state`, `redirect_uri`, `nonce`, PKCE), the critical distinction
OAuth makes so easy to get wrong (an access token proves you may *call an API*, not who you *are* —
that's the ID token's job), and the classic attacks: CSRF on the callback, redirect manipulation,
token substitution, and provider mix-up.

Two boundaries frame it. First, this is the *integration and attack* chapter: building your own
first-party authentication — password hashing, your own token issuance — was Stage 3, Chapter 03,
and hardening those tokens was Chapter 02 here; this chapter is about delegating identity to an
external provider and doing it without inheriting OAuth's footguns. Second, OIDC ID tokens *are*
JWTs, so everything Chapter 02 said about verifying a JWT (pin the algorithm, validate the claims,
fetch keys from JWKS) applies directly to validating an ID token — this chapter builds on that
rather than repeating it. The reason to understand OAuth deeply even though a library implements it:
the library gives you the mechanics, but *which flow, which parameters, and which token proves
what* are decisions the library leaves to you, and getting them wrong ships a login that works and
can be hijacked.

## Why It Matters

OAuth integrations fail in ways that are invisible in the demo and catastrophic in production,
because the protocol's flexibility is precisely its danger — most of the ways to use it are
insecure, and only a narrow path is safe.

- **The access token is not proof of identity — assuming it is, is a real vulnerability.** An
  access token means "the bearer may call these APIs on this user's behalf." It does not
  authenticate *who is presenting it*. A token minted for a malicious app, or stolen, can be
  replayed to a backend that treats "has a valid Google access token" as "is this Google user" —
  the confused-deputy / token-substitution attack. Authentication is the ID token's job (OIDC), and
  conflating the two is the single most common OAuth-for-login mistake.
- **The `state` parameter is a required CSRF defense, not optional plumbing.** Without it, an
  attacker can initiate an OAuth flow with *their own* account and trick a victim's browser into
  completing it, silently logging the victim into the attacker's account (login CSRF) — or the
  reverse, linking the attacker's identity to the victim's session. `state` binds the callback to
  the request that started it; omitting it opens the callback to forgery.
- **`redirect_uri` is where tokens get delivered — loose matching hands them to attackers.** If the
  provider or your app accepts redirect URIs by prefix, or allows open redirects on your domain, an
  attacker registers or crafts a redirect that sends the authorization code or token to a host they
  control. Exact-match registration of redirect URIs is what keeps the credential from being
  delivered to the wrong door.
- **The ID token must be verified like any JWT — a fetched profile is not verification.** Calling
  the provider's userinfo endpoint or decoding the ID token to read an email is not authentication
  unless the ID token's signature, issuer, audience, and nonce are validated (Chapter 02). An
  unverified ID token is attacker-editable data.
- **PKCE closes the code-interception hole, and is now the baseline for everyone.** Originally for
  mobile apps that can't hold a secret, Proof Key for Code Exchange is now recommended for *all*
  clients, including web: it binds the authorization code to the client that requested it, so an
  intercepted code is useless to anyone else. Skipping it leaves the code-interception attack open.
- **The AI dimension is sharp.** Assistants generate OAuth flows that complete the round-trip and
  log a user in while omitting `state`, matching `redirect_uri` loosely, treating the access token
  as identity, or skipping ID-token validation — every one of which authenticates the happy-path
  user and hands an attacker a hijack. The flow "working" says nothing about whether it's safe.

## Mental Model

OAuth is a delegation dance between four parties, and security lives in the parameters that bind
the steps together so an attacker can't splice their own step into your flow.

```
   THE FOUR PARTIES
     Resource Owner  = the user            Client       = your app (Invoicely)
     Authorization Server = the provider (Google)    Resource Server = the provider's API

   AUTHORIZATION CODE FLOW + PKCE (the ONE safe default for web, mobile, SPA)
     1. Client → browser → Auth Server:  /authorize?client_id&redirect_uri&scope
                                          &state=RANDOM&nonce=RANDOM&code_challenge=HASH(verifier)
     2. user authenticates & consents at the Auth Server (your app never sees their password)
     3. Auth Server → browser → redirect_uri?code=AUTHZ_CODE&state=RANDOM
                                          │
                                          ▼  CHECK state == what you sent  (CSRF defense)
     4. Client → Auth Server (back channel): exchange code + code_VERIFIER (+client secret)
                                          │
                                          ▼  PKCE: verifier must hash to the challenge from step 1
     5. Auth Server → Client:  access_token (call APIs)  +  id_token (WHO the user is, OIDC)
                                          │
                                          ▼  VERIFY id_token as a JWT (Ch 02): sig, iss, aud, exp,
                                             and nonce == what you sent
     6. Client establishes ITS OWN session for the user (your session, not the provider's token)

   WHAT EACH TOKEN PROVES  (getting this wrong is the headline bug)
     access_token → "bearer may call these APIs for this user"   NOT identity
     id_token     → "this user authenticated at this provider"   ← authentication (OIDC only)

   THE LOAD-BEARING PARAMETERS (each defends a specific attack)
     state          → CSRF on the callback (bind callback to your request)
     redirect_uri   → token delivery address; EXACT match, pre-registered (no prefix/open redirect)
     PKCE           → binds code to this client (defeats code interception) — use everywhere
     nonce          → binds id_token to this request (defeats id_token replay)
```

Three principles carry the chapter:

**Authentication is the ID token's job; the access token is for calling APIs.** If you are logging
a user in, you need OIDC and a *verified ID token*. Never derive identity from an access token, and
never trust a userinfo response you got by presenting a token you didn't verify the origin of.

**Every binding parameter is a security control — treat missing ones as vulnerabilities.** `state`,
exact `redirect_uri`, PKCE, and `nonce` each defend a named attack. They are not optional
configuration; a flow missing any of them is a flow missing a defense, even though it still logs
people in.

**Use the Authorization Code flow with PKCE, and no other.** The implicit flow (tokens in the URL
fragment) and the resource-owner-password flow are deprecated for good reasons — they leak tokens
and hand your app the user's provider password. There is one safe default; use it for web, SPA, and
mobile alike.

A working definition:

> **OAuth 2.0 delegates authorization; OpenID Connect adds authentication on top via a verifiable
> ID token. Integrating them securely means using the Authorization Code flow with PKCE, treating
> `state`, exact `redirect_uri` matching, PKCE, and `nonce` as mandatory attack-specific defenses,
> deriving identity only from a fully verified ID token (never from an access token), and ending
> the flow by establishing your own session rather than passing the provider's token around.**

## Production Example

**Invoicely** adds "Sign in with Google" so users can onboard without creating another password,
and prepares to let them connect **Stripe** so Invoicely can create charges on their behalf. These
are the two faces of the protocol: Google sign-in is *authentication* (OIDC — who is this user),
Stripe Connect is *authorization* (OAuth — may Invoicely act on this account). Building both in one
chapter makes the distinction concrete, because the security requirements diverge exactly where the
tokens' meanings diverge.

For Google sign-in, Invoicely uses the Authorization Code flow with PKCE. It generates a random
`state` and `nonce` per attempt, stores them bound to the browser session, and pre-registers the
exact `redirect_uri` in the Google console — no wildcards, no prefix matching. On the callback it
checks `state` before doing anything else (CSRF), exchanges the code with the PKCE verifier over the
back channel, then validates the returned **ID token** as a JWT using Chapter 02's rules: signature
against Google's JWKS, `iss` is Google's issuer, `aud` is Invoicely's client ID, `exp` is future,
and `nonce` matches what it sent. Only after all of that does Invoicely map the verified `sub` to a
local account and establish *its own* session — it never treats Google's access token as identity,
and it never stores it as the user's session.

For Stripe Connect, Invoicely uses OAuth for authorization: it receives an access token scoped to
create charges on the connected account, and stores that token (encrypted, Chapter 04) as a
*capability* — proof it may call Stripe for that account — not as proof of who anyone is. The
account linking is bound to the already-authenticated Invoicely user's session so an attacker can't
graft their Stripe account onto a victim's login.

In this chapter we build the Google OIDC flow with every binding parameter in place, contrast it
with the assistant-default version (no `state`, access token treated as identity, ID token
decoded-not-verified), and show each omission as the specific hijack it enables.

## Folder Structure

```
modules/auth/oauth/
├── router.py             # /auth/google/start (build authorize URL) and /auth/google/callback
├── _flow.py              # state+nonce+PKCE generation and one-time storage; the callback checks
├── _providers.py        # provider config: issuer, JWKS URL, client id, EXACT redirect_uri, scopes
├── _idtoken.py           # ID-token verification — reuses Ch 02's JWT verifier against provider JWKS
├── _link.py              # map verified sub -> local account; connect-account bound to session
core/
├── auth.py               # establishes Invoicely's OWN session after verification (not the provider token)
tests/
└── security/
    └── test_oauth_flow.py   # missing/forged state, tampered id_token, wrong aud, code without PKCE
```

Why this shape:

- **`_flow.py`** owns the ephemeral security state (`state`, `nonce`, PKCE verifier): generated per
  attempt, stored server-side bound to the session, single-use, and checked on callback. Centralizing
  it means the CSRF and replay defenses can't be half-implemented per route.
- **`_providers.py`** pins each provider's issuer, JWKS URL, client ID, exact redirect URI, and
  scopes in one config, so validation always checks against the right issuer/audience and the
  redirect URI is never loose or derived from the request.
- **`_idtoken.py`** deliberately reuses Chapter 02's JWT verifier rather than introducing a second,
  weaker token check — the ID token is a JWT and gets the same strict treatment, plus `nonce`.
- **`core/auth.py`** ends every flow by minting Invoicely's own session, drawing the line: the
  provider authenticated the user *to us once*; from there our session carries identity, and the
  provider's tokens are never the app's session credential.

## Implementation

**Starting the flow (`_flow.py` + `router.py`): generate and bind the security parameters.** The
random values are the whole defense; they must be per-attempt, stored server-side, and single-use.

```python
def build_authorize_url(session) -> str:
    verifier = secrets.token_urlsafe(64)                 # PKCE: kept server-side
    state    = secrets.token_urlsafe(32)                 # CSRF: bind callback to this request
    nonce    = secrets.token_urlsafe(32)                 # replay: bind id_token to this request
    session.store_oauth_attempt(state=state, nonce=nonce, verifier=verifier)  # single-use, TTL'd
    return google.authorize_url(
        client_id=CFG.client_id,
        redirect_uri=CFG.redirect_uri,                   # EXACT, pre-registered — never from the request
        scope="openid email profile",
        state=state,
        nonce=nonce,
        code_challenge=pkce_challenge(verifier),         # S256(verifier)
        code_challenge_method="S256",
    )
```

**The callback (`router.py`): check `state` first, exchange with PKCE, verify the ID token.** Order
matters — reject forged callbacks before spending an exchange on them.

```python
@router.get("/auth/google/callback")
def google_callback(code: str, state: str, session):
    attempt = session.pop_oauth_attempt()                # single-use: remove as you read it
    if attempt is None or not secrets.compare_digest(state, attempt.state):
        raise AuthError("invalid state")                 # CSRF defense — fail closed, first thing

    tokens = google.exchange_code(
        code=code, redirect_uri=CFG.redirect_uri,
        code_verifier=attempt.verifier,                  # PKCE: proves this is the client that started
    )
    claims = verify_id_token(tokens.id_token, expected_nonce=attempt.nonce)  # Ch 02 verifier + nonce
    account = link_or_create_account(sub=claims["sub"], email=claims["email"])
    return establish_invoicely_session(account)          # OUR session — not google's tokens
```

**ID-token verification (`_idtoken.py`): a JWT check, plus `nonce`.** This is Chapter 02 applied to
a token minted by someone else — so the key comes from *their* JWKS and the audience is *your*
client ID.

```python
def verify_id_token(id_token: str, expected_nonce: str) -> dict:
    claims = jwt.decode(
        id_token,
        key=PROVIDER_JWKS.public_key_for(id_token),      # provider's keys, by kid, over TLS, cached
        algorithms=["RS256"],                            # PINNED (Ch 02)
        audience=CFG.client_id,                          # aud == US: this token was minted for Invoicely
        issuer=CFG.issuer,                               # iss == the provider we trust
        options={"require": ["exp", "iat", "aud", "iss", "sub", "nonce"]},
    )
    if not secrets.compare_digest(claims["nonce"], expected_nonce):
        raise AuthError("invalid nonce")                 # replay defense: this id_token is for THIS attempt
    return claims
```

**Why the access token never appears here:** identity comes entirely from the verified ID token's
`sub`. Invoicely's access to Google APIs (if any) uses the access token as a *capability*, stored
separately; it is never consulted to answer "who is this user?" That separation is the fix for the
token-substitution attack — a token minted for a different app can't be swapped in, because identity
rides on an ID token whose `aud` must equal Invoicely's client ID.

**The attack tests (`tests/security/test_oauth_flow.py`): prove the bindings hold.**

```python
def test_callback_with_mismatched_state_is_rejected(client):
    start_flow(client)                                   # stores a state
    assert client.get("/auth/google/callback?code=x&state=attacker").status_code == 401

def test_id_token_for_another_audience_is_rejected(client, id_token_aud="some-other-app"):
    assert complete_flow(client, id_token=forge(aud=id_token_aud)).status_code == 401

def test_access_token_cannot_be_used_as_identity(client, provider_access_token):
    # presenting a raw provider access token must NOT establish an Invoicely session
    assert client.post("/auth/session", token=provider_access_token).status_code == 401
```

The suite proves the three things the assistant-default flow gets wrong: `state` is enforced, the
ID token's audience is checked, and an access token can't masquerade as identity.

## Engineering Decisions

Five decisions define a secure OAuth/OIDC integration.

### Which flow?

**Options:** (1) Authorization Code with PKCE; (2) implicit flow (tokens in the URL fragment);
(3) resource-owner password credentials; (4) client credentials (no user).

**Trade-offs:** Authorization Code with PKCE exchanges a short-lived code over a back channel and
binds it to the client — the token never rides in a redirect URL, and an intercepted code is
useless. Implicit returns tokens directly in the fragment, exposing them to the browser history,
referrers, and scripts — deprecated. Resource-owner password hands your app the user's provider
password, defeating the entire point of delegation — never use it for third-party login. Client
credentials is for service-to-service with no user and doesn't apply to login.

**Recommendation:** Authorization Code with PKCE for every user-facing client — web, SPA, and mobile
alike. PKCE is no longer mobile-only; it's the baseline. Implicit and password flows should not
appear in new code; treat their presence as a finding.

### Authentication (OIDC) or authorization (OAuth) — which are you actually doing?

**Options:** (1) OIDC with a verified ID token for login; (2) OAuth access token for API access;
(3) treat the access token as login (the mistake).

**Trade-offs:** if the goal is "log this user in," you need OIDC and a verified ID token — the token
whose *purpose* is to assert authentication. If the goal is "call the provider's API for this user,"
you need an access token, used as a capability. Using the access token for login is the
token-substitution vulnerability; using an ID token to call APIs simply doesn't work.

**Recommendation:** name which you're doing per integration and use the matching token. Login →
verified ID token → your own session. API access → access token stored as an encrypted capability,
never consulted for identity. When you need both (login *and* API access), you get both tokens and
keep their jobs separate.

### How strictly is `redirect_uri` matched?

**Options:** (1) exact match against a pre-registered URI; (2) prefix/subdomain match; (3)
dynamically built from the request.

**Trade-offs:** exact match means the authorization code/token can only be delivered to a URI you
registered — the attacker can't redirect it elsewhere. Prefix or subdomain matching opens the door
to an attacker-controlled path or host that satisfies the loose rule. Building the redirect from the
request is the worst — an open redirect that hands the credential to any host.

**Recommendation:** exact-match, pre-registered redirect URIs, one per environment, never derived
from request input. Combined with no open redirects anywhere on your domain (an open redirect
elsewhere can be chained to steal the code). This is a configuration decision with total
consequences.

### Where do the security parameters live, and for how long?

**Options:** (1) server-side session, single-use, short TTL; (2) signed cookie; (3) not stored (the
vulnerability).

**Trade-offs:** `state`, `nonce`, and the PKCE verifier must be generated by your server, tied to
the specific browser that started the flow, used exactly once, and expired quickly. Server-side
storage is the clean model. A signed, `HttpOnly` cookie can work if it's per-attempt and validated.
Not storing them — or storing them globally rather than per-attempt — means the CSRF and replay
defenses don't actually bind anything.

**Recommendation:** generate per attempt, store server-side (or in a signed per-attempt cookie)
bound to the session, enforce single use by deleting on read, and give them a short TTL (minutes).
An OAuth flow that reuses or omits these values has decorative, not real, defenses.

### First-party auth, buy an auth provider, or federate directly?

**Options:** (1) build your own first-party auth (Stage 3); (2) integrate providers directly
yourself (this chapter); (3) use an auth broker (Auth0, Clerk, Supabase Auth, Better Auth) that
front-ends the providers.

**Trade-offs:** direct integration gives full control and no per-user cost, at the price of getting
every binding parameter right for every provider yourself. A broker implements the flows correctly
once, handles multi-provider and token lifecycle, and moves a class of risk off your plate — at a
cost and with lock-in. First-party-only means users manage another password.

**Recommendation:** for most teams, an auth broker is the sound engineering choice precisely because
this chapter's attacks are easy to get subtly wrong and a specialist gets them right — the same
"buy auth" logic from Stage 1, Chapter 06 and Stage 3, Chapter 03. Integrate directly when you have
a specific reason (cost at scale, control, no third party), and when you do, hold the line on every
decision above.

## Trade-offs

**Delegated identity trades a dependency for not holding passwords.** "Sign in with Google" means
you never store a password and inherit the provider's security and MFA — and means your login
depends on their availability and your users need an account there. For consumer products the trade
usually favors delegation; for some B2B contexts a first-party option must exist alongside it.

**PKCE and the binding parameters trade a little complexity for closing named attacks.** `state`,
`nonce`, PKCE, and exact redirect matching add code and per-attempt state. Each buys the closure of
a specific, exploited attack. This is not complexity for its own sake; it's the minimum that makes
the flow safe, and skipping any piece re-opens a known hole.

**Using a broker trades control and money for correctness.** An auth provider implements the flows
right and maintains them as specs evolve, at the cost of fees, lock-in, and a third party in your
login path. The alternative is owning a security-critical integration whose subtle failures are
breaches. Match the choice to your team's security depth and the stakes.

**Ending in your own session (vs passing provider tokens around) trades a step for control.** Minting
your own session after verification is one more piece to build, but it means provider-token lifetime,
revocation, and scope don't leak into your app's authorization model — your session is yours to
expire and revoke. Passing the provider's token around as the app credential couples you to its
semantics and expands the blast radius of its theft.

## Common Mistakes

**Treating the access token as identity.** Logging a user in because they presented a valid provider
access token, which proves API-access delegation, not who they are — the token-substitution
vulnerability. Fix: authenticate only from a verified ID token (OIDC); use access tokens as
capabilities.

**Omitting or not checking `state`.** No CSRF binding on the callback, so an attacker can complete a
flow in the victim's browser (login CSRF / account grafting). Fix: generate a per-attempt `state`,
store it server-side, and compare it first thing on callback.

**Loose `redirect_uri` matching.** Prefix, subdomain, or request-derived redirect URIs that let an
attacker receive the code/token. Fix: exact-match, pre-registered URIs; no open redirects anywhere
on the domain.

**Decoding the ID token instead of verifying it.** Reading `email`/`sub` from the ID token or
userinfo without checking signature, issuer, audience, and nonce. Fix: verify the ID token as a JWT
(Chapter 02) against the provider's JWKS with `aud` = your client ID.

**Skipping PKCE.** Relying on the client secret alone (or nothing, for public clients), leaving the
authorization code interceptable. Fix: PKCE on every flow, `S256` challenge method.

**Passing the provider's token around as the app session.** Using Google's access token as
Invoicely's session credential, coupling app auth to provider-token lifetime and scope. Fix: mint
your own session after verification; keep provider tokens as separate, encrypted capabilities.

## AI Mistakes

OAuth is a protocol where the happy path and the safe path are different paths, so assistant output
that logs a user in reliably ships the missing defenses. Review the flow for the binding parameters
and the token semantics, not for whether login succeeds.

### Claude Code: the flow with no `state` (an unprotected callback)

Asked to "add Google login," Claude Code often generates a clean Authorization Code flow that omits
`state` entirely — build the authorize URL, handle the callback, exchange the code, log in. It
works perfectly for a real user and leaves the callback open to CSRF: an attacker starts a flow with
their own account and lands the victim in it, or grafts their identity onto the victim's session.
Because the omission is a *missing* parameter, nothing errors and no test that only checks "login
works" catches it.

**Detect:** an authorize URL built without a `state` parameter; a callback handler that reads `code`
but never compares `state` to a stored value; no per-attempt server-side storage of `state`; the
callback succeeding when `state` is absent or arbitrary.

**Fix:** make `state` mandatory and checked first:

> The OAuth flow must generate a random `state` per attempt, store it server-side bound to the
> session, and reject the callback (401) before any code exchange if the returned `state` doesn't
> match. Add a test that a callback with a missing or wrong `state` is rejected.

### GPT: the access token used as proof of identity

GPT-family models frequently blur authentication and authorization: after the exchange, they read
the user's profile by presenting the *access* token (or decode it) and establish a session from
that — treating "holds a valid provider access token" as "is this provider user." This is the
token-substitution vulnerability: a token obtained by a malicious client, or for a different
application, can be replayed to log in as the victim, because identity was never bound to a token
minted *for your app*.

**Detect:** sessions established from an access token or a userinfo call rather than a verified ID
token; no ID token requested (`openid` scope missing) or requested but not verified; identity
(`sub`/`email`) taken from an access-token-authorized API call whose token audience is never checked.

**Fix:** authenticate from a verified ID token only:

> Authentication must use OIDC: request the `openid` scope, and derive identity only from the ID
> token after verifying its signature, `iss`, `aud` (must equal our client id), `exp`, and `nonce`.
> Never establish a session from an access token or an unverified userinfo response. Add a test that
> a raw provider access token cannot create a session.

### Cursor: the ID token decoded but not verified (and no `nonce`)

Completing a callback handler, Cursor often reads the ID token's claims with an unverified decode —
`jwt.decode(id_token, options={"verify_signature": False})` or a base64 split — to get the email,
because the immediate task was "get the user's info," and it skips fetching the provider's JWKS and
checking `aud`/`nonce`. The claims are attacker-editable, and without `nonce` the ID token is
replayable. Login works with a real token and accepts a forged one.

**Detect:** ID-token reads with `verify_signature: False` or manual base64 decoding; no call to the
provider's JWKS; `aud`/`iss` not asserted against your config; no `nonce` generated at start or
checked on return.

**Fix:** verify the ID token with the Chapter 02 verifier and bind the nonce:

> The ID token must be verified, not decoded: signature against the provider's JWKS (by `kid`),
> `algorithms` pinned, `iss` and `aud` (our client id) asserted, `exp` enforced, and `nonce` matched
> to the value generated at flow start. Add a test that a tampered ID token and a wrong-audience ID
> token are both rejected.

## Best Practices

**Use Authorization Code with PKCE, always.** One flow for web, SPA, and mobile; no implicit, no
resource-owner-password. PKCE with `S256` on every attempt.

**Name authentication vs authorization per integration.** Login derives identity from a verified ID
token and ends in your own session; API access uses an access token as an encrypted capability.
Never cross the wires.

**Treat `state`, exact `redirect_uri`, PKCE, and `nonce` as mandatory.** Each defends a named
attack (CSRF, token misdelivery, code interception, replay). Generate the random ones per attempt,
store server-side, single-use, short TTL; check `state` before anything else.

**Verify the ID token like any JWT.** Provider JWKS by `kid`, pinned algorithm, `iss`/`aud`/`exp`
asserted, `nonce` matched — Chapter 02's rules against a token someone else minted.

**End the flow with your own session.** Mint an Invoicely session after verification; keep provider
tokens separate and encrypted. Your session is what you control, expire, and revoke.

**Prefer a vetted auth broker unless you have a reason not to.** These attacks are easy to get
subtly wrong; a specialist implements the flows correctly and maintains them. Direct integration is
a deliberate choice with a security cost you accept knowingly.

**Test the attacks.** Missing/forged `state`, tampered and wrong-audience ID tokens, code exchange
without PKCE, access-token-as-identity — a security test per attack, green in CI.

## Anti-Patterns

**The Implicit Flow.** Tokens returned in the URL fragment, exposed to history, referrers, and
scripts. The tell: `response_type=token`; access tokens appearing in redirect URLs; no back-channel
code exchange.

**The Identity-From-Access-Token.** Logging users in from an access token or unverified userinfo.
The tell: sessions created without an ID token; `openid` scope missing; a raw provider token
accepted as a login credential.

**The Stateless Callback.** An OAuth callback with no `state` check. The tell: no per-attempt
`state` stored; the callback succeeds with an arbitrary or absent `state`.

**The Loose Redirect.** Prefix/subdomain/request-derived `redirect_uri`. The tell: wildcard or
prefix redirect registration; the redirect URI assembled from request input; open redirects
elsewhere on the domain.

**The Decoded ID Token.** ID-token claims read without verification. The tell: `verify_signature:
False` or base64 splitting to read claims; no provider JWKS fetch; `aud`/`nonce` never checked.

**The Provider Token As Session.** The provider's access token used as the app's session credential.
The tell: no first-party session minted; app authorization keyed off the provider token's lifetime
and scope.

## Decision Tree

"I'm integrating a third-party identity/authorization provider — how do I do it safely?"

```
What am I actually doing?
├── LOGGING A USER IN ──► OIDC.
│     ├── flow: Authorization Code + PKCE (never implicit/password)
│     ├── request `openid` scope; generate state + nonce + PKCE verifier per attempt (server-side)
│     ├── callback: check `state` FIRST → exchange code with PKCE verifier
│     ├── verify the ID TOKEN as a JWT (Ch 02): sig via provider JWKS, iss, aud==our client id,
│     │     exp, nonce==ours
│     └── establish YOUR OWN session from the verified `sub` — never the provider's token
│
├── CALLING A PROVIDER API FOR THE USER ──► OAuth authorization.
│     ├── flow: Authorization Code + PKCE; request the specific scopes only
│     ├── store the access token as an ENCRYPTED capability (Ch 04), bound to the app user
│     └── never consult it for identity; refresh/rotate per the provider's rules
│
└── UNSURE WHETHER TO BUILD IT AT ALL ──►
      strongly consider a vetted auth broker — these attacks are subtle and specialists get
      them right. integrate directly only for a concrete reason, holding every decision above.

Any flow: redirect_uri EXACT-match pre-registered · no open redirects on the domain ·
          state/nonce/verifier single-use + short TTL · fail closed on any mismatch.
```

## Checklist

### Implementation Checklist

- [ ] All user-facing flows use Authorization Code with PKCE (`S256`); no implicit or resource-owner-password flow exists.
- [ ] `state`, `nonce`, and the PKCE verifier are generated per attempt, stored server-side bound to the session, single-use, and short-TTL'd.
- [ ] The callback compares `state` before any code exchange and fails closed on mismatch.
- [ ] Identity is derived only from an ID token verified as a JWT (signature via provider JWKS, pinned algorithm, `iss`, `aud` = client id, `exp`, `nonce`).
- [ ] The flow ends by establishing a first-party session; provider access tokens are stored separately as encrypted capabilities, never as identity.
- [ ] `redirect_uri` is exact-match and pre-registered per environment; no open redirects exist on the domain.

### Architecture Checklist

- [ ] Each integration is explicitly classified as authentication (OIDC/ID token) or authorization (OAuth/access token), with the matching token used.
- [ ] Provider configuration (issuer, JWKS URL, client id, redirect URI, scopes) is centralized and not derived from request input.
- [ ] Account linking (connecting a provider to an existing user) is bound to the authenticated app session so identities can't be grafted.
- [ ] The build-vs-broker decision is made deliberately; if integrating directly, ownership of the binding-parameter correctness is assigned.
- [ ] ID-token verification reuses the hardened JWT verifier (Chapter 02), not a second, weaker check.

### Code Review Checklist

- [ ] No authorize URL is built without `state`, `nonce`, and a PKCE challenge.
- [ ] No session is established from an access token or an unverified userinfo/ID-token decode.
- [ ] No `redirect_uri` is prefix-matched, wildcarded, or built from the request.
- [ ] Security parameters are single-use (deleted on read) and never global or reused across attempts.
- [ ] Attack tests exist for missing/forged `state`, tampered and wrong-audience ID tokens, and access-token-as-identity.

### Deployment Checklist

- [ ] Client secrets and provider credentials come from the secret manager (Chapter 04), not code or config files.
- [ ] Exact redirect URIs are registered per environment (dev/staging/prod) with no shared wildcards.
- [ ] Provider JWKS is fetched over TLS and cached with a TTL that supports the provider's key rotation.
- [ ] The `openid`/scope configuration grants least privilege; unused scopes (and their consent) are removed.

## Exercises

**1. Hijack a stateless callback, then close it.** Build (or take) an OAuth login that omits `state`.
Demonstrate the login-CSRF: complete a flow so a victim's browser lands in an attacker-initiated
session. Then add per-attempt `state` and show the same attack now fails at the callback. The
artifact is the attack walkthrough and the before/after.

**2. Prove the access token isn't identity.** In your integration, attempt to establish a session
using a provider access token (one minted for a different client, if you can obtain one). Show
whether it's accepted. If it is, switch identity to a verified ID token with `aud` checked, and show
the substitution is now rejected. The artifact is the two runs and the audience check that closed
it.

**3. Verify an ID token from scratch.** Given a real ID token and the provider's JWKS URL, write the
full verification: fetch keys by `kid`, pin the algorithm, assert `iss`/`aud`/`exp`, and match a
`nonce` you generated. Then feed it a tampered token, a wrong-audience token, and an expired token
and show each is rejected. The artifact is the verifier and the four test cases.

**4. Compare direct integration to a broker.** Implement Google sign-in twice: once directly with
every binding parameter, once through an auth broker (Auth0/Clerk/Supabase/Better Auth). Compare the
code you had to write and secure, and list which of this chapter's attacks each approach makes you
responsible for. Decide which you'd ship and justify it. The artifact is the comparison and the
decision.

## Further Reading

- **OAuth 2.0 Security Best Current Practice (RFC 9700 / datatracker.ietf.org)** — the IETF's
  consolidated, current security guidance: why Authorization Code + PKCE is the default, redirect-URI
  handling, and the attacks (CSRF, mix-up, code injection) this chapter defends.
- **OpenID Connect Core 1.0 (openid.net/specs)** — the authentication layer's specification: the ID
  token, `nonce`, and the validation rules that separate OIDC authentication from bare OAuth.
- **RFC 7636 — Proof Key for Code Exchange (PKCE)** — the mechanism and threat model for binding the
  authorization code to the client; now recommended for all client types.
- **OAuth 2.0 Simplified by Aaron Parecki (oauth.com)** — a clear, practical walkthrough of the
  flows and parameters, good for building the mental model before reading the RFCs.
- **Chapter 02 — JWT Security** and **Stage 3, Chapter 03 — Authentication** — the ID-token
  verification rules this chapter reuses, and the first-party auth this delegated flow is an
  alternative to.

# CSRF, CORS & Browser Security

## Introduction

The last two chapters defended against input the attacker sends *to* your system (SQL injection) and
content that executes *in* your users' browsers (XSS). This chapter defends against a subtler class:
attacks that abuse the browser's own behavior — specifically, the fact that browsers automatically
attach a user's cookies to requests regardless of what site initiated them. That single convenience
is the root of Cross-Site Request Forgery (CSRF), and understanding it requires understanding the
browser's security model: the Same-Origin Policy, how CORS *relaxes* it (and why CORS is not a
defense against anything), and the headers that tell the browser how to protect your users.

The chapter's central and most-confused relationship is CORS versus CSRF. They sound related and are
constantly conflated, including by assistants, but they are nearly opposites. The Same-Origin Policy
stops one site from *reading* another site's responses. CORS is how you *deliberately relax* that
policy to let a trusted frontend read your API — it is a mechanism for granting access, and
misconfiguring it *creates* holes rather than closing them. CSRF is a completely different attack:
the malicious site doesn't need to *read* your response; it just needs the browser to *send* a
state-changing request with the victim's cookies attached, and CORS does nothing to stop that.
Defending CSRF needs its own controls — `SameSite` cookies and CSRF tokens — and believing CORS
handles it is one of the most common and dangerous misunderstandings in web security.

So this chapter covers: the Same-Origin Policy and CORS (what it is, what it emphatically is not),
CSRF (the mechanism, and the `SameSite` + token defenses), clickjacking (`frame-ancestors`), and the
security-header set (HSTS, `X-Content-Type-Options`, `Referrer-Policy`, and the CSP from Chapter 06)
that together form the browser's instructions for protecting your users. The boundaries: `HttpOnly`
cookies (Chapter 02) are *why* CSRF matters here — cookie-borne credentials are what CSRF abuses;
CSP (Chapter 06) shares this response and is referenced, not repeated; and TLS/HTTPS termination
itself is **Stage 7, Chapter 04** — this chapter sets the headers that ride on top of it.

## Why It Matters

Browser-security misconfigurations are uniquely dangerous because they're invisible in normal use,
easy to get subtly wrong, and often *introduced* by an attempt to fix an unrelated error.

- **CSRF turns the victim's own authenticated session against them.** If a state-changing endpoint
  is authenticated only by a cookie the browser sends automatically, then a malicious page the victim
  visits can trigger that endpoint — transferring money, changing an email, deleting data — using the
  victim's logged-in session, without the victim doing anything but loading the attacker's page. The
  request looks completely legitimate to the server because, in every respect it checks, it *is*.
- **A misconfigured CORS policy leaks authenticated data to any site.** CORS done wrong —
  reflecting any origin and allowing credentials — tells the browser it's fine for *any* website to
  read your API's authenticated responses. Now any page the victim visits can read their invoices,
  profile, and data through their session. The wildcard-with-credentials and origin-reflection
  misconfigurations are common precisely because they make a frustrating CORS error go away.
- **CORS is not a security control, and treating it as one is a vulnerability.** CORS *grants*
  cross-origin read access; it doesn't restrict attackers. It's enforced by the victim's browser,
  not your server, and only governs *reading responses* — it has no bearing on whether a
  state-changing request is *sent* (that's CSRF). Relying on CORS to "protect the API" is a category
  error that leaves both CSRF and server-to-server access wide open.
- **Clickjacking hijacks the user's clicks.** If your app can be framed by another site, an attacker
  can overlay it invisibly and trick the user into clicking buttons in *your* app they can't see —
  confirming a payment, granting a permission. The defense is a header telling the browser not to
  allow framing.
- **Missing security headers leave defenses off by default.** Without HSTS, a user's first request
  can be downgraded to HTTP and hijacked; without `X-Content-Type-Options: nosniff`, the browser may
  execute a file you served as data; without a `Referrer-Policy`, URLs (possibly containing tokens)
  leak to other sites. These are one-line headers that close real gaps.
- **The AI dimension is acute for exactly the confusable parts.** Assistants "fix" CORS errors by
  reflecting the origin with credentials, omit CSRF protection on cookie-authenticated endpoints
  (assuming a JSON API or SPA is immune), and conflate CORS with CSRF defense. Each produces a
  working app with a browser-abuse hole that no functional test reveals.

## Mental Model

The browser is an active participant in security. The Same-Origin Policy is its default protection;
CORS relaxes it deliberately; CSRF abuses automatic cookie-sending; headers configure the rest.

```
   SAME-ORIGIN POLICY (SOP) — the browser's default
     a page at site-A cannot READ responses from site-B. (origin = scheme + host + port)
     this is what stops evil.com from reading your bank's API using your session.

   CORS — how you DELIBERATELY RELAX SOP for a trusted frontend
     your API says (via headers) "app.invoicely.com MAY read my responses":
       Access-Control-Allow-Origin: https://app.invoicely.com   ← ONE specific origin
       Access-Control-Allow-Credentials: true                    ← cookies allowed
     CORS is a GRANT, not a guard. it is enforced by the VICTIM's browser, and only governs
     READING responses. it does NOTHING about whether a request is SENT.
     ✗ Access-Control-Allow-Origin: *  WITH credentials → any site reads authenticated data
     ✗ reflecting the request Origin back → same thing, disguised

   CSRF — a DIFFERENT attack CORS does not touch
     the browser attaches your cookies to EVERY request to your site, even ones started by evil.com:
       evil.com auto-submits: POST invoicely.com/transfer  → browser adds the victim's session cookie
     the server sees a valid, authenticated request. it never needed to READ the response.
     DEFENSES (need BOTH ideas; CORS is neither):
       1. SameSite cookies  → SameSite=Lax/Strict: browser won't send the cookie on cross-site requests
       2. CSRF token        → a secret the attacker's page can't know/read, required on state changes
                              (synchronizer token, or double-submit cookie)
     note: token-in-header auth (Authorization: Bearer) is NOT auto-sent → not CSRF-prone,
           but is XSS-prone (Ch 06). cookie auth flips the trade. that's why Ch 02 pairs
           HttpOnly cookies WITH CSRF defense.

   THE REST OF THE BROWSER'S INSTRUCTIONS (security headers)
     Content-Security-Policy   → XSS backstop (Ch 06)
     Strict-Transport-Security → force HTTPS, no downgrade (HSTS)
     X-Frame-Options/frame-ancestors → no framing → clickjacking defense
     X-Content-Type-Options: nosniff → don't guess content types
     Referrer-Policy           → don't leak URLs (and tokens in them) to other sites
```

Three principles carry the chapter:

**CORS relaxes the Same-Origin Policy; it never protects anything.** Configure it as a tight grant to
your specific trusted origins, and understand that a permissive CORS policy is a hole, not a
loosened guard. If you're reaching for CORS to "secure" something, you have the wrong tool.

**CSRF is about requests being *sent*, not responses being *read* — defend it with `SameSite` and
tokens.** Cookie-authenticated state changes need explicit CSRF defense because the browser sends
the cookie automatically. `SameSite=Lax` is a strong baseline; a CSRF token is the belt-and-braces
for sensitive actions. CORS is irrelevant to this.

**Security headers are cheap, high-leverage defaults — set them all, everywhere.** HSTS, frame
denial, nosniff, referrer policy, and CSP are one-line instructions that close real gaps, set once
in middleware/edge on every response including errors.

A working definition:

> **Browser security is configuring the browser's own protections correctly: relaxing the
> Same-Origin Policy only as far as needed via a tight CORS grant (never mistaking CORS for a
> defense), defending cookie-authenticated state changes against CSRF with `SameSite` cookies and
> CSRF tokens, preventing clickjacking by denying framing, and setting the header suite (HSTS,
> nosniff, referrer policy, CSP) that tells the browser how to protect your users.**

## Production Example

**Invoicely** is a Next.js frontend at `app.invoicely.com` talking to a FastAPI backend at
`api.invoicely.com`, with the session in an `HttpOnly` cookie (Chapter 02). This topology forces
every decision in this chapter: two origins mean CORS must be configured (and configured *tightly*),
and cookie authentication means CSRF defense is mandatory. This chapter sets all of it correctly and
shows the misconfigured version of each.

CORS is a precise grant: `Access-Control-Allow-Origin: https://app.invoicely.com` (the exact
frontend origin, never `*`, never reflected), `Access-Control-Allow-Credentials: true`, and a
minimal set of allowed methods and headers. An attacker's page at `evil.com` is simply not in the
allowlist, so the browser refuses to let it read Invoicely's authenticated responses. The chapter is
explicit that this CORS config is *not* the CSRF defense — it governs reading, not sending.

CSRF is defended in two layers. The session cookie is `SameSite=Lax`, so the browser won't attach it
to cross-site POSTs — neutralizing the classic form-submission CSRF for free. On top of that, the
sensitive state-changing endpoints (change email, initiate a payout, delete account) require a CSRF
token via the double-submit pattern: the frontend reads a non-`HttpOnly` CSRF cookie and echoes it
in a header, which the server checks against the cookie — a value `evil.com` can neither read nor
guess. Clickjacking is closed with `frame-ancestors 'none'` (and `X-Frame-Options: DENY` for old
browsers), so no site can frame Invoicely. And the full header suite rides on every response, set in
one place: HSTS to force HTTPS, `nosniff`, a strict `Referrer-Policy`, and the CSP from Chapter 06.
In this chapter we build this configuration and contrast it with the assistant-default versions: the
reflected-origin CORS, the state-changing endpoint with no CSRF token, the app that thinks its CORS
policy protects it.

## Folder Structure

```
api/ (FastAPI — Stage 3)
├── core/
│   ├── cors.py             # tight CORS: exact allowed origins, credentials, minimal methods/headers
│   ├── csrf.py             # double-submit CSRF: issue token cookie, verify header on state changes
│   └── security_headers.py # HSTS, frame-ancestors, nosniff, Referrer-Policy, CSP (Ch 06) — one place
├── main.py                 # wires the middleware in the right order
web/ (Next.js — Stage 4)
├── lib/api.ts              # sends credentials + echoes the CSRF token header on mutations
└── middleware.ts           # frontend security headers (CSP for the app shell)
tests/
└── security/
    └── test_browser_security.py  # cross-origin read blocked, CSRF-less POST rejected, headers present
```

Why this shape:

- **`cors.py` separate and explicit** makes the allowlist of origins a reviewed, named list — not an
  inline `*` that drifts in during a debugging session. One place to see exactly who may read the
  API.
- **`csrf.py`** isolates the CSRF token issuing and verification so the double-submit logic is
  implemented once and applied consistently to every state-changing route, rather than
  half-remembered per endpoint.
- **`security_headers.py` as one middleware** guarantees the header suite is on *every* response —
  including error responses, which are easy to miss and are still attackable — and keeps CSP
  (Chapter 06) and these headers coherent in one place.
- **`web/lib/api.ts`** centralizes the frontend's credential-sending and CSRF-header echoing, so no
  individual fetch call forgets the token.
- **`tests/security/test_browser_security.py`** proves the cross-origin read is blocked, a
  CSRF-token-less state change is rejected, and the headers are present — the verification, in CI.

## Implementation

**Tight CORS (`cors.py`): an exact grant, never a wildcard or a reflection.** This is the difference
between "my frontend can read the API" and "any site can read authenticated data."

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://app.invoicely.com"],   # EXACT origin(s) — never "*", never reflected
    allow_credentials=True,                          # cookies allowed → origin MUST be specific
    allow_methods=["GET", "POST", "PATCH", "DELETE"],
    allow_headers=["Authorization", "Content-Type", "X-CSRF-Token"],
    max_age=600,
)
# CRITICAL: allow_origins=["*"] together with allow_credentials=True is rejected by the spec for a
# reason — and "reflect whatever Origin was sent" is the same hole wearing a disguise. Don't.
```

The rule the spec enforces and assistants break: you cannot combine `*` with credentials. The
dangerous workaround — reflecting the request's `Origin` header back — recreates exactly the hole the
spec forbids, letting any origin read credentialed responses.

**CSRF defense (`csrf.py`): `SameSite` plus a double-submit token.** Two layers, because the cookie
is auto-sent.

```python
# Layer 1: the session cookie is SameSite — the browser won't send it on cross-site requests
set_cookie("session", token, httponly=True, secure=True, samesite="lax")

# Layer 2: double-submit CSRF token for state-changing endpoints
def issue_csrf(response):
    token = secrets.token_urlsafe(32)
    response.set_cookie("csrf", token, secure=True, samesite="lax")  # readable by JS (NOT httponly)

def verify_csrf(request):
    cookie = request.cookies.get("csrf")
    header = request.headers.get("X-CSRF-Token")
    if not cookie or not header or not secrets.compare_digest(cookie, header):
        raise CsrfError()   # evil.com can't read the cookie value, so it can't set the matching header
```

Why double-submit works: `evil.com` can cause the browser to *send* the CSRF cookie (cookies are
auto-attached) but cannot *read* its value (Same-Origin Policy), so it cannot put the matching value
in the `X-CSRF-Token` header. Only a page on your origin can read the cookie and echo it. `SameSite`
alone stops most CSRF; the token covers the residual cases and is required for the sensitive actions.

**The frontend echoes the token (`web/lib/api.ts`).**

```ts
async function mutate(url: string, body: unknown) {
  return fetch(url, {
    method: "POST",
    credentials: "include",                          // send cookies (cross-origin needs this)
    headers: { "Content-Type": "application/json",
               "X-CSRF-Token": readCookie("csrf") },  // echo the CSRF cookie into the header
    body: JSON.stringify(body),
  });
}
```

**The security-header suite (`security_headers.py`): one middleware, every response.**

```python
def security_headers(response):
    response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains; preload"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"                 # legacy clickjacking defense
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Content-Security-Policy"] = (              # Ch 06 — includes:
        "default-src 'self'; script-src 'self'; frame-ancestors 'none'")  # modern clickjacking defense
```

Each header is a one-line instruction closing a real gap: HSTS forbids HTTP downgrade, `nosniff`
stops content-type guessing, `frame-ancestors 'none'`/`DENY` blocks framing, `Referrer-Policy` stops
URL leakage. Set once, applied everywhere — including error responses.

**The attack tests (`tests/security/test_browser_security.py`): prove the config holds.**

```python
def test_cross_origin_credentialed_read_is_not_allowed(client):
    resp = client.get("/api/v1/invoices", headers={"Origin": "https://evil.com"})
    assert resp.headers.get("Access-Control-Allow-Origin") != "https://evil.com"  # not reflected

def test_state_change_without_csrf_token_is_rejected(client, session_cookie):
    resp = client.post("/api/v1/account/email", json={"email": "x@e.com"}, cookies=session_cookie)
    assert resp.status_code == 403                                # no X-CSRF-Token header

def test_security_headers_present(client):
    h = client.get("/").headers
    assert h["X-Frame-Options"] == "DENY" and "max-age" in h["Strict-Transport-Security"]
```

These are the deliverable: the cross-origin read isn't granted, the token-less state change is
rejected, the headers are present.

## Engineering Decisions

Five decisions define browser-security posture.

### How is CORS configured — and is it being asked to do the wrong job?

**Options:** (1) exact allowlist of trusted origins with credentials; (2) wildcard `*` (no
credentials); (3) reflect the request origin; (4) relying on CORS to "secure" the API.

**Trade-offs:** an exact allowlist grants precisely the origins you trust to read responses — correct
and tight. `*` without credentials is fine for genuinely public, non-credentialed APIs but useless
once cookies are involved (the spec forbids `*`+credentials). Reflecting the origin is the dangerous
anti-pattern — it's `*`+credentials in disguise, letting any site read authenticated data. And
treating CORS as a security boundary is a category error: it grants read access; it restricts
nothing.

**Recommendation:** an exact origin allowlist with credentials for your trusted frontend(s); `*`
(no credentials) only for truly public read-only APIs; never reflect the origin; never think of CORS
as protecting anything. If your reason for a CORS setting is "to secure X," stop — CORS is the wrong
tool, and you likely want authentication, CSRF defense, or network controls instead.

### How is CSRF defended on cookie-authenticated endpoints?

**Options:** (1) `SameSite` cookies alone; (2) `SameSite` + CSRF tokens (double-submit or
synchronizer); (3) nothing (assume the API/SPA is immune); (4) use header-based token auth instead of
cookies.

**Trade-offs:** `SameSite=Lax` stops the browser sending the cookie on cross-site navigations/forms —
a strong, free baseline, but with edge cases (some cross-site flows, older browsers, and `Lax`
still allows top-level GET navigations). Adding a CSRF token covers the residual cases and is
standard for sensitive actions. Doing nothing on cookie auth is a live CSRF vulnerability. Switching
to header-based `Authorization: Bearer` tokens sidesteps CSRF entirely (headers aren't auto-sent) but
reopens XSS token theft (Chapter 06) — the trade Chapter 02 analyzed.

**Recommendation:** for cookie-authenticated apps, `SameSite=Lax` (or `Strict` where UX allows) as
the baseline *plus* a CSRF token (double-submit) on state-changing endpoints, required for sensitive
actions. Never rely on "it's a JSON API/SPA so it's safe" — that's false. If you use header tokens
instead, you trade CSRF for XSS exposure and must harden accordingly; there's no free option, only a
deliberate choice.

### Which security headers, and where are they set?

**Options:** (1) the full suite (HSTS, CSP, frame denial, nosniff, referrer policy) in one place;
(2) a subset; (3) set per-route/ad hoc; (4) none.

**Trade-offs:** the full suite set centrally (middleware or edge/Nginx from Stage 7) is
comprehensive and consistent, including on error responses. A subset leaves specific gaps (no HSTS =
downgrade risk; no frame denial = clickjacking). Per-route setting inevitably misses responses. None
leaves every browser-side default gap open.

**Recommendation:** set the full suite in one middleware (or at the edge) so it applies to every
response including errors. HSTS with a long max-age and `includeSubDomains` (and `preload` once
confident), CSP from Chapter 06, `frame-ancestors 'none'`/`X-Frame-Options: DENY`, `nosniff`, and a
strict `Referrer-Policy`. These are cheap and high-leverage; there's no good reason to omit any.

### `SameSite=Lax`, `Strict`, or `None`?

**Options:** (1) `Lax` — cookie sent on same-site and top-level GET navigations; (2) `Strict` — never
sent cross-site; (3) `None` — always sent cross-site (requires `Secure`).

**Trade-offs:** `Lax` is the sensible default — it blocks cross-site POST CSRF while still letting a
user following a link to your site arrive logged in. `Strict` is more secure but breaks that "click a
link, arrive logged in" flow (the user appears logged out until they navigate). `None` sends the
cookie on all cross-site requests — necessary for some legitimate cross-site embedding, but it
*reopens* CSRF and must be paired with tokens.

**Recommendation:** `SameSite=Lax` for session cookies as the default; `Strict` for the most
sensitive cookies where the UX cost is acceptable. Use `None` only when a genuine cross-site scenario
requires it, always with `Secure` *and* CSRF tokens, understanding you've turned the CSRF baseline
back off. Never set `None` casually to fix a cross-site cookie problem.

### Can your app be framed?

**Options:** (1) deny all framing (`frame-ancestors 'none'` / `X-Frame-Options: DENY`); (2) allow
specific origins to frame; (3) allow framing (no header).

**Trade-offs:** denying framing closes clickjacking completely and is right for almost all apps.
Allowing specific origins supports legitimate embedding (a partner dashboard) while blocking others.
Allowing any framing exposes every click-driven action to clickjacking overlays.

**Recommendation:** deny framing by default (`frame-ancestors 'none'`, plus `X-Frame-Options: DENY`
for legacy browsers). Allowlist specific framing origins only when a real embedding use case exists,
and never leave framing wide open — a bank-transfer or permission-grant button under an invisible
overlay is a real attack.

## Trade-offs

**Tight CORS trades cross-origin convenience for not leaking authenticated data.** An exact
allowlist means adding a new frontend origin is a deliberate config change, and it can be a mild
friction during development. What it buys is that no unlisted site can read your credentialed
responses. The convenience of `*` or reflection is never worth handing your data to any origin the
victim visits.

**CSRF tokens trade a little plumbing for closing the cookie-auth hole.** Issuing, storing, and
echoing a token adds request-flow machinery beyond `SameSite` alone. The payoff is covering
`SameSite`'s residual cases and protecting sensitive actions robustly. For cookie-authenticated apps
this plumbing is not optional overhead — it's the defense.

**`SameSite=Strict` trades a smoother login-via-link UX for maximal CSRF protection.** `Strict` never
sends the cookie cross-site, so a user clicking a link to your app appears logged out until they act.
`Lax` restores that flow while still blocking cross-site POSTs. Choose per cookie sensitivity; most
apps land on `Lax` for the session and reserve `Strict` for the highest-value cookies.

**A strict header suite trades rollout care for closing many gaps cheaply.** HSTS in particular is
near-permanent (browsers remember it), so a misconfiguration can lock users to HTTPS on a domain
that isn't ready — hence rolling out with a shorter max-age first. The headers are cheap and
powerful; the only cost is deploying them thoughtfully, especially HSTS `preload`.

## Common Mistakes

**Wildcard or reflected CORS with credentials.** `Access-Control-Allow-Origin: *` (or the reflected
origin) with `Allow-Credentials: true`, letting any site read authenticated data. Fix: an exact
origin allowlist; never `*`+credentials, never reflection.

**No CSRF protection on cookie-authenticated state changes.** Relying on the auto-sent cookie alone,
so any page can trigger the endpoint. Fix: `SameSite=Lax` plus a CSRF token on state-changing routes.

**Believing CORS defends against CSRF.** Configuring CORS and assuming state-changing requests are
now safe — they aren't; CORS governs reading, CSRF is about sending. Fix: understand they're separate;
defend CSRF explicitly.

**`SameSite=None` set casually.** Switching to `None` to fix a cross-site cookie issue, silently
reopening CSRF. Fix: use `Lax`/`Strict` by default; `None` only with `Secure` and CSRF tokens and a
real reason.

**Missing security headers.** No HSTS (downgrade risk), no frame denial (clickjacking), no `nosniff`.
Fix: the full header suite in one middleware on every response.

**Headers missing on error responses.** Security headers set only on success paths, absent on 4xx/5xx.
Fix: set them in middleware/edge so every response carries them.

## AI Mistakes

Browser security is the area where assistants most confidently produce insecure config, because the
confusable concepts (CORS vs CSRF) invite exactly the wrong fix and the results all "work." Review
CORS and CSRF config against the mechanism, not against whether the app functions.

### Claude Code: reflecting the Origin into the CORS response with credentials

Faced with a CORS error, Claude Code frequently "fixes" it by making the allowed origin dynamic —
reading the request's `Origin` header and echoing it back into `Access-Control-Allow-Origin` while
keeping `Allow-Credentials: true`. The error disappears and the frontend works. But origin reflection
means the server approves *every* origin, including `evil.com`, for credentialed reads — it's exactly
the `*`+credentials hole the spec forbids, reconstructed by hand. Any site the victim visits can now
read their authenticated data.

**Detect:** CORS config that reads `request.headers["Origin"]` and returns it in
`Access-Control-Allow-Origin`; `Allow-Credentials: true` alongside a non-static origin; a CORS
"allowlist" that always contains whatever origin asked; the fix for a CORS error being "make the
origin dynamic."

**Fix:** a static allowlist, never reflection:

> Never reflect the request Origin into `Access-Control-Allow-Origin` with credentials — that allows
> every origin, including attackers, to read authenticated responses. Use a static allowlist of exact
> trusted origins. If an origin needs access, add it to the list explicitly. Add a test that an
> untrusted Origin is not reflected.

### GPT: no CSRF protection because "it's a JSON API / SPA"

GPT-family models frequently build cookie-authenticated state-changing endpoints with no CSRF defense
at all, on the implicit assumption that a JSON API or a SPA is immune — a widespread myth. Cookie
authentication is CSRF-prone regardless of whether the body is JSON or the client is a SPA: the
browser still auto-attaches the cookie to a cross-site request, and simple content types (or a
form-encoded body) can be sent cross-origin without even triggering CORS preflight. The endpoints
work for the real frontend and are triggerable by any malicious page.

**Detect:** cookie-authenticated POST/PATCH/DELETE endpoints with no CSRF token check and no
`SameSite` reasoning; the assumption (in code or comments) that JSON/SPA is CSRF-safe; `SameSite` not
set on the session cookie; no CSRF middleware.

**Fix:** defend CSRF explicitly on cookie auth:

> Cookie-authenticated state-changing endpoints are CSRF-prone regardless of JSON or SPA. Set the
> session cookie `SameSite=Lax` and require a CSRF token (double-submit) on all state-changing
> routes. Add a test that a state change without the CSRF token is rejected.

### Cursor: conflating CORS and CSRF (fixing the wrong one)

Asked to address CSRF, or completing security config, Cursor tends to add or tighten *CORS* settings
and treat the CSRF concern as handled — or, conversely, to loosen `SameSite`/CORS to fix a
cross-origin request failure, reopening CSRF in the process. The confusion runs both ways: CORS
config presented as CSRF protection, and CSRF defenses weakened to resolve a CORS/cross-site error.
Either way the actual CSRF exposure is left open while the code looks like it addressed security.

**Detect:** CORS changes in a commit whose stated purpose is CSRF (or vice versa); `SameSite`
downgraded to `None` to fix a cross-origin issue; CSRF described as handled by CORS in comments/PRs;
no distinct CSRF token mechanism despite "CSRF" being addressed.

**Fix:** treat them as the separate problems they are:

> CORS and CSRF are different: CORS governs whether other origins can *read* responses; CSRF is
> about state-changing requests being *sent* with the victim's cookies. Fixing one does not address
> the other. Defend CSRF with `SameSite` + a token, and configure CORS as a tight read-grant
> separately. Don't weaken `SameSite`/CSRF to resolve a CORS error.

## Best Practices

**Configure CORS as a tight, static grant — and never as a defense.** Exact trusted origins with
credentials; never `*`+credentials, never origin reflection; understand CORS grants read access and
protects nothing.

**Defend CSRF explicitly on cookie auth: `SameSite` + tokens.** `SameSite=Lax` (or `Strict`) baseline
plus a double-submit CSRF token required on state-changing and sensitive endpoints. Never assume
JSON/SPA immunity.

**Keep CORS and CSRF conceptually separate.** They solve different problems; fixing one never
addresses the other, and weakening one to fix the other's error is how holes open.

**Set the full security-header suite in one place.** HSTS, CSP (Chapter 06), `frame-ancestors
'none'`/`X-Frame-Options: DENY`, `nosniff`, strict `Referrer-Policy` — in middleware or at the edge,
on every response including errors.

**Choose `SameSite` deliberately per cookie.** `Lax` default, `Strict` for the most sensitive,
`None` only with `Secure` + CSRF tokens and a real cross-site need.

**Deny framing by default.** `frame-ancestors 'none'` and `X-Frame-Options: DENY`; allowlist specific
framing origins only for genuine embedding.

**Roll out HSTS carefully.** Start with a shorter max-age, then extend and add `preload` once the
domain is fully HTTPS-committed — HSTS is sticky and hard to undo.

**Test the browser-security config.** Cross-origin credentialed reads not granted, token-less state
changes rejected, headers present — a security test per control, green in CI.

## Anti-Patterns

**The Reflected Origin.** CORS echoing the request origin with credentials. The tell: `Origin` read
and returned in `Access-Control-Allow-Origin`; `Allow-Credentials: true` with a dynamic origin; any
origin gets access.

**The Undefended Cookie.** Cookie-authenticated state changes with no CSRF token. The tell: mutating
endpoints with no token check; `SameSite` unset; "it's a JSON API" as the safety argument.

**The CORS-As-CSRF Confusion.** CORS config presented as CSRF defense (or CSRF weakened to fix CORS).
The tell: "CSRF handled by CORS"; `SameSite=None` added to resolve a cross-site error; no distinct
CSRF mechanism.

**The Casual `SameSite=None`.** `None` set to make a cross-site cookie work, reopening CSRF. The
tell: `SameSite=None` with no CSRF tokens and no stated cross-site requirement.

**The Framable App.** No framing defense. The tell: no `frame-ancestors`/`X-Frame-Options`;
click-driven sensitive actions with no clickjacking protection.

**The Headerless Response.** Missing security headers, especially on errors. The tell: no HSTS/CSP/
nosniff; headers present on 200s but absent on 4xx/5xx.

## Decision Tree

"I'm handling a cross-origin or cookie-auth concern — which control do I actually need?"

```
What is the actual concern?
├── "another origin (my frontend) needs to READ my API's responses"
│     └─► CORS: static allowlist of exact trusted origins + credentials. never *, never reflected.
│         (this is a GRANT. it protects nothing. don't use it to 'secure' anything.)
│
├── "a state-changing endpoint is authenticated by a COOKIE"
│     └─► CSRF defense (CORS is irrelevant here):
│         1. SameSite=Lax/Strict on the session cookie
│         2. double-submit CSRF token required on state changes (mandatory for sensitive actions)
│         └── using Authorization: Bearer header tokens instead? not CSRF-prone, but XSS-prone (Ch 06).
│
├── "could my app be framed / clicks hijacked?"
│     └─► frame-ancestors 'none' (+ X-Frame-Options: DENY). allowlist framers only if truly needed.
│
├── "am I leaking over HTTP / to other sites / via content sniffing?"
│     └─► HSTS (force HTTPS) · Referrer-Policy (no URL leak) · nosniff · all in one header middleware.
│
└── "I have a CORS error and want to make it go away"
      └─► add the specific origin to the allowlist. NEVER reflect the origin, NEVER add
          *+credentials, NEVER weaken SameSite. the error is the guard working.
```

## Checklist

### Implementation Checklist

- [ ] CORS uses a static allowlist of exact trusted origins with credentials; no `*`+credentials and no origin reflection.
- [ ] Session cookies are `SameSite=Lax` (or `Strict`), `Secure`, and `HttpOnly` (Chapter 02).
- [ ] State-changing endpoints require a CSRF token (double-submit or synchronizer); sensitive actions always do.
- [ ] The full security-header suite (HSTS, CSP, `frame-ancestors`/`X-Frame-Options`, `nosniff`, `Referrer-Policy`) is set in one middleware/edge config.
- [ ] Framing is denied by default (`frame-ancestors 'none'` + `X-Frame-Options: DENY`).
- [ ] Cross-origin read, token-less state change, and header presence are covered by security tests.

### Architecture Checklist

- [ ] CORS and CSRF are implemented as separate, clearly-purposed mechanisms; neither is mistaken for the other.
- [ ] The CORS origin allowlist is a reviewed, named list, not an inline dynamic value.
- [ ] CSRF token issuing/verification is centralized and applied consistently to all state-changing routes.
- [ ] The cookie-vs-header auth trade (CSRF vs XSS exposure) is made deliberately and matches Chapter 02.
- [ ] Security headers are set at a single layer that covers every response, including errors.

### Code Review Checklist

- [ ] No CORS config reflects the request Origin or combines `*` with credentials.
- [ ] No cookie-authenticated state-changing endpoint lacks CSRF protection.
- [ ] No commit weakens `SameSite`/CSRF to resolve a CORS/cross-origin error, and no CORS change is labeled as CSRF defense.
- [ ] `SameSite=None` appears only with `Secure`, CSRF tokens, and a documented cross-site need.
- [ ] Security headers are present on error responses, not only success paths.

### Deployment Checklist

- [ ] HSTS is rolled out with an appropriate max-age (short first, then extended), and `preload` only once fully HTTPS-committed.
- [ ] Security headers are set at the edge (Nginx, Stage 7 Chapter 04) or app middleware consistently across environments.
- [ ] CORS allowed origins are environment-specific (dev/staging/prod), never a shared permissive value.
- [ ] Clickjacking and CSRF protections are verified against the deployed app, not just in unit tests.

## Exercises

**1. Exploit a reflected-origin CORS misconfig.** Configure CORS to reflect the request origin with
credentials. From a page on a different origin, read an authenticated API response using a victim
session. Then switch to a static allowlist and show the cross-origin read is blocked. The artifact is
the exploit page, the two CORS configs, and the blocked read.

**2. Forge a state change via CSRF, then defend it.** Take a cookie-authenticated state-changing
endpoint with no CSRF defense. Build an attacker page that auto-submits a request triggering it with
the victim's session. Then add `SameSite=Lax` and a double-submit token and show the forged request
now fails. The artifact is the attack page and the before/after.

**3. Demonstrate the CORS≠CSRF distinction.** With a tight CORS allowlist in place, show that a
cross-site CSRF attack *still succeeds* against an unprotected state-changing endpoint — proving CORS
doesn't defend CSRF. Then add CSRF tokens and show it's finally blocked. The artifact is the two
attacks proving CORS was never the defense.

**4. Audit and set the header suite.** Inspect your app's response headers (including a 404 and a
500). Add every missing security header in one middleware, verify they appear on all responses
including errors, and roll out HSTS safely. The artifact is the before/after header dump across
success and error responses.

## Further Reading

- **OWASP Cross-Site Request Forgery Prevention Cheat Sheet (cheatsheetseries.owasp.org)** — the
  authoritative guide to `SameSite`, synchronizer and double-submit tokens, and the cookie-auth threat
  model this chapter defends.
- **MDN — Cross-Origin Resource Sharing (CORS) (developer.mozilla.org)** — the precise semantics of
  the CORS headers, preflight, and the `*`+credentials restriction, clarifying what CORS does and
  does not do.
- **MDN — SameSite cookies and Set-Cookie** — the exact behavior of `Lax`/`Strict`/`None` and the
  `Secure`/`HttpOnly` attributes that underpin the CSRF baseline.
- **OWASP Secure Headers Project (owasp.org/www-project-secure-headers)** — the recommended header
  suite (HSTS, CSP, frame options, nosniff, referrer policy) with values and rollout guidance.
- **Chapter 02 — JWT Security** (why cookie auth pairs with CSRF defense) and **Chapter 06 — XSS &
  Content Security** (the CSP that shares this header response) — the chapters this one interlocks
  with; TLS/HTTPS itself is Stage 7, Chapter 04.

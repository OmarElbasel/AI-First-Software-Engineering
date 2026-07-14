# CDN

## Introduction

Every chapter so far has scaled the origin — more instances, shared state, wider queues. A
CDN takes the other path: it arranges for most requests to never reach the origin at all. A
content delivery network is a fleet of caching proxies (points of presence, PoPs) spread
across the world; users connect to the nearest one, and responses the CDN is allowed to
cache are served from there — at single-digit-millisecond latency, at capacity you'll never
saturate, without touching a machine you pay to scale. For the read-heavy fraction of any
web product — JavaScript bundles, images, fonts, marketing pages, PDF downloads — it is the
cheapest capacity on Chapter 01's ladder, and the only remedy on the ladder that also fixes
physics: no amount of origin scaling makes a round trip from Sydney to a Frankfurt VPS
shorter.

The engineering catch is that a CDN is a cache **you configure but don't operate**, sitting
in front of *everything*, obeying instructions you publish in HTTP headers. That inversion
is the whole discipline: the origin doesn't serve responses anymore — it serves responses
*plus caching policy*, and the policy is enforced by thousands of edge servers that will do
exactly what the headers say, at scale, including the wrong thing. Most CDN value is
realized through getting one header right (`Cache-Control`), and the worst CDN incident
class — serving one user's private data to another user, from a cache, worldwide — comes
from getting the same header wrong.

This chapter covers the CDN as a component: the header contract (`Cache-Control`, validators,
`Vary`), a taxonomy of content classes and the correct policy for each, cache keys and the
poisoning/leak risks around them, invalidation (why fingerprinting beats purging), and
private content at the edge via signed URLs. It stays vendor-neutral per the Constitution:
Cloudflare, Fastly, and CloudFront differ in dashboards, not in the HTTP semantics this
chapter teaches.

## Why It Matters

- **It removes load instead of absorbing it.** Chapters 02–05 made the origin stronger; the
  CDN makes most requests never arrive. For Invoicely's frontend, ~90% of bytes (JS, CSS,
  fonts, images) can leave the origin permanently — capacity that costs a config file, not
  a fleet.
- **Latency is physics, and only edges fix it.** A Frankfurt origin serves São Paulo at
  ~200ms RTT before the first byte of the *fourth* asset. TTFB from a local PoP is ~10ms.
  For global users, the CDN does more for perceived performance (Stage 4, Chapter 07's
  metrics) than any origin optimization can.
- **It is spike armor for the read side.** The pricing page going viral, a customer's
  public invoice link shared widely, month-end PDF re-downloads — read spikes land on the
  edge, which is provisioned for the internet's scale, not yours. The origin sees one
  request per TTL window instead of one per reader.
- **Misconfiguration fails at cache scale.** A missing `private` directive doesn't leak
  one response — it leaks the first authenticated user's dashboard to every subsequent
  visitor of that URL until the TTL expires, from every PoP that cached it. Stage 9 taught
  vulnerability classes; this is the one where the amplifier is built in.
- **Deploys and caching interact by default.** Ship new HTML referencing new JS while old
  JS lives at the edge for a day, and users get white screens — the classic Monday-deploy
  bug. Asset strategy (fingerprinting) is what makes long cache lifetimes and continuous
  deployment compatible, and it has to be designed, not hoped.

## Mental Model

**The CDN is an obedient HTTP cache between users and origin.** Its behavior is almost
entirely a function of what your origin says:

```
 user ──► nearest PoP ──────────────────────────► origin
           │  cache key: METHOD + host + path      │
           │  (+ query, + whatever Vary names)     │
           │                                       │
           │  HIT: serve from edge (origin never   │
           │       sees the request)               │
           │  MISS/EXPIRED: fetch from origin ─────┘
           │       obeying the response's headers:
           │
           │  Cache-Control: public, max-age=..., s-maxage=...
           │       → cacheable; how long (s-maxage = "for shared
           │         caches like me", overrides max-age at the edge)
           │  Cache-Control: private | no-store
           │       → NOT cacheable at the edge (private = browsers
           │         only; no-store = nobody)
           │  stale-while-revalidate=N
           │       → serve stale instantly, refresh in background
           │  ETag / Last-Modified
           │       → revalidation: origin answers 304 (cheap)
           │         instead of resending the body
           │  Vary: <header names>
           │       → those headers join the cache key: variants
           │         are stored separately
```

Two defaults to burn in: **the edge caches what you tell it to** — and CDNs also apply
their own defaults for responses with *no* caching headers (some cache them!), which is
why the origin must be explicit on every response, and why the safe application default
is `private, no-store` with caching as a deliberate opt-in.

**Content is not one thing — policy follows class.** The taxonomy that decides every
header:

```
 CLASS                 EXAMPLES                    POLICY
 immutable versioned   /_next/static/*, hashed     public, max-age=31536000,
 assets                bundles, fonts, logo.        immutable — cache FOREVER;
                       [hash].png                   the URL changes when the
                                                    content does (fingerprint)
 semi-static shared    marketing pages, docs,       public, s-maxage=minutes..
 (same for everyone)   blog, public status/pricing  hours + stale-while-
                                                    revalidate — freshness is
                                                    a dial, not a fight
 private files         invoice PDFs, exports,       edge-cacheable ONLY behind
                       uploaded logos               signed URLs (below);
                                                    otherwise private
 per-user dynamic      dashboard, API responses,    private, no-store. The
                       anything behind auth         edge never sees it twice
```

**Invalidation strategy is chosen at URL-design time.** Two ways to update a cached asset:
change the URL (fingerprinting — `app.3f9a2c.js`; the old asset stays valid for old HTML,
the new HTML references the new URL, nothing is ever stale *or* purged), or purge the URL
(an API call to the CDN asking thousands of PoPs to forget — eventually). Fingerprinting
turns cache invalidation — famously one of the two hard problems — into a non-problem for
assets, which is why every modern bundler does it. Purging remains the escape hatch for
mutable-URL content (the marketing page you must update *now*) and the emergency lever —
not the deployment mechanism.

**The cache key is a security boundary.** Whatever isn't in the key can't distinguish
responses — so if a response *varies* by something (cookie, `Accept-Language`, tenant, auth
state) that the key doesn't include, users receive each other's variants. That's the leak.
The converse is the poisoning attack: if an attacker can influence an *unkeyed* input that
shapes the response (a reflected header, an ignored query parameter), they can poison the
cached copy that everyone else receives. `Vary` is how a response declares its true inputs;
the safest design keeps cacheable responses a function of the URL alone.

**Private content at the edge = capability URLs.** A signed URL (issued by the app,
verified by the CDN or object store: path + expiry + HMAC) turns authorization into a
time-limited, unguessable URL — so the edge can serve a private PDF *without* seeing a
session, because possession of the URL is the proof. The app stays the authorizer (it
decides who gets a URL, per Stage 3 Ch 09 and Stage 9's rules); the edge does the byte
delivery. TTLs are short (minutes), and the private cache entry lives at the edge only as
long as its URL is valid.

A working definition:

> **A CDN deployment is a published caching policy: every response carries an explicit
> `Cache-Control` chosen by content class — immutable-forever for fingerprinted assets,
> bounded-staleness for shared pages, `private, no-store` by default for everything else —
> with cache keys that include every input the response actually varies by, fingerprinting
> (not purging) as the invalidation strategy, signed URLs where private files meet the
> edge, and the origin protected so the edge is the only door.**

## Production Example

Invoicely's CDN rollout, driven by three measured pains from the Chapter 01 load test and
one strategic need:

- **Frontend assets** dominate origin bandwidth: every dashboard load pulls ~2MB of JS,
  CSS, and fonts from the Next.js server — identical bytes, thousands of times a day,
  from three continents (the partnership brings LatAm and APAC accountants).
- **Invoice PDFs are re-downloaded heavily**: customers' clients open the same invoice
  link 5–50 times (email clients prefetch, phones re-open). Each open currently hits the
  presigned object-storage URL from Chapter 03 — fine for correctness, slow from Sydney,
  and every download bills origin egress.
- **The marketing site and docs** run on the same origin as the app; a traffic spike on
  a blog post competes with paying users' API calls for the same Nginx and instances.
- **Strategic:** the CDN's TLS + WAF + DDoS layer in front of everything is the cheapest
  way to keep junk traffic off the Chapter 02 balancer entirely.

The design: CDN in front of everything (one hostname, `app.invoicely.io`, edge-routed);
Next.js fingerprinted assets cached immutable-forever; marketing/docs pages at
`s-maxage=600, stale-while-revalidate=86400` (updates visible within 10 minutes, users
never wait on a rebuild); the API and app HTML explicitly `private, no-store`; PDFs served
from the edge via CDN-signed URLs with 15-minute expiry, issued by the API after the
Stage 3 authorization check; origin locked so only CDN traffic reaches the balancer.

## Folder Structure

The CDN work is policy code, not new services — headers at the two places responses are
born, plus edge configuration:

```
frontend/
└── next.config.ts              # headers() for marketing/docs routes
                                #   (s-maxage + SWR); /_next/static is
                                #   fingerprinted + immutable by the
                                #   framework — verify, don't reinvent
app/
├── core/
│   └── http_cache.py           # THE policy module: the no-store
│                               #   default middleware + the explicit
│                               #   cacheable() opt-in — one reviewable
│                               #   home for every caching decision
├── files/
│   └── signed_urls.py          # CDN-signed URL issuance for private
│                               #   files (replaces raw presigned-S3
│                               #   links from Ch 03 in user-facing
│                               #   flows)
infrastructure/
└── cdn/
    ├── config.md               # vendor config as documentation: zones,
    │                           #   cache rules, origin-shield choice,
    │                           #   the origin-lock secret — reviewable
    │                           #   even when the vendor UI isn't
    └── purge.sh                # the escape hatch, scripted and logged
                                #   — never a dashboard click nobody
                                #   can audit later
```

Why a single `http_cache.py`: caching headers scattered across endpoints is how one
endpoint ends up `public` by copy-paste. Policy-as-a-module means the grep for "what can
the edge cache?" has one answer, and code review guards one door.

## Implementation

The application default — nothing is edge-cacheable unless it opts in:

```python
# app/core/http_cache.py
from fastapi import Request, Response

CACHEABLE_DEFAULT = "private, no-store"

async def cache_headers_middleware(request: Request, call_next):
    """Every response leaves with EXPLICIT cache policy. Endpoints that
    set their own Cache-Control keep it; everything else is private by
    default — an unheadered response at a CDN is a coin flip we don't
    take."""
    response: Response = await call_next(request)
    response.headers.setdefault("Cache-Control", CACHEABLE_DEFAULT)
    return response


def cacheable(*, s_maxage: int, swr: int = 0, vary: tuple[str, ...] = ()):
    """The opt-in for the few public, same-for-everyone endpoints.
    Usage: return cacheable(s_maxage=300)(response). Anything using
    this MUST be auth-free and user-independent — that invariant is
    what code review checks at every call site."""
    def apply(response: Response) -> Response:
        value = f"public, max-age=60, s-maxage={s_maxage}"
        if swr:
            value += f", stale-while-revalidate={swr}"
        response.headers["Cache-Control"] = value
        if vary:
            response.headers["Vary"] = ", ".join(vary)
        return response
    return apply
```

Next.js — verify the framework's asset story, add policy for the shared pages:

```ts
// next.config.ts (excerpt)
export default {
  async headers() {
    return [
      {
        // marketing + docs: same for everyone, updated occasionally.
        // 10-minute edge freshness; a day of serve-stale keeps users
        // fast (and the site up) while the edge revalidates.
        source: "/(pricing|docs|blog)/:path*",
        headers: [{
          key: "Cache-Control",
          value: "public, s-maxage=600, stale-while-revalidate=86400",
        }],
      },
      // /_next/static/* ships fingerprinted with
      // "public, max-age=31536000, immutable" by the framework.
      // App pages (dashboard) are dynamic and remain private —
      // confirmed in the deploy checklist, not assumed.
    ];
  },
};
```

Private PDFs at the edge — the app authorizes, the URL carries the proof:

```python
# app/files/signed_urls.py
import hashlib
import hmac
import time

from app.core.config import settings

def signed_cdn_url(path: str, ttl_seconds: int = 900) -> str:
    """CDN-verified signed URL (vendor-neutral HMAC scheme; every CDN
    offers an equivalent). The edge checks expiry+signature and serves
    the object from cache or object storage; no session ever reaches
    the edge. WHO may get a URL was already decided by the caller —
    this function only mints proof, it never authorizes."""
    expires = int(time.time()) + ttl_seconds
    payload = f"{path}:{expires}"
    sig = hmac.new(
        settings.cdn_signing_key.encode(), payload.encode(), hashlib.sha256
    ).hexdigest()
    return f"https://cdn.invoicely.io{path}?exp={expires}&sig={sig}"
```

```python
# app/invoicing/api.py (excerpt) — the endpoint that mints it
@router.get("/invoices/{invoice_id}/pdf-link")
async def invoice_pdf_link(invoice_id: UUID, user: CurrentUser) -> dict:
    invoice = await invoices.get_authorized(invoice_id, user)  # St.9: IDOR check
    return {"url": signed_cdn_url(f"/pdfs/{invoice.pdf_key}"), "expires_in": 900}
```

Origin protection — the edge must be the only door, or every header above is advisory:

```nginx
# Ch 02's balancer, one addition: requests not carrying the CDN's
# secret header (set by the CDN on origin fetches) are refused.
# Without this, "private, no-store" can be bypassed by talking to
# the origin directly — and so can the CDN's WAF and rate limits.
if ($http_x_origin_key != "REPLACED_BY_DEPLOY_SECRET") { return 403; }
```

## Engineering Decisions

### What goes behind the CDN — assets only, or everything?

Everything, with policy doing the discrimination. Routing only `/static` through the CDN
leaves the origin exposed for the rest and splits TLS/DNS/WAF across two front doors. One
edge-routed hostname with per-class `Cache-Control` gets full protection and keeps caching
decisions in code (headers) rather than in routing topology. The cost is that
*every* response's headers now matter — which the no-store default middleware exists to
make safe.

### TTL and staleness per class — what's the dial?

For fingerprinted assets there is no dial: forever + `immutable` is simply correct, because
staleness is impossible when content changes mean URL changes. For shared pages the dial is
`s-maxage` (how stale can the *newest* visitor's copy be?) plus `stale-while-revalidate`
(how long may the edge keep serving while refreshing?) — set from content meaning: pricing
changes are rare but must land within minutes of a launch (600s); docs tolerate more; a
public status page tolerates *less* (30s — its whole job is freshness). The API default
stays no-store: per-user data has no safe shared TTL, and micro-caching authenticated
responses is a leak with a stopwatch.

### Fingerprint or purge?

Fingerprint everything that can be fingerprinted (bundlers do it free), and treat purge as
two things only: the update lever for honest mutable URLs (marketing HTML — purge on
publish, scripted) and the incident lever (something wrong got cached — purge-all and
investigate). Never the deploy mechanism: purge-based deploys race (global purges take
seconds-to-minutes to propagate while mixed old/new assets serve), hit vendor rate limits,
and couple every release to a CDN API being up. The fingerprint design has no race by
construction: old HTML → old (still-cached) assets; new HTML → new assets.

### Signed URLs or proxy-through-app for private files?

Signed URLs, for anything larger than a JSON response: the app does authorization once and
mints proof; bytes flow edge-to-user without occupying an app instance's connection,
worker, and bandwidth for the duration of a mobile download (Stage 3 Ch 09 made this
argument against proxying from object storage; the CDN extends it to the edge). Proxying
through the app remains right when authorization must be *re-checked at read time* per
byte-range or the response is personalized. The knob that matters: expiry. 15 minutes
covers email-client prefetch and re-opens; a 24-hour signed URL is a shareable leak with
a long fuse — anyone holding the link *is* authorized until expiry, so treat TTL length
as an authorization decision, not a convenience one.

### Which vendor — and what's actually portable?

The chapter's semantics (Cache-Control, Vary, validators, signed URLs, origin lock) are
HTTP and portable across Cloudflare/CloudFront/Fastly/bunny — choose on the boring axes:
price per TB, PoP coverage where *your* users are, purge speed if you rely on it, and
whether the WAF/bot layer replaces tooling you'd otherwise run. What is *not* portable:
vendor-specific cache rules, edge functions/workers, and dashboard-only configuration —
which is why `infrastructure/cdn/config.md` documents every setting: the config that
exists only in a vendor UI is Stage 7's pet server, relocated to someone else's cloud.

## Trade-offs

| Choice | You gain | You pay |
|---|---|---|
| CDN in front of everything | One door: WAF/TLS/DDoS coverage, policy in headers | Every response's headers are now load-bearing; the no-store default is mandatory |
| CDN for assets only | Small blast radius, minimal header audit | Origin still exposed; two front doors to operate; dynamic spikes unabsorbed |
| Long s-maxage + SWR on pages | Users never wait; origin barely queried; spikes flattened | Updates propagate on a delay you chose; emergency changes need purge |
| Short TTLs everywhere | Freshness with no purge discipline | Most of the offload evaporates; origin stays in the read path |
| Fingerprinted assets, immutable | Zero staleness, zero purges, deploy-safe by construction | Requires build discipline (bundler-managed URLs; no hand-edited assets) |
| Purge-driven updates | Works for honest mutable URLs | Propagation races, rate limits, CDN API coupling; unusable as deploy strategy |
| Signed URLs for private files | Edge-speed private downloads; app instances freed | URL possession = authorization until expiry; TTL is a security dial |
| Proxying private files | Re-auth on every read | App bandwidth/connections consumed per download; no edge help |
| Micro-caching "safe" API GETs | Origin relief on hot public endpoints | One personalization slip = cross-user leak; needs airtight review |

## Common Mistakes

- **`public` (or nothing) on authenticated responses.** The canonical CDN catastrophe:
  a per-user response cached at the edge and served to the next requester of that URL.
  Causes: a blanket "add caching headers" pass, a framework default, or *headerless*
  responses meeting a CDN that caches by default. The no-store default middleware plus
  an explicit opt-in list is the structural fix.
- **Long TTLs on unfingerprinted assets.** `app.js` cached for a week meets a deploy
  that changes it → users hold the old bundle against new HTML and APIs: white screens,
  hydration errors, "clear your cache" support tickets. Fingerprinting makes this
  impossible; `?v=2` by hand recreates it the first time someone forgets.
- **Missing `Vary` on real response inputs.** The endpoint serves JSON or CSV by
  `Accept`, or localized content by `Accept-Language`, cached without `Vary` — first
  requester's variant becomes everyone's. Also its twin: `Vary: Cookie` on a
  session-cookied site, which fragments the cache into per-user entries (hit rate ~0) —
  usually a sign the response shouldn't be edge-cached at all.
- **Cache poisoning via unkeyed inputs.** The response reflects a header (`X-Forwarded-
  Host` in absolute URLs, an origin echoed into CORS) that isn't in the cache key: an
  attacker sends one crafted request, the poisoned response is cached, and the edge
  serves the attacker's payload to everyone. Cacheable responses must be functions of
  their cache key — nothing else.
- **The unlocked origin.** CDN configured, DNS switched, but the origin still answers
  anyone who finds its IP (certificate-transparency logs make that trivial): every WAF
  rule, rate limit, and cached shield is optional for attackers. The origin-lock header
  (or IP allowlist, or mTLS) is part of the rollout, not a hardening afterthought.
- **Believing the dashboard hit rate.** A 95% global hit rate that is actually 99.9% on
  fonts and 8% on the endpoint you added the CDN for. Hit rate is a per-content-class
  metric; measure it per route before declaring victory (and origin request rate is the
  number that pays bills).
- **Testing through the cache.** Staging behaviors verified against an already-warm
  edge, or QA "fixed" by the CDN serving yesterday's build. Test caching itself
  deliberately (curl with cache-status headers, per the exercises) and keep a
  cache-busting path for verifying origin behavior.

## AI Mistakes

### Claude Code: the public header on private data

Asked to "improve API performance with caching," Claude Code adds `Cache-Control` headers
across endpoints in one enthusiastic pass — including `public, max-age=300` on responses
that are per-user: the invoices list, the dashboard summary, `/me`. Nothing fails in dev
(no shared cache runs there) or in tests (each runs isolated). The bug activates only when
the CDN arrives, at which point user A's invoice list becomes the cached response for user
B — the exact incident class this chapter calls catastrophic, introduced by a diff whose
every line looked like a performance win.

**Detect:** `public` or any `s-maxage` on a route that reads auth context (dependency on
the current user, session, or tenant); caching headers added in bulk rather than per
endpoint with a stated rationale. **Fix:** the structural default from this chapter —
middleware forces `private, no-store`, the `cacheable()` helper is the only opt-in, and
review's rule for each call site is one question: "is this response identical for every
user on earth?"

### GPT: deploying by purge

Ask GPT how to handle CDN caching with frequent deploys and the modal answer is an
invalidation step in CI: "after deploying, purge the CDN cache" — sometimes purge-all,
sometimes a path list, presented as the standard practice. It inverts the correct design:
with fingerprinted assets there is nothing to purge (old URLs stay valid, new URLs are
new), while purge-based deploys inherit propagation races (users worldwide hit mixed
old/new for the purge window), vendor rate limits (deploy #12 today gets throttled), and
a hard dependency of every release on the CDN's control-plane API.

**Detect:** purge/invalidation calls in deploy pipelines for content that could be
fingerprinted; "invalidate on deploy" presented as the asset strategy; `?v=` query
versioning suggested alongside it. **Fix:** fingerprinting is the deploy strategy; purge
survives only as the scripted lever for honest mutable URLs (marketing publish) and
incidents. In the pipeline, the correct CDN step is *none*.

### Cursor: negotiating content the cache key can't see

Adding locale support to the public pricing page, Cursor autocompletes the standard
pattern — read `Accept-Language` (or a `currency` cookie), render localized prices —
directly into a route that already carries `public, s-maxage=600`. The completion is
locally correct and the diff doesn't touch the caching line at all, so nothing flags: the
response now varies by an input the cache key doesn't include. The first German visitor
after each TTL expiry sets the page's language for the world; support gets "your site
shows euros" from Texas, intermittently, unreproducibly — the signature of every
unkeyed-variant bug.

**Detect:** request-header or cookie reads (`Accept-Language`, currency, A/B flags,
feature cookies) appearing in handlers/pages whose responses are edge-cacheable; `Vary`
absent from the same diff. **Fix:** the review invariant — *any new input to a cacheable
response must appear in the same diff as either a `Vary` entry, a URL segment
(`/de/pricing` — usually the right answer: it keeps hit rates high and is shareable), or
the removal of cacheability.* Structural help: keep the cacheable-routes list short and
in one place, so "this route is cached" is visible from the code being completed.

## Best Practices

- **Default closed, open per route.** `private, no-store` from middleware; a single
  `cacheable()` opt-in with a greppable call-site list; PR review asks the
  identical-for-everyone question at each new site. This one structure prevents the
  entire leak class.
- **Let the bundler own asset URLs.** Fingerprinting is free from Next.js/Vite — the
  practice is *not defeating it*: no hand-placed files in static dirs, no CDN rules
  that strip query strings or rewrite asset paths, verify the `immutable` header
  survives to production.
- **Choose TTLs from content meaning, write them down.** The content-class table from
  the Mental Model, instantiated for your product, lives in `infrastructure/cdn/
  config.md` with a sentence of rationale per class — the reviewable artifact that
  stops TTLs drifting by copy-paste.
- **Sign short, mint cheap.** Private-file URLs at ~15 minutes; endpoints re-mint
  freely (a link that expired mid-meeting re-fetches in one call). Expiry length is
  authorization duration — treat extensions as security decisions.
- **Lock the origin on day one and test the lock.** The 403-without-secret check, plus
  a monthly probe (curl the origin IP directly) in the same spirit as Chapter 02's
  kill drill. An origin that answers strangers makes the CDN decorative.
- **Monitor per-class hit rate and origin offload.** Dashboards: edge hit rate by
  route class, origin request rate (the before/after number), origin egress bytes,
  and purge API calls (an audit trail — every purge has an author and a reason).
- **Verify cache behavior as part of QA.** A smoke script that curls each content
  class twice and asserts the cache-status header (HIT/MISS/BYPASS as expected) —
  runs in staging against a real CDN zone, catches both over-caching and
  under-caching before users do.

## Anti-Patterns

- **The DNS-flip rollout.** Pointing DNS at a CDN with default settings and no header
  audit — inheriting the vendor's cache-by-default heuristics across an app full of
  headerless authenticated responses. The rollout order is: headers audited → origin
  locked → smoke script green → then DNS.
- **Caching the logged-in app shell "for speed."** Edge-caching the dashboard HTML or
  per-user API responses with tiny TTLs, reasoning that "30 seconds can't hurt." A
  30-second window at production request rates is thousands of cross-served responses.
  Personalized content gets edge *delivery* (TLS termination, routing) — never edge
  *caching*.
- **Hand-rolled cache busting.** `script.js?v=2` bumped by humans: forgotten on the
  critical deploy, incompatible with parallel releases, and defeated by CDN configs
  that ignore query strings. The bundler already solved this; use its output.
- **CDN as a cloak for a slow origin.** A 6-second page hidden behind a long TTL — the
  p99 (every TTL expiry, every cache-busting user) still eats the full 6 seconds, and
  the miss storm after any purge is an outage. Fix the origin (Chapters 01–05); cache
  the fixed thing.
- **Config that lives only in the vendor dashboard.** Cache rules, redirects, and edge
  logic accumulated by clicking — unreviewable, unreproducible, undiffable, and one
  account mishap from gone. Config-as-documentation (or the vendor's Terraform
  provider) is the Stage 7 discipline applied to rented infrastructure.
- **Purge-all as a reflex.** Every content bug answered with a global purge — which
  "works" (it hides unkeyed-variant and poisoning bugs) while inflicting a full miss
  storm on the origin. Purges treat symptoms; the cache key or headers were wrong, and
  the postmortem should say which.

## Decision Tree

```
A response/asset meets the CDN — set its policy:
│
├─ Is the response identical for every user on earth?
│   ├─ NO →
│   │   ├─ Private FILE (PDF, export, upload) that's heavy or hot?
│   │   │   → signed URL (app authorizes, mints short-expiry proof;
│   │   │     edge delivers). Expiry = authorization duration.
│   │   ├─ Needs re-auth per read / personalized body →
│   │   │   private, no-store; app serves it (the default path)
│   │   └─ "But it's only slightly per-user" → still no-store.
│   │       There is no safe shared TTL for per-user data.
│   └─ YES ↓
├─ Does its URL change when its content changes (fingerprinted)?
│   ├─ YES → public, max-age=31536000, immutable. Done forever.
│   └─ NO ↓
├─ Mutable-URL shared content (pages, docs, public JSON):
│   ├─ How stale may the newest visitor's copy be? → s-maxage
│   ├─ May the edge serve stale while refreshing? → + SWR (usually yes)
│   ├─ Does the response vary by ANY header/cookie input?
│   │   ├─ Put it in the URL (/de/pricing) — best hit rate, shareable
│   │   ├─ Or Vary on it — correct, fragments the cache
│   │   └─ Or drop cacheability — when variance is per-user anyway
│   └─ Update mechanism: publish-triggered scripted purge (logged)
└─ Rollout invariants (any content class):
    ├─ Origin locked: only edge traffic reaches the balancer
    ├─ No response leaves the origin without explicit Cache-Control
    └─ Smoke script asserts HIT/MISS/BYPASS per class in staging
```

## Checklist

### Implementation Checklist

- [ ] No-store default middleware active; `cacheable()` is the only opt-in and every
      call site is auth-free and user-independent.
- [ ] Fingerprinted assets ship `public, max-age=31536000, immutable` and the
      fingerprint pipeline is bundler-owned end to end (verified in prod headers, not
      assumed).
- [ ] Shared pages carry class-appropriate `s-maxage` + `stale-while-revalidate` per
      the documented content-class table.
- [ ] Every input a cacheable response varies by is in its URL or its `Vary` header —
      checked per route.
- [ ] Signed-URL issuance: authorization precedes minting; expiry ≤ 15 minutes unless
      justified; signing key in secrets management (Stage 9), rotated on schedule.
- [ ] Origin lock enforced at the balancer (secret header / allowlist / mTLS) and
      covered by a recurring direct-to-origin probe.

### Architecture Checklist

- [ ] Content-class table written for this product: classes, examples, policy,
      rationale — in the repo, not the vendor dashboard.
- [ ] Invalidation strategy is fingerprint-first; purge scoped to mutable URLs and
      incidents, scripted and logged with author + reason.
- [ ] CDN vendor config documented/exported in the repo; portability boundaries
      (edge functions, vendor rules) known and minimized.
- [ ] Per-class hit rate, origin request rate, and origin egress on dashboards;
      the CDN's spend has a number next to the origin capacity it replaced.
- [ ] Failure story decided: CDN outage → DNS fallback? origin capacity for the
      unshielded load? (Usually: accept vendor SLA, document the decision.)

### Code Review Checklist

- [ ] Any diff adding `public`/`s-maxage` answers "identical for every user?" in the
      PR — reviewer verifies against the auth dependencies of the route.
- [ ] Any new request-header/cookie read in a cacheable route arrives with `Vary`, a
      URL segment, or removed cacheability — in the same diff.
- [ ] No reflected request inputs (host headers, origins, query echoes) in cacheable
      response bodies — the poisoning check.
- [ ] Signed-URL TTL changes are treated as authorization changes and reviewed as
      such.
- [ ] No hand-versioned assets (`?v=`) or files bypassing the bundler's fingerprint
      pipeline.

### Deployment Checklist

- [ ] Rollout order held: header audit → origin lock → staging smoke (HIT/MISS/BYPASS
      per class asserted) → DNS cutover — with the smoke script kept as a permanent
      post-deploy check.
- [ ] Deploy pipeline contains no purge step for fingerprinted assets; marketing
      publish triggers its scoped, logged purge.
- [ ] A deploy was verified under cache reality: old HTML + old assets and new HTML +
      new assets both work during the overlap window.
- [ ] Direct-origin probe, per-class hit-rate dashboards, and purge audit log live
      before the traffic does.
- [ ] The month-end load test (Ch 01, extended each chapter) now runs through the
      edge and reports origin offload as a result line.

## Exercises

1. **Audit before you cache.** Against your current app (no CDN yet), curl every major
   route class and record each `Cache-Control` (or its absence). Classify every route
   into the content-class table and produce the gap list: headerless responses,
   per-user routes that would leak under a cache-by-default CDN, assets without
   fingerprints. This list is the rollout's real work estimate.
2. **Reproduce the leak, then make it structurally impossible.** In staging with a
   local caching proxy (nginx `proxy_cache` stands in for the CDN), set
   `public, max-age=60` on an authenticated endpoint. Log in as user A, hit it, then
   as user B — observe A's data served to B. Install the no-store default middleware
   and the `cacheable()` opt-in, re-run, and keep the failing-then-passing pair as a
   regression test for the middleware.
3. **Race the deploy.** With long-TTL *unfingerprinted* assets in the staging cache,
   deploy a change where new HTML requires new JS. Document the breakage (white
   screen/console errors as old JS meets new markup). Switch to the bundler's
   fingerprinted output, repeat the deploy, and verify the overlap window is clean in
   both directions. Write the two-paragraph postmortem — it's the fingerprinting
   argument in your own incident's words.
4. **Serve a private PDF from the edge.** Implement `signed_cdn_url()` against your
   CDN or a local HMAC-verifying proxy: authorized endpoint mints a 15-minute URL,
   edge verifies signature and expiry, expired URLs get 403 and a clean re-mint flow
   in the UI. Load-test the download path and compare app-instance connection
   occupancy against the Chapter 03 proxy-through-app baseline.
5. **Find the unkeyed variant.** Add locale rendering (via `Accept-Language`) to a
   cached staging page *without* `Vary` and demonstrate cross-language pollution with
   two curl profiles. Fix it all three ways — `Vary`, URL segment, uncache — measure
   hit rates for each, and write three sentences on which you'd ship and why. Then
   check your real app for the same class: grep cacheable routes for header/cookie
   reads.

## Further Reading

- RFC 9111 — *HTTP Caching* — the normative source for every directive this chapter
  uses; shorter and more readable than its reputation.
- MDN — "HTTP caching" and the `Cache-Control` reference — the working engineer's
  version of the RFC.
- James Kettle (PortSwigger) — "Practical Web Cache Poisoning" and its sequels — the
  attack literature behind this chapter's cache-key discipline; required reading
  before caching anything that reflects input.
- web.dev — "Love your cache" / caching best practices — the asset-fingerprinting
  strategy as the framework world implements it.
- Your CDN's documentation on: cache keys, signed URLs, and origin protection — the
  three places vendor behavior genuinely differs; read against this chapter's
  semantics.
- Next.js documentation — "Caching" — what the framework already does (immutable
  static assets, ISR) so you configure around it rather than against it.
- Stage 3, Chapter 09 ([File Storage](../stage-03-backend-engineering/09-file-storage-and-email.md))
  and Stage 4, Chapter 07 ([Frontend Performance](../stage-04-frontend-engineering/07-frontend-performance.md))
  — the storage and performance groundwork this chapter extends to the edge.

# Rate Limiting & Abuse Prevention

## Introduction

Every previous chapter in this stage defended against a *vulnerability* — a flaw in the code that an
attacker exploits. This final chapter defends against an attack that needs no vulnerability at all,
just volume: sending a correct, well-formed request so many times that it becomes an attack.
Credential stuffing tries a million stolen password pairs against your login. Account enumeration
probes which emails are registered. A scraper drains your entire database one paginated page at a
time. An expensive endpoint (a PDF render, a report, a search) gets hammered until the server falls
over. None of these exploits a bug. Each abuses a legitimate feature by using it at a scale it was
never meant for — and the only defense is to limit the rate.

Rate limiting is deceptively simple in concept (count requests, reject over a threshold) and full of
judgment in practice: *what* do you count them against (IP? user? API key?), *which* algorithm
(fixed window, sliding window, token bucket — each with different burst behavior), *where* does the
counter live (in-memory fails the moment you run more than one instance), *where* in the stack do
you enforce it (edge, gateway, application), and *how* do you limit abuse without punishing
legitimate users who happen to be behind a shared IP or having a busy day. Get these wrong and you
either have a limiter that doesn't work (resets on restart, bypassed by IP rotation, keyed on a
spoofable header) or one that blocks your real customers.

This chapter covers the abuse classes (brute force, credential stuffing, enumeration, scraping,
resource exhaustion), the rate-limiting mechanics (algorithms, keys, storage, placement), and the
broader abuse-prevention toolkit that rate limiting anchors: progressive backoff, CAPTCHAs, account
lockout done safely, and the response headers that let good clients cooperate. The boundaries: the
*infrastructure* layer of DoS defense — network-level flood protection, the CDN/WAF, load balancing
— is **Stage 7** and **Stage 11 (System Design)**; this chapter is the *application-layer* defense.
The authentication endpoints being protected were built in **Stage 3, Chapter 03**; this chapter
wraps them in abuse limits. And the caching that also absorbs load (Stage 3, Chapter 07) is a
complement referenced here, not re-taught.

## Why It Matters

Volume-based abuse is the attack class most likely to actually hit a production SaaS, because it
requires no skill, no vulnerability, and no target-specific research — the tools are automated and
point-and-shoot.

- **Login is under constant automated attack.** Credential-stuffing bots replay billions of
  username/password pairs leaked from other breaches against every login form on the internet,
  continuously. Without rate limiting and abuse detection, your login is an open oracle for testing
  stolen credentials — and every successful hit is an account takeover you did nothing to prevent.
  This is not a hypothetical; it is the background radiation of running a web app.
- **Enumeration leaks who your users are.** An endpoint that responds differently for a registered
  vs unregistered email (login, password reset, signup) lets an attacker harvest your user list by
  probing — valuable for targeted phishing and for the credential stuffing above. Rate limiting slows
  it; uniform responses (Chapter 01) close it; together they matter.
- **Expensive endpoints are a cheap way to take you down.** Any endpoint that costs the server real
  work — generating a PDF, running a report, a complex search, sending an email — can be turned into
  a denial-of-service by calling it in a loop. The attacker spends one request; you spend seconds of
  CPU or a database-crushing query. Without per-endpoint limits, your most useful features are your
  most exploitable.
- **Scraping drains data and resources.** A competitor or data broker can walk your entire dataset
  through legitimate paginated endpoints, consuming bandwidth and database load and exfiltrating the
  data you sell access to. Rate limits (plus authorization) are what make bulk extraction expensive
  enough to deter.
- **Unmetered actions cost real money.** Endpoints that trigger SMS, email, or third-party API calls
  convert request volume directly into your bill. An abuse loop on a "resend verification SMS" button
  is a financial attack, not just a technical one.
- **The AI dimension shows up in limiters that don't actually work.** Assistants generate rate
  limiters that are in-memory (reset on every restart, and independent per instance behind a load
  balancer, so the real limit is N× what you set), keyed only on IP (bypassed by rotation, or
  blocking an entire office behind one NAT), or keyed on a client-spoofable header (trivially
  defeated). Each *looks* like rate limiting and enforces almost nothing.

## Mental Model

Rate limiting counts requests against a *key* over a *window* using an *algorithm*, backed by
*shared storage*, enforced at the right *layer* — and every one of those five choices has a way to
get it wrong that quietly disables the protection.

```
   THE FIVE CHOICES (get any wrong and the limit is weaker than it looks)

   1. KEY — what do you count against?
        per IP        → bypassed by rotation; blocks whole NATs (offices, mobile carriers)
        per user/account → the right key for authenticated abuse (login: also key on the account tried)
        per API key   → the right key for API clients
        best: LAYERED — e.g. login limited per-IP AND per-account-being-tried
        ✗ never key on a client-controllable header (X-Forwarded-For) unless the edge sets it trusted

   2. ALGORITHM — how do you count?
        fixed window   simple; allows 2x burst at the window edge (100 at 0:59, 100 at 1:00)
        sliding window smooths the edge; a bit more state
        token bucket   allows controlled bursts, refills at a steady rate — good for APIs
        leaky bucket   smooths output to a constant rate

   3. STORAGE — where does the counter live?
        in-memory   ✗ resets on restart; SEPARATE per instance → behind a load balancer the real
                       limit is (instances x your limit). useless for multi-instance.
        shared store (Redis) ✓ one counter all instances share; survives restarts. the correct default.

   4. LAYER — where is it enforced?
        edge / CDN / WAF   absorbs volumetric floods before they reach you (Stage 7 / 11)
        gateway            coarse per-client limits
        application        per-user, per-endpoint, business-aware limits ← this chapter
        (defense in depth: multiple layers)

   5. RESPONSE — how do you reject?
        429 Too Many Requests + Retry-After  → lets good clients back off cooperatively
        progressive: slow down, then challenge (CAPTCHA), then block — not instant hard-block

   THE ABUSE CLASSES THIS DEFENDS
     brute force / credential stuffing (login) · enumeration (login/reset/signup) ·
     scraping (list/search) · resource exhaustion (expensive endpoints) · cost abuse (SMS/email)
```

Three principles carry the chapter:

**Limit against the right key, usually more than one.** The key decides what the limit actually
constrains. IP alone is both too coarse (blocks shared NATs) and too loose (defeated by rotation).
Authenticated abuse is limited per account; login is limited per-IP *and* per-account-being-tried;
API clients per key. Layer keys so no single bypass (rotate IP, or hammer one account from many IPs)
gets through.

**The counter must be shared and durable, or the limit is a fiction.** An in-memory counter resets on
restart and is per-instance — behind any load balancer, the effective limit is multiplied by your
instance count, and a deploy wipes it. Rate limiting requires shared storage (Redis) so all instances
enforce one limit that survives restarts.

**Rate limiting is one tool in an abuse-prevention system; degrade, don't just block.** Pair limits
with uniform responses (anti-enumeration), progressive friction (slow → challenge → block), safe
account lockout, and cooperative headers (`429` + `Retry-After`). The goal is to make abuse expensive
while keeping legitimate use smooth — a hard instant block on a shared IP punishes real users.

A working definition:

> **Rate limiting counts requests against a well-chosen key (often layered: per-IP and per-account)
> over a window, using an algorithm whose burst behavior you understand, backed by shared durable
> storage so it holds across instances and restarts, enforced at the application layer as part of a
> broader abuse-prevention system — progressive friction, uniform anti-enumeration responses, safe
> lockout, and cooperative `429`/`Retry-After` headers — that makes volume abuse expensive without
> punishing legitimate users.**

## Production Example

**Invoicely** has exactly the surfaces volume abuse targets: a login endpoint (credential stuffing),
password-reset and signup (enumeration), the invoice PDF render and reporting endpoints (resource
exhaustion), the paginated invoice list (scraping), and a "resend verification email" action (cost
abuse). This chapter protects each, backed by the Redis it already runs (Stage 3, Chapter 07), and
shows the assistant-default limiter that protects almost nothing.

Login is the priority. It's limited on two keys at once: per source IP (to slow a single attacker)
*and* per account being targeted (to stop a distributed attack that rotates IPs against one victim's
email). The limits are strict — a handful of attempts per minute — and exceeding them triggers
progressive friction: first a short delay, then a CAPTCHA challenge, and only then a temporary block,
so a legitimate user who fat-fingers their password three times isn't hard-locked. Password-reset and
signup return *uniform* responses whether or not the email exists (Chapter 01) and are rate-limited,
so they can't be used to enumerate the user base. The counters live in Redis, so every app instance
shares one limit and a deploy doesn't reset the protection — the failure mode of the in-memory
default.

The expensive endpoints (PDF, reports) get per-user token-bucket limits sized to real usage, so a
user can burst a little but can't loop the render into a denial-of-service; the same limit protects
the cost-bearing "resend email" action. The paginated list endpoints have per-user limits that make
walking the whole dataset slow enough to deter scraping while never affecting normal browsing. Every
rejection is a `429` with a `Retry-After` header so well-behaved clients (and Invoicely's own
frontend) back off cooperatively. And the whole scheme is layered: the CDN/WAF (Stage 7) absorbs
volumetric floods before they reach the app, while these application limits handle the business-aware
abuse the edge can't understand. In this chapter we build these and contrast each with the
assistant-default: the in-memory limiter, the IP-only key, the header-spoofable key.

## Folder Structure

```
api/ (FastAPI — Stage 3)
├── core/
│   ├── rate_limit.py       # the limiter: Redis-backed, algorithm, layered keys, 429+Retry-After
│   ├── abuse.py            # progressive friction (delay -> CAPTCHA -> block); safe account lockout
│   └── client_ip.py        # trusted client-IP resolution (only from the edge, not raw XFF)
├── modules/auth/
│   └── router.py           # login/reset/signup: layered limits + uniform responses (anti-enumeration)
├── modules/invoices/
│   └── router.py           # PDF/report/list: per-user limits sized to real usage
tests/
└── security/
    └── test_rate_limits.py    # limit enforced across instances, per-account key, spoofed header ignored
```

Why this shape:

- **`rate_limit.py` centralizes the limiter** — one Redis-backed implementation with the algorithm,
  key strategy, and `429`/`Retry-After` response in one place, so every endpoint's limit is
  consistent and correct rather than re-implemented per route.
- **`abuse.py` separates the *policy* (progressive friction, lockout)** from the *mechanism*
  (counting), so login can escalate delay→CAPTCHA→block and lock accounts safely without that logic
  smeared across handlers.
- **`client_ip.py`** exists because the rate-limit key is only as trustworthy as the client IP, and
  the client IP is only trustworthy if resolved from a header the *edge* sets — this module encodes
  "trust `X-Forwarded-For` only from our proxy, never raw," closing the spoofable-key hole.
- **The auth and invoice routers** apply the appropriate keys and limits per surface, with auth also
  returning uniform responses so limiting and anti-enumeration work together.
- **`tests/security/test_rate_limits.py`** proves the limit holds across instances (shared store),
  that the per-account key catches IP rotation, and that a spoofed `X-Forwarded-For` doesn't bypass
  it — the verification the in-memory/IP-only/spoofable defaults would fail.

## Implementation

**The Redis-backed limiter (`rate_limit.py`): shared, durable, layered keys.** In-memory is the
failure; a shared store is the whole point.

```python
async def check_rate_limit(key: str, limit: int, window_seconds: int) -> RateLimitResult:
    # one counter in Redis that ALL instances share and that survives restarts
    count = await redis.incr(key)
    if count == 1:
        await redis.expire(key, window_seconds)
    if count > limit:
        ttl = await redis.ttl(key)
        raise RateLimitExceeded(retry_after=ttl)   # -> 429 + Retry-After
    return RateLimitResult(remaining=limit - count)
```

```python
# login: LAYERED keys — per source IP AND per account being tried
async def rate_limit_login(ip: str, email: str):
    await check_rate_limit(f"login:ip:{ip}", limit=10, window_seconds=60)        # slows one attacker
    await check_rate_limit(f"login:acct:{email}", limit=5, window_seconds=300)   # catches IP rotation
```

The two keys close each other's gaps: the IP key slows a single machine, the account key stops a
distributed attack rotating IPs against one victim's email. Neither alone is enough; together they
cover both bypasses.

**Trusted client-IP resolution (`client_ip.py`): the key is only as good as the IP.**

```python
def client_ip(request) -> str:
    # trust X-Forwarded-For ONLY as set by our own edge/proxy — never the raw client value
    xff = request.headers.get("X-Forwarded-For")
    if TRUSTED_PROXY and xff:
        return xff.split(",")[0].strip()   # the edge appends the real client; take the left-most it set
    return request.client.host            # otherwise the direct socket peer — unspoofable
```

If you key rate limits on a header the *client* controls, the client sets a random value per request
and the limit never triggers. The IP is trustworthy only when your infrastructure sets it; this
module encodes that trust boundary.

**Progressive friction and safe lockout (`abuse.py`): degrade, don't hard-block.**

```python
async def on_failed_login(ip: str, email: str):
    failures = await bump_failure_counter(email)
    if failures >= 10:
        raise AccountChallenge("captcha")     # challenge, not permanent lock
    elif failures >= 5:
        await asyncio.sleep(backoff(failures))  # progressive delay slows automation, barely felt by humans
    # NOTE: lockout is TIME-BASED (auto-expires), never permanent — a permanent lock is a
    #       denial-of-service an attacker can trigger against any known email.
```

The escalation — delay, then CAPTCHA, then a *time-limited* lock — slows automated abuse sharply
while a real user who mistypes their password a few times feels almost nothing. Permanent lockout is
avoided precisely because an attacker could weaponize it to lock every user out by name.

**Per-user limits on expensive endpoints (`invoices/router.py`).**

```python
@router.post("/invoices/{id}/pdf")
async def render_pdf(id, user):
    await check_rate_limit(f"pdf:user:{user.id}", limit=20, window_seconds=60)  # burstable, bounded
    ...   # the expensive render, now protected from a denial-of-service loop
```

**The attack tests (`tests/security/test_rate_limits.py`): prove the defaults' failures are fixed.**

```python
async def test_limit_holds_across_instances(redis):
    # two app instances sharing Redis enforce ONE limit — the in-memory default would allow 2x
    for _ in range(10): await instance_a.login(ip="1.1.1.1", email="a@e.com")
    assert (await instance_b.login(ip="1.1.1.1", email="a@e.com")).status_code == 429

async def test_account_key_catches_ip_rotation(client):
    for i in range(6):
        client.login(ip=f"9.9.9.{i}", email="victim@e.com")   # different IP each time
    assert client.login(ip="9.9.9.99", email="victim@e.com").status_code == 429  # per-account key fires

async def test_spoofed_forwarded_header_does_not_bypass(client):
    for i in range(20):
        client.login(headers={"X-Forwarded-For": f"5.5.5.{i}"}, email="a@e.com")  # spoofed
    assert client.login(email="a@e.com").status_code == 429   # ignored; real key still counts
```

These are the deliverable: the limit holds across instances, the account key defeats IP rotation, and
a spoofed header is ignored — exactly the three ways the assistant-default limiter silently fails.

## Engineering Decisions

Five decisions define an abuse-prevention scheme.

### What key(s) do you limit against?

**Options:** (1) per IP; (2) per authenticated user/account; (3) per API key; (4) layered
combinations; (5) a client-supplied identifier.

**Trade-offs:** IP is available pre-authentication (necessary for login) but is both too coarse
(a corporate NAT or mobile carrier shares one IP among thousands) and too loose (attackers rotate
IPs cheaply). Per-user is precise for authenticated abuse but useless before login. Per-API-key fits
programmatic clients. A client-supplied identifier is worthless — the attacker just varies it.
Layering (IP *and* account for login) covers the gaps each has alone.

**Recommendation:** choose the key by what you're defending and layer them. Login: per-IP *and*
per-account-being-tried (catches both single-source and distributed-rotation attacks).
Authenticated endpoints: per-user (plus per-IP as a coarse backstop). APIs: per-key. Never limit on
a client-controllable value. The layered key is what makes the limit hard to bypass.

### Which algorithm?

**Options:** (1) fixed window; (2) sliding window; (3) token bucket; (4) leaky bucket.

**Trade-offs:** fixed window is the simplest (a counter with a TTL) but permits a 2× burst across the
window boundary — 100 requests at 0:59 and 100 at 1:00. Sliding window smooths that at the cost of a
little more state. Token bucket allows a controlled burst then a steady refill — natural for APIs
where occasional bursts are fine. Leaky bucket enforces a constant output rate.

**Recommendation:** fixed or sliding window for simple protective limits (login, reset) where you
just need a ceiling; token bucket for API and expensive-endpoint limits where a small burst is
legitimate but sustained rate must be bounded. Match the algorithm's burst behavior to the endpoint:
strict ceiling for auth, burstable for user-facing APIs. Don't over-engineer — a windowed counter in
Redis covers most needs.

### Where does the counter live?

**Options:** (1) in-memory (per process); (2) a shared store (Redis); (3) at the edge/gateway;
(4) the database.

**Trade-offs:** in-memory is trivial and *broken* for any multi-instance deployment — each instance
counts separately, so the real limit is instances × your limit, and every restart/deploy resets it.
Redis gives one shared, fast, durable counter across all instances — the standard answer. Edge/gateway
limiting is coarse but absorbs volume early. The database works but adds load to the thing you're
protecting.

**Recommendation:** a shared store (Redis) for application rate limits — it's the only option that
enforces one real limit across instances and survives restarts. Reserve in-memory only for a genuine
single-instance service (rare in production). Add edge/gateway limits as a coarse outer layer. The
in-memory limiter is the single most common way a rate limit turns out to be fake.

### Where in the stack is abuse handled?

**Options:** (1) application only; (2) edge/CDN/WAF only; (3) layered (edge + gateway + application).

**Trade-offs:** application-only limits are business-aware (per-user, per-endpoint) but sit behind
everything, so volumetric floods still consume your bandwidth and connection capacity to reach them.
Edge-only limits absorb floods early but can't understand "this user is scraping invoices" — they
lack business context. Layering gets both: the edge sheds volume, the app enforces semantic limits.

**Recommendation:** layer. Volumetric and network-level flooding is shed at the edge/CDN/WAF (Stage
7, Stage 11); business-aware abuse (credential stuffing, scraping, expensive-endpoint loops) is
handled in the application where the context lives. This chapter builds the application layer; it's
one ring of a defense that starts at the network edge.

### How do you respond to abuse — block, or degrade?

**Options:** (1) hard block (deny, or permanent lockout); (2) progressive friction (slow → challenge
→ temporary block); (3) `429` + `Retry-After` for cooperation; (4) shadow/soft limits.

**Trade-offs:** an instant hard block is simple but punishes false positives harshly — a shared NAT
or a user having a bad day gets denied, and permanent account lockout is itself a
denial-of-service an attacker can trigger by name. Progressive friction slows automation while barely
affecting humans. `429`/`Retry-After` lets well-behaved clients (including your own frontend) back
off correctly. Soft limits (log without blocking) help tune thresholds before enforcing.

**Recommendation:** progressive friction as the default posture — delay, then challenge (CAPTCHA),
then a *time-limited* block — with `429` + `Retry-After` on every rejection so good clients cooperate.
Never use permanent account lockout (weaponizable DoS); make lockouts auto-expire. Consider a
soft/report-only phase to calibrate thresholds against real traffic before enforcing, so you don't
block legitimate users on day one.

## Trade-offs

**Rate limiting trades a hard cap on legitimate power-users for protection against abuse.** Any limit
strict enough to stop abuse will occasionally constrain a genuine heavy user or a shared IP. The
mitigation is layered keys (so the limit is precise), generous limits on normal actions with strict
ones only where abuse concentrates (login, expensive endpoints), and progressive friction rather than
hard blocks. The cost is real but manageable; no limit is not an option.

**Shared-store counting trades a Redis dependency for a limit that actually works.** Redis-backed
limiting adds a dependency in the request path and a small latency cost per check. What it buys is the
difference between a real limit and a fake one (in-memory's instances × limit). For any multi-instance
app the dependency is non-negotiable — and you likely already run Redis (Stage 3, Chapter 07).

**Progressive friction trades implementation complexity for not punishing real users.** Escalating
delay → CAPTCHA → temporary lock is more code than a flat block, and CAPTCHAs add user friction. The
payoff is stopping automated abuse while a mistyped password costs a human almost nothing — far better
than the support load and churn of hard-blocking legitimate users. Reserve the friction for where
abuse actually is.

**Stricter thresholds trade more false positives for catching more abuse.** Lower limits catch more
attackers and block more innocents; higher limits do the reverse. There's no universally right number
— it depends on the endpoint and your traffic. The way through is measurement: run limits in
report-only mode, observe real traffic, and set thresholds with data rather than guessing, then
monitor the `429` rate.

## Common Mistakes

**An in-memory limiter behind a load balancer.** Each instance counts separately and restarts reset
it, so the effective limit is instances × your number and a deploy clears it. Fix: a shared store
(Redis) so all instances enforce one durable limit.

**Keying only on IP.** Bypassed by IP rotation and blocks entire shared NATs (offices, carriers).
Fix: layer keys — per-account for authenticated abuse, per-IP *and* per-account for login.

**Keying on a spoofable header.** Rate-limiting on raw `X-Forwarded-For`/`X-Real-IP` the client
controls, so the attacker varies it and never trips the limit. Fix: resolve the client IP only from a
header your edge sets, or use the socket peer.

**No limit on expensive or cost-bearing endpoints.** PDF renders, reports, searches, and SMS/email
triggers left unlimited, so a loop is a denial-of-service or a bill. Fix: per-user limits sized to
real usage on every costly action.

**Permanent account lockout.** Locking an account forever after N failures, which an attacker
weaponizes to lock any user out by email. Fix: time-limited, auto-expiring lockout with progressive
friction.

**Enumerable auth endpoints.** Login/reset/signup responding differently for known vs unknown emails,
leaking the user list. Fix: uniform responses (Chapter 01) plus rate limiting on those endpoints.

## AI Mistakes

Rate limiting is a domain where assistant output *looks* like protection and enforces almost nothing,
because the limiter runs and returns `429` in a single-instance test while failing in every
production condition. Review the limiter's storage, key, and IP-trust — not whether it returns `429`
locally.

### Claude Code: the in-memory limiter that doesn't survive production

Asked to add rate limiting, Claude Code very commonly produces an in-memory limiter — a module-level
dict or counter tracking requests per key in the process's memory. It works perfectly in local
testing and in a single-instance demo, returning `429` on cue. In production it fails two ways at
once: behind a load balancer each instance has its own counter, so the real limit is (instance count
× the configured limit), and every restart or deploy wipes the counters entirely. The protection
looks present in review and is largely absent in production.

**Detect:** rate-limit state in a module-level dict, `defaultdict`, `lru_cache`, or in-process
structure; no Redis/shared store in the limiter; limits that reset when the app restarts; a limiter
whose numbers don't hold when more than one worker/instance runs.

**Fix:** back it with a shared, durable store:

> Rate limiting must use a shared store (Redis) so all instances enforce one limit and it survives
> restarts — never an in-memory dict, which behind a load balancer allows (instances × limit) and
> resets on deploy. Add a test that the limit still holds when two instances share the store.

### GPT: keying on IP only (bypassable and over-blocking at once)

GPT-family models default to a single per-IP key for everything, including login. This fails in both
directions: an attacker rotating through cheap proxies or a botnet trivially bypasses a per-IP login
limit (each IP gets the full allowance), while a shared corporate NAT or mobile carrier IP means many
legitimate users share one bucket and get blocked by each other's activity. For credential stuffing —
which is inherently distributed — an IP-only limit barely helps, and it collaterally blocks real
users behind shared IPs.

**Detect:** the only rate-limit key being the IP; login limited per-IP with no per-account key;
support reports of whole offices being blocked; credential-stuffing attempts succeeding despite an
"IP limit" because each IP stays under it.

**Fix:** layer keys, especially per-account for login:

> Don't key rate limits on IP alone. For login, limit per-IP *and* per-account-being-tried so a
> distributed attack rotating IPs against one email is still caught, and normal users behind a shared
> NAT aren't blocked by each other. For authenticated endpoints, key per user. Add a test that IP
> rotation against one account still trips the limit.

### Cursor: trusting a client-controllable header as the rate-limit key

Completing a limiter that needs the client's IP, Cursor often reads it straight from
`X-Forwarded-For` or `X-Real-IP` and keys the limit on that value — following the common pattern
without checking whether that header is trustworthy. Because those headers are set by the client
unless an edge overwrites them, an attacker simply sends a different `X-Forwarded-For` on every
request and each one gets a fresh bucket. The limiter runs, returns `429` in a test that doesn't spoof
the header, and is bypassed in one line by anyone who does.

**Detect:** the rate-limit key derived from raw `X-Forwarded-For`/`X-Real-IP` with no trusted-proxy
check; client IP taken from a request header rather than the socket peer or an edge-set value; the
limit not tripping when the same client varies the forwarded header.

**Fix:** resolve the IP only from a trusted source:

> Only trust `X-Forwarded-For`/`X-Real-IP` if it's set by our own edge/proxy; otherwise use the
> socket peer address. Never key a rate limit on a header the client can set freely. Add a test that
> varying the forwarded header does not create fresh rate-limit buckets.

## Best Practices

**Limit against layered keys.** Per-account for authenticated abuse; per-IP *and* per-account for
login (catching both single-source and distributed attacks); per-key for APIs. Never a
client-controllable value.

**Back the counter with a shared, durable store.** Redis (or equivalent) so all instances enforce one
limit that survives restarts — never in-memory for a multi-instance app.

**Resolve the client IP only from a trusted source.** The socket peer, or `X-Forwarded-For` only as
set by your edge — never the raw client header.

**Limit every expensive and cost-bearing endpoint.** Per-user limits sized to real usage on PDF/report/
search renders and on SMS/email/third-party-triggering actions — the denial-of-service and cost
surfaces.

**Degrade progressively; never hard-block or permanently lock.** Delay → CAPTCHA → time-limited
block; `429` + `Retry-After` on every rejection; auto-expiring lockouts (permanent lockout is a
weaponizable DoS).

**Pair limits with uniform anti-enumeration responses.** Login/reset/signup respond identically for
known and unknown accounts (Chapter 01) *and* are rate-limited — the two together close enumeration.

**Layer with the edge.** Volumetric floods shed at the CDN/WAF (Stage 7 / 11); business-aware abuse
handled in the application. Neither layer alone is sufficient.

**Calibrate with data and monitor.** Run new limits report-only to set thresholds against real
traffic, then enforce; alert on `429` rates and on abuse patterns (login-failure spikes).

## Anti-Patterns

**The In-Memory Limiter.** Rate state in process memory behind a load balancer. The tell: a
module-level counter/dict; no shared store; limits that reset on deploy and multiply by instance
count.

**The IP-Only Key.** Every limit keyed solely on IP. The tell: no per-account key on login;
credential stuffing succeeding under an "IP limit"; whole offices blocked.

**The Spoofable Key.** Limit keyed on a raw client header. The tell: `X-Forwarded-For` read without a
trusted-proxy check; the limit never tripping when the header varies.

**The Unmetered Expensive Endpoint.** Costly or billable actions with no limit. The tell: PDF/report/
search or SMS/email endpoints with no rate check; a loop that spikes CPU or the bill.

**The Permanent Lock.** Accounts locked forever after N failures. The tell: no expiry on lockout; an
attacker able to lock any user by submitting bad passwords for their email.

**The Enumeration Oracle.** Rate-limited but distinguishable auth responses. The tell: different
status/message/timing for known vs unknown emails; limiting treated as the whole anti-enumeration
defense.

## Decision Tree

"I need to protect an endpoint from volume abuse — how?"

```
What's being abused?
├── LOGIN (brute force / credential stuffing)
│     └─► layered keys: per-IP AND per-account-being-tried, in Redis. strict limits.
│         progressive friction: delay -> CAPTCHA -> TIME-LIMITED lock (never permanent).
│         uniform responses so it's not also an enumeration oracle (Ch 01).
├── PASSWORD RESET / SIGNUP (enumeration)
│     └─► rate-limit + UNIFORM responses (same reply whether the email exists or not).
├── EXPENSIVE endpoint (PDF, report, search) — resource exhaustion
│     └─► per-user token-bucket limit sized to real usage. burstable, bounded.
├── COST-bearing action (SMS, email, 3rd-party call)
│     └─► strict per-user limit — this is a financial control, not just technical.
└── LIST / SEARCH (scraping)
      └─► per-user limit that makes full-dataset walking slow; + authorization (Stage 3 Ch 04).

For ANY of them:
   KEY      → the right key(s), layered; never a client-controllable value.
   STORAGE  → shared + durable (Redis). never in-memory for multi-instance.
   IP       → from the socket peer or an edge-set header only — never raw XFF.
   RESPONSE → 429 + Retry-After; degrade progressively, don't hard-block.
   LAYER    → edge/WAF sheds floods (Stage 7/11); app enforces business-aware limits (here).
```

## Checklist

### Implementation Checklist

- [ ] Rate-limit counters are backed by a shared, durable store (Redis), never in-memory, so limits hold across instances and restarts.
- [ ] Keys are chosen per threat and layered (login: per-IP *and* per-account; authenticated: per-user; APIs: per-key); no key is client-controllable.
- [ ] The client IP is resolved from the socket peer or an edge-set header only, never raw `X-Forwarded-For`.
- [ ] Every expensive and cost-bearing endpoint (renders, reports, search, SMS/email) has a per-user limit sized to real usage.
- [ ] Rejections return `429` with `Retry-After`; abuse is met with progressive friction and time-limited (never permanent) lockout.
- [ ] Auth endpoints combine rate limiting with uniform responses so they can't be used for enumeration.

### Architecture Checklist

- [ ] Rate limiting is centralized (one implementation) and applied consistently across endpoints, not re-invented per route.
- [ ] Abuse *policy* (friction, lockout, thresholds) is separated from the counting *mechanism*.
- [ ] Application limits are layered with edge/WAF protection (Stage 7 / 11), each handling what it's suited for.
- [ ] The abuse-prevention scheme uses the Redis the app already runs (Stage 3, Chapter 07) rather than adding new infrastructure needlessly.
- [ ] Thresholds are set from measured traffic (report-only calibration) rather than guessed.

### Code Review Checklist

- [ ] No rate-limit state lives in process memory for a multi-instance service.
- [ ] No limit is keyed on IP alone where a per-account key is needed, and none is keyed on a raw client header.
- [ ] No expensive or cost-bearing endpoint is merged without a rate limit.
- [ ] No permanent account lockout is introduced; lockouts auto-expire.
- [ ] New auth endpoints have both rate limiting and uniform responses; rejections carry `429`/`Retry-After`.

### Deployment Checklist

- [ ] The Redis (or shared store) backing rate limits is monitored and sized for the request volume; its failure mode is decided (fail-open vs fail-closed) deliberately.
- [ ] Edge/CDN/WAF volumetric protection is in place ahead of the application limits (Stage 7 / 11).
- [ ] `429` rates and login-failure spikes are alerted on, so abuse and mis-tuned limits are both visible.
- [ ] Trusted-proxy configuration is correct in every environment so client-IP resolution isn't spoofable in production.

## Exercises

**1. Prove your limiter is real across instances.** Take an in-memory rate limiter and run two
instances behind a load balancer (or two workers). Show that the effective limit is doubled and that
a restart resets it. Then move the counter to Redis and show one shared limit that survives restart.
The artifact is the two runs and the shared-store fix.

**2. Defeat, then defend, distributed credential stuffing.** Attack a per-IP-only login limit by
rotating IPs against one account and show the attempts sail through. Add a per-account key and show the
same distributed attack is now blocked, while a shared-NAT scenario (many users, one IP) is not
collaterally blocked. The artifact is the two attacks and the layered-key fix.

**3. Bypass a spoofable-header limiter.** Build a limiter keyed on raw `X-Forwarded-For`, then bypass
it by varying the header per request. Fix it with trusted-proxy IP resolution and show the spoof no
longer creates fresh buckets. The artifact is the bypass and the trusted-IP fix.

**4. Add safe progressive friction to login.** Implement delay → CAPTCHA → time-limited lock on
repeated login failures. Show that automated abuse is slowed sharply while a human mistyping their
password three times is barely affected, and that no permanent lock can be triggered against a known
email. The artifact is the escalation logic and the two scenarios (bot vs fat-fingered human).

## Further Reading

- **OWASP — "Blocking Brute Force Attacks" and the Authentication Cheat Sheet
  (cheatsheetseries.owasp.org)** — practical guidance on login abuse, progressive delays, safe lockout,
  and why permanent lockout is itself a risk.
- **OWASP Automated Threats to Web Applications (owasp.org/www-project-automated-threats)** — the
  taxonomy of volume abuse (credential stuffing, scraping, enumeration, carding) this chapter defends,
  with detection and mitigation patterns.
- **"How we built rate limiting" engineering write-ups (Stripe, Cloudflare, GitHub blogs)** — real
  production treatments of token buckets, Redis-backed counters, and layered edge+application limiting
  at scale.
- **Redis documentation — `INCR`/`EXPIRE` patterns and rate limiting (redis.io)** — the exact
  primitives behind the shared-counter limiter, including the windowed and token-bucket patterns.
- **Stage 3, Chapter 03 (Authentication)** and **Chapter 01 (uniform anti-enumeration responses)** —
  the login endpoints this chapter protects and the response-uniformity that pairs with rate limiting;
  network-level DoS defense is Stage 7 and Stage 11.

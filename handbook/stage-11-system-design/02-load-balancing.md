# Load Balancing

## Introduction

A load balancer gives a system one property nothing else provides: the ability to put more
than one machine behind a single address. Everything this stage builds — interchangeable app
instances, zero-downtime deploys, surviving a machine's death without a customer noticing —
rests on that property. Until a load balancer is in the path, "scale out" is a sentence, not
an option.

The component itself is conceptually small: it accepts connections, picks a healthy backend,
forwards traffic, and watches for failure. All of the engineering lives in the details of
those four verbs. *Picks* — by what algorithm, and does the choice stick for a user's next
request? *Healthy* — according to what test, and what happens when the test is wrong in
either direction? *Forwards* — preserving which information about the original client, with
what timeouts, terminating TLS where? *Watches* — and when a backend fails mid-request, is
the request retried, and is it safe to?

Stage 7, Chapter 04 already put Nginx in front of Invoicely as a reverse proxy — one
upstream, TLS, headers, timeouts. This chapter teaches the promotion from proxy to load
balancer: multiple upstreams, balancing algorithms, health handling, retries, connection
draining, and the operational questions (who balances the balancer?) that arrive with the
role. The proxying fundamentals — TLS issuance, header hygiene, buffering — are assumed from
Stage 7 and not re-taught.

## Why It Matters

- **It is the gateway component for horizontal scaling.** Chapter 01's ladder reaches "scale
  out" and stops until a load balancer exists. It is deliberately the first infrastructure
  this stage adds: every later chapter assumes requests can reach N instances.
- **It converts machine failure from outage to non-event.** One VPS is one failure domain —
  Stage 7 accepted that. A balancer with working health checks turns "the instance died"
  into "capacity dropped by one-Nth for ninety seconds." That is most of what "high
  availability" means at this scale.
- **It is what makes zero-downtime deploys real.** Drain one instance, deploy, return it,
  repeat — the rolling deploy that Stage 7's single-instance setup could only approximate
  with a brief 502 window. The balancer is the tool that makes deployment invisible.
- **Configured carelessly, it multiplies failure instead of containing it.** A retry policy
  that resends POSTs duplicates invoices. A health check that always passes routes users to
  a dead instance forever. A too-aggressive health check removes *all* instances at the
  first database blip and turns a slowdown into a total outage. The same component, wrongly
  tuned, is a failure amplifier.
- **Every request now passes through it.** Its timeout interacts with every upstream
  timeout; its logs are where client IPs live or die; its capacity is the new ceiling. A
  component in 100% of request paths deserves first-class engineering attention, and tends
  to get none because "it's just Nginx config."

## Mental Model

A load balancer makes three decisions per request — is the backend set correct, which member
gets this request, and what to do when it fails — plus one standing decision about what it
tells backends about the client.

```
                        ┌──────────────────────────────┐
                        │        LOAD BALANCER         │
        clients ──────► │                              │
        (one address,   │  MEMBERSHIP  who is healthy? │
         one TLS cert)  │  SELECTION   who gets this   │
                        │              request?        │
                        │  FAILURE     retry? where?   │
                        │              is it safe?     │
                        └──────┬───────┬───────┬───────┘
                               │       │       │
                          ┌────▼──┐ ┌──▼───┐ ┌─▼─────┐
                          │ app-1 │ │ app-2│ │ app-3 │
                          │  OK   │ │  OK  │ │ DEAD  │◄─ health check
                          └───────┘ └──────┘ └───────┘   removes it
```

**Layer 4 vs Layer 7.** An L4 balancer forwards TCP connections — it sees bytes, not
requests; it is fast, protocol-ignorant, and cannot route by path, retry an HTTP request, or
inspect anything. An L7 balancer speaks HTTP: it can route `/api` and `/` to different
upstreams, set headers, retry failed requests, and terminate TLS. Application load balancing
is almost always L7 (Nginx, HAProxy in HTTP mode, cloud ALBs); L4 appears underneath —
cloud network LBs, or balancing non-HTTP traffic like PostgreSQL connections.

**Selection algorithms, and how little they usually matter.** Round robin (each in turn)
is the default and is correct when requests are cheap and uniform. Least-connections (send
to the backend with the fewest in-flight requests) is the better default when request cost
varies — a backend stuck on slow requests automatically receives less traffic. Weighted
variants handle heterogeneous machines. Hash-based selection (by client IP or a key) exists
to make the *same* client land on the *same* backend — which is not a performance feature
but a state crutch, and Chapter 03 exists to remove the need for it. The honest summary:
pick least-connections, spend the attention you saved on health checks and retries, which
is where real outages come from.

**Health is a claim the backend makes and the balancer audits.** Two mechanisms: *passive*
health checking observes real traffic (a backend that errors or times out N times is
suspended for M seconds — Nginx's `max_fails`/`fail_timeout`); *active* checking sends
synthetic probes to a health endpoint on a schedule (HAProxy, cloud LBs, Nginx Plus). The
deep design question is what the health endpoint asserts. Too shallow (`return 200`) and it
reports a process that exists, not a service that works — the balancer routes to an
instance whose database connections are gone. Too deep (checks the database, Redis, and the
email provider) and a database blip makes *every* instance report unhealthy simultaneously
— the balancer, obeying, removes them all and converts a degradation into a total outage.
The rule: **a health check should verify what is local to the instance** (process up, not
deadlocked, dependencies *reachable*) — shared-dependency failure is a fact about the
system, not about any instance, and removing instances cannot fix it.

**Failure handling is a contract about duplication.** When a backend dies mid-request, the
balancer can retry on another. For a GET, always safe. For a POST that creates an invoice,
the first backend may have committed before dying — a retry creates it twice. The retry
policy is therefore not a reliability dial but a correctness contract: retry idempotent
methods freely, retry non-idempotent ones only on errors that guarantee the request was
never processed (connection refused — yes; timeout — absolutely not, the work may still be
running). This is Stage 3 Chapter 06's idempotency discipline surfacing one layer down.

**The balancer inherits the client's identity problem.** Backends now see the balancer's IP
on every connection. Client identity survives only if the balancer forwards it
(`X-Forwarded-For`, `X-Real-IP`) *and* backends trust those headers *only* from the
balancer — Stage 9's rate limiting keyed on a client-controllable header is the standing
warning. And the balancer itself is now a single point of failure; at this stage's scale
the honest answers are a managed cloud balancer (the provider runs the redundant pair) or
keepalived/VRRP for self-hosted pairs — plus the recognition that one *well-monitored*
balancer is often an acceptable, explicitly accepted risk for a small system.

## Production Example

Invoicely, mid-migration from Chapter 01's plan. The single VPS is now three: one running
Nginx (promoted to balancer) and two running app instances, with the PDF workers on their
own machines since Chapter 01. The concrete requirements driving the configuration:

- Month-end traffic spikes to ~4× baseline; dashboard requests are 10–50× more expensive
  than CRUD — request cost varies wildly, so selection is least-connections.
- Deploys happen several times a week and must not drop requests: connection draining and
  a rolling restart, orchestrated by the Stage 7 CI/CD pipeline.
- Invoice creation and payment webhooks are non-idempotent; the retry policy must never
  resend them to a second backend on timeout.
- Rate limiting (Stage 9) and audit logs (Stage 3) key on client IP, so the forwarding
  chain has to deliver real IPs, trustably.
- An app instance must be removable — by failure or by deploy — without any user-visible
  error beyond in-flight requests on a crashed instance.

## Folder Structure

The Stage 7 repo layout gains a balancer-specific configuration area:

```
infrastructure/
├── nginx/
│   ├── nginx.conf              # global: worker counts, logging format
│   │                           #   (unchanged from Stage 7)
│   ├── conf.d/
│   │   ├── upstreams.conf      # NEW — the backend pool, health and
│   │   │                       #   keepalive: membership lives in ONE
│   │   │                       #   file so deploy tooling can edit it
│   │   └── invoicely.conf      # server block: TLS, routing, retry
│   │                           #   policy, forwarded headers
│   └── snippets/
│       ├── proxy-headers.conf  # X-Forwarded-* set once, included
│       │                       #   everywhere — divergence here is how
│       │                       #   one route loses client IPs
│       └── tls.conf            # Stage 7 Ch 04, unchanged
├── compose/
│   └── docker-compose.prod.yml # app service no longer publishes a
│                               #   port — only nginx does; instances
│                               #   are reached on the internal network
└── scripts/
    └── drain-instance.sh       # marks a backend down, waits for
                                #   in-flight requests, used by deploy
```

The reasoning: membership (`upstreams.conf`) is isolated because it is the file that
*changes* — deploys mark instances down and up, scaling adds entries — and a file edited by
automation should contain nothing else. Headers live in a snippet because the forwarding
chain must be identical on every route; the day `/api` and `/webhooks` set different
headers is the day one of them starts rate-limiting the balancer instead of clients.

## Implementation

The upstream pool — membership, health, and connection reuse:

```nginx
# conf.d/upstreams.conf
upstream invoicely_app {
    least_conn;

    # Passive health: 3 failures within 30s suspends the backend 30s.
    server 10.0.1.11:8000 max_fails=3 fail_timeout=30s;
    server 10.0.1.12:8000 max_fails=3 fail_timeout=30s;

    # Deploy tooling flips this flag to drain an instance:
    # server 10.0.1.13:8000 down;

    # Reuse connections to backends: without this, every request
    # pays a TCP (and on internal TLS, a handshake) round trip.
    keepalive 32;
}
```

The server block — routing, retries, and the client-identity chain:

```nginx
# conf.d/invoicely.conf
server {
    listen 443 ssl http2;
    server_name app.invoicely.io;
    include snippets/tls.conf;                 # Stage 7 Ch 04

    location / {
        proxy_pass http://invoicely_app;
        include snippets/proxy-headers.conf;

        proxy_http_version 1.1;
        proxy_set_header Connection "";        # required for keepalive

        # RETRY CONTRACT: only errors where the request provably never
        # reached the app. NOT timeout: a timed-out POST may have
        # committed. non_idempotent is deliberately absent.
        proxy_next_upstream error connect_refused;
        proxy_next_upstream_tries 2;

        # Timeout ordering (LB slightly above app's own limits, so the
        # app times out first and returns a clean error):
        proxy_connect_timeout 2s;
        proxy_read_timeout   35s;              # app's hard limit is 30s
    }

    location /healthz/lb {
        # The balancer's own liveness for whatever watches IT.
        return 200;
    }
}
```

```nginx
# snippets/proxy-headers.conf
proxy_set_header Host              $host;
proxy_set_header X-Real-IP         $remote_addr;
proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
```

The app side of the contract — a health endpoint that reports *this instance's* health, and
trust of forwarded headers restricted to the balancer:

```python
# app/api/health.py
from fastapi import APIRouter, Response

from app.core.db import engine

router = APIRouter()

@router.get("/healthz")
async def healthz(response: Response) -> dict[str, str]:
    """Instance-local health: is THIS process able to serve?

    Verifies the process is responsive and its own resources (DB pool
    connectivity) work. Deliberately does NOT fail on shared-dependency
    degradation: if the database is down for everyone, removing this
    instance from the pool fixes nothing and removes capacity.
    """
    try:
        async with engine.connect() as conn:
            await conn.exec_driver_sql("SELECT 1")
    except Exception:
        response.status_code = 503
        return {"status": "unhealthy", "reason": "db_pool"}
    return {"status": "ok"}
```

```python
# app/main.py — client identity survives the balancer, but ONLY from it
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

app.add_middleware(
    ProxyHeadersMiddleware,
    trusted_hosts=["10.0.1.10"],   # the balancer, and nothing else
)
```

Draining an instance for deploy — the piece that makes rolling restarts request-safe:

```bash
# scripts/drain-instance.sh <ip:port>
# 1. mark the backend down in upstreams.conf (sed the 'down' flag in)
# 2. nginx -s reload            -- reload is graceful: existing
#                                  connections finish on old workers
# 3. wait for the instance's active-request gauge to reach zero
#    (the Stage 7 metrics endpoint), timeout 60s
# 4. deploy proceeds on the drained instance; afterwards remove
#    'down', reload again, health check must pass before the next
#    instance drains
```

Two details carry most of the production weight here. The retry directive lists `error` and
`connect_refused` — *not* `timeout` and not `non_idempotent`; this single line is the
difference between "an instance died and nobody noticed" and "an instance died and three
customers were double-charged." And the timeout ordering (balancer 35s > app 30s) ensures
the application, which can return a clean structured error (Stage 3 Ch 05), times out
before the balancer, which can only return a bare 504.

## Engineering Decisions

### Which selection algorithm?

Least-connections, unless measured reason otherwise. Invoicely's request costs span two
orders of magnitude (dashboard aggregation vs. a status PATCH), and round robin will
happily stack three dashboard requests on one instance while another sits idle.
Least-connections self-corrects for cost variance and slow instances. Hash-based selection
(ip_hash, consistent hashing) is reserved for genuine affinity needs — a cache tier where
hashing raises hit rates (Chapter 04) — never for sessions; session affinity is a state
smell that Chapter 03 removes at the source.

### What does the health check assert?

Instance-local health only: the process responds and its own connectivity works. The
balancer's passive checks (max_fails) catch hard failures fast; the app's `/healthz`
endpoint exists for active checkers (the cloud LB, the deploy script's readiness gate) and
for humans. Shared dependencies are deliberately excluded from unhealthiness — a Postgres
outage must read as "all instances up, all requests erroring" (an application incident,
Stage 7 Ch 07's alerts), not "all instances gone" (a routing decision that removed the
entire service). The exception: during *deploy readiness* checks, deeper verification is
fine — you are asking "is this new build sane," a different question from "should this
instance receive traffic."

### What may be retried?

Only requests that provably never reached an application: connection errors and refusals.
Not timeouts — a timed-out request may have committed before the clock ran out. Not 500s —
the request was processed and failed; retrying re-processes it. This is deliberately
stricter than Nginx's defaults, and the strictness is the point: at the balancer layer you
lack the idempotency keys that would make broader retries safe. Clients that need
guaranteed delivery on writes use application-level idempotency keys (Stage 3 Ch 06's
discipline, exposed as an `Idempotency-Key` header) — then retries are safe *end to end*,
not just at one hop.

### Where does TLS terminate?

At the balancer, with plain HTTP on the private network behind it — the standard choice,
and correct for Invoicely: one certificate to manage (Stage 7's ACME setup, unchanged), no
crypto cost per instance, and the balancer can read requests to route them. Re-encrypting
to backends (TLS between balancer and instance) becomes worth its overhead when the
"private" network isn't yours to trust — shared cloud networks under compliance
requirements, or anything crossing a datacenter boundary. Passing TLS *through* (L4 mode,
terminating on instances) sacrifices L7 routing and is justified mainly by end-to-end
encryption mandates.

### Managed cloud balancer or self-hosted Nginx?

Self-hosted Nginx fits Invoicely's Stage 7 posture (VPS, everything self-run) and this
chapter teaches it because the concepts transfer everywhere. The honest arithmetic changes
as you grow: a managed balancer (ALB, Cloud Load Balancing) is itself redundant, scales
without your attention, integrates health checks and cert rotation, and costs more per
month while costing far less per incident. The balancer-as-SPOF problem — who balances the
balancer? — is exactly the operational burden a managed offering deletes. Rule of thumb:
self-host while one balancer's failure is an acceptable, monitored, quickly-recoverable
risk; go managed when the SLA (or the on-call rotation's sanity) says otherwise.

## Trade-offs

| Choice | You gain | You pay |
|---|---|---|
| Least-connections vs round robin | Self-corrects for expensive requests and slow instances | Slightly less predictable distribution; marginal bookkeeping |
| Shallow (local-only) health checks | Shared-dep failure can't remove the whole pool | A truly broken instance with working locals lingers until passive checks catch it |
| Deep health checks | Instances with broken dependencies leave the pool fast | One shared blip removes every instance: degradation becomes outage |
| Strict retry policy (never on timeout) | No duplicated writes, ever, at this layer | Some recoverable failures surface to clients as errors |
| Loose retry policy | Fewer client-visible errors | Duplicate POSTs; double-charged customers; the worst bug class to debug |
| TLS termination at the balancer | One cert, cheap instances, L7 routing | Plaintext on the internal network — acceptable only if that network is yours |
| Sticky sessions (ip_hash) | Stateful apps "work" behind a balancer | Uneven load (NAT), broken failover, and the state problem is hidden, not solved |
| Self-hosted Nginx | Full control, no per-request cost, portable knowledge | The balancer is now your SPOF to engineer and page on |
| Managed cloud LB | Provider owns redundancy, scaling, certs | Cost, provider coupling, less control over exact behavior |

## Common Mistakes

- **The health check that tests nothing.** `location /health { return 200; }` on the app —
  the process can be deadlocked, the pool exhausted, and the balancer still routes to it.
  Symmetrically: the health check that tests *everything* and removes the whole pool when
  the database sneezes. Local-only, meaningful, fast.
- **Forgetting the forwarded-IP chain — or trusting it from anyone.** Backends log the
  balancer's IP; rate limiting throttles the balancer itself (one "client" making
  everyone's requests); audit trails go blind. Or the opposite failure: the app trusts
  `X-Forwarded-For` from any source, and Stage 9's spoofable-header rate-limit bypass
  reappears one layer up.
- **Timeout inversion.** Balancer read-timeout shorter than the app's own limit: the
  balancer gives up at 10s, returns 504, and (with careless retry config) *resends* the
  request — while the original is still running. Now the work happens twice and the client
  saw an error. Order the timeouts: app strictest, balancer above it.
- **Missing keepalive to upstreams.** Every request opens a fresh TCP connection to a
  backend; under load, the balancer exhausts ephemeral ports and latency grows for
  nothing. `keepalive` in the upstream block plus the HTTP/1.1 + empty `Connection` header
  pair — the three lines everyone forgets one of.
- **Draining by killing.** Deploying by restarting instances without draining: every
  in-flight request on that instance dies. The graceful path — mark down, reload, wait for
  zero in-flight, then touch — is scripting, not architecture, and it is the difference
  between "deploys are invisible" and "we deploy at night."
- **The unmonitored balancer.** Every request flows through it, and it has no dashboards,
  no alerts, and one person who understands its config. When it saturates — connection
  limits, worker counts, file descriptors — the entire system is down and the app metrics
  all say "healthy, no traffic."

## AI Mistakes

### Claude Code: the balancer that retries your writes

Asked to "make the load balancer resilient," Claude Code reaches for maximal retry
coverage — `proxy_next_upstream error timeout http_500 http_502 http_503 non_idempotent`
— because in the training data, more retry conditions look like more resilience. The
`timeout` and `non_idempotent` entries are the trap: a timed-out invoice-creation POST gets
replayed on a second backend while the first may have committed, and the system now
duplicates writes *under exactly the conditions* (slow database, dying instance) where
failures cluster. The config reads as robustness; it is a duplication engine that only runs
during incidents.

**Detect:** `non_idempotent` anywhere; `timeout` in a retry list on routes that accept
writes; retry configuration added without a statement of which methods are safe.
**Fix:** require the retry directive to be justified method-by-method in the PR; the
default is `error connect_refused` only, and anything broader must point to the
application-level idempotency keys that make it safe.

### GPT: the health check that always says yes

Asked for a health endpoint, GPT's modal answer is the static 200 — sometimes literally
`return {"status": "ok"}` with no checks — because most tutorial health checks exist to
demo the route, not to gate routing. Behind a balancer this is worse than no endpoint: it
actively asserts health for an instance whose event loop may be blocked or whose DB pool is
gone, and the balancer keeps sending customers to it. The failure is invisible in every
demo (the instance *is* healthy) and appears only during the incident it was meant to
handle.

**Detect:** a health endpoint with no I/O in it; "healthy" responses that cannot be false;
no distinction anywhere between liveness (process up) and readiness (fit for traffic).
**Fix:** specify the semantics in the prompt — "instance-local readiness: verify the
process and its own DB connectivity, exclude shared-dependency status" — and test the
endpoint by breaking the instance and confirming it says so.

### Cursor: `ip_hash` as a bug fix

A user reports being logged out randomly since the second instance launched. Cursor,
completing in the Nginx config with the error report in context, adds `ip_hash;` — and the
bug disappears. What actually happened: sessions live in process memory (the Chapter 03
audit hasn't run yet), and pinning each IP to one instance hides the statefulness instead
of surfacing it. The costs arrive on a delay: corporate-NAT customers all hash to one
overloaded instance; the next instance failure logs out everyone pinned to it; the deploy
drain now *cannot* move users without logging them out — and the config that caused it
looks like an innocuous one-line fix from months ago.

**Detect:** any affinity mechanism (`ip_hash`, cookie stickiness) appearing in a diff that
fixes a session/login bug; affinity present with no written justification.
**Fix:** treat session-affinity additions as a signal that state lives on instances —
reject the config fix, file the Chapter 03 work (externalize sessions to Redis), and allow
stickiness only as an explicitly temporary, dated bridge.

## Best Practices

- **Make the balancer boring and observable.** Export its metrics (connections, per-backend
  request counts and failures, retry counts, 5xx rates) into the Stage 7 monitoring stack;
  alert on backend-pool shrinkage and on retry-rate spikes — retries are incidents
  announcing themselves early.
- **One snippet for forwarded headers, included everywhere.** The client-identity chain
  must be uniform across routes; divergence is silent and surfaces as a rate-limiting or
  audit bug months later.
- **Keep the retry policy strict at the balancer, and put real retry safety in the app.**
  `Idempotency-Key` on write endpoints (Stage 3 Ch 06) makes retries safe end-to-end —
  including client retries the balancer never sees. The balancer's job is only to never
  *create* duplicates.
- **Script the drain; wire it into CI/CD.** The rolling deploy from Stage 7 Chapter 05
  gains the drain → deploy → verify-healthy → undrain sequence per instance. If draining is
  manual, it will be skipped, and deploys will quietly drop requests.
- **Test failure, not just function.** Kill an instance under synthetic load and watch:
  did errors stay bounded to in-flight requests? Did the pool eject it within
  `fail_timeout`? Did anything retry a write? This ten-minute drill validates more of the
  config than any review.
- **Order timeouts from the inside out.** Application < balancer < client-facing
  infrastructure. The innermost layer has the most context for a clean error; every outer
  layer should give it the chance.
- **Decide the balancer's own failure story explicitly.** Managed LB, keepalived pair, or
  "one instance, monitored, with a documented 15-minute recovery" — any is defensible at
  the right scale; the indefensible version is not having decided.

## Anti-Patterns

- **DNS round robin as the load balancer.** Two A records and hope. No health checks (dead
  instances keep receiving their share until TTL), no draining, no retry, caches ignoring
  TTLs. DNS distributes *traffic*; it cannot manage *membership*. Fine in front of real
  balancers; a failure amplifier in place of one.
- **Sticky sessions as architecture.** Affinity chosen so stateful instances "work,"
  permanently. Every property this stage is buying — interchangeable instances, invisible
  deploys, failure as non-event — is quietly forfeited. Stickiness is a dated bridge or a
  smell, never a foundation.
- **The balancer as application layer.** Rewriting request bodies, implementing auth
  logic, accumulating hundreds of location blocks of business routing in Nginx config —
  untested, unversioned-in-practice, owned by nobody. Route and protect at the edge;
  decide in the application, where logic has tests (Stage 8) and reviews.
- **Health-check theater.** Checks exist, dashboards are green, and no one has ever
  verified the balancer actually ejects a broken instance. Untested failure handling is
  hope with YAML syntax. The kill-an-instance drill exists for this.
- **The retry cascade.** Client retries × balancer retries × application retries = one
  slow database turning every request into nine. Retries multiply across layers; budget
  them in one place (ideally the client, with backoff, against idempotent endpoints) and
  keep every other layer strict.

## Decision Tree

```
Adding/operating a load balancer — the decisions in order:
│
├─ Do you need one at all?
│   ├─ One instance meets Ch 01's measured load AND its failure is
│   │  an accepted risk → NO. Stage 7's reverse proxy is enough.
│   └─ Scaling out, zero-downtime deploys, or surviving instance
│      failure required → YES ↓
├─ Managed or self-hosted?
│   ├─ Team already on a cloud with a managed LB, SLA demands
│   │  balancer redundancy → managed (it deletes the SPOF problem)
│   └─ VPS posture, cost-sensitive, single-balancer risk accepted
│      and monitored → self-hosted Nginx/HAProxy ↓
├─ L4 or L7?
│   ├─ HTTP application → L7 (routing, retries, headers)
│   └─ Raw TCP (DB connections, MQTT...) → L4, different rules
├─ Selection: request costs roughly uniform?
│   ├─ YES → round robin is fine
│   └─ NO (mixed cheap/expensive) → least_conn
│   └─ Tempted by ip_hash for sessions? → STOP: that's state on
│      instances. Externalize it (Ch 03/04); affinity only as a
│      dated temporary bridge.
├─ Health checks:
│   ├─ Endpoint asserts instance-LOCAL readiness (process + own
│   │  connectivity), never shared-dependency status
│   └─ Passive ejection tuned (max_fails/fail_timeout) and TESTED
│      by killing an instance under load
├─ Retries:
│   ├─ Idempotent traffic only, or provably-unsent errors
│   │  (error, connect_refused). Never timeout for writes.
│   └─ Need retry safety on writes → Idempotency-Key in the app,
│      not looser balancer config
└─ TLS: terminate at the balancer (default) → re-encrypt or
   pass through only under compliance/untrusted-network mandates
```

## Checklist

### Implementation Checklist

- [ ] Upstream pool uses least-connections (or documents why not) with passive health
      parameters (`max_fails`, `fail_timeout`) set deliberately.
- [ ] Keepalive to upstreams enabled: `keepalive` in the pool, `proxy_http_version 1.1`,
      empty `Connection` header.
- [ ] Retry policy is `error connect_refused` (or stricter); `timeout` and
      `non_idempotent` absent unless justified in writing against app-level idempotency.
- [ ] Forwarded-header snippet (`Host`, `X-Real-IP`, `X-Forwarded-For`, `-Proto`) included
      on every proxied location; app trusts it only from the balancer's address.
- [ ] Timeouts ordered: application limit < balancer `proxy_read_timeout`.
- [ ] App health endpoint verifies instance-local readiness with real I/O; excludes
      shared-dependency status; returns 503 with a reason when unhealthy.
- [ ] Drain script exists and is wired into the deploy pipeline (down → reload → zero
      in-flight → deploy → healthy → undrain).

### Architecture Checklist

- [ ] The balancer's own failure story is decided and written down (managed / keepalived
      pair / accepted monitored SPOF with recovery runbook).
- [ ] TLS termination point chosen deliberately; internal plaintext justified by network
      trust or replaced by re-encryption.
- [ ] No session affinity — or it is documented as a temporary bridge with an expiry and a
      linked task to externalize the state.
- [ ] Balancer capacity (worker connections, file descriptors) is known and sits above the
      Ch 01 load model's peak with headroom.
- [ ] Retry behavior budgeted across layers: client, balancer, application — multiplication
      checked.

### Code Review Checklist

- [ ] Any change to retry directives names the write endpoints it affects and their
      idempotency story.
- [ ] Any new affinity mechanism (ip_hash, sticky cookies) is rejected or dated-and-tasked.
- [ ] Health endpoint changes preserve instance-local semantics — no shared dependencies
      added to the unhealthy path.
- [ ] New routes include the shared proxy-headers snippet, not hand-copied headers.
- [ ] Rate limiting and audit logging still key on the *forwarded* client IP, trusted only
      from the balancer (Stage 9 Ch 07's check, one layer up).

### Deployment Checklist

- [ ] Rolling deploy drains each instance before touching it and verifies health before
      undraining; the whole sequence aborts (not continues) on a failed health check.
- [ ] The kill-an-instance drill has been run under load: ejection time, error blast
      radius, and retry counts observed and acceptable.
- [ ] Balancer metrics (per-backend errors, retries, pool size, connection counts) are on
      a dashboard with alerts on pool shrinkage and retry spikes.
- [ ] Config is version-controlled and deployed through the pipeline (Stage 7 Ch 05) —
      no live edits on the balancer box (the "pet server" anti-pattern, Stage 7 Ch 06).
- [ ] Balancer host recovery is documented and timed: from dead to serving, using only
      the runbook.

## Exercises

1. **Promote the proxy.** Take the Stage 7 single-upstream Nginx config and convert it to
   this chapter's shape: two app instances (docker-compose can run both on one machine),
   least-connections, passive health, keepalive, strict retries, shared header snippet.
   Verify with logs that both instances receive traffic and that client IPs appear in app
   logs, not the balancer's.
2. **Run the failure drill.** Under a Locust load of mixed GETs and POSTs (exercise 2 of
   Chapter 01), `docker kill` one instance. Measure: how many requests errored, how long
   until the pool ejected it, and — the critical count — how many POSTs executed twice.
   Then loosen the retry policy to include `timeout non_idempotent`, repeat, and count
   duplicated POSTs again. Keep the numbers; they end the "more retries = more reliable"
   argument permanently.
3. **Break the health check both ways.** First give the app a static always-200 health
   endpoint, exhaust its DB pool (hold connections open in a script), and observe the
   balancer routing to a broken instance. Then make the health check verify the shared
   database and stop PostgreSQL: watch every instance leave the pool at once. Write the
   instance-local version that behaves correctly in both experiments.
4. **Make the deploy invisible.** Script the drain sequence and wire it into the Stage 7
   pipeline: for each instance — mark down, reload, wait for zero in-flight, deploy,
   health-gate, undrain. Run it during a sustained load test; success is zero failed
   requests across three consecutive deploys.
5. **Design the balancer's failure story.** For your setup, write the one-page decision:
   managed LB vs keepalived pair vs accepted SPOF. Include the measured recovery time for
   the SPOF option (actually rebuild the balancer from the repo on a fresh host, timed)
   and the monthly cost of each alternative. Decide, and record it as an ADR.

## Further Reading

- Nginx documentation — `ngx_http_upstream_module` (load balancing methods, health
  parameters, keepalive) and `ngx_http_proxy_module` (`proxy_next_upstream` semantics —
  read the fine print this chapter is built on).
- HAProxy documentation — "the other" canonical balancer; its active health checks,
  `agent-check`, and observability are the reference point for what managed LBs do.
- AWS — Application Load Balancer documentation, especially health-check configuration
  and connection draining ("deregistration delay") — the managed mirror of this chapter.
- Google — *Site Reliability Engineering*, Chapter 20, "Load Balancing in the
  Datacenter" — selection algorithms and subsetting at scale.
- Eisenbud et al. — "Maglev: A Fast and Reliable Software Network Load Balancer"
  (NSDI 2016) — how Google builds the L4 layer under everything; consistent hashing in
  production.
- RFC 9110 (HTTP Semantics) — §9.2.2, method idempotency — the normative basis for every
  retry decision in this chapter.
- Stage 7, Chapter 04 ([Nginx, domains and TLS](../stage-07-devops/04-nginx-reverse-proxy-domains-and-tls.md))
  — the proxying, TLS, and header fundamentals this chapter builds on.

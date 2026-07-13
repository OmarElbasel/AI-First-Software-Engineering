# Monitoring & Logging

## Introduction

A deployed system you can't see inside is a system you operate by superstition. When Invoicely is
slow, or throwing errors, or quietly failing to send payment receipts, the difference between a
five-minute fix and a two-hour outage is whether you can *observe* what's happening — read the
logs that explain the error, see the metric that shows the latency spike, and get *alerted* before
a customer emails you. This is the final chapter of the stage because it's what makes everything
before it operable: the container is running (Chapter 02), but is it *healthy*? The deploy
succeeded (Chapter 06), but did error rates spike after it? Observability — logging, metrics, and
alerting — is how you answer those questions with data instead of guesses, and how you find out
about problems from your dashboard rather than from your users.

The single most important idea: **observability is the ability to answer "what is the system doing
and why" from the outside, and it rests on three pillars — logs (what happened, in detail),
metrics (how much/how fast, over time), and alerts (tell me when something's wrong) — each of
which must be deliberately engineered, not hoped for.** Logs you can't search, metrics you don't
collect, and alerts that either never fire or fire constantly are the default, and all three are
useless. The engineering is in the details: *structured* logs (JSON, correlated by request) not
`print` statements; the *right* metrics (the four golden signals) not a wall of noise; and alerts
on *symptoms users feel* (not every twitch) that are *actionable*. Get this right and production
is legible; get it wrong and every incident is archaeology.

The judgment this chapter teaches is **instrument for the questions you'll ask at 2 a.m., and
alert on symptoms, not noise.** The temptation is to log everything (unsearchable) or nothing
(blind), to graph every metric (dashboard soup) or none (flying blind), and to alert on every
anomaly (alert fatigue → ignored alerts) or nothing (found out by customers). Production-grade
observability is specific: structured, correlated, appropriately-leveled logs shipped somewhere
searchable; the golden-signal metrics (latency, traffic, errors, saturation) plus a few
business-critical ones; and a small set of actionable alerts on user-facing symptoms with sane
thresholds. This chapter instruments Invoicely — building on the health checks (Chapters 02–04),
the container logs (Chapter 03), and the deploy pipeline (Chapters 05–06) — so the running system
is one you can see, debug, and be warned about.

## Why It Matters

Observability decides whether you *operate* production or merely *hope* it's fine:

- **You can't debug what you can't see.** When an error happens in production, the log line is
  often the only record of *why* — the input, the stack, the state. No logging, or unstructured
  logging you can't search, means the post-mortem is "we're not sure what happened, it stopped
  recurring." Structured, searchable logs turn an incident into a query.
- **Problems you learn about from customers are already failures.** The goal of monitoring is to
  know about degradation *before* users do — the latency creeping up, the error rate ticking,
  the disk filling (Chapter 01), the queue backing up. Finding out from a support ticket means
  the detection system is the customer, which is slow, incomplete, and reputation-damaging.
- **"It's slow" is unactionable without metrics.** A complaint about performance is a guess until
  you can see *which* endpoint, *how* slow, *since when*, and *correlated with what* (a deploy? a
  traffic spike? a slow query — Stage 6?). Metrics over time turn vague reports into located,
  measurable problems.
- **Bad alerting is worse than none.** Alerts that fire constantly (every blip, every transient)
  train the team to ignore them — so the one real alert is muted with the noise (the boy who
  cried wolf, automated). Alerts that never fire give false confidence. Alerting on *actionable
  user-facing symptoms* is a skill that determines whether on-call works or burns out.
- **Deploys need verification, and observability is it.** Chapter 05/06's pipeline can health-
  check and roll back — but only because there's a signal to check. Post-deploy error rates and
  latency are how you know a release is good, and how automated rollback knows to fire. Without
  observability, "did that deploy break anything?" is answered by waiting for complaints.

Get it right — structured correlated logs you can search, golden-signal and business metrics on a
dashboard, and a lean set of actionable alerts — and production is legible: you debug from data,
detect problems before users, and verify deploys automatically. Get it wrong and you operate
blind, learn of outages from customers, and drown real signals in noise.

The AI dimension: observability is a place assistants generate the *appearance* of it without the
substance. They add `print()`/`logging.info` calls that are unstructured and unsearchable, log
secrets and PII into your logs (a compliance breach — Stage 9), expose a `/metrics` endpoint with
no thought about *which* metrics matter, and write alerts that fire on every minor fluctuation.
The code "has logging" and "has monitoring," and none of it answers a real operational question or
survives contact with production volume.

## Mental Model

Observability is three deliberately-engineered pillars answering "what is the system doing, and
why?":

```
   THE THREE PILLARS (each useless if done by default)

   LOGS  — WHAT happened, in detail (discrete events)
     ✗ print("error!")                    → unsearchable, no context, lost in stdout
     ✓ structured JSON, one event/line, with a correlation/request id + level:
         {"ts":..., "level":"error", "request_id":"a1b2", "route":"/api/invoices",
          "user_id":123, "err":"payment_declined", "latency_ms":840}
       → ship to a searchable store (Loki/ELK/cloud). query: "all errors for request a1b2".
       LEVELS: debug < info < warn < error < critical   (log at the right level; don't log secrets/PII)

   METRICS — HOW MUCH / HOW FAST, aggregated over TIME (numbers)
     THE FOUR GOLDEN SIGNALS (start here, not with 200 metrics):
        LATENCY     how long requests take   (p50/p95/p99 — tail matters, not the average)
        TRAFFIC     how much demand          (requests/sec)
        ERRORS      rate of failures         (5xx/sec, % of requests)
        SATURATION  how full the resources   (CPU, memory, disk, connections, queue depth)
     + a few BUSINESS metrics (invoices sent, payments succeeded) — the ones that mean revenue.
       exposed at /metrics (Prometheus) → scraped → graphed (Grafana) → queried over time.

   ALERTS — TELL ME when something's wrong (metrics/logs → notification)
     alert on SYMPTOMS USERS FEEL, not causes/noise:
        ✓ "error rate > 2% for 5 min"   ✓ "p95 latency > 1s for 10 min"   ✓ "disk > 85%"
        ✗ "CPU hit 90% for 3 seconds"   ✗ one 500   ✗ every transient blip
     every alert must be ACTIONABLE (a human can DO something) and ROUTED (to on-call).
       too many → fatigue → ignored (the real one gets muted). too few → users are your monitoring.

   LOGS vs METRICS vs TRACES
     logs   = the detailed story of one event      (debug the specific failure)
     metrics= the aggregate trend over time         (spot the problem, see the shape)
     traces = one request's path across services    (find WHERE the latency is — grows in Stage 11)
       you use metrics/alerts to KNOW there's a problem, logs/traces to find out WHY.

   HEALTH CHECKS (the simplest signal — Ch 02/04/06)
     liveness  = "is the process up?"      readiness = "can it serve traffic (deps ready)?"
       feed load balancer, orchestrator, deploy verification, and uptime monitoring.
```

Four principles carry the chapter:

**Log structured, correlated events — not `print`.** A log line is a queryable event: JSON, a
consistent schema, a request/correlation ID that ties every line of one request together, and an
appropriate level. Shipped to a searchable store, logs answer "why did *this* fail." Unstructured
`print`s scattered in stdout answer nothing at production volume.

**Measure the golden signals first, then what makes money.** Latency (with tail percentiles),
traffic, errors, and saturation catch nearly every operational problem; a handful of business
metrics catch the ones that matter to the product. Start there — not with a hundred vanity graphs
you'll never look at.

**Alert on actionable, user-facing symptoms.** An alert is a promise that a human should act. Fire
on symptoms users feel (elevated errors, slow responses, exhausted resources), with thresholds and
durations that avoid noise, routed to whoever's on call. Every alert that isn't actionable trains
people to ignore all of them.

**Use metrics to know, logs to explain.** Metrics and alerts tell you *that* something's wrong and
show its shape over time; logs (and, at scale, traces) tell you *why*. Instrument both — a
dashboard with no logs leaves you seeing the spike but not its cause; logs with no metrics leave
you blind until you go looking.

## Production Example

**Invoicely's** observability builds directly on the deployed stack (Chapters 03–06). The
requirement that drives it: **the team finds out about problems from the dashboard and alerts, not
from customers, and any error can be traced from an alert to the exact log line that explains it.**

Every service logs structured JSON to stdout (the Twelve-Factor way — the container runtime and
Chapter 06's stack collect it), with a `request_id` middleware in FastAPI stamping every log line
of a request with the same ID, appropriate levels, and a strict rule that secrets and PII never
enter a log (Stage 9). Those logs ship to a searchable store (Loki, or a hosted equivalent), so
"show me every error for request `a1b2`" or "all `payment_declined` events in the last hour" is a
query. The backend exposes `/metrics` (Prometheus format) with the four golden signals — request
latency histograms (p50/p95/p99), request and error rates per route, and saturation (CPU, memory,
DB pool usage) — plus business metrics: invoices created, emails sent, payments succeeded/failed.
Prometheus scrapes them; Grafana dashboards show the shape over time, annotated with deploy markers
(so a post-deploy regression is obvious). A lean alert set — error rate > 2% for 5 minutes, p95
latency > 1s for 10 minutes, disk > 85%, payment-failure rate elevated, and the health check down —
routes to on-call (Slack + PagerDuty). The health/readiness endpoints (Chapters 02/04) feed the
load balancer, the deploy verification (Chapter 06), and an external uptime monitor. When a deploy
regresses latency, the dashboard shows it, the alert fires, and the pipeline's rollback (Chapter 05)
triggers — observability closing the loop on the whole stage.

## Folder Structure

Observability spans application instrumentation code and the monitoring stack config, all in the
repo:

```
invoicely/
├── backend/app/
│   ├── observability/
│   │   ├── logging.py          structured JSON logger config + request_id middleware
│   │   ├── metrics.py          Prometheus metrics (golden signals + business counters)
│   │   └── health.py           liveness + readiness endpoints (deps checked in readiness)
│   └── main.py                 wires in the middleware, /metrics, /health, /ready
├── monitoring/
│   ├── prometheus.yml          what to scrape (the app's /metrics) and how often
│   ├── alerts.yml              the LEAN, actionable alert rules (symptoms + thresholds)
│   ├── loki-config.yml         log aggregation config (the searchable log store)
│   └── grafana/
│       └── dashboards/         dashboards as code (golden signals, business, per-deploy)
├── docker-compose.monitoring.yml   the monitoring stack as services (Prometheus, Grafana, Loki)
└── ...
```

Why this split:

- **Instrumentation lives *in* the app, as first-class code.** `logging.py`, `metrics.py`, and
  `health.py` are application code (reviewed, tested), not afterthoughts — because *what* to log and
  measure is an engineering decision tied to the domain, and the `request_id` correlation must be
  wired into the request lifecycle.
- **The monitoring stack is config-as-code in `monitoring/`.** Prometheus scrape config, alert
  rules, log config, and Grafana dashboards are version-controlled (Chapter 01's config-as-code) —
  so what you monitor and alert on is reviewed and reproducible, not clicked together in a UI and
  lost.
- **`alerts.yml` is deliberately lean, and that's the point.** The alert rules file being *short*
  is a feature: a small set of actionable, symptom-based alerts. A sprawling alerts file is the
  alert-fatigue anti-pattern made visible in the diff.
- **The monitoring stack is a separate Compose file.** It composes onto the app stack (Chapter 03)
  but is defined separately so it can run alongside (or, for a hosted monitoring service, be
  replaced) without entangling the app's own definition.

## Implementation

Structured logging with request correlation — the foundation that makes logs queryable:

```python
# backend/app/observability/logging.py
import logging, json, sys, contextvars

request_id_ctx: contextvars.ContextVar[str] = contextvars.ContextVar("request_id", default="-")

class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": self.formatTime(record),
            "level": record.levelname.lower(),
            "logger": record.name,
            "request_id": request_id_ctx.get(),   # ties every line of one request together
            "msg": record.getMessage(),
        }
        if record.exc_info:                        # structured stack trace on errors
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload)                  # one JSON event per line → searchable

def configure_logging() -> None:
    handler = logging.StreamHandler(sys.stdout)     # stdout: the container collects it (12-factor)
    handler.setFormatter(JsonFormatter())
    logging.basicConfig(level=logging.INFO, handlers=[handler])
```

```python
# backend/app/main.py — stamp every request with a correlation id (and NEVER log secrets/PII)
import uuid
from fastapi import FastAPI, Request
from app.observability.logging import configure_logging, request_id_ctx

configure_logging()
app = FastAPI()

@app.middleware("http")
async def add_request_id(request: Request, call_next):
    request_id_ctx.set(request.headers.get("X-Request-ID") or uuid.uuid4().hex[:8])
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id_ctx.get()   # surface it to the client + Nginx logs
    return response
```

The golden-signal metrics, exposed for Prometheus:

```python
# backend/app/observability/metrics.py
from prometheus_client import Counter, Histogram, make_asgi_app

# LATENCY (with buckets → p50/p95/p99), TRAFFIC + ERRORS (labelled by route/status), business.
REQUEST_LATENCY = Histogram("http_request_duration_seconds", "Request latency",
                            ["method", "route"], buckets=(.05, .1, .25, .5, 1, 2.5, 5))
REQUESTS = Counter("http_requests_total", "Requests", ["method", "route", "status"])
PAYMENTS = Counter("payments_total", "Payment attempts", ["result"])   # business: succeeded/failed

metrics_app = make_asgi_app()   # mount at /metrics; Prometheus scrapes it (Chapter 03 network)
# (SATURATION — CPU/memory/disk/DB-pool — comes from node/postgres exporters + the app's pool gauge.)
```

Health and readiness — distinct, and both needed:

```python
# backend/app/observability/health.py
from fastapi import APIRouter
from sqlalchemy import text
router = APIRouter()

@router.get("/health")          # LIVENESS: is the process alive? cheap, no deps. (LB/orchestrator restart signal)
async def health(): return {"status": "ok"}

@router.get("/ready")           # READINESS: can it SERVE? checks deps. (don't send traffic if not ready)
async def ready(db=...):
    await db.execute(text("SELECT 1"))     # DB reachable? (Redis, etc. too)
    return {"status": "ready"}
```

The lean, actionable alert rules — symptoms users feel, with durations that kill noise:

```yaml
# monitoring/alerts.yml — SHORT on purpose. Every rule is actionable and user-facing.
groups:
  - name: invoicely
    rules:
      - alert: HighErrorRate                     # users are seeing failures
        expr: sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > 0.02
        for: 5m                                  # sustained, not a blip → no noise
        labels: { severity: page }
        annotations: { summary: "5xx error rate > 2% for 5m" }

      - alert: HighLatencyP95                    # the app is slow for real users (tail, not average)
        expr: histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le)) > 1
        for: 10m
        labels: { severity: page }

      - alert: DiskAlmostFull                    # Chapter 01's silent outage, caught early
        expr: (1 - node_filesystem_avail_bytes / node_filesystem_size_bytes) > 0.85
        for: 15m
        labels: { severity: warn }

      - alert: PaymentFailureSpike               # a BUSINESS symptom — revenue is affected
        expr: rate(payments_total{result="failed"}[10m]) > rate(payments_total{result="succeeded"}[10m])
        for: 10m
        labels: { severity: page }
```

Three details that most separate real observability from its appearance:

- **The `request_id` is the thread that makes logs debuggable.** Without correlation, a production
  error is one line with no context; with it, "give me every log line for request `a1b2`" reconstructs
  the whole failing request across middleware, handler, and DB calls. Propagating it (from the client
  header, into logs, back in the response, and into Nginx's logs — Chapter 04) is what turns logging
  into *tracing-lite* before you need full tracing (Stage 11).
- **Latency is a histogram, and you watch p95/p99 — not the average.** Averages hide the tail: an
  endpoint averaging 120 ms can have a p99 of 4 seconds that's making 1% of users miserable.
  Bucketed histograms let you query percentiles; alerting and dashboards use p95/p99 because that's
  what users at the tail actually feel.
- **`for:` durations are the anti-noise mechanism.** `HighErrorRate ... for: 5m` means the condition
  must hold for five minutes before paging — so a single 500 or a three-second transient doesn't wake
  anyone. Tuning `for:` and thresholds is how you get alerts that fire on *real* problems and stay
  quiet otherwise; it's the difference between alerts people trust and alerts people mute.

## Engineering Decisions

**Log structured JSON to stdout, correlated by request ID.** One JSON event per line, a consistent
schema, a propagated `request_id`, appropriate levels — emitted to stdout for the runtime to collect.
*Rationale:* structured logs are queryable at production volume; correlation reconstructs a single
request's story; stdout is the Twelve-Factor boundary that lets the platform (Chapter 03/06) handle
shipping. `print`/unstructured logs don't survive real traffic.

**Never log secrets or PII.** Passwords, tokens, full card numbers, and personal data are excluded
from logs by design (redaction/allowlisting). *Rationale:* logs are widely readable and long-retained;
a secret or PII in a log is a compliance breach and a leak vector (Stage 9). This is a hard rule, not a
guideline — and a common AI failure.

**Instrument the four golden signals first.** Latency (as histograms → percentiles), traffic, errors,
and saturation before anything else, plus a few business metrics. *Rationale:* the golden signals catch
the overwhelming majority of operational problems with a handful of metrics; starting with a hundred
graphs produces dashboard soup nobody reads. Measure what tells you the system's health, then what
tells you the product's health.

**Alert on user-facing symptoms, with durations, and keep the set lean.** Elevated error rate, high
p95 latency, resource saturation, and business-critical failures — each with a `for:` duration and a
sane threshold, routed to on-call. *Rationale:* alerts are a promise to act; noisy alerting trains the
team to ignore them (and mute the real one), while symptom-based alerts with anti-noise durations fire
when users are actually affected. Fewer, better alerts beat comprehensive noise.

**Separate liveness and readiness health checks.** `/health` (is the process up?) and `/ready` (are
dependencies ready to serve?) as distinct endpoints. *Rationale:* they answer different operational
questions — liveness drives restarts, readiness drives traffic routing and deploy verification
(Chapters 02/04/06). Conflating them means either restarting a process that's just waiting on a
dependency, or routing traffic to one that can't serve.

**Keep monitoring config as version-controlled code.** Prometheus scrape config, alert rules, and
Grafana dashboards live in the repo. *Rationale:* what you monitor and alert on is an engineering
decision that should be reviewed, diffed, and reproducible — not clicked together in a UI and lost when
the instance is rebuilt (Chapter 01's config-as-code, applied to observability).

## Trade-offs

**Self-hosted stack (Prometheus/Grafana/Loki) vs a hosted service (Datadog, Grafana Cloud, etc.).**
Self-hosting is cheap in dollars, fully in your control, and no data leaves your infrastructure — at
the cost of running and scaling the monitoring stack yourself (it's more infrastructure to operate,
and monitoring that's down during an incident is a special kind of bad). A hosted service is
turnkey, scales for you, and is independent of your infra (so it's up when your box is down) — for a
per-host/per-metric bill that grows fast. *Self-host for cost and control on a single VPS; move to
hosted when the operational burden of running your own outweighs the bill,* or when you specifically
want monitoring independent of the infra it watches. The concepts transfer either way.

**Log everything vs log deliberately (verbosity vs cost/signal).** Verbose logging (debug on
everything) captures maximum detail but explodes storage cost and buries the signal in noise; sparse
logging is cheap but leaves gaps when you need detail. *Log at appropriate levels (info for the flow,
debug behind a flag, warn/error for problems), retain by importance, and sample high-volume paths* —
the goal is enough detail to debug without paying to store noise. The `request_id` lets you keep logs
lean and still reconstruct a specific request.

**Metrics vs logs vs traces (and how much to invest now).** Metrics are cheap, aggregate, and perfect
for *knowing* there's a problem and its shape; logs are detailed and perfect for *why* a specific event
failed; distributed traces show *where* latency goes across services and are invaluable in a
multi-service system — but add real instrumentation overhead. *On a single-service/single-VPS system,
metrics + correlated logs cover almost everything;* invest in full distributed tracing when you have
multiple services and "which hop is slow?" becomes a real question (Stage 11). Don't build a tracing
system for a monolith.

**Sensitive alerting vs alert fatigue.** Tighter thresholds and shorter durations catch problems
sooner but fire more (risking fatigue); looser ones are quiet but slower to warn. *Bias toward fewer,
higher-signal alerts and tune from real incidents* — start with the obvious user-facing symptoms, and
add or tighten an alert only when a real incident slipped through. An alert that has never once
corresponded to a real problem should be deleted, not kept "just in case."

## Common Mistakes

**Unstructured `print`/`logging.info` as "logging."** Plain-text lines with no schema, level, or
correlation, dumped to stdout — unsearchable and contextless at production volume. *Fix:* structured
JSON, consistent schema, `request_id`, appropriate levels, shipped to a searchable store.

**Logging secrets or PII.** Tokens, passwords, card numbers, or personal data written into logs — a
compliance breach and a leak. *Fix:* redact/allowlist; make "no secrets/PII in logs" a hard,
reviewed rule (Stage 9).

**No correlation ID.** Logs can't be tied to a single request, so debugging an error means grepping
timestamps and guessing which lines belong together. *Fix:* a `request_id` stamped on every log line of
a request and propagated end-to-end.

**Averaging latency instead of percentiles.** Watching mean response time, which hides a terrible p99 —
so the tail-latency problem affecting real users is invisible. *Fix:* latency as histograms; alert and
dashboard on p95/p99.

**Metric soup (or no metrics).** Either a hundred vanity graphs nobody reads, or no metrics at all so
"it's slow" is unmeasurable. *Fix:* the four golden signals plus a few business metrics — start focused.

**Alert fatigue (or no alerts).** Alerts firing on every transient blip (so all alerts get ignored), or
none at all (so customers are the monitoring). *Fix:* a lean set of actionable, symptom-based alerts
with `for:` durations and sane thresholds, routed to on-call.

**Conflating liveness and readiness (or having neither).** One `/health` that checks dependencies (so a
slow dependency triggers restarts) or none (so the LB/deploy can't tell if the app can serve). *Fix:*
distinct `/health` (liveness) and `/ready` (readiness) endpoints.

## AI Mistakes

Observability is a place assistants produce the *look* of it — logging calls, a `/metrics` endpoint,
some alerts — without the substance that answers a real operational question. Review generated
instrumentation against "does this help me debug/detect at 2 a.m.," not "is there logging."

### Claude Code: unstructured logging with no correlation

Asked to "add logging," Claude Code typically scatters `logging.info(f"...")`/`print` calls with
plain-text messages, no consistent schema, and no request correlation — it produces log *output*, so it
looks like logging, but it's unsearchable and contextless once there's real traffic.

**Detect:** `print()`/f-string `logging.info` with free-text messages; no JSON/structured formatter; no
`request_id`/correlation; no log levels used meaningfully; logs that can't be queried by field.

**Fix:** require structured, correlated logging:

> Make logging structured and queryable: JSON, one event per line, a consistent schema, meaningful
> levels, and a `request_id` correlation ID stamped on every log line of a request and propagated
> end-to-end. Emit to stdout for the runtime to collect. I need to be able to query "all logs for
> request X" and "all errors on route Y."

### GPT: logging secrets/PII and a metrics endpoint with no chosen metrics

GPT-family models often log entire request/response bodies or user objects (sweeping secrets and PII
into logs) and, asked for monitoring, expose `/metrics` with whatever a library auto-instruments — no
deliberate choice of the golden signals or business metrics, so there's a `/metrics` endpoint that
doesn't answer operational questions.

**Detect:** logging full request bodies / user objects / headers (tokens, PII); no redaction; a
`/metrics` mount with no explicit latency/error/traffic/saturation instrumentation; no business
metrics; percentiles unavailable (no histograms).

**Fix:** require redaction and deliberate metrics:

> Never log secrets or PII — no full request/response bodies, tokens, or personal data; redact by
> design. For metrics, deliberately instrument the four golden signals — latency as a *histogram*
> (so I get p95/p99), traffic, error rate, and saturation — plus a few business metrics (payments,
> invoices). A `/metrics` endpoint that doesn't expose these doesn't help.

### Cursor: noisy, unactionable alerts

Editing monitoring config inline, Cursor tends to generate alerts that fire on causes and transients —
"CPU > 80%", "any 500", "memory > 70%" — with no `for:` duration, because the local edit adds
"an alert" without the judgment about what's actionable, producing exactly the alert fatigue that gets
all alerts ignored.

**Detect:** alerts on raw resource thresholds with no duration; alerting on single events (one 500);
no `for:` clauses; many alerts on causes rather than user-facing symptoms; nothing about routing/
severity.

**Fix:** require lean, actionable, symptom-based alerts:

> Alert on symptoms users feel, not causes or noise: elevated *error rate*, high *p95 latency*,
> resource *saturation* (disk/near-OOM), and business failures — each with a `for:` duration so
> transients don't page, a sane threshold, and routing to on-call with a severity. Keep the set small;
> every alert must be something a human can act on. Drop alerts that don't correspond to real user
> impact.

## Best Practices

**Structured, correlated, appropriately-leveled logs to a searchable store.** JSON, one event per
line, a propagated `request_id`, real levels, no secrets/PII — shipped somewhere you can query. Logs
answer *why*.

**Golden signals first, plus what makes money.** Latency (histograms → p95/p99), traffic, errors,
saturation, and a few business metrics. Dashboards annotated with deploy markers so regressions are
obvious. Metrics answer *that* and *what shape*.

**Lean, actionable, symptom-based alerts.** A small set on user-facing symptoms, with `for:`
durations and sane thresholds, routed to on-call by severity. Tune from real incidents; delete alerts
that never correspond to real problems.

**Separate liveness and readiness, and feed them everywhere.** `/health` and `/ready` driving
restarts, traffic routing, deploy verification (Chapter 06), and external uptime monitoring.

**Keep observability config as version-controlled code.** Scrape config, alert rules, and dashboards
in the repo — reviewed, diffed, reproducible. Instrumentation is first-class application code.

**Close the loop with deploys.** Post-deploy error/latency signals verify releases and trigger the
pipeline's automatic rollback (Chapters 05–06). Observability is what makes safe, verifiable deploys
possible.

## Anti-Patterns

**The `print` Debugger.** "Logging" that's scattered plain-text `print`s — unsearchable, contextless,
useless at volume. The tell: no structured formatter, no `request_id`, grepping stdout to debug prod.

**The Leaky Log.** Secrets and PII written into logs — a compliance breach waiting to be discovered. The
tell: full request bodies/user objects/tokens in log output; "we found API keys in our logs."

**The Average Trap.** Latency watched as a mean, hiding a brutal tail. The tell: dashboards showing
"avg response time," no percentiles, users complaining about slowness the graph doesn't show.

**The Dashboard Soup / The Blind Spot.** Either a hundred graphs nobody reads or no metrics at all —
both leave you unable to answer "what's wrong." The tell: a Grafana wall no one looks at, or "is it
slow? no idea, we don't measure it."

**The Alert Storm.** Alerts firing constantly on transients and causes, so the team mutes them and
misses the real one. The tell: a channel of ignored alerts, no `for:` durations, "oh that alert always
fires, ignore it."

**The Silent System.** No alerts, so problems are discovered via customer complaints. The tell:
incidents that start with a support ticket, not a page; "how long was it down? since the last deploy,
apparently."

## Decision Tree

"I'm instrumenting a service (or reviewing its observability) — what must be true?"

```
LOGS (can I debug a specific failure?)
  Structured (JSON, schema, levels), not print/plain text?     no → make it structured.
  A request_id correlating every line of one request, propagated? no → add correlation.
  Shipped to a searchable store?                                no → ship it (stdout → aggregator).
  Guaranteed NO secrets/PII in logs?                            no → redact. hard rule.

METRICS (can I see what the system is doing over time?)
  The four golden signals instrumented — LATENCY (histogram→p95/p99), TRAFFIC, ERRORS, SATURATION?
     no → add them first. averages hide the tail — use percentiles.
  A few BUSINESS metrics (the ones tied to revenue)?           no → add them.
  Exposed + scraped + graphed, annotated with deploys?         no → wire the stack.

ALERTS (will I know before customers do — without drowning in noise?)
  Alerts on user-facing SYMPTOMS (error rate, p95 latency, saturation, business failures)?
     no → rewrite from causes/noise to symptoms.
  Each has a `for:` duration + sane threshold + routing/severity? no → add them (kills fatigue).
  Is the set LEAN and every alert ACTIONABLE?                     no → cut the noise; delete never-fired alerts.

HEALTH (can the LB/deploy/uptime monitor tell state?)
  Distinct /health (liveness) and /ready (readiness, checks deps)? no → separate them.
  Fed to LB routing + deploy verification (Ch 06) + uptime monitor? no → wire them.

CLOSE THE LOOP
  Do post-deploy signals verify releases + trigger rollback (Ch 05/06)?  no → connect them.
  all yes → production is legible. any no → you're operating partly blind.
```

## Checklist

### Implementation Checklist

- [ ] Logs are **structured JSON** to stdout, with a consistent schema and meaningful levels.
- [ ] A **`request_id`** correlates every log line of a request and is propagated end-to-end.
- [ ] **No secrets or PII** are ever logged (redaction/allowlisting in place).
- [ ] The **four golden signals** are instrumented — latency as **histograms** (p95/p99), traffic,
      errors, saturation — plus a few **business metrics**.
- [ ] Metrics are exposed (`/metrics`), scraped, and graphed; dashboards are annotated with deploys.
- [ ] Distinct **`/health`** (liveness) and **`/ready`** (readiness, checking dependencies) endpoints.
- [ ] Alerts fire on **user-facing symptoms** with `for:` durations, sane thresholds, and routing.

### Architecture Checklist

- [ ] Logs ship to a **searchable, retained** store (self-hosted or managed), not just container stdout.
- [ ] Monitoring config (scrape, alerts, dashboards) is **version-controlled code**, reproducible.
- [ ] The alert set is **lean** — every alert is actionable and routed by severity to on-call.
- [ ] Observability **closes the deploy loop** — post-deploy signals verify releases and drive rollback
      (Chapters 05–06).
- [ ] The metrics-vs-logs-vs-traces investment matches the topology (traces deferred to Stage 11's
      multi-service world).

### Code Review Checklist

- [ ] No unstructured `print`/plain-text logging; no missing correlation ID (watch AI-generated
      instrumentation).
- [ ] No secrets/PII in logs (no full request/response bodies, tokens, user objects).
- [ ] No latency averaged instead of percentiled; no metric soup and no missing golden signals.
- [ ] No noisy/cause-based alerts without `for:` durations; no unactionable alerts.
- [ ] Liveness and readiness are distinct and correct.

### Deployment Checklist

- [ ] The monitoring stack (or hosted equivalent) is running and scraping before go-live.
- [ ] Alerts route to a real on-call destination and have been test-fired.
- [ ] An external **uptime monitor** hits the health endpoint independent of the infra it watches.
- [ ] Post-deploy dashboards/alerts and the pipeline's rollback trigger are verified together (Ch 05–06).

## Exercises

**1. Make logs debuggable.** Add structured JSON logging with a `request_id` middleware to Invoicely's
backend, then trace a deliberately-failing request end-to-end by querying every log line for its ID —
demonstrating what you *couldn't* do with the original `print`-style logs. Verify no secrets/PII appear.
The artifact is the before/after log samples and the correlated query result.

**2. Instrument and alert on the golden signals.** Expose a `/metrics` endpoint with latency histograms,
request/error rates, and saturation; build a Grafana dashboard showing p95/p99; and write a
`HighErrorRate` alert with a `for:` duration. Then generate load with an injected error rate and prove
the dashboard shows the spike and the alert fires (and that a brief transient does *not* fire). The
artifact is the dashboard, the alert rule, and the fire/no-fire demonstration.

**3. Catch a bad deploy automatically.** Wire post-deploy latency/error signals to Chapter 06's deploy
verification so that deploying an intentionally-slow build trips the health/latency check and triggers
the pipeline's rollback (Chapter 05) — closing the observability loop. The artifact is the deploy log
showing detection and automatic rollback, with the dashboard corroborating the regression.

## Further Reading

- **Google SRE Book — "Monitoring Distributed Systems" (the Four Golden Signals) and "Practical
  Alerting"** (sre.google/books) — the authoritative source for the golden signals and symptom-based,
  actionable alerting that this chapter is built on.
- **"Observability Engineering" by Majors, Fong-Jones & Miranda** (O'Reilly) — the modern treatment of
  logs, metrics, traces, and high-cardinality observability; the depth behind this chapter's pillars.
- **Prometheus & Grafana documentation** (prometheus.io/docs, grafana.com/docs) — the authoritative
  reference for exposing metrics, histogram/percentile queries (`histogram_quantile`), and alert rules
  used here; Loki's docs for log aggregation.
- **The Twelve-Factor App — "Logs"** (12factor.net) — the principle of treating logs as event streams to
  stdout and letting the platform handle routing, which this chapter implements.
- **Stage 9 — Security** and **Stage 11 — System Design** — the next steps: Stage 9 hardens the "no
  secrets/PII in logs" rule and secure log handling; Stage 11 adds distributed tracing and observability
  across multiple services once you outgrow a single box.
</content>

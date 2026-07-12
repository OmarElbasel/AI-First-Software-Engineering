# Logging & Observability

## Introduction

Observability is the ability to understand what a system is doing — and why —
from the outputs it produces, without attaching a debugger to production. This
chapter is about building that in: structured logs for individual events, metrics
for aggregate trends and alerting, and traces for following a single request across
the boundaries it crosses. Together they answer the question every backend
eventually faces at 2 AM: *what is actually happening in there?*

This is the operational realization of a promise made back in Stage 1, Chapter 08:
maintainability includes being able to understand a system's behavior in production.
It also completes threads from this stage — the correlation ID from error handling
(Chapter 05), the observability of background jobs (Chapter 06), and the implicit
flow of events (Stage 2, Chapter 07) — because all of them depend on being able to
follow what happened after the fact. Instrumentation is how a system stops being a
black box.

The scope is *application-level instrumentation*: how your code emits logs, metrics,
and traces, and what belongs in each. The infrastructure that collects, stores,
dashboards, and alerts on this telemetry — the monitoring platform, the log
aggregator, the dashboards — is **Stage 7 (DevOps)**, which this chapter references
but does not build. The through-line here is that observability is designed in from
the start, not bolted on during the first incident — because the incident is exactly
when it's too late to add it.

## Why It Matters

A system you cannot observe is a system you cannot operate. When something breaks —
and it will — the difference between a five-minute fix and a five-hour outage is
whether you can see what happened. A customer reports "my invoice didn't send." With
observability, you search by the invoice ID or the request's correlation ID, follow
the trace from the API call through the background job to the email provider, and find
the failed provider call in seconds. Without it, you're guessing — reading code,
adding print statements to production, and hoping to reproduce.

Three failure modes make observability the difference between operable and not:

- **Blindness.** Code with no logging, no metrics, and no tracing gives you nothing
  to look at when it misbehaves — you learn about problems from angry customers, not
  your own systems, and you diagnose by speculation. Observability built in means the
  system tells you what's wrong before (and better than) your users do.
- **Noise that hides signal.** The opposite failure: unstructured logs you can't
  query, everything logged at one level so the important line is buried in millions of
  trivial ones, and alerts on everything so no alert means anything. Observability you
  can't actually use is nearly as bad as none.
- **Untraceable flow.** In a system with background jobs (Chapter 06), events (Stage
  2, Chapter 07), and possibly multiple services (Stage 2, Chapter 04), a single
  user action fans out across process boundaries with no call stack connecting them.
  Without a correlation ID propagated across every boundary, you cannot reconstruct
  what one request actually did.

And a fourth, security-critical one: **logging the wrong things.** Logs are read by
many people and often shipped to third-party services; a log line containing a
password, token, or customer PII is a data leak and a compliance violation that lives
forever in log storage.

The AI dimension: assistants omit observability from new code entirely (it's not
needed to make the feature "work"), log unstructured contextless strings when they do
log, break correlation across the very async boundaries they create, and — dangerously
— log entire request bodies and user objects including secrets and PII. Observability
is built-in-by-design, which is precisely the kind of cross-cutting concern generation
skips.

## Mental Model

Observability has three pillars, each answering a different question, and none
substituting for another:

```
   THREE PILLARS — different questions, different tools

   LOGS     "what exactly happened in THIS event?"    per-event, detailed, queryable
            structured (JSON) · a correlation id · context · NO secrets/PII
            → debugging a specific request/failure

   METRICS  "what's the TREND / is it healthy NOW?"    aggregate, cheap, numeric
            counters, gauges, histograms · the golden signals:
            RATE (traffic) · ERRORS · DURATION (latency) · SATURATION (resources)
            → dashboards + ALERTING on user-facing symptoms

   TRACES   "where did this request GO across boundaries?"  one request, many spans
            spans across API → job → service → external call, tied by a trace id
            → following flow through services (Ch 04) / jobs (Ch 06) / events (Ch 07)

   THE THREAD THROUGH ALL THREE: a correlation / trace id, propagated across
   EVERY boundary (request → job → event → downstream), so one action is one story.
```

Four principles make instrumentation useful:

**Logs are structured and carry context.** A log line is a queryable event with
fields — timestamp, level, a correlation ID, the account/operation, the outcome — not
an interpolated string. Structured logs can be filtered, grouped, and searched ("show
all ERROR logs for request X" / "all logs for account 42 in the last hour");
string-interpolated logs can only be `grep`ped and guessed at.

**Never log secrets or PII.** Passwords, tokens, API keys, full card numbers, and
personal data must never reach the logs — logs are widely readable, long-lived, and
often sent to third parties. Log identifiers, not sensitive values; redact or exclude
anything sensitive by default. A leaked secret in a log is a breach that persists in
storage indefinitely.

**Use the right pillar for the question.** Logs for per-event detail (debugging a
specific failure), metrics for aggregate trends and alerting (is the error rate up?),
traces for following one request across boundaries. Conflating them — grepping logs to
compute a rate, or alerting on individual log lines — is expensive and unreliable;
each pillar exists because the others can't do its job well.

**Propagate a correlation ID across every boundary.** The one identifier that ties a
request's logs, metrics context, and trace spans together must flow from the incoming
request into every background job, event, and downstream call it spawns (Chapters 05,
06; Stage 2, Chapters 04, 07). Without it, an async system's flow is unreconstructable;
with it, one user action is one searchable story.

A working definition:

> **Observability is understanding a running system from its outputs: structured logs
> for individual events, metrics for trends and alerting, and traces for cross-boundary
> flow — tied together by a correlation ID propagated everywhere, and never containing
> secrets or PII. It is designed in, not added during the first incident.**

## Production Example

**Invoicely's** "send invoice" flow (Chapter 06) crosses three boundaries: an API
request marks the invoice sent and enqueues a job; a worker renders the PDF and calls
the email provider; the provider succeeds or fails. When a customer says "my invoice
never arrived," support needs to follow that exact flow — and that is precisely the
kind of async, cross-process path that is impossible to reconstruct without
instrumentation.

We will build the app-level observability for it: structured JSON logging with a
correlation ID on every line, a request-logging middleware, redaction so the customer's
data and any secrets never hit the logs, the golden-signal metrics for the invoices
endpoints, error capture for unexpected exceptions (Chapter 05), and — the payoff — the
correlation ID propagated from the request into the background job so the entire "send
invoice" story is one searchable trace. The debugging scenario ("did invoice 8842
send?") is the concrete test: with this in place it's a one-query answer, and without it
it's an afternoon of guessing.

## Folder Structure

```
core/
├── logging.py            # structured JSON logging config + correlation-id injection
├── request_id.py         # correlation-id middleware (from Ch 05), now feeding logs
├── metrics.py            # golden-signal metrics (rate/errors/duration) + registry
├── observability.py      # request-logging middleware + error capture wiring
└── tracing.py            # OpenTelemetry setup (spans across boundaries)
modules/invoicing/
└── tasks.py              # background job carries the correlation id (Ch 06)
```

Why this shape:

- **`core/logging.py`** configures structured JSON logging once, so every log line
  across the app is queryable and carries the correlation ID automatically.
- **`core/metrics.py`** defines the golden-signal metrics in one place, so endpoints
  and jobs emit consistent, aggregatable measurements rather than ad-hoc counters.
- **`core/tracing.py`** wires OpenTelemetry so spans connect across the API, the
  worker, and downstream calls — the cross-boundary pillar.
- **`tasks.py`** shows the correlation ID crossing into the worker, so the async part
  of the flow stays part of the same story.

## Implementation

**Structured logging with an automatic correlation ID (`core/logging.py`).** JSON
logs, and every line carries the current request's correlation ID via a context var —
so you never have to remember to pass it.

```python
import logging
from contextvars import ContextVar
from pythonjsonlogger import jsonlogger

correlation_id: ContextVar[str] = ContextVar("correlation_id", default="-")


class ContextFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.correlation_id = correlation_id.get()   # attach to EVERY log line
        return True


def configure_logging() -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(jsonlogger.JsonFormatter(
        "%(asctime)s %(levelname)s %(name)s %(correlation_id)s %(message)s"
    ))
    handler.addFilter(ContextFilter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)
```

**Request logging + redaction (`core/observability.py`).** One structured log per
request with the fields you actually query on — method, path, status, duration — and
*never* the request body, auth header, or any secret.

```python
import time, logging
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger("app.request")
_REDACT = {"authorization", "cookie", "x-api-key", "password", "token"}


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        start = time.perf_counter()
        response = await call_next(request)
        duration_ms = (time.perf_counter() - start) * 1000
        logger.info(
            "request",
            extra={
                "method": request.method,
                "path": request.url.path,          # path, not full URL with query secrets
                "status": response.status_code,
                "duration_ms": round(duration_ms, 1),
                # NOTE: no request body, no headers dict, no user PII. Log IDs, not data.
            },
        )
        return response


def redact(headers: dict) -> dict:
    return {k: ("***" if k.lower() in _REDACT else v) for k, v in headers.items()}
```

**Golden-signal metrics (`core/metrics.py`).** Cheap, aggregate numbers for
dashboards and alerts — rate, errors, and latency — kept separate from logs.

```python
from prometheus_client import Counter, Histogram

requests_total = Counter(
    "http_requests_total", "Total HTTP requests",
    ["method", "path", "status"],           # RATE and ERRORS (by status)
)
request_duration = Histogram(
    "http_request_duration_seconds", "Request latency",
    ["method", "path"],                     # DURATION (latency distribution)
)
# SATURATION (pool usage, queue depth) is gauged separately; alert on all four.
```

**Correlation ID across the job boundary (`tasks.py`).** The ID set on the request is
carried into the enqueued job, so the worker's logs join the request's story — the
trace survives the async hop.

```python
# enqueue: pass the current correlation id along with the work
await send_invoice_email.enqueue(invoice_id, correlation_id=correlation_id.get())

@task(...)
async def send_invoice_email(invoice_id: int, correlation_id: str) -> None:
    token = _correlation_id.set(correlation_id)   # re-establish the id in the worker
    try:
        logger.info("sending invoice", extra={"invoice_id": invoice_id})
        ...  # the job's logs now carry the SAME correlation id as the request
    finally:
        _correlation_id.reset(token)
```

**Error capture and a real health check.** Unexpected exceptions (Chapter 05's
catch-all) are sent to an error tracker with the correlation ID for grouping and
alerting; the health endpoint checks *real* dependencies, not just "process alive."

```python
# unexpected errors → error tracker with context (integrates the Ch 05 catch-all handler)
sentry_sdk.set_tag("correlation_id", correlation_id.get())
sentry_sdk.capture_exception(exc)

@router.get("/healthz")               # liveness: is the process up?
async def healthz() -> dict: return {"status": "ok"}

@router.get("/readyz")                # readiness: are real dependencies reachable?
async def readyz(session: SessionDep) -> dict:
    await session.execute(text("SELECT 1"))    # DB reachable
    await redis.ping()                          # cache reachable
    return {"status": "ready"}
```

Now the debugging scenario resolves in one step: "did invoice 8842 send?" → search logs
for `invoice_id=8842`, find the request's correlation ID, filter all logs by that ID,
and read the whole story — request received, invoice marked sent, job enqueued, PDF
rendered, email provider returned a 503 — across the API and the worker. The metrics
dashboard already showed the email-provider error rate climbing; the error tracker
already alerted on the exception. None of that is possible if the code was written to
"just work" — which is why observability is built in, not bolted on when the customer
complains.

## Engineering Decisions

Five decisions define an observability implementation.

### Structured logs or plain text?

**Options:** (1) plain-text/interpolated log messages; (2) structured (JSON) logs with
fields.

**Trade-offs:** plain text is human-readable in a terminal and effectively
un-queryable at scale — you can only `grep`, not filter/group/aggregate by field.
Structured logs are slightly less pretty raw but are queryable ("all ERRORs for account
42 with duration > 1s"), which is what you actually need when debugging production at
volume.

**Recommendation:** structured (JSON) logs in any real deployment, with consistent
fields (level, correlation ID, operation, outcome). Human-readable formatting is a
development convenience layered on top; the stored, shipped logs are structured. You
debug by querying fields, not by reading a scroll of strings.

### What is logged, at what level, and what is never logged?

**Options:** (1) log everything at one level; (2) leveled logging with deliberate
content and hard exclusions.

**Trade-offs:** logging everything at INFO buries the important line in noise and
balloons cost; too little logging leaves you blind. And logging request/response bodies
or user objects wholesale leaks secrets and PII. Deliberate leveling and content
require judgment but produce logs that are both useful and safe.

**Recommendation:** use levels meaningfully (DEBUG for development detail, INFO for
notable events and state transitions, WARNING for recoverable anomalies, ERROR for
failures needing attention), log identifiers and outcomes rather than raw data, and
**never** log secrets or PII — redact or exclude them by default. The content of logs is
a security decision as much as an operational one.

### Logs, metrics, or traces — for what?

**Options:** using one pillar for everything, or the right pillar per question.

**Trade-offs:** using logs for everything (computing rates by counting log lines,
alerting on individual lines) is expensive, slow, and unreliable; using only metrics
leaves you unable to debug a specific event; skipping traces leaves cross-boundary flow
invisible. Each pillar is cheap and effective for its job and poor at the others'.

**Recommendation:** logs for per-event debugging, metrics for aggregate trends and
alerting (the golden signals), traces for following a request across boundaries. Alert
off metrics (a rising error rate), then drill into logs/traces for the specific failures
— don't alert off individual log lines or compute trends by grepping logs.

### How do you control log volume and cost?

**Options:** (1) log everything at full volume; (2) sample/level/aggregate to control
volume.

**Trade-offs:** full-volume logging of every request detail is simple and, at scale,
enormously expensive (storage and ingestion costs are real) and noisy. Sampling and
using metrics for high-frequency signals cut cost and noise, at the risk of missing a
detail you later want.

**Recommendation:** log notable events fully, use *metrics* (not logs) for
high-frequency counts and latencies, sample high-volume debug logging, and always log
errors in full. Treat log volume as a cost to manage deliberately — the answer to "should
we log this on every request?" is often "no, make it a metric."

### Build observability, or buy it?

**Options:** (1) self-host the observability stack (Prometheus/Grafana/Loki/Jaeger);
(2) use a managed provider (Datadog, Sentry, Honeycomb, etc.).

**Trade-offs:** self-hosting is free of per-signal fees and full of operational work —
you now run and scale the monitoring system too. Managed providers are fast to adopt and
powerful, at a cost that can grow steeply with volume, plus data leaving your control.
This is the Stage 1, Chapter 06 build-vs-buy decision applied to observability.

**Recommendation:** instrument with vendor-neutral standards (OpenTelemetry for
traces/metrics, structured logs) so you are not locked to a backend, then usually **buy**
the platform early (a managed error tracker and metrics/log backend) because running
observability infrastructure is undifferentiated work — and revisit if volume-based costs
become significant. The instrumentation is yours; the storage/dashboards are a
commodity to buy (the infra choice itself is deepened in Stage 7).

## Trade-offs

Observability trades effort, performance, and cost for the ability to operate, and the
balance is contextual.

**Instrumentation is upfront work for later insight.** Adding structured logging,
metrics, tracing, and correlation propagation is effort spent before you have a problem,
paying off only when you do. It is tempting to skip and disastrous to have skipped when
the incident comes — but a tiny, low-stakes app may genuinely need only basic logging.
Scale the investment to how much it will hurt to be blind.

**Telemetry has a runtime and storage cost.** Logging, metrics, and especially tracing
add some overhead per request, and storing telemetry costs real money at volume — verbose
logging of every request can cost more than the servers. The mitigation is deliberate:
metrics for high-frequency signals, sampling for high-volume traces/logs, full detail for
errors. Observability you can't afford to keep isn't observability.

**More telemetry is not more insight.** Logging everything and alerting on everything
produces noise that actively hides signal and trains people to ignore alerts (alert
fatigue). The valuable system logs and alerts *deliberately* — on things that matter and
things humans should act on — not maximally. Curate; don't accumulate.

**Standardize to avoid lock-in, but don't over-engineer early.** Vendor-neutral
instrumentation (OpenTelemetry) avoids backend lock-in and is worth adopting; a full
three-pillar, multi-service tracing setup for a small monolith is premature (Stage 1,
Chapter 07). Start with structured logs, a correlation ID, and the golden-signal metrics;
add distributed tracing when you actually have distributed flow to trace.

## Common Mistakes

**No observability at all.** Code that ships with no logging, metrics, or tracing, so
problems are invisible until users report them and undiagnosable when they do. Fix: build
in structured logging, golden-signal metrics, and a correlation ID from the start.

**Logging secrets or PII.** Logging full request bodies, auth headers, user objects, or
tokens — a persistent data leak in log storage. Fix: log identifiers and outcomes, redact
or exclude sensitive fields by default.

**Unstructured, contextless logs.** Interpolated string messages with no fields and no
correlation ID, un-queryable and untraceable. Fix: structured JSON logs with consistent
fields and a correlation ID on every line.

**Broken correlation across boundaries.** A correlation ID that stops at the request and
isn't propagated into jobs, events, or downstream calls, so async flow can't be
reconstructed. Fix: propagate the ID across every boundary (Chapters 05, 06; Stage 2,
Chapters 04, 07).

**Log firehose / alert fatigue.** Everything logged at one level burying the signal, or
alerts on everything so none matters. Fix: meaningful levels, curated logs, and alerts on
user-facing symptoms (the golden signals) that a human should act on.

**Confusing the pillars.** Grepping logs to compute rates, alerting on individual log
lines, or having no metrics at all. Fix: metrics for trends/alerting, logs for per-event
detail, traces for flow.

## AI Mistakes

Observability is a cross-cutting concern that nothing in a happy-path demo requires, so an
assistant omits it, or adds it wrong. Worse, when it does log, it tends to log the whole
object — including the secrets. Review generated code for what you'll be able to see (and
what you'll accidentally expose) when it runs in production.

### Claude Code: logging secrets and PII

Asked to add logging, Claude Code frequently logs the entire request, response, or user
object — `logger.info(f"request: {await request.json()}")`, or a user model including
`password_hash`, tokens, and email — because logging "the whole thing" is the most
straightforward way to capture context. It leaks credentials and personal data into
long-lived, widely-read log storage.

**Detect:** logging of full request/response bodies, header dicts including
`Authorization`/`Cookie`, user objects with sensitive fields, tokens, or card/PII data;
any log line that could contain a secret.

**Fix:** require identifiers-not-data and redaction:

> Never log secrets or PII — no request/response bodies, no auth headers, no passwords,
> tokens, or personal data. Log identifiers (user id, account id, resource id) and
> outcomes (status, duration), and redact sensitive fields by default. Logs are
> long-lived and widely readable.

### GPT: unstructured, contextless logging

GPT-family models tend to add plain interpolated log strings — `logger.info(f"processing
invoice {id}")` — with no structured fields and no correlation ID, because it reads
naturally and "logs something." At scale these are un-queryable and can't be tied to a
request or to each other.

**Detect:** f-string/`%`-interpolated log messages with no structured `extra` fields; no
correlation ID on log lines; logs that could only be found by `grep`, not filtered by
field.

**Fix:** require structured, correlated logs:

> Use structured logging with fields (level, a correlation id, operation, ids, outcome),
> not interpolated strings. Every log line must carry the request's correlation id so all
> logs for one request can be filtered together. Emit fields to query on, not prose to
> grep.

### Cursor: correlation dropped across boundaries

Wiring up a background job, an event handler, or a downstream call inline, Cursor tends
not to propagate the correlation ID across the boundary — the job or handler starts a
fresh, disconnected context — because the ID's origin isn't visible from the edit site.
The request's flow then splits into disconnected fragments that can't be reassembled.

**Detect:** a background job, event consumer, or outbound service call that doesn't
receive/re-establish the correlation ID; worker logs with no ID or a new one; a trace that
ends at the enqueue.

**Fix:** require end-to-end propagation:

> Propagate the correlation id across this boundary: pass it into the background job /
> event / downstream call and re-establish it in the consumer, so all logs and spans for
> one user action share the same id. The trace must not break at the async hop.

## Best Practices

**Emit structured logs with a correlation ID, and never log secrets or PII.** JSON logs
with consistent fields and the request's correlation ID on every line; log identifiers and
outcomes, redacting or excluding sensitive data by default.

**Instrument the golden signals as metrics.** Rate, errors, duration, and saturation as
metrics for dashboards and alerting — kept separate from logs, because metrics are the
cheap, aggregate view you alert on.

**Propagate the correlation ID across every boundary.** From the request into jobs, events,
and downstream calls (Chapters 05, 06; Stage 2, Chapters 04, 07), so one user action is one
searchable, traceable story — add distributed tracing (OpenTelemetry) when flow actually
crosses services.

**Capture unexpected errors with context, and alert on symptoms.** Send the Chapter 05
catch-all's exceptions to an error tracker tagged with the correlation ID; alert on
user-facing symptoms (error rate, latency, saturation), not individual log lines — and keep
alerts actionable to avoid fatigue.

**Build observability in, standardize, and health-check real dependencies.** Instrument new
code as you write it (not after an incident), use vendor-neutral standards to avoid lock-in
(buying the backend is usually right — Chapter 06), and make readiness checks probe real
dependencies. Document logging/metrics conventions in `CLAUDE.md`; the monitoring platform
and dashboards are Stage 7.

## Anti-Patterns

**The Black Box.** Code shipped with no logs, metrics, or traces — problems invisible until
users report them, undiagnosable when they do. The tell: an incident where the first
diagnostic step is adding logging to production.

**The Secret Leak.** Passwords, tokens, or PII in the logs — a breach that persists in log
storage. The tell: full request bodies, auth headers, or user objects being logged.

**Print-Debugging Logs.** Unstructured, contextless interpolated strings with no
correlation ID, findable only by grep. The tell: `logger.info(f"...")` with no fields and no
way to tie lines to a request.

**The Untraceable Request.** Correlation that stops at the request boundary, so async flow
fragments. The tell: worker/consumer logs with no shared ID, and a trace that ends at the
enqueue or the service call.

**The Firehose and the Fatigue.** Everything logged at one level (signal buried) and alerts
on everything (none acted on). The tell: millions of INFO lines hiding the one that matters,
and an on-call that mutes the alert channel.

**Logs-as-Metrics.** Grepping or counting log lines to compute rates and trends instead of
emitting metrics. The tell: a "dashboard" built on log queries that's slow and expensive, and
no actual counters or histograms.

## Decision Tree

"I need to be able to understand this in production — what do I instrument?"

```
WHAT DO I NEED TO SEE?
│
├─ Per-event detail to debug a specific request/failure
│    └─► STRUCTURED LOG: JSON fields + correlation id + context.
│        NEVER log secrets/PII. Log ids and outcomes, not raw data.
│
├─ Aggregate trend / health / something to ALERT on
│    └─► METRIC: golden signals (rate, errors, duration, saturation).
│        Alert on user-facing symptoms, not log lines. Keep alerts actionable.
│
├─ Where a request WENT across boundaries (services/jobs/events)
│    └─► TRACE: spans tied by a trace id (OpenTelemetry).
│        Add when flow actually crosses process boundaries.
│
└─ An UNEXPECTED exception (a bug)
     └─► ERROR TRACKER: capture with the correlation id + context; alert.

ALWAYS: one correlation id, propagated across EVERY boundary (request → job →
event → downstream). BUILD it in as you write the code, not after the incident.
```

## Checklist

### Implementation Checklist

- [ ] Logs are structured (JSON) with consistent fields and a correlation ID on every line.
- [ ] No secrets or PII are logged; sensitive fields are redacted/excluded by default.
- [ ] Golden-signal metrics (rate, errors, duration, saturation) are emitted for endpoints and jobs.
- [ ] The correlation ID propagates from the request into jobs, events, and downstream calls.
- [ ] Unexpected exceptions are captured with context (correlation ID) and alertable.
- [ ] Readiness checks probe real dependencies (DB, cache), not just process liveness.

### Architecture Checklist

- [ ] Logs, metrics, and traces are each used for their purpose (per-event / trend / flow), not conflated.
- [ ] Instrumentation uses vendor-neutral standards (OpenTelemetry, structured logs) to avoid lock-in.
- [ ] Log volume is managed deliberately (metrics for high-frequency signals, sampling where needed).
- [ ] Distributed tracing exists where flow crosses process boundaries; it isn't over-built for a simple monolith.
- [ ] Logging/metrics conventions are documented in `CLAUDE.md`; the platform/dashboards are tracked for Stage 7.

### Code Review Checklist

- [ ] No secret or PII appears in a log line (watch AI diffs — this is the dangerous one).
- [ ] Logs are structured with a correlation ID, not interpolated strings.
- [ ] The correlation ID is propagated across any new async/service boundary.
- [ ] New endpoints/jobs emit golden-signal metrics and log notable events at the right level.
- [ ] Alerting (if added) is on symptoms, not individual log lines.

### Deployment Checklist

- [ ] Logs ship to a queryable, durable aggregator that survives container restarts (see [`checklists/production-readiness.md`](../../checklists/production-readiness.md)).
- [ ] Golden-signal dashboards and symptom-based alerts are wired to on-call (platform details: Stage 7).
- [ ] Error-tracker alerts reach a human, keyed by correlation ID.
- [ ] Log retention and sampling are configured to control cost without losing error detail.
- [ ] Deploys are marked in telemetry so "what changed?" is answerable.

## Exercises

**1. Make a flow traceable.** Take Invoicely's "send invoice" flow (API request →
background job → email provider) and instrument it: structured logs with a correlation ID
propagated into the job, and the golden-signal metrics on the endpoint. Then answer "did
invoice 8842 send, and what happened?" using only a log query. The artifact is the
instrumentation and the single query that reconstructs the whole flow.

**2. Find and fix the leaks.** Take logging code that logs the full request body and a user
object including a token (write it, or have an assistant generate "add request logging").
Identify every secret/PII field being leaked, then fix it to log identifiers and outcomes
with redaction. The artifact is the list of leaked fields and the safe replacement.

**3. Design the alerting.** For Invoicely's invoices API and its email-sending job, decide
what to alert on (which golden signals, what thresholds) so that a real problem pages on-call
and normal variation does not. The artifact is the alert definitions plus a one-line
justification each — and an explicit note on what you deliberately do *not* alert on, to
avoid fatigue.

## Further Reading

- **Google SRE Book and the SRE Workbook** (sre.google/books), especially "Monitoring
  Distributed Systems" and the chapters on the golden signals and alerting — the
  authoritative treatment of what to measure and how to alert on symptoms without drowning
  in noise. The foundation for the metrics and alerting half of this chapter.
- **OpenTelemetry documentation** (opentelemetry.io) — the vendor-neutral standard for
  traces, metrics, and (increasingly) logs; read the concepts and the Python instrumentation
  guide to instrument without locking yourself to a backend.
- **Observability Engineering** (Charity Majors, Liz Fong-Jones, George Miranda; O'Reilly) —
  the modern case for observability (especially high-cardinality, trace-centric debugging)
  and why the three-pillars framing is a starting point, not the destination.
- **OWASP Logging Cheat Sheet** (cheatsheetseries.owasp.org) — what to log for security, and
  crucially what *never* to log (credentials, PII, session tokens). The reference for the
  "never log secrets" rule that this chapter treats as non-negotiable.

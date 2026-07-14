# Scalability

## Introduction

Scalability is the most misused word in software engineering. In hiring posts it means "we use
Kubernetes." In architecture reviews it means "I would like to rewrite this." In its actual
engineering sense it means something narrower and more useful: **how the system's performance
and cost respond when load grows**. A system is not "scalable" or "unscalable" in the abstract —
it handles *this* load parameter growing to *that* level with *this much* added cost and
complexity, or it doesn't. Scalability is a relationship, not a badge.

That definition does real work, because it forces three questions that badge-thinking skips.
What load, specifically — requests per second, concurrent users, rows in the invoices table,
PDFs generated per minute? Growing to what level, specifically — 2× by summer, or 100× in a
fantasy pitch deck? And at what cost — because every remedy on the scaling menu (bigger
machine, more machines, cache, queue, partition) buys headroom with a different currency:
money, operational complexity, or consistency guarantees you used to get for free.

This chapter is the judgment layer for the whole stage. The six chapters after it each teach a
component — load balancers, stateless app tiers, Redis, queues, CDNs, event streams. This one
teaches the discipline that decides whether you need any of them yet: measure the load, find
the bottleneck, and spend the smallest amount of complexity that relieves it. It is a
conceptual chapter because the scarce skill is not configuring the components — it is knowing
which one the evidence calls for, and having the nerve to say "none, yet."

## Why It Matters

- **Most scaling failures are design failures that load exposed.** Sessions in process memory,
  files on the instance's disk, a job scheduler that assumes it is the only copy of itself
  running — each works perfectly at one instance and breaks at two. These cost almost nothing
  to avoid at design time and a rewrite to fix under fire. The judgment "what must be decided
  early vs. what can wait" is the highest-leverage decision in this stage.
- **Premature scaling is the same mistake in the other direction — and it is more common.**
  A three-person team operating Kafka, a service mesh, and twelve microservices for 40
  requests per second has converted its runway into infrastructure rehearsal. Complexity is
  paid for daily whether or not the load that justifies it ever arrives.
- **The bottleneck decides whether your spend does anything.** System throughput is the
  throughput of the slowest component in the path. Doubling the app servers while the
  database is at 95% CPU doubles your bill and changes nothing else. Scaling without a
  measured bottleneck is spending without a mechanism.
- **Averages hide the failures your users actually feel.** A 120 ms average latency is
  compatible with a p99 of 8 seconds — and at one page issuing five API calls, a large share
  of page loads eat at least one slow call. Systems are experienced at their tail, not their
  mean; capacity decisions made on averages routinely green-light systems that feel broken.
- **AI assistants amplify whichever instinct you bring.** Ask an assistant for "a scalable
  architecture" and you will get the distributed version of everything — sharded, queued,
  replicated — because that is what the phrase means in its training data. Ask it to find the
  bottleneck in a metrics snapshot and it is genuinely excellent. The engineer's framing
  decides which of those two tools shows up.

## Mental Model

Three ideas carry this entire stage: load is a set of numbers, throughput is set by the
bottleneck, and remedies form a ladder ordered by cost.

**1. Load is a set of numbers, not a feeling.** "We're growing fast" is not designable.
Describe load with parameters, each measured now and projected honestly:

```
LOAD PARAMETERS (Invoicely's, as an example)
  requests/second on the API          current:  45 rps   peak: 120 rps
  concurrent authenticated users      current:  ~300     peak: 900
  invoices generated per hour         current:  400      month-end spike: 6,000
  rows in largest table (line_items)  current:  21M      growing 2M/month
  PDF renders per hour                current:  350      month-end spike: 5,500
  webhook deliveries per hour         current:  1,100    peak: 9,000
```

Different parameters stress different components — rps stresses the app tier, row counts
stress the database, PDF renders stress CPU on workers, fan-out stresses the queue. "Scale"
means nothing until you say which of these numbers is growing.

**2. Throughput is set by the bottleneck.** A request path is a pipeline; its capacity is the
minimum of its parts:

```
            capacity of each component in the path

  Nginx          App tier        PostgreSQL       Worker pool
  ~20,000 rps    ~900 rps        ~350 rps ◄────   ~80 jobs/min
                                 (dashboard        
                                  queries at       
                                  95% CPU)         

  SYSTEM CAPACITY = min(components) = ~350 rps.
  Money spent anywhere except the bottleneck changes nothing.
  And when you fix it: the bottleneck MOVES — to the next-
  slowest component. Scaling is the repeated game of finding
  and relieving the current constraint, not a one-time act.
```

Two consequences follow. First, *measure before you spend* — the bottleneck's location is an
empirical fact, and intuition about it is wrong often enough to be expensive (everyone
suspects the app code; it is usually the database, the N+1, or a lock). Second, *utilization
is the early warning*: a component at 40% has headroom; at 70% it is next quarter's problem;
at 90% it is this month's outage, because load spikes and utilization above ~80% is where
queueing delay turns nonlinear — wait times grow gently until high utilization, then explode.
That is why p99 latency degrades long before anything is "down," and why waiting for errors
to tell you you're out of capacity means finding out during the outage. Watch two families of
numbers per component: utilization (CPU, memory, connections, queue depth) and latency
percentiles (p50 for typical experience, p95/p99 for the tail).

**3. Remedies form a ladder, ordered by the complexity they cost.** Each rung buys headroom;
each rung down the list costs more in operations, failure modes, or consistency:

```
THE SCALING LADDER          costs                     typical headroom
 1 Measure & fix waste      hours of work             often 2–10×
   (N+1s, missing index,
    payloads — Stage 6 Ch 03/05)
 2 Scale UP (vertical)      money; a reboot;          2–4× per step,
   bigger machine           has a hard ceiling        zero new concepts
 3 Cache                    invalidation logic,       2–10× on read-
   (Stage 3 Ch 07; Redis    staleness (already        heavy paths
    the component: Ch 04)   taught — reuse it)
 4 Scale OUT (horizontal)   statelessness required,   near-linear for
   more app instances +     load balancer, N new      the app tier —
   load balancer (Ch 02/03) failure modes             NOT for the DB
 5 Offload                  new infrastructure        removes whole
   queues for writes (05),  per component             classes of load
   CDN for reads (06),                                from the origin
   read replicas
 6 Partition / shard        the expensive rung:       the big numbers —
   split data across        cross-shard queries,      and the big
   machines (streams: 07)   resharding, app changes   operational bills
```

The discipline is boring and correct: take the cheapest rung that relieves the *measured*
bottleneck, then re-measure. Teams get into trouble by skipping rungs upward (sharding what
an index would fix) far more often than by exhausting a rung too late. Vertical scaling in
particular is systematically underrated — a machine 4× the size involves zero new
architecture, and today's large instances (hundreds of GB of RAM, dozens of cores) carry
most businesses further than their founders' ambitions did.

A working definition:

> **Scalability is the measured relationship between a system's load parameters and its
> performance and cost. Scaling is the repeated loop of: describe the load in numbers, locate
> the bottleneck empirically, relieve it with the cheapest rung on the ladder that works,
> and re-measure — while keeping the design choices that are cheap now and prohibitive later
> (statelessness, externalized state) even when today's load doesn't demand them.**

## Real-World Scenario

**The trigger.** Invoicely — 2,000 businesses on the Stage 7 architecture: one VPS running
Nginx, one FastAPI container, PostgreSQL, Redis, and two Celery workers — signs a partnership
with an accounting-software vendor. The vendor will promote Invoicely to its customer base:
a projected 50,000 businesses onboarding over two quarters, with the usage pattern Invoicely
already knows (heavy month-end invoicing) multiplied across a much larger base.

**The first instinct.** The team's senior-most engineer opens a design doc titled "Invoicely
v2: Microservices Migration." Kubernetes, a service per domain, Kafka between them. The
estimate is two quarters — exactly the window in which the customers arrive. An assistant,
prompted with "how should we architect Invoicely to scale to 50,000 customers?", cheerfully
produces the same doc with better diagrams.

**The measurement instead.** One engineer spends two days getting numbers before the debate.
A load test (Locust, driving the real API with a realistic mix: dashboard loads, invoice
CRUD, PDF downloads, month-end generation bursts) against a staging clone, plus the Stage 7
monitoring on production. The results reframe everything:

- The API tier saturates at ~900 rps — but production peak is 120 rps. Not the problem.
- PostgreSQL hits 95% CPU at ~350 rps of mixed traffic. The top queries by total time are
  two dashboard aggregations — unindexed scans over `invoices` filtered by tenant and month.
- Month-end PDF generation queues 6,000 jobs at ~80 jobs/minute of worker capacity —
  a 75-minute backlog *today*, which at 25× the customer base becomes a 30-hour backlog:
  the actual scaling emergency, and nobody had named it.
- p50 API latency is 85 ms; p99 is 3.1 s — the tail is dashboard requests waiting on those
  same two queries.

**The boring plan that follows from the numbers.** Composite indexes and a pre-aggregated
dashboard summary (Stage 6, Chapters 03 and 05) drop the two queries from 1.8 s to 12 ms —
PostgreSQL CPU falls to 30% at peak; system capacity roughly triples from that change alone.
The VPS is upgraded one size ($40 → $80/month) for headroom. PDF rendering — CPU-bound and
embarrassingly parallel — moves to four dedicated worker instances, which is Chapter 03's
subject done on the easiest possible tier (workers were stateless already). Cached dashboard
aggregates get 60-second TTLs per Stage 3 Chapter 07's rules. Total: about three weeks of
work, no new architecture.

**What the measurement bought.** Not just the deferral of a two-quarter rewrite. The load
test also surfaced the constraint that *will* bind next: a single PostgreSQL instance and a
single VPS is one failure domain, and at 50,000 businesses the month-end write load will
genuinely exceed one machine's comfort. The remaining chapters of this stage are that
finding, taken seriously in the right order: a load balancer so there can be more than one
app instance (Ch 02), the statelessness audit that makes those instances safe (Ch 03), Redis
promoted to properly-operated shared infrastructure (Ch 04), the queue tier widened for the
month-end spike (Ch 05), PDFs and the frontend served from a CDN (Ch 06), and invoice
lifecycle events published to a stream so analytics and webhooks stop adding load to the
transactional database (Ch 07). Same destination the v2 doc gestured at — reached one
measured bottleneck at a time, while the product keeps shipping.

## Engineering Decisions

### What load are we actually designing for?

Take the measured current numbers and apply committed growth — signed contracts, a
partnership with a projected funnel — not aspirational growth. Design for the next 12–18
months with a 2–3× safety factor on the projection; re-plan when the numbers move. Designing
for 100× is not prudence, it is spending certain complexity on speculative load — and the
system you'd build for 100× is *worse* at today's job: slower to change, harder to debug,
more expensive to run. The honest failure mode of under-provisioning is a scramble and some
slow weeks; the failure mode of over-architecture is permanent drag. One exception deserves
real front-loading: choices that are one-way doors (see below).

### Scale up or scale out?

Up, until one of three things stops you: the ceiling (the next instance size doesn't exist or
the price curve turns exponential), availability (one machine is one failure domain — if the
SLA needs redundancy, you need "out" for reasons other than capacity), or the workload shape
(embarrassingly parallel work like PDF rendering scales out almost free, so take the free
win). Scaling up buys headroom with money alone; scaling out buys it with money *plus* a
load balancer, statelessness requirements, and N new partial-failure modes. For the
database, the calculus is stronger still: a bigger machine and read replicas carry
PostgreSQL a very long way, and sharding is a last resort, not a milestone.

### Which numbers trigger action?

Decide the thresholds before you're at them, or the outage decides for you. A workable set:
any component sustaining >70% utilization at weekly peak gets a plan; >85% gets the plan
executed now. p99 latency above the SLO for two consecutive weeks is a capacity signal, not
a tuning suggestion. Queue depth that grows across a whole business cycle (not just within a
spike) means the consumers are under-provisioned. Write these into the monitoring from Stage
7 Chapter 07 as alerts — capacity planning is monitoring with a longer time horizon.

### Optimize or add capacity?

Optimization (fixing the N+1, adding the index, trimming the payload) is permanently cheaper
at any scale — it reduces the work per request, so every future machine does more. Capacity
is faster to buy and doesn't risk the code. The rule of thumb: when a measured inefficiency
is fixable in days, fix it first — a 5× win from an index outruns a 2× win from hardware and
costs less forever. When the system is already efficient, or the fix is a quarter-long
refactor and the growth is next month, buy capacity and schedule the fix. Never let "we
should really optimize this" block the $40/month upgrade that ends the incident.

### What must be decided early, and what can wait?

The dividing line is reversibility. **Cheap now, prohibitive later (decide early):** keeping
the app tier stateless (sessions, uploads, caches out of process — Chapter 03); putting a
tenant key on every table (Stage 3's multi-tenancy discipline — retrofitting one is the
worst migration in SaaS); using a queue for work that doesn't belong in the request (Stage 3
Ch 06); structured logs with correlation IDs (Stage 3 Ch 08 — you cannot debug a distributed
system without them). **Deferrable (decide when measured):** how many instances, sharding,
read replicas, CDN, event streaming, multi-region. Notice the pattern: the early decisions
are *hygiene* — they cost near-zero when the code is young. The deferrable ones are
*capacity* — they cost real money and complexity, so they should wait for evidence.

## Trade-offs

| Choice | You gain | You pay |
|---|---|---|
| Scale up (bigger machine) | Zero new architecture; instant; no code changes | Hard ceiling; one failure domain; price curve steepens at the top |
| Scale out (more machines) | Near-linear headroom; redundancy; no ceiling for stateless tiers | Load balancer + statelessness required; N partial-failure modes; harder debugging |
| Optimize first | Permanent efficiency; every future machine does more | Engineering time; risk of touching working code; diminishing returns |
| Buy capacity first | Fast; zero code risk; ends the incident today | Cost recurs monthly; the inefficiency compounds as load grows |
| Design for measured load (+2–3×) | System stays simple, fast to change, cheap to run | A genuine 10× surprise means scrambling (usually: buy capacity, then re-plan) |
| Design for hypothetical 100× | Never surprised by growth | Certain daily complexity for speculative load; worse at today's job; slower shipping |
| Early statelessness hygiene | Scaling out later is a config change, not a rewrite | Mild discipline now (external sessions, no local files) — near-zero when young |
| Deferring all scale thinking | Maximum focus on product | The one-way doors (state, tenancy) close silently; reopening them is a rewrite |

The load-design trade-off deserves its sharp edge: **a system designed for 100× the load is
not a safer version of the system designed for 3× — it is a different, worse system for
today's job**, with more moving parts between every feature and production. You are not
buying insurance; you are pre-paying, daily, for a scenario that usually doesn't arrive on
schedule and rarely arrives in the predicted shape.

## Common Mistakes

- **Scaling without a measurement.** "The app is slow, add more servers" — and the app is
  slow because of one unindexed query, which now runs slowly on four machines. Every scaling
  action should name the bottleneck it relieves and the number that proves it moved.
- **Reasoning from averages.** Mean latency of 120 ms with a p99 of 8 s is a broken system
  wearing a healthy dashboard. Track percentiles; set SLOs on p95/p99; treat the tail as the
  product experience, because for your heaviest users it is.
- **Load-testing the wrong traffic.** A load test of unauthenticated GETs against a warm
  cache proves the system can serve the traffic it never gets. Realistic mixes: real auth,
  real tenant data volumes, realistic read/write ratios, and *your* spike shape (Invoicely's
  is month-end generation, not uniform rps).
- **Thinking only in requests per second.** Data volume is a load parameter that never
  spikes and never recedes. The table that grows 2M rows/month will, on a schedule you can
  compute today, outgrow the query plans, the backup window, and the migration strategy —
  and rps monitoring will never mention it.
- **Treating "scalable" as binary.** "Is this design scalable?" has no answer. "Does this
  design handle 5× our current month-end at acceptable p99 and cost?" does. Insist on the
  second form in design reviews — it converts posturing into arithmetic.
- **Ignoring the spike-to-baseline ratio.** Provisioning for average load means the
  month-end spike — the moment customers most need the product — is when it fails. Provision
  for peak, or engineer the spike flat (queues, Chapter 05).
- **Confusing redundancy with scale.** Two instances behind a load balancer because "we
  need to scale" when the real need was surviving one machine's failure. Both are valid;
  they are different requirements with different designs (two small instances add
  availability while barely adding capacity). Name which one you're buying.

## AI Mistakes

The three tools fail differently here, and all three failures are expensive because scaling
advice *looks* authoritative — the numbers, the acronyms, the architecture diagrams.

### Claude Code: scaling the tier that isn't the bottleneck

Asked to "make Invoicely handle more load," Claude Code produces competent, plausible work on
whatever tier is most visible in the session — usually the app tier: worker counts raised,
replica configs written, connection pools enlarged. If the bottleneck is the database (it
usually is), every one of those changes is a no-op at best; enlarged pools are worse than a
no-op, because more connections pointed at a saturated database *increase* its load. The
diff looks like scaling; the system's capacity does not move.

**Detect:** the plan names no measured bottleneck — no metric, no profile, no "PostgreSQL is
at X% because of Y." Changes cluster on the tier the conversation was about, not the tier
the numbers indict. **Fix:** feed the agent evidence before asking for remedies — the
monitoring snapshot, `pg_stat_statements` output, queue depths — and require every proposed
change to name the bottleneck it relieves and the number that will prove it worked. As with
Stage 10's debugging discipline: hypotheses are welcome, but evidence decides.

### GPT: capacity claims from nowhere

GPT states throughput and capacity numbers with the confidence of a benchmark report and the
provenance of none: "this configuration will comfortably handle 10,000 rps," "PostgreSQL
becomes a bottleneck beyond ~5,000 writes/second," "you'll need sharding past 10M rows."
These numbers are textural — real systems vary by orders of magnitude on hardware, schema,
query shape, and payload size — but they read as engineering and get pasted into design docs,
where they become the justification for building (or skipping) real infrastructure.

**Detect:** any specific performance number that arrived without a load test you ran or a
cited, comparable benchmark. Round numbers and "comfortably" are tells. **Fix:** treat every
capacity claim as a hypothesis to test, never a fact to build on. The assistant's legitimate
role is designing the load test that would produce the real number for *your* workload —
ask it for that instead.

### Cursor: the load test that flatters

Asked to add a load test, Cursor autocompletes the one that is easiest to write: hitting
`/health` or an unauthenticated list endpoint, no tenant data loaded, no auth handshake, no
write traffic, warm caches. The report says 12,000 rps and everyone relaxes. The first real
month-end after the partnership launch is the actual load test, and it disagrees — because
the flattering test exercised the static 5% of the system and skipped the dashboard
aggregations, PDF renders, and write bursts that constitute the real workload.

**Detect:** load-test scripts with no authentication step, no realistic data fixtures, a
single endpoint, or a uniform request rate against a business with spiky traffic. Suspiciously
excellent numbers are themselves the signal. **Fix:** specify the test as a workload, not an
endpoint — the traffic mix in percentages, the tenant data volume, the auth flow, the spike
shape — and review the script against production access-log distributions before believing
its output.

## Best Practices

- **Instrument before you architect.** You cannot find a bottleneck you cannot see. The
  Stage 7 monitoring stack — per-component utilization, latency percentiles, queue depths,
  slow-query logs — is the prerequisite for every decision in this stage. If you cannot
  answer "what is PostgreSQL's CPU at weekly peak?" you are not ready to discuss sharding.
- **Keep a load model document.** One page: the load parameters, their current measured
  values, their growth rates, and the next expected ceiling. Update it quarterly and when a
  growth event (partnership, launch) changes the projection. It converts scaling from
  ambient anxiety into a schedule.
- **Load-test on a schedule, not in a crisis.** A realistic load test (real mix, real data
  shape, your spike pattern) run before each expected growth event and after major
  architectural changes. The goal is to know your current ceiling and the next bottleneck
  *while both are still academic*.
- **Set SLOs and let them arbitrate.** "p95 dashboard load under 500 ms, p99 API under 1 s,
  month-end PDF backlog clears within 30 minutes" — with targets like these, "do we need to
  scale?" becomes arithmetic instead of aesthetics. SLOs also license the negative answer:
  meeting them means you may stop scaling.
- **Take the cheap rungs in order, and re-measure between rungs.** Waste → vertical → cache
  → horizontal → offload → partition. Each relieved bottleneck moves the constraint
  somewhere new; the re-measurement is what tells you where. Skipping it is how teams end up
  with the fourth remedy for the first problem.
- **Spend early effort on the one-way doors only.** Statelessness, tenant keys on every
  table, queued background work, correlation IDs. These are this chapter's entire mandate
  for pre-scale teams — everything else on the ladder waits for a measurement.
- **Write the scaling decision down.** An ADR (the [template](../../templates/adr.md)) for
  each rung taken: the measured bottleneck, the options, the number that will prove success.
  Future engineers inherit the *why*, and the next growth event starts from a record instead
  of archaeology.

## Anti-Patterns

- **Resume-driven scaling.** The architecture chosen because it is what large companies use
  (or what the team wants to have operated), justified by scale that isn't measured or
  projected. The tell: the design doc names technologies before it names bottlenecks.
- **The big-bang scalability rewrite.** "V2 will be scalable" — a quarters-long rewrite
  justified by growth, arriving after the growth window, carrying all the risk of Stage 1's
  rewrite trap plus a deadline. Scaling that works is incremental precisely because each
  step is verified by measurement before the next is funded.
- **"We'll scale later" applied to hygiene.** Correct posture for capacity; disastrous for
  the one-way doors. Sessions in process memory and files on local disk are not deferred
  scaling decisions — they are decisions *against* scaling, made silently.
- **Autoscaling as a substitute for understanding.** Autoscaling multiplies whatever the
  system does — including its inefficiencies (N+1 storms now cost linearly more money) and
  its pathologies (each new instance opens connections against the already-dying database;
  a retry storm gets *funded*). Autoscale a system you understand at fixed sizes first.
- **Benchmarking on the laptop.** Dev-machine numbers — different hardware, empty tables,
  no concurrent tenants, localhost network — extrapolated to production capacity. The only
  numbers that count come from production-shaped environments under production-shaped load.
- **The premature generic platform.** Building "the platform team's Kubernetes + service
  mesh + golden paths" for one product at 120 rps. Platform investment follows product
  scale; it does not summon it.

## Decision Tree

```
"We need to scale" — do we, and how?
│
├─ Is there a measured bottleneck (metric + component)?
│   ├─ NO → STOP. Instrument (Stage 7 Ch 07), load-test with a
│   │        realistic mix, find the constraint. No spend before
│   │        evidence. (Growth expected? Load-test to find the
│   │        ceiling BEFORE traffic does.)
│   └─ YES ↓
├─ Is it waste — N+1, missing index, oversized payloads,
│  chatty endpoints — fixable in days?
│   ├─ YES → Fix it (Stage 6 Ch 03/05), re-measure. Cheapest
│   │        capacity that exists; often 2–10×.
│   └─ NO ↓
├─ Is the bottleneck read traffic on data that tolerates
│  bounded staleness?
│   ├─ YES → Cache it (strategy: Stage 3 Ch 07; Redis as shared
│   │        infra: Ch 04; static/asset reads: CDN, Ch 06).
│   └─ NO ↓
├─ Is it work that doesn't need to happen in the request?
│   ├─ YES → Queue it and widen the worker tier (Ch 05;
│   │        job code: Stage 3 Ch 06). Spiky load especially.
│   └─ NO ↓
├─ Does a bigger machine relieve it at acceptable cost —
│  and is a single failure domain still acceptable?
│   ├─ YES → Scale up. Zero new architecture. Re-measure;
│   │        note the next ceiling in the load model.
│   └─ NO (ceiling / cost / availability requires redundancy) ↓
├─ Is the pressed tier stateless (or cheaply made stateless)?
│   ├─ YES → Scale out: load balancer (Ch 02) + N instances
│   │        (Ch 03). Near-linear for app and worker tiers.
│   └─ NO → The state is the blocker. Externalize it first
│            (Ch 03 → Redis, Ch 04) — that refactor IS the
│            scaling work. Then scale out.
└─ Bottleneck is the database itself, after indexes, caching,
   and a big machine?
    → Read replicas for read pressure; then — with the load
      model proving it — partitioning/sharding, accepting the
      complexity bill. For fan-out consumers (analytics,
      webhooks, audit), take load OFF the transactional DB
      with an event stream (Ch 07) before sharding it.
```

## Checklist

### Engineering Judgment Checklist

- [ ] The load is described in numbers — parameters, current values, growth rates — not
      adjectives, and the load model is written down and dated.
- [ ] The bottleneck is identified by measurement (utilization, percentiles, slow-query
      data), not intuition, and named in every scaling proposal.
- [ ] The remedy is the cheapest rung that relieves the measured constraint — waste →
      vertical → cache → horizontal → offload → partition — and skipped rungs have a stated
      reason.
- [ ] The design target is committed growth times a 2–3× factor over 12–18 months — not a
      hypothetical 100×.
- [ ] Percentiles (p95/p99), not averages, define the SLOs and the alerts.
- [ ] Peak load (your spike shape), not average load, drives provisioning.
- [ ] Data-volume growth has been projected against query plans, backups, and migrations —
      not just request-rate growth.
- [ ] The one-way doors are held open regardless of current scale: stateless app tier,
      tenant keys, queued background work, correlation IDs.
- [ ] Availability requirements are stated separately from capacity requirements — each
      justifies different spending.
- [ ] Each rung taken is recorded as an ADR with the number that will prove it worked, and
      the system is re-measured after each change.

### Code Review Checklist

- [ ] New code introduces no per-instance state — no module-level caches of mutable data, no
      in-process session storage, no local-filesystem writes that must survive the request
      (Stage 3 Ch 09's storage rules).
- [ ] New queries were checked against realistic data volumes (Stage 6 Ch 05) — the table's
      *projected* size, not the dev fixture's.
- [ ] New endpoints state their expected traffic and appear in the load-test mix if they'll
      carry real volume.
- [ ] Work that can leave the request path did (Stage 3 Ch 06) — especially anything on a
      spike-shaped trigger.
- [ ] Capacity numbers cited in the PR or design doc have a source: a load test, production
      metrics, or a cited comparable benchmark — never an assistant's assertion.
- [ ] Changes justified by "scale" name the measured bottleneck they relieve.

## Exercises

1. **Build the load model.** For a system you operate (or Invoicely as described in this
   stage), write the one-page load model: 5–8 load parameters, current values from real
   metrics, growth rates, and the component each parameter stresses first. Identify which
   parameter hits a ceiling soonest and compute roughly when.
2. **Find the bottleneck with a load test.** Set up Locust (or k6) against a staging
   deployment of your API with production-shaped data. Design the traffic mix from your
   access logs — endpoints, ratios, auth, spike shape. Drive load until a component
   saturates. Record: the ceiling in rps, the saturating component and metric, and p50/p99
   at 50%/80%/100% of the ceiling. Compare where the bottleneck actually was against where
   the team guessed it would be before the test.
3. **Judge the AI's plan.** Prompt an assistant: "How should we scale this system to 10×
   the traffic?" — providing only the architecture, no metrics. Then run the review this
   chapter teaches: which recommendations name a bottleneck? Which capacity numbers have a
   source? Which rungs did it skip? Re-prompt with your load model and measurements from
   exercises 1–2 and compare the two plans.
4. **Write the scale-up-vs-out ADR.** Your measured bottleneck is the app tier at 85% CPU
   at peak; the next instance size costs 2× and holds ~2 years of projected growth; the SLA
   requires surviving one machine failure by next year. Write the ADR using the
   [template](../../templates/adr.md): the decision, the numbers, the rejected option, and
   what measurement would reopen the question.
5. **Audit the one-way doors.** On your current codebase, spend one hour answering: Where do
   sessions live? What writes to the local filesystem? What state is held in module-level
   variables? Which scheduled jobs assume a single instance? For each finding, estimate the
   cost of fixing it now vs. at 10 instances under load. (This audit is Chapter 03's
   starting point.)

## Further Reading

- Martin Kleppmann — *Designing Data-Intensive Applications*, Chapter 1 — the definitive
  treatment of describing load and reasoning about scalability as load-parameter-specific.
- Google — *Site Reliability Engineering*, chapters on SLOs and capacity planning — the
  practice of letting objectives arbitrate scaling decisions.
- Jeffrey Dean, Luiz André Barroso — "The Tail at Scale" (CACM, 2013) — why percentiles,
  not averages, describe systems, and how tail latency compounds with fan-out.
- Brendan Gregg — "The USE Method" — a systematic checklist (Utilization, Saturation,
  Errors) for locating bottlenecks in every system resource.
- Neil Gunther — *Guerrilla Capacity Planning* — queueing theory for practitioners; why
  utilization above ~80% turns nonlinear.
- Locust and k6 documentation — the load-testing tools; both cover realistic-workload
  modeling, which is the part that matters.
- Stage 6, Chapters 03 & 05 ([indexing](../stage-06-database-engineering/03-indexing.md),
  [query optimization](../stage-06-database-engineering/05-query-optimization.md)) — the
  cheapest rung of the ladder, in full.

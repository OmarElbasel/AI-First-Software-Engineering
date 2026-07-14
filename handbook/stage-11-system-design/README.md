# Stage 11 — System Design

Design systems that survive success — by learning what actually breaks when load grows, and
which component to reach for at each breaking point: a load balancer when one machine is no
longer enough, a stateless app tier when instances must multiply, Redis when shared state must
be fast, a queue when work must decouple from requests, a CDN when the same bytes are served a
million times, and an event stream when many consumers need the same facts in order.

Everything before this stage built one correct system: Invoicely runs on a VPS behind Nginx
(Stage 7), with a tuned PostgreSQL (Stage 6), tested (Stage 8) and hardened (Stage 9). This
stage asks the question that stack cannot answer: what happens when traffic grows 10× — and
then 10× again? System design is not a catalog of big-company architectures to imitate. It is
the discipline of finding the current bottleneck, understanding the trade-offs of each remedy,
and paying for exactly as much distribution as the load requires — no earlier and no later.
The curriculum topics — scalability, load balancing, horizontal scaling, Redis, queues, CDN,
event streaming — are that progression: first the judgment (what scale means and when to buy
it), then the components in the order a growing system typically needs them.

## Why this stage exists

Most scaling failures are not capacity failures — they are design failures that capacity
exposed. The app that stores sessions in process memory works perfectly until the second
instance starts. The job queue that assumed ordering works perfectly until a second worker
subscribes. The cache that was "just an optimization" becomes a correctness bug the day two
instances disagree about invalidation. These failures are cheap to prevent at design time and
expensive to fix under load, which is why the judgment must come before the traffic. The
opposite failure is just as real and more common: teams building for a million users they do
not have, spending their runway operating Kafka for forty events per hour. AI assistants
amplify both failure modes — ask one for "a scalable architecture" and it will happily
generate the distributed version of everything, because distributed answers dominate its
training data. An engineer who knows what each component costs, what it fixes, and what load
justifies it can direct that firepower precisely. This stage builds that engineer.

## Chapters

| # | Chapter | Status |
|---|---------|--------|
| 01 | [Scalability](01-scalability.md) | Done |
| 02 | [Load Balancing](02-load-balancing.md) | Done |
| 03 | [Horizontal Scaling](03-horizontal-scaling.md) | Done |
| 04 | [Redis](04-redis.md) | Planned |
| 05 | [Queues](05-queues.md) | Planned |
| 06 | [CDN](06-cdn.md) | Planned |
| 07 | [Event Streaming](07-event-streaming.md) | Planned |

Seven chapters, one per curriculum topic, ordered as a growing system meets them. Scalability
(Ch 01) is the conceptual foundation — load, bottlenecks, vertical vs horizontal, and the
judgment of when *not* to scale. Load balancing (Ch 02) is the first infrastructure a scaling
system adds: one entry point, many machines behind it. Horizontal scaling (Ch 03) is what the
application must become for those machines to be interchangeable — stateless, share-nothing,
safe to multiply. Redis (Ch 04) is where the state evicted from the app tier lands: shared,
fast, and with its own operational contract. Queues (Ch 05) decouple work from requests so the
two can scale independently. CDN (Ch 06) moves repeated reads to the edge so they never reach
the origin at all. Event streaming (Ch 07) is the capstone: the durable, ordered, replayable
backbone that feeds many consumers from one write — and the component most often adopted too
early.

## Boundaries with other stages

- **Event-driven architecture as a design style** — events vs commands, choreography vs
  orchestration, the outbox pattern — is **Stage 2, Chapter 07**. Chapter 07 here teaches the
  *infrastructure* (partitions, consumer groups, offsets, replay) that runs those designs at
  scale.
- **Application-level caching strategy** — what to cache, invalidation, TTLs, stampede
  protection — is **Stage 3, Chapter 07**. Chapter 04 here teaches Redis the *component*:
  data structures, persistence, eviction, high availability, and the patterns beyond caching.
- **Background job code** — task design, idempotency, retries in Celery — is **Stage 3,
  Chapter 06**. Chapter 05 here scales the *queue tier* itself: delivery guarantees, ordering,
  dead-letter queues, backpressure, and broker selection.
- **Database scaling mechanics** — indexing, query optimization, transactions — are
  **Stage 6**. This stage treats the database as the bottleneck those tools defend, and adds
  the layers (cache, queue, replicas) that keep load away from it.
- **Nginx configuration, TLS, and deployment** — are **Stage 7, Chapters 04 and 06**.
  Chapter 02 here builds on that reverse proxy and turns it into a load balancer; it does not
  re-teach proxying or certificates.

## Running example

The stage scales **Invoicely** — the invoicing SaaS built across Stages 3–10 — from the
single VPS it shipped to in Stage 7 toward the architecture it needs when a partnership brings
50,000 new businesses onboard. Each chapter is one step of that migration: measuring where
Invoicely actually saturates first, putting Nginx to work as a load balancer across multiple
app instances, evicting sessions and per-instance state so instances become disposable, moving
that state into a properly configured Redis, widening the Celery/queue tier to absorb invoice
generation spikes, serving invoice PDFs and the Next.js frontend through a CDN, and finally
publishing invoice lifecycle events onto a stream that analytics, webhooks, and the audit
trail consume independently. The end state is deliberately not "Invoicely on Kubernetes with
Kafka" — it is Invoicely with exactly the components its load justifies, and a documented
reason for each.

## Learning outcome

You can find a system's actual bottleneck with measurements instead of guesses; choose between
scaling up and scaling out with a defensible cost argument; configure a load balancer whose
health checks and session handling match how the app really behaves; refactor an application
so instances are stateless and interchangeable; run Redis as shared infrastructure with
persistence, eviction, and failover configured on purpose; design queue topologies that
absorb spikes without losing or duplicating work; put a CDN in front of static and
semi-static content without serving stale or private data; and judge when an event stream
pays for its complexity — so that when growth arrives, your system bends instead of breaking,
and when growth hasn't arrived yet, you haven't paid for the architecture it would need.

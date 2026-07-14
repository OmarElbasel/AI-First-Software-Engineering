# Stage 12 — SaaS Engineering

Build the business around the software — by learning the loop every SaaS product runs on:
ship the smallest thing that tests real demand (MVP), decide what the value costs (pricing),
collect the money without losing any (payments), observe what users actually do (analytics),
hear what they say and decide what it means (user feedback), distill both into the numbers
that describe the business (product metrics), and feed those numbers back into how the
product grows (growth).

Everything before this stage built and scaled a correct system: Invoicely is architected
(Stage 2), implemented (Stages 3–5), tuned (Stage 6), deployed (Stage 7), tested (Stage 8),
hardened (Stage 9), built with AI leverage (Stage 10), and ready for load (Stage 11). None of
that answers the question a SaaS company lives or dies on: is anyone paying for this, and
will more people pay next month? This stage treats that question as an engineering problem —
because in an AI-first team it is one. The same engineer who ships the feature now also
instruments it, prices it, bills for it, and reads the numbers it produces. The curriculum
topics — MVP, pricing, payments, analytics, user feedback, product metrics, growth — are that
loop in the order a product meets it: first the judgment of what to build, then the systems
that turn usage into revenue and revenue into knowledge.

## Why this stage exists

Most SaaS failures are not engineering failures — they are products nobody wanted, priced by
guesswork, billed by fragile glue code, and steered by opinions because the metrics were
never trustworthy. Engineers inherit these failures: the founder asks "can we change pricing?"
and the answer is a three-week migration because plan names were hard-coded into a hundred
`if` statements. A webhook handler silently drops a Stripe event and a churned customer keeps
their access — or a paying one loses it. The analytics say 40% activation because the
tracking fired on page load instead of on success. These are engineering problems wearing
business clothes, and they are cheap to prevent at design time and expensive to untangle
after the money is flowing. The opposite failure is equally real: teams building billing
platforms, custom analytics warehouses, and A/B-testing frameworks before the first paying
customer — infrastructure rehearsal in a costume of rigor. AI assistants amplify both modes:
ask one for a billing integration and it produces code that handles the happy path and
silently mishandles retries, refunds, and out-of-order webhooks; ask it for a metrics
dashboard and it computes churn three plausible, mutually incompatible ways. An engineer who
knows what each system must guarantee — and which numbers must be exactly right versus
roughly right — can direct that firepower precisely. This stage builds that engineer.

## Chapters

| # | Chapter | Status |
|---|---------|--------|
| 01 | [MVP](01-mvp.md) | Planned |
| 02 | [Pricing](02-pricing.md) | Planned |
| 03 | [Payments](03-payments.md) | Planned |
| 04 | [Analytics](04-analytics.md) | Planned |
| 05 | [User Feedback](05-user-feedback.md) | Planned |
| 06 | [Product Metrics](06-product-metrics.md) | Planned |
| 07 | [Growth](07-growth.md) | Planned |

Seven chapters, one per curriculum topic, ordered as a product meets them. MVP (Ch 01) is the
conceptual foundation — what "minimum" and "viable" actually mean, and the discipline of
shipping to learn instead of shipping to be finished. Pricing (Ch 02) turns value into a
model the code can enforce: plans, entitlements, and limits designed so the business can
change its mind without a migration. Payments (Ch 03) is the highest-stakes integration in
SaaS — subscription lifecycles, webhooks, and the reconciliation discipline that keeps the
database and the payment provider telling the same story. Analytics (Ch 04) instruments what
users do: an event schema designed on purpose, shipped without leaking PII. User feedback
(Ch 05) is the qualitative channel — collecting it, weighting it, and closing the loop
without letting the loudest voice write the roadmap. Product metrics (Ch 06) computes the
numbers the business runs on — MRR, churn, activation, retention — correctly, from the
billing and event data the previous chapters produced. Growth (Ch 07) is the capstone: the
loops that compound, the engineering work that actually moves them, and the judgment to tell
growth engineering from growth theater.

## Boundaries with other stages

- **Product thinking as a mindset** — users vs. stakeholders, outcomes vs. output — is
  **Stage 1, Chapter 02**. Chapter 01 here applies that mindset to the specific, high-stakes
  decision of what a first shippable product contains and what it deliberately omits.
- **Build vs. buy judgment** is **Stage 1, Chapter 06**. This stage exercises it constantly —
  payment providers, analytics vendors, feature-flag services — and references the framework
  rather than re-teaching it.
- **Background jobs and idempotent task design** are **Stage 3, Chapter 06**. Chapter 03 here
  builds webhook processing and dunning on top of that machinery; it does not re-teach Celery.
- **Webhook signature verification, secrets handling, and rate limiting** are **Stage 9
  (Chapters 04 and 08)**. Chapter 03 applies them to payment webhooks; Chapter 04 applies the
  same trust boundary to ingestion endpoints.
- **Event streaming infrastructure** — partitions, consumer groups, replay — is **Stage 11,
  Chapter 07**. Chapter 04 here designs the analytics *events themselves* (schema, semantics,
  privacy) and can ship them over that infrastructure when volume justifies it.
- **A/B-test statistics and experiment platforms** are deliberately out of scope; Chapter 07
  covers when an experiment is worth running and what invalidates one, not the statistics of
  significance testing.

## Running example

The stage follows **Invoicely** — the invoicing SaaS built across Stages 3–11 — through the
part of its history the earlier stages skipped: how it became a business. Chapter 01 rewinds
to the beginning and asks what the *first* shippable Invoicely should have contained (and
what the team actually shipped, and what that cost). From Chapter 02 onward the timeline is
the present: Invoicely's Free/Professional/Business plans get a real entitlement model,
Stripe subscriptions with webhook-driven state and reconciliation, an event pipeline that
tracks activation without storing invoice contents, a feedback system that survived the
partnership's 50,000-customer influx, a metrics layer that computes MRR and churn the same
way twice, and a growth loop built on the one asset an invoicing product uniquely owns —
every invoice is an email sent to someone who doesn't use Invoicely yet.

## Learning outcome

You can scope a first release that tests a demand hypothesis instead of a feature list;
design a plan-and-entitlement model that survives pricing changes without code rewrites;
integrate a payment provider so that the provider, the database, and the customer's access
never disagree for long — and reconcile them when they do; instrument product events with a
deliberate schema and defensible privacy; run a feedback pipeline that turns anecdotes into
decisions without handing the roadmap to the loudest customer; compute MRR, churn,
activation, and retention correctly enough to bet the company on; and evaluate growth work
like an engineer — by the loop it feeds and the number it moved — so that when the product
finds demand, the systems around it turn that demand into a business instead of a mess.

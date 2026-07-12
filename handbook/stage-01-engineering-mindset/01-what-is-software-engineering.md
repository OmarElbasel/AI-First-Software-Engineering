# What is Software Engineering?

## Introduction

Programming is writing code. Software engineering is everything that makes
code worth running: deciding what to build, structuring it so it can change,
and keeping it alive while real users depend on it.

The two are routinely confused because they look identical from the outside —
both happen in an editor, both produce code. The difference is not the
activity but the scope of responsibility. A programmer is responsible for
making code work. An engineer is responsible for what that code does to the
product, the team, and the business over its entire lifetime.

This chapter also covers "Programming vs Engineering" as one topic, because
the distinction between them *is* the definition of software engineering.
Everything else in this handbook builds on it.

## Why It Matters

Until recently, writing code was expensive enough that typing speed and
framework knowledge were real bottlenecks. AI assistants removed that
bottleneck. Claude Code, Codex, or Cursor can produce a working feature in
minutes — thousands of lines, plausible structure, passing tests.

What AI did not remove is the cost of *wrong* code. A generated feature that
mishandles a payment retry costs the same in refunds, support tickets, and
lost trust as a hand-written one. If anything, the cost went up: AI produces
plausible-looking code faster than most teams can evaluate it.

That inversion defines the modern engineer's value. When implementation is
cheap, judgment is the product:

- Deciding what to build, and what not to build.
- Specifying what "done" means, including failure modes.
- Structuring systems so the tenth change is as cheap as the first.
- Reviewing generated code with the skepticism it deserves.

Engineers who only program now compete with a tool that programs faster than
they do. Engineers who exercise judgment use that same tool as leverage. This
chapter is about the difference.

## Mental Model

Programming is a subset of engineering:

```
┌──────────────────────────────────────────────────┐
│                Software Engineering              │
│                                                  │
│   deciding · designing · reviewing · shipping    │
│   maintaining · communicating · retiring         │
│                                                  │
│              ┌───────────────────┐               │
│              │    Programming    │               │
│              │  (writing code)   │               │
│              └───────────────────┘               │
└──────────────────────────────────────────────────┘
```

A useful working definition:

> **Software engineering is making decisions under constraints, over time,
> with other people.**

Each clause matters:

- **Decisions under constraints** — you never have unlimited time, budget, or
  information. Choosing what to sacrifice is the job.
- **Over time** — code is read, changed, and debugged for years after it is
  written. Every decision is evaluated by its cost across that whole lifetime,
  not by how fast the first version shipped.
- **With other people** — teammates, future maintainers, and now AI assistants
  all read and modify your code. Work that only its author can understand is a
  liability, not an asset.

Every feature passes through the same lifecycle:

```
┌─────────┐   ┌────────┐   ┌───────┐   ┌────────┐   ┌──────┐   ┌──────────┐
│ Problem │ → │ Design │ → │ Build │ → │ Review │ → │ Ship │ → │ Maintain │
└─────────┘   └────────┘   └───────┘   └────────┘   └──────┘   └──────────┘
     ↑                                                              │
     └──────────────── new problems discovered ─────────────────────┘
```

Build is one box out of six. AI dramatically accelerates that one box — and,
used well, assists with the others. A developer who only knows how to operate
inside the Build box has automated away most of their own role. The other
five boxes are where engineering happens, and they are the subject of this
handbook.

## Real-World Scenario

**Invoicely** is a small B2B invoicing SaaS: FastAPI and PostgreSQL on the
backend, Next.js frontend, around 900 paying companies. The founders decide
to add subscription billing — monthly and annual plans, charged through
Stripe, replacing the current manual invoicing for the SaaS's own fees.

Two developers, same task, same AI assistant.

### Developer A — programmer mode

Developer A opens the editor and prompts the AI: *"Add Stripe subscription
billing to this FastAPI app. Monthly and annual plans."* The AI delivers:
a checkout endpoint, a webhook handler, a `plan` column on the `accounts`
table, and a pricing page. It works in testing — the tests exercise only the
happy path. A ships in **3 days**.

What the code does: on `invoice.paid` webhook, mark the account active and
insert a payment record. On checkout, create a Stripe subscription.

What nobody asked:

- What happens when a card payment **fails**? (Stripe retries for days —
  the account's state during that window is undefined.)
- Stripe **redelivers webhooks** on timeout or non-2xx responses. The handler
  inserts a payment record every time it runs. It is not idempotent.
- What happens when a customer **switches plans mid-cycle**? (The code
  cancels and recreates the subscription — charging the full new price with
  no proration credit.)
- What is the source of truth for subscription state — Stripe or the local
  database? (The code assumes both and keeps neither authoritative.)

### Developer B — engineer mode

Developer B spends **day 1 without writing code**, producing a one-page
document of questions and forwarding the commercial ones to the founders:

- Proration on plan changes: credit, charge immediately, or defer to next cycle?
- Failed payments: how many retries, what does the user see, when do we
  restrict access (dunning)?
- Webhook handling: which events matter, and how do we make processing
  idempotent when Stripe redelivers?
- Source of truth: Stripe holds subscription state; our database holds a
  cached copy updated only by verified webhooks.
- Plan changes mid-cycle, cancellation timing, refund policy, tax handling —
  in or out of scope for v1?

With answers in hand, B prompts the same AI — but section by section, against
a written design, reviewing each piece. The webhook handler records processed
Stripe event IDs in a `webhook_events` table and skips duplicates. Failed
payments put the account into a `past_due` state with a banner, not a
lockout. Plan changes use Stripe's proration, and plan definitions live in
configuration rather than code, so a pricing change is an edit, not a
deployment. B ships in **8 days**, with the out-of-scope list written down.

### Six months later

Developer A's half-year included two incident weekends chasing duplicate
payment records, a hot-patched webhook handler, and a batch of manual refunds
— roughly ten unplanned engineering days before the team gave up and
scheduled a rewrite.

The numbers below are illustrative; the mechanism they illustrate is not.

| | Developer A | Developer B |
|---|---|---|
| Time to ship | 3 days | 8 days |
| Double-charge incidents | 2 (webhook redelivery) | 0 |
| Support tickets on billing | ~40 | 3 |
| Refunds issued | 11 | 0 |
| Pricing changes absorbed | Each required code surgery | 3, config-level |
| Outcome at month 6 | Rewrite scheduled (est. 15 days) | Unchanged |
| Total engineering cost | 3 + ~10 firefighting + 15 rewrite = **~28 days** | 8 + 2 = **~10 days** |

The AI wrote most of the code in both cases. The 18-day difference — plus
the refunds and the customers who quietly churned after a double charge — is
largely attributable to the questions Developer B asked before prompting.
That is what this handbook means by engineering.

## Engineering Decisions

The scenario's outcome was determined by four decisions Developer B made
before any code existed. Each recurs in almost every production billing
system, and each follows the shape every engineering decision should:
options, trade-offs, recommendation, reasoning.

### Source of truth for subscription state

**Options:** (1) the local database is authoritative and pushes changes to
Stripe; (2) Stripe is authoritative and the local database holds a cached
copy, updated only by verified webhooks.

**Trade-offs:** local-authoritative gives fast reads and full control, but it
reimplements retry, dunning, and proration logic the processor already runs —
and it drifts the moment anyone touches the Stripe dashboard directly.
Stripe-authoritative accepts eventual consistency (webhook latency) and
deeper vendor coupling in exchange for having exactly one billing state
machine.

**Recommendation:** Stripe authoritative, verified-webhook cache. The
processor executes the billing state machine whether you like it or not;
maintaining a second one that must always agree with it creates a permanent,
unpaid reconciliation job. Developer A's code had no answer to this question,
which is why its two sources of truth diverged.

### Webhook idempotency

**Options:** (1) process every delivery as new; (2) record processed Stripe
event IDs in a `webhook_events` table and skip duplicates; (3) write every
handler as a natural-key upsert so reprocessing is harmless.

**Trade-offs:** option 1 is the double-charge bug — redelivery is documented,
normal Stripe behavior, not an edge case. The event-ID ledger costs one small
table and a unique constraint and works uniformly for every event type.
Upserts are elegant per-handler, but each new handler must re-derive its
natural key, and some events have no natural key to upsert on.

**Recommendation:** the event-ID ledger, written in the same database
transaction as the handler's other writes so a crash cannot record an event
as processed without its effects (or vice versa). Uniform, cheap, and
enforced by the database rather than by developer discipline. Note that this
deduplicates *inbound* webhooks — distinct from Stripe's API idempotency
keys, which protect your *outbound* requests from duplicate submission.

### Failed-payment handling

**Options:** (1) restrict access immediately; (2) a `past_due` grace state
with a visible banner and restricted writes after a deadline; (3) retry
silently and hope.

**Trade-offs:** immediate lockout protects revenue but converts the most
common failure — an expired card on an otherwise happy customer — into a
churn event. Silent retries protect the user experience while unpaid usage
accumulates invisibly. The grace state costs one more account state and some
UI, but it matches how the failure actually resolves: the customer updates
their card.

**Recommendation:** the `past_due` grace state. Design for the common case
(recoverable payment failure), and make the uncommon case (genuine
non-payment) a deadline rather than an accident.

### Plan changes mid-cycle

**Options:** (1) cancel the subscription and create a new one on the new
plan; (2) update the existing subscription and let Stripe prorate.

**Trade-offs:** cancel-and-recreate is easier to reason about locally, but it
forfeits proration credit — the overcharge in Developer A's version — resets
the billing anchor, and can trigger cancellation side effects. Updating in
place delegates the proration math to the processor.

**Recommendation:** update in place. Billing math you do not write is billing
math that cannot be wrong in your code.

None of these decisions requires seniority or special talent. They require
asking the questions while they are still cheap — before the code exists.

## Trade-offs

Engineering rigor is not free, and applying it everywhere is its own failure
mode. The day Developer B spent on questions has to be worth more than the
code it delayed — for billing, it obviously was; for an internal admin page,
it likely is not.

**When programmer mode is the right call:**

- Prototypes and spikes whose purpose is to answer a question, then be deleted.
- Throwaway scripts: one-off data migrations you verify by hand, local tooling.
- Validating demand — a feature behind a flag for five pilot users does not
  need the architecture of a feature serving everyone.
- Hackathons, demos, anything explicitly not production.

The discipline that makes this safe is honesty about the category. A
prototype that gets a URL and real users has silently changed categories, and
its engineering debt comes due with interest.

**When programmer mode is malpractice:**

- Anything touching **money** — billing, refunds, payouts, pricing.
- Anything touching **auth** — login, sessions, permissions, password reset.
- Anything touching **user data** — storage, deletion, export, migration.

These domains share two properties: failures are expensive out of proportion
to the code involved, and failures are often silent until a customer finds
them. The happy path always works in the demo. The failure paths are the
feature.

Rigor is a dial, not a switch. The skill is reading which setting the
situation demands — the Decision Tree below makes the dial explicit.

## Common Mistakes

**Jumping straight to implementation.** The first question is "what problem
is this solving?", not "how do I build this?". Symptom: you are prompting an
AI or writing code within minutes of reading the request. Fix: write the
problem down in one paragraph first; if you cannot, you do not understand it
yet.

**Equating "works on my machine" with done.** Working code is the midpoint of
the lifecycle, not the end. Done includes: failure modes handled, reviewed,
deployed, observable, and documented enough for the next person. Teams that
define done as "compiles and demos" ship their integration testing to
customers.

**Treating requirements as fixed.** Requirements are hypotheses written by
people with incomplete information. Engineers interrogate them: the request
says "export to Excel" — the problem is "the finance team needs data in their
reconciliation tool", which might be a CSV, an API, or a scheduled email.
Building the literal request is how correct code solves the wrong problem.

**Measuring productivity in code produced.** Lines of code measure cost, not
value — every line must be read, tested, and maintained forever. This mistake
is newly dangerous in the AI era, because generating impressive volumes of
code is now effortless. The engineer who closes a ticket by deleting 200
lines or by configuring an existing tool has often out-produced the one who
generated 2,000.

## AI Mistakes

AI assistants fail in characteristic, recognizable ways. These examples name
specific tools, but every failure mode appears in every assistant to some
degree — learn the pattern, not the brand.

### Claude Code: confident architecture for an under-specified problem

Given a vague request, Claude Code tends to produce a complete, internally
consistent, plausible solution — services, models, tests — without asking
what the constraints are. The output *looks* like the work of someone who
understood the problem, which is exactly what makes it dangerous: it is the
Developer A scenario, automated.

**Detect:** the solution arrived without a single clarifying question, and it
makes specific decisions (data model, retry policy, state machine) that were
never discussed.

**Fix:** force the questions to surface before code exists. Review prompt:

> Before implementing, list every assumption you are making about
> requirements, failure modes, and scale. Phrase each as a question I must
> answer. Do not write code until I respond.

### GPT: happy-path code with decorative error handling

GPT-family models tend to produce code where error handling *exists* but
does not match real failure modes — the classic form is a broad
`try/except Exception` that logs the error and continues, converting a loud
failure into silent data corruption. Retryable and permanent failures get
identical treatment; partial failures (the payment succeeded but the database
write failed) are not modeled at all.

**Detect:** every `except` block looks the same; no distinction between
"retry this" and "alert a human"; no idempotency on operations that callers
will retry.

**Fix:** review prompt against the generated code:

> List every way this operation can fail in production: network failure,
> duplicate delivery, concurrent execution, partial failure, invalid input.
> For each, show exactly what this code does, and whether that is safe.

### Cursor: local-file myopia

Inline editors optimize for the file in front of them. Cursor will produce a
locally clean edit that is inconsistent with the rest of the system — raw SQL
in a codebase that uses SQLAlchemy everywhere, a second date-formatting
helper, a new error-response shape that breaks the frontend's parser.

**Detect:** diff review that asks "does this match how the rest of the
codebase does it?" — not just "is this correct?". New utility functions and
new patterns in a mature codebase are yellow flags.

**Fix:** supply the convention, don't hope for it. Include a reference file
in context and instruct: *"Match the existing patterns in `services/billing.py`
and `core/errors.py`. If you need to deviate, say so and justify it."*

The common thread: **AI output is a pull request from a fast, well-read,
context-blind contributor.** It gets exactly the scrutiny a human PR gets —
the review checklist below is written for it.

## Best Practices

**Write the problem before the solution.** One paragraph: who has the
problem, what it costs them, how you will know it is solved. This is the
cheapest engineering artifact that exists, and it is the difference between
Developer A and Developer B. It also makes your AI prompts dramatically
better, because the assistant inherits your framing.

**Define "done" to include failure modes.** Before building, write down what
happens when the payment fails, the webhook arrives twice, the input is
malicious, the third-party API is down. If the definition of done only
describes success, the failure behavior will be defined by accident — in
production.

**Review AI output like a junior engineer's PR.** Trust it to compile;
verify its judgment. Concretely: read every line before committing, run the
failure cases yourself, and reject code you cannot explain. "It works" is not
a review. The AI Mistakes section above gives you the three most common
things to look for.

**Ask "what breaks in six months?"** Six months is when the requirements have
changed twice, the author has moved on, and the shortcuts come due. If the
honest answer is "this hardcoded pricing table" or "nobody else understands
the webhook flow", you have found this week's real task.

## Anti-Patterns

**Resume-driven architecture.** Choosing microservices, event sourcing, or a
new framework because it is interesting or marketable rather than because the
problem demands it. The complexity bill is paid by the team, monthly,
forever. Boring technology that the whole team understands is a competitive
advantage, not a compromise.

**"The AI wrote it, so it must be fine."** Authority transfer to the tool.
AI code is statistically plausible, not verified — it reproduces the
average of its training data, including the average's bugs. The moment
generated code is merged, it is *your* code; "the AI wrote that part" has
never once mollified a customer who was double-charged.

**Rewriting instead of understanding.** When confronted with confusing code,
declaring it garbage and rewriting from scratch. The confusing parts are
often load-bearing: they encode failure cases and edge conditions discovered
in production, at real cost. Rewrites discard exactly that knowledge — and AI
makes the trap worse, because regenerating a subsystem is now trivially easy.
Understand first; then decide.

**Cargo-cult patterns.** Applying repository layers, dependency injection, or
Clean Architecture because "that's how serious projects do it", detached from
the problem the pattern solves. Every pattern is a trade: structure now for
flexibility later. Adopting the structure without needing the flexibility is
a pure loss. If you cannot state what a pattern is protecting you from, you
do not need it yet.

## Decision Tree

"Should I engineer this carefully, or just build it?"

```
Does it touch money, auth, or user data?
│
├── YES ──────────────────────────────► ENGINEER IT. No exceptions.
│                                        (Failure modes first, review
│                                         everything, no unreviewed AI code.)
└── NO
    │
    Will it live longer than ~a month?
    │
    ├── NO (spike / prototype / one-off script)
    │   │
    │   Can it touch production systems or real data by accident?
    │   │
    │   ├── YES ──────────────────────► SANDBOX IT, then build fast.
    │   │
    │   └── NO ───────────────────────► BUILD FAST. Mark it disposable.
    │                                    Delete it when it has answered
    │                                    its question.
    └── YES
        │
        Will anyone besides you maintain it?
        │
        ├── YES ──────────────────────► ENGINEER IT.
        │                                (Conventions, tests, docs —
        │                                 their time is the constraint.)
        └── NO
            │
            Blast radius if it fails?
            │
            ├── One user, recoverable ─► BUILD PRAGMATICALLY.
            │                            Add rigor when usage earns it —
            │                            and notice when it does.
            └── Many users, data loss ─► ENGINEER IT.
```

The most common failure is not choosing the wrong branch — it is refusing to
re-run the tree when the answers change. Yesterday's prototype with today's
users is on a different branch now.

## Checklist

### Engineering Judgment Checklist — before starting any feature

- [ ] I can state the problem in one paragraph, including who has it and what it costs them.
- [ ] I know what "done" means, and it includes failure modes, not just the happy path.
- [ ] I know whether this touches money, auth, or user data — and applied the decision tree.
- [ ] I know the expected lifetime of this code and who will maintain it.
- [ ] I have listed what I am explicitly *not* building (scope is written down).
- [ ] Commercial or product questions are answered by the people who own them, not assumed by me.
- [ ] The design survives the "what breaks in six months?" question.

### Code Review Checklist — for AI-generated code

- [ ] I have read every line and can explain what each part does and why.
- [ ] Error handling matches real failure modes — retryable vs. permanent failures are treated differently.
- [ ] Operations that can be retried or redelivered (webhooks, jobs, payments) are idempotent.
- [ ] Input is validated at the system boundary; nothing trusts external data.
- [ ] The code matches the existing codebase's conventions, patterns, and helpers — no parallel implementations.
- [ ] No secrets, credentials, or config values are hardcoded.
- [ ] Tests assert behavior (including failure behavior), not implementation details.
- [ ] I ran the failure cases myself, not just the happy path.

## Exercises

These produce artifacts. Do them in writing, not in your head.

**1. The question list.** Take this feature request: *"Add a 'delete my
account' button to the settings page."* Produce the one-page document
Developer B would write: every question an engineer must ask before
building it. Cover data (what is deleted, what is retained, legal
requirements), money (active subscriptions?), failure modes (partial
deletion), and irreversibility. Aim for at least twelve questions; the first
five are the easy ones.

**2. The bug hunt.** Prompt an AI assistant to implement a FastAPI endpoint
that accepts a Stripe webhook and records successful payments to PostgreSQL.
Use the naive one-line prompt deliberately. Then write a bug report
identifying at least three classes of production defect in the output —
look for idempotency, signature verification, and transaction boundaries.
Do not fix them; the artifact is the report, written as if for a colleague.

**3. The maintenance forecast.** Pick a feature you shipped in the last six
months. Write its six-month maintenance forecast as of the day you shipped:
what requirements were likely to change, what would break first, what the
next engineer would curse. Then compare the forecast with what actually
happened. The gap between the two is a precise measurement of your current
engineering judgment — repeat quarterly and watch it shrink.

## Further Reading

- **Software Engineering at Google** (Winters, Manshreck, Wright — free
  online) — source of the best short definition in the field: software
  engineering is "programming integrated over time." The first three chapters
  are this chapter, with twenty years of receipts.
- **A Philosophy of Software Design** (John Ousterhout) — the clearest
  argument that complexity is the core enemy of engineering, and a working
  vocabulary for design reviews.
- **The Mythical Man-Month** (Fred Brooks) — fifty years old and still
  correct about why software effort does not scale the way intuition says.
  Read it to understand which problems are permanent.
- **Choose Boring Technology** (Dan McKinley — boringtechnology.club) — a
  short essay that will save you from resume-driven architecture more
  reliably than any framework comparison.
- **The Pragmatic Programmer** (Hunt & Thomas, 20th-anniversary edition) —
  the craft-level habits (tracer bullets, design by contract, "don't live
  with broken windows") that connect this chapter's mindset to daily work.

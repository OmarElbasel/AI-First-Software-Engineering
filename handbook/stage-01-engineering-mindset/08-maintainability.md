# Maintainability

## Introduction

Maintainability is the property of software that keeps the cost of changing
it low across its entire life. It is not a phase that happens after
development, and it is not the same as "clean code" — it is the sum of
several properties working together: readability, testability,
observability, recorded decisions, and the ability of someone *other than the
author* to understand and safely change the system.

This is the final chapter of Stage 1, and it is deliberately the capstone,
because maintainability is where the whole engineering mindset converges.
Chapter 01 defined engineering as "decisions under constraints, over time,
with other people" — maintainability is that "over time, with other people"
clause made into a design goal. Simplicity (Chapter 07) makes code
understandable; managed debt (Chapter 05) keeps change cheap; recorded
decisions (Chapters 04 and 06) preserve the *why*; good build-vs-buy calls
keep the surface small. Maintainability is what you get when those
disciplines hold together — and what you lose when any of them slips.

It is also the mindset chapter that the AI era changed most. When an
assistant generates code faster than any human can read it, the binding
constraint on a system stops being how fast you can write it and becomes
whether anyone — human or AI — can still understand and change it. A codebase
nobody comprehends is unmaintainable no matter how it was produced.
Maintainability is now the discipline that decides whether AI makes your
system faster to evolve or merely faster to ossify.

## Why It Matters

Software spends most of its life being changed, not written. For any system
that survives, the initial development is a small fraction of the total cost;
the majority is spent afterward — fixing, extending, adapting, and
understanding it, over years, mostly by people who did not write it. This is
the single most important economic fact about software, and it has a direct
consequence: **optimizing for the first version over the lifetime of changes
is optimizing the cheap part and neglecting the expensive one.**

Unmaintainable software fails in a characteristic curve. Early changes are
fast, because the system is small and its author remembers everything. Then
each change costs a little more than the last — coupling spreads, knowledge
disperses, fear accumulates — until a two-day feature takes three weeks, new
hires take half a year to become useful, and the team seriously discusses a
rewrite. No single decision caused it; maintainability was never anyone's
explicit goal, so it decayed by default.

The AI era raises the stakes on one specific dimension: understandability.
Generation is free and fast, which means code now accretes faster than
comprehension does, and comprehension is the thing maintenance actually
requires. A team can ship a quarter's worth of AI-generated features and end
up unable to change any of them, because no human ever built a mental model
of the system and the AI's model does not persist between sessions. The same
tool, used well, is a maintenance superpower — it can read legacy code, write
the missing tests, and capture a departing engineer's knowledge faster than
any human. Which outcome you get depends entirely on whether maintainability
was a goal or an afterthought.

## Mental Model

The core measure of maintainability is not a property of a single change but
the *trend* across many:

```
   Cost of change
   │
   │  UNMAINTAINABLE                          ╱
   │  (rising curve — each change            ╱
   │   costs more than the last)           ╱
   │                                     ╱
   │                                  ╱
   │                              ╱
   │  ────────────────────────────────────  MAINTAINABLE
   │                                          (flat curve — the Nth change
   │                                           costs about what the 1st did)
   └────────────────────────────────────────────►  Number of changes over time

   The goal of maintainability is a FLAT change-cost curve.
```

Judge code not by how the first version felt to write, but by how the tenth
modification will feel to a stranger. That reframing is most of the skill.

Maintainability is not one property but a cluster, and a weakness in any one
of them raises the change-cost curve:

```
   READABILITY     Can someone understand it? (code as communication)
   CHANGEABILITY   Can they modify it safely? (low coupling, high cohesion)
   TESTABILITY     Can changes be verified? (the net that makes change unscary)
   OBSERVABILITY   Can its behavior be understood in production?
   DOCUMENTATION   Is the WHY recorded? (decisions, constraints, gotchas)
   ONBOARDABILITY  Can a new person — or AI session — become productive?
```

Two ideas make the cluster actionable.

**Code is read far more than it is written, and changed by people without the
author's context.** Every choice that trades a moment of writing convenience
for lasting reading difficulty is a bad trade, because the readers are many
and the writing is once. Maintainability is, concretely, empathy for a future
stranger who has none of your current context — and that stranger is very
often you, six months on.

**The bus factor is a maintainability metric.** How many people can leave
before the system becomes unmaintainable? When critical knowledge — why a
decision was made, how to recover a stuck process, what a subsystem actually
does — lives only in one person's head, the bus factor is one, and the system
is one resignation away from a crisis regardless of how good the code is.
Maintainability requires knowledge to live in the repository, not in people.

A working definition:

> **Maintainability is the property that keeps the cost of changing software
> low across its whole life — readable, testable, observable, documented, and
> changeable by someone other than its author. It is measured by the cost of
> the Nth change, not the first.**

## Real-World Scenario

**Invoicely**, one last time. The system is now everything the previous
chapters built it into — and Sara, the founding engineer, gives notice. Sara
built the reconciliation engine, made the sync decisions in Chapter 04, took
the deadline debt in Chapter 05, and has carried the whole system in her head
for three years. Her departure is the most honest maintainability test there
is: **what survives when the person who understood everything is gone?**

The team does a reckoning, and the results map precisely onto which
disciplines had been applied where.

### What survived cheaply

- **The reconciliation engine** had just been simplified (Chapter 07). A
  junior engineer had already made a change to it unaided, because it was now
  three explicit functions instead of a DSL only Sara understood. The
  differentiator — the most important code in the company — was maintainable
  by someone other than its author. That is the whole goal, demonstrated.
- **The sync architecture decisions** were recorded as ADRs (Chapters 04 and
  06). Why the sync is one-way, why Stripe is the source of truth, why the
  queue exists — all written down, with their revisit triggers. The *why*
  survived Sara's departure because it never lived only in her head. New
  engineers could change the sync without re-litigating settled decisions or
  reintroducing bugs those decisions had prevented.

### What did not

- **Operational knowledge was tribal.** When the sync got stuck — which
  happened a few times a year — recovery required running an undocumented
  script on the server in a specific way that only Sara knew. This knowledge
  existed nowhere in the repository. Bus factor: one. The code was fine; the
  *operation* of the code was a single point of failure about to walk out the
  door.
- **Observability was a gap.** When something broke, only Sara knew where to
  look, because the logs were unstructured and there was no runbook for "the
  reconciliation numbers look wrong — what do you check?" The system could not
  explain its own behavior; it required Sara to interpret it.

### The response — the maintainability cluster, applied

The team treats the six weeks before Sara leaves as a knowledge-capture
sprint, and does it AI-first. Rather than asking Sara to write documentation
from scratch — slow, and she is busy handing off — they pair her with an
assistant: the assistant reads the code and drafts the runbooks, the ADRs for
the undocumented decisions, and a structured-logging plan, and Sara *corrects*
them. This is dramatically faster than authoring, because reviewing and
correcting a draft is easier than producing one, and it moves her knowledge
into the repository (Chapter 03's repo-as-memory) where every future
engineer and every future AI session can read it. They add structured logs
and a "what to check when X breaks" runbook so the system starts explaining
itself.

### The test that proves it

The real verification is not the documents; it is the onboarding. The team
hands the replacement engineer a genuine task in the sync subsystem and asks
them to complete it using only the repository — no tapping Sara on the
shoulder — and logs every question they still had to ask a human. This is
Chapter 03's cold-start test applied to a person: **every question that could
only be answered by Sara is a maintainability gap**, and each one becomes a
repository change. When the new engineer's change cost drops to roughly what
Sara's would have been, maintainability is real — the change-cost curve
stayed flat across a change of personnel, which is the hardest test it faces.

The lesson of the whole arc lands here: the parts of Invoicely where the
mindset disciplines were applied survived a founder's departure cheaply; the
parts where knowledge lived only in a head were the crisis. Maintainability
is not clean code alone. It is whether the system — and the knowledge required
to run it — can outlive any individual.

## Engineering Decisions

Four decisions inside that scenario recur in every system that has to outlive
its authors.

### Where does knowledge live — in heads or in the repository?

**Options:** (1) rely on the people who know; (2) require knowledge to live in
the repository — code, ADRs, runbooks, conventions.

**Trade-offs:** relying on people (option 1) is frictionless right up until
someone leaves, goes on vacation, or forgets, at which point the bus factor
bill comes due all at once. Codifying knowledge (option 2) costs ongoing
writing effort and discipline, and the writing has to be maintained — but it
is the only thing that makes a system robust to personnel change, which every
system eventually faces.

**Recommendation:** knowledge lives in the repository, always. This is
Chapter 03's repo-as-memory generalized from AI context to the whole team:
the repository is the single source of truth that both humans and AI sessions
read. A fact known only to a person is a fact the system does not reliably
have.

### What is worth documenting — the what or the why?

**Options:** (1) document what the code does; (2) document why it does it —
decisions, constraints, non-obvious gotchas.

**Trade-offs:** documenting the *what* (option 1) duplicates information the
code already carries, adds no understanding, and rots the moment the code
changes — stale "what" docs actively mislead. Documenting the *why* (option
2) captures the one thing the code cannot express — the reasoning, the
rejected alternatives, the constraint that explains a strange-looking choice
— and it stays valid far longer because rationale changes less often than
implementation.

**Recommendation:** document the why, relentlessly, and let the code speak for
the what. ADRs for decisions, comments for non-obvious constraints, runbooks
for operations. The Chapter 04 sync ADRs are exactly why that subsystem
survived Sara; the absence of an operations runbook is exactly why the
operational knowledge did not.

### How do you verify maintainability?

**Options:** (1) assume it, because the code looks clean; (2) test it with an
onboarding exercise — can a newcomer or a fresh AI session be productive from
the repository alone?

**Trade-offs:** assuming maintainability (option 1) is comfortable and
routinely wrong, because the author cannot see the gaps their own context
fills in invisibly. The onboarding test (option 2) costs a real exercise and
some ego, but it surfaces the exact knowledge that lives only in heads —
because it is precisely the questions the newcomer is forced to ask.

**Recommendation:** verify by onboarding, treating every question that only a
person could answer as a maintainability defect to be fixed in the repo.
Maintainability is claimed constantly and demonstrated rarely; the newcomer
(or the cold-start AI session) is the only honest judge.

### Should this code be maintainable at all?

**Options:** (1) invest in maintainability for everything; (2) invest
according to lifetime and change-frequency.

**Trade-offs:** investing everywhere (option 1) spends documentation and test
effort on throwaway prototypes and one-off scripts that will never be changed
— waste, and Chapter 05's over-investment in disguise. Investing by lifetime
(option 2) requires honestly predicting what will live and change, which is
imperfect, but it directs effort where the change-cost curve actually matters.

**Recommendation:** match maintainability investment to lifetime and interest,
exactly as with debt and simplicity. Long-lived, frequently-changed code (the
reconciliation engine) earns full investment; a genuinely disposable script
does not — provided you are honest about which is which, because prototypes
that survive quietly become the unmaintainable core.

## Trade-offs

Maintainability is the default goal for anything that lives, but it is not
free and not always the priority.

**It has an up-front cost that trades against shipping speed.** Tests, docs,
structure, and observability take time that could go to features. For
genuinely short-lived code — a prototype to be deleted, a one-off migration
run once — that investment is waste. Don't maintain what won't live; the
discipline is honesty about what actually won't live, since the graveyard of
unmaintainable systems is full of prototypes that were never deleted.

**Documentation carries its own maintenance cost.** Every document can go
stale, and a stale document is worse than none because it misleads with
authority. This is the reason to document the durable *why* (decisions,
constraints) rather than the volatile *what* (which the code shows and which
drifts): the why needs updating far less often, so it stays true.

**More testing and documentation is not always more maintainability.** A
hundred-percent coverage target that tests trivial getters, or an exhaustive
document nobody reads, is effort spent without buying changeability — and the
untouched tests and docs themselves become a maintenance burden. Maintainability
effort follows the same interest logic as debt (Chapter 05): invest where the
system actually changes, not uniformly.

**Maintainability can trade against performance and cleverness.** The most
maintainable version is sometimes not the fastest (Chapter 04) or the most
compact (Chapter 07). Where a measured performance need justifies a complex,
less-maintainable implementation, isolate it, document why, and cover it with
tests — pay the maintainability cost deliberately, in a contained place,
rather than spreading cleverness everywhere.

## Common Mistakes

**Optimizing for the first version, not the Nth change.** Judging code by how
fast it shipped rather than how the tenth modification will feel. It is the
root maintainability error, because it optimizes the cheap part of the
lifecycle and neglects the expensive part. Fix: evaluate every design by
imagining a stranger making the tenth change to it.

**Letting knowledge live in heads.** Critical decisions, operational
procedures, and system rationale existing only in individuals' memories — the
tribal knowledge that made Sara a single point of failure. Fix: move knowledge
into the repository as ADRs, runbooks, and conventions; treat a bus factor of
one as an incident waiting to happen.

**Documenting the what instead of the why.** Comments and docs that narrate
what the code does (`# loop over invoices`) rather than why it exists or what
constraint it satisfies. They add no understanding and rot immediately. Fix:
document rationale, constraints, and gotchas; delete comments that merely echo
the code.

**Treating tests and observability as optional.** Shipping code with no tests
(so every future change is scary and slow) or no observability (so production
behavior is unknowable) — both make code de facto unmaintainable regardless of
how it reads. Fix: treat testability and observability as parts of the
feature, not follow-ups; a change you cannot verify or observe is not done.

**Deferring maintainability to a "cleanup phase."** "We'll add tests and docs
later" — the later that never arrives (Chapter 05's debt denial, aimed at
maintainability). The cleanup phase is mythical; maintainability is a
continuous property or it is absent. Fix: build the maintainability artifacts
as you go, as part of the definition of done.

## AI Mistakes

The capstone AI risk is the one this whole chapter warns about: **AI produces
code faster than understanding accrues, and understanding is what maintenance
needs.** Each failure below is a way that generated code arrives without the
things that keep it maintainable. The countermeasure is to make maintainability
artifacts part of "done," so that both future humans and future AI sessions
can change what was generated.

### Claude Code: code born without its maintainability artifacts

Claude Code produces the implementation fluently, but unless asked, it omits
the things that make the implementation maintainable: the tests, the doc
update, the ADR for a decision it just made, the comment explaining a
non-obvious constraint. Because the code works, the missing scaffolding goes
unnoticed at merge — and the feature enters the codebase already
unmaintainable, understood only by a session that no longer exists.

**Detect:** a feature merged with no tests, no documentation change, and no
record of why its non-obvious choices were made. The question to ask of any
generated diff: "if this author vanished tomorrow, could someone else maintain
this?" — which, with an AI author, is literally what happens when the session
ends.

**Fix:** make the artifacts part of done, in `CLAUDE.md` and the definition of
done ([`templates/claude-md-starter.md`](../../templates/claude-md-starter.md)):

> A feature is not complete without: tests for its behavior, updated docs for
> anything user- or developer-facing, and a recorded rationale (comment or
> ADR) for any non-obvious decision. Produce these alongside the code, not on
> request.

### GPT: documenting the what, not the why

Ask a GPT-family model to "add comments" or "document this," and it will
narrate the code — a comment per line restating what that line does, a
docstring that repeats the function signature. This is documentation debt: it
adds volume without understanding, and it goes stale the instant the code
changes, at which point it misleads. The one thing maintenance needs — the
*why* — is exactly what it omits.

**Detect:** comments that echo the code (`# increment the counter`),
docstrings that restate parameter names, and a complete absence of rationale,
constraints, or "this looks wrong but is deliberate because…". Volume of
comments with no gain in understanding is the tell.

**Fix:** ask specifically for the why, which is the part it will not produce
by default:

> Do not describe what the code does — the code shows that. Document why this
> exists, what constraint or decision it reflects, what would break if someone
> changed it, and any non-obvious gotcha. Skip anything the code already makes
> clear.

### Cursor: consistency erosion over time

Because inline assistance follows the immediate local context rather than a
global standard, a codebase edited this way slowly accumulates divergence —
three different error-handling styles, two date libraries, a different naming
convention per file — since each edit is locally reasonable but globally
inconsistent. Every inconsistency raises the cognitive load for every future
maintainer, who must now learn N patterns where one would do. It is a slow,
compounding tax that no single edit is ever large enough to trigger a review
of.

**Detect:** multiple ways of doing the same thing across the codebase, and new
code that matches its immediate neighbors rather than the project's intended
standard. The fingerprint is a system where you must ask "which pattern does
*this* part use?" before making a change.

**Fix:** enforce a single standard from outside the local context — conventions
in `CLAUDE.md`, linters and formatters in CI, and a canonical reference file —
and review for consistency, not only correctness:

> Follow the project's established conventions for error handling, naming, and
> structure (see `CLAUDE.md` and `services/billing.py`), even where the file
> you are editing does something different.

Turned the other way, AI is the strongest maintenance tool available: it reads
and explains legacy code, writes the missing tests, drafts the runbooks and
ADRs (as it did for Sara), and refactors toward consistency — but only in a
repository maintainable enough to give it the context. A maintainable codebase
is one an AI can help maintain; an unmaintainable one defeats the human and the
assistant alike.

## Best Practices

**Optimize for the Nth change.** Aim for a flat change-cost curve: judge every
design by how a stranger will experience the tenth modification, not by how
the first version felt to write. This single reframing drives most of the
other practices.

**Put knowledge in the repository, not in heads.** ADRs for the why
([`templates/adr.md`](../../templates/adr.md)), runbooks for operations,
`CLAUDE.md` for conventions — kill the bus factor by making the repository the
source of truth that both people and AI sessions read (Chapter 03). Capture
departing knowledge before it leaves, and use an assistant to make that
capture fast.

**Document the why; prune the what.** Record decisions, constraints, and
gotchas close to the code, and delete or avoid documentation that merely
restates the code — because stale "what" docs are worse than none. Keep docs
near what they describe so they are updated together.

**Make testability and observability first-class.** Tests are what make change
safe and therefore cheap; observability is what makes production behavior
understandable when it breaks. Treat both as parts of the feature, and pair
observability with a runbook so the system explains itself to someone who
isn't its author.

**Verify with the onboarding test.** Periodically hand a real task to a
newcomer — or a fresh AI session — and require it to be done from the
repository alone, treating every question only a person could answer as a
maintainability defect to fix. Claimed maintainability is worthless;
demonstrated maintainability is the goal.

## Anti-Patterns

**The Hero (bus factor of one).** One person who holds a system in their head
and can change it faster than anyone else — which feels like productivity and
is actually a single point of failure. The hero is a bottleneck for every
change and a crisis waiting for their resignation. The tell: a subsystem only
one person ever touches, and a team that routes all its questions to one desk.

**Tribal Knowledge.** Critical decisions and operational procedures that live
only in conversations, memories, and Slack history — never written into the
repository. It works until the person or the message is gone. The tell:
recovering from a known failure requires asking a specific human how.

**Write-Only Code.** Code optimized entirely for the speed of writing it, with
no thought for the many future readings — the opposite of code as
communication. It is cheap to produce and ruinous to maintain. The tell: code
its own author cannot explain a month later.

**Documentation Theater.** Extensive documentation that is out of date, so it
misleads with the authority of officialness — worse than no docs, because
people trust it. The tell: a wiki full of pages last updated two rewrites ago,
describing a system that no longer exists.

**Maintainability Later.** Deferring tests, docs, and structure to a future
cleanup phase that never comes, treating maintainability as a project rather
than a continuous property (Chapter 05's debt denial in a new costume). The
tell: "we'll add tests once it stabilizes," said about code that has been in
production for a year.

## Decision Tree

"I'm about to ship a change — is it maintainable enough?"

```
Will this code live beyond a throwaway / prototype horizon?

├── NO (genuinely disposable — deleted after use, run once)
│        └──► Don't over-invest. Ship it, and mark it disposable so it
│             can't quietly become the permanent core (Chapter 01).
│
└── YES (it will live and be changed)
    │
    Could someone OTHER than me understand and safely change it?
    │   (readable, low coupling, covered by tests)
    │
    ├── NO ──► Not done. Clarify it and add the tests that make change safe
    │          before shipping.
    └── YES
        │
        Is the WHY recorded for every non-obvious decision or constraint?
        │
        ├── NO ──► Record it (comment for a local constraint, ADR for a
        │          real decision). The code shows what; you must supply why.
        └── YES
            │
            If this touches operations: can its production behavior be
            understood, and is recovery documented?
            │
            ├── NO ──► Add observability (structured logs/metrics) and a
            │          runbook line for "what to check when this breaks."
            └── YES
                │
                Does any critical knowledge about this live ONLY in my head?
                │
                ├── YES ──► Put it in the repository. Bus factor is a defect.
                └── NO ───► Verify: could a newcomer or a fresh AI session
                            maintain this from the repo alone? If not, the
                            gap they'd hit is your remaining work.
```

The most-skipped branch is the last question. Teams declare code maintainable
from the author's chair, where all the missing context is silently supplied by
the author's own memory — the only honest test is whether someone without that
memory can succeed.

## Checklist

### Maintainability Judgment Checklist — before shipping durable code

- [ ] I judged this by how the Nth change will feel to a stranger, not by how the first version felt to write.
- [ ] Someone other than me could understand and safely change this — it is readable and covered by tests.
- [ ] The *why* is recorded for every non-obvious decision or constraint (comment or ADR), not just the *what*.
- [ ] Operational code is observable and has a runbook for "what to check when it breaks."
- [ ] No critical knowledge about this lives only in my head; it is in the repository.
- [ ] Maintainability investment matches the code's lifetime and change-frequency — not uniform, not deferred to "later."
- [ ] I could hand this to a newcomer or a fresh AI session and they could maintain it from the repo alone.

### Code Review Checklist — maintainability in the diff

- [ ] If the author vanished tomorrow, could someone else maintain this change?
- [ ] Behavior is covered by tests that would fail if it broke — change is verifiable.
- [ ] Documentation and comments capture why, not what, and no stale docs were left behind.
- [ ] The change follows the project's established conventions (no consistency erosion — no new pattern for a solved problem).
- [ ] Non-obvious decisions are recorded (comment or ADR), so they won't be re-litigated or accidentally reverted.
- [ ] AI-generated code arrived with its maintainability artifacts (tests, why-docs), not just a working happy path.

## Exercises

As before, these produce artifacts — do them in writing. This is the last set
in Stage 1; the third exercise is deliberately a test of the whole stage.

**1. The bus-factor audit.** List the systems or areas you work in, and for
each, honestly assess how many people could maintain it and what knowledge
lives only in heads. The artifact is the map plus the single highest-risk
knowledge concentration you found, and a concrete plan to move that knowledge
into the repository before the person holding it is unavailable.

**2. The Nth-change diagnosis.** Pick a piece of code you have changed several
times and reconstruct its change-cost trend: is the curve flat or rising? If
rising, name what is driving it — coupling, missing tests, absent docs,
knowledge concentration. The artifact is the diagnosis plus the one change to
the code or its documentation that would most flatten the curve.

**3. The onboarding test.** Hand a real task in an unfamiliar-to-them part of
the system to a teammate — or a fresh AI session — and require it to be done
using only the repository, logging every question they have to ask a person.
Each question is a maintainability gap. The artifact is the question log turned
into repository changes (docs, ADRs, `CLAUDE.md` entries, runbook lines) that
would have answered them — which is Stage 1's entire mindset, applied to your
own system: think about the change over time, for the person who comes after.

## Further Reading

- **Software Engineering at Google** (Winters, Manshreck, Wright — free
  online), especially the opening chapters on sustainability and "programming
  over time" — the industrial-scale argument that maintainability
  (sustainability) is the defining discipline of software engineering, not an
  add-on. The natural capstone read for Stage 1.
- **Refactoring** (Martin Fowler, 2nd edition) — the mechanics of keeping code
  maintainable through disciplined, behavior-preserving change, and the
  vocabulary of "code smells" for naming what is degrading before it becomes a
  crisis.
- **Accelerate** (Nicole Forsgren, Jez Humble, Gene Kim) — the research linking
  loosely-coupled, maintainable systems and practices to delivery performance.
  Read it for the evidence that maintainability is an economic property with
  measurable payoff, not an aesthetic preference.
- **Site Reliability Engineering** (Google, free online), the chapters on
  monitoring, runbooks, and postmortems — the operational half of
  maintainability that pure code-quality writing tends to miss: making a
  system observable and its recovery knowable, which is exactly the gap Sara's
  departure exposed.

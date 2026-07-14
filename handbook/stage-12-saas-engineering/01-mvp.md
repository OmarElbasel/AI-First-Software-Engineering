# MVP

## Introduction

MVP is the "scalability" of product vocabulary: a precise term ground down by misuse until it
mostly means "the version we didn't finish." In roadmap meetings it means "v1, but we cut
corners." In investor decks it means "the demo." In its actual engineering sense it means
something narrower and more useful: **the smallest product that tests whether anyone wants —
and will pay for — the thing you believe they want**. An MVP is not a small product. It is an
experiment wearing a product's clothes, and its output is not revenue or users — it is a
validated (or demolished) belief.

That definition does real work, because it forces three questions that "let's ship an MVP"
skips. What, exactly, is the belief being tested — who has what pain, and what would they pay
to make it stop? What is the smallest artifact that produces a real answer — not a survey
answer, not a signup, but behavior with cost attached? And what result would make you stop —
because an experiment without a failure condition is not an experiment, it is a commitment
with extra steps.

This chapter is the judgment layer for the whole stage. The six chapters after it each build
a system around a product that has found demand — pricing models, billing, analytics,
feedback, metrics, growth loops. This one teaches the discipline that decides whether those
systems have anything to serve: name the riskiest assumption, ship the smallest thing that
tests it, and read the answer honestly. It is a conceptual chapter because the scarce skill
has never been building the MVP — least of all now, when AI assistants can scaffold a SaaS in
a weekend. The scarce skill is deciding what *not* to build, and having the nerve to charge
money for what remains.

## Why It Matters

- **Building the wrong product is the dominant failure mode of software businesses.** Not
  outages, not scaling, not technical debt — products nobody wanted, discovered after the
  runway paid for them. Post-mortem surveys of failed startups put "no market need" at or
  near the top every year. Every engineering virtue taught in Stages 1–11 is worthless when
  applied to software without demand.
- **AI has made over-building cheap, which makes it epidemic.** When a full SaaS scaffold —
  auth, orgs, roles, billing stubs, admin panel — costs a weekend of assistant-driven work,
  the natural check on scope ("we don't have time to build that") is gone. The constraint
  that used to force focus must now be supplied by judgment, because the tools will no longer
  supply it by friction.
- **The MVP decides what you learn, and learning speed compounds.** A team that ships a
  demand test in six weeks gets eight learning cycles in the time a team shipping "v1 done
  right" gets one. The second team's single data point arrives after every architectural
  decision has already been made — and made for a product that may not survive contact with
  its market.
- **Scope discipline is an engineering skill, not a product-manager courtesy.** The engineer
  decides, line by line, whether the invoice feature needs multi-currency now, whether plans
  need an enum or a table, whether "we might need it" becomes a schema column. Stage 1's
  simplicity and product-thinking chapters taught the mindset; the MVP is where it faces its
  hardest test, because every cut feels like professional negligence and most of them aren't.
- **The cuts you get wrong are expensive in both directions.** Cut viability — the core path
  is broken, insecure, or legally unusable — and the experiment returns a false negative:
  demand existed, but the artifact was too broken to detect it. Refuse to cut anything and
  the experiment never runs. Knowing *which* corners are structural is the chapter's central
  judgment.

## Mental Model

Three ideas carry this chapter: an MVP is an experiment, "minimum" and "viable" are both
load-bearing, and scope is cut by narrowing, never by thinning.

**1. An MVP is an experiment with a hypothesis, an instrument, and a failure condition.**
Write the hypothesis the way you'd write a test case:

```
DEMAND HYPOTHESIS (Invoicely's original, as an example)
  WHO        freelancers and 1–10 person agencies
  PAIN       invoices are paid late; chasing them is unpaid,
             awkward work that founders do at 11pm
  BELIEF     they will pay ~$15/month for invoicing that
             measurably shortens time-to-paid
  RISKIEST   not "can we build invoicing" (we obviously can) —
  ASSUMPTION but "is late payment painful enough to PAY for,
             when free templates and Word exist"
  TEST       50 paying customers within 90 days of launch
  KILL       <10 paying customers after 90 days and two
             pricing/message iterations → stop or re-aim
```

The riskiest assumption decides the shape of the MVP. If the risk is demand, the MVP tests
willingness to pay. If the risk is technical feasibility (rare in CRUD SaaS, real in AI or
hardware products), the MVP is a feasibility spike instead. Most teams test the assumption
that is easiest to test — "can we build it" — precisely because it is the one that is never
in doubt.

**2. Minimum and viable are both load-bearing, and they fail differently.** Violate
*minimum* and the experiment is slow and expensive — you learn the same answer a year later.
Violate *viable* and the experiment lies — the artifact was too broken, ugly, or illegal to
detect the demand that existed. Viable has a precise meaning: **the core value path works
completely and trustworthily for the target user**. For a product that touches money, viable
includes getting the money right. For a product holding business data, it includes not
leaking it. Viability is judged on the core path only — everything off that path can be
absent, manual, or embarrassing.

**3. Cut scope by narrowing, never by thinning.** The classic failure is building v1 with
every planned feature present but shallow — ten features at 30% depth, none of them complete
enough to rely on. The discipline is the opposite: one path at 100% depth, everything else at
zero:

```
THINNING (wrong)                    NARROWING (right)
every feature, none complete        one complete loop, nothing else

invoices     ▓▓▓░░░░░░░             invoices      ▓▓▓▓▓▓▓▓▓▓
clients      ▓▓▓░░░░░░░             send + pay    ▓▓▓▓▓▓▓▓▓▓
estimates    ▓▓░░░░░░░░             reminders     ▓▓▓▓▓▓▓▓▓▓
expenses     ▓▓░░░░░░░░             estimates     (absent)
time-track   ▓▓░░░░░░░░             expenses      (absent)
reports      ▓░░░░░░░░░             time-track    (absent)
portal       ▓▓░░░░░░░░             reports       (absent)

nothing works well enough           the one thing it does,
to depend on → user leaves          it does completely →
→ experiment reads "no demand"      the experiment measures demand,
   even when demand existed            not brokenness
```

Narrowing has an engineering counterpart: the *walking skeleton* — the thinnest end-to-end
slice that exercises the whole stack (UI → API → database → email → payment) in production.
Once one loop runs end to end for real users, every later feature is an increment; until it
does, everything is theory. And narrowing has one exception, inherited from Stage 11: the
**one-way doors stay open regardless of scope** — tenant keys on every table, real
authentication, externalized state, money handled correctly. These cost near-zero at MVP size
and a rewrite later; they are not scope, they are structure.

A working definition:

> **An MVP is the smallest product that tests your riskiest assumption against real user
> behavior — complete and trustworthy on its one core path, deliberately absent everywhere
> else, with success and kill criteria written down before launch, and with the one-way
> structural doors held open even when today's scope doesn't need them.**

## Real-World Scenario

**The setup.** Two people start Invoicely: a founder who ran a design agency and hated
Fridays (invoice-chasing day), and one engineer. The founder's vision document lists what
"real" invoicing products have: invoices, estimates, expenses, time tracking, client portal,
reports, multi-currency, mobile apps, template designer. An assistant, prompted with "build
an invoicing SaaS," happily scaffolds most of it in a week — models, endpoints, admin panel,
empty screens for everything. Estimated time to finish it all properly: nine months.

**The reframe.** The engineer forces the experiment question: what belief, if wrong, kills
this company? Not "can we build invoicing" — Word can build invoicing. The bet is that *late
payment* is painful enough that small agencies will pay a subscription to shorten it. That
hypothesis names the MVP: the loop that gets an invoice created, delivered, *paid*, and
chased. Nothing else touches the bet.

**What shipped in six weeks.** Create an invoice (line items, tax, logo). Send it as an
email with a hosted payment link (Stripe Checkout — no card handling in-house, per Stage 1's
build-vs-buy judgment). Automatic reminders at +7/+14/+21 days, the feature the founder was
doing by hand at 11pm. A list showing paid/unpaid/overdue. Pricing from day one: $15/month
after a 14-day trial, because the hypothesis is *will they pay*, and a free product tests a
different, easier, nearly worthless hypothesis. Everything else: absent. No estimates, no
expenses, no portal, no templates, one currency, and onboarding done by the founder
personally over a call — a manual step, documented, with a trigger ("automate at 20
signups/week").

**What stayed rigorous anyway.** Four things were built to the standard of Stages 3, 6, and
9 despite the deadline: tenancy (`tenant_id` on every table — the door that never reopens
cheaply), authentication (real password hashing and sessions, not the scaffold's demo auth),
money integrity (amounts in integer cents, invoice state transitions constrained in the
database, Stripe as the source of truth for payment status), and nightly tested backups. The
engineer's rule: *the experiment may fail, but it must not fail because we lied to the user
about their data or their money.*

**What the experiment returned.** Three findings, none of which were in the vision document.
First: reminders were the product. Trial users mentioned them unprompted; two asked to pay
early for them; the marketing message changed from "beautiful invoicing" to "get paid
faster" — which became the pricing anchor Chapter 02 builds on. Second: the dashboard nobody
asked about was ignored — weeks of planned reporting work, deleted from the roadmap by one
month of analytics. Third: a genuine viability miss — sequential, gap-free invoice numbering
is a legal requirement for businesses in much of the EU, and Invoicely's random IDs made it
*legally unusable* for a third of its trial signups. That cut had felt like scope; it was
viability, on the core path, for a definable segment. It shipped as a fix within three
weeks, and the lesson entered the team's review vocabulary: **a cut that makes the core loop
unusable for a target segment is not a cut, it is a defect in the experiment.**

**The outcome.** 61 paying customers at day 90 — hypothesis validated, kill criteria
retired. The nine-month vision was eventually built, feature by feature, each one justified
by the feedback and metrics systems this stage builds in Chapters 04–06 — and two of its
features (the portal, time tracking) were never built at all, because the data never asked
for them.

## Engineering Decisions

### What is the riskiest assumption, and does the MVP actually test it?

List the assumptions the business rests on — someone has this pain, they'll pay this much,
we can reach them, we can build it, it's legal — and rank by (probability of being wrong ×
cost if wrong). The MVP is aimed at the top of that list. For most SaaS, feasibility is
near-certain and demand is the risk, so the MVP must include the payment moment; a free beta
defers the only question that matters. The common evasion is testing a *proxy* — signups,
waitlists, "would you use this?" surveys — because proxies always say yes. Behavior with
cost attached (money, time, data migration) is the only signal that doesn't flatter.

### What does "viable" include for this product?

Derive it from the core loop and the target user, and write it down — it is the
non-negotiable list the deadline cannot touch. For Invoicely: money correctness, tenant
isolation, real auth, deliverable email, legal invoice numbering (learned the hard way).
Almost always on the list: the security basics (Stage 9's mindset chapter — breach at 50
users kills the company as surely as at 50,000), data integrity, and honest failure (an
error the user sees beats silent corruption). Almost never on the list: performance beyond
"not embarrassing," admin tooling, configurability, every browser, mobile.

### Manual behind the curtain, or automated?

Every operation the MVP needs is a candidate for a human doing it by hand: onboarding,
plan changes, refunds, data import, even the "algorithm" itself (concierge MVPs). Manual is
almost always right first — it costs nothing to build, teaches you the real requirements
before you automate the wrong thing, and puts founders in direct contact with users. The
discipline is the **manual-ops ledger**: every manual step documented with who does it, how
long it takes, and the volume trigger at which it gets automated. Manual steps without
triggers silently become the ops team's permanent job.

### When do we charge?

From the first real user, with rare exceptions (marketplaces needing liquidity, products
whose value needs weeks to demonstrate — and then a time-boxed trial, not a free tier). The
objection "charging will scare users away" describes the experiment working: users scared
away by a price were never customers, and counting them as validation is how teams reach
10,000 users and zero revenue. Free tiers are a *pricing* decision (Chapter 02 gives them
their real job); at the MVP stage they are usually an anesthetic for the fear of hearing
"no."

### What are the success and kill criteria — decided when?

Before launch, in writing, with numbers and a date: "50 paying customers in 90 days;
fewer than 10 after two iterations → stop or re-aim." Deciding after launch guarantees the
goalposts move — every founder can narrate 12 lukewarm users into "early traction." The
criteria are not a suicide pact; they are a tripwire forcing an honest conversation at a
predetermined time, against predetermined numbers, instead of a slow bleed of "one more
feature will fix it."

### When does the MVP stop being the MVP?

The label expires when the hypothesis is answered. Validated → the codebase is now a young
production system: the manual-ops ledger starts converting to automation, the deferred
features compete for a roadmap driven by Chapters 04–06's data, and any genuine shortcuts
get scheduled — as Stage 1's technical-debt chapter demands, on a list, not in folklore.
Killed → the discipline that kept it small is what makes stopping affordable. The worst
outcome is the unkillable zombie: too much sunk cost to stop, too little demand to grow —
usually the product of an MVP that took nine months.

## Trade-offs

| Choice | You gain | You pay |
|---|---|---|
| Narrow scope (one complete loop) | Fast, honest demand signal; a product users can rely on | Feels unambitious; some prospects need a missing feature and bounce |
| Broad scope ("thin v1") | Demos well; satisfies stakeholder wish lists | Nothing complete enough to depend on; experiment measures brokenness, not demand |
| Charging from day one | Tests the real hypothesis; every user is a validated data point | Smaller numbers; bruising feedback; no vanity-metric comfort |
| Free beta first | Volume, buzz, gentler feedback | Tests "will people use a free thing" (answer: always yes); demand question merely deferred, at full price |
| Manual ops behind the curtain | Weeks of build time saved; requirements learned before automating | Founder time consumed; breaks without a documented automation trigger |
| Automating from the start | Scales without ops pain | Automates guesses; the wrong workflow, built twice |
| One-way doors kept open (tenancy, auth, money, state) | Later scale is refactoring, not rewriting | Days of discipline the demo didn't strictly need |
| "It's a throwaway, skip the doors" | The absolute fastest demo | If the product lives, the retrofit (tenancy above all) is the worst migration in SaaS |
| Written kill criteria | Honest stopping point; cheap failure | Confronting; removes the comfort of perpetual "early days" |
| "We'll know it when we see it" | Never have to face a number | Goalposts walk; the zombie product eats years |

The narrowing trade-off deserves its sharp edge: **the prospects you lose to a missing
feature are visible and vocal; the signal you lose to ten shallow features is invisible** —
it just reads as "no demand," and you never find out the demand was there.

## Common Mistakes

- **Testing "can we build it" instead of "does anyone want it."** The default failure,
  because building is the assumption engineers can retire with confidence and enjoy
  retiring. If the riskiest assumption is demand, an MVP without a price on it is aimed at
  the wrong target.
- **Thinning instead of narrowing.** Every roadmap feature present at 30% depth. The tell in
  planning: scope negotiations that make every feature smaller instead of deleting features
  whole.
- **Counting signups as validation.** Signups measure curiosity plus marketing spend.
  The metrics that carry signal have cost attached: paid conversions, week-4 retention,
  users who did the core action twice (Chapter 06 makes these precise).
- **Cutting viability and calling it scope.** Demo-grade auth, floats for money, missing
  legal requirements (Invoicely's invoice numbering). The test for any cut: *does the core
  loop still work completely and trustworthily for the target user?* If no, it isn't a cut.
- **The perpetual private beta.** Six months of "polishing" with twenty hand-picked friendly
  users — a structure for avoiding the answer. Friendly users are kind; the market is not;
  only the market's answer counts.
- **No kill criteria.** Without pre-committed numbers, every result reads as "promising."
  The absence of a failure condition converts the experiment into a belief system.
- **Treating MVP code as disposable — in either direction.** "It's throwaway" justifying
  skipped tenancy and fake auth (it won't be thrown away if it works); or, equally wrong,
  gold-plating every corner as if the product were already validated. The resolution is the
  viability list: rigor exactly where the list says, speed everywhere else.
- **Scoping by committee.** The MVP as the union of every stakeholder's minimum — sales
  needs SSO, the founder needs the dashboard for demos, marketing needs the blog. Union
  scoping produces the thin v1. The hypothesis, not the org chart, owns the scope.

## AI Mistakes

The three tools fail differently here, and all three failures push in the same direction:
more product than the experiment needs, sooner than the evidence justifies.

### Claude Code: the scope creep of competence

Asked to "build an invoicing MVP," Claude Code produces a *good SaaS* — which is precisely
the problem: organizations and role management, a settings area, an audit log, estimates
"since they share the invoice model," an admin panel. Each addition is well-built and
individually defensible, none was ordered, and collectively they turn a six-week experiment
into a four-month product. Scope inflates through competence, not error — every diff passes
review because reviewers evaluate code quality, not hypothesis relevance.

**Detect:** features appearing in plans or PRs that no line of the hypothesis requires; the
plan for "MVP" that contains an admin panel. **Fix:** give the assistant the hypothesis
document and an explicit not-list ("no orgs, no roles, no estimates, no admin — reject these
even if convenient"), and add a scope gate to review: every feature in the diff names the
assumption it tests. CLAUDE.md is the right home for the not-list, per Stage 10's context
discipline.

### GPT: market validation from a mirror

Asked "is this a good MVP for freelancer invoicing?", GPT validates warmly and specifically —
"freelancers struggle with late payments and would value automated reminders; consider
adding expense tracking, which users in this segment frequently request." It reads like
user research. It is pattern-matched plausibility: no user was consulted, the "frequent
requests" are invented, and the enthusiasm is uniform across good and bad ideas — ask it to
validate the opposite positioning and it will. Teams have substituted this for customer
conversations because it is instant and always encouraging.

**Detect:** demand claims with no named source; advice that adds features while validating
the ones you listed; enthusiasm invariant under contradiction (test it: pitch the reverse).
**Fix:** never accept demand signal from a model. Use it for what it is good at here —
sharpening the hypothesis statement, drafting interview scripts that avoid leading
questions (The Mom Test's discipline), listing assumptions you haven't named — and get the
answer from users with money.

### Cursor: infrastructure for decisions not yet made

Mid-file, Cursor autocompletes the future: a `currency` column and conversion helper on the
money type, `PlanTier` enums with four tiers, an i18n wrapper around UI strings, a
`feature_flags` table — because the code around a SaaS model statistically has these. Each
lands silently inside an unrelated diff. None is today's decision: pricing tiers are Chapter
02's job *after* validation, multi-currency was explicitly cut, i18n is a market-expansion
decision. The MVP accretes configuration surface for products it may never become — every
option a small tax on reading, testing, and changing the code.

**Detect:** columns, enums, and config for features on the not-list; abstractions with one
caller and speculative parameters; diffs that mention currencies or locales in a
single-currency product. **Fix:** review generated code against the not-list, not just for
correctness; delete speculative generality on sight (Stage 1's simplicity chapter — YAGNI is
a review criterion, not a mood), and keep the one-way-door list as the *only* sanctioned
future-proofing.

## Best Practices

- **Write the hypothesis as one page, and let it own the scope.** Who, pain, belief, riskiest
  assumption, test, kill criteria — the format from the Mental Model. Every scope debate
  reduces to "which assumption does this feature test?" A feature that tests nothing waits.
- **Build the walking skeleton first.** The thinnest end-to-end slice — one invoice, created,
  emailed, paid, in production — before any feature grows sideways. It forces the deployment,
  email, and payment plumbing to exist on week one, and it converts every later debate into
  "extend the loop or not."
- **Keep the viability list and the not-list as first-class documents.** One page each: what
  must be production-grade regardless of deadline; what is banned regardless of convenience.
  Both go into CLAUDE.md so the assistants inherit the constraints (Stage 10 Ch 03).
- **Charge real money from the first real user.** The price can be wrong (Chapter 02 fixes
  prices); the *presence* of a price is the experiment. A validated $15/month is worth more
  than ten thousand free signups.
- **Run the manual-ops ledger.** Every human-in-the-loop step: owner, cost, automation
  trigger. Review it monthly. It is the difference between "doing things that don't scale"
  as a strategy and as a surprise.
- **Instrument from day one, minimally.** A handful of events on the core loop — signed up,
  first invoice sent, first invoice paid, reminder fired (Chapter 04 designs this properly).
  The MVP's entire purpose is learning; an unobserved experiment produces anecdotes.
- **Talk to every early user, personally.** At MVP volume this is possible and it is the
  densest signal you will ever get — Invoicely's "reminders are the product" finding came
  from calls, not dashboards. Chapter 05 systematizes this; at this stage, just do it.
- **Time-box the build and honor the box.** Six weeks that ship beat six months that
  polish. The deadline is the mechanism that forces narrowing; without it, viable quietly
  inflates back into complete.

## Anti-Patterns

- **The nine-month MVP.** The full vision, renamed. The tell: the "MVP" roadmap has phases.
  Its cost is not just time — it makes every architectural decision before the market has
  voted on any of them.
- **The demo MVP.** Built to impress in a 10-minute pitch — screens over substance, seeded
  data, happy path only. It optimizes for the audience that doesn't pay (investors,
  stakeholders) and is unusable by the audience that does. Real users retention-test it in
  minutes.
- **The perpetual beta.** "We'll charge when it's ready" — a fear of the answer, dressed as
  diligence. Ready is a decision, not a state; the market defines it, and only when asked.
- **The Franken-MVP that never converts.** Airtable + Zapier + a Stripe payment link is a
  legitimate day-one experiment — but it has a breaking volume, and without a written
  migration trigger the duct tape becomes the production system, discovered at 2am when the
  Zap silently stops. Prototype tools need the same ledger-and-trigger discipline as manual
  ops.
- **"Security and correctness come after validation."** Plaintext passwords, floats for
  money, no tenancy "for now." This is not lean; it is a defect in the experiment (a product
  users can't trust returns a false negative) and a bet that the retrofit will be affordable
  (it won't; tenancy retrofits are legendary for a reason).
- **The pivot loop.** Kill criteria hit → rather than stopping, the product "pivots" —
  keeping the codebase, the assumptions, and the sunk cost while renaming the target user.
  A real pivot re-runs this chapter from the hypothesis line; if the new experiment wouldn't
  choose this codebase, the codebase is not a reason.
- **Validation theater.** Waitlists, LOIs from friends, upvotes, an assistant's enthusiasm —
  everything that resembles demand except behavior with cost attached. Its defining feature:
  it cannot say no.

## Decision Tree

```
"Should this go into the MVP?" — for each proposed feature/task
│
├─ Does the demand hypothesis exist in writing, with a
│  riskiest assumption and kill criteria?
│   ├─ NO → STOP. Write it first. Scope decisions without a
│   │        hypothesis are taste contests.
│   └─ YES ↓
├─ Does this feature test the riskiest assumption — is it
│  part of the one core loop?
│   ├─ YES → In. Build it COMPLETE (viable = trustworthy
│   │        end-to-end on this path).
│   └─ NO ↓
├─ Is it on the viability list — security, data integrity,
│  money correctness, legal usability for the target segment?
│   ├─ YES → In, at production grade. The deadline moves
│   │        before this does.
│   └─ NO ↓
├─ Is it a one-way door (tenant keys, real auth, external
│  state, queued work — Stage 11 Ch 01's list)?
│   ├─ YES → In, as structure, at near-zero current cost.
│   └─ NO ↓
├─ Can a human do it manually behind the curtain?
│   ├─ YES → Manual. Add to the ops ledger with an
│   │        automation trigger. Build nothing.
│   └─ NO ↓
└─ Out. Onto the not-list, with the assumption it WOULD test
   noted — the post-validation roadmap (Chs 04–06 data
   deciding) is where it competes for life.

"The MVP has been live for a while" —
├─ Success criteria met → hypothesis validated. Retire the
│   label: schedule the shortcuts, automate per the ledger,
│   proceed to pricing/payments/analytics (Chs 02–04).
├─ Kill criteria hit → run the honest conversation the
│   numbers pre-committed you to. Stop, or re-aim with a NEW
│   hypothesis document (a pivot keeps the discipline, not
│   necessarily the code).
└─ Neither, still inside the window → iterate on message and
    price before adding features; talk to the users you have.
    Adding features is the LAST lever, not the first.
```

## Checklist

### Engineering Judgment Checklist

- [ ] The demand hypothesis is written: who, pain, belief, riskiest assumption, success
      test, kill criteria — with numbers and dates, before launch.
- [ ] The MVP tests the *riskiest* assumption, not the most testable one — for most SaaS,
      that means a price is attached from the first real user.
- [ ] Scope was narrowed (features deleted whole), not thinned (features made shallow); the
      core loop works completely, end to end, in production.
- [ ] The viability list exists: security basics, data integrity, money correctness, and
      legal usability for the target segment are production-grade regardless of deadline.
- [ ] The not-list exists and is enforced in review — including against AI-generated scope.
- [ ] One-way doors are open: tenant keys on every table, real auth, no in-process state,
      background work queued (Stage 11 Ch 01's early-decisions list).
- [ ] Every manual operation is in the ops ledger with an owner and an automation trigger;
      every prototype tool has a migration trigger.
- [ ] The core loop is instrumented — the handful of events that measure the hypothesis.
- [ ] Success and kill criteria have a calendar date attached, and someone is assigned to
      call the result.
- [ ] Post-validation debts (skipped automation, deferred hardening) are on a written list,
      not in folklore.

### Code Review Checklist

- [ ] Every feature in the diff maps to the hypothesis, the viability list, or a one-way
      door — anything else is scope creep, however well-built.
- [ ] No speculative generality: no columns, enums, flags, or abstractions for not-list
      features (multi-currency, tiers, i18n) — YAGNI is a review criterion here.
- [ ] Money is integer cents; invoice/payment state transitions are constrained; external
      payment state has a single source of truth.
- [ ] `tenant_id` is present and enforced on every new table and query (Stage 3 Ch 04's
      authorization discipline).
- [ ] Auth, session, and password handling meet Stage 9 basics — no demo-grade auth behind
      a "beta" excuse.
- [ ] Errors on the core path are honest and visible — no silent failure between "user
      clicked send" and "client received invoice."
- [ ] AI-generated diffs were reviewed for scope (features added) and speculation (config
      added), not just correctness.

## Exercises

1. **Write the hypothesis document.** For a product you want to build (or rewrite
   Invoicely's from the scenario): who, pain, belief, riskiest assumption, success test,
   kill criteria — one page. Then list five assumptions you made *while writing it* and rank
   them by (chance wrong × cost if wrong). Check: does your planned MVP test the top one?
2. **Run the narrowing exercise on a real v1.** Take a product you know (your own, or a
   public product's earliest version via the Wayback Machine). List its launch features.
   Identify the core loop. Mark every feature as loop / viability / one-way door / should
   have been absent. Estimate what fraction of the build effort the last category consumed.
3. **Audit an AI-generated MVP for scope.** Prompt an assistant to "build an MVP for
   [your hypothesis product]" and let it plan freely. Then review the plan with this
   chapter's decision tree: mark every item in / viability / door / out. Count the "out"
   items and estimate the weeks they would have cost. Re-prompt with the hypothesis and
   not-list, and compare plans.
4. **Design the manual-ops ledger.** For your MVP, list every operation a human could do by
   hand instead of building software: onboarding, imports, refunds, support, even the core
   service itself. For each: owner, minutes per occurrence, and the weekly volume at which
   it must be automated. Identify which single ledger entry buys the most build-time
   savings.
5. **Write the kill memo in advance.** Before launching (or as a drill), write the memo you
   would send if the kill criteria hit: what was believed, what the numbers said, what was
   learned, what happens to the code and the customers. If writing it feels impossible, the
   criteria aren't real yet — revise them until the memo is writable.

## Further Reading

- Eric Ries — *The Lean Startup* — the origin of MVP as *experiment*: build–measure–learn,
  validated learning, and innovation accounting. Read it for the epistemology, not the
  jargon that later diluted it.
- Rob Fitzpatrick — *The Mom Test* — how to talk to users so their politeness doesn't
  poison your data; the antidote to validation theater (and to GPT's warm nothing).
- Paul Graham — "Do Things That Don't Scale" — the canonical case for manual ops and
  concierge onboarding as strategy, from Airbnb and Stripe's early history.
- Henrik Kniberg — "Making sense of MVP" — the skateboard→bicycle→car essay; the
  narrowing-vs-thinning picture, drawn by the person who drew it first.
- Marty Cagan — *Inspired* — product discovery and the four risks (value, usability,
  feasibility, viability); the mature framework this chapter's hypothesis document
  compresses.
- Teresa Torres — *Continuous Discovery Habits* — what "talk to users every week" looks
  like as a system; the bridge from this chapter to Chapter 05.
- Stage 1, Chapters [02 (Product Thinking)](../stage-01-engineering-mindset/02-product-thinking.md),
  [06 (Build vs Buy)](../stage-01-engineering-mindset/06-build-vs-buy.md), and
  [07 (Simplicity)](../stage-01-engineering-mindset/07-simplicity.md) — the mindset this
  chapter weaponizes against scope.

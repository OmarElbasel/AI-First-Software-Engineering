# Technical Debt

## Introduction

Technical debt is the gap between how a system is built and how it would
need to be built to change it cheaply. Like financial debt, it lets you get
something now — a shipped feature, a met deadline — in exchange for paying
interest later, in the form of every future change costing more than it
should. Repay the principal (do the rework) and the interest stops. Ignore
it, and it compounds.

The term is almost universally misused to mean "code I don't like." That
misreading matters, because it turns a precise financial instrument into a
moral complaint. Debt, in the original sense coined by Ward Cunningham, is
not sloppiness — it is a *financing decision*. Taken deliberately and
recorded, it is one of the most useful tools an engineer has: it is how you
ship a product before you fully understand the domain, then pay back the
shortcuts as understanding arrives. Taken blindly and left invisible, it is
how a codebase becomes something everyone is afraid to touch.

Chapter 04 ended by shipping a deliberate stopgap — the pagination fix —
with a written trigger to revisit it. That was technical debt, taken well.
This chapter is about the whole discipline: how to tell good debt from bad,
which debt to repay and which to leave alone forever, and how AI has turned
into both the fastest debt-generation machine ever built and, under
supervision, a genuine tool for paying it down.

## Why It Matters

Debt is invisible until it isn't. A feature that took two days last year
takes two weeks this year, and no single line of code is to blame — the cost
is spread across a dozen shortcuts nobody recorded. The team's velocity
quietly halves. New engineers take months to become productive because the
system's real behavior lives in undocumented special cases. Eventually
someone proposes the rewrite, which is debt bankruptcy: expensive, risky,
and usually a way of trading known debt for unknown debt.

The reason this compounds rather than staying flat is interest. Every
shortcut makes the code around it harder to change; the next change is built
on top of the shortcut, harder still; and shortcuts taken under the pressure
of *already* being slow are the recklessly-taken kind. Unmanaged debt is a
loan whose interest rate rises the longer you carry it.

AI changes the scale of the problem in both directions, and the direction it
goes is entirely determined by whether the debt is managed. An assistant can
generate a quarter's worth of code in an afternoon — and if that code is
merged faster than anyone understands it, you have manufactured
*understanding debt* at generation speed: a system that works and that no
human can confidently change. The same assistant, pointed at existing debt
with a test harness around it, can repay principal faster than any human
could type. Same tool, opposite outcomes. The differentiator is the
discipline in this chapter, not the model.

## Mental Model

Not all debt is equal, and the single most important skill is telling the
kinds apart. Martin Fowler's quadrant does it along two axes — was the debt
taken *deliberately* or *inadvertently*, and was the taking *prudent* or
*reckless*:

```
                    PRUDENT                        RECKLESS
              ┌───────────────────────┬───────────────────────┐
              │ "Ship now, refactor   │ "We don't have time    │
  DELIBERATE  │  when we understand   │  for design."          │
              │  the domain."         │                        │
              │                       │ Taken knowingly, with  │
              │ A financing decision. │ no plan to repay.      │
              │ Recorded, triggered.  │ The dangerous default  │
              │  ── GOOD DEBT ──      │ under deadline.        │
              ├───────────────────────┼───────────────────────┤
              │ "Now that it works,   │ "What's a layered      │
 INADVERTENT  │  we see how it should │  architecture?"        │
              │  have been built."    │                        │
              │                       │ Debt from not knowing  │
              │ Learning debt. The    │ what you didn't know.  │
              │ tax of doing anything │ Fixed by growing the   │
              │ new. Unavoidable.     │ engineers, not just    │
              │                       │ the code.              │
              └───────────────────────┴───────────────────────┘
```

The top-left is a legitimate tool. The top-right is where most damage comes
from — debt taken knowingly and then hidden. The bottom-left is unavoidable
and healthy: you cannot design perfectly for a domain you have not yet
learned. The bottom-right is an education problem masquerading as a code
problem.

The second, less obvious idea is what actually makes debt expensive:

```
   Interest is only paid on code you CHANGE.

   Debt in a frozen, working, rarely-touched module   →  ~0% interest.
     (ugly, but it costs you nothing. Leave it alone.)

   Debt in the hot path of active development          →  compounding.
     (every feature pays the tax, twice a week, forever.)

   Repayment priority  =  how bad it is  ×  how often you touch it
                          (principal)        (interest rate)
```

This is why "clean up all the messy code" is the wrong goal. Messy code you
never touch is a paid-off asset. The debt worth repaying is the debt sitting
in the path of the work you are actually doing.

A working definition:

> **Technical debt is any shortcut in a system's design that makes future
> change more expensive. It is prudent when taken deliberately, recorded,
> and given a repayment trigger — and reckless when taken silently and left
> to compound.**

## Real-World Scenario

**Invoicely**, eighteen months after the QuickBooks sync shipped. The
company is at ~2,500 customers now. A new feature — multi-entity support, so
a holding company can manage several subsidiaries under one login — is
estimated at two weeks and is now in its sixth. Every change to the billing
and sync area takes three times longer than the estimate, and the newest
engineer has stopped touching that code entirely. The team calls a
half-day debt audit before continuing. Four debts surface, one per quadrant.

### The prudent-deliberate debt (the good kind)

The pagination stopgap from Chapter 04 is still in place. It was taken
knowingly, recorded in an ADR with the trigger "revisit when an account
crosses ~50,000 invoices," and the queue that was meant to replace it was
built the following sprint exactly as planned. The pagination code now runs
in front of the queue as a minor optimization. **Cost to the audit: zero.**
This is what managed debt looks like — it never became a surprise, because
it was never invisible. Nobody even flags it.

### The reckless-deliberate debt (the expensive kind)

Under the Meridian deadline, a second shortcut was taken that *wasn't*
recorded: to ship faster, someone skipped tests on the webhook handler and
left a `# TODO: handle partial failure` comment. The comment is now
fourteen months old. Every engineer who has touched billing since has
routed *around* the untested handler rather than through it, because
changing it is terrifying — there is no net. The multi-entity feature needs
to change exactly this handler, and that is most of why it is in week six.
This is the debt that is actually hurting: taken deliberately, hidden, and
sitting in the hot path.

### The inadvertent-prudent debt (the learning kind)

The original `accounts` table modeled one company per login, because in
month three that was the entire product. Multi-entity support requires a
company-and-subsidiary model the founders could not have known to build
then. Nobody was wrong here — the debt is the tax of having learned
something. **This is not a mistake to feel bad about; it is a migration to
plan.** The right response is a schema change, not a post-mortem.

### The inadvertent-reckless debt (the AI-scaled kind)

The reconciliation logic exists in six near-identical copies. A year of
"add a reconciliation variant for X" prompts produced six functions that an
assistant generated by adapting the previous one — none of the engineers
noticed the duplication accreting, because each individual diff looked
small and reasonable. Now a rule change to reconciliation means finding and
editing six places, and the multi-entity work has already shipped one bug
from a copy that was missed. This is debt from not-knowing, manufactured at
generation speed.

### The decision: repay by interest, not by ugliness

The instinct is to fix the worst-looking thing first. The audit resists it
and ranks by *interest × principal* instead:

- The **untested webhook handler** is repaid first — highest interest (the
  multi-entity feature is blocked on it right now) and high principal
  (fear-inducing, no net). Repayment is not a rewrite: the team writes
  characterization tests that pin the handler's *current* behavior, then
  changes it safely under that net.
- The **six-copy reconciliation** is repaid second and incrementally —
  consolidated into one function the next few times someone passes through,
  under tests, not in a dramatic sweep.
- The **single-company schema** is repaid deliberately as part of the
  multi-entity feature, because that feature is the thing forcing the
  change — the migration is the work, not a detour from it.
- The **pagination stopgap** is not repaid at all. It works, it is in nobody's
  way, and its interest rate is zero. Repaying it would be pure cost.

Six weeks of pain traced back, almost entirely, to one recklessly-taken,
unrecorded, untested shortcut in the hot path — and the fix was never "clean
up the codebase," which would have burned weeks polishing the pagination
code and the frozen modules while the actual blocker sat untouched. **The
discipline is not tidiness. It is knowing which debt charges interest.**

## Engineering Decisions

Four decisions inside that scenario recur every time debt is involved.

### Whether to take the debt at all

**Options:** (1) take the shortcut to ship, and record it; (2) take the
shortcut silently; (3) do it "right" now and delay shipping.

**Trade-offs:** recorded debt (option 1) costs a few minutes of writing and
buys a shipped feature with a paper trail back to the shortcut. Silent debt
(option 2) costs nothing now and becomes the fourteen-month webhook handler
later — the interest is deferred, not avoided. Doing it right now (option 3)
avoids the debt entirely but may be over-engineering if you do not yet
understand the domain well enough to design correctly, or if shipping now is
worth more than the interest.

**Recommendation:** take prudent debt freely, but only if you record it —
a ticket, a linked ADR, and a repayment trigger
([`templates/adr.md`](../../templates/adr.md)). The recording is what
separates a financing decision from a landmine. Debt you don't write down
you have not taken deliberately; you have just made a mess.

### Which accumulated debt to repay first

**Options:** (1) worst-first — fix the ugliest code; (2) interest-first —
fix the debt in the code you change most; (3) opportunistic — fix whatever
you happen to be touching.

**Trade-offs:** worst-first is emotionally satisfying and frequently
worthless, because the worst code is often frozen and charging no interest.
Interest-first targets the debt that is actually slowing the team but
requires honestly measuring where the work happens. Opportunistic (the boy
scout rule) is cheap and continuous but can miss a high-interest debt that
nobody happens to pass through.

**Recommendation:** interest-first for deliberate repayment, opportunistic
for everything else. Rank by *principal × how often the code changes*, and
accept that some bad code will never be worth repaying. The audit's refusal
to touch the pagination stopgap was as correct as its decision to fix the
webhook handler.

### How to repay — incremental vs. rewrite

**Options:** (1) rewrite the debt-laden component from scratch;
(2) incremental repayment under a test harness (characterization tests, then
change; or the strangler pattern for larger components).

**Trade-offs:** the rewrite feels clean and is almost always a trap — it
discards the embedded knowledge in the old code (the special cases and bug
fixes that make it look ugly), reproduces the original debt in new form, and
blocks feature work for its whole duration. Incremental repayment is slower
per step, keeps the system shippable throughout, and preserves the behavior
you cannot see.

**Recommendation:** incremental, under tests, essentially always. Pin the
current behavior with characterization tests *first* — including the ugly
edge cases — then refactor with a net. This is Chapter 01's
"understand before you rewrite" applied to debt: the confusing parts are
usually load-bearing.

### How to prevent reckless debt

**Options:** (1) rely on individual discipline; (2) build prevention into
the definition of done and review — tests required, debt recorded, review
gates.

**Trade-offs:** discipline alone fails predictably under deadline, which is
exactly when reckless debt gets taken. Structural prevention (option 2)
costs process overhead but makes the cheap-to-prevent debt actually cheap —
a test written today is free compared to the fourteen-month interest on its
absence.

**Recommendation:** prevent structurally. The definition of done from
Chapter 01 and the review checklists are debt-prevention instruments: the
reckless debt you never take is the only debt with no interest and no
principal.

## Trade-offs

Managing debt has costs too, and the goal is never zero debt — it is
*optimal* debt.

**Repayment has opportunity cost.** Every hour spent refactoring is an hour
not spent shipping. Debt paydown is only justified by real interest — code
you keep changing — not by aesthetics. A team that refactors code nobody
touches is spending feature time to make frozen assets prettier, which is
its own kind of waste.

**Zero debt is a failure mode.** A startup that gold-plates every module,
refuses every shortcut, and designs for scale it does not have will ship too
slowly to survive long enough for the debt to matter. Taking on prudent debt
to reach the market is frequently the correct engineering decision — the
company that dies debt-free still dies. This is the over-engineering trap
from Chapter 04, wearing the costume of craftsmanship.

**Some debt should never be repaid.** Code that works, is isolated, and will
not change is a paid-off loan. The correct action is to leave it alone, no
matter how it reads. "But it's ugly" is not an interest payment. Tracking it
in a backlog you will never action is itself a small, real waste of
attention.

**Debt tracking can become its own debt.** A debt register with four hundred
items is a graveyard nobody reads, and its existence provides false comfort
("it's tracked") while nothing gets repaid. A small, ruthlessly prioritized
list of the debt actually charging interest beats an exhaustive catalogue
every time.

## Common Mistakes

**Treating all debt as bad.** Moralizing about "garbage code" flattens the
quadrant into a single judgment and blinds you to the useful distinction
between prudent financing and reckless mess. Fix: before reacting to debt,
classify it — deliberate or inadvertent, prudent or reckless — because the
right response differs completely across the four.

**Taking debt silently.** Shipping a shortcut with no ticket, no comment,
no trigger — the fourteen-month webhook handler. The interest is invisible
until it is enormous, and by then the context that would justify or repay it
is gone. Fix: debt is only prudent if it is recorded; an untracked shortcut
is reckless by default, however good the intentions.

**Repaying worst-first instead of highest-interest-first.** Spending a
refactoring budget on the scariest-looking module while the real bottleneck
sits in ordinary-looking code you touch daily. Fix: prioritize by principal
× change-frequency, and be willing to leave genuinely bad code untouched
because its interest rate is zero.

**Declaring bankruptcy — the big rewrite.** Reaching for a from-scratch
rewrite when the debt feels overwhelming. It discards embedded knowledge,
blocks delivery for months, and typically recreates the debt (see
Anti-Patterns, and Chapter 01). Fix: repay incrementally under tests; the
strangler pattern lets you replace a component piece by piece while it keeps
running.

**Using "tech debt" as a slur.** Labeling any unfamiliar, inherited, or
merely disliked code as "debt" to justify rewriting it. This dilutes the
term until it means nothing and often targets code that is fine — the
confusing parts are frequently load-bearing scars, not debt. Fix: reserve
the word for a real gap between the design and cheap changeability, and
prove the interest before proposing repayment.

## AI Mistakes

Debt is the arena where AI's dual nature is sharpest: **by default it is a
debt accelerator, and only under supervision is it a repayment tool.** Every
failure below is a version of the assistant taking the locally-cheap action
that grows debt, because adding and imitating are safer for it than
understanding and changing. The countermeasure is always to make it change
rather than accrete, and to give it a net before it touches anything.

### Claude Code: additive-by-default

Asked to change existing behavior, Claude Code tends to *add* a new function,
branch, or flag alongside the old code rather than modify it in place —
because adding is locally lower-risk than understanding and safely changing
what exists. Repeated across a project, this is exactly how Invoicely got six
copies of its reconciliation logic: each diff was a small, reasonable
addition, and the duplication debt accrued invisibly.

**Detect:** the diff is nearly all additions with little deleted, and the new
code overlaps the responsibility of code that is already there. A growing
file where nothing ever shrinks is the fingerprint.

**Fix:** make replacement explicit in the instruction:

> Modify the existing implementation in place rather than adding a parallel
> one. Show me what you are deleting or replacing. If similar logic already
> exists, consolidate with it instead of duplicating it.

### GPT: debt-blind refactoring that changes behavior

Asked to "clean up" or "refactor" a function, GPT-family models will
confidently rewrite it — and silently drop the edge cases and special-case
branches that made it look ugly, because they cannot tell which strange lines
are load-bearing (a bug fix, a boundary condition discovered in production).
The attempt to *repay* debt produces a regression. This is Chapter 01's
"rewriting instead of understanding," now triggered by a refactor request.

**Detect:** a refactor PR with no behavior-preserving tests, and "simplified"
logic that quietly removed a conditional or a special case. Cleaner code plus
zero new test coverage is the warning.

**Fix:** never let it refactor without a net, and make it surface the scars
first:

> Before refactoring, list every edge case and special condition this code
> currently handles. We will pin them with tests first. The refactor must not
> change any observable behavior — only structure.

### Cursor: debt by imitation

Inline assistants take their cue from the surrounding code. Drop Cursor into
a file that skips error handling, omits types, and carries a `TODO`, and its
completions will match those habits faithfully — propagating the local
shortcut into every new line by imitation. The debt pattern spreads at the
speed of autocomplete, and the file's worst conventions become the de facto
standard for everything added to it.

**Detect:** new code that inherits the surrounding code's shortcuts — the
same missing validation, the same untyped signatures, the same swallowed
errors. The tell is consistency with a bad neighbor rather than with the
project's actual standard.

**Fix:** state the intended standard rather than letting the file define it,
and keep a clean reference in context:

> Do not match the shortcuts in this file. Add full error handling and types
> to new code, following the pattern in `services/billing.py`, even where the
> surrounding code does not.

Used deliberately, the same tools are the best debt-repayment instrument
you have: point an assistant at a duplicated cluster *with a test harness
around it* and ask it to consolidate, and it will do in minutes what would
take an afternoon by hand. The tool is neutral; the net and the instruction
decide which direction the debt moves.

## Best Practices

**Take debt deliberately, and always record it.** A ticket, a comment
linked to that ticket, and a repayment trigger — the same "revisit when"
mechanism from Chapter 04's ADRs
([`templates/adr.md`](../../templates/adr.md)). Debt you write down is a
financing decision; debt you don't is a landmine. This one habit converts
most reckless debt into prudent debt for free.

**Prioritize repayment by interest, not appearance.** Rank debt by principal
× how often the code changes, repay the top of that list, and consciously
leave the bottom — including genuinely ugly code that nobody touches — alone.
The goal is velocity, not tidiness.

**Repay incrementally, under a test harness.** Pin current behavior with
characterization tests before changing anything, then refactor with a net;
use the strangler pattern for components too large to fix in one step.
Combine with the boy scout rule — leave each file a little better than you
found it — so most debt is repaid continuously rather than in dramatic
sweeps.

**Prevent reckless debt with the definition of done.** Tests for new
behavior, review gates, and recorded shortcuts (Chapter 01 and the
[code review checklist](../../checklists/code-review.md)) make cheap-to-prevent
debt actually cheap. The debt you never take is the only debt with no
interest.

**Match AI generation to understanding, and give it a net.** Cap what you
merge to what the team can actually understand (Chapter 03's slice-to-review
size), and never let an assistant refactor or consolidate without tests
pinning behavior first. This is the single control that keeps AI on the
repayment side of the ledger rather than the accrual side.

## Anti-Patterns

**The Big Rewrite.** Declaring debt bankruptcy and rebuilding from scratch.
It feels like a fresh start and is almost always a trap: it discards the
embedded knowledge in the old system, freezes feature delivery for its whole
duration, and reliably recreates the original debt in unfamiliar new code.
The tell: "it'll be faster to rewrite than to understand it." (It won't. See
Chapter 01.)

**Debt Denial.** "We'll clean it up later" with no ticket, no trigger, and
no intention. Later never arrives, the stopgap becomes load-bearing, and the
shortcut is still there years on — now with three features built on top of
it. The tell: shortcuts justified verbally and recorded nowhere.

**Debt Phobia (gold plating).** The inverse failure: refusing all debt,
over-engineering every module for imagined future scale, and shipping too
slowly to survive. Perfect code in a dead company is worth nothing. The tell:
abstractions and flexibility built for requirements that do not exist yet
(Chapter 04's over-engineering, viewed through debt).

**The Debt Sprint.** One "cleanup sprint" per year in which the team pays
down random debt with no interest analysis, feels virtuous, and immediately
resumes accruing at the same rate. Debt management is continuous and
prioritized, not an annual ritual. The tell: refactoring scheduled by the
calendar rather than by where the interest actually is.

## Decision Tree

"I'm looking at some technical debt — what do I do with it?"

```
Am I about to TAKE debt, or did I FIND existing debt?

├── ABOUT TO TAKE IT
│   │
│   Do I understand the shortcut and why it's worth it right now?
│   │
│   ├── NO (skipping tests on money code, no plan, pure haste)
│   │        └──► Don't. This is reckless debt. Do it right, or descope.
│   │
│   └── YES (prudent: cheaper now, understood, worth the interest)
│            └──► Take it — AND record it: ticket + comment + repayment
│                 trigger. Unrecorded prudent debt becomes reckless debt.
│
└── FOUND EXISTING DEBT
    │
    How often does this code actually change?
    │
    ├── Rarely / frozen / it just works
    │        └──► Leave it. ~0% interest. Repaying it is pure cost,
    │             however ugly it looks.
    │
    └── Often / it's slowing current work
        │
        Can I repay it incrementally?
        │
        ├── YES ──► Pin behavior with characterization tests, then
        │           refactor under the net. Boy-scout it as you pass through.
        │
        └── NO (needs a large structural change)
                 └──► Strangler pattern: replace it piece by piece while it
                      keeps running. NOT a big-bang rewrite. Preserve the
                      embedded behavior; understand before you replace.
```

The most-skipped branch is the first "FOUND" question. Engineers repay the
debt that looks worst instead of the debt that costs most — and burn their
refactoring budget on frozen code while the real bottleneck keeps charging
interest.

## Checklist

### Debt Judgment Checklist — when taking or finding debt

- [ ] I classified this debt on the quadrant (deliberate/inadvertent × prudent/reckless) before reacting to it.
- [ ] If I'm taking debt deliberately, it is recorded: ticket, in-code reference, and a repayment trigger.
- [ ] I estimated interest by how often this code changes — not by how bad it looks.
- [ ] For debt worth repaying, I ranked it by principal × change-frequency, not worst-first.
- [ ] My repayment plan is incremental and under a test harness — I am not defaulting to a rewrite.
- [ ] I identified debt that should never be repaid (frozen, working, isolated) and left it alone.
- [ ] Cheap-to-prevent debt (missing tests on new code) is being prevented, not deferred.

### Code Review Checklist — debt in the diff

- [ ] New shortcuts are recorded with a ticket and repayment trigger, not left silent.
- [ ] The change modifies existing code where appropriate rather than adding a parallel copy (no duplication debt).
- [ ] Any refactor preserves behavior and is backed by tests that pin the old behavior first.
- [ ] New code meets the project's standard, not the surrounding file's shortcuts (no debt by imitation).
- [ ] AI-generated additions were checked for logic that duplicates something already in the codebase.
- [ ] The diff isn't spending review/feature budget polishing frozen code that charges no interest.

## Exercises

As before, these produce artifacts — do them in writing.

**1. The debt register.** Take a codebase you work in and list ten real
debts. For each, classify it on Fowler's quadrant, estimate its principal
(how much rework to repay) and its interest rate (how often that code
changes), and rank by principal × frequency. The artifact is the ranked
register plus an explicit list of which debts you would *never* repay and
why — the second list usually teaches more than the first.

**2. The scar hunt.** Find a piece of code you consider ugly and are tempted
to rewrite. Before touching it, use `git blame` and the tests to reconstruct
what each strange-looking line is doing — which are bug fixes, which are edge
cases discovered in production. Then decide: is this debt, or is it a scar
that looks like debt? The artifact is the annotated code plus your verdict,
and the point is to feel how often "ugly" means "load-bearing."

**3. The AI debt experiment.** Ask an assistant to change the behavior of an
existing function, and measure the diff: how many lines added versus
deleted, and does it modify in place or add a parallel path? Then re-prompt,
instructing it to refactor in place and delete what it replaces, and compare
the two diffs' effect on total surface area. The artifact is the two diffs
plus one paragraph on the additive-by-default tendency you observed — this
calibrates your review eye for it better than any description.

## Further Reading

- **The WyCash Portfolio Management System** (Ward Cunningham, 1992
  OOPSLA experience report) and his later short video **"Debt Metaphor"** —
  the origin of the term, and the correction most of the industry missed:
  debt was never meant to describe bad code, but the gap between the code and
  your current understanding of the problem.
- **Technical Debt Quadrant** (Martin Fowler, martinfowler.com) — the
  deliberate/inadvertent × prudent/reckless framing this chapter is built on;
  two minutes to read and it permanently upgrades how you talk about debt.
- **Working Effectively with Legacy Code** (Michael Feathers) — the
  practical manual for repaying debt safely: characterization tests, seams,
  and the discipline of getting untested code under a net before you change
  it. The book that makes "incremental, under tests" actionable.
- **Tidy First?** (Kent Beck) — the economics of small-scale debt repayment,
  framed as option value: when tidying pays for itself immediately, when to
  defer it, and why the answer is a financial calculation rather than a moral
  one.

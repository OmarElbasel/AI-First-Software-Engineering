# User Feedback

## Introduction

Analytics tells you what users did. Feedback tells you what they meant — and, handled
badly, it tells you whatever the loudest fraction of your users wants you to hear. Between
those two sentences sits one of the least-taught skills in software: treating qualitative
signal with the same rigor engineers reflexively apply to quantitative signal. Nobody
would compute churn from a biased sample of hand-picked accounts, but teams routinely
compute their roadmap from exactly that — the users who happened to write in, weighted by
volume and vividness, with the silent majority and the already-departed contributing
nothing.

Feedback is a pipeline, not an inbox. It has collection points with different biases,
a triage step that separates bugs from confusion from requests, a synthesis step that
clusters solutions-people-asked-for into problems-people-actually-have, a decision step
where evidence meets strategy, and a closing step — telling people what you did — that
most teams skip and that quietly outperforms most marketing. Each step can be done with
judgment or by vibes, and the difference compounds: a year of vibes produces a product
shaped like its ten loudest customers.

This is a conceptual chapter because the scarce skill is not the widget — any assistant
can build a feedback form in an afternoon — it is the interpretation: whose voice counts
for what, when a feature request is really a bug report about your onboarding, and how to
say no without bleeding trust. The systems chapters around it supply the machinery
(Chapter 04's events carry the behavioral half; Chapter 06's metrics arbitrate the
disputes); this one supplies the judgment that keeps the machinery honest.

## Why It Matters

- **The loudest-voice roadmap is the default outcome, not a rare failure.** Vocal users
  are systematically unrepresentative: they are more invested, more expert, more
  edge-case-prone, and more tolerant of complexity than the median customer. Ship what
  they ask for, unweighted, and the product tilts toward power-user sprawl while the
  quiet middle churns over basics nobody wrote in about.
- **Churned users are the most informative and least heard.** People rarely file a
  ticket before leaving; they just leave. Every feedback channel you run oversamples
  survivors — the users for whom the product mostly works. Without a deliberate channel
  into the departed (churn interviews, cancellation surveys), the pipeline structurally
  cannot see the reasons people quit.
- **Requests arrive as solutions and are evidence about problems.** "Add expense
  tracking" might mean five different problems — or, as Invoicely discovered below, a
  segment you don't serve using the product for something it isn't. Building the stated
  solution without extracting the underlying problem is how products accrete features
  that satisfy the request and miss the need.
- **In an AI-first team, learning is the bottleneck, so feedback is load-bearing.**
  When implementation is fast (Stage 10), the queue of "what should we build?" empties
  quickly, and the quality of what refills it — the feedback and metrics pipeline —
  becomes the constraint on the whole company. A team that can ship anything in a week
  and doesn't know what to ship has automated the wrong half of the loop.
- **Closing the loop is the cheapest retention mechanism you will ever run.** "You asked
  for bank transfers — it shipped today" converts a complaint into an advocate and a
  churned trial into a reactivation. It costs an email. Teams skip it because nothing in
  their tooling remembers who asked.

## Mental Model

Three ideas carry the chapter: feedback is evidence about problems, evidence gets
weighted by source, and the whole thing is a pipeline with a decision step — not a
democracy.

**1. Feedback is evidence about problems, not instructions about solutions.** Users are
authoritative about their pain and unreliable about your product design — they experience
the problem daily and think about your architecture never. The discipline is the
translation step:

```
  WHAT ARRIVES                      WHAT IT'S EVIDENCE OF
  "add expense tracking"        →   ...what are they doing when they
                                    want it? (an accountant doing
                                    bookkeeping — off-ICP use)
  "I need an export button on   →   they don't trust the app as the
   every screen"                    system of record — why not?
  "make reminders configurable" →   the default schedule embarrassed
                                    someone in front of a client — once
  "just integrate with Xero"    →   their accountant refuses double
                                    entry; a WORKFLOW blocker, stake:
                                    the whole subscription

  Rule: capture the request verbatim, then ask one question —
  "what were you trying to do when you hit this?" — and store
  BOTH. The verbatim is data; the problem is what you build on.
```

**2. Weight evidence by source, stake, and frequency — in that order.** A piece of
feedback carries metadata that matters more than its content: who it came from (target
segment and paying? or free-tier and off-profile?), what's at stake for them (a paper cut
or a workflow blocker? are they about to churn?), and how often the underlying *problem*
appears across independent sources. Frequency counts problems, not requests — ten
identical feature requests from one Slack thread are one datum. And every tally carries
the survivorship asterisk: you are counting the people who stayed and spoke.

**3. The pipeline ends in a decision, and strategy holds the pen.** Feedback informs the
roadmap; it does not vote on it:

```
  COLLECT           TRIAGE              SYNTHESIZE         DECIDE          CLOSE
  in-app widget     bug → issue         cluster by         evidence        tell every
  support tickets   confusion → docs/   PROBLEM, not       meets           requester
  sales/onboarding    UX fix (it's a    by request text;   STRATEGY        what shipped
    call notes        bug in intent)    attach segments,   (Ch 01          — or why
  churn interviews  request → the       revenue, quotes    hypothesis,     not; log
  community/social    problem ledger                       Ch 06           the "no"s
                                                           metrics
                                                           arbitrate)

  The decision step is where most pipelines quietly fail: either
  it doesn't exist (the graveyard — everything collected, nothing
  decided) or it's a popularity count (the loudest-voice roadmap).
  A product with no strategy is steered by whoever emails most.
```

A working definition:

> **User feedback is qualitative evidence about problems, collected through channels with
> known biases, translated from requested solutions into underlying problems, weighted by
> segment, stake, and independent frequency — including a deliberate channel into churned
> users — synthesized into a problem ledger that informs but does not dictate a
> strategy-owned roadmap, with the loop closed to everyone who spoke.**

## Real-World Scenario

**The setup.** Post-partnership Invoicely (Stage 11's 50,000-business influx) watches
feedback volume grow from 30 items a week — readable by everyone over coffee — to 400,
across support tickets, an in-app widget, onboarding calls, and a partner Slack. The
ad-hoc system (a channel everyone skims, memory as the database) stops working in the
first month. Two candidate priorities emerge from the noise.

**The loud one.** "Expense tracking" dominates by volume: 120 requests in a quarter, a
vocal community thread, a competitor's feature page passed around, one champion posting
weekly. The team's sympathy is real — the competitor comparison stings — and an
assistant asked to "summarize what users want" reports *"the most requested feature is
expense tracking"* with perfect confidence, because by raw count it is.

**The quiet one.** A trickle — nine mentions in the same quarter, none angry — from
agencies: "some of my clients pay by bank transfer; can the invoice show payment status
for those?" Individually the notes read as edge cases. Nobody campaigns for them.

**The synthesis that reframed both.** A day of tagging each item with plan, segment, and
tenure changes the picture. The expense requesters: overwhelmingly free-tier, and
disproportionately *accounting firms* — off-ICP users trying to turn an invoicing tool
into bookkeeping software, precisely the segment the Chapter 01 hypothesis excluded. Their
problem is real; it is also a different product. The bank-transfer mentions: eight of
nine from Business-plan agencies, average tenure two-plus years — and cross-referenced
with Chapter 04's events, those tenants take 40% of their invoice value through *manual*
payments the product can't see, which means Invoicely's core promise ("get paid faster,
know when you're paid") is silently broken for its highest-LTV segment. Volume said
expenses; weighting said bank transfers, and it wasn't close.

**The invisible one.** The same month, churn interviews — eight calls with canceled
Business accounts, scheduled with a gift card and honest curiosity — surface a reason
that appears *nowhere* in the feedback channels: three of eight left because their
accountant demanded Xero integration, and none of the three had ever mentioned it in-app.
They didn't complain; they evaluated, found it missing, and left. The pipeline's biggest
finding was a silence.

**The close.** Bank-transfer reconciliation ships in six weeks. The nine requesters get
personal emails; two reply with case-study-grade enthusiasm, one reactivates a second
account. The expense-tracking thread gets an honest public answer — what Invoicely is
for, what it won't become, and an exported integration path for bookkeeping tools — which
costs a day of courage and ends the weekly campaign more effectively than a year of
"great idea, we'll consider it." Xero enters the roadmap queue with churn-interview
evidence attached. The team institutionalizes the ritual: weekly synthesis, segment tags
mandatory, churn calls forever.

## Engineering Decisions

### Which channels, and what is each one for?

Channels are instruments with known biases — deploy a portfolio, not a favorite. The
in-app widget catches in-context friction from active users (biased toward the engaged).
Support tickets are feedback wearing an incident costume — confusion clusters are UX
bugs. Sales and onboarding calls carry the prospect's view (biased toward feature
checklists and whoever's in the room). Churn interviews are the only channel that samples
failure. Community/social is the loudest and least representative — useful for early
signal, worthless for counting. The decision is coverage: every stage of the customer
lifecycle observed by at least one channel, and every channel's bias written down next
to its data.

### How is it stored and triaged — and with how much tooling?

A tagged ledger with an owner beats a platform. The minimum viable pipeline: every item
lands in one place, tagged with source, segment, plan, and revenue (pulled automatically
from the subscription data — never typed by hand), linked to the verbatim, and routed
within a day: bugs to the tracker, confusion to a UX/docs queue, requests to the problem
ledger. Buy a lightweight tool or run it on the issue tracker; *build* nothing beyond a
join against your own customer data (Chapter 01's judgment applies — a bespoke feedback
platform pre-scale is over-building). The pipeline's health metric is simple: median
time from arrival to triage, and the percentage of items that ever reach a decision.

### Who talks to users?

Engineers do — on a rotation, not as a career. A support/feedback duty week per engineer
per quarter converts abstract tickets into remembered voices, kills the "users are dumb"
reflex faster than any all-hands, and produces better products *and* better AI prompts —
the engineer who has heard five agencies describe reminder anxiety writes a sharper spec
than the one who read a summary. The cost is real (a week of delivery per engineer per
quarter) and worth stating honestly; the return shows up in every "what were they trying
to do?" judgment this chapter demands.

### How do you weight a single piece of feedback?

Segment fit first: is this the customer the Chapter 01 hypothesis names? Feedback from
off-ICP users is data about a *different product's* demand. Stake second: workflow
blockers and churn-threats outrank conveniences regardless of eloquence. Frequency third
— counted as independent problem-occurrences across the ledger, never as thread volume.
Revenue is a tiebreaker with a warning label: weight toward high-LTV *segments*, but the
moment one specific account's requests get built on demand, you are a consultancy with a
subscription price (Chapter 02's overrides exist precisely so sales flexibility doesn't
become roadmap capture). And strategy retains the veto — a perfectly weighted request
for the wrong product is still a no.

### How do you say no — and is it recorded?

Explicitly, honestly, and in a ledger. The kind no ("Invoicely won't become bookkeeping
software; here's the export path") ends campaigns and earns respect; the cowardly maybe
("great idea! adding it to the list!") accumulates a debt of implied promises that
detonates in public later. Every deliberate no goes in a "why we said no" log with its
reasoning and revisit conditions — future engineers inherit the decision instead of
re-litigating it, and users who ask again get a consistent answer. The log is the
qualitative sibling of the ADR (Stage 1's decision-record discipline).

### What do surveys measure — and NPS in particular?

Treat NPS as a trend thermometer, never a truth source: its absolute value is
methodology-noise (timing, sample, culture), but a sustained slide in your own series is
a real smoke alarm. The survey with actual decision power is the churn/cancellation
question ("what happened?") and the PMF-style question ("how disappointed if this
disappeared?") on a defined cohort. Every survey competes for a finite attention budget —
each intrusive modal spends trust the widget needed — so schedule them like migrations:
deliberately, rarely, with an owner for the results.

## Trade-offs

| Choice | You gain | You pay |
|---|---|---|
| Public voting board | Users feel heard; passive collection at scale | Popularity ≠ strategy; ossifies into promises; loudest segments capture it; every "planned" is a contract |
| Private ledger + synthesis | Weighting and strategy stay in charge | Less visible listening; users repeat requests you've already logged |
| Engineers on feedback rotation | Judgment built at the source; specs improve | A delivery week per engineer per quarter; some engineers hate it |
| Dedicated support only | Engineers stay heads-down | Feedback arrives pre-filtered through someone else's model of what matters |
| Building the stated request | Fast; requester satisfied; demo-able | Solves the symptom; config sprawl; the underlying problem returns wearing a new request |
| Digging for the problem first | Builds the thing that kills the whole cluster | Slower; requires conversation; feels like friction to the requester |
| Churn interviews | The only unbiased-toward-survivors channel | Scheduling pain; bruising to hear; gift-card budget |
| Cancellation survey only | Cheap, automatic | One-word answers; the real reason is usually two questions deep |
| Closing the loop personally | Reactivations, advocates, trust | Requires remembering who asked — tooling and discipline |
| NPS as the feedback program | One number for the board deck | Measures willingness to answer surveys; hides the why; gamed the moment it's a target |
| Answering everything | Nothing falls through | Triage time scales with volume; quality of attention drops uniformly |

The voting-board trade-off deserves its sharp edge: **a public roadmap converts your
product strategy into a standing election in which your most invested users are the only
voters** — every mechanism this chapter builds (weighting, synthesis, strategic veto)
exists to do what that election structurally cannot.

## Common Mistakes

- **Counting requests instead of problems.** 120 expense-tracking requests, one problem
  (off-ICP bookkeeping) — or 9 bank-transfer mentions, one core-promise breach. Cluster
  before counting; the unit of prioritization is the problem.
- **Treating the request as the spec.** Shipping the asked-for button, toggle, or field
  without the "what were you trying to do?" step. The tell in retrospectives: features
  that satisfied their requesters and moved no metric (Chapter 06 will make that
  visible).
- **Sampling only survivors.** Every channel except churn interviews oversamples the
  users the product already works for. If your pipeline has no deliberate line to
  departed users, its picture of "why people leave" is fiction.
- **The feedback graveyard.** Diligent collection, no synthesis, no decision step — a
  table (or channel) where feedback goes to be acknowledged and die. Worse than not
  collecting: users who wrote in and saw nothing learn that speaking is pointless.
- **Implied promises.** "Great suggestion — adding it to our list!" ×200, compounding
  into a public expectation ledger no roadmap can pay. Acknowledge honestly, promise
  nothing that isn't decided.
- **Vote-count democracy without segments.** The tally that treats a two-year Business
  tenant's workflow blocker and a day-one free-tier drive-by as equal citizens. Attach
  segment/plan/revenue automatically at ingestion, or every later judgment inherits the
  blindness.
- **Support tickets excluded from the pipeline.** Tickets triaged as incidents only —
  "resolved: user error" — while five identical confusions per week fail to register as
  the UX bug they are. Confusion clusters are feedback in its most actionable form.
- **Shipping the fix and telling no one.** The bank-transfer feature ships; the nine
  people who asked hear nothing; the reactivation and the case study never happen. The
  loop-closing email is the highest-ROI sentence in this chapter.

## AI Mistakes

The three tools fail differently here, and all three failures wear the costume of
responsiveness — the appearance of a team that listens.

### Claude Code: the request list, implemented as written

Handed a batch of feedback items and asked to "address the top requests," Claude Code
does exactly that — literally. Each stated solution gets built as stated: the requested
toggle becomes a toggle, the requested field becomes a field, and ambiguity gets resolved
into a *setting*, because a configuration option is the implementation that satisfies
every reading of an ambiguous request. Ten requests in, the product has a preferences
sprawl nobody designed, each option doubling the test matrix (Stage 8's combinatorics),
and the underlying problems — untranslated — are still there, now hidden under
configuration.

**Detect:** diffs that add settings/flags in response to feedback items; feature work
whose ticket contains a verbatim request but no problem statement; the settings page
growing faster than the product. **Fix:** the pipeline feeds assistants *problem
statements*, never raw requests — a ticket template with "verbatim / what they were
doing / problem / evidence" fields, and a review rule that new user-facing options
require a justification the way new dependencies do.

### GPT: synthesis that erases the metadata

Asked to summarize a quarter of feedback, GPT produces exactly what it's optimized for:
a fluent, confident digest — "users are frustrated with the lack of expense tracking,
which is the most requested feature" — that collapses the one dimension this chapter is
about. Frequency survives summarization; segment, stake, and tenure do not. Worse, asked
for supporting evidence, it will compose *representative-sounding quotes* that no user
wrote — plausible paraphrases presented with quotation marks. A team that pipes raw
feedback through a model and reads the summary has automated the loudest-voice roadmap
and given it perfect grammar.

**Detect:** summaries with counts but no segment breakdown; "users want X" with no *which
users*; quotes that can't be traced to a source item. **Fix:** structure before you
summarize — tag items with segment/plan/stake at ingestion, then ask for clusters *per
segment* with item IDs cited for every claim, and spot-check the citations. The model is
genuinely excellent at clustering and theme extraction over structured input; it is the
unstructured-dump summary that manufactures consensus.

### Cursor: the widget without the pipeline

Asked for an in-app feedback feature, Cursor autocompletes the visible half: a polished
modal, a textarea, a `feedback` table, a toast saying "Thanks — we read every message!"
The invisible half — routing, tagging, an owner, a notification, any consumer at all —
doesn't autocomplete, because it isn't code near the cursor. The result is a graveyard
with great UX: users deposit trust into a table nobody queries, and the toast's promise
is a lie the team doesn't know it's telling. Variants of the same failure: the
NPS modal wired to fire on every login (attention-budget arson), and free-text feedback
stored without the PII handling Chapter 04 would demand.

**Detect:** a feedback table with zero application readers (`grep` for reads, not
writes); no notification or triage owner in the diff; collection UI shipping in a PR
with no pipeline counterpart. **Fix:** define feedback collection as done only when an
item demonstrably reaches a triaged, owned queue with segment metadata attached — the
widget is the last 10% of the feature, not the feature.

## Best Practices

- **Enrich at ingestion, automatically.** Every item arrives with segment, plan, revenue,
  and tenure joined from your own subscription data — never hand-typed, never optional.
  Weighting is only possible if the metadata is universal.
- **Keep the verbatim and the translation.** The user's words (data, quotable,
  trust-preserving) and the problem statement (what you build on) — both, linked. Teams
  that keep only summaries lose the evidence; teams that keep only verbatims never
  decide.
- **Run the weekly synthesis ritual.** A fixed hour: new items clustered into the problem
  ledger, counts updated per segment, one decision made or explicitly deferred, and the
  "no" log maintained. The cadence matters more than the tooling — synthesis that isn't
  scheduled doesn't happen.
- **Interview the departed, forever.** A standing pipeline: every cancellation offers a
  20-minute call (paid gift card, no save-pitch); target 5–8 per month. The save-pitch
  ban is what makes the data honest. Cross-reference findings against channels — the
  gaps (Xero) are the headline.
- **Rotate engineers through the front line.** One duty week per quarter: answering
  tickets, sitting in on onboarding calls, running two churn interviews. Write-up
  required; the write-ups feed the ledger.
- **Close every loop, mechanically.** The ledger links requesters to problems; shipping
  a problem's fix triggers the "you asked, it's live" email to every linked requester.
  This must be tooling, not memory — memory closes the recent loops and drops the ones
  that reactivate accounts.
- **Publish the honest no.** For recurring requests that strategy declines, a public,
  reasoned answer (what the product is, why not this, what to use instead) — written
  once, linked forever. It converts a perpetual campaign into a settled question.
- **Feed the loop back into the hypothesis.** Synthesis findings update the Chapter 01
  hypothesis document and the Chapter 06 metric review — feedback that never touches
  strategy documents is being collected for sentiment, not steering.

## Anti-Patterns

- **The election.** A public voting board as the roadmap's actual input queue. Votes
  measure the engagement of segments, not the value of problems; "planned" badges become
  contracts; and strategy is reduced to counting. Boards can *collect*; they must never
  *decide*.
- **The black hole.** Collection with no synthesis step, no owner, no decision cadence.
  Its signature is a team that says "we get tons of feedback" and cannot name the top
  three problems per segment.
- **The feature factory for one logo.** The big account's requests routed straight to
  the sprint, quarter after quarter — roadmap capture purchased at list price. Chapter
  02's overrides exist to give one customer *terms*; nothing exists that should give one
  customer the *backlog*.
- **The survey barrage.** NPS on login, CSAT after every ticket, a quarterly "quick
  10-minute survey" — the attention budget spent measuring instead of hearing. Response
  rates decay, the remaining sample skews agreeable, and the numbers get *more* confident
  as they get less true.
- **The empathy-free dashboard.** Feedback reduced entirely to counts and sentiment
  scores, read by people who have never heard a user speak. The numbers are real; the
  judgment interpreting them starves. (Its mirror twin — decisions made only from the
  five users the founder personally likes — is the same failure with a smaller n.)
- **"We know better" absolutism.** All feedback dismissed because "users don't know what
  they want" — the misread Jobs quote as an operating system. Users are unreliable about
  *solutions* and authoritative about *problems*; a strategy that stops listening to
  problems is a hypothesis that has stopped being tested (Chapter 01's discipline,
  abandoned).

## Decision Tree

```
A piece of feedback arrives —
│
├─ Enrich: attach source, segment, plan, revenue, tenure
│   (automatic, from your own data). Store the verbatim.
│
├─ Triage — what is it?
│   ├─ Something is broken → bug tracker (it exits this
│   │    pipeline, but COUNT it: bug clusters are feedback)
│   ├─ User misunderstood / couldn't find / was surprised
│   │    → UX/docs queue. Recurring confusion = a design bug
│   │      wearing a support costume
│   ├─ Feature request / complaint / idea → problem ledger ↓
│   └─ Churn signal (cancel note, downgrade, silence from a
│        big account) → churn pipeline: offer the interview
│
├─ Translate: what were they trying to do? What problem is
│   this a symptom of? → cluster into the ledger by PROBLEM
│   (new problem: open one; known: increment, link requester)
│
├─ Weigh the CLUSTER, at the weekly synthesis:
│   ├─ Off-ICP segment dominant? → evidence about a different
│   │    product. Honest no (published if recurring), or a
│   │    note for future strategy — not a backlog item
│   ├─ Core-promise breach for a target segment (stake:
│   │    workflow/churn)? → jumps the queue regardless of
│   │    count — verify scale with Ch 04's behavioral data
│   ├─ Real problem, real segment, modest stake → ranked by
│   │    independent frequency × segment value, against
│   │    strategy (Ch 01 hypothesis) and metrics (Ch 06)
│   └─ Conflicts with strategy however popular → deliberate
│        no, reasoning logged, revisit condition named
│
└─ Whatever was decided —
    ├─ Built → close the loop: notify every linked requester
    ├─ Declined → the honest answer (public if the ask is)
    └─ Deferred → say so without promising; keep the links
        (deferrals that ship later still owe their emails)
```

## Checklist

### Engineering Judgment Checklist

- [ ] Every lifecycle stage has a listening channel, and each channel's bias is written
      down next to its data.
- [ ] A deliberate channel into churned users exists and runs monthly — the pipeline
      samples failure, not just survivors.
- [ ] Items are enriched automatically with segment, plan, revenue, and tenure at
      ingestion.
- [ ] Verbatims and problem translations are both stored, linked; clustering happens by
      problem, not request text.
- [ ] Weighting order is explicit: segment fit → stake → independent frequency, with
      strategy holding the veto and no single account owning the backlog.
- [ ] A scheduled synthesis ritual exists with an owner, a cadence, and a decision (or
      explicit deferral) per session.
- [ ] The "why we said no" log exists, with reasoning and revisit conditions.
- [ ] Loop-closing is mechanical: shipping a problem's fix notifies every linked
      requester.
- [ ] Engineers rotate through direct user contact; write-ups feed the ledger.
- [ ] Feedback findings demonstrably update the hypothesis doc (Ch 01) and the metrics
      review (Ch 06) — the pipeline touches strategy, or it's decoration.

### Code Review Checklist

- [ ] Feature work triggered by feedback carries a problem statement, not just the
      verbatim request — "what were they trying to do?" is answered in the ticket.
- [ ] New user-facing settings/toggles added "because users asked" justify themselves
      against the config-sprawl cost (test matrix, docs, support surface).
- [ ] Feedback-collection UI ships only with its pipeline: routing, owner, notification,
      and segment enrichment are in the same PR or already exist.
- [ ] Free-text feedback storage follows Chapter 04's data rules (PII handling,
      retention, no analytics-property leakage).
- [ ] Survey/NPS triggers respect the attention budget: frequency-capped, deduplicated
      per user, and off by default in flows that already contain asks.
- [ ] AI-assisted syntheses cite item IDs for every claim; quotes trace to real items
      before they appear in any decision document.

## Exercises

1. **Audit your channels for survivorship.** List every feedback channel your product
   (or team) runs. For each: which lifecycle stage it samples, its bias, and its volume.
   Then answer honestly: through which channel would you learn why last month's churned
   customers left? If the answer is "none," design the churn-interview pipeline —
   trigger, incentive, script (five questions, no save-pitch), and where findings land.
2. **Re-weight a real backlog.** Take ten feature requests from your tracker (or the
   scenario's: 120× expenses, 9× bank transfer, 0× Xero). Enrich each with segment,
   plan, tenure, and stake. Cluster into problems. Rank once by raw count and once by
   this chapter's weighting — and write a paragraph on where the two rankings diverge
   and which divergence would have cost the most.
3. **Run the translation drill.** Collect five verbatim requests. For each, write the
   probable problem statement, then verify with one question to the requester ("what
   were you trying to do when you hit this?"). Score yourself: how many problem
   statements survived contact? What does your hit rate imply about building from
   requests directly?
4. **Test an AI synthesis for erasure.** Feed a model 30+ real (or scenario) feedback
   items twice: once as raw text, once tagged with segment/plan/stake, requesting
   per-segment clusters with item-ID citations. Diff the two syntheses: what did the
   untagged version erase, which claims lack citations, and are any "quotes" real?
   Write the prompt template your team should standardize on.
5. **Close ten loops.** Find the last shipped feature that originated in feedback.
   Identify every user who asked for it (this is the exercise's real test — can you?).
   Send the ship email. Measure replies, reactivations, and how long the identification
   took; then spec the ledger change that makes it take five minutes next time.

## Further Reading

- Rob Fitzpatrick — *The Mom Test* — the interviewing technique behind every "what were
  they trying to do?" in this chapter; how to ask questions politeness can't corrupt.
- Teresa Torres — *Continuous Discovery Habits* — weekly user contact as an operating
  system: the interview snapshot, opportunity mapping (this chapter's problem ledger,
  matured), and assumption testing.
- Des Traynor / Intercom — "Product strategy means saying no" — the canonical essay on
  the strategic veto, and the taxonomy of persuasive-but-wrong reasons to build a thing.
- Rahul Vohra — "How Superhuman built an engine to find product/market fit" (First
  Round Review) — the "how disappointed?" survey run with real methodology: segmenting
  by response, and building only for the segment that would be very disappointed.
- Jared Spool — "Net Promoter Score considered harmful (and what UX professionals can do
  about it)" — the case against NPS worship, from measurement first principles.
- Stage 1, Chapter [02 (Product Thinking)](../stage-01-engineering-mindset/02-product-thinking.md)
  — outcomes over output: the mindset this chapter's pipeline operationalizes.
- Chapter [04 (Analytics)](04-analytics.md) and Chapter [06 (Product Metrics)](06-product-metrics.md)
  — the quantitative siblings: behavior verifies what feedback claims, and metrics
  arbitrate what feedback proposes.

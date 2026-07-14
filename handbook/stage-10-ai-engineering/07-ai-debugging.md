# AI Debugging

## Introduction

Debugging is the engineering activity where AI assistance is simultaneously most useful and most
dangerous. Most useful, because an agent can do in minutes what consumes hours of a human
debugging session: read every file in a suspect path, generate a dozen plausible hypotheses,
write instrumentation, run the reproduce loop repeatedly without fatigue or boredom. Most
dangerous, because debugging is precisely the activity where a *plausible story* is worth
nothing and only *evidence* counts — and plausible stories are what language models produce by
construction.

Every engineer who has debugged with an assistant knows the failure: you paste a stack trace,
the model replies with a confident diagnosis and a fix, the fix makes the symptom disappear,
and three days later the bug is back wearing different clothes — because the diagnosis was a
well-told guess, the fix was a symptom patch, and the disappearance was coincidence. Repeat
this loop a few times and you have the modern form of the oldest debugging anti-pattern:
programming by permutation, now at machine speed.

This chapter is about keeping the scientific method in charge while an agent does the labor.
The division that works: **AI generates — hypotheses, instrumentation, searches, reproductions;
evidence decides — observed behavior, discriminating experiments, failing tests; and the human
owns the judgment call that no tool can make: "have we actually found the cause, or just a
place to hide the symptom?"** It is a conceptual chapter because the skill is a discipline, not
a technique — the tools came from Chapters 01–03; this is about not letting them debug badly,
faster.

## Why It Matters

- **Debugging is where guessing is most expensive.** A guessed feature gets caught by review; a
  guessed diagnosis produces a fix that *looks* identical to a real one — code that changes
  behavior, a symptom that goes away — while leaving the defect alive. The cost lands later,
  compounded: the bug returns, plus the misleading "fix" now in the codebase, plus the
  regression test that enshrines wrong assumptions.
- **AI accelerates whichever debugging process you actually have.** A disciplined loop
  (reproduce → observe → hypothesize → discriminate → fix → verify) gets dramatically faster
  with an agent running its legs. An undisciplined loop (guess → patch → did the symptom stop?)
  also gets faster — you can now stack four wrong fixes in the time one used to take. The tool
  amplifies the method; it doesn't supply one.
- **Symptom patches accumulate into un-debuggable systems.** Each defensive `if x is None`
  added at a crash site instead of fixing the producer of `None` makes the next bug harder to
  localize — the codebase fills with places where wrong values are tolerated instead of
  rejected. Stage 3's fail-fast principle exists precisely to keep systems diagnosable; AI-era
  patch volume can dismantle it in a quarter.
- **The confident wrong diagnosis anchors everyone.** Once a fluent causal story is in the
  session — "this is a race condition in the cache layer" — both the agent and the human start
  interpreting all subsequent evidence through it (Chapter 03: what's in the window steers
  what comes next). Bad diagnoses aren't neutral misses; they actively bend the investigation.
- **Production incidents raise every stake.** During an outage, the pressure to accept the
  first plausible fix is maximal and the cost of a wrong one (a "fix" deployed onto a live
  fire) is too. Teams that debug with discipline under calm conditions keep the discipline
  under pressure; teams that don't, improvise — with an agent confidently improvising beside
  them.

## Mental Model

The debugging loop hasn't changed since before AI. What changed is who runs each leg — and
where the judgment gates have to sit.

```
        THE LOOP, WITH THE LABOR DIVIDED
  ┌─────────────────────────────────────────────────────────┐
  │ 1 REPRODUCE   make the bug happen on demand             │
  │               AI: writes the repro script/test          │
  │               GATE: no reproduction → no fix, only      │
  │               instrumentation (you can't verify what    │
  │               you can't reproduce)                      │
  │ 2 OBSERVE     gather evidence: logs, state, traces      │
  │               AI: adds instrumentation, filters output  │
  │               (Ch 03: evidence in, bulk out)            │
  │ 3 HYPOTHESIZE candidate causes, RANKED, each with the   │
  │               evidence that would discriminate it       │
  │               AI: superb generator — demand the ranking │
  │               and the discriminators, not one story     │
  │ 4 DISCRIMINATE run the experiment that splits the top   │
  │               hypotheses — ONE variable at a time       │
  │               AI: runs it; HUMAN: reads it honestly     │
  │ 5 EXPLAIN     the causal chain, source to symptom:      │
  │               "X produced Y, Y reached Z, Z crashed"    │
  │               GATE: no chain → back to 2. A fix without │
  │               an explanation is a guess with a diff     │
  │ 6 FIX         at the CAUSE, smallest change that breaks │
  │               the chain — plus the failing test from 1  │
  │               now passing                               │
  │ 7 VERIFY      repro passes, suite passes, AND the fix   │
  │               is removed → repro fails again (the fix   │
  │               is what fixed it, not noise)              │
  │ 8 HARDEN      regression test committed; route the      │
  │               lesson upstream (why didn't tests/review  │
  │               catch it? — Ch 04/06 loop)                │
  └─────────────────────────────────────────────────────────┘

   EVIDENCE ORDER (what outranks what)
     observed behavior  >  code reading  >  model's narrative
     a log line that happened beats any story about what
     "must be" happening — including yours.
```

**Reproduction is the contract.** A failing test (or script) that demonstrates the bug is what
makes every later step honest: hypotheses get tested against it, the fix is proven by it, the
regression suite keeps it. An agent is excellent at building reproductions — make that its
first assignment, not its last. "Fix the bug" without a reproduction is "make the symptom stop
being visible," which has many more solutions than "fix the bug," most of them wrong.

**Hypotheses are cheap; discrimination is the work.** One confident diagnosis is the failure
mode; five ranked hypotheses, each annotated with "and here's the observation that would
confirm or kill it," is the asset. This reframing — from *answer machine* to *hypothesis
generator* — is the single highest-value change in how engineers prompt during debugging.

**The explain gate is where the human earns their keep.** Before any fix merges, someone must
be able to narrate the causal chain from root cause to observed symptom, and every link must be
something observed, not asserted. The agent will happily write this narrative; your job is to
check it the way Chapter 06 checks a diff — is each link *evidence* or *plausibility*?

A working definition:

> **AI debugging is running the classical debugging loop with the agent as its labor — building
> reproductions, instrumenting, generating ranked hypotheses with discriminating experiments,
> executing them — while evidence remains the only judge and two human gates never move: no fix
> without a reproduction, and no fix without an observed causal chain from cause to symptom.
> The output is always three things: the fix, the regression test, and the upstream lesson.**

## Real-World Scenario

**The bug.** Two weeks after Invoicely ships payment reminders (Stage 3's Celery work),
support tickets arrive: some customers receive *duplicate* reminder emails — same invoice, same
day, twice. Maybe one customer in two hundred. No errors in the dashboard; the reminders
worker looks healthy.

**The undisciplined path (as it actually happened first).** An engineer pastes a support
ticket and the reminder task's code into a session: *"customers sometimes get duplicate
reminder emails — here's the task, what's wrong?"* The assistant replies fluently: the task
isn't deduplicated; concurrent scheduling could enqueue it twice; add a Redis lock keyed on
invoice ID. Plausible, idiomatic, twenty minutes to ship. The duplicates drop but don't stop.
Second round: the assistant, anchored on its concurrency story, proposes a longer lock TTL and
a uniqueness check in the scheduler. Also shipped. A week later a customer gets two emails
*forty minutes apart* — nothing concurrent about it — and the team is now debugging through
two layers of dedup machinery that isn't the bug and never was. Cost so far: three deploys,
zero evidence touched.

**The disciplined path (the re-run).** A senior engineer restarts — fresh session (Chapter
03), and a different first prompt: *"Do not propose fixes. Here are the symptom and the task
code. List hypotheses ranked by likelihood, and for each, the specific evidence in our logs or
data that would confirm or eliminate it."* The agent produces five: double-enqueue by the
scheduler; concurrent workers; **task retry after a partial failure — email sent, then
something after it failed, so Celery retried the whole task**; duplicate rows in the
reminders-due query; and a client-side bounce/resend. Each with a discriminator — for the
retry hypothesis: *the task's log would show two executions with the same task ID, the second
marked as a retry, and the first would show an error after the SMTP call.*

The agent (read-only access to logs) is set to check discriminators, filtered per Chapter 03 —
evidence in, bulk out. The scheduler hypothesis dies (one enqueue per invoice, every affected
case). The retry hypothesis lands exactly as predicted: first execution sends the email, then
crashes writing `reminder_sent_at` — a lock timeout when the invoice row is being updated by a
concurrent payment webhook — and Celery retries the task, which happily sends again. The
forty-minute gap was the retry backoff. **Causal chain, all observed:** lock contention →
exception *after* the irreversible side effect → retry re-runs the side effect. The duplicate
emails were never an email bug; they were a non-idempotent task with the side effect on the
wrong side of the commit.

**The fix and the harvest.** Reproduction first: an integration test that forces the
post-send failure and asserts exactly one email — it fails, with two. The fix follows Stage
3's own idempotency guidance: record-then-send (claim the reminder in its own transaction
*before* the SMTP call), making the retry a no-op — and the two Redis-lock layers from the
undisciplined path are deleted with a note. Verify: repro passes; remove the fix → it fails
again. Harden: regression test committed, and two lessons routed upstream — a line in the
review prompt (Chapter 06: *"flag any task where an external side effect precedes the state
write that records it"*) and a `prompts/tasks/` note for background jobs. Then the honest
postmortem question: the undisciplined path wasn't stupid — the concurrency story *was*
plausible. It was just never tested against a single observation. That's the whole chapter in
one sentence.

## Engineering Decisions

**Decision 1: Who drives the loop — the agent or you?** Delegate the *legs* freely (repro
scripts, instrumentation, log filtering, running discriminators); delegate the *loop* — the
agent autonomously cycling hypothesize-test-fix — only when the bug reproduces deterministically
in a sandbox, the blast radius is a working tree, and the two gates hold mechanically (the
fix must make a previously failing test pass; hypotheses and evidence must be reported, not
just the diff). Keep the wheel yourself when reproduction is flaky, when production data is
involved, or when the symptom spans systems — precisely the cases where a wrong-but-fluent
story does the most damage.

**Decision 2: What may the agent touch while debugging?** Chapter 01's tiers, sharpened for
the activity: read-only against production (logs, metrics, traces — via scoped credentials,
never psql on the prod database), free hand for instrumentation and experiments in dev/test,
and *no cleanup of evidence* — no restarting services, clearing queues, or deleting state
before it's captured, because destroyed state is often the only witness. If a debugging step
would change the system being observed, a human takes it deliberately.

**Decision 3: How many failed fixes before you stop fixing?** Two. The first failed fix is
information; the second failed fix from the same diagnosis means the *diagnosis* is wrong,
and continuing is whack-a-mole with better tooling. The two-strike rule triggers a reset:
fresh session (the old one is anchored — Chapter 03), back to evidence, explicitly
re-derive the hypothesis list without the dead story in the window. Cheap to say, hard to do
at 5 p.m. with a green-looking patch in hand — which is why it's a rule and not a mood.

**Decision 4: When is a symptom patch acceptable?** When it's *chosen*, labeled, and paired
with a debt ticket — the production fire needs out now, the root cause needs a week you don't
have tonight. A conscious mitigation ("retry-once wrapper while we fix the idempotency
properly — TICKET-482") is legitimate incident response. The same patch merged as "the fix"
is the anti-pattern. The discriminator is honesty in the PR description: does it claim to be
a cure or a tourniquet?

**Decision 5: What does "done" require?** Four artifacts, no exceptions: the failing-then-
passing reproduction test, the causal-chain explanation in the PR (every link observed), the
fix at the cause, and the upstream routing — why did the test suite, the review stack, and
the type system all miss this, and which one gets patched so this bug class dies (Chapter 06's
escaped-defect discipline). A bug that produces only a diff has taught nobody anything.

## Trade-offs

| Choice | Gain | Cost |
|---|---|---|
| Agent-driven loop (sandboxed) | Tireless iteration; fast on deterministic bugs | Gates must be mechanical; agent can converge on symptom-stopping if repro test is weak |
| Human-driven, agent as legs | Judgment at every step; anchoring caught early | Slower; your attention is the loop's clock speed |
| Demand ranked hypotheses + discriminators | Kills the single-story anchor; makes evidence the plan | More upfront prompting; feels slower than "just fix it" (isn't, over the week) |
| Accept the first fluent diagnosis | Occasionally right, instantly | When wrong: anchored session, patch layers, recurring bug — the expensive path |
| Reproduction-first, always | Every later step verifiable; regression test for free | Real effort for flaky/prod-only bugs — instrument first, reproduce second |
| Fix-first, reproduce never | Ships in minutes | "Verified" = "symptom not currently visible"; you cannot distinguish fix from coincidence |
| Two-strike reset | Caps sunk cost; kills anchored sessions | Discards momentum that *feels* like progress (it wasn't) |
| Conscious symptom patch + ticket | Incident response speed | Debt is real; the ticket culture must actually pay it, or "conscious" is a fiction |
| One variable at a time | Attribution certainty | Slower than shotgunning — but shotgunning's "speed" is unattributable, unrevertable |

The through-line: every shortcut in debugging trades *attribution* for *speed* — you get the
symptom to stop sooner, at the price of not knowing what stopped it. Attribution is the only
thing that makes a fix a fix.

## Common Mistakes

- **Pasting the stack trace and accepting the first answer.** The founding mistake of AI
  debugging. The model's first response to a trace is a pattern-match, not an investigation —
  treat it as hypothesis #1 of five, ask for the other four and the discriminators, and go
  look.
- **Letting the symptom's disappearance stand in for verification.** "Deployed the patch,
  haven't seen it since" — for an intermittent bug, that's not evidence; that's weather. Only
  a reproduction that failed before and passes after (and fails again when the fix is
  reverted) separates cure from coincidence.
- **Debugging in a polluted window.** The session that already contains the wrong diagnosis,
  three dead-end patches, and 400 lines of pasted logs will keep steering toward its own
  residue (Chapter 03). Failed investigations don't get continued; they get *summarized into
  a debugging log* (evidence kept, stories dropped) and restarted clean.
- **Feeding bulk instead of evidence.** The whole CI log, the whole journal, the raw dump —
  burying the discriminating line under ten thousand others degrades both the agent's
  attention and yours (and Stage 9: logs contain tokens and PII; filter *before* the window,
  not after).
- **Fixing the crash site instead of asking why the value arrived.** The `None` check at the
  point of explosion, the try/except around the failing call — each one moves the symptom
  further from the cause for the next investigator. Ask "who produced this value?" until the
  answer is a decision, not another victim.
- **Skipping the harvest.** Fix merged, ticket closed, nothing routed upstream — the test gap
  that let it ship is still open, and the review prompt still doesn't know about this failure
  class. The bug will be back; you've only guaranteed it'll be a surprise again.
- **Deleting the crime scene.** Restarting the worker, flushing the queue, re-running the
  migration "to see if it clears up" — before capturing state. If it clears up, you've
  converted a reproducible bug into an intermittent legend that haunts the backlog for a
  quarter.

## AI Mistakes

Three assistants, three characteristic ways to make a bug *look* solved.

### Claude Code: the fix at the crash site instead of the cause

Given a trace, Claude Code's strong bias is action at the point of failure: the `KeyError`
gets a `.get()` with a default, the `NoneType` error gets a guard clause, the failing
assertion gets a broader tolerance. Each patch is locally reasonable, ships fast, and makes
the *error* disappear while the *defect* — the upstream code that produced the bad value —
keeps producing it, now silently. The system degrades from "crashes loudly at the symptom"
to "propagates corrupt data politely", which is strictly worse: Stage 3 built fail-fast
boundaries precisely so bugs would announce themselves.

**Detect:** debugging diffs that add defensiveness (guards, defaults, broadened excepts,
widened tolerances) at the trace's last frame; no change to any producer of the bad value;
the same defect class resurfacing at a different call site weeks later.

**Fix:** demand the causal chain before permitting any diff:

> Do not patch where the error surfaced. First trace the value: what produced it, what
> should have produced instead, and at which point the data first became wrong. State the
> full chain from origin to crash with the evidence for each link. The fix goes at the
> first wrong link — if you still believe the crash site needs hardening, that's a separate
> proposal with its own justification.

### GPT: the coherent causal story that evidence never touched

GPT-family models excel at narrative — and a debugging narrative is exactly the wrong thing
to excel at unverified. Asked "why is this happening?", they deliver a confident, internally
consistent mechanism — a race in the cache layer, a stale connection pool, a timezone
mismatch — often invoking components that don't appear in the trace or, occasionally, in the
codebase. The story's fluency is the poison: it reads like a diagnosis from a senior
engineer, gets adopted, and every subsequent observation is interpreted through it
(disconfirming evidence explained away, confirming coincidences promoted). The scenario's
undisciplined path — two deploys of dedup machinery for a concurrency story nobody ever
checked — is this failure, verbatim.

**Detect:** diagnoses referencing components or mechanisms absent from the observed trace;
no proposed observation that could *falsify* the story; explanations that survive
contradicting evidence by growing epicycles ("the lock must sometimes not be acquired…");
your own reluctance to abandon the story after a failed fix — that's the anchor talking.

**Fix:** tie every claim to an observation, and ask for the kill condition:

> For each causal claim in your diagnosis: cite the specific observed evidence (log line,
> variable state, trace frame) that supports it, or label it SPECULATION. Then state what
> observation would falsify your leading hypothesis, and check for it. A diagnosis with no
> falsification condition is a story, and we don't deploy fixes for stories.

### Cursor: the shotgun debug — five changes, one green light, zero attribution

Debugging in a tight edit loop, Cursor-style workflows accumulate simultaneous changes: a
guard here, a config value there, a dependency bump, a tweaked timeout, a reordered call —
applied in one flurry until the test goes green. The symptom is gone; the diff is a grab
bag; and the crucial question — *which change fixed it?* — has no answer. Worse than
unattributable: four of the five changes are untested passengers, any of which may be a new
bug, and none of which can be safely reverted because nobody knows which one is load-bearing.

**Detect:** debugging diffs touching multiple files/concerns with no stated per-change
rationale; version bumps or config changes riding along with logic edits; the honest answer
to "which change fixed it?" being a shrug; symptom fixed but the reproduction test (if any)
never run against intermediate states.

**Fix:** one variable at a time, then subtract back to minimal:

> During debugging, make ONE change per iteration and re-run the reproduction after each —
> record which change altered the behavior. Once the symptom is fixed, revert every change
> that wasn't the one that fixed it, re-run to confirm the fix stands alone, and present the
> minimal diff. Unrelated improvements you noticed go in the notes, not the fix.

## Best Practices

- **Reproduction is assignment #1** — for the agent, before any diagnosis: a test or script
  that makes the bug happen on demand. Can't reproduce yet? Then instrumentation is
  assignment #1, and fixes wait.
- **Prompt for hypotheses, not answers.** "Ranked hypotheses, each with the evidence that
  would confirm or eliminate it — no fixes yet." One sentence that converts the model from
  storyteller to lab partner.
- **Evidence outranks everything.** A single observed log line beats the most elegant
  narrative — the model's, the senior engineer's, yours. When story and observation
  disagree, the story loses, immediately and without appeal.
- **One variable per iteration; revert to minimal.** Attribution is the product. A fix you
  can't attribute is a coincidence you've committed.
- **Keep a debugging log outside the window.** Chapter 03's plan-file discipline: evidence
  gathered, hypotheses killed (and by what), current best chain. Sessions are disposable;
  the log survives resets and briefs the next context — human or agent.
- **Enforce the two gates mechanically where you can.** "Fix must flip a failing test" is a
  CI-checkable property of bug-fix PRs; the causal-chain narrative is a PR-template section
  reviewers actually read (Chapter 06).
- **Two strikes → fresh session, re-derived hypotheses.** The anchor doesn't feel like an
  anchor from inside; the rule exists because your judgment about *when you're anchored* is
  exactly what's compromised.
- **Verify by removal.** Fix in: repro passes. Fix out: repro fails. Anything else and
  something other than your fix is doing the work — find out what.
- **Harvest every bug.** Regression test always; then one routed lesson — the missing test
  class, the review-prompt line, the lint rule, the runbook entry. The bug already cost you
  the tuition; collect the diploma.

## Anti-Patterns

**Whack-a-mole at machine speed.** Symptom → patch → new symptom → patch — the oldest bad
loop, now with an agent generating each patch in ninety seconds. The velocity *feels* like
progress; the system accretes defensive scar tissue; the underlying defect outlives four
"fixes". The tell: the same ticket reopening with mutating symptoms, and a diff history of
guards and retries at ever-shifting locations.

**The oracle consultation.** Describing the bug to the model — no logs, no repro, no code
access — and implementing whatever comes back. This uses the model precisely backwards: its
weakness (unverified narrative) with none of its strength (tireless observation). If the
agent can't observe the system, you don't have a debugging partner; you have a horoscope
with an API.

**Debugging by regeneration.** "This module has a bug — rewrite it." Sometimes the rewrite
accidentally doesn't contain the bug; you've learned nothing, the regression test doesn't
exist, and the defect's *cause* (a wrong assumption that lives in three other modules too)
is untouched. Regeneration is a legitimate refactoring move and a bankrupt debugging one —
the difference is whether you can state what was wrong.

**Fix-by-upgrade.** Bump the framework, the driver, the image tag — "it might be that known
issue". Occasionally right, never attributable, and each speculative bump is an untested
change smuggled into a debugging context. Upgrades are scheduled maintenance with their own
verification (Stage 7), not dice to roll at a symptom.

**The heroic marathon session.** Six hours, one window, forty files read, three dead
theories still in context, and a fix at 2 a.m. that reverts by lunch. The marathon *is* the
anchor: everything Chapter 03 says about residue, at the worst possible time. The
disciplined version — log the evidence, kill the window, sleep, re-derive clean — is not
slower. It just doesn't feel like a movie.

## Decision Tree

"A bug is in front of you — how does the loop run?"

```
Can you reproduce it on demand (test, script, request)?
├── NO ──► Instrumentation phase. Agent adds logging/tracing at
│          the suspected path (read-only toward prod; scoped
│          credentials). Capture state BEFORE any restart/cleanup.
│          Reproduce first; fix later. Production on fire?
│          → conscious mitigation + ticket (Decision 4), and the
│          investigation continues on the captured evidence.
└── YES ──► Encode it: failing test committed to the branch.
    │
    Deterministic in a sandbox, blast radius = working tree?
    ├── YES ──► Agent may drive the loop: ranked hypotheses +
    │           discriminators reported, one variable per
    │           iteration, fix must flip the failing test.
    │           You adjudicate the causal chain (gate 2).
    └── NO ──► You drive; agent runs the legs (instrument,
                filter, execute discriminators).
    │
    Fix candidate in hand — before merge:
    ├── Causal chain narrated, every link OBSERVED? ── no ──► back
    │                                                   to evidence.
    ├── Repro: fails without fix, passes with?      ── no ──► not
    │                                                   a fix yet.
    ├── Fix at the CAUSE (not the crash site)?      ── no ──► trace
    │                                                   the value up.
    └── All yes ──► merge with: regression test + chain in PR +
                    one lesson routed upstream (test gap, review
                    prompt, lint rule).

    Two fixes from the same diagnosis have failed?
    └──► STOP. Fresh session. Evidence only. Re-derive the
         hypothesis list without the dead story in the window.
```

## Checklist

**Debugging Judgment Checklist**

- [ ] Reproduction exists (or is explicitly impossible — and instrumentation, not fixing, is
  the current phase)
- [ ] Hypotheses were ranked with discriminating evidence per hypothesis — not one story
- [ ] Every accepted causal claim traces to an observation (log, state, trace) — speculation
  is labeled as such
- [ ] One variable changed per iteration; the final diff is the minimal fix (passengers
  reverted)
- [ ] Verified by removal: fix out → repro fails; fix in → passes; suite green
- [ ] The fix is at the cause; any crash-site hardening is a separate, justified change
- [ ] Two-strike rule honored: no third fix from a twice-failed diagnosis; session reset
  happened
- [ ] Evidence preserved before any state-destroying action; nothing sensitive pasted
  unfiltered into the window
- [ ] Debugging log (plan file) current: evidence, killed hypotheses, chain — survives the
  session

**Code Review Checklist** (bug-fix PRs)

- [ ] PR narrates the causal chain, cause → symptom, with the evidence — not just "fixes
  #482"
- [ ] Regression test present; reviewer confirmed it fails on the pre-fix code (run it, don't
  trust it)
- [ ] Diff is minimal and at the cause; defensive additions at the symptom site are flagged
  and separately justified
- [ ] No test was weakened, skipped, or retuned to make the fix "work" (Ch 04's letter-vs-
  intent, at its most tempting site)
- [ ] Symptom patches are labeled as mitigations with a linked root-cause ticket — no
  tourniquets sold as cures
- [ ] The upstream lesson shipped: what gap let this bug in, and which layer (test / review
  prompt / lint / runbook) got patched

## Exercises

1. **Re-litigate an old bug.** Take a bug your team fixed in the last quarter. From the
   ticket and diff alone: was there a reproduction? Can anyone narrate the causal chain
   today? Was the fix at the cause or the crash site? Did anything route upstream? Score it
   against this chapter — then run the same audit on the *next* bug, live.
2. **Practice the hypothesis prompt.** On your next real bug, forbid fixes for the first
   session: "ranked hypotheses + discriminating evidence only." Run the discriminators. Count
   how many of the model's initial hypotheses died on contact with evidence — that count is
   what accepting answer #1 would have cost you.
3. **Stage the retry bug.** Build the scenario's defect in a sandbox: a task that performs an
   external side effect, then fails before recording it, under a retry policy. Hand an agent
   the symptom ("duplicate side effects, intermittent") and drive the disciplined loop to the
   idempotency fix — reproduction, discriminators, chain, minimal diff, verify by removal.
4. **Catch the shotgun.** Give an agent a seeded bug and let it debug without constraints;
   diff the result and count the passenger changes. Re-run with the one-variable/revert-to-
   minimal protocol. Compare the two diffs — and how confidently you can answer "what fixed
   it?" for each.
5. **Run a two-strike drill.** Mid-investigation, after a failed fix, deliberately reset:
   summarize evidence to the debugging log, kill the session, re-derive hypotheses clean.
   Compare the fresh list to the anchored session's fixation. Most engineers meet their own
   anchoring for the first time in this exercise — better here than during an incident.

## Further Reading

- David J. Agans — *Debugging: The 9 Indispensable Rules* — the classical discipline
  ("understand the system", "make it fail", "change one thing at a time") this chapter
  re-derives for the agent era; every rule survives AI intact.
- Andreas Zeller — *Why Programs Fail: A Guide to Systematic Debugging* — the scientific
  method applied to defects, including automated hypothesis-narrowing (delta debugging) that
  prefigures agent-driven loops.
- [Google SRE Book — Postmortem Culture: Learning from Failure](https://sre.google/sre-book/postmortem-culture/)
  — the harvest step at organizational scale: blameless, evidence-first, action-item-routed.
- Chapter 03 ([Context Engineering](03-context-engineering.md)) — session resets, debugging
  logs as externalized state, and evidence-filtering: the window mechanics under the
  two-strike rule.
- Chapter 06 ([AI Code Review](06-ai-code-review.md)) — where bug-fix PRs get their gates
  enforced, and where escaped-defect lessons get routed.
- Stage 8 ([Test Strategy](../stage-08-testing/01-test-strategy.md)) — the regression-test
  discipline this chapter's "harden" step deposits into.

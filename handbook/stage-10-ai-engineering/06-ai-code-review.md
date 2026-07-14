# AI Code Review

## Introduction

This chapter is about code review in both directions at once: **reviewing code that AI wrote**,
and **using AI to review code**. They arrive together because the same event created both — when
generation became cheap, review became the bottleneck, and the bottleneck is where engineering
attention now lives.

The first direction is a human discipline with a twist. AI-generated code defeats the instincts
that catch human mistakes: it is plausible by construction — consistent naming, confident
structure, idiomatic style — so the "something looks off" reflex that flags a tired colleague's
bug stays silent. Reviewing it well means replacing fluency-based reading with structural,
adversarial checking: against the spec, against the invariants, against the known failure
patterns that this handbook's [code review checklist](../../checklists/code-review.md) compresses
into its AI-generated-code section.

The second direction is an engineering project: an AI reviewer is tireless, fast, and reads every
line of every diff — properties no human reviewer has — while lacking the things only humans
have: knowledge of intent, product context, and accountability. Built well, an automated review
pass raises the floor (nothing merges with the dumb mistakes) and frees human attention for the
top (design, product, risk). Built badly, it becomes a nit cannon everyone ignores, or worse, a
rubber stamp that launders unreviewed code into production. This chapter builds the well-made
version on Invoicely and draws the line that never moves: AI review informs the merge decision;
it never owns it.

## Why It Matters

- **The volume asymmetry is the defining constraint of AI-first engineering.** An agent produces
  a day's worth of diffs in an hour; your review capacity didn't change. Every stage-10 practice
  so far (specs, scope limits, small PRs) manages this asymmetry from the generation side; review
  is where you manage it from the consumption side — or where it silently defeats you via
  rubber-stamping.
- **Plausibility inverts the risk profile.** Human bugs cluster where code looks rushed or
  confused; AI bugs hide inside code that reads *better* than your median PR. The five-line diff
  that renames confidently, the test file that exercises only success, the error handler that
  logs and continues into a corrupt state — each passes the skim test. Review that relies on
  "does it read well?" now selects *for* the failure mode.
- **Accountability doesn't compress.** When the discount calculation is wrong in production,
  "the agent wrote it and the bot approved it" is not an answer anyone accepts — Stage 1's rule
  that AI makes no unreviewed engineering decisions lands here at its sharpest point. Someone
  merges; that someone answers.
- **Review is where the system learns.** Chapter 04's iteration loop routes review findings
  upstream — into prompts, instruction files, hooks. A team that reviews well gets an agent
  configuration that improves weekly; a team that rubber-stamps freezes its failure rate at
  week one. The review comment is the raw material of the whole feedback economy.
- **An AI first pass changes the economics of everything else.** The fan-out ceiling in Chapter
  05 was same-day human review; a trustworthy automated pass that catches the mechanical 60%
  raises that ceiling directly. This is the multiplier that makes the rest of the stage's
  throughput gains real — which is why it's worth engineering properly instead of installing as
  a checkbox.

## Mental Model

Review is a filter stack. Each layer catches what it is structurally best at, and human
attention — the scarcest input — is spent only where the layers below can't reach.

```
        THE REVIEW FILTER STACK (cheapest first, judgment last)
  ┌────────────────────────────────────────────────────────────┐
  │ L0  MECHANICAL GATES (CI: tests, lint, types, hooks)       │
  │     catches: the objectively wrong. Free, deterministic.   │
  │     If a review comment could be a lint rule, it must be.  │
  ├────────────────────────────────────────────────────────────┤
  │ L1  AI FIRST PASS (breadth, tireless, every line)          │
  │     catches: known failure patterns, spec drift, missing   │
  │     tests, security smells, cross-file inconsistency —     │
  │     ADVISORY: posts findings w/ severity + evidence        │
  ├────────────────────────────────────────────────────────────┤
  │ L2  HUMAN JUDGMENT PASS (depth, risk-weighted)             │
  │     catches: wrong design, wrong product behavior, wrong   │
  │     trade-off, "should this exist?" — and adjudicates L1   │
  │     OWNS: the merge decision. Always.                      │
  └────────────────────────────────────────────────────────────┘
   Attention flows DOWN by risk: schema/auth/money get deep L2;
   mechanical diffs may get L0+L1 and an L2 skim. But L2 never
   disappears — it shrinks to fit the risk, not the schedule.

        REVIEWING AI CODE: WHERE THE BUGS ACTUALLY ARE
   fluency signals (naming, style, confidence)  → USELESS (all AI
                                                   code has them)
   the spec's acceptance criteria               → check ABSENCES
   the tests (read first, before the code)      → what do they
                                                   actually assert?
   the decision level                           → what choices does
                                                   this diff embody,
                                                   and who made them?
   the known failure patterns (the checklist)   → hallucinated APIs,
                                                   happy-path tests,
                                                   scope creep, stale
                                                   idioms, permissive
                                                   defaults...
```

**Review against the spec, not the diff.** The diff shows what happened; only the spec knows
what should have. Chapter 04 built acceptance criteria precisely so review could start from
them — absences first (the missing 404 case, the skipped criterion), then correctness of what's
present. A diff-first review of AI output reliably approves beautiful, incomplete work.

**Read the tests first.** In AI output, tests are the confession: they encode what the agent
believed the requirements were. Weak assertions, happy-path-only coverage, or a test that
mirrors the implementation rather than the behavior tell you more in ninety seconds than an
hour in the implementation files.

**The AI reviewer and the human reviewer are different instruments.** The AI pass has breadth
(every line, every time, no fatigue, no ego) and no knowledge of what you actually meant; the
human pass has intent, product sense, and accountability, and cannot sustain line-level
attention across ten agent PRs a day. The stack works when each instrument plays its part —
and fails when either is asked to substitute for the other.

A working definition:

> **AI code review is a two-sided discipline: humans reviewing plausible-by-construction
> generated code structurally — spec-first, tests-first, decision-level, against known failure
> patterns — and an engineered AI first pass that applies breadth (every line, every PR) as an
> advisory filter below the human judgment pass. The stack's invariant: mechanical checks catch
> the wrong, AI catches the patterned, humans judge the intended — and only humans merge.**

## Production Example

**Invoicely's** review load changed shape in one quarter. Before agents: four or five
human-written PRs a week, reviewed thoroughly by habit. After Chapters 01–05: fifteen to twenty
PRs a week, most agent-written, each individually plausible. The team's first response was the
honest one — review got shallower, and two incidents followed: a webhook handler whose
`except Exception: log and continue` corrupted retry state (merged because it "looked
defensive"), and an export endpoint that leaked soft-deleted invoices because nobody checked the
absence of a filter the spec required.

The rebuilt pipeline is the filter stack. **L0** was mostly in place (Stage 8 tests, lint,
types, Chapter 01 hooks) — the team added a diff-budget check that flags PRs exceeding their
brief's declared scope. **L1** is a headless review pass (the workflow below) that runs on every
PR: it receives the diff, the PR's brief, and the repo's review prompt; it posts findings as
comments with severity, file:line anchors, and evidence; it is configured to stay silent on
anything lint already owns. **L2** is the human pass, re-scoped: start from the brief's
acceptance criteria, read the tests first, walk the
[AI-generated-code checklist](../../checklists/code-review.md) for agent PRs, spend depth on
risk (anything touching money, auth, tenancy, or migrations gets full attention regardless of
size), and adjudicate the L1 findings — each one confirmed, rejected with a reason, or routed
upstream into a prompt or rule.

Two numbers the team tracks make the system honest: the L1 **false-positive rate** (rejected
findings ÷ total; when it climbs, the review prompt gets tuned, because a noisy bot trains
humans to ignore it) and **escaped defects** (bugs found post-merge, tagged by which layer
should have caught them). The webhook incident, replayed through the new stack, dies at L1 —
"error handler continues after failure without resetting state" is exactly the patterned
finding an AI pass catches every single time.

## Folder Structure

```
invoicely/
├── prompts/
│   └── review/
│       ├── pr-review-pass.md      # THE review prompt: scope, severity rubric,
│       │                          #   output contract, noise suppression — versioned
│       │                          #   and tuned like any production artifact
│       └── security-pass.md       # deeper pass for risk-tier PRs (Stage 9's
│                                  #   judgment, operationalized)
├── .github/
│   └── workflows/
│       └── ai-review.yml          # L1 wiring: headless agent on every PR, posts
│                                  #   advisory comments; NO approve/merge rights —
│                                  #   the permission model encodes "advisory"
├── checklists/
│   └── code-review.md             # the human L2 instrument (this handbook ships
│                                  #   one; teams keep theirs in-repo, versioned)
└── docs/
    └── review-metrics.md          # false-positive rate, escaped defects by layer,
                                   #   findings routed upstream — the numbers that
                                   #   keep the stack honest
```

Why this shape: the review prompt is **a versioned production artifact** (it will be tuned
weekly at first — that history belongs in git, reviewed like code, per Chapter 04's library
rules); the workflow's *permissions* — not its prose — are what make L1 advisory (a bot that
cannot approve cannot be promoted to gatekeeper by cultural drift); and the metrics file exists
because a review system you don't measure decays silently into either noise or theater.

## Implementation

### The review prompt — engineered against noise

`prompts/review/pr-review-pass.md` (condensed):

```markdown
You are reviewing a pull request for Invoicely. You have read access
to the full repository — use it: verify claims against the actual
code, don't review the diff in a vacuum.

INPUTS: the diff; the task brief (acceptance criteria included);
docs/architecture.md.

REVIEW FOR, in order:
1. Spec adherence — walk the brief's acceptance criteria one by one;
   flag every criterion not demonstrably met. Check ABSENCES: what
   the spec requires that the diff does not contain.
2. Correctness — failure paths, edge boundaries (zero/one/many/max),
   concurrency on shared state, idempotency of external calls.
3. Invariants — tenant scoping on every new query (ADR-0012), money
   as integer cents (ADR-0007), migrations additive (docs map).
4. Tests — read them: do assertions encode the required behavior?
   Would they fail if the behavior broke? Flag weakened/skipped tests.
5. Scope — anything in the diff the brief doesn't explain.

DO NOT COMMENT ON: formatting, naming, import order, or anything
lint/typecheck enforces. If it would pass CI, style is settled.

OUTPUT CONTRACT — findings only, no code rewrites, no praise:
- [BLOCKER|WARN|NOTE] file:line — one-sentence finding.
  Evidence: what you checked (file you read, criterion it violates).
- BLOCKER = wrong or violates an invariant. WARN = probable defect
  or unproven criterion. NOTE = worth a human glance.
- If you are unsure, say unsure — a wrong BLOCKER costs trust.
- End with: criteria checked ✓/✗ table, and "areas I could not
  verify" (be explicit; silence reads as approval).
```

Every design choice here is anti-noise: the lint exclusion kills the nit flood, the evidence
requirement kills vibes-based findings, the severity rubric makes triage cheap, the
unsure-clause and could-not-verify section replace false confidence with useful honesty, and
the findings-only contract (no rewrites) keeps the reviewer a reviewer.

### The CI wiring — advisory by permission, not by promise

`.github/workflows/ai-review.yml` (shape, not gospel — adapt to current action/CLI docs):

```yaml
name: AI review (advisory)
on:
  pull_request:
    types: [opened, synchronize]

permissions:
  contents: read
  pull-requests: write        # comment — deliberately NOT approve

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - name: Run review pass
        run: |
          gh pr diff ${{ github.event.number }} > pr.diff
          claude -p "$(cat prompts/review/pr-review-pass.md)

          BRIEF: $(gh pr view ${{ github.event.number }} --json body -q .body)
          DIFF:  $(cat pr.diff)" \
            --allowedTools "Read,Grep,Glob" \
            > findings.md
          gh pr comment ${{ github.event.number }} --body-file findings.md
        env:
          GH_TOKEN: ${{ github.token }}
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

The load-bearing details: **read-only tools** (a reviewer that can edit "fixes" its findings
unreviewed — Chapter 05's echo chamber), **comment-not-approve permissions** (the advisory line
enforced by the platform, immune to prompt drift), and **the brief travels with the diff**
(review against the spec requires the spec — a reviewer given only the diff can only review
what's there, never what's missing). Branch-protection rules stay human: required approvals
come from people.

### The human pass — a protocol, not a vibe

For agent-written PRs, L2 runs in this order:

1. **Brief first.** Read the acceptance criteria before any code. Walk the author's self-check
   table (Chapter 04) and verify one claimed item yourself at random.
2. **Tests second.** Read every new/changed test. Ask of each: would this fail if the behavior
   broke? Happy-path-only coverage is a finding, not a style preference.
3. **Decisions third.** Scan the diff for choices the brief didn't make — defaults, limits,
   error semantics (Chapter 04's silent-decision failure). Each is either flagged in the PR as
   an assumption, or it's a finding.
4. **Checklist last.** The [AI-generated-code section](../../checklists/code-review.md) —
   hallucinated APIs, stale idioms, duplicated helpers, permissive security defaults — walked
   explicitly on any PR touching risk.
5. **Adjudicate L1.** Every bot finding gets confirmed (fix), rejected (reply with the reason —
   this is the tuning data), or promoted upstream (prompt/rule/hook, per the Chapter 04
   routing).

Time-box by risk tier, not by diff size: a 40-line migration outranks a 400-line test backfill.

## Engineering Decisions

**Decision 1: Is the AI pass advisory or blocking?** Advisory by default, and enforce that with
permissions, not promises. Blocking is earned, narrowly: after months of false-positive data, a
team may promote *specific high-precision finding classes* (say, "new query missing tenant
scope") to CI-blocking — effectively graduating them from L1 to L0, which is the healthy
direction of travel. Blanket-blocking on "the bot objects" imports the bot's full false-positive
rate into everyone's merge path, and the team routes around it within a month.

**Decision 2: Same rigor for human and AI code?** Same standard, different priors. The checklist
is one; the *emphasis* shifts — human PRs earn attention where the author seemed uncertain; AI
PRs earn it where the checklist says the failure patterns live (absences, tests, decisions,
security defaults), because uncertainty signals don't exist in generated code. What must not
vary: the merge bar itself. A lower bar for agent PRs because "the bot already looked" is the
stack eating itself.

**Decision 3: Who reviews what — and may the author's agent review its own PR?** No — Chapter
05's independence rule. The L1 pass runs in CI from a clean context, never in the author's
session; a human other than the delegating engineer reviews anything risk-tiered (the engineer
who wrote the brief shares the author's blind spots — they *are* the author, at the decision
level). Small teams bend this for mechanical diffs; nobody bends it for money, auth, tenancy,
or schema.

**Decision 4: What does the bot stay silent about?** Everything a cheaper layer owns.
Style/formatting/imports → lint (L0). Test execution → CI (L0). Preferences with no defect
consequence → nothing (delete them from the prompt). The review prompt's exclusion list is as
load-bearing as its checklist: every class of noise you fail to exclude taxes every future PR's
triage, and the compound interest on that tax is a team that stops reading the bot entirely.

**Decision 5: How do you keep the system honest over time?** Two metrics, one ritual. Track the
false-positive rate per finding class (tune or delete noisy classes monthly) and escaped defects
by should-have-caught layer (each one patches the layer that missed it: a lint rule, a prompt
line, a checklist item). The ritual: rejected findings get a one-line reason in the PR — that
thread *is* the tuning dataset, and it costs nothing at the moment of rejection.

## Trade-offs

| Choice | Gain | Cost |
|---|---|---|
| AI first pass on every PR | Breadth, tirelessness; floor raised; fan-out ceiling lifted | Token cost per PR; false positives to triage; risk of "the bot looked" complacency |
| No AI pass | Zero noise, zero cost | Human attention spent on patterned findings a machine catches; floor varies by reviewer fatigue |
| Advisory bot | Trust preserved; humans stay the gate | Findings can be ignored wholesale without the triage ritual |
| Blocking bot | Nothing merges past known patterns | Full false-positive rate lands in the merge path; workaround culture within weeks |
| Spec-first human review | Catches absences; reviews what should exist | Requires the Ch 04 discipline upstream — no brief, no spec-first review |
| Diff-first human review | No prerequisites | Structurally blind to missing criteria; approves beautiful incompleteness |
| Deep review of everything | Maximum catch rate | Doesn't survive AI-era volume; decays into uniform shallowness |
| Risk-tiered depth | Attention lands where mistakes are expensive | Requires an honest risk map (Stage 9); mechanical diffs get real but thin review |
| Tracking review metrics | System tunes instead of decays | Someone owns the numbers; crude metrics invite gaming (see Anti-Patterns) |

The central trade-off is **trust calibration**: every false positive spends the bot's
credibility, every escaped defect spends the stack's, and both currencies refill slowly. The
design bias that follows: start the bot narrow and high-precision (few finding classes, strong
evidence requirements), widen as trust data accumulates — never the reverse.

## Common Mistakes

- **Rubber-stamping the green checkmark.** CI passed, the bot commented twice, the diff is
  long — approve. This is the volume asymmetry winning. The protocol exists precisely for the
  PRs you're tempted to skim; the risk tier, not your calendar, decides depth.
- **Implementing every bot suggestion.** The inverse failure: treating L1 findings as
  instructions. A reviewer — human or AI — can be wrong, and generated findings carry the same
  plausible-confidence as generated code. Verify against the code and the spec before acting;
  push back with evidence when the finding is wrong (rejection reasons are tuning data, not
  rudeness).
- **Reviewing the PR description instead of the diff.** Agent-written descriptions are
  excellent — fluent, structured, and occasionally describing code that isn't quite what got
  committed. The checklist's first line exists for this: verify claims against the diff.
- **Skipping the tests because they're "just tests".** In AI output the tests are the highest-
  signal files in the diff — they are the agent's understanding of the requirements, written
  down. Reviewing implementation before tests is reading the answer before the question.
- **Letting scope creep through because it's good.** The diff includes an unrequested refactor,
  and it's genuinely nice — merge? No: unrequested changes got no spec, no targeted tests, and
  no decision to exist (Chapters 02/04). Harvest to a ticket; keep the diff scoped.
- **The unowned bot.** The review workflow was installed in an enthusiastic afternoon and never
  touched again. Six months later it comments in a stale prompt's voice about a convention the
  team abandoned, and everyone scrolls past it. An unowned reviewer isn't neutral — it actively
  teaches the team to ignore review comments as a genre.
- **Confusing review with QA.** The stack reviews *code*; it does not exercise the product.
  "L1 found nothing and L2 approved" does not replace running the feature (Stage 8's
  verification discipline) — review catches what reading can catch.

## AI Mistakes

The reviewer's chair changes the failure modes — these are the three assistants *as reviewers*,
and each one degrades a different layer of the stack.

### Claude Code: the reviewer that starts redesigning

Asked to review, Claude Code drifts from findings into authorship: alternative implementations
sketched in full, refactors proposed beyond the diff's scope, a rewritten version of the
function "for clarity" — thorough, often technically sound, and corrosive to the stack. The
author (human or agent) now faces a second design opinion instead of a defect list; triage cost
explodes; and the actual BLOCKER — buried between two elegant suggestions — gets lost in the
essay. A reviewer that redesigns has silently left the reviewer role.

**Detect:** review output containing code blocks longer than a few lines; findings phrased as
"consider restructuring…" without a defect attached; more suggestions than checks; the
acceptance-criteria table missing because the reviewer spent its effort elsewhere.

**Fix:** pin the role with the output contract, and reject essays in triage:

> You are reviewing, not co-authoring. Output findings only, in the [SEVERITY] file:line
> format, each anchored to a defect or an unmet criterion — no rewrites, no alternative
> implementations, no style opinions. If you believe a redesign is warranted, that is ONE
> finding: "[NOTE] design concern — <one sentence>", and nothing more. Complete the criteria
> table before any optional observations.

### GPT: the sycophantic pass that praises its way past the defect

GPT-family reviewers pattern-match "review" toward summary-plus-encouragement: a paragraph
restating what the PR does, three compliments about clean structure, two trivial observations
("consider a docstring"), and an approving conclusion — with the actual defect unmentioned
because nothing forced a check-by-check pass. It reads like review, satisfies the process box,
and filters nothing. This is the reviewer-side twin of Chapter 04's letter-vs-intent failure:
the *form* of review without its function.

**Detect:** review output with no BLOCKER/WARN distribution over many PRs (real code isn't that
clean); no file:line anchors; praise sentences at all; the same generic observations across
unrelated diffs; a missing or all-✓ criteria table on a PR you know has a gap.

**Fix:** structure that makes vagueness impossible, and audit with seeded defects:

> For each acceptance criterion and each checklist class (failure paths, invariants, tests,
> scope): state what you CHECKED — the files read, the specific thing verified — and the
> result, even when the result is "no issue found". No summaries of the PR, no praise. A
> review with no negative findings must still show its checks. (And operationally: seed a
> known defect into a test PR quarterly — a reviewer that passes it gets its prompt fixed
> before its findings get trusted.)

### Cursor: the diff-local reviewer blind to the system

In-editor review flows anchor on the diff hunks — and a reviewer that sees only the hunks can
only find hunk-local problems. Cursor's characteristic miss: the change is internally flawless
and breaks something it can't see — the new query is clean but bypasses the tenant-scoping
mixin the base class provides; the renamed field is consistent in the diff and unrenamed in
the three callers outside it; the migration is fine alone and collides with the sequence on
main. Verdict: approve. Every finding is true; the review is still wrong, because the unit of
correctness is the system, not the diff.

**Detect:** findings that never reference a file outside the diff; approvals on changes to
shared surfaces (base classes, registries, contracts) with no evidence of caller/implementor
checks; integration failures post-merge on PRs whose review reads clean.

**Fix:** force the context walk, and give the reviewer the repo:

> Before any verdict: for every symbol this diff modifies or newly references, read its
> definition and its callers OUTSIDE the diff; for every new query, read the base
> class/mixin chain it inherits; check docs/architecture.md invariants against the change.
> List the out-of-diff files you read as evidence. A review citing no file beyond the diff is
> incomplete. (Wiring-side: the L1 pass gets read access to the whole repo — a diff-only
> reviewer is a proofreader, not a reviewer.)

## Best Practices

- **Spend human attention by risk tier, mechanically.** Money, auth, tenancy, schema, security
  controls → full-depth L2 every time, any size. Mechanical diffs → L0+L1 plus protocol-order
  L2 skim. Write the tiers down so depth isn't a mood.
- **Brief → tests → decisions → checklist → adjudicate.** The L2 protocol in that order; the
  order is the point (absences before presence, confessions before claims).
- **Keep the bot narrow, evidenced, and lint-silent.** Few finding classes, evidence per
  finding, severity rubric, explicit exclusions. Precision buys the trust that recall spends.
- **Enforce "advisory" with permissions.** Read-only tools, comment-only rights, human-only
  approvals in branch protection. Culture drifts; permission models don't.
- **Adjudicate every L1 finding visibly.** Confirm, reject-with-reason, or route upstream.
  The rejection reasons are your tuning dataset; the routing is Chapter 04's loop closing.
- **Read tests first, always, on generated PRs.** Ninety seconds in the test file beats an hour
  of implementation-reading for finding out what the agent thought you meant.
- **Track two numbers, own them monthly.** False-positive rate per finding class; escaped
  defects per should-have-caught layer. Tune or delete what the numbers indict.
- **Seed defects periodically.** A quarterly test PR with a known bug tells you whether L1
  still catches and whether L2 still reads. Trust, but verify the verifiers.
- **Keep the merge human, permanently.** Not as ceremony — as the accountability anchor the
  whole stack hangs from. The moment "who approved this?" has no human answer, the system has
  failed regardless of its metrics.

## Anti-Patterns

**LGTM-as-a-service.** The bot comments, CI is green, a human types "LGTM" without opening the
files — three layers of theater, zero layers of review. Distinguishable from a working stack by
one question per merged PR: *name one thing you verified.* If the answer is "the checks passed,"
L2 has dissolved and the stack is L0 wearing a trench coat.

**The nit cannon.** A review bot with no exclusion list and no severity rubric, firing twenty
comments per PR — imports, naming, docstrings, "consider…". Within a month the team has learned
one lesson perfectly: bot comments are scroll-past material. The cannon didn't just waste its
own findings; it inoculated the team against the genre, so the eventual real BLOCKER dies in
the same scroll.

**The dual rubber stamp.** Agent writes, bot approves, human waves — the failure the volume
asymmetry is always pushing toward. Everything *looks* reviewed (comments exist! checks
passed!), and no judgment touched the change. The tell: review latency near zero on PRs
touching risk tiers. The fix is never "review harder" as an exhortation; it's the protocol,
the tiers, and the metrics making non-review visible.

**Review-speed leaderboards.** Measuring reviewers on time-to-approve or PRs-per-day. You get
what you measure: fast approvals, which means shallow ones, which means the stack's most
expensive layer optimizing itself into decoration. If you must measure review, measure escaped
defects and adjudication quality — the outputs, not the throughput.

**The self-adjusting reviewer.** Letting the review agent update its own prompt ("stop flagging
this") in response to author pushback — including *agent* author pushback. The reviewer's
standards are team policy (Chapter 01: policy changes are human-reviewed); a reviewer that
negotiates its rubric with the reviewed converges on approving everything, one reasonable
concession at a time.

## Decision Tree

"A PR is open — how much review does it get, and from whom?"

```
Does the diff touch a risk tier (money, auth, tenancy, schema,
security controls, external contracts)?
├── YES ──► Full stack, full depth: L0 + L1 + deep human L2
│           (protocol order, checklist walked, out-of-diff
│           context checked). Reviewer ≠ brief author. Any
│           size — 40 risky lines outrank 400 safe ones.
└── NO ──► Is it agent-written?
    ├── YES ──► Was there a five-clause brief (Ch 04)?
    │   ├── NO ──► Stop. The PR isn't reviewable against intent —
    │   │          write the criteria now (or reject and re-run
    │   │          the task properly). Diff-only review of
    │   │          spec-less agent work = approving guesses.
    │   └── YES ──► L0 + L1 + protocol L2: criteria table
    │              verified, tests read, decisions scanned,
    │              L1 findings adjudicated. Depth ∝ diff's
    │              blast radius, never ∝ its eloquence.
    └── NO (human-written) ──► Standard checklist review; L1
               pass still runs (humans also miss patterned
               defects — the floor is for everyone).

After every review, one routing question (Ch 04's loop):
    finding would recur? → prompt / AGENTS.md / lint / hook.
    bot finding rejected? → reason in thread (tuning data).
    defect escaped later? → patch the layer that should've
    caught it — not just the code.
```

## Checklist

**Implementation Checklist** (building the review stack)

- [ ] Review prompt versioned in-repo: ordered scope, severity rubric, evidence requirement,
  output contract, lint-owned exclusions, unsure/could-not-verify clauses
- [ ] CI wiring: reviewer gets diff + brief + repo read access; read-only tools;
  comment-not-approve permissions; secrets via CI store (Stage 9 Ch 04)
- [ ] Branch protection: required approvals are human; bot cannot satisfy them
- [ ] L2 protocol written and tiered (brief → tests → decisions → checklist → adjudication)
- [ ] Risk tiers documented — which paths always get deep human review
- [ ] Metrics live: false-positive rate per finding class; escaped defects per layer
- [ ] Seeded-defect audit scheduled

**Architecture Checklist**

- [ ] Filter stack ordered cheap-to-judgment: anything expressible as lint/CI moved to L0;
  L1 advisory; L2 owns the merge — permanently
- [ ] Reviewer independence: L1 runs clean-context in CI, never in the author's session;
  brief author ≠ sole reviewer on risk tiers
- [ ] Findings loop closed: adjudications route upstream (prompt/rule/hook), rejections
  captured as tuning data
- [ ] Bot trust managed as a budget: narrow high-precision start, widened only with
  false-positive data
- [ ] Review standards are team policy: prompt changes PR-reviewed, never self-adjusted

**Code Review Checklist**

- For the full instrument, use [checklists/code-review.md](../../checklists/code-review.md) —
  including its AI-generated-code section. Chapter-specific additions:
- [ ] Review started from the brief's acceptance criteria; absences checked before presence
- [ ] Tests read first; each new test would fail if its behavior broke
- [ ] Every decision in the diff traces to the spec or a flagged assumption
- [ ] Every L1 finding adjudicated: confirmed / rejected-with-reason / routed upstream
- [ ] Out-of-diff blast radius checked on shared surfaces (callers, base classes, registries)
- [ ] Named one thing you verified — if you can't, the review didn't happen

## Exercises

1. **Audit your last ten merges.** For each agent-written PR your team merged: was there a
   brief? Were the tests read? Can the approver name one verified thing? Score the stack
   layer-by-layer — the empty cells are your current escape routes for defects.
2. **Build and tune the L1 pass.** Wire the advisory workflow on a real repo. Run it on the
   last five merged PRs (retroactively) and triage every finding: confirmed / false / noise.
   Rewrite the prompt's exclusions and rubric from that triage. Two iterations of this loop
   typically halves the noise — measure it.
3. **Seed three defects.** Plant a happy-path-only test suite, a missing tenant filter, and a
   log-and-continue error handler in a test PR. Run your full stack. Which layer caught each —
   and which caught nothing? Patch the layer, not just your pride, and re-run.
4. **Race the protocol against the skim.** Two reviewers, one agent-written PR with a subtle
   spec absence (or use exercise 3's). One reviews diff-first by habit; one runs
   brief → tests → decisions. Compare findings and time spent. The protocol usually wins on
   both — collect your own evidence, because "review differently" only sticks with receipts.
5. **Close one loop end-to-end.** Take a real review finding from this week and route it all
   the way upstream: the prompt line or lint rule or hook that makes it structurally
   unrepeatable, PR'd and merged. Then find the next PR where it *would* have recurred and
   didn't. That un-happened defect is the whole chapter in one artifact.

## Further Reading

- [checklists/code-review.md](../../checklists/code-review.md) — this handbook's review
  instrument; this chapter is the judgment behind its items, especially the AI-generated-code
  section.
- [Google Engineering Practices — Code Review Developer Guide](https://google.github.io/eng-practices/review/)
  — the canonical human-review discipline this chapter's stack extends; its "speed vs.
  thoroughness" guidance predates AI and survives it.
- [Anthropic — Claude Code GitHub Actions documentation](https://code.claude.com/docs/en/github-actions)
  — current wiring for headless review passes in CI; trust it over this chapter's YAML snapshot.
- Chapter 04 ([Prompt Engineering](04-prompt-engineering.md)) — the briefs and acceptance
  criteria that make spec-first review possible, and the upstream routing loop this chapter
  closes.
- Chapter 05 ([Multi-Agent Systems](05-multi-agent-systems.md)) — reviewer independence as a
  context property; why the author's session never reviews its own work.
- Stage 9 ([Security](../stage-09-security/README.md)) — the risk map that decides where
  full-depth human review is non-negotiable.

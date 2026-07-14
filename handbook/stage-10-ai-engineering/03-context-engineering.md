# Context Engineering

## Introduction

An AI agent's output is a function of two inputs: what it knows when it acts (context) and what
you ask of it (the prompt). This chapter is about the first input — the more powerful and the
less visible of the two. **Context engineering is the discipline of controlling what is in the
model's context window**: curating what loads every session, structuring your repository and
documentation so the agent can retrieve the right knowledge at the right moment, and managing the
window over a session's lifetime so the current task isn't buried under the residue of previous
ones.

The context window is everything the model sees when deciding its next action: system prompt,
instruction files, the conversation so far, every file it has read, every command output it has
observed. It is finite, it is expensive, and — critically — it is the *only* thing the model
knows about your system. The model has broad training knowledge about FastAPI and PostgreSQL; it
has zero knowledge of Invoicely's tenant-isolation invariant, your deprecated billing module, or
the decision you made in March about money handling — unless those facts reach the window. Every
agent failure that gets blamed on "the model being dumb" divides, on inspection, into two piles:
facts that never reached the window, and a window so polluted the facts drowned. Both piles are
engineering problems, and this chapter is how you solve them.

Chapters 01 and 02 built the *always-loaded* layer (instruction files). This chapter builds
everything around it: the on-demand knowledge layer, the retrieval structure, and session
hygiene. Chapter 04 then covers the second input — the prompt.

## Why It Matters

- **Context explains more output variance than anything else you control.** The same model, same
  prompt, same task produces conventional code in a well-contextualized repo and plausible-but-
  foreign code in a bare one. Engineers burn weeks tuning prompts and switching models to fix
  what is actually a missing paragraph of context.
- **The window is a budget, and quality degrades before it runs out.** Long before hard limits,
  models attend less reliably to material buried in the middle of a huge window; instructions
  fade, earlier file versions linger, and behavior gets erratic. "The model has a huge context
  window" is an argument for *headroom*, not for abandoning curation — a large window filled
  with noise performs worse than a small one holding exactly the relevant facts, and costs more
  on every single turn.
- **Wrong context is worse than missing context.** Missing knowledge makes an agent ask or read;
  stale knowledge makes it act — confidently, and wrong. A stale architecture doc, an outdated
  copy of a file read earlier in the session, a deprecated module retrieved as an exemplar: each
  actively steers the agent into error. Curation includes deletion.
- **Retrieval quality is a property of your repository.** Agents find knowledge by listing,
  grepping, and reading — the same way a new engineer does. A repo with predictable naming, a
  documentation map, and small focused docs is *queryable*; a repo with knowledge trapped in
  chat logs and one 3,000-line ARCHITECTURE.md is not. Context engineering is mostly repository
  engineering.
- **Everything the agent needs is what a new hire needs.** The docs map, the ADRs, the module
  READMEs, the glossary — every artifact this chapter builds doubles as onboarding
  documentation. Teams that invest here report the same effect twice: agents stop reinventing
  existing helpers, and new engineers stop asking where things live.
- **Context is also a security boundary.** Whatever enters the window — a pasted log with a
  bearer token, an `.env` read "for debugging" — has left your control (Stage 9, Chapter 04).
  Deciding what the agent may see is as much a part of this discipline as deciding what it
  should.

## Mental Model

Treat the context window as a scarce working memory that you load deliberately, spend
task-by-task, and reset before it sours.

```
              THE CONTEXT WINDOW AS A BUDGET
  ┌──────────────────────────────────────────────────────┐
  │ ALWAYS LOADED (fixed cost — every session, every turn)│
  │   system prompt · CLAUDE.md/AGENTS.md · tool defs    │
  │   → must be small and dense; Ch 01/02's discipline   │
  ├──────────────────────────────────────────────────────┤
  │ LOADED ON DEMAND (variable cost — the working set)   │
  │   files the agent reads · docs it follows pointers to│
  │   command output · search results                    │
  │   → your repo's structure determines how cheaply the │
  │     RIGHT things load and how easily wrong ones do   │
  ├──────────────────────────────────────────────────────┤
  │ ACCUMULATED (residue — grows all session, never      │
  │   shrinks on its own)                                │
  │   conversation history · stale file versions ·       │
  │   dead-end explorations · pasted logs                │
  │   → the reason long sessions degrade; managed by     │
  │     scoping, compaction, and reset                   │
  └──────────────────────────────────────────────────────┘

  THE KNOWLEDGE SUPPLY CHAIN (where facts live → how they arrive)
    code            → agent reads it        (cheap, always current)
    docs/ + ADRs    → agent follows the map (cheap IF map exists)
    instruction file→ always present        (expensive — reserve it)
    your head       → only via prompt       (bottleneck — write it down)
    chat scrollback → NEVER arrives         (knowledge graveyard)

  SESSION LIFECYCLE
    scope task → load working set → work → verify
        └── next task? → RESET (new session / clear)
        └── long task? → COMPACT deliberately or externalize
                         state to a file the next session reads
```

Three principles organize the practice:

**Relevance beats volume.** The goal is never "give the model everything"; it is "give the model
exactly what this task needs, and a cheap way to fetch what you didn't predict." Preloading is
for the universal (conventions, commands); retrieval is for the specific (the three files this
task touches, the one ADR that constrains it).

**The repository is the context database, and the agent queries it.** Every structural choice —
file naming, module boundaries, doc size, a `docs/` map — either speeds or slows the agent's
retrieval. Optimizing this is classic engineering: make the common query fast (find the
convention, find the exemplar, find the decision), make the dangerous query slow or impossible
(secrets, deprecated patterns presented as current).

**Context accumulates; discipline is subtractive.** Within a session the window only grows —
including everything that turned out to be irrelevant or wrong. The subtractive moves (fresh
session per task, compaction at milestones, externalizing long-task state into a plan file)
aren't optimizations; past a modest session length they are what keeps the agent coherent.

A working definition:

> **Context engineering is controlling what the model knows when it acts: a minimal always-loaded
> core, a repository structured so the right knowledge is cheaply retrievable at the moment of
> need (and wrong or stale knowledge is hard to retrieve), and session hygiene — scoping, reset,
> compaction, externalized state — that keeps the window relevant as work accumulates. Its unit
> of account is the token; its quality bar is whether an agent (or engineer) with no history can
> become productive from the repo alone.**

## Production Example

**Invoicely** has nine stages of decisions embedded in it: why money is integer cents (Stage 3),
why tenant scoping is a repository-layer concern (Stage 3), why the old `billing/` module is
frozen pending migration to `credit_notes/` (a Stage 6 refactor), which test tier runs when
(Stage 8), which endpoints are rate-limit-sensitive (Stage 9). Today, most of that lives in three
places agents can't reach: senior engineers' heads, closed PR threads, and chat scrollback.

The symptom is repetitive and expensive. An agent asked to add a discount feature reimplements a
money-formatting helper that already exists (it didn't know to look), copies the invoice-listing
pattern from the deprecated `billing/` module (it retrieved the wrong exemplar), and asks nothing
about tenant scoping (it didn't know there was anything to ask). Every miss was a context miss —
the model was fine.

This chapter makes Invoicely *self-describing*. A short `docs/` map in `AGENTS.md` tells any
agent where knowledge lives. `docs/architecture.md` gives the system map in one screenful with
real file paths. ADRs record the decisions that constrain new work, and the deprecated module
says so *in the code*, where retrieval can't miss it. Module READMEs give each area's local
rules and canonical exemplar. Session practice changes too: one task per session, a
`docs/plans/` scratch file for multi-session work, logs filtered before pasting, and compaction
at milestones rather than mid-reasoning. The acceptance test is the one from the stage README:
a fresh agent, given only the repo and a ticket, produces work that lands inside the
conventions — because the repo itself now carries the knowledge.

## Folder Structure

```
invoicely/
├── AGENTS.md                      # always-loaded core + THE DOCS MAP: five lines
│                                  #   telling any agent where knowledge lives
├── docs/
│   ├── architecture.md            # one-screen system map WITH FILE PATHS — the
│   │                              #   agent's (and new hire's) first read; small
│   │                              #   because every line competes for the budget
│   ├── decisions/                 # ADRs — one decision each, numbered, immutable;
│   │   ├── 0007-money-as-integer-cents.md     # small files = cheap retrieval,
│   │   └── 0012-tenant-scoping-in-repos.md    #   load one without loading all
│   ├── domain.md                  # glossary: invoice vs credit note vs receipt —
│   │                              #   the vocabulary bugs are made of
│   ├── runbooks/                  # operational how-tos (Stage 7); agents doing
│   │                              #   ops tasks retrieve these, not tribal memory
│   └── plans/                     # scratchpads for multi-session work — the
│       └── 2026-07-discounts.md   #   externalized state that survives resets
├── backend/
│   ├── app/
│   │   ├── billing/
│   │   │   └── README.md          # "DEPRECATED — frozen; new work in
│   │   │                          #   credit_notes/. See ADR-0015." Deprecation
│   │   │                          #   lives WHERE RETRIEVAL HAPPENS, in the code
│   │   └── invoices/
│   │       └── README.md          # local rules + "canonical exemplar: api.py" —
│   │                              #   answers "what do I copy?" before it's asked
│   └── tests/README.md            # which tier is which, factories, how to add
└── .cursorignore / ignore config  # keeps build artifacts, fixtures, and vendored
                                   #   code out of index-based retrieval (Ch 02)
```

Why this shape: **small files at predictable addresses.** Agents retrieve by name and by grep;
`docs/decisions/0007-money-as-integer-cents.md` is discoverable three different ways (the map,
the filename, the content) and costs almost nothing to load alone. One combined 3,000-line
document would be discoverable exactly one way and cost the whole budget every time. The
`plans/` directory is the session-hygiene tool: long-running work keeps its state in a file —
goal, decisions made, remaining steps — so a fresh session resumes from a 40-line read instead
of inheriting 100k tokens of history.

## Implementation

### The docs map — five lines that change retrieval

Appended to `AGENTS.md` (Chapter 02), so every agent starts holding the map:

```markdown
## Where knowledge lives (read on demand, not upfront)
- System map + file paths:      docs/architecture.md
- Why decisions were made:      docs/decisions/ (check before structural changes)
- Domain vocabulary:            docs/domain.md
- Module-local rules/exemplars: README.md inside each app/ module
- Multi-session task state:     docs/plans/<task>.md
Before writing a helper, search app/common/ and the target module —
assume it exists until proven otherwise.
```

The last two lines counter the two most common retrieval failures: not looking for existing code,
and not knowing a constraint had a recorded reason.

### architecture.md — a map, not a mural

```markdown
# Invoicely — system map

Request path: Next.js (frontend/) → FastAPI routers (backend/app/api/)
→ services (app/services/) → repositories (app/repositories/)
→ PostgreSQL. Async jobs: Celery (app/workers/) via Redis.

- AuthN/AuthZ: app/core/auth.py — JWT access + rotating refresh
  (ADR-0009). Tenant = account_id claim; scoping enforced in
  repositories (ADR-0012).
- Money: integer cents end-to-end (ADR-0007). Format only in
  frontend/lib/money.ts and app/common/money.py.
- billing/ is FROZEN (ADR-0015) — being replaced by credit_notes/.
  Never use it as a pattern.
- Test tiers: tests/README.md. Fast tier must stay under 60s.

Update this file in the same PR as any change that invalidates it.
```

One screen, every line a pointer or an invariant, real paths throughout. The closing instruction
is the freshness mechanism: **docs the agent reads are load-bearing**, so they update in the same
PR as the code, and reviewers treat a stale map like a failing test. A doc nobody is obligated
to update is a doc that will eventually lie — and agents believe docs.

### ADRs — decisions where retrieval can find them

The format is Stage 1's ([templates/adr.md](../../templates/adr.md)); what's new is the audience.
`docs/decisions/0007-money-as-integer-cents.md` exists so that an agent (or engineer) about to
"clean up" integer cents into `Decimal` retrieves, in one small file: the context (float rounding
bugs in early prototypes), the decision, and the consequences (format at the edges only). An
agent that knows *why* can honor intent in situations the rule's letter doesn't cover — and can
push back correctly when a task conflicts with a recorded decision instead of silently
complying.

### Deprecation at the point of retrieval

`backend/app/billing/README.md`:

```markdown
# DEPRECATED — do not extend, do not copy patterns
Frozen since 2026-03 (ADR-0015); replaced by app/credit_notes/.
Bug fixes only, and only with a failing test demonstrating the bug.
Canonical patterns for new work: app/invoices/.
```

Chat announcements and wiki pages don't reach an agent grepping for an exemplar; a README in the
directory does. For index-based retrieval (Cursor-style), the ignore file keeps generated code
and vendored directories from ever becoming candidates. The principle generalizes: **put
knowledge where the retrieval that needs it will happen** — deprecations in the deprecated code,
local rules in the module, operational steps in runbooks named after the operation.

### Session hygiene — scope, externalize, reset

```markdown
# docs/plans/2026-07-discounts.md   (maintained by the agent, reviewed by you)
## Goal
Percentage + fixed discounts on invoices; applies before tax; audit-logged.
## Decisions
- Stored as basis points (int) on invoice_lines — consistent w/ ADR-0007
- New service method, no changes to totals API contract
## Done
- [x] migration 00-add-discount-columns  [x] service + unit tests
## Next
- [ ] API surface + validation  [ ] frontend form  [ ] E2E happy path
```

The working rules that go with it: **one task per session** — the discount work and the flaky-test
investigation never share a window, because unrelated residue is the main pollutant. **Compact at
milestones, not mid-flight** — after the migration lands is a summary point; halfway through
debugging is not, because compaction is lossy and loses exactly the fine detail live debugging
needs. **Filter before pasting** — the failing test's output, not the whole CI log; the relevant
stack frame, not 400 lines of INFO (and never a log with tokens or secrets in it). **Resume from
the plan file** — tomorrow's session reads 40 lines of curated state instead of replaying today's
100k-token history, which is both cheaper and *more* accurate: the plan holds conclusions, not
the dead ends that led there.

## Engineering Decisions

**Decision 1: Preload or retrieve?** Frequency × universality. Needed on effectively every task
(commands, core invariants, the docs map) → always-loaded file, kept brutally small. Needed on
some tasks (architecture detail, a decision's rationale, module rules) → retrievable doc at a
predictable address. Needed once (this ticket's constraints) → the prompt. When an always-loaded
file wants to grow, the question isn't "is this true?" but "does this earn per-token rent on
every future task?" — usually the answer is a pointer, not a paragraph.

**Decision 2: Where does a given fact live?** By its retrieval moment. Constrains code at one
spot → comment or type at that spot. Governs one module → its README. Crosscuts the system →
`architecture.md`. Explains *why* → an ADR. Is operational → a runbook. Is transient task state →
`plans/`. The anti-decision is Slack, PR threads, and heads — knowledge that no retrieval reaches
is knowledge the team pays to rediscover, agent or not.

**Decision 3: How do docs stay true?** Same-PR updates, enforced in review — the map, the module
README, and any ADR affected by a change ride in the change's own diff. This is why the docs stay
*small*: the maintenance cost of documentation is proportional to its volume, and only documentation
cheap enough to maintain stays trustworthy enough to load. A useful backstop: when an agent's
output reveals it was misled by a stale doc, the fix commits the doc correction alongside the
code fix — same reflex as adding a regression test.

**Decision 4: One session or many for a big task?** Externalize and split. If the work has
natural milestones (migration → service → API → frontend), each gets a session that starts by
reading the plan file and ends by updating it. Long single sessions feel continuous but degrade
silently; the plan file converts continuity from an in-window property (fragile, expensive) to an
on-disk property (durable, reviewable). Reserve in-session compaction for work that genuinely
can't checkpoint.

**Decision 5: What must never enter the window?** Secret values, production PII, and customer
data — enforced structurally (Chapter 01's deny rules; sanitized fixtures from Stage 8), not by
intention. The subtler policy: *unfiltered bulk* (whole logs, whole database dumps, `node_modules`
listings) is banned not for secrecy but for pollution — anything pasted must first pass through
"what part of this is evidence?" That habit, incidentally, is most of Chapter 07's debugging
discipline.

## Trade-offs

| Choice | Gain | Cost |
|---|---|---|
| Rich docs layer | Agents + humans onboard from the repo; fewer context misses | Real authoring and same-PR maintenance cost; stale docs mislead worse than none |
| Minimal docs, code-only | Nothing to maintain; nothing to go stale | Every "why" question hits a human; agents reinvent and violate silently |
| Small, many docs | Cheap targeted retrieval; loadable individually | More files to keep coherent; needs the map to avoid scavenger hunts |
| One big doc | Single place to look | Costs the whole budget per load; buries the relevant screenful; goes stale as a unit |
| Fresh session per task | Clean attention, predictable behavior | Working-set reload cost (mitigated by the map + plan files) |
| Long-lived sessions | No reload; feels continuous | Silent degradation; stale file versions; dead ends steering live work |
| Compaction | Continue past budget limits | Lossy — summaries drop the detail you didn't know you needed; bad mid-debugging |
| Externalized plan files | Durable, reviewable, resumable state | Discipline to maintain; can drift from reality if not updated at milestones |
| Aggressive retrieval hygiene (ignore files, deprecation READMEs) | Wrong exemplars structurally hard to reach | Setup effort; ignore rules need occasional audit |

## Common Mistakes

- **Blaming the model for a context miss.** "It reinvented our helper / used the old module /
  ignored the invariant" — before switching models, ask: *how would it have known?* If the answer
  is "chat scrollback" or "everyone just knows", the failure is yours, and it will survive any
  model upgrade.
- **Dumping instead of curating.** Pasting the whole log, reading the whole directory,
  "here's everything, figure it out." Volume feels helpful and is the opposite: it buries the
  signal, degrades attention, and spends budget the task needed. Filter first — evidence in,
  noise out.
- **The immortal session.** One window carries the morning's debugging, a refactor, two
  explorations, and now a schema change. Behavior degrades so gradually it reads as "the model
  is having a bad day." Sessions are free; scope them like transactions.
- **Docs written once, believed forever.** An architecture doc from two refactors ago is an
  active hazard: agents weight documentation heavily and will follow it off the cliff. No
  same-PR update rule → the docs layer becomes a liability on a delay timer.
- **Duplicating code into docs.** Function-by-function API descriptions, restated schemas —
  stale on arrival, and pure budget waste: the agent reads code fluently and the code is always
  current. Docs carry what code *can't* say: why, boundaries, which of five similar things is
  canonical.
- **Confusing window size with immunity.** "The model handles a million tokens now" — it still
  attends unevenly across a stuffed window, and every turn re-reads what you loaded. Headroom
  changed; the economics and the discipline didn't.
- **Letting anything sensitive in "just this once".** The debugging session where `.env` gets
  read, the log with a live token pasted whole. The window is an exfiltration surface; Stage 9's
  rules apply to it exactly as they apply to git.

## AI Mistakes

All three assistants fail context in characteristic directions — and all three failures look like
competence at first glance.

### Claude Code: confident action on a partial map

Claude Code reads fast and acts decisively — which means that after reading two or three files it
often *believes it has the picture* and proceeds: reimplementing a helper that exists in
`app/common/` it never opened, adding a query that bypasses the tenant-scoping mixin defined in a
base class it didn't read, extending a pattern from the one (deprecated) module it happened to
look at. The work is coherent, idiomatic, and wrong about your system in ways only someone who
knows the *rest* of the repo would catch.

**Detect:** new utilities suspiciously similar to existing ones; base-class or middleware behavior
duplicated inline; diffs whose "Read" trail (visible in the session) never touched the modules
that define the relevant conventions; code that compiles against your system but ignores its
idioms.

**Fix:** make the map load-bearing and the search mandatory:

> Before implementing, locate the existing conventions: read docs/architecture.md, the README of
> every module you will touch, and search app/common/ and the target module for existing helpers
> that cover any part of this task. List what you found and what you'll reuse BEFORE writing new
> code. Assume a helper exists until a search proves otherwise.

### GPT: reasoning from a stale snapshot of your own files

In long sessions, GPT-family models keep reasoning from the version of a file they read earlier —
even after they (or you) changed it. The window contains both versions; the model anchors on the
first. Symptoms: edits that re-introduce code just removed, references to a function signature
from before its rename, a "fix" applied to a line that no longer exists, patches that conflict
with the file as it currently stands. It looks like carelessness; it's actually context —
the stale copy is *right there*, competing with the new one.

**Detect:** patch failures and near-miss edits late in a session; regressions of changes made
earlier in the same session; the model describing file content that doesn't match `git diff`;
confusion that clears up instantly in a fresh session.

**Fix:** re-read before write, and reset at milestones:

> Before editing any file, re-read its current contents — never edit from memory of an earlier
> read. After each completed step, state the current form of what changed. (And operationally:
> end the session at the milestone; start the next one from the plan file, not from history.)

### Cursor: the nearest-neighbor exemplar, wherever it points

Cursor's strength — automatically pulling similar code into context — is also its
characteristic failure: similarity is lexical, not architectural. Ask for a new payments-adjacent
feature and the retrieved exemplar is the *deprecated* `billing/` module (it matches best); ask
for a form and it patterns off the one legacy component that predates your design system; test
fixtures and generated files surface as if they were product code. The agent then writes fluent
code in the style you're trying to eliminate — retrieval laundered the legacy pattern into new
work.

**Detect:** new code resembling deprecated or one-off patterns rather than your canonical
exemplars; imports from frozen modules; generated/vendored code showing up in the agent's cited
context; style regressions clustered in areas that have a legacy twin.

**Fix:** curate the retrieval pool and name the canon:

> Add the deprecated and generated paths to the ignore configuration so they never enter
> retrieval. Put a DEPRECATED README inside each frozen module. In each active module's README,
> name the canonical exemplar file for new work — and when given a task, state which exemplar
> you are following before you write.

## Best Practices

- **Run the "cold agent" test as your quality bar.** Fresh session, real ticket, no verbal
  briefing: does the output land inside conventions? Every miss maps to a specific missing or
  unreachable piece of context — fix the repo, re-run.
- **Keep the always-loaded core minimal and pushed to pointers.** The map earns permanent
  residence; almost nothing else new does. Growth pressure on `AGENTS.md` usually means a doc
  should exist instead.
- **Write docs the size of one retrieval.** One decision per ADR, one screen for the map, one
  README per module. Small docs load alone, stay maintainable, and stay true.
- **Co-locate knowledge with its retrieval moment.** Deprecations in the deprecated directory,
  local rules in the module, ops steps in runbooks, transient state in plan files. If you have
  to remember to tell the agent, it's in the wrong place.
- **Update docs in the same PR as the code — no exceptions.** Load-bearing docs are code. Stale
  entries get deleted on sight; a wrong doc is worse than a missing one.
- **Scope sessions like transactions; externalize long work.** One task per window; plan files
  for anything multi-session; compaction only at milestones.
- **Filter everything you paste.** The failing test, the relevant frames, the pertinent config
  block. If you wouldn't quote it in a PR description as evidence, it doesn't go in the window.
- **Audit the retrieval surface occasionally.** Ignore rules still correct? Any new
  generated/vendored directories leaking into search? Deprecated modules properly labeled? Wrong
  retrieval is silent; only audits catch it.
- **Keep secrets structurally unreachable.** Deny rules + sanitized fixtures + the no-bulk-paste
  habit. "The agent never sees secret values" should be an architectural property, not a hope.

## Anti-Patterns

**The kitchen-sink window.** "Read the whole codebase first, then we'll start." Feels thorough;
delivers a degraded, expensive session anchored on mostly-irrelevant material — and the agent
still won't have read the one ADR that mattered. Load the map, retrieve the working set,
fetch the rest on demand.

**The knowledge graveyard.** The team's real architecture lives in Slack threads, PR comments,
and two seniors' heads; the repo contains code and silence. Every agent session (and every new
hire's first month) pays the rediscovery tax. If it constrains work, it lives in the repo — that
rule is older than AI; agents just made its violation expensive per-session instead of per-hire.

**The documentation mural.** A 3,000-line ARCHITECTURE.md, lovingly complete, updated twice a
year. Too big to load, too monolithic to trust, too expensive to maintain — the docs equivalent
of the god object. Decompose it along retrieval lines: map, decisions, modules, runbooks.

**Context hoarding.** Refusing fresh sessions because "it finally understands the codebase."
What it has is a window full of one-time reads that are aging toward staleness — understanding
that can't be inspected, shared, or trusted tomorrow. Anything worth keeping from a session
belongs in a doc or plan file; then the session is disposable. Durable knowledge lives on disk,
never in a window.

**The verbal briefing dependency.** Output quality depends on a fifteen-minute spoken download
from whoever knows the area. It doesn't scale to parallel agents (Chapter 05), doesn't survive
that person's vacation, and silently exempts the repo from being self-describing. The briefing
*is* the missing doc — write it once.

## Decision Tree

"A piece of knowledge matters to the work — where does it go?"

```
Is it a secret / credential / customer data?
├── YES ──► It never enters the window. Deny rules, sanitized
│           fixtures, filtered pastes. (Stage 9 Ch 04.)
└── NO ──► Is it discoverable by reading current code?
    ├── YES ──► Leave it in code. Duplicating it into docs creates
    │           a staleness liability and spends budget twice.
    └── NO ──► Is it needed on effectively EVERY task?
        ├── YES ──► Always-loaded file (AGENTS.md) — one imperative
        │           line, or a pointer if it's bigger than a line.
        └── NO ──► Does it explain WHY something is the way it is?
            ├── YES ──► ADR in docs/decisions/, linked from the map.
            └── NO ──► Is it scoped to one module / one operation?
                ├── module ──► that module's README (+ canonical
                │              exemplar named).
                ├── operation ──► runbook.
                └── crosscutting ──► architecture.md — kept to one
                                     screen; if it won't fit, it's
                                     probably several module facts.

"Should I load X into THIS session?"
    Does the current task need it → load the relevant PART.
    Might it help → point the agent at the map and let it decide.
    It's bulk (log/dump/tree) → filter to evidence first.
    The session is old and X contradicts something read earlier →
        don't add — reset, and start clean from the plan file.
```

## Checklist

**Implementation Checklist**

- [ ] Docs map in the always-loaded file: five-ish lines, real paths
- [ ] `docs/architecture.md` — one screen, file paths, invariants, same-PR update rule stated
  in the file itself
- [ ] ADRs exist for the decisions agents most often violate (money, tenancy, frozen modules)
- [ ] Deprecated modules carry a DEPRECATED README naming the replacement and canonical exemplar
- [ ] Module READMEs in active areas: local rules + exemplar file
- [ ] Ignore configuration keeps generated, vendored, and fixture content out of retrieval
- [ ] `docs/plans/` in use for multi-session tasks; sessions resume from plan files
- [ ] Sensitive paths structurally unreadable (Chapter 01 deny rules verified live)

**Architecture Checklist**

- [ ] Always-loaded core is minimal; everything else retrievable at a predictable address
- [ ] Every load-bearing fact has exactly one home (code / map / ADR / README / runbook)
- [ ] Docs sized to one retrieval; no murals
- [ ] Session policy written: one task per window, milestone compaction, plan-file resumption
- [ ] The cold-agent test passes on a representative ticket — and is re-run after structural
  changes

**Code Review Checklist**

- [ ] Change invalidates a doc? The doc update is in this diff — or the PR isn't done
- [ ] New module → README with rules + exemplar; new decision → ADR; new deprecation → in-place
  README + ignore/map updates
- [ ] No secrets, tokens, or customer data in any doc, plan file, or committed example
- [ ] Plan files reflect reality at merge time (stale plans mislead the next session)
- [ ] Agent-produced diffs: check the telltales — reimplemented helpers, deprecated-pattern
  imports, edits that fight the current file state

## Exercises

1. **Run the cold-agent audit.** Fresh session, real ticket from your backlog, zero verbal
   context. Record every miss (wrong pattern, reinvented helper, violated invariant, missing
   why) and write the *context* fix for each — a map line, an ADR, a README, an ignore rule.
   Re-run the same ticket cold. The delta is your context layer's ROI, measured.
2. **Build the map.** Write your repo's `docs/architecture.md` under 40 lines with real file
   paths, and the five-line docs map for your instruction file. Hand both to a colleague who
   doesn't know the area: what they still can't find is what's still missing.
3. **Excavate three decisions.** Find three rules in your codebase that exist for reasons
   recorded nowhere (ask the person who knows — that's the point). Write the three ADRs. Then
   ask an agent to "improve" code constrained by each and see whether it retrieves and respects
   them — or argues with them, which is also a pass.
4. **Fix a retrieval trap.** Locate your repo's most dangerous exemplar (deprecated module,
   legacy component, generated code) and confirm an agent can currently retrieve it as a pattern.
   Install the countermeasures — in-place README, ignore rules, canon named in the active
   module — and confirm the same task now patterns off the right code.
5. **Convert a long session.** Take your next multi-day task and run it as plan-file sessions:
   externalize state at each milestone, kill each window, resume cold. Compare against your
   usual marathon session on coherence of late-stage output — and on what the plan file caught
   when you reviewed it that a window never would have surfaced.

## Further Reading

- [Anthropic — Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
  — the provider-side treatment: curation, retrieval, compaction, and why "just add more
  context" fails.
- [Liu et al. — Lost in the Middle: How Language Models Use Long Contexts](https://arxiv.org/abs/2307.03172)
  — the research grounding for position- and volume-dependent attention degradation.
- [ADR templates and rationale](../../templates/adr.md) — this handbook's ADR format; Stage 1
  introduced it for humans, this chapter aims it at retrieval.
- Chapter 01 ([Claude Code](01-claude-code.md)) — the always-loaded layer and the deny rules
  this chapter builds around.
- Chapter 04 ([Prompt Engineering](04-prompt-engineering.md)) — the other input: what you ask,
  given what it now knows.
- Chapter 07 ([AI Debugging](07-ai-debugging.md)) — evidence-filtering as a debugging
  discipline; the "filter before pasting" habit taken to its full depth.

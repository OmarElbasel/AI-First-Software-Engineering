# Multi-Agent Systems

## Introduction

Everything so far assumed one agent, one task, one window. This chapter is about using several —
and it needs an honest framing before anything else, because "multi-agent" is the most
hype-inflated term in AI engineering. In production software work, multi-agent systems are three
mundane, valuable patterns: **parallel agents** working independent tasks in isolated workspaces,
**subagents** — scoped helper agents a main agent dispatches for focused work with their own
context and restricted tools, and **pipelines** — sequential stages (implement, then review, then
fix) where each stage gets fresh eyes. That's the whole taxonomy. There is no swarm, no emergent
organization, no team of AI employees; there is fan-out, delegation, and staging — patterns as
old as distributed systems, with the same failure modes.

The engineering question is never "how many agents can I run?" — it is the question this chapter
asks over and over: **does the coordination cost of splitting this work exceed the gain?**
Agents don't share memory. Everything they coordinate through must be an artifact — the repo, a
plan file, a PR — and every artifact channel is a place for drift, conflict, and duplicated
work. Meanwhile the gains are real but bounded: wall-clock throughput on genuinely independent
tasks, context isolation for noisy subtasks, and the quality lift of fresh-context review. This
chapter builds all three patterns on Invoicely and, just as deliberately, marks where each one
stops paying.

The prerequisites are the whole stage so far: parallel and delegated agents run unwatched, so
they inherit everything Chapters 01–04 built — a self-describing repo, enforced boundaries, and
full task specifications. Multi-agent work doesn't relax those disciplines; it is what they were
for.

## Why It Matters

- **Throughput, where independence is real.** A test backfill across eight modules, a
  lint-rule migration across three packages, dependency bumps across services — genuinely
  independent tasks parallelize almost linearly. For the mechanical, well-specified work that
  agents already do well, fan-out is the difference between a day and an hour of wall-clock.
- **Context isolation is a quality tool, not just a speed tool.** Chapter 03 showed how residue
  degrades a session. A subagent gives a noisy subtask — a sprawling codebase search, a log
  analysis, a doc summarization — its *own* window, returning only the conclusion. The main
  agent's context stays clean, which means its subsequent decisions stay sharp.
- **Fresh eyes are mechanically better reviewers.** An agent reviewing code in the same session
  that wrote it inherits every assumption that produced the bug — it re-reads its own reasoning
  and nods along. A separate agent with clean context, seeing only the diff and the spec,
  catches what the author-context structurally cannot. Pipelines exploit this; Chapter 06
  builds on it.
- **The bottleneck moves to you, immediately.** Five agents producing five PRs did not make
  review five times faster. Human review bandwidth — already the scarce resource in this stage —
  becomes the hard ceiling on useful parallelism, and exceeding it doesn't queue work, it rots
  it: stale branches, merge conflicts, rubber-stamped diffs.
- **Coordination failures are silent and expensive.** Two agents "independently" editing the
  router registry; a subagent contradicting a decision made two hours earlier in a session it
  never saw; the same helper implemented twice in parallel branches. None of these error out.
  They surface as merge hell and review archaeology — the distributed-systems tax, paid in
  engineer attention.
- **The economics multiply.** N agents consume roughly N sessions' worth of tokens, plus
  orchestration overhead. Multi-agent approaches earn that spend on parallelizable, verifiable
  work — and burn it performatively on work that one well-contexted agent would do better.

## Mental Model

Three patterns, one law: agents share nothing — all coordination is through artifacts, and the
human is the integration point.

```
  PARALLEL (fan-out)          HIERARCHICAL (subagents)      PIPELINE (stages)
  independent tasks           one main agent delegates       sequential, fresh
  isolated workspaces         scoped subtasks                context per stage

     you (spec x N)                 main agent                  spec
    ┌────┼────┐              ┌────────┼────────┐                 │
    ▼    ▼    ▼              ▼        ▼        ▼                 ▼
  agent agent agent       search    test     review        implement agent
    A     B     C         subagent  subagent subagent            │ diff
    │     │     │         (own ctx, (own ctx, (own ctx,          ▼
  wt-A  wt-B  wt-C        few tools) few tools) read-only)  review agent (clean ctx)
    │     │     │              └───────┼───────┘                 │ findings
    ▼     ▼     ▼            results return as artifacts         ▼
   PR    PR    PR            /summaries; residue stays        fix agent
    └────┼────┘              in the subagent's window            │
         ▼                                                       ▼
   YOU: review + merge                                       PR → YOU
   (the ceiling)

  THE LAWS (all three patterns)
  1. No shared memory. Coordination = artifacts: repo, plan
     files, PRs, task briefs. If it isn't written down, the
     other agent doesn't know it.
  2. Independence is a property of the TASK GRAPH, not of hope.
     Two tasks are parallel only if their write-sets don't
     intersect — including the hub files everyone forgets
     (routers, configs, migrations, lockfiles, translations).
  3. Parallelism is capped by the sequential part — and the
     sequential part is YOU: specification before, review and
     integration after. (Amdahl's law, wearing a lanyard.)
```

**Fan-out multiplies your spec, not your judgment.** Parallel agents each need the full Chapter
04 brief — distance is maximal, nobody is watching. What fan-out cannot multiply is the
decision-making and review on each end; that stays sequential and human, which is why the
pattern fits mechanical work and misfits design work.

**Subagents are a context firewall first, a division of labor second.** The dispatching agent's
scarcest resource is its window (Chapter 03). Delegating a 50-file search to a subagent that
returns a ten-line summary buys attention, not just parallelism. The corollary: what the
subagent doesn't get told, it doesn't know — dispatch briefs are mini-specs, and thin ones
produce confident, contradictory work.

**Pipelines buy independence of judgment.** The reviewer stage works *because* it shares
nothing with the author stage but the diff and the spec. Preserving that separation — different
session, no author reasoning passed along — is the entire value; a pipeline that leaks author
context into review is one agent agreeing with itself in two voices.

A working definition:

> **Multi-agent engineering is splitting AI work across isolated contexts — parallel agents for
> independent tasks, subagents for scoped delegation and context isolation, pipelines for
> fresh-eyes staging — coordinated exclusively through artifacts, sized by the task graph's real
> independence, and capped by the human review bandwidth at the merge point. Its discipline is
> subtractive: the default is one agent, and every additional context must pay for its
> coordination cost.**

## Production Example

**Invoicely** exercises all three patterns — and one deliberate counter-example.

**Fan-out: the coverage backfill.** Stage 8 left four service modules under-tested
(`credit_notes`, `reminders`, `exports`, `webhooks`). Four tasks, four disjoint write-sets
(each touches only its module's tests), one shared read-only context (factories, test README).
Each gets a Chapter 04 brief from the `test-backfill` library prompt, an isolated git worktree,
and an agent. Four PRs land by afternoon; review takes the evening — and review, not
generation, was the day's real budget, which is why the team fanned out four and not ten.

**Subagents: the firewall.** The team defines two in `.claude/agents/`: a **repo-scout**
(read-only tools; answers "where is X handled, what would Y affect?" and returns a summary,
keeping 40-file exploration residue out of the main window) and a **test-writer** (writes and
runs tests only; can't touch product code, which makes "backfill tests without changing
behavior" a structural guarantee instead of an instruction).

**Pipeline: the discount feature.** Chapter 04's brief goes to an implementing agent; the
resulting diff plus the brief — and nothing else — goes to a fresh review session using the
Chapter 06 review prompt; findings return to the implementer; a human reads the final diff plus
the review transcript. The reviewer catches a rounding edge case at the half-cent boundary that
the author-context had already rationalized twice. That catch is the pipeline's ROI.

**The counter-example the team declined.** "Speed up the discount feature: one agent on the
migration, one on the service, one on the API, in parallel." The task graph says no: service
depends on schema, API depends on service, all three touch `invoice_totals`. Parallelizing a
dependency chain doesn't compress time — it converts sequential work into merge conflicts plus
a reconciliation meeting. One agent, one branch, plan-first: faster.

## Folder Structure

```
invoicely/
├── .claude/
│   └── agents/
│       ├── repo-scout.md          # read-only subagent: search/summarize; exists to
│       │                          #   keep exploration residue out of the main window
│       └── test-writer.md         # scoped subagent: tests only — role boundary
│                                  #   enforced by TOOL access, not by politeness
├── prompts/
│   └── tasks/test-backfill.md     # the library prompt each fan-out instance gets
│                                  #   (Ch 04) — parallel agents multiply the spec
├── docs/
│   └── plans/
│       └── 2026-07-coverage.md    # the fan-out manifest: task list, write-set per
│                                  #   task, owner agent, status — the coordination
│                                  #   artifact humans and agents both read
├── ../invoicely-wt/               # worktrees live OUTSIDE the main checkout:
│   ├── backfill-credit-notes/     #   one per parallel task — same repo, isolated
│   ├── backfill-reminders/        #   working trees, disposable after merge
│   └── ...                        #   (git worktree add ../invoicely-wt/<task> -b <branch>)
└── Makefile                       # every workspace verifies with the same
                                   #   `make check` (Ch 02) — N agents, one gate
```

Why this shape: **isolation by construction** (worktrees give each agent a private working tree
against the same repository — no shared mutable workspace, no stepping on each other's
uncommitted state), **coordination made legible** (the plan file lists every task's write-set
*before* anything runs — independence is checked on paper, where it's cheap), and **roles
enforced mechanically** (subagent definitions restrict tools the way Chapter 01 restricted
permissions: the test-writer *can't* modify product code, which is worth more than any
instruction saying it shouldn't).

## Implementation

### A subagent definition

`.claude/agents/repo-scout.md`:

```markdown
---
name: repo-scout
description: Read-only codebase reconnaissance. Use for "where/what/how
  does X work" questions whose exploration would pollute the main context.
tools: Read, Grep, Glob
---
You are a code scout for Invoicely. Answer the dispatched question by
reading the repository. You never modify anything.

Report back ONLY: a direct answer; the relevant file paths (exact);
surprises or inconsistencies you noticed. Under 30 lines. Do not paste
file contents unless a specific snippet is the answer.
```

The two design choices to copy: the **tool list is the role** (read-only access makes "scout"
a guarantee, not a vibe), and the **report contract caps the return payload** — the entire
point is that 40 files of exploration come back as 30 lines, so the dispatching context pays
30 lines.

### Dispatch briefs — the law of no shared memory, applied

A subagent (or any second agent) knows *nothing* you don't put in its brief. The failure and
the fix, side by side:

```text
✗  "Dispatch test-writer: add tests for the discounts service."

✓  "Dispatch test-writer: add unit tests for
    app/services/discounts.py. Constraints from the session you
    haven't seen: discounts are stored as basis points (ADR-0007);
    rounding at half-cent boundaries was decided ROUND-HALF-EVEN
    today (see docs/plans/2026-07-discounts.md, 'Decisions');
    cross-tenant access must 404. Use tests/factories.py. Do not
    modify product code. Report: test names + one line each."
```

The second brief re-states session decisions *because the subagent wasn't there*. The plan file
(Chapter 03) is what makes this cheap — decisions written down at the moment they're made are
one pointer away for every later context, instead of re-typed or, worse, silently missing.

### Fan-out over worktrees

```bash
# One isolated workspace + branch per independent task
git worktree add ../invoicely-wt/backfill-reminders -b backfill/reminders

# One agent per workspace, non-interactive, full library brief
cd ../invoicely-wt/backfill-reminders
claude -p "$(cat prompts/tasks/test-backfill.md) MODULE: app/services/reminders.py" \
  --allowedTools "Read,Edit,Write,Bash(pytest*),Bash(ruff*),Bash(git add*),Bash(git commit*)"

# Each task ends as a small PR; workspaces are disposable
git worktree remove ../invoicely-wt/backfill-reminders
```

The manifest in `docs/plans/2026-07-coverage.md` is written *first*: each task, its write-set,
its branch. If two write-sets intersect there — including hub files — the tasks are serialized
before any tokens are spent. Cloud agents (Chapter 02) are the same pattern with hosted
workspaces: same briefs, same manifest, same PR-per-task discipline.

### The pipeline — fresh eyes as a mechanism

```bash
# Stage 1: implement (worktree, full brief)
claude -p "$(cat prompts/briefs/2026-07-discounts.md)"

# Stage 2: review — NEW session, sees ONLY spec + diff, read-only
git diff main > /tmp/discounts.diff
claude -p "Review this diff against this spec. $(cat prompts/review/pr-review-pass.md)
SPEC: $(cat prompts/briefs/2026-07-discounts.md)
DIFF: $(cat /tmp/discounts.diff)" \
  --allowedTools "Read,Grep"

# Stage 3: fix — implementer session (or fresh one) gets the findings
# Stage 4: human reads final diff + review transcript, then merges
```

What makes stage 2 work is what it *doesn't* receive: no author reasoning, no session history,
no write access. Give the reviewer the author's context and you've rebuilt self-review;
give it write access and review findings arrive pre-"fixed", unreviewed. Chapter 06 turns this
stage into a full discipline; here it's the pipeline's load-bearing joint.

## Engineering Decisions

**Decision 1: Should this work be multi-agent at all?** Default no. The gate is three questions:
Is the work *specifiable* to Chapter 04 standard? (Unwatched agents need full briefs.) Is it
*divisible* into tasks with disjoint write-sets? (Check the graph — on paper.) Is there *review
budget* for the output? (PRs nobody reads are inventory, not progress.) Any "no" → one agent,
or none. Design-open work fails the first question categorically: parallelize execution, never
exploration of what to build.

**Decision 2: How many parallel agents?** Min(independent tasks, your review bandwidth), and
review bandwidth is almost always the binding term. A useful heuristic: fan out only what you
can review *the same day* — merged-same-day branches don't drift, and feedback reaches the next
batch's briefs while it's still cheap. Scaling further means scaling review (Chapter 06's
automated first pass), not just generation.

**Decision 3: Subagent or main context?** Delegate when the subtask is self-contained and its
*process* is noise to the parent: exploration, bulk analysis, mechanical generation with a
crisp contract. Keep inline when the subtask's intermediate findings would change the parent's
plan — a firewall around information you actually needed is called a blindfold. And keep the
hierarchy flat: dispatcher plus one layer of specialists covers real engineering work;
sub-sub-agents mostly add places for briefs to thin out.

**Decision 4: What may each role touch?** Scope tools per role like Chapter 01 scoped
permissions per repo: scouts read, test-writers write tests, reviewers read (never write),
implementers get the standard loop. The narrow grant isn't distrust — it converts role
descriptions into invariants, which is what lets you *not* watch four agents at once.

**Decision 5: Same model everywhere, or cheaper models for cheap roles?** Scouting,
summarization, and mechanical transforms tolerate smaller/faster models; implementation and
review of production code deserve the strongest model you run — a missed review finding costs
more than the tokens saved finding it. Re-evaluate with your own bake-off (Chapter 02's method)
rather than pricing pages; the boundary moves as models do.

## Trade-offs

| Choice | Gain | Cost |
|---|---|---|
| Fan-out over worktrees | Wall-clock throughput on independent work | Spec effort × N; review pile-up; merge risk if independence was wishful |
| One agent, sequential | No coordination cost; context accumulates usefully within the task | Wall-clock; one window carries everything (Ch 03 limits) |
| Subagent delegation | Clean parent context; role guarantees via tools | Dispatch-brief overhead; information firewalled both ways; latency per hop |
| Everything inline | Parent sees all intermediate findings | Residue degrades the session; exploration noise buries decisions |
| Pipeline (author → fresh reviewer) | Structurally independent judgment; catches author-context bugs | ~2× tokens; slower; findings still need human adjudication |
| Self-review in-session | Fast, cheap | Inherits every assumption that produced the bug — near-zero marginal value |
| Manifest-first coordination | Conflicts caught on paper, pre-spend | Feels like ceremony on small fan-outs (it's ~10 lines; do it anyway) |
| Ad-hoc parallel launches | Zero setup | Hub-file collisions, duplicated helpers, reconciliation archaeology |
| Cheaper models in cheap roles | Meaningful cost cut at scale | Quality cliff is empirical and moves; silent degradation if never re-tested |

The meta-trade-off: multi-agent patterns convert *engineer time* (spec, manifest, review) into
*wall-clock compression*. When engineer time is the scarce resource — it usually is — the
conversion only profits on work where specs are reusable (libraries), review is fast
(mechanical diffs), or quality independently improves (fresh-eyes review).

## Common Mistakes

- **Parallelizing a dependency chain.** Schema → service → API split across three agents
  isn't parallelism, it's a merge conflict with extra steps. If task B needs task A's output,
  the graph has decided for you: sequential, one context.
- **Forgetting the hub files.** "The tasks are independent — they touch different modules."
  And the router registry, the settings file, the migration sequence, the lockfile, the
  translation catalog? Hub files are where "independent" tasks meet; list them in the manifest
  and either partition or serialize them.
- **Fan-out past review bandwidth.** Ten beautiful PRs, three days of review backlog, branches
  drifting stale underneath. Generation was never the bottleneck; you've just made the real
  one worse. Fan out what you can merge today.
- **Thin dispatch briefs.** "Add tests for the discounts service" — and the subagent, missing
  the session's rounding decision, tests ROUND-HALF-UP and enshrines the wrong behavior. No
  shared memory means the brief carries everything, every time.
- **Orchestration theater.** Five named agents with personas coordinating over a message bus
  to do what one agent with a good brief does in twenty minutes. Complexity is a cost you pay,
  not a capability you demo (Stage 1's simplicity chapter, wearing new clothes).
- **Letting the pipeline self-merge.** Implement → review → fix → *merge*, no human at the
  gate. The review stage filters; it doesn't own consequences. Stage 1's rule — AI makes no
  unreviewed engineering decisions — doesn't dissolve because the reviewer is also an AI.
- **Duplicated discovery.** Two parallel agents each notice the missing `format_cents` helper
  and each write one. Cheap to prevent (the manifest's read-set note: "helpers live in
  app/common; extend, don't create"), tedious to reconcile after.

## AI Mistakes

Multi-agent setups fail along their seams — dispatch, orchestration, and workspace boundaries —
and each assistant has a signature seam failure.

### Claude Code: the under-briefed subagent that contradicts the session

Claude Code dispatches subagents readily — often more readily than it writes dispatch briefs.
The characteristic slip: the main session has accumulated hard-won decisions (a rounding mode,
a naming choice, an ADR constraint surfaced an hour ago), and the dispatch message summarizes
the *task* but not the *decisions*. The subagent, competent and context-free, re-derives the
open questions — sometimes differently — and returns work that quietly contradicts the session
it's part of. The contradiction ships inside otherwise-good output, which is what makes it
nasty: everything looks done.

**Detect:** subagent output inconsistent with decisions recorded earlier (plan file vs
delivered code); re-litigated choices you'd already closed; two conventions for the same thing
arriving in one feature; dispatch messages in the transcript that are one line long.

**Fix:** decisions travel by artifact, and the brief is the contract:

> Before dispatching any subagent, write the decisions this subtask must honor into the plan
> file, and include in the dispatch: the task, the relevant decisions (with pointers), the
> constraints, and the report format. A subagent has read NOTHING from this session — if a
> decision isn't in its brief or in a file it's told to read, assume it will violate it.

### GPT: the grandiose orchestration for a one-agent job

Asked to "set up a multi-agent workflow," GPT-family models reliably produce an org chart: a
planner agent, a coder agent, a tester agent, a critic agent, a coordinator, message schemas,
retry policies — for a task that touches four files. The design is internally coherent and
impressively documented, which disguises that every hop is a place for context to thin, every
agent a cost multiplier, and the whole apparatus slower and less reliable than one
well-configured agent with a Chapter 04 brief. This is the architecture-astronaut failure
(Stage 2) reborn with agents as the units.

**Detect:** more agents than modules touched; roles whose output is another agent's input with
no artifact in between; coordination infrastructure (buses, registries, state machines) for
workflows that run start-to-finish in minutes; no stated reason any single stage *requires*
isolation.

**Fix:** justify every context, from a default of one:

> Start from one agent. For each additional agent, state the specific benefit that requires a
> SEPARATE context — true parallelism over disjoint write-sets, context isolation for a noisy
> subtask, or independent judgment for review — and what artifact carries information across
> the boundary. Any agent that exists for role-play rather than isolation gets folded back in.

### Cursor: parallel agents racing through the shared seams

Launching several background agents from the same repo state, Cursor-style workflows hit the
classic race: each agent's task is "independent," but each adds a route to the same router
file, an entry to the same config, a migration to the same sequence. Every agent's work is
correct in isolation; the collisions surface at merge as conflicts (best case) or as
last-write-wins clobbering (worst case — two migrations with the same sequence number, one
config entry silently gone). The tool did nothing wrong; the write-sets were never actually
disjoint.

**Detect:** merge conflicts concentrated in registry/config/migration/lockfile hubs; migration
numbering collisions; a setting one agent added missing after another agent's merge; PRs that
each pass CI alone and fail together.

**Fix:** partition the hubs before launching, not after:

> List every file all launched tasks will write, including registries, configs, migration
> sequences, and lockfiles. Any file in two lists: either restructure the tasks so one owner
> handles that file, serialize the conflicting tasks, or have each task leave a TODO marker for
> a single integration pass. Never launch parallel agents whose write-sets you haven't compared.

## Best Practices

- **Write the manifest first.** Tasks, write-sets (hubs included!), branches, briefs — ten
  lines of paper that replace an afternoon of merge archaeology. If the manifest shows
  intersections, the graph has spoken.
- **One task, one workspace, one PR.** Worktrees (or hosted workspaces) per parallel task;
  small same-day-reviewable PRs; workspaces deleted after merge. Isolation by construction
  beats coordination by care.
- **Briefs carry everything; artifacts carry decisions.** Dispatch like the recipient has read
  nothing — because it hasn't. Keep the plan file current so "everything" is a pointer, not an
  essay.
- **Enforce roles with tools, not adjectives.** Read-only scouts, test-only writers, reviewers
  who cannot edit. The tool list is the role.
- **Keep review stages context-clean.** Fresh session, spec + diff only, no author reasoning.
  The moment the reviewer knows why the author did it, you've paid double for self-review.
- **Cap fan-out at same-day review.** Then raise the cap by making review faster (Ch 06), not
  by letting inventory build.
- **Integrate continuously.** Merge as tasks complete; rebase remaining branches early. The
  big-bang integration of eight finished branches is where fan-out gains go to die.
- **Default to one agent, and let additions argue for themselves.** Parallelism, isolation, or
  independent judgment — those are the three admissible arguments. "It's more agentic" is not.

## Anti-Patterns

**The swarm demo.** An orchestrator, six specialists, a message bus, a live dashboard — solving
a task one agent handles in one session. It demos beautifully and produces: token burn,
un-debuggable failures smeared across contexts, and briefs that thin at every hop. Complexity
without a paying customer (Stage 1). The tell: nobody can name which single stage would degrade
if folded back into its neighbor.

**The shared workspace.** Multiple agents editing one checkout "to avoid worktree overhead."
They interleave uncommitted changes, trip each other's test runs, and produce a working tree
whose state belongs to nobody. Workspace isolation is the cheapest coordination mechanism that
exists; declining it buys nothing and costs everything.

**The echo-chamber pipeline.** Author agent, "reviewer" agent — same session, or the reviewer
receives the author's full reasoning as context. Output: eloquent approval. The pipeline's
value *is* the independence; leak the context and you've built a second opinion from the same
brain and are paying twice for one judgment.

**Parallelism as procrastination.** The design is unsettled, so fan out three agents to "explore
implementations in parallel" — generating three full solutions to compare, each embodying
guesses nobody vetted. Now there are three diffs, no decision, and sunk-cost pressure to merge
the least bad. Exploration is thinking; options-first prompting (Ch 04) does it at the sketch
level for a fraction of the cost. Parallelize *after* the decision.

**Unattended merge authority.** Any configuration where agent output reaches `main` without a
human at the gate — pipeline "reviewed", CI green, auto-merge on. Green means the checks you
encoded passed; it does not mean the change is wanted, safe, or understood. The gate is where
accountability lives (Chapter 08 automates everything *up to* it, never it).

## Decision Tree

"Should this work be split across agents — and how?"

```
Is the work fully specifiable now (Ch 04 criteria stateable)?
├── NO ──► No multi-agent anything. Options-first with ONE agent;
│          decide; then reconsider. (Parallel exploration of an
│          undecided design = 3× the guesses, 0× the decision.)
└── YES ──► What are you buying?
    ├── WALL-CLOCK on many similar tasks?
    │   └── Write the manifest: disjoint write-sets, hubs included?
    │       ├── NO ──► serialize (or restructure ownership of hubs).
    │       └── YES ──► fan-out ≤ same-day review bandwidth:
    │                   worktree + full brief + PR per task.
    ├── A CLEAN PARENT CONTEXT (noisy subtask)?
    │   └── Would its intermediate findings change the parent's plan?
    │       ├── YES ──► keep it inline — you need the noise.
    │       └── NO ──► subagent: scoped tools, decision-bearing
    │                  brief, capped report format.
    ├── INDEPENDENT JUDGMENT on finished work?
    │   └── Pipeline stage: fresh session, spec + diff only,
    │       read-only, findings back through a human or the
    │       author stage. (Ch 06 for the full review discipline.)
    └── NONE OF THE ABOVE ──► one agent. "More agents" is a cost
                              center until one of the three gains
                              names itself.
```

## Checklist

**Implementation Checklist**

- [ ] Manifest written before launch: tasks, write-sets, hub files, branches, brief per task
- [ ] Write-sets verified disjoint — hubs (routers, configs, migrations, lockfiles) explicitly
  listed
- [ ] One worktree/workspace + one branch per parallel task; removed after merge
- [ ] Every unwatched agent got a full five-clause brief (no thin dispatches)
- [ ] Subagent definitions scope tools to the role; report format capped
- [ ] Session decisions written to the plan file before any dispatch that depends on them
- [ ] Review stages: fresh context, spec + diff only, read-only tools
- [ ] Fan-out sized to same-day human review; merges continuous, not big-bang

**Architecture Checklist**

- [ ] Default is one agent; each additional context justified by parallelism, isolation, or
  independent judgment
- [ ] All coordination via artifacts (repo, plan files, PRs) — nothing assumed shared
- [ ] Hierarchy flat: dispatcher + one specialist layer
- [ ] Role boundaries enforced by tool access, not instructions
- [ ] Human merge gate on every path to main — no agent (or pipeline) has merge authority
- [ ] Model/cost per role revisited with your own bake-off, not assumptions

**Code Review Checklist** (multi-agent output)

- [ ] Cross-PR pass done: duplicated helpers, conflicting conventions, hub-file collisions
  between parallel branches
- [ ] Each PR reviewed against ITS brief (Ch 04 rules) — and briefs compared for scope overlap
- [ ] Subagent-produced work consistent with the session's recorded decisions (check the plan
  file)
- [ ] Pipeline review transcript read — findings adjudicated by a human, not auto-applied
- [ ] Migration sequences / config registries verified once ALL parallel branches are merged
  (per-PR CI can't see the combination)

## Exercises

1. **Draw a real task graph.** Take your team's current epic and decompose it: nodes, dependency
   edges, write-set per node — hub files included. Mark what's genuinely parallelizable. Most
   engineers discover the honest answer is "two lanes, not six" — and that the hub files were
   invisible until asked for.
2. **Run a disciplined fan-out.** Pick 3–4 truly independent mechanical tasks (test backfill,
   lint migration). Manifest first, worktree + library brief each, PRs same day. Measure:
   wall-clock saved vs. total engineer time spent on specs + review. Decide, with numbers,
   whether fan-out paid.
3. **Build the firewall subagent.** Define a read-only repo-scout with a capped report format.
   Run the same exploratory question twice: inline in a working session, and via the scout.
   Compare the parent window's size and the quality of the *next* decision made in each session
   — that delta is what context isolation buys.
4. **Prove fresh eyes matter.** Have an agent implement a task, then request review twice:
   (a) same session ("review your work"), (b) fresh session with spec + diff only. Count
   real findings from each. Keep the numbers; you'll cite them when someone proposes
   self-review to save tokens.
5. **Stage a hub-file collision.** Deliberately launch two agents on tasks that both register a
   route (or add a migration). Watch where and how it fails; then re-run with the manifest
   partitioning the hub. The cheap version of this lesson is the exercise; the expensive
   version is production.

## Further Reading

- [Anthropic — Building effective agents](https://www.anthropic.com/research/building-effective-agents)
  — the case for simple, composable patterns over frameworks; the workflow taxonomy this
  chapter's three patterns descend from.
- [Anthropic — How we built our multi-agent research system](https://www.anthropic.com/engineering/built-multi-agent-research-system)
  — a production post-mortem of orchestrator + subagents at scale: token economics, dispatch
  brief quality, and coordination failures, from the builders.
- [Git — git-worktree documentation](https://git-scm.com/docs/git-worktree) — the isolation
  primitive underneath every fan-out in this chapter.
- Chapter 03 ([Context Engineering](03-context-engineering.md)) — plan files and externalized
  decisions: the artifacts multi-agent coordination lives on.
- Chapter 04 ([Prompt Engineering](04-prompt-engineering.md)) — the briefs that parallel and
  dispatched agents depend on entirely.
- Chapter 06 ([AI Code Review](06-ai-code-review.md)) — the review stage as a full discipline,
  and how automated first-pass review raises the fan-out ceiling.

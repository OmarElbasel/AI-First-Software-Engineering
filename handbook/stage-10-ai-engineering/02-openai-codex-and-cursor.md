# OpenAI Codex & Cursor

## Introduction

Chapter 01 went deep on one agent. This chapter widens the lens to the two other tools every
AI-first team encounters — **OpenAI Codex** (a coding agent available as a CLI, an IDE extension,
and a cloud service that works on delegated tasks) and **Cursor** (an AI-native IDE built around
inline completion, chat, and an embedded agent) — and, more importantly, to the question underneath
them: *which of your skills and which of your configuration are portable, and which are product
features you are renting?*

This matters because the tool landscape churns faster than any other layer of your stack. Models
leapfrog each other quarterly; products rename their features; the tool your team standardizes on
this year will look different next year. If your team's AI effectiveness lives in product-specific
muscle memory, churn resets it to zero every cycle. If it lives in a portable layer — instruction
files, verification commands, prompt discipline, review judgment — churn costs you a week of
adaptation. The engineering goal of this chapter is to build that portable layer deliberately:
one source of truth for your standards (`AGENTS.md`), thin per-tool adapters, and an evaluation
method for choosing tools based on your repository rather than on launch-day demos.

As in Chapter 01: product specifics here (flags, file formats, feature names) are a snapshot and
will drift; verify against current documentation. The comparative judgment — what to centralize,
what to adapt, how to evaluate — is the durable content.

## Why It Matters

- **Your team is already polyglot, whether you decided it or not.** One engineer lives in Cursor,
  another in a terminal agent, CI runs a headless agent, and a contractor brings whatever they use.
  Without a shared configuration layer, each tool follows a different notion of your standards —
  and the codebase records the disagreement permanently, one merged PR at a time.
- **Instruction files became a standard; configuration became portable.** `AGENTS.md` is a
  plain-markdown instruction file read by Codex, Cursor, and most other agents (Claude Code can be
  pointed at it in one line). That means the highest-value artifact you built in Chapter 01 — your
  encoded standards — can be written once and honored everywhere, if you structure it that way.
- **Tool choice is a recurring engineering decision, not a one-time religion.** Pricing, model
  quality, sandboxing, IDE fit, and enterprise constraints all shift. Teams that can *evaluate* —
  run a representative task set against a new tool in an afternoon and compare diffs — make this
  decision cheaply and reversibly. Teams that can't either freeze (missing real gains) or churn
  (burning weeks re-tooling on hype).
- **Form factor changes failure modes.** An IDE agent that edits as you watch fails differently
  from a CLI agent that works for ten minutes and presents a diff, which fails differently from a
  cloud agent that opens a PR while you sleep. Knowing which form factor fits which task — and
  which review posture each demands — is a real skill gap between teams that ship with AI and teams
  that clean up after it.
- **Lock-in here is workflow lock-in, not data lock-in.** Nothing stops you from leaving a coding
  tool — except that your rules live in its proprietary format, your automation calls its API, and
  your engineers' habits assume its UX. The cost is real and entirely preventable with one
  architectural decision made early: standards in a neutral file, adapters kept thin.

## Mental Model

Every coding agent is the same loop from Chapter 01 wearing a different product shell. Separate
the layers, and both tool choice and configuration strategy become clear.

```
        WHAT'S SHARED (engineer once, keep forever)
  ┌───────────────────────────────────────────────────────┐
  │   the agent loop: model → tools → feedback → repeat   │
  │   your standards:  AGENTS.md (plain markdown)         │
  │   your feedback:   tests, lint, types (tool-agnostic) │
  │   your prompts:    task specs (Ch 04), versioned      │
  │   your judgment:   review, delegation, verification   │
  └───────────────────────────┬───────────────────────────┘
                              │  consumed through
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
  ┌───────────┐        ┌───────────┐         ┌───────────┐
  │ CLI agent │        │ IDE agent │         │Cloud agent│
  │ Claude    │        │ Cursor    │         │ Codex     │
  │ Code,     │        │ (also:    │         │ cloud,    │
  │ Codex CLI │        │ Copilot,  │         │ background│
  │           │        │ Windsurf) │         │ agents    │
  ├───────────┤        ├───────────┤         ├───────────┤
  │ long tasks│        │ you watch │         │ delegated │
  │ terminal +│        │ inline    │         │ async; PR │
  │ CI native │        │ edits, tab│         │ as output │
  │ review:   │        │ review:   │         │ review:   │
  │ the diff  │        │ as-you-go │         │ the PR,   │
  │ at the end│        │ + the diff│         │ cold      │
  └───────────┘        └───────────┘         └───────────┘
        PRODUCT SHELL (rented: UX, config format,
        sandboxing, pricing, feature names — expect churn)
```

**The portable layer is yours; the shell is rented.** Standards, feedback commands, prompts, and
judgment transfer across every column — they are investments. Config file formats, approval-mode
names, and UI affordances are the shell — learn them, but never let team knowledge live *only*
there.

**Form factor determines the review posture.** The closer the agent is to your keystroke, the more
review happens implicitly as you watch — and the more a lapse of attention lets a subtle edit
through. The further the agent is from you (CLI task, cloud PR), the more the review is a
deliberate, cold read of a finished diff. Neither is safer per se: watching breeds
over-trust-by-familiarity; delegating breeds rubber-stamping of large diffs. Chapter 06 builds the
review discipline for both.

**Instruction files are read differently but written the same.** Codex reads `AGENTS.md` natively
(including nested ones, closest-file-wins, for monorepo scoping). Cursor supports `AGENTS.md`
alongside its own `.cursor/rules/` format, which adds scoping metadata (glob-attached rules,
always-on rules). Claude Code reads `CLAUDE.md`. The strategy that survives all of this: **content
in one neutral file, tool-specific features used only for what they uniquely do** (like Cursor's
glob-scoped attachment), each adapter a few lines.

A working definition:

> **Codex and Cursor are the same agent loop in different form factors — delegated/CLI and
> IDE-embedded respectively. Engineering a multi-tool team means splitting your investment:
> standards, feedback, and prompts in a portable layer (AGENTS.md + tool-agnostic commands) that
> every agent consumes, and per-tool configuration kept to thin adapters — so tool choice becomes
> a cheap, reversible, evaluable decision instead of an identity.**

## Production Example

**Invoicely's** team is realistically mixed. The founding engineer works in a terminal with Claude
Code (Chapter 01's setup). A frontend engineer lives in Cursor and leans on inline completion for
component work. A part-time contractor uses Codex CLI, and the team has started delegating
well-specified, low-risk tasks (dependency bumps, test backfills) to Codex's cloud agent, which
returns PRs overnight. CI runs a headless review pass. Four consumers of the same standards.

The naive version of this team has four sets of rules: a `CLAUDE.md` written in January, a
`.cursor/rules/` folder written in March by someone else, whatever the contractor's global config
says, and nothing for the cloud agent. The tenant-scoping rule — Invoicely's most important
invariant — appears in two of the four, in different wording, one of them stale. Convention drift
stops being hypothetical: it's visible in the diff style of each engineer's PRs.

This chapter rebuilds that as one system. `AGENTS.md` at the repo root becomes the single source
of truth — the same commands, architecture rules, and conventions from Chapter 01, in plain
markdown with no tool-specific syntax. `CLAUDE.md` shrinks to a pointer plus the few Claude
Code-specific notes (hook expectations). Cursor keeps two thin native rules where its scoping
genuinely helps: an always-on pointer to `AGENTS.md`, and a glob-scoped rule attaching
frontend-specific conventions to `frontend/**`. The cloud agent and the contractor's Codex read
`AGENTS.md` natively with zero extra work. One file changes when a convention changes; every agent
— and every human, because `AGENTS.md` is readable onboarding documentation — moves together.

## Folder Structure

```
invoicely/
├── AGENTS.md                       # THE standards file — single source of truth,
│                                   #   plain markdown, no tool-specific syntax;
│                                   #   read natively by Codex, Cursor, and others
├── CLAUDE.md                       # thin adapter: "Read AGENTS.md and follow it."
│                                   #   + Claude Code-specific notes only (hooks)
├── .cursor/
│   └── rules/
│       ├── use-agents-md.mdc       # always-applied pointer to AGENTS.md — makes
│       │                           #   the source of truth explicit inside Cursor
│       └── frontend.mdc            # glob-scoped (frontend/**) — the ONE Cursor
│                                   #   feature worth using natively: rules that
│                                   #   attach only when matching files are touched
├── frontend/
│   └── AGENTS.md                   # nested instructions for the frontend package —
│                                   #   closest-file-wins lets a monorepo scope rules
│                                   #   without bloating the root file
├── .claude/                        # Chapter 01's layer, unchanged — permissions and
│   └── ...                         #   hooks are enforcement, not instructions, so
│                                   #   they don't move into AGENTS.md
├── Makefile                        # tool-agnostic verification: `make test`,
│                                   #   `make lint`, `make check` — every agent and
│                                   #   every CI job calls the same entry points
└── docs/                           # deep context, tool-neutral (unchanged)
```

Why this shape: **content converges, enforcement stays put.** Instructions (what agents should
know) centralize into `AGENTS.md` because every tool can read markdown. Enforcement (what agents
may do — permissions, hooks, sandboxes) stays in each tool's native mechanism because it *is*
tool behavior, not knowledge. The `Makefile` matters more than it looks: encoding verification as
`make check` means instruction files, CI, and every agent share one entry point, and a change to
how tests run happens in exactly one place.

## Implementation

### AGENTS.md — the single source of truth

Structurally identical to Chapter 01's `CLAUDE.md`, because the job is identical — commands first,
imperative rules, pointers to depth:

```markdown
# AGENTS.md

Instructions for AI coding agents (and a fine onboarding doc for humans).

## Verify your work
- `make test`   — fast test tier; run after every change
- `make lint`   — ruff + format check + mypy
- `make check`  — both; a task is not done until this passes

## Architecture rules
- Business logic in app/services/, never in routers.
- DB access through repositories; services never build raw SQL.
- Schema changes ONLY via new Alembic migrations; never edit an
  existing migration.
- Money is integer cents everywhere.
- Every query on tenant-owned tables filters by the authenticated
  account_id (tenant isolation — our most important invariant).

## Conventions
- Mirror neighboring code; new endpoints copy app/api/invoices.py.
- Tests use tests/factories.py; cover the cross-tenant (404) case.
- No new dependencies without asking. Keep diffs scoped to the task.

## Deeper context
- docs/architecture.md, docs/decisions/ (ADRs)
```

And `CLAUDE.md` collapses to an adapter:

```markdown
# CLAUDE.md
Read AGENTS.md and follow it exactly.
Claude Code-specific: hooks will block edits to applied migrations and
lint your edits — treat hook messages as instructions.
```

### Cursor — native features only where they add something

`.cursor/rules/use-agents-md.mdc` (always applied):

```markdown
---
description: Project standards source of truth
alwaysApply: true
---
Follow the rules in AGENTS.md at the repo root. It is the single
source of truth for this project's conventions.
```

`.cursor/rules/frontend.mdc` (attached only when frontend files are in play):

```markdown
---
description: Frontend conventions for Invoicely's Next.js app
globs: ["frontend/**"]
alwaysApply: false
---
- Server Components by default; "use client" only for interactivity.
- Data fetching through lib/api/ client functions — never fetch()
  directly in components.
- Money arrives as integer cents; format with lib/money.ts only.
```

The glob-scoped rule is the one genuinely Cursor-native capability used here: frontend conventions
load only when relevant, protecting context on backend tasks. Everything else points at the
neutral file. One caution that motivates this chapter's AI-mistakes section: a rule with
`alwaysApply: false`, no matching glob, and a vague description may simply *never attach* — config
that exists but never loads is invisible until you audit it.

### Codex — CLI and cloud

Codex CLI reads `AGENTS.md` automatically (root, and nested files for subdirectories). The
operative configuration is the approval/sandbox posture per task:

```bash
# Interactive, confirm before commands run — default working mode
codex

# Scoped autonomous run in a sandboxed workspace — for well-specified,
# low-risk tasks; review the diff at the end
codex exec "Backfill tests for app/services/credit_notes.py following
tests/factories.py patterns. Run 'make check' and fix failures. Do not
modify non-test files." 
```

Approval-mode and sandbox flag names change between versions; the posture decision doesn't:
interactive confirmation while you're steering, full autonomy only inside a sandbox with a scoped
task, and never full autonomy plus network plus credentials. For the cloud agent, the task
specification *is* the interface — it works from your repo and `AGENTS.md` without your
environment, so tasks that depend on undocumented local knowledge fail there first. A team whose
delegated tasks keep failing in the cloud agent has just learned, cheaply, that its repo isn't
self-describing — fix the repo, and both agents and new hires benefit.

## Engineering Decisions

**Decision 1: Standardize on one tool, or support several?** Default: standardize the *layer*,
not the tool — `AGENTS.md`, `make check`, prompt library — and let engineers choose form factor,
because the productivity difference between an engineer in their preferred tool and a mandated one
is real. Mandate a single tool only when a hard constraint forces it (enterprise data-handling
approval for one vendor, a compliance boundary). What you never do is let *standards* vary by
tool — that's the drift this chapter exists to prevent.

**Decision 2: Where does each kind of content live?** Knowledge → `AGENTS.md` (neutral).
Tool-unique capability → native config, thin (Cursor's glob scoping; Claude Code's hooks).
Verification → `Makefile`/scripts, referenced by name everywhere else. The test for "does this go
in a native file?": *would this line mean anything to a different agent?* If yes, it belongs in
`AGENTS.md`.

**Decision 3: Which form factor for which task?** IDE agent for high-context, watch-it work —
UI components, refactors where you steer by feel, anything where seeing intermediate states helps.
CLI agent for task-sized delegated work with a verifiable finish line — endpoints, migrations,
test suites — where you review a finished diff. Cloud/background agents for well-specified,
low-risk, parallelizable work — dependency bumps, test backfills, mechanical migrations — where
the PR-later loop is a feature, not a delay. The gradient is *specification quality*: the further
the agent is from you, the more the written task spec has to carry (Chapter 04).

**Decision 4: How to evaluate a new tool without burning a month?** A fixed, repo-specific task
set: five real tickets from your history (one endpoint, one bug, one refactor, one test task, one
frontend change), run in a worktree per tool, scored on a rubric you wrote in advance — convention
adherence (did it follow `AGENTS.md` unprompted?), verification behavior (did it run and pass
`make check`?), diff scope (did it touch only what the task needed?), and correction count (how
many times did you intervene?). An afternoon of this beats any benchmark, because the benchmark's
repo isn't yours. Re-run it when a major version ships; switching costs stay low because your
config layer already ports.

**Decision 5: What do you let the cloud agent touch?** Start with reversible, low-blast-radius,
high-specification tasks and widen with evidence. The first weeks' PRs get full-depth review (they
are your evaluation data); tasks that consistently arrive clean earn a lighter posture. Schema
changes, auth code, and payment paths stay human-led regardless — not because the agent can't,
but because Stage 9 taught you where mistakes are expensive, and expensive-mistake territory is
where you spend your own attention.

## Trade-offs

| Choice | Gain | Cost |
|---|---|---|
| Standardize on one tool | Shared muscle memory, one config to maintain, simpler support | Forced fit for some work styles; single-vendor exposure; switching becomes political |
| Free tool choice + shared layer | Each engineer at max productivity; churn-resistant | Requires the AGENTS.md discipline; form-factor-specific bugs vary by desk |
| AGENTS.md as source of truth | Write once, every agent + humans aligned | Lowest-common-denominator: can't express tool-unique features there |
| Native config per tool | Full access to each tool's power features | Fork of standards; N files to update per convention change; drift is the default |
| IDE agent (Cursor) | Tight feedback, steer mid-flight, inline speed | Attention-hungry; over-trust from watching; review rigor decays as edits feel familiar |
| CLI agent | Task-sized delegation, CI-native, clean diff review | No mid-flight steering; wrong approaches surface only at the end (plan-first mitigates) |
| Cloud/delegated agent | Parallel work while you sleep; zero local footprint | Total dependence on written spec + repo self-description; cold PR review burden |
| Frequent tool re-evaluation | Capture real gains early | Evaluation time; team whiplash if switches are frequent — evaluate often, switch rarely |

## Common Mistakes

- **Choosing by demo, not by your repo.** Launch demos run on greenfield code. The only benchmark
  that predicts your experience is your own ticket set run against your own conventions —
  Decision 4's afternoon evaluation. Teams that skip it either adopt hype or dismiss real
  improvements, with equal confidence.
- **Letting rules fork.** A convention gets updated in `CLAUDE.md` but not `.cursor/rules/`, or
  vice versa. Three months later two engineers argue about the standard, and both are right —
  according to their tool. If rules exist in more than one place, drift isn't a risk; it's a
  schedule.
- **Assuming feature parity.** "Plan mode", hooks, glob-scoped rules, nested instruction files,
  sandbox semantics — each tool has some, not all. Instructions written for one tool's features
  ("use plan mode before editing") are noise to another. Keep `AGENTS.md` feature-neutral;
  express tool features in tool files.
- **Delegating under-specified work to the most distant form factor.** The cloud agent gets
  "improve error handling" and returns a 40-file PR nobody wants to review. Distance demands
  specification; vague tasks belong in the tightest loop (IDE, or a conversation), not the
  loosest.
- **Ignoring the economics.** Tools price differently (seats, usage, token pass-through), and
  agentic workflows multiply token consumption. A team that never looks at usage data discovers
  its "cheap" workflow at invoice time. Pricing changes fast — what matters is *someone owns
  watching it*.
- **Rule files that never load.** Scoped rules with wrong globs, conditional rules whose
  descriptions never trigger attachment, nested files shadowed by precedence — every scoping
  mechanism is also a way for config to silently not apply. Periodically test: ask the agent to
  do something a rule forbids, and see if the rule actually pushes back.

## AI Mistakes

The multi-tool setting has its own failure family: each assistant assumes *its own* world when
configuring a shared one.

### Claude Code: instructions only it can follow, written into the shared file

Asked to create or extend `AGENTS.md`, Claude Code tends to write instructions in terms of its own
capabilities — "enter plan mode before multi-file changes", "the PostToolUse hook will lint your
edits", "ask for permission before running docker" — because those are true *in its world*. In
Codex or Cursor, those lines are dead weight at best and confusing at worst (an agent may waste
turns looking for a "plan mode" it doesn't have). The shared file quietly becomes a Claude Code
file that other tools half-understand.

**Detect:** tool feature names (plan mode, hooks, permission prompts, subagents, specific slash
commands) inside `AGENTS.md`; instructions that reference enforcement mechanisms rather than
standards; other tools behaving as if sections of the file don't exist (because, to them, they
don't).

**Fix:** re-partition knowledge from mechanism:

> Rewrite AGENTS.md so every instruction is meaningful to ANY coding agent: standards, commands,
> and conventions only — no references to plan mode, hooks, permissions, or any tool-specific
> feature. Move tool-specific notes into that tool's own file (CLAUDE.md, .cursor/rules/). If an
> instruction describes how a tool enforces a rule rather than the rule itself, it moves.

### GPT (Codex): the drive-by cleanup that bloats a delegated diff

Given an autonomous, task-scoped run, Codex-style agents tend to "improve" adjacent code along the
way — reformatting untouched functions, renaming a variable for clarity, upgrading a pattern in a
file the task merely passed through. Each edit is individually defensible; collectively they turn
a reviewable 80-line diff into a 600-line one, bury the actual change, and create merge conflicts
with parallel work. In the cloud-agent form factor this is worst, because no one was present to
say "stop" — the padding is discovered at PR review, where it taxes the scarcest resource this
stage manages: reviewer attention.

**Detect:** diff stats disproportionate to the task; files changed that the task description
doesn't explain; formatting-only hunks mixed into logic changes; PR descriptions that say "also
cleaned up" anything.

**Fix:** scope as an explicit instruction, and reject at review:

> Keep the diff strictly scoped to the task. Do not reformat, rename, or refactor any code the
> task does not require changing — if you notice unrelated improvements, list them at the end as
> suggestions instead of applying them. A larger diff is a worse diff unless the task demands it.

(Then enforce it: a scope note in `AGENTS.md`, and reviewers who send back padded diffs — Chapter
06 makes this a standing review rule.)

### Cursor: scoped rules that silently never attach

Asked to organize project rules, Cursor tends to produce an elegant taxonomy of scoped rule files
— per-directory globs, conditional descriptions, `alwaysApply: false` everywhere — that *looks*
like disciplined engineering and partially doesn't function: a glob that doesn't match the actual
tree (`src/**` in a repo rooted at `backend/`), a conditional rule whose description is too vague
for the attachment heuristic, a critical rule left non-always-apply. Unlike a syntax error,
nothing fails: the agent simply behaves as if the rule doesn't exist, and the team debugs
"the AI ignores our conventions" for weeks with the config sitting right there.

**Detect:** rule files whose globs you can't confirm match real paths; convention violations in
exactly the areas covered by conditional rules; agent behavior that doesn't change after a rule
is edited (the tell that it never loaded).

**Fix:** audit attachment, and default critical rules to unconditional:

> For each rule file: state whether it is always-applied, glob-attached, or model-selected, and
> test each glob against the actual repository tree. Any rule protecting an important invariant
> becomes alwaysApply: true or moves into AGENTS.md. Then verify live: instruct me to violate one
> rule from each file and confirm the rule pushes back.

## Best Practices

- **One neutral standards file; adapters under ten lines.** `AGENTS.md` holds the content;
  `CLAUDE.md` and `.cursor/rules/` pointer files hold almost nothing. A convention change is a
  one-file PR.
- **Make verification tool-agnostic and single-entry.** `make check` (or equivalent) called by
  every instruction file, every agent, and CI. Never let each tool's config describe test
  invocation differently.
- **Use native features only for what they uniquely do.** Cursor's glob scoping, Claude Code's
  hooks, Codex's nested instruction files — adopt each where it earns its place; resist
  re-expressing shared content in them.
- **Match form factor to task distance.** Watchable work → IDE. Task-sized, verifiable work →
  CLI. Well-specified, low-risk, parallel work → cloud. Vague work → none of the above; write a
  better spec first.
- **Evaluate on your own tickets, on a schedule.** Keep the five-task evaluation set and rubric
  in the repo; re-run on major releases. Evaluate often, switch rarely.
- **Review posture scales with distance.** As-you-go review for IDE work still ends with a full
  diff read; delegated and cloud output gets cold, complete review — no diff merges on the
  strength of having watched some of it happen.
- **Give autonomy only inside sandboxes, in every tool.** The Chapter 01 rule is tool-independent:
  full-auto modes pair with isolated environments and scoped credentials, never with a workstation
  that can reach production.
- **Audit that config actually loads.** Quarterly (or when behavior seems off): violate one rule
  per file deliberately and confirm push-back. Silent non-attachment is this layer's signature
  failure.

## Anti-Patterns

**Tool churn as strategy.** Switching the team's primary tool every time a benchmark or launch
thread trends. Each switch resets habits, config polish, and evaluation baselines; the gains are
usually marginal over the portable layer you should have been investing in instead. The tell: the
team has strong opinions about tools and no `AGENTS.md`.

**The N-tool fork.** Maintaining full, parallel rule sets per tool "so each gets the optimal
version". Optimal for a week; divergent forever after. Nobody diffs instruction files across
tools, so the fork is discovered through inconsistent code, not through config review.

**Benchmark-driven adoption.** Choosing the coding agent by leaderboard position. Public
benchmarks measure greenfield task success on repos that aren't yours, with none of your
conventions, constraints, or legacy. They are useful signals about models and nearly useless
predictors of *your team's* experience versus your own five-ticket evaluation.

**The invisible standard.** Standards enforced only through one tool's mechanism (only a Claude
Code hook, only a Cursor rule) with no statement in the shared file and no CI backstop. Every
other tool — and every human — walks straight through the invariant. If it matters, it exists in
`AGENTS.md` *and* in CI; tool mechanisms are accelerators, not the source of truth.

**Delegation as abdication.** Using the cloud agent's async-ness to avoid specifying or reviewing:
fire vague tasks at it, merge whatever comes back green. This is the highest-distance form factor
paired with the lowest-discipline workflow — the exact inversion of what distance demands. The
resulting codebase is Chapter 06's cautionary opening.

## Decision Tree

"A task needs doing with AI — which tool and posture?"

```
Is the task specifiable in writing, with a verifiable finish line
("make check passes", "these tests exist and pass")?
├── NO ──► Don't delegate it yet. Tighten it: explore in an IDE/chat
│          session or write the spec (Ch 04). Vague tasks get the
│          tightest loop, never the loosest.
└── YES ──► Does it touch expensive-mistake territory
            (schema, auth, payments, security controls)?
    ├── YES ──► Human-led in IDE or CLI with plan-first; full review
    │           regardless of which tool. Never cloud-delegated.
    └── NO ──► Do you need to steer mid-flight (design emerging as
               you go, aesthetics, uncertain approach)?
        ├── YES ──► IDE agent (Cursor) — watch, steer, then still
        │           read the final diff cold.
        ├── NO, but I want it done now ──► CLI agent in a worktree;
        │           review the finished diff against the spec.
        └── NO, and it can wait / there are several like it ──►
                    cloud agent: one PR per task, scoped diff
                    demanded, cold full review on arrival.

Team-level: BEFORE any of this — is there one AGENTS.md every tool
reads, and one `make check` every tool runs? If not, that's the task.
```

## Checklist

**Implementation Checklist**

- [ ] `AGENTS.md` at repo root: commands, imperative rules, conventions — no tool-specific
  feature references
- [ ] `CLAUDE.md` and Cursor rule files reduced to thin adapters pointing at it
- [ ] Verification unified behind tool-agnostic entry points (`make test` / `make check`)
- [ ] Nested `AGENTS.md` files where a package's rules genuinely differ (monorepo)
- [ ] Cursor scoped rules: every glob tested against the real tree; critical rules always-applied
- [ ] Codex autonomous runs sandboxed and task-scoped; diff-scope instruction present
- [ ] Cloud-agent task template exists (spec + finish line + scope limits)
- [ ] Five-ticket evaluation set and rubric committed to the repo

**Architecture Checklist**

- [ ] Standards exist in exactly one place; adapters contain zero forked content
- [ ] Every invariant that matters is stated in `AGENTS.md` AND enforced in CI — tool mechanisms
  are additive
- [ ] Form-factor policy written down: what may be IDE-driven, CLI-delegated, cloud-delegated,
  and what stays human-led
- [ ] Review posture defined per form factor (watched work still gets a cold diff read)
- [ ] Tool spend is owned: someone watches usage against pricing changes

**Code Review Checklist** (multi-tool config and delegated output)

- [ ] Instruction-file diffs: change landed in `AGENTS.md`, not forked into an adapter
- [ ] No tool feature names leaking into the shared file
- [ ] Delegated/cloud PRs: diff scope matches the task; padding sent back, not merged
- [ ] New scoped rules: attachment condition verified, not assumed
- [ ] Evaluation rubric updated when the team's standards change (it encodes them)

## Exercises

1. **Consolidate a real fork.** Find a repo (yours or your team's) with more than one AI
   instruction file. Diff their *content* by hand, list every divergence, and rebuild as
   `AGENTS.md` + thin adapters. The divergence list is the drift that was already shipping.
2. **Run the bake-off.** Build the five-ticket evaluation set from your own closed tickets, write
   the rubric *before* running anything, and evaluate two tools you have access to in separate
   worktrees. Publish the scored comparison to your team — including where the rubric itself
   proved wrong.
3. **Test the loosest loop.** Write a full task spec (goal, constraints, finish line, scope
   limits) for a real low-risk task and delegate it to the most distant form factor you have
   (cloud agent, or a CLI agent run with no mid-flight input). Cold-review the result as if a
   stranger wrote it. Every review comment you make is a line your spec was missing.
4. **Audit rule attachment.** In a Cursor-configured repo, list every rule file with its
   attachment mode, test each glob against the tree, then violate one rule per file and record
   which ones actually pushed back. Fix the silent ones — and note how long they'd been silent.
5. **Write the form-factor policy.** For your team: which task classes go to IDE, CLI, cloud, and
   which stay human-led — with the review posture for each. One page. Then check it against the
   last ten AI-assisted PRs: where did practice disagree with the policy you just wrote?

## Further Reading

- [AGENTS.md](https://agents.md) — the open instruction-file convention: format, nesting,
  precedence, and adopting tools.
- [OpenAI Codex documentation](https://developers.openai.com/codex) — current CLI, IDE, and
  cloud-agent capabilities, approval modes, and sandboxing.
- [Cursor documentation — Rules](https://cursor.com/docs/context/rules) — rule types, scoping
  metadata, and `AGENTS.md` support.
- [Anthropic — Claude Code: Best practices for agentic coding](https://www.anthropic.com/engineering/claude-code-best-practices)
  — the reference agent's side of the same portable-layer argument.
- Chapter 01 ([Claude Code](01-claude-code.md)) — the enforcement layer (permissions, hooks) that
  deliberately does *not* centralize into `AGENTS.md`.
- Chapter 04 ([Prompt Engineering](04-prompt-engineering.md)) — task specifications, the skill
  that the distant form factors depend on entirely.

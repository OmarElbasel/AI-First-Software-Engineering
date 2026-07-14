# Claude Code

## Introduction

Claude Code is a terminal-based coding agent: you give it a task in natural language, and it works
toward that task by reading files, editing code, and running commands in a loop — observing the
result of each action and deciding the next one — until the task is done or it needs your input.
That loop is the difference between an *assistant* and an *agent*. An assistant proposes code and
you integrate it; an agent operates directly on your repository, verifies its own work against your
tests, and hands you a diff.

That power is exactly why it must be engineered rather than merely used. An agent that edits files
and runs commands inherits every property of the environment you run it in: your conventions (or
their absence), your permissions (or their absence), your verification commands (or their absence).
Out of the box, Claude Code arrives with strong general defaults and zero knowledge of your system.
Everything this chapter covers — the `CLAUDE.md` instruction file, the settings and permission
model, hooks, custom commands and skills, tool extensions, and headless operation — is the
configuration surface that replaces its guesses with your engineering standards.

This chapter treats Claude Code in depth as the stage's reference agent. Chapter 02 covers OpenAI
Codex and Cursor and, more importantly, which of these skills transfer between tools — the honest
answer is *most of them*, because the underlying shape (an agent loop you configure with
instructions, boundaries, and feedback) is shared. Specific feature names and flags evolve quickly;
the engineering judgment about what to configure and why does not. When a detail here conflicts
with the current official documentation, trust the documentation.

## Why It Matters

The gap between a developer who "uses Claude Code" and one who has engineered their repository for
it is larger than the gap between models. Configuration is where the leverage lives.

- **An unconfigured agent optimizes for plausible, not for yours.** Without instructions it
  guesses conventions from training data: a new ORM pattern here, a different error-handling style
  there, tests in the wrong framework. Each output "works" in isolation and erodes the codebase's
  coherence in aggregate. A configured agent lands code inside your architecture — the difference
  compounds with every task.
- **Feedback loops determine output quality more than prompts do.** An agent that can run your
  tests, linter, and type checker after each change catches its own mistakes and iterates; one that
  can't hands you code that merely *looks* finished. Making verification commands available and
  known to the agent is the single highest-return configuration step.
- **Permissions are the difference between a power tool and a hazard.** An agent that can run
  arbitrary commands can also run destructive ones — against your database, your git history, or
  (via a leaked credential in the environment) production. A deliberate permission policy lets you
  grant autonomy where it's safe and require confirmation where it isn't, instead of choosing
  between babysitting every action and disabling all safety.
- **Team consistency requires shared configuration.** If each engineer prompts the agent from
  scratch, you get five private dialects of your codebase. Committed configuration — instruction
  files, settings, hooks, reusable commands — makes the agent's behavior a reviewed, versioned team
  asset, exactly like CI configuration.
- **Headless operation turns the agent into infrastructure.** Claude Code runs non-interactively —
  in CI, in scripts, on a schedule — which unlocks automated review passes, issue triage, and
  routine maintenance (Chapter 08). That only pays off if the interactive configuration is already
  disciplined, because in CI nobody is watching the loop.
- **The cost of getting this wrong is quiet.** Nothing crashes when your agent is misconfigured.
  You just spend weeks accepting slightly-off diffs, repeating the same corrections, and reviewing
  code that ignores decisions you made months ago — a productivity leak with no error message.

## Mental Model

Claude Code is a loop, and you engineer the environment the loop runs in.

```
                        THE AGENT LOOP
             ┌────────────────────────────────────┐
             │              CONTEXT               │
             │  system prompt + CLAUDE.md +       │
             │  conversation + files it has read  │
             └──────────────────┬─────────────────┘
                                ▼
                       MODEL DECIDES ACTION
                                │
                                ▼
             ┌──────────────── TOOLS ──────────────┐
             │  read file · edit file · run command│
             │  search · git · extensions (MCP)    │
             └──────────────────┬──────────────────┘
                                ▼
                     ENVIRONMENT RESPONDS
             (file contents, test output, lint errors,
              command results — this is the feedback)
                                │
                                ▼
                    result appended to CONTEXT
                                │
                     loop until done / blocked

   YOU ENGINEER THE ENVIRONMENT, NOT THE MODEL:
     instructions  → CLAUDE.md          (what it should know every session)
     boundaries    → permissions, hooks (what it may and may not do)
     capabilities  → tools, MCP servers (what it can reach)
     feedback      → tests, lint, types (how it knows it's wrong)
     reuse         → commands, skills   (how good workflows get repeated)
```

Three consequences of the loop shape everything else:

**The agent is only as good as its feedback.** The loop self-corrects exactly where the
environment pushes back — a failing test, a type error, a hook that rejects an edit — and drifts
exactly where it doesn't. A repository with fast tests and strict linting *teaches the agent* every
iteration; a repository with neither lets every plausible mistake through. This is why Stage 8's
test suite is a prerequisite for AI-first speed, not an alternative to it.

**Context is a budget, and everything competes for it.** The model reasons over a finite window
holding your instructions, the conversation, and every file and command output it has seen. A
bloated `CLAUDE.md` crowds out task context; a session that has wandered across ten tasks buries
the current one in the residue of the previous nine. Managing what's *in* the loop is Chapter 03's
whole subject; here it sets one rule: everything you configure to load every session must earn its
tokens.

**Instructions are probabilistic; hooks are deterministic.** `CLAUDE.md` makes behavior likely.
Hooks — scripts that the harness runs on events like "about to edit a file" or "just ran a command"
— make behavior *certain*, because they execute outside the model and can block or correct actions
mechanically. Rules you can't afford to have broken belong in deterministic enforcement (hooks, CI,
permissions), not in prose the model might deprioritize under a full context.

A working definition:

> **Claude Code is an agent loop — model, tools, environment feedback — operating directly on your
> repository. Engineering it means designing the environment: instructions that encode your
> conventions, permissions and hooks that bound what it can do, verification commands that let it
> catch its own errors, and reusable configuration that makes all of this a versioned team asset
> rather than individual prompting habits.**

## Production Example

**Invoicely** — the invoicing SaaS from Stages 3–9 — is a real production repository: FastAPI
backend with a service layer, PostgreSQL with Alembic migrations, a Next.js frontend, Docker-based
deployment, a test suite with a fast unit tier and a Dockerized integration tier, and security
hardening that must not regress. A new engineer takes days to internalize all that. An unconfigured
agent never internalizes it — it starts from zero every session.

This chapter builds Invoicely's Claude Code layer so that an agent is productive and safe from the
first prompt. A `CLAUDE.md` at the repo root states the stack, the commands that verify work, the
five structural rules of the architecture (logic in services, thin routers, migrations only via
Alembic, money as integer cents, tenant scoping on every query), and pointers to deeper docs. A
committed `settings.json` grants the agent frictionless access to read-only and verification
commands (tests, lint, type checks) while requiring confirmation for git pushes and denying access
to `.env` files and destructive database commands. Two hooks enforce the non-negotiables prose
can't guarantee: one blocks any direct edit to versioned migration files, and one runs the linter
on every edited Python file so style violations are corrected inside the loop instead of surfacing
in review. A custom command packages the team's recurring "add an endpoint" workflow — which
Chapter 04 will treat as a prompt-engineering artifact — and CI runs Claude Code headlessly for a
first-pass review on every pull request (built in Chapters 06 and 08).

The measure of success is concrete: an agent asked to "add a `paid_at` timestamp to invoices"
produces an Alembic migration (not a hand-edited schema), a service-layer change with tenant
scoping, tests in the existing pattern, and a passing verification run — without the prompt
mentioning any of those requirements, because the environment carries them.

## Folder Structure

The AI-engineering layer of Invoicely's repository:

```
invoicely/
├── CLAUDE.md                      # agent instructions, loaded every session — the
│                                  #   repo's standards in ~100 firm lines (see below)
├── AGENTS.md                      # cross-tool instruction file (Ch 02); CLAUDE.md can
│                                  #   simply reference it to avoid duplication
├── .claude/
│   ├── settings.json              # committed team policy: permissions, hooks — reviewed
│   │                              #   in PRs like CI config, because it IS policy
│   ├── settings.local.json        # personal overrides (gitignored) — one engineer's
│   │                              #   extra permissions never silently become team policy
│   ├── commands/
│   │   └── new-endpoint.md        # reusable slash command for a recurring workflow —
│   │                              #   captured once, versioned, improved by review
│   ├── agents/
│   │   └── test-writer.md         # subagent definition (Ch 05) — scoped role with its
│   │                              #   own instructions and reduced tool access
│   └── hooks/
│       ├── protect-migrations.sh  # deterministic guard: blocks edits to applied
│       │                          #   migrations — a rule too important for prose
│       └── lint-on-edit.sh        # feedback injector: lint output returns to the loop
│                                  #   so the agent fixes style before you see the diff
├── docs/
│   ├── architecture.md            # deep context the agent reads ON DEMAND — kept out
│   │                              #   of CLAUDE.md to protect the context budget
│   └── decisions/                 # ADRs (Stage 1) — the "why" behind rules, so the
│                                  #   agent can honor intent, not just letter
├── backend/                       # the product itself, Stages 3–9
├── frontend/
└── .github/workflows/
    └── ai-review.yml              # headless Claude Code in CI (Ch 06/08)
```

Why this split exists: **`CLAUDE.md` is the always-loaded contract** (small, firm, universal),
**`docs/` is on-demand depth** (read when relevant, costing nothing otherwise), **`.claude/` is
behavior** (policy and automation, committed and reviewed), and **`settings.local.json` is the
personal escape hatch** that keeps individual preferences out of team policy. The committed/local
distinction mirrors every other config system in this handbook: shared behavior is versioned,
personal behavior is not.

## Implementation

### CLAUDE.md — the standards, not the codebase

The full starter with reasoning per section is in
[templates/claude-md-starter.md](../../templates/claude-md-starter.md). Invoicely's, condensed:

```markdown
# CLAUDE.md

## Project
Invoicely: multi-tenant invoicing SaaS (FastAPI + PostgreSQL backend,
Next.js frontend). In production with paying customers — prefer boring,
proven approaches; breaking changes need a migration path.

## Commands
- Test (fast tier):   cd backend && pytest -m "not integration" -q
- Test (full):        cd backend && make test-integration
- Lint + format:      cd backend && ruff check . && ruff format --check .
- Types:              cd backend && mypy app/
- Migrations:         cd backend && alembic revision --autogenerate -m "..."
- Frontend checks:    cd frontend && npm run lint && npm run typecheck

Run the fast test tier and lint after every change. A task is not done
until they pass.

## Architecture rules
- Business logic lives in app/services/, never in routers. Routers stay
  thin so logic is testable without HTTP.
- Database access goes through repositories; services never build raw SQL.
- Schema changes ONLY via new Alembic migrations. Never edit an existing
  migration file; never modify models without a migration.
- Money is integer cents everywhere. Never float, never Decimal in APIs.
- Every query on tenant-owned tables must filter by the authenticated
  account_id. No exceptions — this is our tenant isolation boundary.

## Conventions
- Follow the patterns of neighboring code over general best practices.
- New endpoints copy the structure of app/api/invoices.py.
- Tests use the factories in tests/factories.py — don't hand-build models.
- No new dependencies without asking.

## Deeper context (read when relevant)
- docs/architecture.md — system overview and layering
- docs/decisions/ — ADRs; check before proposing structural changes
```

Every line either changes agent behavior or tells it how to verify work. There is no prose the
agent could learn by reading the code — that would spend context on the discoverable. Note the tone:
imperative and specific ("never edit an existing migration") rather than aspirational ("we value
clean code"). Instruction files are specifications, not culture documents.

### settings.json — the permission policy

```json
{
  "permissions": {
    "allow": [
      "Bash(pytest*)",
      "Bash(ruff*)",
      "Bash(mypy*)",
      "Bash(alembic revision*)",
      "Bash(npm run lint*)",
      "Bash(npm run typecheck*)",
      "Bash(git status*)",
      "Bash(git diff*)",
      "Bash(git log*)"
    ],
    "ask": [
      "Bash(git push*)",
      "Bash(alembic upgrade*)",
      "Bash(docker*)"
    ],
    "deny": [
      "Read(.env*)",
      "Read(**/secrets/**)",
      "Bash(psql*)",
      "Bash(rm -rf*)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command",
                    "command": ".claude/hooks/protect-migrations.sh" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command",
                    "command": ".claude/hooks/lint-on-edit.sh" }]
      }
    ]
  }
}
```

The policy reads as three tiers of trust. **Allow** covers verification and read-only inspection —
the commands you *want* the agent running constantly, with zero friction, because they are the
feedback loop. **Ask** covers actions with blast radius beyond the working tree — pushing, applying
migrations, touching containers — where a human glance is cheap insurance. **Deny** covers what the
agent never needs: secret values (a secret pasted into context is disclosed — Stage 9, Chapter 04)
and direct database or destructive filesystem access. Exact matcher syntax and event names evolve;
verify against current documentation rather than trusting any example, including this one.

### Hooks — deterministic enforcement

`protect-migrations.sh` receives the pending tool call as JSON and rejects edits to applied
migrations:

```bash
#!/usr/bin/env bash
# Blocks edits to existing Alembic migration files. New migrations are
# created via `alembic revision` (allowed); history is immutable (Stage 6).
file_path=$(jq -r '.tool_input.file_path // empty')
if [[ "$file_path" == *"/alembic/versions/"* ]] && [[ -f "$file_path" ]]; then
  echo "BLOCKED: $file_path is an applied migration. Create a new migration
with 'alembic revision' instead of editing history." >&2
  exit 2   # non-zero: block the action; stderr goes back to the agent
fi
exit 0
```

The exit code blocks the action mechanically, and the stderr message feeds back into the loop — so
the agent doesn't just fail, it learns the correct move *within the same task*. This is the pattern
for every hook: enforce the boundary, then teach the alternative. `lint-on-edit.sh` is the same
idea inverted — it runs `ruff` on the edited file and returns violations as feedback, so style is
corrected inside the loop instead of in your review.

### A reusable command

`.claude/commands/new-endpoint.md` packages a recurring workflow into a slash command the whole
team invokes as `/new-endpoint`:

```markdown
Add a new API endpoint: $ARGUMENTS

Follow this exact sequence:
1. Read app/api/invoices.py and mirror its structure precisely.
2. Schema in app/schemas/, service method in app/services/,
   route in app/api/. Router stays thin.
3. Tenant scoping: every query filters by account_id from the
   authenticated principal. Ownership returns 404, not 403.
4. Tests: happy path, validation failure, cross-tenant access
   (must 404), unauthenticated (must 401). Use tests/factories.py.
5. Run the fast test tier and lint. Fix everything before reporting.
```

This is a prompt as a versioned artifact — Chapter 04 develops the discipline; the mechanism to
notice here is that good workflows get *captured* in the repo, reviewed like code, and stop living
in one engineer's chat history.

### Headless — the agent as infrastructure

```bash
claude -p "Run the fast test tier. If any test fails, summarize each
failure with the file and likely cause. Output markdown." \
  --allowedTools "Bash(pytest*),Read" \
  --output-format json > triage.json
```

Non-interactive mode takes a prompt, runs the same loop with an explicitly narrowed toolset, and
exits — which is what makes CI review passes (Chapter 06) and scheduled maintenance (Chapter 08)
possible. The narrowed `--allowedTools` matters: in CI nobody answers permission prompts, so you
grant precisely what the task needs and nothing else.

## Engineering Decisions

**Decision 1: What goes in CLAUDE.md vs `docs/` vs nothing at all?**
The test is *frequency times discoverability*. Needed every session and not discoverable from code
(commands, non-negotiable rules, conventions that look optional) → `CLAUDE.md`. Needed occasionally
and too big to always load (architecture rationale, ADRs) → `docs/`, with a one-line pointer in
`CLAUDE.md`. Discoverable by reading the code (what functions exist, current folder layout) →
nothing; the agent reads code fluently, and duplicating it creates a staleness liability. Invoicely
keeps `CLAUDE.md` near 100 lines by pushing depth into `docs/` — protecting the context budget.

**Decision 2: Instructions or hooks for a given rule?** By failure cost. "Prefer our factory
functions in tests" — a violation costs one review comment, so an instruction (probabilistic)
suffices. "Never edit an applied migration" — a violation can corrupt schema history across
environments (Stage 6), so it gets a hook (deterministic). The rule of thumb: if you would want CI
to reject it, prose isn't enough; encode it mechanically. Hooks carry maintenance cost, so reserve
them for rules whose violation is expensive — Invoicely ships two, not twenty.

**Decision 3: How much autonomy?** Permission policy is a dial, not a binary. Invoicely
auto-allows the feedback loop (tests, lint, types — high frequency, zero risk), asks on
blast-radius actions (push, migrate, docker — low frequency, so prompts are cheap), and denies
secrets and destructive commands outright (no legitimate task needs them). Fully-permissive modes
exist for a reason — but the reason is *sandboxed, disposable environments* (a container, a
worktree, no production credentials), never a workstation that can reach production. Match autonomy
to the blast radius of the environment, not to your patience with prompts.

**Decision 4: Plan first, or let it build?** For multi-file work, requiring a plan before edits
(Claude Code has a dedicated plan mode; a "propose an approach first, don't edit yet" instruction
works in any tool) costs one review minute and catches the expensive failure class: a wrong
approach executed thoroughly. Invoicely's norm — plan for anything touching more than two files or
any schema; straight execution for scoped single-file tasks. Reviewing a plan is minutes; unwinding
a confidently wrong 15-file diff is hours.

**Decision 5: Where does team configuration live?** In the repo, reviewed in PRs. `settings.json`,
hooks, and commands are policy — an engineer widening a permission or weakening a hook is a change
to what an agent may do to the codebase, and deserves the same review as a CI change. Personal
preferences go in gitignored `settings.local.json`. The anti-pattern is invisible per-machine
configuration: the team believes it has a policy, and actually has five.

## Trade-offs

| Choice | Gain | Cost |
|---|---|---|
| Rich CLAUDE.md | Conventions followed without prompting | Context budget; staleness liability; diminishing returns past ~150 lines |
| Minimal CLAUDE.md | Cheap context, nothing to maintain | Same corrections re-typed forever; convention drift across the team |
| Strict permissions | Bounded blast radius, safe by default | Prompt fatigue → engineers rubber-stamp or over-widen; slower loop |
| Broad autonomy | Fast, uninterrupted agent loop | One destructive command away from a bad day; safe only sandboxed |
| Many hooks | Deterministic guarantees | Each adds latency to every matching action; scripts to maintain; failures confuse sessions |
| Instructions only | Zero mechanism overhead | Non-negotiables become negotiable under a full context window |
| Plan-first workflow | Catches wrong approaches early | Ceremony on trivial tasks if applied indiscriminately |
| Headless automation | Review/maintenance at zero marginal effort | Unattended loop: needs narrow tools, spend caps, and output treated as *input* to humans |

The through-line: every increment of agent capability is bought with either configuration effort or
risk. Paying with configuration is a one-time, reviewable cost; paying with risk is a recurring,
invisible one. When in doubt, start strict and widen deliberately — loosening a permission that
proved annoying is trivial; discovering what an over-permissive agent did last Tuesday is not.

## Common Mistakes

- **Accepting "done" without verification.** The agent reports success with the same confidence
  whether the tests passed, were skipped, or don't exist. If verification commands aren't in
  `CLAUDE.md` and demanded ("a task is not done until they pass"), you are reviewing the agent's
  self-assessment, not its work. Read the diff; check that tests actually ran.
- **Treating it as a chat window instead of an agent.** Pasting code fragments into a
  conversation and copying answers back throws away the whole loop — file access, command
  execution, self-verification. If you find yourself copy-pasting, you're using 10% of the tool.
- **One eternal session.** Context accumulated across unrelated tasks degrades every subsequent
  task — earlier instructions fade, stale file versions linger, and behavior gets erratic. Start
  fresh (or clear) per task; sessions are cheap, polluted context is not.
- **Never updating CLAUDE.md.** The file is written once at setup, then the team spends months
  re-typing the same correction in prompts. The discipline: when you correct the agent twice for
  the same thing, that correction becomes a line in `CLAUDE.md` — it's the agent's code review
  feedback loop, and it should converge.
- **Permission fatigue → yolo.** Prompts feel like friction, so the agent gets run with
  everything allowed — on a machine with production credentials in the shell environment. The fix
  is tuning (auto-allow the safe, frequent commands so prompts become rare and meaningful), not
  surrender.
- **Vague, giant prompts.** "Improve the billing module" produces a sprawling diff nobody asked
  for. Agents excel with task-sized, verifiable goals — Chapter 04's subject, but the failure
  usually gets blamed on the tool rather than the prompt.
- **Blaming the model for an environment failure.** "It keeps writing raw SQL in services" is not
  a model limitation; it's a missing line in `CLAUDE.md` or a missing check in CI. Before switching
  tools or models, ask what feedback would have caught the mistake in the loop — and add it.

## AI Mistakes

The recursive case: assistants configuring their own (or another agent's) tooling. Generated
configuration *looks* authoritative and fails silently — a config key that doesn't exist doesn't
error, it just does nothing — so this class of output needs verification more than most code.

### Claude Code: the bootstrapped CLAUDE.md that describes instead of instructs

Asked to initialize or improve a `CLAUDE.md`, Claude Code tends to produce a thorough *description
of the repository* — directory-by-directory summaries, feature lists, restated README content —
rather than instructions. It reads as impressively complete and changes almost no behavior: the
agent could discover all of it by reading the code, and the bulk crowds the context budget that
actual rules need. The file passes human review precisely because it looks comprehensive.

**Detect:** `CLAUDE.md` over ~150 lines; paragraphs describing what exists rather than imperatives
about what to do; content that would go stale on the next refactor; no verification commands, or
commands buried under prose.

**Fix:** regenerate against the file's actual job:

> Rewrite CLAUDE.md to contain only: verification commands, non-negotiable rules stated as
> imperatives, conventions that differ from ecosystem defaults, and pointers to deeper docs. Delete
> anything discoverable by reading the code. Target under 120 lines. Every line must plausibly
> change your behavior on a future task — if it wouldn't, cut it.

### GPT: hallucinated configuration schema that fails silently

Asked to write `settings.json`, hook configuration, or CLI invocations, GPT-family models
confidently produce plausible-but-invented structure: permission syntax from an older version, hook
event names that don't exist, flags borrowed from other CLIs. Nothing errors — unknown keys are
typically ignored — so the team believes migrations are protected and secrets unreadable while the
configuration silently does nothing. It's the config-file equivalent of a hallucinated API, with a
longer detection delay because config is exercised rarely.

**Detect:** any generated config accepted without a live test; key names or event names you can't
find in current official docs; a hook that has never been observed to fire; permissions that don't
demonstrably block in a dry run.

**Fix:** validate against reality, not plausibility:

> Verify every key, event name, and flag in this configuration against the current official
> documentation, and state which doc section each comes from. Then give me a test procedure:
> a concrete action that should be blocked by each deny rule and each hook, so I can confirm the
> configuration actually fires before trusting it.

### Cursor: cross-tool config bleed

Asked (inside Cursor) to set up agent instructions for a repo the team also uses Claude Code on,
Cursor tends to write everything in its own conventions — rules files with its frontmatter and
glob-scoping semantics, or a `CLAUDE.md` structured like a Cursor rule — and to scatter duplicated,
slightly divergent copies across tool-specific locations. Each tool then follows a different
version of the "same" standards, and updates land in one copy only. The failure is architectural:
no single source of truth for the team's engineering rules.

**Detect:** tool-specific frontmatter or scoping syntax inside `CLAUDE.md`/`AGENTS.md`;
near-duplicate rule content across `.cursor/`, `CLAUDE.md`, and `AGENTS.md`; a convention update
that changed one file but not its siblings.

**Fix:** one source of truth, thin tool adapters (Chapter 02 develops this):

> Consolidate all engineering rules into AGENTS.md as plain markdown with no tool-specific syntax.
> Make each tool's native file (CLAUDE.md, Cursor rules) a thin pointer to it, containing only
> what that tool genuinely requires in its own format. Rules must exist in exactly one place.

## Best Practices

- **Write CLAUDE.md as a specification, and maintain it like code.** Imperative, specific, short.
  Review changes to it in PRs. The trigger for a new line is empirical: the same correction made
  twice.
- **Lead with verification commands, and demand they gate "done".** The agent's ability to check
  its own work is worth more than any stylistic instruction. "Run the fast tests and lint after
  every change" belongs in every instruction file.
- **Encode non-negotiables mechanically.** If a rule's violation would be expensive, a hook or CI
  check enforces it and the instruction merely explains it. Prose for preferences, mechanisms for
  invariants.
- **Tier permissions by blast radius.** Auto-allow the feedback loop, confirm actions that leave
  the working tree, deny secrets and destruction. Revisit the tiers when prompts get frequent
  enough to breed fatigue — fatigue is a config smell, not a fact of life.
- **Commit shared config; gitignore personal config.** `.claude/settings.json`, hooks, and
  commands are team policy and travel with the repo. `settings.local.json` keeps personal taste
  out of policy.
- **Capture recurring workflows as commands.** The third time you type substantially the same
  prompt, it becomes a versioned command file. Team knowledge belongs in the repo, not in chat
  scrollback.
- **Scope sessions to tasks.** Fresh context per task; plan mode (or plan-first prompting) for
  anything multi-file; review the plan, then let the loop run.
- **Keep secrets structurally out of reach.** Deny-rules on `.env` and secret paths, and never
  paste secret values into a prompt — a secret in context is a secret disclosed (Stage 9, Ch 04).
- **Re-verify tool specifics against current docs.** Feature names, flags, and config schemas in
  this chapter reflect the time of writing; the principles are stable, the syntax is not.

## Anti-Patterns

**The unsandboxed yolo.** Full autonomy — every permission granted, no confirmation — on a
workstation with production credentials, real `.env` files, and push access. The pitch is speed;
the price is that the *worst* action the agent can take is now the ceiling of your bad day.
Autonomy belongs in environments designed for it: containers, worktrees, scoped credentials.

**The CLAUDE.md landfill.** Every incident adds a paragraph, nothing is ever removed, and the file
grows into a 700-line scroll of restated documentation, stale rules, and pasted error logs. Past a
point, more instructions mean *worse* adherence — each line dilutes the others' share of the
model's attention. An instruction file is a curated budget, not an append-only log.

**Config as one engineer's private garden.** All the tuning lives in one person's local settings
and muscle memory; the repo has nothing. The team's AI effectiveness varies 5× by desk, the same
corrections are made in parallel, and when that engineer leaves, the "AI-first workflow" leaves
with them. Institutional knowledge goes in version control — that rule didn't change when the
knowledge became agent configuration.

**The self-modifying constitution.** Letting the agent freely edit its own `CLAUDE.md`, hooks, and
permissions as part of ordinary tasks. It will — helpfully — relax the rule it keeps colliding
with. Instruction and policy changes are precisely the changes that require human review; the agent
may *propose* them, never silently apply them.

**Hook maximalism.** Encoding every stylistic preference as a blocking hook until the loop crawls
and half the scripts are broken on someone's machine. Deterministic enforcement is for expensive
violations; taste is cheaper to enforce through lint config the agent runs anyway.

## Decision Tree

"I want the agent to reliably do (or never do) X — where does X belong?"

```
Is X a secret, destructive, or production-touching capability?
├── YES ──► permissions: deny (or ask). Not prose — mechanism.
└── NO ──► Would X's violation be expensive (data loss, schema history,
           security regression)?
    ├── YES ──► hook (block + teach) AND a CI check as backstop.
    │           Mention it in CLAUDE.md so the agent expects the wall.
    └── NO ──► Is X needed in EVERY session (a convention, a command,
               a standing rule)?
        ├── YES ──► Is it discoverable by reading the code?
        │   ├── YES ──► leave it out — the agent reads code; duplication
        │   │           goes stale and spends context.
        │   └── NO ───► CLAUDE.md, as one imperative line.
        ├── OCCASIONALLY ──► docs/ file, one-line pointer in CLAUDE.md.
        └── ONLY FOR ONE RECURRING TASK ──► a command/skill file
            (versioned prompt), invoked when that task comes up.

Cross-check: after placing X, ask "what feedback tells the agent it
violated X?" If the answer is "nothing until human review," X is not
yet engineered — add the test, lint rule, or hook that pushes back
inside the loop.
```

## Checklist

**Implementation Checklist**

- [ ] `CLAUDE.md` exists at the repo root: verification commands first, non-negotiable rules as
  imperatives, pointers to deeper docs — and nothing discoverable from code
- [ ] Verification commands actually work as written from a clean checkout (an agent will run
  them exactly as written)
- [ ] `.claude/settings.json` committed with tiered permissions: feedback loop allowed,
  blast-radius actions confirmed, secrets and destructive commands denied
- [ ] `settings.local.json` gitignored
- [ ] Every hook has been observed to fire: performed the forbidden action, saw the block and the
  teaching message
- [ ] Deny rules tested live (agent asked to read `.env` → refused)
- [ ] Recurring workflows captured as command files, not chat habits
- [ ] Headless invocations (CI) use explicitly narrowed tool lists

**Architecture Checklist**

- [ ] One source of truth for engineering rules; tool-specific files are thin adapters, not forks
- [ ] Rules placed by mechanism: permissions/hooks for the expensive, `CLAUDE.md` for the
  standing, `docs/` for the deep, prompts for the task-specific
- [ ] Every important rule has in-loop feedback (test, lint, type check, or hook) — not just
  human review
- [ ] Agent autonomy level matches environment blast radius (full autonomy only in sandboxes)
- [ ] Context budget respected: always-loaded content is small and earns its place

**Code Review Checklist** (for changes to the AI-engineering layer)

- [ ] `CLAUDE.md` diff: new lines are imperatives that change behavior; no descriptive filler;
  anything now stale removed
- [ ] `settings.json` diff: any widened permission justified in the PR description — this is a
  policy change, review it as one
- [ ] Hook changes: script tested on both matching and non-matching inputs; failure mode
  (script errors) doesn't wedge the session
- [ ] Command files: prompt includes verification steps, not just generation steps
- [ ] No secret values anywhere in instruction files, commands, or hook scripts

## Exercises

1. **Instrument a real repository.** Take a project you actually work on and write its `CLAUDE.md`
   from scratch: commands, five architecture rules, conventions that differ from defaults. Then
   run the same mid-sized task (a real ticket) in a fresh session with the file and, in a scratch
   copy, without it. Diff the two results — every difference is a measure of what your
   configuration is worth.
2. **Build and verify a guard.** Pick the one file class in your repo an agent must never edit
   (migrations, generated code, a vendored directory). Write the pre-edit hook that blocks it with
   a teaching message, then *prove it works*: ask the agent to edit the file and confirm the
   block, then confirm the agent's next action follows the taught alternative.
3. **Design the permission policy.** Write the allow/ask/deny tiers for your repo, with a one-line
   justification per entry. Trade with a colleague and attack each other's policies: find one
   allowed command that can do more damage than its tier implies, and one ask-rule frequent enough
   to breed fatigue.
4. **Capture a workflow.** Identify a prompt you have typed (in any tool) at least three times.
   Turn it into a committed command file with verification steps, and put it through code review.
   Note what the reviewer caught — prompts get better under review for the same reason code does.
5. **Run it headless.** Write a non-interactive invocation that runs your test suite and produces
   a markdown triage of failures, with a tool allowlist containing exactly what that task needs.
   Run it from a CI workflow or cron. This is the seed of Chapter 08's automation.

## Further Reading

- [Claude Code documentation](https://code.claude.com/docs) — the authoritative, current reference
  for settings, permissions, hooks, commands, and headless mode; trust it over any snapshot in
  this chapter.
- [Anthropic — Claude Code: Best practices for agentic coding](https://www.anthropic.com/engineering/claude-code-best-practices)
  — the engineering-blog treatment of instruction files, permissioning, and workflow patterns.
- [Anthropic — Building effective agents](https://www.anthropic.com/research/building-effective-agents)
  — the agent-loop mental model from the model provider's side; why simple loops beat elaborate
  scaffolds.
- [templates/claude-md-starter.md](../../templates/claude-md-starter.md) — this handbook's
  annotated starter; copy it, don't start from a blank file.
- [playbooks/starting-an-ai-first-project.md](../../playbooks/starting-an-ai-first-project.md) —
  where this chapter's setup steps fit in the first week of a new project.
- Stage 8 ([Test Strategy](../stage-08-testing/01-test-strategy.md)) — the feedback loop this
  chapter keeps invoking; an agent without tests is a generator, not an engineer.

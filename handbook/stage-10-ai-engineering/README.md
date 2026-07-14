# Stage 10 — AI Engineering

Turn the AI assistant from a fast autocomplete into a reliable engineering teammate — by
engineering the collaboration itself: the tools, the context they work in, the instructions they
receive, the review they get, and the workflows that make their output trustworthy at production
scale.

Every stage so far has used AI as a given: chapters assumed you build Invoicely with an assistant
and taught you to judge its output. This stage examines the other side of that relationship. An AI
coding agent is a system component like any other — it has an interface (prompts and context), a
configuration surface (instruction files, permissions, hooks), failure modes (plausible wrong code,
stale knowledge, drift over long sessions), and operational concerns (cost, verification,
automation). Components get engineered, not just used. The curriculum topics — Claude Code, OpenAI
Codex, Cursor, context engineering, prompt engineering, multi-agent systems, AI code review, AI
debugging, AI workflows — are the layers of that engineering: first the tools themselves, then the
two inputs that determine output quality (context and prompts), then the patterns that scale them
(multiple agents), and finally the practices that keep quality up at speed (review, debugging,
end-to-end workflows).

## Why this stage exists

The bottleneck in AI-assisted development is no longer generation — assistants produce more code
per hour than any team can carefully read. The bottleneck is everything around generation: giving
the agent enough context that its output fits your system, constraining it enough that it can't
quietly violate your standards, verifying its work without re-doing it, and knowing which tasks to
delegate and which to keep. Engineers who treat the assistant as a magic box get magic-box results:
impressive demos, unmaintainable diffs, and a codebase that slowly stops resembling anything anyone
decided. Engineers who treat it as a component — configured deliberately, fed deliberately,
reviewed deliberately — get a genuine force multiplier. The difference is not the model. It is the
engineering around the model, and that engineering is a learnable discipline with the same shape as
everything else in this handbook: mental models, trade-offs, failure modes, and judgment about when
each technique applies. This stage also grounds the handbook's own assets — the
[CLAUDE.md starter](../../templates/claude-md-starter.md), the
[AI code review checklist](../../checklists/code-review.md), and the
[AI-first project playbook](../../playbooks/starting-an-ai-first-project.md) — in the reasoning
that produced them.

## Chapters

| # | Chapter | Status |
|---|---------|--------|
| 01 | [Claude Code](01-claude-code.md) | Done |
| 02 | [OpenAI Codex & Cursor](02-openai-codex-and-cursor.md) | Done |
| 03 | [Context Engineering](03-context-engineering.md) | Done |
| 04 | [Prompt Engineering](04-prompt-engineering.md) | Done |
| 05 | [Multi-Agent Systems](05-multi-agent-systems.md) | Planned |
| 06 | [AI Code Review](06-ai-code-review.md) | Planned |
| 07 | [AI Debugging](07-ai-debugging.md) | Planned |
| 08 | [AI Workflows](08-ai-workflows.md) | Planned |

Eight chapters cover the stage's nine curriculum topics (Codex and Cursor share a chapter — the
judgment they require is comparative). The tool chapters come first because everything after them
needs a concrete tool in hand: Claude Code (Ch 01) in depth as the reference agent, then Codex and
Cursor (Ch 02) as the comparison set that separates portable skills from product features. Context
engineering (Ch 03) and prompt engineering (Ch 04) follow as the two input disciplines — what the
agent knows and what you ask of it — which together determine most of the variance in output
quality. Multi-agent systems (Ch 05) scale those foundations across parallel and specialized
agents. The last three chapters are the quality practices: reviewing AI code and using AI to
review (Ch 06), debugging with an agent without surrendering the scientific method (Ch 07), and
composing everything into repeatable team workflows and CI automation (Ch 08).

## Boundaries with other stages

- **The AI-first mindset** — why AI is a teammate, what stays human, delegation philosophy — is
  **Stage 1, Chapter 03**. This stage assumes that conviction and teaches the practice: tools,
  configuration, techniques, workflows.
- **Verification mechanics** — test strategy, what to test, the test pyramid — are **Stage 8**.
  This stage wires those tests into agent feedback loops and CI gates; it does not re-teach how to
  write them.
- **Security judgment** — what to look for when reviewing code for vulnerabilities — is
  **Stage 9**. Chapter 06 here builds the review *workflow* (human and automated) that applies it.
- **CI/CD infrastructure** — GitHub Actions mechanics, runners, deployment pipelines — is
  **Stage 7, Chapters 05–06**. Chapter 08 here adds AI steps to those pipelines, assuming they
  exist.
- **Building products *with* AI features** (LLM APIs inside your product, RAG, embeddings) is a
  different subject from building products *using* AI tools — it belongs to the case studies
  (Stage 14) and is out of scope here.

## Running example

The stage keeps working on **Invoicely** — the invoicing SaaS built and hardened across Stages
3–9 — but the artifact under construction shifts: alongside the product code, we build the
*AI-engineering layer* of the repository. A `CLAUDE.md` and `AGENTS.md` that encode Invoicely's
conventions, a permissions and hooks configuration that lets an agent run tests but not touch
production, a documented context map that gets an agent productive in one session, a prompt library
for recurring tasks (migrations, endpoints, review passes), subagent definitions for parallelizable
work, an AI review step in the pull-request pipeline, and a written team workflow for shipping a
feature with an agent from issue to merged PR. By the end of the stage, Invoicely is not just a
production system — it is a production system a new engineer *or a new agent* can contribute to
safely on day one.

## Learning outcome

You can configure Claude Code, Codex, or Cursor for a production repository so that generated code
lands inside your conventions instead of beside them; engineer context so an agent reasons from
your system's actual constraints rather than plausible defaults; write task prompts that function
as specifications with acceptance criteria; decide when parallel or specialized agents pay for
their coordination cost and when they don't; run a review process that catches the failure modes
specific to AI-generated code; debug with an agent while keeping hypothesis discipline; and
assemble all of it into a team workflow where AI speed survives contact with production standards
— so that "AI-first" describes your engineering system, not just your typing speed.

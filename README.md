# AI-First Software Engineering Handbook

A production-focused engineering handbook for the AI era.

AI has made writing code cheap. The bottleneck is no longer typing — it is
engineering judgment: architecture, trade-offs, reviewing AI output, and
shipping systems that survive real users. This handbook teaches that judgment.

> **New here and want to learn from it?** Read **[START-HERE.md](START-HERE.md)** —
> a reading guide covering what to read, in what order, and how to actually
> learn from it (not just skim it). Stages 1–10 are ready now.

## What This Is

- An engineering handbook, not a tutorial and not documentation.
- A progressive curriculum: mindset → architecture → building → shipping → scaling.
- AI-first: AI is treated as a teammate that accelerates implementation.
  The engineer owns every decision.

## What This Is Not

- Not a syntax course. You should already know basic programming.
- Not framework marketing. Recommendations always include when *not* to use something.
- Not toy examples. Every example resembles software a real company would run.

## Who It Is For

Junior and mid-level engineers, SaaS founders, indie hackers, and any
developer transitioning to AI-first workflows who wants to build production
systems — not just generate code.

## How to Read It

Stages build on each other. Read them in order the first time; return to any
chapter as a reference afterwards. Every chapter follows the same structure:
mental model first, then a real production example, then trade-offs,
mistakes (human and AI), best practices, a decision tree, checklists, and
exercises that resemble real engineering work.

You can read the Markdown files directly, or serve the handbook as a local
website with sidebar navigation, full-text search, and dark mode:

```bash
./web/serve.sh        # requires uv — then open http://127.0.0.1:8000
```

## Curriculum

| Stage | Topic | Status |
|---|---|---|
| 1 | [Engineering Mindset](handbook/stage-01-engineering-mindset/README.md) | Complete |
| 2 | [Software Architecture](handbook/stage-02-software-architecture/README.md) | Complete |
| 3 | [Backend Engineering](handbook/stage-03-backend-engineering/README.md) | Complete |
| 4 | [Frontend Engineering](handbook/stage-04-frontend-engineering/README.md) | Complete |
| 5 | [Mobile Engineering](handbook/stage-05-mobile-engineering/README.md) | Complete |
| 6 | [Database Engineering](handbook/stage-06-database-engineering/README.md) | Complete |
| 7 | [DevOps](handbook/stage-07-devops/README.md) | Complete |
| 8 | [Testing](handbook/stage-08-testing/README.md) | Complete |
| 9 | [Security](handbook/stage-09-security/README.md) | Complete |
| 10 | [AI Engineering](handbook/stage-10-ai-engineering/README.md) | Complete |
| 11 | [System Design](handbook/stage-11-system-design/README.md) | Complete |
| 12 | [SaaS Engineering](handbook/stage-12-saas-engineering/README.md) | Complete |
| 13 | Engineering Leadership | Planned |
| 14 | Case Studies | Planned |

The full topic list per stage lives in [meta/02-curriculum.md](meta/02-curriculum.md).

## Engineering Assets

Chapters teach judgment; these compress it for daily use:

- **[Templates](templates/README.md)** — ADR, pull request, project brief,
  and a CLAUDE.md starter for your own AI-first repositories.
- **[Checklists](checklists/README.md)** — code review (including a
  dedicated AI-generated-code section) and production readiness.
- **[Playbooks](playbooks/README.md)** — end-to-end processes, starting
  with [Starting an AI-First Project](playbooks/starting-an-ai-first-project.md).

## Repository Structure

```
meta/        Project constitution, vision, and curriculum — the rules everything follows
prompts/     Reusable prompts for generating and reviewing chapters
handbook/    The content, one folder per curriculum stage
templates/   Documents to copy and fill in: ADR, PR, project brief, CLAUDE.md starter
checklists/  Verification lists for moments of action: code review, production readiness
playbooks/   Step-by-step processes that tie the templates and checklists together
web/         MkDocs config for reading the handbook as a local website
examples/    (planned) Invoicely reference implementation — the app the chapters build
starter-kits/ (planned) Clone-and-ship SaaS templates extracted from the reference app
```

`meta/00-CONSTITUTION.md` is the highest authority. When documents conflict:
Constitution > Vision > Curriculum.

## Contributing

Read `meta/00-CONSTITUTION.md` and `CLAUDE.md` before writing anything.
Chapters that skip required sections or use toy examples are rejected by
design — see `prompts/01-review-chapter.md` for the review bar.

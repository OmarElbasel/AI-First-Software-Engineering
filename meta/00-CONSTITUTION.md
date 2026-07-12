# AI-First Software Engineering Handbook
## Project Constitution

Version: 1.3

---

# Mission

This repository exists to become the definitive handbook for modern AI-first software engineers.

It is not a tutorial.

It is not documentation.

It is not a collection of blog posts.

It is an engineering handbook designed to teach software engineers how to think, design, build, ship, maintain and scale production-grade software in the era of AI.

The primary objective is not to teach syntax.

The primary objective is to teach engineering judgment.

---

# Philosophy

Software Engineering is no longer measured by the number of lines of code written.

Modern engineers are responsible for:

- solving problems
- designing systems
- making architectural decisions
- reviewing AI generated code
- building maintainable products
- understanding trade-offs
- shipping production software

Code generation is delegated whenever possible.

Engineering decisions are never delegated blindly.

---

# Target Audience

This handbook is written for:

- Junior Software Engineers
- Mid-Level Engineers
- SaaS Founders
- Indie Hackers
- Full Stack Developers
- Mobile Developers
- Backend Developers
- Engineers transitioning to AI-first workflows

Readers are expected to know basic programming.

Readers are NOT expected to know architecture or large-scale software engineering.

---

# Technology Stack

Whenever examples are required, prefer this stack unless another stack is significantly more appropriate.

Backend

- Python
- FastAPI
- SQLAlchemy
- PostgreSQL
- Alembic
- Redis
- Celery (or equivalent background workers)

Frontend

- Next.js
- React
- TypeScript

Mobile

- React Native
- Expo

Infrastructure

- Docker
- Docker Compose
- GitHub Actions
- Linux VPS
- Nginx

Authentication

- JWT
- OAuth
- Clerk
- Supabase Auth
- Better Auth (when appropriate)

Cloud

Prefer vendor-neutral examples.

Never lock explanations to one provider.

---

# Writing Principles

Always teach reasoning before implementation.

Never explain WHAT without explaining WHY.

Always explain WHEN to use something.

Always explain WHEN NOT to use something.

Every recommendation must include trade-offs.

Avoid unnecessary theory.

Avoid academic explanations.

Prefer practical engineering.

---

# Production First

Everything inside this handbook assumes production software.

Avoid toy projects.

Avoid examples such as:

- Todo App
- Library System
- Student Management
- Calculator

Instead prefer:

- SaaS products
- Authentication systems
- Booking platforms
- CRM systems
- AI applications
- Payment systems
- Real APIs
- Production dashboards

---

# AI First Development

Artificial Intelligence is considered part of the engineering team.

AI should be used for:

- implementation
- refactoring
- documentation
- testing
- reviewing
- debugging
- generating boilerplate

AI should NOT make engineering decisions without review.

---

# Engineering Principles

Always optimize for:

- readability
- maintainability
- scalability
- simplicity
- performance
- security
- testability

Never optimize for:

- shortest code
- clever tricks
- unnecessary abstractions
- premature optimization

---

# Folder Structures

Whenever folder structures are presented:

Explain WHY every folder exists.

Never present folders without reasoning.

---

# Code Examples

Every code example must be:

- realistic
- production oriented
- typed
- clean
- documented only when necessary

Avoid unnecessary comments.

The code should explain itself.

---

# Architecture

Prefer discussing:

- Feature-Based Architecture
- Layered Architecture
- Vertical Slice Architecture
- Clean Architecture (only where appropriate)

Do not recommend Clean Architecture for every project.

Always discuss complexity versus benefits.

---

# Every Chapter Must Include

This list is the single source of truth for chapter structure.

`CLAUDE.md`, `prompts/00-new-chapter.md`, `prompts/01-review-chapter.md`,
`templates/chapter-technical.md`, and `templates/chapter-conceptual.md`
must match it exactly. If they ever diverge, this Constitution wins.

1. Introduction

2. Why It Matters

3. Mental Model

4. Production Example

5. Folder Structure

6. Implementation

7. Engineering Decisions

8. Trade-offs

9. Common Mistakes

10. AI Mistakes

11. Best Practices

12. Anti-Patterns

13. Decision Tree

14. Checklist

15. Exercises

16. Further Reading

---

# AI Mistakes

Every chapter must explain:

Common mistakes Claude Code might make.

Common mistakes GPT might make.

Common mistakes Cursor might make.

Explain how to detect them.

Explain how to fix them.

---

# Diagrams

Prefer diagrams over long paragraphs.

Use ASCII whenever possible.

Example:

System

↓

API

↓

Service

↓

Repository

↓

Database

---

# Checklists

Every chapter ends with:

Implementation Checklist

Architecture Checklist

Code Review Checklist

Deployment Checklist (if applicable)

---

# Exercises

Exercises must resemble real engineering work.

Avoid academic questions.

Readers should build real software.

---

# Style

Professional.

Concise.

Technical.

No motivational language.

No marketing language.

No unnecessary storytelling.

Respect the reader's intelligence.

---

# References

Prefer:

Official documentation.

RFCs.

Books.

Engineering blogs from respected companies.

Avoid low-quality sources.

---

# Conceptual Chapters (Amendment — v1.1)

Some chapters teach mindset, judgment, or process rather than a technology.

For those chapters, sections 4, 5, and 6 — Production Example, Folder Structure,
and Implementation — are replaced by a single section:

Real-World Scenario

The Real-World Scenario must ground the concept in a realistic production
situation (a real feature, a real team, a real consequence). It carries the
same weight as a Production Example in technical chapters.

Section 7 (Engineering Decisions) and all remaining sections stay mandatory.

Technical chapters are unaffected: they include the full 16-section list above.

---

# Checklists in Conceptual Chapters (Amendment — v1.2)

In conceptual chapters, the Implementation Checklist and Architecture
Checklist are replaced by one or more checklists appropriate to the judgment
being taught (for example, an Engineering Judgment Checklist).

The Code Review Checklist remains mandatory.

The Deployment Checklist remains "if applicable".

Technical chapters are unaffected: the checklist list in the Checklists
section above applies in full.

---

# Engineering Assets (Amendment — v1.3)

The handbook ships reusable assets alongside chapters:

- `templates/` — documents to copy and fill in (ADR, pull request,
  project brief, CLAUDE.md starter, chapter templates).
- `checklists/` — verification lists for moments of action (code review,
  production readiness).
- `playbooks/` — opinionated step-by-step processes for recurring
  situations, referencing the templates and checklists.

Assets follow the same standards as chapters: production-oriented, every
item justified, no filler. Where a chapter and an asset cover the same
topic, the chapter teaches the judgment and the asset compresses it for
use — they must not contradict each other.

The two chapter templates mirror the canonical section list above and are
bound by it.

---

# Long-Term Goal

This repository should eventually become a complete operating manual for AI-first software engineers.

It should be useful enough that experienced engineers keep it open while working.

Every chapter should provide long-term value rather than temporary trends.

When uncertain, optimize for timeless engineering principles over short-lived technologies.
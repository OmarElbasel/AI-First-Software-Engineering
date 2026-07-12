# Handbook Skeleton + Chapter 01 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the repository skeleton (README, Constitution v1.1, CLAUDE.md sync, stage-01 folder) and produce Chapter 01 through the full outline → write → adversarial review pipeline.

**Architecture:** Plain Markdown handbook, stage folders under `handbook/`, each stage with a README as its table of contents. Content quality is enforced by an adversarial review pass using `prompts/01-review-chapter.md`.

**Tech Stack:** Markdown, git. No build tooling.

## Global Constraints

- Precedence when documents conflict: Constitution > Vision > Curriculum.
- Style: professional, concise, technical. No motivational or marketing language. No filler.
- Examples must be production-realistic SaaS scenarios; never todo apps, calculators, or student systems.
- Every recommendation must state why, when, when not, and trade-offs.
- Preferred stack in examples: FastAPI, PostgreSQL, Next.js/TypeScript, React Native, Docker, GitHub Actions.
- ASCII diagrams preferred.
- All commits end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- Verification for Markdown = required headings present + relative links resolve. There is no test suite.

---

### Task 1: Root README (front door + curriculum TOC)

**Files:**
- Create: `README.md`

**Interfaces:**
- Produces: links to `handbook/stage-01-engineering-mindset/README.md` (created in Task 3). That link is written now and verified at the end of Task 3.

- [ ] **Step 1: Write `README.md` with exactly this content**

```markdown
# AI-First Software Engineering Handbook

A production-focused engineering handbook for the AI era.

AI has made writing code cheap. The bottleneck is no longer typing — it is
engineering judgment: architecture, trade-offs, reviewing AI output, and
shipping systems that survive real users. This handbook teaches that judgment.

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

## Curriculum

| Stage | Topic | Status |
|---|---|---|
| 1 | [Engineering Mindset](handbook/stage-01-engineering-mindset/README.md) | In progress |
| 2 | Software Architecture | Planned |
| 3 | Backend Engineering | Planned |
| 4 | Frontend Engineering | Planned |
| 5 | Mobile Engineering | Planned |
| 6 | Database Engineering | Planned |
| 7 | DevOps | Planned |
| 8 | Testing | Planned |
| 9 | Security | Planned |
| 10 | AI Engineering | Planned |
| 11 | System Design | Planned |
| 12 | SaaS Engineering | Planned |
| 13 | Engineering Leadership | Planned |
| 14 | Case Studies | Planned |

The full topic list per stage lives in [meta/02-curriculum.md](meta/02-curriculum.md).

## Repository Structure

```
meta/       Project constitution, vision, and curriculum — the rules everything follows
prompts/    Reusable prompts for generating and reviewing chapters
handbook/   The content, one folder per curriculum stage
docs/       Design specs and implementation plans for the repo itself
```

`meta/00-CONSTITUTION.md` is the highest authority. When documents conflict:
Constitution > Vision > Curriculum.

## Contributing

Read `meta/00-CONSTITUTION.md` and `CLAUDE.md` before writing anything.
Chapters that skip required sections or use toy examples are rejected by
design — see `prompts/01-review-chapter.md` for the review bar.
```

- [ ] **Step 2: Verify links resolve (stage-01 link is allowed to fail until Task 3)**

Run: `test -f meta/02-curriculum.md && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Add root README with curriculum TOC"
```

---

### Task 2: Canonical section list — Constitution v1.1 + full 4-file sync — DONE

> **Status: already executed** (pre-plan reconciliation). Superseded the
> original "add Decision Tree to CLAUDE.md" step, which was too narrow — the
> section list was actually inconsistent across **four** files, not two.

**What the audit found (4 divergent copies of "Every Chapter Must Include"):**
- `meta/00-CONSTITUTION.md`: had "Step-by-step explanation", no separate "Engineering Decisions".
- `CLAUDE.md`: had "Engineering Decisions", missing the build/Implementation section AND "Decision Tree".
- `prompts/00-new-chapter.md`: had both "Implementation" and "Engineering Decisions" (16), plus name drift ("Why It Exists", "Real Production Example").
- `prompts/01-review-chapter.md`: Completeness list missing "Why It Matters" and "Implementation".

**Decisions made (owner-approved):**
- "Engineering Decisions" is its own mandatory section (not merged into Implementation).
- The build walkthrough is named **Implementation** (replaces "Step-by-step explanation").

**Canonical 16-section list (single source of truth = Constitution):**
Introduction · Why It Matters · Mental Model · Production Example · Folder
Structure · Implementation · Engineering Decisions · Trade-offs · Common
Mistakes · AI Mistakes · Best Practices · Anti-Patterns · Decision Tree ·
Checklist · Exercises · Further Reading.
Conceptual chapters replace Production Example + Folder Structure +
Implementation with a single **Real-World Scenario**.

**Files changed:**
- `meta/00-CONSTITUTION.md`: v1.0 → v1.1; canonical list + source-of-truth note; conceptual-chapter amendment before "# Long-Term Goal".
- `CLAUDE.md`, `prompts/00-new-chapter.md`, `prompts/01-review-chapter.md`: all synced to the canonical list + amendment note.

- [x] **Step 1: Verify all four files agree**

Run:
```bash
grep -c "Real-World Scenario" meta/00-CONSTITUTION.md
grep -rl "Engineering Decisions" CLAUDE.md prompts/00-new-chapter.md prompts/01-review-chapter.md
```
Expected: Constitution matches ≥1; all three other files listed.

- [ ] **Step 2: Commit**

```bash
git add meta/00-CONSTITUTION.md CLAUDE.md prompts/00-new-chapter.md prompts/01-review-chapter.md
git commit -m "Reconcile chapter section list to a single source of truth (Constitution v1.1)"
```

---

### Task 3: Stage 1 folder + stage README

**Files:**
- Create: `handbook/stage-01-engineering-mindset/README.md`

**Interfaces:**
- Consumes: root README's link `handbook/stage-01-engineering-mindset/README.md` (Task 1).
- Produces: the chapter file name `01-what-is-software-engineering.md` that Tasks 4–6 write and review.

- [ ] **Step 1: Write `handbook/stage-01-engineering-mindset/README.md` with exactly this content**

```markdown
# Stage 1 — Engineering Mindset

Learn how software engineers think before learning any technology.

Every later stage assumes the mental models built here. Skipping this stage
is how developers end up knowing frameworks but shipping unmaintainable
systems.

## Why this stage exists

AI can generate a working feature in minutes. It cannot decide whether the
feature should exist, how it should be structured, or what it will cost to
maintain. Those decisions are the engineer's job — and they are learnable.

## Chapters

| # | Chapter | Status |
|---|---|---|
| 01 | [What is Software Engineering?](01-what-is-software-engineering.md) | In progress |
| 02 | Product Thinking | Planned |
| 03 | AI-First Development | Planned |
| 04 | Engineering Trade-offs | Planned |
| 05 | Technical Debt | Planned |
| 06 | Build vs Buy | Planned |
| 07 | Simplicity | Planned |
| 08 | Maintainability | Planned |

Chapter 01 merges the curriculum topics "What is Software Engineering?" and
"Programming vs Engineering" — the two cannot be taught separately without
repeating each other.

## Learning outcome

You stop asking "how do I build this?" as your first question and start
asking "what problem is this solving, and what will this cost over time?"
```

- [ ] **Step 2: Verify the root README link now resolves**

Run: `test -f handbook/stage-01-engineering-mindset/README.md && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add handbook/
git commit -m "Add Stage 1 folder and stage README"
```

---

### Task 4: Chapter 01 outline (checkpoint: owner approval)

**Files:**
- None written. The outline below is presented to the owner for approval before Task 5 begins.

**Interfaces:**
- Produces: the approved section outline Task 5 must follow exactly.

- [ ] **Step 1: Present this outline to the owner and get approval**

Chapter: `handbook/stage-01-engineering-mindset/01-what-is-software-engineering.md`
Type: conceptual chapter (Constitution v1.1 section list applies).

```
# What is Software Engineering?

1. Introduction
   Programming is writing code. Engineering is everything that makes code
   worth running: deciding what to build, structuring it, keeping it alive.

2. Why This Topic Matters
   AI collapsed the cost of code. Judgment is the remaining bottleneck and
   the entire basis of an engineer's value in 2026.

3. Mental Model
   Programming ⊂ Engineering. Engineering = decisions under constraints,
   over time, with other people. ASCII diagram: the lifecycle a feature
   passes through (problem → design → build → review → ship → maintain),
   showing that "build" is one box out of six.

4. Real-World Scenario
   "Invoicely", a small B2B invoicing SaaS (FastAPI + PostgreSQL + Next.js),
   adds subscription billing. Two developers, same task:
   - Developer A (programmer mode): opens the editor, prompts the AI,
     ships in 3 days. Happy path only.
   - Developer B (engineer mode): spends day 1 on questions — proration?
     failed payments? webhook retries? idempotency? plan changes mid-cycle?
     Ships in 8 days.
   Six months later: A's version has produced double-charges, support
   tickets, and a rewrite. B's version absorbed three pricing changes
   without incident. Concrete cost comparison table.

5. Trade-offs
   Engineering rigor is not free. When programmer mode is correct:
   prototypes, spikes, throwaway scripts, validating an idea before it
   deserves engineering. When it is malpractice: anything touching money,
   auth, or user data.

6. Common Mistakes
   Jumping to implementation, equating "works on my machine" with done,
   treating requirements as fixed, measuring productivity in lines of code.

7. AI Mistakes
   - Claude Code: confidently produces a complete, plausible architecture
     for an under-specified problem instead of asking what the constraints are.
   - GPT: happy-path implementations; error handling exists but doesn't
     match real failure modes (e.g., catches exceptions and logs them away).
   - Cursor: local-file myopia — edits the file in front of it into
     inconsistency with the rest of the system.
   For each: how to detect it, how to fix it (review prompts included).

8. Best Practices
   Write the problem before the solution. Define "done" including failure
   modes. Review AI output as you would a junior's PR. Ask "what breaks in
   six months?"

9. Anti-Patterns
   Resume-driven architecture, "the AI wrote it so it must be fine",
   rewriting instead of understanding, cargo-cult patterns.

10. Decision Tree
    "Should I engineer this or just build it?" — branches on: touches
    money/auth/data? expected lifetime? who maintains it? blast radius?

11. Checklist
    Engineering Judgment Checklist (before starting any feature) +
    Code Review Checklist (for AI-generated code).

12. Exercises
    Real work, not quizzes: (1) take a one-line feature request and produce
    the questions an engineer would ask; (2) get an AI to implement a small
    billing endpoint, then find the three classes of production bug in it;
    (3) write a six-month maintenance forecast for a feature you shipped.

13. Further Reading
    Curated, high-quality only (books + respected engineering blogs).
```

**CHECKPOINT: Do not start Task 5 until the owner approves this outline.**

---

### Task 5: Write Chapter 01

**Files:**
- Create: `handbook/stage-01-engineering-mindset/01-what-is-software-engineering.md`

**Interfaces:**
- Consumes: the approved outline from Task 4 — section names and order are fixed.
- Produces: the chapter file Task 6 reviews.

- [ ] **Step 1: Write the full chapter following the approved outline**

Rules for the writer (in addition to Global Constraints):
- Every section from the outline appears as a `##` heading, same order.
- The Invoicely scenario uses the preferred stack and stays consistent
  across the whole chapter (same product, same numbers).
- The lifecycle diagram is ASCII inside a fenced code block.
- The Decision Tree is ASCII, actually branching, not a bullet list.
- Checklists use `- [ ]` items so readers can copy them.
- Exercises produce artifacts (a questions doc, a bug report, a forecast),
  never "explain in your own words".
- Further Reading: 4–6 entries max, each with one line on why it earns
  its place. No low-quality sources, no link dumps.
- No section under 3 sentences except Further Reading. No section is
  padding — if there is nothing non-obvious to say, say less.

- [ ] **Step 2: Verify all required sections are present**

Run:
```bash
for h in "Introduction" "Why This Topic Matters" "Mental Model" "Real-World Scenario" "Trade-offs" "Common Mistakes" "AI Mistakes" "Best Practices" "Anti-Patterns" "Decision Tree" "Checklist" "Exercises" "Further Reading"; do
  grep -q "^## .*$h" handbook/stage-01-engineering-mindset/01-what-is-software-engineering.md || echo "MISSING: $h"
done; echo done
```
Expected: `done` with no `MISSING:` lines.

- [ ] **Step 3: Commit**

```bash
git add handbook/stage-01-engineering-mindset/01-what-is-software-engineering.md
git commit -m "Add Chapter 01: What is Software Engineering? (draft)"
```

---

### Task 6: Adversarial review + improve until Approved

**Files:**
- Modify: `handbook/stage-01-engineering-mindset/01-what-is-software-engineering.md`

**Interfaces:**
- Consumes: the chapter from Task 5 and the review procedure in `prompts/01-review-chapter.md`.

- [ ] **Step 1: Run the adversarial review**

Apply `prompts/01-review-chapter.md` to the chapter **as a fresh reviewer,
not as the author** (dispatch a subagent for this — the author reviewing
their own work is exactly what the prompt forbids). The review must return:
score /10, strengths, weaknesses, missing sections, technical corrections,
suggested improvements, and a verdict.

- [ ] **Step 2: Fix every weakness the review found**

Apply fixes directly to the chapter file. Do not argue with the review
except where it is factually wrong — and note any rejected findings with
reasons.

- [ ] **Step 3: Re-run the review**

Repeat Step 1. Loop Steps 1–3 until the verdict is ✅ Approved.
Maximum 3 loops; if not Approved after 3, stop and escalate to the owner
with the remaining findings.

- [ ] **Step 4: Update statuses**

In `handbook/stage-01-engineering-mindset/README.md`, change Chapter 01's
status from `In progress` to `Done`.

- [ ] **Step 5: Commit**

```bash
git add handbook/stage-01-engineering-mindset/
git commit -m "Chapter 01 passes adversarial review; mark done"
```

---

## Plan Self-Review Notes

- Spec coverage: README (Task 1), Constitution v1.1 + CLAUDE.md sync
  (Task 2), stage-01 folder (Task 3), Chapter 01 pipeline outline → approval
  → write → review → improve (Tasks 4–6). Git init + spec commit already done
  before this plan. Out-of-scope items in the spec stay out.
- Amendment refinement vs spec: the spec said the Real-World Scenario
  replaces "Folder Structure" + "Implementation"; this plan also folds in
  "Production Example" because a conceptual chapter with both a Production
  Example and a Real-World Scenario would duplicate content. Flag to owner
  at outline checkpoint (Task 4) — it is visible in the outline.
- No placeholders: all file contents are verbatim in Tasks 1–3; Task 5 is
  content authorship guided by the approved outline plus explicit writing
  rules, which is the correct granularity for prose.

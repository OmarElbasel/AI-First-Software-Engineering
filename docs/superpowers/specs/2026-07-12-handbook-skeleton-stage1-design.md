# Design: Handbook Skeleton + Stage 1 Content Pipeline

Date: 2026-07-12
Status: Approved by project owner

---

## Goal

Set up the repository skeleton for the AI-First Software Engineering Handbook and
establish the repeatable pipeline used to produce Stage 1 (Engineering Mindset)
chapters, starting with Chapter 01.

## Decisions Made

| Decision | Choice | Reasoning |
|---|---|---|
| First content | Stage 1, one chapter at a time | The first chapter becomes the quality template for all later chapters. Matches the curriculum's learning order. |
| Reading format | Plain Markdown on GitHub | Zero tooling, simplest option, a docs site can be added later without restructuring. |
| Repo layout | Stage folders under `handbook/` | Mirrors the curriculum exactly, keeps reading order obvious, adding chapters never renumbers other stages. |
| Chapter 01 scope | Merge "What is Software Engineering?" + "Programming vs Engineering" | The topics overlap almost completely; one strong chapter beats two thin ones. |
| Constitution amendment | Conceptual chapters swap "Folder Structure" + "Implementation" for "Real-World Scenario" | Prevents filler sections in mindset chapters, which the Constitution itself forbids. Technical chapters keep the full required section list. |

## Repository Layout

```
AI-First-Software-Engineering/
├─ README.md                          ← front door + full curriculum TOC
├─ CLAUDE.md                          ← + missing "Decision Tree" section added
├─ AGENTS.md
├─ meta/
│  ├─ 00-CONSTITUTION.md              ← amended to v1.1 (conceptual-chapter rule)
│  ├─ 01-project-vision.md
│  └─ 02-curriculum.md
├─ prompts/
│  ├─ 00-new-chapter.md
│  └─ 01-review-chapter.md
├─ docs/superpowers/specs/            ← design docs like this one
└─ handbook/
   └─ stage-01-engineering-mindset/
      ├─ README.md                    ← stage goal + chapter list
      └─ 01-what-is-software-engineering.md   (first chapter; others follow)
```

Rules:

- Stage folders are created only when their first chapter is written. No empty
  directories.
- Every folder must be justified (Constitution requirement); the stage README
  carries that justification for its chapters.

## Stage 1 Chapter Map

Derived from the 9 curriculum topics:

```
01-what-is-software-engineering.md   (merges "What is SE?" + "Programming vs Engineering")
02-product-thinking.md
03-ai-first-development.md
04-engineering-trade-offs.md
05-technical-debt.md
06-build-vs-buy.md
07-simplicity.md
08-maintainability.md
```

## Per-Chapter Pipeline

Repeats identically for every chapter:

1. Outline (matches curriculum position and prerequisites)
2. Owner approval of outline
3. Full chapter written per the Constitution's section template
4. Review against `prompts/01-review-chapter.md` (adversarial review, scored)
5. Improve weak sections until the review verdict is "Approved"
6. Chapter committed

Only Chapter 01 is in scope for the first implementation round. Each subsequent
chapter is its own round through the same pipeline.

## Constitution Amendment (v1.1)

Add to `meta/00-CONSTITUTION.md`:

> Conceptual chapters (chapters that teach mindset, judgment, or process rather
> than a technology) replace the "Folder Structure" and "Implementation" sections
> with a single "Real-World Scenario" section that grounds the concept in a
> realistic production situation. All other sections remain mandatory.

Also sync `CLAUDE.md`'s "Every Chapter Must Include" list with the Constitution
by adding the missing "Decision Tree" item.

## Out of Scope

- Docs website / static site generator
- Stages 2–14 content (folders created when reached)
- Templates, playbooks, starter kits (added when a chapter needs them)
- GitHub remote setup / publishing (owner's call, later)

## Success Criteria

- Repo is a git repository with clean, reviewable history.
- README gives a newcomer the full picture and working links.
- Chapter 01 survives the adversarial review prompt with an "Approved" verdict.
- The chapter reads as a reference an experienced engineer would keep open —
  not a blog post.

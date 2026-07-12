<!--
TEMPLATE: Technical chapter.

Use for chapters that teach a technology or technique and contain real code.
For mindset/judgment/process chapters, use chapter-conceptual.md instead.

The section list below is canonical and mirrors meta/00-CONSTITUTION.md.
Do not add, remove, or reorder sections. If this template ever diverges from
the Constitution, the Constitution wins.

Before writing: follow prompts/00-new-chapter.md — read CLAUDE.md, AGENTS.md,
everything in meta/, and the neighboring chapters. Outline first.
-->

# Chapter Title

## Introduction

<!--
2–4 paragraphs. Define the topic in plain engineering terms and state what
the reader will be able to do after this chapter. No history lessons, no
motivational language.
-->

## Why It Matters

<!--
The cost of not knowing this. Tie it to production consequences: outages,
rewrite costs, security incidents, velocity loss. Include the AI angle —
what goes wrong when an engineer lets an assistant make this decision
unreviewed.
-->

## Mental Model

<!--
The one abstraction the reader should carry out of this chapter. Prefer an
ASCII diagram plus a short working definition they can quote. Everything
later in the chapter should hang off this model.
-->

## Production Example

<!--
One realistic system — a SaaS product, booking platform, payment flow, CRM.
Name it, give it scale (users, requests, team size), and state the concrete
problem this chapter's topic solves for it. Never a todo app. This example
carries through Folder Structure and Implementation below.
-->

## Folder Structure

<!--
The real directory layout for the production example. Explain WHY every
folder exists — a structure without reasoning is forbidden by the
Constitution.
-->

```
project/
├── ...
```

## Implementation

<!--
Production-grade code for the example: typed, realistic, minimal comments.
Prefer the handbook stack (FastAPI, PostgreSQL, SQLAlchemy, Next.js,
TypeScript, Docker) unless another is clearly more appropriate. Show the
parts where judgment lives; link or elide pure boilerplate.
-->

## Engineering Decisions

<!--
The 3–6 decisions an engineer had to make in the implementation above, with
the alternatives that were rejected and why. This section is where the
chapter earns its place — the code shows WHAT, this shows WHY.
-->

## Trade-offs

<!--
What this approach costs. Every recommendation in the chapter must have its
price stated here: complexity, performance, operational burden, lock-in.
Include when NOT to use the approach at all.
-->

## Common Mistakes

<!--
Mistakes human engineers actually make with this topic, each with: the
mistake, why it happens, the consequence, the fix. Drawn from production
reality, not hypotheticals.
-->

## AI Mistakes

<!--
Mistakes Claude Code, Codex/GPT, and Cursor make with this topic
specifically. For each: how to detect it in a diff, and how to fix or
prompt around it. This section must be topic-specific — generic "AI
hallucinates" warnings are filler.
-->

## Best Practices

<!--
Positive guidance, each item with its reason. If an item's reason is
obvious from an earlier section, cut the item — no padding.
-->

## Anti-Patterns

<!--
Named patterns to refuse in review, each with why it looks attractive and
what it costs later. Distinct from Common Mistakes: mistakes are errors,
anti-patterns are deliberate designs that seem right and are not.
-->

## Decision Tree

<!--
An ASCII decision tree the reader can apply to their own situation:
"If X → do A. If Y → do B." It should compress the whole chapter into
something usable during a design discussion.
-->

## Checklist

<!--
Per the Constitution, technical chapters end with all of these
(Deployment only if applicable). Checkboxes, one line each, actionable.
-->

### Implementation Checklist

- [ ]

### Architecture Checklist

- [ ]

### Code Review Checklist

- [ ]

### Deployment Checklist

- [ ]

## Exercises

<!--
2–4 exercises that resemble real engineering work: extend the production
example, review a flawed diff, make and defend a decision. No quiz
questions.
-->

## Further Reading

<!--
Official documentation, RFCs, books, and engineering blogs from respected
companies. Every link needs a one-line reason to read it. No low-quality
sources.
-->

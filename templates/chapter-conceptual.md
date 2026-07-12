<!--
TEMPLATE: Conceptual chapter (mindset, judgment, or process).

Per the Constitution's v1.1 amendment, sections 4–6 of the canonical list
(Production Example, Folder Structure, Implementation) are replaced by a
single Real-World Scenario. Per v1.2, the Implementation and Architecture
checklists are replaced by checklists appropriate to the judgment being
taught; the Code Review Checklist stays mandatory.

Everything else matches meta/00-CONSTITUTION.md exactly. If this template
ever diverges from the Constitution, the Constitution wins.

Before writing: follow prompts/00-new-chapter.md — read CLAUDE.md, AGENTS.md,
everything in meta/, and the neighboring chapters. Outline first.
-->

# Chapter Title

## Introduction

<!--
2–4 paragraphs. Define the concept in plain engineering terms and state the
judgment the reader will gain. No history lessons, no motivational language.
-->

## Why It Matters

<!--
The production cost of lacking this judgment: failed projects, rewrites,
burned runway, team churn. Include the AI angle — why this judgment matters
MORE now that implementation is cheap.
-->

## Mental Model

<!--
The one abstraction the reader should carry out of this chapter. Prefer an
ASCII diagram plus a short working definition they can quote.
-->

## Real-World Scenario

<!--
Replaces Production Example + Folder Structure + Implementation, and carries
the same weight. Ground the concept in a realistic production situation: a
named product with real scale, a real decision point, and real consequences.
The strongest form contrasts two engineers (or two teams) facing the same
situation and shows where the judgment diverges and what each path costs.
See handbook/stage-01-engineering-mindset/01-what-is-software-engineering.md
for the established pattern.
-->

## Engineering Decisions

<!--
The explicit decisions inside the scenario: what was chosen, what was
rejected, and why. Make the judgment visible and transferable — the reader
should be able to reapply the reasoning to their own product.
-->

## Trade-offs

<!--
The concept's price. Even good judgment has costs — time spent deciding,
opportunities declined, tension with speed. State when the usual advice
does NOT apply.
-->

## Common Mistakes

<!--
Mistakes human engineers make with this concept, each with: the mistake,
why it happens, the consequence, the fix.
-->

## AI Mistakes

<!--
How Claude Code, Codex/GPT, and Cursor fail at this concept specifically —
usually by optimizing for the stated request instead of the underlying
judgment. For each: how to detect it, how to fix or prompt around it.
Generic warnings are filler.
-->

## Best Practices

<!--
Positive guidance, each item with its reason. Cut anything already earned
by an earlier section.
-->

## Anti-Patterns

<!--
Deliberate approaches that look like good judgment and are not, each with
why it seems attractive and what it costs later.
-->

## Decision Tree

<!--
An ASCII decision tree that compresses the chapter's judgment into
something usable in a real discussion: "If X → do A. If Y → do B."
-->

## Checklist

<!--
Per the v1.2 amendment: replace Implementation/Architecture checklists with
one or more checklists fitting the judgment taught (rename the first one
below accordingly). Code Review Checklist is mandatory. Deployment only if
applicable.
-->

### Engineering Judgment Checklist

- [ ]

### Code Review Checklist

- [ ]

## Exercises

<!--
2–4 exercises resembling real engineering work: analyze a scenario, make
and defend a decision, review a plan. No quiz questions.
-->

## Further Reading

<!--
Official documentation, RFCs, books, and engineering blogs from respected
companies. Every link needs a one-line reason to read it.
-->

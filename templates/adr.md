<!--
TEMPLATE: Architecture Decision Record (ADR).

WHY: Six months from now, someone — possibly you, possibly an AI assistant
reading the repo — will ask "why is it built this way?" Without a record,
the answer is archaeology, and rejected options get re-proposed and
re-litigated. ADRs make decisions cheap to revisit and expensive to forget.

WHEN: The decision is expensive to reverse (database choice, auth strategy,
architecture style, third-party dependency you'll build around), or it will
shape code across multiple modules, or a reasonable engineer would ask why.

WHEN NOT: Trivially reversible choices. An ADR for a variable naming
convention is bureaucracy.

WHERE: Store as docs/adr/NNNN-short-title.md, numbered sequentially.
Never edit a decided ADR's Decision section — supersede it with a new one
and update the Status line.
-->

# ADR-NNNN: Short decision title

**Status:** Proposed | Accepted | Superseded by ADR-NNNN
**Date:** YYYY-MM-DD
**Deciders:** <!-- who agreed to this — a decision without owners is a suggestion -->

## Context

<!--
The situation forcing a decision, in 1–3 paragraphs: the problem, the
constraints (deadline, budget, team skills, existing systems), and what
happens if no decision is made. Facts only — save opinions for Options.
-->

## Decision Drivers

<!--
The forces that actually determine the outcome, ranked. Be honest: "team
already knows PostgreSQL" is a legitimate driver and belongs above
theoretical scalability. 3–6 items.
-->

1.
2.
3.

## Options Considered

<!--
Every seriously considered option — including the one you rejected for a
reason that later turns out wrong. Two options minimum; a one-option ADR
is a press release. Keep the trade-offs concrete: numbers, operational
cost, failure modes. If AI proposed or evaluated an option, note what was
verified rather than trusted.
-->

### Option 1: Name

- **Pros:**
- **Cons:**
- **Cost of reversal:**

### Option 2: Name

- **Pros:**
- **Cons:**
- **Cost of reversal:**

## Decision

<!--
The chosen option and the 2–3 sentences of reasoning that outweighed the
alternatives. Someone reading only this section should understand what to
build.
-->

## Consequences

<!--
What becomes easier, what becomes harder, and what new obligations exist
(operational burden, upgrade path, skills to learn). Negative consequences
you accept knowingly are the mark of an honest ADR.
-->

**Positive:**

**Negative:**

## Revisit When

<!--
The concrete trigger that should reopen this decision: a scale threshold,
a price change, a dependency's end-of-life. "Never" is a valid answer if
you mean it.
-->

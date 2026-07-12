<!--
TEMPLATE: Project brief.

WHY: AI assistants amplify whatever you give them. Given a vague goal, they
generate a plausible product you didn't ask for. A one-page brief written
BEFORE the first prompt is the cheapest architecture work you will ever do —
it turns "add billing" into a specification an assistant can actually
satisfy, and it is the reference you review the output against.

WHEN: Starting a new project, or a feature large enough that getting it
wrong costs more than a day.

WHEN NOT: Small, well-understood changes. A brief for a bugfix is theater.

Keep it to roughly one page. If it grows past two, you are writing a spec —
split the project instead.
-->

# Project Brief: Name

**Date:** YYYY-MM-DD
**Owner:** <!-- one person accountable for scope decisions -->

## Problem

<!--
The problem in the user's terms, not the solution's. "Customers abandon
signup because it requires a credit card" — not "build passwordless auth".
If you cannot state the problem without naming a technology, you haven't
found the problem yet.
-->

## Users

<!--
Who has this problem and how badly. One or two concrete user types with
their current workaround. "Everyone" means you don't know.
-->

## Success Criteria

<!--
Measurable outcomes that mean "done and working" — signup conversion,
processing time, support ticket volume. These are what you test against
and what you tell the AI "done" means. 2–4 items.
-->

-

## Scope

<!--
What ships in the first version. Small enough that a slipped estimate is
survivable.
-->

### Non-Goals

<!--
The most valuable section. Explicitly list plausible features you are NOT
building and why. This is your defense against scope creep — both your own
and the AI's habit of "helpfully" adding admin panels, analytics, and
settings pages nobody asked for.
-->

-

## Constraints

<!--
The real limits: deadline, budget, team size and skills, existing systems
to integrate with, compliance requirements. Constraints are inputs to
architecture, not obstacles to it.
-->

-

## Stack

<!--
Chosen stack and one line on why — usually "team knows it" is the honest
and correct reason. Decisions that are expensive to reverse deserve an ADR
(templates/adr.md) instead of a line here.
-->

## Risks

<!--
The 2–3 things most likely to sink this, each with the cheapest possible
early test. "Stripe Connect may not support our payout model — spike it
first week."
-->

-

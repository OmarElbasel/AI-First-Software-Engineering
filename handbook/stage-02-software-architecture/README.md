# Stage 2 — Software Architecture

Learn how to structure software *before* writing the bulk of it.

Stage 1 taught how engineers think; this stage turns that judgment into
structure. Architecture is the set of decisions that are expensive to reverse
(Chapter 04 of Stage 1's one-way doors) — how code is organized, how systems
are split, and how the pieces depend on each other. Get it roughly right and
change stays cheap; get it wrong and every feature fights the structure.

## Why this stage exists

AI can generate a working endpoint in seconds — in whatever shape its
training data suggests, which is usually everything crammed into one route
handler. Architecture is what the AI cannot decide for you: where code
belongs, how strongly to separate concerns, when to split a system, and what
each of those choices costs. A codebase without deliberate architecture
becomes one an assistant makes *worse* faster, because it amplifies whatever
structure it finds.

## Chapters

| # | Chapter | Status |
|---|---------|--------|
| 01 | [Layered Architecture](01-layered-architecture.md) | Done |
| 02 | [Feature-Based & Vertical Slice Architecture](02-feature-based-and-vertical-slice.md) | Done |
| 03 | [Clean Architecture](03-clean-architecture.md) | Done |
| 04 | [Monolith, Modular Monolith & Microservices](04-monolith-modular-monolith-microservices.md) | Done |
| 05 | [Service Layer & Repository Pattern](05-service-layer-and-repository-pattern.md) | Done |
| 06 | [Dependency Injection](06-dependency-injection.md) | Done |
| 07 | [Event-Driven Architecture](07-event-driven-architecture.md) | Done |

These seven chapters cover the eleven curriculum topics for this stage. Some
are deliberately taught together, because they are the same decision seen
from different angles and cannot be separated without repetition:

- **Feature-Based and Vertical Slice** (Ch 02) are two names for organizing by
  feature rather than by technical layer; they share one mental model.
- **Monolith, Modular Monolith, and Microservices** (Ch 04) are points on a
  single spectrum of deployment topology — teaching one without the others
  produces cargo-cult conclusions.
- **Service Layer and Repository Pattern** (Ch 05) are the two building-block
  patterns for separating business logic from data access; they are almost
  always introduced together.

## Running example

This stage continues with **Invoicely**, the invoicing SaaS from Stage 1
(FastAPI, PostgreSQL, SQLAlchemy, Next.js). Now we look at its actual code
structure — the same product, seen from the architecture layer.

## Learning outcome

You can choose and justify a structure for a system before building it, put
each piece of code where it belongs, and recognize when an architecture is
buying you something versus costing you for nothing.

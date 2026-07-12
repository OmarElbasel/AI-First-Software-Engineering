# Stage 3 — Backend Engineering

Build production-ready backend services.

Stage 1 taught how to think; Stage 2 taught how to structure. This stage
builds — the concrete, production concerns of a real backend: HTTP APIs,
persistence and migrations, authentication and authorization, error handling,
background work, caching, observability, and the integrations every SaaS needs.

## Why this stage exists

An assistant can generate an endpoint in seconds, but the parts that make a
backend *production-ready* — validation that can't be bypassed, migrations that
don't lose data, auth that resists real attacks, jobs that survive redelivery,
errors that are diagnosable at 2 AM — are exactly the parts it skips by default.
This stage is about building those parts deliberately, on the architecture from
Stage 2, with the judgment from Stage 1.

## Chapters

| # | Chapter | Status |
|---|---------|--------|
| 01 | [Building APIs with FastAPI](01-building-apis-with-fastapi.md) | Done |
| 02 | Data Persistence: SQLAlchemy & Alembic | Planned |
| 03 | Authentication | Planned |
| 04 | Authorization | Planned |
| 05 | Error Handling & API Versioning | Planned |
| 06 | Background Jobs | Planned |
| 07 | Caching | Planned |
| 08 | Logging & Observability | Planned |
| 09 | File Storage & Email | Planned |

These nine chapters cover the fourteen curriculum topics for this stage.
Related topics are taught together where they are one concern seen from two
sides: FastAPI and Validation (Ch 01), SQLAlchemy and Alembic (Ch 02), Error
Handling and API Versioning (Ch 05, both about the API contract's robustness
over time), and File Storage and Email (Ch 09, both external-service
integrations).

## Boundaries with later stages

This stage teaches how to *build* these concerns into a backend. The deeper,
specialist treatments live in their own stages, and this stage defers to them:

- **Database internals** — data modeling, indexing, transactions, and query
  optimization — belong to **Stage 6 (Database Engineering)**. Chapter 02 here
  covers persistence and migrations as an application concern, not database
  design.
- **Security hardening** — the OWASP Top 10, injection, XSS, CSRF, rate
  limiting, and threat modeling — belongs to **Stage 9 (Security)**. Chapters 03
  and 04 here cover building authentication and authorization *correctly*; Stage
  9 covers defending them against attack.
- **Test strategy** belongs to **Stage 8 (Testing)**; **deployment** to **Stage
  7 (DevOps)**. Both appear here in passing where a chapter needs them.

## Running example

The stage builds the backend of **Invoicely**, the invoicing SaaS carried
through Stages 1 and 2 — now implemented, endpoint by endpoint and concern by
concern, in FastAPI, PostgreSQL, SQLAlchemy, and the rest of the handbook stack.

## Learning outcome

You can build a backend service that is correct under real conditions — bad
input, partial failure, duplicate delivery, concurrent access, and attack — not
just one that passes a happy-path demo.

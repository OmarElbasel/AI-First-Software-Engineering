# Stage 6 — Database Engineering

Design, index, query, and evolve a production database that stays correct and fast as it
grows.

Stage 3 used PostgreSQL through SQLAlchemy and Alembic without dwelling on the database
itself; this stage is the depth that chapter deferred. The focus, as always, is
engineering judgment: how to model a domain so invalid data can't be stored, how to index
and query so the database stays fast at scale, how to keep data correct under concurrent
load, and how to change a live schema without downtime or data loss.

## Why this stage exists

The database is the least reversible and highest-stakes part of a system — code is
rewritten routinely, but data outlives it and a bad schema calcifies. It's also where AI
assistants are most confidently wrong in ways that pass every demo: schemas with no
constraints, money as float, N+1 queries, missing indexes (and index-everything), read-
modify-write code that corrupts under concurrency, and migrations that lock a table or
drop data against a live database. Each is invisible on the small dev dataset and an
incident on the production one. The judgment this stage teaches is what separates a
database that survives real users from one that quietly rots.

## Chapters

| # | Chapter | Status |
|---|---------|--------|
| 01 | [Relational Databases & Data Modeling](01-relational-databases-and-data-modeling.md) | Done |
| 02 | [Schema Design & Normalization](02-schema-design-and-normalization.md) | Done |
| 03 | [Indexing](03-indexing.md) | Done |
| 04 | [Transactions & Concurrency Control](04-transactions-and-concurrency-control.md) | Done |
| 05 | [Query Optimization](05-query-optimization.md) | Done |
| 06 | [Migrations & Schema Evolution](06-migrations-and-schema-evolution.md) | Done |

These six chapters cover the seven curriculum topics for this stage. Relational
Databases and Data Modeling are taught together (Ch 01, since the relational guarantees
and the act of modeling onto them are one idea); Database Design is the normalization
chapter (Ch 02). Indexing (Ch 03) and Query Optimization (Ch 05) are the two halves of
performance — both driven by reading the query plan.

## Boundaries with other stages

- **The ORM/tooling** (SQLAlchemy, Alembic) is introduced in **Stage 3, Chapter 02**;
  this stage is the database depth behind it.
- **Caching** as a read-performance tool is **Stage 3, Chapter 07**; this stage points to
  it as the thing to reach for before denormalizing.
- **Deployment/CI-CD** of migrations is **Stage 7 (DevOps)**; Chapter 06 designs the
  migrations, Stage 7 runs them in the pipeline.
- **Testing** database code is **Stage 8**; concurrency and migrations are tested there.
- **Security** (SQL injection, least-privilege DB access) is **Stage 9**.
- **Scaling** (replicas, sharding, partitioning at scale) is **Stage 11 (System Design)**;
  this stage fixes the query before scaling the hardware.

## Running example

The stage deepens **Invoicely's** PostgreSQL schema — modeling customers, invoices, line
items, payments, and tags with correct relationships and constraints; indexing the real
query patterns; keeping invoice numbering and payments correct under concurrency;
eliminating the N+1 in the invoice list; and evolving the schema (splitting a name column,
adding a required field) with zero-downtime migrations — so the database under the Stage 3
backend is production-grade.

## Learning outcome

You can model a domain into a schema that makes invalid states unstorable, normalize by
default and denormalize only by measurement, index and optimize queries from real query
plans (killing N+1 and avoiding both under- and over-indexing), keep data correct under
concurrent load with the right transaction boundaries and locking, and evolve a live schema
through expand/contract migrations with no downtime and no data loss.
</content>

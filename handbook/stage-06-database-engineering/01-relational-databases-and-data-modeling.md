# Relational Databases & Data Modeling

## Introduction

The database is the part of a system you can least afford to get wrong. Application
code is replaced routinely — rewritten, refactored, ported to a new framework — but
the data outlives all of it, and a bad data model calcifies: once real users have
created millions of rows against a flawed schema, changing it is a migration project,
not an edit. This chapter is about the foundation under everything in Stage 3's
backend — what a relational database actually guarantees, and how to model a domain
into tables, relationships, and keys so the schema is a faithful, durable
representation of the business rather than an accident of the first feature.

The single most important idea: **the relational model is a set of guarantees, and
data modeling is the act of encoding your domain's truth into those guarantees so the
database — not the application — enforces correctness.** A relational database gives
you tables (relations), typed columns, keys that establish identity, foreign keys that
enforce relationships, constraints that reject invalid data, and ACID transactions
that keep it consistent under concurrency. Data modeling decides how your domain maps
onto that: what is an entity, how entities relate (one-to-many, many-to-many), what
uniquely identifies a row, and which rules become constraints. Done well, the schema
makes invalid states *impossible to store*. Done poorly, the application is forever
compensating for a database that permits nonsense.

The judgment this chapter teaches is modeling judgment. You will decide entities and
their relationships (and the join tables that many-to-many requires), choose **keys**
(surrogate versus natural), decide which rules live in the database as **constraints**
versus in application code, and choose column **types** deliberately (the difference
between `TEXT`, `VARCHAR`, `NUMERIC`, and `FLOAT` for money is a correctness decision,
not a style one). This is the layer Stage 3, Chapter 02 used (SQLAlchemy/Alembic)
without dwelling on the modeling — here we go deep on getting the model right, because
everything downstream (indexes, queries, migrations) is built on it.

## Why It Matters

The data model is the highest-leverage and least-reversible decision in a system, and
getting it wrong is expensive in a way application bugs are not:

- **Data outlives code.** You will rewrite the application; you will not casually
  rewrite the schema once it holds real data. A modeling mistake isn't a bug you patch
  — it's a structural flaw you migrate around for years. The cost of getting it right
  is paid once; the cost of getting it wrong is paid forever.
- **The database is the last line of defense for correctness.** Application code has
  bugs, races, and multiple entry points (the API, a background job, a manual script).
  A constraint in the database (`NOT NULL`, `UNIQUE`, `FOREIGN KEY`, `CHECK`) holds
  regardless of which code path runs — it's the one guarantee that can't be bypassed by
  a forgotten check. Rules enforced only in the application *will* eventually be
  violated.
- **A wrong model corrupts data silently.** A missing foreign key lets orphaned rows
  accumulate; a missing unique constraint lets duplicates in; storing money as `FLOAT`
  loses cents. These aren't crashes — they're quietly wrong data you discover months
  later when the numbers don't reconcile.
- **Relationships modeled wrong are the worst.** Getting a one-to-many backwards, or
  faking a many-to-many with a comma-separated string in a column, produces a schema
  that fights every query and can't enforce integrity. Relationships are the skeleton;
  a broken skeleton can't be fixed with better queries.
- **The model shapes everything downstream.** Indexes (Chapter 03), query performance
  (Chapter 05), and migrations (Chapter 06) are all constrained by the model. A clean
  model makes them tractable; a tangled one makes every one of them harder.

Get it right — entities and relationships that mirror the domain, keys that establish
clear identity, constraints that make invalid data unstorable, and correct types — and
the database becomes a reliable foundation that enforces correctness for free. Get it
wrong and the application spends its life compensating for a schema that permits the
impossible, and the data slowly rots.

The AI dimension: assistants generate schemas that "work" for the immediate feature and
skip the durable-correctness parts — they omit foreign keys and constraints (the app
"handles it"), pick types carelessly (money as float, everything as `VARCHAR(255)`),
fake many-to-many relationships, and model for the current screen rather than the
domain. Each produces a schema that demos fine and calcifies into a liability.

## Mental Model

Guarantees the database gives you, and the modeling that maps your domain onto them:

```
   THE RELATIONAL MODEL = GUARANTEES YOU CAN LEAN ON
     tables (relations) · typed columns · KEYS (identity) · FOREIGN KEYS (relationships)
     CONSTRAINTS (NOT NULL / UNIQUE / CHECK / FK) · ACID TRANSACTIONS (consistency under load)
        │
   DATA MODELING = encoding your DOMAIN'S TRUTH into those guarantees
        ▼
   ENTITIES ──────── the nouns: Customer, Invoice, LineItem, Payment
   RELATIONSHIPS ──── how they connect (enforced by FOREIGN KEYS):
        one-to-many   Customer 1───∞ Invoice        (FK on the "many" side)
        many-to-many  Invoice ∞───∞ Tag             (needs a JOIN TABLE)
        one-to-one    Customer 1───1 BillingProfile (rare; usually fold in)
   KEYS ──────────── surrogate (id serial/uuid) vs natural (email) — identity of a row
   CONSTRAINTS ────── the domain's RULES the DB enforces (not the app):
        amount NUMERIC NOT NULL CHECK (amount >= 0) · UNIQUE(customer_id, number)
   TYPES ─────────── money → NUMERIC (never FLOAT) · time → TIMESTAMPTZ · ids → int/uuid

   THE GOAL:  make invalid states IMPOSSIBLE TO STORE.
     if the app is the only thing stopping bad data, bad data will get in.
```

Four principles carry the chapter:

**Model the domain, not the screen.** Entities and relationships should mirror the
business's real structure (a customer has many invoices; an invoice has many line
items), not the shape of the first UI you're building. A domain-faithful model absorbs
new features; a screen-shaped model breaks on the second one.

**Get relationships right, with the database enforcing them.** One-to-many puts a
foreign key on the many side; many-to-many needs a join table; never fake a relationship
with a delimited string or a duplicated column. Foreign keys enforce referential
integrity so orphans and dangling references can't exist.

**Push rules into the database as constraints.** Anything that must always be true —
non-null fields, uniqueness, valid ranges, referential integrity — belongs as a
constraint, because the database enforces it across every code path and every race.
Application-only validation is a suggestion the database will eventually let through.

**Choose keys and types deliberately.** Pick a key strategy (surrogate ids by default,
natural keys where identity is genuinely natural and stable) and correct types (money as
`NUMERIC`, timestamps as `TIMESTAMPTZ`) — these are correctness decisions with long
tails, not defaults to accept blindly.

A working definition:

> **A relational database is a set of guarantees — typed tables, keys, foreign keys,
> constraints, and ACID transactions — and data modeling is encoding your domain's truth
> into them so invalid states are impossible to store. Model the domain (not the screen),
> get relationships right with the database enforcing them, push every always-true rule
> into a constraint, and choose keys and types deliberately, because the data outlives the
> code and the database is the last line of defense for correctness.**

## Production Example

**Invoicely's** core domain is a clean modeling exercise, and every relationship type
shows up. A **Customer** (the freelancer's client) has many **Invoices** (one-to-many).
An **Invoice** has many **LineItems** (one-to-many) and many **Payments** (one-to-many,
since an invoice can be paid in installments). An invoice can carry several **Tags**, and
a tag applies to many invoices (many-to-many — needs a join table). Each of these
relationships, modeled correctly, becomes a foreign key the database enforces; modeled
carelessly, each becomes a source of orphaned or duplicated data.

The correctness stakes are concrete. Money (`amount`, `total`) must be `NUMERIC`, not
`FLOAT`, or Invoicely loses cents on rounding — unacceptable for financial software. An
invoice number must be unique *per customer* (`UNIQUE(customer_id, number)`), a rule the
database enforces so two invoices can't collide. A line item must belong to an invoice
that exists (a foreign key), so deleting an invoice can't leave orphaned line items. An
amount can't be negative (`CHECK (amount >= 0)`). Each rule, expressed as a constraint,
makes a class of bad data unstorable — regardless of whether it's the API, a background
job (Stage 3, Chapter 06), or a manual fix that tries to write it.

In this chapter we model that domain into a PostgreSQL schema: entities as tables,
relationships as foreign keys (including the invoice↔tag join table), identity as keys,
and business rules as constraints, with types chosen for correctness. We contrast it with
the assistant-default schema (no foreign keys, money as float, a tags string column,
everything `VARCHAR(255)`, rules left to the app) to make the difference between a durable
model and a calcifying liability concrete.

## Folder Structure

```
api/app/                                 # the schema lives with the backend (Stage 3)
├── models/                              # SQLAlchemy models = the data model, in code
│   ├── customer.py                      # Customer entity
│   ├── invoice.py                       # Invoice (FK → customer); UNIQUE(customer_id, number)
│   ├── line_item.py                     # LineItem (FK → invoice); NUMERIC amounts
│   ├── payment.py                       # Payment (FK → invoice)
│   └── tag.py                           # Tag + invoice_tags join table (many-to-many)
├── migrations/                          # Alembic — the schema's version history (Chapter 06)
│   └── versions/
└── db/
    └── constraints.sql                  # DB-level checks/constraints not expressible in the ORM
```

Why this shape: the data model is expressed as code (SQLAlchemy models) and versioned as
migrations (Alembic, Chapter 06) — the schema is a first-class, reviewed artifact, not
something that drifts. Each entity is one model file so relationships and constraints are
visible where the entity is defined. The join table (`invoice_tags`) is explicit because a
many-to-many relationship *is* a table, not a hidden detail. `constraints.sql` holds the
database-level rules (multi-column checks, exclusion constraints) that belong in the DB even
when the ORM can't express them — a reminder that the database, not the ORM, is the source
of enforcement.

## Implementation

**Entities, relationships, keys, and constraints (the model).** The schema as it should
be: foreign keys enforcing relationships, a surrogate key for identity, a per-customer
uniqueness rule, correct money and time types, and check constraints for domain rules.

```sql
CREATE TABLE customers (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,   -- surrogate key (identity)
  email       TEXT NOT NULL,
  name        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),                -- TIMESTAMPTZ, not naive timestamp
  UNIQUE (email)                                                 -- natural uniqueness rule
);

CREATE TABLE invoices (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id  BIGINT NOT NULL REFERENCES customers (id),        -- FK: an invoice MUST have a real customer
  number       TEXT NOT NULL,
  total        NUMERIC(12, 2) NOT NULL CHECK (total >= 0),       -- money = NUMERIC; rule = CHECK
  status       TEXT NOT NULL DEFAULT 'draft'
                 CHECK (status IN ('draft', 'sent', 'paid', 'overdue')),  -- valid states only
  issued_at    TIMESTAMPTZ,
  UNIQUE (customer_id, number)                                   -- number unique PER customer
);

CREATE TABLE line_items (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  invoice_id  BIGINT NOT NULL REFERENCES invoices (id) ON DELETE CASCADE,  -- delete invoice → its items go
  description TEXT NOT NULL,
  quantity    INTEGER NOT NULL CHECK (quantity > 0),
  unit_price  NUMERIC(12, 2) NOT NULL CHECK (unit_price >= 0)
);
```

**A many-to-many relationship (the join table).** An invoice has many tags and a tag has
many invoices — this *is* a table, with foreign keys to both sides and a composite primary
key preventing duplicate pairings.

```sql
CREATE TABLE tags (
  id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name  TEXT NOT NULL UNIQUE
);

CREATE TABLE invoice_tags (                    -- the join table IS the many-to-many relationship
  invoice_id  BIGINT NOT NULL REFERENCES invoices (id) ON DELETE CASCADE,
  tag_id      BIGINT NOT NULL REFERENCES tags (id) ON DELETE CASCADE,
  PRIMARY KEY (invoice_id, tag_id)             -- a tag can't be applied to an invoice twice
);
```

**The same model in the ORM (`invoice.py`).** SQLAlchemy expresses the entity,
relationships, and constraints in code — but the enforcement still lives in the database.

```python
class Invoice(Base):
    __tablename__ = "invoices"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    customer_id: Mapped[int] = mapped_column(ForeignKey("customers.id"), nullable=False)
    number: Mapped[str] = mapped_column(Text, nullable=False)
    total: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)   # Decimal, never float
    status: Mapped[str] = mapped_column(Text, nullable=False, default="draft")

    customer: Mapped["Customer"] = relationship(back_populates="invoices")
    line_items: Mapped[list["LineItem"]] = relationship(cascade="all, delete-orphan")

    __table_args__ = (
        UniqueConstraint("customer_id", "number"),                # per-customer uniqueness
        CheckConstraint("total >= 0", name="total_non_negative"), # domain rule in the DB
    )
```

**The anti-pattern — the assistant-default schema.** Each shortcut is a durable-correctness
failure:

```sql
-- ANTI-PATTERN: "works" for the demo, calcifies into a liability
CREATE TABLE invoices (
  id           SERIAL PRIMARY KEY,
  customer_id  INTEGER,                       -- 1) NO foreign key → orphaned invoices possible
  number       VARCHAR(255),                  -- 2) VARCHAR(255) reflex; no per-customer uniqueness
  total        FLOAT,                          -- 3) money as FLOAT → lost cents, un-reconcilable
  status       VARCHAR(255),                   -- 4) no CHECK → 'paidd', 'PAID', '' all allowed
  tags         VARCHAR(255),                   -- 5) comma-separated tags → a faked many-to-many
  issued_at    VARCHAR(255)                    -- 6) a timestamp stored as a string
);
-- ...and every rule (non-null, uniqueness, valid status) left to the application to remember.
```

The difference is the whole chapter: the good model enforces relationships with foreign
keys, makes money exact, forbids invalid statuses and duplicates, and models tags as a real
relationship — so bad data can't be stored. The bad model permits orphans, loses cents,
accepts any status string, and buries a many-to-many in a text column — a schema that
passes the first demo and becomes a data-integrity nightmare and a migration project as it
fills with real, subtly-wrong data.

## Engineering Decisions

Five decisions define the model.

### Surrogate keys or natural keys?

**Options:** (1) surrogate keys (an auto-generated `id`); (2) natural keys (a real-world
unique attribute like email); (3) composite natural keys.

**Trade-offs:** surrogate keys are stable (they never change even if the underlying data
does), uniform, and index-friendly, at the cost of an extra column and a layer of
indirection. Natural keys avoid the surrogate and can remove a join, but real-world
identifiers change (people change email, "unique" codes get reused) — and a changing
primary key cascades pain through every foreign key. Composite natural keys compound this.

**Recommendation:** default to a surrogate primary key (`id`) for entities, and add unique
constraints on the natural keys that must be unique (email, per-customer number). You get
stable identity *and* enforced natural uniqueness. Use a natural primary key only when the
identifier is genuinely immutable and there's a clear reason — rare in practice.

### Which rules become database constraints versus application checks?

**Options:** (1) enforce rules only in application code; (2) enforce in the database via
constraints; (3) both.

**Trade-offs:** application-only checks are flexible and expressive but bypassable — a
different code path, a background job, a manual query, or a race skips them, and the bad
data lands. Database constraints are absolute (every write goes through them) but limited to
what SQL can express (null, unique, check, foreign key) and less flexible to change.
Both-layers gives good UX (early app-level errors) *and* absolute enforcement.

**Recommendation:** every rule that must *always* hold — non-null, uniqueness, valid ranges,
referential integrity — belongs in the database as a constraint, because it's the only layer
that can't be bypassed. Add application-level validation on top for good error messages and
complex rules. When forced to choose one, choose the database — it's the last line of
defense.

### How do you model a many-to-many relationship?

**Options:** (1) a proper join table; (2) a delimited string / array column; (3) duplicated
columns.

**Trade-offs:** a join table is the correct relational model — it enforces integrity (foreign
keys to both sides), prevents duplicates (composite key), and supports efficient queries and
indexing, at the cost of an extra table and a join. A delimited string (`tags = "a,b,c"`) or a
duplicated set of columns is easier to eyeball for one row and destroys queryability, integrity,
and indexing — you can't foreign-key or efficiently filter a comma-separated blob.

**Recommendation:** always model many-to-many with a join table. The delimited-string shortcut
is a faked relationship that the database can't enforce and queries can't use — a classic
source of rot. (A PostgreSQL array or JSONB column is legitimate for genuinely unstructured
data, but not as a substitute for a real relationship.)

### What column types do you choose?

**Options:** (1) deliberate types (`NUMERIC` for money, `TIMESTAMPTZ` for time, enums/checks
for finite sets); (2) `VARCHAR(255)`/`FLOAT`/`TEXT` for everything by reflex.

**Trade-offs:** deliberate types make the database enforce shape and preserve correctness —
`NUMERIC` keeps money exact, `TIMESTAMPTZ` stores an unambiguous instant, a check/enum
restricts a status to valid values. Reflexive types (money as `FLOAT`, timestamps as strings,
`VARCHAR(255)` everywhere) lose precision, ambiguity, and validity, and are painful to fix
after data exists.

**Recommendation:** choose types for correctness — money is `NUMERIC` (never `FLOAT`),
timestamps are `TIMESTAMPTZ`, finite sets are constrained (`CHECK`/enum), text that has no
length rule is `TEXT` (Postgres `VARCHAR(n)` gives no performance benefit; the `255` is a
MySQL-era cargo cult). Types are correctness decisions with long tails.

### Model the domain or the current feature?

**Options:** (1) model the domain's real entities and relationships; (2) model exactly what
the current screen/feature needs.

**Trade-offs:** modeling the domain produces a schema that reflects the business's real
structure and absorbs new features with local changes, at the cost of thinking past the
immediate task. Modeling the current feature is faster now and produces a schema shaped like
one UI — which the second feature contradicts, forcing a reshape once data exists.

**Recommendation:** model the domain — the real entities, relationships, and rules — not the
first screen. The schema is the most expensive thing to change later, so the up-front modeling
thought has the highest return of any design work. Let the model lead the features, not the
other way around.

## Trade-offs

A well-modeled schema trades up-front thought and some rigidity for durable correctness on the
least-reversible part of the system.

**Constraints trade flexibility for guaranteed integrity.** Every constraint is a rule the
database enforces on all writes — absolute protection against a class of bad data, and a rule
that's slightly harder to change later. For anything that must always be true, the rigidity is
the point: you *want* it impossible to store invalid data. The trade is strongly positive for
core invariants.

**Surrogate keys trade an extra column for stable identity.** An `id` adds a column and an
indirection, and it gives you identity that never changes even as the underlying data does —
sparing every foreign key the pain of a shifting key. For entities, the small cost buys a large,
recurring benefit.

**Normalization/relationships trade some join cost for integrity and non-duplication.** Modeling
relationships properly (foreign keys, join tables) means queries join rather than reading one
denormalized row, and it makes integrity enforceable and duplication impossible. Chapter 02
covers when deliberate denormalization is worth reversing this; the default (a normalized,
relational model) is right until measurement says otherwise.

**Domain modeling trades up-front effort for downstream tractability.** Thinking through the real
entities and relationships before coding the first feature is slower to start and makes indexes,
queries, and migrations tractable for the life of the system. Because the schema is the hardest
thing to change, this up-front effort has the highest leverage in the stage.

## Common Mistakes

**Missing foreign keys.** Relationships modeled as bare id columns with no `REFERENCES`, allowing
orphaned and dangling rows. Fix: foreign keys on every relationship, so referential integrity is
enforced.

**Rules only in the application.** Uniqueness, non-null, and valid ranges checked in code and
bypassable by other paths/races. Fix: database constraints for every always-true rule; app
validation on top.

**Money as `FLOAT`.** Financial amounts stored as floating point, losing cents to rounding. Fix:
`NUMERIC` for all money.

**Faked many-to-many.** Tags/relationships stuffed into a delimited string or duplicated columns —
unqueryable, unenforceable. Fix: a join table.

**Reflexive types.** `VARCHAR(255)` everywhere, timestamps as strings, no `CHECK` on finite sets.
Fix: deliberate types (`TEXT`/`NUMERIC`/`TIMESTAMPTZ`/`CHECK`).

**Modeling the screen.** A schema shaped like the first UI that the second feature breaks. Fix:
model the domain's real entities and relationships.

## AI Mistakes

Assistants optimize schemas for the immediate feature working, not for durable correctness, so
they systematically omit the parts that protect data over time. Review generated schemas for what
the database *enforces*, not just whether the feature runs.

### Claude Code: omitting foreign keys and constraints

Asked to create tables for a feature, Claude Code often produces columns that *imply* relationships
(a `customer_id` integer) without the `REFERENCES` that enforces them, and skips `NOT NULL`/
`UNIQUE`/`CHECK` because the application "handles" those. The schema works in the demo and permits
orphans, duplicates, and invalid values in production.

**Detect:** id columns with no `REFERENCES`; nullable columns that should be required; no `UNIQUE`
on fields that must be unique; no `CHECK` on finite sets (status) or ranges; "the app validates it"
reasoning for invariants.

**Fix:** require database-level enforcement:

> Enforce relationships and rules in the schema, not only the app. Every relationship needs a
> `FOREIGN KEY`; every always-true rule needs a constraint (`NOT NULL`, `UNIQUE`, `CHECK`). The
> database is the last line of defense and can't be bypassed by another code path or a race — don't
> rely on application validation for data integrity.

### GPT: careless types (money as float, VARCHAR(255) everywhere)

GPT-family models default to `FLOAT` for numbers (including money), `VARCHAR(255)` for strings, and
naive timestamps — reflexive types that look fine and quietly lose correctness (cents, timezone,
validity). The `255` in particular is a MySQL-era habit with no basis in Postgres.

**Detect:** money/financial columns typed `FLOAT`/`REAL`/`DOUBLE`; `VARCHAR(255)` used
indiscriminately; timestamps as `VARCHAR`/naive `TIMESTAMP`; finite-valued columns with no
constraint.

**Fix:** require deliberate types:

> Choose types for correctness: money is `NUMERIC` (never `FLOAT`), timestamps are `TIMESTAMPTZ`,
> finite sets are constrained (`CHECK`/enum), and unbounded text is `TEXT` (there's no reason for
> `VARCHAR(255)` in Postgres). Don't default every string to `VARCHAR(255)` or every number to
> `FLOAT`.

### Cursor: faking relationships and modeling the current screen

Editing to satisfy the immediate feature, Cursor tends to add a column to an existing table (a
comma-separated `tags` string, a duplicated field) rather than model the relationship properly, and
shapes tables around the screen being built — decisions that are local and fast now and structurally
wrong as the domain grows.

**Detect:** many-to-many data stored in a delimited string/array instead of a join table; duplicated
columns instead of a related table; tables that mirror a specific UI rather than the domain; a new
feature bolted onto a table it doesn't belong in.

**Fix:** require proper relational modeling:

> Model this as a real relationship: many-to-many needs a join table, not a comma-separated column;
> a distinct entity needs its own table, not duplicated columns. Model the domain's real structure,
> not the current screen — the schema outlives the UI and is expensive to reshape later.

## Best Practices

**Model the domain into entities, relationships, and rules first.** Identify the real entities and
how they relate before coding the feature, and let the model lead. It's the most expensive thing to
change later and the highest-leverage thing to get right.

**Enforce relationships and invariants in the database.** Foreign keys for every relationship,
constraints (`NOT NULL`/`UNIQUE`/`CHECK`) for every always-true rule. The database is the only
layer that can't be bypassed; application validation is an addition, not a substitute.

**Use surrogate keys with unique constraints on natural keys.** Stable `id` primary keys for
identity, plus `UNIQUE` on the attributes that must be unique — stable identity and enforced natural
uniqueness together.

**Model many-to-many with join tables and choose types deliberately.** A real join table for
many-to-many; `NUMERIC` for money, `TIMESTAMPTZ` for time, `CHECK`/enum for finite sets, `TEXT` for
unbounded strings. Never fake a relationship or reach for `VARCHAR(255)`/`FLOAT` by reflex.

**Version the schema and document the model.** Manage the schema through migrations (Chapter 06) so
it's reviewed and reversible, and document the modeling conventions (keys, constraints, types) in
`CLAUDE.md` so assistants stop omitting them.

## Anti-Patterns

**The Foreign-Key-Free Schema.** Relationships as bare id columns with no `REFERENCES` — orphans and
dangling references accumulate. The tell: `customer_id INTEGER` with no foreign key.

**The App-Enforced Invariant.** Uniqueness/non-null/validity checked only in code and bypassed by
other paths or races. The tell: no constraints in the schema, "the app handles it" in review.

**The Float Money.** Financial amounts as `FLOAT`, losing cents. The tell: `total FLOAT` in anything
that touches money.

**The Comma-Separated Relationship.** Many-to-many faked as a delimited string or duplicated columns.
The tell: `tags VARCHAR(255) = "a,b,c"` instead of a join table.

**The VARCHAR(255) Reflex.** Every string `VARCHAR(255)`, timestamps as strings, finite sets
unconstrained. The tell: a schema of uniform `VARCHAR(255)` columns with no domain types.

**The Screen-Shaped Schema.** Tables modeled after the first UI, contradicted by the second feature.
The tell: a table that only makes sense for one screen.

## Decision Tree

"I'm modeling a piece of the domain — how do I get the schema right?"

```
Start from the DOMAIN, not the screen. What are the real entities and how do they relate?

Relationship between two entities?
├── one-to-many ──► FOREIGN KEY on the "many" side (invoice.customer_id → customers.id).
├── many-to-many ─► a JOIN TABLE with FKs to both sides + a composite PK. Never a delimited string.
└── one-to-one ───► usually fold into one table; separate only with a real reason.

Choosing a primary key?
└──► surrogate id by default (stable identity) + UNIQUE constraints on natural keys (email, number).
     Natural PK only if the identifier is genuinely immutable.

A rule that must ALWAYS hold (non-null / unique / valid range / referential)?
└──► make it a DATABASE CONSTRAINT (it can't be bypassed). Add app validation on top for UX.
     If it's only in the app, assume it will eventually be violated.

Choosing a column type?
├── money ──────► NUMERIC (never FLOAT)          ├── time ──────► TIMESTAMPTZ
├── finite set ─► CHECK / enum                    └── unbounded text ─► TEXT (not VARCHAR(255))

Then: version it as a migration (Ch 06). Index it based on real queries (Ch 03).
```

## Checklist

### Implementation Checklist

- [ ] Every relationship is enforced by a `FOREIGN KEY`; there are no bare id columns.
- [ ] Every always-true rule is a database constraint (`NOT NULL`/`UNIQUE`/`CHECK`), not only app code.
- [ ] Entities use a stable surrogate primary key, with `UNIQUE` on the natural keys that must be unique.
- [ ] Many-to-many relationships use join tables — no delimited strings or duplicated columns.
- [ ] Types are chosen for correctness (`NUMERIC` money, `TIMESTAMPTZ` time, `CHECK`/enum finite sets, `TEXT`).
- [ ] The schema is managed through migrations (Chapter 06), not ad-hoc changes.

### Architecture Checklist

- [ ] The model reflects the domain's real entities and relationships, not the first screen.
- [ ] The database is the source of enforcement for data integrity; app validation is additive.
- [ ] Cascade/deletion behavior (`ON DELETE`) is deliberate for each relationship.
- [ ] Key strategy (surrogate + natural uniqueness) is consistent across entities.
- [ ] Modeling conventions (keys, constraints, types) are documented in `CLAUDE.md`.

### Code Review Checklist

- [ ] No relationship without a foreign key (watch AI diffs).
- [ ] No invariant enforced only in the application.
- [ ] No money stored as `FLOAT`; no reflexive `VARCHAR(255)`.
- [ ] No many-to-many faked in a column instead of a join table.
- [ ] No table modeled after a screen rather than the domain.

*(A Deployment Checklist is not applicable to this chapter; schema changes ship via migrations — Chapter 06.)*

## Exercises

**1. Model the Invoicely domain.** From the domain description (customers, invoices, line items,
payments, tags), produce the full PostgreSQL schema with correct relationships (including the
invoice↔tag join table), keys, constraints, and types. The artifact is the schema plus a note on
which rules you pushed into the database and why.

**2. Break, then fix, an AI schema.** Have an assistant generate "a schema for invoices and
customers" and catalog every durable-correctness failure (missing FKs, float money, `VARCHAR(255)`,
faked relationships, missing constraints). Rewrite it correctly. The artifact is the before/after and
the categorized list.

**3. Prove the database is the last line of defense.** Take a rule enforced only in application code
(e.g., unique invoice number per customer), then write directly to the database from two paths (or
concurrently) to violate it. Add the constraint and show the database now rejects the bad write. The
artifact is the demonstration and a note on why app-only enforcement failed.

## Further Reading

- **PostgreSQL documentation — "Data Definition" (constraints, foreign keys) and "Data Types"**
  (postgresql.org/docs) — the authoritative reference for constraints and types; the "Constraints" and
  "Numeric/Date-Time Types" sections directly back this chapter's correctness rules.
- **"Database Design for Mere Mortals" by Michael Hernandez** — a practical, non-academic guide to
  modeling entities and relationships; the best single source for the modeling judgment this chapter
  teaches.
- **PostgreSQL documentation — "Don't Do This" (wiki.postgresql.org/wiki/Don't_Do_This)** — a concise
  list of type and modeling mistakes (including `VARCHAR(n)` and money-as-float) that maps almost
  directly onto the AI mistakes here.
- **Stage 3, Chapter 02 — Data Persistence (SQLAlchemy & Alembic)** — how this model is expressed and
  migrated in the backend; this chapter is the modeling depth behind that chapter's tooling.
</content>

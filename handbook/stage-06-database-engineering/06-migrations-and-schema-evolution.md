# Migrations & Schema Evolution

## Introduction

A schema is never finished. The model from Chapters 01–02 is correct for today; next
month a feature needs a new column, a table split, a type change. The question this
chapter answers is *how* to make those changes safely — against a live database, holding
real user data, serving traffic, with no downtime and a way back if the change goes
wrong. This is schema evolution, and it's where database engineering is most unforgiving:
a bad migration doesn't just throw an error, it can lock a table for minutes under load,
destroy data irreversibly, or leave the schema and the running code in states that
disagree. Getting it wrong is a production incident; getting it right is a discipline.

The single most important idea: **a migration is a version-controlled, reversible,
forward-only change to the schema, and the hard constraint is that it runs against a
live system — so the change and the code that depends on it must be compatible at every
moment during the deploy, not just after.** In development you can drop and recreate a
database freely. In production the database is always on, always holding data, and
always being read and written by a version of the application code that is *mid-deploy* —
old code and new code running simultaneously during a rollout. A migration that assumes
the new code is already everywhere (drop a column the old code still reads) breaks
production during the deploy window. Safe schema evolution means designing changes that
are backward-compatible with the currently-running code, which is what the
**expand/contract** pattern exists to do.

The judgment this chapter teaches: treat every schema change as a **migration** (never a
manual `ALTER` in production), make migrations **reversible** and tested, understand which
operations **lock** and how to avoid downtime (a `NOT NULL` column with a default, an index
built non-concurrently, a type change — each can lock a busy table), and separate the two
genuinely dangerous cases: **destructive** changes (dropping data — irreversible, needs
extreme care) and **breaking** changes (incompatible with running code — needs
expand/contract). This is the operational counterpart to the modeling in Chapters 01–02
and the tooling (Alembic) introduced in Stage 3, Chapter 02 — here we go deep on doing it
safely at production scale, which is where AI-generated migrations are especially
hazardous.

## Why It Matters

Schema changes are the most dangerous routine operation in a production system, because
the database is stateful, always-on, and holds the one thing you can't regenerate:

- **The database is stateful and live — you can't just redeploy it.** A bad application
  deploy is rolled back by shipping the previous build. A bad migration has often already
  altered or dropped data by the time you notice; "roll back the code" doesn't un-drop a
  column. State makes mistakes durable.
- **Migrations run during a rollout, when old and new code coexist.** During a deploy,
  some servers run the old code and some the new, against the same database. A migration
  that only works with the new code (removing something the old code still uses) breaks
  every request hitting an old server. Compatibility must hold *throughout* the deploy,
  not just at the end.
- **Some operations lock the table.** Adding a column with a volatile default, creating an
  index non-concurrently, changing a column type, or adding a `NOT NULL` constraint can
  take a lock that blocks reads and/or writes for the duration — seconds on a small table,
  minutes on a large busy one. A locking migration during peak traffic is an outage.
- **Destructive changes are irreversible.** Dropping a column or table deletes data that
  no rollback restores. A migration that drops "the old column" before confirming nothing
  needs it, run against production, is permanent data loss.
- **Schema and code drift causes subtle breakage.** If the schema changes but the code's
  model doesn't (or vice versa), you get runtime errors, missing columns, or writes that
  silently fail — the two must evolve together, in a defined order.
- **Manual changes are unrepeatable and unauditable.** An `ALTER TABLE` typed into a
  production console isn't in version control, isn't in staging, can't be reviewed, and
  can't be reproduced on another environment. It's the schema equivalent of editing
  production code live.

Get it right — every change a reviewed, reversible, tested migration; locking operations
handled without downtime; destructive and breaking changes staged through expand/contract
— and the schema evolves continuously with no outages and no data loss. Get it wrong and a
single migration locks a table under load, drops data with no recovery, or breaks
production during the deploy window when old and new code disagree.

The AI dimension: assistants generate migrations that work against an empty dev database
and are dangerous against a live one — they add `NOT NULL` columns without defaults (lock/
fail on existing rows), create indexes non-concurrently (lock the table), drop columns in
the same deploy as the code change (break during rollout), and omit the `down`/rollback.
Each is invisible in development and an incident in production.

## Mental Model

A migration is versioned, reversible, and runs live — so it must stay compatible with the
running code throughout the deploy:

```
   A MIGRATION = a versioned, reversible schema change (never a manual prod ALTER)
     up:   apply the change      down: revert it       both in version control, tested, reviewed
     runs on a LIVE database with DATA and TRAFFIC — dev's "drop & recreate" doesn't apply.

   THE DEPLOY WINDOW — old & new code run AT THE SAME TIME:
     [ old code ]───┐
                    ├── same database ──► the migration must work for BOTH during rollout
     [ new code ]───┘

   TWO DANGEROUS KINDS OF CHANGE:
     DESTRUCTIVE (drops data) ─────► irreversible. no rollback restores dropped data. extreme care.
     BREAKING  (incompatible w/ running code) ─► breaks during the deploy window.

   THE FIX FOR BREAKING CHANGES — EXPAND / CONTRACT (multi-step, each step compatible):
     rename column old → new:
       1. EXPAND   add `new`; write to BOTH old & new (code compatible with either)   ← deploy
       2. BACKFILL copy old → new for existing rows                                    ← migration
       3. MIGRATE  switch reads to `new`                                               ← deploy
       4. CONTRACT drop `old` (only once nothing reads it)                             ← later migration
     never rename-in-place in one step on a live system.

   LOCKING AWARENESS (avoid downtime on big/busy tables):
     CREATE INDEX ─────────► CREATE INDEX CONCURRENTLY
     ADD COLUMN NOT NULL ──► add nullable + default, backfill, then set NOT NULL (or use a fast default)
     change type / add FK ─► can lock/validate — do it in steps / NOT VALID then VALIDATE
```

Four principles carry the chapter:

**Every schema change is a versioned, reversible, tested migration.** No manual `ALTER` in
production. Migrations live in version control, run in every environment in order, have a
tested rollback, and are reviewed like code — so schema changes are repeatable, auditable,
and recoverable.

**Design for the deploy window: stay compatible with the running code.** During a rollout,
old and new code hit the same database. A migration must not break the code currently
running — which means breaking changes are done as multi-step, each step compatible with
what's live.

**Use expand/contract for breaking changes.** Add the new shape, make the code write to
both, backfill, switch reads, and only then remove the old shape — each step deployable
without breaking the previous code. Never rename/drop/retype in a single step on a live
system.

**Know what locks, and never drop data casually.** Understand which operations take blocking
locks (indexes, `NOT NULL`, type changes) and use the non-locking form (`CONCURRENTLY`,
nullable-then-backfill, `NOT VALID` then `VALIDATE`). Treat destructive changes as
irreversible: confirm nothing needs the data, and stage the drop well after the code stops
using it.

A working definition:

> **A migration is a version-controlled, reversible, reviewed schema change that runs against
> a live database where old and new code coexist during the deploy — so it must stay
> compatible with the running code at every moment. Do breaking changes as multi-step
> expand/contract, use non-locking operations to avoid downtime on busy tables, and treat
> destructive changes as irreversible. Never manually `ALTER` production, never drop data in
> the same step the code changes, and always have a tested rollback.**

## Production Example

**Invoicely** needs a schema change that looks trivial and is a live-system minefield:
splitting the customer's single `name` column into `first_name` and `last_name`. Done the
dev way — `ALTER TABLE customers RENAME/DROP name, ADD first_name, last_name` in one
migration — it breaks production three ways at once: it drops data (the combined names) with
no recovery, it locks the table while rewriting rows, and it breaks every old-code server
mid-deploy that still reads `name`. The correct approach is expand/contract across several
deploys, each step compatible with the code running at the time.

A second, common case: adding a **required** `currency` column to `invoices`. Naively,
`ADD COLUMN currency TEXT NOT NULL` fails outright (existing rows have no value) or, with a
volatile default, rewrites and locks the whole table. The safe path: add it nullable with a
default, backfill existing rows in batches, then set `NOT NULL` once every row has a value —
no lock long enough to matter, no failure on existing data.

A third: adding an **index** to the now-huge `invoices` table (Chapter 03). `CREATE INDEX`
locks the table against writes for the whole build — an outage under load. `CREATE INDEX
CONCURRENTLY` builds it without blocking writes, at the cost of running longer and not being
transactional. Each of these is a migration whose *shape* is dictated by the fact that the
database is live, full, and busy.

In this chapter we implement these with Alembic (Stage 3, Chapter 02): the name-split as a
staged expand/contract, the required-column add as add-nullable-backfill-constrain, and the
index as `CONCURRENTLY` — each reversible and reviewed. We contrast them with the assistant-
default single-step migrations (rename in place, `NOT NULL` with no plan for existing rows,
non-concurrent index, no `down`) that are green against an empty dev database and an incident
against production.

## Folder Structure

```
api/app/migrations/                       # Alembic — the schema's version history (Stage 3 Ch 02)
├── versions/
│   ├── 0009_expand_customer_name.py      # STEP 1: add first_name/last_name (nullable), write both
│   ├── 0010_backfill_customer_name.py    # STEP 2: backfill from `name` in batches
│   ├── 0011_switch_reads_to_new_name.py  # (code deploy) reads use first/last; then...
│   └── 0012_contract_drop_old_name.py    # STEP 3: drop `name` — only after nothing reads it
├── env.py                                # connection, transaction-per-migration config
└── README.md                             # the team's migration rules: reversible, non-locking, staged
```

Why this shape: the name-split is *four numbered files across multiple deploys*, not one —
the folder structure itself shows that a breaking change is a sequence, each step separately
deployable and compatible with the code live at that moment. Migrations are ordered and
version-controlled so every environment applies the same changes in the same order (dev →
staging → production), and each is reviewed like code. `README.md` records the team's rules
(every migration reversible, index builds concurrent, destructive drops staged after the code
change) so the safe patterns are the default, not rediscovered each time. The structure encodes
the chapter's core claim: safe schema evolution is staged, ordered, and reviewed.

## Implementation

**The dangerous single-step change (what NOT to do).** One migration that drops data, locks,
and breaks the deploy window:

```python
# ANTI-PATTERN: rename-in-place on a live system — three production failures in one migration
def upgrade():
    op.add_column("customers", sa.Column("first_name", sa.Text(), nullable=False))  # 1) fails: existing rows
    op.add_column("customers", sa.Column("last_name", sa.Text(), nullable=False))   #    have no value
    op.drop_column("customers", "name")   # 2) DROPS DATA irreversibly  3) breaks old code still reading `name`
def downgrade():
    pass                                   # 4) no rollback — and the dropped data is gone anyway
```

**Expand/contract, step 1 — expand (add the new, compatible with old code).** Add the new
columns nullable so existing rows and old code are fine; the application deploy alongside this
writes to both old and new.

```python
# STEP 1 (0009): EXPAND — add new columns nullable. Old code (reading `name`) still works.
def upgrade():
    op.add_column("customers", sa.Column("first_name", sa.Text(), nullable=True))
    op.add_column("customers", sa.Column("last_name", sa.Text(), nullable=True))
def downgrade():
    op.drop_column("customers", "last_name")
    op.drop_column("customers", "first_name")   # reversible: dropping just-added empty columns is safe
```

**Step 2 — backfill existing rows in batches.** Populate the new columns from the old one
without locking the whole table in one statement.

```python
# STEP 2 (0010): BACKFILL in batches — no single table-wide lock, safe on a live busy table.
def upgrade():
    conn = op.get_bind()
    while True:
        result = conn.execute(sa.text("""
            UPDATE customers SET first_name = split_part(name, ' ', 1),
                                 last_name  = substr(name, position(' ' in name) + 1)
            WHERE id IN (SELECT id FROM customers WHERE first_name IS NULL LIMIT 1000)
        """))
        if result.rowcount == 0:
            break                                  # done when no more unbackfilled rows
```

**Step 3 — contract (drop the old column), only after nothing reads it.** A *separate*
migration shipped after the code deploy that switched reads to the new columns.

```python
# STEP 3 (0012): CONTRACT — drop `name`. Runs ONLY after a deploy where no code reads `name`.
def upgrade():
    op.alter_column("customers", "first_name", nullable=False)  # now safe: every row backfilled
    op.alter_column("customers", "last_name", nullable=False)
    op.drop_column("customers", "name")            # destructive — but nothing depends on it now
def downgrade():
    op.add_column("customers", sa.Column("name", sa.Text(), nullable=True))  # shape back (data can't return)
```

**The required-column and index cases — non-locking forms.**

```python
# Add a REQUIRED column safely: nullable + default → backfill → set NOT NULL (no long lock, no failure).
def upgrade():
    op.add_column("invoices", sa.Column("currency", sa.Text(), server_default="USD", nullable=True))
    op.execute("UPDATE invoices SET currency = 'USD' WHERE currency IS NULL")  # backfill (batch if huge)
    op.alter_column("invoices", "currency", nullable=False)

# Build an index WITHOUT locking writes on a large busy table (must be outside a transaction).
def upgrade():
    op.execute("COMMIT")  # CONCURRENTLY can't run in a transaction
    op.create_index("ix_invoices_currency", "invoices", ["currency"], postgresql_concurrently=True)
```

The difference is the whole chapter: the safe versions stage breaking changes across deploys
(each step compatible with the running code), backfill in batches, add required columns without
failing on existing rows, and build indexes concurrently — every step reversible and reviewed.
The dangerous version does it all in one migration that drops data, locks the table, and breaks
old code mid-deploy — perfectly fine against the empty dev database it was written against, and a
production incident against the live one.

## Engineering Decisions

Five decisions define safe schema evolution.

### Migration tool or manual changes?

**Options:** (1) manual `ALTER` in each environment; (2) a migration tool (Alembic) with
version-controlled, ordered migrations.

**Trade-offs:** manual changes are fast for one environment and unrepeatable, unauditable, and
error-prone across environments — dev, staging, and production drift, and there's no review or
rollback. A migration tool makes every change a versioned, ordered, reviewable file applied
identically everywhere, at the cost of the tooling and discipline.

**Recommendation:** every schema change goes through the migration tool (Alembic) — versioned,
ordered, reviewed, and applied the same way in every environment. Never `ALTER` production by
hand. This is non-negotiable for a team: the schema's history must be as managed as the code's.

### Reversible migrations, or forward-only?

**Options:** (1) write both `up` and `down`; (2) forward-only (no rollback); (3) rely on
backups.

**Trade-offs:** a tested `down` lets you revert a bad *structural* change quickly. Forward-only
is simpler and leaves you with only "fix forward" when a migration goes wrong. Backups restore
data but are slow and coarse (whole-database, point-in-time), not a per-migration rollback.

**Recommendation:** write and test a `down` for every migration where it's meaningful (structural
changes are reversible; genuinely destructive data changes are not, and you should know which is
which). Reversibility is your fast path back for schema mistakes; backups are the safety net for
data, not a substitute for a rollback. Test the `down`, not just the `up`.

### How do you handle a locking operation on a big table?

**Options:** (1) run it directly (accept the lock); (2) use the non-locking form
(`CONCURRENTLY`, nullable-then-backfill, `NOT VALID`/`VALIDATE`); (3) schedule it for a
maintenance window.

**Trade-offs:** running it directly is simplest and can lock a busy table for the duration —
an outage under load. The non-locking forms avoid the blocking lock at the cost of being
multi-step, longer, and sometimes non-transactional. A maintenance window sidesteps the lock's
impact at the cost of downtime (increasingly unacceptable).

**Recommendation:** use the non-locking form for operations on large, busy tables — `CREATE
INDEX CONCURRENTLY`, add-nullable-then-backfill-then-`NOT NULL`, `ADD CONSTRAINT ... NOT VALID`
then `VALIDATE`. Know which operations lock (indexes, `NOT NULL`, many type changes, some FK
adds) and reach for the safe form by default on anything that isn't tiny. Reserve maintenance
windows for changes with no online path.

### How do you make a breaking change without breaking the deploy?

**Options:** (1) change in place in one step; (2) expand/contract across multiple deploys; (3)
take downtime.

**Trade-offs:** an in-place change (rename/drop/retype in one migration) breaks the old code
still running during the rollout — every request to an un-updated server fails. Expand/contract
(add new, dual-write, backfill, switch, drop old) keeps every intermediate state compatible with
the code that's live, at the cost of several coordinated deploys. Downtime avoids the coexistence
problem at the cost of an outage.

**Recommendation:** use expand/contract for any change incompatible with the currently-running
code — add the new shape, make the code work with both old and new, backfill, switch reads, then
remove the old shape in a later deploy. Never rename, drop, or retype a column in a single step on
a live system. The multi-step coordination is the price of zero-downtime evolution.

### When (and how) do you make a destructive change?

**Options:** (1) drop immediately when the code stops using it; (2) stage the drop well after the
code change, after confirming disuse; (3) never drop (leave dead columns).

**Trade-offs:** dropping immediately risks removing something still referenced (by old code
mid-deploy, a report, a downstream consumer) — irreversible data loss. Staging the drop (deploy
the code that stops using it, confirm nothing reads it, then drop in a later migration) is safe at
the cost of a temporary dead column. Never dropping accumulates cruft.

**Recommendation:** stage destructive changes — ship the code that stops using the data, confirm
(via logs/usage) nothing depends on it, then drop in a separate, later migration. Treat every drop
as irreversible and gate it behind proof of disuse. The dead column costs nothing for a few weeks;
the premature drop can cost you data permanently.

## Trade-offs

Safe schema evolution trades speed and simplicity for the ability to change a live, stateful
system without outages or data loss.

**Migrations trade convenience for repeatability and recoverability.** A migration file is more
overhead than a quick `ALTER`, and it makes every change versioned, reviewable, reproducible across
environments, and reversible. For a production system with more than one environment, the overhead
is the difference between managed evolution and drift-and-incidents.

**Expand/contract trades several deploys for zero downtime.** A breaking change done safely is
multiple coordinated steps instead of one migration, and it keeps the system serving traffic
throughout with no broken deploy window. You trade coordination effort for not taking an outage —
the right trade for any system real users depend on.

**Non-locking operations trade simplicity and speed for availability.** `CONCURRENTLY`,
backfill-in-batches, and `NOT VALID`/`VALIDATE` are more steps and run longer than the direct form,
and they keep a busy table available during the change. The extra effort buys the difference between
a smooth change and a locked table under load.

**Staged destructive changes trade a temporary dead column for data safety.** Waiting to drop until
disuse is confirmed leaves cruft in the schema briefly and removes the risk of irreversible data
loss from a premature drop. Against permanent data loss, a few weeks of a dead column is nothing.

## Common Mistakes

**Manual production `ALTER`.** Unversioned, unreviewed, unrepeatable changes typed into a prod
console. Fix: every change is a migration through the tool.

**`NOT NULL` column with no plan for existing rows.** `ADD COLUMN ... NOT NULL` that fails on
existing data or locks while rewriting. Fix: add nullable + default, backfill, then set `NOT NULL`.

**Non-concurrent index on a big table.** `CREATE INDEX` locking writes for the whole build. Fix:
`CREATE INDEX CONCURRENTLY`.

**Rename/drop/retype in one step.** A breaking change that breaks old code during the deploy window.
Fix: expand/contract across deploys.

**Premature or casual drop.** Dropping data still referenced, irreversibly. Fix: stage the drop after
the code stops using it and disuse is confirmed.

**No tested rollback.** Migrations with no `down`, or a `down` never run. Fix: write and test the
`down` for reversible changes; know which changes aren't reversible.

## AI Mistakes

Migrations are written and tested against an empty dev database, which is exactly where assistants'
blind spots hide — the danger is entirely in the *live, full, concurrently-accessed* production
database the migration never saw. Review every generated migration as if it runs against millions of
rows and code mid-deploy.

### Claude Code: `NOT NULL` columns and non-concurrent indexes (locks/fails on real data)

Asked to add a required field or an index, Claude Code produces the direct form — `ADD COLUMN ... NOT
NULL` (no default), `CREATE INDEX` (not concurrent) — which works instantly against the empty dev
table and, against a populated production table, either fails on existing rows or locks the table for
the duration.

**Detect:** `ADD COLUMN` with `NOT NULL` and no `server_default`/backfill; `CREATE INDEX` without
`CONCURRENTLY` on a large table; type changes or `NOT NULL` constraints applied directly; no
consideration of existing-row count.

**Fix:** require the non-locking, existing-data-safe form:

> This runs against a populated, live table. Add a required column as nullable-with-default, backfill
> existing rows (in batches if large), then set `NOT NULL`. Build indexes with `CREATE INDEX
> CONCURRENTLY`. Assume the table has millions of rows and is serving traffic — never use the form that
> locks or fails on existing data.

### GPT: rename/drop in one step (breaks the deploy window)

GPT-family models implement a rename or restructure as a single in-place migration (rename the column,
drop the old one) because that's the minimal change that reaches the desired end state — ignoring that
old code runs simultaneously during the rollout and that dropping data is irreversible.

**Detect:** a migration that renames/drops/retypes a column the application still reads; a drop in the
same migration/deploy as the code change; no expand/contract staging; no dual-write/backfill step.

**Fix:** require expand/contract:

> This is a breaking change on a live system — old and new code run together during the deploy. Stage it
> as expand/contract: add the new shape, make the code write to both, backfill, switch reads, and drop
> the old shape only in a later deploy once nothing reads it. Never rename or drop a column the running
> code still uses in a single step.

### Cursor: omitting the rollback and not testing against data

Editing to produce the `up`, Cursor tends to leave `downgrade` empty (or wrong) and to validate the
migration only by running it against the local, near-empty dev database — so the rollback doesn't work
when needed and the locking/data behavior against production is never observed.

**Detect:** empty or unimplemented `downgrade`; a `down` that doesn't actually revert the `up`; a
migration tested only against an empty local DB; no note of behavior on a large/populated table.

**Fix:** require a tested rollback and realistic testing:

> Write a `downgrade` that actually reverts this migration and test it (apply then roll back). Test the
> migration against a copy with realistic data volume, not just an empty dev database, so locking and
> existing-row behavior are observed. If the change is genuinely irreversible (a drop), say so explicitly
> rather than leaving an empty `down`.

## Best Practices

**Every schema change is a versioned, reviewed, reversible migration.** Through the tool (Alembic),
ordered, applied identically in every environment, with a tested `down`. No manual production `ALTER`,
ever.

**Design every migration for the live deploy window.** Assume old and new code run simultaneously and
the table is full and busy — the migration must be compatible with the running code and must not lock or
fail on existing data.

**Stage breaking changes with expand/contract.** Add new, dual-write, backfill, switch reads, drop old —
each step separately deployable and compatible with the code live at that moment. Never change in place
on a live system.

**Use non-locking operations and stage destructive drops.** `CONCURRENTLY` for indexes,
nullable-then-backfill-then-`NOT NULL` for required columns, `NOT VALID`/`VALIDATE` for constraints; and
drop data only after confirming disuse, in a separate later migration.

**Test migrations against realistic data and document the rules.** Run migrations (and their rollbacks)
against a production-sized copy, and document the team's migration rules (reversible, non-locking, staged,
expand/contract) in `CLAUDE.md`/the migrations README so the safe patterns are the default.

## Anti-Patterns

**The Manual ALTER.** Schema changed by hand in production — unversioned, unreviewed, unrepeatable. The
tell: a change in prod that isn't in a migration file.

**The Locking Migration.** A `NOT NULL` add or non-concurrent index that locks a busy table under load. The
tell: `CREATE INDEX` (not concurrent) or `ADD COLUMN NOT NULL` on a large table.

**The In-Place Break.** A rename/drop/retype in one step that breaks old code during the rollout. The tell:
a migration altering a column the running code still uses, with no expand/contract.

**The Premature Drop.** Dropping data before confirming nothing needs it — irreversible loss. The tell: a
`drop_column`/`drop_table` in the same deploy as the code change, or with no disuse check.

**The Rollback-Less Migration.** No `down`, or an untested one, so a bad structural change can't be
reverted. The tell: empty `downgrade` functions; a `down` never executed.

**The Empty-DB Test.** A migration validated only against a near-empty dev database, hiding its
locking/data behavior. The tell: no testing against realistic data volume.

## Decision Tree

"I need to change the production schema — how do I do it safely?"

```
Is it a migration file (versioned, reviewed, reversible)?
└──► if not, STOP. Never ALTER production by hand. Write a migration.

Does the change break code that's currently running (rename/drop/retype/required-field)?
├── YES ──► EXPAND/CONTRACT across deploys:
│            1. add the new shape (nullable/additive)          ← compatible with old code
│            2. make the code write to BOTH old and new        ← deploy
│            3. backfill existing rows (in batches)            ← migration
│            4. switch reads to the new shape                  ← deploy
│            5. drop the old shape                             ← later migration, after disuse confirmed
└── NO (purely additive) ──► still make it non-locking (below).

Does the operation LOCK a big/busy table?
├── CREATE INDEX ──────────► CREATE INDEX CONCURRENTLY
├── ADD COLUMN NOT NULL ───► nullable + default → backfill → SET NOT NULL
├── ADD FK / CHECK ────────► ADD ... NOT VALID → VALIDATE (separate step)
└── type change ───────────► stage it; avoid a full-table rewrite under load

Is it destructive (drops data)?
└──► irreversible. Ship the code that stops using it FIRST, confirm disuse, THEN drop in a later migration.

Always: write and TEST the `down`. Test against a production-SIZED copy, not an empty dev DB.
```

## Checklist

### Implementation Checklist

- [ ] Every schema change is a versioned migration through the tool (no manual production `ALTER`).
- [ ] Each migration has a tested `downgrade` (or is explicitly documented as irreversible).
- [ ] Required columns are added nullable-with-default, backfilled, then set `NOT NULL` — not `NOT NULL` directly.
- [ ] Indexes on large tables are built `CONCURRENTLY`.
- [ ] Breaking changes are staged as expand/contract across deploys; nothing is renamed/dropped/retyped in place.
- [ ] Destructive drops happen only after the code stops using the data and disuse is confirmed.

### Architecture Checklist

- [ ] Migrations are ordered and applied identically across dev → staging → production.
- [ ] Every migration is designed for the deploy window (old and new code coexisting).
- [ ] Locking operations use their non-locking forms on any non-trivial table.
- [ ] Migrations are tested against a production-sized dataset, not just an empty dev DB.
- [ ] The team's migration rules (reversible, non-locking, staged, expand/contract) are documented in `CLAUDE.md`/README.

### Code Review Checklist

- [ ] No manual/undocumented schema change outside a migration (watch AI diffs).
- [ ] No `NOT NULL` add without an existing-row plan; no non-concurrent index on a big table.
- [ ] No in-place rename/drop/retype of a column the running code still uses.
- [ ] No destructive drop in the same deploy as the code change / without a disuse check.
- [ ] No migration without a tested rollback (or an explicit irreversibility note).

### Deployment Checklist

- [ ] The migration was applied and rolled back successfully against a staging copy with realistic data.
- [ ] Migration run time and lock impact on large tables are known and acceptable for the deploy window.
- [ ] The deploy order (migration vs code) is correct for the expand/contract step being shipped.
- [ ] A database backup / point-in-time recovery is confirmed available before a destructive or risky migration.
- [ ] Long-running migrations (backfills, concurrent index builds) are monitored to completion.

## Exercises

**1. Do a safe expand/contract.** Split `customers.name` into `first_name`/`last_name` as a staged
expand/contract: the add-nullable migration, the batched backfill, the (simulated) code deploys, and the
final drop — each step compatible with the code running at the time. The artifact is the ordered migrations
and a note on why each step is deploy-window-safe.

**2. Add a required column without downtime.** Add a `NOT NULL currency` to a populated `invoices` table.
First write the naive `ADD COLUMN NOT NULL` and show it fails/locks; then do it safely
(nullable+default → backfill → `NOT NULL`). The artifact is the before/after migrations and the observed
failure of the naive one.

**3. Test a rollback against data.** Write a migration with a real `downgrade`, apply it against a copy with
realistic data, then roll it back and confirm the schema (and, where possible, the data) is restored.
Identify one change in your schema that is genuinely irreversible and explain why. The artifact is the
tested up/down and the irreversibility analysis.

## Further Reading

- **Alembic documentation — "Operation Reference" and "Cookbook"** (alembic.sqlalchemy.org) — the tooling
  for versioned, reversible migrations introduced in Stage 3, Chapter 02; the operations used throughout
  this chapter.
- **PostgreSQL documentation — "ALTER TABLE" and "CREATE INDEX" (locking notes)** (postgresql.org/docs) —
  exactly which operations take which locks and how `CONCURRENTLY`/`NOT VALID` avoid them; the basis for the
  non-locking patterns.
- **"Online DDL / zero-downtime migrations" writeups (e.g., GitLab, Stripe, PlanetScale engineering blogs)**
  — real-world expand/contract playbooks and safe-migration checklists from teams operating large live
  databases; the production discipline behind this chapter.
- **Stage 7 — DevOps (CI/CD)** — where migrations run in the deploy pipeline and how migration ordering
  relative to code deploys is enforced; the operational context for the deploy-window reasoning here.
</content>

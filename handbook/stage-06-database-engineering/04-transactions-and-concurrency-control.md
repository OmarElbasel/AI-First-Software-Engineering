# Transactions & Concurrency Control

## Introduction

The moment two users touch the same data at the same time, correctness stops being
obvious. One request reads a balance, another updates it, and the interleaving decides
whether the final number is right or silently wrong. Transactions are the database's
answer to this: a way to group operations so they happen all-or-nothing and don't
corrupt each other under concurrency. This chapter is about using them correctly —
understanding the ACID guarantees, drawing transaction boundaries in the right places,
choosing an isolation level that matches the risk, and avoiding the concurrency bugs
(lost updates, race conditions, deadlocks) that only appear under real load and are
nearly impossible to reproduce after the fact.

The single most important idea: **a transaction turns a sequence of operations into a
single atomic, consistent, isolated, durable unit — and the hard, non-obvious part is
isolation, because the database's default isolation level does not protect you from
every concurrency anomaly.** Atomicity (all-or-nothing) and durability (committed data
survives a crash) are intuitive and the database handles them. Isolation — how
concurrent transactions are prevented from interfering — is where the subtle bugs live,
because there are *degrees* of it. PostgreSQL's default (`READ COMMITTED`) prevents some
anomalies but permits others, including the classic **lost update**: two transactions
read the same value, both modify it, and one silently overwrites the other. Believing
"I used a transaction, so I'm safe" without understanding isolation is the root of most
concurrency corruption.

The judgment this chapter teaches: draw transaction **boundaries** correctly (wrap the
operations that must be atomic together — no more, no less), choose the **isolation
level** or locking strategy that matches the correctness requirement (row locks with
`SELECT ... FOR UPDATE`, or `SERIALIZABLE` for genuine invariants), keep transactions
**short** (long ones hold locks and cause contention), and handle the failure modes
(**deadlocks** and serialization failures need retry logic, not a crash). This is the
correctness-under-concurrency foundation that the Stage 3 backend relied on
implicitly; here we make it explicit, because AI-generated code is especially prone to
concurrency bugs that pass every single-user test.

## Why It Matters

Concurrency bugs are the most dangerous class of database bug: they corrupt data, they
appear only under load, and they're nearly impossible to reproduce or debug after the
fact:

- **The lost update silently corrupts data.** Two requests read a value, both compute a
  new one from it, both write — and one overwrites the other with no error. A credit is
  applied twice, an inventory count is wrong, two invoices get the same number. Nothing
  crashes; the data is just wrong, and you find out from a customer.
- **The default isolation level doesn't protect you.** `READ COMMITTED` (Postgres's
  default) prevents dirty reads but permits lost updates and other anomalies. Code that
  "uses a transaction" is not automatically correct under concurrency — the isolation
  level and locking decide, and the default is not the strongest.
- **These bugs don't show up in testing.** Single-user tests, demos, and code review all
  pass, because the bug requires a specific interleaving of concurrent requests. It
  surfaces in production under load, intermittently, and can't be reproduced on demand —
  the worst possible debugging profile.
- **Wrong transaction boundaries break atomicity.** Operations that must succeed or fail
  together (debit one account, credit another) split across separate transactions can
  leave the system half-updated after a failure — money debited but not credited.
  Boundaries drawn too wide hold locks too long and cause contention.
- **Deadlocks and serialization failures are normal, not exceptional.** Under
  concurrency the database will sometimes abort a transaction to break a deadlock or
  preserve serializability. Code that doesn't retry these treats a routine, recoverable
  event as a fatal error — a request fails that should have quietly succeeded on retry.
- **Long transactions poison throughput.** A transaction held open (doing slow work,
  calling an external API, waiting on the user) holds its locks the whole time, blocking
  everyone who needs those rows. One long transaction can stall a whole table.

Get it right — correct boundaries, an isolation level or lock matched to the invariant,
short transactions, and retry on deadlock/serialization failure — and the system stays
correct and performant under concurrent load. Get it wrong and you get silent data
corruption that no test catches and that you can't reproduce, plus contention and failed
requests under load.

The AI dimension: assistants write code that is correct for one user and wrong under
concurrency. They implement read-modify-write without locking (the lost update), assume a
transaction is sufficient without considering isolation, draw boundaries incorrectly, and
never add deadlock retry — because their training rewards single-threaded correctness and
concurrency is invisible in a demo.

## Mental Model

ACID with isolation as the hard part, the lost-update trap, and the tools that prevent it:

```
   A TRANSACTION = one ATOMIC unit:  BEGIN ... COMMIT (or ROLLBACK)
     A — atomicity:   all-or-nothing (a failure rolls the whole thing back)
     C — consistency: constraints hold before and after
     I — ISOLATION:   concurrent txns don't corrupt each other  ← the hard, subtle part
     D — durability:   once committed, it survives a crash

   ISOLATION HAS DEGREES — the default doesn't stop everything:
     READ UNCOMMITTED → READ COMMITTED (PG default) → REPEATABLE READ → SERIALIZABLE
        weaker/faster ─────────────────────────────────── stronger/safer
     READ COMMITTED permits the LOST UPDATE:

   THE LOST UPDATE (classic silent corruption)
     T1: read balance=100 ─┐                 both read 100, both write from 100:
     T2: read balance=100 ─┘                 T1 writes 100+50=150, T2 writes 100+30=130
     T1: write 150                           final = 130.  T1's +50 is LOST. no error.
     T2: write 130

   THE FIXES (match to the invariant)
     row lock:   SELECT ... FOR UPDATE   ← lock the row; the 2nd reader waits. simplest correct fix.
     atomic op:  UPDATE ... SET balance = balance + 50   ← let the DB do the arithmetic
     isolation:  SERIALIZABLE            ← DB detects the conflict, aborts one → RETRY
     optimistic: version column, check-and-set          ← retry on version mismatch

   ALSO:  keep txns SHORT (locks held = contention) · RETRY deadlocks & serialization failures (normal)
```

Four principles carry the chapter:

**A transaction is an atomic unit; wrap what must succeed or fail together.** Group the
operations that form one logical change (debit + credit, create invoice + its line items)
into one transaction so a failure rolls back all of it. Draw the boundary around exactly
that — not less (broken atomicity), not more (locks held too long).

**Isolation is the hard part, and the default isn't the strongest.** Understand what your
isolation level does and doesn't prevent. `READ COMMITTED` permits lost updates; correctness
under concurrency requires choosing a stronger level or an explicit lock for the invariant
you're protecting. "I used a transaction" is not "I'm safe."

**Prevent the lost update explicitly.** For read-modify-write on shared data, use a row lock
(`SELECT ... FOR UPDATE`), an atomic in-database update (`SET x = x + n`), `SERIALIZABLE`
isolation, or optimistic version-checking. Pick one deliberately; doing nothing is the bug.

**Keep transactions short and retry the recoverable failures.** Long transactions hold locks
and cause contention — never do slow work or external calls inside one. Deadlocks and
serialization failures are normal under concurrency; retry them rather than surfacing them as
errors.

A working definition:

> **A transaction makes a group of operations atomic, consistent, isolated, and durable, and
> the subtle part is isolation: the default level (`READ COMMITTED`) permits anomalies like the
> lost update, so correctness under concurrency requires deliberately drawing transaction
> boundaries around what must be atomic, choosing a locking/isolation strategy that matches the
> invariant, keeping transactions short, and retrying deadlocks and serialization failures.
> "I used a transaction" is not automatically "I'm correct under load."**

## Production Example

**Invoicely** has several operations that are correct single-user and corrupt under
concurrency without care. The clearest is **generating the next invoice number per
customer**: read the customer's current max number, add one, insert. Under concurrency, two
requests read the same max, both compute the same next number, and both insert — a lost
update producing duplicate invoice numbers (and violating the `UNIQUE(customer_id, number)`
constraint from Chapter 01, so one request also errors). The fix is a lock or an atomic
strategy, not hope.

A second case: **recording a payment and updating the invoice status**. Inserting the payment
row and flipping the invoice to `paid` must be atomic — if the process dies between them, a
payment exists against an invoice still marked unpaid (or vice versa). These two writes belong
in one transaction with a boundary drawn around exactly them. A third: **applying account
credit** across concurrent requests — the textbook lost-update scenario, fixed with
`SELECT ... FOR UPDATE` on the balance row or an atomic `UPDATE ... SET balance = balance +
amount`.

And Invoicely must handle the failure modes: under load, concurrent status updates on related
rows can deadlock, and `SERIALIZABLE` transactions can abort with a serialization failure —
both need a retry loop so a routine, recoverable event doesn't fail a user's request.

In this chapter we implement these with correct boundaries and locking: the payment+status
atomic transaction, the invoice-number generation protected against lost updates, credit
application with row locking, and a deadlock/serialization retry wrapper. We contrast each with
the assistant-default version (read-modify-write with no lock, split boundaries, no retry) that
passes every single-user test and corrupts under concurrent load.

## Folder Structure

```
api/app/
├── db/
│   └── transaction.py         # transaction context manager + deadlock/serialization RETRY wrapper
├── services/
│   ├── payments.py            # record-payment-and-mark-paid: ONE transaction, correct boundary
│   ├── invoice_numbers.py     # next-number-per-customer: lost-update-safe (lock / atomic / sequence)
│   └── credits.py             # apply account credit: SELECT ... FOR UPDATE (row lock)
└── db/
    └── isolation.md           # documents which operations need which isolation/locking and WHY
```

Why this shape: transaction boundaries live in the **service layer** (Stage 2), because a
transaction wraps a logical business operation, not a single query — so `payments.py` owns the
atomic payment+status change as one unit. The retry logic for deadlocks and serialization
failures is centralized in `transaction.py` so every concurrency-sensitive operation gets it
without re-implementing it (and forgetting it). `isolation.md` documents *which operations need
which locking/isolation and why*, because concurrency requirements are invisible in the code and
the reasoning must be recorded or the next change silently breaks it. The structure encodes the
chapter's claim: correctness under concurrency is a deliberate, documented, service-level concern.

## Implementation

**An atomic transaction with a correct boundary (`payments.py`).** Insert the payment and update
the status as one unit — both commit or both roll back. The boundary is exactly these two writes.

```python
def record_payment(session: Session, invoice_id: int, amount: Decimal) -> None:
    # ONE transaction: payment insert + status update are atomic. A crash between them rolls BOTH back.
    with session.begin():                              # BEGIN ... COMMIT/ROLLBACK
        session.add(Payment(invoice_id=invoice_id, amount=amount))
        session.execute(
            update(Invoice).where(Invoice.id == invoice_id).values(status="paid")
        )
    # No half-state possible: never a payment against an unpaid invoice, or a paid invoice with no payment.
```

**Preventing the lost update — row lock (`credits.py`).** Read-modify-write on a shared balance,
made safe with `SELECT ... FOR UPDATE`: the second concurrent transaction waits for the first to
commit before it reads.

```python
def apply_credit(session: Session, account_id: int, amount: Decimal) -> None:
    with session.begin():
        # FOR UPDATE locks the row: a concurrent apply_credit BLOCKS here until we commit.
        account = session.execute(
            select(Account).where(Account.id == account_id).with_for_update()
        ).scalar_one()
        account.balance += amount                      # safe: no other txn can read this row meanwhile
    # Without with_for_update(), two concurrent calls both read the old balance → LOST UPDATE.
```

**The even-simpler fix — atomic in-database update.** When the change is expressible as
arithmetic, let the database do it atomically; no application-side read-modify-write, no lock
needed.

```python
def apply_credit_atomic(session: Session, account_id: int, amount: Decimal) -> None:
    with session.begin():
        # The DB computes balance = balance + amount atomically. No read-modify-write race exists.
        session.execute(
            update(Account).where(Account.id == account_id).values(balance=Account.balance + amount)
        )
```

**Deadlock / serialization retry (`transaction.py`).** Concurrency-recoverable failures are
normal; retry them with backoff instead of failing the request.

```python
from psycopg import errors
import time

def run_with_retry(operation, *, retries: int = 3):
    for attempt in range(retries):
        try:
            return operation()
        except (errors.DeadlockDetected, errors.SerializationFailure):
            if attempt == retries - 1:
                raise                                   # give up after N tries
            time.sleep(0.05 * (2 ** attempt))           # backoff, then retry the WHOLE transaction
    # Deadlocks/serialization failures are expected under concurrency — retry, don't crash.
```

**The invoice-number case — the sequence-or-lock decision.** Generating a per-customer number is
the lost-update trap; the robust fix is a lock (or, where gap-free isn't required, a sequence).

```python
def next_invoice_number(session: Session, customer_id: int) -> str:
    with session.begin():
        # Lock the customer row so concurrent number-generation for the SAME customer serializes.
        session.execute(select(Customer).where(Customer.id == customer_id).with_for_update()).scalar_one()
        current_max = session.scalar(
            select(func.coalesce(func.max(Invoice.number_seq), 0)).where(Invoice.customer_id == customer_id)
        )
        return f"INV-{current_max + 1:05d}"             # no two concurrent requests can compute the same number
```

**The anti-pattern — the assistant default.**

```python
# ANTI-PATTERN: read-modify-write with no lock, split boundary, no retry — corrupts under load
def apply_credit_bad(session, account_id, amount):
    account = session.get(Account, account_id)         # 1) read (no lock) — concurrent req reads same value
    account.balance = account.balance + amount          # 2) modify in app
    session.commit()                                    #    → LOST UPDATE: one write silently overwrites the other

def record_payment_bad(session, invoice_id, amount):
    session.add(Payment(invoice_id=invoice_id, amount=amount)); session.commit()  # boundary 1
    invoice = session.get(Invoice, invoice_id); invoice.status = "paid"; session.commit()  # boundary 2
    # 3) split into TWO transactions — a crash between them leaves a payment against an unpaid invoice
# 4) no deadlock/serialization retry anywhere → routine recoverable failures become user-facing errors
```

The difference is the whole chapter: the good versions draw the boundary around what must be
atomic, prevent the lost update with a lock or atomic update, and retry recoverable failures. The
bad versions do read-modify-write with no protection (silent corruption), split atomic operations
across transactions (half-states on failure), and treat deadlocks as fatal — all invisible in
single-user testing and corrupting under the concurrent load of production.

## Engineering Decisions

Five decisions define concurrency correctness.

### Where do you draw the transaction boundary?

**Options:** (1) one transaction per query; (2) one transaction per logical operation; (3) one big
transaction per request.

**Trade-offs:** per-query transactions break atomicity for multi-step operations (a failure leaves
a half-state). Per-logical-operation wraps exactly the writes that must succeed or fail together —
the correct grain. One giant per-request transaction holds locks across unrelated work, causing
contention and long lock-hold times.

**Recommendation:** draw the boundary around one logical operation — the set of writes that must be
atomic (payment + status; invoice + line items) — and no wider. Not per-query (breaks atomicity),
not per-request (over-broad locking). The boundary is a design decision about what must be all-or-
nothing.

### How do you prevent the lost update?

**Options:** (1) nothing (rely on the default); (2) pessimistic row lock (`FOR UPDATE`); (3) atomic
in-DB update (`SET x = x + n`); (4) `SERIALIZABLE`; (5) optimistic version-checking.

**Trade-offs:** nothing means the lost update happens under concurrency. A row lock is simple and
correct — concurrent writers serialize on the row — at the cost of blocking (and possible
deadlocks). An atomic update is the simplest fix when the change is arithmetic (no read-modify-write
at all). `SERIALIZABLE` protects arbitrary invariants but aborts conflicting transactions (needs
retry). Optimistic version-checking avoids locks and retries on conflict (good under low
contention).

**Recommendation:** prefer the atomic in-DB update when the change is expressible as arithmetic
(no race exists); use a row lock (`FOR UPDATE`) for read-modify-write where you must read then decide;
use `SERIALIZABLE` (with retry) for complex invariants a single lock can't express; use optimistic
concurrency where contention is low and locks are undesirable. Choose deliberately — doing nothing is
the bug.

### What isolation level do you use?

**Options:** (1) `READ COMMITTED` (default); (2) `REPEATABLE READ`; (3) `SERIALIZABLE`.

**Trade-offs:** `READ COMMITTED` is the fast default and permits lost updates and non-repeatable
reads. `REPEATABLE READ` (Postgres: snapshot isolation) prevents non-repeatable reads and, in PG,
detects some write conflicts, at some cost. `SERIALIZABLE` guarantees transactions behave as if run
one at a time — the strongest correctness — at the cost of aborting conflicting transactions (which
you must retry) and some throughput.

**Recommendation:** keep `READ COMMITTED` as the default for most operations (with explicit locks/
atomic updates for the specific invariants that need them), and raise to `SERIALIZABLE` for operations
whose correctness depends on a complex multi-row invariant that locks can't cleanly express — always
with retry logic. Match the isolation level to the risk; don't assume the default is strong enough,
and don't make everything `SERIALIZABLE`.

### How long should a transaction be held open?

**Options:** (1) as long as convenient; (2) as short as possible (only the atomic writes); (3) do
slow/external work outside the transaction.

**Trade-offs:** long transactions hold their locks the entire time, blocking every other transaction
that needs those rows — one slow transaction can stall a table. Short transactions minimize lock-hold
time and contention. Doing slow work (an external API call, heavy computation, waiting on user input)
*inside* a transaction is the classic contention bug.

**Recommendation:** keep transactions as short as possible — do slow work, external calls, and user
waits *outside* the transaction, and open the transaction only around the atomic writes. Never hold a
transaction open across a network call to a payment provider or an email service (Stage 3). Short
transactions are the difference between healthy and contended under load.

### How do you handle deadlocks and serialization failures?

**Options:** (1) let them propagate as errors; (2) retry with backoff; (3) design to avoid them
entirely.

**Trade-offs:** propagating them fails user requests for a routine, recoverable event. Retrying with
backoff turns them into transparent, successful operations at the cost of a retry wrapper and
idempotent transactions. Designing to avoid them (consistent lock ordering, short transactions,
atomic updates) reduces their frequency but can't eliminate serialization failures under
`SERIALIZABLE`.

**Recommendation:** retry deadlocks and serialization failures with backoff (the whole transaction),
and reduce their frequency with consistent lock ordering and short transactions. Treat them as
expected under concurrency, not as bugs — the retry is part of correct concurrent code, not an
afterthought.

## Trade-offs

Concurrency control trades throughput and complexity for correctness under load — and the failure of
skipping it is invisible until it corrupts data.

**Isolation trades throughput for correctness.** Stronger isolation (`SERIALIZABLE`) and locking
prevent more anomalies and reduce concurrency (blocking, aborts-and-retries). Weaker isolation is
faster and permits corruption. The right level is per-operation: pay for the strength where an
invariant demands it, use the cheap default with targeted locks elsewhere.

**Locking trades concurrency for a simple correctness guarantee.** A row lock (`FOR UPDATE`) makes
read-modify-write trivially correct by serializing writers on the row, at the cost of blocking and
possible deadlocks. It's the simplest correct fix for the lost update; the concurrency cost is local
to the contended rows and usually acceptable.

**Short transactions trade some code convenience for throughput.** Keeping slow/external work outside
the transaction means structuring code so the transaction wraps only the atomic writes — slightly less
convenient than one big block, and the difference between a table that scales under load and one that
serializes on a held lock. Always worth it.

**Retry logic trades a little complexity for resilience.** A deadlock/serialization retry wrapper adds
code and requires idempotent transactions, and it converts routine recoverable failures into
successful operations. For any concurrent write path it's not optional — without it, load produces
spurious user-facing errors.

## Common Mistakes

**The lost update.** Read-modify-write on shared data with no lock/atomic update, so concurrent writes
overwrite each other silently. Fix: `FOR UPDATE`, atomic `SET x = x + n`, `SERIALIZABLE`, or optimistic
versioning.

**Assuming a transaction is enough.** Believing "I wrapped it in a transaction" protects against all
concurrency, ignoring isolation. Fix: understand what your isolation level permits; add locks for the
invariant.

**Wrong boundaries.** Splitting atomic operations across transactions (half-states on failure) or one
giant transaction (over-broad locking). Fix: one transaction per logical operation.

**Long transactions.** Slow work or external calls held inside a transaction, blocking others. Fix: do
slow/external work outside; keep the transaction to the atomic writes.

**No deadlock/serialization retry.** Treating routine recoverable failures as fatal errors. Fix: retry
with backoff; make transactions idempotent.

**Everything SERIALIZABLE (or nothing).** Over-using the strongest isolation (throughput collapse) or
never strengthening it (corruption). Fix: match isolation/locking to each operation's invariant.

## AI Mistakes

Concurrency is the area where assistant code is most confidently wrong, because single-threaded
correctness — which their training optimizes — looks identical to concurrent correctness in a demo.
Review every shared-data write for what happens under a concurrent interleaving.

### Claude Code: read-modify-write with no locking (the lost update)

Asked to update a value based on its current state (increment a balance, compute the next number,
decrement inventory), Claude Code writes the natural read-then-write-in-application code with no lock or
atomic update. It's correct for one user and produces lost updates under concurrency — silent
corruption no test catches.

**Detect:** read a row → modify a field in Python/JS → write it back, on data multiple requests can
touch; a "next number"/counter computed by reading the max and adding one; inventory/balance decrements
without a lock or atomic update; no `FOR UPDATE` and no `SET x = x + n`.

**Fix:** require lost-update protection:

> This is a read-modify-write on shared data and will lose updates under concurrency. Either make it an
> atomic in-database update (`SET balance = balance + :amount`) or lock the row first
> (`SELECT ... FOR UPDATE`), or use `SERIALIZABLE` with retry. Don't read a value into the application,
> modify it, and write it back for data that concurrent requests can also modify.

### GPT: wrong transaction boundaries and no retry

GPT-family models tend to draw boundaries at the wrong grain — separate transactions for operations
that must be atomic, or an over-broad transaction — and omit deadlock/serialization retry, because the
happy single-user path never exercises either problem.

**Detect:** multi-step operations that must be atomic split across multiple `commit()`s; a transaction
spanning slow work or an external API call; no retry for deadlocks/serialization failures on concurrent
write paths; a half-completed state possible if the process dies mid-operation.

**Fix:** require correct boundaries and retry:

> Wrap the operations that must succeed or fail together in ONE transaction (not several), and keep slow
> or external work outside it. Add deadlock/serialization-failure retry (with backoff) around concurrent
> write operations — these are normal under load and must be retried, not surfaced as errors.

### Cursor: ignoring isolation and testing only single-user

Editing one operation, Cursor assumes the default isolation level is sufficient and validates against
single-user behavior, so it ships code whose correctness silently depends on an interleaving that never
occurs in the edit-site test.

**Detect:** correctness that depends on isolation the default (`READ COMMITTED`) doesn't provide; no
consideration of concurrent interleavings; an invariant across multiple rows enforced without
`SERIALIZABLE` or appropriate locking; "works" verified only single-user.

**Fix:** require concurrency-aware reasoning:

> Consider the concurrent case explicitly: what happens if two requests run this at the same time? The
> default `READ COMMITTED` permits lost updates and doesn't protect multi-row invariants — use an
> appropriate lock or `SERIALIZABLE` (with retry) for the invariant this protects. Correctness must hold
> under concurrent interleavings, not just single-user.

## Best Practices

**Wrap logical operations in one transaction with the right boundary.** Group exactly the writes that
must be atomic; keep the boundary tight (not per-query, not per-request). Correct boundaries are what
make atomicity real.

**Prevent lost updates explicitly.** For read-modify-write on shared data, use an atomic in-DB update,
a row lock (`FOR UPDATE`), `SERIALIZABLE` with retry, or optimistic versioning — chosen deliberately.
Never rely on the default to protect concurrent modifications.

**Match isolation to the invariant.** `READ COMMITTED` plus targeted locks for most operations;
`SERIALIZABLE` (with retry) for complex multi-row invariants. Don't assume the default is strong enough
or make everything the strongest level.

**Keep transactions short; retry the recoverable failures.** Do slow and external work outside the
transaction, and wrap concurrent write paths in deadlock/serialization retry with backoff. Short
transactions plus retry are what keep the system correct *and* performant under load.

**Document and test concurrency requirements.** Record which operations need which locking/isolation and
why, test under concurrent load (not just single-user), and document the conventions in `CLAUDE.md` so
assistants stop shipping single-threaded-correct code.

## Anti-Patterns

**The Lost Update.** Read-modify-write on shared data with no lock or atomic update. The tell: read a
row, change a field in app code, write it back, for data concurrent requests touch.

**The False Safety.** "It's in a transaction, so it's safe," ignoring that the isolation level permits
the anomaly. The tell: a transaction with no lock protecting a concurrency-sensitive invariant.

**The Split Atom.** Operations that must be atomic spread across multiple transactions, allowing
half-states on failure. The tell: multiple `commit()`s for one logical operation.

**The Long Transaction.** Slow work or an external call held inside a transaction, blocking others. The
tell: an API/email/compute call between `BEGIN` and `COMMIT`.

**The Unretried Deadlock.** Deadlocks/serialization failures propagated as fatal errors. The tell: a
concurrent write path with no retry wrapper.

## Decision Tree

"I'm writing an operation that touches shared data — how do I make it correct under concurrency?"

```
Do multiple writes need to succeed or fail together?
└──► YES ──► ONE transaction around exactly those writes (not per-query, not per-request).
             Keep slow/external work OUTSIDE it.

Is this a read-modify-write on data concurrent requests can touch?
├── change is arithmetic (balance + n, count - 1) ──► ATOMIC UPDATE: SET x = x + n. Done, no race.
├── must read then decide ─────────────────────────► lock the row: SELECT ... FOR UPDATE.
├── complex multi-row invariant ───────────────────► SERIALIZABLE isolation + RETRY.
└── low contention, want no locks ─────────────────► optimistic: version column, check-and-set, retry.

Is the default READ COMMITTED enough for this invariant?
└──► it permits LOST UPDATES and doesn't protect multi-row invariants. If correctness depends on more,
     use a lock or SERIALIZABLE. Don't assume "in a transaction" = safe.

Concurrent write path?
└──► wrap it in deadlock/serialization-failure RETRY (backoff). Make the transaction idempotent.

Always: transactions SHORT · test under CONCURRENT load, not just single-user.
```

## Checklist

### Implementation Checklist

- [ ] Each logical operation that must be atomic is wrapped in one transaction with a tight boundary.
- [ ] Read-modify-write on shared data uses an atomic update, `FOR UPDATE` lock, `SERIALIZABLE`, or optimistic versioning.
- [ ] Isolation level is chosen per operation to match its invariant (not blindly the default, not all `SERIALIZABLE`).
- [ ] Transactions are short; slow work and external calls happen outside them.
- [ ] Concurrent write paths retry deadlocks and serialization failures with backoff and are idempotent.
- [ ] Concurrency-sensitive operations are tested under concurrent load, not only single-user.

### Architecture Checklist

- [ ] Transaction boundaries live in the service layer, around logical operations.
- [ ] The locking/isolation strategy for each concurrency-sensitive operation is documented and justified.
- [ ] Retry logic is centralized so every concurrent write path gets it.
- [ ] Lock ordering is consistent to reduce deadlocks.
- [ ] Concurrency conventions are documented in `CLAUDE.md`.

### Code Review Checklist

- [ ] No read-modify-write on shared data without lost-update protection (watch AI diffs closely).
- [ ] No atomic operation split across multiple transactions.
- [ ] No external/slow call inside a transaction.
- [ ] No concurrent write path without deadlock/serialization retry.
- [ ] No correctness that silently depends on an isolation level the default doesn't provide.

### Deployment Checklist

- [ ] Statement/transaction timeouts are configured to bound long-held locks.
- [ ] Deadlock and lock-wait monitoring is in place (they're expected; watch their rate).
- [ ] Connection-pool and transaction settings are tuned for the concurrency the workload produces.

## Exercises

**1. Reproduce and fix a lost update.** Write `apply_credit` as an unlocked read-modify-write, then run
two concurrent calls (two connections) and show the final balance is wrong. Fix it three ways — atomic
update, `FOR UPDATE`, and `SERIALIZABLE` + retry — and note the trade-offs. The artifact is the
reproduction and the three fixes.

**2. Draw the right boundary.** Take a "record payment and mark invoice paid" implemented as two separate
transactions, simulate a failure between them to produce a half-state, then combine them into one
transaction and show the half-state is now impossible. The artifact is the before/after and the
demonstrated failure.

**3. Add deadlock retry.** Create a scenario where two transactions acquire locks in opposite orders and
deadlock, observe the error, then add a retry wrapper (and/or consistent lock ordering) so the operations
succeed. The artifact is the deadlock reproduction and the retry that resolves it.

## Further Reading

- **PostgreSQL documentation — "Transaction Isolation" and "Explicit Locking"** (postgresql.org/docs) —
  exactly what each isolation level permits and how row locks (`FOR UPDATE`) and `SERIALIZABLE` behave; the
  authoritative source for this chapter's core decisions.
- **"Designing Data-Intensive Applications" by Martin Kleppmann, Ch. 7 (Transactions)** — the clearest
  explanation of isolation levels, the lost update, write skew, and serializability; essential background
  for the judgment here.
- **PostgreSQL documentation — "Concurrency Control"** (postgresql.org/docs) — how PostgreSQL's MVCC works
  and how serialization failures and deadlocks arise and are reported; the basis for the retry strategy.
- **Stage 3, Chapter 06 — Background Jobs** — where long-running and external work belongs (outside the
  transaction); this chapter's "keep transactions short, do slow work elsewhere" points there.
</content>

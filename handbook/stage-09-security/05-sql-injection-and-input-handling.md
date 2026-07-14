# SQL Injection & Input Handling

## Introduction

SQL injection is the oldest serious web vulnerability that still, decades later, breaches
production systems every year. Its mechanism is simple: when user input is concatenated into a SQL
string, the input can *stop being data and start being code* — a value like `'; DROP TABLE
invoices; --` closes the intended string and appends the attacker's own SQL, which the database
dutifully executes. The fix is equally simple and has been known for as long: never build queries
by concatenation; use parameterized queries, where the database receives the SQL structure and the
values separately and can never confuse one for the other. And yet the vulnerability persists,
because there are just enough cases the simple rule doesn't obviously cover — dynamic sort columns,
`LIKE` searches, `IN` lists, raw-SQL escape hatches — that developers (and assistants) reach for
string-building exactly where it's most dangerous.

This chapter is broader than SQL injection alone, because injection is one instance of a general
class: **untrusted input treated as code in some interpreter.** The same failure shape produces
NoSQL injection, OS command injection, LDAP injection, and (in the next chapter) XSS, where the
interpreter is the browser. The defense is always the same shape too: keep data as data, use the
interpreter's parameterization/escaping rather than building strings, and validate input at the
boundary. So the chapter teaches SQL injection concretely and deeply — because it's the canonical
case and the one this handbook's stack most directly faces — and then generalizes to input handling
as a discipline: validation vs sanitization vs escaping (three different things that get conflated),
allowlisting over blocklisting, and where in the request lifecycle each belongs.

The boundary with other stages: how SQLAlchemy executes parameterized queries and how the database
plans them is **Stage 6**; this chapter uses those mechanics to *defend*, not to explain the engine.
Building the API and its validation layer was **Stage 3**; this chapter hardens that layer against a
hostile sender. XSS — injection into the browser — is **Chapter 06**, the sibling to this one.

## Why It Matters

SQL injection is simultaneously one of the most severe and one of the most completely preventable
vulnerabilities, which is exactly why shipping it is inexcusable and why it keeps happening.

- **A single injectable query can compromise the entire database.** Not one row, not one table —
  injection often yields read access to everything (other tenants' data, password hashes, tokens),
  write access (tampering, privilege escalation), and sometimes command execution on the database
  host. The blast radius of one concatenated query is the whole datastore. For a multi-tenant SaaS
  like Invoicely, that is every customer's financial data at once.
- **It's invisible to functional testing and easy to introduce.** The injectable query returns the
  right rows for normal input; the vulnerability only appears when someone sends a crafted value.
  One f-string in one endpoint, added in a hurry for a "dynamic" filter, opens the hole — and the
  feature works perfectly in every demo and test that uses ordinary input.
- **Parameterization solves it completely — but only where it's used.** Parameterized queries make
  injection *structurally impossible* for values: the database never parses the value as SQL. The
  catch is that the protection is per-query — one hand-built query anywhere in the codebase is the
  hole, no matter how many parameterized ones surround it. Security here is about the *weakest*
  query, not the average.
- **The cases parameterization doesn't cover are where people go wrong.** You can't bind a *column
  name*, a *table name*, or a *sort direction* as a parameter — they're SQL structure, not values.
  So dynamic `ORDER BY`, dynamic table selection, and similar require a different defense
  (allowlisting), and this is precisely where developers fall back to string-building and reintroduce
  injection.
- **Input handling is a broader discipline than any one injection.** Validation (is this input
  well-formed and expected?), escaping (making input safe for a specific interpreter), and
  sanitization (removing dangerous content) are three distinct controls that solve different
  problems, and conflating them — "I validated it, so it's safe to concatenate" — is a common
  reasoning error. Validation is not an injection defense; parameterization is.
- **The AI dimension is significant.** Assistants reach for string-formatted SQL exactly in the
  tricky cases (dynamic sorting, search, `IN` lists, raw-SQL escape hatches), use the ORM's raw
  execution with f-strings, and trust validated input as if validation made concatenation safe.
  Each produces a working feature with an injectable query, and each passes every test that doesn't
  send an attack.

## Mental Model

Injection is a *confusion between data and code*. The defense is to make that confusion structurally
impossible — the interpreter must receive structure and data separately, so a value can never be
promoted to code.

```
   THE INJECTION MECHANISM (value becomes code)
     query = "SELECT * FROM invoices WHERE id = '" + user_input + "'"
     user_input = "x' OR '1'='1"          → returns every row (auth bypass / data dump)
     user_input = "x'; DROP TABLE ...; --" → executes the attacker's statement
     the value ESCAPED the data context and became SQL. that's the whole bug.

   THE FIX — PARAMETERIZED QUERIES (structure and data travel separately)
     db.execute("SELECT * FROM invoices WHERE id = :id", {"id": user_input})
     the DB parses the SQL ONCE with :id as a placeholder, then binds the value.
     the value is NEVER parsed as SQL. injection is structurally impossible.  ← for VALUES

   WHAT PARAMETERS CAN'T BIND (structure, not values) → needs ALLOWLISTING
     column names, table names, ORDER BY direction, JOINs
     sort = {"created": "created_at", "total": "amount"}[user_sort]   # map to KNOWN-safe identifiers
     dir  = "DESC" if user_dir == "desc" else "ASC"                   # choose from fixed set
     NEVER: f"ORDER BY {user_sort} {user_dir}"                        # identifier injection

   THE INPUT-HANDLING TOOLBOX (three DIFFERENT controls — don't conflate)
     VALIDATE   is it well-formed & expected? (type, range, shape) — reject at the boundary.
                NOT an injection defense; a good-input filter. (Stage 3 schemas)
     PARAMETERIZE / ESCAPE  make it safe for a SPECIFIC interpreter (SQL, shell, HTML).
                the actual injection defense, per interpreter.
     SANITIZE   remove dangerous content where you MUST accept rich input (HTML → Ch 06).
                last resort; hard to get right; allowlist-based.

   THE GENERAL RULE (applies to SQL, NoSQL, shell, LDAP, HTML...)
     ALLOWLIST > blocklist   define what's ALLOWED, reject the rest — never enumerate the bad.
```

Three principles carry the chapter:

**Keep data as data — let the interpreter separate structure from values.** Parameterized queries
for SQL, argument arrays (not shell strings) for commands, the driver's typed operations for NoSQL.
Never build an interpreter's input by string concatenation with untrusted data. This is the one
defense that makes injection *impossible* rather than *filtered*.

**For the structural parts you can't parameterize, allowlist.** Column names, sort fields, table
choices — map untrusted input to a fixed set of known-safe values. Never pass user input into query
structure, even "validated" — validation checks shape, not safety, and an allowlist is the only
thing that guarantees a safe identifier.

**Validate at the boundary, but never mistake validation for an injection defense.** Validation
rejects malformed and unexpected input early and is essential — but a perfectly valid string can
still be an injection payload. Validation reduces attack surface; parameterization closes the hole.
You need both, and you must not substitute one for the other.

A working definition:

> **SQL injection (and its NoSQL/command/LDAP siblings) is untrusted input being interpreted as
> code. The defense is parameterization — sending structure and values separately so a value can
> never become code — for everything that is a value, and allowlisting for the structural parts
> (identifiers, sort fields) that can't be parameterized. Validation at the boundary is a necessary
> complement, never a substitute.**

## Production Example

**Invoicely** exposes exactly the surfaces where injection lives: an invoice search (filter by
customer name, status, date range), a sortable, paginated invoice list (sort by any of several
columns, either direction), a reporting endpoint that builds a query from several optional filters,
and — inevitably — one or two places where a developer dropped to raw SQL for a query the ORM made
awkward. This chapter hardens all of them and shows the injectable version of each.

The ordinary value filters (customer name, status, date range) go through SQLAlchemy's parameterized
queries — the values are bound, never concatenated, so `'; DROP TABLE invoices; --` in the search
box is just a customer name that matches nothing. The sortable list is the interesting case: sort
column and direction are *structure*, not values, so they can't be bound. Invoicely maps the
client's `sort=total&dir=desc` through an allowlist — `{"total": Invoice.amount, "created":
Invoice.created_at}` and a two-value direction — so an attacker sending `sort=(SELECT ...)` gets a
`422`, not a query. The multi-filter report builds its `WHERE` clause dynamically but *composes
parameterized fragments*, never string-concatenated ones. And the raw-SQL escape hatch uses bound
parameters (`text("... WHERE account_id = :aid")`), because dropping to raw SQL is not license to
drop parameterization.

On top of the query layer, Stage 3's validation schemas do their job at the boundary: status must be
one of the known enum values, dates must parse, page sizes are bounded — malformed input is rejected
before it reaches a query at all, shrinking the attack surface. But the chapter is explicit that this
validation is *defense in depth, not the injection defense*: even if a bad value slipped through,
parameterization and allowlisting mean it still can't become SQL. We build each of these and contrast
them with the assistant-default versions: the f-string `ORDER BY`, the raw `execute(f"...")` filter,
the hand-concatenated search — each a working feature with a hole.

## Folder Structure

```
modules/invoices/
├── _repository.py        # all queries: parameterized values; NO string-built SQL
├── _sorting.py           # the ORDER BY allowlist: client keys -> known-safe columns/directions
├── _filters.py           # dynamic WHERE built from PARAMETERIZED fragments, never concatenation
├── schemas.py            # Stage 3 validation: enums, ranges, shapes — boundary rejection (defense in depth)
core/
├── db.py                 # session/engine; the ONE place raw SQL is allowed, always with bound params
tests/
└── security/
    └── test_injection.py     # ' OR '1'='1, ;DROP, ORDER BY injection, UNION SELECT — must all be inert
```

Why this shape:

- **`_repository.py` as the single query layer** means there's one place to audit for string-built
  SQL — injection can't hide in a query scattered into a route handler if queries live here.
- **`_sorting.py`** exists because dynamic sort is the number-one place parameterization doesn't
  apply and string-building sneaks in; isolating the allowlist makes "map to a known column" the
  only way to sort, and a new sort option a deliberate allowlist entry.
- **`_filters.py`** builds dynamic `WHERE` clauses by composing parameterized fragments, so "the
  query changes based on which filters are present" never becomes "the query is a concatenated
  string."
- **`schemas.py`** keeps validation at the boundary (Stage 3) as the outer ring — rejecting
  malformed input early — while the repository's parameterization is the inner ring that holds even
  if validation is bypassed.
- **`tests/security/test_injection.py`** fires real payloads at every surface and asserts they're
  inert (no extra rows, no error, no execution) — the proof the hardening works, kept green in CI.

## Implementation

**Parameterized value queries (`_repository.py`): the default that makes injection impossible.**
With an ORM, this is simply *using the ORM as intended* — the bound parameters are automatic.

```python
def search_invoices(db, account_id: int, name: str | None, status: str | None):
    query = select(Invoice).where(Invoice.account_id == account_id)   # tenant scope, bound
    if name:
        query = query.where(Invoice.customer_name.ilike(f"%{name}%"))  # value is BOUND, not concatenated
    if status:
        query = query.where(Invoice.status == status)                  # bound
    return db.execute(query).scalars().all()
```

The `ilike(f"%{name}%")` looks like string-building but isn't: the f-string only assembles the
*pattern value*, which SQLAlchemy binds as a parameter — the database receives `%...%` as data. (The
one nuance: `%` and `_` in `name` are LIKE wildcards; escape them if exact-substring matching
matters. That's a correctness detail, not an injection hole — the value can't become SQL.)

**The sort allowlist (`_sorting.py`): the case parameters can't cover.** Identifiers are structure;
map them, never interpolate them.

```python
SORT_COLUMNS = {"created": Invoice.created_at, "total": Invoice.amount, "due": Invoice.due_date}

def apply_sort(query, sort_key: str, direction: str):
    column = SORT_COLUMNS.get(sort_key)          # unknown key -> None -> reject (allowlist)
    if column is None:
        raise ValidationError("invalid sort field")
    order = column.desc() if direction == "desc" else column.asc()   # fixed two-value choice
    return query.order_by(order)
    # NEVER: query.order_by(text(f"{sort_key} {direction}"))  ← identifier injection
```

An attacker sending `sort=(SELECT password FROM users)` hits the allowlist miss and gets a
validation error. The client's sort keys are a *contract*, decoupled from column names, and adding a
sortable field is a deliberate one-line allowlist entry — the secure path is the only path.

**Dynamic filters as parameterized fragments (`_filters.py`): flexible query, no concatenation.**

```python
def build_report_query(account_id, filters: ReportFilters):
    query = select(Invoice).where(Invoice.account_id == account_id)
    if filters.min_total is not None:
        query = query.where(Invoice.amount >= filters.min_total)   # each fragment: bound value
    if filters.customer_id is not None:
        query = query.where(Invoice.customer_id == filters.customer_id)
    if filters.statuses:
        query = query.where(Invoice.status.in_(filters.statuses))  # IN-list: bound, not joined by hand
    return query
```

"The query depends on which filters are present" is handled by *composing* clauses, each carrying a
bound value — the `IN` list in particular is built by the ORM's `in_()`, never by string-joining the
values (the classic `IN (` + `,`.join(ids) + `)` injection).

**The raw-SQL escape hatch, done safely (`core/db.py`): raw is fine; unparameterized is not.**

```python
db.execute(
    text("SELECT count(*) FROM invoices WHERE account_id = :aid AND status = :status"),
    {"aid": account_id, "status": status},        # bound — text() is not an excuse to concatenate
)
```

Dropping to raw SQL for a query the ORM makes awkward is a legitimate engineering choice; dropping
parameterization is not. `text()` with bound parameters is exactly as safe as the ORM.

**The attack tests (`tests/security/test_injection.py`): prove the payloads are inert.**

```python
@pytest.mark.parametrize("payload", ["x' OR '1'='1", "'; DROP TABLE invoices; --",
                                     "' UNION SELECT password FROM users --"])
def test_search_payloads_are_inert(client, payload):
    resp = client.get(f"/api/v1/invoices?name={quote(payload)}")
    assert resp.status_code == 200
    assert resp.json()["items"] == []           # treated as a literal name that matches nothing

def test_order_by_injection_is_rejected(client):
    assert client.get("/api/v1/invoices?sort=(SELECT+1)&dir=asc").status_code == 422
```

These are the deliverable: an injection defense you can't demonstrate defeating a real payload is a
belief. The suite fires the canonical attacks at every surface and asserts nothing leaks, nothing
executes, and structural injection is rejected.

## Engineering Decisions

Five decisions define an injection-safe data layer.

### ORM, query builder, or raw SQL?

**Options:** (1) an ORM (SQLAlchemy) for most queries; (2) a query builder; (3) raw SQL strings.

**Trade-offs:** an ORM parameterizes by default — the safe path is the default path, and you have to
work to introduce injection. A query builder is similar with more explicit SQL. Raw SQL strings give
full control and full responsibility: safe *only* if every value is bound, and the place injection
most often enters because concatenation is right there. The security difference isn't that raw SQL
*can't* be safe — it's that safe-by-default beats safe-if-you-remember.

**Recommendation:** default to the ORM's parameterized queries; they make injection structurally
hard to write. Drop to raw SQL (`text()`) when the ORM genuinely obstructs a query — but always with
bound parameters, never with interpolation, and confined to the data layer where it can be reviewed.
The goal is that the easy path is the safe path.

### How is dynamic sorting/filtering handled — the un-parameterizable part?

**Options:** (1) interpolate the user's column/direction into the SQL; (2) allowlist client keys to
known-safe columns; (3) forbid dynamic sorting entirely.

**Trade-offs:** interpolation is identity injection — the one place the "just parameterize" advice
doesn't apply, and the hole opens. Allowlisting maps a fixed set of client-facing keys to actual
columns, decoupling the API from the schema and guaranteeing a safe identifier. Forbidding dynamic
sort avoids the problem and constrains the product.

**Recommendation:** allowlist. A dictionary from client sort keys to known columns and a fixed
direction choice — an unknown key is a validation error. This is the canonical fix for the one case
parameterization can't cover, and it doubles as a clean API contract. Never interpolate an
identifier from user input, validated or not.

### Where does input validation live, and what is it responsible for?

**Options:** (1) validate at the API boundary with schemas (Stage 3); (2) validate in the data
layer; (3) rely on parameterization alone with no validation.

**Trade-offs:** boundary validation (Pydantic/Stage 3) rejects malformed input early, documents the
contract, and shrinks attack surface — but is *not* an injection defense (a valid string can be a
payload). Data-layer validation is a redundant inner check. No validation leans entirely on
parameterization, which stops SQL injection but lets malformed and abusive input flow deep into the
system.

**Recommendation:** validate at the boundary as defense in depth (types, ranges, enums, shapes) *and*
parameterize in the data layer as the actual injection defense — the two are complementary rings,
not alternatives. Explicitly reject the reasoning "it's validated, so I can concatenate it": that
sentence is how injection ships.

### Allowlist or blocklist for input filtering?

**Options:** (1) allowlist — define what's permitted, reject everything else; (2) blocklist — try to
strip or reject known-bad patterns (`'`, `DROP`, `--`, `;`).

**Trade-offs:** allowlisting is bounded and safe — you enumerate the finite set of acceptable inputs.
Blocklisting is an unwinnable arms race: attackers have endless encodings, comment tricks, and
casing variations, and a blocklist that misses one is bypassed. Worse, blocklists give false
confidence and often break legitimate input (the customer named `O'Brien`).

**Recommendation:** allowlist everywhere it applies — enum values, sort keys, known formats — and
rely on parameterization for the value cases where any content must be accepted. Never write a SQL
blocklist that strips quotes or keywords; it's both insecure and buggy. Escaping/parameterization,
not keyword filtering, is the injection defense.

### How do you defend the whole injection family, not just SQL?

**Options:** (1) address SQL only; (2) apply the same data-as-data principle across every interpreter
(NoSQL, shell, LDAP, HTML).

**Trade-offs:** focusing on SQL leaves the siblings open — a system with perfect SQL parameterization
can still have command injection in a shell-out or NoSQL injection in a Mongo query built from a
request body. Treating them as one class (untrusted input into an interpreter → parameterize/escape,
never concatenate) closes them uniformly.

**Recommendation:** apply the principle everywhere an interpreter meets untrusted input: parameterized
DB queries, argument arrays for subprocess calls (never a shell string), the driver's typed
operations for NoSQL, and context-aware escaping for HTML (Chapter 06). One mental model — data stays
data — covers the whole family.

## Trade-offs

**Parameterization costs nothing and there is no real trade — which is why injection is inexcusable.**
Unlike most security controls, the safe path (parameterized queries) is not slower, not more complex,
and often *simpler* than the unsafe one. The only "cost" is not reaching for string-building in the
few awkward cases — and those have clean allowlist answers. There is no performance or maintainability
argument for concatenated SQL.

**Allowlisting dynamic structure trades a little flexibility for safety and a cleaner contract.**
Mapping client sort/filter keys to known columns means adding a sortable field is a deliberate code
change, not automatic. That "limitation" is a feature: it decouples your API from your schema and
makes the safe identifier guaranteed. The flexibility you give up is flexibility you didn't want to
expose.

**Boundary validation trades a bit of upfront schema work for early rejection and smaller surface.**
Writing validation schemas (Stage 3) is effort, and it doesn't stop injection by itself. What it buys
is rejecting malformed input before it travels deep, clearer contracts, and defense in depth — worth
it, as long as no one mistakes it for the injection defense.

**Strict input handling can occasionally reject unusual-but-valid input.** An over-tight allowlist or
format check can block a legitimate edge case (an international name, an unusual but valid value). The
mitigation is validating *shape and category* generously while parameterizing *content* — you rarely
need to restrict content when parameterization makes any content safe.

## Common Mistakes

**Building queries by string concatenation or f-strings.** `f"... WHERE id = '{user_id}'"` — the
textbook hole. Fix: parameterized queries / ORM bindings for every value, always.

**Interpolating identifiers for dynamic sort or filter.** `f"ORDER BY {col} {dir}"` — identifier
injection, the case parameters can't cover. Fix: allowlist client keys to known-safe columns and a
fixed direction set.

**Using the raw-SQL escape hatch without binding.** `text(f"... = {value}")` or `execute(f"...")` —
dropping to raw SQL and dropping parameterization with it. Fix: `text()` with bound parameters; raw
is fine, unparameterized is not.

**Trusting validation as an injection defense.** "It passed the schema, so I can concatenate it" — a
valid string is still a payload. Fix: validate *and* parameterize; never substitute one for the
other.

**Blocklisting bad characters/keywords.** Stripping `'`, `;`, or `DROP` and calling it safe — bypassable
and breaks `O'Brien`. Fix: allowlist and parameterize; delete the blocklist.

**Ignoring the injection siblings.** Perfect SQL safety with a `os.system(f"convert {filename}")`
command injection or a NoSQL query built from a request body. Fix: apply data-as-data everywhere —
argument arrays for shell, typed operations for NoSQL.

## AI Mistakes

Injection is a domain where assistants write working features with holes, because the string-built
query returns the right rows for ordinary input. Review every query for how it's *built*, not
whether it returns correct results.

### Claude Code: interpolating the identifier for dynamic sorting

Asked for a sortable list endpoint, Claude Code parameterizes the value filters correctly and then
builds the `ORDER BY` from user input by string interpolation — `query.order_by(text(f"{sort_field}
{direction}"))` — because sort columns can't be bound as parameters and interpolation is the obvious
way to make it dynamic. The values are safe; the *identifier* is injectable. An attacker controls
part of the SQL structure, enabling data exfiltration via crafted `ORDER BY` subqueries or blind
techniques. The list sorts perfectly for `sort=total`, so it looks done.

**Detect:** `ORDER BY`, column names, or table names built with f-strings/`.format()`/concatenation
from request input; `text()` containing an interpolated identifier; a sort or filter parameter that
flows into query *structure* rather than a bound value.

**Fix:** allowlist the identifier:

> Sort and filter *columns* cannot be parameterized and must never be interpolated from user input.
> Map the client's sort key through an allowlist to a known-safe column, and choose direction from a
> fixed set. Reject unknown keys with a 422. Add a test that `sort=(SELECT 1)` is rejected, not
> executed.

### GPT: the raw-SQL escape hatch with string formatting

GPT-family models, when a query is awkward for the ORM or when asked for "a quick raw query,"
frequently reach for `db.execute(f"SELECT ... WHERE x = '{value}'")` or `text(f"...{value}...")` —
using raw SQL *and* string formatting together, which is the fully injectable classic. It happens
most on search and reporting endpoints where the query feels too dynamic for the ORM. The result
runs and returns correct rows for normal input and is wide open to `' OR '1'='1` and `UNION SELECT`.

**Detect:** `execute`/`text` calls with f-strings or `%`/`.format()` and any request-derived value;
raw SQL anywhere outside the data layer; string-built `WHERE`/`IN` clauses; a "quick query" that
concatenates a value.

**Fix:** bind every value, even in raw SQL:

> Raw SQL is acceptable when the ORM is genuinely awkward, but it must use bound parameters
> (`text("... = :x")`, `{"x": value}`) — never string formatting with request data. Move it into the
> data layer. Add injection tests (`' OR '1'='1`, `; DROP`, `UNION SELECT`) that must return inert.

### Cursor: hand-concatenating a search or IN-list while completing the feature

Completing a search or bulk endpoint, Cursor tends to build the dynamic parts by hand following
whatever local pattern exists: a `WHERE` clause assembled by joining strings, or an `IN` list built
as `"(" + ",".join(str(i) for i in ids) + ")"` interpolated into the query. Each concatenation of a
request value is an injection point, and the `IN`-list case is a classic because the ids "look
numeric" but aren't validated to be. The search works; the concatenation is the hole.

**Detect:** `WHERE`/`IN` clauses built by `join`/concatenation with request data; `IN (` followed by
a formatted list; dynamic query strings assembled piecewise from input; ids interpolated on the
assumption they're integers.

**Fix:** compose parameterized fragments, never strings:

> Build dynamic queries by composing ORM clauses (`.where(...)`, `.in_(list)`), each with bound
> values — never by concatenating or joining request data into a SQL string. `IN` lists go through
> `in_()`, not hand-joined. Add a test sending a non-numeric / injection value in the id list and
> assert it's rejected or inert.

## Best Practices

**Parameterize every value, always.** ORM bindings by default, `text()` with bound parameters when
raw SQL is warranted — never string concatenation or formatting with untrusted data. This is the
whole defense for values, and it's free.

**Allowlist every un-parameterizable identifier.** Sort columns, filter fields, table choices mapped
from a fixed set of client keys to known-safe columns; unknown keys rejected. The canonical fix for
the case parameters can't cover.

**Validate at the boundary as defense in depth.** Types, ranges, enums, and shapes rejected early
(Stage 3 schemas) — shrinking attack surface and documenting the contract, while parameterization
remains the actual injection defense.

**Prefer allowlists to blocklists, everywhere.** Enumerate what's permitted and reject the rest;
never try to strip or block dangerous characters or keywords — it's bypassable and breaks legitimate
input.

**Confine raw SQL to the data layer.** Raw queries live in the repository where they're reviewable,
always parameterized; injection can't hide in a query embedded in a route handler.

**Apply data-as-data to the whole injection family.** Argument arrays for subprocess (never a shell
string), typed operations for NoSQL, context-aware escaping for HTML (Chapter 06) — one principle
across every interpreter.

**Test with real payloads.** A security test per surface firing `' OR '1'='1`, `; DROP`, `UNION
SELECT`, and `ORDER BY` injection, asserting each is inert — kept green in CI.

## Anti-Patterns

**The Concatenated Query.** SQL built by string formatting with request data. The tell: f-strings,
`%`, or `+` assembling a query; `execute(f"...")`; any user value inside quotes in a SQL string.

**The Interpolated Identifier.** Dynamic `ORDER BY`/column/table built from input. The tell:
`text(f"{col} {dir}")`; a sort or field parameter flowing into query structure; no allowlist between
client keys and columns.

**The Unparameterized Escape Hatch.** Raw SQL used as a reason to concatenate. The tell: `text()`
with an interpolated value; "we needed raw SQL here" next to string formatting.

**The Blocklist Filter.** Stripping quotes/keywords as the injection defense. The tell: code removing
`'`, `;`, `--`, or `DROP`; legitimate input like `O'Brien` breaking; false confidence with a
bypassable filter.

**Validation-As-Injection-Defense.** Trusting a validated string enough to concatenate it. The tell:
"it passed the schema" used to justify string-building; validation and parameterization treated as
interchangeable.

**The Forgotten Sibling.** SQL locked down while shell/NoSQL/LDAP injection ships. The tell:
`os.system`/`shell=True` with an interpolated value; a NoSQL query built from a raw request body;
`subprocess` called with a formatted string.

## Decision Tree

"I need to put user input into a query (or another interpreter) — how do I do it safely?"

```
Is the input a VALUE or part of the query STRUCTURE?
├── a VALUE (id, name, amount, status, date, IN-list item)
│     └─► PARAMETERIZE it. ORM binding or text("... = :x", {"x": value}). always.
│         never concatenate/format it into the SQL string. done — injection is impossible.
│
├── STRUCTURE (column name, table, ORDER BY, JOIN, direction)
│     └─► parameters CAN'T bind this. ALLOWLIST:
│         map the client key -> a known-safe column/value; reject unknown keys (422).
│         never interpolate the identifier from input, even if "validated".
│
└── a different interpreter?
      ├── SHELL   ─► argument array (subprocess([...])), never shell=True with a built string.
      ├── NoSQL   ─► the driver's typed query ops, never a query built from a raw request body.
      ├── LDAP    ─► the library's escaping/parameterization.
      └── HTML    ─► context-aware output encoding — Chapter 06.

Across all of them, at the boundary: VALIDATE (type/range/shape, reject malformed) as defense in
depth — but NEVER treat validation as the injection defense. parameterize/escape is the defense.
```

## Checklist

### Implementation Checklist

- [ ] Every query value is parameterized (ORM binding or bound `text()`); no query is built by string concatenation or formatting with request data.
- [ ] Dynamic sort/filter identifiers go through an allowlist mapping client keys to known-safe columns; unknown keys are rejected.
- [ ] `IN` lists and dynamic `WHERE` clauses are composed from parameterized fragments, never hand-joined strings.
- [ ] Raw SQL (`text()`) exists only in the data layer and always uses bound parameters.
- [ ] Boundary validation (types, ranges, enums, shapes) rejects malformed input as defense in depth.
- [ ] Injection tests (`' OR '1'='1`, `; DROP`, `UNION SELECT`, `ORDER BY` injection) exist per surface and assert inert results.

### Architecture Checklist

- [ ] Queries are centralized in a data/repository layer where they can be audited for string-building.
- [ ] The safe path is the default: the ORM's parameterization is the norm and raw SQL is the reviewed exception.
- [ ] Allowlists (sort fields, filter keys) are the API contract, decoupling client keys from schema column names.
- [ ] The injection principle is applied across all interpreters in the system (shell, NoSQL, LDAP), not SQL alone.
- [ ] Validation and parameterization are treated as complementary rings, with parameterization as the authoritative injection defense.

### Code Review Checklist

- [ ] No f-string, `%`, `.format()`, or `+` builds a SQL string from request-derived data.
- [ ] No identifier (column, table, sort, direction) is interpolated from input; each goes through an allowlist.
- [ ] No `text()`/`execute()` contains an interpolated value; every raw query binds its parameters.
- [ ] No blocklist "sanitizer" strips characters/keywords as an injection defense.
- [ ] `subprocess`/`os.system` calls use argument arrays, not shell strings built from input; NoSQL queries aren't built from raw bodies.

### Deployment Checklist

- [ ] The database credential used by the app is least-privilege (scoped to its schema/operations), so a residual injection is contained.
- [ ] Database error messages are not returned to clients (no SQL errors leaking structure — error handling from Stage 3, Chapter 05).
- [ ] A WAF or query-anomaly monitoring is in place as a reinforcing layer (not the primary defense) where the risk justifies it.
- [ ] Static analysis / linters flag string-built SQL in CI so a new concatenated query fails the pipeline.

## Exercises

**1. Exploit, then close, an ORDER BY injection.** Build a sortable list endpoint that interpolates
the sort column from input. Demonstrate an injection through `ORDER BY` (extract data via a crafted
subquery or boolean-blind technique). Then replace it with an allowlist and show the same payload is
rejected with a 422. The artifact is the exploit, the allowlist, and the before/after tests.

**2. Harden a raw-SQL reporting endpoint.** Take (or write) a reporting query built with string
formatting. Fire `' OR '1'='1`, `UNION SELECT`, and a stacked `; DROP` at it and show what leaks or
breaks. Convert it to bound `text()` parameters and an allowlist for any dynamic structure, and show
every payload is now inert. The artifact is the two versions and the payload test suite.

**3. Audit the whole injection family.** Grep your codebase for every interpreter boundary: SQL
string-building, `subprocess`/`os.system` with `shell=True`, NoSQL queries from request bodies, any
`eval`/template rendering of input. For each, classify it safe or vulnerable and fix the vulnerable
ones with the matching data-as-data technique. The artifact is the audit table and the fixes.

**4. Prove validation is not the injection defense.** Take an endpoint with strict boundary
validation but a concatenated query. Construct an input that passes validation *and* injects (a valid
string that's also a payload), demonstrating the gap. Then parameterize the query and show the same
valid-but-hostile input is now harmless. The artifact is the payload that passes validation and the
parameterized fix.

## Further Reading

- **OWASP SQL Injection Prevention Cheat Sheet (cheatsheetseries.owasp.org)** — the definitive
  practical guide: parameterized queries, the identifier-allowlist pattern for the cases parameters
  can't cover, and why blocklisting fails.
- **OWASP Top 10 — A03: Injection (owasp.org/Top10)** — the category this chapter maps to, covering
  the whole injection family (SQL, NoSQL, command, LDAP) under one principle.
- **PortSwigger Web Security Academy — SQL Injection (portswigger.net/web-security)** — hands-on,
  exploit-level labs (UNION, blind, out-of-band) that make concrete what an injectable query actually
  yields an attacker; the best way to internalize the severity.
- **SQLAlchemy documentation — "Using Textual SQL" and parameter binding (docs.sqlalchemy.org)** —
  the correct use of `text()` with bound parameters, the safe form of the raw-SQL escape hatch this
  chapter relies on.
- **Stage 3, Chapter 05 (Error Handling)** and **Chapter 06 — XSS & Content Security** — not leaking
  SQL errors to clients, and the browser-side sibling of injection covered next.

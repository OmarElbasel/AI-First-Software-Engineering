# Security Mindset & the OWASP Top 10

## Introduction

Every other stage of this handbook asked *does the system do what it should?* This stage asks
the opposite question: *what can the system be made to do that it shouldn't?* That inversion is
the security mindset, and it is a different discipline from building. A builder reasons about the
intended user following the intended path; a security engineer reasons about a hostile user
following every path *except* the intended one — changing the ID in the URL, sending the field
you didn't validate, replaying the request you assumed happens once, reading the token you
thought was secret. The code is the same code. The lens is inverted.

This chapter establishes that lens before the rest of the stage applies it. It covers three
things: how to **threat-model** a feature — systematically ask who would attack it, how, and
what they'd gain — before you build it; how to locate **trust boundaries**, the lines in a
system where data crosses from less-trusted to more-trusted and must be checked; and how to read
the **OWASP Top 10**, the industry's consensus list of the vulnerability classes that actually
breach web applications, as a *map of your own codebase* rather than a list to memorize. The Top
10 is the organizing spine of this entire stage: nearly every chapter that follows is a deep
dive into one of its categories.

The reason this comes first, as a mindset chapter rather than a technique chapter, is that
security is not a feature you add — it is a property of how you think while building every
feature. You cannot bolt it on at the end, and you cannot test your way to it after the fact.
The specific techniques in Chapters 02–08 only work if you know *where* to apply them, and
knowing where is what this chapter teaches.

## Why It Matters

Security failures are not a worse kind of bug; they are a different kind of event, and four
properties make them uniquely dangerous.

**They are invisible from the builder's seat.** A functional bug announces itself — a page
errors, a total is wrong, a user complains. A vulnerability does the opposite: the feature works
perfectly for every legitimate user, the demo is flawless, the tests are green, and the system
is simultaneously exploitable. You test as yourself, following the happy path, and the happy path
is exactly the one an attacker ignores. The IDOR that leaks every tenant's invoices (Stage 3,
Chapter 04) is invisible until someone changes a number in a URL; the SQL injection is invisible
until someone sends a quote mark. You will not find these by using the product. You find them
only by attacking it, or by thinking like someone who will.

**The blast radius is categorical, not incremental.** A broken feature inconveniences the users
who hit it. A breach exposes *every* user at once, converts into a legal disclosure obligation,
and — for a SaaS holding other companies' data, like Invoicely — ends the trust the business
runs on. There is no partial credit: "we leaked only the customer table" is still a breach. The
cost of a single security failure can exceed the cost of every functional bug the product will
ever have.

**The adversary is intelligent and adaptive.** Ordinary bugs are found by accident; vulnerabilities
are found by people actively looking, who chain small weaknesses into large compromises, who
automate the search across thousands of targets, and who share techniques. You are not defending
against random noise. You are defending against someone who will do the one thing you didn't
think of — which is why a systematic framework (threat modeling, the Top 10) beats intuition:
it forces you to enumerate what you'd otherwise skip.

**The AI dimension multiplies all three.** Assistants generate code whose *functional*
correctness they can often verify but whose *security* properties they cannot. They produce
string-built SQL that returns the right rows, tokens that authenticate correctly and never
expire, CORS configured to `*` because it "fixed" the browser error, error responses that leak
stack traces. Each passes every functional test. And they produce it at a volume that outpaces
careful human review. In an AI-first workflow the scarce skill is precisely the security lens:
reading generated code and asking not "does it work?" but "what does this let an attacker do?"
That question is what this stage trains.

## Mental Model

Security is reasoning about **trust boundaries** — the lines where data or control crosses from
a less-trusted zone into a more-trusted one — and ensuring every crossing is authenticated,
authorized, and validated. Vulnerabilities live at boundaries that were crossed without a check.

```
  THE TRUST-BOUNDARY MAP OF A REQUEST (each ║ is a boundary; each must check)
                                                                       trust: LOW ──────────► HIGH
   [ attacker / internet ] ║ [ CDN/edge ] ║ [ your app: routes→services→ORM ] ║ [ database ]
        anyone, anything      rate limit,     authN: who are you? (Ch 02-03)      parameterized
        hostile by default    WAF, TLS        authZ: may you? (Stage 3 Ch04)      queries (Ch 05)
                                              validate: is this input safe?
                                              encode on the way OUT (Ch 06)

   THE FIVE QUESTIONS AT EVERY BOUNDARY
     1. AUTHENTICATION  who is this? can the claim of identity be forged/stolen/replayed?
     2. AUTHORIZATION   may THIS identity do THIS to THIS resource? (default: no)
     3. INPUT           is this data treated as data, never as code/query/markup?
     4. OUTPUT          is data encoded for the context it's rendered into?
     5. RATE/ABUSE      what happens if this is sent a million times? (Ch 08)

   THREAT MODELING A FEATURE (before building) — one pass of STRIDE, in plain words:
     Spoofing      can someone pretend to be another user/service?
     Tampering     can someone alter data in transit or at rest?
     Repudiation   can someone deny doing something, with no audit trail?
     Info leak     can someone read data they shouldn't? (the most common; IDOR lives here)
     Denial        can someone make it unavailable? (Ch 08)
     Elevation     can a normal user gain admin / cross-tenant power?
```

Three principles carry the whole stage:

**Never trust input — and "input" is broader than you think.** Every byte that crosses a trust
boundary from a lower-trust zone is hostile until validated: request bodies, query strings,
headers, cookies, file uploads, JWT claims, OAuth callback parameters, and — critically — data
read back from your *own* database that a user put there earlier (stored XSS is your database
attacking your users). The boundary, not the source's familiarity, decides whether a check is
required.

**Defense in depth: no single control is the whole defense.** Real systems assume any one layer
can fail and add another behind it. Parameterized queries *and* input validation *and* least-privilege
database credentials; short-lived tokens *and* revocation *and* HTTPS-only cookies. A single
control is a single point of failure, and the attacker's whole job is finding the one you forgot.

**Fail closed, and make the secure path the only path.** When something is ambiguous — an unknown
role, a missing check, an unexpected input — deny. Better still, structure the code so the
insecure option doesn't exist: an ORM that parameterizes by default, a base query scoped to the
tenant so "forgetting" the filter is impossible, a template engine that escapes by default. The
strongest security is the kind a tired engineer (or an assistant) cannot accidentally skip.

A working definition:

> **The security mindset is the discipline of reasoning about a system as an adversary would:
> identifying every trust boundary, assuming all input crossing it is hostile, and verifying that
> each crossing is authenticated, authorized, validated, and rate-limited — with layered controls
> so that no single failure becomes a breach. The OWASP Top 10 is the map of where those crossings
> are most often left unchecked.**

## Real-World Scenario

Invoicely ships a feature that, on the surface, is trivial: let a customer download their invoice
as a PDF from a link in an email. The email contains `https://app.invoicely.com/invoices/8412/pdf`.
The builder's version is done in an afternoon: the route loads invoice `8412`, renders it, returns
the PDF. It works. Every test is green. The demo is clean.

A security engineer reads the same feature and sees a trust boundary with no check. The URL
contains a sequential integer, and the endpoint fetches by that integer with no ownership
verification — a textbook **IDOR** (OWASP A01, Broken Access Control). Anyone with a link can
change `8412` to `8411`, `8410`, `8409`, and walk the entire table: every business's invoices,
totals, customer names, and payment references. There is no exploit code, no injection, no stolen
password. It's just a `for` loop over a number. This is the single most common serious web
vulnerability, and it ships constantly because it is invisible to the person who only ever views
their own invoices.

The threat model makes the fixes obvious once the lens is applied. *Spoofing / info leak:* the
link is unauthenticated, so add a check — but which? Requiring login breaks the email use case;
the right answer is a **capability URL** carrying a signed, expiring, single-invoice token, so
the link grants access to *that* invoice and nothing else, and only for a window. *Elevation /
enumeration:* sequential IDs advertise the table's size and let an attacker guess neighbors, so
switch external identifiers to non-sequential UUIDs — defense in depth behind the token, not
instead of it. *Denial:* the PDF render is expensive, so the endpoint needs a rate limit
(Chapter 08) or it's a cheap way to burn the server. *Tampering:* the token must be signed so its
invoice ID can't be edited. One "trivial" feature touches four of the six STRIDE categories, and
the builder's version addressed none of them — not through carelessness, but because building and
attacking are different activities and only one of them was performed.

The lesson that carries through the stage: the vulnerability was not in the PDF library or a
missing patch. It was in *whose perspective the feature was built from*. The code was correct for
the intended user and wide open to every other one. Threat modeling is simply the practice of
spending ten minutes as that other user before you ship — and in an AI-first workflow, of reading
the assistant's afternoon-fast, functionally-perfect implementation with the same suspicion.

## Engineering Decisions

Security judgment is a series of decisions about where to spend a finite defense budget. Five
recur.

### How much threat modeling, and when?

**Options:** (1) none — build and react to reports; (2) lightweight STRIDE pass on every
non-trivial feature at design time; (3) heavyweight formal threat models with data-flow diagrams
and signoff.

**Trade-offs:** none is free until the first breach, then catastrophic. Formal modeling is
thorough and expensive, and its ceremony gets skipped under deadline pressure — a process nobody
follows protects nothing. A lightweight pass — ten minutes walking STRIDE against a feature that
touches auth, money, personal data, or a trust boundary — catches the IDOR and the missing rate
limit at design time, when they're free to fix.

**Recommendation:** lightweight threat modeling, gated by risk. Every feature that crosses a
trust boundary or handles identity, money, or personal data gets a STRIDE pass in its design
notes or PR description. Reserve formal modeling for the genuinely high-stakes surfaces (auth,
payments, tenant isolation). The goal is a habit cheap enough to actually perform, not a document
that impresses an auditor.

### Where do security controls live — edge, application, or data layer?

**Options:** (1) at the edge (WAF, gateway, CDN rules); (2) in the application; (3) at the data
layer (database permissions, row-level security); (4) all three.

**Trade-offs:** edge controls are broad and cheap but coarse — a WAF blocks known injection
patterns but can't know that user A may not read invoice B. Application controls know the business
logic but are only as good as the code. Data-layer controls (least-privilege credentials, row-level
security) are the last line and survive application bugs, but add operational complexity.

**Recommendation:** defense in depth across all three, with the *authoritative* control in the
application where the business logic lives, and the edge and data layers as reinforcing rings — a
WAF is a speed bump, not a wall; row-level security is a backstop, not the plan. Never let the
edge be the *only* control: it can be bypassed, and it doesn't understand your domain.

### Build the security control, or buy/adopt a framework default?

**Options:** (1) hand-roll (custom crypto, custom auth, custom sanitizer); (2) use the
framework's built-in secure defaults; (3) adopt a managed provider (auth-as-a-service, managed
WAF).

**Trade-offs:** hand-rolling security primitives is where catastrophic bugs are born — everyone
who invents their own crypto or HTML sanitizer ships a hole an expert wouldn't. Framework defaults
(SQLAlchemy's parameterization, React's auto-escaping, FastAPI's validation) are battle-tested and
free. Managed providers move whole risk classes off your plate at the cost of money and lock-in.

**Recommendation:** never hand-roll a security primitive; use the ecosystem's vetted default, and
for the highest-stakes surfaces (authentication in particular — Stage 3, Chapter 03) treat "buy
it" as a first-class option. The engineering skill is knowing which wheels must never be
reinvented. Reserve custom work for business-logic authorization, which no library can know for
you.

### When do you invest in security — upfront or after product-market fit?

**Options:** (1) security-first from day one; (2) secure the fundamentals now, harden as you
scale; (3) ship fast, secure later.

**Trade-offs:** full security-first can starve an unproven product of the iteration speed it needs
to survive. "Secure later" reliably becomes "secure never" until the breach, and retrofitting
security into a system built without it is far more expensive than building it in. The fundamentals
— no injection, no broken access control, secrets out of git, auth done right — are cheap when
built in and ruinous to retrofit.

**Recommendation:** a non-negotiable baseline from day one (the fundamentals above — most of them
are *free* given secure framework defaults and a bit of judgment), with deeper hardening (advanced
rate limiting, formal threat models, pen testing) scaled to the data you hold and the users you
have. The mistake is treating *all* security as deferrable; the baseline never is, because its
failures are the ones that end companies.

### Fail open or fail closed?

**Options:** (1) fail open — on error or ambiguity, allow (favor availability); (2) fail closed —
on error or ambiguity, deny (favor security).

**Trade-offs:** failing open keeps the product working when a check errors — and turns every bug
in a security control into a silent bypass. Failing closed means a bug in the auth path locks
people out (visible, fixable) rather than letting everyone in (invisible, breach). Failing closed
can hurt availability and must be applied with judgment — you don't want a flaky permission cache
locking out all users.

**Recommendation:** fail closed for anything touching authentication, authorization, or trust
boundaries — an unknown role denies, a missing check denies, an errored token check rejects. The
asymmetry is the whole argument: a false denial is an annoyance you'll hear about immediately; a
false grant is a breach you'll hear about from an attacker. Pair it with good error handling so
"closed" degrades gracefully rather than taking the system down.

## Trade-offs

Security is bought with other properties; pretending otherwise leads to either theater or
paralysis.

**Security trades against usability, and the balance is a product decision.** Every control adds
friction: MFA, short sessions, rate limits, re-authentication for sensitive actions. Too little
and you're breached; too much and users route around you (password reuse, shared logins, shadow
IT). The right point depends on what you protect — a bank and a photo-sharing app draw the line in
different places. Security engineering is calibrating this deliberately, not maximizing controls.

**Defense in depth trades simplicity and cost for resilience.** Layered controls mean more code,
more configuration, more things to operate and get right. The payoff is that no single failure is
fatal. The discipline is layering where the blast radius justifies it (auth, tenant isolation,
payment) and not gold-plating low-risk surfaces into unmaintainable complexity.

**"Secure by default" trades flexibility for safety — usually worth it.** Framework defaults that
escape, parameterize, and deny force you to *opt out* to do the dangerous thing, which is exactly
the right friction. Occasionally the default is genuinely wrong for a case (you really do need raw
HTML), and then you pay attention precisely because you had to disable a guard. That friction is a
feature.

**Perfect security is unattainable, and chasing it has a cost too.** There is no "secure" system,
only one whose risk is acceptable for what it holds. Effort spent hardening a low-value surface is
effort not spent on the high-value one. Threat modeling exists to *rank* risk so the budget flows
to where a failure actually hurts — the alternative is either negligence or spreading defense so
thin it's absent where it counts.

## Common Mistakes

**Security as a phase, not a property.** Treating it as a pre-launch checklist item rather than a
lens applied to every feature. By launch the vulnerabilities are woven through the codebase and
far more expensive to remove. Fix: threat-model at design time, review for security in every PR.

**Trusting input because of where it came from.** Validating the public API but trusting the
internal one, the admin panel, the mobile client, or data read back from your own database.
Trust is about the *boundary crossed*, not the source's familiarity. Fix: validate at every
boundary; treat your own stored data as untrusted on the way out.

**Confusing authentication with authorization.** Assuming that because a user is logged in, they
may do what they're asking — the exact gap that produces IDOR and privilege escalation. Fix:
check *may this identity do this to this resource* on every state-changing and data-returning
operation, not just *are they logged in*.

**Security through obscurity as the plan.** Relying on a URL being unguessable, an endpoint being
undocumented, or a parameter being hidden. Obscurity can be a thin extra layer; as the actual
control it fails the moment someone looks. Fix: assume the attacker has your source code and knows
every endpoint — then secure it anyway.

**Patching the instance, not the class.** A report says "invoice endpoint leaks other tenants'
data," so you fix *that* endpoint and close the ticket — while the same missing check sits on
twelve other endpoints. Fix: for every vulnerability, ask "where else does this class live?" and
fix the pattern, ideally structurally.

**Leaking information through errors and responses.** Stack traces to the client, "user not found"
vs "wrong password" distinguishing valid accounts, verbose 500s revealing internals. Each is a
free gift to an attacker mapping the system. Fix: generic external errors, detailed internal logs
(Stage 3, Chapter 08), identical responses for enumeration-sensitive paths.

## AI Mistakes

Security is the domain where assistants are most confidently, dangerously wrong, because their
training rewards *working* code and security failures don't stop code from working. Review
AI-generated code for what it *permits*, not just what it does.

### Claude Code: fixing the symptom by disabling the control

Faced with an error caused by a security control — a CORS rejection, a CSRF token mismatch, a TLS
verification failure, a 403 from a permission check — Claude Code frequently makes the error go
away by *removing the guard*: `allow_origins=["*"]` with credentials enabled, `verify=False` on
the HTTP client, CSRF protection disabled, the permission check commented out "to unblock." The
error vanishes, the feature works, and a security boundary is now wide open. It's the most
seductive class of AI fix because it's fast and it demonstrably resolves the symptom.

**Detect:** diffs that *loosen* a security setting to fix a bug — wildcard CORS (especially with
`allow_credentials=True`), `verify=False`, `SECURE=False`, disabled CSRF, removed or commented-out
authorization checks, `# TODO: re-enable`; any commit where the message is a feature fix but the
change is to a security config.

**Fix:** treat "the fix was to disable a control" as a red flag in review, and prompt for the
real cause:

> That CORS error means the browser is enforcing a boundary correctly — do not open it to `*`.
> Configure the specific allowed origin instead. Never fix a security-control error by disabling
> the control; find why the legitimate request is being rejected and fix that.

### GPT: security as a bolt-on feature added at the end

GPT-family models, asked to build a feature, build the functional feature and stop — auth,
validation, rate limiting, and authorization treated as separate follow-up tasks rather than
intrinsic to the feature. The result is a fully working endpoint with no ownership check, no
input validation beyond types, and no rate limit, presented as complete. When security *is* asked
for, it's often appended as a superficial layer (a lone `@login_required`) that satisfies the word
"secure" without closing the actual holes.

**Detect:** feature implementations that are functionally complete but have no authorization
check on data access, no validation of untrusted fields, no rate limit on expensive or
auth-adjacent endpoints; security added only when explicitly requested, and then only at the
coarsest level (authenticated vs not, never authorized-for-this-resource).

**Fix:** make security part of the feature's definition of done, in the prompt:

> Implement this feature including its security properties as part of the same task: authorize
> every data access to the current tenant/owner, validate every untrusted input, and note where a
> rate limit is needed. A feature without its authorization checks is not complete — treat it like
> a missing requirement, not a later enhancement.

### Cursor: patching the reported instance while the vulnerability class survives everywhere

Editing within an open file, Cursor fixes exactly the line the comment or error points at and
nothing beyond it. Told an invoice query is missing a tenant filter, it adds the filter to *that*
query — leaving the identical gap on every other query in the file and the codebase, because its
attention is anchored to the cursor. The reported instance is closed, the ticket looks resolved,
and the vulnerability class is still shipping. Security bugs almost always travel in packs (the
same missing check, copy-pasted), so instance-level fixing is especially damaging here.

**Detect:** a security fix that touches one call site when grep shows the same pattern in many;
PRs that resolve a specific report without a codebase-wide search for siblings; recurring reports
of "the same bug" in different endpoints over successive weeks.

**Fix:** turn every instance into a class, and prefer a structural fix:

> This missing tenant filter is a class of bug, not one bug. Search the codebase for every query
> against this table and every by-ID fetch, fix all of them, and then make it structural — a
> base query scoped to the tenant, or a repository that requires the tenant — so the insecure
> version can't be written again. Report all the sites you found.

## Best Practices

**Threat-model at design time, proportional to risk.** A ten-minute STRIDE pass on any feature
touching identity, money, personal data, or a trust boundary — written into the PR — catches the
IDOR and the missing rate limit while they're free.

**Map every feature to the OWASP Top 10.** Use the list as a checklist against your own code: does
this touch access control (A01)? crypto/secrets (A02)? injection (A03)? Each category has a chapter
in this stage; the Top 10 is the index.

**Never trust input, and never hand-roll a security primitive.** Validate everything crossing a
boundary (including your own stored data on the way out); use the framework's vetted parameterization,
escaping, and validation rather than inventing your own.

**Default deny and fail closed on the security path.** Unknown roles, missing checks, and errored
verifications deny. Structure code so the secure path is the only path — tenant-scoped base
queries, escape-by-default templates — so the insecure option can't be written by accident.

**Layer controls; assume each can fail.** Edge, application, and data-layer defenses reinforcing
each other, with the authoritative check in the application. No single control is the whole
defense.

**Give errors nothing to leak.** Generic external error messages, detailed internal logs, identical
responses on enumeration-sensitive paths (login, password reset), no stack traces past the
boundary.

**Write the security rules into `CLAUDE.md`.** The assistant defaults are known and consistent —
"never widen CORS to fix an error, never `verify=False`, every data access is authorized to the
tenant, every fix checks for sibling instances." Name them before they're taken.

## Anti-Patterns

**Security Theater.** Controls that look protective and check nothing — a validator that rejects
`<script>` but not `<img onerror>`, a rate limit keyed on a spoofable header, a "sanitizer" that
misses half the vectors. The tell: security code that has never been tested against an actual
attack, and confidence out of proportion to coverage.

**The Perimeter Fallacy.** Assuming the network edge (VPN, WAF, "internal only") makes what's
behind it safe, so internal services skip auth and validation. The tell: services that trust any
caller who reached them; "it's not exposed to the internet" as a security argument.

**The Afternoon Feature.** Shipping the builder's version — correct for the intended user, wide
open to every other — because building and attacking were never separated. The tell: features
with no authorization on data access, merged because "it works."

**Security-Through-Obscurity-As-Plan.** Unguessable URLs, hidden endpoints, and undocumented
parameters relied on *as* the control rather than as a thin extra layer. The tell: "nobody knows
that endpoint exists" offered as the reason it's safe.

**The Lonely Patch.** Fixing the one reported instance of a vulnerability while its identical
siblings ship untouched. The tell: the same class of bug reported repeatedly in different places;
fixes that touch one line where the pattern spans the codebase.

**Retrofit Roulette.** Deferring *all* security to post-launch, then discovering the fundamentals
(injection, access control, secrets) are woven through a codebase built without them. The tell:
"we'll do a security pass before launch" with no baseline enforced along the way.

## Decision Tree

"I'm building or reviewing a feature — how do I apply the security lens?"

```
Does this feature cross a trust boundary?
(takes untrusted input · returns data · changes state · handles identity/money/PII)
├── NO ──► minimal: still validate inputs by type; no special ceremony.
└── YES ─► run the pass:

  1. AUTHENTICATION — does it need to know who the caller is?
     └─► yes: is the identity claim un-forgeable, un-replayable, un-stealable?  (Ch 02-03)

  2. AUTHORIZATION — may THIS caller do THIS to THIS resource?
     └─► the #1 miss. Check ownership/tenant on every data access, not just "logged in".
         (Stage 3 Ch 04) — structure it so forgetting the check is impossible.

  3. INPUT — is every untrusted field treated as data, never code/query/markup?
     └─► parameterized queries (Ch 05), validated shapes, size limits.
         remember: your own stored data is untrusted on the way out.

  4. OUTPUT — is data encoded for the context it renders into?
     └─► escape for HTML/JS/URL/SQL context (Ch 06). default-escape frameworks.

  5. ABUSE — what happens under a million requests / automated guessing?
     └─► rate limit auth-adjacent and expensive endpoints (Ch 08).

  6. FAILURE — when a check errors or input is unexpected, what happens?
     └─► fail CLOSED. errors leak nothing to the client.

  Then, for any vuln found: "where else does this class live?" ─► fix the pattern, not the line.
```

## Checklist

### Engineering Judgment Checklist

- [ ] Every feature touching identity, money, personal data, or a trust boundary gets a lightweight STRIDE pass at design time, recorded in the PR.
- [ ] Trust boundaries are identified explicitly, and each crossing has an authentication, authorization, validation, and (where relevant) rate-limiting decision made on purpose.
- [ ] Authorization is checked per-resource (ownership/tenant), not conflated with authentication — and structured so the check can't be forgotten.
- [ ] The security baseline (no injection, no broken access control, secrets out of git, auth done right) is treated as non-negotiable from day one, regardless of product maturity.
- [ ] Security controls fail closed; framework secure-by-default behavior is preserved rather than disabled to resolve errors.
- [ ] Every vulnerability found is treated as a class: the codebase is searched for siblings and the fix is made structural where possible.

### Code Review Checklist

- [ ] No diff loosens a security control (wildcard CORS, `verify=False`, disabled CSRF, removed authorization) to fix a functional error.
- [ ] Every new data-access and state-changing endpoint authorizes the caller to the specific resource, not merely authenticates them.
- [ ] Every untrusted input is validated; queries are parameterized; output is encoded for its rendering context.
- [ ] Error responses and logs leak nothing exploitable (no stack traces to clients, no account-enumeration via differing responses).
- [ ] Security-relevant fixes are checked for sibling instances across the codebase, not applied only at the reported line.
- [ ] Expensive and auth-adjacent endpoints have (or are noted to need) rate limiting.

## Exercises

**1. Threat-model an existing feature.** Take one non-trivial endpoint from Invoicely (or your own
codebase) — ideally one that returns or changes data. Run a full STRIDE pass in writing: for each
of Spoofing, Tampering, Repudiation, Info leak, Denial, Elevation, name a concrete attack against
*this* endpoint and the control that stops it. The artifact is the written model and a list of any
gaps it surfaced. You will almost certainly find at least one.

**2. Hunt the IDOR.** Audit every by-ID data-access route in a codebase for the ownership/tenant
check. For each, answer: what happens if a logged-in user of tenant A requests a resource
belonging to tenant B? Where the check is missing, write the failing test that proves the leak
(you have the Stage 8 harness), fix it, and then propose the *structural* fix that makes the class
impossible. The artifact is the audit table, one proving test, and the structural proposal.

**3. Map your code to the OWASP Top 10.** For each of the ten categories, write one sentence: where
in your system does this risk live, and what currently defends it (or doesn't)? This produces both
a security overview of your codebase and a reading order for the rest of this stage — the
categories with the weakest answers are the chapters to read first.

**4. Review an assistant against the lens.** Ask an AI assistant to build a small feature that
takes user input and returns data (e.g. "an endpoint to search invoices by customer name").
Review the output against the six-question boundary pass in the Decision Tree without prompting for
security. Document every question it failed to answer on its own. This calibrates how much security
judgment you must supply on top of generated code.

## Further Reading

- **OWASP Top 10 (owasp.org/Top10)** — the canonical list this stage is organized around, with
  each category's description, examples, and prevention guidance. Read the current edition's
  overview before the rest of the stage; it is the map.
- **OWASP Application Security Verification Standard (ASVS)** — a far more detailed, level-based
  catalog of security requirements than the Top 10, useful as the checklist when you need depth on
  a specific control.
- **OWASP Cheat Sheet Series (cheatsheetseries.owasp.org)** — concise, practical, per-topic
  guidance (authentication, authorization, input validation, and each Top 10 category) — the
  reference to keep open while implementing the rest of this stage.
- **"Threat Modeling: Designing for Security" by Adam Shostack** — the standard practical treatment
  of STRIDE and threat modeling as an engineering practice, for going deeper than this chapter's
  lightweight pass.
- **Stage 3, Chapters 03–04 — Authentication & Authorization** — how the identity and access-control
  mechanisms this stage attacks are built; the IDOR and tenant-isolation material there is the
  foundation Chapter 01's scenario builds on.

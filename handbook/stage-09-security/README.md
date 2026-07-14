# Stage 9 — Security

Attack the system you built in Stages 3–8, then harden it — learning to think like the
adversary so that the authentication, APIs, frontend, and infrastructure you ship survive
contact with hostile input, hostile clients, and hostile traffic.

Stages 3–8 built Invoicely the way an engineer builds: correct behavior, clean architecture,
tested code. This stage re-examines all of it the way an attacker reads it: every input is a
potential injection, every token a theft target, every endpoint an enumeration surface, every
secret a time bomb in git history. The curriculum topics — JWT, OAuth, secrets, the OWASP
Top 10, SQL injection, XSS, CSRF, rate limiting — are not a list of technologies; they are
the failure classes that actually breach production SaaS products, ordered from identity
(who are you, and can I steal being you?) through injection (can I make your system run my
input?) to abuse (can I grind your system down with sheer volume?). The focus, as always, is
judgment: not memorizing payloads but knowing where each class of vulnerability structurally
lives, which controls actually close it, and what each control costs.

## Why this stage exists

Security failures are categorically different from bugs. A bug loses a request; a breach
loses every customer's data, triggers legal disclosure obligations, and ends trust in the
product permanently. Worse, security failures are invisible in exactly the way bugs aren't:
the vulnerable system works perfectly — logins succeed, invoices render, the demo shines —
right up until someone hostile looks at it. You cannot find these failures by using the
product, only by attacking it. And the AI dimension raises the stakes twice over: assistants
generate plausible-looking code whose security properties they do not verify (string-built
SQL that works, tokens that never expire, CORS opened to `*` to "fix" an error), and they
generate it at a volume no human review fully covers. In an AI-first workflow, security
judgment is the review skill that matters most — it is the difference between shipping fast
and shipping breaches fast.

## Chapters

| # | Chapter | Status |
|---|---------|--------|
| 01 | [Security Mindset & the OWASP Top 10](01-security-mindset-and-owasp-top-10.md) | Done |
| 02 | [JWT Security](02-jwt-security.md) | Done |
| 03 | OAuth 2.0 & OpenID Connect | Planned |
| 04 | Secrets Management | Planned |
| 05 | SQL Injection & Input Handling | Planned |
| 06 | XSS & Content Security | Planned |
| 07 | CSRF, CORS & Browser Security | Planned |
| 08 | Rate Limiting & Abuse Prevention | Planned |

Eight chapters cover the stage's eight curriculum topics in the order an attacker meets your
system. The mindset chapter (Ch 01) comes first because it is the map: threat modeling, trust
boundaries, and the OWASP Top 10 as an index of where everything else in the stage lives.
Identity comes next — JWT hardening (Ch 02) and delegated auth via OAuth/OIDC (Ch 03) —
because stolen identity makes every other defense irrelevant. Secrets (Ch 04) protect the
credentials the system itself holds. Then the injection family: SQL injection (Ch 05) attacks
the backend through input, XSS (Ch 06) attacks users through your frontend, CSRF and
cross-origin abuse (Ch 07) attack users through their own logged-in browsers. Rate limiting
(Ch 08) closes the stage with the abuse class that needs no vulnerability at all — just
volume.

## Boundaries with other stages

- **Building authentication and authorization** — password hashing, token issuance, session
  design, ownership checks, tenant isolation — is **Stage 3, Chapters 03–04**. This stage
  attacks those mechanisms and hardens them; it does not re-teach how to build them.
- **Infrastructure hardening** — SSH configuration, firewalls, non-root containers, TLS
  termination and certificates — is **Stage 7, Chapters 01–04**. This stage covers the
  application layer above it and assumes that foundation is in place.
- **Testing mechanics** are **Stage 8**; the security tests written in this stage (authz
  matrices, injection probes, header assertions) reuse that harness rather than building a
  new one.
- **Database internals** — how parameterized queries execute, indexes, query plans — are
  **Stage 6**; Chapter 05 here covers the attack and the defense, not the engine.
- **AI-assisted security review workflows** in depth are **Stage 10**; this stage builds the
  security judgment that makes those reviews mean something.

## Running example

The stage attacks and hardens **Invoicely** — the invoicing SaaS built across Stages 3–8. A
multi-tenant product that stores other businesses' revenue data, customer lists, and payment
references is a genuinely attractive target, which makes it the right one to defend: JWTs
that survive theft attempts and algorithm confusion, a "Sign in with Google" flow that can't
be turned against its users, secrets that never touch git, invoice queries that treat every
filter as hostile, invoice notes and customer names that render as text instead of executing
as script, state-changing endpoints a hostile page can't trigger, and a login endpoint that
credential-stuffing traffic can't grind through. Same product, adversarial lens.

## Learning outcome

You can threat-model a feature before building it, read the OWASP Top 10 as a map of your own
codebase, harden a JWT implementation against the attacks that actually steal sessions,
integrate OAuth without inheriting its classic vulnerabilities, keep secrets out of code and
git and rotate them when (not if) they leak, make injection structurally impossible rather
than individually patched, defend users against XSS and CSRF with layered browser-side
controls, and put rate limits where abuse actually arrives — so you can review AI-generated
code for the security properties it confidently gets wrong, and ship a SaaS that holds other
people's data without betting the company on nobody ever looking.

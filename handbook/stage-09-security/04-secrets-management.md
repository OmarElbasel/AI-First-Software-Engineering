# Secrets Management

## Introduction

Every system holds secrets: the JWT signing key from Chapter 02, the OAuth client secret and the
encrypted Stripe token from Chapter 03, the database password, the SMTP credentials, the third-party
API keys. A secret is any value whose disclosure lets someone impersonate the system, read its data,
or spend its money. This chapter is about the lifecycle of those values — where they live, how they
reach the code that needs them, how you keep them out of the places they leak from, and what you do
when (not if) one gets out.

Secrets management sounds like an operations concern, but it is a security discipline with its own
failure modes, and most of them are boring in a way that makes them dangerous: a key committed to
git, a credential printed in a log, a `.env` file baked into a Docker image, a signing secret that
has never been rotated in three years and is known to four former employees. None of these is a
clever attack. They are hygiene failures, and they cause a large share of real breaches precisely
because they don't feel like security problems while you're making them.

The chapter covers the full lifecycle: getting secrets *out* of code and git (and what to do about
the ones already in the history), delivering them to running code via environment and secret
managers, encrypting the application-level secrets you must store (like a user's OAuth token),
rotating them on a schedule and on compromise, and detecting leaks before an attacker does. The
boundary with Stage 7 is deliberate: that stage covered *where infrastructure config lives* —
Docker, Compose, CI variables, the mechanics of injecting environment values into containers. This
chapter covers the *security discipline* of secrets as a class: their lifecycle, rotation, leak
response, and the application code that handles them. Where they touch, Stage 7 places the value and
this chapter decides how it's protected and rotated.

## Why It Matters

A leaked secret is not a vulnerability that *might* be exploited through a chain of conditions — it
is a working credential. The exploit is "use it." That directness, plus the number of easy ways
secrets escape, makes this one of the highest-return areas of security hygiene.

- **A committed secret is compromised forever, even after you delete it.** Git history is
  permanent and widely mirrored; removing a key in a later commit leaves it in every clone, fork,
  and the reflog. Public-repo secrets are found by automated scanners within *minutes* of the push.
  The only real remediation for a leaked secret is rotation — deleting it from code does nothing to
  the copy the attacker already has.
- **Secrets leak from mundane places.** Logs (a request dump that includes an `Authorization`
  header), error trackers (an exception with the connection string in it), Docker image layers (a
  `.env` copied in and "removed" in a later layer that still exists), client bundles (a server key
  bundled into frontend JavaScript), CI output, and screenshots. The attack surface for a secret is
  every place its value is written, not just the code.
- **"Set once, never rotated" turns a small leak into a permanent one.** If your system can't
  rotate a secret without a painful manual redeploy, then in practice you never will — so the day a
  secret leaks (a departing employee, a compromised laptop, a logged token) you have no clean
  response. Rotatability is what caps the blast radius of every future leak; it is a design
  property, not an afterthought.
- **Application-level secrets you store need encryption at rest and access control.** Some secrets
  aren't yours — a user's connected-provider OAuth token (Chapter 03), a customer's API key you hold
  for them. These live in your database and must be encrypted with a key *you* manage separately, so
  a database dump isn't a credential dump.
- **Least privilege limits what a leaked secret can do.** A database credential scoped to one
  schema, an API key scoped to one operation, a token with a short TTL — each means a leak is a
  contained incident rather than total compromise. Over-privileged secrets convert any leak into a
  full breach.
- **The AI dimension is a leak amplifier.** Assistants hardcode secrets as convenient defaults,
  echo them into new config files and log statements while completing code, and paste them into
  places (frontend, commit messages, chat) where they persist. And every secret ever pasted into a
  third-party tool should be considered disclosed. The volume and the copy-paste convenience make
  leaks more frequent, not less.

## Mental Model

A secret has a lifecycle, and security means controlling every stage of it — especially keeping the
value out of the durable, copyable, published places, and being able to replace it fast when it
escapes anyway.

```
   THE SECRET LIFECYCLE (control every arrow)
     GENERATE ──► STORE ──► DELIVER ──► USE ──► ROTATE ──► REVOKE
     long, random   secret     env/mount   in RAM,   scheduled +   old value
     never a         manager    at runtime  never     on leak       stops working
     literal         (not git)  (not baked) logged

   WHERE SECRETS MUST NEVER LIVE (the leak surfaces)
     ✗ source code / git history      ✗ logs, error trackers, traces
     ✗ Docker image layers            ✗ client/frontend bundles
     ✗ CI logs / commit messages      ✗ chat, tickets, screenshots, AI prompts
     ✗ hardcoded "default" fallbacks  ✗ config files committed to the repo

   WHERE THEY SHOULD LIVE (by environment)
     local dev  → a .env file that is GITIGNORED (never committed); or a dev vault
     CI         → the platform's encrypted secrets store, masked in logs
     production → a secret manager (Vault, AWS/GCP Secrets Manager, SOPS+KMS),
                  injected as env vars or mounted files at runtime, access-controlled

   APP-LEVEL SECRETS YOU STORE (e.g. a user's OAuth token)
     encrypt at rest with a key from the secret manager (envelope encryption / KMS)
     → a database dump reveals ciphertext, not credentials

   WHEN A SECRET LEAKS — the ONLY real fix:
     ROTATE (generate new, deploy, revoke old). deleting it from code does nothing.
     rotatability must be built BEFORE the leak, or you have no response.
```

Three principles carry the chapter:

**A secret in git is compromised — treat deletion and rotation as different things.** Removing a
secret from the current code prevents *future* exposure of new secrets; it does nothing about the
one already in history. Every leaked secret must be rotated, and the mindset "we took it out" is the
mistake that leaves the live credential live.

**Rotatability is the property that caps every future leak.** Design so any secret can be replaced
without downtime — versioned keys (the `kid` pattern from Chapter 02), a secret manager you can
update and redeploy from, dual-key windows. If rotation is easy, leak response is a routine; if it's
painful, leak response is a crisis you'll defer.

**Least privilege and separation limit blast radius.** Scope every credential to the minimum it
needs, give each environment and service its own distinct secrets (never share prod and staging
keys), and encrypt stored third-party secrets with a separately managed key. A leak should be a
contained incident, and scoping is what contains it.

A working definition:

> **Secrets management is controlling the full lifecycle of every credential — generating strong
> values, storing them outside code and git in a secret manager, delivering them to runtime without
> baking or logging them, encrypting the application-level secrets you must store, and rotating them
> on schedule and on compromise. Its central truths: a secret in git is already compromised, the
> only fix for a leak is rotation, and rotatability must exist before you need it.**

## Production Example

**Invoicely** holds a representative spread of secrets: its JWT signing keys (Chapter 02), Google's
OAuth client secret and each user's encrypted Stripe access token (Chapter 03), the PostgreSQL
password, the SMTP credentials, and a handful of third-party API keys. This chapter puts all of them
under one disciplined lifecycle and fixes the leaks a functional build accumulates.

None of these values appears in code or in git. Locally, developers use a `.env` file that is
gitignored, seeded from a committed `.env.example` that lists the *names* with placeholder values —
so a new developer knows what's needed without any real secret being in the repo. In CI, secrets
live in the platform's encrypted store and are masked in logs. In production, they come from a
secret manager, injected as environment variables at container start (Stage 7), with each secret
scoped to least privilege — the app's database credential can touch only its schema, the Stripe key
is restricted to the operations Invoicely actually performs.

Two things get special handling. The JWT signing keys are *versioned* (`kid`), so rotation is the
zero-downtime procedure from Chapter 02 rather than a flag day. And each user's Stripe token — a
secret that isn't Invoicely's and must be stored — is encrypted at rest using envelope encryption: a
data key from the KMS encrypts the token, so a database dump yields ciphertext, not a pile of
working payment credentials. On top of all this, secret scanning runs in CI and as a pre-commit
hook, so a key accidentally added to a diff is caught before it's pushed, and there's a written
rotation runbook so that "a secret leaked" triggers a rehearsed procedure, not an improvised panic.
In this chapter we build this lifecycle and contrast each piece with the assistant-default version:
the hardcoded fallback key, the committed `.env`, the token stored in plaintext, the secret with no
way to rotate it.

## Folder Structure

```
config/
├── settings.py           # loads secrets from env; FAILS to start if a required one is missing/default
├── .env.example          # COMMITTED: names + placeholders only, never real values
└── .env                  # GITIGNORED: local real values, never committed
core/
├── secrets.py            # thin client over the secret manager (prod) / env (dev) — one access point
├── crypto.py             # envelope encryption for app-level stored secrets (KMS data keys)
modules/auth/
├── _keys.py              # versioned JWT keys (Ch 02) — rotation lives here
└── _link.py              # stores the user's Stripe token via crypto.encrypt (Ch 03)
.github/
└── workflows/ci.yml      # secret scanning gate (gitleaks/trufflehog) — blocks a leaking diff
.pre-commit-config.yaml   # local secret scan before a commit can be made
ROTATION.md               # the runbook: how to rotate each secret, and the leak-response procedure
```

Why this shape:

- **`settings.py` refusing to start on a missing or default secret** turns the most dangerous
  failure mode (a hardcoded fallback silently used in production) into a loud, immediate boot
  failure — the app cannot run on `"changeme"`.
- **`.env.example` committed, `.env` gitignored** gives onboarding the list of required secrets
  without ever putting a real one in the repo — the single most effective anti-leak convention.
- **`core/secrets.py` as one access point** means every secret is read through one place that knows
  where secrets come from per environment, so there's no scattered `os.environ` access to audit and
  no accidental fallback.
- **`core/crypto.py`** isolates envelope encryption so app-level stored secrets (the Stripe token)
  are encrypted consistently with a KMS-managed key, never hand-rolled per call.
- **The CI scan, pre-commit hook, and `ROTATION.md`** make leak *prevention* and leak *response*
  first-class artifacts — the scanner stops most leaks at the door, and the runbook means the ones
  that get through trigger a rehearsed rotation, not a scramble.

## Implementation

**Loading secrets, failing closed on a default (`settings.py`): the app must not run on a
placeholder.** This one guard neutralizes the most common AI leak.

```python
class Settings(BaseSettings):
    jwt_private_key: str            # required; no default
    database_url: str
    stripe_secret_key: str
    kms_key_id: str

    model_config = SettingsConfigDict(env_file=".env")  # local dev only; prod injects env directly

    @field_validator("jwt_private_key", "stripe_secret_key")
    @classmethod
    def reject_placeholders(cls, v: str) -> str:
        if v in {"", "changeme", "secret", "your-secret-key"} or len(v) < 32:
            raise ValueError("refusing to start on a missing or weak secret")  # loud, at boot
        return v
```

**One access point (`core/secrets.py`): environment-aware, no scattered reads.**

```python
def get_secret(name: str) -> str:
    if ENV == "production":
        return secret_manager.get(name)     # Vault / AWS Secrets Manager / GCP — access-controlled
    return os.environ[name]                 # dev/CI: injected env, from a gitignored .env or CI store
```

Everything reads secrets here, so there is exactly one place that knows the source per environment
and exactly one place to audit — no `os.getenv("KEY", "default")` scattered through the codebase,
which is where fallback leaks hide.

**Envelope encryption for stored app-level secrets (`core/crypto.py`): a DB dump yields
ciphertext.** The user's Stripe token isn't Invoicely's to leak; encrypt it with a key Invoicely
manages.

```python
def encrypt_secret(plaintext: str) -> bytes:
    data_key = kms.generate_data_key(key_id=CFG.kms_key_id)   # a fresh key per secret, from KMS
    ciphertext = aesgcm(data_key.plaintext).encrypt(plaintext)
    return pack(data_key.encrypted, ciphertext)               # store the ENCRYPTED data key + ciphertext
    # the plaintext data key exists only in memory, briefly; KMS holds the master key
```

Storing the encrypted data key alongside the ciphertext (envelope encryption) means the master key
never leaves KMS, decryption is an authorized KMS call, and a stolen database has neither the
plaintext token nor the key to get it.

**Rotation as a first-class procedure (`ROTATION.md` + versioned keys).** The JWT keys use
Chapter 02's `kid` versioning, so rotation is: publish the new key, sign with it, keep verifying the
old, then retire the old — zero failed requests. For a credential like the database password:
provision the new one, deploy the app reading it, revoke the old. The runbook writes these down *per
secret* so the response to a leak is a checklist, not an investigation.

**Leak prevention in CI and pre-commit (`ci.yml`, `.pre-commit-config.yaml`).**

```yaml
# ci.yml — a leaking diff fails the build
- name: Scan for secrets
  run: gitleaks detect --source . --redact   # blocks merge if a secret pattern appears in the diff
```

The pre-commit hook runs the same scan locally so most leaks never even reach a push. Together they
make "a secret in a commit" a caught error rather than a permanent history entry.

The result is a system where no secret lives in code or history, every secret is scoped and
rotatable, stored third-party secrets are encrypted with a managed key, and both prevention (scanning)
and response (the runbook) are built in — so a leak is a bounded, rehearsed incident.

## Engineering Decisions

Five decisions define a secrets posture.

### Environment variables, or a dedicated secret manager?

**Options:** (1) plain environment variables / `.env` files; (2) a dedicated secret manager (Vault,
AWS/GCP Secrets Manager); (3) encrypted-file-in-git with KMS (SOPS, sealed-secrets).

**Trade-offs:** environment variables are simple, universally supported, and fine for small
deployments — but they offer no access auditing, no built-in rotation, and are easy to leak into
logs and process listings. A secret manager adds access control, audit logs, versioning, and
rotation APIs at the cost of setup and a runtime dependency. Encrypted-file-in-git keeps secrets in
your existing GitOps flow, encrypted, with the tradeoff of managing the KMS key and decryption at
deploy.

**Recommendation:** environment variables (from a gitignored `.env`) are acceptable for local dev
and small single-service deployments *if* they're never committed and never logged. Move to a secret
manager as soon as you have multiple services, a team, rotation needs, or compliance requirements —
the audit trail and rotation support are worth the setup. Encrypted-file-in-git (SOPS) is a strong
middle option for GitOps shops. The non-negotiable across all three: never in plain git, never
logged.

### How are leaked secrets rotated — and is rotation even possible?

**Options:** (1) no rotation capability (manual redeploy, in practice never); (2) manual but
documented rotation (a runbook); (3) automated/scheduled rotation via the secret manager.

**Trade-offs:** no capability means a leak has no clean response — the worst place to be. A
documented manual runbook makes rotation reliable and rehearsable at low cost. Automated rotation
(the manager issues new credentials on a schedule and updates consumers) is the strongest and needs
integration work and rotatable-credential support from each provider.

**Recommendation:** at minimum, a written rotation runbook per secret *before* you need it, plus
versioned keys (`kid`) so the high-value secrets rotate without downtime. Automate rotation for the
secrets that support it (databases, cloud credentials) as you mature. The failure to avoid is
discovering at leak time that you have no rotation path.

### Where do application-level stored secrets get encrypted?

**Options:** (1) plaintext in the database (the mistake); (2) application-level encryption with a
KMS-managed key (envelope encryption); (3) rely solely on database/disk encryption at rest.

**Trade-offs:** plaintext means a database dump is a credential dump. Disk-level encryption at rest
protects against stolen disks but *not* against a SQL-injection dump or a leaked backup — the data
is plaintext to anything with database access. Application-level envelope encryption keeps the value
ciphertext even to database access, with the master key in KMS, at the cost of encryption code and a
KMS dependency.

**Recommendation:** encrypt application-level secrets (users' OAuth tokens, stored API keys) at the
application layer with envelope encryption and a KMS-managed key — disk encryption is a complement,
not a substitute. This is the difference between "our database leaked" and "our customers' payment
credentials leaked."

### Are secrets shared across environments and services?

**Options:** (1) shared secrets across dev/staging/prod and services; (2) distinct secrets per
environment and per service.

**Trade-offs:** shared secrets are convenient and catastrophic — a staging leak (staging is always
less guarded) becomes a production compromise, and a shared key means rotating one forces rotating
everywhere. Distinct secrets per environment and service contain any leak to its scope, at the cost
of managing more values (which a secret manager makes cheap).

**Recommendation:** every environment and every service gets its own distinct secrets, always. The
convenience of sharing is never worth converting a low-value leak into a total one. This also makes
least-privilege scoping meaningful — a service's credential grants only what that service needs.

### How are leaks detected — proactively or after the breach?

**Options:** (1) nothing (find out from the attacker); (2) secret scanning in CI and pre-commit;
(3) scanning plus provider-side push protection and monitoring for exposed credentials.

**Trade-offs:** no detection means the first sign of a leak is misuse. CI and pre-commit scanning
catches the most common vector (a secret in a diff) cheaply and early. Adding platform push
protection and credential monitoring (many providers alert on exposed keys) catches what slips past.

**Recommendation:** secret scanning as a CI gate and a pre-commit hook is the baseline — cheap, and
it stops the most common leak at the door. Enable your git platform's push protection where
available, and treat any scanner hit as a rotation trigger, not just a "remove the file" fix — by
the time it's in a diff, assume it should be rotated.

## Trade-offs

**A secret manager trades operational dependency for control and auditability.** It adds a service
your app depends on at startup and some setup cost, and returns access control, audit logs,
versioning, and rotation — the things plain env vars can't give you. For anything past a single
small service, the control is worth the dependency; below that, disciplined env vars can suffice.

**Rotatability trades upfront design for bounded leak damage.** Building versioned keys and rotation
runbooks costs effort before any leak happens, and it's effort spent on something that "works fine"
without it — until the day it doesn't. The payoff is that every future leak is a routine rotation
instead of a crisis. This is insurance: you pay before you know you need it.

**Application-level encryption trades performance and complexity for dump-resistance.** Envelope
encryption adds a KMS call and crypto code to every store/read of a protected secret, and means one
more key to manage. It buys the property that database access alone can't yield the plaintext — the
right trade for third-party credentials you're custodian of, overkill for non-secret data.

**Strict scanning trades occasional false positives for catching real leaks early.** A scanner will
sometimes flag a high-entropy string that isn't a secret, adding friction. The alternative — no
scanning — means the real leaks reach history and public mirrors. Tune the allowlist; keep the gate.

## Common Mistakes

**A secret hardcoded as a default fallback.** `os.getenv("JWT_KEY", "dev-secret")` — the fallback
becomes the production secret when the env var is missing, silently. Fix: no fallback; fail to start
on a missing required secret.

**Committing the `.env` file.** The real secrets land in git history the first time someone forgets
the gitignore. Fix: gitignore `.env`, commit only `.env.example` with placeholders, and scan for
leaks in CI.

**Deleting a leaked secret without rotating it.** Removing the key from code and considering it
handled, while the value sits in history and in the attacker's scanner results. Fix: rotate every
leaked secret; deletion is not remediation.

**Secrets in logs and error trackers.** An `Authorization` header dumped in a request log, a
connection string in a stack trace sent to the error tracker. Fix: redact secrets in logging
(Stage 3, Chapter 08); never log credential-bearing values.

**Storing third-party secrets in plaintext.** A user's OAuth token or API key sitting readable in
the database, so a dump is a credential breach. Fix: envelope-encrypt app-level stored secrets with
a KMS-managed key.

**No way to rotate.** Secrets wired in such that changing one requires a painful manual flag day, so
it never happens. Fix: versioned keys and a rotation runbook built before the leak, not after.

## AI Mistakes

Assistants are leak amplifiers: they optimize for code that runs immediately, and the fastest path
often puts a secret somewhere it shouldn't be. Review generated code for where secret *values* end
up, and never paste real secrets into a prompt.

### Claude Code: the hardcoded fallback default that becomes the production secret

Asked to load a secret, Claude Code frequently writes it with a convenient fallback —
`os.getenv("SECRET_KEY", "dev-secret-change-me")` or an inline default in the settings class — so
the code runs even when the environment variable isn't set. In development it's a convenience; in
production, if the env var is ever missing or misnamed, the app *silently* runs on the hardcoded
default, which is now the real signing secret and is sitting in the source. Everything works, and
the system is signing tokens with a key anyone who's read the repo knows.

**Detect:** `getenv`/`environ.get` calls with a second (default) argument that is a real-looking
secret; settings fields with inline default secret values; a signing key or credential appearing as
a string literal anywhere; the app starting successfully with required secret env vars unset.

**Fix:** no fallbacks for secrets; fail closed at boot:

> Never provide a default value for a secret. Required secrets must have no fallback, and the app
> must refuse to start (raise at startup) if any is missing or matches a known placeholder or is too
> short. Add a startup check that enforces this.

### GPT: no rotation path — secrets loaded once, leak has no response

GPT-family models wire secrets in as set-once values read at import and never designed to change:
a single unversioned signing key, a database password threaded directly into a connection string, no
`kid`, no runbook, no dual-key window. The code is clean and works — and the day a secret leaks,
there is no way to rotate it without a coordinated manual redeploy that risks downtime, so in
practice the leaked secret stays live. The vulnerability isn't in the code that runs; it's in the
response capability that doesn't exist.

**Detect:** a single unversioned signing key with no `kid`; secrets read once at module import with
no reload/rotation mechanism; no rotation runbook; providers used in a way that assumes credentials
never change; "how do we rotate this?" having no answer.

**Fix:** design rotatability in from the start:

> Design every secret to be rotatable without downtime: version signing keys with a `kid` and
> support verifying old + new during a rotation window, read rotatable credentials through the
> secret manager rather than a fixed import, and write a rotation procedure per secret. Assume every
> secret will need to be rotated and build the path before it's needed.

### Cursor: secret sprawl — copying a secret value into a new place while completing code

Completing a task that needs a secret, Cursor tends to propagate the *value* to wherever it's
convenient: pasting a key into a new config file, adding it to a second service's settings, echoing
it into a log line or a debug print, or duplicating it across environments — following the local
pattern without a single source of truth. Each copy is a new leak surface and a place rotation will
miss, so months later a "rotated" secret is still live in the forgotten copy.

**Detect:** the same secret value appearing in more than one file or service; secrets added to
new config with no reference to the central secrets access point; secrets in log/print statements;
duplicated values across environment configs; rotation that updates one location while others keep
the old value.

**Fix:** one source, referenced never copied:

> Every secret has exactly one source (the secret manager / one access point) and is referenced from
> there — never copy the value into a second file, service config, or log statement. If code needs a
> secret, read it through the central accessor. Search for and remove any duplicated secret values.

## Best Practices

**No secret in code or git, ever.** Gitignore `.env`, commit only `.env.example` with placeholders,
read every secret through one environment-aware access point, and provide no default fallbacks —
fail to start on a missing or placeholder secret.

**Use a secret manager past the smallest scale.** Access control, audit logs, versioning, and
rotation for anything beyond a single small service; environment variables only where they're never
committed and never logged.

**Build rotatability before you need it.** Versioned keys (`kid`) for zero-downtime rotation of
high-value secrets, a rotation runbook per secret, distinct secrets per environment and service so a
leak stays scoped.

**Encrypt the secrets you store for others.** Envelope-encrypt application-level secrets (users'
OAuth tokens, stored API keys) with a KMS-managed key, so a database dump is ciphertext.

**Scope every secret to least privilege.** Credentials restricted to the schema, operation, or
resource they need; short TTLs where possible — so a leak is contained, not total.

**Scan for leaks, and treat any hit as a rotation trigger.** Secret scanning in CI and pre-commit,
platform push protection, and the rule that a scanner hit means rotate, not just delete.

**Keep secrets out of logs, errors, and AI prompts.** Redact credential-bearing values everywhere
they're written; never paste a real secret into a third-party tool or model prompt — consider any
pasted secret disclosed.

## Anti-Patterns

**The Fallback Secret.** `getenv("KEY", "changeme")` shipping the default to production. The tell: a
secret with a real-looking default argument; the app starts fine with the env var unset.

**The Committed `.env`.** Real secrets in git history. The tell: `.env` tracked by git; secrets
visible in `git log`; a scanner lighting up on the history.

**The Delete-Not-Rotate.** A leaked secret removed from code but never rotated. The tell: an incident
closed by a "remove secret" commit with no corresponding key rotation; the old credential still
valid.

**The Plaintext Vault.** Third-party tokens stored readable in the database. The tell: a `token` or
`api_key` column in plaintext; a database dump that yields working credentials.

**The Immovable Secret.** A secret with no rotation path. The tell: no `kid`/versioning; "how do we
rotate this?" has no answer; secrets unchanged for years.

**The Sprawled Secret.** The same value copied across files, services, and logs. The tell: grep finds
a secret value in multiple places; rotation that misses a copy and leaves it live.

## Decision Tree

"I have a secret — how do I handle it safely across its life?"

```
Is it MY system's secret (signing key, DB password) or one I store FOR someone (user's OAuth token)?
├── stored FOR someone ──► envelope-encrypt at rest with a KMS-managed key (ciphertext in the DB).
└── my system's secret ──► continue:

  WHERE does it live?
   ├── local dev  ──► gitignored .env (never committed); .env.example has names + placeholders only
   ├── CI         ──► platform encrypted secret store, masked in logs
   └── production ──► secret manager, injected at runtime; scoped to least privilege
        (single small service with discipline? env vars are acceptable — never committed, never logged)

  Can it be ROTATED without downtime?
   ├── NO ──► build the path FIRST: version it (kid) or make it manager-managed; write the runbook.
   └── YES ─► good. document the procedure per secret.

  Is it kept out of every LEAK SURFACE?
   └── code/git · logs/errors · docker layers · client bundles · CI logs · AI prompts
        └── any NO ─► remove it AND rotate it (assume compromised). add scanning to catch the next one.

  Did it LEAK?
   └── ROTATE it (generate new, deploy, revoke old). deleting from code is NOT remediation.
```

## Checklist

### Implementation Checklist

- [ ] No secret appears in source code or git history; `.env` is gitignored and only `.env.example` (placeholders) is committed.
- [ ] Secrets are read through one environment-aware access point with no default fallbacks; the app fails to start on a missing or placeholder secret.
- [ ] Application-level stored secrets (users' tokens, stored API keys) are envelope-encrypted with a KMS-managed key.
- [ ] High-value secrets are versioned (`kid`) for zero-downtime rotation; a rotation runbook exists per secret.
- [ ] Each environment and service has its own distinct, least-privilege-scoped secrets.
- [ ] Secret scanning runs in CI and pre-commit, and secrets are redacted from logs and error trackers.

### Architecture Checklist

- [ ] Production secrets come from a secret manager (or KMS-encrypted GitOps), not plain committed config.
- [ ] The secrets access layer is centralized so there is one place to audit and no scattered raw reads.
- [ ] Rotation is possible for every secret without a downtime flag day, and the capability is tested, not assumed.
- [ ] Blast radius is bounded: secrets are scoped least-privilege and never shared across environments or services.
- [ ] Stage 7's config-injection mechanics and this stage's protection/rotation policy are consistent, not contradictory.

### Code Review Checklist

- [ ] No `getenv`/`environ.get` call supplies a secret as a default argument, and no secret appears as a literal.
- [ ] No secret value is copied into a new file, service config, log, or print statement.
- [ ] Stored third-party secrets go through the encryption helper, not plaintext columns.
- [ ] Any secret touched by the diff is confirmed rotatable and not shared across environments.
- [ ] The secret scanner passes, and any historical hit has an associated rotation, not just a deletion.

### Deployment Checklist

- [ ] Production secrets are injected at runtime from the secret manager; none are baked into Docker image layers or CI-built artifacts.
- [ ] Secret-manager access is itself access-controlled and audited; only the services that need a secret can read it.
- [ ] Automated or scheduled rotation is enabled for the secrets that support it; the runbook covers the rest.
- [ ] A leak-response procedure exists and has been rehearsed: detect → rotate → revoke → verify old value is dead.

## Exercises

**1. Find the secrets already in your history.** Run a secret scanner (`gitleaks`, `trufflehog`)
across your repository's full history, not just the working tree. For every hit, decide: is this
still a live credential? Rotate the ones that are, and add the scanner as a CI gate and pre-commit
hook so the next one is caught at the door. The artifact is the findings list, the rotations
performed, and the CI gate.

**2. Make the app refuse a placeholder.** Add startup validation that the application fails loudly to
boot if any required secret is missing, matches a known placeholder, or is too short. Prove it: unset
a secret and a hardcoded-default variant and show the app now refuses to start instead of silently
running insecurely. The artifact is the validation and the failed-boot output.

**3. Encrypt a stored third-party secret.** Take a secret you store for a user (an OAuth token, an
API key). Implement envelope encryption with a KMS (or a local KMS emulator): encrypt on store,
decrypt on use, and show that a database dump contains only ciphertext. The artifact is the
encryption code and a dump showing no plaintext credential.

**4. Rotate a key with zero downtime.** Take your JWT signing key (or any versioned secret).
Rotate it using the `kid` dual-key window: introduce the new key, sign with it while still verifying
the old, then retire the old — with no request failing across the switch. Write the procedure into a
rotation runbook. The artifact is the runbook and a test spanning the rotation.

## Further Reading

- **OWASP Secrets Management Cheat Sheet (cheatsheetseries.owasp.org)** — practical, current
  guidance on storage, rotation, detection, and the lifecycle this chapter is organized around.
- **The Twelve-Factor App — "Config" (12factor.net)** — the foundational argument for keeping config
  and secrets in the environment, out of code; the baseline the secret-manager approaches build on.
- **NIST SP 800-57, "Recommendation for Key Management"** — the authoritative treatment of key
  lifecycle, rotation, and the separation-of-duties principles behind envelope encryption and KMS.
- **gitleaks and trufflehog documentation** — the two widely used secret scanners for CI gates,
  pre-commit hooks, and full-history audits used in this chapter's exercises.
- **Chapter 02 — JWT Security** (versioned keys and rotation) and **Stage 7, Chapters 05–06**
  (CI secrets and runtime injection) — the mechanisms this chapter's lifecycle policy governs.

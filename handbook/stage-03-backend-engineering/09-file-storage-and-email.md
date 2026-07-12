# File Storage & Email

## Introduction

This final Stage 3 chapter covers two capabilities almost every SaaS needs and
almost no SaaS should build itself: storing user files (uploads, generated PDFs,
exports) and sending transactional email (receipts, password resets,
notifications). They are taught together because they are the same *kind* of
thing — integrations with external, specialized services — and because getting
them right draws on nearly everything earlier in the stage: they run through
background jobs (Chapter 06), require multi-tenant authorization (Chapter 04), and
are textbook cases for buying rather than building (Stage 1, Chapter 06).

The unifying lesson is that object storage and email are commodity infrastructure
solved by providers whose entire business is doing them well — durable, scalable
file storage (S3 and S3-compatible services) and deliverable transactional email
(SES, SendGrid, Postmark, Resend). Your job is not to build a storage system or a
mail server; it is to *integrate* one correctly: store files in object storage with
metadata in your database, move files with presigned URLs, authorize every access,
and send email asynchronously through a provider with the reliability machinery from
Chapter 06.

Both are also full of security and correctness traps that a naive implementation
walks straight into — files stored where they vanish on redeploy, client-controlled
storage keys that enable path traversal, files served without authorization (file
IDOR), and email sent synchronously in the request where it blocks and gets lost.
This chapter is about integrating these commodities the way a production system must.

## Why It Matters

File storage and email look simple and are full of ways to be quietly wrong in
production — and both, done naively, fail in ways a demo never reveals.

For **file storage**, the naive approaches all break at scale or on the next deploy.
Storing files as bytes in the database bloats it, wrecks backups, and doesn't scale;
writing them to the app server's local disk means they vanish on redeploy and are
invisible to other instances behind a load balancer; proxying large uploads and
downloads through the app ties up workers and memory. And the security traps are
severe: a client-controlled storage key enables path traversal, an unvalidated upload
is a malware or resource-exhaustion vector, and — the big one — serving files without
an ownership check is IDOR for files (Chapter 04), leaking one tenant's documents to
another.

For **email**, the naive approaches fail on reliability and deliverability. Sending
synchronously in the request blocks the response on a slow external call and loses
the email if it fails (Chapters 01 and 06). Running your own mail server is a
deliverability disaster — your mail lands in spam without the reputation and
authentication (SPF, DKIM, DMARC) that providers manage. And without idempotency,
retries redeliver the same receipt twice; without bounce handling, you keep mailing
dead addresses and wreck your sender reputation.

Both are, at their core, the **buy-not-build** decision from Stage 1, Chapter 06:
object storage and email are undifferentiated, security- and reputation-critical
infrastructure that specialists run better than you can. The engineering is in the
integration — and the integration has to be reliable (jobs), authorized
(multi-tenancy), and secure (validation, private-by-default).

The AI dimension follows: assistants store files on local disk or in the database
(the simplest thing that "works" locally), use the client's filename as the storage
key with no validation (path traversal), and send email synchronously in the request
with no retry or idempotency. Each produces a working demo and a system that loses
files on deploy, is exploitable, and drops or duplicates critical email.

## Mental Model

Both capabilities follow the same shape — a thin, correct integration over a bought
service — with a few non-negotiable rules:

```
   FILE STORAGE
   ┌───────────────────────────────────────────────────────────────┐
   │ FILE bytes ──► OBJECT STORAGE (S3-compatible)   NOT the DB, NOT local disk │
   │ METADATA (key, size, type, OWNER) ──► your DATABASE (references the object)│
   │                                                                            │
   │ UPLOAD:  client ──presigned PUT──► storage directly (bypass your server)   │
   │ DOWNLOAD: authorize (owner?) ──► presigned GET (short-lived) ──► client     │
   │ KEYS: server-generated (uuid, account-prefixed) — NEVER the client filename │
   │ VALIDATE: type + size; private-by-default; authorize EVERY access (Ch 04)  │
   └───────────────────────────────────────────────────────────────┘

   EMAIL
   ┌───────────────────────────────────────────────────────────────┐
   │ request ──► enqueue a JOB (Ch 06) ──► provider API (SES/SendGrid/…)         │
   │ NEVER send synchronously in the request. NEVER run your own mail server.   │
   │ job is IDEMPOTENT (no double-send) + RETRIED (Ch 06)                        │
   │ DELIVERABILITY: SPF + DKIM + DMARC on a real sending domain                 │
   │ handle BOUNCES/complaints (webhook) to protect sender reputation            │
   └───────────────────────────────────────────────────────────────┘
```

Four principles carry the chapter:

**Files live in object storage; metadata lives in the database.** The bytes go to an
S3-compatible object store (durable, scalable, CDN-frontable); a database row holds
the storage key, size, content type, and — critically — the owning account, and
references the object. Never store file bytes in the database, and never on the app
server's local disk (ephemeral and per-instance).

**Move files with presigned URLs, and generate keys yourself.** Clients upload
directly to storage via a short-lived presigned PUT and download via a short-lived
presigned GET, so large files never proxy through your app. The storage key is
generated server-side (a UUID under an account-scoped prefix), never the client's
filename — which would enable path traversal and collisions.

**Authorize every file access; private by default.** A file belongs to an account,
and every access — issuing a download URL, serving a file — checks that the caller
owns it (Chapter 04). Buckets and objects are private by default; a presigned URL is
issued only *after* an authorization check and expires quickly. Serving a file by key
or ID without an ownership check is file IDOR.

**Send email asynchronously through a provider, reliably.** Email goes out via a
transactional email provider's API, from a background job (Chapter 06) so the request
never blocks and a failure retries — and the job is idempotent so a retry doesn't
double-send. Deliverability (SPF/DKIM/DMARC on a real domain) and bounce handling are
part of doing it correctly, not extras.

A working definition:

> **File storage and email are commodity integrations you buy, not build: files in
> object storage with metadata in the database, moved by presigned URLs with
> server-generated keys and per-account authorization; email sent asynchronously
> through a provider via an idempotent, retried job, with deliverability and bounce
> handling. The engineering is a correct, secure, reliable integration.**

## Production Example

**Invoicely** needs both. Customers upload company logos and attach files to invoices,
and the system generates invoice PDFs — all of which must be stored durably, served
only to the account that owns them, and survive deploys. And Invoicely emails invoice
PDFs and receipts to customers — the "send invoice" job from Chapter 06 — which must go
out reliably, not twice, and actually reach the inbox.

We will integrate object storage for files (S3-compatible), with upload and download
via presigned URLs, server-generated account-scoped keys, type/size validation,
metadata in the database, and per-account authorization on every access — closing the
file-IDOR hole explicitly. And we will complete the email side: the transactional
provider integration, sending through the Chapter 06 job (idempotent, retried), and a
bounce webhook. Both are thin integrations over bought services, and both are where the
naive version is insecure, unreliable, or both.

## Folder Structure

```
core/
├── storage.py            # object-storage client + presigned URL helpers + key generation
└── email.py              # transactional email provider client + template rendering
modules/files/
├── router.py             # request upload URL, confirm upload, request download URL
├── _service.py           # validation, key generation, per-account authorization
└── _models.py            # StoredFile: key, size, content_type, account_id (owner)
modules/invoicing/
└── tasks.py              # send_invoice_email job (Ch 06) — now sends via the provider
```

Why this shape:

- **`core/storage.py`** wraps the object-storage client and centralizes presigned-URL
  generation and server-side key creation, so keys are always safe and access is
  always time-limited.
- **`modules/files/_service.py`** owns the security: validation, key generation, and the
  per-account authorization that every file access passes through.
- **`_models.py`** stores file *metadata* (including the owning `account_id`) in the
  database, referencing the object in storage — the split that keeps the database lean
  and access authorizable.
- **`core/email.py`** wraps the provider; sending happens from the Chapter 06 job in
  `tasks.py`, never inline in a request.

## Implementation

**Presigned upload with a server-generated key (`files/_service.py` + `storage.py`).**
The client asks for an upload URL; the server validates, generates a safe
account-scoped key (never the client filename), records metadata, and returns a
short-lived presigned PUT. The client uploads *directly* to storage.

```python
# core/storage.py
import uuid
import boto3

_s3 = boto3.client("s3", endpoint_url=settings.S3_ENDPOINT)   # S3 or S3-compatible

def generate_key(account_id: int, filename: str) -> str:
    # Server-generated, account-scoped key. NEVER the client filename (path traversal!).
    ext = sanitize_extension(filename)         # derive a safe extension only
    return f"accounts/{account_id}/uploads/{uuid.uuid4()}{ext}"

def presigned_put(key: str, content_type: str, expires: int = 300) -> str:
    return _s3.generate_presigned_url(
        "put_object",
        Params={"Bucket": settings.S3_BUCKET, "Key": key, "ContentType": content_type},
        ExpiresIn=expires,        # short-lived
    )
```

```python
# modules/files/_service.py
ALLOWED_TYPES = {"image/png", "image/jpeg", "application/pdf"}
MAX_SIZE = 10 * 1024 * 1024   # 10 MB

class FileService:
    async def create_upload(self, account_id: int, filename: str, content_type: str,
                            size: int) -> UploadTicket:
        # Validate BEFORE issuing a URL. Never trust client-supplied type/size blindly,
        # and re-check server-side after upload where it matters.
        if content_type not in ALLOWED_TYPES:
            raise ValidationError("Unsupported file type.")
        if size > MAX_SIZE:
            raise ValidationError("File too large.")
        key = generate_key(account_id, filename)          # server-side, account-scoped
        await self._repo.add(StoredFile(
            key=key, account_id=account_id, content_type=content_type, size=size,
            status="pending",
        ))
        return UploadTicket(url=presigned_put(key, content_type), key=key)
```

**Authorized download — file IDOR closed (`files/router.py`).** A download URL is
issued only after confirming the file belongs to the caller's account. The
presigned GET is short-lived. There is no path that returns a file by key without the
ownership check.

```python
@router.get("/files/{file_id}/download-url")
async def get_download_url(
    file_id: int, service: FileServiceDep, account: CurrentAccountDep
) -> DownloadUrlOut:
    # AUTHORIZE: the file must belong to THIS account (Ch 04). Scoped query, no IDOR.
    stored = await service.get_for_account(file_id, account.id)
    if stored is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "File not found")   # not-yours == 404
    # Only now issue a short-lived presigned GET.
    url = presigned_get(stored.key, expires=120)
    return DownloadUrlOut(url=url)
```

**Transactional email via a provider, from the Chapter 06 job (`core/email.py` +
`tasks.py`).** Sending is a provider API call, made from the idempotent, retried job
built in Chapter 06 — never inline in a request.

```python
# core/email.py — a thin wrapper over the transactional provider
class EmailClient:
    async def send(self, to: str, subject: str, html: str, text: str,
                   idempotency_key: str) -> None:
        await self._provider.send(                 # SES / SendGrid / Postmark / Resend
            to=to, subject=subject, html=html, text=text,
            idempotency_key=idempotency_key,        # provider-side dedup, belt-and-braces
        )
```

```python
# modules/invoicing/tasks.py — the Ch 06 job, now sending through the provider
@task(max_retries=5, retry_backoff=True, acks_late=True)
async def send_invoice_email(invoice_id: int, correlation_id: str) -> None:
    if await email_log.already_sent(invoice_id, kind="invoice"):   # idempotent (Ch 06)
        return
    invoice = await invoices.get(invoice_id)
    html, text = render_invoice_email(invoice)     # server-rendered template, HTML + text
    try:
        await email.send(
            to=invoice.customer_email, subject=f"Invoice {invoice.number}",
            html=html, text=text, idempotency_key=f"invoice-{invoice_id}",
        )
    except EmailProviderTimeout as exc:
        raise Retry() from exc                       # transient → bounded retry (Ch 06)
    await email_log.record_sent(invoice_id, kind="invoice")
```

**Bounce handling (deliverability).** A provider webhook reports bounces and complaints;
handling them (stop mailing dead addresses, honor unsubscribes) protects sender
reputation so future email keeps reaching inboxes.

```python
@router.post("/webhooks/email")     # verify the provider's signature (like Stripe webhooks)
async def email_events(payload: EmailEvent) -> None:
    if payload.type in {"bounce", "complaint"}:
        await suppression_list.add(payload.email)    # stop sending to this address
```

The through-line: files go to object storage with metadata in the database, move via
short-lived presigned URLs with server-generated account-scoped keys, and are served
only after an ownership check (no file IDOR); email goes out through a provider, from
the idempotent retried job, on an authenticated sending domain, with bounces handled.
Every one of those is a thing the naive version omits — local-disk storage that dies on
deploy, client-named keys that traverse paths, files served to anyone, email sent
inline that blocks and vanishes. And both are integrations over bought commodities, not
systems you built — the Stage 1, Chapter 06 decision, realized.

## Engineering Decisions

Five decisions define these integrations.

### Where are files stored?

**Options:** (1) in the database (as bytes/BLOBs); (2) on the app server's local disk;
(3) in object storage.

**Trade-offs:** the database is transactional and terrible for files — it bloats the
database, wrecks backups and replication, and doesn't scale. Local disk is simple and
ephemeral — files vanish on redeploy and are invisible to other instances behind a load
balancer. Object storage is durable, scales infinitely, is CDN-frontable, and is what
the providers are built for — at the cost of an external dependency and presigned-URL
plumbing.

**Recommendation:** object storage (S3 or S3-compatible: MinIO, Cloudflare R2, Spaces),
always, with file *metadata* in the database referencing the object. Never store file
bytes in the database or on local disk. This is not a close call for any app that
outlives a single server or a single deploy.

### Presigned direct transfer, or proxy through the app?

**Options:** (1) proxy uploads/downloads through your application; (2) presigned URLs for
direct client↔storage transfer.

**Trade-offs:** proxying is simpler to reason about and lets you inspect/transform the
stream, but ties up app workers and memory on large files and doesn't scale. Presigned
URLs let the client transfer directly to/from storage, so your app never handles the
bytes — scalable and cheap — at the cost of the presigning flow and slightly less direct
control.

**Recommendation:** presigned URLs for direct transfer as the default, especially for
anything large — it keeps file bytes off your app entirely. Proxy only when files are
small and you have a strong reason to see the stream (e.g., server-side transformation),
and even then be mindful of the load. Either way, keys are server-generated and access
is authorized.

### How is file access authorized?

**Options:** (1) public/unauthenticated access by key; (2) per-account authorization on
every access with short-lived URLs.

**Trade-offs:** public access (a world-readable bucket, or serving by key without a
check) is simplest and exposes every file to anyone who has or guesses a key — a breach
for private data. Per-account authorization with short-lived presigned URLs keeps files
private and access controlled, at the cost of an authorization check and URL expiry on
every access.

**Recommendation:** private by default, authorize every access by owning account (Chapter
04), and issue only short-lived presigned URLs *after* the check. Serving a file by key or
ID without an ownership check is file IDOR — the same OWASP-#1 hole as Chapter 04, applied
to documents. Public access is only for genuinely public assets (a marketing image),
never user data.

### Build or buy — storage and email?

**Options:** (1) build (run your own storage system / mail server); (2) buy (object
storage and email providers).

**Trade-offs:** building means operating durable, scalable storage or a
reputation-managed mail system yourself — an enormous, specialized, security- and
deliverability-critical undertaking for zero differentiation. Buying offloads all of that
to specialists, at a per-use cost and a dependency.

**Recommendation:** buy both — this is the clearest possible case of Stage 1, Chapter 06.
Object storage and transactional email are commodity infrastructure that providers do far
better than you can, and building either is almost never justified. Your engineering goes
into the *integration*, not the system.

### Synchronous or asynchronous email?

**Options:** (1) send email inline in the request; (2) send from a background job.

**Trade-offs:** inline is simplest and blocks the response on a slow external call, fails
the user's request if the provider hiccups, and loses the email with no retry. A
background job returns the user immediately, retries on failure, and dedupes to avoid
double-sends — at the cost of the job machinery (which you already have from Chapter 06).

**Recommendation:** always send email from a background job (Chapter 06) — idempotent so
retries don't double-send, retried so a transient provider failure recovers, and off the
request path so the user isn't blocked. Critical email (password reset, receipts) should
use the enqueue-after-commit / outbox reliability from Chapter 06 so it is never lost.
Email in the request path is a Chapter 01 and Chapter 06 anti-pattern combined.

## Trade-offs

These integrations trade simplicity and control for scale, security, and reliability, and
a few points are contextual.

**Object storage adds a dependency and indirection.** Presigned URLs, server-generated
keys, and the metadata/object split are more moving parts than writing a file to disk —
worth it for durability and scale, and genuine overhead for a throwaway prototype that
will never run on more than one machine. For anything real, the local-disk simplicity is a
trap that springs on the first redeploy or second instance.

**Presigned direct transfer trades control for scale.** Letting clients talk directly to
storage means your app can't inspect or transform the bytes in flight — fine for most
uploads, a real constraint if you need server-side processing (virus scanning,
thumbnailing), which then happens after upload (often via a job, Chapter 06). Choose
proxying only when that in-flight control is genuinely required and the files are small.

**Buying trades a fee and lock-in for not owning the hard part.** Providers charge per use
and create some lock-in (though S3's API is a de facto standard, and email providers are
swappable behind a thin wrapper). The alternative — running storage or mail yourself — is
so much worse for these commodities that the trade is rarely close. Keep the integration
behind a thin interface so the provider is swappable (Stage 2, Chapters 03 and 06).

**Reliability and deliverability are ongoing, not one-time.** Idempotent retried email,
bounce handling, and SPF/DKIM/DMARC are setup *and* maintenance — sender reputation
degrades if you mail dead addresses, and deliverability needs monitoring. This is real
ongoing work; it is also exactly the work a provider helps with, which is another argument
for buying and integrating carefully rather than improvising.

## Common Mistakes

**Files in the database or on local disk.** BLOBs bloating the database and wrecking
backups, or local-disk files that vanish on redeploy and are invisible across instances.
Fix: object storage for bytes, database for metadata.

**Client-controlled storage keys / no validation.** Using the client's filename as the
storage key or path (path traversal, collisions), and accepting any type or size. Fix:
server-generated account-scoped keys, and validate type and size (never trust client
metadata).

**File access without authorization (file IDOR).** Serving files by key or ID, or issuing
presigned URLs, without checking the caller owns the file — leaking one tenant's documents
to another. Fix: authorize every access by owning account (Chapter 04); private by default;
short-lived URLs only after the check.

**Public buckets for private data.** A world-readable bucket holding user files, exposed to
anyone with (or guessing) a URL. Fix: private by default; public access only for genuinely
public assets.

**Synchronous, unreliable email.** Sending in the request path (blocking, lost on failure)
with no idempotency or retries, so email double-sends or vanishes. Fix: send from an
idempotent, retried background job (Chapter 06); use the outbox for critical mail.

**Neglecting deliverability.** Running your own mail server, or skipping SPF/DKIM/DMARC and
bounce handling, so mail lands in spam and sender reputation rots. Fix: use a reputable
provider on an authenticated sending domain, and handle bounces/complaints.

## AI Mistakes

File storage and email are integrations whose naive form works perfectly on a developer's
single-machine, single-tenant, nothing-fails setup and breaks on deploy, at scale, and under
attack. An assistant produces that naive form. Review generated integrations for what happens
on the second instance, the second tenant, and the failed send.

### Claude Code: storing files in the database or on local disk

Asked to handle a file upload, Claude Code typically writes the bytes to the local
filesystem (`open(path, "wb")`) or stores them in a database column, because both "work"
immediately in a single-process dev environment. In production the local files disappear on
the next deploy and are invisible to other instances, and database BLOBs bloat and slow the
database.

**Detect:** file bytes written to a local path or served from the filesystem; a database
column holding file contents; uploads buffered fully into app memory.

**Fix:** require object storage:

> Store file bytes in object storage (S3-compatible), not on local disk or in the database.
> Keep only metadata (storage key, size, content type, owning account) in the database.
> Move files with presigned URLs so bytes don't proxy through the app.

### GPT: client-controlled keys and unvalidated uploads

GPT-family models routinely use the client-supplied filename as the storage key or path and
skip type/size validation, because it's the direct way to "save the uploaded file." A
client filename as a key enables path traversal and collisions, and an unvalidated upload is
a malware and resource-exhaustion vector.

**Detect:** the client filename used as the storage key or in a path; no allowlist of
content types; no size limit; trusting the client-supplied content type without check.

**Fix:** require server-generated keys and validation:

> Generate the storage key server-side (a UUID under an account-scoped prefix) — never use
> the client's filename as the key or path. Validate the file type against an allowlist and
> enforce a maximum size before accepting the upload, and don't trust the client-supplied
> content type.

### Cursor: sending email synchronously in the request

Wiring up an email inline, Cursor tends to call the email provider (or an SMTP library)
directly in the request handler with no job, retry, or idempotency, because that's the
shortest path from "user did X" to "email sent." It blocks the response on an external call,
fails the request if the provider hiccups, loses the email on error, and double-sends on any
naive retry.

**Detect:** an email/SMTP send inside a request handler; no background job; no retry or
idempotency around the send; the request awaiting the provider before responding.

**Fix:** require asynchronous, reliable sending:

> Send email from a background job (Chapter 06), never synchronously in the request. The job
> must be idempotent (no double-send on retry) and retried on transient provider failures,
> and critical email should use enqueue-after-commit / the outbox so it is never lost. The
> request returns immediately.

## Best Practices

**Store files in object storage, metadata in the database.** Bytes go to an S3-compatible
store; a database row holds the key, size, content type, and owning account. Never the
database or local disk for the bytes.

**Move files with presigned URLs and server-generated keys.** Direct client↔storage transfer
via short-lived presigned URLs keeps bytes off your app; keys are server-generated and
account-scoped, never the client filename. Validate type and size on upload.

**Authorize every file access; private by default.** A file belongs to an account, and every
access checks ownership (Chapter 04) before issuing a short-lived URL. Buckets and objects
are private; public access is only for genuinely public assets. No serving by key without a
check (no file IDOR).

**Send email asynchronously, reliably, through a provider.** Email goes out from an
idempotent, retried background job (Chapter 06) via a transactional provider — never inline,
never your own mail server. Use the outbox for critical mail so it's never lost.

**Buy both, integrate behind a thin interface, and manage deliverability.** Object storage
and email are commodities to buy (Stage 1, Chapter 06); wrap each provider thinly so it's
swappable, set up SPF/DKIM/DMARC on a real sending domain, and handle bounces/complaints to
protect deliverability. Record the provider choices in an ADR
([`templates/adr.md`](../../templates/adr.md)); document the integration conventions in
`CLAUDE.md`.

## Anti-Patterns

**Files in the Database.** User files stored as BLOBs, bloating the database and destroying
backup/restore performance. The tell: a `bytea`/`BLOB` column holding uploads.

**The Ephemeral Upload.** Files written to the app server's local disk, gone on the next
deploy and invisible to other instances. The tell: `open(path, "wb")` for user uploads, or
serving files from the local filesystem behind a load balancer.

**The Client-Named Key.** The client's filename used as the storage key or path — path
traversal, collisions, and injection. The tell: the upload's key derived from
`file.filename` rather than generated server-side.

**The Public Bucket.** Private user data in a world-readable bucket or served by key without
authorization — file IDOR. The tell: files accessible to anyone with the URL, or a download
endpoint with no ownership check.

**Synchronous Email.** Email sent inline in the request — blocking, fragile, lost on failure,
duplicated on retry. The tell: a provider/SMTP call in a request handler with no job.

**The Home-Grown Mailserver.** Running your own SMTP to send transactional mail, landing in
spam for want of reputation and authentication. The tell: direct SMTP from your servers
instead of a transactional provider, and a spam-folder deliverability problem.

## Decision Tree

"I need to store files / send email — how do I integrate it correctly?"

```
FILE STORAGE
├─ Where? ──► OBJECT STORAGE (S3-compatible) for bytes; DATABASE for metadata.
│             Never local disk, never DB BLOBs.
├─ Transfer? ──► presigned URLs (client ↔ storage directly). Proxy only if small
│                AND you truly need the stream. Keys are SERVER-generated + account-scoped.
├─ Validate? ──► type allowlist + size limit on upload; don't trust client content-type.
└─ Access? ──► authorize by owning account (Ch 04) BEFORE a short-lived presigned URL.
              private by default. No serving-by-key without a check (file IDOR).

EMAIL
├─ Build or buy? ──► BUY a transactional provider (Stage 1 Ch 06). Never your own mailserver.
├─ How to send? ──► from a background JOB (Ch 06): idempotent (no double-send) + retried.
│                   NEVER synchronously in the request. Critical mail → outbox (Ch 06).
├─ Deliverability? ──► SPF + DKIM + DMARC on a real sending domain.
└─ Bounces? ──► handle provider webhooks; suppress dead addresses to protect reputation.
```

## Checklist

### Implementation Checklist

- [ ] File bytes are in object storage; only metadata (key, size, type, owning account) is in the database.
- [ ] Uploads/downloads use short-lived presigned URLs; large files don't proxy through the app.
- [ ] Storage keys are server-generated and account-scoped — never the client filename.
- [ ] Uploads are validated (type allowlist, size limit); client content-type isn't trusted blindly.
- [ ] Every file access is authorized by owning account before a URL is issued (no file IDOR); objects are private by default.
- [ ] Email is sent from an idempotent, retried background job via a provider — never synchronously.

### Architecture Checklist

- [ ] Object storage and email are bought providers, integrated behind thin, swappable interfaces (Stage 1, Chapter 06).
- [ ] File access authorization reuses the Chapter 04 tenant model.
- [ ] Email sending reuses the Chapter 06 job reliability (idempotency, retries, outbox for critical mail).
- [ ] Deliverability (SPF/DKIM/DMARC) and bounce handling are set up, not deferred.
- [ ] Provider choices are recorded (ADR); integration conventions are in `CLAUDE.md`.

### Code Review Checklist

- [ ] No file stored on local disk or as a DB BLOB (watch AI diffs).
- [ ] No client filename used as a storage key/path; uploads validate type and size.
- [ ] No file served or download URL issued without an ownership check.
- [ ] No email sent synchronously in a request handler; sends are idempotent and retried.
- [ ] No private data in a public bucket.

### Deployment Checklist

- [ ] The object-storage bucket is private by default with correct access policies (see [`checklists/production-readiness.md`](../../checklists/production-readiness.md)).
- [ ] Storage credentials are managed as secrets and scoped to least privilege.
- [ ] The sending domain has SPF, DKIM, and DMARC configured and verified.
- [ ] Email bounce/complaint webhooks are handled and their signatures verified.
- [ ] File storage and email provider outages degrade gracefully (uploads/sends retry or queue; the core request still succeeds).

## Exercises

**1. Integrate object storage safely.** Implement Invoicely's logo upload: a presigned-URL
upload flow with a server-generated account-scoped key, type and size validation, metadata
stored in the database, and an authorized download URL that returns 404 for a file the caller
doesn't own. The artifact is the flow plus a cross-tenant test proving one account can't get
another's file.

**2. Fix the naive file handler.** Take a file upload that writes to local disk and uses the
client's filename (write it, or have an assistant generate "handle a file upload in FastAPI").
Identify each problem — ephemeral storage, path traversal, no validation, no authorization —
and fix all of them. The artifact is the before/after and a line naming the production failure
or exploit each problem enabled.

**3. Make email reliable and deliverable.** Take a handler that sends email synchronously and
convert it to the Chapter 06 job pattern (idempotent, retried, off the request path), then
list the deliverability setup (SPF/DKIM/DMARC, provider, bounce handling) Invoicely needs so
its invoice emails reach inboxes. The artifact is the async sending code and the deliverability
checklist.

## Further Reading

- **Amazon S3 documentation — Presigned URLs, and Bucket policies / Block Public Access**
  (docs.aws.amazon.com/s3) — the reference for presigned upload/download and for keeping
  objects private; the concepts apply to any S3-compatible store (R2, MinIO, Spaces).
- **OWASP File Upload Cheat Sheet** (cheatsheetseries.owasp.org) — the security checklist for
  uploads: type/size validation, server-generated names, avoiding path traversal, and content
  handling. The reference for the upload-security half of this chapter.
- **Transactional email provider documentation** (Postmark, SES, SendGrid, Resend), especially
  their guides on **SPF/DKIM/DMARC and deliverability** — read one provider's deliverability
  guide end to end; it is the clearest explanation of why you buy rather than run your own mail
  and how to reach the inbox.
- **DMARC.org and "Email Authentication" overviews** — background on SPF, DKIM, and DMARC and
  why they determine whether your mail is trusted; essential context for configuring a sending
  domain correctly.

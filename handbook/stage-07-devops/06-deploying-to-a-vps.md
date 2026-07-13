# Deploying to a VPS

## Introduction

This is the chapter where everything meets the metal. You have a Linux mental model (Chapter 01),
container images (Chapter 02), a Compose stack (Chapter 03), a hardened Nginx front door
(Chapter 04), and a CI/CD pipeline (Chapter 05) — and a Virtual Private Server is the actual
computer where they run and serve real users. A VPS is a rented Linux machine with a public IP,
full root access, and nothing else: no platform, no guardrails, no one else responsible for it.
That is its appeal (cheap, controllable, yours) and its danger (cheap, controllable, *yours* —
including the security, the backups, and the 2 a.m. page). This chapter is the end-to-end process
of taking Invoicely from a repository to a running, secure, observable production system on a
single VPS: provisioning the box, hardening access, deploying the stack, wiring DNS and TLS,
restarting without dropping requests, and recovering when it breaks.

The single most important idea: **a VPS is unmanaged infrastructure, so the reproducibility,
security, and recoverability that a platform would give you become *your* explicit
responsibility — and the goal is a server you can rebuild from scripts, not a hand-tuned pet you
pray never dies.** On a PaaS, "how do I recreate this?" and "is SSH secure?" and "where are the
backups?" are answered for you. On a VPS they're answered by you, in code, or they're not answered
until the disaster. The whole discipline of this chapter is turning a unique, fragile, manually-
configured machine into a *reproducible* one: provisioning scripted, deploys automated through the
Chapter 05 pipeline, config in the repo, and a documented, *tested* path to stand up a replacement.

The judgment this chapter teaches is **own the responsibilities a platform would have hidden.** A
VPS deploy that "works" — the site is up — can simultaneously have password SSH open to the world,
no firewall, no backups, a deploy that drops every in-flight request on restart, and no way to
recover if the disk dies. Making it production-grade is a specific set of decisions layered on the
previous chapters: key-only SSH and a firewall, a non-root deploy user, the Compose stack pulled
and run as an artifact, zero-downtime restarts, automated database backups (with *tested*
restores), and a rebuild runbook. This chapter ties the stage together — and hands off to Stage 9
for deeper hardening and Stage 11 for when one server is no longer enough.

## Why It Matters

The VPS is where the abstractions end and the consequences are real:

- **Unmanaged means every hidden responsibility is now yours.** A platform silently handles OS
  patching, firewall defaults, TLS, backups, and recovery. A VPS hands you a root shell and a
  public IP and handles none of it. Every one of those becomes an explicit task you do — or a gap
  an attacker or an outage finds. The cost saving of a VPS is real; so is the operational burden.
- **An exposed server is attacked within minutes.** A fresh VPS with a public IP starts receiving
  automated SSH brute-force and vulnerability scans almost immediately. Password auth, root login,
  and no firewall aren't theoretical risks — they're actively exploited defaults. The first
  actions on any VPS are hardening access, before the app even matters.
- **"Just SSH in and pull" is how deploys go wrong.** Manual deploys on the server reintroduce
  everything CI/CD (Chapter 05) removed: the forgotten migration, the wrong branch, the untested
  build, the dropped requests on a hard restart, no rollback. The VPS should be the *target* of an
  automated deploy, not a place you log in to run commands from memory.
- **The pet server is an unrecoverable single point of failure.** A box configured by hand over
  months — undocumented tweaks, config edited live, "don't touch it, we're not sure it'll come
  back" — cannot be rebuilt when the disk fails or the provider has an incident. Reproducibility
  (scripts, config in the repo, a rebuild runbook) is what converts a catastrophe into an
  inconvenience.
- **No backups means one bad moment ends the business.** A dropped table, a `down -v`, a disk
  failure, a ransomware event — without *tested* database backups, any of these is
  unrecoverable data loss. On a VPS, backups are your job, and a backup you've never restored is a
  hope, not a backup.

Get it right — a scripted, hardened, firewalled server running the CI-built stack with
zero-downtime deploys, automated tested backups, and a rebuild runbook — and a single VPS is a
legitimate, cheap, controllable production home for a SaaS. Get it wrong and it's an exposed,
unrecoverable, manually-operated liability that fails at the worst possible time with no way back.

The AI dimension: asked to "deploy this to a server," assistants generate the happy path — a
sequence that gets the app running — and omit the responsibilities a platform would have hidden.
They'll `ssh` in and `git pull && docker compose up` (manual, no rollback, drops requests), leave
password SSH and root login enabled, skip the firewall, and never mention backups or a rebuild
plan. The site comes up in the demo; the server is undefended, unrecoverable, and deployed by hand.

## Mental Model

A VPS is a raw Linux box you make reproducible, hardened, and recoverable — layering the whole
stage onto real hardware:

```
   A VPS = a rented Linux computer: public IP + root + NOTHING else provided.
     everything a platform hides is now YOUR job:  security · patching · backups · recovery.

   THE ORDER OF OPERATIONS (do NOT deploy before you harden)
     1. PROVISION      create the box; a non-root `deploy` user with sudo
     2. HARDEN ACCESS  key-only SSH (no passwords, no root login) · firewall (ufw: 22/80/443 only)
                          ⇒ a fresh public IP is brute-forced within MINUTES — this is step 1, not last.
     3. INSTALL RUNTIME Docker + Compose (the only real dependency; the app is images)
     4. DEPLOY         CI pushes image → server PULLS the tagged image → compose up (Ch 03/05)
     5. DNS + TLS      point the domain at the IP → Nginx + Let's Encrypt (Ch 04)
     6. BACKUPS        automated DB dumps off the box + a TESTED restore
     7. OBSERVE        logs, health, alerts (Ch 07)

   PET  vs  CATTLE   (the core VPS discipline)
     PET    = hand-configured, undocumented, edited live, irreplaceable  ← the trap
     CATTLE = provisioned by script, config in the repo, rebuildable from scratch  ← the goal
        test: "our disk died — how long to a working replacement?"  hours-from-a-runbook, not "we're doomed."

   DEPLOY = PROMOTE AN ARTIFACT, not build/pull-source on the box
     ✗ ssh in; git pull; docker build; restart      (manual, untested bytes, drops requests, no way back)
     ✓ CI built image:<sha> → server: docker compose pull → migrate → up -d → healthcheck → (rollback)

   ZERO-DOWNTIME RESTART (don't drop in-flight requests on every deploy)
     old container keeps serving → new one starts + passes healthcheck → traffic shifts → old drains → stops
        graceful SIGTERM (Ch 01/02 exec-form) lets in-flight requests finish. hard `down && up` = dropped requests.

   BACKUPS (the responsibility with no second chance)
     automated pg_dump on a schedule → stored OFF the server (object storage) → restore TESTED regularly.
        a backup you have never restored is a hope, not a backup.
```

Four principles carry the chapter:

**Harden before you deploy.** A public IP is under attack immediately; key-only SSH, no root
login, and a firewall come *first*, before the app. Security on a VPS is not a later hardening pass
(that depth is Stage 9) — the baseline is the price of admission to putting a box on the internet.

**Build cattle, not pets.** The server must be reproducible from scripts and config in the repo, so
a dead disk or a compromised box is a rebuild from a runbook, not a catastrophe. Every hand-edit on
the box is a step toward an irreplaceable pet — resist it.

**Deploy by promoting the CI artifact, never by building on the box.** The server *pulls and runs*
the tested SHA-tagged image (Chapter 05), applies migrations, and restarts gracefully. "SSH in and
pull source and build" throws away every guarantee the pipeline provides and drops requests.

**Own backups and recovery as first-class work.** Automated, off-box, *tested* database backups and
a documented rebuild path are the difference between a recoverable system and a business-ending
outage. On a VPS nobody else is doing this; a backup you haven't restored doesn't count.

## Production Example

**Invoicely** runs in production on a single Ubuntu 24.04 LTS VPS (a modest instance — a few vCPUs,
a few GB of RAM is plenty for a young SaaS). The requirement that frames every decision: **the
server is hardened before it serves a byte, deploys come only through the CI/CD pipeline, and the
whole box — plus its data — can be reconstructed from scripts and backups if it's lost.**

The lifecycle: a provisioning script creates a non-root `deploy` user, installs Docker and Compose,
configures `ufw` to allow only SSH/80/443, and locks SSH to key-only with no root login and
(ideally) a non-default port — all before the app exists. DNS points `app.invoicely.com` at the
server's IP; Nginx and Certbot (Chapter 04) provide TLS. Deployment is entirely Chapter 05's
pipeline: on a release tag, CI pushes the SHA-tagged images and the deploy step SSHes in as
`deploy`, `docker compose pull`s the exact tested images, runs `alembic upgrade head` (Stage 6's
expand/contract migrations), and brings the stack up with a graceful, health-checked, rollback-
capable restart — no in-flight requests dropped, no manual commands. A nightly job runs `pg_dump`,
encrypts it, and ships it to object storage off the server, and a monthly job *restores* the latest
backup into a scratch database to prove it works. A `RUNBOOK.md` in the repo documents standing up a
replacement server from zero. This is a single machine, operated like production — and Stage 11 is
where Invoicely graduates to multiple nodes when it outgrows one.

## Folder Structure

The VPS deploy is defined by scripts and runbooks in the repo (cattle, not pets) plus the layout on
the server itself. First, what lives in version control:

```
invoicely/
├── infra/
│   ├── provision.sh            idempotent: create deploy user, install Docker, ufw, harden SSH
│   ├── backup.sh               pg_dump → encrypt → upload off-box (run by cron/timer)
│   ├── restore.sh              pull a backup → restore into a target DB (the TESTED path)
│   └── RUNBOOK.md              stand up a replacement server from zero; incident procedures
├── docker-compose.prod.yml     the stack the server runs (Chapter 03)
├── nginx/                      proxy + TLS config (Chapter 04)
├── .github/workflows/          the pipeline that deploys here (Chapter 05)
└── .env.example                the runtime config contract (real .env lives only on the server)
```

Then the layout *on* the server — deliberately minimal, because the app is images, not files:

```
/home/deploy/                   the non-root deploy user's home (never deploy as root)
├── invoicely/
│   ├── docker-compose.prod.yml  pulled from the repo at deploy time
│   ├── nginx/                   proxy config
│   └── .env                     RUNTIME secrets — chmod 600, owned by deploy (Chapter 01)
└── (Docker manages images/volumes under /var/lib/docker — the DB volume lives here)
```

Why this shape:

- **`infra/` makes the server reproducible.** The provisioning, backup, and restore *scripts* and
  the *runbook* are in the repo, reviewed and version-controlled — so the server is defined by code,
  not by someone's memory. This is the single most important structural choice for avoiding a pet.
- **`provision.sh` is idempotent and does hardening first.** Re-running it converges the box to the
  desired state (safe to run again), and it hardens access before anything else — the order encodes
  "secure before deploy."
- **`backup.sh`/`restore.sh` are a pair, and `restore.sh` is not optional.** A backup script alone
  is a false comfort; the restore script (run on a schedule against a scratch DB) is what proves the
  backups are real. They live together so no one forgets the second half.
- **The server holds almost nothing but the Compose file, Nginx config, and `.env`.** Because the
  app ships as images (Chapter 02) and state lives in a Docker volume, the server's own filesystem is
  nearly stateless — which is exactly what makes it rebuildable. The `.env` is the one secret,
  `chmod 600` and owned by `deploy`.

## Implementation

The provisioning script — run once on a fresh box, idempotent, hardening before anything else:

```bash
# infra/provision.sh — run as root on a fresh Ubuntu VPS; safe to re-run.
set -euo pipefail

# 1. A non-root deploy user with sudo — the app is NEVER operated as root (Chapter 01).
id deploy &>/dev/null || adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys   # your public key only
chown deploy:deploy /home/deploy/.ssh/authorized_keys && chmod 600 "$_"

# 2. HARDEN SSH — key-only, no root login. (A public IP is brute-forced within minutes.)
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/'               /etc/ssh/sshd_config
systemctl restart ssh

# 3. FIREWALL — deny by default, allow only SSH + HTTP + HTTPS.
ufw default deny incoming && ufw default allow outgoing
ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp
ufw --force enable

# 4. Unattended security updates — the OS patching a platform would have done for you.
apt-get update && apt-get install -y unattended-upgrades && dpkg-reconfigure -f noninteractive unattended-upgrades

# 5. The only real runtime dependency: Docker + Compose. The app is images.
curl -fsSL https://get.docker.com | sh
usermod -aG docker deploy
```

The deploy itself is **not** a script you run by hand — it's the Chapter 05 pipeline's composite
action targeting this server. The remote sequence it runs, with the zero-downtime and rollback
details that separate it from `down && up`:

```bash
# The remote steps the CI deploy runs as `deploy@server` (from Chapter 05's composite action):
set -euo pipefail
cd /home/deploy/invoicely

PREVIOUS=$(docker compose -f docker-compose.prod.yml images -q backend || true)   # for rollback
docker compose -f docker-compose.prod.yml pull                       # the SAME tested image:<sha> (Ch 05)
docker compose -f docker-compose.prod.yml run --rm backend alembic upgrade head   # expand/contract (Stage 6)

# Rolling restart: start the new container, wait for its healthcheck, THEN retire the old one.
# `up -d` with a healthcheck + graceful SIGTERM (exec-form, Ch 02) drains in-flight requests.
docker compose -f docker-compose.prod.yml up -d --wait                # --wait blocks until healthy

curl -fsS https://app.invoicely.com/health || {                       # verify from the real edge
  echo "post-deploy health FAILED — rolling back"
  docker tag "$PREVIOUS" invoicely-backend:rollback && \
  APP_VERSION=rollback docker compose -f docker-compose.prod.yml up -d --wait
  exit 1
}
```

Automated, off-box, *tested* backups — the responsibility with no second chance:

```bash
# infra/backup.sh — run nightly by a systemd timer or cron. Ships the dump OFF the server.
set -euo pipefail
STAMP=$(date +%F)
docker compose -f docker-compose.prod.yml exec -T db \
  pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip | \
  gpg --encrypt --recipient ops@invoicely.com > "/tmp/invoicely-$STAMP.sql.gz.gpg"
# Off-box storage is the point — a backup on the same disk dies with the disk.
aws s3 cp "/tmp/invoicely-$STAMP.sql.gz.gpg" "s3://invoicely-backups/db/" && rm "/tmp/invoicely-$STAMP.sql.gz.gpg"

# infra/restore.sh (run MONTHLY against a scratch DB) is what makes the above real:
#   aws s3 cp s3://invoicely-backups/db/<latest> - | gpg -d | gunzip | psql -d invoicely_restore_test
#   ...then assert row counts / a known invoice exists. An untested backup is a hope.
```

Three details that most separate a real VPS deploy from "the site is up":

- **Hardening is steps 1–3 of provisioning, before the app.** SSH is locked to keys and the
  firewall is up *before* Docker is even installed. Deploying first and hardening later means the box
  spends its most vulnerable window (default config, public IP) exposed to the automated attacks that
  hit within minutes.
- **`up -d --wait` plus graceful shutdown is the zero-downtime mechanism.** `--wait` blocks until the
  new container's health check passes; the exec-form entrypoint (Chapter 02) means the old container
  gets `SIGTERM` and drains its in-flight requests before stopping. A naive `docker compose down &&
  up` kills the old container immediately — every request in flight is dropped on every deploy.
- **The backup is only real because `restore.sh` runs on a schedule.** Countless teams have a nightly
  `pg_dump` and discover during an incident that it's been failing for months, or that they've never
  actually restored one and the process doesn't work. The tested restore is the backup; the dump alone
  is a file of uncertain value.

## Engineering Decisions

**Harden access before deploying anything.** Key-only SSH, no root login, a default-deny firewall
allowing only SSH/80/443 — as the *first* actions on the box. *Rationale:* a public IP is under
automated attack within minutes; the default config (password auth, root login, no firewall) is
exactly what those attacks exploit. Security is the entry fee for a public server, not a later pass
(Stage 9 goes deeper; this is the non-negotiable baseline).

**Operate as a non-root `deploy` user.** All deploys and app operation happen as an unprivileged user
with scoped sudo, never as root. *Rationale:* Chapter 01's least-privilege at the server level — a
compromised deploy path or a bad command is contained, not catastrophic. Root is for the one-time
provisioning, not day-to-day operation.

**Make the server reproducible: scripts and config in the repo, a rebuild runbook.** Provisioning,
backup, restore, and recovery are code and documentation in version control. *Rationale:* a
hand-configured pet is an unrecoverable single point of failure; a scripted, documented server is
rebuildable when (not if) the disk dies or the box is compromised. "How fast can we replace this?"
must have an answer better than "we can't."

**Deploy only through the CI/CD pipeline, promoting the tested artifact.** The server is the target
of Chapter 05's pipeline; it pulls and runs the SHA-tagged image, migrates, and restarts — no manual
`git pull`/build on the box. *Rationale:* manual server deploys reintroduce every risk CI/CD removed
(untested bytes, wrong branch, forgotten migration, no rollback). The box runs artifacts; it doesn't
build them.

**Restart gracefully with health-gated rollout; never hard-cycle.** `up -d --wait` with health
checks and graceful `SIGTERM`, rolling the new container in before retiring the old. *Rationale:* a
hard `down && up` drops every in-flight request on every deploy — user-visible errors as a routine
cost of shipping. Graceful, health-gated restarts make deploys invisible to users and safely
reversible.

**Automate backups off the box and test the restore.** Scheduled encrypted `pg_dump` to off-server
storage, plus a scheduled *restore* into a scratch database. *Rationale:* on a VPS, backups are
entirely your responsibility, and the only backup that counts is one you've restored. Off-box because
a backup on the same disk dies with it; tested because a silently-failing backup is worse than none
(it's false confidence).

## Trade-offs

**VPS vs PaaS vs managed Kubernetes.** A VPS is cheapest and most controllable and teaches you the
whole stack — at the cost of owning security, patching, backups, and recovery. A PaaS (Render, Fly,
Railway) hides all of that for a higher price and less control. Managed Kubernetes is for when you've
outgrown a single box and need multi-node scheduling — enormous power and enormous complexity. *A
single well-run VPS is a legitimate production home for a SaaS for a long time;* choose a PaaS when
you'd rather pay to not be on-call for the OS, and reach for orchestration (Stage 11) only when one
server genuinely isn't enough. Don't run Kubernetes for one app's worth of traffic.

**Single VPS vs redundant infrastructure.** One server is simple and cheap but is a single point of
failure — if it dies, you're down until you rebuild (hence backups and a runbook). Redundancy
(multiple servers, a load balancer, a replica database) removes the single point at the cost of
significant complexity and money. *Start with one server plus tested recovery;* the honest trade for a
young SaaS is "minutes-to-hours of downtime on a rare failure, and no data loss" — which a runbook and
backups deliver. Multi-node HA is a Stage 11 decision driven by real availability requirements, not a
default.

**Self-managed database on the VPS vs a managed database.** Running Postgres in the Compose stack is
self-contained and cheap; a managed database (RDS, Cloud SQL, Neon) offloads backups, failover,
patching, and point-in-time recovery for a price. *The Compose database is fine to start — with real,
tested, off-box backups* — but production data is where teams most often (and most wisely) graduate to
a managed service, because the recovery guarantees are hard to match by hand. Know the self-managed DB
is a starting point for critical data, not a permanent answer.

**Zero-downtime rigor vs deploy simplicity.** True zero-downtime (health-gated rolling restart,
graceful drain, backward-compatible migrations) is more moving parts than "stop, migrate, start." The
simple version has a brief outage window and risks dropped requests and migration-related errors.
*Invest in graceful, health-gated restarts and expand/contract migrations (Stage 6)* for anything with
real users — the complexity is modest and the alternative is user-visible errors on every deploy. A
true single-user internal tool can accept the simple version.

## Common Mistakes

**Deploying before hardening (or never hardening).** The app goes up while SSH still allows passwords
and root login and there's no firewall, during the box's most-exposed window. *Fix:* harden access
(key-only SSH, no root, `ufw`) as the *first* thing on the server, before the app.

**Deploying manually by SSHing in and pulling.** `git pull && docker compose up` on the server —
manual, unversioned, untested bytes, drops requests, no rollback. *Fix:* deploy only through the CI/CD
pipeline, promoting the tested image.

**Running everything as root.** Deploying and operating as root, so any mistake or compromise is total.
*Fix:* a non-root `deploy` user with scoped sudo; root only for one-time provisioning.

**No firewall / everything exposed.** Internal service ports (the app, even Postgres) reachable from the
internet because no firewall restricts them. *Fix:* default-deny `ufw` allowing only SSH/80/443; only
Nginx is public (Chapters 03–04).

**No backups, or untested ones.** Either no `pg_dump` at all, or a nightly dump nobody has ever
restored (and which may have been failing silently). *Fix:* automated, encrypted, *off-box* backups
**and** a scheduled restore test.

**Hard-cycling the stack on deploy.** `docker compose down && up` kills the old container instantly,
dropping every in-flight request each deploy. *Fix:* health-gated rolling restart (`up -d --wait`) with
graceful `SIGTERM` and backward-compatible migrations.

**The undocumented pet server.** Config edited live, tweaks undocumented, nothing scripted — so the box
can't be rebuilt and no one dares touch it. *Fix:* provisioning/backup/restore scripts and a rebuild
runbook in the repo; config deployed, not hand-edited.

## AI Mistakes

"Deploy this to a server" is a request assistants answer with the happy path — get it running — while
omitting the responsibilities a platform would have hidden. Review any generated deploy against
security, reproducibility, backups, and recovery, not "is the site up."

### Claude Code: the manual `ssh + git pull + up` deploy with no hardening or rollback

Asked to deploy to a VPS, Claude Code commonly produces a sequence that SSHes in, pulls the repo, and
runs `docker compose up` — it gets the app running, so it looks done, but it's a manual deploy of
untested source with no firewall, no SSH hardening, no graceful restart, and no rollback or backups.

**Detect:** deploy instructions that `git clone`/`pull` and `docker build`/`up` on the server; no
firewall or SSH-hardening step; no CI/CD pipeline as the deploy mechanism; `down && up` restarts; no
mention of backups or recovery.

**Fix:** require the platform responsibilities you now own:

> Don't deploy by SSHing in and pulling source. Deploy through the CI/CD pipeline, pulling the tested
> tagged image. And before any of that, provision the server with hardening *first*: key-only SSH, no
> root login, a default-deny firewall (SSH/80/443 only), a non-root deploy user. Add automated off-box
> DB backups with a tested restore, and a graceful health-gated restart with rollback.

### GPT: exposed ports, root operation, and no backups

Prompted for a full deploy, GPT-family models often expose service ports directly (mapping the app or
even Postgres to `0.0.0.0`), operate as root, and produce a setup with no backup strategy at all —
because the goal it optimizes is "reachable and running," not "secure and recoverable."

**Detect:** published internal ports in the prod compose/run (app/DB on public interfaces); commands run
as root; no non-root user; no `pg_dump`/backup automation; no off-box storage; no recovery plan.

**Fix:** require least privilege, a closed surface, and backups:

> Only Nginx should be public (80/443) — do not expose the app or database ports to the internet; the
> firewall denies by default. Operate as a non-root `deploy` user. And add a real backup story:
> automated, encrypted `pg_dump` shipped *off* the server, plus a scheduled restore test. A deploy with
> no tested backups isn't production-ready.

### Cursor: a pet server — live config edits, nothing reproducible

Editing deploy steps or a runbook inline, Cursor tends to instruct editing config directly on the box
(`nano /etc/nginx/...`, tweak and reload) and installing things ad hoc, producing a unique
hand-configured server with no script and no rebuild path — because each edit is local and doesn't
account for reproducibility.

**Detect:** instructions to edit server config in place rather than deploy it from the repo; ad-hoc
`apt install`/manual setup with no provisioning script; no rebuild runbook; "SSH in and change X"
guidance; config that exists only on the server.

**Fix:** require reproducibility:

> Make the server reproducible, not a pet. Put provisioning, backup, and restore in idempotent scripts
> in the repo and a rebuild runbook; deploy config (Nginx, Compose, `.env` template) from version
> control rather than editing it live on the box. I should be able to stand up a replacement server from
> the repo plus a backup — write it so that's true.

## Best Practices

**Harden first, always.** Key-only SSH, no root login, default-deny firewall (SSH/80/443 only),
unattended security updates — the *first* actions on any public box, before the app. (Deeper hardening:
Stage 9.)

**Operate as non-root; expose only the proxy.** A `deploy` user with scoped sudo; the firewall and
Compose keep everything but Nginx internal. Least privilege and a minimal public surface.

**Build cattle: scripts and runbook in the repo.** Idempotent provisioning, config deployed from
version control, and a *tested* rebuild runbook — so a lost server is a rebuild, not a catastrophe.

**Deploy only through the pipeline, promoting the tested artifact.** The server pulls and runs the
SHA-tagged image (Chapter 05), migrates (Stage 6), and restarts gracefully. No manual `git pull`/build
on the box.

**Restart gracefully, roll back automatically.** Health-gated rolling restarts (`up -d --wait`),
graceful `SIGTERM` draining, backward-compatible migrations, and automatic rollback on a failed health
check. Deploys invisible to users and safely reversible.

**Back up off-box and test the restore.** Automated encrypted `pg_dump` to off-server storage, plus a
scheduled restore into a scratch DB. The tested restore is the backup. Pair it with observability
(Chapter 07) so you know the box's state before it becomes an incident.

## Anti-Patterns

**The Undefended Box.** App deployed with password SSH, root login, and no firewall still open — under
automated attack from minute one. The tell: `PasswordAuthentication yes`, `PermitRootLogin yes`, no
`ufw`, the app deployed before any hardening.

**The Manual Deploy.** Shipping by SSHing in and `git pull && up` — untested bytes, dropped requests, no
rollback. The tell: deploy "docs" that are a list of SSH commands; "let me just pull the latest on prod."

**The Pet Server.** A unique, hand-tuned, undocumented box no one can rebuild or dares touch. The tell:
config edited live, nothing scripted, "don't restart it, we're not sure it comes back."

**The Backup Mirage.** A nightly dump that's never been restored, stored on the same disk it's backing
up, possibly failing silently. The tell: `pg_dump` in a cron with no restore test; backups on the server
itself; "we have backups" said with no one having ever tried one.

**The Hard-Cycle Deploy.** `docker compose down && up` on every release, dropping in-flight requests each
time. The tell: no `--wait`/health gate, no graceful shutdown, users seeing errors during every deploy.

**The Root Operator.** Everything done as root — provisioning, deploys, day-to-day ops — so any slip is
system-wide. The tell: deploy scripts full of root commands, no `deploy` user, the app running as root.

## Decision Tree

"I'm putting an app on a VPS (or reviewing a VPS deploy) — what must be true, and in what order?"

```
BEFORE THE APP — HARDEN (a public IP is attacked within minutes)
  Key-only SSH, no root login?                 no → fix sshd_config FIRST. this is step 1.
  Default-deny firewall, only SSH/80/443 open?  no → configure ufw before deploying.
  A non-root `deploy` user (root only for provisioning)?  no → create it.
     → do NOT proceed to deploy until these pass.

REPRODUCIBILITY — CATTLE, NOT PET
  Is provisioning an idempotent script in the repo?      no → script it.
  Is config (Nginx/Compose/.env template) deployed from version control, not edited live?  no → fix.
  Is there a tested rebuild RUNBOOK?                      no → write it. "disk died" needs an answer.

DEPLOY — PROMOTE THE ARTIFACT
  Does the server PULL the CI-built tagged image (not build/pull-source on the box)?  no → use the pipeline (Ch 05).
  Migrations run as an explicit safe step (expand/contract, Stage 6)?                 no → add it.
  Restart health-gated + graceful (up -d --wait, SIGTERM drain), with rollback?       no → make it zero-downtime.

EXPOSE — DNS + TLS
  Only Nginx public; DNS → server IP; Let's Encrypt with auto-renew (Ch 04)?  any no → fix the edge.

RECOVER — BACKUPS
  Automated DB backups, encrypted, stored OFF the server?   no → add them.
  Is the RESTORE tested on a schedule?                       no → a backup you've never restored is a hope.

OBSERVE
  Logs, health checks, alerts in place (Chapter 07)?         no → add them before you rely on the box.
  all yes → a single VPS run like production. any no → fix before real users depend on it.
```

## Checklist

### Implementation Checklist

- [ ] SSH is **key-only** with **root login disabled**; a non-root `deploy` user operates the app.
- [ ] A **default-deny firewall** allows only SSH, 80, and 443; no internal service ports are exposed.
- [ ] Provisioning is an **idempotent script in the repo**; unattended security updates are enabled.
- [ ] The server **pulls and runs the CI-built tagged image** (Chapter 05) — no build/pull-source on
      the box.
- [ ] Deploys run migrations as an explicit safe step and restart **gracefully** (`up -d --wait`, health
      gate, `SIGTERM` drain) with **rollback**.
- [ ] Automated, encrypted DB backups ship **off the server**, and a **restore is tested** on a schedule.
- [ ] The `.env` on the server is `chmod 600`, owned by `deploy`; only Nginx is public.

### Architecture Checklist

- [ ] The server is **reproducible** — scripts + config in version control + a rebuild runbook (cattle,
      not a pet).
- [ ] Deployment happens **only through the CI/CD pipeline**, not manual SSH sessions.
- [ ] The single-server topology's failure modes are understood; recovery (backups + runbook) is the
      mitigation, with multi-node HA deferred to Stage 11.
- [ ] The self-managed database's backup/recovery is real, with a managed-DB migration path noted for
      when data criticality grows.

### Code Review Checklist

- [ ] No deploy before hardening; no password/root SSH; no missing firewall (watch AI-generated deploys).
- [ ] No manual `git pull`/build-on-server deploy; the tested artifact is what runs.
- [ ] No root operation; no exposed internal/DB ports.
- [ ] No hard-cycle restart (dropped requests); graceful, health-gated, reversible.
- [ ] Backups are automated, off-box, and restore-tested — not a never-tried cron job.

### Deployment Checklist

- [ ] Hardening (SSH, firewall, non-root user) is verified *before* the app is exposed.
- [ ] DNS resolves to the server and TLS is live and auto-renewing (Chapter 04) before go-live.
- [ ] A practice **rollback** and a practice **restore** were performed before real users depended on
      the box.
- [ ] Monitoring, health checks, and alerts (Chapter 07) are active; the runbook is where on-call can
      find it.

## Exercises

**1. Provision and harden from zero.** On a fresh throwaway VPS, write and run an idempotent
`provision.sh` that creates a non-root `deploy` user, locks SSH to keys with no root login, and
configures a default-deny firewall — *before* installing the app. Prove the hardening by confirming
password SSH and root login are refused and only 22/80/443 are open. The artifact is the script and the
verification output.

**2. Deploy through the pipeline with zero downtime.** Wire Chapter 05's pipeline to deploy the Invoicely
stack to the server by pulling the tested image, and implement a health-gated graceful restart. Prove
zero downtime by running a load generator against `/health` throughout a deploy and showing no failed
requests — then compare against a naive `down && up` and show the dropped requests. The artifact is the
two request logs.

**3. Prove your backups by restoring them.** Implement `backup.sh` (encrypted `pg_dump` shipped off-box)
and `restore.sh`, then simulate a disaster: destroy the database volume, and reconstruct the data from
the latest backup on a freshly provisioned server, verifying a known invoice is present. Time it. The
artifact is the recovery transcript and the time-to-restore.

## Further Reading

- **DigitalOcean / Linode community tutorials — "Initial Server Setup" and "How To Secure a VPS"**
  (digitalocean.com/community, linode.com/docs) — the practical, widely-used guides to provisioning and
  hardening a fresh Ubuntu box; the source behind this chapter's `provision.sh`.
- **The `ufw`, `sshd_config`, and `unattended-upgrades` documentation** (Ubuntu Server Guide) — the
  authoritative reference for the firewall, SSH hardening, and automatic patching used here.
- **PostgreSQL documentation — "Backup and Restore" (`pg_dump`/`pg_restore`, continuous archiving)**
  (postgresql.org/docs) — the correct way to back up and restore a database, and the basis for a tested
  recovery.
- **"Site Reliability Engineering" (Google) — chapters on release engineering and simplicity**
  (sre.google/books) — the principles behind reproducible, automated, reversible deploys and treating
  servers as cattle.
- **Stage 7, Chapter 07 — Monitoring & Logging** — the final step: observing the running server and
  application so you know its health, can debug incidents, and get alerted before users notice.
</content>

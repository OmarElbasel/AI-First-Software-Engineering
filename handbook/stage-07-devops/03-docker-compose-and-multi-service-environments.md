# Docker Compose & Multi-Service Environments

## Introduction

A real application is never one container. Invoicely is a FastAPI backend, a Next.js frontend, a
PostgreSQL database, a Redis cache, and a Celery worker — five services that have to start in the
right order, find each other over a network, share configuration, persist data across restarts,
and come up together with one command. Wiring that by hand with a pile of `docker run` flags is
error-prone and unrepeatable; the moment you have more than one container, you need something that
describes the *whole system* as a single, versioned, reviewable file. That is Docker Compose: a
declarative description of a multi-service environment — services, networks, volumes, config, and
dependencies — that you bring up with `docker compose up` and that runs the same way on every
developer's laptop and (with care) on the production server.

The single most important idea: **Compose turns a multi-service system into one declarative,
version-controlled artifact, and its central engineering job is getting three things right —
service dependencies (start order and *readiness*), configuration (injected, per-environment,
secrets out of the file), and state (named volumes that survive restarts).** A Compose file that
"works" on the first `up` but hardcodes secrets, assumes services are ready the instant they
start, and stores the database on an anonymous volume is a demo. A production one is explicit
about all three. Get those right and Compose is the reproducible environment that makes "works on
my machine" true for the whole team; get them wrong and it's a new class of subtle,
environment-dependent bugs.

The judgment this chapter teaches is **describe the system, don't script it.** The temptation is
to treat Compose as a shortcut for a bash script that runs some containers. The discipline is to
treat it as the source-of-truth description of an environment: dependencies expressed with health
conditions (not `sleep 10`), configuration expressed with env files and per-environment overrides
(not values pasted into the YAML), and data expressed with named volumes (not "hope it's still
there"). This chapter builds Invoicely's full local-and-production environment on the images from
Chapter 02 — and hands off to Chapter 04 (Nginx/TLS) to expose it and Chapter 06 (VPS) to run it
on a real server.

## Why It Matters

Compose is where a collection of containers becomes a system, and the failures it prevents (or
introduces) are the ones that waste the most time:

- **Reproducible environments end "works on my machine" for the whole team.** One `docker compose
  up` gives every developer, and CI, the exact same backend + DB + cache + worker on the same
  network with the same config. Without it, onboarding is a day of installing Postgres and Redis
  locally and matching versions, and "it works for me" bugs are untraceable.
- **Start order without readiness is a race that fails intermittently.** The backend needs the
  database *accepting connections*, not merely *started*. Compose starts containers fast; a
  database takes seconds to become ready. Express dependency as "started" and the backend crashes
  on boot some fraction of the time — the worst kind of bug, the one that's fine on your machine
  and fails in CI. Express it as "healthy" and it's deterministic.
- **State lives in volumes, and getting that wrong loses data.** A database's data belongs on a
  *named volume* that survives `docker compose down` and container replacement. Store it in the
  container's writable layer or an anonymous volume and a routine `down`/rebuild silently deletes
  the database. This is a genuinely destructive mistake that Compose makes easy to commit.
- **Configuration and secrets are per-environment, and hardcoding them is a leak and a coupling.**
  Dev, CI, and production differ in URLs, credentials, and flags. Bake them into the Compose file
  and you can't reuse it across environments and you commit secrets to git. Inject them and one
  file serves everywhere.
- **The whole system starts, stops, and is inspected as a unit.** `up`, `down`, `logs`, `ps`, and
  `exec` operate on the environment, not one container — which is how you actually run and debug a
  multi-service app locally.

Get it right — a versioned Compose file with health-gated dependencies, injected per-environment
config, and named volumes for state — and the environment is reproducible, safe to tear down, and
identical across machines. Get it wrong and you get boot-order races that only fail in CI, a
database that vanishes on `down`, and secrets committed to the repo.

The AI dimension: Compose is a magnet for the "works on the happy path" failure. Assistants
generate files with `depends_on` but no health conditions (the race), secrets pasted directly into
`environment:` (the leak), the database on no named volume or an anonymous one (data loss), and no
`restart:` policy or resource limits — all of which run perfectly on the first `up` in the demo.
This is exactly where reviewing the generated Compose against production criteria matters.

## Mental Model

Compose is a declarative description of a multi-service system; three things decide whether it's
production or a demo:

```
   A COMPOSE FILE = the whole system as one versioned artifact
     services:  the containers (backend, frontend, db, redis, worker)
     networks:  how they find each other (a private network; DNS by SERVICE NAME)
     volumes:   where state persists (named volumes outliving containers)
        docker compose up   → bring the WHOLE system up      docker compose down → tear down
        one file, in git, same result on every laptop and in CI.

   SERVICE DISCOVERY (why there are no IPs in the file)
     services share a network and reach each other by SERVICE NAME as a hostname:
        backend → "db:5432"   "redis:6379"   (Compose runs a DNS resolver)
     → you never hardcode IPs. the name in the file IS the address.

   THE THREE THINGS PRODUCTION COMPOSE GETS RIGHT
     1. DEPENDENCIES = order + READINESS  (not just "started")
          depends_on:
            db: { condition: service_healthy }   ← WAIT for the DB's healthcheck to pass
        started ≠ ready. a DB container is "up" seconds before it accepts connections.
        health condition = deterministic;  bare depends_on / sleep 10 = a race.

     2. CONFIG = injected, per-environment, secrets OUT of the file
          env_file: .env        ← values live in an ignored file, not the YAML
          override files:  docker-compose.yml + docker-compose.prod.yml (per env)
        one file serves dev / CI / prod;  secrets never committed.

     3. STATE = named volumes that SURVIVE down/rebuild
          volumes: { pgdata: {} }   →   db mounts pgdata:/var/lib/postgresql/data
        named volume  = data outlives the container.  no volume / anonymous = data LOST on down.

   RUN IT AS A SYSTEM
     up -d · down · ps · logs -f <svc> · exec <svc> sh · restart <svc>   ← operate the whole env
```

Four principles carry the chapter:

**Compose describes a system as one versioned artifact.** Services, networks, volumes, and their
relationships live in one file in the repo — reviewed, diffed, and identical across machines. It's
the source of truth for the environment, not a convenience script.

**Services find each other by name over a private network.** Compose gives the services a network
and resolves service names to addresses, so `db` and `redis` are hostnames. No IPs, no
`--link`, no manual wiring — the name in the file is the address.

**Dependency means readiness, not start order.** `depends_on` with a health `condition` waits for
a service to be *actually ready* (its health check passes), turning a boot-order race into a
deterministic startup. `sleep` and bare `depends_on` are the bugs this replaces.

**State lives in named volumes; config is injected.** The database's data goes on a named volume
that survives `down` and rebuilds; configuration and secrets come from env files and
per-environment overrides, never hardcoded in the YAML. These two decisions are the difference
between a safe, reusable environment and one that leaks secrets and loses data.

## Production Example

**Invoicely's** local development *and* production both run from Compose (with a production
override), on the images built in Chapter 02. The environment is five services: `backend`
(FastAPI), `frontend` (Next.js), `db` (PostgreSQL), `redis`, and `worker` (Celery, sharing the
backend image). The requirement driving the design: **a new engineer clones the repo, copies
`.env.example` to `.env`, runs one command, and has the entire app running correctly — and the
same file, with a production override, runs on the VPS.**

The decisions that make it production rather than a demo: the backend and worker `depends_on` the
`db` and `redis` with `condition: service_healthy`, so they never start against a database that
isn't accepting connections — the boot race is gone and CI is deterministic. Postgres stores its
data on a named `pgdata` volume, so `docker compose down` (routine during development) never
deletes the database; only an explicit `down -v` does. All configuration comes from `env_file`,
with secrets in a git-ignored `.env` and a committed `.env.example` template — the same Compose
file serves dev, CI, and prod because the *values* live outside it. A `docker-compose.prod.yml`
override adds restart policies, resource limits, and removes the dev-only bind mounts. Nginx and
TLS (Chapter 04) front this stack; the VPS deploy (Chapter 06) runs exactly this file on the
server.

## Folder Structure

Compose adds a small, deliberate set of files at the repo root — the base file, the environment
overrides, and the config/secret split:

```
invoicely/
├── docker-compose.yml          BASE: the system for local dev (all services, dev conveniences)
├── docker-compose.prod.yml     OVERRIDE for production (restart, limits, no bind mounts, no dev ports)
├── docker-compose.override.yml optional: auto-merged in dev only (extra dev-only tweaks)
├── .env                        the REAL config/secrets — git-IGNORED, per environment
├── .env.example                COMMITTED template documenting every required variable
├── backend/
│   ├── Dockerfile              built into the backend + worker images (Chapter 02)
│   └── ...
├── frontend/
│   ├── Dockerfile
│   └── ...
└── nginx/                      reverse-proxy config, added in Chapter 04
    └── nginx.conf
```

Why this split:

- **A base file plus per-environment overrides, not one file with `if`s.** `docker-compose.yml`
  describes the system; `docker-compose.prod.yml` layers on the production-only differences
  (`restart: always`, resource limits, dropping the source bind mount and exposed dev ports).
  `docker compose -f docker-compose.yml -f docker-compose.prod.yml up` merges them. One system,
  explicit per-environment deltas — instead of a tangle of conditionals or two divergent files.
- **`.env` is secrets/config and is git-ignored; `.env.example` is its committed contract.** The
  Compose file references variables; their *values* live in `.env` (never committed) with
  `.env.example` documenting exactly which variables an environment must supply. This is what lets
  one file run everywhere without leaking secrets.
- **`override.yml` is the dev-only auto-merge.** Compose automatically merges
  `docker-compose.override.yml` when present, which is the idiomatic place for local conveniences
  (source bind mounts for hot-reload, extra debug ports) that must never reach production — so
  they're not in the base file.
- **`nginx/` sits alongside** because the reverse proxy is part of this environment (Chapter 04);
  Compose runs it as another service.

## Implementation

The base `docker-compose.yml` for Invoicely's local environment, with every production-relevant
decision annotated:

```yaml
# docker-compose.yml — the whole Invoicely system for local development
services:
  db:
    image: postgres:16                      # pinned, like all base images (Chapter 02)
    environment:
      POSTGRES_USER: ${POSTGRES_USER}       # injected from .env — no secrets in this file
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - pgdata:/var/lib/postgresql/data      # NAMED volume → data survives `down` and rebuilds
    healthcheck:                             # this is what makes the dependency deterministic
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 5s
      timeout: 3s
      retries: 5
    restart: unless-stopped

  redis:
    image: redis:7
    volumes:
      - redisdata:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    restart: unless-stopped

  backend:
    build: ./backend                         # or `image:` in prod — the artifact from Chapter 02
    env_file: .env                           # config injected, not hardcoded
    depends_on:
      db:
        condition: service_healthy           # WAIT for the DB to accept connections, not just start
      redis:
        condition: service_healthy
    ports:
      - "8000:8000"                          # dev only; in prod Nginx fronts this (override drops it)
    restart: unless-stopped

  worker:
    build: ./backend                         # same image as backend, different command
    command: ["celery", "-A", "app.worker", "worker", "--loglevel=info"]
    env_file: .env
    depends_on:
      redis:
        condition: service_healthy
      db:
        condition: service_healthy
    restart: unless-stopped

  frontend:
    build: ./frontend
    env_file: .env
    depends_on:
      - backend
    ports:
      - "3000:3000"
    restart: unless-stopped

volumes:
  pgdata:                                    # declared here → managed, named, persistent
  redisdata:
```

The production override — the *deltas*, not a second full file:

```yaml
# docker-compose.prod.yml — merged over the base: `-f docker-compose.yml -f docker-compose.prod.yml`
services:
  backend:
    image: ghcr.io/acme/invoicely-backend:${APP_VERSION}   # the CI-built image (Ch 05), not a local build
    ports: []                                # do NOT expose the app port publicly — Nginx proxies it
    deploy:
      resources:
        limits: { cpus: "1.0", memory: 512M }   # bound resource use (the OOM killer is real, Ch 01)
    restart: always                          # production wants always, not unless-stopped

  worker:
    image: ghcr.io/acme/invoicely-backend:${APP_VERSION}
    restart: always

  frontend:
    image: ghcr.io/acme/invoicely-frontend:${APP_VERSION}
    ports: []
    restart: always
```

Operating the environment as a single system:

```bash
cp .env.example .env               # fill in the values once
docker compose up -d               # bring the WHOLE system up (dev)
docker compose ps                  # what's running and each service's health
docker compose logs -f backend     # follow one service's logs
docker compose exec db psql -U invoicely   # shell into a running service
docker compose down                # stop + remove containers — DATA SURVIVES (named volumes)
docker compose down -v             # ⚠ ALSO deletes named volumes — the DB is GONE. rarely what you want.

# production: merge base + prod override
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

The three details that most separate this from a naive file:

- **`condition: service_healthy`, not bare `depends_on`.** Bare `depends_on` waits only for the
  container to *start*; the backend then races the database's few-second startup and crashes
  intermittently. The health condition waits for `pg_isready` to pass — deterministic every time,
  including in CI. This single change eliminates the most common Compose bug.
- **Named volumes (`pgdata`) declared in `volumes:`.** Because Postgres's data directory is a
  named volume, `docker compose down` (which you run constantly) keeps the data; only the explicit,
  scary `down -v` removes it. Anonymous volumes or the container layer would lose the database on
  routine teardown.
- **`down` vs `down -v` is a data-safety distinction worth internalizing.** `down` = remove
  containers, keep volumes. `down -v` = also delete named volumes. Running `-v` out of habit is a
  way to delete a database; it should be a deliberate, rare act.

## Engineering Decisions

**Gate dependencies on health, not start order.** Use `depends_on` with `condition:
service_healthy` and give stateful services real health checks. *Rationale:* "started" is not
"ready"; a database accepts connections seconds after its container starts. Health-gated
dependencies turn a nondeterministic boot race (fine locally, failing in CI) into deterministic
startup. Never substitute `sleep`.

**Store all state on declared, named volumes.** The database and any persistent service mount a
named volume declared in `volumes:`. *Rationale:* the container filesystem is ephemeral; a named
volume survives `down`, rebuilds, and image updates. This is the line between "I tore down my env
and started fresh" and "I deleted the database."

**Inject configuration; keep secrets out of the file.** Use `env_file`/variable substitution with
a git-ignored `.env` and a committed `.env.example`. *Rationale:* one Compose file must serve dev,
CI, and prod, which differ only in values — and secrets must never be committed. Hardcoding
couples the file to one environment and leaks credentials into git history.

**Model environments as a base file plus overrides.** One `docker-compose.yml` for the system,
`docker-compose.prod.yml` (and the auto-merged `override.yml` for dev) for the deltas. *Rationale:*
production differs from dev in a few specific ways (images vs builds, restart policy, resource
limits, no exposed app ports); expressing those as an override keeps the system defined once,
without divergent copies or conditionals.

**Set restart policies and resource limits in production.** `restart: always` and `deploy.resources.limits`
in the prod override. *Rationale:* production services must come back after a crash or reboot
(Chapter 01's supervision, now at the Compose layer), and unbounded memory use invites the OOM
killer to take down a random service. Bound them explicitly.

**Don't expose internal service ports in production; front with a proxy.** Drop the `ports:` on
backend/frontend in prod; only Nginx binds public ports. *Rationale:* publishing the app's port
puts an unauthenticated internal service on the internet (Chapter 01's bind-address lesson at the
Compose layer). Chapter 04's proxy is the single public entry point.

## Trade-offs

**Compose vs an orchestrator (Kubernetes/Nomad).** Compose is simple, file-based, and perfect for
a single host — one server running the whole stack. Kubernetes gives multi-node scheduling,
self-healing, rolling deploys, and horizontal scaling at the cost of enormous operational
complexity. *When Compose wins:* a single VPS, a small team, a SaaS that fits on one machine (which
is most of them for a long time) — Compose plus a good server is a legitimate production setup.
*When you outgrow it:* multiple nodes, need for automated scaling and self-healing across hosts —
that's Stage 11. Don't reach for Kubernetes to run one server's worth of containers.

**One shared Compose file (base + overrides) vs separate files per environment.** Base-plus-override
keeps the system defined once and makes the per-environment differences explicit and reviewable;
fully separate files per environment are simpler to read in isolation but drift apart — a change to
the dev stack silently doesn't reach prod. *Prefer base + overrides* for anything beyond a toy, and
accept the small mental cost of merging.

**Bind mounts (dev) vs baked images (prod).** In dev, bind-mounting source into the container gives
instant hot-reload without rebuilding; in prod, the code must be *baked into the image* (Chapter 02)
so the running system matches the built artifact exactly. *Use bind mounts only in the dev override*
— a bind mount in production means the container isn't running the image you built and scanned,
defeating the reproducibility that's the whole point.

**Compose-managed database vs managed database service.** Running Postgres as a Compose service is
simple and self-contained; a managed database (RDS, Cloud SQL, Neon) offloads backups, failover,
patching, and scaling for a price and less control. *Compose-managed is fine to start* (with real
backups — Stage 6), but production data is where teams most often graduate to a managed service;
know that the Compose Postgres is a starting point, not a permanent answer, for critical data.

## Common Mistakes

**`depends_on` without a health condition.** The backend waits only for the DB *container* to
start, then races its few-second readiness and crashes intermittently — green locally, red in CI.
*Fix:* `condition: service_healthy` plus a real health check on the dependency.

**`sleep 10` to "wait for the database."** A fixed sleep is a guess: too short and it still races,
too long and every startup is slow, and it breaks on a slower machine. *Fix:* health-gated
`depends_on`, which waits exactly as long as needed.

**No named volume for the database (or an anonymous one).** Data lives in the container layer or an
anonymous volume, so a routine `docker compose down` or rebuild deletes the database. *Fix:* a named
volume declared in `volumes:`, mounted at the data directory.

**Running `down -v` out of habit.** `-v` deletes named volumes — i.e. the database — and it's easy
to append reflexively. *Fix:* use `down` for routine teardown; treat `-v` as a deliberate,
rare, "I want to wipe state" action.

**Hardcoding secrets/config in the Compose file.** `POSTGRES_PASSWORD: hunter2` and full DSNs
pasted into `environment:` couple the file to one environment and commit secrets to git. *Fix:*
`env_file`/variable substitution with a git-ignored `.env` and a committed `.env.example`.

**Exposing internal ports in production.** Leaving `ports: "8000:8000"` on the backend in prod puts
the app directly on the internet, bypassing Nginx, TLS, and auth at the edge. *Fix:* drop internal
`ports` in the prod override; only the proxy is public.

**Bind-mounting source in production.** A dev-style bind mount in prod means the container runs
your working directory, not the built image — non-reproducible and a deploy hazard. *Fix:* bind
mounts only in the dev override; prod runs the baked image.

## AI Mistakes

Compose files are a top source of "runs perfectly in the demo, wrong for production." Assistants
default to the happy path — no health conditions, secrets inline, state not persisted. Review every
generated Compose file against the three things (dependencies, config, state).

### Claude Code: `depends_on` without readiness (the boot race)

Asked to "add a database" or "make a Compose file," Claude Code typically writes `depends_on: [db]`
with no health check, because it starts fine on the developer's machine where Postgres happens to be
ready quickly. Under CI or a slower host, the backend races the DB and crashes on boot
intermittently.

**Detect:** `depends_on` as a bare list (no `condition:`); stateful services with no `healthcheck:`;
a backend that "sometimes" fails on `up` or in CI; any `sleep`/wait-for scripts papering over
startup timing.

**Fix:** require health-gated dependencies:

> Give the database and Redis real `healthcheck`s and make dependents wait with `depends_on: { db:
> { condition: service_healthy } }`. No `sleep`-based waits. Startup must be deterministic, including
> on a slow CI runner.

### GPT: secrets and config hardcoded in the YAML

GPT-family models frequently paste real values straight into `environment:` — passwords, database
URLs, API keys — because it makes the single file self-contained and runnable, at the cost of
committing secrets and coupling the file to one environment.

**Detect:** literal passwords/keys/DSNs in `environment:`; no `env_file`/`${VAR}` substitution; no
`.env.example`; the same file with prod values that can't be reused for dev/CI.

**Fix:** require injected config:

> Move all config and secrets out of the Compose file into an `env_file: .env` (git-ignored) with a
> committed `.env.example` template, using `${VAR}` substitution. The one file must run in dev, CI,
> and prod by changing only `.env` — with no secret ever committed.

### Cursor: ephemeral state and no production hardening

Editing a Compose file inline, Cursor tends to add a service without a named volume for its data,
and without `restart:` policies or resource limits — so the database is on ephemeral storage
(lost on `down`) and nothing is production-ready, because the edit optimizes for "add the service,"
not "persist and supervise it."

**Detect:** a stateful service with no named volume (or an anonymous `/var/lib/...` mount); no
`volumes:` top-level declaration; missing `restart:`; no resource limits; internal `ports:` exposed
in the prod config.

**Fix:** require persistence and prod policies:

> Put the database's data on a declared named volume so it survives `docker compose down`. Add
> `restart: always` and resource limits for production, and don't expose internal service ports in
> prod — only the reverse proxy is public. Confirm `down` (without `-v`) keeps the data.

## Best Practices

**Health-gate every dependency on a stateful service.** Real `healthcheck`s on the DB/cache and
`condition: service_healthy` on dependents. Deterministic startup everywhere, including CI. No
`sleep`.

**Persist all state on declared named volumes.** The database and anything durable mounts a named
volume; `down` keeps data and only `down -v` (deliberate, rare) removes it. Verify a teardown
doesn't lose data before you rely on it.

**Inject config; commit a template, never the secrets.** `env_file` + `${VAR}` with a git-ignored
`.env` and a committed `.env.example`. One file, every environment, no leaked credentials.

**Model environments as base + overrides.** Define the system once; express prod deltas (CI images,
`restart: always`, resource limits, no exposed app ports, no bind mounts) in an override. Keep
dev-only conveniences in the auto-merged `override.yml`.

**Harden production: restart policies, resource limits, no public app ports.** Bring services back
after crashes/reboots, bound memory/CPU so one service can't OOM the box, and front everything with
the proxy (Chapter 04) as the single public entry point.

**Operate it as a system.** `up`/`down`/`ps`/`logs`/`exec` on the whole environment; pin every
image; run the *same* file (base + prod override) in CI and on the server so what you test is what
you ship.

## Anti-Patterns

**The Boot Race.** `depends_on` without health conditions, so dependents start against not-yet-ready
services and fail intermittently. The tell: bare `depends_on` lists, no health checks, "works on my
machine but flaky in CI," `sleep` waits.

**The Disappearing Database.** State on the container layer or an anonymous volume, deleted by a
routine `down`/rebuild. The tell: no top-level `volumes:`, a stateful service with no named volume,
"my data keeps resetting."

**The Committed Secret.** Passwords and keys pasted into the Compose YAML and pushed to git. The
tell: literal credentials in `environment:`, no `env_file`, secrets in the repo history.

**The `sleep`-and-Pray Startup.** A fixed `sleep` standing in for readiness, racing on fast hosts and
wasting time on slow ones. The tell: `command: sh -c "sleep 10 && ..."`, wait-for-it scripts as the
only synchronization.

**The Publicly-Exposed Stack.** Internal service ports published in production, putting the app and
even the database directly on the internet. The tell: `ports:` on the backend/DB in the prod config;
no reverse proxy as the sole entry point.

**The Divergent Environments.** Separate, hand-maintained Compose files per environment that drift,
so a change reaches dev but not prod. The tell: `docker-compose.dev.yml` and
`docker-compose.prod.yml` that share nothing, config that's fixed in one and broken in the other.

## Decision Tree

"I'm writing (or reviewing) a Compose file for a multi-service app — what must be true?"

```
DEPENDENCIES (start order + readiness)
  Does any service depend on a stateful one (DB, cache, broker)?
     yes → does the dependency have a healthcheck AND the dependent use
           depends_on: { <svc>: { condition: service_healthy } } ?
        no → add them. bare depends_on / sleep = an intermittent boot race.

STATE (does anything need to persist?)
  Any service with data that must survive a restart (DB, uploads, cache with persistence)?
     yes → is it on a NAMED volume declared in top-level volumes: ?
        no → add one. container layer / anonymous volume = data lost on `down`.
  Reminder: `down` keeps volumes; `down -v` DELETES them. don't type -v by reflex.

CONFIG & SECRETS
  Are values injected via env_file / ${VAR} (not literals in the YAML)?
     no → move to a git-ignored .env + committed .env.example. one file, every env, no leaks.

ENVIRONMENTS
  Do dev and prod differ (images vs build, restart, limits, exposed ports, bind mounts)?
     yes → express prod deltas in docker-compose.prod.yml (merge with -f -f);
           dev-only conveniences in the auto-merged override.yml. don't fork the whole file.

PRODUCTION HARDENING
  restart policy set (always)?  resource limits set?  internal app/DB ports NOT published?
  running the CI-built image (not a bind mount)?
     any no → fix before it's a production file.

VERIFY
  `up -d` twice in a row is deterministic (no race)?  `down` (no -v) keeps the DB?
  the same file runs in CI and on the server?   all yes → it's a system, not a demo.
```

## Checklist

### Implementation Checklist

- [ ] Every dependency on a stateful service uses `depends_on` with `condition: service_healthy`,
      and that service has a real `healthcheck`.
- [ ] No `sleep`/wait-for scripts stand in for readiness.
- [ ] All persistent state is on a **named volume** declared in top-level `volumes:`.
- [ ] Config and secrets come from `env_file`/`${VAR}`, with a git-ignored `.env` and a committed
      `.env.example`.
- [ ] Production deltas live in an override file (`docker-compose.prod.yml`), not a forked copy.
- [ ] Production services set `restart: always` and resource limits; internal app/DB ports are not
      published.

### Architecture Checklist

- [ ] The Compose file is the single source of truth for the environment, in version control.
- [ ] The same base file runs in dev, CI, and prod (via overrides) — no divergent copies.
- [ ] Production runs the CI-built images by tag/digest, not local builds or bind mounts.
- [ ] Only the reverse proxy (Chapter 04) is a public entry point; everything else is internal.
- [ ] The database's persistence and backup story is decided (Compose volume now, managed service
      as data grows — Stage 6).

### Code Review Checklist

- [ ] No bare `depends_on` / `sleep` where a health condition is needed (watch AI-generated files).
- [ ] No hardcoded secrets/config in the YAML; `.env` is git-ignored and `.env.example` exists.
- [ ] No stateful service without a named volume; no accidental `down -v` in scripts/docs.
- [ ] No internal ports exposed in the prod config; no bind mounts in production.
- [ ] `restart:` and resource limits present for production services.

### Deployment Checklist

- [ ] The exact base + prod override files that ran in CI run on the server.
- [ ] Named volumes exist and are backed up (the DB volume especially — Stage 6).
- [ ] `restart: always` verified by rebooting the host and confirming the stack returns.
- [ ] `up`/`down` are documented so no one runs `down -v` on production by accident.

## Exercises

**1. Kill the boot race.** Build a two-service Compose file (FastAPI + Postgres) with a bare
`depends_on`, and reproduce the intermittent boot failure by adding an artificial startup delay to
Postgres. Then fix it with a `pg_isready` health check and `condition: service_healthy`, and prove
`up` is deterministic across ten consecutive runs. The artifact is the before/after file and the run
log.

**2. Prove your data survives (and how to lose it).** Bring up the stack, insert a row, run `docker
compose down`, bring it back up, and confirm the row is still there (named volume working). Then run
`down -v`, bring it up, and observe the empty database — demonstrating exactly what `-v` does. The
artifact is the command transcript showing both outcomes.

**3. One file, three environments.** Take a Compose file with hardcoded config and refactor it to
`env_file` + `.env.example`, then add a `docker-compose.prod.yml` override that switches to CI-built
images, adds `restart: always` and resource limits, and removes exposed app ports — proving the same
base file runs both a dev `up` and a prod `-f -f` up. The artifact is the base file, the override, and
both up commands.

## Further Reading

- **Docker documentation — "Compose file reference" and "Compose in production"** (docs.docker.com)
  — the authoritative reference for `depends_on` conditions, volumes, `env_file`, and merging
  override files; the source behind every decision here.
- **Docker documentation — "Startup order" and "Control startup and shutdown order"**
  (docs.docker.com) — the specific guidance on why `depends_on` isn't enough and how health
  conditions fix it.
- **"Docker: Up & Running" by Sean Kane & Karl Matthias** (O'Reilly) — multi-container systems,
  networking, volumes, and the dev-to-prod path at the depth this chapter compresses.
- **The Twelve-Factor App — "Config" and "Backing services"** (12factor.net) — the principles behind
  injecting config and treating the DB/cache as attached resources, which Compose implements.
- **Stage 7, Chapter 04 — Nginx, Reverse Proxy, Domains & TLS** — the next step: putting a single
  secure public entry point in front of this stack, with a real domain and automatic HTTPS.
</content>

# Docker & Containerization

## Introduction

"Works on my machine" is the oldest failure in software, and containerization is the durable
fix. A container packages your application together with the exact runtime, libraries, and OS
userland it needs into a single image that runs identically on your laptop, in CI, and on the
production server. No more "the server has Python 3.10 but I built on 3.12," no more a
dependency that exists in dev and not in prod, no more a deploy that works Tuesday and breaks
Thursday because someone `apt upgrade`d the box. This chapter is about containerizing a real
application well: understanding what a container actually is (a Linux process, not a virtual
machine), writing a Dockerfile that produces a small, secure, reproducible image, and avoiding
the handful of mistakes that turn "we use Docker" into "we ship a bloated, root-running,
cache-busting 1.5 GB image."

The single most important idea: **a container is a reproducible, isolated Linux process defined
by an image, and the image is a build artifact you should treat like compiled code — small,
immutable, versioned, and built the same way every time.** An image is not a snapshot you tweak
by hand; it's the deterministic output of a `Dockerfile`, layer by layer. Get that mental model
and the two things that matter fall out: the *Dockerfile* is source code (reviewed, in the
repo, cache-friendly) and the *image* is the artifact (immutable, tagged, promoted through
environments). Miss it, and you get the anti-patterns: giant images, secrets baked into layers,
containers that run as root, and builds nobody can reproduce.

The judgment this chapter teaches is **containerize deliberately, not decoratively.** It is easy
to write a Dockerfile that "works" and is simultaneously huge, slow to build, insecure, and
non-reproducible. The difference between a toy Dockerfile and a production one is entirely in
the decisions: a slim base image, multi-stage builds to leave build tools behind, layer
ordering that maximizes cache reuse, a non-root `USER`, a proper `.dockerignore`, secrets passed
at runtime not baked in, and a health check. This chapter is those decisions applied to
Invoicely's FastAPI backend and Next.js frontend — and Chapter 03 (Compose) then wires the
resulting images into a full multi-service environment.

## Why It Matters

Containerization is the packaging standard production runs on, and doing it badly is expensive
in ways that stay hidden until they aren't:

- **Reproducibility is the whole point — and it's fragile.** The promise is "identical
  everywhere." An unpinned base image (`python:latest`), an unpinned dependency, or an
  `apt-get install` without a locked version quietly breaks that promise — the image built today
  differs from the one built last month, and the bug is unreproducible. A container is only as
  reproducible as its Dockerfile is disciplined.
- **Image size is deploy speed, cost, and attack surface.** A 1.5 GB image pushes slowly, pulls
  slowly on every deploy and scale-up, costs registry storage, and ships a full OS of packages
  (each a potential CVE) you never use. A well-built image of the same app can be 150 MB. Size
  is not vanity; it's minutes per deploy and a larger thing to secure.
- **Build caching is developer time.** Docker builds in layers and caches them; get the layer
  order wrong (copy all your code before installing dependencies) and every one-line change
  reinstalls every dependency — turning a 5-second rebuild into a 5-minute one, dozens of times
  a day, in CI and locally.
- **Containers running as root are a real risk.** A container is not a security boundary the way
  a VM is; a process running as root inside the container is root-adjacent to the host in ways
  that matter when there's a container-escape CVE or a mounted volume. Running as root is the
  default and the wrong default.
- **Secrets baked into an image leak permanently.** A secret `COPY`ed or `ARG`ed into a layer is
  in the image history forever, extractable by anyone who pulls it, even if a later layer deletes
  the file. Images are pushed to registries; a baked secret is a published secret.

Get it right — a slim, multi-stage, non-root, cache-friendly image built from a pinned base with
secrets injected at runtime — and you deploy fast, cheaply, securely, and identically across
every environment. Get it wrong and you ship a slow, bloated, insecure artifact that's
different every time you build it.

The AI dimension: this is one of the areas where assistants are *confidently mediocre*. They
produce Dockerfiles that work in the demo and violate most production rules at once — `FROM
python` (unpinned, full-fat), no multi-stage, `COPY . .` before `pip install` (cache-busting),
no `USER` (root), no `.dockerignore`, and occasionally a secret baked in. Every one passes a
`docker build` and a smoke test. Containerization is precisely where "it runs" and "it's
production-grade" diverge most, and where reviewing the AI's Dockerfile against real criteria
pays off.

## Mental Model

A container is an isolated Linux process; an image is its reproducible, layered blueprint:

```
   CONTAINER ≠ VM
     VM         = full guest OS + kernel on a hypervisor    (GBs, boots in seconds)
     CONTAINER  = an isolated PROCESS sharing the host kernel (MBs, starts instantly)
        isolation via Linux namespaces (its own PIDs, network, mounts) + cgroups (limits)
        → it's Chapter 01's process model, walled off. Not a smaller VM.

   IMAGE = the blueprint (build artifact) │ CONTAINER = a running instance of it
     image: immutable, tagged, layered, in a registry   (like a class / compiled binary)
     container: a live process from an image             (like an object / a run)
        docker build → image    docker run image → container    docker push → registry

   IMAGES ARE LAYERS (this is why order matters)
     each Dockerfile instruction = a cached layer, stacked:
        FROM python:3.12-slim         ← base (pin it)
        COPY requirements.txt .       ← changes rarely  ┐ put SLOW, STABLE steps
        RUN pip install -r ...        ← slow, cacheable ┘ EARLY so cache survives
        COPY . .                      ← changes often   ┐ put FAST, VOLATILE steps
        CMD [...]                     ← the entrypoint  ┘ LATE
     change a layer → it and everything AFTER it rebuilds. order least→most volatile.

   MULTI-STAGE (ship the artifact, not the toolchain)
     STAGE 1 "builder": full toolchain, compile/install deps          (heavy, discarded)
     STAGE 2 "runtime": slim base + COPY --from=builder just the output (small, shipped)
        → build tools never reach the final image. 1.5 GB → 150 MB.

   THE PRODUCTION CHECKLIST (what separates a real Dockerfile)
     pinned slim base · multi-stage · deps before code (cache) · .dockerignore ·
     USER non-root · secrets at RUNTIME not baked · HEALTHCHECK · one process per container
```

Four principles carry the chapter:

**A container is a process, not a VM.** It shares the host kernel and is isolated by namespaces
and cgroups — this is why it's megabytes and starts instantly, and why the security model differs
from a VM (hence: don't run as root). Everything from Chapter 01 (processes, ports, users) still
applies inside it.

**The image is a build artifact; the Dockerfile is its source.** Treat the Dockerfile like code
— reviewed, in the repo, deterministic — and the image like a compiled binary — immutable,
tagged, promoted through environments, never hand-edited. Reproducibility comes from pinning
everything the build depends on.

**Layer order is cache strategy.** Instructions become cached layers; a change invalidates that
layer and all after it. Put slow, stable steps (install dependencies) before fast, volatile ones
(copy source). This one decision is the difference between 5-second and 5-minute rebuilds.

**Ship the artifact, not the toolchain.** Multi-stage builds compile/install in a heavy builder
stage and copy only the result into a slim runtime stage — leaving compilers, headers, and
package caches behind. Small images are faster, cheaper, and smaller attack surfaces.

## Production Example

**Invoicely** ships two images: the FastAPI backend and the Next.js frontend, both built by CI
(Chapter 05), pushed to a registry, and run by Compose (Chapter 03) in dev and on the VPS
(Chapter 06). The requirement that drives every decision here: **the image built in CI must be
the exact bytes that run in production** — same Python, same dependencies, same OS libraries —
and it must be small enough to push and pull in seconds and secure enough to expose.

The backend Dockerfile is multi-stage: a `builder` stage on `python:3.12-slim` installs
dependencies into a virtualenv using pinned versions; a `runtime` stage on the same slim base
copies only the virtualenv and the application code, adds a non-root `appuser`, sets a
`HEALTHCHECK` hitting `/health`, and runs `uvicorn`. The result is ~180 MB instead of ~1 GB,
runs as UID 1000 not root, rebuilds in seconds when only application code changes (dependencies
stay cached), and carries no build toolchain into production. Secrets — the database URL, JWT
key, Stripe key — are **not** in the image; they're injected at runtime via environment
variables (Chapter 03). The same discipline applies to the Next.js image, which additionally
uses Next's `standalone` output to ship only the traced runtime files. These two images are the
deployable artifacts the rest of the stage orchestrates.

## Folder Structure

Containerization touches a few files at the repo root; each earns its place, and the
`.dockerignore` is as important as the Dockerfile:

```
invoicely/
├── backend/
│   ├── Dockerfile              the backend image's SOURCE — reviewed, pinned, multi-stage
│   ├── .dockerignore           what NOT to send to the build (as important as Dockerfile)
│   ├── requirements.txt        PINNED deps — copied & installed BEFORE code (cache layer)
│   └── app/                    application code — copied AFTER deps (volatile layer)
│       └── main.py
├── frontend/
│   ├── Dockerfile              the frontend image (multi-stage: deps → build → standalone)
│   ├── .dockerignore
│   ├── package.json
│   └── ...
├── docker-compose.yml          wires the images into a running system (Chapter 03)
└── .env.example                template for the RUNTIME secrets (never baked into images)
```

Why these:

- **`Dockerfile` lives next to what it builds and is source code.** One per service, in the
  repo, reviewed like any code — because the image's reproducibility and security are decided
  entirely here.
- **`.dockerignore` controls the build context, and its absence is a common bug.** Without it,
  `docker build` sends the entire directory — `.git`, `node_modules`, local `.env`, `__pycache__`,
  the `.venv` — to the daemon: slow builds, a bloated context, and the real risk of a local
  `.env` getting `COPY . .`'d into the image. It's the first file to add.
- **`requirements.txt`/`package.json` are copied separately and first.** The dependency manifest
  is copied and installed *before* the source, so the (slow) install layer stays cached across
  code changes. This split is the entire cache strategy.
- **`.env.example` is a template, not a secret.** It documents which runtime variables the image
  expects, injected at `docker run`/Compose time — the real `.env` is git-ignored and
  never enters the image.

## Implementation

A production backend Dockerfile embodying every principle above. Read the comments as the
*reasoning*, not decoration:

```dockerfile
# backend/Dockerfile

# ---- Stage 1: builder — has the toolchain, produces the venv, then is DISCARDED ----
FROM python:3.12-slim AS builder          # PINNED + slim (not python:latest, not full python)

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Copy ONLY the dependency manifest first, so the slow install layer caches
# across source-code changes (the leftmost-volatility rule from the mental model).
COPY requirements.txt .
RUN python -m venv /opt/venv && \
    /opt/venv/bin/pip install --upgrade pip && \
    /opt/venv/bin/pip install -r requirements.txt

# ---- Stage 2: runtime — slim base, no toolchain, non-root, just the app ----
FROM python:3.12-slim AS runtime

# Create a dedicated non-root user (Chapter 01's least-privilege, inside the container).
RUN groupadd --system app && useradd --system --gid app --uid 1000 appuser

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1                    # logs stream to stdout immediately (Chapter 07)

WORKDIR /app

# Bring ONLY the built virtualenv from the builder — the compilers/caches stay behind.
COPY --from=builder /opt/venv /opt/venv
# Then the application code (the most volatile layer, so it's last).
COPY --chown=appuser:app ./app ./app

USER appuser                             # drop from root — everything below runs as appuser

EXPOSE 8000                              # documents the port (does not publish it)

# The orchestrator/Nginx uses this to know the container is actually ready, not just up.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')" || exit 1

# exec form (JSON array) so the process is PID 1 and receives SIGTERM for graceful shutdown.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

The matching `.dockerignore` — small, high-leverage, and the file most often missing:

```gitignore
# backend/.dockerignore
.git
.venv
__pycache__/
*.pyc
.env                 # NEVER let a local secrets file into the build context
.pytest_cache/
tests/               # tests don't belong in the runtime image
*.md
```

Building, running, and injecting secrets at runtime (never at build):

```bash
# Build a tagged, immutable artifact (tag = the git SHA in CI — Chapter 05).
docker build -t invoicely-backend:1.4.2 ./backend

# Run it, injecting secrets at RUNTIME via env — they are not in the image.
docker run --rm -p 8000:8000 \
  --env-file .env \                      # DATABASE_URL, JWT_SECRET, STRIPE_KEY, ...
  --name invoicely-backend \
  invoicely-backend:1.4.2

docker image ls invoicely-backend        # confirm the size is ~180MB, not ~1GB
docker history invoicely-backend:1.4.2   # inspect layers; verify NO secret is in any layer
```

Two details that are easy to miss and matter a lot:

- **`CMD` uses the exec form (`["uvicorn", ...]`), not the shell form (`uvicorn ...`).** The
  shell form runs your process as a child of `/bin/sh`, so `sh` is PID 1 and your app *doesn't
  receive `SIGTERM`* on `docker stop` — it gets `SIGKILL`ed after a timeout, skipping graceful
  shutdown (draining connections, closing the DB pool). The exec form makes your app PID 1 and
  it shuts down cleanly.
- **`0.0.0.0` inside the container is correct** — it means "all interfaces *within the
  container's* network namespace," reachable by Compose/Nginx on the container network. This is
  not the same as binding `0.0.0.0` on the host (Chapter 01); the container's network is
  isolated, and only the ports you publish/proxy are exposed.

## Engineering Decisions

**Pin a slim base image, never `latest` or full-fat.** Use `python:3.12-slim` (or `-alpine`
with eyes open, or a distroless runtime), pinned to a specific version. *Rationale:* `latest`
makes builds non-reproducible (it changes under you) and the full image ships hundreds of MB and
CVEs you don't use. Pinning + slim is reproducibility and a smaller attack surface in one
decision.

**Use multi-stage builds to leave the toolchain behind.** Compile/install in a builder stage;
copy only the output into a slim runtime stage. *Rationale:* build tools (gcc, headers, package
caches, dev dependencies) are needed to *build* and are pure attack surface and bloat at
*runtime*. Multi-stage is the single biggest lever on image size.

**Order layers least-volatile to most-volatile.** Copy and install dependencies before copying
source. *Rationale:* a change to any layer rebuilds it and all after it; putting the slow,
stable dependency install first means a one-line code change reuses the cached deps instead of
reinstalling everything. This is the difference between fast and painful iteration.

**Run as a non-root `USER`.** Create a dedicated user and drop to it before `CMD`. *Rationale:*
containers aren't a hard security boundary; root inside the container is unnecessary privilege
that matters under a container-escape CVE or with mounted volumes. It costs two lines and is a
production requirement, not a nicety.

**Inject secrets at runtime, never bake them into layers.** Secrets come from env vars / mounted
secrets at `docker run`/Compose time. *Rationale:* anything `COPY`ed or `ARG`ed into a layer is
in the image history forever and extractable from any pull — a baked secret is a published
secret, and a later `rm` doesn't remove it from history.

**Add a `HEALTHCHECK` and use the exec-form `CMD`.** A health check lets the orchestrator know
*ready* vs merely *started*; the exec form makes your app PID 1 so it receives `SIGTERM`.
*Rationale:* without the health check, traffic hits a not-yet-ready app; without exec form, you
lose graceful shutdown and drop in-flight requests on every deploy.

## Trade-offs

**Image size vs base familiarity: `slim` vs `alpine` vs `distroless`.** `-slim` (Debian, glibc)
is the safe default — small and compatible. `-alpine` (musl libc) is smaller still but can break
Python packages with C extensions and produce baffling bugs (DNS, timezones, wheels that don't
exist for musl). `distroless` is the smallest and most secure (no shell, no package manager) but
hard to debug (no shell to exec into). *Default to `-slim`;* reach for distroless when you want
minimal attack surface and have your debugging story sorted; use `-alpine` only when you've
verified your dependencies work on musl.

**Build speed vs image size vs reproducibility.** Aggressive multi-stage and layer squashing
minimize size; caching maximizes speed; pinning everything maximizes reproducibility — and they
sometimes pull against each other (e.g. combining `RUN`s for fewer layers can hurt cache
granularity). *The priority order for production:* reproducibility first (pin, don't use
`latest`), then size (multi-stage, slim), then speed (layer order, cache mounts). Never trade
reproducibility for a faster build.

**Containers vs native (systemd) deployment.** Containers give environment parity, isolation,
and a CI-built artifact; native deployment (Chapter 01) is simpler with one less layer. *This is
the same trade as Chapter 01's* — most multi-service SaaS wins with containers for the parity
alone; a single simple service may not need them. Don't containerize a one-file script to seem
modern.

**One process per container vs stuffing several in.** The Docker model is one concern per
container (app, DB, cache each their own), orchestrated together (Chapter 03). Cramming Nginx +
app + a cron into one container with a process manager is possible but fights the model —
independent scaling, independent logs, and clean restarts all break. *Prefer one process per
container;* let Compose/orchestration do the composition.

## Common Mistakes

**Using `FROM python:latest` (or `node:latest`).** Unpinned and full-fat: builds aren't
reproducible (the tag moves) and the image is hundreds of MB of unused packages and CVEs. *Fix:*
pin a specific slim tag (`python:3.12-slim`) and rebuild deliberately when you choose to upgrade.

**`COPY . .` before installing dependencies.** Every source change busts the cache and
reinstalls all dependencies, making every rebuild slow. *Fix:* copy the manifest
(`requirements.txt`/`package.json`) and install first, then copy source.

**No `.dockerignore`.** The whole directory — `.git`, `node_modules`, `.venv`, local `.env` — is
sent as build context: slow builds and, worse, a real chance of `COPY . .` baking a local `.env`
into the image. *Fix:* add a `.dockerignore` excluding VCS, deps, caches, and secrets.

**Running as root.** No `USER` line, so the container runs as root — unnecessary privilege and a
larger blast radius under any escape. *Fix:* create a non-root user and `USER` to it before
`CMD`.

**Baking secrets into the image.** `COPY .env` or `ARG API_KEY=...` puts secrets in the layer
history forever, extractable from any pull. *Fix:* inject secrets at runtime via env vars /
mounted secrets; keep `.env` out of the context.

**No multi-stage build.** Shipping the full toolchain (compilers, dev headers, package caches)
in the runtime image — huge and a bigger attack surface. *Fix:* build in a builder stage, copy
only the output into a slim runtime stage.

**Shell-form `CMD` and no health check.** `CMD uvicorn ...` makes `sh` PID 1 (no graceful
`SIGTERM`); no `HEALTHCHECK` means the orchestrator can't tell ready from started. *Fix:*
exec-form `CMD` and a `HEALTHCHECK` hitting a real readiness endpoint.

## AI Mistakes

Dockerfiles are a place assistants produce something that builds and passes a smoke test while
violating several production rules at once. Review every generated Dockerfile against the
checklist — "it built" proves almost nothing here.

### Claude Code: the "works but not production" Dockerfile

Asked to "add a Dockerfile," Claude Code commonly produces a single-stage image on an unpinned
or full base, running as root, with `COPY . .` before `pip install` and no `.dockerignore` — it
builds and runs, so it looks done, but it's large, cache-hostile, and root.

**Detect:** `FROM python`/`FROM node` (no pinned slim tag); single stage; `COPY . .` before the
dependency install; no `USER`; no `.dockerignore` mentioned; no `HEALTHCHECK`.

**Fix:** require the production shape explicitly:

> Make this a production Dockerfile: pinned slim base, multi-stage (builder → slim runtime),
> copy and install dependencies *before* copying source (for layer caching), a non-root `USER`,
> a `.dockerignore` excluding `.git`/deps/caches/`.env`, and a `HEALTHCHECK`. Show the image
> size.

### GPT: cache-busting layer order and combined mega-`RUN`s

GPT-family models often order layers so that any code change reinstalls dependencies (source
copied before the manifest), or collapse everything into one giant `RUN` that both bloats a
single layer and destroys cache granularity — the image builds correctly but rebuilds slowly
every time.

**Detect:** `COPY . .` (or the whole app) appearing before the dependency install; a single
`RUN` doing apt-install + pip-install + code setup together; no separation of stable vs volatile
layers; rebuilds that always reinstall deps.

**Fix:** require cache-aware layering:

> Order layers least-volatile to most-volatile: copy the dependency manifest and install it in
> its own layer *before* copying application source, so a code change reuses the cached deps.
> Keep dependency install separate from copying source. Confirm a one-line code change doesn't
> reinstall dependencies.

### Cursor: baked secrets and lost graceful shutdown

Editing a Dockerfile inline, Cursor tends to wire configuration in the way that's local to the
edit — `COPY .env .` or `ARG`/`ENV` with a secret value to "make it configurable," and shell-form
`CMD`/`ENTRYPOINT` — baking secrets into layers and breaking `SIGTERM` handling.

**Detect:** `COPY .env`/`ADD .env`; `ARG`/`ENV` holding an actual secret value; secrets visible
in `docker history`; shell-form `CMD uvicorn ...` (not the JSON-array exec form); no signal
handling / graceful shutdown.

**Fix:** require runtime secrets and exec-form entrypoint:

> Don't put secrets in the image — no `COPY .env`, no secret `ARG`/`ENV`. Secrets are injected
> at runtime via env/mounted secrets. Use the exec form (`CMD ["uvicorn", ...]`) so the app is
> PID 1 and receives `SIGTERM` for graceful shutdown. Verify `docker history` shows no secret.

## Best Practices

**Pin a slim base and rebuild upgrades deliberately.** `python:3.12-slim`, never `latest`. Your
image is only reproducible if its base is fixed; upgrade the pin as a reviewed change, not
silently.

**Multi-stage, always, for compiled/installed dependencies.** Build in a heavy stage, ship a
slim runtime stage with only the artifact. It's the biggest lever on both size and attack
surface.

**Order layers for cache; separate deps from source.** Copy and install the manifest first, copy
source last. Keep the slow, stable steps early so iteration stays fast.

**Non-root `USER`, always.** Create a dedicated user and drop to it. Two lines, and it's a
production requirement — pair it with the host-side non-root user from Chapter 01.

**Secrets at runtime, never in a layer.** Inject via env/mounted secrets; keep `.env` out of the
context with `.dockerignore`. Verify with `docker history` that no secret is baked in.

**Add a `.dockerignore`, a `HEALTHCHECK`, and use exec-form `CMD`.** Small, high-leverage: a
`.dockerignore` shrinks context and prevents leaks; a health check gives readiness; exec form
gives graceful shutdown. Tag images immutably (git SHA) so an image is traceable to a commit.

## Anti-Patterns

**The Kitchen-Sink Image.** Full-fat base, no multi-stage, the whole toolchain shipped — a 1.5 GB
image for a small app. The tell: `FROM python`/`node` (not slim), single stage, hundreds of MB in
`docker image ls`.

**The Cache-Buster.** Source copied before dependencies, so every build reinstalls everything.
The tell: `COPY . .` above `pip install`/`npm ci`; CI builds that take minutes for a one-line
change.

**The Root Container.** No `USER`, so the app runs as root inside the container. The tell: no
`USER` line; `whoami` in the container returns `root`.

**The Baked Secret.** A secret `COPY`ed or `ARG`ed into a layer, living in image history forever.
The tell: `COPY .env`; secrets visible in `docker history`; "we rotated the key but it's still in
the old image."

**The Contextless Build.** No `.dockerignore`, so `.git`/`node_modules`/`.venv`/`.env` are sent as
context — slow builds and leaked local files. The tell: a huge build context, a local `.env`
inside the image.

**The Snapshot Image.** An image built once and hand-modified with `docker exec`/`docker commit`
instead of rebuilt from the Dockerfile — non-reproducible and undocumented. The tell: images that
don't correspond to any Dockerfile; "don't rebuild it, we tweaked it live."

## Decision Tree

"I'm containerizing a service (or reviewing a Dockerfile) — what must be true?"

```
BASE IMAGE
  Is it pinned AND slim?  (python:3.12-slim, not python / python:latest)
     no → pin a specific slim tag. latest = non-reproducible; full = bloat + CVEs.

BUILD SHAPE
  Does it compile/install dependencies (C ext, node build, etc.)?
     yes → MULTI-STAGE: builder (toolchain) → runtime (slim, COPY --from only the output).
     no  → single slim stage is fine.

LAYER ORDER
  Is the dependency manifest copied + installed BEFORE the source?
     no → reorder. deps (slow, stable) first; source (fast, volatile) last → cache survives.

CONTEXT
  Is there a .dockerignore excluding .git / deps / caches / .env ?
     no → add one. prevents bloated context AND baking a local .env into the image.

SECURITY
  Is there a non-root USER before CMD?          no → add a user, drop to it.
  Are secrets injected at RUNTIME (not COPY/ARG)? no → move them out; check docker history.

RUNTIME
  Exec-form CMD (["cmd","arg"]) for PID-1 / SIGTERM?   no → convert from shell form.
  A HEALTHCHECK hitting a real readiness endpoint?      no → add one.

VERIFY
  docker image ls → is the size sane (tens–low-hundreds of MB, not GB)?
  docker history  → no secret in any layer?
  one-line code change → rebuilds WITHOUT reinstalling deps?
     all yes → production-ready. any no → fix before it ships.
```

## Checklist

### Implementation Checklist

- [ ] Base image is a **pinned slim** tag (`python:3.12-slim`), never `latest`/full-fat.
- [ ] **Multi-stage** build: toolchain in a builder stage, only the artifact copied into a slim
      runtime stage.
- [ ] Dependency manifest is copied and installed **before** application source (cache order).
- [ ] A **`.dockerignore`** excludes `.git`, dependency dirs, caches, and `.env`.
- [ ] A non-root **`USER`** is created and dropped to before `CMD`.
- [ ] Secrets are injected at **runtime** (env/mounted), never `COPY`/`ARG`ed into a layer.
- [ ] `CMD` uses the **exec form**; a **`HEALTHCHECK`** hits a real readiness endpoint.

### Architecture Checklist

- [ ] One process/concern per container; multi-service composition is left to Compose (Ch 03).
- [ ] Images are tagged **immutably** (git SHA), traceable to the commit that built them.
- [ ] Base-image and dependency pins are upgraded as reviewed changes, not silently.
- [ ] The Dockerfile lives in the repo and is code-reviewed like source.

### Code Review Checklist

- [ ] No `FROM ...:latest` or full-fat base; no single-stage build shipping the toolchain.
- [ ] No `COPY . .` before the dependency install (watch AI-generated Dockerfiles).
- [ ] No missing `USER` (root container); no `COPY .env`/secret `ARG` (baked secret).
- [ ] No shell-form `CMD` where graceful shutdown matters; a `HEALTHCHECK` is present.
- [ ] `docker history` and `docker image ls` were checked (no baked secret; sane size).

### Deployment Checklist

- [ ] The image that runs in production is the **exact image** built and scanned in CI (by
      digest/SHA), not rebuilt on the box.
- [ ] Image size and layer count are reasonable (fast push/pull on deploy and scale-up).
- [ ] A vulnerability scan (e.g. `docker scout`/Trivy) runs against the image in CI (Stage 9
      hardens this).
- [ ] The container runs read-only where possible and with a restart policy (Chapter 03).

## Exercises

**1. Shrink a bloated image.** Start from a naive single-stage `FROM python` Dockerfile with
`COPY . .` before install and no `USER`. Convert it to multi-stage on a pinned slim base, fix the
layer order, add a non-root user and `.dockerignore`, and measure the before/after size with
`docker image ls`. The artifact is the two Dockerfiles and the size difference (expect a
5–10× reduction).

**2. Prove the cache order matters.** With the fixed Dockerfile, change one line of application
code and rebuild; confirm the dependency-install layer is reused (`CACHED` in the build output).
Then move `COPY . .` above the install, make the same change, and observe every dependency
reinstall. The artifact is the two build logs showing the timing difference.

**3. Hunt a baked secret.** Deliberately `COPY .env` into an image, build it, then use `docker
history` and unpacking a layer to extract the secret from the pushed image — proving why baking
secrets is a leak even after a later `rm`. Then fix it to runtime injection and confirm `docker
history` is clean. The artifact is the extraction and the fixed Dockerfile.

## Further Reading

- **Docker documentation — "Best practices for building images" and "Multi-stage builds"**
  (docs.docker.com) — the authoritative source for layer caching, multi-stage, and slim images;
  reinforces every decision in this chapter.
- **Docker documentation — Dockerfile reference** (docs.docker.com) — the exact semantics of
  `COPY` vs `ADD`, exec vs shell form, `HEALTHCHECK`, and `USER` that this chapter depends on.
- **"Docker Deep Dive" by Nigel Poulton** — the clearest full mental model of images, layers,
  namespaces, and the container-vs-VM distinction at the depth this chapter compresses.
- **Google's distroless images and Snyk/"Docker security" guides** (github.com/GoogleContainerTools/distroless)
  — the next step for minimal, hardened runtime images once slim isn't small enough.
- **Stage 7, Chapter 03 — Docker Compose & Multi-Service Environments** — the next step: wiring
  these images (backend, frontend, Postgres, Redis, Nginx) into one reproducible running system
  for dev and production.
</content>

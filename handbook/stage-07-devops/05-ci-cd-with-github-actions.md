# CI/CD with GitHub Actions

## Introduction

Every time a human deploys software by hand, they run a checklist from memory — run the tests,
build the image, push it, SSH in, apply migrations, restart the services — and every manual
checklist is eventually run wrong, at the worst time, by the most tired person. CI/CD replaces
that ritual with an automated pipeline: every push runs the same tests, every merge builds the
same artifact, and every release deploys it the same way, with the same safety checks, whether
it's a quiet Tuesday or a Friday-night hotfix. This chapter is about building that pipeline well
with GitHub Actions — Continuous Integration (every change is automatically built and tested) and
Continuous Delivery/Deployment (every accepted change is automatically shipped) — for the
Invoicely application, turning "deploy" from a nerve-wracking manual event into a boring,
repeatable, reversible one.

The single most important idea: **CI/CD is executable, version-controlled discipline — the same
build, test, and deploy steps run automatically on every change, so quality gates can't be
skipped and deployments can't be improvised.** The pipeline is not a convenience that saves
typing; it is the mechanism that makes "all tests pass before merge" and "production runs exactly
the artifact CI built and scanned" *true by construction* instead of true when everyone
remembers. A good pipeline builds an artifact once and promotes that same artifact through
environments; gates merges on tests, lint, and type checks; injects secrets from a secure store
never the repo; and — the part teams most often skip — can *roll back* as fast as it rolls
forward.

The judgment this chapter teaches is **automate the whole path and make it safe, not just fast.**
It is easy to write a workflow that runs `pytest` and calls it CI, or one that SSHes in and `git
pull`s and calls it CD. A production pipeline is a specific set of decisions: caching so the
pipeline is fast enough that people actually wait for it; a real quality gate on protected
branches; building the deployable artifact once and deploying *that* (not rebuilding on the
server); secrets from GitHub's encrypted store; a manual approval gate before production; and a
rollback that's a button, not an archaeology project. This chapter builds Invoicely's pipeline —
test → build image (Chapter 02) → push → deploy the Compose stack (Chapters 03–04) to the VPS
(Chapter 06) — with all of that.

## Why It Matters

The pipeline is where quality is enforced and where deployment risk is either managed or ignored:

- **Manual deployments are the highest-variance operation a team does.** A human running steps
  from memory forgets the migration, deploys the wrong branch, skips the tests "just this once,"
  or fat-fingers a command against production. Automation makes the deploy *identical every time*
  — the whole point is removing the human variance from the most dangerous action.
- **Gates that depend on discipline are gates that fail.** "We always run the tests before
  merging" is true until a deadline. A required CI check on the protected branch makes it
  *impossible* to merge red code — the enforcement is mechanical, not cultural. Without it, the
  test suite is decoration.
- **Build-once-deploy-many is what makes environments trustworthy.** If CI builds an image,
  staging tests *that image*, and production runs *that same image by digest*, then "it passed in
  staging" means something. Rebuilding on the server, or building separately per environment,
  breaks the chain — now prod runs bytes nobody tested.
- **Rollback speed is your real blast-radius control.** Every deploy can break production; what
  determines the severity is how fast you can get back to the last good version. A pipeline that
  can redeploy the previous artifact in one click turns an incident into a five-minute blip; one
  that can only roll forward turns it into an outage while you debug under pressure.
- **Secrets in CI are a prime leak target.** Pipelines need database URLs, registry credentials,
  and deploy keys — and the naive way to supply them (hardcoded in the workflow, echoed in logs)
  publishes them to anyone who can read the repo or the build output. Doing this right (encrypted
  secrets, masked in logs, least-privilege tokens) is a security-critical part of CI/CD.

Get it right — a fast, cached pipeline that gates merges on real checks, builds one artifact,
promotes it through environments with an approval before prod, and rolls back in one click — and
shipping becomes frequent, boring, and safe. Get it wrong and you have either a red-suite theater
that everyone bypasses or a manual-deploy ritual that fails at the worst moment with no way back.

The AI dimension: assistants generate GitHub Actions YAML fluently and produce pipelines that
*run* while missing the things that make CI/CD trustworthy — no caching (so it's too slow to
respect), secrets pasted into the workflow, no branch protection or required checks (so the gate
is optional), rebuilding on deploy instead of promoting the tested artifact, and no rollback path
at all. The YAML is valid and the green checkmark appears; the discipline it's supposed to
enforce isn't there.

## Mental Model

CI/CD is one automated path from commit to production, with gates and a way back:

```
   THE PIPELINE (every change takes the SAME path — no improvised deploys)

   commit / PR ──► CI ───────────────► CD ──────────────────────────► production
                   │                    │
     ┌─────────────┴───────────┐   ┌────┴──────────────────────────────────┐
     │ CONTINUOUS INTEGRATION  │   │ CONTINUOUS DELIVERY / DEPLOYMENT       │
     │ runs on every push/PR   │   │ runs on merge / tag                    │
     │  • lint + type check    │   │  • push the SAME image to the registry │
     │  • run the test suite   │   │  • [manual approval gate before PROD]  │
     │  • build the image once │   │  • deploy: pull image, migrate, restart│
     │  • scan the image       │   │  • health check → keep, else ROLL BACK │
     │  = the QUALITY GATE     │   │  = the SAFE DELIVERY of one artifact    │
     └─────────────────────────┘   └────────────────────────────────────────┘

   BUILD ONCE, PROMOTE THE SAME ARTIFACT  (never rebuild per environment)
     CI builds  invoicely-backend:<git-sha>  ──►  staging runs :<sha>  ──►  prod runs :<sha>
        the bytes tested in CI/staging are the EXACT bytes in prod. rebuilding breaks this.

   DELIVERY vs DEPLOYMENT
     continuous DELIVERY   = every accepted change is READY to deploy; a human clicks "go"
     continuous DEPLOYMENT = every accepted change deploys AUTOMATICALLY (no click)
        → most teams: auto-deploy to staging, delivery (approval) to production.

   THE FOUR THINGS A PIPELINE MUST GET RIGHT
     1. FAST (cache deps/layers) → people actually wait for it; slow CI gets bypassed
     2. GATED (required checks on protected branch) → red code CANNOT merge
     3. SECURE (secrets from the encrypted store, masked, least-privilege) → no leaks
     4. REVERSIBLE (redeploy the previous artifact in one click) → incidents stay small

   GITHUB ACTIONS VOCAB
     workflow (.github/workflows/*.yml) ─ triggered ON events (push, pull_request, tag)
        └─ job (runs on a runner; jobs parallel unless needs:)
             └─ step (an action `uses:` or a `run:` command)
        secrets → ${{ secrets.NAME }} (encrypted, masked)   environments → approval + scoped secrets
```

Four principles carry the chapter:

**One automated path, no manual deploys.** Every change goes commit → CI → CD → production through
the same pipeline. The value is the *removal of human variance* from building, testing, and
shipping — not the keystrokes saved. If there's a manual back door, the pipeline's guarantees
don't hold.

**The gate must be mechanical.** Quality checks (tests, lint, types) are *required status checks*
on a protected branch, so red code cannot merge. A gate that relies on people remembering to run
it isn't a gate. This is how a test suite becomes enforcement instead of decoration.

**Build once, promote the same artifact.** CI builds one image tagged by commit SHA; staging and
production run *that exact image*. Rebuilding per environment (or on the server) breaks the chain
of custody that makes "it passed in staging" meaningful.

**Deployment must be reversible and secure.** A deploy can always fail; the pipeline must roll
back to the previous artifact in one click, and it must handle secrets through GitHub's encrypted
store with least-privilege tokens — never hardcoded, never logged. Reversibility and secret
hygiene are not optional extras; they're what make automated deployment safe.

## Production Example

**Invoicely** ships through a GitHub Actions pipeline with three workflows: `ci.yml` (on every
push and PR), `deploy-staging.yml` (on merge to `main`), and `deploy-production.yml` (on a version
tag, with an approval gate). The requirement driving the design: **no change reaches `main` without
passing the full quality gate, production always runs the exact image that passed CI and staging,
and any bad deploy is reversible in one click.**

`ci.yml` runs lint (`ruff`), type checks (`mypy`), and the test suite (`pytest` against a
service-container Postgres), with pip and Docker layer caching so it finishes in a couple of
minutes; it then builds the backend and frontend images (Chapter 02) tagged with the git SHA and
runs a vulnerability scan. Branch protection on `main` makes these checks *required* — a red PR
cannot merge. On merge, `deploy-staging.yml` pushes the SHA-tagged images to the registry (GitHub
Container Registry) and deploys the Compose stack (Chapters 03–04) to the staging server, running
the database migrations (Stage 6) as a pipeline step and health-checking before declaring success.
Promoting to production is a tagged release that triggers `deploy-production.yml`, which requires a
manual approval (GitHub Environments protection) and deploys the *same* SHA image staging already
validated. Every secret — registry token, SSH deploy key, database URL — comes from GitHub's
encrypted secrets, scoped per environment and masked in logs. Rollback is redeploying the previous
release tag: one click, the last-good image, minutes not hours. Chapter 06 is the server side of
this deploy.

## Folder Structure

CI/CD lives in `.github/`, version-controlled like everything else — the pipeline is code, and
its structure keeps CI, per-environment deploys, and reusable pieces separate:

```
invoicely/
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                 runs on every push/PR: lint, type, test, build, scan (the GATE)
│   │   ├── deploy-staging.yml     on merge to main: push image + deploy to staging (auto)
│   │   ├── deploy-production.yml  on version tag: approval gate + deploy same image to prod
│   │   └── _build.yml             reusable workflow: build+push the image (called by the above, DRY)
│   ├── actions/
│   │   └── deploy/action.yml      composite action: the deploy+migrate+healthcheck+rollback steps
│   └── dependabot.yml             automated dependency-update PRs (they flow through the same gate)
├── docker-compose.prod.yml        what the deploy brings up on the server (Chapter 03)
├── backend/Dockerfile             the artifact CI builds (Chapter 02)
└── ...
```

Why this layout:

- **One workflow per trigger/purpose, not one mega-workflow.** `ci.yml` (validate), staging
  deploy (auto on merge), production deploy (gated on tag) are distinct concerns with distinct
  triggers and permissions. Splitting them keeps each readable and lets production have stricter
  protection than CI.
- **A reusable `_build.yml` and a composite `deploy` action keep the pipeline DRY.** Building the
  image and the deploy sequence (push → migrate → restart → health-check → roll back on failure)
  are identical across staging and prod; factoring them out means the deploy logic is defined and
  fixed *once*, not copy-pasted and drifting between environments (the same DRY lesson as the
  Nginx snippets in Chapter 04).
- **`dependabot.yml` routes dependency updates through the same gate.** Automated dependency PRs
  run the full CI suite before a human merges them — keeping dependencies current without
  bypassing the quality gate (a security practice deepened in Stage 9).
- **The workflows reference, not duplicate, the deploy artifacts.** They build the `Dockerfile`
  from Chapter 02 and deploy the `docker-compose.prod.yml` from Chapter 03 — the pipeline
  *orchestrates* the pieces the rest of the stage defines.

## Implementation

The CI workflow — the quality gate that runs on every push and PR — with caching and a real test
database, annotated for the *why*:

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push: { branches: [main] }
  pull_request:               # runs on every PR → this is what branch protection requires

jobs:
  test:
    runs-on: ubuntu-latest
    services:                 # a real Postgres for the tests, not mocks (Stage 8)
      postgres:
        image: postgres:16
        env: { POSTGRES_PASSWORD: postgres, POSTGRES_DB: test }
        ports: ["5432:5432"]
        options: >-
          --health-cmd pg_isready --health-interval 5s --health-timeout 3s --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: pip          # CACHE deps → CI stays fast → people actually wait for it
      - run: pip install -r backend/requirements.txt
      - run: ruff check backend         # lint  ┐
      - run: mypy backend               # types ├ the QUALITY GATE (all required to pass)
      - run: pytest backend             # tests ┘
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/test

  build:
    needs: test                 # build ONLY if the gate passed — no artifact from red code
    runs-on: ubuntu-latest
    permissions: { contents: read, packages: write }   # least-privilege token
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}     # scoped, auto-rotated — not a PAT in the YAML
      - uses: docker/build-push-action@v6
        with:
          context: ./backend
          push: true
          tags: ghcr.io/acme/invoicely-backend:${{ github.sha }}   # tag = commit SHA (promote THIS)
          cache-from: type=gha           # reuse Docker layer cache across runs (fast builds)
          cache-to: type=gha,mode=max
```

The production deploy workflow — tagged release, approval gate, same artifact, health-checked with
rollback:

```yaml
# .github/workflows/deploy-production.yml
name: Deploy Production
on:
  push: { tags: ["v*"] }        # a version tag = a release

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production      # ← GitHub Environment: REQUIRED REVIEWER approval + scoped secrets
    steps:
      - uses: actions/checkout@v4
      - name: Deploy the SAME image that passed CI/staging
        uses: ./.github/actions/deploy       # composite action: the deploy sequence, defined once
        with:
          image_tag: ${{ github.sha }}       # promote the tested artifact, do NOT rebuild
          host: ${{ secrets.PROD_HOST }}     # all inputs from the encrypted, environment-scoped store
          ssh_key: ${{ secrets.PROD_SSH_KEY }}
```

The composite deploy action — the safe sequence, including the rollback most pipelines omit:

```yaml
# .github/actions/deploy/action.yml  (invoked with the image tag + host + key)
runs:
  using: composite
  steps:
    - shell: bash
      run: |
        ssh -i "$SSH_KEY" deploy@"$HOST" bash -s <<'REMOTE'
          set -euo pipefail
          PREVIOUS=$(docker inspect --format '{{.Config.Image}}' invoicely-backend || true)  # for rollback
          docker compose -f docker-compose.prod.yml pull                 # fetch the SAME tagged image
          docker compose -f docker-compose.prod.yml run --rm backend alembic upgrade head  # migrate (Stage 6)
          docker compose -f docker-compose.prod.yml up -d                # restart with the new image
          for i in {1..10}; do curl -fsS http://127.0.0.1:8000/health && exit 0; sleep 3; done
          echo "health check FAILED — rolling back to $PREVIOUS"         # ← the part teams skip
          APP_VERSION="$PREVIOUS" docker compose -f docker-compose.prod.yml up -d
          exit 1
        REMOTE
```

Three details that separate a real pipeline from valid-but-hollow YAML:

- **`build` has `needs: test`, so no artifact is ever produced from red code.** Ordering the jobs
  so the image is built only after the gate passes means a broken commit can't even leave a
  deployable image lying around. The gate isn't just "tests ran"; it's "nothing downstream happens
  unless they pass."
- **Every image is tagged by `github.sha`, and deploys reference that tag — build once, promote
  many.** Staging and production `pull` the *same* SHA image; nothing rebuilds on the server. This
  is the chain of custody: the bytes that passed CI are the bytes in production.
- **The deploy health-checks and rolls back in the same script.** After restarting, it polls
  `/health`; if the new version doesn't come up, it redeploys the previous image and fails the
  job. A deploy that can't fail safely is a deploy waiting to cause an outage — the rollback is not
  optional.

## Engineering Decisions

**Make the quality checks required on a protected branch.** Branch protection on `main` with
`test` (lint + types + suite) as a required status check. *Rationale:* enforcement must be
mechanical — a gate that people can skip under deadline pressure isn't a gate. This is what turns
the test suite from something people *should* run into something that *cannot* be bypassed.

**Cache aggressively so the pipeline is fast.** Cache pip/npm dependencies and Docker layers
(`cache: pip`, `type=gha`). *Rationale:* a slow pipeline gets worked around — people merge without
waiting, or disable checks "temporarily." Speed is a correctness property of CI: the faster it is,
the more it's respected. A 2-minute pipeline is used; a 20-minute one is bypassed.

**Build the artifact once and promote it by digest/SHA.** CI builds one SHA-tagged image; every
environment deploys *that* image. *Rationale:* the entire value of testing in CI/staging is that
production runs the same bytes. Rebuilding per environment or on the server breaks that guarantee
and reintroduces "works in staging, breaks in prod." Never rebuild to deploy.

**Supply secrets from GitHub's encrypted store, scoped and masked.** `${{ secrets.* }}` from
environment-scoped secrets; the built-in `GITHUB_TOKEN` with least-privilege `permissions:` over a
long-lived PAT where possible. *Rationale:* pipelines handle deploy keys and credentials; hardcoding
them in YAML publishes them to anyone with repo read, and echoing them leaks them in logs. Encrypted,
masked, least-privilege secrets are a security requirement, not a preference.

**Gate production behind a manual approval; auto-deploy to staging.** GitHub Environments with a
required reviewer on `production`; automatic deploy to staging on merge. *Rationale:* staging should
be continuously deployed to catch problems fast; production benefits from a human "go" for
release timing and a final sanity check. This is the delivery-vs-deployment choice made per
environment.

**Make rollback a first-class, one-click path.** The deploy action captures the previous image and
redeploys it on health-check failure; a manual rollback is redeploying the previous release tag.
*Rationale:* every deploy can fail; the severity is set by recovery speed. A pipeline that can only
roll forward turns a bad deploy into a prolonged incident. Design the way back before you need it.

## Trade-offs

**Continuous deployment vs continuous delivery (auto-deploy vs approval gate).** Full continuous
deployment (every merge ships to prod automatically) maximizes speed and forces small, safe changes,
but demands excellent tests, monitoring, and rollback. Continuous delivery (an approval before prod)
adds a human checkpoint for release timing and judgment at the cost of some latency. *Auto-deploy to
staging always; for production, start with an approval gate* and graduate to full CD as your tests,
observability (Chapter 07), and rollback mature. Don't fully automate production deploys before you
can *detect and reverse* a bad one automatically.

**Speed vs thoroughness in CI.** A minimal fast pipeline (lint + unit tests) gives quick feedback;
a thorough one (integration, E2E, security scans, multiple versions) catches more but is slower and
flakier. *Split by stage:* run the fast gate (lint, types, unit) on every push as the required
check, and heavier suites (E2E — Stage 8, deep security scans — Stage 9) on a schedule or pre-deploy.
Keep the *blocking* gate fast so it's respected; run the slow stuff where it won't stall every PR.

**Build on the runner vs build on the server.** Building images in CI (on the runner) keeps the
server clean, produces a scannable artifact, and centralizes the build; building on the deploy
target is simpler infra but rebuilds per server, ties up production resources, and breaks
build-once-promote-many. *Build in CI, always,* and deploy the resulting artifact — the server runs
images, it doesn't build them.

**GitHub Actions vs GitLab CI vs Jenkins vs a PaaS's built-in CD.** GitHub Actions is tightly
integrated, has a huge marketplace, and is free for public/small repos; GitLab CI is similar in a
GitLab shop; Jenkins is maximally flexible and maximally your-problem to operate; a PaaS (Vercel,
Render) gives push-to-deploy with near-zero config but less control. *Actions is the right default
when your code is on GitHub;* the *concepts* (gate, artifact promotion, secrets, rollback) transfer
to all of them — don't over-invest in one tool's YAML dialect at the expense of the principles.

## Common Mistakes

**No required checks / no branch protection.** CI runs but merging red code is still possible, so the
gate is advisory and eventually ignored. *Fix:* protect the branch and mark the CI job a *required*
status check; make green mandatory to merge.

**No caching, so CI is slow and gets bypassed.** Every run reinstalls dependencies and rebuilds all
Docker layers, taking 15+ minutes, so people stop waiting for it. *Fix:* cache dependencies
(`cache: pip`/`npm`) and Docker layers (`type=gha`); keep the blocking gate to a couple of minutes.

**Rebuilding the artifact on deploy instead of promoting the tested one.** The server does a fresh
`docker build` (or a separate CI build per environment), so production runs bytes that were never
tested together. *Fix:* build once in CI, tag by SHA, and `pull`/deploy that exact image everywhere.

**Secrets hardcoded in the workflow or echoed in logs.** Credentials pasted into the YAML or printed
by a debug `echo`, leaking to anyone with repo/log access. *Fix:* GitHub encrypted secrets, scoped per
environment, least-privilege tokens; never `echo` a secret.

**No rollback path.** The pipeline can only roll forward, so a bad deploy is an outage until someone
manually reconstructs the previous version under pressure. *Fix:* a one-click rollback (redeploy the
previous tag) and an automatic rollback on health-check failure in the deploy step.

**No approval gate on production (or, conversely, gates on everything).** Either every merge auto-ships
to prod before the team can catch a bad one, or every trivial change needs manual approval and shipping
grinds to a halt. *Fix:* auto-deploy staging, require approval for production, and tune as maturity
grows.

**Deploying without running migrations (or running them unsafely).** The new code expects a schema the
database doesn't have, or migrations run in a way that locks the table. *Fix:* run migrations as an
explicit, ordered pipeline step using the expand/contract migrations from Stage 6, Chapter 06.

## AI Mistakes

CI/CD YAML is easy for assistants to produce and easy to produce *hollow* — valid workflows that run
but don't enforce or protect anything. Review generated pipelines against the four things (fast,
gated, secure, reversible), not "does the workflow have a green check."

### Claude Code: a pipeline with no cache, no gate enforcement, and no rollback

Asked to "set up CI/CD," Claude Code typically generates workflows that lint/test/build/deploy in
sequence and *run*, but with no dependency/layer caching (slow), no note that the checks must be made
*required* via branch protection (so the gate is optional), and a deploy step with no health check or
rollback — because "the workflow runs and deploys" looks complete.

**Detect:** no `cache:`/`cache-from`; no mention of branch protection / required checks; a deploy
`run:` that restarts services with no health check and no rollback; slow pipelines; red code that can
still merge.

**Fix:** require the missing discipline:

> Make this pipeline production-grade: cache dependencies and Docker layers so it's fast; tell me to set
> the CI job as a *required* status check with branch protection (the gate must be mechanical); and make
> the deploy health-check after restart and roll back to the previous image on failure. A deploy with no
> way back isn't done.

### GPT: secrets in the workflow and rebuilding on deploy

GPT-family models often paste credentials or config directly into the YAML (or into an `env:` block
with real values) and generate a deploy that does a fresh `docker build`/`git pull && build` on the
server — both of which "work" while leaking secrets and breaking build-once-promote-many.

**Detect:** literal tokens/keys/DSNs in the workflow or `env:`; no `${{ secrets.* }}`; a deploy step
that builds the image (rather than pulling a tagged one); different builds per environment; secrets
visible in logs.

**Fix:** require secret hygiene and artifact promotion:

> Move every credential to GitHub encrypted secrets (`${{ secrets.NAME }}`), scoped per environment,
> with least-privilege `permissions:` — nothing hardcoded, nothing echoed. Build the image once in CI,
> tag it by commit SHA, and have the deploy *pull and run that exact image* — don't rebuild on the
> server. The bytes tested must be the bytes deployed.

### Cursor: skipping the approval gate and deploying straight to prod

Editing a workflow inline to "add a deploy," Cursor tends to wire a push to `main` straight through to
production with no environment protection or approval, and often no staging step — because the local
edit is "make it deploy," not "make deployment safe" — so an unreviewed merge ships to prod
automatically.

**Detect:** a `deploy` job triggered on push to `main` targeting production with no `environment:` /
required reviewer; no staging deploy between merge and prod; no manual promotion/tag for releases;
production and staging using the same trigger with no gate.

**Fix:** require the environment gate and staging path:

> Don't deploy straight to production on merge. Auto-deploy to *staging* on merge to `main`, and gate
> *production* behind a GitHub Environment with a required reviewer, triggered by a release tag —
> deploying the same image staging validated. Production needs a human "go" and a real promotion step.

## Best Practices

**Make green mechanical.** Branch protection with the CI job as a required status check — red code
cannot merge. Enforcement is structural, not cultural.

**Keep the blocking pipeline fast.** Cache dependencies and Docker layers; run the required gate (lint,
types, unit) in a couple of minutes; push heavy suites (E2E, deep scans) to non-blocking stages. Fast
CI is respected CI.

**Build once, promote the same artifact.** One SHA-tagged image from CI; staging and production deploy
*that* image by tag/digest. Never rebuild per environment or on the server.

**Handle secrets as security-critical.** Encrypted, environment-scoped secrets; least-privilege
`GITHUB_TOKEN`/`permissions:`; never hardcoded, never logged. Route dependency updates (Dependabot)
through the same gate.

**Auto-deploy staging, gate production, always roll back.** Continuous deployment to staging; an
approval gate for production; a one-click and an automatic (health-check-triggered) rollback. Run
migrations as an explicit, safe pipeline step (Stage 6).

**Keep the pipeline DRY and in the repo.** Reusable workflows and composite actions define build and
deploy once; the whole pipeline is version-controlled and reviewed like application code.

## Anti-Patterns

**The Optional Gate.** CI runs but nothing is a required check, so red code merges whenever someone's in
a hurry. The tell: no branch protection; "the tests are failing but it's unrelated, I'll merge anyway."

**The Glacial Pipeline.** No caching, 20-minute runs, so people stop waiting and start bypassing. The
tell: dependencies reinstalled every run; PRs merged before CI finishes; "just skip CI this once."

**The Rebuild-on-Deploy.** Production builds its own image (or CI builds separately per environment), so
prod runs untested bytes. The tell: `docker build`/`git pull && build` in the deploy step; "it passed in
staging but broke in prod."

**The Hardcoded Secret.** Credentials in the workflow YAML or an `env:` block, published to anyone with
repo access. The tell: literal tokens in `.github/workflows/`; secrets in build logs.

**The One-Way Deploy.** No rollback, so every bad deploy is a manual firefight to reconstruct the last
good state. The tell: a deploy step that only rolls forward; "how do we get back to the previous
version?" asked *during* the incident.

**The Straight-to-Prod Push.** Merges auto-deploy to production with no staging and no approval, so a
missed bug ships instantly and widely. The tell: production deploy triggered on push to `main`; no
environment protection; no release/promotion step.

## Decision Tree

"I'm building (or reviewing) a CI/CD pipeline — what must be true?"

```
THE GATE (is quality enforced, not suggested?)
  Does CI run lint + types + tests on every PR?              no → add the CI job.
  Is that job a REQUIRED status check via branch protection? no → protect the branch. optional = ignored.
  Is `build` gated on the tests passing (needs: test)?       no → order it. no artifact from red code.

SPEED (will people actually wait for it?)
  Are dependencies AND Docker layers cached?                 no → add caching. slow CI gets bypassed.
  Is the blocking gate ~a few minutes (heavy suites deferred)? no → move E2E/deep scans off the gate.

THE ARTIFACT (build once, promote many?)
  Is ONE image built in CI, tagged by SHA?                   no → build once, tag by commit.
  Do staging AND prod deploy that SAME image (pull, not build)? no → promote the artifact; don't rebuild.

SECRETS (secure?)
  All credentials from ${{ secrets.* }}, scoped per env, masked, least-privilege token?
     no → move them to encrypted secrets; never hardcode or echo.

DELIVERY (safe promotion?)
  Auto-deploy to staging on merge; production behind an approval (environment + reviewer, tag trigger)?
     no → add the staging step and the production gate.
  Migrations run as an explicit, safe pipeline step (Stage 6)?  no → add it.

REVERSIBILITY (can you get back?)
  Does the deploy health-check and auto-roll-back on failure?   no → add it.
  Is manual rollback one click (redeploy previous tag)?         no → make it one.
  all yes → shipping is fast, gated, secure, and reversible. any no → fix before you rely on it.
```

## Checklist

### Implementation Checklist

- [ ] CI runs lint, type checks, and the test suite (against a real service DB) on every push/PR.
- [ ] Dependencies **and** Docker layers are cached; the blocking gate finishes in ~a few minutes.
- [ ] One image is built in CI, tagged by **commit SHA**; the build job is gated on tests passing.
- [ ] Staging and production **deploy the same tagged image** (pull, never rebuild on the server).
- [ ] All secrets come from GitHub encrypted secrets, environment-scoped and masked; tokens are
      least-privilege (`permissions:`), nothing hardcoded or echoed.
- [ ] Database migrations run as an explicit, ordered, safe pipeline step (Stage 6).
- [ ] The deploy health-checks after restart and **rolls back** to the previous image on failure.

### Architecture Checklist

- [ ] The protected branch has the CI job as a **required status check** (green is mandatory to merge).
- [ ] Staging auto-deploys on merge; production is gated behind a **required reviewer** (GitHub
      Environment) and a release-tag trigger.
- [ ] Build and deploy logic is DRY (reusable workflows / composite actions), defined once.
- [ ] Dependency updates (Dependabot) flow through the same gate.
- [ ] The whole pipeline is version-controlled and reviewed like application code.

### Code Review Checklist

- [ ] No missing caching (slow CI); no missing required-check/branch-protection (optional gate) — watch
      AI-generated workflows.
- [ ] No rebuild-on-deploy; the tested SHA image is what deploys.
- [ ] No hardcoded/echoed secrets; secrets are scoped and masked; tokens least-privilege.
- [ ] No straight-to-prod push without staging + approval; no deploy without a rollback path.
- [ ] Migrations are a deliberate, safe step, not implicit or skipped.

### Deployment Checklist

- [ ] The image deployed to production is the exact SHA that passed CI and staging (by digest).
- [ ] The production approval gate and rollback were tested (do a practice rollback before you need it).
- [ ] Migrations were verified safe (expand/contract — Stage 6) and run before/with the deploy as
      designed.
- [ ] Post-deploy health checks and monitoring (Chapter 07) confirm the release before it's declared
      done.

## Exercises

**1. Build the gate and prove it's mechanical.** Set up `ci.yml` (lint + types + tests with a service
Postgres and caching) for Invoicely's backend, then enable branch protection making it a required check.
Prove the gate works by opening a PR that fails a test and confirming it *cannot* be merged, and that a
green PR can. The artifact is the failing-PR screenshot and the protection settings.

**2. Promote one artifact through environments.** Extend the pipeline to build a SHA-tagged image once,
auto-deploy it to a staging environment on merge, and deploy the *same* image to production behind an
approval gate on a version tag. Prove — by digest — that the production image is byte-identical to the one
that passed CI. The artifact is the two workflows and the matching digests.

**3. Break a deploy and watch it roll back.** Implement the health-check-and-rollback deploy step, then
deploy an intentionally broken image (fails `/health`) and confirm the pipeline detects the failure and
automatically redeploys the previous version — with production never serving the broken build. The
artifact is the deploy log showing the failed health check and the rollback.

## Further Reading

- **GitHub Actions documentation — "Workflow syntax," "Using secrets," "Environments," and "Caching
  dependencies"** (docs.github.com/actions) — the authoritative reference for every construct in this
  chapter, including environment protection rules and encrypted secrets.
- **"Continuous Delivery" by Jez Humble & David Farley** (the foundational book) — the principles behind
  build-once-promote-many, deployment pipelines, and making release a non-event; the theory this chapter
  applies.
- **"Accelerate" by Forsgren, Humble & Kim** — the research linking CI/CD practices (deploy frequency,
  lead time, MTTR, change-fail rate) to organizational performance; the *why* behind fast, gated,
  reversible pipelines.
- **GitHub — "About protected branches" and "Securing your deployments"** (docs.github.com) — the exact
  mechanics of required status checks, environment approvals, and OIDC/least-privilege tokens.
- **Stage 7, Chapter 06 — Deploying to a VPS** — the next step: the server side of this pipeline —
  provisioning, first deploy, zero-downtime restarts, and operating the box the pipeline ships to.
</content>

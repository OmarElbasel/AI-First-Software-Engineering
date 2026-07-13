# Stage 7 — DevOps

Package, ship, expose, automate, and observe a production application on infrastructure you
control — turning the code from Stages 3–6 into a running system on the internet.

Stages 3–6 built the application: a FastAPI backend, a Next.js frontend, a React Native app,
and a production PostgreSQL schema. This stage is everything between "it runs on my laptop" and
"it serves real users reliably": containerizing the app so it runs identically everywhere,
orchestrating its services, putting a reverse proxy and TLS in front of it, automating build and
deployment through CI/CD, provisioning and operating a real server, and observing the whole
thing in production. The focus, as always, is engineering judgment — not "how to type a Docker
command" but which decisions make a deployment reproducible, secure, cheap, and debuggable at
3 a.m.

## Why this stage exists

Software that isn't deployed delivers no value, and software deployed badly is a liability. DevOps
is where most of the real-world failures live: the image that's different in prod than in CI, the
container running as root, the deploy with no rollback, the server whose disk fills silently, the
outage with no logs to explain it, the manual deployment that only one person knows how to do.
It's also where AI assistants are confidently wrong in ways that pass every demo — Dockerfiles
that build but bloat and run as root, Compose files with hardcoded secrets and no health checks,
CI pipelines with no caching or approvals, Nginx configs missing timeouts and security headers,
"just SSH in and `git pull`" deploys with no rollback. Each looks done and is an incident waiting
for real traffic. The judgment this stage teaches is what separates a deployment you can operate,
scale, and sleep behind from one you hope keeps working.

## Chapters

| # | Chapter | Status |
|---|---------|--------|
| 01 | [Linux for Production Servers](01-linux-for-production-servers.md) | Done |
| 02 | [Docker & Containerization](02-docker-and-containerization.md) | Done |
| 03 | [Docker Compose & Multi-Service Environments](03-docker-compose-and-multi-service-environments.md) | Done |
| 04 | [Nginx, Reverse Proxy, Domains & TLS](04-nginx-reverse-proxy-domains-and-tls.md) | Done |
| 05 | [CI/CD with GitHub Actions](05-ci-cd-with-github-actions.md) | Planned |
| 06 | [Deploying to a VPS](06-deploying-to-a-vps.md) | Planned |
| 07 | [Monitoring & Logging](07-monitoring-and-logging.md) | Planned |

These seven chapters cover the eleven curriculum topics for this stage. Linux (Ch 01) is the
foundation the rest stands on. Docker (Ch 02) and Compose (Ch 03) are containerization and
orchestration. Nginx, Domains, and SSL are taught together (Ch 04) as one idea — exposing the app
to the internet securely. GitHub Actions and CI/CD are the same idea — the tool and the practice —
so they share Ch 05. VPS (Ch 06) ties everything into one end-to-end deploy, and Monitoring and
Logging (Ch 07) are the two halves of observability.

## Boundaries with other stages

- **The application code** (FastAPI, Next.js) is **Stages 3–4**; this stage packages and deploys
  it, and points back rather than re-teaching it.
- **Database migrations** are designed in **Stage 6, Chapter 06**; this stage runs them in the
  CI/CD pipeline and the deploy (Ch 05–06).
- **Testing** in the pipeline is **Stage 8**; Ch 05 runs the test suite as a CI gate but the test
  strategy itself lives there.
- **Security hardening** (secrets management, OWASP, SSH/firewall hardening, image scanning depth)
  is **Stage 9**; this stage establishes the mechanics (non-root, TLS, least privilege) and points
  forward for the depth.
- **Scaling** (load balancing across many nodes, orchestration at scale, Kubernetes) is **Stage 11
  (System Design)**; this stage deploys and operates a single well-run server and containers, which
  is where most SaaS should start.

## Running example

The stage takes **Invoicely** — the FastAPI backend, Next.js frontend, PostgreSQL, and Redis built
in earlier stages — from source to a running production system: containerized into slim, non-root
images; orchestrated with Compose; fronted by Nginx with a real domain and Let's Encrypt TLS;
built, tested, and deployed by a GitHub Actions pipeline; running on a single Ubuntu VPS; and
observed with structured logs, metrics, health checks, and alerts — a deployment you can operate,
roll back, and debug.

## Learning outcome

You can operate a Linux server with confidence, containerize an application into a small secure
reproducible image, orchestrate its services with Compose, expose it to the internet through Nginx
with a domain and automatic TLS, automate build/test/deploy through a CI/CD pipeline with caching
and rollback, provision and run a production VPS end to end, and observe the running system through
logs, metrics, and alerts — shipping software you can maintain and sleep behind rather than hope
about.
</content>

# Starter Kits

Production-ready templates to clone when starting a new SaaS — so you never
begin from zero.

## How this differs from `examples/`

| | `examples/` | `starter-kits/` |
|---|---|---|
| Purpose | Reference implementation to **read and learn from** | Template to **clone and ship from** |
| Content | Invoicely, built out fully as the handbook describes | The same foundation, stripped of product-specific logic |
| Optimized for | Understanding the decisions | Starting a new product fast |

## Planned kit

**`saas-fastapi-nextjs/`** — the handbook's default stack, wired together:

- FastAPI backend: auth (JWT + refresh), users/organizations, settings,
  background jobs, structured logging
- Next.js frontend: app shell, auth flows, forms, data fetching conventions
- PostgreSQL with Alembic migrations
- Stripe payments skeleton (subscription-ready, no product logic)
- Docker Compose for local dev, Dockerfiles for production
- GitHub Actions: lint, test, build, deploy
- Test suite scaffolding (unit, integration, E2E) with CI wired in
- `CLAUDE.md` pre-configured for AI-first development on the codebase

## Build order (why this folder is still empty)

The starter kit is **extracted from the reference implementation, not written
from scratch**. First `examples/` gets the full Invoicely build — which
validates that every chapter's code actually composes into a working system.
Then the kit is derived from it by removing the invoice-specific product logic.
That way the template is proven code, not speculative boilerplate.

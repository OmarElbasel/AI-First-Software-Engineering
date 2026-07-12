# Production Readiness Checklist

Run before the first deploy of a service, and again before any high-risk
release (payments, auth changes, data migrations). The purpose is to answer
one question with evidence: **when this breaks at 2 AM, can it be diagnosed
and rolled back without heroics?**

Assume it will break. Production readiness is not the absence of bugs — it
is the presence of recovery paths.

## Configuration and Secrets

- [ ] All configuration comes from the environment; the same image/artifact runs in every environment
- [ ] Secrets live in a secret manager or deployment environment — never in the repo, image, or logs
- [ ] Every secret has a documented rotation path that does not require a code change
- [ ] Debug mode, verbose errors, and API docs endpoints are disabled or protected in production

## Database

- [ ] Migrations run as a deliberate deploy step — not automatically on app start with multiple instances
- [ ] Every migration has been tested against a production-sized dataset, not an empty dev database
- [ ] Automated backups exist AND a restore has actually been performed once — an untested backup is a hope, not a backup
- [ ] Connection pool limits are set and match what the database can actually serve

## Failure Handling

- [ ] Every external dependency (payment provider, email, third-party API) has a timeout — no unbounded waits
- [ ] Retries are bounded with backoff, and only on idempotent operations
- [ ] The service degrades deliberately when a dependency is down (clear error, queued work) rather than accidentally (hung requests, corrupt state)
- [ ] A health check endpoint exists and checks real dependencies, not just "process is up"

## Observability

- [ ] Logs are structured, include request IDs, and go somewhere searchable that survives a container restart
- [ ] Errors are captured with stack traces and context (user, request) — and someone is notified, not just recorded
- [ ] The golden signals are visible: request rate, error rate, latency, resource saturation
- [ ] You can answer "what changed?" — deploys are marked in monitoring, and the running version is identifiable

## Security

- [ ] TLS everywhere; HTTP redirects to HTTPS; internal services are not exposed publicly
- [ ] Rate limiting exists on authentication and other abuse-prone endpoints
- [ ] Dependencies are scanned for known vulnerabilities in CI
- [ ] CORS, cookies, and security headers are configured for the real domain — not left at the permissive defaults that made dev work

## Deploy and Rollback

- [ ] Deploys are reproducible from CI — no hand-built artifacts, no "deploy from my laptop"
- [ ] Rollback is tested and takes minutes: previous version redeployable, and compatible with the current schema
- [ ] A deploy that fails health checks does not receive traffic
- [ ] The first production deploy is boring: shipped small, watched live, with a person able to roll it back

## Knowledge

- [ ] Another person (or your future self) can deploy, roll back, and find the logs using only the README/runbook
- [ ] The irreversible decisions behind the system are recorded (see `templates/adr.md`)
- [ ] There is a written answer to "the site is down — what do I check first?"

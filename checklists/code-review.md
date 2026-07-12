# Code Review Checklist

Run against the full diff, not the summary. The goal of review is not to
find style nits — it is to stop defects, security holes, and unmaintainable
design before they merge, where fixing them is 10–100× cheaper than in
production.

Reviewing AI-generated code uses the same checklist plus the dedicated
section at the end. Generated code deserves *more* scrutiny, not less: it is
plausible by construction, which defeats the "this looks off" instinct that
catches human mistakes.

## Correctness

- [ ] The change does what the PR description claims — verified against the diff, not the title
- [ ] Failure paths are handled: timeouts, empty results, invalid input, partial failure
- [ ] External calls (payments, email, webhooks) are safe to retry — idempotent or deduplicated
- [ ] Concurrent access is considered where state is shared (double-submit, race on read-modify-write)
- [ ] Edge cases at boundaries are handled: zero, one, many, max; empty strings; timezone and encoding

## Design

- [ ] The change lives in the right layer (no business logic in route handlers, no HTTP concerns in services)
- [ ] It follows existing patterns in the codebase — or the PR explains why it deviates
- [ ] No new abstraction serving a single caller ("we might need it later" is not a caller)
- [ ] Public interfaces are minimal; nothing is exposed that callers shouldn't depend on

## Security

- [ ] All user input is validated at the boundary; database access is parameterized
- [ ] Authorization is checked on every new endpoint and query — not just authentication
- [ ] No secrets, tokens, or credentials in code, config, logs, or test fixtures
- [ ] Sensitive data (passwords, tokens, PII) never appears in log output or error messages

## Tests

- [ ] New behavior has tests that would fail if the behavior broke
- [ ] Failure modes are tested, not only the happy path
- [ ] Tests assert outcomes, not implementation details (they survive refactoring)
- [ ] No test was weakened, skipped, or deleted to make the suite pass

## Operations

- [ ] Schema migrations are backward-compatible, or the deploy order is documented
- [ ] New failure modes are observable: logged with context, or surfaced in metrics
- [ ] Performance is bounded: no unindexed query on a growing table, no N+1 introduced, no unbounded loop over external data

## AI-Generated Code

Each item is a known failure pattern of Claude Code, Codex/GPT, and Cursor.

- [ ] **Hallucinated APIs** — every unfamiliar method, parameter, and config key verified against real documentation, not assumed to exist
- [ ] **Happy-path bias** — the generated tests were read, not just run; they typically exercise only the success case
- [ ] **Silent scope creep** — the diff contains nothing beyond what was asked (no bonus refactors, renamed files, added endpoints, or "improved" unrelated code)
- [ ] **Invented requirements** — behavior not in the ticket (default values, retry counts, validation rules) was chosen deliberately, not accepted by default
- [ ] **Stale patterns** — generated code uses this codebase's current conventions, not an older idiom of the framework from training data
- [ ] **Confident error handling that isn't** — `try/except` blocks actually handle the error rather than logging and continuing in a corrupt state
- [ ] **Duplication over reuse** — the assistant didn't re-implement a helper, model, or validation that already exists in the codebase
- [ ] **Security defaults** — generated auth, CORS, cookie, and crypto settings were checked explicitly; assistants often produce permissive defaults that work in dev

<!--
TEMPLATE: Pull request description.

WHY: The PR description is the reviewer's context and the future debugger's
first search result. A PR that only says "add billing" forces the reviewer
to reverse-engineer intent from the diff — which is exactly how AI-generated
mistakes slip through.

WHEN: Any non-trivial PR. For a one-line typo fix, a sentence is enough.

To use as a GitHub default, copy the body (without these comments) into
.github/pull_request_template.md.
-->

## Summary

<!--
1–3 sentences: what this PR does and why now. Lead with the user-facing or
system-facing outcome, not the mechanics.
-->

## Why

<!--
The problem or requirement driving the change. Link the issue/ticket/ADR.
If the approach was chosen over an alternative, say so in one sentence —
it preempts the reviewer asking.
-->

## What Changed

<!--
Bullet list of meaningful changes, grouped by area. Call out anything a
reviewer would not expect from the title: schema migrations, config
changes, new dependencies, behavior changes to existing endpoints.
-->

-

## How It Was Tested

<!--
Evidence, not assertions. Name the tests added, paste the relevant command
output, describe the manual verification of the actual flow. "Tests pass"
without saying which tests cover the new behavior is not evidence.
-->

## AI Assistance

<!--
Which parts were AI-generated or AI-assisted, and what YOU verified:
edge cases checked, APIs confirmed against real docs, security review done.
This is not a confession — it tells the reviewer where to look hardest.
Generated code reviewed only by the tool that generated it has not been
reviewed.
-->

- Generated/assisted:
- Verified by author:

## Risk and Rollback

<!--
What could break, who is affected, and how to undo it. If rollback requires
more than reverting the commit (data migration, cache flush, config change),
spell it out here — during an incident nobody wants to derive it.
-->

- **Risk:**
- **Rollback:**

## Checklist

- [ ] Self-reviewed the full diff — including generated code — line by line
- [ ] Tests cover the new behavior and its failure modes, not just the happy path
- [ ] No secrets, credentials, or debug output in the diff
- [ ] Migrations are backward-compatible or the deploy order is documented
- [ ] Docs/ADRs updated if behavior or architecture changed

# Checklists

Operational checklists for moments where forgetting one thing costs real
money: merging code and shipping to production.

A checklist is not a substitute for judgment — it is a defense against the
failure mode where competent people skip a known step under time pressure.
Every item here exists because skipping it has caused a real production
incident somewhere. If an item never applies to your context, delete it from
your copy; a checklist people ignore is worse than none.

## Index

| Checklist | Run it when |
|---|---|
| [code-review.md](code-review.md) | Reviewing any pull request — with a dedicated section for AI-generated code |
| [production-readiness.md](production-readiness.md) | Before the first deploy of a service, and before high-risk releases |

## How to use them

- Run the checklist against evidence, not memory. "I'm sure the tests
  cover it" is not a checked box — open the tests.
- Checklists shrink with maturity: automate items into CI or linters
  whenever possible, then remove them from the manual list.
- These pair with the chapter checklists in `handbook/` — chapters teach
  the judgment, these compress it for the moment of action.

# Templates

Reusable starting points for engineering documents. Copy the file, delete the
guidance comments, fill it in.

Templates exist to remove the blank-page problem, not to enforce bureaucracy.
Every section in every template is there because skipping it has a known
failure mode. If a section genuinely does not apply, delete it — but know why.

## Index

| Template | Use it when | Do not use it when |
|---|---|---|
| [chapter-technical.md](chapter-technical.md) | Writing a handbook chapter about a technology or technique | The chapter teaches mindset or process — use the conceptual template |
| [chapter-conceptual.md](chapter-conceptual.md) | Writing a handbook chapter about mindset, judgment, or process | The chapter has real code to show — use the technical template |
| [adr.md](adr.md) | Making a decision that is expensive to reverse or that someone will question later | The choice is trivially reversible (a variable name, a minor library) |
| [pull-request.md](pull-request.md) | Opening any non-trivial pull request | — |
| [project-brief.md](project-brief.md) | Starting a new project or major feature, before prompting any AI | The work is a small, well-understood change |
| [claude-md-starter.md](claude-md-starter.md) | Setting up a repository for AI-first development | — |

## Rules

- The two chapter templates mirror the canonical section list in
  [`meta/00-CONSTITUTION.md`](../meta/00-CONSTITUTION.md). If they ever
  diverge, the Constitution wins.
- Guidance appears as HTML comments (`<!-- like this -->`) so it never
  renders. Delete the comments as you fill in each section.
- Templates are versioned with the repository. Improve them when a real
  document exposes a gap — do not fork private variants.

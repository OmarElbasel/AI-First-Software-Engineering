# Frontend Architecture & Folder Structure

## Introduction

This capstone chapter is about how to organize a frontend codebase so it stays
navigable and changeable as it grows from ten components to a thousand. It's the
structure that holds everything the stage built — typed components (Chapter 01),
routes (Chapter 02), the server/client boundary (Chapter 03), data (Chapter 04),
state (Chapter 05), forms (Chapter 06), and performance (Chapter 07) — into one
maintainable whole.

The core idea is not new: it's Stage 2, Chapter 02's "package by feature, not by
layer," applied to the frontend. Organize the codebase by *what the app does* —
`invoices/`, `customers/`, `dashboard/` — with each feature's components, hooks,
queries, and types colocated, rather than by *technical type* — a global
`components/`, `hooks/`, `utils/` where every feature's pieces are scattered and
mixed. The type-based structure (the tutorial default, and the AI default) works
for a demo and dissolves features into an undifferentiated pile as the app grows;
the feature-based structure keeps what changes together, together.

Alongside features sits one shared layer: the **design system** — generic UI
primitives (`Button`, `Input`, `Modal`, `Table`) that every feature uses and that
depend on no feature. Getting the boundary right — feature-specific components in
their feature, generic primitives shared, features talking through public
interfaces rather than each other's internals, and dependencies pointing one way —
is what makes a frontend scale. This chapter is Stage 1, Chapter 08's
maintainability and Stage 2's architecture, realized in the frontend.

## Why It Matters

Frontend codebases grow fast and rot faster than most, because the type-based
structure that feels natural at first actively worsens with scale:

- **Type-based folders scatter features.** With top-level `components/`, `hooks/`,
  and `utils/`, everything about invoicing is spread across all three (and mixed
  with everything about customers, payments, and the rest). To understand or change
  the invoices feature you open three folders and read a fraction of each; the
  feature has no home. This is Stage 2's package-by-layer problem, in the frontend.
- **The `utils.ts` junk drawer.** A single catch-all utilities module (or folder)
  accretes unrelated helpers until it's a dumping ground everything imports and
  nobody understands — a coupling magnet with no cohesion.
- **A polluted design system.** Without a clear boundary, feature-specific
  components leak into the shared `components/` folder, and generic primitives get
  duplicated per feature. The design system stops being a clean, reusable
  foundation and becomes another pile.
- **Cross-feature coupling and cycles.** Features importing each other's internals
  (or the shared layer importing a feature) couple things that should change
  independently and create import cycles — the frontend version of the distributed
  big ball of mud (Stage 2, Chapters 02 and 04).

Feature-based structure with a clean shared layer avoids all of this: a
feature-shaped change is a single-folder diff, the design system stays a reusable
leaf, and features stay independently changeable. The structure is an asset that
compounds, rather than a liability that grows.

The AI dimension: assistants default to the type-based tutorial structure
(`components/`, `hooks/`, `utils/`), blur the design-system/feature boundary
(feature components in the shared folder, duplicated primitives), and violate import
direction (cross-feature internal imports, shared importing features) — because those
are the shapes that saturate training data and the local edit never reveals the
whole structure.

## Mental Model

The frontend is features plus one shared foundation, with dependencies pointing one
way:

```
   ORGANIZE BY FEATURE (what the app does), not by TYPE (what a file is)

   ✗ TYPE-BASED (scatters features)      ✓ FEATURE-BASED (what changes together, together)
     components/  (everyone's)              features/
     hooks/       (everyone's)                invoices/   → components, hooks, queries,
     utils/       (junk drawer)                            api, types + a public index
     ...features dissolved...                 customers/
                                              dashboard/
                                            components/ui/  → SHARED design system
                                              (Button, Input, Modal — generic, no feature deps)
                                            lib/            → cross-cutting (api client, query setup)
                                            app/            → thin route components composing features

   DEPENDENCY DIRECTION (one way — like Stage 2)
     app (routes) ──► features ──► design system (components/ui) ──► (nothing feature-specific)
     features talk to each other ONLY through public interfaces, never internals.
     the design system NEVER imports a feature (it's a leaf).
```

Three principles carry the chapter:

**Organize by feature; colocate what changes together.** Each feature is a folder
holding its own components, hooks, queries, API calls, and types, so a feature-shaped
change touches one place. The structure screams the domain (Stage 2's "screaming
architecture"), not the framework. This is the single most important frontend
structural decision.

**Separate the shared design system from features, and keep it a leaf.** Generic UI
primitives (`Button`, `Input`, `Modal`, `Table`) live in one shared layer that every
feature uses and that depends on *no* feature. Feature-specific components stay in
their feature. The design system is the foundation; it must not import upward into
features, or the dependency graph cycles.

**Features talk through public interfaces; dependencies point one way.** A feature
exposes a public interface (a barrel `index.ts`) and hides its internals; other
features use that interface, never reach into internals, and the import direction runs
routes → features → design system (Stage 2, Chapters 02 and 04, applied to the
frontend). No cross-feature internal imports, no cycles.

A working definition:

> **A frontend scales when it's organized by feature (colocating each feature's
> components, hooks, data, and types) atop a shared design system that depends on no
> feature, with features communicating through public interfaces and dependencies
> pointing one way. The type-based `components/`+`hooks/`+`utils/` structure is the
> default that dissolves features as the app grows.**

## Production Example

**Invoicely's** frontend has grown to several features — invoices, customers,
dashboard, auth — plus the shared UI they all use. The type-based structure it started
with (a global `components/`, a growing `utils.ts`) has begun to hurt: the invoices
code is scattered, the shared folder mixes generic buttons with invoice-specific
widgets, and a couple of features import each other's internals.

We will restructure it feature-first: each feature a folder with its components, hooks,
queries, API, and types colocated behind a public `index.ts`; a `components/ui/` design
system of generic primitives that depends on no feature; thin route components in
`app/` that compose features; and `lib/` for genuinely cross-cutting concerns (the API
client, React Query setup from Chapter 04, auth). We'll show a feature's public
interface, the shared/feature boundary, and the import-direction rules — contrasted with
the type-based dumping-ground structure and why it doesn't scale. This is Stage 2,
Chapter 02 for the frontend; the payoff is the same (locality, extractability,
navigability).

## Folder Structure

```
web/src/
├── app/                          # ROUTES (Ch 02): thin components that COMPOSE features
│   └── (app)/invoices/page.tsx   #   imports from features/invoices, renders it
│
├── features/                     # BY FEATURE — what changes together lives together
│   ├── invoices/
│   │   ├── index.ts              #   PUBLIC interface (barrel): what other code may use
│   │   ├── InvoiceList.tsx       #   components (Ch 01)
│   │   ├── CreateInvoiceForm.tsx  #   (Ch 06)
│   │   ├── queries.ts            #   server state (Ch 04)
│   │   ├── api.ts                #   this feature's API calls
│   │   ├── types.ts              #   this feature's types
│   │   └── _internal/            #   private helpers — not exported from index.ts
│   ├── customers/  └─ ...
│   └── dashboard/  └─ ...
│
├── components/ui/                # SHARED DESIGN SYSTEM — generic, NO feature deps (a leaf)
│   ├── Button.tsx
│   ├── Input.tsx
│   └── Modal.tsx
│
└── lib/                          # CROSS-CUTTING: api client, query provider (Ch 04), auth
    ├── api-client.ts
    └── query.tsx
```

Why this shape:

- **`features/`** is the top level, organized by domain — everything for invoicing is
  in `invoices/`, so a feature change is a single-folder diff and the structure
  announces what the app does.
- **`index.ts` per feature** is the feature's public interface; `_internal/` (and
  un-exported files) are private. Other code imports from the feature's index, not its
  internals.
- **`components/ui/`** is the design system: generic primitives every feature uses and
  that import no feature — a leaf in the dependency graph.
- **`app/`** holds thin route components (Chapter 02) that compose features; **`lib/`**
  holds genuinely cross-cutting infrastructure, not a junk drawer.

## Implementation

**A feature's public interface (`features/invoices/index.ts`).** The barrel exports the
feature's public API; internals stay private. Other features and routes import from here.

```typescript
// features/invoices/index.ts — the feature's PUBLIC interface
export { InvoiceList } from "./InvoiceList";
export { CreateInvoiceForm } from "./CreateInvoiceForm";
export { useInvoices } from "./queries";
export type { Invoice, InvoiceStatus } from "./types";
// NOT exported: _internal/*, api.ts internals, helper components — private to the feature.
```

**A thin route composing a feature (`app/(app)/invoices/page.tsx`).** The route imports
from the feature's public interface and composes it; it holds no feature logic.

```tsx
import { InvoiceList } from "@/features/invoices";   // the PUBLIC interface, not internals
import { getInvoices } from "@/features/invoices/api";

export default async function InvoicesPage() {
  const invoices = await getInvoices({ status: "all" });   // server-fetch (Ch 04)
  return <InvoiceList invoices={invoices} />;               // compose the feature
}
```

**A shared design-system primitive (`components/ui/Button.tsx`).** Generic, typed,
feature-agnostic — it knows nothing about invoices or customers, so every feature can use
it and it depends on none.

```tsx
// Design system: generic, no feature dependencies (a leaf in the dependency graph).
import { type ButtonHTMLAttributes } from "react";

export function Button({
  variant = "primary",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: "primary" | "secondary" | "ghost" }) {
  return <button className={buttonStyles(variant)} {...props} />;
}
```

**Enforcing import direction (the convention, optionally lint-enforced).** Features don't
import each other's internals; the design system never imports a feature. Like Stage 2,
Chapter 04, this can be enforced in tooling rather than left to discipline.

```js
// eslint import rules (sketch): forbid the boundary violations
//  - features/* may NOT import another feature's internals (only its index.ts)
//  - components/ui/* may NOT import from features/*  (design system is a leaf)
//  - nothing imports from another feature's _internal/
// (e.g. eslint-plugin-boundaries / import/no-restricted-paths)
```

**The anti-pattern — type-based dumping grounds.** The structure that feels natural and
doesn't scale:

```
// ANTI-PATTERN: organized by TYPE — features dissolved
src/
├── components/     # InvoiceList, CustomerCard, DashboardChart, Button, Modal... (all mixed)
├── hooks/          # useInvoices, useCustomers, useAuth... (all mixed)
├── utils/
│   └── utils.ts    # 40 unrelated helpers — the junk drawer everything imports
└── ...             # to change "invoices" you touch components/, hooks/, utils/, and hunt
```

The difference is the whole chapter: feature-first, the invoices feature is one folder
with a public interface, the design system is a clean reusable leaf, and dependencies point
one way — so a feature change is local, the shared layer stays uncoupled, and the app is
navigable at any size. Type-based, invoicing is smeared across `components/`/`hooks/`/`utils/`,
the shared folder mixes generic and feature-specific, and `utils.ts` is a coupling magnet —
the same big-ball-of-mud rot Stage 2 warned about, in the frontend.

## Engineering Decisions

Five decisions define frontend structure.

### Organize by feature or by type?

**Options:** (1) by technical type (`components/`, `hooks/`, `utils/`); (2) by feature.

**Trade-offs:** type-based is the tutorial default and scatters every feature across the
type folders, so features have no home and changes touch many folders — worsening with scale.
Feature-based colocates each feature's pieces, so changes are local and the structure reflects
the domain, at the cost of deciding feature boundaries.

**Recommendation:** organize by feature (Stage 2, Chapter 02), with each feature's components,
hooks, queries, and types colocated. Reserve a small shared layer for genuinely cross-cutting
UI and infrastructure. Type-based grouping is the frontend package-by-layer mistake; avoid it
for anything beyond a tiny app.

### Where's the line between the design system and features?

**Options:** (1) one `components/` folder for everything; (2) a shared design system of generic
primitives, with feature-specific components in their features.

**Trade-offs:** one folder is simplest and blends generic reusable primitives with
feature-specific components, so the shared layer isn't reusable and features aren't cohesive.
A separated design system keeps generic primitives clean and reusable and feature components
with their feature, at the cost of judging what's generic.

**Recommendation:** a shared design system (`components/ui/`) of generic, feature-agnostic
primitives (Button, Input, Modal, Table), with feature-specific components living in their
feature. The test: "would three unrelated features use this unchanged?" — if yes, it's shared;
if it knows about a domain concept, it belongs to that feature.

### Feature public interfaces, or open internals?

**Options:** (1) import anything from anywhere; (2) features expose a public interface and hide
internals.

**Trade-offs:** open imports are frictionless and let any file depend on any other feature's
internals, coupling them and making refactors ripple. A public interface (barrel `index.ts`)
per feature keeps internals private and dependencies explicit, at the cost of maintaining the
interface.

**Recommendation:** each feature exposes a public interface and keeps internals private; other
features and routes import only the public interface (Stage 2, Chapters 02 and 04, for the
frontend). Enforce it with lint rules where possible. This keeps features independently
changeable and prevents the internal-coupling that makes a frontend un-refactorable.

### How much do you colocate?

**Options:** (1) split a component's parts across type folders; (2) colocate a component with
its hook, styles, and test.

**Trade-offs:** splitting by type puts a component's test, styles, and hook in separate folders,
so working on it means hopping around. Colocating keeps everything about a unit together
(easier to find, change, and delete), at the cost of larger feature folders.

**Recommendation:** colocate related files — a component with its styles, its test, and its
feature-specific hook — within the feature. Colocation is the maintainability default (Stage 1,
Chapter 08): things that change together live together, and a deleted feature deletes cleanly.

### How much design system up front?

**Options:** (1) build a comprehensive component library first; (2) start with a few primitives
and grow it as real needs appear.

**Trade-offs:** building a big design system up front is speculative — you build components and
variants before knowing what's needed (Stage 1, Chapter 07's over-engineering). Growing it
organically adds primitives when a real second use appears, at the risk of some early
inconsistency.

**Recommendation:** start with a minimal set of primitives and extract shared components when a
genuine second (ideally third) use appears — the rule of three from Stage 2, Chapter 02. Don't
build a speculative component library; let the design system grow from real reuse. Adopting an
existing primitive library (Radix, shadcn/ui) is a reasonable buy-vs-build shortcut (Stage 1,
Chapter 06) for the generic layer.

## Trade-offs

Frontend structure trades upfront organization for long-term navigability, and the calls mirror
Stage 2.

**Feature organization trades boundary decisions for locality.** Organizing by feature requires
deciding where features begin and end, and it returns single-folder changes, a domain-revealing
structure, and independently changeable features. The boundary judgment is the cost; the
locality is the payoff, and it compounds with size.

**A design system trades a boundary to maintain for reuse.** Separating generic primitives from
features means maintaining the boundary (what's shared vs feature-specific) and buys a clean,
reusable foundation and cohesive features. The boundary needs occasional adjudication; the
alternative (one mixed folder) doesn't scale.

**Public interfaces trade a little ceremony for decoupling.** Barrel files and hidden internals
are a small amount of maintenance and buy independently-refactorable features and an explicit
dependency graph. For a large or team-scale frontend the decoupling is worth it; for a tiny app
it may be more ceremony than needed — scale it to size.

**Structure discipline trades effort now for change-cost later.** Enforcing feature boundaries,
import direction, and colocation is ongoing effort (and lint config) that keeps the change-cost
curve flat (Stage 1, Chapter 08). Skipping it is cheaper today and pays compounding interest as
the codebase rots into a type-based pile. As always, match the rigor to the app's expected
lifetime and size.

## Common Mistakes

**Type-based structure.** Top-level `components/`, `hooks/`, `utils/` holding everything, so
features scatter and changes touch many folders. Fix: organize by feature; colocate each
feature's pieces.

**The `utils.ts` junk drawer.** A catch-all utilities module accreting unrelated helpers into a
coupling magnet. Fix: put helpers with the feature that uses them; keep `lib/` for genuine
cross-cutting infrastructure, not a dumping ground.

**A polluted design system.** Feature-specific components in the shared `components/` folder, or
generic primitives duplicated per feature. Fix: generic primitives shared, feature-specific
components in their feature; extract to shared only on real reuse.

**Cross-feature internal imports.** Features reaching into each other's internals, coupling them
and breaking refactors. Fix: features expose a public interface; import only that, never
internals.

**Wrong dependency direction / cycles.** The design system importing a feature, or import cycles
between features. Fix: dependencies point routes → features → design system; the design system is
a leaf; no cycles.

**Speculative design system.** A large component library built before it's needed. Fix: start
minimal, grow on real reuse (rule of three); consider buying a primitive library.

## AI Mistakes

Frontend structure is a whole-codebase property that no single file reveals, so an assistant —
seeing only the local edit — defaults to the type-based tutorial shape, blurs the shared/feature
boundary, and violates import direction. Review generated structure against the feature-based
architecture, not against whether an individual file looks fine.

### Claude Code: type-based structure and the utils junk drawer

Asked to add components or "organize the frontend," Claude Code creates or fills top-level
`components/`, `hooks/`, and `utils/` folders — scattering each feature across them — and grows a
catch-all `utils.ts`, because that structure dominates React tutorials and training data. Features
dissolve and the junk drawer accretes.

**Detect:** top-level `components/`/`hooks/`/`utils/` holding many features' files mixed together;
a growing `utils.ts`/`helpers.ts` of unrelated functions; a feature's files spread across type
folders rather than colocated.

**Fix:** require feature-based organization:

> Organize the frontend by feature, not by type. Put each feature's components, hooks, queries,
> and types together in `features/<feature>/`, not in global `components/`/`hooks/`/`utils/`
> folders. Reserve a shared `components/ui/` for generic primitives and `lib/` for genuine
> cross-cutting infrastructure — no `utils.ts` junk drawer.

### GPT: blurring the design-system/feature boundary

GPT-family models frequently put feature-specific components into the shared `components/`/UI
folder, or duplicate generic primitives (a second `Button`, another `Modal`) inside features,
because the shared/feature distinction isn't visible from a single component. The design system
gets polluted and primitives fragment.

**Detect:** a component that knows about a domain concept (e.g. `InvoiceStatusBadge`) living in
`components/ui/`; duplicated generic primitives across features; a shared folder mixing generic
and feature-specific components.

**Fix:** require a clear boundary:

> Shared `components/ui/` holds only generic, feature-agnostic primitives (Button, Input, Modal) —
> anything that knows about a domain concept belongs in its feature. Don't duplicate primitives
> per feature; reuse the shared one. The test: would three unrelated features use this unchanged?

### Cursor: import-direction violations and cycles

Wiring imports inline, Cursor tends to import one feature's internals from another, or import a
feature into the shared design system, creating cross-feature coupling and import cycles — because
the dependency direction isn't visible at the edit site.

**Detect:** an import from another feature's internal files (not its public `index.ts`); a
`components/ui/` file importing from `features/*`; circular imports between features; a lint/build
warning about import cycles.

**Fix:** require one-way dependencies through interfaces:

> Import another feature only through its public `index.ts`, never its internals. The design
> system (`components/ui/`) must not import from `features/*` — it's a leaf. Dependencies point
> routes → features → design system, with no cycles; enforce it with import lint rules.

## Best Practices

**Organize by feature and colocate.** Each feature is a folder with its components, hooks,
queries, API, and types together; a feature change is a single-folder diff, and the structure
reveals the domain (Stage 2, Chapter 02).

**Separate a clean design system and keep it a leaf.** Generic, feature-agnostic primitives in
`components/ui/` that import no feature; feature-specific components in their features. Grow the
design system on real reuse, or adopt a primitive library.

**Expose feature public interfaces; enforce one-way dependencies.** A barrel `index.ts` per
feature, internals private, imports through interfaces only, and dependency direction routes →
features → design system — enforced with lint rules where possible (Stage 2, Chapters 02 and 04).

**Keep `lib/` for cross-cutting infrastructure, not a junk drawer.** The API client, query setup
(Chapter 04), auth — genuinely shared infrastructure — go in `lib/`; feature helpers go with
their feature. No catch-all `utils.ts`.

**Match rigor to size, and document the conventions.** Apply the full discipline (interfaces,
enforced boundaries) to growing and team-scale frontends; keep a tiny app simpler. Document the
structure and import rules in `CLAUDE.md` so it survives contributors and assistants — this
chapter's structure is Stage 1, Chapter 08's maintainability made concrete.

## Anti-Patterns

**The Type-Based Pile.** Top-level `components/`/`hooks/`/`utils/` holding everything, features
dissolved across them. The tell: changing one feature means editing several type folders and
hunting for its pieces.

**The Junk Drawer.** A catch-all `utils.ts`/`helpers.ts` of unrelated functions that everything
imports. The tell: a utilities module that grows without bound and couples unrelated code.

**The Polluted Design System.** Feature-specific components in the shared UI folder, or duplicated
generic primitives per feature. The tell: `components/ui/` containing something that names a domain
concept, or three different `Button`s.

**The Feature Tangle.** Features importing each other's internals, with import cycles. The tell:
imports from another feature's internal files and a build warning about circular dependencies.

**The Upside-Down Dependency.** The design system importing a feature (a leaf depending on a
branch). The tell: a `components/ui/` file that imports from `features/*`.

## Decision Tree

"Where does this frontend code go?"

```
Is it specific to one feature (components, hooks, queries, types for invoices/customers/…)?
├── YES ──► in that FEATURE's folder (features/<feature>/), colocated. Export only its
│           public API from index.ts; keep the rest internal.
└── NO ──►
     │
     Is it a GENERIC, feature-agnostic UI primitive (Button, Input, Modal)?
     ├── YES ──► the DESIGN SYSTEM (components/ui/). It imports NO feature (it's a leaf).
     │           (Would 3 unrelated features use it unchanged? If no, it's a feature component.)
     └── NO ──►
          │
          Is it genuine cross-cutting INFRASTRUCTURE (api client, query setup, auth)?
          ├── YES ──► lib/.  (Not a utils.ts junk drawer.)
          └── Is it a ROUTE? ──► app/, as a THIN component that composes features (Ch 02).

   IMPORTS: another feature → only via its public index.ts (never internals).
            design system → never imports a feature. Direction: routes → features → design system.
```

## Checklist

### Implementation Checklist

- [ ] Code is organized by feature; each feature colocates its components, hooks, queries, API, and types.
- [ ] Each feature exposes a public interface (`index.ts`) and keeps internals private.
- [ ] The design system (`components/ui/`) holds only generic, feature-agnostic primitives and imports no feature.
- [ ] Cross-cutting infrastructure lives in `lib/`; there is no catch-all `utils.ts` junk drawer.
- [ ] Route components in `app/` are thin and compose features (Chapter 02).
- [ ] Related files (component, styles, test, feature hook) are colocated.

### Architecture Checklist

- [ ] Dependencies point one way: routes → features → design system; no cycles.
- [ ] Features import each other only through public interfaces, never internals (lint-enforced where possible).
- [ ] The design system is a leaf and reusable; feature-specific components aren't in it.
- [ ] The design system grew from real reuse (or an adopted library), not speculation.
- [ ] The structure and import rules are documented in `CLAUDE.md`.

### Code Review Checklist

- [ ] No feature code added to global type-based folders or a `utils.ts` junk drawer (watch AI diffs).
- [ ] No feature-specific component placed in the shared design system, and no duplicated primitives.
- [ ] No import of another feature's internals (only its public interface).
- [ ] No design-system file importing a feature; no import cycle introduced.
- [ ] New shared components earned their place by real reuse, not speculation.

*(A Deployment Checklist is not applicable to this chapter; frontend build/deploy is Stage 7.)*

## Exercises

**1. Restructure by feature.** Take a type-based frontend (a global `components/`/`hooks/`/`utils/`
— write a small one, or have an assistant generate "a React app with a components and hooks folder")
and restructure it feature-first with a shared design system and feature public interfaces. The
artifact is the before/after tree and a note on which change got cheaper (feature changes) and what
the design system now cleanly holds.

**2. Draw the boundary.** Take a mixed `components/` folder and classify each component as
design-system (generic) or feature-specific, moving each to its correct home, and de-duplicate any
repeated primitives. The artifact is the classification and the resulting structure, with the "would
three unrelated features use this?" test applied.

**3. Enforce import direction.** Add lint rules (e.g. eslint-plugin-boundaries / import restrictions)
that forbid cross-feature internal imports and the design system importing features, then
deliberately introduce a violation and confirm it's caught. The artifact is the rules and the caught
violation — the frontend version of Stage 2, Chapter 04's enforced boundaries.

## Further Reading

- **Stage 2, Chapter 02 — Feature-Based & Vertical Slice Architecture** (this handbook) — the
  architectural principle this chapter applies to the frontend; read it for the deeper rationale on
  organizing by feature and the share-vs-duplicate judgment.
- **"Screaming Architecture"** (Robert C. Martin, blog.cleancoder.com) — the case that a codebase's
  structure should announce what it does, not which framework it uses; the justification for
  feature-first folders.
- **Bulletproof React** (github.com/alan2207/bulletproof-react) — a well-regarded, opinionated
  reference architecture for React apps: feature folders, a shared components layer, and enforced
  import boundaries, in practice.
- **shadcn/ui and Radix Primitives** (ui.shadcn.com; radix-ui.com) — practical approaches to the
  design-system layer (owning accessible primitives in your codebase vs depending on a library); the
  buy-vs-build (Stage 1, Chapter 06) option for the generic UI foundation.

# Building UIs with React & TypeScript

## Introduction

This chapter is the foundation of the frontend stage: how to build user
interfaces out of typed React components. React and TypeScript are taught
together because in a production frontend they are inseparable — the typed
component is the unit that every later chapter (rendering, data, state, forms) is
built from, and untyped React is where most frontend bugs and most AI mistakes
live.

React's whole model is one idea: **the UI is a function of state.** You describe
what the screen should look like for a given state, and React figures out the DOM
changes to get there. You do not imperatively manipulate the DOM; you change
state and let React re-render. Almost every React mistake — including the ones
assistants make constantly — comes from fighting that model: reaching for effects
to push state around imperatively, duplicating state that should be derived,
breaking the reconciliation that makes re-rendering cheap.

TypeScript is the other half. It is not optional polish on a real frontend — it
is what catches an entire class of errors at compile time instead of in
production, and it matters *more* in an AI-first workflow, because it turns "the
assistant passed the wrong prop shape" from a runtime surprise into a red squiggle
before the code ever runs. This chapter builds the habit of typed components and
the discipline of working *with* React's model instead of against it.

## Why It Matters

The frontend is the part of the system users actually touch, and its bugs are the
most visible — a wrong number on a dashboard, a form that silently drops input, a
list that shows stale data after an edit. Many of those bugs trace to two root
causes this chapter addresses: fighting React's state model, and skipping the type
safety that would have caught the mistake.

Fighting the model is expensive because React re-renders on state change, and
misusing that mechanism produces bugs that are hard to reason about: an effect that
derives state introduces an extra render and a chance to be out of sync; state
copied from props goes stale when the props change; a list keyed by array index
shows the wrong row's data after a reorder. These are not exotic — they are the
most common React defects, and they come from treating React as if you were
imperatively updating the screen rather than declaring it.

Skipping types is expensive because the frontend is a web of data passed between
components — props, event payloads, API responses — and without types, a wrong
shape anywhere surfaces as `undefined is not a function` in production, far from
its cause. Types make the data flow checkable: the compiler proves the invoice you
passed has the fields the component reads.

The AI dimension is sharp because React is the domain assistants are most fluent
in and most foot-gunned in. They reach for `useEffect` to push state around
(fighting the model), type props as `any` (throwing away the safety that would
catch their own errors), and use unstable keys and inline props (breaking
reconciliation). Every one produces a UI that renders correctly in the first
screenshot and misbehaves the moment state changes.

## Mental Model

React's core loop, and the rule that follows from it:

```
   UI = f(state)

   state changes ──► React RE-RENDERS the affected components ──► reconciles
   ──► updates only the changed DOM. You NEVER touch the DOM yourself.

   DATA FLOW is one-directional:
        props DOWN (parent → child)      events UP (child → parent, via callbacks)

   ┌──────────── Parent (owns state) ────────────┐
   │  state ─► passed as props ─► Child            │
   │  Child fires onEvent ─► Parent updates state ─┘ (re-render)
   └───────────────────────────────────────────────┘

   DERIVED values are COMPUTED during render, never stored in state:
        ✗  useEffect(() => setTotal(sum(items)), [items])   // extra render, can desync
        ✓  const total = sum(items)                          // just compute it
```

Four principles keep you working *with* React, not against it:

**Derive, don't duplicate.** If a value can be computed from existing state or
props, compute it during render — do not store it in its own state and sync it with
an effect. Duplicated state is state that can disagree with itself; the classic bug
is a total that doesn't match the line items because an effect didn't fire.

**Effects are for synchronizing with external systems, not for data flow.**
`useEffect` exists to reach outside React — a subscription, a non-React widget, a
browser API. It is *not* for transforming props into state, responding to a user
action (that's an event handler), or fetching data when the framework offers a
better way (Chapter 04). "You might not need an effect" is the single
highest-leverage React lesson.

**State lives at the lowest common owner, and props flow down.** Put state in the
component that needs it; lift it only as high as the nearest common ancestor of the
components that share it. Data flows down as props and back up as event callbacks —
one direction, always, which is what makes the flow traceable.

**Type the boundaries.** Every component's props, every event payload, every API
shape is typed. TypeScript then proves the data flowing through the tree is
well-formed, and — crucially in an AI workflow — catches a wrong shape the instant
an assistant introduces it, at compile time.

A working definition:

> **A React UI is a function of state: you declare what the screen should be, and
> React renders it. Build it from typed components, derive values instead of
> duplicating them into state, reserve effects for external systems, and let props
> flow down and events flow up. Most React bugs are the result of fighting this
> model.**

## Production Example

**Invoicely's** frontend needs an invoice list: a table of the account's invoices,
each row showing the customer, amount, and a status badge, selectable to open the
detail view. It is ordinary UI and full of the decisions this chapter is about —
how to decompose it into components, what to type, where the selection state lives,
and how to compute the status badge without an effect.

We will build it as typed, composed components: a presentational `InvoiceRow`, a
`StatusBadge` whose variants are a typed union, and a list that keys rows correctly
and lifts selection state to the right owner. Then we'll contrast it with the
version an assistant tends to produce — status derived through a `useEffect`, props
typed as `any`, rows keyed by index — to make the difference concrete. The domain
is trivial; the point is the model and the types.

## Folder Structure

```
web/src/
├── features/invoices/
│   ├── InvoiceList.tsx       # owns selection state; renders rows
│   ├── InvoiceRow.tsx        # presentational: typed props, no state
│   ├── StatusBadge.tsx       # typed variant component (discriminated union)
│   └── types.ts              # Invoice, InvoiceStatus — shared types
└── components/               # cross-feature UI primitives (Button, Table, ...)
```

Why this shape (developed fully in Chapter 08): the frontend is organized by
**feature** (mirroring Stage 2, Chapter 02), so everything for invoices lives
together; shared, generic UI primitives live in `components/`. Types shared across
a feature live with it.

## Implementation

**Shared types (`types.ts`).** The status is a *union of literals*, not `string` —
so the compiler knows every possible value and can check exhaustiveness.

```typescript
export type InvoiceStatus = "draft" | "sent" | "paid" | "void";

export interface Invoice {
  id: number;
  customerName: string;
  total: number;          // minor units or a typed Money in a real app
  status: InvoiceStatus;
  createdAt: string;
}
```

**A typed variant component (`StatusBadge.tsx`).** The `status` prop is the union,
so passing an invalid status is a compile error, and the `switch` is checked for
exhaustiveness — add a status later and TypeScript flags every place that must
handle it.

```tsx
import type { InvoiceStatus } from "./types";

const STYLES: Record<InvoiceStatus, string> = {
  draft: "bg-gray-100 text-gray-700",
  sent: "bg-blue-100 text-blue-700",
  paid: "bg-green-100 text-green-700",
  void: "bg-red-100 text-red-700",
};

export function StatusBadge({ status }: { status: InvoiceStatus }) {
  return <span className={`rounded px-2 py-0.5 text-xs ${STYLES[status]}`}>{status}</span>;
}
```

**A presentational row (`InvoiceRow.tsx`).** Typed props, no state, events up via a
callback. It renders what it's given and reports clicks; it decides nothing.

```tsx
import type { Invoice } from "./types";
import { StatusBadge } from "./StatusBadge";

interface InvoiceRowProps {
  invoice: Invoice;
  selected: boolean;
  onSelect: (id: number) => void;   // event UP to the parent
}

export function InvoiceRow({ invoice, selected, onSelect }: InvoiceRowProps) {
  return (
    <tr
      aria-selected={selected}
      className={selected ? "bg-slate-50" : undefined}
      onClick={() => onSelect(invoice.id)}
    >
      <td>{invoice.customerName}</td>
      <td>{formatMoney(invoice.total)}</td>            {/* derived: computed, not stored */}
      <td><StatusBadge status={invoice.status} /></td>
    </tr>
  );
}
```

**The list — state at the right owner, correct keys (`InvoiceList.tsx`).**
Selection is state shared by the rows, so it lives in their common owner, the list.
Rows are keyed by a *stable id*, never the array index. Derived values (the sorted
order, the selected invoice) are computed during render.

```tsx
import { useState } from "react";
import type { Invoice } from "./types";
import { InvoiceRow } from "./InvoiceRow";

export function InvoiceList({ invoices }: { invoices: Invoice[] }) {
  const [selectedId, setSelectedId] = useState<number | null>(null);

  // Derived during render — NOT stored in state, NOT synced via an effect.
  const sorted = [...invoices].sort((a, b) => b.createdAt.localeCompare(a.createdAt));

  return (
    <table>
      <tbody>
        {sorted.map((invoice) => (
          <InvoiceRow
            key={invoice.id}                 // STABLE id, never the array index
            invoice={invoice}
            selected={invoice.id === selectedId}
            onSelect={setSelectedId}
          />
        ))}
      </tbody>
    </table>
  );
}
```

**The contrast — what an assistant tends to produce.** Every line here is a common
React mistake, and each renders fine in the first screenshot:

```tsx
// ANTI-PATTERN: fighting React's model
function InvoiceListBad({ invoices }: { invoices: any }) {     // any → no type safety
  const [sorted, setSorted] = useState([]);
  useEffect(() => {                                            // effect to DERIVE state...
    setSorted([...invoices].sort(...));                        // ...extra render, can desync
  }, [invoices]);
  return sorted.map((inv: any, i: number) =>                   // any again
    <InvoiceRow key={i} ... />                                 // index key → wrong-row bugs on reorder
  );
}
```

The differences are the whole chapter: the sorted list is *computed*, not stored via
an effect (no desync, no extra render); the props are *typed* (the compiler checks
every shape); and rows are *keyed by id* (reordering or deleting a row updates the
right DOM). The good version works with React's model; the bad one imperatively
pushes state around and throws away the safety that would have caught its own bugs —
which is exactly the version generation produces by default.

## Engineering Decisions

Five decisions define a React component's quality.

### How is the UI decomposed into components?

**Options:** (1) few large components; (2) many tiny components; (3) decomposition by
responsibility, with presentational and container roles distinguished.

**Trade-offs:** large components are quick to write and become unreadable, untestable
tangles of concerns. Excessive tiny components fragment logic across files with
props-drilling between them (Stage 1, Chapter 07's shallow-module sprawl, in JSX).
Decomposition by responsibility — a component does one thing, presentational
components render and report while a container owns state and data — keeps each piece
comprehensible.

**Recommendation:** decompose by responsibility, and keep most components
presentational (typed props in, events out, no state or side effects) with state and
data concentrated in a few container components. Presentational components are trivial
to reason about, reuse, and test; push complexity up into a small number of owners.

### Where does state live?

**Options:** (1) all state high up (e.g. in a top container); (2) state colocated at
the lowest component that needs it, lifted only when shared.

**Trade-offs:** hoisting all state creates props-drilling and re-renders large trees on
every change. Colocating keeps state near its use (fewer re-renders, clearer ownership)
but requires lifting when two components come to share it — a refactor you do when the
need appears.

**Recommendation:** colocate state at the lowest common owner of the components that use
it, and lift only when sharing demands it. This is the "state colocation" principle: the
closer state lives to where it's used, the easier the component is to understand and the
narrower each re-render. (Genuinely global state is Chapter 05.)

### Compute derived values, or store them in state?

**Options:** (1) store derived values in their own state, synced with an effect; (2)
compute them during render.

**Trade-offs:** storing derived state feels efficient and is a bug factory — the stored
copy can disagree with its source, the syncing effect adds a render and a dependency to
get wrong, and you now have two sources of truth. Computing during render is always
consistent and usually plenty fast; if a computation is genuinely expensive, `useMemo`
caches it without making it separate state.

**Recommendation:** compute derived values during render; never mirror props or other
state into `useState` and sync with `useEffect`. Reach for `useMemo` only when profiling
shows a computation is actually expensive. Duplicated state is the root of a large share
of React bugs.

### How strict is the TypeScript?

**Options:** (1) loose (`any`, casts, `strict: false`); (2) strict typing throughout.

**Trade-offs:** loose typing is faster to write and forfeits the entire benefit of
TypeScript — `any` propagates and silences the compiler exactly where you need it.
Strict typing costs the effort of describing shapes and returns compile-time proof that
the data flow is correct, which is worth far more on a frontend threaded with passed
data.

**Recommendation:** `strict: true`, no `any` (use `unknown` and narrow when a type is
truly unknown), model finite sets as literal unions (like `InvoiceStatus`) so the
compiler checks exhaustiveness, and type every prop and event. In an AI workflow this is
non-negotiable: strict types are how you catch an assistant's shape errors at compile
time instead of in production.

### When do you optimize re-renders (`useMemo`/`useCallback`/`memo`)?

**Options:** (1) memoize aggressively by default; (2) memoize only where profiling shows
a problem.

**Trade-offs:** default memoization adds noise and complexity everywhere, often for no
measurable gain, and can even hurt (the memo bookkeeping isn't free). Measured
memoization keeps the code clean and targets the actual hot spots, at the cost of having
to measure.

**Recommendation:** write clean, correct components first; add `memo`/`useMemo`/
`useCallback` only where the React Profiler shows a real re-render problem (a large list,
an expensive child). Premature memoization is Stage 1, Chapter 07's premature
optimization, in React. Correct keys and colocated state prevent more re-render problems
than memoization fixes.

## Trade-offs

React and TypeScript buy productivity and safety at real, contextual costs.

**React's model trades directness for consistency.** Declaring UI as a function of state
means you can't just "change that one element" — you change state and re-render, which is
more indirect than imperative DOM manipulation but keeps the UI consistent with its data
by construction. The cost is the discipline to route everything through state; the
payoff is not fighting a web of manual DOM updates.

**Strict typing trades upfront effort for caught errors.** Describing every shape is real
work, and it returns compile-time correctness and refactoring safety — change a type and
the compiler lists every place to update. For a throwaway prototype the effort can
outweigh the benefit; for anything maintained, and anything an AI touches, it pays for
itself quickly.

**Component granularity trades reuse against indirection.** Smaller components are more
reusable and testable and add file-hopping and props-passing; larger ones are more
self-contained and less reusable. The right grain is per responsibility, not a fixed
size — and it's a judgment that shifts as a component grows.

**Computing over caching trades CPU for simplicity.** Deriving values every render is
simpler and correct and does more work than caching; for the vast majority of
computations that work is negligible. Only when profiling shows a specific computation is
expensive does caching (`useMemo`) earn its complexity — the default is compute.

## Common Mistakes

**Using `useEffect` to derive or sync state.** An effect that sets state from props or
other state — an extra render and a chance to desync. Fix: compute the value during
render; effects are for external systems only.

**Duplicating state.** Copying props into `useState`, or storing a value that could be
computed — two sources of truth that drift. Fix: derive, don't duplicate; keep one source
of truth.

**`any` and type escapes.** Props typed `any`, `as` casts, `@ts-ignore` — the compiler
silenced exactly where it's needed. Fix: strict types, `unknown` + narrowing for genuinely
unknown data, literal unions for finite sets.

**Array index as `key`.** Keying list items by index, so reordering, inserting, or
deleting maps state and DOM to the wrong item. Fix: key by a stable unique id.

**State in the wrong place / prop drilling.** State hoisted far above its use (re-renders,
drilling) or trapped below where a sibling needs it. Fix: colocate at the lowest common
owner; lift when shared.

**Premature memoization.** `useMemo`/`useCallback`/`memo` sprinkled everywhere without
measurement, adding complexity for no gain. Fix: measure with the Profiler; optimize the
proven hot spots only.

## AI Mistakes

React is the domain assistants are most fluent in and most foot-gunned in — the generated
component renders correctly in the first screenshot and misbehaves the moment state
changes, which a static look never triggers. Review generated React for how it behaves on
the *second* render, not the first.

### Claude Code: `useEffect` to push state around

Asked to derive or transform data, Claude Code reaches for `useEffect` — an effect that
sorts a list into state, computes a total into state, or copies a prop into state — because
that reads like a clear "when X changes, update Y" instruction. It fights React's model:
an extra render, a dependency array to get wrong, and two sources of truth that can
desync.

**Detect:** a `useEffect` whose only job is to `setState` from props or other state;
effects used for data transformation or in response to user actions rather than to
synchronize with something outside React.

**Fix:** eliminate the effect:

> Don't use `useEffect` to derive or transform state — compute the value during render
> instead (`const total = sum(items)`), and handle user actions in event handlers.
> Reserve effects for synchronizing with external systems (subscriptions, non-React
> widgets, browser APIs). Most effects that call `setState` from props are bugs.

### GPT: `any` and discarded type safety

GPT-family models frequently type props as `any` (or omit types, or reach for `as` casts
and `@ts-ignore`) to make the code compile quickly — discarding exactly the type safety
that would have caught the shape errors it's prone to. The component runs and the compiler
is proving nothing.

**Detect:** `any` on props or state, `as` casts, `@ts-ignore`/`@ts-expect-error`, untyped
event handlers, `string` where a literal union belongs.

**Fix:** require strict typing:

> Type every prop, event, and piece of state — no `any` (use `unknown` and narrow if truly
> unknown), no casts to silence errors, no `@ts-ignore`. Model finite sets as literal
> unions so the compiler checks exhaustiveness. The types must actually constrain the data.

### Cursor: unstable keys and inline props breaking reconciliation

Editing lists and JSX inline, Cursor tends to key list items by array index and pass
freshly-created inline objects/arrays/functions as props, because those are the shortest
local expressions. Index keys cause wrong-item bugs on reorder/delete, and new-every-render
props defeat memoization and trigger avoidable re-renders.

**Detect:** `key={index}` (or `key={i}`); inline object/array literals or arrow functions
passed as props to list items or memoized children; a `.map` whose items carry component
state and are keyed by position.

**Fix:** require stable keys and props:

> Key list items by a stable unique id, never the array index — index keys corrupt state and
> DOM on reorder or delete. Avoid creating new objects/arrays/functions inline as props to
> list items or memoized children; hoist or memoize them so identity is stable across
> renders.

## Best Practices

**Work with React's model: UI is a function of state.** Change state and let React render;
never manipulate the DOM directly. Data flows down as props, events flow up as callbacks —
keep it one-directional.

**Derive, don't duplicate; reserve effects for external systems.** Compute derived values
during render (memoize only if measured expensive), keep one source of truth, and use
`useEffect` only to synchronize with things outside React — not for data flow or user
actions.

**Type strictly, at every boundary.** `strict: true`, no `any`, literal unions for finite
sets, typed props and events. Strict types are the compile-time net that catches shape
errors — including an assistant's — before they ship.

**Colocate state and decompose by responsibility.** Put state at the lowest common owner;
keep most components presentational (props in, events out) with state concentrated in a few
containers. Key lists by stable ids.

**Optimize only what you measure.** Write clean, correct components; reach for
`memo`/`useMemo`/`useCallback` only where the Profiler shows a real re-render cost. Correct
keys and colocated state prevent most re-render problems before memoization is needed.
Document component/typing conventions in `CLAUDE.md`.

## Anti-Patterns

**The Effect-Driven Component.** State pushed around with `useEffect` — derived values and
prop-to-state copies synced by effects, producing extra renders and desync. The tell: effects
whose bodies are mostly `setState` from props/state.

**The `any` Frontend.** Types present in name only — `any`, casts, and `@ts-ignore`
throughout — so the compiler proves nothing. The tell: `any` on props and API data, and
runtime `undefined` errors that types should have caught.

**The Duplicated State.** The same fact stored in two places (a prop copied into state, a
derived value stored), drifting out of sync. The tell: a value that's sometimes right and
sometimes stale depending on which update fired.

**The Index Key.** List items keyed by position, so component state and DOM attach to the
wrong item after a reorder or delete. The tell: `key={index}` on a list whose items have
state or can be reordered.

**The Memoization Cargo Cult.** `memo`/`useMemo`/`useCallback` everywhere without
measurement — complexity and bookkeeping for no proven gain. The tell: pervasive memoization
and no profiler evidence that any of it helps.

## Decision Tree

"I'm building a component — how do I get it right?"

```
DATA
├─ Can this value be computed from props/state? ──► COMPUTE it during render.
│    (Do NOT store it in state or sync it with useEffect. useMemo only if measured slow.)
└─ Is this genuinely independent state? ──► useState, at the LOWEST common owner.
     (Lift only when a sibling needs to share it.)

EFFECTS
└─ Am I reaching for useEffect? Is it synchronizing with something OUTSIDE React
   (subscription, browser API, non-React widget)?
   ├─ YES ──► ok, an effect is right.
   └─ NO (deriving state / responding to a user action) ──► NOT an effect.
        derive during render, or handle it in an event handler.

TYPES
└─ Every prop, event, and API shape is typed. No any (use unknown + narrow).
   Finite sets ──► literal unions (exhaustiveness-checked).

LISTS
└─ key = a stable unique id. NEVER the array index.

PERFORMANCE
└─ Only after it's correct: does the Profiler show a real re-render cost?
   ├─ YES ──► memo/useMemo/useCallback the proven hot spot.
   └─ NO ───► leave it clean. (Premature memoization is a cost, not a win.)
```

## Checklist

### Implementation Checklist

- [ ] Derived values are computed during render, not stored in state or synced via `useEffect`.
- [ ] `useEffect` is used only to synchronize with external systems, never for data flow or user actions.
- [ ] Every prop, event, and API shape is typed; no `any`, casts, or `@ts-ignore`; finite sets are literal unions.
- [ ] State is colocated at the lowest common owner; data flows down, events flow up.
- [ ] List items are keyed by a stable unique id, never the array index.
- [ ] Memoization appears only where profiling showed a real re-render cost.

### Architecture Checklist

- [ ] Components are decomposed by responsibility; most are presentational, with state in a few containers.
- [ ] `strict: true` is on and there are no type escapes across the codebase.
- [ ] Shared types live with their feature; the data flow through the tree is fully typed.
- [ ] No prop drilling that signals misplaced state (candidate for lifting or Chapter 05's state management).
- [ ] Component and typing conventions are documented in `CLAUDE.md`.

### Code Review Checklist

- [ ] No `useEffect` that merely sets state from props/other state (watch AI diffs).
- [ ] No `any`/cast/`@ts-ignore` silencing the compiler.
- [ ] No duplicated/mirrored state; one source of truth.
- [ ] No array-index keys on stateful or reorderable lists.
- [ ] No inline objects/arrays/functions passed as props to memoized children or list rows.

*(A Deployment Checklist is not applicable to this chapter; frontend deployment is Stage 7.)*

## Exercises

**1. Kill the effect.** Take a component that derives state with `useEffect` (write one, or
have an assistant generate "show a sorted, filtered list with a computed total"). Rewrite it
to compute the derived values during render with no effect and no mirrored state. The
artifact is the before/after and a one-line note on the desync bug the effect version could
produce.

**2. Type the boundary.** Take an untyped or `any`-typed component tree (an invoice list is
ideal) and type it strictly end to end: props, events, and the invoice/status shapes as
literal unions. Then intentionally pass a wrong shape and confirm the compiler catches it.
The artifact is the typed code and the compile error you triggered.

**3. Break and fix reconciliation.** Build a reorderable list keyed by index where each row
holds local state (say, an "expanded" toggle), reorder it, and observe the state attaching to
the wrong row. Fix it with stable keys. The artifact is the demonstrated bug and the fix — the
most memorable way to internalize why keys matter.

## Further Reading

- **React documentation — "Thinking in React," "You Might Not Need an Effect," and "Keeping
  Components Pure"** (react.dev) — the official, modern guidance on exactly this chapter's
  core ideas: deriving state, avoiding effects, and working with React's model. "You Might Not
  Need an Effect" is essential and directly targets the most common AI mistake.
- **TypeScript documentation — Handbook, and the React+TypeScript Cheatsheet**
  (typescriptlang.org; react-typescript-cheatsheet.netlify.app) — how to type components,
  props, events, and hooks properly, and the patterns (discriminated unions, generics) that
  make components type-safe.
- **Overreacted — "A Complete Guide to useEffect"** (Dan Abramov, overreacted.io) — a deep,
  canonical explanation of how effects actually work and why most uses are wrong; read it once
  and effects stop being mysterious.
- **Josh Comeau — "Why React Re-Renders"** (joshwcomeau.com) — a clear model of the render and
  reconciliation cycle, which is the foundation for keys, memoization, and every performance
  decision in Chapter 07.

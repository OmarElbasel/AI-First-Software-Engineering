# State Management

## Introduction

"State management" is the frontend topic most likely to be over-engineered,
because the phrase suggests a single big problem solved by a single big tool — a
global store holding everything. The reality this chapter teaches is the opposite:
**there are several distinct kinds of state, each with its own right home, and most
of what teams reach for a global store to hold does not belong there.** The skill
is not choosing a state library; it is classifying each piece of state and routing
it to where it belongs.

The kinds:

- **Server state** — data fetched from the backend. It belongs in React Query
  (Chapter 04), not a client store. Most "state" on a data-driven screen is this.
- **URL state** — filters, sorting, pagination, the selected tab, a search query.
  It belongs in the URL, so it's shareable, bookmarkable, survives refresh, and
  works with the back button.
- **Local (UI) state** — is this dropdown open, this row expanded. It belongs in
  `useState`, colocated in the component.
- **Form state** — the values being edited in a form. It has its own tools
  (Chapter 06).
- **Global client state** — genuinely app-wide UI state shared across distant
  components: theme, the client-side session, a global modal. This is the *only*
  kind a global store is for — and it's a small fraction of an app's state.

Once you classify correctly, "state management" mostly dissolves: the server state
is React Query's job, the URL state is the URL's, the local state is `useState`,
and the sliver that remains — genuine global UI state — needs only a small, simple
tool. The mistake, and the AI default, is skipping the classification and dumping
everything into one global store.

## Why It Matters

Over-centralizing state is one of the most common and most expensive frontend
architecture mistakes. A global store holding server data, filter state, and local
UI state alike creates a tangle where every screen touches the store, every change
risks a wide re-render, server data goes stale with no caching, and the URL doesn't
reflect what the user is looking at. It's the frontend version of the big ball of
mud, and it grows worse with every feature.

Classifying state correctly avoids specific, concrete failures:

- **Server state in a store goes stale and uncached.** Fetched data hand-managed in
  a global store has no caching, deduplication, or invalidation — the problems
  Chapter 04 solved with React Query, reintroduced. Server data does not belong in a
  client store.
- **URL state in component state breaks sharing and navigation.** Put the filter,
  sort, page, or selected tab in `useState` and the user can't share the link, can't
  bookmark the view, loses it on refresh, and the back button doesn't restore it. The
  URL *is* state for these; not using it is a real UX regression.
- **High-frequency state in Context causes re-render storms.** React Context
  re-renders *every* consumer whenever its value changes, so putting rapidly-changing
  state (form input, a live value) in Context janks the whole subtree. Context is for
  low-frequency, dependency-injection-style values.
- **A heavyweight store for a light need is dead complexity.** Reaching for Redux
  when the app has a little genuinely-global UI state adds boilerplate and concepts
  for no benefit (Stage 1, Chapter 07's over-engineering).

The AI dimension: assistants reach for a global store (often Redux) by default,
because "state management" pattern-matches to it in their training data — so they put
server data, URL-appropriate state, and local state all in one store, and they misuse
Context for high-frequency state. The result is an over-centralized, stale, un-shareable
frontend with re-render problems.

## Mental Model

For every piece of state, the question is *what kind is it?* — and the answer routes
it to a home:

```
   WHAT KIND OF STATE IS THIS?

   ┌─ Data from the backend? ─────────► SERVER STATE  → React Query (Chapter 04).
   │                                     (NOT a client store — no caching there.)
   │
   ├─ A filter / sort / page / tab / ──► URL STATE     → the URL (searchParams).
   │  search query the user navigates?    (shareable, bookmarkable, survives refresh,
   │                                        back button works.)
   │
   ├─ Values being edited in a form? ──► FORM STATE    → form tools (Chapter 06).
   │
   ├─ Local UI (is this open/expanded)? ► LOCAL STATE  → useState, colocated (Chapter 01).
   │
   └─ Genuinely APP-WIDE UI state shared ► GLOBAL CLIENT STATE → the smallest tool that works:
      across distant components?           low-frequency → Context; complex/frequent → a small store.
      (theme, client session, global modal)  ← the ONLY kind a store is for, and it's SMALL.

   THE LADDER (reach only as far as you need):
     useState ──► lift state up ──► Context (low-frequency) ──► a state library (complex/high-frequency)
```

Three principles carry the chapter:

**Classify before you reach for a tool.** The first move for any state is to name its
kind, because the kind determines the home. Most state on a real screen is server state
(React Query's job) or URL state (the URL's job); the amount that is genuinely
global client state is small. "State management" is mostly a classification problem.

**Global client state is the exception, and it stays small.** A global store is for the
narrow set of state that is truly app-wide and shared across distant components — theme,
client session, feature flags, a global modal. It is not for server data, not for URL
state, and not for state a component and its neighbor can share by lifting. You need far
less global state than the phrase "state management" implies.

**Climb the ladder only as far as the need.** Start with local `useState`; lift it to a
common parent when shared (Chapter 01); use Context for low-frequency app-wide values
(dependency injection: theme, current user); reach for a state library only when the
global state is complex or changes frequently enough that Context's re-render behavior
hurts. Don't start at the top.

A working definition:

> **State management is mostly classification: route server state to React Query, URL
> state to the URL, local state to `useState`, form state to form tools, and only
> genuinely app-wide UI state to a global store — which stays small. The mistake is
> skipping the classification and centralizing everything.**

## Production Example

**Invoicely's** invoices screen holds several pieces of state, and the whole lesson is
that they belong in *different* places:

- the **invoice data** → server state → React Query (Chapter 04);
- the **status filter, sort, and page** → URL state → the URL, so a filtered view is
  shareable and survives refresh;
- whether **a given row is expanded** → local state → `useState` in the row;
- the **theme and collapsed sidebar** → genuinely app-wide UI state → a small global
  store or Context.

We will route each to its correct home, and contrast it with the anti-pattern an
assistant tends to produce: one global Redux store holding the invoice data, the
filters, the pagination, *and* the expanded-row flags — over-centralized, stale, and
un-shareable. The point is not which store to pick; it's that most of this state
shouldn't be in a store at all.

## Folder Structure

```
web/src/
├── app/(app)/invoices/page.tsx      # reads filter/sort/page from URL searchParams
├── features/invoices/
│   ├── queries.ts                   # SERVER state (React Query, Chapter 04)
│   └── InvoiceRow.tsx               # LOCAL state (useState) for "expanded"
├── lib/
│   ├── url-state.ts                 # helpers for reading/writing URL state
│   └── ui-store.ts                  # small GLOBAL store: theme, sidebar (app-wide UI only)
└── app/providers.tsx                # Context for the client session (low-frequency DI)
```

Why this shape: each kind of state lives with the tool that fits it — server state in
the query hooks, URL state read from `searchParams`, local state in the component, and a
*small* global store for app-wide UI. No single "store" holds everything.

## Implementation

**URL state — filters, sort, page (`page.tsx`).** These live in the URL, so the view is
shareable, bookmarkable, and refresh-proof, and the server can read them for rendering.

```tsx
// Server Component reads URL state from searchParams — the filtered view IS the URL.
export default async function InvoicesPage({
  searchParams,
}: { searchParams: { status?: string; sort?: string; page?: string } }) {
  const filter = {
    status: searchParams.status ?? "all",
    sort: searchParams.sort ?? "recent",
    page: Number(searchParams.page ?? 1),
  };
  const invoices = await getInvoices(filter);       // server state, keyed by URL state
  return <InvoicesClient initial={invoices} filter={filter} />;
}
```

```tsx
// Client: changing a filter updates the URL (not useState) — shareable, back-button works.
"use client";
import { useRouter, useSearchParams, usePathname } from "next/navigation";

function StatusFilter() {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  function setStatus(status: string) {
    const next = new URLSearchParams(params);
    next.set("status", status);
    next.delete("page");                            // reset pagination on filter change
    router.push(`${pathname}?${next}`);             // URL is the source of truth
  }
  // ...
}
```

**Local state — colocated in the component (`InvoiceRow.tsx`).** "Is this row expanded"
is nobody else's business; it lives in the row.

```tsx
"use client";
import { useState } from "react";

function InvoiceRow({ invoice }: { invoice: Invoice }) {
  const [expanded, setExpanded] = useState(false);   // LOCAL UI state — colocated
  // ...
}
```

**Global client state — small, app-wide UI only (`ui-store.ts`).** Theme and sidebar are
genuinely app-wide and shared across distant components, so a *small* store fits. Note
what's NOT here: no invoice data, no filters.

```tsx
"use client";
import { create } from "zustand";

// GLOBAL client state — ONLY genuinely app-wide UI. Small on purpose.
export const useUiStore = create<{
  theme: "light" | "dark";
  sidebarCollapsed: boolean;
  toggleTheme: () => void;
  toggleSidebar: () => void;
}>((set) => ({
  theme: "light",
  sidebarCollapsed: false,
  toggleTheme: () => set((s) => ({ theme: s.theme === "light" ? "dark" : "light" })),
  toggleSidebar: () => set((s) => ({ sidebarCollapsed: !s.sidebarCollapsed })),
}));
```

**Context for low-frequency DI (`providers.tsx`).** The client session is set once and
rarely changes — a perfect Context value (dependency injection), not something that
re-renders consumers constantly.

```tsx
"use client";
import { createContext, useContext } from "react";

const SessionContext = createContext<Session | null>(null);
export const useSession = () => useContext(SessionContext);   // low-frequency value

export function SessionProvider({ session, children }: { session: Session; children: React.ReactNode }) {
  return <SessionContext.Provider value={session}>{children}</SessionContext.Provider>;
}
```

**The anti-pattern — everything in one global store.** Each line here is a
misclassification:

```tsx
// ANTI-PATTERN: one global store holding EVERYTHING
const useStore = create((set) => ({
  invoices: [],          // SERVER state → belongs in React Query (stale, uncached here)
  statusFilter: "all",   // URL state → belongs in the URL (un-shareable here)
  currentPage: 1,        // URL state → belongs in the URL
  expandedRows: {},      // LOCAL state → belongs in the component
  theme: "light",        // ← the ONLY thing that genuinely belongs in a global store
  // ...50 more fields, every screen coupled to this store
}));
```

The difference is the whole chapter: routed correctly, the invoice data is cached and
fresh (React Query), the filtered view is a shareable URL, the row state is local and
isolated, and the global store holds only theme and sidebar. Dumped into one store, the
server data is stale and uncached, the view can't be shared or bookmarked, every screen
is coupled to a giant store, and changes ripple as wide re-renders. The state is the
same; only one arrangement scales.

## Engineering Decisions

Five decisions define state management — and the first one resolves most of them.

### What kind of state is this?

**Options:** treat all state uniformly (one tool), or classify each piece and route it.

**Trade-offs:** one uniform tool (usually a global store) is conceptually simple and wrong
— it forces server state, URL state, and local state into a container built for none of
them, losing caching, shareability, and colocation. Classifying takes a moment of thought
per piece and puts each where it works.

**Recommendation:** classify every piece of state by kind — server / URL / form / local /
global-client — and route it to that kind's home. This single habit prevents the majority
of state-management problems, because most state turns out to be server or URL state that
never needed "management" in the store sense at all.

### Do you need a global store at all?

**Options:** (1) adopt a global store early; (2) add one only when genuine global client
state accumulates.

**Trade-offs:** adopting early gives a ready home for shared state and tempts you to put
everything in it (over-centralization). Waiting keeps the app simple and means a small
refactor if real global state appears — which is cheap, because by then you know exactly
what's global.

**Recommendation:** don't add a global store until you have genuine app-wide client state
that Context can't comfortably handle — and even then keep it small. Most apps need far
less global state than expected once server state (React Query) and URL state (the URL) are
routed away. Reaching for Redux on day one is usually premature.

### Context or a state library for global state?

**Options:** (1) React Context; (2) a state library (Zustand/Redux/Jotai).

**Trade-offs:** Context is built in and ideal for low-frequency, dependency-injection
values (theme, session, config) — but it re-renders all consumers on every change, so it's
wrong for high-frequency state. A state library provides selective subscriptions (consumers
re-render only for the slice they use) and structure, at the cost of a dependency.

**Recommendation:** Context for low-frequency app-wide values (theme, session, feature
flags); a state library when global state is complex or changes frequently enough that
Context's re-render-everything behavior hurts. Never put rapidly-changing state in Context.

### URL state or component/store state for filters, tabs, pagination?

**Options:** (1) `useState`/a store; (2) the URL (`searchParams`).

**Trade-offs:** `useState`/a store is quick and makes the view ephemeral — not shareable,
not bookmarkable, lost on refresh, and invisible to the back button. The URL makes the view
a first-class, linkable, navigable thing and can be read on the server, at the cost of a bit
of URL-syncing plumbing.

**Recommendation:** put navigational state — filters, sort, pagination, selected tab, search
query — in the URL. It's shareable, bookmarkable, refresh-proof, back-button-friendly, and
server-readable. Keep truly ephemeral UI (a hover, an open menu) in local state. "Would the
user want to share or bookmark this view?" — if yes, it's URL state.

### Which state library, if you need one?

**Options:** Zustand (minimal), Redux Toolkit (structured, conventions), Jotai/atoms
(atomic), and others.

**Trade-offs:** Zustand is minimal and unopinionated — great for a small amount of global
state. Redux Toolkit brings structure, devtools, and conventions that help large, complex,
team-scale state at the cost of boilerplate. Jotai's atomic model suits fine-grained,
derived state. The wrong-sized choice is either boilerplate you don't need or too little
structure for genuinely complex state.

**Recommendation:** default to the simplest that fits — Zustand for the typical small amount
of global UI state; Redux Toolkit only when the global state is genuinely large and complex
enough to benefit from its structure and tooling. But first make sure the state is genuinely
global client state and not server/URL state in disguise — the library choice is downstream
of, and far less important than, the classification.

## Trade-offs

State-management choices trade simplicity, shareability, and performance, and the balance is
mostly about not over-reaching.

**Classifying trades a moment of thought for the right architecture.** Routing each piece of
state to its home is more up-front thinking than "put it in the store," and it returns
caching (server state), shareability (URL state), isolation (local state), and a small store.
The cost is negligible; the payoff compounds as the app grows.

**A global store trades boilerplate for genuine sharing.** When state really is app-wide, a
store is the right tool and worth its overhead; when it isn't, the store is dead complexity
and a coupling magnet. The trade only pays off for genuinely global state — which is why the
"do you need it at all?" question comes first.

**Context trades simplicity for its re-render behavior.** Context is built-in and perfect for
low-frequency values, and its all-consumers-re-render behavior makes it wrong for
high-frequency state. The trade is fine within its lane and bad outside it — the mitigation
is to use Context only for the low-frequency values it's suited to.

**URL state trades a little plumbing for real UX.** Syncing state to the URL is slightly more
work than `useState` and buys shareable, bookmarkable, navigable views. For navigational state
the UX win is decisive; for genuinely ephemeral UI the plumbing isn't worth it — match the
choice to whether the view is worth sharing.

## Common Mistakes

**Everything in a global store.** Server data, URL state, and local state all centralized —
stale server data, un-shareable views, wide coupling, and re-render ripple. Fix: classify and
route; the store holds only genuine app-wide UI state.

**Server state in a client store.** Fetched data hand-managed in Redux/Zustand — the caching
and invalidation problems Chapter 04 solved, reintroduced. Fix: React Query for server state.

**Navigational state in `useState`.** Filters, sort, pagination, tabs in component state — not
shareable, lost on refresh, back button broken. Fix: put it in the URL.

**High-frequency state in Context.** Rapidly-changing values in a Context provider, re-rendering
every consumer. Fix: Context for low-frequency values only; local state or a store with
selectors for frequent changes.

**A heavyweight store for a light need.** Redux (and its boilerplate) for an app with a little
global state. Fix: use the simplest tool (often Context or Zustand), or none — after confirming
the state is genuinely global.

**Prop drilling instead of the right home.** Threading state through many layers because it
wasn't classified — often it's server state, URL state, or a Context value. Fix: route it to
its proper home rather than drilling.

## AI Mistakes

"State management" pattern-matches to "global store" in training data, so assistants
over-centralize by default and skip the classification that makes the problem tractable.
Review state code for whether each piece is in the right kind of home.

### Claude Code: centralizing everything in a global store

Asked to "manage state" or "add state management," Claude Code reaches for a global store
(often Redux) and puts server data, filters, pagination, and local UI flags into it, because
that's the shape "state management" takes in its training data. The store becomes a
catch-all, server data goes stale, and every screen couples to it.

**Detect:** a global store holding fetched server data, or filter/sort/pagination state, or
per-component UI flags; Redux/a store introduced for an app with little genuinely-global
state; `useState`-worthy local state living in a global store.

**Fix:** require classification:

> Don't put everything in a global store. Classify each piece of state: server data → React
> Query (Chapter 04); filters/sort/pagination/tabs → the URL; local UI → `useState`; only
> genuinely app-wide UI state (theme, session) → a small global store. Most of this does not
> belong in a store.

### GPT: high-frequency state in Context

GPT-family models reach for React Context to share state widely, including rapidly-changing
values (a form field, a live counter, mouse position), because Context is the built-in
"share state" mechanism — not accounting for Context re-rendering every consumer on each
change, which janks the whole subtree.

**Detect:** a Context provider whose value changes frequently and is consumed across a large
subtree; visible jank/re-renders tied to a Context update; form or input state lifted into
Context.

**Fix:** match the tool to the frequency:

> Context re-renders all consumers on every value change, so use it only for low-frequency
> values (theme, session, config). For frequently-changing shared state, keep it local, or use
> a state library with selective subscriptions so only the components using a slice re-render.

### Cursor: navigational state trapped in component state

Wiring up filters, tabs, or pagination inline, Cursor puts them in `useState`, because that's
the shortest local way to make the control work — so the view isn't shareable, doesn't survive
refresh, and the back button doesn't restore it.

**Detect:** filter/sort/pagination/selected-tab/search state in `useState` (or a store) rather
than the URL; a filtered or paginated view whose URL doesn't change as the user navigates it.

**Fix:** require URL state:

> Filters, sorting, pagination, the selected tab, and search queries are URL state — put them in
> the URL (`searchParams`), not `useState`, so the view is shareable, bookmarkable, survives
> refresh, and works with the back button. Keep only truly ephemeral UI in local state.

## Best Practices

**Classify every piece of state, then route it.** Server → React Query; URL/navigational →
the URL; local UI → `useState`; form → form tools (Chapter 06); genuinely app-wide UI → a small
global store. Classification is the whole discipline.

**Keep global client state small, and add a store late.** A store is only for genuinely
app-wide UI state, and it stays small; add one only when such state accumulates beyond what
Context handles. You need less global state than "state management" implies.

**Use Context for low-frequency values, a library for frequent/complex ones.** Theme, session,
config in Context; a state library (with selective subscriptions) when global state changes
frequently or is complex. Never put high-frequency state in Context.

**Put navigational state in the URL.** Filters, sort, pagination, tabs, search — in
`searchParams`, so views are shareable, bookmarkable, refresh-proof, and server-readable.

**Climb the ladder only as far as needed, and don't duplicate server state.** `useState` →
lift → Context → a library, in that order of escalation; never copy server data into a client
store (Chapter 04). Document the state-classification conventions in `CLAUDE.md`.

## Anti-Patterns

**The God Store.** One global store holding server data, URL state, and local state alike —
stale data, un-shareable views, app-wide coupling, re-render ripple. The tell: a store with
dozens of fields that every screen imports.

**Server State in the Store.** Fetched data hand-managed in a client store, reintroducing the
caching/invalidation problems React Query solves. The tell: API responses stored in Redux/Zustand
and synced by hand.

**The Ephemeral View.** Navigational state (filter/sort/page/tab) in `useState`, so the view
can't be shared or bookmarked and dies on refresh. The tell: a filtered URL that never changes as
you filter.

**The Context Firehose.** High-frequency state in Context, re-rendering every consumer. The tell:
Context whose value updates rapidly and a laggy subtree.

**The Premature Redux.** A heavyweight store and its boilerplate for an app with barely any global
state. The tell: Redux setup dwarfing the amount of genuinely-global state it holds.

## Decision Tree

"I have a piece of state — where does it live?"

```
WHAT KIND OF STATE IS THIS?
│
├─ Data fetched from the backend? ─────────► SERVER STATE → React Query (Chapter 04).
│
├─ A filter / sort / page / tab / search   ─► URL STATE → the URL (searchParams).
│  the user would share or bookmark?          (shareable, refresh-proof, back button works)
│
├─ Values being edited in a form? ─────────► FORM STATE → form tools (Chapter 06).
│
├─ Local UI (open/expanded/hovered)? ──────► LOCAL STATE → useState, colocated.
│    (need it in a sibling too? ── lift it to the common parent, Chapter 01.)
│
└─ Genuinely APP-WIDE UI state shared ─────► GLOBAL CLIENT STATE (and keep it small):
   across distant components?                  ├─ low-frequency (theme, session)? ─► Context
   (theme, session, global modal, flags)       └─ frequent/complex? ─► a small store (Zustand;
                                                   Redux only if genuinely large & complex)

   Reach up the ladder ONLY as far as the need. Most state never leaves the first two branches.
```

## Checklist

### Implementation Checklist

- [ ] Each piece of state is classified (server / URL / form / local / global-client) and routed to that home.
- [ ] Server data is in React Query, never a client store.
- [ ] Navigational state (filter/sort/page/tab/search) is in the URL, not `useState`.
- [ ] Local UI state is colocated with `useState`; lifted only when shared.
- [ ] The global store (if any) holds only genuinely app-wide UI state and is small.
- [ ] Context holds only low-frequency values; frequent/complex global state uses a library with selectors.

### Architecture Checklist

- [ ] There is no single store holding everything; state lives in kind-appropriate homes.
- [ ] A global store was added only because genuine app-wide client state required it.
- [ ] The state library choice (if any) matches the scale of the global state (Zustand vs Redux).
- [ ] Views the user would share/bookmark are reflected in the URL.
- [ ] State-classification conventions are documented in `CLAUDE.md`.

### Code Review Checklist

- [ ] No server data placed in a client store (watch AI diffs).
- [ ] No navigational state trapped in `useState` instead of the URL.
- [ ] No high-frequency state in Context.
- [ ] No global store introduced for state that is local, URL, or server state.
- [ ] No prop drilling that a correct classification (Context/URL/server) would remove.

*(A Deployment Checklist is not applicable to this chapter.)*

## Exercises

**1. Classify a screen's state.** List every piece of state on Invoicely's invoices screen and
classify each (server / URL / local / global-client), naming its correct home. The artifact is
the table; the point is how little of it is genuinely global client state.

**2. Move a view into the URL.** Take a filtered/paginated list whose filter and page are in
`useState` (write one, or have an assistant generate "a filterable invoice list") and move that
state into the URL. Then demonstrate the wins: a shareable link, a working back button, and
state surviving refresh. The artifact is the before/after and the demonstrated behaviors.

**3. Deflate a god store.** Take a global store holding server data, filters, and local flags
(write one, or generate "add Redux state management to this app") and refactor it: server data to
React Query, filters to the URL, local flags to `useState`, leaving only genuine app-wide UI in a
small store. The artifact is the before/after and a note on what each screen no longer couples to.

## Further Reading

- **TkDodo — "Working with Zustand" and the React Query articles on the server-state/client-state
  split** (tkdodo.eu/blog) — the clearest writing on the central distinction of this chapter: most
  "global state" is server state, and what remains is small.
- **React documentation — "Managing State," "Passing Data Deeply with Context," and "Scaling Up
  with Reducer and Context"** (react.dev) — the official guidance on lifting state, when Context
  fits, and its re-render behavior; the foundation for the ladder.
- **Zustand documentation** (github.com/pmndrs/zustand) and **Redux Toolkit documentation**
  (redux-toolkit.js.org) — read both briefly to calibrate the difference: Zustand's minimalism vs
  Redux Toolkit's structure, so you can match the tool to the scale of genuinely-global state.
- **"Storing State in the URL"** (search for write-ups on `searchParams`/`nuqs` and URL state in
  Next.js) — practical patterns for treating the URL as a first-class state store, the most
  under-used idea in frontend state management.

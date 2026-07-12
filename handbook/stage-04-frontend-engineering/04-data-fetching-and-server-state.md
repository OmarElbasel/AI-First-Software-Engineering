# Data Fetching & Server State

## Introduction

Most of the data a frontend displays does not belong to the frontend — it lives on
the server, is fetched over the network, can be out of date the moment it arrives,
and is shared across components and users. This chapter is about handling that
**server state** correctly: fetching it (on the server by default, on the client
when needed), caching it, keeping it fresh after changes, and doing so without the
waterfalls, race conditions, and stale-UI bugs that the naive approach produces.

The single most important idea here is a distinction: **server state is not client
state.** Client (UI) state — is this dropdown open, what's typed in this field — is
owned by the frontend, synchronous, and yours to mutate. Server state — the invoice
list, the current user — is owned by the server, asynchronous, cached, and shared;
it can be stale and must be refetched. Conflating the two — stuffing fetched server
data into `useState` or a global store and hand-syncing it — is the root of a large
share of frontend data bugs, and it's the default an assistant reaches for.

The tools follow the distinction. In the Next.js App Router, initial data is
fetched on the **server** (Chapters 02–03) — fast, secure, no client waterfall. For
data that must be fetched or refetched *on the client* — interactive filters,
polling, and mutations that update the cache — the right tool is a server-state
library, **React Query (TanStack Query)**, which handles caching, deduplication,
background refetching, and invalidation. What you should almost never do is manage
server state by hand with `useEffect` + `fetch` + `useState`, which is where the
bugs live.

## Why It Matters

Server state is genuinely hard — it's asynchronous, shared, cacheable, and goes
stale — and the naive `useEffect` + `fetch` + `useState` approach gets nearly every
part of it wrong:

- **No caching or deduplication.** Every component that needs the data fetches it
  again; navigating away and back refetches from scratch; two components wanting the
  same data make two requests. A server-state cache fetches once and shares.
- **Race conditions.** Fire a fetch, change the input, fire another — the responses
  can arrive out of order and the stale one wins, showing the wrong data. Manual
  effect-based fetching is riddled with this; a real data layer handles it.
- **Waterfalls.** Fetching sequentially what could be fetched in parallel, or
  fetching on the client what should have been fetched on the server, adds
  round-trips and spinners the user feels as slowness.
- **Stale UI after mutations.** Change data on the server and the cached copy on the
  client is now wrong — the list still shows the old status after you edited it —
  unless the mutation invalidates the affected queries (the client-side echo of the
  cache-invalidation problem from Stage 3, Chapter 07).

Handled well — server-fetched initial data plus React Query for client interactions
— you get fast first paint, shared caching, no races, background freshness, and a UI
that reflects changes immediately. Handled naively, you get spinners, waterfalls,
stale data, and flicker.

The AI dimension: assistants treat server state like client state — they store
fetched data in `useState` or a global store and sync it by hand, they forget to
invalidate the cache after a mutation (stale UI), and they build waterfalls by
awaiting sequentially. Each is the exact problem the server/client-state distinction
and React Query exist to eliminate.

## Mental Model

Two kinds of state, two homes, and one library for the hard one:

```
   CLIENT (UI) STATE                    SERVER STATE
   owned by the frontend                 owned by the server
   synchronous, yours to mutate          async, fetched, CACHED, can be STALE, shared
   "is this modal open?"                 "the invoice list", "the current user"
   → useState / a UI store (Ch 05)       → fetch on the SERVER, or React Query on the CLIENT
                                            NOT useState + useEffect + fetch by hand

   WHERE TO FETCH (App Router)
     initial page data ──► on the SERVER (async Server Component) — fast, secure, no waterfall
     interactive / refetch / mutations / polling ──► React Query on the CLIENT

   REACT QUERY gives you (for free) what useEffect+fetch doesn't:
     caching · deduplication · background refetch · stale-while-revalidate
     loading/error state · race-condition handling · cache invalidation after mutations

   AFTER A MUTATION: invalidate the affected queries ──► the UI refetches & updates
     (the client-side version of cache invalidation — Stage 3, Ch 07)
```

Four principles carry the chapter:

**Server state and client state are different problems.** Client state is local,
synchronous, and owned by you; server state is remote, asynchronous, cached, shared,
and stale-able. Manage them with different tools — `useState`/a UI store for client
state (Chapter 05), server-fetching or React Query for server state — and never put
server data into `useState` or a global store to hand-sync it.

**Fetch on the server by default; use React Query for client data.** In the App
Router, fetch a page's initial data in the Server Component — it's fast, secure, and
avoids a client waterfall (Chapters 02–03). Use React Query for data that genuinely
needs client-side fetching or refetching: interactive filters, polling, and mutations
that update a client cache.

**Never manage server state by hand with `useEffect` + `fetch`.** That pattern has no
caching, no deduplication, races, no background refetch, and manual loading/error
handling — it reimplements (badly) what a server-state library does correctly. Raw
`useEffect` + `fetch` for server data is an anti-pattern, not a simpler alternative.

**Invalidate after mutations.** When a mutation changes server data, the cached client
copy is stale until you invalidate (or update) the affected queries, prompting a
refetch so the UI reflects the change. Forgetting this is why the list still shows the
old value after an edit.

A working definition:

> **Server state — remote, cached, stale-able, shared — is a different problem from
> client UI state and needs different tools: fetch it on the server by default, use
> React Query for client-side fetching and mutations, never hand-roll it with
> `useEffect` + `fetch` + `useState`, and invalidate the cache after every mutation
> so the UI stays correct.**

## Production Example

**Invoicely's** invoices screen shows the tension perfectly. The initial list should
render fast and be indexable, so it's fetched on the **server** (Chapters 02–03). But
the screen is interactive: the user filters by status (refetch), and marks invoices
paid (a mutation that must update both the list and the detail view). Those
client-side interactions are exactly what React Query is for — and doing them with
raw `useEffect` + `fetch` would bring the races, spinners, and stale-after-mutation
bugs this chapter is about.

We will fetch the initial list on the server, then use React Query on the client for
the filtered refetch and the "mark as paid" mutation with cache invalidation so the UI
updates immediately. We'll contrast the mutation-without-invalidation bug (list shows
stale status after the edit) and the `useEffect` + `fetch` waterfall. The point is the
division of labor: server for the initial load, React Query for the live interaction,
and the two composed cleanly.

## Folder Structure

```
web/src/
├── app/(app)/invoices/page.tsx      # SERVER: fetches initial list on the server
├── lib/query.tsx                    # "use client": QueryClient + provider (once, at root)
└── features/invoices/
    ├── api.ts                       # fetch functions (server + client)
    ├── queries.ts                   # useInvoices, useInvoice — React Query hooks
    ├── mutations.ts                 # useMarkPaid — mutation + cache invalidation
    └── InvoicesClient.tsx           # "use client": interactive list (filter, refetch)
```

Why this shape: the page (Server Component) fetches the first render server-side; the
client island (`InvoicesClient`) uses React Query hooks from `queries.ts`/`mutations.ts`
for interaction. Query and mutation logic is colocated with the feature, and the
`QueryClient` provider is set up once at the root (a Client Component).

## Implementation

**Server-fetch the initial data (`page.tsx`).** The default, best path in the App
Router: fetch on the server, render immediately, no client spinner or waterfall.

```tsx
// Server Component — initial data fetched on the server (Chapters 02-03)
import { getInvoices } from "@/features/invoices/api";
import { InvoicesClient } from "@/features/invoices/InvoicesClient";

export default async function InvoicesPage() {
  const initialInvoices = await getInvoices({ status: "all" });   // server-side fetch
  return <InvoicesClient initialInvoices={initialInvoices} />;    // handoff to the client island
}
```

**React Query setup (`lib/query.tsx`).** One `QueryClient`, provided once. This is the
client cache the rest of the feature uses.

```tsx
"use client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState } from "react";

export function QueryProvider({ children }: { children: React.ReactNode }) {
  const [client] = useState(() => new QueryClient({
    defaultOptions: { queries: { staleTime: 30_000 } },   // fresh for 30s; SWR after
  }));
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}
```

**A query for client-side (re)fetching (`queries.ts` + `InvoicesClient.tsx`).** React
Query handles caching, deduplication, background refetch, loading/error, and races —
none of which you write. The server-fetched data seeds the cache as `initialData`, so
there's no second fetch on first render.

```tsx
// queries.ts
import { useQuery } from "@tanstack/react-query";
import { getInvoices, type InvoiceFilter } from "./api";

export function useInvoices(filter: InvoiceFilter, initialData?: Invoice[]) {
  return useQuery({
    queryKey: ["invoices", filter],      // cache key includes the filter (like a cache key, Ch 07)
    queryFn: () => getInvoices(filter),
    initialData: filter.status === "all" ? initialData : undefined,   // seed from server
  });
}
```

```tsx
// InvoicesClient.tsx
"use client";
import { useState } from "react";
import { useInvoices } from "./queries";

export function InvoicesClient({ initialInvoices }: { initialInvoices: Invoice[] }) {
  const [status, setStatus] = useState<"all" | InvoiceStatus>("all");   // CLIENT/UI state
  const { data, isLoading } = useInvoices({ status }, initialInvoices);  // SERVER state via RQ

  // Changing `status` refetches via React Query — cached, deduped, race-safe. No useEffect.
  return (
    <>
      <StatusFilter value={status} onChange={setStatus} />
      {isLoading ? <InvoiceListSkeleton /> : <InvoiceList invoices={data!} />}
    </>
  );
}
```

**A mutation with cache invalidation (`mutations.ts`).** After marking an invoice paid,
invalidate the affected queries so the list and detail refetch and show the new status.
This is the client-side cache invalidation that keeps the UI correct.

```tsx
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { markInvoicePaid } from "./api";

export function useMarkPaid() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (invoiceId: number) => markInvoicePaid(invoiceId),
    onSuccess: (_data, invoiceId) => {
      // INVALIDATE affected queries → they refetch → UI reflects the change.
      qc.invalidateQueries({ queryKey: ["invoices"] });          // the list
      qc.invalidateQueries({ queryKey: ["invoice", invoiceId] }); // the detail
    },
  });
}
```

**The anti-patterns — what an assistant tends to produce.** Two classic bugs, each
green in a first click-through:

```tsx
// ANTI-PATTERN 1: server state by hand — no cache, races, manual loading
"use client";
function InvoicesBad() {
  const [invoices, setInvoices] = useState([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {                                   // refetch on every mount; no dedup
    fetch("/api/invoices").then(r => r.json()).then(d => { setInvoices(d); setLoading(false); });
  }, []);                                             // change a filter fast → race → wrong data
  // ...
}

// ANTI-PATTERN 2: mutation without invalidation — UI goes stale
function useMarkPaidBad() {
  return useMutation({ mutationFn: markInvoicePaid });   // no onSuccess invalidate
  // the invoice is paid on the server; the list still shows "sent" until a manual reload
}
```

The difference is the whole chapter: the good version fetches the initial list on the
server (fast, no waterfall), manages the interactive/refetch/mutation on the client with
React Query (cached, deduped, race-safe), and invalidates after the mutation (UI updates
immediately). The bad version hand-rolls server state in `useState` (races, no cache) and
mutates without invalidating (stale UI). The interactivity is identical; the correctness
and speed are not.

## Engineering Decisions

Five decisions define how you handle data.

### Server-fetch or client-fetch?

**Options:** (1) fetch everything on the client; (2) fetch initial data on the server,
client-fetch only what needs it.

**Trade-offs:** all-client fetching is the SPA habit — it ships an empty shell, shows a
spinner, and adds a client round-trip (and waterfalls) before anything renders.
Server-fetching the initial data renders it immediately, keeps it secure, and avoids the
waterfall, but the interactive parts still need a client story.

**Recommendation:** in the App Router, fetch a page's initial data on the server
(Chapters 02–03), and use React Query on the client only for genuinely client-side needs —
interactive refetching, polling, and mutations. Server for the first paint, React Query for
the live interaction; don't client-fetch what the server can render.

### React Query, `useEffect` + `fetch`, or a global store — for server state?

**Options:** (1) `useEffect` + `fetch` + `useState`; (2) a global store (Redux/Zustand);
(3) React Query (a server-state library).

**Trade-offs:** `useEffect` + `fetch` hand-rolls caching, dedup, races, and loading state —
badly and repeatedly. A global store isn't built for async server data and turns caching and
invalidation into manual work you'll get wrong. React Query is purpose-built for server
state — caching, dedup, background refetch, invalidation — at the cost of a dependency and
its concepts.

**Recommendation:** React Query (or an equivalent server-state library) for client-side
server state, always. It exists because `useEffect` + `fetch` and general-purpose stores are
the wrong tools for the job. Reserve `useState`/a UI store for *client* state (Chapter 05);
don't put server data in them.

### How is the cache kept fresh after mutations?

**Options:** (1) do nothing (rely on a manual reload); (2) invalidate affected queries;
(3) optimistically update, then reconcile.

**Trade-offs:** doing nothing leaves the UI stale after every change. Invalidation is simple
and correct — the affected queries refetch and show the new truth — with a brief refetch.
Optimistic updates make the UI feel instant by updating the cache before the server confirms,
at the cost of complexity and rollback-on-failure logic.

**Recommendation:** invalidate the affected queries after every mutation (the default, correct
choice), and add optimistic updates only where the snappiness is worth the extra complexity
(a toggle, a like). Forgetting invalidation is the client-side version of the cache bug from
Stage 3, Chapter 07 — the cache is only useful if it's correct.

### How do you avoid waterfalls?

**Options:** (1) fetch sequentially as needs arise; (2) fetch in parallel / on the server /
restructure to remove dependencies.

**Trade-offs:** sequential fetching is the natural way code reads and adds a round-trip per
step — a chain of spinners the user feels. Parallel fetching (independent data at once),
server-fetching, and restructuring to remove artificial dependencies cut the latency, at the
cost of deliberately arranging the fetches.

**Recommendation:** fetch independent data in parallel (`Promise.all` on the server, parallel
queries on the client), fetch on the server where possible, and restructure to avoid
dependent fetches where a request only exists to get an id for the next one. Treat a chain of
sequential awaits as a waterfall to flatten.

### How aggressively is data refetched (staleness tuning)?

**Options:** (1) always fresh (refetch constantly); (2) tuned `staleTime`/refetch behavior.

**Trade-offs:** always-fresh maximizes correctness and hammers the server with refetches;
never-refetch minimizes requests and serves stale data. React Query's `staleTime`, refetch-on-
focus/reconnect, and polling let you set the freshness per query.

**Recommendation:** set `staleTime` (and refetch behavior) per query from how fast the data
changes and how much staleness is acceptable — a dashboard summary can be stale for a minute
(like the Stage 3, Chapter 07 budget); a live status might refetch on focus. Don't accept the
defaults blindly for data with real freshness requirements, and don't refetch constantly for
data that rarely changes.

## Trade-offs

Handling server state well trades a dependency and concepts for correctness, and a few points
are contextual.

**React Query trades a library and learning curve for solving a genuinely hard problem.** It
adds a dependency and its concepts (query keys, staleness, invalidation), and it removes an
entire category of bugs (races, stale UI, duplicate fetches, manual loading state) that you
would otherwise reimplement badly. For any app with real server-state interaction the trade is
strongly worth it; for a purely server-rendered app with no client fetching, you may not need
it at all (fetch on the server and stop).

**Server-fetching trades some client flexibility for speed and security.** Fetching on the
server gives fast first paint and keeps data access server-side, and it means the initial data
isn't managed by the client cache until you hand it over. The `initialData` handoff bridges
this; the cost is understanding the server→client data flow, which is worth it for the
performance.

**Caching trades freshness for speed — again.** As on the backend (Stage 3, Chapter 07), a
client cache serves possibly-stale data fast, and the `staleTime`/invalidation settings are
where you choose the staleness. The same discipline applies: tune per data type, invalidate on
change, and don't treat cached data as guaranteed-fresh.

**Optimistic updates trade complexity for perceived speed.** They make the UI feel instant and
require rollback logic and careful reconciliation when the server disagrees. Worth it for
high-frequency, low-stakes interactions; over-engineering for a rare, important mutation where
a brief spinner is fine.

## Common Mistakes

**Treating server state as client state.** Storing fetched data in `useState` or a global
store and hand-syncing it — no caching, manual invalidation, drift. Fix: React Query for
server state; `useState`/UI store only for client state.

**`useEffect` + `fetch` for server data.** The hand-rolled pattern with races, no cache, no
dedup, and manual loading/error. Fix: server-fetch, or React Query — never raw effect-based
fetching for server state.

**No cache invalidation after mutations.** Mutating server data without invalidating the
affected queries, so the UI shows stale data until a reload. Fix: `invalidateQueries` (or an
optimistic update) after every mutation.

**Waterfalls.** Sequential dependent fetches, or client fetching that should be on the server,
adding round-trips and spinners. Fix: parallelize independent fetches, fetch on the server,
remove artificial fetch dependencies.

**Refetching wrong.** Refetching constantly (server hammered) or never (stale data), instead of
tuning per query. Fix: set `staleTime` and refetch behavior from the data's real freshness
needs.

**Duplicate fetching.** The same data fetched independently by multiple components with no
shared cache. Fix: a shared query key so React Query dedupes and shares one fetch.

## AI Mistakes

Server state is a hard, distinct problem, and assistants default to the client-state habits
that don't fit it — producing code that works in a single click-through and breaks under
interaction, concurrency, and mutation. Review data code for what happens on refetch, on a fast
input change, and after a mutation.

### Claude Code: treating server state like client state

Asked to load and display data, Claude Code stores it in `useState` (often via `useEffect` +
`fetch`) or in a global store, and manages loading, errors, and updates by hand — treating
remote, cached, shared server state as if it were local UI state. The result has no caching, no
deduplication, races on fast changes, and goes stale after mutations.

**Detect:** fetched server data held in `useState`/Redux/Zustand and synced manually;
`useEffect` + `fetch` + `setState` for server data; manual `isLoading`/`error` state around
fetches; the same data fetched separately in multiple components.

**Fix:** require a server-state library:

> Server state (data fetched from the backend) must be managed by React Query, not `useState`,
> `useEffect` + `fetch`, or a global store. Use `useQuery` (with a query key) for reads and
> `useMutation` for writes; keep `useState`/stores for client/UI state only. Server-fetch the
> initial data where possible (App Router).

### GPT: mutations that don't invalidate the cache

GPT-family models write the mutation — call the API, done — and omit the cache invalidation, so
the mutation succeeds on the server while the client cache (and the UI) still shows the old
data until a manual reload. It's the client-side cache-invalidation bug.

**Detect:** a `useMutation` (or manual mutation) with no `onSuccess` invalidation/refetch; UI
that shows stale data after a successful change; a mutation that updates the server but not the
affected queries.

**Fix:** require invalidation:

> After a mutation succeeds, invalidate (or optimistically update) the affected React Query
> keys so the UI refetches and reflects the change — `queryClient.invalidateQueries` in
> `onSuccess`. A mutation isn't done until the cached data it affects is refreshed.

### Cursor: waterfalls from sequential fetches

Writing data loading inline, Cursor tends to `await` fetches one after another — including
independent ones that could run in parallel — and to create client fetch chains, because
sequential code reads naturally at the edit site. Each added await is a round-trip the user
waits through.

**Detect:** multiple sequential `await` calls for data that don't depend on each other; nested
client fetches where one only feeds the next; a page whose load time grows with each data
dependency added.

**Fix:** require parallel/server fetching:

> These fetches are independent — run them in parallel (`Promise.all`) rather than sequentially,
> and fetch on the server where possible. Only chain fetches when one genuinely depends on
> another's result, and even then consider fetching by a shared key on the server to avoid the
> waterfall.

## Best Practices

**Separate server state from client state, and use the right tool for each.** Server state
(remote, cached, shared) → server-fetching or React Query; client/UI state (local, synchronous)
→ `useState`/a UI store (Chapter 05). Never store server data in `useState` or a global store to
hand-sync.

**Fetch initial data on the server; use React Query for client interaction.** Server-fetch the
first render (fast, secure, no waterfall), seed the client cache with it, and let React Query
handle interactive refetching, polling, and mutations.

**Invalidate the cache after every mutation.** `invalidateQueries` (or an optimistic update) so
the UI reflects server changes immediately — the client-side discipline that matches Stage 3,
Chapter 07's backend invalidation.

**Avoid waterfalls; parallelize and tune freshness.** Fetch independent data in parallel,
remove artificial fetch dependencies, and set `staleTime`/refetch behavior per query from the
data's real freshness needs.

**Let the library handle the hard parts.** Don't reimplement caching, deduplication, races, or
loading state with `useEffect` + `fetch` — that's what React Query is for. Document the
data-fetching conventions (server-fetch initial, React Query for client, invalidate on mutate)
in `CLAUDE.md`.

## Anti-Patterns

**Server State in `useState`.** Fetched data held and hand-synced in component state or a global
store — no cache, manual invalidation, drift. The tell: `useState` holding an API response, kept
in sync by effects.

**The `useEffect` Fetch.** Raw `useEffect` + `fetch` + `setState` for server data — races, no
cache, no dedup, manual loading. The tell: the `useEffect(() => { fetch().then(setData) }, [])`
pattern for server data.

**The Stale Mutation.** A mutation with no cache invalidation, so the UI lies until a reload. The
tell: `useMutation` with no `onSuccess` invalidation and a UI that needs a refresh to show
changes.

**The Waterfall.** Sequential fetches of independent data, or client fetching that should be on
the server — round-trips stacked into visible latency. The tell: a chain of `await`s with no
dependency between them.

**The Duplicate Fetch.** The same data fetched separately by multiple components with no shared
cache/key. The tell: identical requests fired by sibling components on the same screen.

## Decision Tree

"I need some data on the screen — how do I get it and keep it correct?"

```
Is this SERVER state (fetched from the backend) or CLIENT/UI state (local)?
├── CLIENT/UI state ──► useState / a UI store (Chapter 05). Not this chapter.
└── SERVER state ──►
     │
     Is it the page's INITIAL data?
     ├── YES ──► fetch on the SERVER (async Server Component). Fast, secure, no waterfall.
     │           Seed React Query with it (initialData) if the client will manage it.
     └── Interactive / refetch / poll / depends on client state?
          └──► React Query (useQuery) on the client. Query key includes all inputs (filters).
     │
     A MUTATION (write)?
     └──► useMutation, and in onSuccess INVALIDATE the affected query keys (or optimistic update).
          The mutation isn't done until the cache is refreshed.
     │
     Multiple fetches? ──► parallelize independent ones (Promise.all); don't chain unless dependent.
     Freshness? ──► set staleTime/refetch per query from how fast the data changes.

     NEVER: useState + useEffect + fetch to manage server state by hand.
```

## Checklist

### Implementation Checklist

- [ ] Server state is managed by server-fetching or React Query — never `useState`/a store hand-synced.
- [ ] Initial page data is fetched on the server; the client cache is seeded from it where applicable.
- [ ] Client-side reads use `useQuery` with a query key that includes all inputs (filters, ids).
- [ ] Every mutation invalidates (or optimistically updates) the affected query keys in `onSuccess`.
- [ ] Independent fetches run in parallel; there are no accidental waterfalls.
- [ ] `staleTime`/refetch behavior is set per query from the data's freshness needs.

### Architecture Checklist

- [ ] Client state and server state are clearly separated, with the right tool for each.
- [ ] React Query is set up once at the root; query/mutation logic is colocated with features.
- [ ] The server→client data handoff (initialData/hydration) is deliberate.
- [ ] Cache invalidation on mutations mirrors the backend's invalidation discipline (Stage 3, Chapter 07).
- [ ] Data-fetching conventions are documented in `CLAUDE.md`.

### Code Review Checklist

- [ ] No server data stored in `useState`/a global store and hand-synced (watch AI diffs).
- [ ] No raw `useEffect` + `fetch` managing server state.
- [ ] No mutation without cache invalidation/refetch.
- [ ] No waterfall of independent sequential fetches.
- [ ] No duplicate fetching of the same data across components (shared query key).

*(A Deployment Checklist is not applicable to this chapter.)*

## Exercises

**1. Replace hand-rolled fetching.** Take a component that loads server data with `useEffect` +
`fetch` + `useState` (write one, or have an assistant generate "load and show the invoices list")
and convert it to React Query, then demonstrate a benefit the old version lacked — no refetch on
remount, or a fast filter change that doesn't race. The artifact is the before/after and the
demonstrated improvement.

**2. Fix the stale mutation.** Take a "mark invoice paid" mutation with no cache invalidation and
observe the list showing stale status after the mutation succeeds. Fix it with
`invalidateQueries`, then add an optimistic update and note the difference in perceived speed. The
artifact is the two versions and a note on when the optimistic complexity is worth it.

**3. Flatten a waterfall.** Take a screen that fetches several pieces of independent data
sequentially (write it, or generate "load the invoice, its customer, and its payments") and
restructure it to fetch them in parallel (and/or on the server). The artifact is the before/after
and the load-time difference you'd expect.

## Further Reading

- **TanStack Query (React Query) documentation** (tanstack.com/query) — the authoritative guide,
  especially "Important Defaults," "Query Invalidation," and "Mutations." The invalidation and
  mutations sections directly address the stale-UI mistake.
- **TkDodo's blog — "Practical React Query" series** (tkdodo.eu/blog) — written by a React Query
  maintainer; the best practical guidance on query keys, the server-vs-client-state distinction,
  and avoiding common pitfalls.
- **Next.js documentation — "Data Fetching, Caching, and Revalidating"** (nextjs.org/docs) — how
  server-side fetching and caching work in the App Router, and how to revalidate after mutations
  on the server side; the counterpart to React Query's client cache.
- **"You Might Not Need an Effect" and the data-fetching guidance** (react.dev) — React's own
  statement that fetching in `useEffect` is not the recommended path, and why a framework or a
  library should handle it instead.

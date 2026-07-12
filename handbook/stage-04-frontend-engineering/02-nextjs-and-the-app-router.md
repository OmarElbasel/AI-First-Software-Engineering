# Next.js & the App Router

## Introduction

React is a library for building UIs; it says nothing about routing, rendering on
a server, bundling, or data loading. Next.js is the framework that supplies all
of that around React, and its modern form — the **App Router** — organizes an
application by the filesystem, renders on the server by default, and streams UI to
the browser. This chapter is about that framework layer: how routes and layouts
are structured, how the rendering strategies differ, and how to choose the right
one per route.

Two later chapters carve out the hardest parts so this one can focus. The
server/client component boundary — the single most important and most-misunderstood
idea in the modern Next.js model — gets its own chapter (Chapter 03). Data
fetching and caching get theirs (Chapter 04). Here we cover the framework
scaffolding they sit inside: filesystem routing, nested layouts, the rendering
strategies (server-rendered per request, static at build, incrementally
regenerated, client-rendered), navigation, streaming boundaries, and route
handlers.

The reason this matters as its own topic is that Next.js's power *is* its
rendering model, and the most common way to misuse it — including by an assistant
— is to ignore that model and rebuild a plain client-side single-page app inside
a framework designed to render on the server. Understanding what the framework
does, and choosing rendering deliberately per route, is what separates using
Next.js from fighting it.

## Why It Matters

The rendering strategy decides three things users and operators care about: how
fast the page appears, how fresh its data is, and how much it costs to serve. A
dashboard that must reflect live data should render on the server per request; a
marketing page that changes weekly should be static and served from a CDN; a
highly interactive editor might render its shell on the server and hydrate on the
client. Choosing wrong means a slow page, stale data, or a needless server bill —
and the default, if you don't choose, is often the worst of these by accident.

Next.js also structures the whole application, and that structure is either an
asset or a liability as it grows:

- **Routing and layouts.** Filesystem routing plus nested layouts means shared UI
  (an app shell, a sidebar, auth) is defined once and persists across navigation,
  rather than being re-declared and re-rendered on every page. Skip layouts and you
  duplicate the shell across every route and reload it on every navigation.
- **Server-first rendering.** The App Router renders on the server by default,
  which keeps data-fetching and secrets on the server, ships less JavaScript, and
  makes pages fast and indexable. Opting the whole app into client rendering throws
  all of that away.
- **Streaming and boundaries.** `loading` and `error` files give you streaming
  Suspense and error boundaries per route segment for free — a fast first paint and
  contained failures — if you use them.

The AI dimension: assistants learned React in the client-side-SPA era, so their
default instinct is to fetch data in `useEffect` on the client and render
everything in the browser — rebuilding a CSR SPA inside Next.js and discarding the
server-first model that is the point of the framework. They also mishandle Next's
caching (stale data, or no revalidation) and mix Pages-Router idioms into
App-Router projects. The result renders, and it's the framework used against
itself.

## Mental Model

The App Router maps the filesystem to routes, and special files give each segment
its behavior:

```
   app/                        →  routing by FOLDER; special files per segment:
   ├── layout.tsx              →  shared UI that WRAPS children and PERSISTS across nav
   ├── page.tsx                →  the route's page (renders on the SERVER by default)
   ├── loading.tsx             →  Suspense fallback: streams instantly while page loads
   ├── error.tsx               →  error boundary for this segment
   ├── (app)/                  →  route GROUP: organize without adding a URL segment
   │   ├── layout.tsx          →      the app shell (sidebar) — wraps everything inside
   │   ├── dashboard/page.tsx  →      /dashboard
   │   └── invoices/
   │       ├── page.tsx        →      /invoices
   │       └── [invoiceId]/    →      DYNAMIC segment
   │           └── page.tsx    →      /invoices/42
   └── api/.../route.ts        →  ROUTE HANDLER: server endpoint (a BFF / webhook)

   RENDERING STRATEGY — chosen per route, trading freshness / speed / cost:
     SSR  render on the server PER REQUEST   → fresh, personalized (a dashboard)
     SSG  render once at BUILD                → fastest, cacheable (marketing pages)
     ISR  static + periodic REVALIDATION      → fast, tolerably fresh (a blog, a catalog)
     CSR  render in the browser               → for genuinely client-only, interactive UI
```

Three principles carry the chapter:

**Routes and shared UI are the filesystem.** A folder is a route; `page.tsx` is its
page; `layout.tsx` wraps that route and everything nested under it, persisting across
navigation so the shell doesn't reload. Nesting layouts models the real UI hierarchy
(root → app shell → section) and defines shared chrome exactly once.

**Server-first is the default, and a deliberate one.** Pages render on the server
unless you opt a component into the client (Chapter 03). Server rendering keeps data
access and secrets server-side, ships less JavaScript, and produces fast, indexable
pages. Treat client rendering as a choice you make for a reason (interactivity), not
the default you reach for.

**Choose the rendering strategy per route from the data.** The question for each
route is "how fresh must this be, and how is it accessed?" Live, personalized data →
server-render per request. Rarely-changing, public content → static, optionally with
timed revalidation. Genuinely client-only interactive state → client-render. One app
mixes all of these, route by route.

A working definition:

> **Next.js is the framework around React: filesystem routing, nested persistent
> layouts, server-first rendering, and streaming. Its power is the rendering model —
> choose SSR / static / ISR / CSR per route from how fresh the data must be — and its
> most common misuse is ignoring that model to rebuild a client-side SPA inside it.**

## Production Example

**Invoicely's** web app has a clear route structure: a dashboard, an invoices list, an
invoice detail page, and settings — all inside an authenticated app shell with a
sidebar — plus public marketing pages outside it. The rendering needs differ by route:
the dashboard shows live, per-account data (server-render per request); an invoice
detail is live too; the marketing pages change rarely (static). That mix is the normal
case, and choosing per route is the skill.

We will build the App Router structure: a route group for the authenticated app with a
shared sidebar layout that persists as you navigate between invoices, a dynamic
`[invoiceId]` route, `loading` and `error` boundaries so the detail page streams and
fails gracefully, and a route handler acting as a thin backend-for-frontend to the
Stage 3 FastAPI backend. The server/client split within these pages is Chapter 03; the
data fetching is Chapter 04. Here it's the scaffolding and the rendering choices.

## Folder Structure

```
web/src/app/
├── layout.tsx                 # root layout: <html>, fonts, providers
├── (marketing)/               # route group: public pages, no app shell
│   └── page.tsx               #   / — static (SSG)
├── (app)/                     # route group: authenticated app
│   ├── layout.tsx             #   the app SHELL (sidebar, nav) — persists across nav
│   ├── dashboard/
│   │   └── page.tsx           #   /dashboard — server-rendered per request (live data)
│   └── invoices/
│       ├── page.tsx           #   /invoices — server-rendered list
│       ├── loading.tsx        #   streams instantly while the list loads
│       ├── error.tsx          #   error boundary for the invoices section
│       └── [invoiceId]/
│           └── page.tsx       #   /invoices/42 — dynamic, server-rendered
└── api/
    └── webhooks/stripe/route.ts   # route handler: a server endpoint (webhook receiver)
```

Why this shape:

- **Route groups** `(marketing)` and `(app)` organize routes and give each its own
  layout without adding URL segments — public pages get no app shell, authenticated
  pages share one.
- **The `(app)/layout.tsx`** defines the sidebar/nav once; navigating between
  `/invoices` and `/invoices/42` re-renders only the page area, not the shell.
- **`loading.tsx` and `error.tsx`** attach a streaming fallback and an error boundary
  to the invoices segment, so a slow or failed load is contained and fast-painting.
- **`api/.../route.ts`** is a server route handler — here a webhook receiver; a BFF
  proxy to the FastAPI backend would live similarly.

## Implementation

**The app shell layout (`(app)/layout.tsx`).** Shared UI that wraps every
authenticated route and persists across navigation. It's a Server Component
(Chapter 03) — it renders on the server and ships no JavaScript for the static
chrome.

```tsx
import { Sidebar } from "@/components/Sidebar";
import { requireSession } from "@/lib/auth";   // server-side auth check

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  await requireSession();                        // gate the whole (app) group on the server
  return (
    <div className="flex">
      <Sidebar />                                {/* persists — not re-rendered on nav */}
      <main className="flex-1 p-6">{children}</main>
    </div>
  );
}
```

**A server-rendered dynamic page (`invoices/[invoiceId]/page.tsx`).** The dynamic
segment arrives as a typed param; the page fetches its data on the server (Chapter 04
covers the fetch itself) and renders. No client-side data fetching, no `useEffect`.

```tsx
import { notFound } from "next/navigation";
import { getInvoice } from "@/features/invoices/api";
import { InvoiceDetail } from "@/features/invoices/InvoiceDetail";

export async function generateMetadata({ params }: { params: { invoiceId: string } }) {
  const invoice = await getInvoice(params.invoiceId);
  return { title: invoice ? `Invoice ${invoice.number}` : "Invoice" };
}

export default async function InvoicePage({ params }: { params: { invoiceId: string } }) {
  const invoice = await getInvoice(params.invoiceId);   // fetched on the SERVER
  if (!invoice) notFound();                              // → renders not-found.tsx
  return <InvoiceDetail invoice={invoice} />;
}
```

**Streaming and error boundaries (`loading.tsx`, `error.tsx`).** `loading.tsx` streams
instantly as the page's data loads (fast first paint); `error.tsx` catches a failure in
the segment and offers recovery without taking down the whole app.

```tsx
// invoices/loading.tsx — shown immediately while invoices/page.tsx awaits data
export default function Loading() {
  return <InvoiceListSkeleton />;
}

// invoices/error.tsx — must be a Client Component; catches errors in this segment
"use client";
export default function Error({ error, reset }: { error: Error; reset: () => void }) {
  return (
    <div>
      <p>Couldn't load invoices.</p>
      <button onClick={reset}>Try again</button>
    </div>
  );
}
```

**Choosing the rendering strategy (route segment config).** The dashboard needs
per-request freshness; a marketing page can be static. You choose explicitly rather
than accept a default by accident.

```tsx
// dashboard/page.tsx — always fresh, rendered per request
export const dynamic = "force-dynamic";     // SSR every request (live, per-account data)

// (marketing)/page.tsx — static, regenerated periodically (ISR)
export const revalidate = 3600;             // rebuild at most hourly; served from cache
```

**A route handler as a thin BFF / webhook (`api/webhooks/stripe/route.ts`).** Route
handlers are server endpoints in the Next app — useful for webhooks, or as a
backend-for-frontend that adds auth and hides secrets in front of the FastAPI backend.

```ts
import { NextRequest } from "next/server";

export async function POST(req: NextRequest) {
  const signature = req.headers.get("stripe-signature");
  const event = verifyStripeSignature(await req.text(), signature);   // server-only secret
  await handleStripeEvent(event);
  return Response.json({ received: true });
}
```

The through-line: the filesystem defines the routes; the nested `(app)` layout renders
the shell once and keeps it as you navigate; each page renders on the server with its
data fetched server-side; `loading`/`error` give streaming and contained failures; and
the rendering strategy is chosen per route from the data's freshness needs — dynamic for
the live dashboard, static-with-revalidation for marketing. That is Next.js used *as*
Next.js. The failure mode — the one an assistant defaults to — is a page marked
client-side that fetches in an effect, with no layout nesting and no rendering choice,
which is a client-side SPA wearing a Next.js costume.

## Engineering Decisions

Five decisions define how you use the framework.

### App Router or Pages Router?

**Options:** (1) the App Router (`app/`); (2) the legacy Pages Router (`pages/`).

**Trade-offs:** the App Router is the modern default — Server Components, nested layouts,
streaming, colocated data fetching — and is where Next.js is heading, at the cost of a
newer model to learn (and a lot of stale training data that predates it). The Pages
Router is mature and simpler in some ways but is the previous generation, without Server
Components or the streaming/layout model.

**Recommendation:** the App Router for new applications — it's the current model and the
one this stage teaches. Don't mix the two routers or import Pages-Router idioms
(`getServerSideProps`, `getStaticProps`) into an App-Router project; they don't apply and
signal outdated (often AI-generated) code.

### Which rendering strategy per route?

**Options:** SSR (per request), SSG (at build), ISR (static + revalidation), CSR (client).

**Trade-offs:** SSR is always-fresh and personalized but runs server work on every
request. SSG is fastest and cheapest (served from a CDN) but frozen until the next build.
ISR gets static speed with bounded staleness via periodic revalidation. CSR ships an
empty shell and renders in the browser — right for highly interactive, client-only UI,
wrong for content that should be fast and indexable.

**Recommendation:** choose per route from the data. Live, personalized data (dashboard,
invoice detail) → SSR. Rarely-changing public content (marketing, docs) → SSG, or ISR if
it changes on a known cadence. Reserve CSR for genuinely client-only interactivity. One
app mixes strategies route by route; a single global choice is almost always wrong for
some routes.

### How are layouts and route groups structured?

**Options:** (1) repeat shared UI per page; (2) nested layouts and route groups.

**Trade-offs:** repeating the shell per page is simple for one page and duplicative and
slow across many (the shell re-renders on every navigation, and changing it means editing
every page). Nested layouts define shared UI once, persist it across navigation (only the
page area re-renders), and model the UI hierarchy; route groups organize routes and scope
layouts without polluting the URL — at the cost of learning the convention.

**Recommendation:** use nested layouts for all shared UI (app shell, section chrome) and
route groups to give different areas different layouts (public vs authenticated) without
extra URL segments. This is Stage 2's feature/shared organization applied to routing:
define shared chrome once, at the right level.

### Route handlers/BFF, or call the backend directly from the client?

**Options:** (1) the client calls the (FastAPI) backend directly; (2) a Next route handler
sits in front as a backend-for-frontend.

**Trade-offs:** calling the backend directly is simplest and exposes the backend to the
browser (CORS, tokens in the client) and offers no place to hide secrets or aggregate
calls. A BFF route handler runs on the server — it can hold secrets, add auth, aggregate
multiple backend calls into one, and shape responses for the UI — at the cost of another
hop and a layer to maintain.

**Recommendation:** call the backend directly (from Server Components) for straightforward
reads where the backend already enforces auth; introduce a BFF route handler when you need
server-side secrets, response aggregation, webhook receipt, or to keep the backend off the
public internet. Don't build a BFF reflexively — it's a real layer (Stage 2, Chapter 06's
buy/build restraint applies) — but reach for it when those needs are real.

### Where does auth/session live?

**Options:** (1) check auth in each page/component; (2) gate at layouts and middleware.

**Trade-offs:** per-page checks are explicit and easy to forget on the next page (a
Chapter 04-style authorization gap). Gating at a shared layout (server-side) and/or
middleware centralizes the check so a whole route group is protected by default.

**Recommendation:** gate authenticated route groups at their shared server layout (and/or
Next middleware) so protection is default-on for everything nested inside, rather than
opt-in per page — the deny-by-default posture from Stage 3, Chapter 04, applied to routing.

## Trade-offs

Next.js buys structure and rendering power at the cost of a model you must actually learn.

**The rendering model trades simplicity for control — and confuses.** Having four
rendering strategies and a server/client split gives precise control over speed,
freshness, and cost, and it is genuinely more to understand than a plain SPA. The App
Router's caching and rendering behavior is a well-known source of confusion; the mitigation
is to choose rendering explicitly per route and understand the caching (Chapter 04) rather
than trusting defaults. The power is real; so is the learning curve.

**Server-first trades some interactivity locality for speed and safety.** Rendering on the
server ships less JS and keeps secrets server-side, but interactivity requires deliberately
crossing to the client (Chapter 03), which is more ceremony than "everything is client."
For content-and-data apps (most SaaS) the trade strongly favors server-first; for an app
that is essentially one big interactive canvas, the balance shifts.

**A BFF trades a hop for control.** A route-handler BFF adds latency and a layer, and buys
secret-hiding, aggregation, and a shaping point. It's worth it when those needs exist and
overhead when they don't — a deliberate call, not a default.

**Framework lock-in is real but usually worth it.** Adopting Next.js couples you to its
routing, rendering, and deployment model; leaving is a rewrite. For most React apps the
productivity and performance are worth the coupling, but it is a one-way-door decision
(Stage 1, Chapter 04) to make deliberately, not by reflex.

## Common Mistakes

**Rebuilding a client-side SPA inside Next.js.** Marking pages client, fetching in
`useEffect`, ignoring rendering strategy — discarding the server-first model entirely. Fix:
render on the server by default; fetch server-side; opt into the client only for
interactivity (Chapter 03).

**No rendering strategy chosen.** Accepting whatever the default does, so a live dashboard
serves stale cached data or a static page needlessly runs per-request work. Fix: choose
SSR/SSG/ISR/CSR per route from the data's freshness needs, explicitly.

**Duplicated layouts / no nesting.** Repeating the app shell per page, re-rendering it on
every navigation and editing it everywhere to change it. Fix: nested layouts for shared UI;
route groups for area-specific layouts.

**Mixing Pages- and App-Router idioms.** `getServerSideProps`/`getStaticProps` in an
App-Router project, or mixing the two routers — outdated patterns that don't apply. Fix:
App-Router data fetching and conventions only; treat Pages-Router idioms as a red flag
(often AI-generated from stale data).

**Per-page auth instead of gated groups.** Checking auth in each page and forgetting it on
the next one. Fix: gate authenticated route groups at a shared server layout/middleware
(deny by default).

## AI Mistakes

Assistants learned React in the client-side-SPA era, and the App Router post-dates most of
their training data — so they default to the pre-framework habits and to older Next idioms.
Review generated Next.js code for whether it uses the framework's model or fights it.

### Claude Code: rebuilding a CSR SPA inside Next.js

Asked to build a page, Claude Code tends to make it client-rendered and fetch its data in a
`useEffect`, because that's the SPA pattern that dominates its React training — discarding
server rendering, shipping more JavaScript, and reintroducing loading spinners and
waterfalls the server would have avoided.

**Detect:** `"use client"` on a page that only displays data; data fetched in `useEffect`
on a route that could server-render; no use of Server Components, `loading.tsx`, or
server-side data fetching.

**Fix:** require server-first rendering:

> This is Next.js App Router — render on the server by default and fetch data in the Server
> Component, not in a client-side `useEffect`. Only opt a component into the client
> (`"use client"`) for interactivity (Chapter 03). Use `loading.tsx` for the loading state,
> not a client fetch-and-spinner.

### GPT: stale data and Pages-Router idioms

GPT-family models frequently mishandle the App Router's caching — no revalidation strategy,
so mutations don't reflect or a route serves stale cached data — and mix in Pages-Router
APIs (`getServerSideProps`, `getStaticProps`) that don't exist in the App Router, because
those saturate its older training data.

**Detect:** `getServerSideProps`/`getStaticProps`/`getInitialProps` in an `app/` project;
no `revalidate`/cache handling on fetches; data that doesn't update after a mutation; the
two routers mixed.

**Fix:** require current App-Router patterns:

> Use App-Router data fetching only — no `getServerSideProps`/`getStaticProps`. Set caching
> explicitly per fetch/route (`revalidate`, `cache`, or `dynamic`), and revalidate after
> mutations so data isn't stale (Chapter 04). Do not mix Pages-Router and App-Router
> idioms.

### Cursor: flat routing and duplicated shells

Building pages inline, Cursor tends to repeat the header/sidebar markup in each page rather
than using a nested layout, and to create flat routes without groups, because each page is
edited in isolation without the routing structure in view. The shell duplicates and
re-renders on every navigation.

**Detect:** the same shell/nav markup repeated across `page.tsx` files; no `layout.tsx` for
shared chrome; navigation that visibly reloads the whole shell; no route groups separating
public from authenticated areas.

**Fix:** require layout nesting:

> Put shared UI (app shell, sidebar, nav) in a nested `layout.tsx`, not repeated in each
> page, so it's defined once and persists across navigation. Use route groups to give the
> public and authenticated areas their own layouts without extra URL segments.

## Best Practices

**Render on the server by default; choose the strategy per route.** Let pages be
server-rendered, opt into the client only for interactivity (Chapter 03), and pick
SSR/SSG/ISR/CSR per route from how fresh the data must be — explicitly, not by default.

**Structure routes with nested layouts and groups.** Define shared UI once in nested
layouts so it persists across navigation; use route groups to give different areas
different layouts without polluting the URL. Fetch data on the server, in the page.

**Use streaming and error boundaries.** Add `loading.tsx` for instant streamed fallbacks
and `error.tsx` for contained, recoverable failures per segment, rather than client
spinners and app-wide error states.

**Gate auth at shared layouts, and use route handlers deliberately.** Protect authenticated
route groups at a shared server layout/middleware (deny by default); add a BFF route handler
when you need server secrets, aggregation, or webhooks — not reflexively.

**Stay on current App-Router patterns.** No Pages-Router idioms, no mixing routers, caching
set explicitly. Record the rendering-strategy decisions per route where non-obvious, and put
the routing/rendering conventions in `CLAUDE.md` so assistants stop reaching for the SPA
default.

## Anti-Patterns

**The SPA-in-Next.** The whole app client-rendered with `useEffect` data fetching —
Next.js used as a create-react-app SPA, its server model discarded. The tell: `"use client"`
at the top of the tree and no server-side data fetching anywhere.

**The Default-Rendering Gamble.** No explicit rendering strategy, so freshness and cost are
whatever the default happens to be — stale dashboards or needlessly dynamic static pages. The
tell: no `dynamic`/`revalidate`/`cache` decisions and surprise staleness or cost.

**The Copy-Pasted Shell.** The app chrome duplicated across pages instead of a nested layout —
re-rendered on every navigation and changed in N places. The tell: identical header/sidebar
markup in every `page.tsx`.

**The Router Time Warp.** Pages-Router APIs in an App-Router project (or the two mixed) —
outdated patterns that don't apply. The tell: `getServerSideProps` in `app/`.

**The Ungated Route.** Authentication checked per page and forgotten on new ones, instead of
gated at a shared layout. The tell: a new authenticated page that's accidentally public.

## Decision Tree

"I'm adding a route — how do I structure and render it?"

```
RENDERING — how fresh must this route's data be, and how interactive is it?
├─ Live / personalized data (a dashboard, a user's record) ──► SSR (render per request).
├─ Rarely-changing public content ──► SSG (static); on a known cadence ──► ISR (revalidate).
└─ Genuinely client-only interactive UI ──► CSR (client component; Chapter 03).
   (Choose explicitly — don't accept the default by accident.)

STRUCTURE
├─ Shared UI (shell, nav, section chrome)? ──► a nested layout.tsx (persists across nav).
├─ Different layout for a group of routes (public vs app)? ──► a route group (name).
└─ A slow segment? ──► add loading.tsx (stream) and error.tsx (contain failures).

DATA
└─ Fetch on the SERVER in the page (Chapter 04). Not in a client useEffect.

AUTH
└─ Gate the authenticated route GROUP at its shared server layout / middleware (deny by default).

A SERVER ENDPOINT (webhook, secret-holding aggregation)? ──► a route handler (api/.../route.ts).
```

## Checklist

### Implementation Checklist

- [ ] Each route's rendering strategy (SSR/SSG/ISR/CSR) is chosen explicitly from its data freshness.
- [ ] Shared UI lives in nested layouts and persists across navigation; route groups separate public/authenticated areas.
- [ ] Pages render on the server and fetch their data server-side, not in a client `useEffect`.
- [ ] Slow segments have `loading.tsx` (streaming) and `error.tsx` (error boundary).
- [ ] Authenticated route groups are gated at a shared server layout/middleware.
- [ ] Only App-Router patterns are used; no Pages-Router idioms and no router mixing.

### Architecture Checklist

- [ ] The route structure mirrors the product's information hierarchy (groups, nesting).
- [ ] BFF route handlers exist only where server secrets/aggregation/webhooks require them.
- [ ] Caching/revalidation is set deliberately per route (detailed in Chapter 04).
- [ ] The App Router choice and any non-obvious per-route rendering decisions are recorded.
- [ ] Routing/rendering conventions are documented in `CLAUDE.md`.

### Code Review Checklist

- [ ] No page needlessly client-rendered or fetching data in `useEffect` (watch AI diffs).
- [ ] No Pages-Router API (`getServerSideProps` etc.) in the App Router.
- [ ] No shared shell duplicated across pages instead of a layout.
- [ ] Rendering strategy is explicit and correct for the route's freshness needs.
- [ ] New authenticated routes are covered by the group's auth gate.

*(A Deployment Checklist for the frontend is Stage 7; rendering strategy interacts with
deployment/CDN, covered there.)*

## Exercises

**1. Choose rendering per route.** For Invoicely's routes — dashboard, invoice detail,
public pricing page, blog — decide the rendering strategy (SSR/SSG/ISR/CSR) for each and
justify it from the data's freshness and access. The artifact is the table with a one-line
reason each; the point is that a single strategy is wrong for at least one route.

**2. Nest the layouts.** Take a set of pages that each duplicate an app shell (write them,
or have an assistant generate "a dashboard and an invoices page") and refactor the shell into
a nested `(app)/layout.tsx` with a route group, so it's defined once and persists across
navigation. The artifact is the before/after structure and a note on what re-renders on
navigation in each version.

**3. Server-render a client page.** Take a page that's client-rendered and fetches in
`useEffect` (the SPA-in-Next anti-pattern) and convert it to a Server Component that fetches
on the server, with a `loading.tsx` for the streamed fallback. The artifact is the before/
after and a note on what the user experiences differently (first paint, JS shipped).

## Further Reading

- **Next.js documentation — App Router: Routing, Layouts and Pages, Rendering, and Caching**
  (nextjs.org/docs) — the authoritative reference for everything in this chapter; the Routing
  and Rendering sections especially. Prefer the docs over blog posts, which are often written
  against the older Pages Router.
- **Next.js — "Rendering: Server Components" and "Partial Prerendering"** (nextjs.org/docs) —
  the framework's own explanation of the rendering model and where it's heading; essential
  background before Chapter 03's server/client deep dive.
- **Patterns.dev — Rendering Patterns** (patterns.dev) — a clear, framework-neutral tour of
  SSR, SSG, ISR, CSR, and streaming, so you understand the strategies as concepts, not just
  Next.js APIs.
- **Vercel — Caching and revalidation guides** (vercel.com/docs) — practical guidance on the
  App Router's caching behavior (the most confused part of the framework), useful alongside
  Chapter 04.

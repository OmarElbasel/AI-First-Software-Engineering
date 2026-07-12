# Server & Client Components

## Introduction

This chapter is about the single most important — and most misunderstood — idea
in the modern React/Next.js model: the boundary between **Server Components** and
**Client Components**. In the App Router, components render on the server by
default, ship no JavaScript to the browser, and can access data and secrets
directly; a component only runs in the browser (with state, effects, event
handlers, and browser APIs) when you explicitly mark it with `"use client"`.
Learning where to draw that boundary is the core skill of this stage.

Chapter 02 established that Next.js renders server-first; this chapter is the
mechanics of *how you keep it that way while still having an interactive UI*. The
answer is an "islands" model: the page is a server-rendered tree, and
interactivity lives in small client-side islands pushed to the leaves. Get the
boundary right and you ship a fast, mostly-server-rendered page with tiny
interactive pieces; get it wrong — the universal mistake, and the one assistants
make by default — and you mark the whole page `"use client"`, turning a
server-first framework back into a client-side SPA.

The boundary also carries real correctness and composition rules that trip
everyone up at first: what each kind of component *can* do (a Server Component
can't use `useState`; a Client Component can't query the database), how they
compose (a Client Component can't import a Server Component but can receive one as
children), and what can cross the line (only serializable data). Those rules are
the substance of the chapter, because violating them is exactly how the model
breaks.

## Why It Matters

The server/client boundary directly determines a page's JavaScript size,
performance, and security surface — three things users and attackers both notice.

- **JavaScript shipped.** Server Components render to output and ship *zero*
  JavaScript for their own logic; Client Components ship their code (and their
  imports) to the browser. Marking the whole page `"use client"` means shipping
  the entire page's JavaScript, slowing load and interactivity — the exact cost
  the server-first model exists to avoid. Small client islands keep the bundle
  small.
- **Data and secrets.** Server Components run only on the server, so they can read
  the database, call internal services, and use secret keys directly and safely.
  Client Components run in the browser, where any secret is exposed — so pushing
  logic that touches secrets into a Client Component either breaks (no access) or,
  worse, leaks a key into the bundle.
- **Interactivity.** Only Client Components can hold state, run effects, attach
  event handlers, and use browser APIs. A button that does something, a form, a
  dropdown — those must be Client Components. The art is making *only* those pieces
  client, not the static content around them.

The whole payoff is an islands architecture: a fast, server-rendered page with
interactivity confined to small, cheap client islands. The failure — one big
`"use client"` at the top — forfeits every server benefit at once.

The AI dimension is acute because this model post-dates most training data and
inverts the SPA default. Assistants slap `"use client"` at the top of the tree
(the whole page becomes client), try to use `useState`/`onClick` in Server
Components (a runtime error) or query the database in Client Components, and break
the composition and serialization rules (importing a Server Component into a
Client Component, passing a function across the boundary). Each collapses the model
this chapter is about.

## Mental Model

The page is a server tree with client islands at the leaves, and one directive
marks the boundary:

```
   SERVER by default ──────────────────────────────────────────────
   ┌──────────────────────────────────────────────────────────────┐
   │  <InvoicePage>          Server Component (async, fetches data,  │
   │    <InvoiceHeader/>       reads secrets, ships NO JS)            │
   │    <InvoiceLineItems/>                                          │
   │    <MarkPaidButton/> ◄── "use client" ── CLIENT ISLAND          │
   │                          (state, onClick, ships JS — small!)    │
   │    <StatusDropdown/> ◄── "use client" ── CLIENT ISLAND          │
   └──────────────────────────────────────────────────────────────┘
   Push "use client" DOWN to the smallest interactive leaves.

   WHAT EACH CAN DO
     SERVER  ✓ async · direct DB / secrets / internal calls · zero JS
             ✗ useState/useEffect · onClick · browser APIs · interactivity
     CLIENT  ✓ state/effects · event handlers · browser APIs · interactivity
             ✗ direct DB/secret access · async component · (ships JS)

   COMPOSITION RULES
     Server CAN render Client.                       ✓
     Client CANNOT import Server.                    ✗
     Client CAN receive Server as {children}/props.  ✓  ← the key pattern
     Across the boundary: only SERIALIZABLE data (no functions, no class instances).
```

Four principles govern the boundary:

**Server by default; client only for interactivity.** A component stays a Server
Component unless it needs state, effects, event handlers, or browser APIs. Those are
the only reasons to reach for `"use client"`. Static content — text, layout,
server-fetched data displayed — is a Server Component and ships no JavaScript.

**Push `"use client"` to the leaves.** The directive marks a boundary: the component
*and everything it imports* become part of the client bundle. So place it as low and
narrow as possible — on the interactive leaf (the button, the dropdown), not on the
page or layout. One directive high in the tree drags the whole subtree to the client.

**Compose client-in-server, and server-as-children-to-client.** A Server Component can
render a Client Component directly. A Client Component *cannot import* a Server
Component (it would pull server code into the browser), but it *can receive one as
`children` or props* — so an interactive client shell (tabs, a collapsible, a modal)
can wrap server-rendered content passed in as children. This slot pattern is how you
keep content on the server while the interactive wrapper is on the client.

**Only serializable data crosses the boundary.** Props passed from a Server Component
to a Client Component are serialized to reach the browser, so they must be
serializable — plain data, not functions, class instances, or other non-serializable
values. Pass the data the island needs, and keep it minimal.

A working definition:

> **Server Components render on the server and ship no JS; Client Components run in
> the browser and provide interactivity. Stay server by default, push `"use client"`
> to the smallest interactive leaves, compose by passing server content as children
> into client shells, and send only serializable data across the boundary. One big
> `"use client"` at the top throws the whole model away.**

## Production Example

**Invoicely's** invoice detail page is the ideal case: it is mostly static,
server-rendered content — the invoice header, the line items, the customer info,
fetched on the server — with a few interactive pieces: a "Mark as paid" button, a
status dropdown, a "copy link" button. That is precisely the shape the server/client
model is designed for: a server tree with small client islands.

We will build the page as a Server Component that fetches the invoice and renders the
static content, with the interactive pieces extracted into small Client Component
islands pushed to the leaves. We'll show the key composition move — a client `Tabs`
shell receiving server-rendered panels as children — and contrast it with the
anti-pattern of marking the whole page `"use client"`, which would ship all of it as
JavaScript and require fetching the invoice on the client. The interactivity is a
fraction of the page; keeping the client footprint to that fraction is the lesson.

## Folder Structure

```
web/src/features/invoices/
├── InvoiceDetail.tsx         # SERVER Component: fetches + renders static content
├── InvoiceHeader.tsx         # SERVER: static, no JS
├── MarkPaidButton.tsx        # "use client": interactive island (state + onClick)
├── StatusDropdown.tsx        # "use client": interactive island
└── Tabs.tsx                  # "use client": interactive shell that takes server children
```

Why this shape: the default is Server Components (no directive), and only the files
that need interactivity carry `"use client"`. The interactive components are separate,
small files at the leaves — so the `"use client"` boundary is narrow, and the bulk of
the page ships as zero-JS server output. `Tabs.tsx` is a client shell designed to
receive server-rendered children (the slot pattern).

## Implementation

**The page — a Server Component (`InvoiceDetail.tsx`).** No directive (server by
default), `async` so it fetches directly on the server, and it renders static content
plus small client islands. It ships no JavaScript for itself.

```tsx
// Server Component (no "use client"): async, fetches on the server, ships no JS.
import { getInvoice } from "./api";
import { InvoiceHeader } from "./InvoiceHeader";
import { MarkPaidButton } from "./MarkPaidButton";     // client island
import { StatusDropdown } from "./StatusDropdown";     // client island

export async function InvoiceDetail({ invoiceId }: { invoiceId: string }) {
  const invoice = await getInvoice(invoiceId);          // direct server data access

  return (
    <article>
      <InvoiceHeader invoice={invoice} />               {/* server, static, no JS */}
      <StatusDropdown                                    /* client island — leaf */
        invoiceId={invoice.id}
        current={invoice.status}                        // serializable props only
      />
      <ul>
        {invoice.lineItems.map((item) => (              /* server-rendered list */
          <li key={item.id}>{item.description} — {formatMoney(item.total)}</li>
        ))}
      </ul>
      {invoice.status !== "paid" && (
        <MarkPaidButton invoiceId={invoice.id} />        // client island — leaf
      )}
    </article>
  );
}
```

**An interactive leaf — a Client Component (`MarkPaidButton.tsx`).** It needs state
and an event handler, so it's a Client Component — and it's *small*, so the client
bundle it adds is small. It receives serializable data (an id) and calls a mutation.

```tsx
"use client";                    // THIS component (and its imports) join the client bundle
import { useState } from "react";
import { markInvoicePaid } from "./actions";     // a Server Action (Ch 06) or client fetch

export function MarkPaidButton({ invoiceId }: { invoiceId: number }) {
  const [pending, setPending] = useState(false);
  return (
    <button
      disabled={pending}
      onClick={async () => {                       // event handler → must be client
        setPending(true);
        await markInvoicePaid(invoiceId);
        setPending(false);
      }}
    >
      {pending ? "Marking…" : "Mark as paid"}
    </button>
  );
}
```

**The composition trick — server content as children of a client shell (`Tabs.tsx`).**
A client `Tabs` needs state (which tab is active), but the *panels* are static
server-rendered content. The client shell can't import server components — but it can
receive them as `children`, so the panels stay on the server while only the tab-switching
logic is client-side.

```tsx
"use client";
import { useState } from "react";

// Client shell: interactive, but its content is passed IN as server-rendered children.
export function Tabs({ tabs }: { tabs: { label: string; content: React.ReactNode }[] }) {
  const [active, setActive] = useState(0);
  return (
    <div>
      <div role="tablist">
        {tabs.map((t, i) => (
          <button key={t.label} aria-selected={i === active} onClick={() => setActive(i)}>
            {t.label}
          </button>
        ))}
      </div>
      <div role="tabpanel">{tabs[active].content}</div>   {/* server-rendered content */}
    </div>
  );
}
```

```tsx
// Used from a SERVER Component — the panels are server-rendered and passed as children:
<Tabs tabs={[
  { label: "Details", content: <InvoiceHeader invoice={invoice} /> },   // server content
  { label: "History", content: <InvoiceHistory invoiceId={invoice.id} /> }, // server content
]} />
```

**The anti-pattern — `"use client"` at the top.** Marking the page client turns the
whole subtree into client code and forces client-side data fetching:

```tsx
// ANTI-PATTERN: the whole page becomes a client bundle, must fetch on the client
"use client";
import { useEffect, useState } from "react";
export function InvoiceDetailBad({ invoiceId }: { invoiceId: string }) {
  const [invoice, setInvoice] = useState(null);
  useEffect(() => { fetch(...).then(setInvoice); }, [invoiceId]);   // client waterfall
  // ...everything below is now client JS, and secrets can't be used here
}
```

The difference is the whole chapter: the good version is a server tree that ships JS
only for the button and the dropdown, fetches the invoice on the server (fast, secure,
no waterfall), and keeps the panels server-rendered inside a client tab shell. The bad
version ships the entire page as JavaScript, fetches on the client (a spinner and a
waterfall), and can't touch server-only resources. The interactive surface is
identical; the client footprint is not.

## Engineering Decisions

Five decisions define the boundary.

### Server Component or Client Component?

**Options:** (1) client; (2) server.

**Trade-offs:** a Client Component gives interactivity (state, effects, event handlers,
browser APIs) and ships JavaScript and can't touch server-only resources. A Server
Component ships no JS, can access data and secrets directly, and can't be interactive.

**Recommendation:** Server Component by default; reach for a Client Component *only* when
the component genuinely needs state, effects, event handlers, or browser APIs. "Does this
need interactivity or a browser API?" is the entire test — if no, it stays on the server.
Most components in a typical app are (or should be) Server Components.

### Where do you place the `"use client"` boundary?

**Options:** (1) high (page/layout); (2) at the smallest interactive leaves.

**Trade-offs:** placing it high is fewer directives and drags the whole subtree — and all
its imports — into the client bundle, forfeiting server rendering for everything beneath.
Placing it at the leaves keeps the client bundle tiny (just the interactive pieces) at the
cost of a few more small client files.

**Recommendation:** push `"use client"` as low and narrow as possible — on the interactive
leaf component, never on a page or layout. Extract the interactive piece into its own small
component and mark *that* client, leaving its parents on the server. The directive is a
boundary; keep it around the smallest possible island.

### How do you compose across the boundary?

**Options:** (1) import a Server Component into a Client Component; (2) pass server content
into a client shell as children/props.

**Trade-offs:** importing a Server Component into a Client Component doesn't work — it pulls
server code into the client bundle and breaks the model. Passing server content as
`children`/props to a client shell keeps the content on the server while the interactive
wrapper is on the client — the correct and only clean way to combine them.

**Recommendation:** compose with the children-as-props (slot) pattern: build interactive
shells (tabs, modals, collapsibles) as Client Components that accept server-rendered
`children`, so content stays server-side and only the interaction logic is client. A Server
Component can render a Client Component directly; a Client Component receives server content,
never imports it.

### What crosses the boundary?

**Options:** (1) pass anything; (2) pass only serializable, minimal data.

**Trade-offs:** props from server to client are serialized, so non-serializable values
(functions, class instances, some complex objects) can't cross — passing them breaks. And
passing large objects when the island needs one field wastes serialization and bundle.

**Recommendation:** pass only serializable data across the boundary, and only what the
island actually needs (an id, a status — not the whole entity). Keep interactive islands
data-light. For actions that must run on the server, use Server Actions (Chapter 06) rather
than trying to pass server functions to the client.

### Server Action or client fetch for mutations?

**Options:** (1) a client-side fetch to an API; (2) a Server Action invoked from the client.

**Trade-offs:** a client fetch is the familiar pattern and requires an API endpoint and
client-side handling. A Server Action lets a Client Component call a server function directly
(the framework handles the round trip), keeping mutation logic and secrets on the server —
at the cost of a newer pattern and its own caveats.

**Recommendation:** Server Actions are a clean fit for form and button mutations in the App
Router — they keep the mutation on the server without a hand-written endpoint (detailed with
forms in Chapter 06). Use a client fetch/React Query when you need client-side cache
management around the mutation (Chapter 04). Either way, the *trigger* is a small client
island; the *work* stays on the server.

## Trade-offs

The server/client model buys performance and security at the cost of a boundary you must
reason about.

**Server-first trades a mental model for a smaller, safer bundle.** Splitting components
into server and client is more to think about than "everything is a client component," and
it returns dramatically less shipped JavaScript, direct and safe server data access, and
faster pages. For content-and-data apps the trade is strongly worth it; the cost is the
discipline to decide, per component, which side of the line it's on.

**Small islands trade a few more files for a fast page.** Extracting each interactive piece
into its own client leaf is more files than one big client page, and it keeps the client
bundle to just the interactive surface. The file count is trivial; the bundle difference is
not.

**The composition rules are real constraints.** The "client can't import server" rule and
the serialization boundary are genuine limits that shape how you structure components — the
children-as-props pattern exists to work within them. They feel restrictive at first and are
what make the model coherent; fighting them (trying to import server into client, passing
functions across) just breaks things.

**The model is newer and less familiar.** Server Components invert the SPA default most
developers (and assistants) internalized, so there's a real learning curve and a lot of
outdated guidance and generated code that ignores the boundary. The payoff is worth the
learning; the cost is vigilance against reverting to the all-client habit.

## Common Mistakes

**`"use client"` at the top of the tree.** Marking a page or layout client, dragging the
whole subtree into the client bundle and forfeiting server rendering. Fix: server by
default; push `"use client"` to the smallest interactive leaves.

**Interactivity in a Server Component.** `useState`, `onClick`, or a browser API in a
component with no `"use client"` — a runtime/build error. Fix: extract the interactive piece
into a Client Component leaf.

**Server-only access in a Client Component.** Trying to read the database, use a secret, or
make a server-internal call from a Client Component — it breaks or leaks the secret into the
bundle. Fix: keep data/secret access in Server Components; pass the resulting data (or use a
Server Action) to the client island.

**Importing a Server Component into a Client Component.** Pulling server code into the client
bundle, breaking the boundary. Fix: pass server content as `children`/props to the client
shell (the slot pattern), never import it.

**Passing non-serializable props across the boundary.** Functions, class instances, or
complex objects passed from server to client, which can't be serialized. Fix: pass only
serializable data (and only what's needed); use Server Actions for server-side behavior.

## AI Mistakes

This model post-dates most training data and inverts the SPA default, so assistants
reliably collapse it — and the mistakes often "work" enough to render, masking that the
whole page became client JavaScript or that a secret leaked. Review generated components for
which side of the boundary they're on and why.

### Claude Code: `"use client"` too high, poisoning the tree

Asked for an interactive page, Claude Code tends to put `"use client"` at the top of the
page or a layout — because "the page has a button, so the page is a client component" — which
turns the entire subtree (and all its imports) into client JavaScript and forces client-side
data fetching. The interactivity needed one leaf; the whole page paid for it.

**Detect:** `"use client"` on a page or layout, or high in the tree above large amounts of
static content; a big client subtree where only a button or two is interactive; server data
fetching replaced by a client `useEffect` because the page went client.

**Fix:** push the boundary down:

> Keep this a Server Component. Extract only the interactive parts (the button, the dropdown)
> into their own small Client Components marked `"use client"`, and leave the page and its
> static content on the server. `"use client"` belongs on the smallest interactive leaves, not
> the page.

### GPT: putting the wrong capability on the wrong side

GPT-family models frequently use `useState`/`useEffect`/`onClick` in a component with no
`"use client"` (interactivity in a Server Component — an error), or conversely try to query
the database / use a secret inside a Client Component, because it doesn't track which runtime
each component belongs to.

**Detect:** hooks, event handlers, or browser APIs in a component without `"use client"`;
direct database/ORM calls, secret env vars, or server-internal imports inside a component
marked `"use client"`.

**Fix:** state what each side can do:

> Interactivity (state, effects, event handlers, browser APIs) requires a Client Component
> (`"use client"`). Data and secret access must stay in a Server Component. Don't use hooks in
> a Server Component, and don't touch the database or secrets in a Client Component — move each
> to the correct side and pass data across as needed.

### Cursor: broken composition and non-serializable props

Wiring components together inline, Cursor tends to import a Server Component into a Client
Component (breaking the boundary) and to pass functions or class instances as props from a
Server Component to a Client Component (non-serializable), because from the edit site the
boundary isn't visible.

**Detect:** a `"use client"` component importing a Server Component; a function, class
instance, Date, or other non-serializable value passed as a prop from a Server to a Client
Component; a "cannot be passed to Client Component" or serialization error.

**Fix:** require the correct composition:

> A Client Component can't import a Server Component — pass server-rendered content in as
> `children`/props (the slot pattern) instead. Across the server→client boundary, pass only
> serializable data (ids, strings, plain objects), never functions or class instances; use a
> Server Action for server-side behavior.

## Best Practices

**Server by default; client only for interactivity.** A component stays a Server Component
unless it needs state, effects, event handlers, or browser APIs — those are the only reasons
to add `"use client"`. Most components ship no JavaScript.

**Push the `"use client"` boundary to the smallest leaves.** Extract interactive pieces into
their own small Client Components and mark those client, leaving pages, layouts, and static
content on the server. Keep client islands small and data-light.

**Compose with the slot pattern.** Build interactive shells as Client Components that accept
server-rendered `children`; a Server Component renders Client Components directly, and a
Client Component never imports a Server Component. This keeps content on the server inside
client wrappers.

**Keep data and secrets on the server; pass only serializable data across.** Fetch data and
use secrets in Server Components; pass the minimal serializable result to client islands, and
use Server Actions (Chapter 06) for server-side mutations triggered from the client.

**Make the boundary a documented convention.** State in `CLAUDE.md` that the app is
server-first and `"use client"` goes on interactive leaves only — this is the single most
effective guard against an assistant reverting to the all-client default.

## Anti-Patterns

**The Top-Level `"use client"`.** The directive on a page or layout, turning the whole subtree
into client JavaScript and forcing client-side fetching — the server model discarded. The
tell: `"use client"` at the top of a page with mostly static content below it.

**The Wrong-Runtime Component.** Interactivity in a Server Component (hooks/handlers without
`"use client"`) or data/secret access in a Client Component. The tell: a build error about
hooks on the server, or a secret/DB call inside a `"use client"` file.

**The Server Import Into Client.** A Client Component importing a Server Component, pulling
server code into the browser bundle. The tell: an import of a server component from inside a
`"use client"` file, or a build error about it.

**The Non-Serializable Prop.** A function or class instance passed from a Server to a Client
Component across the boundary. The tell: a "cannot be serialized / passed to a Client
Component" error, or a handler passed down instead of using a Server Action.

**The Client Continent.** No islands at all — the interactive parts never extracted, so a
huge client region exists to support a couple of buttons. The tell: a large `"use client"`
subtree whose only interactivity is a small fraction of it.

## Decision Tree

"I have a component — server or client, and how do I compose it?"

```
Does this component need state, effects, event handlers, or a browser API?
├── NO ──► SERVER Component (default). No "use client". Ships no JS.
│          It can fetch data / use secrets directly, and render Client Components.
└── YES ──► CLIENT Component ("use client") — but make it the SMALLEST interactive LEAF.
     │       Extract just the interactive part into its own component; keep parents on the server.
     │
     Does this client component need to show static / server-fetched content?
     ├── YES ──► receive it as {children}/props (slot pattern). Do NOT import a Server Component.
     └── NO ───► fine as-is.
     │
     Passing data from server → client? ──► SERIALIZABLE data only (ids, strings, plain objects).
     Need server-side behavior from the client? ──► a Server Action (Ch 06), not a passed function.
```

## Checklist

### Implementation Checklist

- [ ] Components are Server Components by default; `"use client"` appears only where interactivity/browser APIs are needed.
- [ ] The `"use client"` boundary is on the smallest interactive leaves, never on pages or layouts.
- [ ] Data fetching and secret access happen in Server Components; client islands receive serializable data.
- [ ] Server content is composed into client shells via `children`/props, never by importing server into client.
- [ ] Only serializable values cross the server→client boundary; server-side behavior uses Server Actions.
- [ ] Interactive islands are small and data-light.

### Architecture Checklist

- [ ] The page is a server tree with small client islands (islands architecture), not a client continent.
- [ ] No secret or server-only resource is reachable from a Client Component.
- [ ] Reusable interactive shells use the slot pattern to accept server children.
- [ ] The client JavaScript footprint reflects only the genuinely interactive surface.
- [ ] The server-first / boundary convention is documented in `CLAUDE.md`.

### Code Review Checklist

- [ ] No `"use client"` on a page/layout or high above static content (watch AI diffs).
- [ ] No hooks/handlers in a Server Component, and no DB/secret access in a Client Component.
- [ ] No Client Component importing a Server Component.
- [ ] No non-serializable prop (function, class instance) passed server→client.
- [ ] Interactivity is confined to small extracted leaves.

*(A Deployment Checklist is not applicable to this chapter.)*

## Exercises

**1. Split a page into islands.** Take a whole-page `"use client"` invoice detail (write one,
or have an assistant generate "an interactive invoice page") and refactor it into a Server
Component that fetches on the server, with only the interactive pieces (a button, a dropdown)
extracted as small client leaves. The artifact is the before/after and a note on the JavaScript
each version ships.

**2. Use the slot pattern.** Build an interactive client `Tabs` (or accordion) component whose
panels are server-rendered content passed as children, and use it from a Server Component.
Confirm the panels are server-rendered (no client fetching for them) while the tab switching is
client-side. The artifact is the component and its server-side usage.

**3. Find the boundary bugs.** Take a component tree with boundary violations — a hook in a
Server Component, a DB call in a Client Component, a Server Component imported into a client one,
a function passed across the boundary (write them, or have an assistant generate a mixed tree) —
and fix each, labeling the rule it broke. The artifact is the annotated fixes.

## Further Reading

- **Next.js documentation — "Server Components" and "Client Components," and "Composition
  Patterns"** (nextjs.org/docs) — the authoritative guide to the boundary, what each can do, and
  the composition rules (including passing server content as children). The composition-patterns
  page directly addresses the mistakes in this chapter.
- **React documentation — "Server Components"** (react.dev) — React's own explanation of the RSC
  model beneath Next.js, useful for understanding it as a React feature, not just a Next.js one.
- **"Making Sense of React Server Components"** (Josh Comeau, joshwcomeau.com) — a clear,
  patient explanation of the mental model that trips most people up, including what "use client"
  actually means (a boundary, not "runs only on the client").
- **Next.js — "Server Actions and Mutations"** (nextjs.org/docs) — the mechanism for triggering
  server-side work from client islands without hand-written endpoints; background for the mutation
  decision here and for forms in Chapter 06.

# Stage 4 — Frontend Engineering

Build production frontends: fast, typed, maintainable user interfaces.

Stage 3 built Invoicely's backend; this stage builds the frontend that consumes
it — with React, Next.js, and TypeScript. As with every stage, the focus is
engineering judgment, not API tours: how to structure components, where state
lives, when to render on the server versus the client, how to fetch data
correctly, and how to keep a UI fast as it grows.

## Why this stage exists

Frontend is where AI assistants are most fluent and most dangerous. They produce
plausible React instantly — and it is riddled with the field's known foot-guns:
`useEffect` misused to push state around, `any` types that defeat the compiler,
re-render and reconciliation bugs, and client-side data fetching where the server
should have rendered. The judgment this stage teaches is what turns generated
React into a UI that stays fast, typed, and changeable.

## Chapters

| # | Chapter | Status |
|---|---------|--------|
| 01 | [Building UIs with React & TypeScript](01-building-uis-with-react-and-typescript.md) | Done |
| 02 | [Next.js & the App Router](02-nextjs-and-the-app-router.md) | Done |
| 03 | [Server & Client Components](03-server-and-client-components.md) | Done |
| 04 | [Data Fetching & Server State](04-data-fetching-and-server-state.md) | Done |
| 05 | [State Management](05-state-management.md) | Done |
| 06 | Forms & Validation | Planned |
| 07 | Frontend Performance | Planned |
| 08 | Frontend Architecture & Folder Structure | Planned |

These eight chapters cover the ten curriculum topics for this stage. React and
TypeScript are taught together (Ch 01, since typed components are the unit of
everything after); Server and Client Components share one chapter (Ch 03, because
the boundary between them is the single idea); React Query is the core of data
fetching (Ch 04).

## Boundaries with other stages

- **Mobile** (React Native/Expo) is **Stage 5** — this stage is web frontend.
- **Testing** frontend code (component/E2E) is **Stage 8**; it appears here only in passing.
- **Deployment** of the frontend is **Stage 7 (DevOps)**.
- **Design/UX** is out of scope for the curriculum; the focus is frontend *engineering*.

## Running example

The stage builds **Invoicely's** web frontend (Next.js + React + TypeScript)
against the backend from Stage 3 — the invoice list and detail views, the
create/edit forms, the dashboard — so the frontend and backend form one coherent
product.

## Learning outcome

You can build a frontend that is typed end to end, renders the right work on the
right side of the network, fetches data without waterfalls or stale caches,
manages state where it belongs, and stays fast as features accumulate.

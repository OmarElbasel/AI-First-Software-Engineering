# Frontend Performance

## Introduction

Frontend performance is what the user actually feels: how fast the page appears,
how quickly it responds to a tap, whether it jumps around while loading. This
chapter is about making a frontend fast the way users and search engines measure
it — and, just as importantly, about *how to know* what's slow, because the single
most common performance mistake is optimizing the wrong thing.

The chapter has two anchors. The first is **measure before you optimize.**
Performance intuition is unreliable; the real bottleneck is usually not where you'd
guess. Before changing anything, measure with the right tool (Lighthouse, the
Performance panel, the React Profiler, a bundle analyzer) and target the biggest
lever the measurement reveals — which, on most frontends, is the amount of
JavaScript shipped or an unoptimized image, not the micro-optimization an assistant
reaches for. This is Stage 1's premature-optimization lesson (Chapters 04 and 07)
applied to the frontend: performance is a real requirement, so you measure and fix
what's actually slow rather than sprinkling `useMemo` and hoping.

The second anchor is the **Core Web Vitals** — LCP (loading), INP
(responsiveness), CLS (visual stability) — the user-perceived, search-ranked
metrics that define "fast" concretely. Most of the wins come from a short list of
levers: ship less JavaScript (server-render, code-split), optimize images and
fonts (the usual LCP and CLS culprits), and add perceived-performance affordances
(skeletons, streaming, optimistic UI). Get those right, measured against the
Vitals, and the frontend is fast where it counts.

## Why It Matters

Frontend performance is a business and UX property, not a vanity metric: slow pages
lose users, hurt conversion, and rank worse in search (Core Web Vitals are a ranking
signal). And "slow" is specific — it's a large image blocking the first paint, a
megabyte of JavaScript delaying interactivity, a layout that jumps as content loads.
Users feel each of these directly.

The reason this needs a disciplined approach is that performance work is easy to
waste:

- **Optimizing without measuring wastes effort on non-problems.** The instinct to
  memoize components, or micro-optimize a render, usually targets something that
  isn't the bottleneck — while a 2 MB unoptimized image or a huge eager-loaded
  dependency, the actual cause, goes untouched. Without measurement you optimize by
  guess, and the guess is usually wrong.
- **JavaScript is the dominant cost, and it's easy to ship too much.** Every
  kilobyte of JS must be downloaded, parsed, and executed before the page is
  interactive; a heavy dependency imported eagerly or an all-client-rendered app
  ships far more than needed. Shipping less JS — server components (Chapter 03),
  code splitting — is the biggest lever on most frontends.
- **Images and layout shift are the usual visible culprits.** Unoptimized images are
  frequently the largest thing on the page (bad LCP), and unsized images, fonts, and
  late-loading content cause layout shift (bad CLS) that makes the page feel janky
  and mis-taps happen. These are high-impact and routinely skipped.
- **Perceived performance is half the battle.** A page that shows a skeleton and
  streams content *feels* fast even while data loads; one that shows a blank screen
  feels slow at the same actual speed. Optimistic UI and streaming (Chapter 02) buy
  perceived speed cheaply.

The AI dimension: assistants ship too much JavaScript (eager heavy imports,
everything client-rendered, no code splitting), micro-optimize the wrong thing
without measuring (memoize everything while ignoring the giant image), and skip image
and font optimization (the actual LCP/CLS culprits) — because none of it shows up when
the page merely renders on a fast local machine.

## Mental Model

Performance is measured against the Core Web Vitals, and won with a short list of
high-impact levers:

```
   MEASURE FIRST (never optimize blind)
     Lighthouse / PageSpeed ─► overall + Core Web Vitals
     Performance panel ──────► what's slow in a trace
     React Profiler ─────────► component re-render costs
     Bundle analyzer ────────► what's in the JavaScript
     Real-User Monitoring ───► what real users actually experience

   THE METRICS THAT DEFINE "FAST" (Core Web Vitals)
     LCP  Largest Contentful Paint  → loading      (usually: images, JS, server render)
     INP  Interaction to Next Paint → responsiveness (usually: too much JS / main-thread work)
     CLS  Cumulative Layout Shift   → visual stability (usually: unsized images/fonts/late content)

   THE BIGGEST LEVERS (in rough order of typical impact)
     1. Ship LESS JavaScript ─► server-render (Ch 03), code-split, drop heavy deps
     2. Optimize IMAGES ──────► sized, lazy, modern formats (next/image)  → LCP + CLS
     3. Prevent LAYOUT SHIFT ─► reserve space for images/fonts/content     → CLS
     4. PERCEIVED speed ──────► skeletons, streaming (Ch 02), optimistic UI → feels fast
     (micro-optimizations like memoization: only after measuring, only the proven hot spot)
```

Three principles carry the chapter:

**Measure before you optimize, and fix the biggest lever.** Use the right tool to
find the actual bottleneck, then fix *that* — which is usually JavaScript shipped or
images, not a render micro-optimization. Optimizing without measurement is guessing,
and Stage 1's premature-optimization warning applies: the effort is wasted if it
doesn't target a measured problem.

**Ship less JavaScript.** JS is the dominant cost of interactivity, so the largest
wins come from shipping less of it: render on the server (Server Components ship zero
JS, Chapter 03), code-split so a route or a heavy/below-the-fold component loads only
when needed, and avoid heavy dependencies. Before micro-optimizing renders, look at
how much JavaScript the page ships.

**Optimize the user-perceived experience, not just the numbers.** The Core Web Vitals
are the targets because they reflect what users feel — and perceived performance
(skeletons, streaming, optimistic UI) makes a page *feel* fast even before it's fully
loaded. Optimize the metrics that matter to users (LCP/INP/CLS) and the perception
around them, not micro-benchmarks that don't move the experience.

A working definition:

> **Frontend performance is what users feel, measured by the Core Web Vitals
> (LCP/INP/CLS). Win it by measuring first and fixing the biggest lever — usually
> shipping less JavaScript (server-render, code-split) and optimizing images and
> layout stability — plus perceived-performance affordances. Never optimize blind, and
> don't micro-optimize past the real bottleneck.**

## Production Example

**Invoicely's** dashboard is slow — users report a lag before it appears and a jump as
it loads. The disciplined response is to *measure*, not guess. Lighthouse and the
Profiler reveal the actual culprits: a heavy charting library imported eagerly and
bundled into the initial load (huge JS → poor LCP and INP), the whole dashboard
client-rendered (more JS, no server render), customer-logo images served full-size as
plain `<img>` (a large LCP element and layout shift), and the invoice list re-rendering
and unvirtualized.

We will work the measure → target → fix → re-measure loop: code-split the chart so it
loads only when visible (dynamic import), server-render the static dashboard content
(Chapter 03) to ship less JS, use `next/image` for logos (sized, lazy, modern format —
fixing LCP and CLS), reserve space and use `next/font` to stop layout shift, virtualize
the long list, and add a skeleton (Chapter 02) for perceived speed. The point is the
discipline: each fix targets a measured bottleneck, and we re-measure to confirm it
helped — rather than sprinkling memoization and hoping.

## Folder Structure

```
web/src/
├── app/(app)/dashboard/
│   ├── page.tsx              # server-rendered static content (ships no JS for it)
│   ├── loading.tsx           # skeleton — perceived speed while data streams (Ch 02)
│   └── RevenueChart.tsx      # heavy client component — dynamically imported (code-split)
├── components/
│   └── CustomerLogo.tsx      # next/image — sized, lazy, modern format
└── lib/perf/                 # (optional) web-vitals reporting to RUM
```

Why this shape: the heavy chart is isolated so it can be code-split and lazy-loaded;
the static content is server-rendered; images go through an optimized component; and
a `loading.tsx` skeleton covers perceived speed. The structure reflects the levers.

## Implementation

**Code-split a heavy component (`page.tsx` + dynamic import).** The charting library is
large and below the fold, so it's loaded on demand rather than bundled into the initial
JavaScript.

```tsx
import dynamic from "next/dynamic";

// Heavy chart lib: NOT in the initial bundle — loaded only when this renders.
const RevenueChart = dynamic(() => import("./RevenueChart"), {
  loading: () => <ChartSkeleton />,   // perceived speed while the chunk loads
  ssr: false,                          // client-only widget; keep it out of the server render
});

export default async function DashboardPage() {
  const summary = await getDashboardSummary();   // server-fetched (Ch 04), ships no JS
  return (
    <>
      <SummaryCards summary={summary} />          {/* server-rendered, zero JS */}
      <RevenueChart accountId={summary.accountId} /> {/* code-split, lazy */}
    </>
  );
}
```

**Optimize images (`CustomerLogo.tsx`).** `next/image` serves correctly-sized, lazy,
modern-format images and *reserves space* (width/height) so there's no layout shift —
addressing both LCP and CLS. A plain `<img>` does none of this.

```tsx
import Image from "next/image";

export function CustomerLogo({ src, name }: { src: string; name: string }) {
  return (
    <Image
      src={src} alt={`${name} logo`}
      width={48} height={48}        // reserves space → NO layout shift (CLS)
      loading="lazy"                // off-screen images don't block initial load (LCP)
      // next/image also serves modern formats (WebP/AVIF) at the right size automatically
    />
  );
}
```

**Prevent layout shift from fonts (`next/font`).** Fonts loaded naively cause a flash and
a shift; `next/font` self-hosts and reserves metrics so text doesn't jump.

```tsx
import { Inter } from "next/font/google";
const inter = Inter({ subsets: ["latin"], display: "swap" });   // no layout shift, no extra request
// applied on <html className={inter.className}> in the root layout
```

**Virtualize a long list.** Rendering 5,000 invoice rows mounts 5,000 components;
virtualization renders only the visible ones, cutting DOM nodes and render cost.

```tsx
"use client";
import { useVirtualizer } from "@tanstack/react-virtual";
// render only the rows in view (+ a small overscan), not all 5,000 → far less DOM/JS work
```

**Perceived speed with streaming (`loading.tsx`).** The skeleton (Chapter 02) streams
instantly while the server fetches data, so the page feels fast even before its data
arrives.

```tsx
// dashboard/loading.tsx — shown immediately; the page streams in behind it
export default function Loading() {
  return <DashboardSkeleton />;
}
```

**The measure → re-measure discipline.** Every change above targeted a *measured*
culprit, and each is verified by re-running Lighthouse/the Profiler:

```
   BEFORE (measured):  LCP 4.2s · INP 320ms · CLS 0.28 · initial JS 1.8 MB
     culprits: eager chart lib (900 KB), all-client render, full-size <img> logos, unsized fonts
   FIX (each targets a culprit): code-split chart · server-render static · next/image · next/font · virtualize
   AFTER (re-measured): LCP 1.6s · INP 90ms · CLS 0.02 · initial JS 320 KB
```

The through-line is the discipline, not the individual tricks: measure to find that the
bottlenecks were JavaScript and images (not render performance), fix those biggest
levers, and re-measure to confirm. The failure mode — the one an assistant defaults to —
is to skip the measurement, memoize a few components (leaving the 900 KB chart and the
full-size images untouched), and wonder why nothing got faster.

## Engineering Decisions

Five decisions define frontend performance work.

### Measure first, or optimize by intuition?

**Options:** (1) optimize where you suspect the problem is; (2) measure, then optimize the
biggest lever the data shows.

**Trade-offs:** optimizing by intuition is fast to start and usually targets the wrong
thing — performance bottlenecks are rarely where they feel like they are, so the effort is
wasted while the real cause remains. Measuring first costs a little upfront and directs
every subsequent change at a proven problem.

**Recommendation:** always measure before optimizing — Lighthouse/PageSpeed for the
overall picture and Core Web Vitals, the bundle analyzer for JavaScript, the React Profiler
for re-renders, RUM for real users — and optimize the biggest lever the measurement reveals.
This is Stage 1's premature-optimization discipline: no optimization without a measured
target.

### Which lever do you pull first?

**Options:** micro-optimizations (memoization, small tweaks) vs the big levers (JS shipped,
images, layout shift).

**Trade-offs:** micro-optimizations are tempting and usually move the needle little,
because they rarely address the dominant cost. The big levers — shipping less JavaScript,
optimizing images, preventing layout shift — typically account for most of the poor Vitals
and deliver the largest gains, at the cost of more substantial changes (server-rendering,
code-splitting, image pipelines).

**Recommendation:** pull the big levers first, guided by measurement: reduce JavaScript
(server-render, code-split, drop heavy deps), optimize images and fonts, and eliminate
layout shift — before reaching for memoization. Micro-optimize only the specific hot spot the
Profiler proves, and only after the big levers are addressed.

### Server-render or client-render (for performance)?

**Options:** (1) client-render; (2) server-render as much as possible.

**Trade-offs:** client rendering ships the component's JavaScript and renders in the browser
(more JS, later interactivity, a client fetch). Server rendering ships zero JS for that
component and produces fast, indexable output (Chapters 02–03), reserving client JS for
genuine interactivity.

**Recommendation:** server-render by default and keep client components to the interactive
islands (Chapter 03) — this is the single biggest structural lever on JavaScript shipped, and
therefore on LCP and INP. Client-render only what needs interactivity, and code-split heavy
client widgets.

### What's the code-splitting strategy?

**Options:** (1) one big bundle; (2) route-based splitting; (3) route-based plus
component-level splitting for heavy/below-the-fold pieces.

**Trade-offs:** one bundle is simplest and ships everything to every page (slow initial
load). Route-based splitting (largely automatic in Next.js) loads only the current route's
code. Adding component-level splitting (dynamic import) defers heavy or below-the-fold
components (a chart, an editor, a modal) until needed, at the cost of managing the boundaries.

**Recommendation:** rely on route-based splitting and add component-level dynamic imports for
heavy or below-the-fold components (charts, editors, rarely-opened modals). Don't split
trivially small components — the overhead isn't worth it — but keep large dependencies out of
the initial bundle.

### Actual performance, perceived performance, or both?

**Options:** optimize only the real numbers, only perceived speed, or both.

**Trade-offs:** optimizing only actual performance ignores that a technically-fast page can
feel slow (blank screen while loading), and a technically-slower page can feel fast (skeleton
+ streaming). Optimizing only perception papers over genuinely slow pages. Both — fast actual
metrics plus good perceived-speed affordances — gives the best experience.

**Recommendation:** do both: hit the Core Web Vitals *and* add perceived-performance
affordances — skeletons and streaming (Chapter 02) for loading, optimistic UI (Chapter 04)
for mutations. Perceived speed is a cheap, high-impact complement to real optimization, not a
substitute for it.

## Trade-offs

Performance work trades effort, complexity, and sometimes freshness for speed, and the
balance is set by measurement.

**Optimization trades effort for speed — so target it.** Every optimization costs time and
often complexity (code-splitting boundaries, image pipelines, virtualization), and it's only
worth it if it moves a metric users feel. Measuring first is what keeps this trade positive;
optimizing blind spends the effort with no guaranteed return.

**Less JavaScript sometimes trades interactivity locality for speed.** Server-rendering to
ship less JS means interactivity requires the deliberate client-island model (Chapter 03),
which is more structure than "everything is client." For most apps the speed and INP wins are
decisive; for a deeply interactive app the balance shifts. It's a measured trade, not a
dogma.

**Perceived-performance affordances trade a little complexity for a lot of feel.** Skeletons,
streaming, and optimistic UI add code and (for optimistic UI) rollback logic, and they
dramatically improve how fast the app feels. Cheap and high-impact for loading and mutations;
not a reason to ignore genuinely slow actual performance.

**Micro-optimization is usually a bad trade.** Memoizing broadly, or hand-optimizing renders,
adds complexity for typically-small gains and can even hurt — it's worth it only for the
specific hot spot profiling proves. The default is clean code plus the big levers; reach for
micro-optimization last, and only with evidence (Stage 1, Chapter 07).

## Common Mistakes

**Optimizing without measuring.** Guessing at the bottleneck and optimizing the wrong thing
while the real cause (a huge image, a heavy bundle) is untouched. Fix: measure first
(Lighthouse/Profiler/bundle analyzer), fix the biggest lever, re-measure.

**Shipping too much JavaScript.** Eager-importing heavy dependencies, client-rendering
everything, no code splitting — a large initial bundle and slow interactivity. Fix:
server-render, code-split heavy/below-the-fold components, drop heavy deps.

**Unoptimized images.** Full-size images served as plain `<img>` — the largest thing on the
page (bad LCP) and often a layout-shift source. Fix: `next/image` (sized, lazy, modern
format).

**Layout shift.** Unsized images, late-loading fonts, and injected content that pushes the
page around as it loads (bad CLS). Fix: reserve space (width/height, `next/font`, placeholders)
so nothing jumps.

**Rendering huge lists.** Mounting thousands of rows at once, spiking DOM and render cost.
Fix: virtualize long lists so only visible rows render.

**Micro-optimizing prematurely.** Memoizing everything and tweaking renders without
measurement, missing the actual bottleneck. Fix: big levers first, guided by measurement;
micro-optimize only the proven hot spot.

## AI Mistakes

Performance problems don't show on a fast local machine rendering a small dataset, so an
assistant ships the slow version and, when asked to "optimize," reaches for the wrong lever.
Review generated frontends against a measurement, not a local impression.

### Claude Code: shipping too much JavaScript

Asked to build a feature, Claude Code tends to import heavy libraries eagerly at the top of a
module and client-render everything, with no code splitting — because that's the direct way to
use a dependency and the SPA default. The result is a large initial bundle, slow LCP, and
sluggish INP.

**Detect:** top-level imports of heavy libraries (charting, editors, date/utility mega-libs)
used only in one place or below the fold; whole pages client-rendered; no `dynamic()` imports;
a large initial bundle in the analyzer.

**Fix:** require shipping less JS:

> Server-render what you can (Chapter 03) and code-split heavy or below-the-fold components
> with `dynamic()` so they're not in the initial bundle. Don't eagerly import a large library
> used in one place. The goal is less JavaScript shipped on first load.

### GPT: optimizing without measuring / micro-optimizing the wrong thing

GPT-family models, asked to make something faster, reach for memoization and render
micro-optimizations across the board without measuring — often leaving the actual bottleneck (a
2 MB image, a 900 KB dependency) untouched while adding `useMemo`/`memo` noise.

**Detect:** memoization and micro-optimizations added with no profiling; a "performance" change
that doesn't address the largest asset or the biggest bundle contributor; no before/after
measurement.

**Fix:** require measurement-driven optimization:

> Measure first (Lighthouse, the bundle analyzer, the React Profiler) and optimize the biggest
> lever the data shows — usually JavaScript shipped or an image, not memoization. Don't add
> memoization or micro-optimizations without a profile proving they address a real bottleneck,
> and re-measure after.

### Cursor: unoptimized images and layout shift

Adding images and media inline, Cursor uses a plain `<img>` with no dimensions, lazy loading,
or format optimization, and doesn't reserve space for late-loading content — producing large
LCP elements and layout shift (CLS), because the perf attributes aren't visible from the markup.

**Detect:** `<img>` instead of `next/image`; images with no `width`/`height` or `loading`;
fonts loaded without `next/font`; content injected without reserved space; a poor CLS/LCP in
Lighthouse.

**Fix:** require image and stability optimization:

> Use `next/image` with explicit `width`/`height` and lazy loading (serves sized, modern-format
> images) instead of a plain `<img>`, and use `next/font` for fonts. Reserve space for images,
> fonts, and late-loading content so the layout doesn't shift (CLS). These fix the usual LCP and
> CLS culprits.

## Best Practices

**Measure first; optimize the biggest lever; re-measure.** Use Lighthouse/PageSpeed, the bundle
analyzer, the React Profiler, and RUM to find the real bottleneck, fix the largest one (usually
JS or images), and confirm with a re-measure. No optimization without a measured target.

**Ship less JavaScript.** Server-render by default (Chapter 03), code-split heavy and
below-the-fold components, and avoid heavy dependencies. JS shipped is the dominant lever on LCP
and INP.

**Optimize images and prevent layout shift.** `next/image` (sized, lazy, modern format) for
images, `next/font` for fonts, and reserved space for anything that loads late — the usual fixes
for LCP and CLS.

**Add perceived-performance affordances.** Skeletons and streaming (Chapter 02) for loading and
optimistic UI (Chapter 04) for mutations, so the app feels fast alongside being fast.

**Target the Core Web Vitals and monitor real users.** Optimize LCP, INP, and CLS — the
user-perceived, ranked metrics — and watch RUM so you optimize what real users on real devices
experience, not just your dev machine. Document performance budgets/conventions in `CLAUDE.md`.

## Anti-Patterns

**The Blind Optimization.** Optimizing by intuition with no measurement, targeting non-problems
while the real bottleneck remains. The tell: a "performance" PR with no before/after numbers and
no change to the largest asset or bundle.

**The JavaScript Firehose.** Heavy deps imported eagerly and everything client-rendered — a bloated
initial bundle and slow interactivity. The tell: a large initial JS payload in the analyzer and a
poor INP/LCP.

**The Full-Size Image.** Plain `<img>` serving oversized images with no lazy loading or modern
format — the biggest LCP element and a CLS source. The tell: `<img>` tags and images dominating the
Lighthouse LCP/opportunities.

**The Jumping Page.** Unsized images/fonts/late content shifting the layout as it loads. The tell: a
high CLS and visible content jumps (and mis-taps) on load.

**The Memoization Blanket.** Broad memoization and micro-optimization with no profiling, missing the
actual bottleneck. The tell: `useMemo`/`memo` everywhere and no measured impact (Chapter 01's
premature memoization, at the app scale).

## Decision Tree

"The frontend feels slow — what do I do?"

```
MEASURE FIRST (do not guess):
  Lighthouse/PageSpeed → Core Web Vitals + opportunities
  Bundle analyzer → what's in the JS   |  React Profiler → re-render costs  |  RUM → real users
        │
   What's the biggest lever the data shows?
        │
   ├─ Large initial JavaScript? ──► server-render more (Ch 03); code-split heavy/below-fold
   │                                 (dynamic import); drop/replace heavy deps.
   ├─ Large / slow images (bad LCP)? ──► next/image (sized, lazy, modern format).
   ├─ Layout shifting (bad CLS)? ──► reserve space; next/font; sized media/placeholders.
   ├─ Sluggish interaction (bad INP)? ──► less main-thread JS; virtualize long lists;
   │                                       break up long tasks.
   └─ A specific component re-rendering hot (Profiler)? ──► memoize THAT (only, with evidence).
        │
   Add PERCEIVED speed: skeletons + streaming (Ch 02), optimistic UI (Ch 04).
        │
   RE-MEASURE to confirm the fix helped. (No optimization is done until re-measured.)
```

## Checklist

### Implementation Checklist

- [ ] A measurement (Lighthouse/bundle analyzer/Profiler) identified the bottleneck before any optimization.
- [ ] The biggest lever was addressed first (usually JS shipped or images), not micro-optimizations.
- [ ] Heavy and below-the-fold components are code-split (`dynamic()`); static content is server-rendered.
- [ ] Images use `next/image` (sized, lazy, modern format); fonts use `next/font`.
- [ ] Layout shift is prevented (reserved space for images/fonts/late content); long lists are virtualized.
- [ ] Perceived-performance affordances (skeletons/streaming, optimistic UI) are in place, and the fix was re-measured.

### Architecture Checklist

- [ ] Server-first rendering is the default; client JS is confined to interactive islands (Chapter 03).
- [ ] A performance budget (initial JS size, target Vitals) is defined and tracked.
- [ ] Core Web Vitals (LCP/INP/CLS) are monitored, including real-user monitoring.
- [ ] Code-splitting boundaries are deliberate (heavy/below-fold split; trivial components not).
- [ ] Performance conventions/budgets are documented in `CLAUDE.md`.

### Code Review Checklist

- [ ] No heavy dependency imported eagerly where it could be code-split (watch AI diffs).
- [ ] No plain `<img>` where `next/image` belongs; images are sized and lazy.
- [ ] No layout-shift source (unsized media/fonts/late content) introduced.
- [ ] No memoization/micro-optimization added without a profile justifying it.
- [ ] A performance-sensitive change includes before/after measurements.

*(A Deployment Checklist for the frontend — CDN, caching headers, build output — is Stage 7;
rendering strategy from Chapter 02 interacts with it.)*

## Exercises

**1. Measure, then fix the biggest lever.** Run Lighthouse on a slow page (Invoicely's dashboard,
or your own) and record LCP/INP/CLS and the top opportunities. Fix the single biggest lever the
report shows (usually JS or an image), then re-measure. The artifact is the before/after numbers
and the one change that moved them most — proving measurement beats intuition.

**2. Code-split a heavy component.** Take a page that eagerly imports a heavy library (a chart, an
editor) and move it behind a `dynamic()` import with a loading fallback. Measure the initial bundle
size before and after. The artifact is the before/after bundle size and a note on the LCP/INP
impact.

**3. Fix images and layout shift.** Take a page using plain `<img>` and naively-loaded fonts and
convert to `next/image` and `next/font`, reserving space so nothing jumps. Measure CLS and LCP
before and after. The artifact is the before/after Vitals and the specific shifts you eliminated.

## Further Reading

- **web.dev — Core Web Vitals, and the LCP/INP/CLS optimization guides** (web.dev) — the
  authoritative, current guidance on the metrics that define "fast" and how to improve each. Start
  here to know what you're optimizing for.
- **Next.js documentation — Optimizing (Images, Fonts, Scripts, Lazy Loading, Bundle Analyzer)**
  (nextjs.org/docs) — the framework's built-in performance tools (`next/image`, `next/font`,
  `dynamic`) that do most of the heavy lifting in this chapter.
- **Chrome DevTools — Performance panel and Lighthouse docs; the React Profiler** (developer.chrome.com;
  react.dev) — how to actually measure: find slow tasks in a trace, audit a page, and profile
  component re-renders. The tools behind "measure first."
- **"The Cost of JavaScript"** (Addy Osmani) — the definitive explanation of why shipping less
  JavaScript is the dominant frontend performance lever, and how download/parse/execute costs hit
  real devices. The case for the biggest lever in this chapter.

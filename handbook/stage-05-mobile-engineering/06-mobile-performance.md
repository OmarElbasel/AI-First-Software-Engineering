# Mobile Performance

## Introduction

Performance is more visceral on mobile than anywhere else. Users feel a dropped
frame as a stutter under their thumb, feel a slow launch as an app that's "always
loading," and feel a memory hog as a phone that gets hot and drains. Unlike the web,
where a beefy laptop hides a lot of waste, a mobile app runs on a mid-range Android
phone from three years ago with a cold battery — and that device, not your flagship
test phone, is where performance is decided. This chapter is about keeping a React
Native app smooth: hitting 60fps, launching fast, rendering long lists without jank,
and staying within a memory and battery budget the device actually enforces.

The single most important idea: **React Native has two threads that matter — the JS
thread and the native UI thread — and jank is almost always one of them being
blocked.** Your JavaScript (components, state, business logic) runs on the JS thread;
the native UI and animations run on the UI thread; they communicate across a bridge
(now the JSI). When the JS thread is busy — re-rendering a huge tree, doing heavy
work in a handler — it can't respond, and the UI stutters. When too much data crosses
the bridge — an unvirtualized list, chatty native calls — frames drop. Understanding
which thread is blocked, and moving work off it (or off the bridge), is the core skill
of mobile performance.

The judgment this chapter teaches is *where the wins actually are*, because they're
concentrated and not where beginners look. **Lists** are the single biggest source of
mobile jank (virtualization, `memo`, cheap rows). **Launch time** is a first
impression you optimize deliberately (bundle, splash, deferred work). **Re-renders**
matter more here than on the web because the device is slower. And **measurement on a
real low-end device** is non-negotiable — optimizing by guessing on a flagship
simulator wastes effort on non-problems and misses the real ones. As always: measure
first, optimize the proven bottleneck, and don't pay complexity for speed you can't
perceive.

## Why It Matters

Mobile performance is judged harder and on worse hardware than web performance, and
the failures are the ones users notice most:

- **Jank is felt, not measured.** A dropped frame during a scroll or a gesture is a
  physical stutter under the user's finger. The 60fps budget (≈16ms per frame) is
  tight, and blowing it — with a heavy re-render or too much bridge traffic — reads
  instantly as a cheap, broken app.
- **The low-end device is the real target.** Your app doesn't run on your test iPhone;
  it runs on a three-year-old mid-range Android with 4GB of RAM and thermal
  throttling. Performance that's "fine" on a flagship can be unusable there — and
  that's a large share of real users.
- **Launch time is a first impression.** A slow cold start (heavy JS bundle, blocking
  work before the first screen) makes the app feel sluggish before the user does
  anything. Startup is one of the most-noticed and most-optimizable metrics.
- **Lists are where jank lives.** Long lists rendered naively (`.map()`, or `FlatList`
  with expensive rows and no memoization) drop frames on scroll, spike memory, and are
  the most common performance bug in React Native apps by a wide margin.
- **Memory and battery are enforced.** The OS kills memory-hungry apps (Chapter 01),
  and a phone that heats up and drains gets uninstalled. Unlike a desktop, the device
  pushes back — leaks and wasteful work have visible consequences.
- **Guessing wastes effort.** Without profiling on a real device, you optimize the
  wrong thing — micro-tuning a function that isn't the bottleneck while the actual
  jank (an unvirtualized list) sits untouched. Measurement is what makes optimization
  pay off.

Done right — 60fps scrolls, fast launch, virtualized and memoized lists, controlled
memory, and decisions driven by real-device profiling — the app feels native and
premium even on modest hardware. Done wrong, it stutters, launches slowly, janks on
every list, heats the phone, and gets uninstalled — often after passing every test on
the developer's flagship.

The AI dimension: assistants carry web performance instincts (where hardware hides
waste) and skip the mobile-specific wins — they `.map()` lists instead of
virtualizing, ignore memoization on list rows, do heavy work on the JS thread, and
never mention the low-end device or measurement. Their code is smooth in the demo and
janky in the field.

## Mental Model

Two threads, a frame budget, and the concentrated places wins actually live:

```
   TWO THREADS (jank = one of them blocked)
     JS THREAD ──────────── your React: components, state, handlers, business logic
        │  bridge / JSI (keep traffic thin)
     UI THREAD ──────────── native views, layout, animations, gestures
     16ms per frame @ 60fps. Blow the budget on either thread → dropped frame → stutter.

   WHERE THE WINS ACTUALLY ARE (concentrated, not uniform)
     1. LISTS ───────── virtualize (FlatList/FlashList) · memo rows · cheap renderItem
                        the #1 source of RN jank by far
     2. RE-RENDERS ──── memo / useMemo / useCallback · stable keys · avoid prop churn
                        (matters MORE than web — the device is slower)
     3. LAUNCH ──────── trim JS bundle · defer non-critical work · splash while loading
     4. ANIMATIONS ──── run on the UI THREAD (Reanimated), not the JS thread
     5. MEMORY ──────── release images/listeners · don't retain unbounded data

   THE RULE (same as web, higher stakes)
     MEASURE on a real LOW-END device ──► optimize the PROVEN bottleneck ──► verify.
     never optimize by guessing on a flagship simulator.
```

Four principles carry the chapter:

**Know which thread is blocked.** Jank is the JS thread busy (heavy render/handler) or
the bridge overloaded (too much data crossing). Diagnose *which* before optimizing:
move heavy work off the JS thread, run animations on the UI thread (Reanimated), and
keep bridge traffic thin.

**Lists are the main event.** Virtualize every growable list (`FlatList`/`FlashList`),
memoize the row component, keep `renderItem` cheap, and give stable keys. This one area
is where most mobile jank is won or lost — start every list right.

**Optimize launch and re-renders deliberately.** Trim the JS bundle and defer
non-critical startup work so the first screen appears fast; use `memo`/`useMemo`/
`useCallback` and stable references to avoid the re-render storms that cost more on a
slow device than on a laptop.

**Measure on a real low-end device, then optimize the bottleneck.** The device is the
target and the truth. Profile on modest hardware, fix the proven bottleneck, and verify
the win — don't micro-optimize by guessing on a flagship. Same discipline as web
performance (Stage 4, Chapter 07), higher stakes.

A working definition:

> **Mobile performance is keeping both the JS thread and the native UI thread inside
> the 16ms frame budget on a real low-end device: virtualize and memoize lists (the #1
> jank source), avoid re-render storms, optimize launch by trimming the bundle and
> deferring work, run animations on the UI thread, and control memory — all driven by
> profiling the proven bottleneck on modest hardware, never by guessing on a flagship.**

## Production Example

**Invoicely mobile's** performance-critical surface is the invoice list. A power user
has hundreds of invoices; the list must scroll at 60fps on a mid-range Android, launch
quickly to that list, and not spike memory as the user scrolls through months of
history. Each row shows a client name, amount, status badge, and date — cheap
individually, ruinous if the list renders all of them at once or re-renders every row
on every state change.

The performance work is concentrated exactly where the mental model predicts. The list
uses `FlashList` (virtualized, tuned for large lists) rather than `.map()` or a naive
`FlatList`; the row is a memoized component so unrelated state changes don't re-render
every visible row; `renderItem` and `keyExtractor` are stable references so the list
doesn't thrash. Launch defers non-critical work (analytics init, prefetching) until
after the first screen paints, so the list appears fast. A status-change animation runs
on the UI thread via Reanimated so it stays smooth even while the JS thread is fetching.
And every decision is validated by profiling on a real low-end Android — not the
developer's iPhone — because that device is where the app actually has to be smooth.

In this chapter we build and tune that: a virtualized, memoized list; launch
optimization; UI-thread animation; and a measurement workflow. We contrast it with the
assistant-default version (`.map()` list, unmemoized rows, heavy JS-thread work,
flagship-only "testing") that demos smooth and janks on real hardware.

## Folder Structure

```
mobile/src/
├── features/invoices/
│   ├── InvoiceList.tsx        # FlashList (virtualized) — the perf-critical surface
│   ├── InvoiceRow.tsx         # React.memo'd row; cheap render; stable props
│   └── useInvoiceList.ts      # stable renderItem/keyExtractor; data shaping off the render path
├── lib/
│   ├── startup.ts             # defer non-critical launch work until after first paint
│   └── perf.ts                # dev-only render/interaction measurement helpers
└── components/
    └── AnimatedStatusBadge.tsx # animation on the UI thread (Reanimated), not the JS thread
```

Why this shape: the structure puts the performance-critical code where it's found and
reviewed. The list, its memoized row, and the stable-callback hook are colocated because
they must be tuned together — a virtualized list with an unmemoized row is still janky.
`startup.ts` isolates launch-time sequencing (what runs before vs after first paint) so
startup cost is deliberate, not accidental. Animations that must be smooth live in
components built on the UI-thread animation library. The folders encode the "wins are
concentrated" claim: performance lives in a few files, tuned intentionally, not sprinkled
everywhere.

## Implementation

**A virtualized, memoized list (`InvoiceList.tsx` + `InvoiceRow.tsx`).** The single most
important performance code in the app: `FlashList` virtualizes (renders only visible
rows), the row is memoized (so unrelated re-renders don't touch it), and the callbacks are
stable (so the list doesn't thrash).

```tsx
// InvoiceRow.tsx — memoized so unrelated state changes don't re-render every visible row
import { memo } from "react";
import { Pressable, Text, View, StyleSheet } from "react-native";

export const InvoiceRow = memo(function InvoiceRow(
  { invoice, onPress }: { invoice: Invoice; onPress: (id: number) => void },
) {
  return (
    <Pressable style={styles.row} onPress={() => onPress(invoice.id)}>
      <Text style={styles.client}>{invoice.clientName}</Text>
      <Text style={styles.amount}>${invoice.amount.toFixed(2)}</Text>
    </Pressable>
  );
});
```

```tsx
// InvoiceList.tsx — virtualized; stable renderItem/keyExtractor avoid re-creating them each render
import { FlashList } from "@shopify/flash-list";
import { useCallback } from "react";
import { InvoiceRow } from "./InvoiceRow";

export function InvoiceList({ invoices }: { invoices: Invoice[] }) {
  const onPress = useCallback((id: number) => router.push(`/invoices/${id}`), []);
  const renderItem = useCallback(
    ({ item }: { item: Invoice }) => <InvoiceRow invoice={item} onPress={onPress} />, [onPress]);

  return (
    <FlashList
      data={invoices}
      renderItem={renderItem}                 // stable reference — no re-create per render
      keyExtractor={(i) => String(i.id)}      // stable keys — no reconciliation thrash
      estimatedItemSize={64}                  // lets FlashList size the virtualization window
    />
  );
}
```

**Launch optimization (`startup.ts`).** The first screen should paint before
non-critical work runs. Defer analytics init, prefetching, and other startup cost until
after the first interaction/paint so launch feels fast.

```ts
import { InteractionManager } from "react-native";

export function initApp() {
  // Critical path only before first paint. Everything else waits.
  InteractionManager.runAfterInteractions(() => {
    initAnalytics();          // non-critical — deferred so it doesn't delay the first screen
    prefetchLikelyScreens();  // warm caches AFTER the user sees content
  });
}
```

**UI-thread animation (`AnimatedStatusBadge.tsx`).** Animations driven by Reanimated run
on the **UI thread**, so they stay smooth even when the JS thread is busy (fetching,
re-rendering). A JS-thread animation stutters exactly when the app is doing work.

```tsx
import Animated, { useAnimatedStyle, withTiming, useSharedValue } from "react-native-reanimated";
import { useEffect } from "react";

export function AnimatedStatusBadge({ paid }: { paid: boolean }) {
  const opacity = useSharedValue(0);
  useEffect(() => { opacity.value = withTiming(paid ? 1 : 0); }, [paid]);
  // This interpolation runs on the UI thread — smooth even while the JS thread works.
  const style = useAnimatedStyle(() => ({ opacity: opacity.value }));
  return <Animated.View style={style} />;
}
```

**The anti-patterns — the assistant defaults.**

```tsx
// ANTI-PATTERN: web-habit list + JS-thread work + flagship-only "testing"
function InvoiceListBad({ invoices }) {
  return (
    <ScrollView>
      {invoices.map((invoice) => (            // 1) NOT virtualized — renders ALL rows, spikes memory
        <InvoiceRowBad                         // 2) not memoized — re-renders every row on any state change
          invoice={invoice}
          onPress={() => router.push(`/invoices/${invoice.id}`)}  // 3) new fn per row per render → churn
        />
      ))}
    </ScrollView>
  );
}
// 4) heavy sorting/formatting done inline on the JS thread during render
// 5) only ever run on the developer's flagship simulator → jank invisible until users hit it
```

The difference is the whole chapter: the good version virtualizes, memoizes, keeps
callbacks stable, defers launch work, animates on the UI thread, and is profiled on a
low-end device. The bad version renders every row, re-renders them all on any change,
allocates new closures per row, blocks the JS thread, and is "tested" only where the
hardware hides the cost — smooth in the demo, janky for real users.

## Engineering Decisions

Five decisions define mobile performance.

### How do you render a list?

**Options:** (1) `.map()` in a `ScrollView`; (2) `FlatList` (built-in virtualization);
(3) `FlashList` (higher-performance virtualization).

**Trade-offs:** `.map()` renders every row up front — fine for a handful, catastrophic
for hundreds (memory spike, long frames). `FlatList` virtualizes and is the safe default
but can struggle with very large or complex lists. `FlashList` improves throughput and
memory for large/heavy lists at the cost of a dependency and providing `estimatedItemSize`.

**Recommendation:** never `.map()` a growable list. `FlatList` by default; `FlashList` for
large or heavy lists where you measure `FlatList` dropping frames. Pair either with a
memoized row and stable callbacks — virtualization alone isn't enough if each row is
expensive or re-renders constantly.

### When do you memoize (rows, components, callbacks)?

**Options:** (1) never (rely on React); (2) memoize proven-hot paths (list rows, stable
callbacks); (3) memoize everything preemptively.

**Trade-offs:** never memoizing lets re-render storms hit — costly on a slow device,
especially for list rows re-rendering on unrelated state. Memoizing everything adds
complexity and its own overhead (comparisons, dependency arrays) and can hide bugs.
Targeted memoization (list rows with `memo`, callbacks with `useCallback`, derived data
with `useMemo`) fixes the real hot paths.

**Recommendation:** memoize the proven hot paths — list rows, `renderItem`/`keyExtractor`,
expensive derived values — not everything. On mobile, list-row memoization is usually worth
it by default because rows re-render often and the device is slow. Measure before
memoizing broadly; don't cargo-cult `memo` onto every component.

### What runs before the first screen paints?

**Options:** (1) everything at startup; (2) only the critical path, deferring the rest; (3)
lazy-load screens/features on demand.

**Trade-offs:** doing everything at startup (analytics, prefetch, heavy init) delays the
first paint and makes launch feel slow. Deferring non-critical work (`runAfterInteractions`)
gets content on screen fast at the cost of sequencing what's critical vs deferrable.
Lazy-loading screens cuts the initial bundle further at the cost of a small delay when a
screen is first opened.

**Recommendation:** run only the critical path before first paint; defer analytics,
prefetching, and non-essential init until after; lazy-load heavy or rarely-used screens.
Launch is a first impression — optimize it deliberately rather than letting startup cost
accrete.

### Where do animations run — JS thread or UI thread?

**Options:** (1) JS-thread animations (`Animated` without native driver, or state-driven);
(2) UI-thread animations (Reanimated / native driver).

**Trade-offs:** JS-thread animations stutter exactly when the JS thread is busy (fetching,
re-rendering) — the worst timing. UI-thread animations (Reanimated, or `useNativeDriver`)
run independently of the JS thread and stay smooth under load, at the cost of a library and
its worklet model.

**Recommendation:** run animations on the UI thread — Reanimated (or the native driver for
simple `Animated` cases) — so they stay smooth while the JS thread works. Never drive
frequent animations from React state on the JS thread; that's guaranteed jank under load.

### How do you decide what to optimize?

**Options:** (1) optimize by intuition; (2) profile on a flagship; (3) profile on a real
low-end device, then optimize the proven bottleneck.

**Trade-offs:** intuition optimizes non-problems and misses real ones. Profiling on a
flagship hides the jank that only appears on modest hardware — the device most users have.
Profiling on a real low-end device surfaces the actual bottlenecks at the cost of owning/
testing on that hardware.

**Recommendation:** profile on a real low-end device (the target), find the proven
bottleneck (usually a list or a re-render storm), optimize it, and verify the win. Same
measure-first discipline as Stage 4, Chapter 07 — the low-end device is what makes the
measurement honest. Don't optimize what you haven't measured, and don't measure only where
the hardware lies.

## Trade-offs

Mobile performance trades targeted effort for a native feel on hardware that punishes
waste — and over-optimizing trades clarity for speed nobody feels.

**Virtualization + memoization trade a little setup for the biggest win.** A virtualized,
memoized list is slightly more code than `.map()`, and it's the difference between 60fps and
a stutter on every scroll for any real dataset. This is the highest-return performance work
in the app; the setup cost is trivial against it.

**Launch optimization trades sequencing effort for a fast first impression.** Deferring
non-critical startup work means deciding what's critical and wiring `runAfterInteractions`/
lazy loading, and it buys a launch that feels instant. The sequencing discipline pays off on
every cold start.

**UI-thread animation trades a library for smoothness under load.** Reanimated adds a
dependency and a worklet mental model, and it keeps animations smooth precisely when the JS
thread is busy — the moments a JS-thread animation would stutter. For anything the user
watches, the trade is worth it.

**Optimization has a complexity cost — pay it only for measured wins.** Every `memo`, deferral,
and worklet adds indirection. Applied to a proven bottleneck it's clearly worth it; applied
preemptively everywhere it's complexity for imperceptible gains and a source of bugs (stale
memo deps). Measurement is what keeps the trade positive.

## Common Mistakes

**`.map()` for long lists.** Rendering every row, spiking memory and dropping frames. Fix:
`FlatList`/`FlashList` virtualization for anything growable.

**Unmemoized list rows.** Every row re-rendering on unrelated state changes. Fix: `React.memo`
the row and stable `renderItem`/`keyExtractor`/callbacks.

**Heavy work on the JS thread.** Sorting/formatting/parsing during render or in handlers,
blocking frames. Fix: move it off the render path, memoize derived data, or offload it.

**JS-thread animations.** Animations driven by React state that stutter under load. Fix:
Reanimated / the native driver (UI thread).

**Slow launch from eager startup work.** Analytics, prefetch, and heavy init blocking the first
paint. Fix: defer non-critical work; lazy-load heavy screens.

**Testing only on a flagship.** Shipping jank that only appears on the low-end devices most
users have. Fix: profile on a real low-end device; optimize the measured bottleneck.

## AI Mistakes

Assistants bring web performance instincts, where fast hardware hides waste, and skip the
mobile-specific wins entirely. Review generated UI code for the concentrated bottlenecks —
lists, re-renders, thread usage — and for any acknowledgment of the low-end device.

### Claude Code: `.map()` lists and unmemoized rows

Asked to render a list, Claude Code often uses `.map()` (web-idiomatic) or a `FlatList` with an
inline, unmemoized row and a fresh `onPress` closure per item — none of which the demo dataset
exposes. On a real list it drops frames on scroll and spikes memory.

**Detect:** `.map()` producing rows (especially in a `ScrollView`); list rows not wrapped in
`memo`; inline arrow closures created per row; `renderItem`/`keyExtractor` re-created each render;
no `keyExtractor` at all.

**Fix:** require virtualization + memoization together:

> Render growable lists with `FlatList`/`FlashList`, memoize the row component (`React.memo`), and
> make `renderItem`, `keyExtractor`, and row callbacks stable (`useCallback`) so rows don't
> re-render or re-create on every parent render. Virtualization alone isn't enough if each row is
> expensive.

### GPT: heavy work on the JS thread and JS-thread animations

GPT-family models put sorting, formatting, or filtering inline in render, and drive animations
from React state — both of which block or stutter the JS thread. It's smooth in a small demo and
janks under real data or concurrent work.

**Detect:** expensive computation (sort/format/parse) in the render body or a hot handler with no
memoization; animations driven by `useState`/`setInterval` rather than Reanimated/native driver;
frame drops when the app is also fetching or rendering.

**Fix:** move work off the JS thread's hot path:

> Don't do heavy computation during render — memoize derived data (`useMemo`) or compute it off the
> render path. Run animations on the UI thread with Reanimated (or the native driver), never from
> React state, so they stay smooth while the JS thread is busy.

### Cursor: no measurement and flagship-only assumptions

Editing at the cursor, Cursor optimizes (or doesn't) by intuition and implicitly targets the
developer's fast simulator — no profiling, no low-end-device consideration — so it both misses real
bottlenecks and "confirms" performance where the hardware hides problems.

**Detect:** performance changes with no profiling evidence; assumptions that a screen is "fast
enough" without measurement; no consideration of low-end hardware; micro-optimizations on code
that isn't the bottleneck while a `.map()` list sits nearby.

**Fix:** require measurement on the real target:

> Base performance work on profiling a real low-end device, not intuition or a flagship simulator.
> Identify the proven bottleneck (usually a list or a re-render storm), optimize that, and verify the
> win. Don't micro-optimize code you haven't measured, and don't declare something fast based on
> flagship hardware.

## Best Practices

**Virtualize and memoize every real list.** `FlatList`/`FlashList` with a `React.memo` row and
stable `renderItem`/`keyExtractor`/callbacks. This is the highest-return performance work — do it
by default for any growable list.

**Keep the JS thread free and animate on the UI thread.** Move heavy computation off the render
path (memoize or precompute), and run animations with Reanimated/native driver so they stay smooth
under load. Diagnose which thread is blocked before optimizing.

**Optimize launch deliberately.** Run only the critical path before first paint; defer analytics,
prefetching, and non-essential init; lazy-load heavy screens. Treat startup as a first impression.

**Control memory.** Release images and listeners, avoid retaining unbounded data, and virtualize so
off-screen rows aren't held. The OS enforces memory; don't give it a reason to kill you.

**Measure on a real low-end device, then optimize the proven bottleneck.** Profile the target
hardware, fix what the profile shows, verify the win, and don't pay complexity for imperceptible
gains. Document the perf conventions (virtualized lists, UI-thread animation, low-end target) in
the mobile `CLAUDE.md`.

## Anti-Patterns

**The Unvirtualized List.** `.map()` (or a `ScrollView` of rows) rendering everything — memory
spike and scroll jank. The tell: rows built with `.map()` for a growable dataset.

**The Re-rendering Row.** Unmemoized rows and fresh closures re-rendering the whole visible list on
any state change. The tell: no `memo` on the row, inline `onPress` per item.

**The Blocked JS Thread.** Heavy computation in render/handlers, or state-driven animations,
stuttering under load. The tell: sorting/formatting in the render body; animations from `useState`.

**The Slow Launch.** Analytics, prefetch, and heavy init running before the first paint. The tell: a
startup path that does everything eagerly.

**The Flagship-Only Ship.** Performance judged only on high-end hardware, shipping jank to the
low-end majority. The tell: no low-end-device profiling anywhere in the process.

## Decision Tree

"Something feels slow (or I'm building a perf-sensitive surface) — what do I do?"

```
FIRST: profile on a REAL LOW-END device. Which thread is blocked? What's the actual bottleneck?
  (Don't optimize by guessing, and don't trust a flagship simulator.)

Is it a LIST?  (it usually is)
├── .map()/ScrollView ──► switch to FlatList/FlashList (virtualize).
├── virtualized but janky ──► memoize the row (React.memo); stable renderItem/keyExtractor/callbacks;
│                              make each row cheap.
└── still heavy ──► FlashList with estimatedItemSize; simplify row content.

Is the JS thread blocked?
├── heavy compute in render/handler ──► memoize (useMemo) or move off the render path.
└── animation stutters under load ──► run it on the UI thread (Reanimated / native driver).

Is LAUNCH slow?
└──► run only the critical path before first paint; defer analytics/prefetch (runAfterInteractions);
     lazy-load heavy screens.

Memory growing / phone hot?
└──► release images/listeners; virtualize; don't retain unbounded data.

THEN: verify the win on the low-end device. Stop when it's imperceptible — don't over-optimize.
```

## Checklist

### Implementation Checklist

- [ ] Every growable list is virtualized (`FlatList`/`FlashList`) with a memoized row and stable callbacks.
- [ ] No heavy computation runs during render; derived data is memoized or precomputed.
- [ ] Animations run on the UI thread (Reanimated / native driver), not from React state.
- [ ] Launch runs only the critical path before first paint; non-critical work is deferred.
- [ ] Images and listeners are released; no unbounded data is retained.
- [ ] Performance changes are backed by profiling on a real low-end device.

### Architecture Checklist

- [ ] Performance-critical surfaces (lists, animations, startup) are isolated and tuned intentionally.
- [ ] Startup sequencing (critical vs deferred) is explicit, not accidental.
- [ ] Optimization is applied to measured bottlenecks, not preemptively everywhere.
- [ ] The low-end device is treated as the performance target.
- [ ] Performance conventions are documented in the mobile `CLAUDE.md`.

### Code Review Checklist

- [ ] No `.map()`/`ScrollView` for growable lists (watch AI diffs).
- [ ] No unmemoized list rows or per-row closure churn.
- [ ] No heavy work on the JS thread's render path; no JS-thread animations.
- [ ] No eager, launch-blocking startup work.
- [ ] No performance claim without measurement on a real (ideally low-end) device.

*(A Deployment Checklist is not applicable to this chapter; production performance monitoring ties into observability — Stage 3, Chapter 08 — and shipping — Chapter 07.)*

## Exercises

**1. Fix a janky list.** Build the invoice list with `.map()` in a `ScrollView` and 500 items,
profile the scroll on a low-end device (or a throttled simulator), then convert to `FlashList` with a
memoized row and stable callbacks. The artifact is the before/after frame-rate measurement.

**2. Speed up launch.** Measure cold-start time with analytics/prefetch running eagerly at startup,
then defer them with `runAfterInteractions` and lazy-load a heavy screen. The artifact is the launch-
time difference and a note on what you classified as critical vs deferrable.

**3. Move an animation to the UI thread.** Build a status-change animation driven by React state,
observe it stutter while the app fetches, then reimplement it with Reanimated (UI thread) and confirm
it stays smooth under load. The artifact is both versions and the observed difference.

## Further Reading

- **React Native — "Performance," "Optimizing FlatList Configuration," and "Profiling"**
  (reactnative.dev) — the authoritative guide to the two-thread model, list performance, and
  profiling tools; the foundation of this chapter.
- **Shopify — FlashList documentation** (shopify.github.io/flash-list) — why and how it outperforms
  `FlatList` for large lists, and how to configure it (`estimatedItemSize`, recycling).
- **React Native Reanimated documentation** (docs.swmansion.com/react-native-reanimated) — running
  animations and gestures on the UI thread with worklets; the basis for smooth-under-load animation.
- **Stage 4, Chapter 07 — Frontend Performance** — the web counterpart; the measure-first discipline
  and re-render reasoning carry over directly, with mobile raising the stakes and adding the two-thread
  and low-end-device dimensions.
</content>

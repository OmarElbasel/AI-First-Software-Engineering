# React Native & Expo Foundations

## Introduction

A mobile app is not a website in a smaller window. It runs on a device you don't
control, with a battery, an operating system that can kill your process at any
time, an app-store gatekeeper between you and your users, and a native UI toolkit
that has nothing to do with the DOM. **React Native** lets you write that app in
React and TypeScript — the same mental model as Stage 4 — while rendering to real
native views (`UIView` on iOS, `android.view.View` on Android) instead of HTML.
**Expo** is the toolchain and runtime that makes React Native usable in
production: it gives you native modules (camera, notifications, secure storage)
without touching Xcode or Android Studio, a build service, and an over-the-air
update system. This chapter is the foundation the rest of Stage 5 builds on —
what React Native actually is, what Expo adds, and how to reason about a codebase
that runs on hardware.

The single most important idea: **React Native is React with a different renderer,
not a different framework.** Your components, hooks, state, and TypeScript carry
over unchanged. What changes is everything *below* the component — there is no
DOM, no CSS, no `<div>`; there is a **bridge** (now the JSI) to native code, a
layout engine (Flexbox only), and platform APIs that differ between iOS and
Android. The engineering judgment this chapter teaches is knowing which of your
web instincts transfer (React itself, composition, typing) and which will produce
bugs on a device (assuming CSS, assuming the DOM, assuming a page that never gets
killed).

The second idea: **prefer Expo, and prefer managed native access.** The React
Native ecosystem has a "bare" workflow where you manage native iOS/Android
projects yourself, and a managed Expo workflow where you don't. For the vast
majority of production apps — including everything in this stage — Expo with
**config plugins** and **EAS** (Expo Application Services) is the right default:
you get native capability without native-project maintenance, and you drop to
custom native code only when a specific requirement forces it.

## Why It Matters

Mobile is a fundamentally more hostile runtime than the web, and treating it like
the web produces apps that pass a demo and fail in the field:

- **The OS owns your process.** iOS and Android suspend and kill background apps
  to reclaim memory. A web page assumes it lives until the tab closes; a mobile
  app must assume it can be frozen mid-task and resumed later, or killed and
  cold-started. State that lived only in memory is gone.
- **There is no DOM and no CSS.** Layout is Flexbox-only, styling is a JavaScript
  object subset (no cascade, no inheritance, no media queries in the CSS sense),
  and there is no `<div>`/`<span>`/`<p>` — only `<View>`, `<Text>`, `<Image>`,
  `<ScrollView>`, `<FlatList>`. Every string **must** be inside a `<Text>`; a raw
  string in a `<View>` crashes.
- **Two platforms, one codebase.** iOS and Android differ in navigation gestures,
  safe areas (notches, home indicators), permissions, back-button behavior, and
  dozens of native APIs. "Works on my iPhone simulator" is not "works."
- **A native bridge with a cost.** JavaScript runs in a separate engine (Hermes)
  from the native UI thread. Large or chatty data crossing that boundary — a
  giant list rendered naively, heavy work on the JS thread — drops frames the
  user feels as jank.
- **A gatekeeper between you and users.** You cannot `git push` to production. App
  Store and Play Store review stand between a build and your users — which is
  exactly why OTA updates (Chapter 07) matter so much.

Get the foundation right — React Native as a renderer, Expo for native access,
platform differences respected, the process lifecycle assumed — and you ship one
TypeScript codebase to both stores with native performance. Get it wrong and you
ship web habits to a runtime that punishes them: crashes from raw strings, layout
that only works on one device, lost state after a background kill, and jank from
ignoring the bridge.

The AI dimension: assistants are fluent in web React and carry those habits
straight into React Native. They reach for HTML elements (`<div>`, `<p>`) and CSS
that don't exist, they use browser APIs (`localStorage`, `window`) that aren't
there, and they ignore the process lifecycle and platform differences because the
web has neither. The foundation this chapter builds is what lets you catch that.

## Mental Model

React on top, a native world underneath, Expo bridging the two:

```
   YOUR CODE (unchanged from Stage 4)
     React components · hooks · TypeScript · composition · props/state
        │
        ▼
   REACT NATIVE = React with a NATIVE renderer (no DOM, no CSS)
     <View> not <div>   <Text> not <span>   Flexbox-only layout
     StyleSheet objects not CSS   every string INSIDE a <Text>
        │
        │  JSI / bridge  (JS engine: Hermes)   ← cost lives here; keep it thin
        ▼
   NATIVE PLATFORM (two of them)
     iOS (UIView, UIKit)          Android (View, Jetpack)
     differ in: safe areas · gestures · permissions · back button · APIs
        │
        ▼
   EXPO = the toolchain + runtime that makes this shippable
     expo-* native modules (camera, secure-store, notifications)
     config plugins (native config without Xcode/Android Studio)
     EAS Build / Submit / Update (cloud build, store submit, OTA)   ← Ch 07

   THE OS OWNS YOUR PROCESS: it can suspend or KILL the app.
     in-memory state is not durable — assume cold starts and resumes.
```

Four principles carry the chapter:

**React Native is a renderer, not a new framework.** Everything you learned in
Stage 4 about React — components, hooks, composition, typing, when to lift state —
applies unchanged. What you re-learn is the primitive layer: `View`/`Text`/`Image`
instead of DOM elements, `StyleSheet` instead of CSS, Flexbox as the only layout
system. Don't relearn React; relearn the primitives.

**Prefer Expo and managed native access.** Use Expo with config plugins and EAS as
the default. It gives you native modules and native build configuration without
maintaining Xcode/Android Studio projects by hand. Drop to custom native code
(a development build with your own module, or the bare workflow) only when a
concrete requirement has no Expo/community solution — not preemptively.

**Respect the two platforms.** iOS and Android differ in ways that matter:
safe areas, back-button behavior, permissions, gestures. Write one codebase, but
test on both, handle safe areas explicitly (`react-native-safe-area-context`),
and use `Platform.select` where behavior genuinely differs. "It works on the iOS
simulator" is half a test.

**Assume the OS can kill you.** The process lifecycle is real: apps get
backgrounded, suspended, and killed. Durable state must be persisted (Chapter 04),
not held only in memory. Design flows to survive a cold start mid-task.

A working definition:

> **React Native is React with a native renderer — same components and TypeScript,
> a different primitive layer (View/Text/Flexbox, no DOM or CSS) over a native,
> two-platform runtime whose OS can kill your process — and Expo is the toolchain
> and runtime (native modules, config plugins, EAS) that makes shipping it to both
> app stores practical. Keep your React instincts; replace your web-platform
> instincts.**

## Production Example

**Invoicely** — the invoicing SaaS whose backend we built in Stage 3 and whose web
frontend we built in Stage 4 — needs a mobile app. The use case is real and mobile-
specific: a freelancer or small-business owner who wants to check whether an
invoice was paid, send a reminder, or create a quick invoice from their phone
while away from a desk. This is not a port of the web app; it's the same product
surfaced for the moments mobile is actually used — glanceable status, push when an
invoice is paid (Chapter 05), and working on a spotty train connection
(Chapter 04).

In this chapter we bootstrap that app: a new **Expo** project (TypeScript,
Expo Router), the core screen primitives (`View`, `Text`, `FlatList`, `Image`,
`Pressable`), a typed `StyleSheet`, safe-area handling for notches and home
indicators, and a first screen — the invoice list — that fetches from the Stage 3
API and renders natively. We'll contrast it with the web-habit version an
assistant tends to produce (HTML elements, CSS, `localStorage`) to make the
primitive layer concrete. The later chapters add navigation, auth, offline, push,
performance, and shipping on top of this foundation.

## Folder Structure

```
mobile/                                  # the Expo app (sibling to web/ and api/)
├── app.config.ts                        # Expo config: name, icon, plugins, EAS — typed
├── eas.json                             # EAS Build/Submit profiles (Chapter 07)
├── package.json
├── tsconfig.json
├── assets/                              # icon, splash, fonts — bundled into the binary
└── src/
    ├── app/                             # Expo Router: file-based routes (Chapter 02)
    │   ├── _layout.tsx                  # root layout: providers, safe area, fonts
    │   └── (app)/invoices/index.tsx     # the invoice list screen
    ├── components/                      # shared native UI: Screen, Text, Button, Card
    │   ├── Screen.tsx                   # safe-area-aware screen wrapper
    │   └── InvoiceRow.tsx               # one row in the invoice list
    ├── features/invoices/              # feature-scoped (mirrors Stage 4's structure)
    │   ├── api.ts                       # calls the Stage 3 backend
    │   └── types.ts
    ├── lib/                             # api client, config, query client
    └── theme/                           # colors, spacing, typography tokens
```

Why this shape: it deliberately mirrors the **feature-based** structure from
Stage 2 and Stage 4 so a team moving between web and mobile finds the same map.
`app/` is Expo Router's file-based routing (Chapter 02). `components/` holds shared
native primitives — including a `Screen` wrapper that handles safe areas once so
every screen doesn't re-solve notches. `features/` colocates each domain's API and
types. `app.config.ts` and `eas.json` are the Expo/EAS layer that makes the thing
buildable and shippable (Chapter 07). Nothing here is mobile-exotic; it's the same
architecture with a native primitive layer.

## Implementation

**The app config (`app.config.ts`).** Typed Expo configuration — the app's
identity, icon, splash, and native config plugins. This replaces hand-editing
`Info.plist` and `AndroidManifest.xml`.

```ts
import { ExpoConfig } from "expo/config";

const config: ExpoConfig = {
  name: "Invoicely",
  slug: "invoicely",
  scheme: "invoicely",               // deep-link scheme (Chapter 02)
  ios: { bundleIdentifier: "com.invoicely.app", supportsTablet: true },
  android: { package: "com.invoicely.app" },
  plugins: ["expo-router", "expo-secure-store"],   // native config, no Xcode
  extra: { apiUrl: process.env.EXPO_PUBLIC_API_URL },
};

export default config;
```

**A safe-area-aware screen wrapper (`components/Screen.tsx`).** Solve the notch and
home-indicator problem once. Every screen renders inside this instead of re-doing
safe-area math. This is a platform difference handled at the foundation.

```tsx
import { StyleSheet, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

export function Screen({ children }: { children: React.ReactNode }) {
  const insets = useSafeAreaInsets();          // notch/home-indicator padding, per device
  return (
    <View style={[styles.screen, { paddingTop: insets.top, paddingBottom: insets.bottom }]}>
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: "#fff", paddingHorizontal: 16 },
});
```

**A native list row (`components/InvoiceRow.tsx`).** The primitive layer made
concrete: `View` for layout, `Text` for every string (a raw string here would
crash), `Pressable` for touch, `StyleSheet` for styling. Compare this to a web
`<div>`/`<span>` row — same React, different primitives.

```tsx
import { Pressable, StyleSheet, Text, View } from "react-native";
import type { Invoice } from "@/features/invoices/types";

export function InvoiceRow({ invoice, onPress }: { invoice: Invoice; onPress: () => void }) {
  return (
    <Pressable style={styles.row} onPress={onPress}>
      <View>
        <Text style={styles.client}>{invoice.clientName}</Text>
        <Text style={styles.number}>#{invoice.number}</Text>
      </View>
      {/* every string is inside <Text>; a bare string in <View> crashes */}
      <Text style={[styles.amount, invoice.status === "paid" && styles.paid]}>
        ${invoice.amount.toFixed(2)}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: "row", justifyContent: "space-between", paddingVertical: 14 },
  client: { fontSize: 16, fontWeight: "600" },
  number: { fontSize: 13, color: "#6b7280" },
  amount: { fontSize: 16, fontWeight: "600" },
  paid: { color: "#16a34a" },
});
```

**The list screen (`app/(app)/invoices/index.tsx`).** `FlatList`, not `.map()` —
the single most important list decision in React Native. `FlatList` virtualizes
(renders only visible rows), which is what keeps a long list from janking the
bridge. The data comes from the Stage 3 API via React Query (Stage 4, Chapter 04 —
the same server-state discipline carries over).

```tsx
import { FlatList } from "react-native";
import { useQuery } from "@tanstack/react-query";
import { Screen } from "@/components/Screen";
import { InvoiceRow } from "@/components/InvoiceRow";
import { getInvoices } from "@/features/invoices/api";

export default function InvoicesScreen() {
  const { data: invoices = [] } = useQuery({ queryKey: ["invoices"], queryFn: getInvoices });

  return (
    <Screen>
      <FlatList
        data={invoices}
        keyExtractor={(i) => String(i.id)}
        renderItem={({ item }) => <InvoiceRow invoice={item} onPress={() => {}} />}
      />
    </Screen>
  );
}
```

**The anti-pattern — web habits an assistant produces.** Every line here is a
different way the web instinct fails on a device:

```tsx
// ANTI-PATTERN: web React pasted into React Native — none of this works on a device
function InvoicesBad() {
  const token = localStorage.getItem("token");     // no localStorage on a device — crash
  return (
    <div className="screen">                        {/* no <div>, no className/CSS */}
      {invoices.map((i) => (                         // .map() over a long list — no virtualization
        <p key={i.id}>{i.clientName}: ${i.amount}</p> {/* no <p>; and this renders fine but... */}
      ))}
      Total: {total}                                 {/* a bare string in a View-like parent → crash */}
    </div>
  );
}
```

The difference is the whole chapter: the good version uses native primitives
(`View`/`Text`/`FlatList`), handles safe areas, stores nothing in a nonexistent
`localStorage`, and virtualizes the list. The bad version is idiomatic *web* React
that doesn't compile or crashes at runtime on a device — the exact output of
treating React Native as "React in a phone-shaped browser."

## Engineering Decisions

Five decisions define the foundation.

### Expo (managed) or bare React Native?

**Options:** (1) Expo managed workflow with config plugins + EAS; (2) bare React
Native with hand-managed native projects; (3) Expo with a development build for
custom native code.

**Trade-offs:** bare gives you total control over the native projects at the cost
of maintaining Xcode/Android Studio configuration, native dependency upgrades, and
your own build pipeline — real, recurring work. Expo managed removes almost all of
that (native config via plugins, builds via EAS) at the cost of some constraint.
The historical objection — "you can't use custom native code with Expo" — is
outdated: development builds let you add any native module while keeping the Expo
workflow.

**Recommendation:** Expo managed with EAS as the default for essentially all
production apps, moving to a **development build** (still Expo) the moment you need
a native module Expo/the community doesn't provide. Reach for bare React Native
only with a specific, justified reason. The maintenance you avoid is the point.

### `FlatList`/`FlashList` or `.map()` for lists?

**Options:** (1) `.map()` over the array; (2) `FlatList` (built-in virtualization);
(3) `FlashList` (Shopify's higher-performance list).

**Trade-offs:** `.map()` renders every row up front — fine for 5 items, a
frame-dropping memory hog for 500. `FlatList` virtualizes (renders only what's near
the viewport) and gives you `keyExtractor`, pull-to-refresh, and pagination hooks.
`FlashList` improves on `FlatList`'s performance for large/complex lists at the
cost of a dependency and a few API differences.

**Recommendation:** never `.map()` a list that can grow — use `FlatList` by default,
and `FlashList` for large or heavy lists where you measure `FlatList` struggling.
The list is where mobile performance is won or lost (Chapter 06); start it right.

### Styling: `StyleSheet`, inline objects, or a styling library?

**Options:** (1) `StyleSheet.create`; (2) inline style objects; (3) a library
(NativeWind/Tailwind, Tamagui, styled-components).

**Trade-offs:** `StyleSheet.create` is the built-in, zero-dependency baseline —
plain objects, no cascade, validated at load. Inline objects re-create the style
object on every render (minor cost, and no reuse). A styling library (NativeWind
brings Tailwind's utility classes to native) buys ergonomics and a shared design
language with the web at the cost of a dependency and its abstraction.

**Recommendation:** `StyleSheet.create` for the foundation and small apps;
NativeWind (or Tamagui) when the team already thinks in Tailwind or wants a shared
token system across web and mobile. Either way, keep styles as reusable objects,
not scattered inline — and remember it is **not CSS**: no cascade, no inheritance,
Flexbox only.

### Where does app state live across a background kill?

**Options:** (1) in-memory only (`useState`/context); (2) persisted to device
storage; (3) persisted with a rehydration step on launch.

**Trade-offs:** in-memory is simplest and is *gone* when the OS kills the app —
fine for ephemeral UI state, wrong for anything the user expects to survive.
Persisting (AsyncStorage/SecureStore/SQLite — Chapter 04) survives cold starts but
needs a load-and-rehydrate step and a plan for what's durable versus disposable.

**Recommendation:** keep ephemeral UI state in memory, and persist anything the
user would be upset to lose on a background kill — auth tokens (SecureStore,
Chapter 03), draft invoices, cached data (Chapter 04). Decide per piece of state
whether it must survive a cold start; don't assume the process lives forever.

### Handle platform differences: `Platform.select`, `.ios/.android` files, or ignore?

**Options:** (1) ignore differences and hope; (2) `Platform.select`/`Platform.OS`
inline; (3) platform-specific files (`Foo.ios.tsx`/`Foo.android.tsx`).

**Trade-offs:** ignoring differences ships bugs (Android back button unhandled,
iOS safe area wrong). `Platform.select` handles small divergences inline and keeps
the code together. Platform-specific files cleanly separate genuinely different
implementations at the cost of two files to maintain.

**Recommendation:** handle the common differences at the foundation (safe areas via
a wrapper, back button via navigation — Chapter 02), use `Platform.select` for
small inline divergences, and reserve `.ios`/`.android` files for components that
are genuinely different per platform. Test on both platforms; never assume the
simulator you have open represents the other.

## Trade-offs

React Native trades some native fidelity for one codebase, and Expo trades some
control for enormous convenience.

**One codebase trades peak native fidelity for shared velocity.** React Native
ships one TypeScript codebase to both stores — huge for a small team — at the cost
of the last few percent of native feel that a fully native (Swift/Kotlin) app can
reach, and the occasional need to write a native module for something exotic. For a
SaaS companion app like Invoicely, the trade is strongly worth it; for a
performance-critical game or a deeply platform-specific app, it may not be.

**Expo trades some control for removing native-project maintenance.** Managed Expo
means you don't hand-maintain Xcode/Android Studio projects, native dependency
upgrades, or a build pipeline — a large, recurring cost removed — at the price of
working within Expo's model and occasionally reaching for a development build. The
control you give up is mostly control you didn't want to exercise.

**The native bridge trades a clean JS model for a real performance boundary.**
Writing React that renders native views is clean, but the JS↔native boundary is a
cost: large data, chatty calls, and unvirtualized lists cross it and drop frames.
You get a familiar programming model and inherit a performance discipline
(Chapter 06) the web mostly hides.

**The process lifecycle trades simplicity for durability work.** A web page mostly
lives until closed; a mobile app can be killed anytime, so durable state costs a
persistence-and-rehydration step. You trade "state just lives in memory" for an app
that survives real device conditions — non-negotiable for anything a user relies on.

## Common Mistakes

**Treating React Native like web React.** Using `<div>`/`<p>`/CSS/`localStorage`/
`window` — none of which exist. Fix: native primitives (`View`/`Text`/`Image`),
`StyleSheet`, and native storage (Chapter 04); relearn the primitive layer, keep
your React.

**A bare string outside `<Text>`.** `<View>Total: {x}</View>` crashes with "Text
strings must be rendered within a `<Text>` component." Fix: wrap every string in
`<Text>`.

**`.map()` for long lists.** Rendering every row up front, janking the bridge and
burning memory. Fix: `FlatList`/`FlashList` for anything that can grow.

**Ignoring safe areas.** Content under the notch or behind the home indicator. Fix:
`react-native-safe-area-context` (a `Screen` wrapper), applied once at the
foundation.

**Assuming the process lives forever.** Keeping durable state only in memory and
losing it on a background kill. Fix: persist anything that must survive a cold
start (Chapters 03–04).

**Testing one platform.** Shipping after checking only iOS or only Android and
missing back-button, safe-area, or permission differences. Fix: run both; use a
development build to test on real devices.

## AI Mistakes

Assistants are trained on far more web React than React Native, so they default to
web primitives and browser APIs and forget the native runtime entirely. Review
generated mobile code as if it were written for the wrong platform, because
frequently it half was.

### Claude Code: reaching for web/DOM primitives

Asked to build a screen, Claude Code often produces JSX with `<div>`, `<span>`,
`<p>`, `className`, and CSS-style props, or uses `localStorage`/`window`/`document`
— idiomatic web React that either fails to compile or crashes on a device. It knows
React deeply; it slips into the web dialect of React.

**Detect:** any HTML element (`div`/`span`/`p`/`button`/`img`) in a React Native
file; `className` or CSS files; `localStorage`/`sessionStorage`/`window`/`document`;
strings rendered outside `<Text>`.

**Fix:** pin the primitive layer:

> This is React Native, not web React. Use native primitives only — `View`, `Text`,
> `Image`, `Pressable`, `FlatList` — never HTML elements or `className`/CSS. Every
> string must be inside `<Text>`. Use `expo-secure-store`/AsyncStorage for storage,
> never `localStorage` or `window`. Style with `StyleSheet.create`.

### GPT: `.map()` and ignoring list virtualization

GPT-family models tend to render lists with `.map()` inside a `ScrollView`, because
that's the web pattern and it looks correct in a short demo. On a real list it
renders every row eagerly, drops frames, and can exhaust memory — the mobile
performance foot-gun.

**Detect:** `array.map(...)` producing rows inside a `ScrollView` (or bare) for data
that can grow; no `FlatList`/`FlashList`; no `keyExtractor`.

**Fix:** require virtualization:

> Render this list with `FlatList` (or `FlashList` for large/heavy rows), not
> `.map()` in a `ScrollView`. Provide `keyExtractor` and a `renderItem`. Only use
> `.map()`/`ScrollView` for a small, fixed number of items.

### Cursor: ignoring platform differences and safe areas

Editing at the cursor, Cursor tends to write layout that works on the one platform/
simulator in view — full-bleed content that sits under the iOS notch, or an unhandled
Android back button — because the immediate edit looks fine where it's being tested.

**Detect:** screens with no safe-area handling (content at `top: 0`); hardcoded
status-bar/notch offsets; no `Platform.select` where behavior differs; no Android
back-button handling on flows that need it.

**Fix:** require platform-awareness:

> Wrap screens in a safe-area-aware container (`react-native-safe-area-context`) so
> content clears the notch and home indicator on both platforms. Where iOS and
> Android genuinely differ, use `Platform.select`. Assume this runs on both
> platforms and test both — don't hardcode for one device.

## Best Practices

**Keep your React, relearn the primitives.** Reuse everything from Stage 4 —
components, hooks, composition, typing, server-state discipline — and swap the
primitive layer: `View`/`Text`/`Image`/`FlatList`, `StyleSheet`, native storage. Don't
port web primitives; replace them.

**Default to Expo + EAS; drop to native only when forced.** Managed Expo with config
plugins and EAS removes native-project maintenance. Move to a development build for
custom native code only when a real requirement demands it, and to bare only with a
strong reason.

**Solve platform concerns once, at the foundation.** Safe areas via a `Screen`
wrapper, navigation and back button via the router (Chapter 02), storage via a typed
wrapper (Chapter 04) — so individual screens don't re-solve them and get them
inconsistently.

**Virtualize every growable list.** `FlatList`/`FlashList` with `keyExtractor` from
the start; never `.map()` a list that can grow. This is the cheapest large
performance win in the app (Chapter 06).

**Assume the OS can kill you; persist what must survive.** Keep ephemeral state in
memory, persist durable state (tokens, drafts, cached data) with a rehydration step.
Document the primitive-layer and Expo conventions in the mobile `CLAUDE.md` so
assistants stop reaching for the web.

## Anti-Patterns

**Web React in a Native File.** `<div>`/`<p>`/`className`/CSS/`localStorage` in a
React Native component — compiles wrong or crashes. The tell: any HTML element or
browser API in `src/`.

**The `ScrollView` of Everything.** A long `.map()`ed list inside a `ScrollView`,
rendering every row — jank and memory pressure. The tell: `.map()` rows with no
`FlatList`.

**The Notch-Blind Screen.** Full-bleed content with no safe-area handling, sitting
under the notch or behind the home indicator. The tell: screens starting at
`top: 0` with no safe-area context.

**Memory-Only Durable State.** Auth tokens or drafts held only in `useState`/context,
lost on a background kill. The tell: nothing persisted; a cold start loses the user's
session or work.

**The Single-Platform Ship.** Built and tested on one platform only, shipping
back-button/safe-area/permission bugs to the other. The tell: no evidence the other
platform was run.

## Decision Tree

"I'm starting (or extending) a mobile app — how do I set the foundation?"

```
Starting a new app?
├── YES ──► Expo managed + TypeScript + Expo Router (Chapter 02) + EAS (Chapter 07).
│           Add a safe-area Screen wrapper and a native storage wrapper up front.
└── Extending ──► keep the primitive layer honest (native primitives, no web habits).

Need a native module?
├── Expo/community provides it ──► use it (config plugin).
├── Custom native code needed ──► Expo DEVELOPMENT BUILD (still managed workflow).
└── Deep native platform work ──► only then consider bare React Native (justify it).

Rendering a list?
├── Small & fixed (< ~10) ──► .map() in a View is fine.
└── Can grow ──► FlatList (default) or FlashList (large/heavy). Never .map() in ScrollView.

State that must survive a background kill?
├── Ephemeral UI state ──► useState/context (in memory).
└── Durable (tokens/drafts/cache) ──► persist it (SecureStore/AsyncStorage/SQLite, Ch 03-04).

Behavior differs by platform?
└──► handle safe areas once (wrapper); Platform.select for small diffs; .ios/.android files
     for genuinely different implementations. Test BOTH platforms.

NEVER: <div>/<p>/CSS/localStorage in a native file · a bare string outside <Text>.
```

## Checklist

### Implementation Checklist

- [ ] The app is an Expo (managed) project with TypeScript and Expo Router.
- [ ] Only native primitives are used (`View`/`Text`/`Image`/`Pressable`/`FlatList`) — no HTML elements or CSS.
- [ ] Every string is rendered inside a `<Text>`.
- [ ] Growable lists use `FlatList`/`FlashList` with `keyExtractor` — never `.map()` in a `ScrollView`.
- [ ] Safe areas are handled via a shared `Screen` wrapper (`react-native-safe-area-context`).
- [ ] Durable state (tokens, drafts, cache) is persisted; only ephemeral UI state is memory-only.

### Architecture Checklist

- [ ] Feature-based structure mirrors the web app (`features/`, `components/`, `lib/`).
- [ ] Native access goes through Expo config plugins; custom native code (if any) is a development build, not bare.
- [ ] Platform differences are handled deliberately (safe areas, back button, `Platform.select`), not ignored.
- [ ] Storage, navigation, and safe areas are solved once at the foundation, not per screen.
- [ ] Mobile conventions (primitive layer, Expo, storage) are documented in a mobile `CLAUDE.md`.

### Code Review Checklist

- [ ] No web/DOM primitives or browser APIs in native files (watch AI diffs).
- [ ] No bare strings outside `<Text>`.
- [ ] No `.map()` for lists that can grow.
- [ ] No durable state held only in memory.
- [ ] Change was (or can be) verified on both iOS and Android.

*(A Deployment Checklist appears in Chapter 07, where EAS Build/Submit and store submission are covered.)*

## Exercises

**1. Bootstrap Invoicely mobile.** Create the Expo project (TypeScript, Expo Router),
add the `Screen` safe-area wrapper, and build the invoice-list screen with `FlatList`
fetching from the Stage 3 API via React Query. The artifact is a running app showing
the list correctly inset on both an iOS and an Android simulator.

**2. Break, then fix, the web habits.** Have an assistant generate "an invoice list
screen" and catalog every web-ism it produces (HTML elements, CSS, `localStorage`,
`.map()`, missing safe areas). Rewrite it with native primitives and note which fixes
were compile errors versus runtime crashes versus silent bugs. The artifact is the
before/after and the categorized list.

**3. Survive a kill.** Add a piece of durable state (a draft invoice) held only in
`useState`, background the app and force-kill it, and observe the loss. Then persist
it (AsyncStorage) with a rehydration step on launch and confirm it survives. The
artifact is the two versions and a note on what state should be durable versus
ephemeral.

## Further Reading

- **React Native documentation — "Core Components and APIs" and "Style"**
  (reactnative.dev) — the authoritative reference for the primitive layer:
  `View`/`Text`/`Image`/`FlatList` and how `StyleSheet`/Flexbox differ from CSS.
- **Expo documentation — "Get started" and "Develop"** (docs.expo.dev) — the managed
  workflow, config plugins, development builds, and EAS; the counterpart to this
  chapter's Expo recommendation.
- **React Native — "Optimizing Flatlist Configuration" and "Performance"**
  (reactnative.dev) — why virtualization matters and how the JS/native boundary
  drives the performance discipline expanded in Chapter 06.
- **Expo — "Config plugins"** (docs.expo.dev) — how native configuration is expressed
  without editing Xcode/Android Studio projects, the mechanism behind the managed
  workflow recommendation.
</content>
</invoke>

# Navigation & Deep Linking

## Introduction

A mobile app is a graph of screens, and navigation is how the user moves through
it — but unlike the web, there is no address bar, the back button behaves
differently on each platform, screens have lifecycle (they mount, blur, focus, and
unmount as the user pushes and pops), and users can arrive at any screen from
*outside* the app entirely: a push notification, a link in an email, a scan of a QR
code. This chapter covers both halves of that problem together because they are the
same problem: **navigation is routing inside the app, and deep linking is routing
into the app from outside — and a good router models both with one URL system.**

The tool is **Expo Router**, a file-based router built on React Navigation that
brings the App Router mental model from Stage 4 to mobile: a file in `app/` is a
route, folders are nested navigators, and every screen has a URL. That last point
is the key that unifies the chapter. Because every screen has a URL, a deep link
(`invoicely://invoices/42`) and an in-app navigation (`router.push("/invoices/42")`)
resolve through the *same* routing table to the *same* screen. Deep linking stops
being a bolt-on and becomes "the router already knows this address."

The judgment this chapter teaches is threefold: choosing the right **navigator**
for each part of the app (stack for drill-down, tabs for top-level sections, modal
for interruptions), designing routes as a **URL hierarchy** rather than an ad-hoc
pile of screens, and treating **deep links as first-class entry points** — every
important screen reachable by URL, authentication and missing-data handled on
arrival, because a user can land on a deep screen with no history behind them.

## Why It Matters

Navigation is the app's skeleton, and getting it wrong is expensive to fix later
because everything hangs off it:

- **The back button is not one thing.** Android has a hardware/gesture back button
  the OS expects your app to handle; iOS has a swipe-back gesture and a header back
  button but no hardware button. A navigation model that ignores this traps users
  on Android (back does nothing or exits the app unexpectedly) — a top app-store
  complaint.
- **Screens have lifecycle, and web habits leak.** A screen you navigated away from
  is often still mounted (in the stack, just not focused). Data fetching, timers,
  and subscriptions tied to mount instead of *focus* keep running on unfocused
  screens, or fail to refresh when you return. `useEffect(..., [])` — the web
  habit — is frequently the wrong hook here.
- **Deep links are how mobile actually gets used.** Users arrive from notifications
  ("your invoice was paid" → the invoice), emails, and shared links far more than
  they navigate from a home screen. If those entry points don't resolve to the
  right screen — or crash because the user isn't authenticated or the data is
  missing — you've broken the primary way people enter the app.
- **Arriving deep means no history.** A user who taps a notification lands on the
  invoice detail with *nothing* behind it. Back must go somewhere sensible (the
  list, the home tab), not off the edge of the app. This has to be designed, not
  assumed.
- **Auth gating is a routing concern.** Which screens require a logged-in user, and
  where an unauthenticated deep link redirects (to login, then back to the target),
  is navigation logic. Bolting it onto individual screens produces gaps a deep link
  walks right through.

Done well — a clear navigator hierarchy, screens that respond to focus, every
important screen URL-addressable, auth and missing-data handled on arrival — the
app feels native on both platforms and every entry point lands correctly. Done
badly, you get back-button traps, stale or double-fetching screens, and deep links
that crash or dump the user on a blank screen with no way back.

The AI dimension: assistants model navigation as web routing (a flat list of pages,
`useEffect` for data, no focus concept, no back-stack reasoning), treat deep linking
as an afterthought if at all, and rarely handle the "arrived here from outside with
no auth and no history" case — because none of it exists on the web the way it does
on a device.

## Mental Model

One URL system serving two directions — navigation out from inside, deep links in
from outside:

```
   NAVIGATORS (choose per section)
     Stack   ── push/pop, drill-down        invoices → invoice detail → edit
     Tabs    ── top-level sections          [Invoices] [Clients] [Settings]
     Modal   ── interruptions over content  "Create invoice" sheet
        │
        ▼
   EXPO ROUTER: files in app/ ARE routes — every screen has a URL
     app/(app)/invoices/index.tsx        → /invoices
     app/(app)/invoices/[id].tsx         → /invoices/42   (dynamic segment)
     app/(auth)/login.tsx                → /login
        │
        ├──────────────── IN-APP NAV ─────────────►  router.push("/invoices/42")
        │
        └──────────────── DEEP LINK IN ────────────►  invoicely://invoices/42
                                                       https://app.invoicely.com/invoices/42
              same routing table → same screen. Deep linking is not a bolt-on.

   SCREEN LIFECYCLE (not the web!)
     mounted ≠ focused. A pushed-over screen stays MOUNTED but BLURRED.
     data that must refresh on return ──► useFocusEffect, not useEffect([])

   ARRIVING FROM OUTSIDE:
     no history behind you ──► design a sensible "back" target
     not authenticated     ──► redirect to login, then RETURN to the deep target
     data missing/deleted  ──► handle gracefully, don't crash on a blank screen
```

Four principles carry the chapter:

**Pick the navigator that matches the relationship.** Stack for drill-down (a
back-stack of screens), tabs for parallel top-level sections, modal for
interruptions that sit over the current context. Nesting them (tabs containing
stacks) models most apps. Using the wrong one — tabs where a stack belongs — fights
the platform.

**Design routes as a URL hierarchy.** Because every screen has a URL, name and nest
routes deliberately: `/invoices`, `/invoices/[id]`, `/invoices/[id]/edit`. A clean
hierarchy makes deep linking, auth gating, and navigation all fall out naturally. A
flat pile of screens makes all three ad-hoc.

**Deep links are first-class entry points, not a feature you add later.** Every
important screen should be reachable by URL, and the app must handle *arrival*:
authenticate if needed (then return to the target), tolerate missing data, and
provide a sensible back target when there's no history. Design entry, not just
traversal.

**Respect the screen lifecycle.** Mounted is not focused. Use `useFocusEffect` for
work that should run when a screen becomes focused (refresh on return) and clean up
on blur; handle the Android back button through the navigator. Don't port
`useEffect(..., [])` reasoning from the web unchanged.

A working definition:

> **Navigation and deep linking are one problem — routing — solved by giving every
> screen a URL: pick the navigator (stack/tabs/modal) that matches each section,
> design routes as a deliberate URL hierarchy, treat deep links as first-class entry
> points that handle auth/missing-data/no-history on arrival, and respect the screen
> lifecycle (focus, not just mount, and the platform back button).**

## Production Example

**Invoicely mobile** has a clear navigation shape. The top level is **tabs**:
Invoices, Clients, Settings. Inside the Invoices tab is a **stack**: the list →
an invoice detail → an edit screen. Creating an invoice is a **modal** that slides
over whatever you're looking at. That's all three navigator types, nested the way
a real app nests them.

The deep-linking requirement is concrete and drives the design: when the backend
sends a push notification "Invoice #42 was paid" (Chapter 05), tapping it must open
`/invoices/42` — even from a cold start, even if the user's session needs
refreshing, and with a back button that returns to the invoice list rather than
exiting the app. An emailed "view invoice" link
(`https://app.invoicely.com/invoices/42`) must resolve to the same screen via
universal/app links.

In this chapter we build that structure with Expo Router: the tab layout, the
invoices stack, the create-invoice modal, dynamic routes (`[id]`), the deep-link
scheme and universal-link configuration, an auth gate that redirects unauthenticated
deep links to login and returns to the target, and `useFocusEffect` so the detail
screen refreshes when you navigate back to it after marking an invoice paid. We'll
contrast it with the web-habit version (flat screens, `useEffect` data, no deep-link
or arrival handling) an assistant tends to produce.

## Folder Structure

```
mobile/src/app/                          # Expo Router — files ARE routes
├── _layout.tsx                          # ROOT: providers, auth gate, deep-link config
├── (auth)/                              # unauthenticated group (no tab bar)
│   └── login.tsx                        # /login
└── (app)/                               # authenticated group
    ├── _layout.tsx                      # TABS navigator: Invoices | Clients | Settings
    ├── invoices/
    │   ├── _layout.tsx                  # STACK navigator for the invoices tab
    │   ├── index.tsx                    # /invoices          (list)
    │   ├── [id].tsx                     # /invoices/42       (detail, dynamic)
    │   └── [id]/edit.tsx                # /invoices/42/edit
    ├── clients/index.tsx                # /clients
    ├── settings/index.tsx               # /settings
    └── create.tsx                       # /create   (presented as a MODAL)
```

Why this shape: the folder tree *is* the URL hierarchy and the navigator tree at
once — this is Expo Router's core idea and why it unifies navigation with deep
linking. `(auth)` and `(app)` are **route groups** (parentheses = grouping without a
URL segment) that separate the logged-out and logged-in worlds, which is exactly
where the auth gate lives. Each `_layout.tsx` declares a navigator (root → tabs →
per-tab stack). `[id].tsx` is a dynamic segment, so `/invoices/42` and a deep link
to it resolve identically. `create.tsx` is configured as a modal presentation.
Nothing is a flat list; the structure encodes the navigation *and* every deep-link
target.

## Implementation

**The tabs layout (`(app)/_layout.tsx`).** The top-level navigator — parallel
sections the user switches between. Declared as data, not imperative navigation.

```tsx
import { Tabs } from "expo-router";

export default function AppTabsLayout() {
  return (
    <Tabs screenOptions={{ headerShown: false }}>
      <Tabs.Screen name="invoices" options={{ title: "Invoices" }} />
      <Tabs.Screen name="clients" options={{ title: "Clients" }} />
      <Tabs.Screen name="settings" options={{ title: "Settings" }} />
    </Tabs>
  );
}
```

**The invoices stack (`(app)/invoices/_layout.tsx`).** Inside the Invoices tab, a
stack for drill-down: list → detail → edit. The stack is what gives you the native
back button and swipe-back gesture for free.

```tsx
import { Stack } from "expo-router";

export default function InvoicesStackLayout() {
  return (
    <Stack>
      <Stack.Screen name="index" options={{ title: "Invoices" }} />
      <Stack.Screen name="[id]" options={{ title: "Invoice" }} />
      <Stack.Screen name="[id]/edit" options={{ title: "Edit" }} />
    </Stack>
  );
}
```

**A dynamic detail screen that refreshes on focus (`invoices/[id].tsx`).** The URL
parameter (`id`) is read with `useLocalSearchParams` — the same value whether the
user tapped a row (`router.push`) or arrived via a deep link. `useFocusEffect`, not
`useEffect([])`, is the mobile-correct hook: it refetches when the screen regains
focus (e.g., you edited the invoice and navigated back).

```tsx
import { useLocalSearchParams, useRouter } from "expo-router";
import { useFocusEffect } from "@react-navigation/native";
import { useQuery } from "@tanstack/react-query";
import { useCallback } from "react";
import { getInvoice } from "@/features/invoices/api";

export default function InvoiceDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();   // same for nav OR deep link
  const router = useRouter();
  const { data: invoice, refetch } = useQuery({
    queryKey: ["invoice", id],
    queryFn: () => getInvoice(id),
  });

  // Refresh when this screen regains FOCUS (returning from edit) — not just on mount.
  useFocusEffect(useCallback(() => { refetch(); }, [refetch]));

  if (!invoice) return <NotFound message="Invoice not found" />;  // handle missing data
  return <InvoiceDetail invoice={invoice} onEdit={() => router.push(`/invoices/${id}/edit`)} />;
}
```

**The modal (`create.tsx` + root config).** Presenting a screen as a modal is a
navigator option, not a different mechanism — same routing table, different
presentation.

```tsx
// in the (app) stack/root layout options:
<Stack.Screen name="create" options={{ presentation: "modal", title: "New invoice" }} />
```

**Deep linking: scheme + universal links (`app.config.ts`).** The `scheme` enables
`invoicely://…` links; `associatedDomains`/`intentFilters` enable
`https://app.invoicely.com/…` universal (iOS) and app (Android) links. Expo Router
maps both onto the same file-based routes — no manual link-to-screen table.

```ts
// app.config.ts (excerpt)
export default {
  scheme: "invoicely",                                  // invoicely://invoices/42
  ios: { associatedDomains: ["applinks:app.invoicely.com"] },   // https:// universal links
  android: {
    intentFilters: [{
      action: "VIEW",
      data: [{ scheme: "https", host: "app.invoicely.com" }],
      category: ["BROWSABLE", "DEFAULT"],
    }],
  },
};
```

**The auth gate that handles deep-link arrival (`app/_layout.tsx`).** The critical
"arrived from outside" logic: a deep link to a protected screen while logged out
must redirect to login and then **return to the intended target** — not silently
drop the user on the home screen. Route groups make "which world am I in" explicit.

```tsx
import { Redirect, Slot, useSegments, useRootNavigationState } from "expo-router";
import { useAuth } from "@/features/auth/useAuth";

export default function RootLayout() {
  const { isSignedIn, isLoaded } = useAuth();
  const segments = useSegments();
  const navState = useRootNavigationState();

  if (!navState?.key || !isLoaded) return null;          // wait for router + auth to be ready

  const inAuthGroup = segments[0] === "(auth)";
  // Deep link into a protected screen while signed out → login, remembering the target.
  if (!isSignedIn && !inAuthGroup) return <Redirect href="/login" />;
  if (isSignedIn && inAuthGroup) return <Redirect href="/invoices" />;

  return <Slot />;   // render the matched route
}
```

**The anti-patterns — web-habit navigation an assistant produces.** Each line is a
mobile concern the web doesn't have:

```tsx
// ANTI-PATTERN: web routing habits ported to a device
function AppBad() {
  useEffect(() => { fetchInvoice(id); }, []);            // won't refresh on focus/return
  // no deep-link scheme configured → notification/email links open nothing
  // no auth gate → a deep link to /invoices/42 while logged out crashes or shows a blank
  // no back-target design → arriving deep, back exits the app
  return currentScreen === "detail" ? <Detail /> : <List />;  // hand-rolled routing, no URLs
}
```

The difference is the whole chapter: the good version models sections with the right
navigators, gives every screen a URL so deep links resolve for free, handles auth and
missing-data on arrival, and refreshes on focus. The bad version hand-rolls routing
with no URLs (so nothing deep-links), fetches on mount (stale on return), and has no
story for a user arriving from a notification while logged out.

## Engineering Decisions

Five decisions define the app's navigation.

### Which navigator for each section — stack, tabs, or modal?

**Options:** (1) stack (push/pop drill-down); (2) tabs (parallel top-level
sections); (3) modal (interruption over the current context); nested combinations.

**Trade-offs:** a stack gives native back/swipe and a history — right for
drill-down (list → detail → edit), wrong for parallel sections (you'd lose the
back-stack semantics). Tabs give persistent top-level switching but aren't a
history. Modals interrupt and return — right for "create" or "confirm," wrong for
primary navigation. Real apps nest them: tabs containing per-tab stacks, with modals
presented over the top.

**Recommendation:** map the *relationship* to the navigator — drill-down → stack,
parallel sections → tabs, interruption → modal — and nest (tabs of stacks) for most
apps. Don't force one navigator to do another's job; the platform gestures and back
behavior depend on getting this right.

### File-based (Expo Router) or component-based (React Navigation) routing?

**Options:** (1) Expo Router (file-based, every screen a URL); (2) React Navigation
directly (navigators declared in components).

**Trade-offs:** React Navigation is the underlying, battle-tested library with
maximal configurability declared imperatively. Expo Router sits on top and adds
file-based routes and — critically — a URL for every screen, which makes deep linking
and universal links close to automatic. The cost is a convention (the `app/` tree)
and slightly less imperative control.

**Recommendation:** Expo Router for new apps — the URL-per-screen model is exactly
what unifies navigation and deep linking and matches the App Router mental model from
Stage 4. Drop to React Navigation's APIs directly only for advanced customizations
Expo Router doesn't expose. The deep-linking payoff alone justifies it.

### How are deep links authenticated and returned to their target?

**Options:** (1) no gating (protected screens open regardless); (2) gate and redirect
to login but drop the target; (3) gate, redirect to login, and return to the original
target after auth.

**Trade-offs:** no gating leaks protected data or crashes on missing session. Gating
without return sends the user to login and then dumps them on the home screen —
they've lost the invoice they tapped a notification to see. Gating with return is the
correct UX but requires remembering the intended URL across the auth flow.

**Recommendation:** gate protected routes at the group level (`(app)` requires auth)
and **return to the target** after login — remember the intended href and redirect
back. A deep link that survives an auth detour is the difference between a working
notification and a frustrating one (Chapter 03 covers the auth mechanics).

### What runs on mount versus on focus?

**Options:** (1) `useEffect(..., [])` for all screen work (web habit); (2)
`useFocusEffect` for work that should track focus; (3) a mix by intent.

**Trade-offs:** `useEffect([])` runs once on mount and never again while the screen
stays mounted in the stack — so a detail screen won't refresh when you return to it
after an edit, and background timers keep running on blurred screens.
`useFocusEffect` runs on focus and cleans up on blur — correct for refresh-on-return
and for pausing work when unfocused, at the cost of remembering the distinction.

**Recommendation:** use `useFocusEffect` for anything that should refresh when the
screen is returned to, or that should stop when the screen is blurred (subscriptions,
timers, video); reserve `useEffect` for true one-time setup. Mounted is not focused —
default to focus-awareness for screen data.

### Where does back go when the user arrived deep?

**Options:** (1) rely on the natural back-stack (empty on deep arrival); (2) seed a
sensible back target; (3) always route back to a known anchor (the tab root).

**Trade-offs:** relying on the stack means a user who tapped a notification into
`/invoices/42` has nothing behind them — back exits the app, which feels broken.
Seeding a back target (push the list, then the detail) gives natural back behavior at
the cost of arranging it. Anchoring back to the tab root is simple and predictable but
can feel abrupt.

**Recommendation:** for deep arrivals, ensure back goes somewhere sensible — typically
by making the deep target part of its natural stack (so back lands on the list/tab
root), and handle the Android hardware back explicitly. Never let back off the edge of
the app from a deep-linked screen.

## Trade-offs

Good navigation trades some up-front structure for an app that feels native and links
correctly.

**File-based routing trades a convention for near-free deep linking.** Expo Router
asks you to organize screens as an `app/` tree and, in return, gives every screen a
URL — so deep links, universal links, and in-app navigation all resolve through one
table. You trade imperative flexibility for a structure that makes the hardest part
(links from outside) mostly automatic.

**Nested navigators trade some complexity for native feel.** Tabs-of-stacks-with-modals
matches how users expect a mobile app to behave (per-tab history, modal
interruptions, correct back/swipe) at the cost of a deeper navigator tree to reason
about. The complexity buys the platform-native behavior users judge the app by.

**Focus-awareness trades a new concept for correctness.** Distinguishing mount from
focus (`useFocusEffect`) is one more thing to hold in your head, and it removes a class
of bugs — stale screens on return, work running on blurred screens — that
`useEffect([])` silently creates on mobile.

**First-class deep linking trades arrival-handling work for reliable entry points.**
Making every screen URL-addressable and handling auth/missing-data/no-history on
arrival is real work, and it's what makes notifications, emails, and shared links
actually land where they should — the primary way mobile apps get opened.

## Common Mistakes

**Wrong navigator for the relationship.** Tabs where a stack belongs (or vice versa),
fighting the platform's back/gesture behavior. Fix: drill-down → stack, parallel →
tabs, interruption → modal; nest them.

**`useEffect([])` where `useFocusEffect` belongs.** Screens that don't refresh on
return, or keep timers/subscriptions running while blurred. Fix: `useFocusEffect` for
focus-tracked work.

**Deep linking as an afterthought.** No scheme/universal-link config, so notification
and email links open nothing (or the app cold-starts to the home screen). Fix:
configure the scheme and associated domains; rely on the URL-per-screen router.

**No auth handling on deep arrival.** A deep link to a protected screen while logged
out crashes or leaks. Fix: gate protected route groups and return to the target after
login.

**No back target on deep arrival.** Back exits the app because there's no history
behind a deep-linked screen. Fix: seed the natural stack or anchor back to the tab
root; handle Android hardware back.

**Not handling missing/deleted data.** A deep link to a now-deleted invoice crashes on
a null. Fix: handle not-found gracefully with a real screen and a way back.

## AI Mistakes

Assistants model navigation the way the web does — a flat set of pages, `useEffect`
for data, no back-stack or focus concept — and treat deep linking as out of scope.
Review generated navigation for the two things the web lacks: the screen lifecycle and
external entry points.

### Claude Code: web-style flat routing without URLs or deep-link config

Asked to add screens, Claude Code often wires navigation as conditional rendering or a
flat set of routes without leaning on the URL-per-screen model, and omits deep-link
configuration entirely — so nothing is reachable from a notification or a link. It
reproduces web SPA routing, where external deep entry isn't a first-class concern.

**Detect:** hand-rolled routing (state deciding which screen renders) instead of the
`app/` route tree; no `scheme`/`associatedDomains`/`intentFilters`; screens with no
stable URL; `router.push` targets that don't correspond to files.

**Fix:** require the router's URL model and deep-link config:

> Use Expo Router's file-based routes so every screen has a URL, and navigate by URL
> (`router.push("/invoices/42")`). Configure the deep-link `scheme` and universal/app
> links so notification and email links resolve to those same routes. Don't hand-roll
> routing with conditional rendering.

### GPT: `useEffect([])` for screen data, ignoring focus

GPT-family models fetch screen data in `useEffect(..., [])`, the web default, which
doesn't account for the mobile screen lifecycle — the screen won't refresh when
returned to, and cleanup doesn't track blur. The bug shows only on the *second* visit,
so it passes a quick demo.

**Detect:** `useEffect(() => { fetch... }, [])` in screen components that should
refresh on return; subscriptions/timers with no blur cleanup; stale data after
navigating back from an edit.

**Fix:** require focus-awareness:

> Screens that should refresh when returned to must use `useFocusEffect` (or React
> Query with refetch-on-focus), not `useEffect([])`. Work that should stop when the
> screen is unfocused (timers, subscriptions) must clean up on blur. Mounted is not
> focused.

### Cursor: deep links that ignore auth and no-history arrival

Editing a specific screen, Cursor tends to implement the happy path — the screen
renders given its params — without handling the *arrival* cases a deep link creates:
the user is logged out, the data is gone, or there's no back-stack. The screen works
when reached in-app and breaks when reached from a notification.

**Detect:** protected screens with no auth gate on the route group; no not-found
handling for a missing/deleted resource; deep-linkable screens where back has no
sensible target; no return-to-target after login.

**Fix:** require arrival handling:

> This screen is deep-linkable, so handle arrival from outside: gate the route group so
> a logged-out deep link redirects to login and returns to the target; handle
> missing/deleted data with a not-found state; ensure back goes somewhere sensible when
> there's no history. Don't assume the user reached this screen in-app while
> authenticated.

## Best Practices

**Match navigators to relationships and nest them.** Stack for drill-down, tabs for
top-level sections, modal for interruptions; tabs-of-stacks-with-modals for most apps.
Let the navigator provide native back/swipe rather than hand-rolling it.

**Design routes as a deliberate URL hierarchy.** Name and nest routes so the tree
reads as the app's structure (`/invoices`, `/invoices/[id]`, `/invoices/[id]/edit`).
The hierarchy makes deep linking, auth gating, and navigation fall out for free.

**Treat every important screen as a deep-link target.** Configure the scheme and
universal/app links, rely on the URL-per-screen router, and handle arrival: auth
(return to target), missing data, and a sensible back. Deep links are how the app is
opened, not an add-on.

**Track focus, not just mount.** Use `useFocusEffect` (or refetch-on-focus) for screen
data that must be fresh on return and for work that should pause when blurred. Handle
the Android hardware back button through the navigator.

**Keep the logged-out and logged-in worlds separate.** Use route groups (`(auth)` vs
`(app)`) so the auth boundary is structural, and document navigation and deep-link
conventions in the mobile `CLAUDE.md` so assistants stop reaching for web routing.

## Anti-Patterns

**Hand-Rolled Routing.** Conditional rendering deciding which screen shows, with no
URLs — so nothing deep-links and back is manual. The tell: `screen === "x" ? <X/> :
<Y/>` instead of a route tree.

**The Afterthought Deep Link.** No scheme/universal-link config; notification and email
links open the home screen or nothing. The tell: push notifications that don't open the
relevant screen.

**The Mount-Only Screen.** `useEffect([])` for data that should refresh on return;
stale screens and blurred-screen timers. The tell: data that's wrong on the second
visit.

**The Unguarded Deep Link.** A protected or data-dependent screen that crashes when
reached from outside while logged out or when the data is gone. The tell: deep links
that work in-app and crash from a notification.

**The Dead-End Back.** A deep-linked screen with no history, so back exits the app. The
tell: tapping a notification, then back, closes the app instead of going to the list.

## Decision Tree

"I'm adding navigation / a screen / a link into the app — how do I model it?"

```
Relationship between screens?
├── Drill-down (list → detail → edit) ──► Stack navigator
├── Parallel top-level sections ──────────► Tabs navigator
└── Interruption over current context ────► Modal presentation      (nest as needed)

Defining routes?
└──► Expo Router file tree = URL hierarchy. Dynamic data → [id].tsx.
     Separate logged-out/in with route groups: (auth) vs (app).

Should this screen be reachable from outside (notification/email/link)?
├── YES ──► it already has a URL. Configure scheme + universal/app links.
│           Handle ARRIVAL:  auth? → gate + return to target
│                            data missing? → not-found state
│                            no history? → sensible back target
└── NO ───► still give it a URL; just don't advertise it.

Screen needs data?
├── Fresh only once ──────────► useEffect (rare for screens)
└── Fresh on return / focus ──► useFocusEffect (or React Query refetch-on-focus)

Android hardware back matters? ──► handle it via the navigator; never trap the user.

NEVER: hand-rolled conditional routing · deep links with no auth/no-history handling.
```

## Checklist

### Implementation Checklist

- [ ] Sections use the right navigator (stack/tabs/modal), nested appropriately.
- [ ] Routes are defined as an Expo Router file tree; every screen has a URL.
- [ ] Dynamic screens read params with `useLocalSearchParams` and resolve identically for nav and deep links.
- [ ] The deep-link `scheme` and universal/app links are configured.
- [ ] Screen data that must be fresh on return uses `useFocusEffect`/refetch-on-focus, not `useEffect([])`.
- [ ] Protected route groups gate deep links and return to the target after login.

### Architecture Checklist

- [ ] Logged-out and logged-in worlds are separated with route groups (`(auth)`/`(app)`).
- [ ] The route tree reads as the app's structure (a deliberate URL hierarchy).
- [ ] Every important screen is a deep-link target with arrival handling (auth, missing data, back).
- [ ] Android hardware back is handled; back never exits the app from a deep-linked screen.
- [ ] Navigation and deep-link conventions are documented in the mobile `CLAUDE.md`.

### Code Review Checklist

- [ ] No hand-rolled conditional routing where the router should be used.
- [ ] No `useEffect([])` for screen data that should refresh on focus.
- [ ] No deep-linkable screen without auth/missing-data/no-history handling.
- [ ] No dead-end back from a deep-linked screen.
- [ ] Deep links verified from a cold start and while logged out, on both platforms.

*(A Deployment Checklist is covered in Chapter 07; universal/app-link domain verification is part of shipping.)*

## Exercises

**1. Build the navigator hierarchy.** Implement Invoicely's tabs (Invoices/Clients/
Settings), the invoices stack (list → detail → edit), and the create-invoice modal
with Expo Router. The artifact is a running app where back/swipe behave natively on
both platforms and the modal presents and dismisses correctly.

**2. Make a notification land correctly.** Configure the deep-link scheme, then
simulate opening `invoicely://invoices/42` from a cold start while logged out. Make it
redirect to login and *return* to invoice 42 with a back button that goes to the list.
The artifact is the working flow and the auth-gate/return code.

**3. Catch the focus bug.** Build the detail screen with `useEffect([])` data, edit an
invoice, navigate back, and observe the stale value. Fix it with `useFocusEffect`
(or refetch-on-focus) and confirm it refreshes. The artifact is the before/after and a
note on which screens need focus-awareness.

## Further Reading

- **Expo Router documentation** (docs.expo.dev/router) — file-based routing, dynamic
  routes, layouts/navigators, and how URLs map to screens; the authoritative source for
  this chapter's routing model.
- **React Navigation documentation** (reactnavigation.org) — the underlying library:
  stack/tabs/modal navigators, the screen lifecycle, and `useFocusEffect`; read the
  "Navigation lifecycle" and "Deep linking" guides directly.
- **Expo — "Linking" and "Deep linking"** (docs.expo.dev) — configuring schemes,
  universal links (iOS associated domains), and Android app links; the mechanics behind
  first-class deep linking.
- **Apple — "Supporting Universal Links" / Android — "App Links"** (developer.apple.com,
  developer.android.com) — the platform requirements (associated domains, Digital Asset
  Links) for `https://` links to open your app instead of the browser.
</content>

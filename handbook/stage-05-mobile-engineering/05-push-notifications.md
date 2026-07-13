# Push Notifications

## Introduction

Push notifications are how a mobile app reaches a user when the app is closed —
the one channel the web platform never had as a first-class citizen. For a SaaS
product they are enormously valuable ("your invoice was paid," "a payment failed")
and enormously easy to abuse into the thing users uninstall an app over. This
chapter is about implementing them correctly: the delivery pipeline (from your
backend, through Apple's and Google's push services, to the device), the
permission and token lifecycle, what a notification should *do* when tapped, and
the product discipline that separates a useful signal from spam.

The single most important idea: **a push notification is a request that travels
through infrastructure you don't own, to a user who can revoke it at any time —
so every step is unreliable and every send is a permission you're spending.**
Unlike an in-app message, you don't control delivery: Apple Push Notification
service (APNs) and Firebase Cloud Messaging (FCM) sit between your server and the
device, delivery is best-effort (not guaranteed, not instant), the device token can
change or expire, and the user can deny or revoke permission in a tap. Treating
push as a reliable, always-available message bus — the way you'd treat an in-process
event — is the root of most push bugs and most push *abuse*.

The judgment this chapter teaches spans engineering and product. On the engineering
side: manage the **token lifecycle** (request permission at the right moment,
register the token to the user, handle rotation and revocation), send through the
correct pipeline (Expo's push service over APNs/FCM), and make notifications
**actionable** — tapping one deep-links to the relevant screen (Chapter 02), and
handling differs by app state (foreground/background/killed). On the product side:
notifications are a **budget**, not a feature — every send costs attention and trust,
and the right default is *fewer, higher-signal, user-controlled* pushes. Sending is
the easy part; deciding what's worth sending is the engineering-judgment part.

## Why It Matters

Push notifications are simultaneously a high-value feature and the fastest way to get
an app uninstalled, and both come from the same properties:

- **They reach users when nothing else can.** The app is closed, the user isn't
  looking — push is the only channel. For time-sensitive events (a payment failed, an
  invoice is overdue) that reach is genuinely valuable and hard to replace.
- **Delivery is unreliable by design.** APNs and FCM are best-effort: notifications
  can be delayed, coalesced, or dropped (device off, throttling, token expired).
  Anything that *must* happen — a state change, a data update — cannot depend on a
  push arriving. Push is a nudge, not a delivery guarantee.
- **Permission is a one-shot you can waste.** iOS shows the system permission prompt
  essentially once; if you ask at the wrong moment (cold app launch, before any value)
  and the user denies, you've lost the channel for good short of them digging into
  Settings. *When* you ask matters as much as that you ask.
- **Tokens rotate and revoke.** The device push token changes (reinstall, restore,
  OS events) and permission can be revoked anytime. A backend that sends to stale
  tokens wastes sends and misses users; token lifecycle management is not optional.
- **Every send spends trust.** Users judge an app by its notifications. One
  well-timed, relevant push builds engagement; a stream of marketing pings trains the
  user to swipe them away, disable them, or uninstall. The notification budget is a
  real, depletable resource.
- **Tapping must go somewhere useful.** A notification about invoice #42 that opens
  the app to a generic home screen wastes the tap. Notifications are entry points
  (Chapter 02) — they must deep-link to the relevant context.

Done well — permission asked in context, tokens managed, delivery treated as
best-effort, notifications actionable and deep-linked, and a disciplined,
user-controllable send policy — push becomes a high-value re-engagement channel users
keep enabled. Done badly, you ask too early and lose permission, send to dead tokens,
rely on push for things that must be reliable, dump users on the home screen, and
train them to disable notifications or uninstall.

The AI dimension: assistants implement the *sending* mechanics (which are easy) and
skip the parts that matter — they ask for permission on launch (wasting the one-shot),
ignore token rotation, treat delivery as guaranteed, forget the tap-handling/deep-link,
and have no notion of the notification budget. The result sends notifications and
mismanages every hard part.

## Mental Model

A pipeline you don't fully own, a token lifecycle, tap-handling by app state, and a
budget:

```
   THE PIPELINE (you own only the ends)
     YOUR BACKEND ──► Expo Push Service ──► APNs (iOS) / FCM (Android) ──► DEVICE
        (send a message)                      └── best-effort: delayed / coalesced / dropped ──┘
        push is a NUDGE, not a guaranteed delivery. Never depend on arrival.

   TOKEN LIFECYCLE
     ask permission IN CONTEXT (not on cold launch) ──► get device push token ──►
       register token ↔ user on the backend ──► token ROTATES/REVOKES ──► update/prune it
       (send to stale token = wasted send / missed user)

   ON TAP — behavior depends on APP STATE:
     foreground ──► app is open: show in-app / update UI (don't interrupt rudely)
     background ──► tapping OPENS the app → DEEP LINK to the relevant screen (Ch 02)
     killed     ──► cold start → read the notification → route to the screen (Ch 02)

   THE BUDGET (product discipline, not a feature toggle)
     every send spends ATTENTION + TRUST.  default: FEWER, higher-signal, user-controlled.
     transactional (invoice paid, payment failed) ≫ marketing (come back!).
     give users granular controls. respect the deny.
```

Four principles carry the chapter:

**Push is best-effort; never depend on delivery.** APNs/FCM can delay, coalesce, or
drop notifications. Use push to *nudge* the user toward something that is reliably
stored server-side — never as the mechanism that delivers a state change or data.
Anything critical must be retrievable when the user opens the app, push or no push.

**Manage the token lifecycle.** Ask permission at a moment of demonstrated value (not
cold launch), register the token to the user, and handle rotation and revocation so the
backend only holds live tokens. The pipeline is only as good as the token you're
sending to.

**Make notifications actionable and state-aware.** A notification is an entry point:
tapping it deep-links to the relevant screen (Chapter 02), and handling differs by app
state (foreground/background/killed). A push that opens a generic home screen wastes the
tap.

**Notifications are a budget — spend it sparingly and give control.** Every send costs
attention and trust; default to fewer, high-signal, transactional notifications, offer
granular user controls, and respect denials. This is a product decision that lives in
engineering, and it's the difference between a kept channel and an uninstall.

A working definition:

> **A push notification travels best-effort through infrastructure you don't own
> (Expo → APNs/FCM) to a user who can revoke it — so never depend on delivery, manage
> the token lifecycle (ask in context, register, handle rotation/revocation), make every
> notification actionable and deep-linked with state-aware tap handling, and treat sends
> as a budget: fewer, higher-signal, user-controlled. Sending is easy; deciding what's
> worth sending is the engineering judgment.**

## Production Example

**Invoicely** has a clear, high-value push use case and an obvious way to abuse it. The
valuable, transactional notifications: "Invoice #42 was paid" (the freelancer wants to
know immediately), "Payment failed for invoice #17," "Invoice #9 is now overdue." The
abuse waiting to happen: "Haven't invoiced in a while — come back!", "Check out our new
feature!", daily "tips." The first set users keep enabled; the second set gets
notifications turned off.

The engineering: when the Stage 3 backend records a payment (via the Stripe webhook,
Stage 3 background jobs), it sends a push to the invoice's owner — through Expo's push
service, to the token registered for that user. Tapping "Invoice #42 was paid" deep-links
straight to `/invoices/42` (Chapter 02), whether the app was backgrounded or killed. The
app asks for notification permission not on first launch but *after the user creates their
first invoice* — a moment where the value of "we'll tell you when it's paid" is obvious.
Users get granular controls (paid / failed / overdue, each toggleable) in Settings, and a
denied permission is respected, not re-nagged.

In this chapter we build that: permission requested in context, token registration and
rotation handling, the backend send through Expo's push API keyed to the user, deep-linked
tap handling across app states, and user-facing notification preferences. We contrast it
with the assistant-default version (permission on launch, no token rotation, delivery
assumed reliable, tap opens home, no budget) that mismanages every hard part.

## Folder Structure

```
mobile/src/features/notifications/
├── permissions.ts        # request permission IN CONTEXT (after value shown), not on launch
├── registerToken.ts      # get the push token; register/update it on the backend; handle rotation
├── handlers.ts           # foreground/background/killed tap handling → deep link (Chapter 02)
└── preferences.ts        # user-facing granular controls (paid/failed/overdue toggles)

api/ (Stage 3 backend)
└── app/notifications/
    ├── send.py           # send via Expo Push API to a user's registered tokens
    ├── tokens.py         # store/prune device tokens per user (rotation, revocation)
    └── events.py         # which domain events trigger which notification (the budget lives here)
```

Why this shape: the mobile side separates the four concerns that each get mishandled —
permission timing, token lifecycle, tap handling, and user preferences — into distinct
files so none is an afterthought. The backend side is where the *budget* is enforced:
`events.py` is the single place that decides which domain events are worth a notification,
so the "should we even send this?" decision is centralized and reviewable rather than
scattered across the codebase. `tokens.py` owns rotation and pruning so the backend never
sends to dead tokens. The structure encodes the chapter's claim that the hard parts are
lifecycle and product discipline, not the send call.

## Implementation

**Request permission in context (`permissions.ts`).** The one-shot prompt, asked after
the user has seen why it's useful — not on cold launch. This single timing decision
determines whether you keep the channel.

```ts
import * as Notifications from "expo-notifications";

// Call this AFTER a value moment (e.g., first invoice created), never on app launch.
export async function requestNotificationPermission(): Promise<boolean> {
  const existing = await Notifications.getPermissionsAsync();
  if (existing.status === "granted") return true;
  if (!existing.canAskAgain) return false;          // already denied — respect it, don't nag
  const { status } = await Notifications.requestPermissionsAsync();
  return status === "granted";
}
```

**Register and rotate the token (`registerToken.ts`).** Get the device push token,
register it against the user, and re-register when it rotates — so the backend only ever
holds live tokens.

```ts
import * as Notifications from "expo-notifications";
import { apiFetch } from "@/lib/apiClient";

export async function registerPushToken() {
  const { data: token } = await Notifications.getExpoPushTokenAsync();
  await apiFetch("/notifications/tokens", { method: "POST", body: JSON.stringify({ token }) });

  // Tokens ROTATE (reinstall/restore/OS events) — keep the backend copy current.
  return Notifications.addPushTokenListener(({ data: newToken }) => {
    apiFetch("/notifications/tokens", { method: "POST", body: JSON.stringify({ token: newToken }) });
  });
}
```

**State-aware, deep-linked tap handling (`handlers.ts`).** A notification is an entry
point. Tapping it routes to the relevant screen via the router (Chapter 02) — the same
mechanism whether the app was backgrounded or cold-started.

```ts
import * as Notifications from "expo-notifications";
import { router } from "expo-router";

export function registerNotificationHandlers() {
  // Foreground: how a notification is shown while the app is open.
  Notifications.setNotificationHandler({
    handleNotification: async () => ({ shouldShowBanner: true, shouldPlaySound: false }),
  });

  // Tapped from background OR killed: deep-link to the target screen (Chapter 02).
  return Notifications.addNotificationResponseReceivedListener((response) => {
    const { screen } = response.notification.request.content.data as { screen?: string };
    if (screen) router.push(screen);            // e.g. "/invoices/42"
  });
}
```

**The backend send, keyed to the user (`send.py`).** Triggered by a real domain event
(a payment recorded), sent through Expo's push service to the user's live tokens, with
the deep-link target in the payload. Delivery is best-effort — the payment is already
persisted regardless.

```python
# api/app/notifications/send.py
import httpx

async def notify_invoice_paid(user_id: int, invoice_id: int) -> None:
    tokens = await get_live_tokens(user_id)          # only current, non-revoked tokens
    if not tokens:
        return                                        # no channel — fine; the data is still in-app
    messages = [{
        "to": token,
        "title": "Invoice paid",
        "body": f"Invoice #{invoice_id} was paid.",
        "data": {"screen": f"/invoices/{invoice_id}"},   # deep-link target (Chapter 02)
    } for token in tokens]
    async with httpx.AsyncClient() as client:
        resp = await client.post("https://exp.host/--/api/v2/push/send", json=messages)
    await prune_invalid_tokens(resp.json())          # APNs/FCM report dead tokens → prune them
```

**The budget, centralized (`events.py`).** One place decides what's worth sending —
transactional events yes, engagement nags no — and respects per-user preferences.

```python
# api/app/notifications/events.py — the notification BUDGET lives here, reviewable in one place
NOTIFIABLE_EVENTS = {
    "invoice.paid":    {"pref": "paid",    "transactional": True},
    "invoice.failed":  {"pref": "failed",  "transactional": True},
    "invoice.overdue": {"pref": "overdue", "transactional": True},
    # NOT here: "come back!", "new feature!", daily tips — engagement spam is excluded by design.
}
```

**The anti-patterns — the assistant defaults.**

```ts
// ANTI-PATTERN: mismanaging every hard part while nailing the easy "send"
async function setupPushBad() {
  await Notifications.requestPermissionsAsync();     // 1) asked ON LAUNCH → user denies → channel lost
  const { data } = await Notifications.getExpoPushTokenAsync();
  saveTokenOnce(data);                                // 2) no rotation handling → token goes stale
  // 3) delivery assumed reliable: the app relies on the push arriving to update state
  // 4) no tap handler → tapping opens the home screen, not the invoice (wasted tap)
  // 5) no budget: backend also fires "come back!" nags → users disable notifications
}
```

The difference is the whole chapter: the good version asks in context, manages token
rotation and pruning, treats delivery as best-effort, deep-links taps by app state, and
enforces a notification budget. The bad version nails the trivial send call and botches
permission timing, token lifecycle, reliability assumptions, tap handling, and product
discipline — the parts that actually determine whether push helps or gets the app
uninstalled.

## Engineering Decisions

Five decisions define push.

### When do you request notification permission?

**Options:** (1) on first app launch; (2) in context after a value moment; (3) with a
pre-permission priming screen, then the system prompt.

**Trade-offs:** asking on launch maximizes how many users *see* the prompt and minimizes
how many accept — the value isn't established, so denials are high, and iOS won't re-ask.
Asking in context (after creating an invoice: "we'll notify you when it's paid") lands
when the value is obvious, raising acceptance. A priming screen first (a soft, dismissible
ask before the real one) lets you gauge interest without burning the one-shot on a likely
"no."

**Recommendation:** ask in context at a demonstrated value moment, optionally behind a
priming screen so you only spend the system one-shot on users likely to accept. Never ask
on cold launch. The timing of this single prompt is the highest-leverage push decision.

### Can the app depend on a notification arriving?

**Options:** (1) treat push as reliable delivery; (2) treat push as a best-effort nudge
over server-persisted state.

**Trade-offs:** treating push as reliable is simple and wrong — APNs/FCM drop, delay, and
coalesce, so anything depending on arrival will intermittently fail (the state never
updates, the data never shows). Treating it as a nudge means the real state always lives
server-side and the app fetches it on open; push just prompts the user, at the cost of not
being able to "deliver" via push.

**Recommendation:** always treat push as a best-effort nudge; the source of truth is
server-side and retrievable when the app opens (Chapter 04's sync). Never make correctness
depend on a notification arriving. Push tells the user to look; it doesn't deliver.

### How is the token lifecycle managed?

**Options:** (1) register once, never update; (2) register and handle rotation/revocation
and prune dead tokens.

**Trade-offs:** register-once is easy and steadily degrades — tokens rotate on reinstall/
restore and revoke on permission loss, so the backend accumulates dead tokens (wasted
sends) and misses users whose token changed. Full lifecycle management (listen for
rotation, prune on APNs/FCM "invalid token" responses) keeps the token set live at the
cost of the plumbing.

**Recommendation:** manage the full lifecycle — register per user, update on rotation,
prune on revocation/invalid-token responses. Send only to live tokens. A push system is
only as reliable as its token hygiene.

### What happens when a notification is tapped, per app state?

**Options:** (1) always open the home screen; (2) deep-link to the relevant screen,
handling foreground/background/killed.

**Trade-offs:** always-home is trivial and wastes every tap — the user tapped *because* of
the specific event and lands nowhere useful. Deep-linking to the relevant screen honors the
intent but requires handling all three app states (foreground: show in-app; background: open
+ route; killed: cold-start + route) via the router (Chapter 02).

**Recommendation:** deep-link every tappable notification to its relevant screen, handling
all app states through Expo Router (Chapter 02). A notification is an entry point; opening
the home screen throws away the tap.

### What is the notification budget and who controls it?

**Options:** (1) send freely (transactional + marketing + engagement); (2) transactional-
only by default with granular user controls; (3) no notifications.

**Trade-offs:** sending freely maximizes short-term reach and steadily erodes trust until
users disable notifications or uninstall — the classic over-notification death spiral.
Transactional-only with user controls sends fewer, higher-signal notifications users keep
enabled, at the cost of resisting the urge to use push for growth. No notifications forgoes a
valuable channel.

**Recommendation:** default to transactional, high-signal notifications, give users granular
per-type controls, respect denials, and centralize the "is this worth sending?" decision in
one reviewable place. Treat sends as a depletable budget — the restraint is the strategy.

## Trade-offs

Push trades real lifecycle and product work for a channel that reaches users when nothing
else can — and abusing it trades long-term trust for short-term reach.

**Push reach trades reliability for the ability to re-engage.** It's the only way to reach a
user with the app closed, and it's best-effort — delayed, coalesced, droppable. You gain a
unique channel and you must never depend on it for correctness. That constraint (server-side
source of truth, push as a nudge) is the price of the reach.

**In-context permission trades some reach for far higher acceptance.** Asking at a value
moment (or behind a priming screen) means fewer users see the prompt immediately and far more
accept — and because iOS gives one shot, acceptance is what matters. You trade prompt volume
for a channel you actually keep.

**Token lifecycle management trades plumbing for a working pipeline.** Handling rotation,
revocation, and pruning is unglamorous code, and without it the pipeline silently rots —
dead tokens, missed users. The plumbing is the difference between a push system that works
and one that appears to.

**Restraint trades short-term reach for long-term retention.** Sending fewer, transactional
notifications forgoes the easy engagement pings and keeps users from disabling the channel or
uninstalling. Over-notifying is a loan against trust that comes due as churn; restraint is the
higher-return strategy.

## Common Mistakes

**Asking for permission on launch.** Burning the one-shot before showing value, so users deny
and the channel is lost. Fix: ask in context at a value moment, optionally behind a priming
screen.

**Depending on delivery.** Relying on a push to update state or deliver data over best-effort
infra. Fix: keep the source of truth server-side; push is a nudge, fetch on open.

**Ignoring token rotation.** Registering once and sending to stale tokens forever. Fix: handle
rotation/revocation and prune dead tokens on invalid-token responses.

**Tap opens the home screen.** Wasting the tap by not deep-linking to the relevant context.
Fix: deep-link every notification via the router, handling all app states (Chapter 02).

**Over-notifying.** Transactional plus marketing plus engagement nags, training users to
disable notifications. Fix: transactional-only default, granular controls, centralized send
decision.

**No user controls / ignoring denials.** No per-type toggles, or re-nagging after a denial.
Fix: granular preferences and respect for `canAskAgain === false`.

## AI Mistakes

Assistants implement the easy 20% of push (the send call) and skip the 80% that determines
whether it helps — permission timing, token lifecycle, reliability, tap handling, and the
budget. Review generated push code for everything *except* the send.

### Claude Code: requesting permission on app launch

Asked to "set up push notifications," Claude Code calls `requestPermissionsAsync()` during app
initialization — the obvious place structurally, and the worst place strategically. On iOS the
user sees the prompt with no context, denies, and the one-shot is gone.

**Detect:** `requestPermissionsAsync()` in an app-init/`_layout`/mount path; permission asked
before any value is shown; no priming or in-context trigger; no `canAskAgain` check.

**Fix:** require in-context timing:

> Do not request notification permission on launch. Trigger it after a value moment (e.g.,
> after the first invoice is created) — ideally behind a brief priming screen — and respect a
> prior denial (`canAskAgain === false`). iOS effectively gives one prompt; spend it when the
> user is likely to accept.

### GPT: treating delivery as reliable and ignoring token rotation

GPT-family models wire the send and register the token once, implicitly assuming push is a
reliable message bus — so the app leans on the notification arriving to update state, and the
backend keeps sending to a token that has since rotated. Both fail intermittently and
invisibly.

**Detect:** app logic that depends on a push arriving (state only updates via the notification);
a token registered once with no rotation listener; a backend with no dead-token pruning; no
"fetch on open" fallback for the state the push refers to.

**Fix:** require best-effort semantics and lifecycle:

> Treat push as best-effort — the source of truth is server-side and fetched when the app opens;
> never depend on a notification arriving. Handle token rotation (`addPushTokenListener`) and
> prune tokens the push service reports as invalid, so the backend only sends to live tokens.

### Cursor: tap handling that ignores app state and deep linking

Editing the notification setup in isolation, Cursor implements a tap handler that (at best)
opens the app, without deep-linking to the relevant screen or handling the killed/background/
foreground distinction — so tapping "Invoice #42 was paid" lands on the home screen.

**Detect:** a notification-response handler with no `router.push` to a target screen; no data
payload carrying the deep-link target; no handling of the cold-start (app killed) case; taps
that open the home screen.

**Fix:** require deep-linked, state-aware handling:

> Tapping a notification must deep-link to its relevant screen via Expo Router, handling all app
> states: foreground (show in-app), background (open + route), and killed (cold-start + route).
> Carry the target route in the notification `data` payload and route to it on tap — never leave
> the user on the home screen.

## Best Practices

**Ask for permission in context, once, and respect the answer.** Trigger the prompt at a
demonstrated value moment (optionally behind a priming screen), never on launch, and never
re-nag after a denial. The timing decides whether you keep the channel.

**Treat push as a best-effort nudge.** Keep the source of truth server-side and fetch it on
open (Chapter 04); never make correctness depend on a notification arriving. Push tells the user
to look.

**Manage the token lifecycle end to end.** Register per user, handle rotation/revocation, and
prune tokens the push service reports invalid. Send only to live tokens.

**Make every notification actionable and deep-linked.** Carry the target route in the payload and
route to it on tap across all app states (Chapter 02). A notification is an entry point, not a
buzz.

**Spend the notification budget sparingly and give control.** Default to transactional,
high-signal notifications; centralize the send decision; offer granular per-type controls;
resist using push for growth. Document the notification policy and lifecycle in the mobile
`CLAUDE.md`.

## Anti-Patterns

**The Launch Prompt.** Requesting permission on cold start, before value, burning the one-shot.
The tell: `requestPermissionsAsync()` in app init.

**The Reliable-Delivery Assumption.** App logic that depends on a push arriving to update state.
The tell: state that only changes when the notification is received, with no fetch-on-open.

**The Stale Token.** Register-once with no rotation handling or dead-token pruning. The tell: a
backend token table that only grows and is never validated.

**The Dead-End Tap.** A notification that opens the home screen instead of its relevant context.
The tell: no `router.push` target in the tap handler.

**The Notification Firehose.** Transactional plus marketing plus engagement nags with no user
controls. The tell: "come back!" pushes and no per-type toggles — followed by users disabling
notifications.

## Decision Tree

"I'm adding a push notification — how do I make it valuable rather than an uninstall trigger?"

```
Requesting permission?
├── On launch ──► NO. You'll burn the one-shot. 
└── At a value moment (after showing why) ──► yes, optionally behind a priming screen.
     Already denied (canAskAgain false)? ──► respect it; don't nag.

Does anything depend on this notification ARRIVING?
├── YES ──► redesign. Push is best-effort. Put the source of truth server-side; fetch on open.
└── NO (it's a nudge) ──► good.

Sending to a device?
└──► send only to LIVE tokens. Handle rotation (listener) + prune invalid tokens from responses.

What happens on tap?
└──► deep-link to the relevant screen (Ch 02), handling foreground / background / killed.
     Never open the home screen for an event-specific notification.

Is this notification worth sending?
├── Transactional / time-sensitive (paid, failed, overdue) ──► yes; honor the user's per-type prefs.
└── Marketing / engagement nag ──► default NO. It spends trust you won't get back.

Give users granular controls and a global off. Respect them.
```

## Checklist

### Implementation Checklist

- [ ] Permission is requested in context at a value moment (optionally primed), never on launch; denials are respected.
- [ ] The push token is registered per user, updated on rotation, and pruned on revocation/invalid-token responses.
- [ ] The app never depends on a notification arriving; the source of truth is server-side and fetched on open.
- [ ] Tapping a notification deep-links to its relevant screen across foreground/background/killed states.
- [ ] Sends go through Expo's push service and carry a deep-link target in the payload.
- [ ] Users have granular per-type notification controls and a global toggle.

### Architecture Checklist

- [ ] Permission timing, token lifecycle, tap handling, and preferences are distinct, deliberate concerns.
- [ ] The "is this worth sending?" decision is centralized in one reviewable place (the budget).
- [ ] Notifications are transactional/high-signal by default; engagement spam is excluded by design.
- [ ] Push integrates with deep linking (Chapter 02) and the server-side source of truth (Chapter 04).
- [ ] Notification policy and token lifecycle are documented in the mobile `CLAUDE.md`.

### Code Review Checklist

- [ ] No permission request on launch (watch AI diffs).
- [ ] No app logic that depends on a notification being delivered.
- [ ] No register-once token handling without rotation/pruning.
- [ ] No tap handler that opens the home screen instead of deep-linking.
- [ ] No marketing/engagement notifications slipping past the transactional-by-default policy.

### Deployment Checklist

- [ ] APNs keys/certificates and FCM credentials are configured for the build (via EAS credentials, Chapter 07).
- [ ] The push-token registration endpoint and dead-token pruning are live on the backend.
- [ ] Deep-link targets in notification payloads are verified end-to-end from a real push.

## Exercises

**1. Time the permission ask.** Implement notification permission requested after the user
creates their first invoice (with a one-line priming rationale), not on launch. Then, in a second
build, ask on launch and compare acceptance in a small test. The artifact is both flows and a note
on why timing changes acceptance.

**2. Deep-link a real notification.** Wire the backend to send "Invoice #N was paid" with a
`/invoices/N` deep-link target, and handle the tap from background and from a cold start so it
lands on the right screen. The artifact is a real push that opens the correct invoice from a killed
app.

**3. Design the budget.** Write Invoicely's notification policy: which events are notifiable, which
are deliberately excluded, and the per-type user controls. Implement the granular preferences and
the centralized send decision. The artifact is the written policy plus the preferences UI and the
`events` gate.

## Further Reading

- **Expo — "Notifications" (overview, push notifications, receiving/handling)** (docs.expo.dev) —
  the authoritative guide to permissions, tokens, sending via Expo's push service, and handling
  taps; the API this chapter is built on.
- **Apple — "Human Interface Guidelines: Managing Notifications" and "UserNotifications"**
  (developer.apple.com) — Apple's guidance on notification quality, permission timing, and the
  one-shot prompt; the product-discipline half of this chapter.
- **Firebase Cloud Messaging documentation** (firebase.google.com/docs/cloud-messaging) — the
  Android delivery layer under Expo's push service, including best-effort delivery semantics and
  token management.
- **"The Right Way to Ask Users for iOS Permissions" (and similar permission-priming research)** —
  the empirical case for in-context, primed permission requests over cold-launch prompts; the basis
  for the timing recommendation.
</content>

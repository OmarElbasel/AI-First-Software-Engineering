# Offline Support & Data Sync

## Introduction

A web app can mostly assume the network is there; a mobile app cannot. Phones go
into tunnels, elevators, and airplane mode; they hop between Wi-Fi and cellular
mid-request; they sit for hours with the app suspended and no connection at all.
An app that shows a spinner or an error the moment connectivity drops feels broken
in exactly the situations mobile is most used. This chapter is about building an
app that keeps working when the network doesn't — reading cached data offline,
accepting writes offline, and reconciling everything with the server when the
connection returns.

The single most important idea: **offline support is a spectrum, not a switch, and
most apps need the middle of it — not the extremes.** At one end is "online-only"
(fail without a network); at the other is "fully offline-first" (a local database
is the source of truth and the server is a sync peer). The extreme offline-first
architecture is powerful and *expensive* — conflict resolution, sync engines, and
a mental model most features don't need. The pragmatic middle — **cache reads so
the app is usable offline, and queue writes so actions aren't lost** — delivers the
experience users actually want at a fraction of the cost. Choosing the right point
on that spectrum, per app and even per screen, is the core judgment here.

The second idea: **the hard part of offline is not storing data; it's
reconciliation.** Reading from a cache is easy. The difficulty is what happens when
the user changed something offline and the server also changed — conflicts,
ordering, retries, and the "optimistic UI now, real result later" gap. A serious
offline story is mostly a *sync* story: an outbox of pending writes, idempotent
operations so retries are safe, a conflict policy, and honest UI about what's
confirmed versus pending. Get storage right and reconciliation wrong, and you
corrupt data or silently lose the user's work — worse than being online-only.

## Why It Matters

Offline behavior is where mobile apps are judged, because the failure modes are
both common and severe:

- **Connectivity is intermittent by default.** Unlike a desktop on Ethernet, a
  phone constantly loses and regains the network. "Handle the offline case" isn't
  an edge case on mobile — it's a routine state the app passes through many times a
  session.
- **A spinner-on-drop app feels broken.** If reads aren't cached, every network dip
  blanks the screen; if writes aren't queued, tapping "send reminder" on the subway
  either errors or, worse, *appears* to work and silently does nothing. Users
  experience both as the app being unreliable.
- **Lost writes are the worst outcome.** A user who creates an invoice offline and
  sees it "saved," only for it to vanish because it was never queued, has lost work
  and trust. Silently dropping an offline write is more damaging than refusing it
  outright.
- **Reconciliation bugs corrupt data.** When offline edits meet server changes, a
  naive "last write wins" can clobber someone else's update; a non-idempotent write
  retried after a flaky connection can create duplicates (two invoices, two
  charges). These are data-integrity bugs, not UI glitches.
- **Optimistic UI can lie.** Showing a write as done before the server confirms
  feels fast — and is a lie if the write later fails and the UI never rolls back.
  The gap between "shown as done" and "actually done" has to be managed honestly.

Get it right — cached reads, a durable write outbox, idempotent operations, a clear
conflict policy, and UI that distinguishes pending from confirmed — and the app
stays usable and trustworthy through tunnels and airplane mode, syncing cleanly when
the network returns. Get it wrong and you either block users whenever the signal
dips or, worse, lose and corrupt their data while telling them everything's fine.

The AI dimension: assistants treat the network as reliable (the web default), so
they skip caching, fire writes with no offline queue, add optimistic UI with no
rollback, and never make writes idempotent — producing an app that works flawlessly
on the office Wi-Fi in the demo and loses data in the field. And they tend to
over-correct when asked for "offline," reaching for a full offline-first database the
app doesn't need.

## Mental Model

A spectrum to place yourself on, then a read path, a write path, and a sync loop:

```
   THE OFFLINE SPECTRUM  (pick per app / per screen)
     online-only ──── cached reads ──── queued writes ──── FULL offline-first
     (fail on drop)   (usable offline)  (actions survive)   (local DB is source of truth)
                      └──────────── the pragmatic middle most apps want ───────────┘
                                                              ↑ expensive: sync engine + conflicts

   READ PATH (offline-usable):
     screen ──► cache first (instant) ──► revalidate from network when online
                (React Query persisted cache / local store)   stale-while-revalidate

   WRITE PATH (durable, never lost):
     user action ──► OPTIMISTIC UI (show as pending) ──► enqueue in a persistent OUTBOX
                                                             │
                     (offline: it just waits in the outbox)  │
                                                             ▼
   SYNC LOOP (on reconnect — detect via NetInfo):
     drain outbox in order ──► each write IDEMPOTENT (safe to retry) ──►
       success ──► mark confirmed        conflict ──► apply CONFLICT POLICY
       failure ──► retry w/ backoff       (last-write-wins / merge / ask the user)

   UI HONESTY:  pending ≠ confirmed. Show the difference. Roll back on real failure.
```

Four principles carry the chapter:

**Place yourself on the spectrum deliberately.** Decide, per app and often per
screen, how much offline you need: online-only where it's genuinely fine, cached
reads for browsing, queued writes for actions, full offline-first only where the
product truly requires it. Don't default to the most powerful (and most expensive)
architecture; match the investment to the need.

**Cache reads, queue writes.** The pragmatic core: persist read data so screens
render offline (stale-while-revalidate when back online), and put writes in a
durable outbox so an action taken offline is never lost. This middle covers the vast
majority of real offline needs.

**Make writes idempotent, and sync is safe.** Give each write a client-generated id
(or idempotency key) so replaying it after a flaky connection doesn't duplicate it.
Idempotency is what turns "retry on reconnect" from a duplication bug into a safe
operation — the client-side echo of the backend idempotency from Stage 3.

**Reconciliation is the real work; be honest in the UI.** Have an explicit conflict
policy (last-write-wins, merge, or ask), retry with backoff, and make the UI
distinguish pending from confirmed and roll back on genuine failure. Optimistic UI
without rollback is a lie.

A working definition:

> **Offline support is a spectrum; most apps want the pragmatic middle — cache reads
> so screens work offline, queue writes in a durable outbox so actions are never
> lost, make writes idempotent so reconnect retries are safe, apply an explicit
> conflict policy, and keep the UI honest about pending versus confirmed. The hard
> part is reconciliation (sync), not storage; reserve full offline-first for apps
> that genuinely need it.**

## Production Example

**Invoicely mobile** is used exactly where connectivity is unreliable — a contractor
on a job site, a freelancer on a train. Two flows drive the offline design. First,
**browsing**: opening the app in a dead zone should still show the invoice list and
recent details from cache, not a blank screen. Second, **acting**: creating an
invoice or marking one paid while offline should *appear* to work immediately, be
stored durably, and actually reach the server when the signal returns — never lost,
never duplicated.

Invoicely lands in the pragmatic middle of the spectrum: cached reads (React Query's
persisted cache) so the list and details are available offline, and a durable write
outbox so "create invoice" and "mark paid" survive being offline. Writes carry a
client-generated id so retrying after a flaky reconnect doesn't create two invoices
(idempotency, matching the Stage 3 backend). Conflicts — the invoice was edited on
the web while the phone was offline — resolve with a defined policy rather than a
silent clobber. The UI shows a pending invoice with a subtle "syncing" state until
the server confirms.

In this chapter we build that: NetInfo-based connectivity detection, a persisted
read cache, a durable outbox with idempotent writes, a sync loop that drains the
outbox on reconnect with backoff, and optimistic UI with rollback. We contrast it
with the assistant-default version (fire-and-forget writes, no cache, optimistic UI
that never rolls back) and with the over-engineered version (a full offline-first DB
for an app that doesn't need one).

## Folder Structure

```
mobile/src/
├── lib/
│   ├── network.ts            # NetInfo wrapper: isOnline, subscribe to changes
│   ├── queryPersist.ts       # persist the React Query cache (offline reads)
│   └── db.ts                 # local store for the outbox (SQLite / MMKV / AsyncStorage)
├── features/sync/
│   ├── outbox.ts             # durable queue of pending writes (enqueue, list, remove)
│   ├── syncEngine.ts         # drains the outbox on reconnect; retry + backoff + conflicts
│   └── idempotency.ts        # client-generated ids / idempotency keys for writes
└── features/invoices/
    ├── mutations.ts          # optimistic mutations that enqueue to the outbox
    └── api.ts                # network calls (carry the idempotency key)
```

Why this shape: offline concerns are isolated in `lib/` (connectivity, cache
persistence, local storage) and a dedicated `features/sync/` module (the outbox and
the sync engine), so the offline machinery lives in one place rather than smeared
through every feature. Individual features (`invoices/mutations.ts`) opt into it by
enqueuing to the outbox instead of calling the API directly. This keeps the read
cache, the write outbox, and the sync loop as distinct, testable pieces — the three
parts of the mental model made into modules.

## Implementation

**Connectivity detection (`network.ts`).** The sync loop needs to know when the
network returns. `@react-native-community/netinfo` reports reachability and notifies
on change — the trigger for draining the outbox.

```ts
import NetInfo from "@react-native-community/netinfo";

export function subscribeToConnectivity(onChange: (online: boolean) => void) {
  return NetInfo.addEventListener((state) => {
    onChange(Boolean(state.isConnected && state.isInternetReachable));
  });
}

export async function isOnline() {
  const s = await NetInfo.fetch();
  return Boolean(s.isConnected && s.isInternetReachable);
}
```

**Persisted read cache (`queryPersist.ts`).** Persisting React Query's cache to disk
makes reads available offline: the screen renders cached data instantly, then
revalidates when online (stale-while-revalidate — the Stage 4, Chapter 04 discipline,
now surviving app restarts).

```ts
import { persistQueryClient } from "@tanstack/react-query-persist-client";
import { createAsyncStoragePersister } from "@tanstack/query-async-storage-persister";
import AsyncStorage from "@react-native-async-storage/async-storage";

// Read cache may use AsyncStorage — it's NOT sensitive (tokens go in SecureStore, Ch 03).
export function enableOfflineCache(queryClient: QueryClient) {
  persistQueryClient({
    queryClient,
    persister: createAsyncStoragePersister({ storage: AsyncStorage }),
    maxAge: 1000 * 60 * 60 * 24,   // keep cached reads usable for 24h offline
  });
}
```

**A durable, idempotent outbox (`outbox.ts` + `idempotency.ts`).** Writes go here,
not straight to the network. Each carries a client-generated id so a retry after a
flaky reconnect is the *same* operation, not a new one — no duplicate invoices.

```ts
// idempotency.ts
import * as Crypto from "expo-crypto";
export const newIdempotencyKey = () => Crypto.randomUUID();   // client-generated, stable across retries

// outbox.ts
import { db } from "@/lib/db";

export type PendingWrite = {
  id: string;               // idempotency key — SAME across retries
  op: "createInvoice" | "markPaid";
  payload: unknown;
  createdAt: number;
};

export const outbox = {
  async enqueue(write: PendingWrite) { await db.insert("outbox", write); },   // durable: survives kill
  async all(): Promise<PendingWrite[]> { return db.selectAll("outbox", { orderBy: "createdAt" }); },
  async remove(id: string) { await db.delete("outbox", id); },
};
```

**An optimistic mutation that enqueues (`mutations.ts`).** The user sees the result
immediately (optimistic), the write is stored durably, and it syncs later — offline or
online. Crucially, the optimistic update has a **rollback** path if the write
ultimately fails.

```ts
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { outbox, newIdempotencyKey } from "@/features/sync";

export function useCreateInvoice() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (draft: InvoiceDraft) => {
      const write = { id: newIdempotencyKey(), op: "createInvoice", payload: draft, createdAt: Date.now() };
      await outbox.enqueue(write);      // DURABLE first — never lost, even offline
      return write;
    },
    onMutate: async (draft) => {        // OPTIMISTIC: show it as pending immediately
      await qc.cancelQueries({ queryKey: ["invoices"] });
      const prev = qc.getQueryData(["invoices"]);
      qc.setQueryData(["invoices"], (old: Invoice[] = []) => [...old, { ...draft, pending: true }]);
      return { prev };                  // snapshot for ROLLBACK
    },
    onError: (_e, _draft, ctx) => { qc.setQueryData(["invoices"], ctx?.prev); },  // roll back the lie
  });
}
```

**The sync loop (`syncEngine.ts`).** On reconnect, drain the outbox in order; each
write is idempotent so retries are safe; failures back off; conflicts apply a policy.

```ts
import { outbox } from "./outbox";
import { subscribeToConnectivity } from "@/lib/network";
import { sendWrite } from "@/features/invoices/api";

export function startSyncEngine() {
  return subscribeToConnectivity(async (online) => {
    if (!online) return;                          // offline: writes just wait in the outbox
    for (const write of await outbox.all()) {     // in order
      try {
        await sendWrite(write);                   // carries write.id → backend dedupes (idempotent)
        await outbox.remove(write.id);            // confirmed → drop from outbox
      } catch (err) {
        if (isConflict(err)) await resolveConflict(write, err);   // explicit policy, not a silent clobber
        else break;                               // transient: stop, retry on next reconnect (backoff)
      }
    }
  });
}
```

**The anti-patterns — the assistant defaults.**

```ts
// ANTI-PATTERN: online-assuming, data-losing writes
async function createInvoiceBad(draft) {
  setInvoices((prev) => [...prev, draft]);   // optimistic — but NO rollback if it fails (a lie)
  await fetch("/invoices", { method: "POST", body: JSON.stringify(draft) });
  // offline? this throws and the write is LOST — never queued, never retried
  // flaky reconnect + user retap? NO idempotency key → TWO invoices created
}
// ...and no read cache: every network dip blanks the list.
```

The difference is the whole chapter: the good version caches reads (usable offline),
enqueues writes durably (never lost), makes them idempotent (never duplicated), syncs
on reconnect with a conflict policy, and rolls back optimistic UI on real failure. The
bad version assumes the network, loses writes when offline, duplicates them on retry,
and shows optimistic UI that lies when the write fails — all invisible on office Wi-Fi
and catastrophic in a tunnel.

## Engineering Decisions

Five decisions define the offline story.

### Where on the offline spectrum does this app (or screen) sit?

**Options:** (1) online-only; (2) cached reads; (3) cached reads + queued writes; (4)
full offline-first (local DB as source of truth).

**Trade-offs:** online-only is simplest and fails on every network dip. Cached reads
make browsing work offline cheaply. Queued writes add durability for actions at the
cost of an outbox and sync loop. Full offline-first makes the app fully functional
offline but demands a sync engine, conflict resolution, and a local-first data model —
a large, ongoing investment most features don't justify.

**Recommendation:** default to the pragmatic middle — cached reads plus queued writes —
and choose per screen (a settings page can be online-only; the invoice list should be
cached). Reserve full offline-first for apps whose core value *is* working offline
(field tools, note-takers). Don't buy the expensive architecture by reflex.

### How are offline reads served?

**Options:** (1) no cache (spinner/blank on drop); (2) in-memory cache (lost on kill);
(3) a persisted cache (React Query persist / local store).

**Trade-offs:** no cache blanks the screen whenever the signal dips. An in-memory cache
helps within a session but is gone after an OS kill — so a cold start offline shows
nothing. A persisted cache survives kills and serves stale-while-revalidate at the cost
of managing persistence and staleness.

**Recommendation:** persist the read cache (React Query's persisted client, or a local
store) so screens render offline even after a cold start, revalidating when online. Tune
`maxAge`/`staleTime` per data type as in Stage 4, Chapter 04 — offline just raises the
stakes of getting caching right.

### How are offline writes handled?

**Options:** (1) fire-and-forget (lost when offline); (2) block writes when offline; (3)
a durable outbox synced on reconnect.

**Trade-offs:** fire-and-forget silently loses offline actions — the worst outcome.
Blocking writes offline is honest but hostile (the user can't do anything in a tunnel).
A durable outbox accepts the write, stores it through kills, and syncs later at the cost
of the outbox + sync machinery.

**Recommendation:** a durable outbox for any write the user expects to succeed —
persisted (survives an OS kill), drained on reconnect, with idempotent operations. Never
fire-and-forget a write that matters; never silently drop an offline action.

### How are writes made safe to retry (idempotency)?

**Options:** (1) no idempotency (retries duplicate); (2) client-generated ids /
idempotency keys; (3) server-side dedup only.

**Trade-offs:** without idempotency, a retry after a flaky reconnect creates duplicates —
two invoices, two "mark paid" events. A client-generated id sent with the write lets the
backend dedupe, making retries safe at the cost of generating and threading the key.
Server-side dedup alone still needs a client-provided key to dedupe *on*.

**Recommendation:** give every queued write a client-generated idempotency key and have
the backend dedupe on it (the Stage 3, Chapter 05 idempotency contract). This is what
makes the sync loop's retries safe. Without it, offline sync corrupts data.

### What is the conflict-resolution policy?

**Options:** (1) last-write-wins; (2) field-level merge; (3) ask the user; (4) pretend
conflicts don't happen.

**Trade-offs:** ignoring conflicts silently clobbers data. Last-write-wins is simple and
loses the other side's change. Merge preserves more but is complex and only valid for
data that merges cleanly. Asking the user is the most correct for high-stakes conflicts
and the most intrusive.

**Recommendation:** choose a policy *explicitly* per data type — last-write-wins for
low-stakes fields, merge where fields are independent, ask-the-user for high-stakes
conflicts (financial data). The wrong choice is having no policy and letting sync clobber
silently. Deep conflict-resolution strategies (CRDTs, vector clocks) are beyond this
chapter; the requirement here is an intentional policy.

## Trade-offs

Offline support trades real engineering effort for an app that works where mobile
actually gets used — and over-investing has its own cost.

**Offline capability trades complexity for field reliability.** Caching, an outbox,
idempotency, and sync are meaningfully more code than assuming the network, and they buy
an app that stays usable and trustworthy through tunnels and airplane mode. For an app
used on the move, the trade is clearly worth it; for one only ever used on stable Wi-Fi,
much of it is over-engineering.

**The pragmatic middle trades full-offline power for a fraction of the cost.**
Cached-reads-plus-queued-writes covers most real needs without a sync engine or a
local-first data model. You give up "fully functional offline for arbitrarily long" and
you avoid the largest, most bug-prone part of offline architecture. For most SaaS
companion apps, that's the right trade.

**Optimistic UI trades honesty risk for perceived speed.** Showing writes as done before
the server confirms feels instant and is a lie without rollback. You buy responsiveness
and you owe correct rollback-on-failure and honest pending/confirmed states. Worth it
when done fully; a trap when the rollback is skipped.

**Idempotency trades a little plumbing for safe retries.** Threading a client-generated
key through every write is minor work that converts the sync loop's retries from a
duplication hazard into a safe operation. It's cheap insurance against the worst offline
bug (duplicated financial actions).

## Common Mistakes

**Assuming the network is there.** No cache, no queue — the app breaks or loses data on
every drop. Fix: cache reads, queue writes; treat offline as a routine state.

**Fire-and-forget offline writes.** Actions taken offline are silently lost. Fix: a
durable outbox that survives kills and syncs on reconnect.

**No idempotency.** Retries after flaky reconnects create duplicate invoices/charges. Fix:
a client-generated idempotency key the backend dedupes on.

**Optimistic UI without rollback.** The UI shows a write as done that actually failed. Fix:
snapshot before the optimistic update and roll back on error; show pending vs confirmed.

**No conflict policy.** Offline edits silently clobber server changes on sync. Fix: an
explicit per-data-type policy (last-write-wins/merge/ask).

**Over-engineering with full offline-first.** Building a local-first DB and sync engine an
app doesn't need. Fix: place yourself on the spectrum; use the pragmatic middle unless the
product demands more.

## AI Mistakes

Assistants inherit the web's reliable-network assumption, so their code works online and
fails offline — usually by losing or duplicating data rather than erroring visibly. Review
generated data code for what happens with the network *off* and with a *flaky* reconnect.

### Claude Code: no offline handling at all (assumes the network)

Asked to implement a feature, Claude Code writes straight-through fetches with no cache and
no queue — the network is assumed present, as on the web. The feature works in the demo and
blanks the screen or throws the moment connectivity drops, and offline writes are lost.

**Detect:** mutations that call the API directly with no outbox; reads with no persisted
cache; no NetInfo/connectivity awareness; no handling of the offline branch anywhere.

**Fix:** require offline handling by design:

> This runs on mobile, where the network drops routinely. Serve reads from a persisted
> cache (usable offline) and route writes through a durable outbox that syncs on reconnect —
> never call the API directly for a write the user expects to succeed. Assume the network
> can be absent at any point.

### GPT: optimistic updates with no rollback

GPT-family models add optimistic UI (it looks responsive) but omit the rollback path, so a
write that later fails leaves the UI showing a success that didn't happen — a lie the user
acts on. It demos beautifully because the happy path always "succeeds."

**Detect:** `onMutate` optimistic cache updates with no `onError` rollback; no snapshot of
prior state; UI that never reverts a failed write; no distinction between pending and
confirmed.

**Fix:** require full optimistic handling:

> An optimistic update must snapshot the prior state and roll back on error, and the UI must
> distinguish pending from confirmed. Don't show a write as done unless it's confirmed —
> pending writes should render as pending until the server acknowledges them.

### Cursor: non-idempotent writes that duplicate on retry

Editing the write in isolation, Cursor implements the send without a client-generated
idempotency key, so when the sync loop (or the user) retries after a flaky connection, the
backend creates a second record — two invoices, two charges. The bug only appears under
retry, which the edit-site test never exercises.

**Detect:** writes with no client-generated id/idempotency key; a retry/sync path that can
replay a write; backend create calls that don't dedupe on a client key.

**Fix:** require idempotency:

> Every write that can be retried (offline sync, network flakiness) must carry a
> client-generated idempotency key, and the backend must dedupe on it so a retry is the same
> operation, not a new record. Generate the key when enqueuing the write and keep it stable
> across retries.

## Best Practices

**Place the app on the offline spectrum deliberately, per screen.** Online-only where fine,
cached reads for browsing, queued writes for actions, full offline-first only when the
product demands it. Match the investment to the need; don't reflexively build the most
powerful architecture.

**Cache reads and queue writes as the default.** Persist the read cache (usable offline
across kills, stale-while-revalidate online) and route writes through a durable outbox that
syncs on reconnect. This middle covers most real offline needs.

**Make every retryable write idempotent.** A client-generated key the backend dedupes on, so
reconnect retries never duplicate. The client-side match to the Stage 3 backend idempotency.

**Keep optimistic UI honest.** Snapshot before optimistic updates, roll back on real failure,
and show pending vs confirmed distinctly. Never let the UI claim a success that didn't happen.

**Have an explicit conflict policy and document the offline model.** Choose last-write-wins/
merge/ask per data type, and document the offline conventions (what's cached, the outbox,
idempotency, conflict policy) in the mobile `CLAUDE.md` so assistants stop assuming the
network.

## Anti-Patterns

**The Online-Only App.** No cache, no queue — breaks or loses data on every network dip. The
tell: direct fetches everywhere, no NetInfo, no outbox.

**The Lost Write.** Fire-and-forget writes that vanish when offline. The tell: a mutation that
calls the API directly with no durable queue.

**The Duplicating Retry.** Non-idempotent writes that create duplicates when the sync loop
retries. The tell: writes with no client-generated idempotency key.

**The Lying UI.** Optimistic updates with no rollback, showing successes that failed. The tell:
`onMutate` with no `onError` revert and no pending/confirmed distinction.

**The Silent Clobber.** Sync with no conflict policy, overwriting server changes with stale
offline edits. The tell: last-write-wins applied everywhere by default, with no per-data
decision.

**The Offline-First Overkill.** A full local-first DB and sync engine for an app that only
needed cached reads and a small outbox. The tell: CRDTs/sync-engine complexity with no product
requirement driving it.

## Decision Tree

"I'm building a data feature on mobile — how much offline does it need, and how do I make it
safe?"

```
How important is offline for THIS screen?
├── Not important (rare, low-stakes) ──► online-only is fine. Show a clear offline state.
├── Users browse it offline ──────────► persist the read cache (stale-while-revalidate).
├── Users ACT on it offline ──────────► cached reads + a durable OUTBOX for writes.
└── The product IS an offline tool ───► full offline-first (local DB as source of truth). Rare.

Handling an offline write?
└──► enqueue in a DURABLE outbox (survives kill) → sync on reconnect (NetInfo).
     Give it a client-generated IDEMPOTENCY KEY → backend dedupes → retries are safe.

Showing the write immediately (optimistic)?
└──► snapshot prior state → show as PENDING → roll back on real failure. Never a silent lie.

Offline edit meets a server change (conflict)?
└──► apply an EXPLICIT policy per data type: last-write-wins / merge / ask the user.
     Never let sync clobber silently.

NEVER: fire-and-forget offline writes · retryable writes without idempotency ·
       optimistic UI without rollback · full offline-first with no product need for it.
```

## Checklist

### Implementation Checklist

- [ ] Each screen's offline level is a deliberate choice on the spectrum (online-only → offline-first).
- [ ] Read data is served from a persisted cache that works offline across cold starts.
- [ ] Writes the user expects to succeed go through a durable outbox, not direct fetches.
- [ ] Every retryable write carries a client-generated idempotency key the backend dedupes on.
- [ ] Optimistic updates snapshot prior state, roll back on failure, and show pending vs confirmed.
- [ ] Connectivity is detected (NetInfo) and drives the sync loop with retry/backoff.

### Architecture Checklist

- [ ] Offline machinery (network, cache persistence, outbox, sync engine) is isolated in dedicated modules.
- [ ] An explicit conflict-resolution policy exists per data type — no silent clobbering.
- [ ] The offline investment matches the product need (no offline-first overkill).
- [ ] Idempotency keys align with the Stage 3 backend's dedup contract.
- [ ] Offline conventions (cached data, outbox, idempotency, conflicts) are documented in the mobile `CLAUDE.md`.

### Code Review Checklist

- [ ] No direct-fetch writes for actions that must survive offline (watch AI diffs).
- [ ] No retryable write without an idempotency key.
- [ ] No optimistic update without a rollback path.
- [ ] No sync path that clobbers server changes with no conflict policy.
- [ ] No full offline-first complexity without a requirement driving it.

*(A Deployment Checklist is not applicable to this chapter; sync behavior is exercised in testing — Stage 8.)*

## Exercises

**1. Make the list work offline.** Persist the React Query cache and confirm the invoice list
and a detail render after a cold start in airplane mode, then revalidate when back online. The
artifact is the running offline read path and a note on your `maxAge`/staleness choices.

**2. Build a durable, idempotent outbox.** Implement "create invoice" through an outbox with a
client-generated idempotency key. Create one offline (it shows pending), force-kill and relaunch
(still queued), go online (it syncs once), and verify a simulated double-send creates only one
invoice. The artifact is the outbox + sync loop and the idempotency proof.

**3. Fix the lying UI and pick a conflict policy.** Take an optimistic "mark paid" with no
rollback, make a failing write, and observe the false success; add rollback and a pending state.
Then define and implement a conflict policy for an invoice edited on web while the phone was
offline. The artifact is the corrected mutation and a short written conflict policy.

## Further Reading

- **TanStack Query — "Offline support" / "Persist" and the persist-client docs**
  (tanstack.com/query) — persisting the cache for offline reads and managing pause/resume of
  mutations; the basis for this chapter's read-and-write approach.
- **`@react-native-community/netinfo` documentation** (github.com/react-native-netinfo) — reliable
  connectivity detection (`isConnected` vs `isInternetReachable`) that drives the sync loop.
- **Expo — "SQLite," "AsyncStorage," and "MMKV" storage options** (docs.expo.dev) — the local
  stores for the outbox and cache, and when to choose each (SQLite for structured/large data, MMKV
  for fast key-value).
- **Martin Kleppmann — "Designing Data-Intensive Applications," conflict-resolution chapters** — the
  conceptual grounding for sync conflicts, last-write-wins, and merges; background for choosing a
  policy (and for knowing when CRDTs are and aren't worth it).
</content>

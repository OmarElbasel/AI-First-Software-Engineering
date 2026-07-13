# Building, Shipping & OTA Updates

## Introduction

Everything up to this chapter runs on a simulator or a development build on your own
device. Shipping is different, and it's where mobile diverges most sharply from the
web: you cannot `git push` to production. Between your code and your users stand two
gatekeepers — Apple's App Store review and Google's Play review — who can take days
and can reject you. Getting a signed binary onto real devices requires code signing,
provisioning, store listings, and platform-specific credentials that have nothing to
do with your app's logic. This chapter is about that last mile: building release
binaries with **EAS Build**, submitting them with **EAS Submit**, shipping instant
JavaScript-only fixes with **EAS Update** (OTA), and doing all of it through a
repeatable pipeline rather than a person clicking through Xcode.

The single most important idea: **there are two ways to ship a change, and knowing
which one a change requires is the core competence of mobile releases.** A **native
build** (new binary through EAS Build → store review) is required whenever native code,
permissions, SDK versions, or app config change — slow, gated, unavoidable for those.
An **OTA update** (EAS Update) pushes new JavaScript and assets directly to installed
apps in seconds, bypassing review — but *only* for changes that are pure
JS/asset changes compatible with the already-installed native runtime. Pushing an OTA
update that assumes native code the installed binary doesn't have will crash your users'
apps. The judgment is knowing the boundary: OTA for JS fixes, a native build for
anything that touches the native layer.

The second idea: **releases must be a pipeline, not a ritual.** Manual signing and
store uploads are error-prone, unrepeatable, and bus-factor-of-one. EAS turns builds,
submissions, and updates into commands (and CI steps) with managed credentials and
**release channels** (preview/production) — so shipping is reproducible, auditable, and
safe to roll back. This is the mobile instance of the CI/CD discipline that Stage 7
covers for the backend; here it's shaped by the store gatekeepers and the native/OTA
split.

## Why It Matters

The release process is where mobile's unique constraints concentrate, and getting it
wrong is uniquely expensive because there's a gatekeeper and a slow feedback loop:

- **You can't hotfix like the web.** On the web a bad deploy is reverted in minutes.
  On mobile, a native bug shipped to the store takes a *new review cycle* (hours to
  days) to replace — unless the fix is OTA-eligible. Not knowing which of your changes
  can go OTA versus must re-review turns a small bug into a multi-day incident.
- **OTA misuse crashes installed apps.** An OTA update ships JS to a native runtime
  that's already installed. If the JS calls a native module or API the installed binary
  doesn't include (because you added it in source but didn't ship a new build), the
  update crashes every app that downloads it — a self-inflicted outage pushed
  instantly to all users.
- **Code signing and credentials are their own discipline.** Certificates, provisioning
  profiles, keystores, push keys — mismanaged, they block releases at the worst moment
  or, leaked, become a security incident. Manual credential handling is a classic
  source of "we can't ship, the certificate expired" fire drills.
- **Store review can reject you.** Apple and Google reject builds for guideline
  violations, metadata issues, permission misuse, and more. A release process that
  doesn't account for review (and its latency) plans releases that slip.
- **Manual releases don't scale or survive.** A release that only one person can do,
  by clicking through Xcode from their laptop, is unrepeatable, unauditable, and gone
  when that person is on vacation. Pipelines make releases boring, which is the goal.
- **Rollback matters more when review is slow.** Because a forward native fix is slow,
  the ability to roll back an OTA update (or channel) and to stage releases (preview →
  production, phased rollout) is what limits blast radius.

Done right — EAS builds and submissions in a pipeline, managed credentials, a clear
OTA-vs-native rule, staged channels, and rollback — shipping is a repeatable, low-drama
command, JS fixes reach users in seconds, and native releases go through review
predictably. Done wrong, you fumble credentials, crash users with an over-eager OTA
update, can't hotfix without a multi-day review, and depend on one person's laptop to
release.

The AI dimension: assistants know the *commands* (`eas build`, `eas update`) but not the
*judgment* — they'll suggest an OTA update for a change that added a native module
(crashing users), skip credential and channel setup, treat the two platforms as
identical, and ignore review and rollback. The pipeline and the native/OTA boundary are
exactly where their command-level fluency is most dangerous.

## Mental Model

Two ways to ship, gated by the native/OTA boundary, run as a pipeline with staged
channels:

```
   THE TWO WAYS TO SHIP A CHANGE
     NATIVE BUILD (EAS Build → EAS Submit → store REVIEW → users)
        required when: native code · permissions · SDK/Expo upgrade · app.config native fields
        slow (review: hours–days), gated, unavoidable for the above
     OTA UPDATE (EAS Update → installed apps, seconds, NO review)
        allowed ONLY when: pure JS / asset changes compatible with the INSTALLED native runtime
        ⚠ ships JS to an existing binary — assume native it doesn't have → CRASH for all users

   THE BOUNDARY (the core judgment)
     touched anything native? ──► NATIVE BUILD.   pure JS/asset? ──► OTA is safe.
     when unsure ──► native build. An OTA crash hits everyone instantly.

   THE PIPELINE (not a person clicking Xcode)
     source ──► EAS Build (cloud, managed credentials) ──► EAS Submit (to stores)
                    │
                    └── release CHANNELS:  preview ──► production   (test before all users)
     rollback: republish a prior update / roll back the channel · phased store rollout

   CREDENTIALS: certificates, provisioning, keystore, push keys — MANAGED by EAS, not by hand.
```

Four principles carry the chapter:

**Know the native/OTA boundary, and default to native when unsure.** Any change to
native code, permissions, SDK/Expo version, or native config fields requires a new build
through store review. Only pure JS/asset changes compatible with the installed native
runtime may go OTA. When in doubt, ship a native build — an OTA crash reaches everyone
instantly.

**Make releases a pipeline.** Use EAS Build/Submit/Update as commands and CI steps with
managed credentials, so shipping is repeatable, auditable, and not dependent on one
person's machine. Manual signing and uploads are the thing you're replacing.

**Stage releases through channels, and keep rollback ready.** Ship to a preview channel/
internal track first, then production; use phased rollouts for native releases; and be
able to roll back an OTA update or channel fast — because the forward native fix is slow.

**Respect the gatekeepers and the two platforms.** Plan for review latency and rejection,
and handle iOS and Android's distinct credentials, store requirements, and review
processes. Shipping is where the platform differences and the store constraints are most
concrete.

A working definition:

> **Shipping a mobile app means building signed release binaries with EAS Build,
> submitting them through store review with EAS Submit, and pushing OTA-eligible JS/asset
> fixes instantly with EAS Update — all as a repeatable pipeline with managed credentials,
> staged channels, and rollback. The core judgment is the native/OTA boundary: native
> build for anything touching the native layer, OTA only for pure JS changes compatible
> with the installed runtime, and a native build whenever you're unsure.**

## Production Example

**Invoicely mobile** is ready to ship to the App Store and Play Store, and then to be
maintained. The release story makes the native/OTA boundary concrete with real changes:

- **A typo in the invoice-list empty state** (pure JS) → **OTA update**: pushed via EAS
  Update to the production channel, live on users' devices in seconds, no review.
- **Adding push notifications** (Chapter 05 — new native permission and config) →
  **native build**: requires a new binary through EAS Build and store review; it can
  *not* go OTA, because the installed binary lacks the notification native module.
- **A pricing-logic bug fix** (pure JS) → **OTA update** to a preview channel first
  (internal testers), verified, then promoted to production.
- **An Expo SDK upgrade** (native runtime change) → **native build**, submitted and
  reviewed, with a phased Play Store rollout so a regression hits 10% before 100%.

The pipeline: EAS Build produces signed iOS and Android binaries in the cloud with
credentials EAS manages (no certificates juggled by hand); EAS Submit uploads them to App
Store Connect and Play Console; EAS Update serves OTA JS to the matching channel; and a
CI workflow (GitHub Actions, Stage 7) runs builds and submissions on a tagged release. If
an OTA update misbehaves, the team republishes the prior update to roll back in seconds.

In this chapter we set that up: `eas.json` build/submit profiles, channels, an OTA update
flow with the native/OTA rule enforced, credential management, and a release pipeline. We
contrast it with the assistant-default failure mode (OTA-updating a change that added a
native module, no channels, hand-managed credentials, one-platform thinking) that crashes
users and can't be reproduced.

## Folder Structure

```
mobile/
├── app.config.ts             # native config (permissions, SDK, plugins) — changes here ⇒ NATIVE BUILD
├── eas.json                  # EAS Build/Submit PROFILES + channels (preview/production)
└── .github/workflows/
    └── release.yml           # CI pipeline: eas build + eas submit on a tagged release (Stage 7)

# EAS-managed (not files in the repo):
#   credentials  → certificates, provisioning profiles, keystore, push keys (managed by EAS)
#   channels     → preview, production (which build gets which OTA updates)
```

Why this shape: `eas.json` is the single declaration of *how* the app builds and submits —
profiles for development/preview/production, and the channels that connect builds to OTA
updates — so releases are configuration, not tribal knowledge. `app.config.ts` is flagged
here as the tripwire: a change to its native fields means an OTA update is *not* enough and
a new build is required (the boundary made visible in the file layout). The CI workflow puts
builds and submissions in a pipeline (Stage 7's CI/CD, applied to mobile). Credentials and
channels live in EAS, not the repo — managed, not hand-rolled, and never committed.

## Implementation

**Build and submit profiles (`eas.json`).** The declarative pipeline: how each variant
builds, which channel it uses for OTA, and how it's submitted. `preview` and `production`
are separate channels so updates can be staged.

```jsonc
{
  "build": {
    "preview":    { "distribution": "internal", "channel": "preview" },     // internal testers
    "production": { "channel": "production", "autoIncrement": true }         // store release
  },
  "submit": {
    "production": {
      "ios":     { "appleId": "release@invoicely.com", "ascAppId": "..." },
      "android": { "track": "production" }                                    // Play track
    }
  }
}
```

**A native build and submission (the slow, gated path).** Required for anything touching
the native layer (permissions, SDK, config). Runs in the cloud with EAS-managed credentials.

```bash
# Native build → produces signed iOS + Android binaries in the cloud (credentials managed by EAS).
eas build --profile production --platform all

# Submit the built binaries to App Store Connect / Play Console → enters STORE REVIEW.
eas submit --profile production --platform all
# ...then review (hours–days), then release (optionally a PHASED rollout on the store).
```

**An OTA update (the fast path — for JS/asset changes only).** Ships new JavaScript to the
matching channel's installed apps in seconds, no review. Stage to `preview` first, then
promote to `production`.

```bash
# Pure JS/asset fix (a typo, a pricing-logic bug) → push OTA to internal testers first.
eas update --channel preview --message "Fix invoice empty-state copy"

# Verified on preview? Promote the SAME update to production users (seconds, no review).
eas update --channel production --message "Fix invoice empty-state copy"
```

**The native/OTA gate (the judgment, made explicit).** Before every ship, answer one
question. This is the check that prevents the crash-everyone incident.

```
# Did this change touch ANY of these?
#   - native code / a new native module        (e.g., added push notifications, Ch 05)
#   - permissions (camera, notifications, ...)
#   - Expo SDK / React Native version
#   - native fields in app.config.ts (plugins, bundle id, entitlements)
#
#   YES → NATIVE BUILD (eas build + eas submit + review). OTA is NOT allowed.
#   NO  → OTA update is safe (eas update).
#   UNSURE → NATIVE BUILD. An OTA update incompatible with the installed binary crashes everyone.
```

**Rollback (because the forward native fix is slow).** An OTA update can be reverted in
seconds by republishing the previous good update to the channel.

```bash
# Bad OTA update in production? Republish the last known-good update to roll back instantly.
eas update --channel production --message "Rollback to previous stable" --republish --group <good-update-id>
```

**The anti-patterns — the assistant-default release failures.**

```bash
# ANTI-PATTERN 1: OTA-updating a NATIVE change → crashes every app that downloads it
#   (source added expo-notifications, but no new build was shipped)
eas update --channel production --message "Add push notifications"   # 💥 installed binary has no native module

# ANTI-PATTERN 2: no channels, no staging → every update hits all users with no preview
eas update  # straight to everyone, untested

# ANTI-PATTERN 3: hand-managed credentials on one laptop → unrepeatable, expires, bus-factor 1
#   (certificates/keystore juggled manually instead of managed by EAS + CI)
```

The difference is the whole chapter: the good process classifies each change against the
native/OTA boundary (native build for native changes, OTA only for compatible JS), stages
through channels with rollback ready, and runs in a pipeline with managed credentials. The
bad process pushes a native-dependent change OTA (instant outage), ships untested to all
users, and depends on manual credential handling from one machine — three ways to turn a
release into an incident.

## Engineering Decisions

Five decisions define shipping.

### Native build or OTA update for this change?

**Options:** (1) OTA update; (2) native build + store review; (3) guess.

**Trade-offs:** OTA is instant and review-free but only valid for JS/asset changes
compatible with the installed native runtime — used wrongly, it crashes every app that
downloads it. A native build is slow (review latency) and gated but is the only correct
path for native code, permissions, SDK upgrades, or native config. Guessing risks the
crash-everyone outcome.

**Recommendation:** classify every change against the boundary — touched native code/
permissions/SDK/native config → native build; pure JS/asset compatible with the installed
runtime → OTA; **unsure → native build**. This single classification is the most important
release decision, and the safe default is always the native build.

### Manual releases or an EAS pipeline?

**Options:** (1) manual Xcode/Gradle builds and store uploads; (2) EAS Build/Submit as
commands; (3) EAS in CI/CD (Stage 7).

**Trade-offs:** manual releases are unrepeatable, unauditable, and bus-factor-one, and they
invite signing mistakes. EAS commands make builds/submissions reproducible with managed
credentials at the cost of setup. EAS in CI (triggered by a tagged release) makes shipping a
reviewed, automated step at the cost of a pipeline to maintain.

**Recommendation:** EAS Build/Submit at minimum, wired into CI/CD (Stage 7) for anything
beyond a solo prototype. Releases should be a command or a pipeline trigger, not a ritual on
one person's laptop. The reproducibility and managed credentials are the point.

### How are credentials managed?

**Options:** (1) by hand (certificates/keystore on a laptop); (2) EAS-managed credentials.

**Trade-offs:** hand-managed credentials are a recurring hazard — expiring certificates that
block releases, keystores that live on one machine (and are catastrophic to lose), push keys
mishandled. EAS-managed credentials generate, store, and rotate them centrally at the cost of
trusting EAS with them (and understanding the model).

**Recommendation:** let EAS manage credentials (certificates, provisioning profiles,
keystore, push keys). Never juggle them by hand or commit them; a lost Android keystore can
mean you can never update the app under the same listing. Credential hygiene is a
release-blocking, security-sensitive concern — automate it.

### How are releases staged and rolled back?

**Options:** (1) straight to all users; (2) channels/tracks (preview → production) with
phased rollout; (3) staged plus tested rollback.

**Trade-offs:** shipping straight to everyone maximizes speed and blast radius — a bad
release hits 100% at once. Channels/tracks let you verify on internal testers/a percentage
first at the cost of a staging step. A tested rollback path (republish a prior OTA update,
phased store rollout) limits damage when something slips.

**Recommendation:** stage releases — OTA to a `preview` channel then `production`, native
builds to an internal track then a phased store rollout — and keep an OTA rollback ready.
Because a forward native fix is slow (review), staging and rollback are how you bound the
blast radius. Don't ship straight to all users.

### Plan for store review, or ship and hope?

**Options:** (1) ignore review until it rejects you; (2) plan for review latency and common
rejection reasons.

**Trade-offs:** ignoring review leads to surprise rejections and slipped releases (a launch
date that assumed instant shipping). Planning — accounting for review time, following store
guidelines, preparing metadata/permissions rationale — makes releases predictable at the cost
of the up-front diligence.

**Recommendation:** plan releases around review latency (build the buffer into timelines),
follow Apple/Google guidelines (permission usage strings, metadata, privacy disclosures), and
keep OTA available for post-release JS fixes so a small bug doesn't need a full re-review.
Treat review as a known, planned-for step, not a surprise.

## Trade-offs

Shipping mobile trades the web's instant deploys for a gated process — and OTA gives some of
that speed back, with a sharp edge.

**OTA trades a hard compatibility constraint for instant JS delivery.** EAS Update pushes JS
fixes to users in seconds, bypassing review — and only safely for changes compatible with the
installed native runtime. You regain web-like hotfix speed for JS, and you take on the
responsibility of never shipping an OTA update that assumes native code the binary lacks. The
constraint is the price of the speed.

**A pipeline trades setup for repeatable, safe releases.** EAS + CI is more up-front work than
clicking through Xcode once, and it makes every subsequent release reproducible, auditable,
credential-safe, and independent of any one machine. For anything shipped more than once, the
setup pays for itself immediately.

**Managed credentials trade some control for removing a class of fire drills.** Letting EAS own
certificates and keystores means trusting its model, and it removes expiring-certificate and
lost-keystore incidents that otherwise strike at the worst time. For most teams that's a
strongly positive trade.

**Staging and rollback trade release speed for bounded blast radius.** Preview channels, phased
rollouts, and rollback-readiness slow a release slightly and cap how many users a bad release
can reach before you catch it. Because forward native fixes are slow, that cap is worth the
small delay.

## Common Mistakes

**OTA-updating a native change.** Pushing JS that assumes native code the installed binary
lacks, crashing everyone who downloads it. Fix: classify against the native/OTA boundary; native
changes require a new build.

**No channels or staging.** Every update hitting all users untested. Fix: preview → production
channels/tracks, phased rollouts.

**Hand-managed credentials.** Expiring certificates and single-laptop keystores blocking releases
or causing incidents. Fix: EAS-managed credentials; never commit or hand-juggle them.

**Manual, unrepeatable releases.** Shipping from one person's Xcode, unauditable and bus-factor-
one. Fix: EAS Build/Submit in CI/CD (Stage 7).

**Ignoring review latency.** Planning releases as if shipping were instant, then slipping on
rejection/review. Fix: build review time into timelines; keep OTA for post-release JS fixes.

**No rollback plan.** No way to undo a bad OTA update quickly, so a forward native fix (slow) is
the only option. Fix: keep an OTA republish/rollback path ready.

## AI Mistakes

Assistants know the EAS commands but not the release judgment, so they'll confidently suggest a
command that ships an outage. Review any release advice for the native/OTA boundary, credentials,
staging, and the two platforms — the judgment the commands don't encode.

### Claude Code: recommending OTA for a native change

Asked how to ship a fix that happens to include a native change (a new permission, an added
native module like the Chapter 05 notifications), Claude Code suggests `eas update` because it's
faster and it "ships the change" — not registering that the installed binary lacks the native
code, so the OTA update crashes every app that downloads it.

**Detect:** an `eas update` recommendation for a change that added/modified native code,
permissions, the Expo SDK, or `app.config.ts` native fields; no mention of needing a new build;
"just OTA it" for a change that isn't pure JS.

**Fix:** enforce the boundary:

> Before recommending OTA vs a native build, check whether the change touched native code,
> permissions, the SDK/Expo version, or native config. If any of those, it requires a new EAS
> build and store review — an OTA update would crash installed apps that lack the native code.
> OTA is only for pure JS/asset changes compatible with the installed runtime; when unsure,
> build.

### GPT: skipping channels, credentials, and staging

GPT-family models produce a bare `eas build`/`eas update` flow with no release channels, no
credential management, and no staging — shipping straight to all users from an unmanaged setup.
It runs once on the happy path and is unrepeatable and unsafe as a real release process.

**Detect:** `eas update` with no `--channel`/no preview stage; no `eas.json` profiles/channels;
no credential setup (implying manual handling); no phased rollout or internal track; no CI wiring.

**Fix:** require a real pipeline:

> Set up release channels (preview → production) in `eas.json`, let EAS manage credentials, stage
> updates through preview before production, and wire builds/submissions into CI (Stage 7). Don't
> ship straight to all users from an unmanaged, one-off command.

### Cursor: one-platform thinking

Editing release config in isolation, Cursor tends to handle iOS or Android but not both — an
`eas submit` for one platform, credentials for one store, a rollout plan that ignores the other —
because the immediate edit targets one target.

**Detect:** build/submit config for only one platform; credentials or store setup for one store
only; rollout/review handling that assumes a single platform; `--platform ios` (or `android`) with
no counterpart.

**Fix:** require both platforms:

> Handle iOS and Android as distinct targets with their own credentials, store submission
> (App Store Connect and Play Console), review processes, and rollout controls. A release config that
> only covers one platform is incomplete — build and submit for both.

## Best Practices

**Classify every change against the native/OTA boundary.** Native code, permissions, SDK, or
native config → native build + review. Pure JS/asset compatible with the installed runtime → OTA.
Unsure → native build. This one rule prevents the crash-everyone incident.

**Make releases a pipeline with managed credentials.** EAS Build/Submit/Update as commands and CI
steps (Stage 7), with EAS-managed certificates and keystores. Never hand-juggle credentials or ship
from one person's laptop.

**Stage through channels and keep rollback ready.** OTA to preview then production; native builds to
an internal track then a phased store rollout; an OTA republish path to roll back in seconds.
Because forward native fixes are slow, bound the blast radius.

**Plan for the gatekeepers and both platforms.** Build review latency into timelines, follow store
guidelines (permission strings, metadata, privacy), and handle iOS and Android's distinct
credentials and stores. Keep OTA available for post-release JS hotfixes.

**Document the release process.** Record the native/OTA rule, channels, credential model, and
rollback steps in the mobile `CLAUDE.md`/release runbook so shipping is repeatable and assistants
don't suggest an outage.

## Anti-Patterns

**The Crashing OTA.** An `eas update` for a change that needed a new binary — instant outage for
everyone who downloads it. The tell: OTA-ing a change that added native code/permissions/SDK.

**The Firehose Release.** Updates straight to all users with no preview channel or staging. The tell:
`eas update` with no channel and no internal test step.

**The Laptop Release.** Manual builds and hand-managed credentials from one machine — unrepeatable,
expiring, bus-factor-one. The tell: no `eas.json` pipeline, credentials on a developer's disk.

**The Review Surprise.** Release plans that assume instant shipping and slip on review/rejection. The
tell: a launch date with no buffer for store review.

**The One-Platform Ship.** Build/submit/rollout config that covers iOS or Android but not both. The
tell: single-`--platform` release config with no counterpart.

## Decision Tree

"I have a change to ship — how do I get it to users safely?"

```
Did the change touch native code / permissions / Expo SDK / native app.config fields?
├── YES ──► NATIVE BUILD: eas build → eas submit → store review → (phased) release.
│           OTA is NOT allowed for this change.
├── NO (pure JS/asset, runtime-compatible) ──► OTA: eas update.
└── UNSURE ──► NATIVE BUILD. An incompatible OTA update crashes everyone instantly.

Shipping an OTA update?
└──► push to the PREVIEW channel first → verify on internal testers → promote to PRODUCTION.
     keep a rollback ready (republish the last good update).

Shipping a native build?
└──► EAS Build (managed credentials) → EAS Submit → internal track → PHASED store rollout.
     plan for review latency; follow store guidelines; do BOTH platforms.

Releasing more than once / with a team?
└──► put builds + submissions in CI/CD (Stage 7). No laptop releases, no hand-managed credentials.

Something went wrong in production?
├── bad OTA update ──► republish the previous good update (seconds).
└── bad native build ──► roll back the store rollout / ship an OTA fix IF it's JS-only; else re-review.
```

## Checklist

### Implementation Checklist

- [ ] `eas.json` defines build/submit profiles and preview/production channels.
- [ ] Every change is classified against the native/OTA boundary before shipping (native build vs OTA).
- [ ] OTA updates go to a preview channel first, then production; a rollback (republish) path exists.
- [ ] Native builds go to an internal track, then a phased store rollout.
- [ ] Credentials (certificates, keystore, push keys) are EAS-managed, never committed or hand-juggled.
- [ ] Both iOS and Android are built, submitted, and rolled out.

### Architecture Checklist

- [ ] Builds and submissions run in CI/CD (Stage 7), not from a personal machine.
- [ ] The native/OTA rule is explicit and enforced (unsure ⇒ native build).
- [ ] Release channels and staging separate testers from production users.
- [ ] Store-review latency is planned into release timelines; OTA is available for JS hotfixes.
- [ ] The release process, native/OTA rule, and rollback steps are documented (mobile `CLAUDE.md`/runbook).

### Code Review Checklist

- [ ] No OTA update proposed for a change that touched native code/permissions/SDK/native config (watch AI diffs).
- [ ] No release without channels/staging.
- [ ] No hand-managed or committed credentials.
- [ ] No single-platform release config where both platforms are needed.
- [ ] No rollback-less OTA release.

### Deployment Checklist

- [ ] App identifiers, versions, and build numbers are correct and auto-incremented per release.
- [ ] Store listings, screenshots, privacy disclosures, and permission usage strings are complete for both stores.
- [ ] EAS credentials are valid and not near expiry; the Android keystore is backed up/managed.
- [ ] The OTA channel matches the built binary's channel (updates reach the right builds).
- [ ] A phased rollout and a rollback path are configured before releasing to 100%.

## Exercises

**1. Ship both ways.** Take two changes to Invoicely — a copy fix (pure JS) and adding a native
permission — and ship each correctly: the copy fix as an OTA update to preview then production, the
permission as a new EAS build through submission. The artifact is the two flows and a written
justification of why each took its path.

**2. Cause and prevent the crashing OTA.** In a safe test, describe (or, carefully, demonstrate) how
OTA-updating a native change would crash installed apps, then write the pre-ship native/OTA checklist
that prevents it. The artifact is the checklist and an explanation of the failure it stops.

**3. Build a release pipeline.** Set up `eas.json` with preview/production channels and a GitHub
Actions workflow (Stage 7) that runs `eas build` and `eas submit` on a tagged release, with
EAS-managed credentials. The artifact is the working pipeline and a note on what it makes repeatable
that a manual release doesn't.

## Further Reading

- **Expo — "EAS Build," "EAS Submit," and "EAS Update"** (docs.expo.dev/eas) — the authoritative
  guides for cloud builds, store submission, and OTA updates, including channels and the update/runtime
  compatibility model this chapter's boundary depends on.
- **Expo — "EAS Update" runtime versions and compatibility** (docs.expo.dev) — precisely how updates
  are matched to compatible native runtimes; the technical basis for "OTA only for compatible JS
  changes."
- **Apple — "App Store Review Guidelines" / Google — "Developer Program Policies"** (developer.apple.com,
  play.google.com) — the gatekeepers' rules; essential for planning around review and avoiding rejection.
- **Stage 7 — DevOps (CI/CD, GitHub Actions)** — the pipeline discipline this chapter applies to mobile;
  the CI/CD, secrets, and rollout concepts generalize from backend deploys to EAS builds and submissions.
</content>

# Stage 5 — Mobile Engineering

Build production mobile apps: one TypeScript codebase, native performance, shipped to
both app stores.

Stages 3 and 4 built Invoicely's backend and web frontend; this stage builds the
**mobile app** that reaches the user where the web can't — a glanceable invoice on a
phone, a push when a payment lands, an app that keeps working on a train. As with
every stage, the focus is engineering judgment, not an API tour: which web instincts
transfer to React Native and which cause bugs, where auth tokens live on a device,
how much offline an app actually needs, when a change can ship instantly versus wait
for store review.

## Why this stage exists

Mobile is a fundamentally more hostile runtime than the web, and AI assistants are
most dangerous exactly here — fluent in web React, blind to the device. They reach for
`<div>`/CSS/`localStorage` that don't exist, store tokens in plain storage, assume the
network is always there, ask for notification permission at the worst moment, and
suggest an OTA update that crashes every installed app. The judgment this stage teaches
is what turns generated React Native into an app that is secure on a device, smooth on
low-end hardware, usable offline, and shippable through two gatekeepers.

## Chapters

| # | Chapter | Status |
|---|---------|--------|
| 01 | [React Native & Expo Foundations](01-react-native-and-expo-foundations.md) | Done |
| 02 | [Navigation & Deep Linking](02-navigation-and-deep-linking.md) | Done |
| 03 | [Authentication on Mobile](03-authentication-on-mobile.md) | Done |
| 04 | [Offline Support & Data Sync](04-offline-support-and-data-sync.md) | Done |
| 05 | [Push Notifications](05-push-notifications.md) | Done |
| 06 | [Mobile Performance](06-mobile-performance.md) | Done |
| 07 | [Building, Shipping & OTA Updates](07-building-shipping-and-ota-updates.md) | Done |

These seven chapters cover the ten curriculum topics for this stage. React Native and
Expo are taught together (Ch 01, since Expo is how React Native is shipped in
production); Navigation and Deep Linking share one chapter (Ch 02, because Expo Router's
URL-per-screen model makes them one problem); OTA Updates and App Store Deployment share
one chapter (Ch 07, because they are one EAS toolchain and one release decision).

## Boundaries with other stages

- **Web frontend** (React/Next.js) is **Stage 4** — this stage is native mobile; the
  React knowledge carries over, the platform layer does not.
- **Security hardening** (OWASP, token theft, deeper OAuth) is **Stage 9**; Chapter 03
  builds a correct auth flow and references it.
- **Deployment/CI-CD** foundations are **Stage 7 (DevOps)**; Chapter 07 applies that
  pipeline discipline to EAS builds and store submission.
- **Testing** mobile code is **Stage 8**; it appears here only in passing.
- **Database internals** behind the backend the app consumes are **Stage 6**.

## Running example

The stage builds **Invoicely's** mobile app (React Native + Expo) against the backend
from Stage 3 — the invoice list and detail, secure login, offline browsing and creation,
a push when an invoice is paid, and the EAS pipeline that ships it to both stores — so
mobile, web, and backend form one coherent product.

## Learning outcome

You can build a mobile app that keeps your React skills and replaces your web-platform
instincts: native primitives and virtualized lists, URL-based navigation that deep-links
from notifications and emails, tokens in the platform secure store with silent refresh,
a pragmatic offline story (cached reads, a durable idempotent outbox), notifications that
are actionable and spent as a budget, 60fps on low-end hardware, and a repeatable EAS
release pipeline governed by the native-vs-OTA boundary.
</content>

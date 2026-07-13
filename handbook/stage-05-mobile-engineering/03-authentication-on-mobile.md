# Authentication on Mobile

## Introduction

Authentication on mobile is the same problem as on the web — prove who the user is,
then keep them signed in — but the environment changes every constraint. There are
no HTTP-only cookies to lean on, so **where you store the token** becomes an explicit
security decision you own. The app is expected to stay signed in for weeks, so
**long-lived sessions and silent token refresh** are the norm, not the exception.
The device has a lock screen and biometrics, so **the token store can be
hardware-backed** in a way no browser offers. And the user can arrive from a deep
link or an OAuth redirect back into the app (Chapter 02), so the auth flow has to
survive **leaving and re-entering the process**.

The single most important idea: **on mobile, token storage is a security decision,
and the answer is the platform's secure keystore — never plain storage.** The web's
default safe box (the HTTP-only cookie) isn't available; the mobile equivalent is
the **iOS Keychain / Android Keystore**, exposed through `expo-secure-store`.
`AsyncStorage`/`localStorage`-style plain storage is unencrypted and readable on a
rooted/jailbroken device or a device backup — putting an access token there is the
mobile version of writing it to a world-readable file. Getting this one decision
right removes the most common and most serious mobile auth vulnerability.

The judgment this chapter teaches: choose a **token strategy** (short-lived access
token + long-lived refresh token, refreshed silently), store each token in the
**right place** (secure store for the refresh token and anything sensitive), handle
the **process lifecycle** (rehydrate the session on cold start, refresh
transparently on 401), integrate **biometrics** as an unlock gate rather than as the
credential itself, and reuse the **backend's auth model from Stage 3** rather than
inventing a mobile-only one. Deep security hardening (OWASP, token theft, OAuth
internals) is Stage 9; here we build a correct, production-shaped mobile auth flow.

## Why It Matters

Mobile auth failures are both the most common and the most damaging security bug in
mobile apps, because the constraints are unforgiving and the wrong defaults are easy:

- **Plain storage leaks tokens.** A token in `AsyncStorage` (or any unencrypted
  store) is recoverable from a device backup, a rooted device, or another app with
  filesystem access. Unlike a web cookie, nothing protects it by default — the
  developer must choose the secure store. This is the number-one mobile auth mistake.
- **Sessions must survive the process lifecycle.** The OS kills the app (Chapter 01);
  when it cold-starts, the user still expects to be logged in. That requires the
  token to be persisted (securely) and the session **rehydrated on launch**. Holding
  auth state only in memory logs the user out on every kill.
- **Long-lived sessions need silent refresh.** A mobile user signs in once and
  expects to stay signed in for weeks. A short-lived access token (minutes) with a
  long-lived refresh token, refreshed **transparently** when a request 401s, is what
  delivers that without either constant re-logins (token too long-lived is a risk) or
  a token that never expires (a bigger risk).
- **Deep links and OAuth cross the process boundary.** An OAuth login opens a browser
  and redirects back into the app; a "magic link" or a post-auth deep link
  (Chapter 02) re-enters the process. The flow must complete correctly across that
  hop — and a deep link into a protected screen while unauthenticated must route to
  login and return (Chapter 02).
- **Biometrics are an unlock, not an identity.** Face ID/Touch ID prove the *device
  owner* is present; they don't authenticate to your backend. Treating a biometric
  check as the login itself (with no real token) is security theater. Used correctly,
  biometrics gate access to a token already held in the secure store.

Done right — secure-store tokens, silent refresh, session rehydration, biometrics as
an unlock, the backend's model reused — the user signs in once, stays signed in
safely across kills and weeks, and their token is protected by hardware. Done wrong,
you leak tokens to anyone with the device, log users out constantly, or build a
biometric gate that protects nothing.

The AI dimension: assistants default to web/simple patterns — `AsyncStorage` for the
token (the critical leak), auth state in memory (lost on kill), no refresh flow (or a
broken one), and biometrics misused as the credential. Each is a real vulnerability or
a real UX failure, and each looks fine in a single happy-path demo.

## Mental Model

Two tokens, a secure vault, a refresh loop, and a lifecycle that survives kills:

```
   SIGN IN (reuse the Stage 3 backend auth model)
     email/password  OR  OAuth (expo-auth-session)  OR  magic link (deep link back, Ch 02)
        │  backend returns:
        ▼
     ACCESS TOKEN  (short-lived, ~15 min)     REFRESH TOKEN (long-lived, ~30 days)
        │  in memory / secure store               │  ALWAYS secure store
        ▼                                          ▼
   ┌─────────────────────  TOKEN STORAGE  ─────────────────────┐
   │  expo-secure-store  →  iOS Keychain / Android Keystore     │  ← hardware-backed, encrypted
   │  NEVER AsyncStorage / plain storage for tokens             │  ← unencrypted = leak
   └────────────────────────────────────────────────────────────┘
        │
   REQUEST ──► attach access token ──► 401? ──► use refresh token to get a new
        │                                        access token ──► retry  (SILENT refresh)
        │                                        refresh failed? ──► sign out → /login
        ▼
   COLD START (OS killed the app):
     read refresh token from secure store ──► REHYDRATE session ──► user still signed in
        (auth state is NOT memory-only)

   BIOMETRICS (Face ID / Touch ID):  an UNLOCK gate over the stored token,
     NOT the credential itself. Device-owner presence, then use the real token.
```

Four principles carry the chapter:

**Store tokens in the platform secure store, always.** `expo-secure-store` (Keychain/
Keystore) for the refresh token and anything sensitive — hardware-backed and
encrypted. Never `AsyncStorage`/plain storage for tokens. This single decision is the
core of mobile auth security.

**Short access token + long refresh token, refreshed silently.** Keep access tokens
short-lived and refresh them transparently on a 401 using a securely stored refresh
token, so the user stays signed in for weeks without re-logging-in and without a
token that never expires.

**Rehydrate the session across the process lifecycle.** On cold start, read the
persisted token and restore the session before deciding what to render. Auth state
must survive an OS kill — it can't live only in memory.

**Biometrics gate the token; they aren't the token.** Use Face ID/Touch ID to unlock
access to a token already in the secure store (or to re-authorize a sensitive action).
The real authentication is still the backend-issued token.

A working definition:

> **Mobile authentication is the Stage 3 backend auth model plus mobile-specific
> handling: store tokens in the platform secure store (Keychain/Keystore via
> `expo-secure-store`) — never plain storage; use a short-lived access token with a
> long-lived refresh token refreshed silently on 401; rehydrate the session on cold
> start so it survives OS kills; and treat biometrics as an unlock over the stored
> token, not as the credential.**

## Production Example

**Invoicely mobile** needs the freelancer to sign in once and stay signed in for
weeks — checking invoice status on the go shouldn't demand a fresh login every time.
The backend from Stage 3 already issues JWT access tokens and refresh tokens
(Stage 3, Chapter 03); the mobile app reuses that exact model rather than inventing a
new one.

The flow: the user signs in with email/password (or Google via OAuth); the backend
returns an access token (15 min) and a refresh token (30 days); the app stores the
refresh token in the **secure store** and keeps the access token for API calls. When
an API call 401s because the access token expired, the app **silently** exchanges the
refresh token for a new access token and retries — the user never sees it. On cold
start after an OS kill, the app reads the refresh token from the secure store and
**rehydrates** the session, so the user opens the app already signed in. For an extra
layer on a sensitive device, Face ID **unlocks** the app on launch — gating access to
the already-stored token, not replacing it. A deep link into `/invoices/42` while the
session needs refreshing completes transparently (Chapter 02's auth gate).

In this chapter we build that: the secure token store wrapper, the auth context with
session rehydration, the API client with silent refresh on 401, an OAuth sign-in with
`expo-auth-session`, and an optional biometric unlock. We contrast it with the
assistant-default version (token in `AsyncStorage`, memory-only session, no refresh,
biometrics-as-login) to make the vulnerabilities concrete.

## Folder Structure

```
mobile/src/
├── features/auth/
│   ├── tokenStore.ts          # SECURE token storage wrapper (expo-secure-store)
│   ├── AuthContext.tsx        # session state + rehydration on cold start
│   ├── useAuth.ts             # useAuth() — isSignedIn, signIn, signOut
│   ├── api.ts                 # login / refresh / logout calls to the Stage 3 backend
│   └── biometrics.ts          # optional Face ID / Touch ID unlock gate
├── lib/
│   └── apiClient.ts           # attaches access token; SILENT refresh on 401
└── app/
    ├── _layout.tsx            # root: waits for rehydration, then routes (Chapter 02)
    └── (auth)/login.tsx       # /login — email/password + OAuth buttons
```

Why this shape: `tokenStore.ts` is the single choke point for token persistence, so
the "use the secure store" rule is enforced in one place instead of scattered across
call sites (where an assistant will reach for `AsyncStorage`). `AuthContext` owns the
session and the rehydration step so every screen reads a consistent auth state.
`apiClient.ts` centralizes the silent-refresh-on-401 logic so no individual request
has to think about token expiry. The auth flow is a feature module mirroring the
backend's auth boundary from Stage 3 — one auth model, two clients.

## Implementation

**The secure token store (`tokenStore.ts`).** The most important file in the chapter.
Every token read/write goes through the platform secure store — Keychain on iOS,
Keystore on Android — never plain storage. This is the one wrapper that makes the
security rule unavoidable.

```ts
import * as SecureStore from "expo-secure-store";

const REFRESH_KEY = "invoicely.refreshToken";

export const tokenStore = {
  // Refresh token lives ONLY in the hardware-backed secure store — never AsyncStorage.
  async getRefreshToken() {
    return SecureStore.getItemAsync(REFRESH_KEY);
  },
  async setRefreshToken(token: string) {
    await SecureStore.setItemAsync(REFRESH_KEY, token, {
      keychainAccessible: SecureStore.WHEN_UNLOCKED,   // available only when device unlocked
    });
  },
  async clear() {
    await SecureStore.deleteItemAsync(REFRESH_KEY);
  },
};
```

**The auth context with rehydration (`AuthContext.tsx`).** On cold start it reads the
persisted refresh token and restores the session *before* the app decides what to
render — so an OS kill doesn't sign the user out. `isLoaded` gates rendering until
rehydration finishes (the root layout in Chapter 02 waits on it).

```tsx
import { createContext, useContext, useEffect, useState } from "react";
import { tokenStore } from "./tokenStore";
import { refreshSession, loginRequest } from "./api";

type AuthState = { isSignedIn: boolean; isLoaded: boolean };

const AuthContext = createContext<AuthState & { signIn: Function; signOut: Function }>(null!);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [isSignedIn, setSignedIn] = useState(false);
  const [isLoaded, setLoaded] = useState(false);

  useEffect(() => {
    // COLD-START REHYDRATION: restore the session from the secure store.
    (async () => {
      const refresh = await tokenStore.getRefreshToken();
      if (refresh) {
        try { await refreshSession(refresh); setSignedIn(true); }
        catch { await tokenStore.clear(); }              // expired/revoked → signed out
      }
      setLoaded(true);                                    // now the router may decide (Ch 02)
    })();
  }, []);

  async function signIn(email: string, password: string) {
    const { refreshToken } = await loginRequest(email, password);
    await tokenStore.setRefreshToken(refreshToken);       // persist securely
    setSignedIn(true);
  }
  async function signOut() { await tokenStore.clear(); setSignedIn(false); }

  return (
    <AuthContext.Provider value={{ isSignedIn, isLoaded, signIn, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}

export const useAuth = () => useContext(AuthContext);
```

**Silent refresh on 401 (`apiClient.ts`).** The access token expires every ~15
minutes; when a request 401s, the client transparently exchanges the refresh token for
a new access token and retries — once. The user never sees an expiry. A failed refresh
signs out.

```ts
import { tokenStore } from "@/features/auth/tokenStore";
import { exchangeRefreshToken } from "@/features/auth/api";

let accessToken: string | null = null;   // in memory; short-lived, re-derivable from refresh

export async function apiFetch(path: string, init: RequestInit = {}, retry = true): Promise<Response> {
  const res = await fetch(`${API_URL}${path}`, {
    ...init,
    headers: { ...init.headers, Authorization: accessToken ? `Bearer ${accessToken}` : "" },
  });

  if (res.status === 401 && retry) {
    const refresh = await tokenStore.getRefreshToken();
    if (!refresh) throw new UnauthenticatedError();
    try {
      accessToken = await exchangeRefreshToken(refresh);   // SILENT refresh
      return apiFetch(path, init, false);                  // retry ONCE, no infinite loop
    } catch {
      await tokenStore.clear();                            // refresh dead → sign out
      throw new UnauthenticatedError();
    }
  }
  return res;
}
```

**OAuth sign-in (`login.tsx`).** `expo-auth-session` handles the browser hop and the
redirect back into the app (a deep link, Chapter 02) — the standard, secure OAuth flow
(PKCE) rather than embedding a webview or hand-rolling redirects.

```tsx
import * as AuthSession from "expo-auth-session";
import * as Google from "expo-auth-session/providers/google";

export function GoogleSignInButton() {
  const [, response, promptAsync] = Google.useAuthRequest({
    clientId: process.env.EXPO_PUBLIC_GOOGLE_CLIENT_ID,
    redirectUri: AuthSession.makeRedirectUri({ scheme: "invoicely" }),   // deep link back
  });
  // On success, exchange the provider token with YOUR backend for your app's tokens.
  return <Button title="Continue with Google" onPress={() => promptAsync()} disabled={!response} />;
}
```

**Optional biometric unlock (`biometrics.ts`).** Face ID/Touch ID *gate* the app over
the already-stored token — it is not the credential.

```ts
import * as LocalAuthentication from "expo-local-authentication";

export async function unlockWithBiometrics(): Promise<boolean> {
  const hasHardware = await LocalAuthentication.hasHardwareAsync();
  if (!hasHardware) return true;   // fall back to the stored session; don't lock users out
  const { success } = await LocalAuthentication.authenticateAsync({ promptMessage: "Unlock Invoicely" });
  return success;                  // gate access to the token; the token is still the real auth
}
```

**The anti-patterns — the assistant defaults, each a real bug.**

```ts
// ANTI-PATTERN: the four classic mobile-auth failures
import AsyncStorage from "@react-native-async-storage/async-storage";

await AsyncStorage.setItem("token", accessToken);   // 1) TOKEN IN PLAIN STORAGE — leaks on backup/root
const [signedIn, setSignedIn] = useState(false);     // 2) memory-only session — lost on OS kill
// 3) no refresh flow: on 401 the app just logs the user out (or breaks)
if (await faceId()) setSignedIn(true);               // 4) biometrics AS login — no real token, protects nothing
```

The difference is the whole chapter: the good version stores tokens in the secure
store, rehydrates the session on cold start, refreshes silently on 401, and uses
biometrics as an unlock over a real token. The bad version leaks the token to anyone
with the device, logs the user out on every kill, has no session continuity, and
builds a biometric gate with nothing behind it — four vulnerabilities that all pass a
five-second happy-path demo.

## Engineering Decisions

Five decisions define mobile auth.

### Where is the token stored?

**Options:** (1) `AsyncStorage`/plain storage; (2) `expo-secure-store`
(Keychain/Keystore); (3) in-memory only.

**Trade-offs:** plain storage is unencrypted — the token is recoverable from backups,
rooted/jailbroken devices, and (in some cases) other apps; this is a genuine
vulnerability, not a nitpick. The secure store is hardware-backed and encrypted at the
cost of a slightly more constrained API and platform-specific behavior. In-memory
alone is safe from disk exposure but doesn't survive a kill (no rehydration).

**Recommendation:** the refresh token (and anything sensitive) goes in
`expo-secure-store`, always; the short-lived access token can live in memory
(re-derived via refresh). Never store tokens in `AsyncStorage`/plain storage. This is
the single most important mobile-auth decision.

### Token strategy: one long-lived token or access + refresh?

**Options:** (1) one long-lived token; (2) short access token + long refresh token
with silent refresh; (3) short token with frequent re-login.

**Trade-offs:** one long-lived token is simple and dangerous — if it leaks it's valid
for a long time and can't be cheaply revoked. Frequent re-login is secure but hostile
on mobile, where users expect weeks of persistence. Access + refresh gives both:
short-lived access limits exposure, the refresh token (revocable, securely stored)
provides longevity, and silent refresh hides the seams.

**Recommendation:** short-lived access token + long-lived refresh token, refreshed
transparently on 401 — the standard that matches the Stage 3 backend. Reuse the
backend's model; don't invent a mobile-only token scheme.

### How does the session survive a cold start?

**Options:** (1) memory-only (re-login every launch); (2) rehydrate from the secure
store on launch; (3) rehydrate plus a freshness/validity check.

**Trade-offs:** memory-only logs the user out on every OS kill — unacceptable UX for a
weeks-long session. Rehydrating from the stored refresh token restores the session at
the cost of a launch-time async step (and a gate so the UI waits for it). Adding a
validity check (refresh on launch) catches revoked/expired tokens at the cost of a
launch request.

**Recommendation:** rehydrate the session from the secure store on cold start, gating
rendering until it completes (Chapter 02's `isLoaded`), and validate the refresh token
(a refresh call) so a revoked session is caught. Never make users re-login because the
OS did its job and killed the app.

### Is biometrics an unlock or the credential?

**Options:** (1) biometrics as the login (no backend token); (2) biometrics as an
unlock gate over a stored token; (3) no biometrics.

**Trade-offs:** biometrics-as-login is security theater — a local `true`/`false` with
no server-verified identity behind it; anyone who bypasses the check (or the code that
calls it) is "authenticated." Biometrics-as-unlock adds a device-owner-presence gate
over a real, backend-issued token at the cost of a dependency and a fallback path.

**Recommendation:** if you use biometrics, use them as an **unlock** over a token
already in the secure store (or to re-authorize a sensitive action), never as the
credential — and always provide a fallback so a failed/absent sensor doesn't lock the
user out. Deeper biometric and token-binding hardening is Stage 9.

### OAuth: `expo-auth-session`, an embedded webview, or a hand-rolled redirect?

**Options:** (1) `expo-auth-session` (system browser + PKCE); (2) an embedded webview
login; (3) a hand-rolled redirect flow.

**Trade-offs:** an embedded webview is discouraged by providers (Google blocks it),
can't share the system session, and is a phishing/credential-capture risk. A
hand-rolled redirect is easy to get subtly wrong (state, PKCE, the deep-link hop).
`expo-auth-session` uses the system browser with PKCE and the correct redirect-back
mechanics, at the cost of learning its API.

**Recommendation:** `expo-auth-session` for OAuth — it implements the secure, provider-
approved flow (system browser + PKCE + deep-link return) that pairs with Chapter 02's
deep linking. Don't embed a webview or hand-roll the redirect.

## Trade-offs

Secure mobile auth trades some simplicity for protecting the most sensitive thing the
app holds.

**The secure store trades a simpler API for real token protection.** Plain storage is
trivially easy and leaks tokens; the secure store is slightly more constrained
(platform-specific accessibility options, no bulk JSON blobs) and protects the token
with hardware-backed encryption. For a credential, the protection is non-negotiable —
this is a trade you always take.

**Access + refresh trades a refresh flow for security *and* longevity.** Maintaining
silent refresh on 401 (and its edge cases — concurrent requests, refresh failure) is
more code than a single token, and it buys both short exposure windows and weeks-long
sessions. The complexity is standard and worth it; skipping it forces a bad choice
between insecure and annoying.

**Rehydration trades a launch step for session continuity.** Restoring the session on
cold start adds an async gate before the first render, and it delivers the "still
signed in after a kill" behavior users expect. The brief launch delay is worth not
logging users out constantly.

**Biometrics trade a fallback path for a stronger gate.** A biometric unlock adds a
dependency, a fallback (device passcode, or graceful skip when no sensor), and the
discipline of keeping it an unlock rather than the credential. Worth it for sensitive
apps; skippable for low-stakes ones — but never a replacement for a real token.

## Common Mistakes

**Token in plain storage.** The access/refresh token in `AsyncStorage` — recoverable
from backups and rooted devices. Fix: `expo-secure-store` (Keychain/Keystore) for all
tokens. This is the critical one.

**Memory-only session.** Auth state only in `useState`/context, logging the user out on
every OS kill. Fix: persist the refresh token securely and rehydrate on cold start.

**No silent refresh.** No refresh flow, so the app breaks or logs out when the access
token expires. Fix: exchange the refresh token on 401 and retry once, transparently.

**Biometrics as the credential.** A Face ID check that flips a boolean with no real
token behind it. Fix: biometrics gate access to a securely stored, backend-issued
token; the token is the auth.

**Embedded webview OAuth.** Logging in inside a webview — insecure, provider-blocked,
phishable. Fix: `expo-auth-session` with the system browser and PKCE.

**Refresh loops and races.** Retrying refresh infinitely on failure, or firing many
concurrent refreshes when several requests 401 at once. Fix: retry once, and
single-flight the refresh so concurrent 401s share one refresh.

## AI Mistakes

Mobile auth is where assistants' web/simple defaults become security vulnerabilities,
not just style issues. Review generated auth code specifically for token storage, the
process lifecycle, and whether biometrics actually protect anything.

### Claude Code: storing the token in AsyncStorage

Asked to persist a login, Claude Code reaches for `AsyncStorage` (or a plain
key-value store) because it's the ubiquitous React Native storage API and it works in
the demo. For a token that's a real vulnerability — the credential is now sitting
unencrypted on the device.

**Detect:** `AsyncStorage`/plain storage holding a token, credential, or session;
`import AsyncStorage` in auth code; any token written without `expo-secure-store`.

**Fix:** mandate the secure store:

> Tokens and credentials must be stored with `expo-secure-store` (iOS Keychain /
> Android Keystore), never `AsyncStorage` or any unencrypted storage. Route all token
> reads/writes through a single secure `tokenStore` wrapper. Non-sensitive data may use
> AsyncStorage; tokens may not.

### GPT: memory-only auth state with no rehydration

GPT-family models model the session as `useState`/context and never persist or
rehydrate it — the web habit, where a page reload is the only "restart." On mobile the
OS kills the app routinely, so the user is silently logged out on the next launch.

**Detect:** auth state only in `useState`/context with no persistence; no cold-start
rehydration reading a stored token; no `isLoaded`/gating step before routing on auth.

**Fix:** require persistence and rehydration:

> The session must survive an OS kill. Persist the refresh token in the secure store,
> and on cold start rehydrate the session from it before routing (gate rendering with
> an `isLoaded` flag). Auth state cannot be memory-only — assume the app is killed and
> cold-started regularly.

### Cursor: no silent refresh (or a broken refresh loop)

Editing the request or login code in isolation, Cursor either omits the token-refresh
flow entirely (so the app breaks when the short-lived access token expires) or writes a
refresh that retries infinitely on failure and fires concurrently for every 401 — a
loop or a thundering herd.

**Detect:** API calls that don't handle 401/expiry; a refresh with no retry cap
(infinite loop on a dead refresh token); multiple concurrent refreshes for simultaneous
401s; sign-out that never triggers when refresh genuinely fails.

**Fix:** require a bounded, single-flight refresh:

> On a 401, exchange the refresh token for a new access token and retry the request
> exactly once; if refresh fails, clear the session and sign out — never retry refresh
> infinitely. Single-flight the refresh so concurrent 401s share one refresh call
> rather than triggering many.

## Best Practices

**Store tokens in the secure store, through one wrapper.** `expo-secure-store` for the
refresh token and anything sensitive, accessed via a single `tokenStore` module so the
rule can't be bypassed at a call site. Never plain storage for tokens.

**Use access + refresh with silent, bounded refresh.** Short-lived access token,
long-lived securely stored refresh token, transparent refresh on 401 that retries once
and single-flights concurrent 401s, sign-out on refresh failure. Reuse the Stage 3
backend model.

**Rehydrate the session on cold start.** Read the stored token and restore the session
before routing, gating the UI until rehydration completes. Assume the OS kills and
cold-starts the app.

**Use biometrics as an unlock, not the credential.** Gate access to a real, stored
token with Face ID/Touch ID, always with a fallback; never let a local biometric
boolean *be* the authentication.

**Use `expo-auth-session` for OAuth and document the model.** System browser + PKCE +
deep-link return (Chapter 02), never an embedded webview. Document the auth conventions
(secure store, refresh flow, rehydration) in the mobile `CLAUDE.md` so assistants stop
defaulting to AsyncStorage and memory-only state.

## Anti-Patterns

**The Plaintext Token.** The token in `AsyncStorage`/plain storage — recoverable from a
backup or rooted device. The tell: `AsyncStorage.setItem("token", …)`.

**The Amnesiac Session.** Auth state only in memory, logging the user out on every OS
kill. The tell: no persisted token, no cold-start rehydration.

**The Refreshless Client.** No silent refresh, so the app breaks or logs out when the
short access token expires. The tell: API calls with no 401/refresh handling.

**The Fake Lock.** Biometrics that flip a boolean with no real token behind them. The
tell: a Face ID check that "logs in" with nothing server-verified.

**The Webview Login.** OAuth inside an embedded webview — insecure, phishable,
provider-blocked. The tell: a login form rendered in a `WebView` instead of the system
browser.

## Decision Tree

"I'm building the mobile auth flow — how do I make it correct and secure?"

```
Storing a token or credential?
├── YES ──► expo-secure-store (Keychain/Keystore), via one tokenStore wrapper. NEVER AsyncStorage.
└── Non-sensitive data ──► AsyncStorage is fine.

Token strategy?
└──► short-lived access token + long-lived refresh token (reuse the Stage 3 backend).
     On 401 ──► silent refresh (retry ONCE, single-flight, sign out on failure).

App just cold-started (OS killed it)?
└──► read the stored refresh token → rehydrate the session → THEN route (gate on isLoaded).
     Never force a re-login because the OS killed the app.

Using biometrics?
├── As the credential ──► NO. That protects nothing.
└── As an unlock over the stored token ──► yes, with a fallback (passcode / graceful skip).

OAuth login?
└──► expo-auth-session (system browser + PKCE + deep-link return, Ch 02).
     NEVER an embedded webview or a hand-rolled redirect.

Deep link into a protected screen while unauthenticated? ──► gate + return to target (Ch 02).
```

## Checklist

### Implementation Checklist

- [ ] All tokens are stored via `expo-secure-store` through a single `tokenStore` wrapper — never `AsyncStorage`.
- [ ] A short-lived access token + long-lived refresh token strategy reuses the Stage 3 backend model.
- [ ] The API client silently refreshes on 401, retries once, single-flights concurrent refreshes, and signs out on failure.
- [ ] The session is rehydrated from the secure store on cold start, gated by an `isLoaded` flag.
- [ ] OAuth uses `expo-auth-session` (system browser + PKCE), not an embedded webview.
- [ ] Biometrics (if used) unlock a stored token and have a fallback — they are not the credential.

### Architecture Checklist

- [ ] Auth is a feature module mirroring the Stage 3 backend auth boundary (one model, two clients).
- [ ] Token persistence has a single choke point (the secure `tokenStore`), so the rule can't be bypassed.
- [ ] Session state and rehydration are owned by an auth context every screen reads consistently.
- [ ] Deep-link auth (gate + return to target) integrates with the router (Chapter 02).
- [ ] Auth conventions (secure store, refresh, rehydration, biometrics) are documented in the mobile `CLAUDE.md`.

### Code Review Checklist

- [ ] No token or credential in `AsyncStorage`/plain storage (watch AI diffs closely).
- [ ] No memory-only session without cold-start rehydration.
- [ ] No missing refresh flow, and no unbounded/concurrent refresh loop.
- [ ] No biometric check used as the credential.
- [ ] No embedded-webview OAuth.

### Deployment Checklist

- [ ] Keychain/Keystore accessibility options are set appropriately (e.g., `WHEN_UNLOCKED`).
- [ ] OAuth redirect URIs and the deep-link scheme are registered with the provider and in the build config.
- [ ] Refresh-token revocation/expiry on the backend is verified end-to-end from the app.

## Exercises

**1. Secure the token, prove it.** Build the `tokenStore` with `expo-secure-store` and
the auth context, then demonstrate the difference from `AsyncStorage`: show (conceptually
or via a device inspection tool) that the AsyncStorage token is readable while the secure-
store token is not. The artifact is the wrapper and a note on the exposure you closed.

**2. Survive the kill with silent refresh.** Implement session rehydration and the
silent-refresh-on-401 client. Sign in, force-kill the app, relaunch (still signed in),
then let the access token expire and make a request (it refreshes transparently). The
artifact is the running flow and the refresh code with a single-retry cap.

**3. Add a real biometric unlock.** Add a Face ID/Touch ID unlock that gates access to
the stored token on launch, with a fallback when the sensor is unavailable — and write a
short note explaining why this is an unlock and not the authentication. The artifact is
the gate plus the explanation.

## Further Reading

- **Expo — "SecureStore," "AuthSession," and "LocalAuthentication"** (docs.expo.dev) —
  the authoritative docs for secure token storage, OAuth with PKCE, and biometrics; the
  three APIs this chapter is built on.
- **OWASP Mobile Application Security (MASVS/MASTG)** (owasp.org) — the standard for
  mobile auth and storage requirements; the "Data Storage" and "Authentication" sections
  detail why plain-storage tokens fail. Expanded in Stage 9.
- **IETF RFC 8252 — "OAuth 2.0 for Native Apps"** (ietf.org) — why native apps must use
  the system browser and PKCE (not embedded webviews); the rationale behind the
  `expo-auth-session` recommendation.
- **Apple Keychain Services / Android Keystore documentation** (developer.apple.com,
  developer.android.com) — how the platform secure stores work and their
  accessibility/hardware-backing guarantees, the foundation under `expo-secure-store`.
</content>

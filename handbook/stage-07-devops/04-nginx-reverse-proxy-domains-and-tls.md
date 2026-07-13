# Nginx, Reverse Proxy, Domains & TLS

## Introduction

Between your application and the internet sits one job: take an untrusted flood of public
requests on a real domain over encrypted connections, and hand them safely to services that
should never face the internet directly. That job is the reverse proxy, and Nginx is the
workhorse that does it for a huge fraction of the web. It terminates TLS (so your app speaks
plain HTTP internally while users get HTTPS), routes requests to the right backend, serves static
assets efficiently, sets timeouts and size limits that protect your app from abuse, and presents
a single hardened front door on ports 80 and 443. This chapter ties together three curriculum
topics that are really one idea — **exposing an application to the internet securely** — the
proxy (Nginx), the address (domains/DNS), and the encryption (TLS/SSL via Let's Encrypt).

The single most important idea: **a reverse proxy is the single public entry point that decouples
"how the world reaches you" (one domain, HTTPS, port 443) from "how your services are structured"
(several internal services on private ports) — and it's where TLS, routing, timeouts, limits, and
security headers belong, not in the application.** Your FastAPI app shouldn't terminate TLS, parse
`X-Forwarded-For`, enforce a request-size cap, or serve static files — those are edge concerns, and
the edge is Nginx. Get this boundary right and your app stays simple and internal while the proxy
handles the hostile public surface; get it wrong and you either expose the app directly (no TLS, no
protection) or push edge logic into the app where it doesn't belong.

The judgment this chapter teaches is **the proxy is a security and reliability boundary, and its
defaults are not production defaults.** A reverse proxy that "works" — requests get through — can
still be missing HTTPS redirects, forwarding the wrong client IP, timing out too aggressively (or
never), allowing unlimited upload sizes, and leaking server details in headers. Making it
production-grade is a specific set of decisions: real TLS from Let's Encrypt with auto-renewal,
correct proxy headers so the app sees the true client, sane timeouts and body-size limits, HTTP→HTTPS
redirect, security headers (HSTS and friends), and gzip. This chapter puts a hardened Nginx in front
of Invoicely's Compose stack (Chapter 03), on a real domain, with automatic HTTPS — the front door
the VPS deploy (Chapter 06) exposes.

## Why It Matters

The edge is where security, reliability, and the public contract of your app are decided:

- **TLS is non-negotiable, and the app shouldn't handle it.** Users, browsers, SEO, and every
  modern API require HTTPS; plain HTTP leaks credentials and gets flagged "Not Secure." Terminating
  TLS at the proxy means one place manages certificates and renewal, and your app speaks simple HTTP
  internally. Do it in the app and every service reimplements certificate handling badly.
- **The proxy protects the app from the hostile public surface.** Timeouts stop a slow-loris client
  from tying up workers; a body-size limit stops a 2 GB upload from exhausting memory; rate limiting
  (and Stage 9's depth) blunts abuse. Without these, a single misbehaving client degrades the whole
  service — and the app's defaults are usually wrong for a public endpoint.
- **Wrong proxy headers silently break security and logging.** Behind a proxy, the app sees the
  *proxy's* IP unless you forward the real one (`X-Forwarded-For`) and the app trusts it correctly.
  Get this wrong and rate limits, audit logs, and geo-logic all key off the wrong address, and
  `https` detection (`X-Forwarded-Proto`) fails — so the app thinks it's on HTTP and builds broken
  redirect URLs or refuses secure cookies.
- **The domain is the public identity, and DNS/TLS have sharp edges.** An A record pointing at the
  server, a certificate that matches the hostname, `www` vs apex, propagation delays, and
  *auto-renewal* (certificates expire every 90 days with Let's Encrypt — a forgotten renewal is a
  site-wide outage) are all failure points that take a site down in ways the app can't fix.
- **The edge decouples structure from exposure.** One domain and one HTTPS port can front a backend,
  a frontend, and static assets on different internal ports — and you can restructure services
  without changing the public contract. That indirection is what makes the system evolvable.

Get it right — a single hardened Nginx terminating real auto-renewing TLS, forwarding correct
headers, enforcing timeouts and limits, redirecting HTTP to HTTPS, and setting security headers —
and your app is securely on the internet with the hostile surface handled at the edge. Get it wrong
and you expose the app directly, serve plain HTTP, break client-IP logic, or wake up to an expired
certificate and a down site.

The AI dimension: Nginx configs are a classic "looks right, isn't production" area for assistants.
They generate a `proxy_pass` that routes traffic and omit nearly everything that makes it safe — no
`proxy_set_header` for real client IP/proto, no timeouts, no `client_max_body_size`, no HTTPS
redirect, no security headers, and often a hand-waved or self-signed TLS setup instead of real
Let's Encrypt with auto-renewal. It works in the demo (the request goes through) and is wrong for
production in half a dozen quiet ways.

## Mental Model

The reverse proxy is the one public door; TLS, routing, and protection live there, not in the app:

```
   REVERSE PROXY = the single public entry point (the ONLY thing on 80/443)
                                    the internet
                                        │  https:// invoicely.com  (443)
                                        ▼
                          ┌───────────────────────────┐
                          │            NGINX           │  ← terminates TLS, routes, protects
                          │  · TLS termination (443)   │
                          │  · HTTP→HTTPS redirect (80)│
                          │  · routing by path/host    │
                          │  · timeouts, body limits   │
                          │  · security headers, gzip  │
                          │  · correct proxy headers   │
                          └─────────────┬─────────────┘
             plain HTTP over the private network (Compose), by SERVICE NAME:
              /api  →  backend:8000        /  →  frontend:3000       (never public)
        → the app speaks simple HTTP internally; the world only ever touches Nginx.

   FORWARD vs REVERSE PROXY
     forward proxy = in front of CLIENTS (outbound; a VPN/corporate proxy)
     reverse proxy = in front of SERVERS (inbound; this) — clients think Nginx IS the app

   TLS / HTTPS (terminate once, at the edge)
     Let's Encrypt (certbot) issues a FREE cert for your domain, AUTO-RENEWED every ~90 days.
        cert proves you control the domain (ACME challenge) → browser trusts the padlock.
        FORGET renewal → cert expires → whole site down. automation is mandatory, not optional.

   DOMAIN / DNS (the address that points at the box)
     A record   invoicely.com     → <server IP>          (apex)
     A/CNAME    www.invoicely.com  → <server IP>/apex     (pick canonical, redirect the other)
        DNS propagation takes minutes–hours; the cert is issued for the NAME, not the IP.

   THE PROXY HEADERS THAT MUST BE RIGHT (or security/logging breaks silently)
     proxy_set_header Host              $host;               ← app sees the real hostname
     proxy_set_header X-Real-IP         $remote_addr;        ← the true client IP (logs, limits)
     proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
     proxy_set_header X-Forwarded-Proto $scheme;             ← app knows it's HTTPS (cookies, redirects)
```

Four principles carry the chapter:

**One public entry point, everything else internal.** Nginx is the only service on 80/443; the
backend, frontend, and static assets live on private ports reachable only through it. This is the
Compose lesson (Chapter 03) enforced at the edge — the app is never directly exposed.

**Terminate TLS once, at the proxy, and automate renewal.** The proxy holds the certificate,
speaks HTTPS to the world, and forwards plain HTTP internally. Let's Encrypt makes real
certificates free; the non-negotiable part is *auto-renewal*, because a 90-day cert forgotten is a
guaranteed outage.

**The app must see the real client and protocol.** Behind a proxy, the app only knows what the
proxy tells it. Forward `Host`, `X-Real-IP`/`X-Forwarded-For`, and `X-Forwarded-Proto` correctly —
and configure the app to trust them — or client IP, HTTPS detection, secure cookies, and redirect
URLs all break in subtle ways.

**Defaults aren't production; the edge is where you harden.** Timeouts, `client_max_body_size`,
the HTTP→HTTPS redirect, security headers (HSTS), and gzip don't appear by magic — each is a
deliberate line. The proxy is where the hostile public surface is managed, so this hardening lives
here, not in the app.

## Production Example

**Invoicely** is served at `https://app.invoicely.com` through a single Nginx container in the
Compose stack (Chapter 03), the only service publishing ports 80 and 443. Everything else — the
FastAPI backend, the Next.js frontend — is internal, reachable by Nginx over the private network by
service name. The requirement that drives the config: **one domain, always HTTPS, the app never
directly exposed, and a certificate that renews itself so the site never goes down over a forgotten
cert.**

The setup: DNS has an A record for `app.invoicely.com` pointing at the VPS, and `invoicely.com` /
`www` redirect to it (one canonical host). Nginx listens on 80 (redirecting everything to HTTPS)
and 443 (TLS terminated with a Let's Encrypt certificate obtained and auto-renewed by Certbot).
Requests to `/api/...` proxy to `backend:8000`; everything else proxies to the Next.js
`frontend:3000`. Every `proxy_pass` forwards the real `Host`, client IP, and `X-Forwarded-Proto`,
and the FastAPI app is configured to trust that proxy (so it sees real client IPs and knows it's on
HTTPS). Nginx enforces a 20 MB body limit (invoices with attachments, not 2 GB uploads), sensible
read/connect timeouts, gzip, and security headers including HSTS. Certbot's renewal runs on a timer
and reloads Nginx — the cert never expires unattended. This is the front door the VPS chapter
(Chapter 06) puts the server behind.

## Folder Structure

The proxy adds a focused set of files — the Nginx config, the ACME/TLS material, and the
certificate storage — kept in the repo where they're config-as-code (Chapter 01):

```
invoicely/
├── nginx/
│   ├── nginx.conf              main config: worker/gzip/log defaults + include of the site
│   ├── conf.d/
│   │   └── invoicely.conf      THE site: server blocks (80 redirect, 443 TLS), proxy routes
│   └── snippets/
│       ├── proxy-headers.conf  the proxy_set_header block, included by every location (DRY)
│       └── security-headers.conf  HSTS + security headers, included once
├── docker-compose.yml          nginx is a service here; publishes 80/443 (Chapter 03)
├── certbot/
│   ├── conf/                   Let's Encrypt certs + renewal config (a VOLUME — persists!)
│   └── www/                    ACME http-01 challenge webroot (Nginx serves it on port 80)
└── ...
```

Why this layout:

- **`nginx.conf` includes `conf.d/*.conf`, not one giant file.** Global defaults (worker
  processes, gzip, log format) live in the main file; each site/domain is its own file in
  `conf.d/`. This is Nginx's idiom and keeps a multi-site or growing config readable and
  reviewable.
- **Shared `snippets/` keep proxy and security headers DRY.** The `proxy_set_header` block and the
  security-header block are identical across locations; factoring them into included snippets means
  a header fix happens once, not in five places — the common source of an inconsistent, partially
  hardened config.
- **`certbot/conf` is persistent state and must be a named volume.** The issued certificates and
  renewal config live here; if this isn't persisted (Chapter 03's volume lesson), every container
  rebuild loses the cert and re-requests from Let's Encrypt — straight into their rate limits.
  Treat it like the database volume.
- **`certbot/www` is the challenge webroot.** Let's Encrypt proves you control the domain by
  fetching a token over HTTP; Nginx serves that path on port 80 (the one thing port 80 does besides
  redirect). Keeping it explicit makes the renewal mechanism visible instead of magic.

## Implementation

A production `invoicely.conf` with the two server blocks — port 80 (redirect + ACME) and port 443
(TLS + routing) — and every hardening line annotated. This assumes Nginx runs in the Compose stack
and reaches services by name.

```nginx
# nginx/conf.d/invoicely.conf

# ---- Port 80: redirect everything to HTTPS, except the ACME challenge ----
server {
    listen 80;
    server_name app.invoicely.com;

    # Let's Encrypt fetches its verification token over plain HTTP — must NOT be redirected.
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Everything else → HTTPS. (No app is ever served over plain HTTP.)
    location / {
        return 301 https://$host$request_uri;
    }
}

# ---- Port 443: terminate TLS, harden, and route to internal services ----
server {
    listen 443 ssl;
    http2 on;
    server_name app.invoicely.com;

    # --- TLS: the Let's Encrypt certificate (auto-renewed by Certbot) ---
    ssl_certificate     /etc/letsencrypt/live/app.invoicely.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.invoicely.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;               # no legacy SSL/TLS 1.0/1.1
    ssl_ciphers HIGH:!aNULL:!MD5;

    # --- Protection: don't accept unbounded bodies or hang forever ---
    client_max_body_size 20m;                    # invoices with attachments, not 2GB uploads
    proxy_connect_timeout 5s;
    proxy_read_timeout    30s;
    proxy_send_timeout    30s;

    # --- Security headers (HSTS tells browsers "always HTTPS for this domain") ---
    include snippets/security-headers.conf;

    gzip on;
    gzip_types text/plain application/json application/javascript text/css;

    # --- Route: /api → FastAPI backend (internal, by service name) ---
    location /api/ {
        proxy_pass http://backend:8000;
        include snippets/proxy-headers.conf;     # the headers the app depends on
    }

    # --- Route: everything else → Next.js frontend ---
    location / {
        proxy_pass http://frontend:3000;
        include snippets/proxy-headers.conf;
    }
}
```

The two snippets that must be included on every proxied location / once per server:

```nginx
# nginx/snippets/proxy-headers.conf — the app is BLIND to the real client without these
proxy_set_header Host              $host;                        # real hostname (redirects, routing)
proxy_set_header X-Real-IP         $remote_addr;                 # true client IP (logs, rate limits)
proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;   # client IP chain
proxy_set_header X-Forwarded-Proto $scheme;                      # app knows it's HTTPS (cookies!)
```

```nginx
# nginx/snippets/security-headers.conf
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;  # HSTS
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "DENY" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
# (Content-Security-Policy is app-specific; full header hardening is Stage 9.)
```

Obtaining and auto-renewing the certificate with Certbot (the renewal is the part that matters):

```bash
# One-time issuance: prove domain control via the http-01 challenge (Nginx serves the token on :80).
docker compose run --rm certbot certonly --webroot -w /var/www/certbot \
  -d app.invoicely.com --email ops@invoicely.com --agree-tos --no-eff-email

# Renewal is AUTOMATIC and mandatory: a timer runs `certbot renew` twice daily; it renews
# only when <30 days remain, then reloads Nginx to pick up the new cert.
#   certbot renew --deploy-hook "docker compose exec nginx nginx -s reload"
# Verify it works WITHOUT waiting 90 days:
docker compose run --rm certbot renew --dry-run
```

The three things that most often separate this from a config that merely routes traffic:

- **`X-Forwarded-Proto` (and the app trusting it) is what makes the app know it's on HTTPS.**
  Without it, FastAPI behind the proxy thinks every request is HTTP: it builds `http://` redirect
  URLs, may refuse to set `Secure` cookies, and OAuth callbacks break. The app must be told to trust
  the proxy (e.g. Uvicorn's `--proxy-headers` / `--forwarded-allow-ips`, or Starlette's
  `ProxyHeadersMiddleware`) — the header alone isn't enough if the app ignores it.
- **`client_max_body_size` and timeouts are protection, and their defaults are wrong.** Nginx's
  default body limit is 1 MB (too small for real uploads — you'll get mysterious 413s) and its
  default timeouts can hang workers on slow clients. Set them to your real needs explicitly; don't
  discover them in production.
- **The ACME challenge location must stay on plain HTTP.** The one exception to "redirect
  everything to HTTPS" is `/.well-known/acme-challenge/` — Let's Encrypt fetches the token over HTTP
  on port 80. Redirect it too (a common copy-paste error) and renewal fails and the cert eventually
  expires.

## Engineering Decisions

**Make the proxy the single public entry point.** Only Nginx binds 80/443; every app service is
internal, reached by name over the private network. *Rationale:* the app should never face the
internet directly (Chapter 01/03) — the proxy is the one hardened surface, and centralizing the
public boundary is what lets you add TLS, limits, and headers in one place and restructure services
without changing the public contract.

**Terminate TLS at the proxy with Let's Encrypt, and automate renewal.** Free certificates via ACME,
terminated at Nginx, with Certbot renewing on a timer and reloading Nginx. *Rationale:* HTTPS is
mandatory and certificates should be free and self-maintaining; the 90-day lifetime makes automation
non-optional — a manual renewal *will* eventually be forgotten and take the site down. Persist the
cert volume so rebuilds don't re-request into rate limits.

**Forward the real client and protocol, and make the app trust the proxy.** Set `Host`,
`X-Real-IP`/`X-Forwarded-For`, `X-Forwarded-Proto`, and configure the app to honor them. *Rationale:*
behind a proxy the app is blind to the real client; correct headers (and app-side trust) are what keep
logging, rate limiting, HTTPS detection, secure cookies, and redirect URLs correct. This is a
security-relevant configuration, not a nicety.

**Set timeouts and a body-size limit deliberately.** Explicit `client_max_body_size` matched to real
uploads, and connect/read/send timeouts. *Rationale:* the proxy protects the app from the hostile
public surface — unbounded bodies exhaust memory, missing timeouts let slow clients tie up workers —
and Nginx's defaults (1 MB body, generous timeouts) are wrong for a public endpoint. Decide them; don't
inherit them.

**Redirect HTTP→HTTPS and set security headers (HSTS).** Port 80 redirects everything (except the ACME
path) to 443; 443 sends HSTS and the standard security headers. *Rationale:* no bytes of the app should
travel in plaintext, and HSTS makes browsers refuse to even try HTTP for your domain — closing the
downgrade window. (Full header/CSP hardening is Stage 9; this is the baseline.)

**Choose one canonical hostname and redirect the rest.** Pick apex or `www`, point DNS at the server,
and 301 the other to the canonical one; issue the cert for the names you serve. *Rationale:* serving the
same app on two hostnames splits cookies, SEO, and caching, and doubles the TLS surface; one canonical
host with redirects keeps identity, sessions, and certificates clean.

## Trade-offs

**Nginx vs Caddy vs Traefik vs a cloud load balancer.** Nginx is battle-tested, ubiquitous, and
maximally controllable, but you configure TLS/renewal yourself. Caddy gives *automatic* HTTPS with
near-zero config (great for simple setups). Traefik auto-discovers containers (nice with dynamic
Docker/Kubernetes). A cloud load balancer (ALB, Cloud LB) offloads TLS and scaling to the provider.
*When Nginx wins:* you want control, portability, and the most transferable skill — and it's the right
default for a single VPS. *When Caddy wins:* you want HTTPS to "just work" and don't need Nginx's
tunability. *When a cloud LB wins:* you're already in that cloud and want managed TLS/scaling. Nginx is
taught here because the concepts transfer to all of them.

**TLS termination at the proxy vs end-to-end (re-encrypt to the backend).** Terminating at the proxy
(app speaks plain HTTP internally) is simpler and the standard for a single trusted host/private
network. Re-encrypting proxy→backend adds defense-in-depth for zero-trust or when the internal network
isn't trusted, at the cost of managing internal certs too. *Terminate at the proxy for a single-host
Compose setup;* re-encrypt when the internal hop crosses an untrusted boundary (a concern that grows in
Stage 11's multi-node world).

**Proxy-level rate limiting/WAF vs app-level vs a CDN/edge service.** Basic protection (timeouts, body
limits, `limit_req`) at Nginx is cheap and close to the metal; a CDN/WAF (Cloudflare) adds DDoS
absorption and edge rules but is another dependency and cost; app-level limiting knows business context
(per-user, per-plan). *Do the cheap proxy-level protection always;* add a CDN when you face real abuse
or need global caching; keep business-rule limits in the app. Depth is Stage 9/11.

**One Nginx doing everything vs separate concerns.** A single Nginx handling TLS, routing, static
files, and caching is simple and fine for one app; splitting (a CDN for static/caching, the proxy for
routing) scales better but adds moving parts. *Start with one Nginx;* it comfortably fronts a SaaS on a
single server, and you split only when a specific concern (global static delivery, edge caching) demands
it.

## Common Mistakes

**Exposing the app directly instead of proxying it.** Publishing the backend's port and pointing users
at it — no TLS, no limits, no headers, the app naked on the internet. *Fix:* only Nginx binds 80/443;
the app is internal, reached through the proxy.

**Missing `proxy_set_header`, so the app sees the proxy, not the client.** No `X-Real-IP`/`X-Forwarded-*`,
so logs, rate limits, and geo-logic all key off Nginx's IP, and `X-Forwarded-Proto` absence makes the app
think it's on HTTP. *Fix:* the proxy-headers snippet on every proxied location, and configure the app to
trust the proxy.

**Forgetting cert auto-renewal.** A cert obtained once, manually, then forgotten — until it expires 90
days later and the whole site throws certificate errors. *Fix:* Certbot on a timer with a reload hook;
verify with `renew --dry-run`.

**Redirecting the ACME challenge to HTTPS.** A blanket "redirect all of port 80 to HTTPS" also redirects
`/.well-known/acme-challenge/`, so Let's Encrypt can't validate and renewal silently fails. *Fix:* serve
the ACME path over HTTP; redirect everything else.

**Leaving Nginx's default body size and timeouts.** The 1 MB default body limit causes mysterious 413s on
real uploads; default timeouts let slow clients hang workers. *Fix:* set `client_max_body_size` and
timeouts to your real requirements explicitly.

**No HTTP→HTTPS redirect (serving both).** The app answers on plain HTTP as well as HTTPS, so some traffic
is unencrypted and mixed-content/downgrade issues appear. *Fix:* port 80 redirects to 443; add HSTS so
browsers stop trying HTTP.

**Not persisting the certificate volume.** The Certbot cert directory isn't a named volume, so a container
rebuild loses the cert and re-requests from Let's Encrypt — quickly hitting their rate limits and leaving
you without a cert. *Fix:* the cert directory is a persistent named volume (Chapter 03).

## AI Mistakes

Nginx configs are a signature "routes traffic, isn't production" area for assistants — the `proxy_pass`
works, and almost every protection is missing. Review generated configs against the whole hardening list,
not "does the request get through."

### Claude Code: a bare `proxy_pass` with no headers, timeouts, or limits

Asked to "put Nginx in front of the app," Claude Code typically produces a single server block with
`proxy_pass` and little else — no `proxy_set_header`, no `client_max_body_size`, no timeouts, no security
headers — because that's the minimum that routes a request, and the request routing is what it verifies.

**Detect:** a `location` with `proxy_pass` and no `proxy_set_header` lines; no `client_max_body_size`; no
`proxy_*_timeout`; no security headers; the app seeing Nginx's IP in its logs; 413 errors on upload.

**Fix:** require the full proxy hardening:

> This proxy config needs the production essentials: `proxy_set_header` for `Host`, `X-Real-IP`,
> `X-Forwarded-For`, and `X-Forwarded-Proto` on every proxied location; an explicit
> `client_max_body_size` and connect/read/send timeouts; and security headers (HSTS et al.). Confirm the
> app logs show real client IPs and knows it's on HTTPS.

### GPT: TLS that's self-signed or has no auto-renewal

Prompted for HTTPS, GPT-family models often wire up TLS with a self-signed certificate (browser warnings)
or a manual Let's Encrypt issuance with no renewal automation — HTTPS "works" in the config but is either
untrusted or a 90-day time bomb.

**Detect:** `openssl req -x509 ... self-signed` presented as the TLS setup; a one-off `certbot certonly`
with no timer/cron/`--deploy-hook`; no persistent cert volume; no `renew --dry-run` verification; certs
that will expire unattended.

**Fix:** require real, auto-renewing certificates:

> Use Let's Encrypt for a real trusted certificate, not self-signed, and set up automatic renewal (a timer
> running `certbot renew` with a hook that reloads Nginx). Persist the cert directory as a named volume so
> rebuilds don't re-request. Verify renewal with `certbot renew --dry-run`.

### Cursor: breaking the ACME challenge or the HTTPS redirect

Editing an Nginx config inline, Cursor tends to add a clean "redirect all HTTP to HTTPS" that also catches
the ACME challenge path, or forwards headers inconsistently across locations (hardened on one route, bare
on another) — because the edit is local and doesn't see the whole config's invariants.

**Detect:** a port-80 `return 301 https://...` with no carve-out for `/.well-known/acme-challenge/`;
proxy headers present on some `location`s and missing on others; a security snippet included in one server
block but not another; renewal failing after a config edit.

**Fix:** require the whole-config invariants:

> Keep the ACME challenge path (`/.well-known/acme-challenge/`) served over plain HTTP; only redirect
> everything *else* to HTTPS. Apply the same proxy-headers and security-headers snippets consistently to
> every proxied location — factor them into includes so they can't drift. Re-run `renew --dry-run` after
> any port-80 change.

## Best Practices

**One hardened public entry point.** Only Nginx on 80/443; all app services internal. Add TLS, limits,
and headers once, at the edge — never expose the app directly.

**Real, auto-renewing TLS.** Let's Encrypt via Certbot, terminated at the proxy, renewed on a timer with a
reload hook, cert directory persisted. Verify with `renew --dry-run`. HTTPS is mandatory; expiry is
preventable.

**Correct proxy headers, and an app that trusts the proxy.** `Host`, `X-Real-IP`, `X-Forwarded-For`,
`X-Forwarded-Proto` on every route, plus the app configured to honor forwarded headers. Confirm real
client IPs in logs and correct HTTPS detection.

**Deliberate protection: timeouts, body limits, redirect, security headers.** Set
`client_max_body_size` and timeouts to real needs; redirect HTTP→HTTPS (except ACME); send HSTS and the
standard security headers. Don't inherit Nginx's defaults for a public endpoint.

**Keep the config DRY and in version control.** Global defaults in `nginx.conf`, one file per site in
`conf.d/`, shared header blocks in `snippets/` includes — so hardening is consistent and a fix happens
once. The config is code (Chapter 01).

**One canonical hostname.** Pick apex or `www`, redirect the other, issue the cert for what you serve. One
identity for cookies, SEO, and TLS.

## Anti-Patterns

**The Naked App.** The application published directly to the internet with no proxy — no TLS, no limits,
no headers. The tell: users hitting the app's port; `http://` with a raw port in the URL; the app
terminating its own TLS.

**The Blind Backend.** A `proxy_pass` with no forwarded headers, so the app sees the proxy's IP and thinks
it's on HTTP. The tell: every request logged from one internal IP; broken `Secure` cookies and `http://`
redirect URLs behind HTTPS.

**The Expiring Certificate.** TLS set up once by hand with no renewal automation, guaranteed to expire. The
tell: no Certbot timer/hook, no persistent cert volume, "the site went down and it's a cert error" every
~90 days.

**The Self-Signed Padlock.** A self-signed cert used in production, throwing browser warnings and training
users to click through security errors. The tell: `openssl ... -x509` in the setup; `NET::ERR_CERT_AUTHORITY_INVALID`.

**The ACME-Blocked Renewal.** A blanket HTTP→HTTPS redirect that also redirects the ACME challenge, so
renewal silently fails. The tell: renewal errors about the challenge path; `--dry-run` failing after a
port-80 edit.

**The Default-Limits Proxy.** Nginx defaults left in place — 1 MB body limit causing 413s, generous
timeouts letting slow clients hang workers. The tell: mysterious upload failures at ~1 MB; workers tied up
by slow connections.

## Decision Tree

"I'm putting a proxy in front of the app (or reviewing an Nginx config) — what must be true?"

```
ENTRY POINT
  Is Nginx the ONLY thing on 80/443, with all app services internal?
     no → stop exposing the app directly. one public door; everything else behind it.

TLS
  Is there a REAL (Let's Encrypt, not self-signed) certificate?          no → issue one via ACME.
  Is renewal AUTOMATED (timer + reload hook) and the cert dir PERSISTED? no → automate + persist.
        verify: certbot renew --dry-run passes.
  Is the ACME challenge path served over HTTP (not redirected)?          no → carve it out.

REDIRECT & HEADERS
  Does port 80 redirect everything (except ACME) to HTTPS?               no → add the 301.
  Are HSTS + security headers set on 443?                                no → add the snippet.

PROXY HEADERS (per proxied location)
  Host, X-Real-IP, X-Forwarded-For, X-Forwarded-Proto all forwarded?     no → add proxy-headers snippet.
  Is the APP configured to trust the proxy (forwarded-allow-ips)?        no → configure it.
        verify: app logs show real client IPs; app knows it's HTTPS.

PROTECTION
  client_max_body_size set to real upload needs (not the 1MB default)?   no → set it.
  connect/read/send timeouts set?                                        no → set them.

DOMAIN
  DNS A record points at the server; one canonical host, others 301'd; cert covers the names served?
     any no → fix DNS / redirects / cert SANs.

CONSISTENCY
  Same proxy-headers + security snippets on EVERY location/server (via includes)?
     no → factor into snippets so hardening can't drift.
  all yes → it's a secure front door, not just a router.
```

## Checklist

### Implementation Checklist

- [ ] Only Nginx binds 80/443; all app services are internal (reached by service name).
- [ ] A real **Let's Encrypt** certificate terminates TLS at the proxy (`TLSv1.2`/`1.3` only).
- [ ] Certificate **auto-renewal** is configured (timer + Nginx reload hook) and verified with `renew
      --dry-run`; the cert directory is a persistent volume.
- [ ] Port 80 **redirects to HTTPS** — except `/.well-known/acme-challenge/`, served over HTTP.
- [ ] Every proxied location forwards `Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`, and
      the app is configured to trust the proxy.
- [ ] `client_max_body_size` and connect/read/send **timeouts** are set to real needs (not defaults).
- [ ] **HSTS** and security headers are set on the HTTPS server.

### Architecture Checklist

- [ ] The Nginx config is version-controlled config-as-code; sites in `conf.d/`, shared blocks in
      `snippets/` includes (DRY, no drift).
- [ ] One canonical hostname; other hostnames 301-redirect to it; the cert covers what's served.
- [ ] TLS is terminated at the proxy (app speaks internal HTTP), an appropriate choice for the single-host
      topology.
- [ ] Basic edge protection (timeouts, body limit, and `limit_req` where needed) is present; deeper WAF/
      rate-limit depth is deferred to Stage 9.

### Code Review Checklist

- [ ] No app service exposed directly to the internet; only the proxy is public.
- [ ] No `proxy_pass` missing the forwarded headers (watch AI-generated configs); no self-signed cert in
      prod; no missing renewal automation.
- [ ] The ACME challenge path is not caught by the HTTPS redirect.
- [ ] Body-size and timeouts are set explicitly; HSTS/security headers present.
- [ ] Proxy and security snippets are applied consistently to every location (via includes).

### Deployment Checklist

- [ ] DNS A/AAAA records point at the server and have propagated before issuing the cert.
- [ ] The certificate is issued and `renew --dry-run` passes on the actual server.
- [ ] The cert volume is persisted and backed up; a rebuild does not re-request certs.
- [ ] HTTPS is confirmed end-to-end (padlock, correct hostname, HTTP→HTTPS redirect working) before
      going live.

## Exercises

**1. Front the app and forward the client correctly.** Put Nginx in front of Invoicely's backend so
`/api` proxies to it, and prove — from the app's own request logs — that without the proxy headers the app
sees Nginx's IP and thinks it's on HTTP, and *with* them (and app-side trust config) it sees the real
client IP and knows it's HTTPS. The artifact is the two log samples and the diff that fixed it.

**2. Issue and auto-renew a real certificate.** On a domain you control pointed at a test server, obtain a
Let's Encrypt cert via the http-01 challenge, wire up automatic renewal with a reload hook, and prove
renewal works with `certbot renew --dry-run` — then deliberately break the ACME path with a blanket HTTPS
redirect and observe the dry-run fail, demonstrating the carve-out's necessity. The artifact is the working
renewal and the broken/fixed redirect.

**3. Harden against the hostile surface.** Starting from a bare `proxy_pass`, add `client_max_body_size`,
timeouts, HTTP→HTTPS redirect, and HSTS/security headers; then demonstrate each protection working — a 413
on an over-limit upload, a slow-client timeout, an HTTP request redirected, and HSTS in the response
headers. The artifact is the config diff and a short capture of each behavior.

## Further Reading

- **Nginx documentation — "Reverse Proxy" and `ngx_http_proxy_module`** (nginx.org/en/docs) — the
  authoritative reference for `proxy_pass`, `proxy_set_header`, timeouts, and buffering behind this
  chapter's config.
- **Let's Encrypt & Certbot documentation** (letsencrypt.org, certbot.eff.org) — how ACME challenges work
  and how to automate issuance and renewal correctly, including the http-01 webroot flow used here.
- **Mozilla SSL Configuration Generator** (ssl-config.mozilla.org) — generates a modern, secure
  `ssl_protocols`/`ssl_ciphers` block for Nginx; the practical source for the TLS settings here.
- **MDN — HTTP headers: `Strict-Transport-Security`, `X-Forwarded-*`, `Forwarded`** (developer.mozilla.org)
  — precise semantics of HSTS and the forwarding headers the app depends on.
- **Stage 7, Chapter 05 — CI/CD with GitHub Actions** — the next step: automating the build, test, and
  deployment of the app and this proxy so shipping is a pipeline, not a manual SSH session.
</content>

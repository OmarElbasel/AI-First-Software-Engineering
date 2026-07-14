# XSS & Content Security

## Introduction

Cross-Site Scripting is injection with the browser as the interpreter. Where SQL injection (Chapter
05) tricked the database into running attacker input as SQL, XSS tricks the *browser* into running
attacker input as JavaScript — in the victim's session, with the victim's cookies, on your origin.
The mechanism is the same data-versus-code confusion: user-supplied content is inserted into a page
without being encoded for its context, so a value like `<script>steal(document.cookie)</script>`
stops being text and starts being executable script. And the connection to earlier chapters is
direct: an XSS on a page that stores a JWT in `localStorage` (Chapter 02) is instant token theft;
an XSS anywhere on your origin can drive any action the user can perform.

This chapter covers the three shapes XSS takes — reflected (payload bounces off a request), stored
(payload is saved and served to every viewer — the most dangerous), and DOM-based (the payload never
reaches the server; client JavaScript injects it) — and the layered defense that closes them.
Output encoding is the primary defense: encoding data for the exact context it's rendered into (HTML
body, attribute, JavaScript, URL, CSS) so it can't break out and execute. Modern frameworks
(React, Vue, the templating engines) auto-escape by default, which handles most cases — so the
chapter focuses hard on where that default is *bypassed*: `dangerouslySetInnerHTML`, `v-html`,
`innerHTML`, server-built HTML strings, and the rich-text feature that legitimately needs to render
user HTML and so requires real sanitization. On top of encoding sits Content Security Policy (CSP),
a browser-enforced backstop that limits what scripts can run even if an injection slips through —
defense in depth, not a substitute for encoding.

The boundaries: the frontend itself — components, rendering, the Next.js/React app — was built in
**Stage 4**; this chapter hardens how it renders untrusted content. XSS is the browser-side member
of the injection family whose server-side members were **Chapter 05**. And the browser-trust
mechanics that CSP shares a response with — CORS, other security headers, CSRF — are **Chapter 07**;
this chapter covers CSP specifically as an XSS control.

## Why It Matters

XSS is consistently among the most common web vulnerabilities, and its consequences are severe
because executing script in the victim's session is nearly equivalent to *being* the victim.

- **XSS runs in the victim's session, on your origin.** The injected script has the victim's
  cookies, can read anything the page can read, can make authenticated requests as the victim, and
  can rewrite the page. It can steal session tokens (especially from `localStorage`, Chapter 02),
  submit forms, change the account email, exfiltrate data, or plant a persistent keylogger. "Script
  execution on your origin" is close to full account takeover.
- **Stored XSS attacks every viewer, including admins.** A payload saved in a field that's rendered
  to others — a customer name, an invoice note, a support message — executes in every viewer's
  browser. When an admin views the malicious record, the script runs with *admin* privileges. One
  stored payload can cascade to full compromise; it doesn't need the victim to click anything.
- **The default is safe, so XSS ships where the default is bypassed.** React, Vue, and template
  engines escape by default — so most rendered values are safe automatically. XSS almost always
  enters through a deliberate opt-out: `dangerouslySetInnerHTML`, `v-html`, `innerHTML`,
  `mark_safe`/`| safe`, or server-side string-built HTML. Security here is auditing the *exceptions*,
  because the rule is already safe.
- **Your own stored data is untrusted input on the way out.** The most-missed source: data read back
  from your database that a user put there earlier. Stored XSS exists precisely because "it's our own
  data" leads developers to render it without encoding. The trust boundary is *rendering into a
  page*, regardless of where the data came from.
- **`localStorage` tokens turn any XSS into token theft.** This is the payoff of Chapter 02's
  storage decision. If tokens live in `localStorage`, one XSS anywhere on the origin reads and
  exfiltrates them. `HttpOnly` cookies keep the token out of script reach, so XSS can still *act* as
  the user but can't *steal the credential* — a meaningful reduction in blast radius.
- **The AI dimension is direct.** Assistants reach for `dangerouslySetInnerHTML` to render
  user-provided rich content, build HTML by concatenation on the server, and render stored data
  without treating it as untrusted. Each produces a working feature that displays content correctly
  and executes an attacker's script when the content is hostile.

## Mental Model

XSS is untrusted data rendered into a page without encoding for its context. The defense is layered:
encode on output (primary), sanitize when you must accept HTML, and let CSP catch what slips through.

```
   THE THREE SHAPES
     REFLECTED  payload in the request, echoed into the response (search term in an error page)
     STORED     payload saved, served to EVERY viewer (invoice note, customer name) — worst;
                hits admins; no click needed
     DOM-BASED  payload never hits the server; client JS writes it into the DOM
                (location.hash → innerHTML)

   THE PRIMARY DEFENSE — CONTEXT-AWARE OUTPUT ENCODING
     the SAME value needs DIFFERENT encoding depending on WHERE it lands:
       HTML body      <div>{value}</div>          → HTML-entity encode  (< becomes &lt;)
       attribute      <img alt="{value}">          → attribute encode + always quote
       JavaScript     <script>var x="{value}"</script> → JS-string encode (or don't — see below)
       URL            <a href="{value}">           → URL encode + validate scheme (no javascript:)
       CSS            style="{value}"               → CSS encode (or don't allow)
     frameworks (React/Vue/templates) do HTML+attr encoding AUTOMATICALLY. that's the safe default.

   WHERE THE SAFE DEFAULT IS BYPASSED (audit THESE)
     React:  dangerouslySetInnerHTML     Vue: v-html      vanilla: el.innerHTML =
     server: string-built HTML, mark_safe, {{ x | safe }}, template autoescape off
     → each renders raw HTML. only safe if the content is SANITIZED or truly trusted.

   WHEN YOU MUST RENDER USER HTML (rich text editor) — SANITIZE
     run it through an allowlist sanitizer (DOMPurify) that permits safe tags/attrs and strips
     script, event handlers, javascript: URLs. NEVER a hand-rolled regex/blocklist.

   DEFENSE IN DEPTH — CONTENT SECURITY POLICY (browser-enforced backstop)
     Content-Security-Policy: default-src 'self'; script-src 'self'; object-src 'none'; ...
     even if a payload is injected, CSP can block it from executing (no inline script, no
     evil.com). NOT a substitute for encoding — a second wall behind it.

   THE CONNECTION TO CH 02
     token in localStorage + any XSS = token stolen.  token in HttpOnly cookie = out of script reach.
```

Three principles carry the chapter:

**Encode on output, for the context — this is the real defense.** The same value is safe in one
context and dangerous in another, so encoding is a property of *where you render*, not of the data.
Lean on the framework's automatic HTML/attribute encoding, and treat every place you step outside it
as a decision that needs justification.

**Treat all rendered data as untrusted — including your own.** Data from the database, the API, the
URL, and the user is all hostile at the moment of rendering. Stored XSS lives in the belief that
"our data" is safe. The boundary is output, not origin.

**Sanitize only when you must render HTML, and only with a real sanitizer; back it with CSP.** If a
feature genuinely needs user-provided HTML (rich text), run it through an allowlist sanitizer — never
a regex. And deploy CSP as the backstop that limits damage when encoding is missed somewhere,
because in a large app, something will be.

A working definition:

> **XSS is untrusted data rendered into a page without context-appropriate encoding, letting it
> execute as script in the victim's session. The defense is layered: context-aware output encoding
> as the primary control (mostly automatic via the framework, audited wherever bypassed), real
> allowlist sanitization for the rare case of rendering user HTML, and Content Security Policy as a
> browser-enforced backstop — with all rendered data, including your own stored data, treated as
> untrusted.**

## Production Example

**Invoicely** renders user-controlled content all over: customer names and invoice line
descriptions (entered by users, shown to other users and to admins), invoice notes with basic rich
formatting (bold, lists, links), a support-message thread, and PDF/email templates generated from
invoice data. Every one of these is an XSS surface, and the rich-text note is the one that needs
real sanitization rather than plain encoding. This chapter hardens all of them and shows the stored-
XSS version of each.

The plain-text fields (names, descriptions, statuses) render through React, which HTML-encodes them
automatically — a customer named `<script>alert(1)</script>` displays as literal text, not script.
No special work is needed *as long as no one reaches for* `dangerouslySetInnerHTML`, and the review
rule is exactly that. The rich-text invoice note is the hard case: users legitimately submit HTML
(bold, links, lists), so it can't be plain-encoded away. Invoicely sanitizes it with DOMPurify on
render, allowing a small tag/attribute allowlist and stripping `<script>`, event handlers
(`onerror`, `onclick`), and `javascript:` URLs — so `<a href="javascript:steal()">` and `<img
src=x onerror=steal()>` become inert. Links are additionally forced to safe schemes and
`rel="noopener noreferrer"`.

The server-generated PDF and email templates — built outside React's protection — use an
auto-escaping template engine, never string concatenation, so invoice data can't inject into the
generated HTML. And crucially, Invoicely stores its JWT in an `HttpOnly` cookie (Chapter 02), so
even if an XSS slipped through somewhere, the session token is out of script reach — the attacker
could act within the page but couldn't steal the durable credential. Over all of it sits a Content
Security Policy: `script-src 'self'`, no inline script, `object-src 'none'` — so an injected payload
has no way to execute inline or load from an attacker's domain. In this chapter we build each
defense and contrast it with the assistant-default version: the `dangerouslySetInnerHTML` note, the
concatenated email HTML, the stored customer name rendered raw.

## Folder Structure

```
web/ (Next.js — Stage 4)
├── components/
│   ├── RichText.tsx        # the ONLY component that renders HTML — sanitizes with DOMPurify
│   └── SafeLink.tsx        # forces safe URL schemes; rel=noopener; no javascript:
├── lib/
│   └── sanitize.ts         # DOMPurify config: tag/attr allowlist, strip handlers & bad schemes
├── middleware.ts           # sets Content-Security-Policy + related headers (Ch 07 shares this)
api/ (FastAPI — Stage 3)
├── templates/              # PDF/email: auto-escaping engine, NEVER string-built HTML
└── core/security_headers.py  # CSP for server-rendered/API responses
tests/
└── security/
    └── test_xss.py         # stored & reflected payloads render inert; CSP header present
```

Why this shape:

- **`RichText.tsx` as the single HTML-rendering component** confines `dangerouslySetInnerHTML` to
  one audited, sanitizing place. Anywhere else rendering raw HTML is a review red flag by
  construction — the dangerous API has exactly one legitimate home.
- **`lib/sanitize.ts`** centralizes the DOMPurify allowlist so the sanitization policy is defined
  once, reviewed once, and can't drift into a weaker per-use config.
- **`SafeLink.tsx`** handles the URL-context XSS (`javascript:` and `data:` scheme links) that HTML
  encoding doesn't cover, in one place every user-provided link goes through.
- **`templates/` with an auto-escaping engine** keeps server-generated HTML (PDF, email) — which is
  outside React's automatic protection — safe by default, closing the XSS surface frameworks don't
  cover.
- **`middleware.ts` / `security_headers.py`** set CSP as the backstop on every response, so the
  browser enforces script restrictions even where encoding is missed.
- **`tests/security/test_xss.py`** fires stored and reflected payloads and asserts they render inert
  and that CSP is present — the proof, kept green in CI.

## Implementation

**Plain values: rely on the framework's automatic encoding.** The safe default handles the common
case — the discipline is not breaking it.

```tsx
// SAFE — React HTML-encodes automatically. <script> shows as text.
<div className="customer">{invoice.customerName}</div>
<td>{invoice.lineDescription}</td>

// DANGER — the ONLY way XSS enters here. never do this with user content:
// <div dangerouslySetInnerHTML={{ __html: invoice.note }} />   ← raw HTML, executes payloads
```

The entire plain-text surface is safe for free. The review rule writes itself: user content goes in
`{curly braces}`, never into `dangerouslySetInnerHTML`.

**Rich text: sanitize with an allowlist (`sanitize.ts` + `RichText.tsx`).** When you *must* render
user HTML, a real sanitizer is the only safe path.

```ts
// lib/sanitize.ts — one policy, allowlist-based
export function sanitizeHtml(dirty: string): string {
  return DOMPurify.sanitize(dirty, {
    ALLOWED_TAGS: ["b", "i", "em", "strong", "ul", "ol", "li", "p", "br", "a"],
    ALLOWED_ATTR: ["href"],                       // no onerror/onclick/style
    ALLOWED_URI_REGEXP: /^(https?|mailto):/i,     // no javascript:/data: URLs
  });
}
```

```tsx
// RichText.tsx — the one sanctioned place raw HTML renders, and it's sanitized first
export function RichText({ html }: { html: string }) {
  return <div dangerouslySetInnerHTML={{ __html: sanitizeHtml(html) }} />;
}
```

DOMPurify parses the HTML and strips everything not on the allowlist — `<script>`, `onerror`,
`javascript:` links all removed — so `<img src=x onerror=steal()>` becomes `<img src="x">` or
nothing. This is an allowlist (permit known-safe), never a blocklist (strip known-bad), because the
attacker's encodings are endless.

**Safe links (`SafeLink.tsx`): the URL-context defense HTML encoding misses.**

```tsx
export function SafeLink({ href, children }: Props) {
  const safe = /^(https?|mailto):/i.test(href) ? href : "#";   // no javascript:/data: schemes
  return <a href={safe} rel="noopener noreferrer" target="_blank">{children}</a>;
}
```

HTML-encoding an `href` doesn't stop `javascript:alert(1)` — a value can be perfectly encoded and
still be a dangerous scheme. URL context needs scheme validation, which is why user links go through
one component.

**Server-generated HTML: auto-escaping templates, never concatenation (`templates/`).**

```python
# PDF/email built with an autoescaping engine — invoice data is escaped into the HTML
template = jinja_env.get_template("invoice.html")   # autoescape=True
html = template.render(invoice=invoice)             # customer_name is escaped automatically
# NEVER: html = f"<h1>{invoice.customer_name}</h1>"  ← concatenated server HTML, injectable
```

React protects the browser app, but server-generated HTML (PDFs, emails) is outside that protection
and is a real XSS/HTML-injection surface — an auto-escaping engine makes it safe by default.

**Content Security Policy: the backstop (`middleware.ts`).**

```ts
// even if a payload slips past encoding somewhere, CSP blocks its execution
const csp = [
  "default-src 'self'",
  "script-src 'self'",            // no inline <script>, no eval, no external script hosts
  "object-src 'none'",            // no plugins
  "base-uri 'self'",
  "frame-ancestors 'none'",       // clickjacking defense (Ch 07)
].join("; ");
response.headers.set("Content-Security-Policy", csp);
```

`script-src 'self'` means an injected inline `<script>` simply won't run, and a payload can't load
`evil.com/steal.js`. CSP is the wall behind the wall — it doesn't excuse missing encoding, it limits
the damage when encoding is missed.

**The attack tests (`tests/security/test_xss.py`): prove payloads are inert.**

```python
def test_stored_customer_name_payload_renders_as_text(client):
    create_customer(client, name="<script>window.__xss=1</script>")
    page = render_invoice_page(client)
    assert "<script>window.__xss=1</script>" not in page       # escaped, not raw
    assert "&lt;script&gt;" in page                             # rendered as visible text

def test_rich_note_strips_event_handlers(client):
    note = sanitize_html('<img src=x onerror="steal()"><b>ok</b>')
    assert "onerror" not in note and "<b>ok</b>" in note        # handler stripped, safe tag kept

def test_csp_header_blocks_inline_script(client):
    assert "script-src 'self'" in client.get("/").headers["Content-Security-Policy"]
```

These are the deliverable: XSS defense you can't demonstrate neutralizing a real payload is a
belief. The suite proves stored payloads render as text, the sanitizer strips handlers, and CSP is
present.

## Engineering Decisions

Five decisions define an app's XSS posture.

### Encode/escape, sanitize, or validate — which, where?

**Options:** (1) output-encode for context (the framework default); (2) sanitize HTML with an
allowlist library; (3) input-validate/reject; (4) some combination.

**Trade-offs:** output encoding is the primary defense and is mostly automatic — it makes data safe
for its render context without altering what's stored. Sanitization is for the specific case of
rendering user-provided HTML and is lossy and harder to get right. Input validation reduces surface
but is *not* an XSS defense (a valid string is a valid payload, and the same data may be safe in one
context and dangerous in another — so encoding must happen at output, not input).

**Recommendation:** output-encode everywhere (lean on the framework, audit the bypasses) as the
primary control; sanitize *only* the fields that must contain HTML, with a real library; validate at
the boundary as defense in depth. The key judgment: encode at *output* for the *context*, because
the same value's safety depends on where it's rendered — encoding at input can't know the future
context.

### Auto-escaping default, or manual encoding?

**Options:** (1) a framework/engine that auto-escapes by default (React, Vue, Jinja `autoescape`);
(2) manual encoding at each render; (3) auto-escaping disabled for convenience.

**Trade-offs:** auto-escaping makes the safe path the default and XSS the opt-out — the strongest
structural position. Manual encoding is error-prone (one forgotten call is a hole). Disabling
auto-escaping (for "flexibility" or to render some HTML) turns the whole surface dangerous to save a
few sanitize calls.

**Recommendation:** always use auto-escaping frameworks/engines and keep the default on — for the
browser app *and* for server-generated HTML (emails, PDFs). Never disable auto-escaping globally to
render HTML in a few places; sanitize those few places instead. The structural win is that safety is
the default and every exception is visible.

### How is user-provided HTML (rich text) handled?

**Options:** (1) don't allow HTML — store/render plain text or Markdown rendered safely; (2) allow
HTML, sanitize with an allowlist library (DOMPurify); (3) allow HTML, filter with a hand-rolled
regex/blocklist.

**Trade-offs:** not allowing HTML is safest and often sufficient (Markdown, rendered through a safe
renderer, covers most rich-text needs without raw HTML). An allowlist sanitizer safely supports real
HTML at the cost of a dependency and careful configuration. A hand-rolled regex filter is a
guaranteed hole — HTML parsing by regex is famously unwinnable, and attackers have endless bypasses.

**Recommendation:** avoid raw user HTML when you can — Markdown rendered by a safe renderer meets
most needs. When you genuinely need HTML, sanitize with a vetted allowlist library (DOMPurify),
configured to a minimal tag/attribute set, and never hand-roll it. A regex HTML sanitizer is an
anti-pattern, full stop.

### Deploy Content Security Policy, and how strict?

**Options:** (1) no CSP; (2) a strict CSP (`script-src 'self'`, nonces/hashes for any inline);
(3) a loose CSP with `unsafe-inline`/`unsafe-eval` (which defeats much of the point).

**Trade-offs:** no CSP means an injection that gets past encoding executes freely. A strict CSP
blocks inline scripts and external script origins, turning many XSS bugs into non-events — at the
cost of real work (no inline scripts/handlers, nonces for what's needed, tuning for third-party
widgets). A loose CSP with `unsafe-inline` is easy and largely cosmetic — it permits exactly the
inline injection XSS uses.

**Recommendation:** deploy a strict CSP as defense in depth: `script-src 'self'` with nonces or
hashes for any necessary inline script, `object-src 'none'`, `base-uri 'self'`. Avoid
`unsafe-inline`/`unsafe-eval`. Start in report-only mode to find violations, then enforce. CSP is a
backstop that has saved many apps from a missed encoding — but it is never a reason to encode less.

### Where do session tokens live (the XSS blast-radius decision)?

**Options:** (1) `HttpOnly` cookie — unreachable by script; (2) `localStorage`/`sessionStorage` —
readable by any script; (3) in-memory.

**Trade-offs:** this is Chapter 02's decision seen from the XSS side. `HttpOnly` cookies keep the
token out of an XSS's reach (the attacker can act in-page but can't steal the durable credential),
at the cost of needing CSRF defense (Chapter 07). `localStorage` is trivially exfiltrated by any XSS —
one payload, every token gone. In-memory is safer than `localStorage` but doesn't persist.

**Recommendation:** `HttpOnly`, `Secure`, `SameSite` cookies for tokens, paired with CSRF defense —
so XSS, if it occurs, can't harvest the credential. This is the single most impactful way to cap the
blast radius of an XSS you didn't catch. Never `localStorage` for tokens.

## Trade-offs

**Output encoding is nearly free and is the one control with no real downside.** Like
parameterization, the safe path (framework auto-escaping) costs nothing and is the default. The only
"cost" is not opting out casually. There's no performance or DX argument for rendering raw user HTML
where encoding would do.

**Sanitizing rich HTML trades fidelity and a dependency for safe rich text.** An allowlist sanitizer
will strip some markup users might want, and adds a library to maintain and configure. The
alternative — rendering user HTML raw — is stored XSS. When you need rich text, the sanitizer's
constraints are the price of safety; prefer Markdown to avoid the trade entirely.

**A strict CSP trades engineering effort for a powerful backstop.** Eliminating inline scripts,
adding nonces, and tuning for third-party widgets is real work, and a strict CSP can break things
during rollout (hence report-only first). What it buys is that many injections become non-events —
often worth it for an app holding sensitive data, and the report-only phase de-risks the rollout.

**HttpOnly cookies trade the need for CSRF defense for XSS-proof token storage.** Moving tokens out
of script reach means you must now defend against CSRF (Chapter 07) — you trade one problem for a
better-understood one with a standard solution. It's a good trade: XSS token theft is silent and
total; CSRF has well-established, cheap defenses.

## Common Mistakes

**`dangerouslySetInnerHTML` / `v-html` / `innerHTML` with user content.** Rendering raw user HTML,
bypassing the framework's encoding — the number-one XSS vector in modern apps. Fix: render as text
(`{value}`); if HTML is required, sanitize with DOMPurify first, in one component.

**Rendering stored data as if it's trusted.** Treating "our own database" as safe and rendering it
without encoding — the source of stored XSS. Fix: treat all rendered data as untrusted; the boundary
is output, not origin.

**Building HTML by string concatenation on the server.** Emails, PDFs, or server-rendered pages built
with f-strings/format from data. Fix: an auto-escaping template engine; never concatenate data into
HTML.

**A hand-rolled regex "sanitizer."** Stripping `<script>` with a regex and calling HTML safe —
endlessly bypassable (`<img onerror>`, encoded payloads, mutation XSS). Fix: a vetted allowlist
sanitizer (DOMPurify); never parse/filter HTML with regex.

**Ignoring URL and attribute contexts.** HTML-encoding a value into an `href` and thinking it's safe,
while `javascript:` schemes still execute. Fix: validate URL schemes (allowlist `https`/`mailto`);
always quote attributes.

**Tokens in `localStorage`.** Storing the session token where any XSS can read it, turning every XSS
into token theft. Fix: `HttpOnly` cookies (Chapter 02), so an XSS can't harvest the credential.

## AI Mistakes

XSS is a domain where assistant output renders content correctly and executes attacker script,
because the payload only fires on hostile input. Review every render of user content for how it's
encoded, and every bypass of the framework default for a sanitizer.

### Claude Code: `dangerouslySetInnerHTML` to render user content

Asked to render user-provided content that "might contain formatting" — an invoice note, a
description, a preview — Claude Code frequently reaches for `dangerouslySetInnerHTML={{ __html:
content }}` (or `v-html`, or `element.innerHTML = content`) to make the HTML render. It displays the
formatting correctly, so it looks like the right call — and it renders any `<script>`,
`<img onerror>`, or event handler in the content as executable code. Stored in a field shown to
others, it's stored XSS hitting every viewer including admins.

**Detect:** `dangerouslySetInnerHTML`, `v-html`, or `innerHTML =` anywhere with user- or
API-derived content; raw HTML rendering not wrapped in a sanitizer; the same pattern used for
"preview" or "formatted" fields.

**Fix:** render as text, or sanitize in one place:

> Never pass user or API content to `dangerouslySetInnerHTML`/`v-html`/`innerHTML`. Render it as
> text in `{}` so React encodes it. If it must render as HTML (rich text), route it through a single
> sanitizing component using DOMPurify with a minimal allowlist. Add a test that a `<script>` /
> `onerror` payload renders inert.

### GPT: server-side HTML built by string concatenation

GPT-family models, when generating emails, PDFs, or any server-rendered HTML, often build it with
f-strings or `.format()` — `f"<h1>Invoice for {customer_name}</h1>"` — outside any framework's
auto-escaping. Invoice and customer data flows straight into HTML, so a customer name containing
markup injects into every generated email and PDF. It's the server-side twin of the SQL-string
mistake from Chapter 05, and it's invisible until the data is hostile.

**Detect:** HTML built with f-strings/`.format()`/concatenation from data; email/PDF templates
assembled as strings; a template engine used with autoescape disabled; `mark_safe`/`| safe` applied
to data-derived values.

**Fix:** auto-escaping templates, never concatenation:

> Generate all server-side HTML (emails, PDFs, pages) with an auto-escaping template engine
> (`autoescape=True`), passing data as template variables — never build HTML by string formatting.
> Do not use `mark_safe`/`| safe` on any data-derived value. Add a test that a payload in a data
> field is escaped in the output.

### Cursor: rendering DB-stored data raw while completing a display feature

Completing a component or endpoint that displays saved data, Cursor tends to treat data from the
database or an API response as trusted — building the DOM from it via `innerHTML`, or dropping it
into a raw-HTML render — because the immediate task is "show the saved content" and the data feels
internal. This is the exact belief that produces stored XSS: the payload was saved earlier (past a
UI with no encoding) and executes now, on render, in every viewer's session.

**Detect:** API/DB response fields written to the DOM via `innerHTML` or raw-HTML props; rendering
of stored fields (names, notes, messages) without encoding on the assumption they're trusted; DOM
built from a fetch response by string/HTML assembly.

**Fix:** stored data is untrusted at render:

> Treat all data from the database and API as untrusted when rendering — it may contain payloads
> stored earlier. Render it as text (framework-encoded), never via `innerHTML` or raw-HTML props;
> sanitize only genuine rich-text fields through the shared sanitizer. Add a stored-XSS test: save a
> `<script>` payload via the API, then assert it renders as text.

## Best Practices

**Encode on output, for the context; lean on the framework default.** Render user content as text so
React/Vue/templates auto-encode it; treat every bypass of that default as a decision requiring a
sanitizer or genuine trust.

**Treat all rendered data as untrusted — including your own stored data.** The trust boundary is
output, not origin; stored XSS lives in the belief that database data is safe.

**Sanitize user HTML with a vetted allowlist library, in one place.** DOMPurify with a minimal
tag/attribute allowlist, confined to a single component; never a hand-rolled regex; prefer Markdown
to avoid raw HTML entirely.

**Auto-escape server-generated HTML too.** Emails, PDFs, and server-rendered pages built with an
auto-escaping engine, never string concatenation — the surface frameworks don't cover.

**Validate URL schemes and quote attributes.** User links routed through one component that
allowlists `https`/`mailto` and blocks `javascript:`/`data:`; attributes always quoted.

**Deploy a strict CSP as the backstop.** `script-src 'self'`, no `unsafe-inline`/`unsafe-eval`,
nonces/hashes for necessary inline script; roll out report-only first. A wall behind encoding, never
a replacement.

**Keep tokens in `HttpOnly` cookies.** So an XSS that does occur can't steal the session credential
(Chapter 02) — the highest-leverage blast-radius reduction.

**Test with real payloads.** Stored and reflected `<script>`/`onerror`/`javascript:` payloads
asserted inert, sanitizer tests, and a CSP-present check — green in CI.

## Anti-Patterns

**The Raw HTML Render.** User content passed to `dangerouslySetInnerHTML`/`v-html`/`innerHTML`. The
tell: raw-HTML APIs with user- or API-derived content; no sanitizer in the path.

**The Trusted Database.** Stored data rendered without encoding. The tell: DB/API fields written to
the DOM raw; "it's our data" as the reason it's unescaped; stored XSS in a name or note field.

**The Concatenated Template.** Server HTML built by string formatting. The tell: f-string HTML;
emails/PDFs assembled as strings; autoescape disabled or `mark_safe` on data.

**The Regex Sanitizer.** HTML "sanitized" by stripping patterns. The tell: a regex removing
`<script>`; a hand-rolled `clean_html`; bypasses via `onerror`/encoding/mutation XSS.

**The Cosmetic CSP.** A CSP with `unsafe-inline`/`unsafe-eval` that permits the injection it claims
to stop. The tell: `script-src` including `unsafe-inline`; a CSP present but toothless.

**The localStorage Token.** Session token readable by any script. The tell: `localStorage.setItem`
for a token; auth state in JS-reachable storage; any XSS becoming full account theft.

## Decision Tree

"I'm rendering user- or data-derived content — how do I do it safely?"

```
Does this content need to render as HTML (formatting), or as text?
├── as TEXT (names, descriptions, most fields)
│     └─► render in the framework's encoded context ({value} in React). done — auto-encoded.
│         NEVER innerHTML / dangerouslySetInnerHTML / v-html for this.
│
├── as HTML (rich text: bold, links, lists)
│     ├── can it be Markdown instead? ─► yes: render Markdown through a safe renderer. simpler & safer.
│     └── must be raw HTML ─► sanitize with DOMPurify (allowlist of tags/attrs) in ONE component.
│                             never a regex/blocklist. force safe URL schemes on links.
│
├── is it a URL (href/src)?
│     └─► allowlist the scheme (https/mailto); reject javascript:/data:. encoding alone isn't enough.
│
└── is it SERVER-generated HTML (email, PDF, SSR)?
      └─► auto-escaping template engine, data as variables. never string-concatenate HTML.

Across all of it, defense in depth:
   · treat DB/API data as untrusted at render (stored XSS)
   · strict CSP (script-src 'self', no unsafe-inline) as the backstop
   · tokens in HttpOnly cookies so an XSS can't steal them (Ch 02)
```

## Checklist

### Implementation Checklist

- [ ] User/data content renders through the framework's encoded context (`{value}`), not `innerHTML`/`dangerouslySetInnerHTML`/`v-html`.
- [ ] Rich-text (HTML) fields are sanitized with a vetted allowlist library (DOMPurify) in a single component; no hand-rolled regex sanitizer exists.
- [ ] User-provided URLs are scheme-allowlisted (`https`/`mailto`), blocking `javascript:`/`data:`.
- [ ] Server-generated HTML (emails, PDFs, SSR) uses an auto-escaping engine; no HTML is built by string concatenation.
- [ ] A strict CSP (`script-src 'self'`, no `unsafe-inline`/`unsafe-eval`) is set on responses.
- [ ] Stored and reflected XSS payloads are tested and render inert; a CSP-present check exists.

### Architecture Checklist

- [ ] Raw-HTML rendering is confined to one audited, sanitizing component; the dangerous API has a single legitimate home.
- [ ] The sanitization policy (allowlist) is centralized and reviewed once, not configured per use.
- [ ] All rendered data is treated as untrusted regardless of source, closing the stored-XSS gap.
- [ ] Session tokens are in `HttpOnly` cookies (Chapter 02), so an XSS cannot exfiltrate them.
- [ ] CSP is versioned/managed alongside the other security headers (Chapter 07), rolled out report-only before enforce.

### Code Review Checklist

- [ ] No `dangerouslySetInnerHTML`/`v-html`/`innerHTML` receives user- or API-derived content without going through the sanitizer.
- [ ] No server-side HTML is built by f-string/`.format()`/concatenation; no `mark_safe`/`| safe` on data-derived values.
- [ ] No hand-rolled regex is used to sanitize HTML.
- [ ] User-provided links validate their scheme; attributes are quoted.
- [ ] New render paths for stored data include a stored-XSS test.

### Deployment Checklist

- [ ] CSP is enforced (not just report-only) in production, with a report endpoint monitored for violations.
- [ ] Security headers (CSP, and the Chapter 07 set) are set at the edge/middleware on every response, including error pages.
- [ ] The DOMPurify/sanitizer dependency is kept current (sanitizer bypasses are patched over time).
- [ ] Third-party scripts (analytics, widgets) are inventoried and constrained by CSP, not blanket-allowed with `unsafe-inline`.

## Exercises

**1. Land a stored XSS, then close it.** In a rendering path that uses raw HTML (or build one),
store a `<script>` or `<img onerror>` payload through the normal UI and show it executes when another
user views the record. Then switch to encoded rendering (or the sanitizer) and show the payload
renders as inert text. The artifact is the exploit, the fix, and the stored-XSS test.

**2. Break a regex sanitizer.** Take a hand-rolled regex HTML sanitizer (write a plausible one).
Craft payloads that bypass it (`<img onerror>`, case/encoding tricks, mutation XSS). Then replace it
with DOMPurify and show the same payloads are neutralized. The artifact is the bypasses and the
allowlist config that stops them.

**3. Roll out a strict CSP.** Add a Content Security Policy to your app in report-only mode, collect
the violations (inline scripts, external origins), fix or nonce them, then switch to enforce.
Demonstrate that an injected inline `<script>` no longer executes under the enforced policy. The
artifact is the before/after policy and the blocked-injection proof.

**4. Prove the token-storage difference.** Store a token in `localStorage` and simulate an XSS that
reads and exfiltrates it. Then move the token to an `HttpOnly` cookie and show the same XSS can no
longer read it (while still, honestly, being able to act in-page). The artifact is the two runs
demonstrating the blast-radius difference.

## Further Reading

- **OWASP Cross-Site Scripting Prevention Cheat Sheet (cheatsheetseries.owasp.org)** — the
  authoritative rules for context-aware output encoding and the framework-bypass cases this chapter
  audits.
- **OWASP DOM-based XSS Prevention Cheat Sheet** — the client-side sink/source model (`innerHTML`,
  `location`, `eval`) for the DOM XSS shape that never touches the server.
- **DOMPurify (github.com/cure53/DOMPurify)** — the vetted allowlist HTML sanitizer this chapter uses;
  its documentation covers safe configuration and why regex sanitizers fail.
- **MDN — Content Security Policy (developer.mozilla.org)** and **content-security-policy.com** — the
  CSP directives, nonce/hash usage, and report-only rollout the backstop relies on.
- **Chapter 02 — JWT Security** (token storage and the `HttpOnly` decision) and **Chapter 07 — CSRF,
  CORS & Browser Security** (the rest of the security-header response and the CSRF defense HttpOnly
  cookies require) — the chapters this one connects to on both sides.

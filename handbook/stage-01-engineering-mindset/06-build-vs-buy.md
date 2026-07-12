# Build vs Buy

## Introduction

Build vs buy is the decision of whether to construct a capability yourself or
acquire it from someone else — a library, an open-source project, or a paid
service. Stated that way it sounds like a procurement question. It is
actually one of the highest-leverage engineering decisions you make, because
every "build" is a permanent liability you have agreed to own, and every
"buy" is a dependency you have agreed to live inside.

The decision has a strong default that most engineers get backwards: **build
only what differentiates you; buy everything else.** Your engineering time is
the scarcest resource you have, and spending it on authentication, email
delivery, or full-text search — problems thousands of companies have already
solved — is spending your one advantage on work that makes you no different
from anyone else. The instinct to build is strong because building is
satisfying and feels like "real engineering." That instinct, unexamined, is
how teams end up maintaining a mediocre in-house version of a solved problem
while the thing that actually distinguishes their product goes underfunded.

This chapter builds directly on the two before it. Chapter 04 gave you the
method for weighing options with no clean winner; build vs buy is that method
applied to one recurring, high-stakes choice. Chapter 05 established that
everything you build is debt you service forever; build vs buy is the
decision of whether to take on that debt at all. And AI has quietly tilted
the whole thing, by making "build" look cheaper and more finished than it has
ever looked — which is exactly when a strong default matters most.

## Why It Matters

The cost of building is almost universally underestimated, because people
price the first version and forget the rest. The first version is the cheap
part. What follows is perpetual: bug fixes, security patches, edge cases
discovered in production, scaling work, the on-call burden, documentation for
each new hire, and — largest of all — the opportunity cost of every hour
spent maintaining it instead of improving your product. A commodity you build
is not a one-time cost; it is a subscription you pay in engineering attention,
forever, whether or not you ever look at the invoice.

The failure is most brutal in security-sensitive commodities. An engineer can
stand up a working authentication system quickly — login, tokens, a password
field. What they have not built is the part that matters: rate limiting,
credential-stuffing defense, secure password reset, session revocation,
multi-factor auth, breach monitoring, and the standing obligation to respond
when a new attack class appears. A managed provider's entire value is that
they own that surface and the liability attached to it. When you build auth,
you have not saved a subscription fee — you have made yourself liable for a
breach.

AI sharpens this precisely where it is most dangerous. It collapses the
visible cost of building — the first version now takes an afternoon instead of
a month — while doing nothing to the invisible cost of ownership. Worse, it
makes the first version *look* complete, because it produces the happy path
fluently and stays silent about the ninety percent of a commodity that is not
the happy path. The economic signal that used to steer you toward buying
commodity infrastructure — "building this is obviously too much work" — has
been muffled at the exact moment the ownership cost stayed the same. The
default in this chapter is your replacement for that missing signal.

## Mental Model

Every capability your product needs sits somewhere on one axis, and that
position decides almost everything:

```
   COMMODITY  ◄──────────────────────────────────────►  DIFFERENTIATOR
   (undifferentiated heavy lifting)              (why customers choose you)

   auth · email · payments · search ·        your core algorithm, the
   PDF generation · monitoring · queues      workflow only you do well,
   · file storage · feature flags            the data or insight that
                                             is your moat

   ── BUY / ADOPT ──                          ── BUILD ──
   Someone else owns the liability.           This is where your scarce
   You buy back your engineering time.        engineering time earns its
                                              return. Owning it IS the point.
```

Two refinements turn the axis into a usable method.

**Ownership is the real cost, not construction.** The question is never "can
we build this?" — with enough time and an AI assistant, you can build almost
anything. The question is "do we want to *own* this forever?" Buying is
fundamentally the purchase of someone else owning a problem: its edge cases,
its security surface, its scaling, its 3 AM pages. Price the ownership, not
the build.

```
   Cost of BUILD  =  first version  +  maintenance + security + scaling
                     (the cheap,        + on-call + docs + opportunity cost
                      visible part)        (the expensive, invisible,
                                            PERPETUAL part)

   Cost of BUY    =  subscription/usage  +  integration  +  lock-in
                     (visible, scales        (one-time-ish)   (a one-way door
                      with you)                                — Chapter 04)
```

**The decision decomposes; it is rarely all-or-nothing.** The mature pattern
is *buy the commodity core and build the thin differentiating layer on top*.
You do not build a payment processor — you buy Stripe and build the pricing
logic that is specific to your business. You do not build a search engine —
you use what your database already offers and build the ranking rules that
encode your domain. Almost every real capability splits into commodity
plumbing (buy) and a differentiating slice (build).

A working definition:

> **Build vs buy is deciding whether a capability is worth owning forever.
> Build only what differentiates you; buy the rest — and weigh the cost of
> owning it, not the cost of the first version.**

## Real-World Scenario

**Invoicely**, still around 2,500 customers. Two build-vs-buy decisions land
in the same sprint, and in the background sits the capability that is
actually the company's reason to exist.

### Decision one: search

Customers with thousands of invoices cannot find anything, so "search across
invoices" is on the roadmap. A capable engineer is excited about it and
proposes building a proper search system — a custom indexer, relevance
scoring, the works. It is, they argue, core functionality.

It is not. Search is a commodity: nearly every product has it, and none of
Invoicely's customers chose it *for* its search. The options, weighed by
Chapter 04's method:

- **Build a custom search engine.** *Buys:* total control. *Spends:* months
  of work reinventing solved problems (tokenization, stemming, ranking), plus
  perpetual ownership of all of it. Pure resume-driven building — the engineer
  is drawn to it because it is interesting, not because it is valuable.
  Rejected.
- **Buy a managed search service** (a hosted search product). *Buys:*
  excellent search, owned by someone else. *Spends:* a monthly bill that
  grows with data, a new vendor dependency, and integration work — for a
  scale Invoicely has not reached.
- **Use the database's built-in full-text search** (the boring option).
  *Buys:* good-enough search at current scale, no new dependency, days not
  months. *Spends:* it will not scale forever, and it lacks the polish of a
  dedicated service.

The decision: **the boring built-in option now**, with a recorded trigger
(Chapter 05's discipline) to revisit and buy a managed service if search
latency or relevance becomes a real complaint at larger scale. Good-enough
commodity, cheapest ownership, reversible.

### Decision two: the afternoon auth prototype

In the same sprint, an eager engineer arrives with a demo: *"I replaced our
auth provider with a custom JWT system over the weekend — look, login works,
and we'll save the subscription fee."* An AI assistant generated most of it,
and the demo is genuinely convincing: sign up, log in, a token, a protected
route.

The team asks one question — *what does our current provider do that this
doesn't?* — and lists it: password reset that resists enumeration, rate
limiting and lockout, credential-stuffing detection, MFA, session revocation,
audit logging, SSO for the enterprise accounts sales is chasing, SOC 2
evidence, and a security team whose job is to patch the next vulnerability
class before it reaches Invoicely. The prototype has none of it. It is not an
auth system; it is the ten percent of one that is fun to build. **Building it
would not save a subscription fee — it would make a four-person team liable
for every credential breach, forever.** Decision: keep buying auth. The
prototype is deleted, and the weekend is chalked up as a lesson about what AI
makes look finished.

### The background: the thing actually worth building

While two commodities almost got built, the reconciliation engine — the
matching logic from Chapter 02 that measurably reduced churn, the one
capability customers genuinely choose Invoicely *for* — had a backlog of
accuracy improvements nobody had staffed. This is the whole lesson in one
frame: **the team's build instinct was aimed at exactly the wrong targets.**
Search and auth are commodities to buy; reconciliation is the differentiator
to build.

And even reconciliation decomposes. The team does not build its own
infrastructure to run it — it buys the database, the queue, the hosting. It
builds only the matching algorithm itself, because that thin slice is the
part no vendor sells and the part that is the moat. Buy the plumbing, build
the differentiator, integrate.

The reallocation: buy auth (unchanged), use built-in search (days), and
redirect the search-engine and auth-rewrite time into reconciliation
accuracy — the one place where a week of engineering produces something a
competitor cannot simply purchase.

## Engineering Decisions

Four decisions inside that scenario recur in every build-vs-buy call.

### Is this a differentiator or a commodity?

**Options:** (1) treat the capability as core and build it; (2) treat it as
commodity and buy it.

**Trade-offs:** the honest test is "do customers choose us because of this,
or do they simply expect it to exist?" Search and auth are expected;
reconciliation is chosen. Misjudging this axis is the root error — building a
commodity wastes your scarce engineering on undifferentiated work, while
buying a differentiator hands your competitive advantage to a vendor.

**Recommendation:** classify against the differentiator test *first*, before
any cost analysis, because it determines which way the default points.
Everything downstream — cost, lock-in, decomposition — is secondary to
getting this axis right. Be ruthless: most capabilities are commodities, and
the feeling that something is "core" is often just the feeling that it is
interesting to build.

### What is the true cost of building?

**Options:** (1) estimate the first version; (2) estimate the total cost of
ownership across its life.

**Trade-offs:** the first-version estimate is easy, concrete, and wrong by an
order of magnitude — it ignores the perpetual maintenance, security, scaling,
and opportunity costs that dwarf construction. The lifetime estimate is
harder and full of uncertainty, but it is the only number that makes the
decision honestly.

**Recommendation:** always price ownership, not construction, and make the
opportunity cost explicit — "building this is a quarter of reconciliation
work we won't do." AI makes this discipline more important, not less: when
the first version costs an afternoon, the first-version estimate becomes even
more misleading relative to the unchanged ownership cost.

### How does the capability decompose?

**Options:** (1) build the whole thing; (2) buy the whole thing; (3) buy the
commodity core and build the thin differentiating layer.

**Trade-offs:** all-build and all-buy are both usually wrong for anything
non-trivial. All-build reinvents commodity plumbing; all-buy either can't
express your differentiator or forces you to bend a generic product into a
shape it resists (integration cost that can exceed building). Decomposing
takes design thought up front but produces the right allocation of effort.

**Recommendation:** decompose by default. Find the commodity substrate to buy
(processing, search infrastructure, hosting) and the differentiating slice to
build (your pricing rules, your matching logic, your ranking). This is the
pattern behind almost every well-engineered system.

### How much lock-in are you accepting?

**Options:** (1) choose the buy option purely on features and price;
(2) weight switching cost and data portability as first-class factors.

**Trade-offs:** ignoring lock-in optimizes the decision you are making today
and mortgages the one you'll face when the vendor triples its price, degrades,
or becomes your competitor. Weighting exit cost may mean choosing a slightly
less capable option with open standards and clean data export — trading some
capability now for reversibility later.

**Recommendation:** treat lock-in as an explicit cost (Chapter 04's one-way
door) and prefer buy options with real exit paths — standard protocols, full
data export. For a deep vendor commitment, record it as an ADR
([`templates/adr.md`](../../templates/adr.md)) with the switching cost and a
revisit trigger written down, so the dependency is a decision and not a trap.

## Trade-offs

The buy-default is a default, not a law, and buying has genuine costs that
sometimes justify building.

**Buy has recurring and structural costs.** A subscription that scales with
your usage can eventually exceed the cost of building; vendor lock-in is a
one-way door; feature limits you cannot work around can block your roadmap;
and you inherit the vendor's uptime, pricing changes, and roadmap priorities.
"Buy" is not "solved and forgotten" — it is a dependency you must manage.

**Legitimate reasons to build a commodity exist.** When the buy option's cost
or lock-in is genuinely unacceptable at your scale; when no adequate solution
exists; when regulatory or data-residency constraints forbid sending data to
a third party; or when the commodity is so central to your economics that
owning it becomes a differentiator (a company doing millions of transactions
may correctly build what a startup should buy). The key is that these are
*reasoned* exceptions with the ownership cost accepted open-eyed — not the
default reflex to build.

**"Buy" can quietly become "build anyway."** A poorly-fitting purchased tool
that you bend into shape with mountains of glue code and workarounds can cost
more than building would have. Integration is a real, often underestimated
cost of buying; a bad fit is not a bargain.

**Self-hosted open source is a third option, not free.** Adopting an
open-source project instead of a paid service avoids the subscription and the
lock-in — but you take on the operational burden: deployment, upgrades,
scaling, security patching, and the on-call. "Free" open source frequently
costs more in engineering time than the paid service it replaced. It sits
between build and buy, and it must be priced like the ownership commitment it
is.

## Common Mistakes

**Building the commodity because it's interesting.** The search-engine
proposal — reaching for the fun, impressive-looking build while a solved
problem gets reinvented. It is resume-driven development (Chapter 04) aimed at
infrastructure. Fix: apply the differentiator test honestly, and notice when
"this is core" is really "this is interesting to build."

**Pricing the first version instead of ownership.** Deciding to build because
the prototype is cheap, ignoring the perpetual maintenance, security, and
opportunity cost that follow. Fix: estimate total cost of ownership over
years, and always name the opportunity cost in terms of the differentiator
work you won't do.

**Buying (or outsourcing) the differentiator.** The inverse error: handing
your actual moat to a vendor to save short-term effort, after which the vendor
owns your competitive advantage — and can raise prices, degrade, or become
your competitor. Fix: whatever customers choose you *for* stays in-house, even
when a vendor offers something adjacent.

**Ignoring lock-in.** Choosing a vendor on features and price alone, then
discovering the switching cost is a rewrite when the terms change. Fix: weight
data portability and exit cost as first-class criteria; prefer open standards;
record deep commitments as ADRs.

**Treating self-hosted open source as free.** Adopting an OSS tool to dodge a
subscription while ignoring the operational and security burden you just
signed up to own. Fix: price the operational cost — including on-call and
patching — and compare it honestly to the paid option's fee.

## AI Mistakes

Every failure below shares one direction: **AI systematically tilts the scale
toward Build**, by making building feel cheap, complete, and frictionless —
while the very thing that makes Buy worthwhile, someone else owning the
liability, is precisely what an assistant cannot provide. Your countermeasure
is to force the buy option and the full ownership surface onto the table
before deciding.

### Claude Code: the finished-looking facade

Asked to build a commodity — auth, a payment flow, a search feature — Claude
Code produces something that passes the demo and omits the ninety percent
that is not the happy path: the security edge cases, the compliance surface,
the operational tooling, the failure handling. The result *looks* like a
finished system, which biases the build-vs-buy decision toward Build by
hiding how much of the commodity is actually missing — the afternoon auth
prototype exactly.

**Detect:** the prototype handles the core flow and nothing around it — no
rate limiting, no password reset, no audit log, no failure paths. Compare its
surface to what a mature vendor in that space actually covers.

**Fix:** before deciding to build, make the assistant enumerate the real
surface:

> List everything a production-grade version of this must handle — security,
> edge cases, compliance, scale, operations — that a prototype would omit.
> Compare that list to what an existing provider offers. Then tell me whether
> building or buying is the sounder call, and why.

The enumerated list, more often than not, makes the case for buying on its
own.

### GPT: the solution-generation reflex

Ask a GPT-family model "how do I add search / auth / notifications to my
app," and its reflex is to hand you an implementation — code to *build* the
thing — rather than to surface that a mature product or library already solves
it. It answers the literal "how do I build this" and never raises the prior
question, "should I build this at all?" The result is that the buy option
never enters the conversation.

**Detect:** you asked a "how do I add X" question and received an
implementation, when the better answer was "adopt this existing tool." No
existing products or libraries were mentioned as alternatives.

**Fix:** ask the build-vs-buy question explicitly, because the model won't:

> Before writing any code: what existing products, services, and libraries
> already solve this? For each, when would building it myself be justified
> over adopting it? Only propose an implementation if building is actually
> the better choice.

### Cursor: buying, then building it anyway

When integrating a purchased tool, inline assistants tend to generate glue
code that *reimplements the vendor's own features* rather than calling them —
writing custom tax logic beside a payment SDK that offers tax calculation,
hand-rolling retry logic the client library already provides — because the
completion is driven by local patterns, not by the vendor's full capability
set. You end up paying to buy and building anyway, getting the worst of both.

**Detect:** integration code that duplicates functionality the vendor already
provides. The tell is custom logic sitting right next to an SDK that has a
built-in method for exactly that job.

**Fix:** anchor the assistant to the vendor's capabilities before it writes
glue:

> We are using this SDK — here are its capabilities. Before implementing
> anything, check whether the SDK already does it. Only write custom code for
> what the vendor genuinely does not provide.

## Best Practices

**Default to buy for commodity; reserve build for your differentiator.** Make
the differentiator test the first question, and state explicitly what your
differentiator actually is — the capability customers choose you for. Your
scarce engineering time goes there, and almost nowhere else.

**Price ownership, not construction.** Estimate total cost of ownership —
maintenance, security, scaling, on-call, and opportunity cost — over years,
not the first version. Make the opportunity cost concrete: name the
differentiator work that building this commodity would displace.

**Decompose: buy the plumbing, build the thin slice.** Split every non-trivial
capability into its commodity substrate (buy) and its differentiating layer
(build). Buy the payment processor and build the pricing rules; use the
built-in search and build the domain ranking. This is where most good
engineering effort belongs.

**Treat lock-in as a cost and keep an exit path.** Weight switching cost and
data portability as first-class criteria, prefer open standards and clean
export, and record deep vendor commitments as ADRs
([`templates/adr.md`](../../templates/adr.md)) with the switching cost and a
revisit trigger. A dependency you chose deliberately is manageable; one you
fell into is a trap.

**Re-run the decision when scale changes.** The boring commodity option
(built-in search, a single database) is right until it isn't, and buy options
can get expensive at scale while build options can get cheaper. Attach a
revisit trigger to the choice (Chapters 04 and 05), so "good enough for now"
is a decision with an expiry, not a permanent accident.

## Anti-Patterns

**Not-Invented-Here.** Reflexively building everything in-house out of
distrust for external code or the belief that your needs are uniquely special.
It buries the team under commodity maintenance and starves the differentiator.
The tell: an in-house version of a widely-solved problem, justified by
requirements that turn out to be ordinary. (Joel Spolsky's essay in Further
Reading draws the line: build your core, not your commodities.)

**Resume-Driven Build.** Building the *interesting* commodity — a search
engine, a custom auth system, a homegrown queue — because it is fun and
impressive, while the actual differentiator goes underfunded. It is Chapter
04's resume-driven architecture pointed at the build-vs-buy decision. The
tell: the excitement is about the technology, not about the customer value.

**Outsourcing the Moat.** Buying or outsourcing the one capability that is
your competitive advantage, to save short-term effort. The vendor now owns
what makes you different and can raise prices, stagnate, or compete with you
directly. The tell: your differentiator appears as a line item on a vendor
invoice.

**"Free" Self-Hosting.** Adopting self-hosted open source specifically to
avoid a subscription, while ignoring the operational and security cost that
often exceeds the fee. The tell: the decision was justified by the sticker
price alone, with no accounting for the on-call rotation it just created.

**Buy-and-Build.** Paying for a tool and then reimplementing its features in
glue code — the Cursor failure at team scale. You carry both the subscription
and the maintenance. The tell: substantial custom logic doing what the vendor
you pay for already does.

## Decision Tree

"Should I build this or buy it?"

```
Is this capability a core differentiator — a reason customers choose us,
not just something they expect to exist?

├── YES (it's the moat) ──► BUILD it. This is where your engineering goes.
│                           (But still BUY its commodity sub-parts — you
│                            build the differentiating slice, not the
│                            plumbing under it.)
│
└── NO (it's commodity / undifferentiated heavy lifting)
    │
    Does an adequate solution exist to buy or adopt?
    │
    ├── YES
    │   │
    │   Is its cost or lock-in genuinely unacceptable at our scale?
    │   │
    │   ├── NO ──► BUY it. Weigh lock-in, prefer an exit path, build
    │   │          only thin glue. (Default outcome for most commodities.)
    │   │
    │   └── YES ─► Reconsider: self-host open source (price the ops
    │              burden honestly) or build — with the full ownership
    │              cost accepted open-eyed, recorded as an ADR.
    │
    └── NO adequate solution exists
            └──► You may have to build — but scope it to good-enough,
                 not gold-plated, and attach a revisit trigger to adopt
                 a real solution once one appears.
```

The most-skipped branch is the very first question. Engineers answer "is this
core?" with their build instinct instead of the customer's perspective — and
so they build the commodity that felt important and buy, or neglect, the
differentiator that actually was.

## Checklist

### Build-vs-Buy Judgment Checklist — before committing to build or buy

- [ ] I applied the differentiator test first: do customers choose us *for* this, or merely expect it?
- [ ] For a build, I estimated total cost of *ownership* over years — maintenance, security, scaling, on-call, opportunity — not just the first version.
- [ ] I named the opportunity cost concretely: what differentiator work this build displaces.
- [ ] I decomposed the capability into commodity plumbing (buy) and differentiating slice (build) rather than deciding all-or-nothing.
- [ ] For a buy, I weighed lock-in and data portability, and recorded deep commitments as an ADR with a switching cost and revisit trigger.
- [ ] If self-hosting open source, I priced the operational and security burden, not just the avoided fee.
- [ ] The choice has a revisit trigger for when scale changes the answer.

### Code Review Checklist — build-vs-buy concerns in the diff

- [ ] The change isn't reimplementing a feature a vendor we already pay for provides (no buy-and-build).
- [ ] A homegrown commodity subsystem isn't accreting here without anyone having made an explicit build decision.
- [ ] Any new self-built commodity has its ownership cost acknowledged (tests, security, docs), not just a happy-path prototype.
- [ ] New vendor dependencies are recorded, with their lock-in and exit path noted.
- [ ] AI-generated "just build it" code was checked against whether an existing tool should have been adopted instead.
- [ ] Integration/glue code uses the vendor's real capabilities rather than hand-rolling around them.

## Exercises

As before, these produce artifacts — do them in writing.

**1. The differentiator audit.** List your product's major capabilities and
mark each as commodity or differentiator using the customer-choice test. Then
map where your team's engineering time actually went last quarter. The
artifact is the two lists side by side, and the value is the mismatch almost
everyone finds: time spent building commodities while the differentiator
waited.

**2. The true-cost estimate.** Pick a commodity your team built or could build
in an afternoon with an assistant — auth, email, search, file uploads.
Estimate its real three-year cost of ownership (maintenance, security, on-call,
opportunity cost) and put it next to the annual price of buying it. The
artifact is the two numbers plus one sentence on which one surprised you —
usually the ownership cost, by a wide margin.

**3. The AI facade test.** Ask an assistant to build a commodity system — "a
login and signup system," say. Then ask it to enumerate everything a
production-grade authentication provider handles that the prototype does not.
The artifact is that gap list, which is the most direct demonstration of how
much of a commodity AI leaves invisible — and it usually makes the buy case by
itself.

## Further Reading

- **In Defense of Not-Invented-Here Syndrome** (Joel Spolsky,
  joelonsoftware.com, 2001) — the canonical statement of the differentiator
  rule and its crucial nuance: build your *core competency* in-house precisely
  because it is your advantage, and buy everything that isn't. Ages
  extraordinarily well.
- **Don't Reinvent The Wheel, Unless You Plan on Learning More About Wheels**
  (Jeff Atwood, codinghorror.com) — a balanced treatment of when reinventing a
  solved problem is and isn't justified, and how to tell the difference before
  you sink months into it.
- **"Undifferentiated heavy lifting"** (Werner Vogels / Amazon — search his
  talks and writing for the phrase) — the origin of the framing that you
  should offload commodity infrastructure so your scarce engineering goes to
  what actually differentiates you. The intellectual foundation of the
  buy-the-commodity default.
- **Falsehoods Programmers Believe About Names** (Patrick McKenzie,
  kalzumeus.com) — not about build-vs-buy directly, but the single best
  demonstration that "simple" commodity domains (names, addresses, time, email)
  are far deeper than they look. Read it as evidence for why buying commodities
  usually beats discovering their depth yourself, one production bug at a time.

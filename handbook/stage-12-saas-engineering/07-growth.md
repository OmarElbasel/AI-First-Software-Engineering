# Growth

## Introduction

Every chapter in this stage built an instrument: an MVP that tested demand, a pricing
model that maps value to money, a payment system that collects it, analytics that observe
behavior, a feedback pipeline that hears users, and a metrics layer that tells the truth
about all of it. Growth is where the instruments get spent. It is the capstone not because
it comes last chronologically but because it is meaningless without the rest — a growth
experiment without trustworthy metrics is a coin flip with a dashboard, and acquisition
poured into a product with broken retention is revenue rented by the month.

This chapter treats growth as an engineering discipline, because in an AI-first team it is
one. The work is not "marketing": it is identifying the loop your product natively runs on,
instrumenting its edges, removing friction at its weakest step, and proving the number
moved. For Invoicely that loop was hiding in plain sight the whole stage: **every invoice
is an email sent to someone who does not use Invoicely yet.** A tenant sending twenty
invoices a month is running twenty micro-demos of the product for exactly the audience —
small businesses that invoice — that no ad campaign targets as precisely. Chapter 02
refused to meter payment-link clicks for precisely this reason; this chapter explains what
that restraint was protecting and builds the machinery that harvests it.

The chapter also draws the line the industry blurs: growth *engineering* — instrumented
loops, honest experiments, arithmetic — versus growth *theater* — vanity launches, dark
patterns, and playbooks copied from products with different physics. An engineer who can
tell them apart is worth more to a SaaS company than one who can build either.

## Why It Matters

- **Retention gates everything upstream.** Acquisition into a product losing 8% of tenants
  a month is filling a leaky bucket at rising cost: the bucket's level plateaus where
  inflow equals leak, and every acquired cohort is a depreciating asset. The growth
  equation — net new = (new + reactivation + expansion) − (churn + contraction), straight
  from Chapter 06's movements view — makes the order of work arithmetic, not opinion.
- **Loops compound; channels saturate.** A paid channel buys each customer at a price that
  rises as the cheap audience depletes. A loop makes each cohort of users generate part of
  the next cohort — output feeding back into input — so the same engineering effort keeps
  paying every cycle. Loops are the only growth mechanism with the compounding shape that
  retention curves and MRR movements already taught this stage to look for.
- **The engineer is now the growth team.** In an AI-first company the person who ships the
  invoice-email template is the person best positioned to instrument it, attribute the
  signups it produces, and A/B its footer. Handing that to a separate "growth team" with
  its own fork of the codebase produces the untested, unreviewed, metric-gaming code this
  chapter's Anti-Patterns section catalogs.
- **Growth theater burns the scarcest resource.** A quarter spent on a referral program
  nobody asked for, a landing-page redesign that moved nothing, and three underpowered A/B
  tests is a quarter the runway does not give back. The judgment to *not* run those plays —
  and to say why, with numbers — is the cheapest growth work there is.
- **AI assistants are playbook machines.** Ask one "how do we grow" and you get the
  universal checklist; ask for "a referral program" and you get a competent implementation
  of the wrong loop. The assistant amplifies whatever growth thinking you bring — which is
  exactly why the thinking, not the implementation, is this chapter's subject.

## Mental Model

Three ideas: growth is a loop, not a funnel; the work has a forced order; and an
experiment is a contract with conditions that invalidate it.

**1. Funnels deplete; loops compound.** A funnel is linear: spend → visitors → signups →
customers, and next month you pay again. A loop closes: some output of *using* the product
becomes input to acquiring the next user. Invoicely's native loop:

```
        ┌──────────────────────────────────────────────────┐
        │                                                  │
        ▼                                                  │
  tenant sends invoice                                     │
        │                                                  │
        ▼                                                  │
  RECIPIENT gets a clean email + hosted payment link       │
  (a non-user, experiencing the product's best moment      │
   from the receiving end — and they invoice people too)   │
        │                                                  │
        ▼                                                  │
  recipient pays → sees "Powered by Invoicely —            │
  invoices like this one, free" → some click, sign up      │
        │                                                  │
        ▼                                                  │
  new tenant activates (first invoice PAID, Ch 06) ────────┘

  Loop math, per cycle (a month):
    K = new activated tenants attributed to the loop
        ─────────────────────────────────────────────
        tenants actively sending during the month

  K < 1 (SaaS reality: 0.1–0.3): the loop AMPLIFIES other
  acquisition — every 100 tenants recruit 15–30 more, forever,
  at zero marginal cost. K is a product of edge conversions:

    K = invoices/sender × view rate × footer CTR
        × signup rate × activation rate

  Five edges. Growth engineering = measuring all five and
  fixing the WORST one. Growth theater = redesigning the
  logo on the footer.
```

The loop is why Chapter 02's rule — never meter the growth loop — has teeth: capping
payment-link views would price the product's own distribution.

**2. The order of work is forced: retention → activation → loop → paid.** Fix them
backwards and each layer wastes the one below. Improving retention lifts the value of
every past and future cohort; improving activation lifts every acquisition source at once;
the loop multiplies whatever acquisition exists; paid channels multiply *cost* unless the
layers beneath convert. The metric tree from Chapter 06 is the map: you work the lowest
broken node first, and "broken" is a number, not a feeling.

**3. An experiment is a contract, and most changes don't deserve one.** The statistics of
significance testing are out of this handbook's scope; the *judgment* is not. An
experiment is worth running when the traffic can detect the effect you care about in weeks
(a 7-percentage-point activation lift at ~250 signups/week: detectable in about a month;
a 1-point lift: don't bother), when the change is cheap to run both arms of, and when
being wrong is expensive enough to pay for proof. Everything else ships with judgment, a
guardrail metric, and a rollback path. And a valid experiment dies the moment you peek at
results daily and stop at the first good-looking number, change the arms mid-flight, mix
cohorts across the boundary of another launch, or declare success on a metric you picked
after seeing the data. Invalidation is silent — the dashboard still renders — which is why
the contract is written before the traffic starts.

A working definition:

> **Growth is the engineering of compounding acquisition: identify the loop your product
> natively runs on, instrument every edge of it, work the metric tree bottom-up —
> retention, then activation, then the loop, then paid — one measured bet at a time, each
> bet owned, guardrailed, and honest enough to survive its own results.**

## Production Example

Chapter 06 left Invoicely with trustworthy numbers and an uncomfortable reading: activation
stuck at 34%, gross MRR churn dominated by contraction, acquisition flat at ~250
signups/week, and a REFERRAL node in the metric tree with no data behind it. The founder's
instinct is paid ads. The team runs the arithmetic first: at 34% activation and current
week-4 retention, a paid signup returns roughly 60% of its cost in the first year — ads
would scale a loss. The tree says the order is activation, then the loop.

**Bet 1 — onboarding aimed at the activation moment (six weeks).** Chapter 06 chose
activation empirically: first invoice *paid* within 14 days. The funnel (Ch 04) shows the
cliff is not creating an invoice — 71% do that — but between *sent* and *paid*. Two
changes: payment reminders default to ON for the first invoice (the Ch 06 leading
indicator, made a default instead of a setting), and a post-send screen that prompts
sending a test invoice to yourself so tenants see what recipients see. Run as a real
experiment — 50/50 assignment at signup, contract written first, four weeks, guardrail on
unsubscribe complaints. Result: activation 34% → 41%. Every acquisition source, including
the untouched ones, now converts better.

**Bet 2 — instrument the loop that already runs (two weeks).** The invoice email has
carried a "Powered by Invoicely" footer since the MVP — unlinked, untracked, pure
decoration. The team makes it a measured edge: footer links carry a signed token naming
the sending tenant and invoice, a landing page converts recipient context into a signup,
and attribution is written server-side at tenant creation — first touch, one row, from the
token, not from UTM guesswork. First honest read: K = 0.14, with the weakest edge the
footer's click-through (0.9%). One copy change — "Get paid like this — free" with the
recipient's just-completed payment as social proof — lifts CTR to 2.1%; K reaches 0.23.
At current volume that is ~55 free activated tenants a month, compounding.

**Bet 3 — the save flow (two weeks).** Contraction and cancellation both funnel through
one screen. The rebuilt flow asks one question (reason, four options), makes one honest
offer keyed to the answer — pause two months for seasonal businesses, Professional
downgrade for "too expensive," a support escalation for the Xero-shaped answers Chapter 05
flagged — and then cancels cleanly, per Chapter 02's safe-to-leave rule. No maze, no
guilt. Measured against Chapter 06's period-end churn: 14% of cancel intents accept pause
or downgrade, and paused tenants return 60% of the time. Logo churn drops 0.4 points.

**The rejected bet** matters as much: an incentivized referral program ($10 credit per
invite) was scoped, then killed — the native loop was still cheap to improve, incentives
add a fraud surface (Stage 9's problem) and a cost per signup, and the team had one
quarter of attention. It goes in the experiment log as *not run, and why*, so the next
hire doesn't re-litigate it from zero.

## Folder Structure

Growth code is product code — reviewed, tested, feature-flagged, living in the same app:

```
app/
├── growth/
│   ├── attribution.py        # signed footer tokens; first-touch attribution
│   │                         #   written server-side at tenant creation
│   ├── router.py             # GET /via/{token} landing redirect + cookie;
│   │                         #   nothing else — signup stays in auth's router
│   ├── experiments.py        # deterministic assignment: hash(tenant_id, exp_name)
│   │                         #   → arm; assignment tracked as a Ch 04 event
│   ├── save_flow.py          # cancel-intent offers: pause / downgrade / escalate
│   └── onboarding.py         # first-run checklist state (reminder default, test-send)
├── invoicing/
│   └── emails.py             # invoice email template — footer built by ONE helper
│                             #   from attribution.py; no hand-built links
└── metrics/
    └── views/
        └── referral_loop.sql # the five edges + K, monthly — joins attribution
                              #   to snapshots; read beside mrr_movements
docs/
└── experiments/
    ├── LOG.md                # every bet: hypothesis, dates, result, decision —
    │                         #   including bets REJECTED and why
    └── 2026-Q3-onboarding-reminders.md   # one contract per experiment
tests/
└── growth/
    ├── test_attribution.py   # token round-trip; tamper rejection; first-touch wins
    └── test_experiments.py   # assignment is deterministic, stable, and 50/50
```

Why each piece exists: `attribution.py` owns link-building *and* token verification so the
footer can't drift from the parser (the Cursor failure below). `experiments.py` is ten
lines on purpose — assignment must be boring, deterministic, and identical everywhere it's
called. `referral_loop.sql` lives in the metrics layer, not in `growth/`, because K is a
metric and Chapter 06's rules apply to it: one view, fixture-tested, no dashboard computes
its own. `docs/experiments/LOG.md` is the institutional memory that stops the team from
running 2026's failed experiment again in 2028.

## Implementation

Attribution first — the loop is invisible until this exists. The footer link carries a
signed, non-guessable token; the landing sets a cookie; signup writes one append-only row:

```python
# app/growth/attribution.py
from itsdangerous import URLSafeSerializer, BadSignature

_signer = URLSafeSerializer(settings.attribution_secret, salt="invoice-footer")

def footer_url(invoice: Invoice) -> str:
    """The ONLY place footer links are built. Email templates call this."""
    token = _signer.dumps({"t": str(invoice.tenant_id), "i": str(invoice.id)})
    return f"{settings.app_url}/via/{token}"

def parse_token(token: str) -> dict | None:
    try:
        return _signer.loads(token)
    except BadSignature:
        return None          # tampered/expired: land normally, attribute nothing


class SignupAttribution(Base):
    """One row per tenant, written at creation, never updated.
    First touch wins; a later ad click does not rewrite history."""
    __tablename__ = "signup_attributions"

    tenant_id: Mapped[UUID] = mapped_column(primary_key=True)
    source: Mapped[str]                      # 'invoice_footer' | 'organic' | 'paid:...'
    referrer_tenant_id: Mapped[UUID | None]  # who sent the invoice
    created_at: Mapped[datetime]
```

The signup handler consumes the cookie once, server-side — no client analytics involved,
because attribution feeds revenue math and Chapter 06 banned money-adjacent facts from the
lossy pipeline:

```python
# in auth's signup flow, after the tenant row commits
def record_attribution(session: Session, tenant: Tenant, request: Request) -> None:
    claims = parse_token(request.cookies.get("via", ""))
    session.add(SignupAttribution(
        tenant_id=tenant.id,
        source="invoice_footer" if claims else infer_source(request),  # utm fallback,
        referrer_tenant_id=UUID(claims["t"]) if claims else None,      # labeled 'directional'
        created_at=utcnow(),
    ))
```

The loop as a metric — five edges and K, computed in the metrics layer under Chapter 06's
rules (snapshot-joined, fixture-tested, one view that every dashboard reads):

```sql
-- app/metrics/views/referral_loop.sql
CREATE OR REPLACE VIEW referral_loop AS
SELECT month,
       active_senders,                              -- tenants who sent ≥1 invoice
       footer_clicks::numeric / NULLIF(link_views, 0)      AS footer_ctr,
       signups::numeric       / NULLIF(footer_clicks, 0)   AS signup_rate,
       activated::numeric     / NULLIF(signups, 0)         AS loop_activation,
       activated::numeric     / NULLIF(active_senders, 0)  AS k_factor
FROM referral_loop_edges                            -- CTE over attribution rows,
GROUP BY month, active_senders;                     -- events, and snapshots
```

Experiment assignment — deterministic, stable, and recorded, so any analyst can rebuild
the arms from raw data months later:

```python
# app/growth/experiments.py
def assign(tenant_id: UUID, experiment: str, arms: int = 2) -> int:
    """Same tenant + experiment → same arm, every call, every machine."""
    digest = sha256(f"{experiment}:{tenant_id}".encode()).digest()
    return int.from_bytes(digest[:4], "big") % arms

# at signup, once:
arm = assign(tenant.id, "onboarding-reminders-2026q3")
track(user.id, tenant.id, ExperimentAssigned(          # Ch 04 event — analysis
    experiment="onboarding-reminders-2026q3", arm=arm)) # joins on this
```

The save flow reuses machinery this stage already built: pause is a Stripe subscription
pause (Ch 03's state machine gains one transition), downgrade is Chapter 02's entitlement
change, and outcomes land in the churn view's leading indicators. The one rule the code
enforces: whatever the offer, the **Cancel** button is on every screen of the flow, and it
works.

## Engineering Decisions

### Which loop — and why not a referral program?

Inventory the loops the product *natively* runs before building one it doesn't: content
users create that non-users see (Invoicely: invoices — strong), artifacts shared publicly
(payment-link pages — same channel), collaboration invites (weak: invoicing is
single-player at this stage), and incentivized referrals (exists for any product, which is
exactly why it's the default suggestion and rarely the right first move). The native loop
wins on three axes: zero marginal cost, perfect audience targeting (invoice recipients
demonstrably run businesses that get invoiced), and no fraud surface. Incentives are a
tuning knob for *after* the unincentivized conversion is measured — you cannot know what
the $10 credit buys you until you know what free was producing.

### Attribution: signed tokens or UTM parameters?

Both, with a trust boundary between them. The loop you own end-to-end — your email, your
link, your landing — gets deterministic attribution: signed tokens, parsed server-side,
written once at signup. UTM parameters remain for channels you don't control (a podcast
link, a paid campaign) and are labeled what they are: directional, last-touch,
stripped-by-privacy-tools evidence. The failure to avoid is promoting UTM guesswork into
revenue math — "paid CAC" computed from parameters that 30% of browsers drop. First touch
is the recorded truth here because the loop's economics depend on *what recruited the
tenant*, not what they clicked last; teams that need multi-touch models need them after
PMF, with an analyst, not now.

### Experiment or ship-and-monitor?

Run the two-question test: *can the traffic detect the effect in weeks* (at 250
signups/week, arms of ~500/month — detectable effects are in whole percentage points, not
tenths), and *is being wrong expensive*? Onboarding defaults: experiment — cheap to run
both arms, wrong answer costs activation forever. Footer copy: experiment — the loop
volume can detect CTR changes fast. The save flow: ship-and-monitor — there is no ethical
"no offer" arm worth running against churning customers, the change is reversible, and
period-end churn (Ch 06) is the monitor. One-way doors (pricing changes, plan
restructures) get judgment plus Chapter 02's grandfathering, not an experiment that can't
be blinded anyway. Write the decision in the experiment log either way.

### Does the Business tier's white-label remove the footer — and is that okay?

Yes, and yes — deliberately. Chapter 02 made white-label a Business fence because agencies
structurally need it; that means paying customers can buy their way out of the loop. This
is the correct trade: the fence prices a segment's real need, the loop runs on the Free
and Professional volume (the large majority of invoice traffic), and a footer you cannot
remove at any price is the kind of decision that curdles into resentment and churn. The
principle: **the loop is fueled by users who are getting value for free, not extracted
from customers who are paying.** Revisit only if Business tenants become most of send
volume — a nice problem the metrics will announce.

### Where does growth code live?

In the product codebase, behind the same review, tests, and flags as everything else — and
each experiment's flag carries an expiry. The alternative — a growth-team fork, a
tag-manager full of unreviewed JavaScript, a "temporary" landing-page microservice — is
how companies end up with three signup flows, two of them broken, none instrumented
consistently. The velocity growth work genuinely needs comes from feature flags and small
reversible bets, not from exempting the code from engineering.

### When do paid channels enter?

When the arithmetic clears, and not before: activation and retention good enough that a
cohort's LTV is believable (Ch 06's curves, not a spreadsheet's wish), attribution able to
tell channels apart, and payback under a threshold the runway sets. Then paid is just
another loop edge to instrument — spend → activated tenant → LTV — with the discipline
that channel CAC rises as it scales. Invoicely's numbers cleared that bar only after Bet 1
lifted activation; the ads the founder wanted in week one would have been paying full
price to fill the leaky part of the funnel.

## Trade-offs

| Choice | You gain | You pay |
|---|---|---|
| Native loop first | Zero marginal cost; targeted audience; no fraud surface | Bounded by product's natural exposure; K < 1 — amplifier, not engine |
| Incentivized referrals | Pushes conversion above native rate; schedulable | Cost per signup; fraud surface (Stage 9); attracts reward-hunters who don't retain |
| Signed-token attribution | Deterministic; revenue-grade; tamper-proof | Only covers channels you own; needs a helper + tests |
| UTM-only attribution | Covers every channel; zero build | Lossy, last-touch, spoofable; poisons CAC math if trusted |
| First-touch recorded | Loop economics measurable; append-only truth | Undercounts channels that close rather than introduce |
| Real experiment | Proof; protects against shipping noise | Weeks of calendar time; needs traffic; contract discipline |
| Ship-and-monitor | Fast; works at low traffic; fine for reversible bets | Wrong sometimes, silently; demands honest rollback triggers |
| Save-flow offers | Recovers genuine subset of cancels; reads churn reasons | One step from a dark pattern if the exit ever gets harder |
| Clean instant cancel | Trust; returning customers; no regulator interest | Loses saves an honest offer would have made |
| Footer on free tiers only | Loop fueled by value-for-free; fence stays sellable | Paying (non-Business) tenants still carry branding — watch sentiment |
| Growth code in product repo | Reviewed, tested, one signup flow | Slower than a tag manager; growth work queues with product work |

The sharpest edge is the save-flow row: the distance between "one honest offer" and "a
cancellation maze" is three product reviews of drift, and the maze converts better *this
quarter* — which is exactly how teams talk themselves into it. Decide the line before the
numbers argue.

## Common Mistakes

- **Scaling acquisition before retention.** The leaky-bucket spend: paid signups into 34%
  activation, CAC quietly exceeding first-year value. The movements view makes it
  visible; the order of work (retention → activation → loop → paid) is the fix.
- **Expecting K > 1.** "Viral" SaaS is folklore; consumer products with contact-book
  access hit K > 1 briefly, B2B tools do not. Treating K = 0.2 as failure — and abandoning
  a loop that compounds 20% onto every cohort forever — is innumeracy. Treating K as a
  target to force above 1 produces the spammy invite mechanics users punish.
- **Trusting last-click attribution.** The signup's final UTM says "google" because the
  recipient searched "invoicely" after seeing three invoices. Paid gets the credit, the
  loop gets defunded — self-deception with a budget line. First-touch tokens for owned
  loops; skepticism for everything else.
- **The underpowered A/B test.** Forty signups a week, two arms, a 2-point effect: the
  test cannot conclude within the quarter, so it concludes whatever the peek says. Run
  the detectability arithmetic before the experiment, or ship-and-monitor instead.
- **Peeking and stopping at the first green.** Daily checks, stop on the first day the
  delta looks good — a procedure that finds "wins" in pure noise. The contract (metric,
  duration, threshold — written first) exists to make this impossible to do innocently.
- **Measuring signups instead of activated tenants.** The footer copy that maximizes
  clicks attracts curiosity, not businesses; signups rise, activation of loop-attributed
  tenants falls, and the loop's real output (activated tenants, per the K definition)
  didn't move. Every loop edge is measured through to activation, or the optimization
  aims at the wrong target.
- **Copying another product's loop.** Dropbox's storage bonus, Calendly's booking page,
  Notion's shared docs — each loop worked because of that product's physics (what users
  natively expose to non-users). The transferable thing is the *method* — inventory,
  instrument, fix the weakest edge — never the mechanism.
- **Growth changes without guardrails.** The onboarding experiment that lifted activation
  and — unmeasured — doubled email complaints, burning the sending domain every invoice
  depends on. Every bet names its guardrail metric at contract time; Chapter 04's events
  and Chapter 06's views are where the guardrails already live.

## AI Mistakes

The trio here fails at the strategy layer, not the syntax layer — which makes the failures
more expensive: the code is fine, the bet is wrong.

### Claude Code: the wrong loop, competently built

Asked to "add growth features" or "build referrals," Claude Code produces the canonical
incentivized referral system — codes, a credits ledger, share buttons, reward emails,
sometimes a leaderboard — a competent implementation of the loop *every* product could
have, while the loop only *this* product has (invoice emails to non-users, at existing
volume, free) sits uninstrumented. The generic pattern dominates its training data; your
product's native loop appears nowhere in it. The result is weeks of work, a fraud surface,
and a reward liability, all bolted on before anyone measured what the footer was already
producing.

**Detect:** referral-code tables, credit ledgers, or reward logic in a diff for a product
whose native loop has no attribution rows yet — the build order itself is the tell.
**Fix:** make the loop inventory a written artifact before any growth prompt (`docs/`
carries it, CLAUDE.md points to it: "growth work targets the invoice-email loop; measure
before incentivizing"), and scope prompts to edges — "instrument footer → signup
attribution," not "add referrals."

### GPT: the playbook without the arithmetic

Asked "how should we grow," GPT returns the universal answer: content marketing, SEO,
paid social, a referral program, community, partnerships, PLG onboarding — each with
confident generalities, none weighted by your traffic, stage, or unit economics, and often
seasoned with fabricated benchmarks ("a healthy viral coefficient is above 1.0"; "aim for
CAC payback under 12 months" — plausible, unsourced, sometimes simply wrong for the
segment). It is a strategy-shaped answer with no strategy in it: nothing about *your* 250
signups/week, *your* 34% activation, *your* K = 0.14 — the numbers that make all but two
of its ten suggestions arithmetic dead ends this quarter.

**Detect:** growth advice that would read identically for any SaaS product — no reference
to your metric tree's actual values is the fingerprint; every benchmark un-cited.
**Fix:** invert the prompt — supply the tree with numbers (activation, retention curve,
K and its five edges, signups/week) and ask "which single node, worked this quarter, moves
net-new MRR most — show the arithmetic." The model is genuinely useful as a calculator
and a devil's advocate once it is forced to compute instead of recite.

### Cursor: the loop broken one autocompletion at a time

Growth machinery is connective tissue — a token built here must parse there; a hash bucket
computed at signup must recompute identically at analysis — and Cursor's pattern-matching
severs it in ways that type-check. Editing the email template, it autocompletes the footer
href from other links in the file (`{settings.app_url}/signup?ref=invoice`), silently
dropping the signed token: emails still send, the landing still loads, and attribution
flatlines while the loop appears dead. Or it inlines assignment in a second file with the
argument order flipped (`sha256(f"{tenant_id}:{experiment}")`), splitting the experiment
into four inconsistent buckets that no analysis can reconstruct.

**Detect:** the metrics catch it if you let them — an attribution `source` distribution
that lurches toward `organic`, an experiment whose event arms don't match assignment
recomputed from IDs. Alert on both. **Review flag:** any hand-built URL or inline hash in
growth-adjacent code. **Fix:** structural — `footer_url()` and `assign()` are the only
places their logic exists, tests pin token round-trip and bucket stability, and template
review rejects raw hrefs where a helper exists.

## Best Practices

- **Instrument before optimizing — the loop especially.** The two weeks of attribution
  work precede any copy test, incentive, or redesign; you cannot fix the weakest of five
  edges you haven't measured. "We improved the loop" without a before-K is theater.
- **One bet at a time per tree node, with an owner.** Concurrent bets on the same node
  contaminate each other's reads (the onboarding experiment during the footer change
  attributes one's lift to the other). The metric tree, worked bottom-up, is the queue.
- **Write the experiment contract first.** Hypothesis, primary metric (from Chapter 06's
  views — never a bespoke query), guardrails, duration, decision threshold, and what
  happens on a null result — dated, in `docs/experiments/`, before assignment starts. A
  result without a prior contract is an anecdote with error bars.
- **Log rejected bets with their arithmetic.** The killed referral program, the deferred
  paid channel — written down, they're institutional judgment; unwritten, they're a
  re-litigation every planning cycle.
- **Keep the exit honest, permanently.** The save flow makes one offer per reason and
  cancels on the first click that asks. Audit it quarterly against drift — dark patterns
  arrive one "improvement" at a time, and Chapter 03 already showed where blocked exits
  resurface: chargebacks, which cost more than the churn.
- **Guardrail every bet with the boring metrics.** Email complaint rate, support volume,
  activation of *attributed* cohorts, unsubscribe rate — the numbers a growth win can
  quietly spend. They're one `SELECT` away in the views; name them in the contract.
- **Review the loop beside the tree, monthly.** K and its five edges join the weekly
  metrics ritual's monthly edition — trend, weakest edge, one decision. A loop nobody
  reviews decays silently as templates, landings, and flows evolve around it.
- **Let flags expire.** Every experiment flag carries a removal date; a "temporary"
  assignment branch that survives two quarters is dead code shaping live signups.

## Anti-Patterns

- **Growth theater.** The weekly landing-page redesign, the launch-platform badge hunt,
  the rebrand — work whose common property is that no metric-tree node was named before
  it started and none moved after it shipped. Its tell is the same as the vanity
  dashboard's: activity, applause, no decision anywhere in the loop.
- **The dark-pattern ratchet.** Cancel behind four screens, confirm-shaming copy, the
  retention discount that only appears if you start leaving, prices that hide the annual
  commitment. Each step "converts" — and borrows the conversion from trust, chargebacks
  (Ch 03), review-site reputation, and, increasingly, regulators (the FTC's click-to-cancel
  rule made "cancel as easy as signup" a legal floor, not a courtesy). The ratchet only
  turns one way; the defense is the pre-decided line, in writing.
- **Spam wearing a loop costume.** "Invite your contacts" pre-checked, recipient emails
  used for marketing (the exact breach Chapter 04's PII rules prevent), footer links on
  emails recipients can't opt out of receiving. The native loop works because the invoice
  email is *wanted*; the moment growth makes it less wanted, the loop eats the product's
  deliverability and its own fuel.
- **The growth fork.** A separate team, repo, or tag-manager layer shipping unreviewed
  changes to signup and onboarding. Two quarters later: three signup variants, attribution
  double-counted, an experiment nobody can turn off. Growth work is product work; it buys
  velocity with flags, not exemptions.
- **Metric-moving as a career.** Bets chosen for legibility — signups, always signups —
  over impact; the activated-tenant definition quietly loosened the quarter the loop
  became an OKR (Chapter 06's Goodhart defense applies verbatim: contracts, diffs,
  restatements). A growth culture is measured by what it declines to claim.
- **Premature machinery.** An experimentation platform, a multi-touch attribution model,
  a growth-data warehouse — for a product with 250 signups a week and one experiment a
  quarter. Chapter 01's over-building trap in its final costume; the assign() function is
  ten lines and the log is a Markdown file, until the cadence says otherwise.

## Decision Tree

```
"We need to grow" — in order:
│
├─ 1. RETENTION healthy? (wk-4 curve flattens; NRR ≳ 100%;
│     churn not dominated by product gaps — Ch 05/06 read)
│     ├─ NO → fix retention first. Growth on top of leak
│     │        = renting revenue. Ch 05's synthesis names
│     │        the gaps; this quarter belongs to them.
│     └─ YES ↓
│
├─ 2. ACTIVATION at benchmark for your motion?
│     ├─ NO → onboarding bets aimed at the Ch 06 activation
│     │        moment. Cheapest lift: helps EVERY source.
│     │        Enough traffic to test? contract + arms.
│     │        Not enough? ship-and-monitor with rollback.
│     └─ YES ↓
│
├─ 3. LOOP instrumented? (attribution + edge view live)
│     ├─ NO → build that first. Two weeks. No optimizing
│     │        an unmeasured loop.
│     └─ YES → work the WEAKEST edge of five. Re-read K
│              monthly. Incentivize only when the free
│              conversion is known AND fraud is budgeted
│              (Stage 9) AND the arithmetic beats paid.
│
├─ 4. PAID channels: LTV believable (real cohort curves)?
│     attribution can separate channels? payback < runway
│     threshold?
│     ├─ All three → smallest spend that measures; scale
│     │              while CAC & guardrails hold.
│     └─ Any no → not yet. The no is the finding.
│
└─ Throughout: one bet per node · contract before traffic ·
   guardrails named · results (and rejections) logged ·
   exit stays honest — the line is written BEFORE the
   numbers argue for crossing it.
```

## Checklist

### Implementation Checklist

- [ ] Loop attribution exists end-to-end: signed footer tokens from a single helper,
      server-side first-touch row at tenant creation, tamper cases landing safely.
- [ ] `referral_loop` view computes all five edges and K under Chapter 06's rules —
      fixture-tested, no dashboard re-derives it.
- [ ] Experiment assignment is deterministic, recorded as an event at assignment time,
      and reconstructible from raw IDs.
- [ ] Every experiment has a contract in `docs/experiments/` dated before traffic
      started; the log includes rejected bets.
- [ ] Save flow: one reason question, one keyed offer, working cancel on every screen;
      outcomes feed the churn view's leading indicators.
- [ ] Guardrail metrics (complaints, unsubscribes, attributed-cohort activation) are
      named per bet and alertable.
- [ ] Experiment flags carry expiry dates; expired flags are findings.

### Architecture Checklist

- [ ] The loop inventory is a written artifact; growth prompts and PRs reference it.
- [ ] Attribution trust boundary is explicit: tokens = revenue-grade, UTM = directional,
      and no CAC math reads the directional side.
- [ ] The order of work (retention → activation → loop → paid) is visible in the
      experiment log's history — or the deviation has a written reason.
- [ ] White-label/footer interaction matches the pricing fences (Ch 02); loop fuel comes
      from free-tier value, not paid-tier extraction.
- [ ] Growth code ships through the product pipeline — review, tests, flags — with no
      parallel deployment path.
- [ ] Paid-channel entry criteria (LTV basis, attribution readiness, payback threshold)
      are written down before the first dollar.

### Code Review Checklist

- [ ] No hand-built attribution URLs or inline assignment hashes — helpers only; a raw
      `?ref=` in a template is a finding.
- [ ] New growth surfaces fire Chapter 04 events under the existing taxonomy — no
      bespoke tracking dialects.
- [ ] Changes to the cancel flow diffed against the dark-pattern line: no added steps,
      no hidden exits, offers keyed to stated reasons only.
- [ ] Experiment analysis queries read the views and the assignment events — any
      after-the-fact metric definition is a finding.
- [ ] Recipient-facing changes re-checked against Ch 04's PII rules: recipients are not
      marketing targets, and their emails stay out of growth tooling.

## Exercises

1. **Inventory the loops.** For your product (or Invoicely), list every surface a
   non-user sees because a user used the product. For each: audience quality, natural
   volume, and the five-edge conversion chain. Pick the strongest, and write the two-week
   instrumentation plan that would make its K measurable.
2. **Build the attribution spine.** Implement `footer_url()`/`parse_token()` and the
   `SignupAttribution` row against the stage's schema, with tests for round-trip,
   tampering, and first-touch-wins. Then break it the Cursor way — rebuild the link by
   hand without the token — and confirm which alert catches it, and how fast.
3. **Run the detectability arithmetic.** At 250 signups/week: for activation lifts of 2,
   5, and 10 percentage points from a 34% base, estimate how long a 50/50 test needs to
   read (any online calculator is fine — the judgment is in the inputs). State which
   lifts justify a contract and which should ship-and-monitor, and defend the boundary.
4. **Audit a cancel flow.** Take a real product's cancellation (your own product's, or a
   subscription you can safely test). Count screens, name each dark pattern against this
   chapter's list, and redesign it as one honest screen with reason-keyed offers.
   Estimate what the honest version loses this quarter — and what the maze costs in
   Chapter 03's chargeback terms and Chapter 06's reactivation terms.
5. **Grade the machine's growth plan.** Ask an assistant "how should we grow" with no
   context, then again with the full metric tree and numbers, demanding per-suggestion
   arithmetic. Diff the answers against this chapter's order of work. Catalog which
   playbook items survived contact with your numbers — that ratio is your calibration
   for AI strategy advice, the same measurement Exercise 5 of Chapter 06 gave you for
   AI metrics code.

## Further Reading

- Brian Balfour — "Growth Loops are the New Funnels" (Reforge) — the loops-over-funnels
  argument in full, with the taxonomy of loop types this chapter's inventory exercise
  applies.
- Andrew Chen — *The Cold Start Problem* — network effects and why K > 1 is rarer than
  the folklore claims; the honest math behind "viral."
- Sean Ellis, Morgan Brown — *Hacking Growth* — the experiment-cadence operating system;
  read with this chapter's contract discipline as the corrective to its enthusiasm.
- Lenny Rachitsky — "How the Fastest-Growing B2B Companies Found Their First Ten
  Customers" and the growth-loop case library — practitioner evidence for which loops
  fit which product physics.
- deceptive.design (Harry Brignull) — the dark-pattern taxonomy, with a hall of shame;
  the vocabulary for the lines this chapter says to draw in advance.
- FTC — "Negative Option Rule" (click-to-cancel) — the regulatory floor under
  cancellation flows; growth's legal constraint, not just its ethical one.
- Chapter [02 (Pricing)](02-pricing.md), Chapter [04 (Analytics)](04-analytics.md), and
  Chapter [06 (Product Metrics)](06-product-metrics.md) — the fences the loop must
  respect, the events it's measured with, and the tree it exists to move.

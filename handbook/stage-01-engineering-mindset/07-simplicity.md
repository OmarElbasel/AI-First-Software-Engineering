# Simplicity

## Introduction

Simplicity is the deliberate minimization of complexity — where complexity is
whatever makes a system hard to understand and change. It is not fewer
features, not fewer lines of code, and not whatever was easiest to write
this afternoon. It is the property that lets the next person (or the next
AI assistant, or you in six months) look at a piece of the system, understand
it quickly, and change it safely.

Simplicity is counterintuitively difficult, because complexity is the path of
least resistance. The first solution to any problem is almost always more
complex than it needs to be; the simple version is discovered by iteration
and removal, not produced on the first try. As the apology goes — "I would
have written a shorter letter, but I did not have the time" — brevity and
clarity cost more effort than sprawl, not less. This is why simplicity is a
discipline and not a default.

This chapter is the positive principle underneath three earlier warnings.
Chapter 04's over-engineering, Chapter 05's gold-plating, and Chapter 06's
build-the-commodity impulse are all the same disease: complexity added
without a benefit that justifies it. Simplicity is the cure, and in the AI
era it is more important and more endangered than ever — because assistants
generate plausible complexity fluently and cheaply, and the simplest version
is the one thing they almost never produce on their own.

## Why It Matters

Complexity is the dominant cost in software, and it is a cost paid
continuously. A complex system is slow to understand, dangerous to change,
and expensive to onboard into — every feature takes longer than the last,
bugs hide in interactions nobody can hold in their head, and the team's
velocity decays even as the headcount grows. Nothing about a complex system
announces itself as the problem; it presents as "everything just takes a
while here."

The reason simplicity pays is that software is read and changed far more
than it is written. A clever, compact, or highly abstract solution that
saved its author an hour will cost every future reader — and there are many
— the time to decode it, multiplied across every change for the life of the
system. Optimizing for the moment of writing over the years of reading is
one of the most expensive mistakes an engineer can make, and it is
extremely common because the writing cost is visible and the reading cost is
diffuse.

AI reshapes this in a specific and dangerous way. Generation is now free, so
the natural brake on complexity — "this is too much code to write" — is
gone. An assistant will happily produce five hundred lines of layered,
pattern-rich, configurable machinery for a problem that needed fifty, and
because the output looks professional and runs, the complexity slips in
unreviewed. AI has a structural bias toward the elaborate solution, trained
as it is on large mature codebases full of abstractions built for problems
bigger than yours. Simplicity now has to be actively demanded, because the
tool that writes most of the code will never volunteer it.

## Mental Model

The first move is to stop treating "complexity" as a vague complaint and
name what it actually is. John Ousterhout's definition is the useful one:
complexity is anything about a system's structure that makes it hard to
understand or modify, and it shows up as three symptoms:

```
   CHANGE AMPLIFICATION   a simple change requires edits in many places
   COGNITIVE LOAD         how much you must know to make a change safely
   UNKNOWN UNKNOWNS       you can't even tell what you need to know
                          (the worst one — you don't know what will break)
```

If a one-line behavioral change touches six files, or requires understanding
the whole system, or breaks something nobody predicted — that is complexity,
measured directly. Note what is *not* on the list: line count. A longer,
explicit version with low cognitive load is simpler than a short, dense,
clever one.

The second move is to separate the complexity you can remove from the
complexity you cannot. Fred Brooks' distinction:

```
   ESSENTIAL complexity      inherent in the problem itself.
   (reconciliation matching   Irreducible. You can only contain it,
    genuinely is hard)         isolate it, and make it as clear as
                               the problem allows.

   ACCIDENTAL complexity     added by our tools, patterns, and choices.
   (the config DSL wrapped    Not in the problem — in your solution.
    around the matching)       This is the complexity to hunt and delete.
```

Most of what makes real systems painful is accidental. The engineering skill
is telling the two apart, then eliminating the accidental and honestly
containing the essential.

A third distinction prevents the most common confusion, from Rich Hickey:
**simple is not the same as easy.** Simple means *not intertwined* — one
concept, one responsibility, not braided together with others. Easy means
*familiar* or *near at hand*. They are independent: a familiar tool
(easy) can produce deeply intertwined systems (complex), and an unfamiliar
technique (not easy) can be beautifully simple. The engineering virtue is
simplicity, even when it is not the easy choice.

Finally, the shape simplicity usually takes in code is the **deep module** —
a simple interface hiding substantial functionality — as opposed to the
shallow module, a complex interface wrapping very little. Ten tiny classes
that each do almost nothing, with elaborate wiring between them, are not
"simple" because the pieces are small; they are complex, because the
cognitive load lives in the interactions.

A working definition:

> **Simplicity is minimizing the complexity required to understand and change
> a system — deleting the accidental kind and honestly containing the
> essential kind. It is measured by cognitive load, not by line count.**

## Real-World Scenario

**Invoicely.** Chapter 06 confirmed the reconciliation engine as the
company's differentiator — the capability worth building. Which is exactly
why what happened to it hurts: over eighteen months it grew a "flexible rules
engine." A departed engineer, anticipating that Invoicely would one day
support arbitrary customer-defined matching rules, built a small
configuration DSL, a plugin-loading system, and three layers of abstraction
so that new matching strategies could be "added without code changes."

In reality, the engine has ever needed exactly three matching strategies:
exact invoice-ID match, amount-and-date match, and fuzzy vendor-name match.
No customer has ever defined a rule. The speculative flexibility serves no
present need — and it has made the differentiator nearly unmaintainable.

### The symptoms, measured

A new engineer is asked to make a one-line behavioral change: the fuzzy
vendor-name match should ignore a trailing "Inc." or "LLC." It takes two
weeks. The reconciliation engine exhibits all three of Ousterhout's
symptoms at once:

- **Change amplification** — the change touches the DSL parser, a plugin
  registration file, an abstract base strategy, and the concrete strategy,
  because the "flexibility" spread one behavior across four places.
- **Cognitive load** — to change one matching rule safely, the engineer must
  first understand the entire plugin architecture and DSL, none of which has
  anything to do with matching vendor names.
- **Unknown unknowns** — nobody can say with confidence what else consumes
  the DSL, so nobody can predict what the change might break. That is the
  worst symptom, and the reason it took two weeks: most of the time went to
  fear, not work.

### Telling essential from accidental

The team runs the Brooks test on the engine. The **essential** complexity is
real: reconciliation matching genuinely is hard — fuzzy matching, ambiguous
amounts, and partial payments are inherent to the problem, and no
simplification makes them go away. The **accidental** complexity is the
entire scaffolding: the DSL, the plugin loader, and the abstraction layers
exist to serve a requirement (customer-defined rules) that does not exist and
may never exist. It is speculative generality — flexibility built for an
imagined future, paid for continuously in the present.

### The simplification

The team deletes the DSL, the plugin system, and the abstraction layers, and
replaces them with three explicit, well-named functions — one per matching
strategy — behind one small interface. Notably, the explicit version is *not
dramatically shorter*; in raw line count it is close to a wash. But its
complexity collapses: the one-line vendor-name change now touches one
function, requires understanding only that function, and cannot break
anything outside it. A deep module (a simple `match(invoice, candidates)`
interface hiding the real matching work) replaced a shallow, intertwined
framework. The essential complexity of matching stayed, now clearly visible;
the accidental complexity of the framework is gone.

### The AI thread

Midway through, the team had actually tried to *extend* the old system first
— they asked an assistant to add a fourth matching strategy to the existing
DSL-and-plugin engine. It dutifully did, generating another plugin class,
another DSL binding, and another layer — faithfully amplifying the existing
complexity, because a complex architecture teaches the assistant to produce
more of the same. After the simplification, the same request against the new
code produced a single clear function. **The lesson landed twice: a simple
codebase is one an AI can work in safely, and a complex one turns the
assistant's own bias toward elaboration into a multiplier.** Simplicity is
not only for humans anymore.

## Engineering Decisions

Four decisions inside that scenario recur whenever complexity is on the
table.

### Is this complexity essential or accidental?

**Options:** (1) accept the complexity as inherent to the problem; (2)
interrogate it as possibly self-inflicted.

**Trade-offs:** treating all complexity as essential ("reconciliation is just
hard") protects bad structure from scrutiny and lets accidental complexity
hide behind real difficulty. Interrogating every bit of complexity risks
churning on genuinely irreducible problems. The discriminating question is
Brooks': "is this complexity in the problem, or in my solution to it?"

**Recommendation:** run the essential/accidental test explicitly before
accepting any complexity. In the scenario, matching was essential and the
framework was accidental — and naming that difference is what made the
simplification obvious. Most painful complexity turns out to be accidental
once you actually ask.

### Speculative generality: build for the future or the present?

**Options:** (1) build flexibility now for anticipated future needs; (2)
build for the case you actually have, and generalize later if the need
becomes real.

**Trade-offs:** building for the future (option 1) feels prudent and
occasionally saves a later rewrite — but usually pays continuous complexity
cost for a requirement that never arrives, exactly as the DSL did. Building
for the present (YAGNI — "you aren't gonna need it") keeps things simple and
risks a real refactor later if the future need does materialize — but that
refactor is usually cheaper than carrying the speculative complexity the
whole time.

**Recommendation:** build for the present by default; treat imagined future
requirements as complexity with no current benefit. When a real, present need
for generality arrives — and the rule of three is a good threshold — abstract
then, with knowledge of the actual cases rather than guesses.

### Simplify now, or live with it?

**Options:** (1) simplify the complex code now; (2) leave it and move on.

**Trade-offs:** this is Chapter 05's interest calculation. Simplifying costs
present effort; leaving it costs future change-velocity — but only on code you
actually change. The reconciliation engine is hot-path differentiator code
under active development, so its complexity charges high interest, and
simplifying it pays back fast.

**Recommendation:** simplify high-interest complexity (frequently changed,
central) and leave low-interest complexity (frozen, isolated) alone, exactly
as with debt. The team was right to simplify the engine; they would have been
wrong to spend the same effort untangling a report generator nobody touches.

### How to simplify without breaking behavior?

**Options:** (1) rewrite the complex component from scratch; (2) simplify
incrementally under a test harness.

**Trade-offs:** identical to Chapter 05's debt-repayment decision. A rewrite
risks discarding essential behavior encoded in the mess; incremental
simplification under characterization tests preserves behavior while
structure improves.

**Recommendation:** pin behavior with tests first — including the fuzzy
edge cases that are the essential complexity — then remove the accidental
structure with a net. Simplification is refactoring: it must not change what
the code does, only how clearly it does it.

## Trade-offs

Simplicity is the default goal, not an absolute, and pursuing it blindly has
its own failure modes.

**Finding the simple version costs effort.** The simple solution is harder to
discover than the complex one — it requires understanding the problem well
enough to remove everything inessential. Under a real deadline, shipping the
first (more complex) version as deliberate, recorded debt (Chapter 05) can be
the correct call, with simplification scheduled. What is not acceptable is
pretending the rushed version was simple.

**Some abstraction is worth its complexity.** Simplicity is not "never
abstract" or "never reuse." Genuine, present duplication of real logic across
three or more places earns an abstraction; a known, concrete future
requirement can justify building for it. The skill is distinguishing real
generality (earned) from speculative generality (imagined). The opposite
extreme — copy-pasted logic everywhere, no abstraction at all — is its own
complexity, just distributed.

**Simplicity can trade against other axes.** The simplest design is sometimes
slower, and a hot loop may justify a more complex but faster implementation
(Chapter 04's performance trade-off) — with the cleverness isolated,
commented, and justified by measurement. The simple, explicit version may
also carry more duplication than a clever one. These are real trade-offs to
weigh, not license to reach for complexity by default.

**"Simple for whom?"** Simplicity is relative to a reader. Code that is
simple to its author can be opaque to a newcomer, and the reader who matters
is the future maintainer — human or AI — not the writer at the moment of
writing. Optimize for the person who has to change it next with none of the
context you have now.

## Common Mistakes

**Confusing simple with easy.** Choosing the familiar approach over the
genuinely simple one — reaching for the tool or pattern you know rather than
the one that leaves the system least intertwined. Fix: ask whether a choice
reduces *complexity* (Hickey's "not complected"), separately from whether it
feels comfortable.

**Speculative generality.** Building configurability, plugins, and abstraction
layers for requirements that do not yet exist — the reconciliation DSL. It is
the single most common source of accidental complexity in ambitious
codebases. Fix: apply YAGNI ruthlessly; build for the case you have, and
generalize when a real one arrives.

**Confusing simple with fewest lines.** Compressing logic into dense
one-liners — nested comprehensions, chained ternaries, clever tricks — and
calling it simple because it is short. Short and dense is *more* complex, not
less: it raises cognitive load. Fix: measure simplicity by how fast a new
reader understands it, not by line count.

**Premature abstraction.** Applying DRY the moment two pieces of code look
similar, before you know whether they are the same *concept* or just
coincidentally alike. The wrong abstraction couples things that should vary
independently and is harder to unwind than duplication. Fix: tolerate
duplication until the shared concept is proven (the rule of three); "a little
duplication is cheaper than the wrong abstraction."

**Shallow-module sprawl.** Decomposing a system into many tiny pieces that
each do almost nothing, on the theory that small = simple, and hiding all the
real complexity in the wiring between them. Fix: prefer deep modules — simple
interfaces over substantial, self-contained functionality — and count the
interactions, not the file sizes.

## AI Mistakes

Every failure here is a facet of one bias: **AI defaults to more structure
than the problem needs.** Trained on large, mature, heavily-abstracted
codebases, assistants produce the elaborate solution as their natural output
and treat sophistication as a virtue. The countermeasure is constant and
explicit: demand the simplest thing that works, define "simple" as low
cognitive load, and ask what can be removed.

### Claude Code: pre-abstracted code for a one-case problem

Asked to solve a concrete, singular problem, Claude Code frequently returns
it pre-wrapped in structure built for variation that does not exist — an
interface with a single implementation, a strategy pattern for one strategy,
dependency injection for a dependency that never changes, config for values
that never vary. Each individual piece looks like good practice; together
they are the reconciliation DSL, generated on the first try.

**Detect:** abstraction with exactly one concrete case, configuration for
things that have never varied, and design patterns applied to a problem too
small to need them. An interface implemented once is the clearest tell.

**Fix:** ask for the simplest version and make it justify any structure:

> Give me the simplest implementation that handles exactly the cases I named.
> No interfaces, patterns, or configuration unless a present requirement
> forces them — and if you add any structure, justify why this problem needs
> it.

### GPT: brevity mistaken for simplicity

Ask a GPT-family model to "simplify" code and it will often make it *shorter*
rather than *clearer* — collapsing readable logic into a dense expression,
nesting comprehensions, chaining conditionals — optimizing line count, which
is the wrong metric. The result is compact and harder to understand: more
complex by the only measure that matters, presented as a simplification.

**Detect:** "simplified" output that is shorter but denser — more happening
per line, more you have to hold in your head to read one statement. If you
have to slow down to parse it, it got more complex, not less.

**Fix:** define the target metric, because the model's default is length:

> Simplify this for a new reader's understanding, not for fewer lines. It is
> fine if the result is longer, as long as each part is obvious. Optimize for
> lowest cognitive load.

### Cursor: complexity by branch-creep

Inline, each new requirement gets handled by adding one more conditional,
flag, or special case right where the cursor is — the locally smallest
change. Over time a function that began simple accumulates a thicket of
branches, its cyclomatic complexity climbing one accepted completion at a
time, and no single step is ever large enough to prompt a step-back to a
simpler structure. Simple code rots into complex code by increments.

**Detect:** functions that have grown more branches, flags, and nesting over
successive edits; deeply nested conditionals; a parameter list padded with
booleans that switch behavior. The history shows steady additions and no
restructuring.

**Fix:** treat accumulating special cases as a signal to restructure, and ask
for it deliberately:

> This function has grown several special cases. Before adding another,
> propose a structure that removes them — a different data model, a lookup,
> or a split — rather than one more branch.

Pointed the other way, assistants are excellent *simplifiers* on demand:
"remove everything not needed for the current cases," "reduce this to a deep
module with a minimal interface," "eliminate the speculative generality" —
all under a test harness. They will not simplify unprompted, but they
simplify well when asked. The bias is one-directional, and you supply the
other direction.

## Best Practices

**Start with the simplest thing that could work.** Build for the case you
actually have, and add complexity only when a present, real requirement forces
it (YAGNI). It is far easier to add structure when a need proves itself than
to remove speculative structure after it has spread.

**Optimize for the reader, measured by cognitive load.** Write for the future
maintainer with none of your current context. Judge every construct by how
fast someone new understands it and how safely they can change it — never by
how short or clever it is.

**Prefer deep modules and explicit code.** Hide substantial functionality
behind simple interfaces; avoid shallow layers whose complexity lives in the
wiring. Prefer explicit, obvious code over clever or implicit code, and
resist premature abstraction — tolerate duplication until the shared concept
is real (the rule of three).

**Treat simplification as a distinct step.** After code works, make a
separate pass asking "what can I remove?" The working version is rarely the
simple version; simplicity is reached by deletion. This is the pass that most
often gets skipped, and the one with the highest return.

**Demand simplicity from AI, and use it to simplify.** Assistants never
volunteer the simple version — ask for it explicitly ("simplest thing that
works, no abstraction unless earned"), and turn them loose as simplifiers on
existing complexity under tests. Match generation volume to what stays simple
and reviewable (Chapter 03).

## Anti-Patterns

**Speculative Generality.** Abstraction, configurability, and extension points
built for imagined future requirements — the reconciliation DSL. It pays
continuous complexity cost for a benefit that usually never arrives. The tell:
flexibility with no present consumer; an interface, plugin system, or config
option that only one thing has ever used. (Chapters 04 and 05, seen as
structure.)

**Configurable Everything.** Turning every design decision into a
configuration flag rather than making the decision — indecision encoded as
complexity, and a combinatorial explosion of untested option interactions
(Chapter 04's config anti-pattern). The tell: options whose correct value the
authors themselves cannot explain.

**Shallow-Module Sprawl.** Over-decomposing a system into many tiny units,
mistaking small pieces for simplicity while the real complexity concentrates
in the interactions between them. The tell: a change requires opening a dozen
files that each do almost nothing, and the logic lives in the wiring.

**Clever Code.** Treating brevity or ingenuity as a value in itself — dense
one-liners, exploited language quirks, code that shows off. It optimizes the
writer's satisfaction at the reader's expense. The tell: code that draws a
"how does this even work?" and takes minutes to decode what a plain version
would show in seconds.

**Premature (Wrong) Abstraction.** Extracting a shared abstraction from code
that merely looks alike, coupling things that should evolve independently. The
wrong abstraction is harder to remove than the duplication it replaced, and
teams keep contorting code to fit it. The tell: an abstraction that grows
special-case parameters every time a new caller "almost" fits.

## Decision Tree

"I'm about to add — or am looking at — some complexity. What do I do?"

```
Is this complexity ESSENTIAL (in the problem) or ACCIDENTAL (in my solution)?

├── ACCIDENTAL ──► Remove it or avoid it. Find a simpler approach.
│                  (The framework around the matching, not the matching.)
│
└── ESSENTIAL (irreducible difficulty of the problem itself)
    │
    Am I ADDING structure, or SIMPLIFYING existing code?
    │
    ├── ADDING abstraction / flexibility / configuration
    │   │
    │   Is the need real and PRESENT, or imagined / future?
    │   │
    │   ├── Imagined / future ──► Don't (YAGNI). Build for the case
    │   │                         you actually have.
    │   │
    │   └── Real & present (≥3 concrete instances) ──► Abstract — but
    │                                                  keep it a DEEP module:
    │                                                  simple interface,
    │                                                  real work hidden.
    │
    └── SIMPLIFYING existing complex code
        │
        Is it hot-path / high-interest (frequently changed, central)?
        │
        ├── YES ──► Simplify it, incrementally, under tests. High return.
        │
        └── NO (frozen, isolated, rarely touched) ──► Leave it. Its
                 complexity charges ~no interest (Chapter 05). Simplifying
                 it is effort with no payoff.
```

The most-skipped branch is the first one. Engineers accept accidental
complexity as though it were essential — "this is just a hard problem" — and
never ask whether the difficulty is in the problem or in their own solution
to it.

## Checklist

### Simplicity Judgment Checklist — when adding or reviewing complexity

- [ ] I separated essential complexity (in the problem) from accidental complexity (in my solution), and I'm only keeping the essential.
- [ ] Any abstraction, config option, or extension point serves a real, present need — not an imagined future one (YAGNI).
- [ ] I measured complexity by cognitive load and change amplification, not by line count.
- [ ] New abstractions are deep modules (simple interface, substantial hidden functionality), not shallow layers.
- [ ] I resisted abstracting code that only looks similar; duplication stays until the shared concept is proven.
- [ ] I made a deliberate "what can I remove?" pass after the code worked.
- [ ] If I shipped a complex version under deadline, I recorded it as debt rather than calling it simple.

### Code Review Checklist — simplicity in the diff

- [ ] Could a new reader understand this change without understanding the whole system?
- [ ] Does a one-line behavioral change require edits in only one place (no change amplification)?
- [ ] Are there interfaces with a single implementation, or config for things that never vary (speculative generality)?
- [ ] Is any "simplification" actually just shorter/denser code with higher cognitive load?
- [ ] Have inline additions grown a function's branches/flags to the point it needs restructuring, not another special case?
- [ ] Was AI-generated structure (patterns, layers, abstraction) checked against whether the problem actually needs it?

## Exercises

As before, these produce artifacts — do them in writing.

**1. The complexity symptom hunt.** Take a module you find painful and
diagnose it against Ousterhout's three symptoms: for a typical change, how
many places must you edit (change amplification), how much must you understand
to do it safely (cognitive load), and what has surprised you by breaking
(unknown unknowns)? The artifact is the diagnosis plus a single sentence
naming the largest source of *accidental* complexity — the thing that, if
removed, would help most.

**2. The removal exercise.** Take working code you wrote recently and remove
everything not needed for the cases it actually handles today — speculative
config, unused parameters, premature abstraction, extension points with no
consumer. Measure the before and after by cognitive load, not line count. The
artifact is the diff plus a note on what you were "saving for later," and an
honest guess at whether later will ever come.

**3. The AI simplicity experiment.** Ask an assistant to implement a small
feature and note the structure it adds by default (interfaces, patterns,
config). Then re-prompt: "implement the simplest version that handles exactly
these cases, with no abstraction unless it earns its place," and compare. The
artifact is the two versions side by side plus one paragraph characterizing
the assistant's default complexity bias — the thing you will now correct for
in every generation.

## Further Reading

- **Simple Made Easy** (Rich Hickey, 2011 talk — widely available) — the
  foundational separation of *simple* (not intertwined) from *easy*
  (familiar), and why conflating them is the root of most self-inflicted
  complexity. The single most clarifying hour on this topic.
- **No Silver Bullet: Essence and Accident in Software Engineering** (Fred
  Brooks, 1986) — the origin of essential vs. accidental complexity, and a
  sober argument about which parts of software difficulty we can and cannot
  engineer away.
- **A Philosophy of Software Design** (John Ousterhout) — the practical manual
  for this chapter: the three symptoms of complexity, deep vs. shallow
  modules, and the case that reducing complexity is the central act of design.
  Worth returning to specifically for its module-design chapters.
- **The Wrong Abstraction** (Sandi Metz, sandimetz.com, 2016) — the definitive
  short argument that "duplication is far cheaper than the wrong abstraction,"
  and the antidote to DRY applied too early. Read it before you extract your
  next shared helper.

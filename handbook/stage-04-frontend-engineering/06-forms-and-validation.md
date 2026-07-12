# Forms & Validation

## Introduction

Forms are where users hand your application data, and they concentrate more
frontend complexity than any other UI: input handling, validation, submission,
error display, loading and disabled states, and accessibility all meet in one
place. This chapter is about building forms that are correct on every one of those
axes — not just the happy path where a user fills in valid data and clicks once.

The chapter's load-bearing rule connects directly back to the backend stage:
**client-side validation is a UX convenience, not a security control.** Validating
in the browser gives users immediate feedback, but it can be bypassed trivially
(disable JavaScript, call the API directly), so the *server* must validate
independently and authoritatively — the boundary validation from Stage 3, Chapter
01. A form that validates on the client and trusts that the backend is therefore
safe has a security hole, and it's the hole an assistant leaves by default.

The rest is craft that the naive version skips: use a form library (react-hook-form)
and a schema (Zod) instead of hand-rolling a `useState` per field; handle the full
lifecycle of a submission (pending, success, error) and prevent double-submits; map
server errors back to the right fields; and make the form accessible (labels,
error association, focus management). None of these show up when you glance at a
rendered form, and all of them are what separate a form that demos from a form that
works for real users.

## Why It Matters

Forms are the highest-stakes input surface in a frontend, and the naive
implementation is wrong in ways that range from annoying to dangerous:

- **Client-only validation is a security hole.** If the only validation is in the
  browser, an attacker (or a buggy client) sends whatever they want straight to the
  API. Client validation improves UX; it protects nothing. The server must validate
  every field independently (Stage 3, Chapters 01 and 04) — client validation that's
  *trusted* as protection is the vulnerability.
- **Missing submission states cause double-submits and confusion.** A submit button
  that isn't disabled while the request is in flight lets an impatient user click
  twice — creating two invoices, two charges. No pending indicator leaves users
  unsure if anything happened. The submission lifecycle (pending → success/error) is
  not optional polish.
- **Hand-rolled form state is buggy and heavy.** A `useState` per field with manual
  `onChange` handlers and hand-written validation is verbose, error-prone, and (when
  every keystroke re-renders the whole form) slow on large forms. Form libraries exist
  because this is a solved problem people keep re-solving badly.
- **Inaccessible forms exclude users and fail audits.** Inputs without labels, errors
  not associated with their fields, no focus management — forms are a major
  accessibility surface, and getting them wrong makes the app unusable with a screen
  reader and non-compliant.

The AI dimension: assistants render the fields correctly (the visible part) and skip
the invisible parts — they validate only on the client and treat it as sufficient
(security hole), hand-roll `useState`-per-field forms with no submission states
(double-submit, no feedback), and omit accessibility (labels, error association). The
form looks done in a screenshot and fails under a real user, an attacker, and a screen
reader.

## Mental Model

A production form has four concerns, and each has a rule:

```
   1. INPUT & STATE       controlled vs uncontrolled; use a form library (react-hook-form)
                          — not a useState per field.

   2. VALIDATION          CLIENT (Zod) = UX: instant feedback, can be bypassed.
                          SERVER (Stage 3, Ch 01/04) = AUTHORITATIVE: the real check.
                          ┌─────────────────────────────────────────────────────┐
                          │ client validation improves UX; the SERVER protects.   │
                          │ NEVER trust the client as the security boundary.       │
                          └─────────────────────────────────────────────────────┘

   3. SUBMISSION LIFECYCLE   idle → PENDING (disable submit, show progress; NO double-submit)
                             → SUCCESS (feedback, reset/redirect) | ERROR (map to fields)

   4. ACCESSIBILITY       <label> per input · errors linked via aria-describedby ·
                          focus the first error · announce submission result.
```

Four principles carry the chapter:

**Client validation is UX; the server is the authority.** Validate on the client for
fast feedback, and validate again — independently — on the server, which is the only
check that can't be bypassed (Stage 3, Chapter 01). Ideally the client schema mirrors
the server's rules so the two agree, but the server never trusts that the client ran.

**Use a form library and a schema, not `useState` per field.** react-hook-form manages
field state, validation wiring, and submission efficiently (with uncontrolled inputs, so
typing doesn't re-render the whole form), and Zod defines the validation schema
declaratively. Together they replace dozens of lines of hand-rolled, buggy form
plumbing.

**Handle the whole submission lifecycle and block double-submits.** A submission is
idle → pending → success or error. Disable the submit while pending (no double-submit),
show progress, give clear success feedback, and on error map server messages back to the
relevant fields. A form that only handles the success path is unfinished.

**Accessibility is part of "working."** Every input has an associated `<label>`; each
error is linked to its field with `aria-describedby`; on a failed submit, focus moves to
the first error; the result is announced. These are requirements, not enhancements — a
form that a screen-reader user can't complete is broken.

A working definition:

> **A production form manages input with a form library and schema, validates on the
> client for UX and on the server for security (never trusting the client), handles the
> full submission lifecycle (pending/success/error, no double-submit), and is accessible.
> The naive `useState`-per-field, client-only-validation, no-states version is a security
> and usability hole that merely looks done.**

## Production Example

**Invoicely's** "create invoice" form is the realistic case: a customer selector, a
dynamic list of line items (add/remove rows), and a submit that creates the invoice via
the Stage 3 backend. It exercises every concern — schema validation matching the server's
rules (Stage 3, Chapter 01: customer required, at least one line item, positive
quantities), a dynamic field array, a submission lifecycle with double-submit prevention,
server errors mapped back to fields, and accessible inputs.

We will build it with react-hook-form and Zod, submit it (via a Server Action or a React
Query mutation, Chapters 03–04), handle pending/success/error, and make it accessible —
then contrast it with the hand-rolled, client-only-validated, no-states, inaccessible
version an assistant produces. The client Zod schema deliberately mirrors the server's
Pydantic validation from Stage 3, and the chapter is explicit that the server check is the
one that counts.

## Folder Structure

```
web/src/features/invoices/
├── invoice-form-schema.ts     # Zod schema (mirrors the server's rules — client UX check)
├── CreateInvoiceForm.tsx      # "use client": react-hook-form + Zod, states, a11y
└── actions.ts                 # Server Action (or a React Query mutation) — server-side create
```

Why this shape: the schema is defined once and reused for client validation; the form
component owns the input, validation wiring, submission states, and accessibility; the
actual create runs on the server (Server Action or the Stage 3 API), which validates
authoritatively regardless of the client schema.

## Implementation

**The schema (`invoice-form-schema.ts`).** Zod defines the validation declaratively; it
mirrors the server's rules (Stage 3, Chapter 01) and gives the client instant feedback —
but it is the *client's* copy, not the source of truth.

```typescript
import { z } from "zod";

export const invoiceFormSchema = z.object({
  customerId: z.number({ required_error: "Select a customer." }),
  lineItems: z
    .array(
      z.object({
        description: z.string().min(1, "Description is required.").max(500),
        quantity: z.number().int().positive("Quantity must be positive."),
        unitPrice: z.number().nonnegative(),
      }),
    )
    .min(1, "Add at least one line item."),   // mirrors the server rule
});

export type InvoiceFormValues = z.infer<typeof invoiceFormSchema>;
```

**The form (`CreateInvoiceForm.tsx`).** react-hook-form + the Zod resolver: typed values,
declarative validation, a dynamic field array, the full submission lifecycle with
double-submit prevention, server errors mapped to fields, and accessible inputs.

```tsx
"use client";
import { useForm, useFieldArray } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { invoiceFormSchema, type InvoiceFormValues } from "./invoice-form-schema";
import { createInvoice } from "./actions";

export function CreateInvoiceForm({ customers }: { customers: Customer[] }) {
  const {
    register, control, handleSubmit, setError,
    formState: { errors, isSubmitting },        // isSubmitting drives the PENDING state
  } = useForm<InvoiceFormValues>({
    resolver: zodResolver(invoiceFormSchema),    // client validation (UX)
    defaultValues: { lineItems: [{ description: "", quantity: 1, unitPrice: 0 }] },
  });
  const { fields, append, remove } = useFieldArray({ control, name: "lineItems" });

  async function onSubmit(values: InvoiceFormValues) {
    const result = await createInvoice(values);   // SERVER validates authoritatively
    if (!result.ok) {
      // Map server field errors back to the fields (server is the source of truth).
      for (const [field, message] of Object.entries(result.fieldErrors ?? {})) {
        setError(field as keyof InvoiceFormValues, { message });
      }
      return;
    }
    // success: redirect / toast / reset
  }

  return (
    <form onSubmit={handleSubmit(onSubmit)} noValidate>
      <label htmlFor="customer">Customer</label>
      <select id="customer" aria-invalid={!!errors.customerId}
              aria-describedby={errors.customerId ? "customer-error" : undefined}
              {...register("customerId", { valueAsNumber: true })}>
        {customers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
      </select>
      {errors.customerId && <p id="customer-error" role="alert">{errors.customerId.message}</p>}

      {fields.map((field, i) => (            /* dynamic line items */
        <fieldset key={field.id}>
          <label htmlFor={`desc-${i}`}>Description</label>
          <input id={`desc-${i}`} aria-invalid={!!errors.lineItems?.[i]?.description}
                 {...register(`lineItems.${i}.description`)} />
          {/* quantity, unitPrice, remove button... */}
          <button type="button" onClick={() => remove(i)}>Remove</button>
        </fieldset>
      ))}
      <button type="button" onClick={() => append({ description: "", quantity: 1, unitPrice: 0 })}>
        Add line item
      </button>

      <button type="submit" disabled={isSubmitting}>   {/* NO double-submit */}
        {isSubmitting ? "Creating…" : "Create invoice"}
      </button>
    </form>
  );
}
```

**The submission runs — and validates — on the server (`actions.ts`).** Whether a Server
Action (Chapter 03) or a React Query mutation (Chapter 04), the create validates on the
server independently of the client schema. This is the authoritative check.

```ts
"use server";
import { invoiceFormSchema } from "./invoice-form-schema";

export async function createInvoice(values: unknown) {
  // SERVER-SIDE validation — authoritative, regardless of what the client did.
  const parsed = invoiceFormSchema.safeParse(values);   // (the FastAPI backend also validates)
  if (!parsed.success) {
    return { ok: false, fieldErrors: fieldErrorsFrom(parsed.error) };
  }
  // ...create via the backend (Stage 3), which enforces business rules too.
  return { ok: true };
}
```

**The anti-pattern — hand-rolled, client-only, no states, inaccessible.** Every gap here
is invisible in a screenshot:

```tsx
// ANTI-PATTERN: a useState per field, client-only validation trusted, no states, no a11y
function CreateInvoiceBad() {
  const [customerId, setCustomerId] = useState<number>();      // useState per field...
  const [description, setDescription] = useState("");
  function submit() {
    if (!customerId) { alert("pick a customer"); return; }      // client-only "validation"
    fetch("/api/invoices", { method: "POST", body: ... });      // server may not re-check!
    // no isSubmitting → double-submit; no label/aria → inaccessible; no error mapping
  }
  return <input onChange={(e) => setDescription(e.target.value)} />;  // no <label>
}
```

The difference is the whole chapter: the good version validates on the client for UX *and*
on the server for security, uses a library so state and validation aren't hand-rolled,
disables submit while pending (no double-submit), maps server errors to fields, and is
accessible. The bad version trusts client validation (a hole), hand-rolls buggy state, lets
users double-submit, and can't be used with a screen reader — while rendering identically.

## Engineering Decisions

Five decisions define a production form.

### Controlled or uncontrolled inputs — and which library?

**Options:** (1) controlled inputs (`useState` per field); (2) uncontrolled inputs via a
form library (react-hook-form).

**Trade-offs:** controlled inputs put every value in React state, which is explicit and
re-renders the form on every keystroke — fine for tiny forms, slow and verbose for large
ones. Uncontrolled inputs (the DOM holds the value, read on change/submit) are what
react-hook-form uses; they're performant and terse, at the cost of a library and its API.

**Recommendation:** use react-hook-form (uncontrolled by default) for anything beyond a
trivial one-field form — it handles state, validation wiring, field arrays, and submission
efficiently, and avoids re-rendering the whole form per keystroke. Hand-rolled controlled
state per field is the pattern to avoid; it's verbose, buggy, and slow at scale.

### Where does validation live?

**Options:** (1) client only; (2) server only; (3) both — client for UX, server
authoritative.

**Trade-offs:** client-only validation gives great UX and zero security (bypassable).
Server-only validation is secure and gives poor UX (a round-trip to learn a field is
required). Both gives instant feedback *and* real protection, at the cost of expressing the
rules in two places (mitigated by a shared or mirrored schema).

**Recommendation:** both, with the server authoritative. Validate on the client (Zod) for
immediate feedback, and validate independently on the server (Stage 3, Chapters 01/04) —
which is the only check that matters for security, because the client can always be
bypassed. Never treat client validation as protection.

### Share the validation schema, or duplicate it?

**Options:** (1) one shared schema used on client and server; (2) separate schemas that
mirror each other.

**Trade-offs:** a shared schema (possible in an all-TypeScript stack — the same Zod schema
on the Next client and a Next Server Action) is a single source of truth with no drift, at
the cost of requiring a shared codebase. When the backend is another language (Invoicely's
FastAPI/Pydantic), the client and server schemas are necessarily separate and must be kept
in sync by discipline.

**Recommendation:** share the schema where the stack allows (TypeScript client + TypeScript
server code) so there's one source of truth; where the backend is a different language,
mirror the rules and keep them in sync deliberately, remembering the server's schema is the
authoritative one. Either way, the client schema is a convenience, not the contract.

### Server Action or client mutation for submission?

**Options:** (1) a Next Server Action; (2) a client-side React Query mutation to an API.

**Trade-offs:** a Server Action runs the submission on the server without a hand-written
endpoint, works with progressive enhancement, and keeps logic server-side (Chapter 03), at
the cost of the newer pattern. A React Query mutation gives client-side cache management
around the submission (optimistic updates, invalidation — Chapter 04), at the cost of an
endpoint and client wiring.

**Recommendation:** use a Server Action for straightforward form submissions in the App
Router (clean, progressive-enhancement-friendly); use a React Query mutation when you need
client-side cache coordination around the submit (invalidate lists, optimistic UI). Either
way, validate on the server and handle the full lifecycle.

### How are server errors handled?

**Options:** (1) show a generic form-level error; (2) map server field errors back to the
specific fields.

**Trade-offs:** a generic error is simple and unhelpful ("something went wrong" — which
field?). Mapping server errors to fields tells the user exactly what to fix, at the cost of
a server error format that identifies fields and client code to route them.

**Recommendation:** map server field errors back to their fields (`setError` in
react-hook-form) so the user sees precisely what's wrong where, and reserve a form-level
error for genuinely form-wide problems (a failed submission, a conflict). This requires the
server to return structured, field-keyed errors — which the Stage 3, Chapter 05 error
contract supports.

## Trade-offs

Building forms well trades effort and a dependency for correctness, UX, and security.

**A form library trades a dependency for solving a hard, repetitive problem.** react-hook-form
adds a dependency and its API, and removes the verbose, buggy, slow hand-rolled form state
that teams otherwise reinvent. For anything past a trivial form the trade is clearly worth it;
a single-field form might not need it.

**Dual validation trades duplicated rules for UX-plus-security.** Validating on both client
and server means expressing the rules twice (or sharing a schema), and it's the only way to
get instant feedback *and* real protection. The duplication is the cost; a shared/mirrored
schema minimizes it; skipping the server side is not an option.

**Full lifecycle handling trades code for trust.** Pending states, double-submit prevention,
success feedback, and error mapping are more code than a bare submit, and they're what make
the form trustworthy — no double charges, no silent failures, clear recovery. The code is
modest; the reliability is not optional for anything that mutates data.

**Accessibility trades attention for reach and compliance.** Labels, error association, and
focus management take deliberate attention and make the form usable by everyone and compliant.
It's not extra work you can skip — an inaccessible form is a broken form for a real segment of
users, and increasingly a legal exposure.

## Common Mistakes

**Trusting client validation as security.** Validating only in the browser and assuming the
backend is therefore safe — bypassable, so unvalidated data reaches the server. Fix: client
validation for UX, independent server validation for security (Stage 3, Chapter 01).

**Hand-rolling form state.** A `useState` per field with manual `onChange` and validation —
verbose, buggy, and slow on large forms. Fix: react-hook-form + Zod.

**No submission states / double-submit.** A submit button always enabled, no pending
indicator, so users double-submit and can't tell what happened. Fix: disable submit while
pending, show progress, give success/error feedback.

**Generic errors / no field mapping.** "Something went wrong" with no indication of which
field failed. Fix: map server field errors back to fields; reserve form-level errors for
form-wide problems.

**Inaccessible forms.** Inputs without labels, errors not associated, no focus management. Fix:
`<label>` per input, `aria-describedby` for errors, focus the first error on failed submit.

**Schema drift.** Client and server validation rules that disagree, so the client accepts what
the server rejects (or vice versa). Fix: share the schema where possible, mirror and sync it
where not; the server is authoritative.

## AI Mistakes

Forms render fine in a screenshot, so the invisible parts — server validation, submission
states, accessibility — are exactly what an assistant skips. Review generated forms for what
happens on an invalid submit, a double-click, a server error, and a screen reader, not for
whether the fields appear.

### Claude Code: client-only validation trusted as protection

Asked to add form validation, Claude Code validates on the client (often nicely, with a schema)
and stops there — no server-side validation, and an implicit assumption that the client check
protects the backend. The form feels validated and the API is unprotected.

**Detect:** validation present only in the form component; no independent server-side
validation of the submitted data; a submit that posts to an endpoint (or action) that trusts
the payload; comments implying the client check is sufficient.

**Fix:** require server validation:

> Client validation is for UX only and can be bypassed. Validate the submitted data
> independently on the server (Server Action or API), which is the authoritative check —
> mirror the client rules there and never trust that the client validated. The server rejects
> invalid data regardless of the form.

### GPT: hand-rolled `useState`-per-field forms with no lifecycle

GPT-family models frequently build forms as a `useState` per field with manual `onChange`
handlers and no form library, and omit the submission lifecycle — no `isSubmitting`, no
disabled submit, no error mapping — because that's the most literal "make the inputs work"
approach. The result is verbose, allows double-submits, and gives no feedback.

**Detect:** multiple `useState` hooks for form fields with manual `onChange`; no
react-hook-form/Zod; a submit with no pending/disabled state; no success/error handling; no
double-submit guard.

**Fix:** require a library and the full lifecycle:

> Use react-hook-form with a Zod schema instead of a `useState` per field. Handle the whole
> submission lifecycle: disable the submit button while `isSubmitting` (prevent double-submit),
> show progress, give success feedback, and map server errors back to fields.

### Cursor: inaccessible fields and missing states

Wiring up inputs inline, Cursor tends to render bare inputs without associated labels, show
error text that isn't linked to its field, and leave the submit always enabled — because the
accessibility attributes and state wiring aren't visible from the markup at the edit site.

**Detect:** `<input>` with no associated `<label>` (no `htmlFor`/`id` pairing); error messages
not linked via `aria-describedby`; no `aria-invalid`; a submit button with no `disabled` during
submission; no focus moved to the first error.

**Fix:** require accessibility and state:

> Every input needs an associated `<label>`; link each error to its field with
> `aria-describedby` and set `aria-invalid`; move focus to the first error on a failed submit;
> and disable the submit button while the form is submitting. An inaccessible form is not a
> finished form.

## Best Practices

**Validate on the client for UX and on the server for security.** Use a client schema (Zod)
for instant feedback and validate independently on the server (Stage 3, Chapter 01), which is
authoritative and never trusts the client. Share the schema where the stack allows; mirror and
sync it where not.

**Use a form library and schema.** react-hook-form for state, validation wiring, field arrays,
and performant uncontrolled inputs; Zod for declarative validation. Don't hand-roll a `useState`
per field.

**Handle the whole submission lifecycle and block double-submits.** Disable the submit while
pending, show progress, give clear success feedback, and map server errors back to fields —
idle → pending → success/error, always.

**Make forms accessible.** A `<label>` per input, errors linked with `aria-describedby` and
`aria-invalid`, focus moved to the first error on failure, and the result announced.
Accessibility is part of "working," not an add-on.

**Submit on the server and map errors precisely.** Use a Server Action or a React Query
mutation, validate server-side, and return structured field-keyed errors (Stage 3, Chapter 05)
so the client can show the user exactly what to fix. Document form conventions in `CLAUDE.md`.

## Anti-Patterns

**The Trusted Client.** Validation only in the browser, treated as protection — bypassable, so
the server takes unvalidated data. The tell: no server-side validation behind a "validated"
form.

**The Hand-Rolled Form.** A `useState` per field with manual `onChange` and validation —
verbose, buggy, slow, and missing states. The tell: a dozen `useState` hooks and no form
library.

**The Double-Submit.** A submit button never disabled during submission and no pending state, so
users click twice and create duplicates. The tell: no `isSubmitting`/`disabled` on submit, and
duplicate records from impatient clicks.

**The Mystery Error.** A generic "something went wrong" with no field-level detail. The tell: a
form-level error and no mapping of server errors to specific fields.

**The Inaccessible Form.** Inputs without labels, unlinked errors, no focus management —
unusable with a screen reader. The tell: `<input>` with no `<label>`, and errors that assistive
tech never announces.

## Decision Tree

"I'm building a form — how do I make it correct?"

```
INPUT & STATE
└─ Beyond one trivial field? ──► react-hook-form (uncontrolled) + Zod schema.
   (Not a useState per field.)

VALIDATION
├─ CLIENT (Zod): instant feedback — UX only, bypassable.
└─ SERVER (Stage 3, Ch 01): independent, authoritative — the real check.
   Share the schema if same-language; mirror + sync if the backend differs. Never trust the client.

SUBMISSION
├─ Disable submit while pending (NO double-submit); show progress.
├─ Success → feedback / reset / redirect.
├─ Error → map SERVER field errors back to fields (setError); form-level error for form-wide issues.
└─ Run it on the SERVER: a Server Action (Ch 03) or a React Query mutation (Ch 04).

ACCESSIBILITY (required)
└─ <label> per input · aria-describedby links errors · aria-invalid · focus first error on failure.
```

## Checklist

### Implementation Checklist

- [ ] The form uses react-hook-form + a Zod schema, not a `useState` per field.
- [ ] Client validation gives UX feedback; the server validates independently and authoritatively.
- [ ] The submit is disabled while pending (no double-submit) with a progress indicator.
- [ ] Success and error are both handled; server field errors are mapped back to fields.
- [ ] Every input has an associated `<label>`; errors are linked via `aria-describedby` with `aria-invalid`.
- [ ] Focus moves to the first error on a failed submit.

### Architecture Checklist

- [ ] The validation schema is shared (same-language stack) or mirrored-and-synced (different backend), with the server authoritative.
- [ ] Submission runs on the server (Server Action or API) and returns structured field-keyed errors (Stage 3, Chapter 05).
- [ ] Form state (server/client) is handled with the right tools (React Query for the mutation where cache coordination is needed).
- [ ] Accessibility is treated as a requirement, tested with a screen reader/axe.
- [ ] Form conventions are documented in `CLAUDE.md`.

### Code Review Checklist

- [ ] Server-side validation exists and isn't skipped because the client validates (watch AI diffs).
- [ ] No hand-rolled `useState`-per-field form where a library belongs.
- [ ] Submit is disabled during submission; no double-submit path.
- [ ] Server errors are mapped to fields, not shown as a generic message.
- [ ] Inputs have labels, errors are associated, and focus is managed.

*(A Deployment Checklist is not applicable to this chapter.)*

## Exercises

**1. Add the server side.** Take a form with client-only validation (write one, or have an
assistant generate "a create-invoice form with validation") and add independent server-side
validation, then bypass the client (call the endpoint directly, or disable JS) to confirm the
server still rejects invalid data. The artifact is the server validation and the demonstrated
bypass-then-rejection.

**2. Replace the hand-rolled form.** Take a `useState`-per-field form with no submission states
and rebuild it with react-hook-form + Zod, adding a pending/disabled submit, server-error
mapping, and a dynamic field array. The artifact is the before/after and a note on the
double-submit the original allowed.

**3. Make it accessible.** Take a form with bare inputs and unlinked errors and make it
accessible: labels, `aria-describedby`/`aria-invalid`, focus-to-first-error on failure. Verify
with a screen reader or an accessibility linter (axe). The artifact is the accessible form and
the audit result before and after.

## Further Reading

- **react-hook-form documentation** (react-hook-form.com) — the standard form library; read
  "Get Started," "useFieldArray," and the validation/resolver docs. The reference for the input
  and submission mechanics in this chapter.
- **Zod documentation** (zod.dev) — declarative schema validation and type inference; the client
  half of the shared-schema pattern, and useful on the server too.
- **WAI-ARIA Authoring Practices — Forms, and the MDN forms accessibility guide**
  (w3.org/WAI/ARIA/apg; developer.mozilla.org) — the authoritative guidance on labels, error
  association, and focus management; the reference for the accessibility requirements this
  chapter treats as mandatory.
- **Next.js — "Forms and Mutations" / Server Actions** (nextjs.org/docs) — how to submit forms
  with Server Actions, including progressive enhancement and server-side validation; the
  submission half for the App Router.

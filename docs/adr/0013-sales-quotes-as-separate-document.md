# ADR 0013: Sales quotes (orcamentos) are a separate document, not the sales order's draft state

- Status: accepted
- Date: 2026-09-21

## Context

Tiago's slice 5 research notes (2026-09-21) add a "balcao" screen: a quote that prices a note with and without discount but commits nothing, kept separate from the sales screen. The sales screen must later be able to capture a saved quote and turn it into a real sale. He asked us to decide, before slice 5 design starts, whether this is already covered by `Sales::Order`'s existing `draft` state (ADR 0009) or needs a document of its own, and to record the decision.

`Sales::Order`'s transition table (ADR 0009) starts at `draft`, and `draft` already reserves nothing: `docs/scope.md`'s reservation lifecycle only reserves stock on approval. On that one axis, a draft order already behaves like a quote.

But the same research notes add requirements that only make sense once turning the note into a sale is the actual intent: the operator names which salesperson will carry out the sale "before anything else," and payment is chosen from the organization's configured methods. A price inquiry at the counter has neither yet, and most inquiries never become a sale. The demo tenant is a small counter distributor (`docs/scope.md`'s product section); quoting there is meant to be fast and disposable, the opposite of a sales order's document number, which `docs/scope.md` says is "sequential per organization and document type, assigned inside the transaction that creates the document," a guarantee that exists for traceability of real business documents.

## Options

| | Reuse `Sales::Order.draft` as the quote | A separate `Sales::Quote` document, captured into a new `Sales::Order` draft |
|---|---|---|
| Sales order number sequence stays meaningful | no: every abandoned counter inquiry burns a real order number and shows up whichever place later reads "open orders" | yes: an order only exists once someone actually means to sell |
| Required fields match intent at each stage | no: salesperson and payment method either become required too early (blocking a quick price check) or the order model grows optional fields no other draft state needs | yes: the quote only needs lines and prices; the order keeps requiring what a real sale requires |
| Fits ADR 0009's own taste (reversals are new records, never edits) | no: "capture" would have to mutate a draft order in place or bolt a second lifecycle onto the same table | yes: capturing is creating a new order from the quote's lines, the same shape as every other "new record referencing the original" in this codebase |
| Touches ADR 0004's lock order or the six-document state machine set | yes: it is the same table and the same machine | no: a quote never reserves stock, never locks a balance, title or counter; it sits entirely outside ADR 0004's order |
| Cost now | none: zero new schema | one more table, one more (small) state machine, one more screen |
| Milestone 2 reporting risk (ABC curve, dashboards) | inflates "draft orders" with intents that were never sales | none: only real orders count |

## Decision

A quote is its own lightweight document, `Sales::Quote` (name to be finalized in slice 5), independent of `Sales::Order`. Capturing a saved quote creates a brand new `Sales::Order` in `draft` state with its lines copied over; the quote keeps a reference to the order it produced. `Sales::Order`'s transition table (ADR 0009) is untouched.

Left open for slice 5 design, deliberately not decided here: the quote's own state table (something small: open, captured, discarded/expired), whether it gets a sequential document number or only an internal id, whether the salesperson is required at quote time or only at capture, and whether capture needs an `Idempotency-Key` (ADR 0005's critical-write list does not currently include plain order creation either; revisit together).

## Consequences

- A seventh document type in the domain, more code up front than reusing `draft`.
- `Sales::Order`'s draft count, document number sequence and (once Milestone 2 exists) any report reading orders stay meaningful; a counter that quoted 40 times and sold twice never pollutes them.
- The quote never touches ADR 0004's lock order, ADR 0006's rounding points or ADR 0009's transition table; its own rules (if it grows a state machine) get their own small ADR-free entry the way `HasStateMachine`-adjacent but lighter concerns already work elsewhere in this codebase, unless it turns out to need real concurrency control, in which case that is a new decision on its own.
- Slice 5 grows by one table, one capture command and one screen versus the reuse option.

## What would make me change my mind

- If slice 5 design finds that a captured quote must already hold a stock reservation before conversion (collapsing the two intents back together): revisit, this ADR's whole argument rests on quotes reserving nothing.
- If real usage shows the vast majority of quotes convert (say, over 80% in the seeded demo's realistic scenario), the volume-mismatch argument weakens and reuse becomes cheaper than it looks here.

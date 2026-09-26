# ADR 0015: Master data edits are checked against a revision, and documents will not depend on live master data

- Status: accepted
- Date: 2026-09-26

## Context

An adversarial review of slice 2 found three ways master data edits corrupt
what slices 3 to 5 will build on it:

1. Lost updates. `PATCH /products/:id` replaces the whole representation and
   nothing checked what it was based on. Admin A changes a conversion factor
   from 1000 to 50; admin B, whose form still holds 1000, saves a new name and
   silently puts 1000 back. `stale` was already in the API's list of conflict
   codes and nothing ever emitted it.
2. The stock unit can be edited. Every quantity of a product is stored in its
   stock unit, so changing it reinterprets balances (500 UN becomes 500 MIL).
3. Documents read live master data. A receipt priced with a factor of 1000 and
   an invoice issued to a partner whose CPF was corrected afterwards would show
   the new value on old documents, and the audit trail deliberately holds no
   personal data (ADR 0010) to reconstruct the old one.

Facts: one stock unit per product; one conversion row per product (ADR 0006);
`Catalog::UpdateProduct` already writes two rows in one transaction.

## Options

For (1), criteria in order: never loses an update, works when only a dependent
row (the conversion) changed, cost to the SPA and to the API contract.

| Option | Loses no update | Covers a conversion-only edit | Cost |
|---|---|---|---|
| A. Rails `lock_version` | yes | no: Rails skips the UPDATE, and so the check, when no column of the product changed | low |
| B. `ETag` and `If-Match` | yes | only if the tag covers the conversion | new header on every client and test |
| C. Explicit `revision` column, compared and bumped under a row lock | yes | yes, the command decides when to bump | low |
| D. Lock the record while someone has the form open | yes | yes | needs sessions, timeouts and release logic |

For (2) and (3) the options are to allow the change, forbid it, or forbid it
once it is dangerous; only the last needs stock movements, which do not exist
yet.

## Decision

1. **Option C** for products and partners, the two records other documents
   will point at. `catalog_products.revision` and `catalog_partners.revision`
   are integers starting at 0. A `PATCH` must send the revision it read. The
   command opens a transaction with `lock_timeout` of 3 seconds like its
   siblings, locks the row, compares, writes and increments in that same
   transaction. A mismatch answers `409 stale` with `current_revision` and
   writes nothing. An edit that changes nothing does not bump the revision or
   write an audit event. Units, categories and warehouses are not versioned: a
   rename there has no downstream numeric meaning and the last write wins.
2. **The stock unit is immutable after creation** (`stock_unit: immutable` on
   the model). Slice 3 relaxes it to "while the product has no stock movement",
   which is the first moment that rule can be evaluated.
3. **A rule for the slices that follow**: a purchase, sales or finance
   document copies, when it is created or posted, the values it depends on
   (the conversion factor, the partner's name and document) instead of
   reading them from the record later. Master data stays editable; documents
   stay true to the day they were issued.

## Consequences

- The SPA reads `revision` from the record it shows and sends it back. After a
  conflict it says nothing was saved and offers a reload that refetches the
  record and rebuilds the form.
- A client that does not send `revision` gets a 422; the API has one client.
- The revision is a second write to the row on every edit; both statements run
  under the same row lock, so it costs one extra statement per edit.
- Weakest assumption: that a stale edit should be refused rather than merged.
  With two admins on one product this is right; if partners grow many
  independently edited fields, a field-level merge may pay for itself.
- Documents that snapshot partner and product data make slices 3 to 6 a little
  wider (extra columns) and much safer.

## What would make me change my mind

- Users report frequent conflicts on records they edit in different fields:
  merge non-overlapping fields instead of refusing.
- A movement-based check turns out to be too coarse (a product needing a unit
  correction after a single test receipt): add a reviewed correction command
  instead of a general edit.
- Master data gets a bulk import: it needs its own revision semantics, since it
  writes many rows without a form.

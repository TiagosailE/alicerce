# ADR 0009: Explicit transition tables on the model, enforced by the domain

- Status: accepted
- Date: 2026-09-19

## Context

Sales orders, purchase orders, receipts, invoices, titles and installments move through states, and most of the dangerous bugs in an earlier project came from status being changed with a plain `update!(status:)` from several services: a cancelled booking could be paid and brought back to confirmed. Invalid transitions must be rejected by the domain, not merely hidden in the UI, and every allowed and forbidden transition needs a test. Reversals complicate the tables: cancelling an invoice moves its order backwards.

## Options

| | Plain enum + `update!` | AASM gem | Transition table on the model | Transition trigger in the database |
|---|---|---|---|---|
| Invalid transitions rejected | no | yes | yes | yes, even from SQL |
| Side effects | anywhere | callbacks inside the machine | in the command that transitions | none |
| Dependency or code | none | a gem and its DSL | one small concern | a trigger per table |
| Enumerating transitions for tests | manual | introspection | the table is data | duplicated in SQL |

## Decision

- Status is a string column with a `CHECK` constraint listing the valid states. The database restricts states, not transitions; transitions are the domain's job, and every write goes through a command.
- Each model declares its table as data. The sales order:
  `TRANSITIONS = { "draft" => %w[approved cancelled], "approved" => %w[draft partially_invoiced invoiced cancelled], "partially_invoiced" => %w[approved invoiced cancelled], "invoiced" => %w[approved partially_invoiced], "cancelled" => [] }`.
- A `HasStateMachine` concern, used by the six document models, provides `can_transition_to?` and `transition_to!`, which raises on an invalid transition. It is the only writer of the status column; `update!(status:)` is a forbidden pattern in `CONTRIBUTING.md`.
- Side effects never live in the concern or in callbacks; they belong to the command that calls `transition_to!` inside its transaction, after taking its locks (ADR 0004) and re-reading the state.

Reversal rules for sales orders:
- Cancelling an order releases its remaining reservations. A partially invoiced order can be cancelled: its invoices stay valid and only the uninvoiced quantities are released.
- Cancelling an invoice returns its stock at the cost it left with and cancels its receivables. If the order is still open (not cancelled), the order moves back (`invoiced` to `partially_invoiced` or `approved`, `partially_invoiced` to `approved` when no other invoice remains) and the returned quantities are reserved for it again, so it can be invoiced later. If the order was cancelled, it stays cancelled and the returned stock becomes available.

A shared spec iterates each model's table: every allowed transition succeeds and every pair not in the table raises. Reversal specs cover both branches above.

## Consequences

- One small concern with six users instead of a gem; the table doubles as the test fixture.
- A write that bypasses commands through raw SQL could set an invalid transition; the audit trail and the rule that only commands write are the controls, recorded in `docs/security.md`.

## What would make me change my mind

- Transitions needing guards that differ per organization or per role at the machine level: evaluate a workflow library in a new ADR.
- A second writer to these tables outside the application: add transition triggers.

# ADR 0009: Explicit transition tables on the model, checked by the domain and the database

- Status: accepted
- Date: 2026-09-19

## Context

Sales orders, purchase orders, receipts, invoices, titles and installments move through states, and most of the dangerous bugs in an earlier project came from status being changed with a plain `update!(status:)` from several services: a cancelled booking could be paid and brought back to confirmed. Invalid transitions must be rejected by the domain, not merely hidden in the UI, and every allowed and forbidden transition needs a test.

## Options

| | Plain enum + `update!` | AASM gem | Transition table on the model |
|---|---|---|---|
| Invalid transitions rejected | no | yes | yes |
| Side effects | anywhere | callbacks inside the machine | in the command that performs the transition |
| Dependency | none | one, with its own DSL and callbacks | none |
| Enumerating transitions for tests | manual | via introspection | the table is data |

## Decision

- Status is a string column with a `CHECK` constraint listing the valid states.
- Each model declares its table as data. The sales order, for example, where the backward moves come from invoice cancellation and cancelling a partially invoiced order releases only what was not invoiced:
  `TRANSITIONS = { "draft" => %w[approved cancelled], "approved" => %w[draft partially_invoiced invoiced cancelled], "partially_invoiced" => %w[approved invoiced cancelled], "invoiced" => %w[approved partially_invoiced], "cancelled" => [] }`.
- A small `HasStateMachine` concern, used by the six document models, provides `can_transition_to?(state)` and `transition_to!(state)`, which raises on an invalid transition and writes the status. It is the only writer of the status column; a RuboCop-level check is not available, so `update!(status:)` is listed in the forbidden patterns of `CONTRIBUTING.md` and searched in review.
- Side effects (reservations, movements, titles) never live in the concern or in callbacks; they belong to the command that calls `transition_to!` inside its transaction, after taking its locks and re-reading the state.
- A shared spec iterates the table of each model: every allowed transition succeeds, every pair not in the table raises.

## Consequences

- One small concern with six users instead of a gem; the table is readable by anyone and doubles as the test fixture.
- Commands must re-read the state after locking; the domain reviewer agent checks it.

## What would make me change my mind

- Transitions needing guards that differ per organization or per role at the machine level: evaluate a workflow library in a new ADR.

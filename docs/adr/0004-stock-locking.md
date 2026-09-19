# ADR 0004: Pessimistic row locks on stock balances, taken in a fixed order

- Status: accepted
- Date: 2026-09-19

## Context

Stock changes come from receipts, sales order approval (reservations), invoicing, invoice cancellation, adjustments, counts and transfers. Two of them touching the same product and warehouse at the same time must not both read the old balance: that is how an ERP oversells the last 50 bags of cement or lets on-hand go below zero. The rules are in `docs/scope.md`:

- `available = on_hand - reserved` per product and warehouse.
- `on_hand >= -negative_allowance`, where the allowance exists only through a recorded authorization.
- Average cost is kept as `value_cents` on the balance row; an issue takes value in proportion to quantity.

A sales order has several lines, so one command touches several balance rows. Popular products (cement, sand) are touched by almost every order: contention on a few hot rows is the normal case, not an edge case.

## Options

| | Optimistic (`lock_version`, retry on conflict) | Pessimistic (`SELECT ... FOR UPDATE`) | Atomic conditional `UPDATE` only | Serializable isolation |
|---|---|---|---|---|
| Behavior on hot rows | retries pile up; a 5 line order conflicts often | waits in line; each waits milliseconds | good for one row | aborts under contention, retries needed |
| Multi-row consistency | needs all versions checked and retried together | locks all rows, then checks, then writes | hard to express across rows and cost | correct, costly |
| Where the rule lives | app, with retry loop | app, readable, after the lock | SQL, one statement per rule | database |
| Deadlock risk | none | yes, prevented by lock order | low | none, but serialization failures |
| Testability | retries hide races | barrier tests show a clear winner | good | flaky under test |

## Decision

Pessimistic locking through one entry point, `Inventory::Balance.lock_for(pairs)`:

1. Sort the `(product_id, warehouse_id)` pairs ascending and remove duplicates.
2. Create missing balance rows with `INSERT ... ON CONFLICT DO NOTHING` so there is always a row to lock.
3. `SELECT ... FOR UPDATE` the rows in that order, inside the command's transaction.
4. Check availability, allowance and document state after the lock, then write movements and balances.
5. The document number counter, when the command creates a document, is locked last.

Database guards back the domain checks on the same row: `CHECK (on_hand >= -negative_allowance)`, `CHECK (reserved >= 0)`, `CHECK (negative_allowance >= 0)`. A negative allowance is raised only by `Inventory::AuthorizeNegativeStock`, which records who, why, the quantity cap and the expiry.

No external call happens while locks are held. Lock waits are bounded with `SET LOCAL lock_timeout = '3s'`; a timeout surfaces as 409 `conflict_retry`, and the idempotency key makes the retry safe.

## Consequences

- Concurrent approvals for the last units produce exactly one winner and one `insufficient_stock` failure, which is the flagship demo of the sales slice and has a real-thread barrier spec.
- Throughput on one hot product is serialized. At the scale of a small distributor (tens of orders per hour) the wait is milliseconds.
- Deadlocks are prevented by the fixed order; a spec runs two commands that touch the same products in opposite line order.
- Code that locks balances any other way is a review failure listed in `CONTRIBUTING.md`.

## What would make me change my mind

- Lock waits above 200 ms at the 95th percentile in production traces: split hot balances by warehouse zone or queue approvals per product.
- A move to a database without row locks, or to a pooler that breaks long transactions.

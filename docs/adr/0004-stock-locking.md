# ADR 0004: Pessimistic row locks in one global order

- Status: accepted
- Date: 2026-09-19

## Context

Stock changes come from receipts, sales order approval (reservations), invoicing, invoice cancellation, adjustments, counts and transfers. Two of them touching the same product and warehouse at the same time must not both read the old balance: that is how an ERP oversells the last 50 bags of cement. The rules are in `docs/scope.md`: `available = on_hand - reserved`, `on_hand >= -negative_allowance`, and average cost kept as value on the balance row (ADR 0006).

Popular products (cement, sand) are touched by almost every order, so contention on a few hot rows is the normal case. And commands lock more than balances: the document they act on, financial titles and installments, document number counters. Two commands that take the same rows in different orders deadlock.

## Options

| | Optimistic (`lock_version`, retry) | Pessimistic (`SELECT ... FOR NO KEY UPDATE`) | Atomic conditional `UPDATE` only | Serializable isolation |
|---|---|---|---|---|
| Hot rows | retries pile up; a 5 line order conflicts often | waits in line for milliseconds | good for one row | aborts under contention |
| Several rows and cost | all versions retried together | lock all, check, write | hard across rows | correct, costly |
| Deadlocks | none | prevented by a global order | rare | serialization failures instead |
| Testability | retries hide races | barrier tests show one winner | good | flaky under test |

## Decision

Pessimistic row locks, taken in one global order by every command:

1. `SET LOCAL lock_timeout = '3s'`, the first statement of the transaction.
2. The idempotency key row (ADR 0005).
3. The documents the command acts on (orders, receipts, invoices), ascending by table name then id, and their lines the same way.
4. Stock balances through `Inventory::Balance.lock_for(pairs)`: missing rows created with `INSERT ... ON CONFLICT DO NOTHING`, then `FOR NO KEY UPDATE` in ascending `(product_id, warehouse_id)` order. A transfer locks both warehouses' rows in that same order.
5. Financial titles, then their installments, ascending by id. A settlement follows the same rule: title first, then installment.
6. Document number counters, ascending by document type.

All checks that depend on locked rows (availability, allowance, document state, settlements present) happen after the lock, on re-read values.

Database guards back the domain on the balance row: `CHECK (on_hand >= -negative_allowance)`, `CHECK (reserved >= 0)`, `CHECK (negative_allowance >= 0)`. A negative allowance is raised only by `Inventory::AuthorizeNegativeStock`, which records who, why, the quantity cap and the expiry. Expiry is enforced by the domain at issue time: an expired allowance counts as zero for new issues, and the column is lowered to `max(0, -on_hand)` by the next movement on that balance, so the check never blocks the expiry itself.

Both lock timeouts (`55P03`) and deadlocks (`40P01`) surface as 409 `conflict_retry`; the idempotency key makes the retry safe. No external call happens while locks are held.

## Consequences

- Concurrent approvals for the last units produce exactly one winner and one `insufficient_stock` failure; a real-thread barrier spec proves it.
- A spec runs pairs of commands that touch the same rows from opposite ends (orders with reversed lines, a settlement against an invoice cancellation) and expects no deadlock.
- Throughput on one hot product is serialized; at tens of orders per hour the wait is milliseconds.
- Locking anything outside this order is a review failure listed in `CONTRIBUTING.md`.

## What would make me change my mind

- Lock waits above 200 ms at the 95th percentile: split hot balances by warehouse zone or queue approvals per product.
- A pooler that breaks long transactions.

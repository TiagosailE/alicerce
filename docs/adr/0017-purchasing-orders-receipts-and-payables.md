# ADR 0017: Purchase orders, receipts and payables

- Status: accepted
- Date: 2026-09-26

## Context

Slice 4 closes the first half of the loop: buy goods, receive them in parts,
see stock rise at what they cost, and see what is owed. `docs/scope.md` fixes the
contract (purchase order, approval, partial receipts, stock entry at the order's
cost, payables from what was received). ADR 0004 fixes the lock order, ADR 0005
idempotency, ADR 0006 the arithmetic, ADR 0009 the state machines, ADR 0015 that
documents copy what they depend on, ADR 0016 the ledger they post to.

What those leave open, and this decides: the shape of the documents, how a
discount, a unit conversion and a partial receipt round so receipts add up to the
order line, what a receipt creates on the finance side before the finance slice
exists, and the order of operations of `Purchasing::ReceiveGoods`. A design
review of the first draft of this ADR found real defects (a completion rule that
could yield a negative discount, a body that defeated the over-receipt guard,
steps that could not be executed in the order written, zero and tiny amounts left
undefined); each is settled below.

## Options

**Payables per receipt or per order.** Per order would make one title whose
installments change as receipts arrive. Per receipt makes a title final when it
exists, which is what settlement needs, and matches the architecture diagram
(`purchasing_receipts ||--o| finance_titles`). Per receipt.

**Discount as a fixed amount or as basis points.** A fixed amount has to be split
across partial receipts. Basis points (0 to 10000) apply to whatever is being
received. Basis points.

**Rounding a partial receipt.** Rounding each receipt on its own and letting the
last take the remainder (ADR 0006's completion rule as written) can make the last
receipt's discount negative: R$ 32,25 with 2% rounds each bag's discount 64,5 up
to 65, so 199 single-bag receipts take 12.935 against a line total of 12.900. The
cumulative rule below is monotone, so every amount is at least zero and the last
receipt lands on the line's totals with no special case. Cumulative.

**Unit conversion at the order or at the receipt.** At the receipt, so the order
stays in the unit the buyer thinks in (bags, thousands) and the conversion rounds
on what actually arrived, by the same cumulative rule.

**A receipt that cannot be reversed.** A reversal of a receipt cannot always take
back what it added: after later receipts at other costs and issues at the average,
removing the original net can leave a value that no longer follows the stock (10
units worth 3.000 after two receipts and an issue, reversing the first receipt of
5.000 leaves -2.000 at zero stock). Returns to suppliers are already out of scope
(`docs/scope.md`). So no receipt reversal in Milestone 1; see Decision.

## Decision

### Documents

All are tenant tables under row level security, with composite
`(organization_id, id)` foreign keys, `currency = 'BRL'` checks and cents in
`bigint`. A constraint added on an existing table is added `NOT VALID` and
validated in a following migration.

- `purchasing_orders`: `number` (unique per organization), the supplier
  (composite foreign key to the partner) with its name, document type and
  document number copied when the order is created (the number encrypted with
  Active Record's non-deterministic encryption, since nothing looks it up), `status`
  (a check on the five states below), payment terms (`installments` 1 to 24,
  `first_due_days` 0 to 365, `interval_days` 0 to 365), a free-text `note`,
  `total_cents` (the sum of the lines' net, stored), approval and cancellation
  stamps, and a `revision` (ADR 0015). Unique `(organization_id, id)`.
- `purchasing_order_lines`: (the database states the money formula in checks,
  `gross = round(quantity x price)` and `discount = round(gross x bp / 10000)`, and a
  trigger freezes a line once its order is not a draft, refusing any change to the
  quantity, price, discount, factor, unit, product or amounts and any insert or
  delete; only what has been received moves) the order, `position`, the product with its sku and
  name copied, the purchase unit and its code and the `factor` copied from the
  product's conversion (numeric(15,6)), `quantity` in purchase units
  (numeric(15,3)), `unit_price_cents` per purchase unit, `discount_bp`, and the
  line's `gross_cents`, `discount_cents` and `net_cents`, stored. What has been
  received is kept on the line: `received_quantity`, `received_stock_quantity`,
  `received_gross_cents`, `received_discount_cents`, with checks that each lies
  between zero and the line's own total. Unique `(organization_id, order_id, id)`,
  the target of the receipt lines' composite key. An order may hold two lines for
  the same product (two pack sizes, two prices).
- `purchasing_receipts`: `number` (unique per organization), the order, the
  warehouse (one per receipt), `received_on`, the supplier's invoice number as
  free text, `total_cents`, the actor, and a `status` with one state, `posted`
  (there is no reversal; see Consequences). Unique `(organization_id, order_id, id)`.
- `purchasing_receipt_lines`: the receipt, the order and the order line through
  one composite key `(organization_id, order_id, order_line_id)`, so a line always
  belongs to the receipt's own order; unique `(receipt_id, order_line_id)`, so a
  line is received at most once per receipt. The quantity in purchase units, the
  `stock_quantity` it became, `gross_cents`, `discount_cents`, `net_cents` (net is
  gross minus discount, a check), and copies of what it was priced with (unit price,
  `discount_bp`, factor, unit codes, product sku and name), so the receipt is a
  document that stands on its own.
- `document_counters`: `(organization_id, kind)` with the last number issued
  (built; the kind check is widened by each slice that adds a document type).
- `finance_titles`: kind (`payable` now, `receivable` with slice 5), the partner
  with its name copied, a typed `receipt_id` (composite key, unique) that slice 5
  will sit beside an `invoice_id` with a check that exactly one is set, `total_cents`
  greater than zero, and a `status` of `open` or `cancelled` (slice 6 adds the
  paid states).
- `finance_installments`: the title, `number` (unique per title), `due_on`,
  `amount_cents` greater than zero, and `settled_cents` (from zero to the amount);
  an index on `(organization_id, due_on)` for the overdue list.
- `inventory_movements` gains `kind = 'receipt'` and a typed, nullable
  `receipt_line_id` (composite key, unique where set), not a polymorphic
  `source_type`/`source_id`: a polymorphic pair cannot carry the composite tenant
  key ADRs 0015 and 0016 require. Slice 5 adds `invoice_line_id` the same way. The
  checks: a receipt movement has a positive quantity, no reason and a receipt line;
  a movement with a receipt line is a receipt. (`quantity = 0` with a value is
  allowed for other kinds by an existing check, so the receipt check must state
  `quantity > 0` itself.)

### State machines

`HasStateMachine` (ADR 0009) is built with this slice. Purchase orders:

`draft -> approved | cancelled`; `approved -> partially_received | received |
cancelled`; `partially_received -> partially_received | received | cancelled`;
`received` and `cancelled` are final.

`partially_received -> partially_received` is a real move (a second partial
receipt) and is in the table; a command only calls `transition_to!` when the status
actually changes. The command rule: every command that changes an order or its
lines, edits of a draft, approval, cancellation and receiving alike, locks the
order with `Order.lock("FOR NO KEY UPDATE").find` inside its transaction and
decides from that row, never from an instance loaded before the lock. A spec runs
each with a stale instance. Approval and cancellation need no line lock; receiving
locks the lines too.

Approval carries the `revision` the approver saw (ADR 0015), so an edit made
between the read and the click is refused as `409 stale` instead of approved unseen.
Approval requires at least one line, positive quantities and prices, an active
supplier that is a supplier, active products with a conversion, and every line's
gross and the order's total within `Ledger::VALUE_CAP_CENTS`, so an order that
could never be received cannot exist (a line's stock quantity must fit a movement's
`numeric(15,3)` too). Approval refreshes the descriptive copies (the supplier's name
and document, each product's name and sku) and freezes them, but never changes what
the approver saw in money: if a product's purchase unit or factor changed since the
draft was saved, approval is refused (`lines.N.conversion: changed`) and saving the
draft again refreshes the copy, bumps the revision and shows the approver the new
terms. An approved order cannot be
edited or returned to draft; a mistake is cancelled and created again. Cancelling
closes what has not been received; what was received stays.

A receipt against an order that is not `approved` or `partially_received` is
`409 invalid_transition`.

### Arithmetic

Every rounding is half up on exact rationals. A line's totals at creation:
`gross = round(quantity x unit_price)`, `discount = round(gross x discount_bp /
10000)`, `net = gross - discount`.

A receipt takes each amount as the difference of a cumulative figure. With `Qc` the
line's received quantity after this receipt and `prev_*` what earlier receipts took:

- `gross_r = round(Qc x unit_price) - prev_gross`
- `discount_r = round((prev_gross + gross_r) x discount_bp / 10000) - prev_discount`
- `stock_r = round(Qc x factor, 3 places) - prev_stock_quantity`
- `net_r = gross_r - discount_r`

Each cumulative figure is monotone in the quantity, so `0 <= discount_r <= gross_r`
and every amount is at least zero, and when the last receipt brings `Qc` to the
line's quantity the sums equal the line's `gross_cents`, `discount_cents` and
`round(quantity x factor, 3)` exactly. (A design review checked this on 200.000
random lines against the completion rule of ADR 0006, which failed 465 of 100.000.)
Nothing else rounds, except the last cost below.

The receipt movement's quantity is `stock_r` and its value is `net_r`.
`last_unit_cost` becomes `net_r / stock_r` rounded half up to 6 places when
`net_r > 0`, and is left alone when `net_r` is 0 (a free line must not wipe the
cost that ADR 0006 and `AdjustStock` rely on); a cost that would not fit
`numeric(19,6)` is refused as `too_large`. A receipt line whose `stock_r` is zero
is refused (`quantity_too_small`): a receipt movement moves stock. If that is what
remains of a line, the order is cancelled to close it.

The payable is the receipt's `total_cents`. No title is created when it is zero.
Otherwise the number of installments is `min(order.installments, total_cents)`, so
none is ever zero, split with `Money.allocate` (each part `total / n` rounded down,
the first `total mod n` parts one cent more). Due dates are `received_on +
first_due_days`, then every `interval_days`, as day offsets: there is no month-end
drift and no business-day adjustment.

`received_on` is a date in the organization's time zone
(`Time.current.in_time_zone(organization.time_zone).to_date` for the default, not
the application's zone), supplied by the client, never in the future and not
before the day the order was approved.

Worked example. 200 bags of cement (factor 1) at R$ 32,50, 2% discount: gross
650.000, discount 13.000, net 637.000. Receive 120: gross 390.000, discount 7.800,
net 382.200, stock +120 at a last cost of 3.185 cents, a payable of 382.200 in the
order's installments. Receive the remaining 80: `Qc` is 200, gross 650.000 - 390.000 =
260.000, discount 13.000 - 7.800 = 5.200, net 254.800; 382.200 + 254.800 = 637.000. At
R$ 32,25 the same rule receives 199 single bags and then the last one without a
negative discount. Bricks: 5 thousand at R$ 849,90 (84.990 cents), factor 1000: stock
5.000, net 424.950, last cost 84,99 cents. A payable of 382.201 in three
installments is 127.401, 127.400, 127.400.

### `Purchasing::ReceiveGoods`

A critical write: idempotent (ADR 0005), one transaction, at most one title, one
movement per line. The order of operations separates the locks (ADR 0004) from
the writes, so nothing waits on a number that depends on a row not yet written:

1. `SET LOCAL lock_timeout = '3s'`.
2. `Idempotency.run` (a replay returns the receipt as it is now).
3. The order, then its lines ascending by id, `FOR NO KEY UPDATE` (a document
   before its lines; ADR 0004's "ascending by table name" would put the lines
   first). The state is re-read: `approved` or `partially_received`.
4. The balances of every `(product, warehouse)` involved, through
   `Balance.lock_for`, ascending. A negative balance is refused (`negative_balance`)
   until the slice that can create one also posts the revaluation ADR 0016 orders.
5. With everything locked and re-read, validate and compute every line, in memory,
   in order: no duplicate order line in the request (`validation_failed`,
   `duplicate_line`), quantity positive and at most what is left (`over_receipt`; no
   tolerance), amounts by the cumulative rule, the value cap checked against each
   balance's running value across all the request's lines, the cost fits.
6. The receipt number, from `document_counters` (the last lock).
7. Write: the receipt, its lines, one `receipt` movement per line through
   `Inventory::Ledger.post` (each carrying its receipt line), the lines'
   received figures and the order's status, the title and its installments, the
   audit event. The links point one way (movement to receipt line, unique), so no
   row waits on one written after it.

Any failure rolls all of it back, the key and the number included. A lock timeout
or a deadlock is `conflict_retry`.

### API and roles

`GET/POST /purchase_orders`, `GET/PATCH /purchase_orders/:id` (a draft, with its
`revision`), `POST /purchase_orders/:id/approval` (with the `revision`), `POST
/purchase_orders/:id/cancellation`, `POST /purchase_orders/:id/receipts`
(`Idempotency-Key`), `GET /receipts` and `GET /receipts/:id` (the detailed report:
per line gross, discount and net, the stock quantity, what it was priced with, and
the payable), and a read-only `GET /payables`. Money is stored, so no screen sums
or rounds it.

ADR 0008's matrix decides who: owner, admin and purchasing write orders and
receipts; finance and read_only read them; sales has no access. Payables are
titles: owner, admin and finance read them, read_only too, purchasing does not.

The supplier's name and document are copied personal data (ADR 0012, ADR 0014):
the copy is masked for a role that may not see the partner's CPF in full, recorded
in the audit trail as changed without its value, and listed in the LGPD map. The
free-text `note` and `supplier_invoice_number` are filtered from request logs.

## Consequences

- One title per receipt: settlement never sees a title change.
- Receiving a line in any number of parts can never leave a cent behind, and no
  amount is ever negative.
- The receipt and the order line are self-contained documents; a corrected partner
  or product never rewrites them.
- A mistaken receipt (wrong warehouse, 1.200 instead of 120) cannot be reversed in
  Milestone 1. The way out is a stock adjustment out (valued at the average cost),
  the finance slice cancelling the title while nothing is settled, and cancelling
  the order and creating it again, because the over-receipt guard keeps a corrected
  receipt out of the same line. This is a limit of the MVP, stated in
  `docs/scope.md`; a return document (already listed there as out of scope) would
  add the reversal together with `reverses_movement_id`.
- **This amends ADR 0016 on two points**: the movement's `reverses_movement_id`
  arrives with the first reversal, which is invoice cancellation in slice 5, not
  here; and the revaluation-first receipt is still required, but only when negative
  stock can exist (slice 5), so `ReceiveGoods` refuses a negative balance until then.
- The receipts slice cannot go negative on stock.
- Weakest assumption: that the buyer thinks in whole purchase units per line.
- The supplier's invoice PDF is not part of this ADR: storing an upload on free
  hosting (an ephemeral disk) is its own decision with its own security review.

## What would make me change my mind

- Users need to undo receipts more than rarely: build the return document and
  `reverses_movement_id`, deciding the value a reversal takes out (the receipt's
  cost, the average, or a return at the current cost).
- Suppliers routinely invoice per shipment with totals that differ by cents from
  ours: add a supplier-invoice document between receipt and payable
  (`docs/scope.md` names this as out of scope for Milestone 1).
- Users ask to correct an approved order: allow a return to draft only while
  nothing is received, with the same revision check as a draft edit.

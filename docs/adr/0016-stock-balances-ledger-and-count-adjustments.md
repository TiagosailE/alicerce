# ADR 0016: Stock balances, an immutable movement ledger and count adjustments

- Status: accepted
- Date: 2026-09-26

## Context

Slice 3 is the first slice that changes stock. ADR 0004 fixes how rows are
locked, ADR 0005 how a critical write is made idempotent and ADR 0006 how cost
is kept (value on the balance row, every movement stores its value). Three
things those ADRs leave open, and that this slice must decide:

1. What an adjustment that adds stock is worth. A count that finds 40 more
   bags of cement, or the opening stock of a new warehouse, has no receipt to
   take a cost from, and the roadmap's demo for this slice includes "the
   average cost update".
2. The shape of the two tables everything later depends on: the balance
   (`inventory_balances`) and the ledger (`inventory_movements`).
3. Who may read stock and who may adjust it (ADR 0008 lists adjustments only).

Facts: `available = on_hand - reserved`; quantities are `numeric(15,3)`;
money is integer cents; a unit cost can be a fraction of a cent (bricks at
R$ 849,90 per thousand are 84.99 cents each), hence `last_unit_cost` is
`numeric(19,6)` (ADR 0006); negative stock exists only under a recorded
allowance, which nothing grants yet.

## Options

For the value of an incoming adjustment, criteria in order: no stock enters
the books at a made-up cost, the operator can supply the truth when there is
no better source, the moving average stays explainable from the ledger.

| Option | No made-up cost | Operator can state the truth | Average explainable |
|---|---|---|---|
| A. Always value at zero | yes, but the value is wrong | no | no: a zero-cost layer drags the average down |
| B. At the current average cost, else the last cost, else refuse until the operator states one; a stated cost always wins | yes | yes | yes |
| C. Always require the operator to state the cost | yes | yes | yes, but a routine count that finds one missing unit needs a price nobody has |

## Decision

**Count adjustment, option B.** `Inventory::AdjustStock` takes the counted
quantity, the balance the operator saw (`expected_on_hand`), a reason and an
optional note. Under the balance lock it computes `delta = counted - on_hand`
and writes one movement of that signed quantity. No difference writes no
movement.

- **A count is an observation at a moment.** If a sale or a receipt moved the
  balance since the operator looked (they saw 100, counted 98, and 10 were
  issued in between), applying the difference they meant would silently undo
  part of that movement. The count is refused with `409 stale`, carrying
  `current_on_hand`, exactly as an edit of master data is (ADR 0015); a refused
  attempt stores nothing, so the operator can look again and count again with
  the same key.
- **The reason agrees with the direction.** `loss`, `damage`, `theft` and
  `expiry` only decrease stock; `found` and `opening_balance` only increase it;
  `count` and `other` go either way. Reports built on reasons (losses, the
  income statement) depend on it. `opening_balance` is allowed only for a
  balance with no movement yet.
- **Values are bounded.** A movement and the running total stay within
  R$ 10 trillion (`Ledger::VALUE_CAP_CENTS`), refused as `too_large` on the
  field that caused it, so no input becomes a database range error.
- **A count may go below what is reserved.** The shelf is the shelf. The
  balance then shows a negative `available`; slice 5 must refuse new
  reservations while it is negative and answer `insufficient_stock` when
  invoicing an over-reserved order, rather than this command refusing a
  physical fact.

- A decrease is valued at the current average, `round_half_up(value_cents x
  quantity / on_hand)`, and the decrease that empties the balance takes all the
  remaining value (ADR 0006's issue rule). A unit cost on a decrease is
  rejected: it would mean nothing.
- An increase is valued at the operator's `unit_cost_cents` when given
  (`round_half_up(quantity x unit_cost)`, a named rounding point), which also
  becomes `last_unit_cost`; otherwise at the current average when the balance
  has stock and a positive value (a balance worth less than a cent a unit after
  rounding has no average); otherwise at `last_unit_cost` when it is positive;
  otherwise it is refused (`unit_cost_cents` required). Stock never enters the
  books at zero by default. The field is named `*_cents` like every amount, and
  is a decimal string because a unit can cost a fraction of a cent.
- A balance below zero is refused (`negative_balance`) until the slice that
  can create one also defines how an adjustment settles it.
- Reasons are a closed list: `opening_balance`, `count`, `loss`, `damage`,
  `theft`, `expiry`, `found`, `other`. A free-text note is optional and is
  recorded in the audit trail as changed, without its value (ADR 0010).

**Tables.** Both are tenant tables under row level security with composite
`(organization_id, id)` foreign keys, as ADR 0015 and the tenant-integrity
migrations require.

- `inventory_balances`: one row per organization, product and warehouse, with
  `on_hand`, `reserved`, `negative_allowance`, `value_cents`, `last_unit_cost`
  and `currency`. Checks: `on_hand >= -negative_allowance`, `reserved >= 0`,
  `negative_allowance >= 0`, the value has the sign of the stock and is zero
  when the stock is zero (it can be zero with stock left: a half-up share of a
  one-cent balance can round the last cent away), currency is BRL. Rows are created by
  `Inventory::Balance.lock_for`, never by a caller.
- `inventory_movements`: append-only (the same revoke and row trigger as the
  audit trail, ADR 0010, plus a statement trigger against TRUNCATE). Signed quantity, signed value, the balance's `on_hand` and
  `value_cents` after the movement, kind, reason, note and actor. The sum of
  every movement's quantity and value for a product and warehouse always equals
  the balance, and a spec asserts it after a sequence of adjustments. A mistake
  is corrected by a new movement, never by an edit.

**One writer.** `Inventory::Ledger.post` is the only code that writes a movement
and moves a balance, without a transaction or valuation of its own, so receipts,
issues and reversals will post through it inside their own transactions. It
re-reads the balance under the lock the caller holds instead of trusting the
instance it was given, so a stale copy (a second line of the same document
loaded before the first posted) cannot make a movement's "after" figures drift
from the ledger. Nothing in the database ties a balance to its last movement
(the app role must be able to update both); the single writer, this re-read and
the chain spec are the controls. Slice 5 adds `reserved` and the lowering of
`negative_allowance` (ADR 0004) to this one method, not to a second writer.

**A receipt that clears negative stock posts its revaluation first.** ADR 0006
lists the receipt and then a `revaluation` movement (quantity zero) for the
units that went out uncovered. Posted in that order, a receipt that lands
exactly on zero at a cost other than the last cost (on hand -4, value -4.400,
receive 4 at 1.200) would leave the balance at zero stock with a value of 400 for
an instant, which the `value follows stock` check refuses. So the slice that
builds receipts posts the revaluation of the uncovered units first (-4 units now
worth -4.800, still a valid negative balance) and the receipt second (0 units,
value 0). Every intermediate balance is valid, ADR 0006's numbers are
unchanged, and that slice specs both its worked example and this exact-clear
case.

**Idempotency** (ADR 0005) is `Idempotency.run` inside the command transaction
and `IdempotencyKey`. It handles a replay and a reused key itself and raises if
a block succeeds without completing its claim (a key committed with no resource
would replay as a 404). The digest covers the method, the path and every
parameter the action reads, the query string included. The header is required
on `POST /stock_adjustments`; a missing one answers 400, a reused key with
another request 422 `idempotency_key_reused`. `Idempotency::PurgeExpiredJob`
deletes keys older than 24 hours, organization by organization, every hour.

**Authorization.** Every role reads the balances. Sales reads quantities only:
what stock is worth and what it cost (`value_cents`, `last_unit_cost_cents`) is
margin data and is null for sales. The movement ledger, which names who moved
what and carries the note, is for every role but sales (ADR 0008's matrix gives
sales no stock access beyond seeing what is available to sell). This reads
ADR 0008's "read" for stock as: balances for all, the ledger for all but sales. Adjusting: owner, admin and purchasing, as ADR 0008's
matrix says, at most 60 requests a minute per user and 200 in ten minutes per
organization (each writes a permanent row, and the demo accounts are shared and
public, so several accounts of one organization must not add up to a flood). The capabilities live in
`Identity::Capabilities`.

**The note is free text in an immutable table.** It is filtered from request
logs, recorded in the audit trail as changed without its value, and can be
erased through the owner-only, organization-bound function
`inventory_movement_redact_note`, so an erasure request can be met without
weakening the ledger for anyone else. It is executable by the owner role only:
the app role is what an SQL injection would run as, and nothing in the
application calls the function. Erasing a note is therefore an operator's act
until the LGPD slice adds a command that records who did it. `db/structure.sql`
omits privileges, so `DatabaseRoles` re-revokes the function on every prepare in
development and test; a spec runs as the owner to prove the function works and
as a role that does hold the table privileges to prove the ledger's triggers.

**Locks.** The order of ADR 0004 is followed as written; a product row is locked
`FOR NO KEY UPDATE` everywhere (the edit commands of ADR 0015 included), because
a stock movement takes a `FOR KEY SHARE` lock on the product through its foreign
key and `FOR UPDATE` would make every product edit stall stock.

## Consequences

- The average cost changes visibly in the slice's demo, and every change is
  traceable to a ledger row.
- An operator who finds stock of a product that never had a cost must state
  one once. That is friction on purpose.
- Money helpers exist for the first time: `Inventory::Costing` holds the named
  rounding points as exact rational arithmetic, no floats.
- Known and left for later, on purpose: `source_type`/`source_id` and
  `reverses_movement_id` on movements (nullable columns are a safe expand step,
  best designed by the slice that first needs them, receipts and reversals);
  a database-level tie between a balance and its last movement (today the
  single writer and the chain spec carry it); allowing an adjustment on an
  inactive product or warehouse (a discontinued product still has stock to
  count); every role seeing the name of whoever made a movement (accountability
  is the point of a ledger); and clearing the ledger of the public demo, which
  the app role cannot do: the nightly reset (not built yet) runs as the owner
  role, which the trigger allows, deleting movements, balances and keys before
  reseeding. The seeds skip a balance that already has history, so a reseed
  after the keys expired does not fail as stale.
- Weakest assumption: that a stated cost overwriting `last_unit_cost` is the
  right treatment. It is the freshest cost knowledge the system has, but a
  clerk typing the wrong price would distort the next issue at zero stock; the
  ledger shows who did it and why.

## What would make me change my mind

- Stale refusals are frequent on busy products. A count takes minutes, and on a
  product that moves twenty times an hour the chance that the balance changed
  while someone counted is about 80%. Exact `expected_on_hand` is right for a
  count made in a quiet moment (closing time), and wrong for a live count of a
  hot product. The alternative is to let the operator state when they counted
  (`counted_at`, defaulting to when the form opened) and have the API derive the
  balance at that moment from the ledger (the current balance minus the
  movements after it), post the difference, and never refuse. That trades a
  refusal for a rule about trusting a client clock, so it waits for evidence that
  the refusals cost more than they protect.
- Users routinely count stock with no cost knowledge: allow a "no cost yet"
  state on the balance and a later revaluation, rather than refusing.
- Adjustments are needed in bulk (a full inventory count of thousands of
  products): a batch command and a separate document, not this one.

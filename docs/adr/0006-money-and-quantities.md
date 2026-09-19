# ADR 0006: Money as integer cents with a currency, cost kept as value, every rounding named

- Status: accepted
- Date: 2026-09-19

## Context

Prices, costs, invoices, installments and settlements must add up to the cent in Ruby, in Postgres and on screen. Floats cannot represent most decimal fractions and drift when summed. Building materials make the problem concrete: bricks are bought at R$ 849,90 per thousand and sold per unit (84.99 cents each), sand is sold in cubic meters with decimals, orders are invoiced in several loads, and a total split in three installments leaves cents over. Negative stock (allowed only with a recorded authorization) makes average cost undefined exactly when it is needed.

## Options

| | Float | `numeric(12,2)` + BigDecimal | Integer cents + currency | A money gem |
|---|---|---|---|---|
| Exact | no | yes | yes | yes |
| Same representation in Ruby, SQL, JSON, TypeScript | no | JSON needs strings | yes (integers) | Ruby only |
| Dependency | none | none | none | one more |

## Decision

**Representation.** Amounts are `bigint` columns named `*_cents`; every document and title carries `currency char(3)`, constrained to `'BRL'`. A small `Money` value object (cents plus currency) adds, subtracts, multiplies by a quantity and allocates; different currencies cannot be combined. Quantities are `numeric(15,3)` in Postgres, `BigDecimal` in Ruby and decimal strings in JSON (`"12.500"`); conversion factors are `numeric(15,6)`. The SPA formats with `Intl.NumberFormat("pt-BR")` and never computes money.

**Cost.** The balance row keeps `on_hand`, `value_cents` and `last_unit_cost` (`numeric(19,6)`, the cost of the latest receipt). Every movement stores its signed quantity and value, and the sum of movement values always equals `value_cents`:
- Receipt: value = quantity x purchase unit cost, rounded half up; `last_unit_cost` updated.
- Issue while `on_hand` covers it: value = `round_half_up(value_cents x quantity / on_hand)`; the issue that empties the balance takes all remaining value.
- Issue at zero or negative stock (only under an allowance): value = `round_half_up(quantity x last_unit_cost)`. An issue that crosses zero takes the remaining value for the covered part and `last_unit_cost` for the rest.
- Receipt that clears negative stock: after the receipt, the units that went out uncovered are revalued at the receipt's cost, and the difference is posted as a `revaluation` movement (quantity zero) against cost of goods sold.

Worked example: on hand 0, value 0, last cost 1.100 cents, allowance 10. Issue 4: value -4.400, balance -4 / -4.400. Receive 10 at 1.200: value +12.000, balance 6 / 7.600. Revaluation of the 4 uncovered units: 4 x (1.200 - 1.100) = -400, balance 6 / 7.200, which is 6 x 1.200. Movements sum to 7.200.

**Rounding points**, all half up and all named in code: purchase and sale line totals (quantity x unit price), partial invoice amounts, issue costs, quantity conversion between units (to three places), allocation. Nowhere else.
- Partial invoicing: each partial invoice of a line bills `round_half_up(quantity x unit price)`, except the one that completes the line, which bills the line total minus what was already billed. The invoices of a line always add up to the line total.
- Allocation (installments and any proportional split): each part gets `total / n` rounded down, and the first `total mod n` parts get one more cent. 10.000 in 3 gives 3.334, 3.333, 3.333; 10.001 in 3 gives 3.334, 3.334, 3.333. Specs assert these exact values, not only the sum.

## Consequences

- No rounding drift anywhere in the ledger; tests assert exact equality.
- Every price is parsed from a string into cents; more than two decimals is a validation error, not a silent rounding.
- Cost of goods sold for the income statement is the sum of issue and revaluation movement values, with no recomputation.

## What would make me change my mind

- A second currency in scope: amounts keep their shape, and an ADR defines exchange rates and when conversion happens.
- A product priced below one cent per unit being sold per unit: price per pack instead.

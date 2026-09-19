# ADR 0006: Money as integer cents with a currency, quantities as fixed-point decimals

- Status: accepted
- Date: 2026-09-19

## Context

Prices, costs, invoices, installments and settlements must add up to the cent, in Ruby, in Postgres and on screen. Floats cannot represent most decimal fractions and drift when summed. Building materials make the problem concrete: bricks are bought at R$ 849,90 per thousand and sold per unit (84.99 cents each), sand is sold in cubic meters with decimals, and a R$ 100,00 invoice split in three installments has a cent left over.

## Options

| | Float | `numeric(12,2)` + BigDecimal | Integer cents + currency | A money gem |
|---|---|---|---|---|
| Exact | no | yes | yes | yes |
| Sub-cent unit costs | lossy | lossy at 2 places | handled by keeping totals, not unit costs | depends |
| Same representation in Ruby, SQL, JSON, TypeScript | no | JSON needs strings | yes (integers) | Ruby only |
| Dependency | none | none | none | one more |

## Decision

- Amounts are `bigint` columns named `*_cents`, and every document or title carries `currency char(3)`, constrained to `'BRL'` until another currency is in scope. The API sends `*_cents` integers plus `currency`.
- A small `Money` value object (integer cents plus currency) does addition, subtraction, multiplication by a quantity with half-up rounding, and allocation. Money of different currencies cannot be combined.
- Unit costs are never stored. The balance row stores `value_cents`; an issue costs `round_half_up(value_cents * quantity / on_hand)`, and the last unit takes whatever value is left. The sum of movement values always equals the balance value.
- Rounding happens once per document line (quantity times unit price) and nowhere else. The rule is half up, named in code.
- Allocation (installments, and any future proportional split) divides evenly and gives the remaining cents to the first parts; a property spec checks that the parts always add up to the total.
- Quantities are `numeric(15,3)` in Postgres, `BigDecimal` in Ruby and strings with three decimals in JSON (`"12.500"`), because JavaScript numbers are floats. Unit conversion factors are `numeric(15,6)`.
- The SPA formats money and quantities with `Intl.NumberFormat("pt-BR")` and never computes them; totals come from the API.

## Consequences

- No rounding drift anywhere in the ledger; tests can assert exact equality.
- Every price input is parsed from a string into cents; an input with more than two decimals is a validation error, not a silent rounding.
- Reports divide cents only for display.

## What would make me change my mind

- A second currency in scope: amounts keep their shape, and an ADR defines exchange rates, their source and when conversion happens.
- A product priced below one cent per unit being sold per unit: price per pack instead of per unit, not fractional cents.

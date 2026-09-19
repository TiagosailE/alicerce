# Scope

## Product

Alicerce is a multi-tenant ERP for small Brazilian distributors. Its core is the closed loop purchase, stock, sale and finance, where every step leaves the others consistent: receiving goods raises stock and creates payables, invoicing a sale issues stock and creates receivables in the same transaction, cancelling an invoice reverses both, and every change is recorded in an append-only audit trail. Everything else (master data, reports, access control) exists to support that loop.

The demo tenant is a fictional building materials distributor in Paulo Afonso, Bahia, with a store and a yard as warehouses: it buys bricks by the thousand, cement by the bag and rebar by the bar, and sells them by the unit. A second, smaller tenant exists only to demonstrate isolation between organizations. All personal data in seeds, tests and screenshots is generated (valid CPF and CNPJ check digits, fictitious names).

Interface in Brazilian Portuguese only, with every string in locale files. Code, API and technical documentation in English. Currency is BRL.

## Invariants

Each one holds in the domain layer and, where the database can express it, in a constraint. Each one has a dedicated test.

1. Stock on hand never goes below zero, unless a recorded authorization grants a negative allowance on that balance; the database checks `on_hand >= -negative_allowance` on the same row.
2. Invoicing a sale and issuing its stock are atomic: both happen or neither does. The same holds for receiving and stock entry, and for every reversal.
3. Critical writes are idempotent through a key: sales order approval, invoicing, invoice cancellation, receiving, stock adjustments, settlements and settlement reversals.
4. Concurrent stock changes are serialized by a pessimistic lock on the balance row of each product and warehouse, taken in a fixed order.
5. Sales orders, purchase orders, receipts, invoices and financial titles move only through explicit state machines; invalid transitions are rejected by the domain, not only hidden in the UI.
6. Money is an integer number of cents with an explicit currency. No floats anywhere in the money path.

## Domain rules fixed at scope level

These are the rules the invariants depend on. The reasoning behind each lives in its ADR.

| Topic | Rule |
|---|---|
| Available stock | `available = on_hand - reserved` per product and warehouse. Approving a sales order reserves only what is available, under the balance lock. |
| Reservation lifecycle | Approval reserves; each partial invoice consumes its share; cancelling the order releases what was not invoiced. An approved order cannot be edited: returning it to draft releases its reservation. Cancelling an invoice of an open order reserves the returned quantities for that order again. Reservations do not expire in Milestone 1. |
| Lock order | One global order for every command: idempotency key, documents and their lines, balances in ascending `(product_id, warehouse_id)`, financial titles then installments, document number counters. A missing balance row is created with `INSERT ... ON CONFLICT DO NOTHING` before locking (ADR 0004). |
| Cost | Moving average per product and warehouse, kept as the inventory value in cents on the balance row with the last receipt cost. An issue takes value in proportion to quantity; at zero or negative stock it takes the last receipt cost, and the receipt that clears negative stock posts a revaluation movement. Every movement stores its value, so movements always add up to the balance value and are the source of cost of goods sold (ADR 0006). |
| Quantities | Decimal with three places (sand by the cubic meter); never floats. Purchase units convert to the stock unit with a per-product factor. |
| Rounding | Half up, at named points only: line totals, partial invoice amounts (the invoice that completes a line takes the remainder), issue costs, unit conversions and allocation. Allocation gives each part the total divided by the count rounded down and one extra cent to the first parts until the remainder is used: 10.001 in 3 is 3.334, 3.334, 3.333 (ADR 0006). |
| Overdue | Derived, never stored: an open installment whose due date is before today in the organization's time zone. |
| Settlements | Each settlement records principal, interest, fine and discount separately. Paying more than the open balance is rejected. |
| Reversals | Cancelling an invoice returns the stock at the cost it left with and cancels its receivables; it is refused while any installment has a settlement, which must be reversed first. Reversals are new records, never edits. |
| Idempotency keys | Unique per organization and user. A repeated key with the same method, path and body replays the original status and the resource; with a different request it is rejected. Only successes are stored, so a failed attempt can be retried with the same key. The UI keeps a key across network errors, 5xx and 409, and creates a new one after any other response (ADR 0005). |
| Document numbers | Sequential per organization and document type, assigned inside the transaction that creates the document. |
| Audit | Records actor, organization, action, record ids, changed field names and before and after values, except personal data and free-text fields, which are recorded as changed without their values, and an IP prefix instead of the address (ADR 0010). |

## MVP

### Milestone 1: the closed loop, live

| Module | Included |
|---|---|
| Identity and access | Organizations (tenants), users with a membership and a fixed role (owner, admin, purchasing, sales, finance, read-only), invitations, policies denied by default, database sessions with revocation on password change, rate-limited login, password reset with single-use expiring token, optional TOTP two-factor authentication. The data model allows a user in several organizations; the Milestone 1 interface handles one. |
| Master data | Partners as customers and/or suppliers with CPF or CNPJ (including the alphanumeric CNPJ format valid from July 2026), document fields encrypted at rest, products, categories, units of measure with per-product purchase conversion, warehouses |
| Inventory | Immutable stock movements, balance per product and warehouse, moving average cost, reservations, negative allowance authorizations, adjustments and physical counts with a mandatory reason, transfers between warehouses |
| Purchasing | Purchase order, approval, partial receipts, stock entry at the order's cost, payables generated from what was received, the supplier's invoice PDF attached to the receipt |
| Sales | Sales order, approval with reservation, partial invoicing that issues stock and creates receivables atomically, invoice cancellation, order cancellation that releases reservations |
| Finance | Payables and receivables in installments, partial settlements with interest, fine and discount, settlement reversal, overdue status, cash and bank accounts, cash position |
| Audit | Append-only trail of every relevant change, protected against UPDATE and DELETE in the database |
| Delivery | Public demo with test users and nightly data reset, README in English and Portuguese with screenshots, ADRs, OpenAPI document. Demo users are flagged: whatever their role, they cannot send email, invite users or change authentication settings (ADR 0008). |

### Milestone 2: insight and compliance

| Module | Included |
|---|---|
| Reports | Dashboard, ABC curve, stock turnover, projected cash flow, simplified income statement (DRE) built from stored movement costs and settlements |
| LGPD | Personal data map, export and anonymization on request of the data subject, retention jobs |
| Resilience | Automated backups and a documented, executed restore test; alert on spikes of 401 and 403 responses |
| Operations | Reservation expiry, write-offs of uncollectible receivables |

## Out of scope

Each item below has a named place where it would plug in; none of them gets code before it is in scope.

| Out | Where it would plug in |
|---|---|
| Fiscal documents (NF-e, NFS-e) and tax calculation | Invoicing happens in a single command. A fiscal integration would be a job enqueued inside that command's transaction; jobs live in the same database, so the enqueue commits or rolls back with the invoice. |
| Real bank integration (CNAB, Pix, Open Finance) | A bank integration would call the same settlement command with its own idempotency key. |
| Customer returns and returns to suppliers | A return document would reuse the compensating stock movements of invoice cancellation, per line. |
| Matching supplier invoices against receipts | Payables come from received quantities at the order price; a supplier invoice document would sit between receipt and payable. |
| Multiple currencies | Only BRL is accepted; amounts already carry their currency. |
| Lots, expiry dates, serial numbers | A lot would extend the balance key `(product, warehouse)`. |
| Payroll, manufacturing, price lists per customer, e-commerce integrations, mobile app, offline mode | None. |

## Roadmap in vertical slices

Each slice goes from migration to screen and ends in something that can be shown in the demo. Every slice ships its authorization and tenant isolation tests, OpenAPI updates and seeds.

| # | Slice | Demo at the end |
|---|---|---|
| 0 | Foundation: repository, CI with lint, tests, dependency audit, SAST and secret scanning; Compose for the database; application skeleton; hosting ADR; approved visual proposal; walking skeleton deployed | The empty app is live and every check runs on each pull request |
| 1 | Identity and access (without TOTP), audit trail base, tenant isolation harness | The owner invites a salesperson; the salesperson cannot open finance screens nor reach another organization's data through any endpoint |
| 2 | Master data | Building materials catalog with suppliers, customers and unit conversions |
| 3 | Inventory | A count adjustment with its reason, the movement ledger and the average cost update |
| 4 | Purchasing | Order 200 bags of cement, receive 120, see stock and the payable appear |
| 5 | Sales | Two salespeople approve orders for the last 50 bags at the same moment: one reserves, the other is refused. The approved order is invoiced in two loads, then one invoice is cancelled and its stock returns. |
| 6 | Finance | Partial settlement with interest, settlement reversal, overdue list, cash position |
| 7 | Hardening: TOTP two-factor authentication, session list and revocation screen | |
| | Milestone 1 | The closed loop live with README and screenshots |
| 8 | Reports | Dashboard, ABC curve, turnover, projected cash flow, DRE |
| 9 | LGPD, resilience and operations | Data subject export and anonymization, retention job, restore test report, reservation expiry |
| | Milestone 2 | |

Milestone 1 comes before any Milestone 2 work. There are no fixed dates. Each slice's pull request reports lines changed in the SPA versus the backend and its tests, which feeds the review criterion in ADR 0001.

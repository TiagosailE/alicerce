# Scope

## Product

Alicerce is a multi-tenant ERP for small Brazilian distributors. Its core is the closed loop purchase, stock, sale and finance, where every step leaves the others consistent: receiving goods raises stock and creates payables, invoicing a sale issues stock and creates receivables in the same transaction, and every change is recorded in an append-only audit trail. Everything else (master data, reports, access control) exists to support that loop.

The demo tenant is a fictional building materials distributor in Paulo Afonso, Bahia: it buys bricks by the thousand, cement by the bag and rebar by the bar, and sells them by the unit. A second, smaller tenant exists only to demonstrate isolation between organizations. All personal data in seeds, tests and screenshots is generated (valid CPF and CNPJ check digits, fictitious names).

Interface in Brazilian Portuguese only, with every string in locale files. Code, API and technical documentation in English. Currency is BRL, stored explicitly on every amount.

## Invariants

These hold in the domain layer and, where possible, in the database. Each one has a dedicated test.

1. Stock on hand never goes negative without an explicit, recorded authorization.
2. Invoicing a sale and issuing its stock are atomic: both happen or neither does.
3. Critical writes (invoicing, receiving, settling a title, stock adjustments) are idempotent through an idempotency key.
4. Concurrent stock changes are serialized by a lock on the balance row (the reasoning is in its own ADR).
5. Sales orders, purchase orders, receipts and financial titles move only through explicit state machines; invalid transitions are rejected by the domain, not only hidden in the UI.
6. Money is an integer number of cents plus a currency. No floats anywhere in the money path.

## MVP

### Milestone 1: the closed loop, live

| Module | Included |
|---|---|
| Identity and access | Organizations (tenants), users, memberships in more than one organization, invitations, fixed roles (owner, admin, purchasing, sales, finance, read-only), policies denied by default, database sessions with listing and revocation, rate-limited login, password reset with single-use expiring token, optional TOTP two-factor authentication |
| Master data | Partners as customers and/or suppliers with CPF or CNPJ (including the alphanumeric CNPJ format valid from July 2026), products, categories, units of measure with per-product purchase conversion, warehouses |
| Inventory | Immutable stock movements, balance per product and warehouse, moving average cost, reservations from approved sales orders, adjustments and physical counts with a mandatory reason, transfers between warehouses |
| Purchasing | Purchase order, approval, partial receipts, stock entry at the order's cost, payables generated from what was received |
| Sales | Sales order, approval with stock reservation, invoicing that issues stock and creates receivables atomically, cancellation that releases reservations |
| Finance | Payables and receivables in installments, partial settlements, overdue status, cash and bank accounts, cash position |
| Audit | Append-only trail of every relevant change: actor, organization, action, before and after, time, IP and request id; protected against UPDATE and DELETE in the database |
| Delivery | Public demo with a test user and nightly data reset, README in English and Portuguese with screenshots, ADRs, OpenAPI document |

### Milestone 2: insight and compliance

| Module | Included |
|---|---|
| Reports | Dashboard, ABC curve, stock turnover, projected cash flow, simplified income statement (DRE) |
| LGPD | Personal data map, export and deletion on request of the data subject, retention jobs, field encryption for documents (encryption itself ships in Milestone 1 with the partner model) |
| Resilience | Automated backups and a documented, executed restore test; alert on spikes of 401 and 403 responses |

## Out of scope

Each item below is modeled as an extension point: a place in the design where it would plug in, without speculative code.

| Out | Extension point |
|---|---|
| Fiscal documents (NF-e, NFS-e) and tax calculation (ICMS, IPI, ST, PIS, COFINS) | Invoicing writes an `invoice.issued` event to the transactional outbox; a fiscal integration would consume it. Invoice lines keep a tax amount column fixed at zero. |
| Real bank integration (CNAB, Pix, Open Finance) | Settlements are recorded manually with a payment method; a bank integration would create the same settlement through the same command and idempotency key. |
| Payroll and HR | None; no personnel data is modeled beyond users. |
| Multiple currencies with conversion | Every amount already carries its currency; only BRL is accepted. |
| Lots, expiry dates, serial numbers | Stock movements are keyed by product and warehouse; a lot dimension would extend that key. |
| Manufacturing, price lists per customer, e-commerce and marketplace integrations, mobile app, offline mode | None. |

## Roadmap in vertical slices

Each slice goes from migration to screen and ends in something that can be shown in the demo. Every slice ships its authorization and tenant isolation tests, OpenAPI updates and seeds.

| # | Slice | Demo at the end |
|---|---|---|
| 0 | Foundation: repository, CI with lint, tests, dependency audit, SAST and secret scanning; Compose for the database; application skeleton; approved visual proposal; walking skeleton deployed | The empty app is live and every check runs on each pull request |
| 1 | Identity and access, audit trail base, tenant isolation harness | Owner invites a salesperson; the salesperson cannot open finance screens nor reach another organization's data through any endpoint |
| 2 | Master data | Building materials catalog with suppliers, customers and unit conversions |
| 3 | Inventory | A count adjustment with its reason, the movement ledger and the average cost update |
| 4 | Purchasing | Order 200 bags of cement, receive 120, see stock and the payable appear |
| 5 | Sales | Approve an order (stock reserved), invoice it (stock issued and receivables created in one transaction); two concurrent invoices for the last units: one succeeds, one is rejected |
| 6 | Finance | Partial settlement of a receivable, overdue list, cash position |
| | Milestone 1 | The closed loop live with README and screenshots |
| 7 | Reports | Dashboard, ABC curve, turnover, projected cash flow, DRE |
| 8 | LGPD and resilience | Data subject export and deletion, retention job, restore test report |
| | Milestone 2 | |

Milestone 1 comes before any Milestone 2 work. There are no fixed dates.

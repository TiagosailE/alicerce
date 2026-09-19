# Architecture

How Alicerce is put together and why. Decisions are recorded in [docs/adr](adr/README.md); the domain rules are in [docs/scope.md](scope.md).

## Context

```mermaid
flowchart LR
  staff["Staff of a distributor<br/>(owner, purchasing, sales, finance)"]
  visitor["Portfolio visitor<br/>(demo user)"]
  alicerce["Alicerce<br/>Rails API + React SPA<br/>one Docker image on Render"]
  db[("Postgres 18<br/>Supabase")]
  mail["Brevo<br/>transactional email API"]
  monitor["Uptime monitor"]
  gha["GitHub Actions<br/>CI, backups, restore test"]

  staff -->|HTTPS| alicerce
  visitor -->|HTTPS| alicerce
  alicerce -->|SQL, session pooler| db
  alicerce -->|HTTPS| mail
  monitor -->|GET /up| alicerce
  gha -->|pg_dump| db
```

## Components

```mermaid
flowchart TB
  subgraph browser["Browser"]
    spa["React SPA<br/>features/*, TanStack Query,<br/>typed client from OpenAPI"]
  end

  subgraph app["Rails 8.1 process (Puma)"]
    shell["SpaController<br/>shell + CSP"]
    api["Api::V1 controllers<br/>authenticate, set tenant, authorize"]
    policies["Pundit policies<br/>(ADR 0008)"]
    commands["Commands per context<br/>transaction, locks, state, idempotency, audit"]
    queries["Queries<br/>filters, sort, pagination"]
    models["Models<br/>TenantScoped, transition tables, Money"]
    jobs["Solid Queue workers<br/>(inside Puma)"]
  end

  subgraph pg["Postgres"]
    tables["Domain tables<br/>RLS by organization (ADR 0003)"]
    infra["solid_queue_*, solid_cache_*<br/>idempotency_keys, audit_events"]
  end

  spa -->|"/api/v1 JSON, cookie session,<br/>X-CSRF-Token, Idempotency-Key"| api
  spa -->|"deep links"| shell
  api --> policies
  api --> commands
  api --> queries
  commands --> models
  queries --> models
  models --> tables
  commands --> infra
  jobs --> infra
  jobs --> commands
```

Contexts and what they own:

| Context | Owns |
|---|---|
| identity | organizations, users, memberships, invitations, sessions |
| catalog | partners, products, categories, units, unit conversions |
| inventory | warehouses, balances, movements, reservations, negative allowances, counts |
| purchasing | purchase orders, receipts |
| sales | sales orders, invoices |
| finance | titles, installments, settlements, accounts |
| audit | audit events |

Only a context's commands write its tables. Cross-context effects (an invoice creating receivables) happen inside the command of the context that starts them, in one transaction.

## Data model (Milestone 1 core)

Business tables, `audit_events`, `idempotency_keys` and `identity_invitations` carry `organization_id` under row level security; the identity tables used before a tenant is known (users, organizations, memberships, sessions) and the Solid Queue and Solid Cache tables do not (ADR 0003). `organization_id` is omitted below for readability.

```mermaid
erDiagram
  identity_organizations ||--o{ identity_memberships : has
  identity_users ||--o{ identity_memberships : has
  identity_users ||--o{ identity_sessions : signs_in
  identity_organizations ||--o{ identity_invitations : has
  identity_users ||--o{ identity_invitations : invites
  identity_organizations ||--o{ catalog_partners : has

  catalog_products ||--o{ inventory_balances : "stocked as"
  inventory_warehouses ||--o{ inventory_balances : holds
  inventory_balances ||--o{ inventory_movements : "changed by"
  inventory_balances ||--o{ inventory_reservations : "held by"

  catalog_partners ||--o{ purchasing_orders : supplies
  purchasing_orders ||--o{ purchasing_order_lines : has
  purchasing_orders ||--o{ purchasing_receipts : "received in"
  purchasing_receipts ||--o{ inventory_movements : "enters stock"

  catalog_partners ||--o{ sales_orders : buys
  sales_orders ||--o{ sales_order_lines : has
  sales_order_lines ||--o{ inventory_reservations : reserves
  sales_orders ||--o{ sales_invoices : "invoiced in"
  sales_invoices ||--o{ sales_invoice_lines : has
  sales_invoice_lines ||--o{ inventory_movements : "issues stock"

  purchasing_receipts ||--o| finance_titles : "creates payable"
  sales_invoices ||--o| finance_titles : "creates receivable"
  finance_titles ||--o{ finance_installments : "split in"
  finance_installments ||--o{ finance_settlements : "settled by"
  finance_accounts ||--o{ finance_settlements : receives

  inventory_balances {
    bigint product_id
    bigint warehouse_id
    numeric on_hand "CHECK on_hand >= -negative_allowance"
    numeric reserved "CHECK reserved >= 0"
    numeric negative_allowance
    bigint value_cents "average cost kept as value"
  }
  inventory_movements {
    string kind "receipt, issue, adjustment, count, transfer, reversal"
    numeric quantity "signed"
    bigint value_cents "signed; cost of goods sold on issues"
    string source_type
    bigint source_id
  }
  sales_orders {
    string number
    string status "draft, approved, partially_invoiced, invoiced, cancelled"
    char currency "BRL"
  }
  finance_installments {
    date due_on
    bigint amount_cents
    bigint settled_cents
  }
```

## Invoicing a sales order

The flow that proves the loop: invoicing issues stock and creates receivables in one transaction, and a retry with the same key changes nothing.

```mermaid
sequenceDiagram
  autonumber
  participant SPA
  participant API as Api::V1::SalesInvoicesController
  participant Cmd as Sales::InvoiceOrder
  participant Idem as Idempotency
  participant Inv as Inventory::Balance
  participant Fin as Finance
  participant DB as Postgres

  SPA->>API: POST /api/v1/sales_orders/184/invoices<br/>Idempotency-Key, X-CSRF-Token, lines
  API->>API: session lookup, set app.organization_id, authorize (policy)
  API->>Cmd: call(order, lines, actor, key)
  Cmd->>DB: BEGIN, SET LOCAL lock_timeout = 3s
  Cmd->>Idem: INSERT key (organization, user, key, digest) ON CONFLICT DO NOTHING RETURNING
  alt key existed with the same digest
    Idem-->>API: original status and the invoice as it is now (no effect)
  end
  Cmd->>DB: lock the order and its lines, re-read status
  Cmd->>Inv: lock_for(pairs sorted by product, warehouse)
  Inv->>DB: INSERT balances ON CONFLICT DO NOTHING<br/>SELECT ... FOR NO KEY UPDATE (ascending)
  Cmd->>Cmd: check reserved quantities cover the lines
  Cmd->>DB: movements out (quantity, cost from value), consume reservations, update balances
  Cmd->>Fin: create receivable title and installments (allocation, first parts take the extra cents)
  Cmd->>DB: lock the document counters last, number the invoice and the title
  Cmd->>DB: order.transition_to!(partially_invoiced or invoiced)
  Cmd->>DB: audit event, store status and invoice id on the idempotency key
  Cmd->>DB: COMMIT
  Cmd-->>API: Result.success(invoice)
  API-->>SPA: 201 { data: invoice }
```

If any step fails, the transaction rolls back entirely: no invoice without stock issue, no stock issue without receivable, and the idempotency key is gone too, so the retry runs again. A lock timeout or deadlock answers 409 and the SPA retries with the same key (ADR 0004, 0005).

## Request lifecycle

1. TLS ends at the platform edge. Thruster (port 10000, compression, 8 MB cache) forwards to Puma.
2. Host authorization (`APP_HOST`), HSTS, request id. Rails assumes SSL behind the edge.
3. Hashed files under `/spa/assets/` are served as static files with immutable caching. Page navigations (HTML requests to paths without a file extension, outside `/api` and `/spa`) go to `SpaController`, which returns the shell from `frontend/dist` with the CSP header. Anything else answers 404.
4. `/api/v1/*`: session from the `__Host-session` cookie, CSRF check on writes, tenant setting on the connection, the organization's time zone, Pundit authorization, command or query, serializer, JSON envelope.
5. Structured logs with request id, user id and organization id, with personal data filtered.

## Background work

Solid Queue runs as threads inside the Puma process (async mode: one worker thread, a dispatcher and a scheduler) and uses the same database, so a job enqueued in a transaction commits or rolls back with it. Recurring tasks: clearing finished jobs, expiring idempotency keys, the nightly demo reset. External calls (email) always run in jobs, never inside a request transaction. The production image in CI checks that all Solid Queue roles register and that the whole process stays under a 450 MB budget (121 MiB measured).

## Time

Rails runs in `America/Sao_Paulo` (`config.time_zone = "Brasilia"`) and stores timestamps in UTC. Each organization has its own time zone: API requests and jobs run inside `Time.use_zone(organization.time_zone)`, so `Date.current` is the organization's date. Overdue status compares due dates with that date: at 23:30 in Manaus it is already 00:30 in Brasília, and an installment due that day is not yet overdue for a Manaus tenant. Recurring tasks name their zone explicitly in the schedule (`every day at 3am America/Sao_Paulo`), because the container clock is UTC.

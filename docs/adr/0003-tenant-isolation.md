# ADR 0003: Tenant isolation by organization_id, enforced by the app and by Postgres row level security

- Status: accepted
- Date: 2026-09-19

## Context

Every organization's purchases, stock, sales and finances share one database. Reading or changing another organization's record (IDOR across tenants) is the most damaging bug an ERP can ship, and it is the easiest to introduce: one `find` without a scope is enough. The demo is public, so anyone can sign in and try ids.

The database is a single Supabase Postgres (ADR 0002) reached through the session pooler, which keeps one server connection per client connection, so a session setting survives for as long as Rails holds the connection. Postgres row level security (RLS) can filter rows by such a setting. Two details shape the design: once a custom setting has been set on a connection, resetting it leaves an empty string rather than null, and Rails 8.1 returns a connection to the pool at the end of a `with_connection` block unless the request has leased it.

Not every table can be filtered by tenant. Authentication must find a session by its token and a user's memberships before any organization is known, and an invitation is opened by its token by someone who belongs to no organization yet.

## Options

| | Shared tables, app scoping only | Shared tables, app scoping plus RLS on business tables | Schema per tenant | Database per tenant |
|---|---|---|---|---|
| A forgotten scope leaks business data | yes | no, Postgres returns no rows | no | no |
| Migrations | one run | one run | one run per tenant | one run per tenant |
| Fits one free Postgres | yes | yes | until catalog bloat | no |
| Operational complexity | lowest | one setting per request, two roles | high | highest |

## Decision

Shared tables with a mandatory `organization_id`, enforced twice.

**Application.** Every tenant model includes `TenantScoped`: `belongs_to :organization` and a default scope on `Current.organization`, which raises when there is no current organization instead of returning everything. Controllers never read `organization_id` from parameters. A record of another organization answers 404.

**Database.** Every business table (catalog, inventory, purchasing, sales, finance) and `audit_events`, `idempotency_keys` and `identity_invitations` has RLS enabled and one policy for the app role:
`USING (organization_id = NULLIF(current_setting('app.organization_id', true), '')::bigint)` with the same `WITH CHECK`. Unset and reset both produce null, and null matches nothing.

Tables without tenant RLS, each with a single reviewed access path and its own specs:
- `identity_users`: global, one row per person; read through memberships or by email at sign-in.
- `identity_sessions`: looked up by token digest before any tenant is known; deleted by `user_id` when a password or role changes, across all organizations of that user.
- `identity_memberships` and `identity_organizations`: read by `user_id` to list a user's organizations at sign-in and when switching.
- Solid Queue and Solid Cache tables: infrastructure without tenant data.
Invitations keep RLS; the acceptance endpoint reads one invitation by token digest through `Identity::Invitation.find_by_token`, which sets the tenant from a SECURITY DEFINER lookup of the invitation's organization before loading it.

**Applying the setting.**
- After authentication, the API base controller leases the connection for the rest of the request (`ActiveRecord::Base.lease_connection`), so every query of the request runs on it, and calls `set_config('app.organization_id', id, false)`. An `ensure` resets it. A pool `checkin` callback resets it only on connections that carried a tenant (a flag on the connection), so Solid Queue's polling pays no extra round trip.
- Jobs lease and set the same way in an `around_perform` from their organization argument.
- `load_async` and threads spawned inside a request are not used on tenant tables; the setting would not follow them.
- Work that spans organizations (idempotency key expiry, the nightly demo reset, retention) loops over organizations and sets the tenant for each. Schema changes and backfills run as the owner role, which owns the tables and is therefore not subject to RLS; `FORCE ROW LEVEL SECURITY` is not used.

**Roles.** Production uses two roles created by hand (SQL in `docs/deploy.md`), neither with `BYPASSRLS`: `alicerce_owner` runs migrations and owns the tables; `alicerce_app` serves requests and jobs with row privileges only, so it can neither change a policy nor disable RLS.

**Tests run under RLS.** Development and CI create an `alicerce_app` role with the production grants. Migrations and schema loads run as the database owner; the test suite connects as `alicerce_app`, so every spec runs with the policies active and a missing tenant setting shows up as a failing test, not as a silent pass under a superuser. Dedicated specs also prove with raw SQL that another organization's rows are invisible and cannot be inserted or updated.

Schema format: policies, triggers and functions do not fit `schema.rb`, so the schema is dumped to `db/structure.sql` from the first policy on.

## Consequences

- A missing scope on a business table becomes an empty result instead of a leak, and the suite catches it because it runs as the app role.
- The identity tables are protected by application code only; their few access paths are listed above, named in code and covered by the isolation specs.
- Transaction pooling (Supabase port 6543) cannot be used; the session pooler is required.
- Requests hold one connection each for their whole duration; with 3 Puma threads and 1 job thread the pool stays small (ADR 0002).

## What would make me change my mind

- Measured overhead of RLS above 10 percent on the heaviest report query, after indexes that start with `organization_id`: keep application scoping on reads and RLS on writes.
- A pooler in transaction mode: switch to `SET LOCAL` inside a per-request transaction.
- A tenant needing data residency: database per tenant for that customer.

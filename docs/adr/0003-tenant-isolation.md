# ADR 0003: Tenant isolation by organization_id, enforced by the app and by Postgres row level security

- Status: accepted
- Date: 2026-09-19

## Context

Every organization's purchases, stock, sales and finances share one database. Reading or changing another organization's record (IDOR across tenants) is the most damaging bug an ERP can ship, and it is the easiest to introduce: one `find` without a scope is enough. The demo is public, so anyone can sign in and try ids.

The database is a single Supabase Postgres (ADR 0002). Postgres 18 supports row level security (RLS) with policies that read a session setting. Supabase's default `postgres` role bypasses RLS, so the application needs its own role. The session pooler keeps one server connection per client connection, so session settings survive for the duration of a checkout; transaction pooling would not keep them.

## Options

| | Shared tables, app scoping only | Shared tables, app scoping plus RLS | Schema per tenant | Database per tenant |
|---|---|---|---|---|
| A forgotten scope leaks data | yes | no, Postgres returns no rows | no | no |
| Migrations | one run | one run | one run per tenant | one run per tenant |
| Cross-tenant reporting for operators | easy | explicit role | hard | hard |
| Fits one free Postgres | yes | yes | yes, until catalog bloat | no |
| Operational complexity | lowest | one setting per request, one extra role | high | highest |

## Decision

Shared tables with a mandatory `organization_id`, enforced twice:

1. Application: every tenant model includes `TenantScoped`, which adds `belongs_to :organization` and a default scope on `Current.organization`. With no current organization the scope raises instead of returning everything (fail closed). Controllers never read `organization_id` from parameters. A record of another organization is answered with 404.
2. Database: every tenant table has `ENABLE` and `FORCE ROW LEVEL SECURITY` and one policy:
   `USING (organization_id = current_setting('app.organization_id', true)::bigint)` with the same `WITH CHECK`. When the setting is missing, `current_setting` returns null and the policy matches nothing.

How the setting is applied:
- The API base controller sets `app.organization_id` with `set_config(..., false)` on the checked-out connection after authentication, and resets it in an `ensure`. A connection pool `checkin` callback also resets it, so a connection never returns to the pool carrying a tenant.
- Jobs set it from their arguments in an `around_perform`, the same way.
- Queries that legitimately cross tenants (sign-in, finding a user's memberships, the nightly demo reset, Solid Queue and Solid Cache tables) run on tables without tenant policies or through a dedicated method that is named and reviewed.

Roles:
- Production uses two roles created by hand in Supabase (SQL in `docs/deploy.md`), neither with `BYPASSRLS`: `alicerce_owner` runs migrations and owns the tables; `alicerce_app` serves requests with row privileges only, so it can neither alter a policy nor disable RLS. `FORCE ROW LEVEL SECURITY` also subjects the owner to the policies, in case a maintenance task ever runs with it.
- Development and CI connect as a superuser, which bypasses RLS. RLS is therefore tested explicitly: the RLS specs switch to a non-superuser probe role with `SET LOCAL ROLE`, insert rows for two organizations and prove, with raw SQL that skips every Rails scope, that the other organization's rows are invisible and cannot be inserted or updated.

Schema format: policies, triggers and functions do not fit `schema.rb`, so the schema is dumped to `db/structure.sql` from the first policy on.

Every endpoint is covered by a route inventory spec: a route under `/api/v1` without an isolation entry fails the suite (see the testing strategy in `CONTRIBUTING.md`).

## Consequences

- A missing scope in application code becomes an empty result instead of a leak, and the isolation specs catch it as a failing test.
- Every request pays one `set_config` call per checkout, which is negligible.
- Transaction pooling (Supabase port 6543) cannot be used; the session pooler is required. This is documented in `docs/deploy.md`.
- Superuser connections in development hide RLS; the probe role specs are what prove the policies work, and they run in CI.
- Operators' cross-tenant tools, if ever needed, require a separate role and an ADR.

## What would make me change my mind

- Measured overhead of RLS policies above 10 percent on the heaviest report query, after indexes that start with `organization_id`: keep application scoping and move RLS to write paths only.
- A tenant needing data residency or a custom schema: database per tenant for that customer.
- The hosting moving to a pooler in transaction mode: switch to `SET LOCAL` inside a per-request transaction.

# ADR 0008: Pundit policies with fixed roles, denied by default and verified on every action

- Status: accepted
- Date: 2026-09-19

## Context

Each organization has people with different jobs: the owner, an administrator, purchasing, sales, finance, and read-only accountants. An ERP leaks through authorization gaps as often as through tenant gaps: a salesperson approving their own discount, a read-only user settling a title. Authorization must be explicit per action, testable as a matrix, and impossible to forget on a new endpoint. Tenant isolation is a separate layer (ADR 0003); policies assume they only ever see records of the current organization.

## Options

| | Checks in controllers | Pundit | Action Policy | Permission tables editable per organization |
|---|---|---|---|---|
| Forgetting a check is caught | no | `verify_authorized` and `verify_policy_scoped` fail the request | same, plus pre-checks | depends |
| Familiarity for reviewers | high | high | lower | n/a |
| Test as a matrix | awkward | policy specs per action | same | needs data setup |
| Scope of the MVP | n/a | fits fixed roles | fits, more features than needed | more than needed |

## Decision

- Pundit, one policy per model in `app/policies/<context>/`, inheriting `ApplicationPolicy`, where every rule returns false unless overridden.
- The API base controller calls `after_action :verify_authorized` on every action and `verify_policy_scoped` on index actions. Skipping either requires a line in the pull request explaining why (only the session and health endpoints do).
- Roles are fixed per membership: `owner`, `admin`, `purchasing`, `sales`, `finance`, `read_only`. A role is a column on the membership, not a table. Policies ask capabilities (`can_approve_sales?`) defined in one module that maps roles to capabilities, so the matrix lives in one file.
- Denials for records the user can see answer 403 `forbidden`; records outside the tenant never reach a policy and answer 404.
- The SPA hides actions the API reports as not allowed (each resource response includes an `allowed_actions` list computed from the policy), but the API is the only enforcement.

Initial matrix (M1):

| Capability | owner | admin | purchasing | sales | finance | read_only |
|---|---|---|---|---|---|---|
| Manage members and roles | yes | yes | | | | |
| Master data (partners, products, warehouses) | yes | yes | yes | read | read | read |
| Purchase orders and receipts | yes | yes | yes | | read | read |
| Sales orders, approval, invoicing | yes | yes | | yes | read | read |
| Invoice cancellation | yes | yes | | | yes | |
| Stock adjustments, counts, negative allowance | yes | yes | yes | | | read |
| Titles and settlements | yes | yes | | | yes | read |
| Audit trail | yes | yes | | | | |

## Consequences

- A new endpoint without `authorize` fails its first request spec.
- The authorization matrix spec generates one example per endpoint and role from this table, so changing the table changes the tests.
- Organizations cannot customize roles in the MVP.

## What would make me change my mind

- Customers asking for custom roles: capabilities become rows per organization, still behind the same capability methods, in a new ADR.
- Field-level rules (hiding cost from sales): serializer-level checks through the same capabilities.

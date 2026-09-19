# ADR 0008: Pundit policies with fixed roles, denied by default and verified on every action

- Status: accepted
- Date: 2026-09-19

## Context

Each organization has people with different jobs: the owner, an administrator, purchasing, sales, finance and read-only accountants. An ERP leaks through authorization gaps as often as through tenant gaps: a read-only accountant settling a title, a salesperson cancelling an invoice that finance already reconciled. Authorization must be explicit per action, testable as a matrix, and impossible to forget on a new endpoint. Tenant isolation is a separate layer (ADR 0003); policies only ever see records of the current organization.

The public demo adds a constraint: visitors must see the full loop, which needs broad permissions, yet must not invite people, send email or change authentication settings.

## Options

| | Checks in controllers | Pundit | Action Policy | Permission tables per organization |
|---|---|---|---|---|
| Forgetting a check is caught | no | `verify_authorized` and `verify_policy_scoped` fail the request | same | depends |
| Familiarity for reviewers | high | high | lower | n/a |
| Test as a matrix | awkward | policy specs per action | same | needs data setup |
| Fits fixed roles in the MVP | n/a | yes | yes, more than needed | more than needed |

## Decision

- Pundit, one policy per model in `app/policies/<context>/`, inheriting `ApplicationPolicy`, where every rule returns false unless overridden.
- The API base controller runs `verify_authorized` after every action and `verify_policy_scoped` after index actions. Only the session and health endpoints skip them, and say why in code.
- Roles are fixed per membership: `owner`, `admin`, `purchasing`, `sales`, `finance`, `read_only`, a column on the membership. Policies ask capabilities (`can_approve_sales?`) defined in one module that maps roles to capabilities, so the matrix lives in one file and generates the matrix spec.
- Demo users are ordinary memberships with a `demo` flag on the user. The capability module denies `manage_members`, `send_email` and `manage_authentication` to demo users regardless of role.
- A denied action on a record the user can see answers 403 `forbidden`; records outside the tenant never reach a policy and answer 404 (ADR 0003).
- Detail responses include `allowed_actions`, computed from the policy, so the SPA can show only what the API would accept; list responses do not. The API remains the only enforcement.

Initial matrix (Milestone 1):

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
- Changing the matrix changes the tests, because the spec is generated from it.
- Organizations cannot customize roles in the MVP.

## What would make me change my mind

- Customers asking for custom roles: capabilities become rows per organization, still behind the same capability methods, in a new ADR.
- Field-level rules (hiding cost from sales): serializer checks through the same capabilities.

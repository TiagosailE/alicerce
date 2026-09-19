# Architecture decision records

Decisions that are hard to reverse, cross modules or change the security posture. A decision is never edited; a new record supersedes it. Factual corrections are recorded as dated amendments at the end of the record.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-stack.md) | Rails 8.1 API with a React + TypeScript SPA on the same origin | accepted, amended |
| [0002](0002-free-hosting.md) | Render free web service with a Supabase free Postgres | accepted, amended |
| [0003](0003-tenant-isolation.md) | Tenant isolation by `organization_id`, enforced by the app and by Postgres row level security | accepted |
| [0004](0004-stock-locking.md) | Pessimistic row locks on stock balances, taken in a fixed order | accepted |
| [0005](0005-idempotency-keys.md) | Idempotency keys stored in the same transaction as the effect | accepted |
| [0006](0006-money-and-quantities.md) | Money as integer cents with a currency, quantities as fixed-point decimals | accepted |
| [0007](0007-authentication-and-sessions.md) | Password authentication with database sessions in an HttpOnly cookie | accepted |
| [0008](0008-authorization.md) | Pundit policies with fixed roles, denied by default and verified on every action | accepted |
| [0009](0009-state-machines.md) | Explicit transition tables on the model, checked by the domain and the database | accepted |
| [0010](0010-audit-trail.md) | Append-only audit trail written by commands, protected by a trigger | accepted |

Related: [architecture](../architecture.md), [threat model](../threat-model.md), [security checklist](../security.md), [scope](../scope.md), [deploy](../deploy.md).

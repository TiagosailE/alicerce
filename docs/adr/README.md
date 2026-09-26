# Architecture decision records

Decisions that are hard to reverse, cross modules or change the security posture. A decision is never edited; a new record supersedes it. Factual corrections are recorded as dated amendments at the end of the record.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-stack.md) | Rails 8.1 API with a React + TypeScript SPA on the same origin | accepted, amended |
| [0002](0002-free-hosting.md) | Render free web service with a Supabase free Postgres | accepted, amended |
| [0003](0003-tenant-isolation.md) | Tenant isolation by `organization_id`, enforced by the app and by Postgres row level security | accepted |
| [0004](0004-stock-locking.md) | Pessimistic row locks in one global order | accepted |
| [0005](0005-idempotency-keys.md) | Idempotency keys stored with the successful effect only | accepted |
| [0006](0006-money-and-quantities.md) | Money as integer cents with a currency, cost kept as value, every rounding named | accepted |
| [0007](0007-authentication-and-sessions.md) | Password authentication with database sessions in a `__Host-` cookie | accepted |
| [0008](0008-authorization.md) | Pundit policies with fixed roles, denied by default and verified on every action | accepted |
| [0009](0009-state-machines.md) | Explicit transition tables on the model, enforced by the domain | accepted |
| [0010](0010-audit-trail.md) | Append-only audit trail written by commands, purged only through owner functions | accepted |
| [0011](0011-openapi-schema-first.md) | Schema-first OpenAPI, validated in request specs, typed client generated for the SPA | accepted |
| [0012](0012-personal-data-encryption.md) | Active Record Encryption for document numbers, keys from the environment | accepted |
| [0013](0013-sales-quotes-as-separate-document.md) | Sales quotes (orcamentos) are a separate document, not the sales order's draft state | accepted |
| [0014](0014-partner-personal-data-visibility.md) | Partner personal data is masked in lists and hidden from the read_only role | accepted |
| [0015](0015-concurrent-edits-and-master-data-that-documents-reference.md) | Master data edits are checked against a revision, and documents will not depend on live master data | accepted |

Related: [architecture](../architecture.md), [threat model](../threat-model.md), [security checklist](../security.md), [scope](../scope.md), [deploy](../deploy.md).

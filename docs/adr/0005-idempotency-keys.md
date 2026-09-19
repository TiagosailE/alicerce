# ADR 0005: Idempotency keys stored with the successful effect only

- Status: accepted
- Date: 2026-09-19

## Context

Invoicing, receiving, settling, adjustments and approvals must not happen twice when a user double-clicks, a request times out and is retried, or a connection drops after the server committed. Double submission is the most common way a small ERP ends up with two invoices for one load. Two traps shape the design. An earlier project recorded webhook events before processing them, so a failure after the record made every retry look like a duplicate. And a stored failure is worse than none: a user whose approval failed for lack of stock must be able to approve again once the stock arrives.

## Options

| | Unique constraint on a natural key | Key table, separate transaction | Key table, same transaction, successes only |
|---|---|---|---|
| Covers every critical write | no | yes | yes |
| Crash after saving the key | n/a | effect lost, retries blocked | both roll back |
| A failed attempt can be retried | n/a | only if failures are not stored | yes |
| Replays return the original result | no | yes | yes, re-rendered |

## Decision

Table `idempotency_keys`: `organization_id`, `user_id`, `key` (UUID from the client), `request_digest` (SHA-256 of method, path and canonical body), `response_status`, `resource_type`, `resource_id`, `created_at`; unique on `(organization_id, user_id, key)`, under tenant RLS.

`Idempotency.run(key:)` inside the command transaction, right after the lock timeout (ADR 0004):
1. `INSERT ... ON CONFLICT DO NOTHING RETURNING id`. A concurrent request with the same key waits on the unique index until the first one commits or rolls back.
2. If a row came back, run the effect. On success, store the status and the created or changed resource on the row and commit together with the effect. On any failure (validation, `insufficient_stock`, a lock timeout) the transaction rolls back, so the key disappears with the attempt and a later retry runs again.
3. If no row came back, read the existing row. Same digest: replay the stored status and re-render the stored resource in its current state. Different digest: 422 `idempotency_key_reused`.

Response bodies are never stored, so the table holds no personal data. Keys expire after 24 hours; a recurring job deletes older rows organization by organization. The header is `Idempotency-Key` and critical endpoints answer 400 without it.

The SPA creates a key when a form opens, keeps it across retries after a network error, a 5xx or a 409, and creates a new one after any other response.

## Consequences

- A retried request never produces a second invoice, receipt or settlement, and gets the original status and resource.
- Replays show the resource as it is now, which is what the user needs after a reload.
- Keys are per user, so one user cannot replay another's request, and per path, so a key reused on another document is rejected.
- Future bank or fiscal integrations reuse the mechanism with their own keys.

## What would make me change my mind

- Integrations that cannot keep a key across retries: derive the key from a natural identifier they send.

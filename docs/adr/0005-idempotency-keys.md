# ADR 0005: Idempotency keys stored in the same transaction as the effect

- Status: accepted
- Date: 2026-09-19

## Context

Invoicing, receiving, settling, adjustments and approvals must not happen twice when a user double-clicks, a request times out and is retried, or a mobile connection drops after the server committed. Double submission is the most common way a small ERP ends up with two invoices for one load. An earlier project recorded webhook events before processing them, so a failure after the record made every retry look like a duplicate and the effect never happened.

## Options

| | Unique constraint on a natural key | Idempotency key table, separate transaction | Idempotency key table, same transaction as the effect |
|---|---|---|---|
| Covers all critical writes | no, not every write has a natural key | yes | yes |
| Failure after the key is saved | n/a | key saved, effect lost, retries blocked | both roll back together |
| Replays return the original response | no | yes | yes |

## Decision

A table `idempotency_keys` with `organization_id`, `key` (UUID from the client), `scope` (the command name), `request_digest` (SHA-256 of the canonical request body), `response_status`, `response_body` and `created_at`, unique on `(organization_id, key)`.

`Idempotency.run(key:, scope:)` inside a command:
1. `INSERT` the key with a null response. If the insert hits the unique constraint, read the existing row:
   - same scope and digest with a stored response: return the stored response, no effect;
   - same key with a different scope or digest: fail with 422 `idempotency_key_reused`;
   - no stored response yet (a concurrent request holds it): wait on the row lock, then apply the first two rules.
2. Run the effect in the same transaction.
3. Store the final response on the row before commit. Expected failures (`insufficient_stock`, `invalid_transition`) are final and stored; `conflict_retry` from a lock timeout is not stored, so the retry runs again.

Keys expire after 24 hours; a recurring job deletes older rows. The header is `Idempotency-Key`; critical endpoints answer 400 when it is missing. The SPA creates the key when a form opens and keeps it until a success.

## Consequences

- A retried request never produces a second invoice, receipt or settlement, and gets the same response as the first.
- A crash in the middle rolls back the key with the effect, so the retry works.
- Stored responses hold response bodies for a day; they contain no data the caller could not already read.
- Future bank or fiscal integrations reuse the same mechanism with their own keys.

## What would make me change my mind

- Response bodies large enough to matter in storage: store a reference to the created record instead of the body.
- Clients that cannot keep a key across retries (third-party integrations): derive the key from a natural identifier they send.

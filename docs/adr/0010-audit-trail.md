# ADR 0010: Append-only audit trail written by commands, protected by a trigger

- Status: accepted
- Date: 2026-09-19

## Context

Every relevant change must be traceable: who did it, in which organization, what changed from what to what, when and from where. The trail must not be editable by the application, including by a bug or an injection. It also meets LGPD: personal data in the trail would survive a data subject's deletion request, and documents like CPF are encrypted at rest.

## Options

| | paper_trail or audited (model callbacks) | Database triggers writing the trail | Commands write explicit events |
|---|---|---|---|
| Knows the actor, request id and IP | through globals | through session settings | directly |
| Knows the business action (approved, invoiced) | no, only row diffs | no | yes |
| Captures changes made outside commands | yes | yes | no |
| Personal data control | per model config | hard | explicit per field |

## Decision

- A table `audit_events` (`organization_id`, `actor_user_id`, `action`, `subject_type`, `subject_id`, `changes` jsonb, `request_id`, `ip`, `created_at`). Commands call `Audit.record(action, subject, actor:, changes:)` in their transaction, so the event commits or rolls back with the change.
- `changes` holds before and after values for ordinary fields. Fields marked as personal data (names of people, CPF, email, phone, address) are recorded as `"changed"` with no values.
- A trigger rejects every `UPDATE` and `DELETE` on `audit_events`; the application role has only `INSERT` and `SELECT` on it. Retention cleanup, when it exists, runs as a separate maintenance role.
- Changes that bypass commands are not allowed by `CONTRIBUTING.md`; the database guards (checks, RLS) protect data integrity, and the trail records business actions.

## Consequences

- The trail reads as a business history ("approved PV-000184", "cancelled FT-000093") rather than column diffs.
- Anonymizing a data subject leaves the trail intact and free of their personal data.
- A change made through the console bypasses the trail; console access in production is limited to the maintainer and is itself an operational risk recorded in `docs/security.md`.

## What would make me change my mind

- A compliance requirement to capture every row change regardless of path: add triggers that write a technical change log next to the business trail.

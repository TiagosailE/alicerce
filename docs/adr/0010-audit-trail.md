# ADR 0010: Append-only audit trail written by commands, purged only through owner functions

- Status: accepted
- Date: 2026-09-19

## Context

Every relevant change must be traceable: who did it, in which organization, what changed, when and from where. The trail must not be editable by the application, including by a bug or an injection. It also has to respect LGPD: a data subject's personal data cannot survive their anonymization request inside the trail, and records have a retention period. The public demo resets its data every night, which the trail must follow, or yesterday's "approved PV-000184" would point at today's different order.

## Options

| | paper_trail or audited (model callbacks) | Database triggers writing the trail | Commands write explicit events |
|---|---|---|---|
| Knows the actor, request id and IP | through globals | through session settings | directly |
| Knows the business action (approved, invoiced) | no, only row diffs | no | yes |
| Captures changes made outside commands | yes | yes | no |
| Personal data control | per model config | hard | explicit per field |

## Decision

- Table `audit_events` (`organization_id`, `actor_user_id`, `action`, `subject_type`, `subject_id`, `changes` jsonb, `request_id`, `ip_prefix`, `created_at`) under tenant RLS. Commands call `Audit.record(action, subject, actor:, changes:)` in their transaction, so the event commits or rolls back with the change.
- `changes` holds before and after values for ordinary fields. Fields marked as personal data (names of people, CPF, email, phone, address) and free-text fields are recorded as `"changed"` without values. `ip_prefix` keeps the /24 of IPv4 or /48 of IPv6, not the full address.
- The migration that creates the table revokes `UPDATE` and `DELETE` from `alicerce_app`, and a trigger rejects both for every role except `alicerce_owner`.
- Deletion happens only through two `SECURITY DEFINER` functions owned by `alicerce_owner`, which the app role may execute:
  - `audit_purge(organization_id, before)`: the nightly demo reset purges the demo organizations' events, and the retention job purges events older than five years for all organizations.
  - `audit_redact(organization_id, subject_type, subject_id)`: part of a data subject's anonymization; it replaces any remaining values tied to that subject.
- Failed sign-ins have no organization, so they are structured log events, not audit events (ADR 0007).

## Consequences

- The trail reads as business history ("approved PV-000184", "cancelled FT-000093") rather than column diffs.
- The application cannot alter or delete events except through the two named functions, whose use is itself logged.
- A change made through the console bypasses the trail; console access in production is limited to the maintainer, recorded as an accepted risk in `docs/security.md`.

## What would make me change my mind

- A compliance requirement to capture every row change regardless of path: add triggers that write a technical change log next to the business trail.

# ADR 0014: Partner personal data is masked in lists and hidden from the read_only role

- Status: accepted
- Date: 2026-09-26

## Context

ADR 0012 encrypts a partner's CPF or CNPJ at rest. Encryption at rest does
nothing against a caller the application already trusts: until now every role
that can read master data (all six, ADR 0008) received the full CPF, e-mail
and phone of every partner, up to 100 partners per request. One compromised or
merely curious `read_only` account could page through every customer's CPF,
and the security checklist called minimization "in place". An adversarial
review of slice 2 found the gap.

Constraints: a sale, a receipt or a financial title needs the counterparty's
document, so sales and finance genuinely work with it; a CNPJ is public
registry data while a CPF identifies a person (LGPD); the list screens only
need enough to recognize a partner.

## Options

Criteria, in order: least personal data per request, does not break the
flows that need the document, cost to build and test.

| Option | Least data | Keeps flows working | Cost |
|---|---|---|---|
| A. Status quo, full data everywhere | worst | yes | none |
| B. Lists masked for all; detail full for every role except read_only | good | yes | small |
| C. Lists masked; detail full only for owner, admin, purchasing | best | sales and finance lose the document they need | small |
| D. B plus an audit event per reveal | best | yes | a write inside every GET, noisy |

## Decision

Option B.

- The list response is its own shape (`PartnerSummary`): the CPF is masked to
  its middle six digits (`***982247**`), a CNPJ stays in full, and e-mail and
  phone are not part of it.
- The detail response (`GET`, `POST`, `PATCH`) carries the full record when
  `Identity::Capabilities.view_partner_personal_data?` holds (every role but
  `read_only`). Otherwise the CPF is masked, e-mail and phone are null, and
  `personal_data_visible` is false so the SPA can say "restricted" instead of
  "not informed".
- The rule lives in one capability and one policy method, not in the
  serializers or the SPA.

## Consequences

- A table can no longer show a full CPF; whoever needs it opens the partner.
  A future document search or export needs its own explicit parameter and
  authorization, not a wider list.
- Revealing a partner is not audited (option D rejected for now): an owner,
  admin, purchasing, sales or finance account that is compromised can still
  read partners one at a time. Rate limiting on reads and an access log are the
  next steps if that risk needs closing.
- The weakest assumption is that sales and finance need the full document. If
  they only ever need it inside a document they issue, they should get it there
  and option C becomes right.

## What would make me change my mind

- A regulator or a customer asks who viewed a person's data: add option D.
- Sales staff report they never use the CPF outside an issued document: move
  to option C.
- A search by document becomes a requirement: design it as its own endpoint.

# ADR 0012: Active Record Encryption for document numbers, keys from the environment

- Status: accepted
- Date: 2026-09-21

## Context

Slice 2 adds `Catalog::Partner` (customers and suppliers), carrying a CPF or
CNPJ. `docs/scope.md` and `CONTRIBUTING.md` already commit to encrypting
document numbers at rest; this ADR picks how.

Two constraints shape the options:

- `config/credentials` is not used in this project: every earlier secret
  (`SECRET_KEY_BASE`, `BREVO_API_KEY`) comes from the environment, never
  from `config/credentials.yml.enc`. Rails' usual path for Active Record
  Encryption keys is exactly that credentials file (`bin/rails
  db:encryption:init` writes into it), so the default path is closed.
- The CNPJ format itself changed under this project: Receita Federal's
  Instrucao Normativa RFB 2.229/2024 makes the first 12 characters of a
  CNPJ alphanumeric (0-9, A-Z) from July 2026, with the two check digits
  staying numeric, computed by the same modulo 11 algorithm applied to each
  character's ASCII value minus 48. `docs/scope.md` already commits to
  accepting this format; today (2026-09-21) it is already in effect.

The value that gets encrypted also needs an equality lookup: a partner's
document number must be unique per organization, and a future receipt or
invoice screen will look a partner up by document number, not only by id.

## Options

| | Active Record Encryption, deterministic, keys from ENV | Active Record Encryption, keys from `config/credentials` | Hand-rolled encryption concern | Postgres `pgcrypto` column encryption |
|---|---|---|---|---|
| Fits "no credentials file" | yes | no | yes | yes |
| Equality lookup (uniqueness, find by document) | yes, deterministic mode | yes | only if built to support it | yes, if the same key encrypts every row the same way |
| Audited, maintained by Rails core | yes | yes | no, new surface to get wrong | no, key handling is entirely ours |
| Query integration (`where(document_number: ...)` works transparently) | yes | yes | no, needs a custom type | no, needs raw SQL with `pgp_sym_decrypt` |
| Keys reachable from a database-only compromise | no, keys live in app config or the environment, not the database | no | depends | yes, if keys are ever passed through the same connection |

## Decision

- `encrypts :document_number, deterministic: true` on `Catalog::Partner`
  (Rails 8.1's Active Record Encryption). Deterministic, not the default
  randomized mode, because the uniqueness validation and a future
  find-by-document lookup both need equality to work at the database level;
  `docs/scope.md` already calls this out as the expected mode.
- The three keys Active Record Encryption needs (`primary_key`,
  `deterministic_key`, `key_derivation_salt`) come from
  `AR_ENCRYPTION_PRIMARY_KEY`, `AR_ENCRYPTION_DETERMINISTIC_KEY` and
  `AR_ENCRYPTION_KEY_DERIVATION_SALT` in
  `config/initializers/active_record_encryption.rb`, the same way
  `SECRET_KEY_BASE` and `BREVO_API_KEY` already do. Development and test
  use fixed, non-secret values instead (`Rails.env.local?`), so a fresh
  clone works with no extra setup, the same exemption `SECRET_KEY_BASE`
  already gets from Rails itself outside production.
- `document_number` is normalized before validation and encryption:
  stripped of punctuation, upper-cased. Equality lookups and the unique
  index depend on every row reaching the database in the same canonical
  form; letters only ever appear in the alphanumeric CNPJ, which Receita
  Federal's own published examples write upper-case.
- Format and checksum validation live in the domain, not in the database:
  `Catalog::DocumentNumber.valid?(type, value)` implements the CPF check
  digit algorithm and the CNPJ one (numeric and alphanumeric, same modulo
  11 formula, ASCII-48 values per character). `DocumentNumberGenerator`
  (`lib/`) produces valid fictitious numbers of both kinds for seeds and
  specs, since `docs/scope.md` requires every seed and test document to be
  generated, never a real one.
- `Catalog::Partner::PERSONAL_DATA_FIELDS` (`name`, `document_number`,
  `email`, `phone`) names the fields `Catalog::CreatePartner` and
  `Catalog::UpdatePartner` must record in the audit trail as changed
  without values (ADR 0010): a partner's own name is personal data exactly
  like a user's, not only the document number.

## Consequences

- Positive: no secret ever needs `config/credentials`; the pattern matches
  every other secret in this codebase, so there is one story for "where do
  secrets come from," not two. Deterministic encryption keeps the
  uniqueness constraint and future lookups working at the database level
  with an ordinary index, no application-side scan.
- Positive: the CNPJ validator accepts both the legacy numeric format and
  the alphanumeric one already in effect, verified against Receita
  Federal's own published worked example (`12.ABC.345/01DE-35`).
- Negative: rotating `AR_ENCRYPTION_PRIMARY_KEY` or
  `AR_ENCRYPTION_DETERMINISTIC_KEY` in production requires re-encrypting
  every row that used them; Rails supports key rotation
  (`ActiveRecord::Encryption::Properties`) but nothing here builds or
  exercises that path yet, since Milestone 1 only ever generates one set of
  keys. Documented as a gap, not solved.
- Negative: a compromised production environment (the same blast radius
  `docs/security.md`'s Secrets section already lists for every other ENV
  secret) can decrypt every document number; deterministic encryption also
  means two partners sharing a document number produce identical
  ciphertext, an accepted tradeoff `docs/scope.md` already implies by
  naming deterministic encryption directly.

## What would make me change my mind

- A field needing encryption where equality-leakage through identical
  ciphertext is unacceptable: use Active Record Encryption's default
  non-deterministic mode for that field alone, not a new mechanism.
- A compliance requirement for managed key storage (a KMS, envelope
  encryption): Active Record Encryption supports a custom key provider;
  the three ENV keys here would move behind that provider rather than
  forcing a switch away from Active Record Encryption itself.

# Security

Target: OWASP ASVS 4.0.3 level 2 on authentication, session management, access control and the invoicing and stock flows. This file is the checklist; each line points to the evidence. Threats and their reasoning are in [threat-model.md](threat-model.md).

Status: **in place** (code and a test or CI step exist), **designed** (decided in an ADR, lands in the named slice), **accepted** (a known risk, with the reason below).

## Tenant isolation

| Control | Status | Evidence |
|---|---|---|
| `organization_id` on every tenant table, scope fails closed without a current organization | in place | ADR 0003, `TenantScoped`, `Audit::Event` (the first table to use it) |
| Postgres RLS on business tables, audit, idempotency keys and invitations, policies on `app.organization_id` (null when unset or reset), app role without `BYPASSRLS` | in place for `audit_events`, `identity_invitations` the slice 2 tables (`catalog_units`, `catalog_categories`, `catalog_products`, `catalog_unit_conversions`, `inventory_warehouses`, `catalog_partners`) and the slice 3 tables (`inventory_balances`, `inventory_movements`, `idempotency_keys`), designed for the rest | ADR 0003, `docs/deploy.md`, `db/migrate/20260919110000_create_audit_events.rb`, `db/migrate/20260919120000_create_identity_invitations.rb`, `db/migrate/20260920100000_create_catalog_units.rb` |
| The whole test suite connects as the app role with production grants, so every spec runs under RLS; raw SQL specs prove other organizations are invisible | in place | ADR 0003, `spec/rails_helper.rb`, `spec/db/audit_events_constraints_spec.rb`, `spec/db/identity_invitations_constraints_spec.rb` |
| The tenant setting lives on a connection leased for the whole request and is reset on checkin | in place | ADR 0003, `TenantSetting`, `spec/lib/tenant_setting_spec.rb` |
| Every `/api/v1` route in an isolation spec; a route without an entry fails the suite | in place | `RouteInventory`, `spec/requests/api/v1/route_inventory_spec.rb` |
| Records of another organization answer 404, never 403 | designed, slice 1 | ADR 0003, `CONTRIBUTING.md` (API contract) |

## Authentication and sessions

| Control | Status | Evidence |
|---|---|---|
| bcrypt cost 12, 12 to 72 byte passwords | in place | ADR 0007, `Identity::User` |
| Common password check on new passwords | designed, not yet built | ADR 0007 |
| Rate limits on sign-in, reset, invitation acceptance and password change; no hard lockout | in place | ADR 0007, `Api::V1::SessionsController`, `Api::V1::Invitations::AcceptancesController`, `Api::V1::PasswordResetsController`, `Api::V1::PasswordResets::CompletionsController`, `Api::V1::PasswordsController` |
| Database sessions storing only token digests; rotation on sign-in, organization switch and role or password change; revocation | in place | ADR 0007, `Identity::Session.revoke_others_for!`, `spec/requests/api/v1/memberships_spec.rb`, `spec/requests/api/v1/passwords_spec.rb` |
| Idle (30 min) and absolute (12 h) session expiry (ASVS 3.3.2) | in place | ADR 0007, `Identity::Session`, `Api::V1::BaseController#resume_session` |
| Single-use reset token, 20 minute expiry, uniform response (identical status, body and enqueue for every request, so neither shape nor timing tells an unknown, demo or real email apart) | in place | ADR 0007, `Identity::User` (`has_secure_password reset_token:`), `Identity::RequestPasswordReset`, `Identity::PasswordResetMailerJob` |
| Single-use and invitation tokens travel only in the request body, never the URL path: Rails logs the raw request path unfiltered (`filtered_path` only redacts the query string), so a token there would leak into every log line for that request | in place | `config/routes.rb` (`POST /password_resets/completion`, `POST /invitations/acceptance`) |
| Timing-safe comparison of tokens and codes | designed, slice 1 | ADR 0007 |
| Optional TOTP with recovery codes | designed, slice 7 | ADR 0007 |

## Authorization

| Control | Status | Evidence |
|---|---|---|
| Pundit policies, every rule false unless allowed | in place | ADR 0008, `ApplicationPolicy`, `Audit::EventPolicy`, `Identity::InvitationPolicy`, `Identity::MembershipPolicy` |
| `verify_authorized` and `verify_policy_scoped` on every API action | in place | ADR 0008, `Api::V1::BaseController`, `spec/requests/api/v1/authorization_enforcement_spec.rb` |
| Role matrix spec generated per endpoint and role | in place | ADR 0008, `spec/requests/api/v1/audit_events_spec.rb` (one example per role), `spec/requests/api/v1/route_inventory_spec.rb` |

## Input and output

| Control | Status | Evidence |
|---|---|---|
| Validation in the domain and database constraints, not only in the UI | designed, each slice | `docs/scope.md`, ADRs 0004, 0006, 0009 |
| Mass assignment: `params.expect` with explicit lists, no status or tenant from clients | designed, each slice | `CONTRIBUTING.md` |
| No SQL built by interpolation | in place (checked) | Brakeman in `bin/ci` with `--exit-on-warn` |
| Output escaping: React by default, raw HTML banned | in place | `frontend/eslint.config.js` (`dangerouslySetInnerHTML` rule) |
| CSRF on state-changing requests | in place | ADR 0007, `Api::V1::BaseController#verify_csrf_token!`, `spec/requests/api/v1/session_spec.rb` |
| Outbound HTTP only to allowlisted hosts with timeouts (anti-SSRF); no user-supplied URLs are fetched | in place | ADR 0002, `BrevoClient` (a fixed host constant, never built from input), `Identity::PasswordResetMailerJob` |
| Uploads (supplier invoice PDF on receipts): type by magic bytes, 5 MB cap, generated names, stored in Postgres, served with `Content-Disposition: attachment` | designed, slice 4 | `docs/scope.md` |

## Transport and headers

| Control | Status | Evidence |
|---|---|---|
| HTTPS only: TLS ends at the platform edge, which redirects HTTP; Rails assumes SSL and sends HSTS | in place | `config/environments/production.rb`, `script/check_production_headers.rb` (run by `bin/ci` with production settings) |
| CSP `default-src 'none'`, scripts, styles, fonts, connections from self only, no `unsafe-inline`, `frame-ancestors 'none'` | in place | `config/initializers/content_security_policy.rb`, `spec/requests/spa_spec.rb`, `script/check_production_headers.rb` |
| The built app runs under that CSP with no violations, checked in a real browser against the production image | in place | `frontend/e2e/shell.spec.ts` (with a control test that proves violations are detected), image job in `.github/workflows/ci.yml` |
| The shell is never served as a static file | in place | `frontend/vite.config.ts` builds it into `frontend/dist`; `spec/requests/spa_spec.rb`; shell location step in `config/ci.rb` |
| `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` | in place | `config/application.rb`, `spec/requests/spa_spec.rb`, `script/check_production_headers.rb` |
| Session cookie `__Host-`, `Secure`, `HttpOnly`, `SameSite=Lax` | in place | ADR 0007, `Api::V1::BaseController`, verified against a real production-mode boot |
| Host allow list; production refuses to boot without a host | in place | `config/environments/production.rb`, `script/check_production_headers.rb` (unknown host answers 403) |

## Secrets

| Control | Status | Evidence |
|---|---|---|
| No secret in the repository; no encrypted credentials file | in place | `.gitignore`, `.dockerignore` |
| Every variable documented with placeholders | in place | `.env.example` |
| gitleaks over full history on every pull request; GitHub push protection | in place | `.github/workflows/ci.yml`, repository settings |
| The workflow token is not left in `.git/config` for later steps | in place | `persist-credentials: false` on every checkout |
| Rotation procedure | in place | `docs/deploy.md` (Rotating secrets) |
| Separate database roles: owner for migrations, app for requests, neither bypassing RLS | designed, first deploy | `docs/deploy.md`, `bin/docker-entrypoint` (`MIGRATION_DATABASE_URL`) |
| TLS to the database verified against the provider CA (`sslmode=verify-full`) | designed, first deploy | `docs/deploy.md` |

## Dependencies and supply chain

| Control | Status | Evidence |
|---|---|---|
| Locked versions (`Gemfile.lock`, `package-lock.json` with exact versions, pinned Ruby and Node) | in place | `.ruby-version`, `.node-version`, `frontend/.npmrc` |
| Base images pinned by digest | in place | `Dockerfile`, `compose.yaml`, CI Postgres service |
| No package install scripts run (`ignore-scripts`) | in place | `frontend/.npmrc` |
| bundler-audit (updated database) and npm audit fail the build, and run daily on `main` | in place | `config/ci.rb`, `.github/workflows/audit.yml` |
| Image scanned for fixable high and critical vulnerabilities | in place | Trivy in the image job; the one exception is explained in `.trivyignore` and guarded by a loaded-version check |
| Dependency review on pull requests; Dependabot with a 7 day cooldown, grouped minor and patch, security updates on | in place | `.github/workflows/ci.yml`, `.github/dependabot.yml`, repository settings |
| CodeQL for Ruby, TypeScript and workflows | in place | `.github/workflows/codeql.yml` |
| Actions pinned to SHAs (required by the repository), minimal permissions | in place | `.github/workflows/*.yml`, repository Actions settings |

## Observability

| Control | Status | Evidence |
|---|---|---|
| Structured JSON logs tagged with the request, user and organization ids, personal data filtered | in place | `StructuredLogFormatter`, `config/environments/production.rb`, `config/initializers/filter_parameter_logging.rb` (`config.filter_parameters` covers the request-parameter log line at `:info`; `config.active_record.filter_attributes` covers `#inspect`/`#to_json` of a record; the SQL query log itself is a separate case, see Accepted risks below) |
| Append-only audit trail protected by a trigger | in place | ADR 0010, `db/migrate/20260919110000_create_audit_events.rb`, `spec/db/audit_events_constraints_spec.rb` |
| Append-only stock movement ledger: no UPDATE or DELETE for the app role, a trigger for every role but the owner, read-only at the model | in place | ADR 0016, `db/migrate/20260926120200_create_inventory_movements.rb`, `spec/db/inventory_constraints_spec.rb` |
| Idempotent critical writes (stock adjustments so far): key inserted first in the command transaction, successes only, digest of method, path and body | in place for `POST /stock_adjustments`, designed for the rest | ADR 0005, ADR 0016, `Idempotency`, `spec/commands/inventory/adjust_stock_spec.rb`, `spec/concurrency/inventory/adjust_stock_spec.rb` |
| Alert on spikes of 401 and 403 responses | designed, Milestone 2 | `docs/scope.md` |

## LGPD

Personal data map: what is held, where, why and its retention.

| Data | Where | Why | Retention |
|---|---|---|---|
| CPF or CNPJ | `catalog_partners.document_number`, encrypted at rest (deterministic, ADR 0012) | Legal identification of a customer or supplier; required to issue a purchase order, a sale, a receipt or a financial title against that party | Kept while the partner record exists; export and anonymization on request lands in Milestone 2 |
| Partner name | `catalog_partners.name` | Identifies who is being bought from or sold to on every document | Same as above |
| Partner email, phone | `catalog_partners.email`, `catalog_partners.phone` | Contact for purchasing, sales and finance workflows | Same as above |
| User name, email | `identity_users.name`, `identity_users.email` | Account identification and sign-in | Kept while the account exists; a user can belong to more than one organization |
| Request IP, truncated | `audit_events.ip_prefix` (a /24 or /48, never the full address, ADR 0010) | Security investigation of an audited action | Same retention as the audit trail itself |

| Control | Status | Evidence |
|---|---|---|
| Personal data map (what, where, why, retention) | in place | the table above |
| Minimization: only data the flows need; no personal data in audit values; partner lists carry a masked CPF and no e-mail or phone, and read_only sees neither in full | in place; reveals are not audited | ADR 0010, ADR 0014, `Catalog::Partner::PERSONAL_DATA_FIELDS`, `Catalog::PartnerSummarySerializer`, `Catalog::PartnerSerializer`, `spec/requests/api/v1/partners_spec.rb` |
| CPF and CNPJ encrypted at rest (Active Record encryption, deterministic for lookups) | in place | ADR 0012, `Catalog::Partner`, `config/initializers/active_record_encryption.rb` |
| Export and anonymization on request of the data subject; retention jobs | designed, Milestone 2 | `docs/scope.md` |
| Seeds, tests and screenshots use generated people and documents only | in place | `docs/scope.md`, `DocumentNumberGenerator`, `db/seeds.rb` |

## Resilience

| Control | Status | Evidence |
|---|---|---|
| Scheduled database dump, encrypted before storage, and an executed restore test in CI | designed, Milestone 2 | ADR 0002 |
| Rollback to the previous deploy, safe because migrations never break the previous release | in place | `docs/deploy.md`, strong_migrations (`spec/db/strong_migrations_spec.rb`) |
| The production image starts and runs its jobs within the memory of the free instance | in place | image job in `.github/workflows/ci.yml` (450 MB budget, 121 MiB measured) |

## Accepted risks

| Risk | Why it is accepted | Mitigation |
|---|---|---|
| Identity tables (users, organizations, memberships, sessions) are not under tenant RLS | they are read before a tenant is known | a few named access paths, each covered by isolation specs (ADR 0003) |
| Passwords limited to 72 bytes, below the 64 characters ASVS 2.1.2 asks for when many are accented | bcrypt limit in Rails 8.1 | ASCII passphrases up to 72 characters work; migration path in ADR 0007 |
| Distributed password guessing against one account from many IPs | a per-account limit would let anyone lock the account out | per IP and per IP and email limits, password policy, optional TOTP |
| A raw SQL write could set an invalid status transition | the database restricts states, the domain restricts transitions | only commands write documents; the audit trail records every transition (ADR 0009) |
| Passwords hashed with bcrypt, not argon2id | Rails 8.1 `has_secure_password` supports bcrypt only; a custom hasher adds more risk than it removes | cost 12, 72 byte limit enforced, migration path in ADR 0007 |
| Free hosting: no managed backups, instance may restart, availability depends on a keep-alive ping | the demo must cost nothing | CI dumps and restore test; the demo tolerates restarts (ADR 0002) |
| The public demo accounts are shared by visitors | it is a demo | demo flag denies invitations, email and authentication settings; no session list or IP stored for demo users; nightly reset (ADR 0008) |
| Console access in production bypasses the audit trail | needed for maintenance | only the maintainer has access; no production console in routine operations |
| Rate limit counters live in Solid Cache and reset if it is cleared | acceptable window | limits are per minute; clearing is a manual action |
| The ActiveRecord SQL query log line for an INSERT or UPDATE (`Catalog::Partner Create ... INSERT INTO ...`) prints personal data in clear text: this Postgres adapter logs that line with every value already substituted into the printed string, so neither `filter_parameters` nor `filter_attributes` has a separate bind value left to redact by the time it is printed. Confirmed against a real request, not by reasoning about it. | that log line is written at `:debug`, and every environment outside development and test runs at `:info` or above (`config.log_level`, `RAILS_LOG_LEVEL`), so it is never emitted where it would matter; fully suppressing it would need a custom log subscriber, disproportionate to a gap production never exposes under its documented default | do not run production with `RAILS_LOG_LEVEL=debug`; `filter_attributes` still protects `#inspect`/`#to_json` of a record (an exception backtrace, a console session) |

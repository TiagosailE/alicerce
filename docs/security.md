# Security

Target: OWASP ASVS 4.0.3 level 2 on authentication, session management, access control and the invoicing and stock flows. This file is the checklist; each line points to the evidence. Threats and their reasoning are in [threat-model.md](threat-model.md).

Status: **in place** (code and a test or CI step exist), **designed** (decided in an ADR, lands in the named slice), **accepted** (a known risk, with the reason below).

## Tenant isolation

| Control | Status | Evidence |
|---|---|---|
| `organization_id` on every tenant table, scope fails closed without a current organization | in place | ADR 0003, `TenantScoped`, `Audit::Event` (the first table to use it) |
| Postgres RLS on business tables, audit, idempotency keys and invitations, policies on `app.organization_id` (null when unset or reset), app role without `BYPASSRLS` | in place for `audit_events`, designed for the rest | ADR 0003, `docs/deploy.md`, `db/migrate/20260919110000_create_audit_events.rb` |
| The whole test suite connects as the app role with production grants, so every spec runs under RLS; raw SQL specs prove other organizations are invisible | designed, slice 1 | ADR 0003 |
| The tenant setting lives on a connection leased for the whole request and is reset on checkin | in place | ADR 0003, `TenantSetting`, `spec/lib/tenant_setting_spec.rb` |
| Every `/api/v1` route in an isolation spec; a route without an entry fails the suite | in place | `RouteInventory`, `spec/requests/api/v1/route_inventory_spec.rb`; both matrices are still empty, nothing but the exempt session endpoints exists yet |
| Records of another organization answer 404, never 403 | designed, slice 1 | ADR 0003, `CONTRIBUTING.md` (API contract) |

## Authentication and sessions

| Control | Status | Evidence |
|---|---|---|
| bcrypt cost 12, 12 to 72 byte passwords, common password check | designed, slice 1 | ADR 0007 |
| Rate limits on sign-in, reset and invitation acceptance; no hard lockout | designed, slice 1 | ADR 0007 |
| Database sessions storing only token digests; rotation on sign-in, organization switch and role or password change; revocation | designed, slice 1 | ADR 0007 |
| Idle (30 min) and absolute (12 h) session expiry (ASVS 3.3.2) | in place | ADR 0007, `Identity::Session`, `Api::V1::BaseController#resume_session` |
| Single-use reset token, 20 minute expiry, uniform responses | designed, slice 1 | ADR 0007 |
| Timing-safe comparison of tokens and codes | designed, slice 1 | ADR 0007 |
| Optional TOTP with recovery codes | designed, slice 7 | ADR 0007 |

## Authorization

| Control | Status | Evidence |
|---|---|---|
| Pundit policies, every rule false unless allowed | in place | ADR 0008, `ApplicationPolicy`; no concrete policy exists yet, nothing to authorize besides the exempt session endpoints |
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
| Outbound HTTP only to allowlisted hosts with timeouts (anti-SSRF); no user-supplied URLs are fetched | designed, slice 1 (email) | ADR 0002 |
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
| Logs tagged with request id | in place | `config/environments/production.rb` (`log_tags`) |
| Structured JSON logs with user and organization ids, personal data filtered | designed, slice 1 | `config/initializers/filter_parameter_logging.rb` gains document and contact fields |
| Append-only audit trail protected by a trigger | in place | ADR 0010, `db/migrate/20260919110000_create_audit_events.rb`, `spec/db/audit_events_constraints_spec.rb` |
| Alert on spikes of 401 and 403 responses | designed, Milestone 2 | `docs/scope.md` |

## LGPD

| Control | Status | Evidence |
|---|---|---|
| Personal data map (what, where, why, retention) | designed, slice 2 | this file gains the map when partners exist |
| Minimization: only data the flows need; no personal data in audit values | designed | ADR 0010 |
| CPF and CNPJ encrypted at rest (Active Record encryption, deterministic for lookups) | designed, slice 2 | `docs/scope.md` |
| Export and anonymization on request of the data subject; retention jobs | designed, Milestone 2 | `docs/scope.md` |
| Seeds, tests and screenshots use generated people and documents only | designed, each slice | `docs/scope.md` |

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

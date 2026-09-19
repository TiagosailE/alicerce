# Threat model

STRIDE over the three flows where a failure costs the most: authentication, invoicing and stock changes. Each threat names its mitigation and where it is enforced or tested. Status: **in place** (code and test exist), **designed** (decided in an ADR, lands in the slice named), **accepted** (risk recorded in `docs/security.md`).

## Assets and trust boundaries

- Assets: each organization's commercial data (prices, costs, customers, receivables), personal data of customers and users (names, CPF, email, phone), sessions, the integrity of stock and money.
- Boundaries: browser to API (untrusted input, cookies), API to Postgres (tenant setting, roles), app to email provider, CI to production database (backups).
- Attackers considered: an anonymous visitor, a signed-in user of another organization, a signed-in user with a lower role in the same organization, a visitor sharing the public demo account.

## Authentication

| STRIDE | Threat | Mitigation | Status |
|---|---|---|---|
| Spoofing | Credential stuffing and brute force on sign-in | `rate_limit` per IP and per email, delayed responses after repeated failures, bcrypt cost 12, common password list (ADR 0007) | designed, slice 1 |
| Spoofing | Stolen session cookie | `__Host-` cookie, `Secure`, `HttpOnly`, `SameSite=Lax`, idle 8 h and absolute 7 d expiry, revocation list, rotation on sign-in and role change | designed, slice 1 |
| Spoofing | Session tokens read from a database dump | only SHA-256 digests stored | designed, slice 1 |
| Tampering | CSRF on state-changing requests | Rails forgery protection with `X-CSRF-Token`, `SameSite=Lax` as second layer | designed, slice 1 |
| Repudiation | A user denies having signed in or changed a password | audit events for sign-in, sign-out, password and role changes, with IP and request id | designed, slice 1 |
| Information disclosure | Account enumeration through sign-in or reset responses | identical responses and timing whether or not the email exists | designed, slice 1 |
| Information disclosure | Reset token reuse or interception | single use (bound to the password salt), 20 minute expiry, sent only by email | designed, slice 1 |
| Denial of service | Locking a known user out with failed attempts | no hard lockout; throttling and owner notification instead | designed, slice 1 |
| Elevation of privilege | Demo visitor changes the demo account's password or invites others | demo role cannot change authentication settings, invite or send email; nightly reset | designed, slice 1 |
| Elevation of privilege | XSS drives the API with the victim's cookie | CSP `default-src 'none'`, `script-src 'self'`, no inline code, `dangerouslySetInnerHTML` banned by lint | in place: `spec/requests/spa_spec.rb`, `frontend/eslint.config.js` |

## Invoicing

| STRIDE | Threat | Mitigation | Status |
|---|---|---|---|
| Spoofing | User of organization A invoices an order of organization B by id | tenant scope returns 404; Postgres RLS returns no rows even if a scope is missing; isolation spec per route (ADR 0003) | designed, slices 1 and 5 |
| Tampering | Client sends prices, totals or status in the request | only line ids and quantities accepted (`params.expect`); prices and totals come from the order; status changes only through transitions (ADR 0009) | designed, slice 5 |
| Tampering | Double submission creates two invoices | idempotency key stored in the invoicing transaction; replay returns the first response (ADR 0005) | designed, slice 5 |
| Tampering | Invoice issued without stock issue, or receivables without invoice | one transaction for invoice, movements, reservations, receivables and audit; failure rolls back all | designed, slice 5 |
| Repudiation | Salesperson denies invoicing or cancelling | audit event per invoice and cancellation with actor, request id, IP; trail cannot be updated or deleted (ADR 0010) | designed, slices 1 and 5 |
| Information disclosure | Cost of goods visible to roles that should not see margins | serializers include cost only for capabilities that allow it (ADR 0008) | designed, slice 5 |
| Denial of service | Long lock waits block invoicing | `lock_timeout` 3 s, 409 `conflict_retry`, retry safe through the key | designed, slice 5 |
| Elevation of privilege | Sales role cancels an invoice (finance action) | policy capability matrix, `verify_authorized` on every action, matrix spec per role | designed, slices 1 and 5 |

## Stock

| STRIDE | Threat | Mitigation | Status |
|---|---|---|---|
| Tampering | Two concurrent approvals reserve the same last units | pessimistic lock on balance rows in fixed order, availability checked after the lock; barrier spec with real threads (ADR 0004) | designed, slice 5 |
| Tampering | Code path writes balances without the lock | single entry point `Inventory::Balance.lock_for`; forbidden patterns in `CONTRIBUTING.md`; domain reviewer | designed, slice 3 |
| Tampering | On-hand goes negative through a bug | `CHECK (on_hand >= -negative_allowance)` in the database; allowance only through a recorded authorization | designed, slice 3 |
| Tampering | Average cost drifts by rounding | cost kept as value in cents; issues take proportional value; exact-sum specs (ADR 0006) | designed, slice 3 |
| Repudiation | Adjustment without explanation | reason mandatory, actor and before/after in the audit trail | designed, slice 3 |
| Information disclosure | Stock levels of another organization | tenant scope and RLS as above | designed, slice 3 |
| Denial of service | Deadlock between orders with lines in opposite order | lock order by `(product_id, warehouse_id)`; spec with reversed line order | designed, slice 5 |
| Elevation of privilege | Sales role grants itself a negative allowance | capability limited to owner, admin and purchasing | designed, slice 3 |

## Platform

| Threat | Mitigation | Status |
|---|---|---|
| Secret committed to the repository | gitleaks over full history in CI, GitHub secret scanning with push protection, no credentials file | in place: `.github/workflows/ci.yml` |
| Vulnerable dependency | bundler-audit and npm audit in `bin/ci` and daily on `main`, dependency review on pull requests, Dependabot security updates | in place |
| Malicious package release (install script worm) | npm install scripts disabled, 7 day Dependabot cooldown, exact versions | in place: `frontend/.npmrc`, `.github/dependabot.yml` |
| Tampered or retagged base image | images pinned by digest, Trivy scan of the built image | in place: `Dockerfile`, image job |
| Injection or unsafe patterns in code | Brakeman with zero warnings, CodeQL for Ruby, TypeScript and workflows | in place |
| Compromised or moved GitHub Action tag; token read by a later step | actions pinned to commit SHAs (required by the repository), minimal `permissions`, `persist-credentials: false` | in place |
| Host header attacks | `config.hosts` restricted to `APP_HOST`, production refuses to boot without it | in place: `config/environments/production.rb`, `script/check_production_headers.rb` |
| Clickjacking | `frame-ancestors 'none'` and `X-Frame-Options: DENY` | in place: `spec/requests/spa_spec.rb` |
| Shell served without its headers | shell built outside `public/`, served only by `SpaController` | in place: `spec/requests/spa_spec.rb`, `bin/ci` |
| A compromised app process rewrites its own code | application code owned by root in the image; runtime user writes only `tmp` and `log`; no restart plugin in production | in place: `Dockerfile`, `config/puma.rb` |
| Database traffic intercepted between Render and Supabase | `sslmode=verify-full` with the provider CA | designed, first deploy |
| Application role alters the schema or disables RLS | separate owner and app roles | designed, first deploy |
| A migration breaks the running release or a rollback | strong_migrations | in place: `spec/db/strong_migrations_spec.rb` |
| Loss of the free database | scheduled dump, encrypted before storage, and restore test from GitHub Actions (ADR 0002) | designed, Milestone 2 |

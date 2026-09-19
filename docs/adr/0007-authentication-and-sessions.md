# ADR 0007: Password authentication with database sessions in an HttpOnly cookie

- Status: accepted
- Date: 2026-09-19

## Context

The SPA and the API share an origin (ADR 0001), so the browser can hold the session in a cookie the JavaScript cannot read. The target is OWASP ASVS level 2 on authentication and session management: modern password hashing, throttling, session rotation and revocation, single-use expiring reset tokens, timing-safe comparisons and optional multi-factor authentication. Rails 8.1 ships an authentication generator (database sessions, `has_secure_password`, `generates_token_for` for resets, `rate_limit`) but it stores the session record id in a signed cookie and has no absolute or idle expiry.

## Options

| | Devise | JWT in browser storage | Rails 8 generator as is | Generator, hardened |
|---|---|---|---|---|
| Revocation | yes | no, until expiry | yes | yes |
| Token readable by an XSS | no (cookie) | yes | no | no |
| Stolen database rows reveal usable sessions | n/a (cookie store) | n/a | ids only, cookie is signed | no, only token digests are stored |
| Idle and absolute timeouts | via modules | by expiry only | no | yes |
| Code the author must defend | large, implicit | custom | small | small, explicit |

## Decision

The generator's shape, hardened:

- Passwords: `has_secure_password` (bcrypt, cost 12; argon2 is not supported by Rails 8.1 and a custom hasher is not worth the risk). Minimum 12 characters, maximum 72 bytes (bcrypt limit), checked against a list of common passwords.
- Sessions: a `sessions` row per sign-in with the SHA-256 digest of a 32-byte random token, `user_id`, `organization_id`, `ip`, `user_agent`, `created_at`, `last_seen_at`. The raw token lives only in an encrypted cookie `__Host-session` with `Secure`, `HttpOnly`, `SameSite=Lax`, `Path=/`. Lookups compare digests, so a database leak does not yield usable sessions.
- Expiry: idle timeout 8 hours (`last_seen_at` refreshed at most once a minute), absolute lifetime 7 days.
- Rotation and revocation: a new session on every sign-in and on switching organization; changing the password or role destroys all other sessions of that user; users list and revoke their sessions.
- CSRF: Rails request forgery protection on every state-changing request, with the token read from `GET /api/v1/session` and sent in `X-CSRF-Token`. `SameSite=Lax` is the second layer, not the only one.
- Throttling: `rate_limit` on sign-in (per IP and per email), password reset requests and invitation acceptance, with a cache store that survives restarts (Solid Cache). No hard account lockout, which would let anyone lock a known user out; after repeated failures on one account the response is delayed and a notice is emailed to the owner.
- Uniform responses: sign-in failures and reset requests answer the same way whether or not the email exists.
- Password reset: `generates_token_for` with a 20 minute expiry, bound to the password salt, so the token stops working after one use.
- Two-factor: optional TOTP (RFC 6238) with recovery codes stored as digests, in the hardening slice. Its secret is encrypted with Active Record encryption.
- Comparisons of tokens and codes use `ActiveSupport::SecurityUtils.secure_compare`.

## Consequences

- No token is ever reachable from JavaScript; an XSS can still act inside the page, which is why the CSP stays strict.
- Session checks cost one indexed lookup per request.
- Rate limits depend on Solid Cache; if the cache is cleared, limits reset, which is accepted.
- The demo user shares one account among visitors; its role cannot change authentication settings, invite users or send email (see `docs/scope.md`).

## What would make me change my mind

- A requirement for single sign-on with customers' identity providers: OIDC through a maintained library, in a new ADR.
- Rails adding argon2id support to `has_secure_password`: migrate hashes on next sign-in.

# ADR 0007: Password authentication with database sessions in a __Host- cookie

- Status: accepted
- Date: 2026-09-19

## Context

The SPA and the API share an origin (ADR 0001), so the session can live in a cookie the JavaScript cannot read. The target is OWASP ASVS 4.0.3 level 2 for authentication and session management. Rails 8.1 ships an authentication generator (database sessions, `has_secure_password`, `generates_token_for` for resets, `rate_limit`) that stores the session record id in a signed cookie and has no idle or absolute expiry. API mode also drops the cookie and session middleware that request forgery protection needs.

## Options

| | Devise | JWT in browser storage | Rails 8 generator as is | Generator, hardened |
|---|---|---|---|---|
| Revocation | yes | no, until expiry | yes | yes |
| Token readable by an XSS | no | yes | no | no |
| A database dump yields usable sessions | n/a | n/a | no, but ids are guessable if the signing key leaks | no, only token digests are stored |
| Idle and absolute timeouts | via modules | by expiry only | no | yes |
| Code the author must defend | large, implicit | custom | small | small, explicit |

## Decision

**Passwords.** `has_secure_password` with bcrypt at cost 12. Rails 8.1 supports only bcrypt there; a custom argon2 hasher adds more risk than it removes. Passwords are 12 to 72 bytes (bcrypt's limit): at least 64 characters of ASCII, fewer when many characters are accented; this deviation from ASVS 2.1.2 is recorded in `docs/security.md`. New passwords are checked against a list of common passwords shipped with the app.

**Sessions.** One `identity_sessions` row per sign-in: `user_id`, `organization_id`, the SHA-256 digest of a 32-byte random token, `created_at`, `last_seen_at`, and `ip` and `user_agent` for the user's own session list. The raw token lives only in the cookie `__Host-session` (`Secure`, `HttpOnly`, `SameSite=Lax`, `Path=/`); it is random and verified by digest, so it is not additionally signed or encrypted.
- Expiry (ASVS 3.3.2): idle 30 minutes (`last_seen_at` refreshed at most once a minute), absolute 12 hours.
- Rotation: a new session on sign-in and on switching organization; the old row is deleted.
- Revocation: changing the password or role deletes every other session of that user in every organization; users can list and end their own sessions. Demo users see no session list, and their sessions store no IP or user agent.

**CSRF.** The cookie and cookie-store session middleware are added back in API mode. The Rails session holds only the CSRF token, in its own cookie `__Host-csrf`, and is reset on sign-in and sign-out, which also covers login CSRF. `GET /api/v1/session` returns the token (and the signed-in user, when there is one) as a JSON object; the SPA sends it in `X-CSRF-Token` on every state-changing request.

**Throttling without lockout.** `rate_limit` per IP (10 sign-in attempts per 3 minutes) and per IP and email pair (5 per 3 minutes) on sign-in, and per IP on password reset requests and invitation acceptance. There is no limit per email alone, so nobody can lock another user out, including the shared demo account. Responses are not delayed. Distributed guessing against one account remains possible and is recorded as an accepted risk, mitigated by the password policy and optional two-factor authentication.

**Uniform responses.** Sign-in failures and reset requests answer the same way and do the same work (a bcrypt comparison against a dummy digest when the email is unknown), whether or not the account exists.

**Password reset.** `generates_token_for` with a 20 minute expiry, bound to the password salt, so a token stops working after one use or any password change.

**Two-factor (hardening slice).** Optional TOTP (RFC 6238): the secret encrypted with Active Record encryption, the last accepted time step stored to reject replays, attempts rate limited like sign-in, recovery codes stored as digests.

**Comparisons** of tokens and codes use `ActiveSupport::SecurityUtils.secure_compare`. Failed sign-ins are logged as structured events with a hashed email; successful sign-ins and password changes are audit events.

## Consequences

- No token is reachable from JavaScript; an XSS can still act inside the page, which is why the CSP stays strict.
- A 30 minute idle timeout interrupts long pauses; the SPA warns before it expires.
- Rate limit counters live in Solid Cache and reset if it is cleared, which is accepted.

## What would make me change my mind

- Single sign-on with customers' identity providers: OIDC through a maintained library, in a new ADR.
- Rails adding argon2id to `has_secure_password`: migrate hashes on next sign-in and lift the 72 byte limit.

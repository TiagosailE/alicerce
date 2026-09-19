# ADR 0001: Rails 8.1 API with a React + TypeScript SPA on the same origin

- Status: accepted
- Date: 2026-09-19

## Context

Alicerce is a multi-tenant ERP whose core is the closed loop purchase, stock, sale and finance. The invariants that matter (no negative stock without authorization, atomic invoicing and stock issue, idempotent critical writes, explicit state machines, money as integer cents) are about transactions, locks and database constraints. The UI is dense: filterable lists, master-detail documents, bulk actions, keyboard shortcuts.

The project is a portfolio piece with no specific target role. The owner's stated priority is the broadest market fit. This ADR assumes that React with TypeScript is a stronger general signal for front-end and full-stack roles than Hotwire, and that backend interviews probe transactions, concurrency and security more than the language. That assumption is not backed by a job post count here; it is the weakest link of this decision and is listed below as a reason to reopen it.

Prior work of the author: one earlier Rails 8.1 project contains a pessimistic lock on a contended row with a CHECK constraint and a real-thread race test, raw SQL constraint specs, integer cents with price snapshots, a CSP built from an inventory and `rate_limit` on authentication. Neither Rails project had multi-tenancy, a policy layer or correct idempotency, and the earlier Node project had no multi-statement transactions at all. Tenancy, authorization and idempotency are new work under every option.

## Options

**A. Rails 8.1 full stack with Hotwire.** Server-rendered screens with Turbo and Stimulus. Fastest way to ship dense CRUD; sessions, CSRF, CSP nonces and form handling come from the framework. A JSON API would only exist if an integration needed one. Weakness for this project: no React in the result, and interactive grids with keyboard shortcuts need more custom Stimulus code.

**B. Rails 8.1 JSON API + React/TypeScript SPA, same origin.** Rails owns the domain, persistence, authentication and authorization. The SPA is built with Vite and served by Rails from the same origin, so the session stays in an HttpOnly cookie and there is no CORS. The OpenAPI document comes from request specs and is turned into TypeScript types for the SPA.

**C. Node (NestJS) + React/TypeScript.** One language and the widest keyword match for full-stack posts. Authorization, tenancy, transactions, jobs and security scanning are assembled from separate libraries.

| Criterion | A. Rails + Hotwire | B. Rails API + React | C. Node + React |
|---|---|---|---|
| Speed on dense CRUD | best | slower: every screen is a component tree plus an endpoint | slowest: more layers before the first screen |
| Authorization and multi-tenancy | mature (Action Policy or Pundit, `Current` attributes, Postgres RLS) | same as A on the server | available (CASL, manual scoping, RLS), less conventional |
| Transactions and financial consistency | Active Record transactions, row locks, CHECK constraints | same as A | capable, unproven in prior work |
| Background jobs | Solid Queue in the same Postgres, so enqueueing is transactional | same as A | pg-boss or BullMQ (Redis) |
| Security defaults | CSRF, CSP with nonces, strong params, encrypted attributes, Brakeman | server as A; the SPA shell, CSRF and CSP must be wired by hand in API mode | assembled by hand (helmet, CSRF, generic SAST) |
| Tests | RSpec, FactoryBot, system tests | RSpec + rswag on the API; Vitest and Playwright on the SPA | Vitest, supertest, Playwright |
| Toolchains to maintain | one | two (Bundler and npm) | one |
| Market signal (assumption) | Rails only | React/TS on data-heavy screens plus a Rails backend | full-stack TypeScript |

Without the market row, A wins or ties every criterion. The choice of B is the decision to pay A's speed and simplicity for React on data-heavy screens, which is the gap in the owner's earlier work.

## Decision

Option B, with these specifics:

- Rails runs with `config.api_only = true`. The cookie and session middleware are added back explicitly, API controllers include request forgery protection, and the CSRF token is sent by the SPA in the `X-CSRF-Token` header.
- The SPA shell (`index.html`) is rendered by a Rails controller, not served as a static file, so every response carries the CSP header and the CSRF token. Deep links fall through to that controller; `/api` and `/up` never do.
- React escapes output by default; `dangerouslySetInnerHTML` is forbidden by lint. HttpOnly cookies do not stop an XSS from calling the API from inside the page, so CSP with `script-src 'self'` and no inline scripts is the real control.
- Response schemas in the OpenAPI document are strict (`required` fields and `additionalProperties: false`). CI regenerates the document and the TypeScript types and fails when they differ from what is committed.
- Money is never computed in the SPA. Totals come from the API.

Pinned toolchain (exact versions in `mise.toml`, `Gemfile.lock` and `package-lock.json`): Ruby 4.0, Rails 8.1, PostgreSQL 18, Node 24 LTS, TypeScript 6.0, React 19, Vite, TanStack Query, React Router. Each further dependency is justified in the commit that adds it.

## Consequences

Positive
- Domain rules, locks and transactions live in one place and are tested without a browser.
- One deploy unit: a multi-stage Docker image builds the SPA and copies it next to Rails.
- The API is a real, published contract.

Negative
- Two toolchains, two linters, two test runners.
- UI work is slower than with Hotwire. A small set of shared components (data table, form field, money input, status badge) is built when the second screen needs it, not before.
- API mode drops framework defaults that A would provide; each one added back is listed above and covered by a test.
- Logic in the browser needs real browser tests. Playwright covers the money flows end to end.

## What would make me change my mind

- Evidence that the target market values Hotwire or full-stack TypeScript over React with a Rails backend (a count of relevant job posts, or a concrete target role). Node-specific roles would trigger an ADR on porting the API; the SPA and the contract would survive.
- If slices 1 and 2 together show more lines changed in the SPA than in the backend and its tests, the UI cost is dominating domain work, and a new ADR evaluates replacing the SPA with Hotwire. The two are never mixed without that ADR.
- If Ruby 4.0 blocks a required gem, Ruby 3.4 is the fallback, recorded in the commit that changes `mise.toml`.

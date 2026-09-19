# ADR 0001: Rails 8.1 API with a React + TypeScript SPA on the same origin

- Status: accepted
- Date: 2026-09-19

## Context

Alicerce is a multi-tenant ERP whose core is the closed loop purchase, stock, sale and finance. The invariants that matter (no negative stock without authorization, atomic invoicing and stock issue, idempotent critical writes, explicit state machines, money as integer cents) are all about transactions, locks and database constraints. The UI is dense: filterable lists, master-detail documents, bulk actions, keyboard shortcuts.

The project is also a portfolio piece, so the choice has to hold up in two places: in the code review of a tech lead, and in the job market the author is aiming at. No specific role is targeted, so the market criterion is the broadest one: React and TypeScript are the most requested front-end skills, and backend roles screen for transactional and security fundamentals more than for a language.

Prior work matters too. Two earlier Rails 8.1 projects already contain the patterns this domain needs: a pessimistic lock on a contended row with a CHECK constraint and a real-thread race test, raw SQL constraint specs, integer cents with price snapshots, a CSP built from an inventory, `rate_limit` on authentication and a CI with Brakeman and bundler-audit. The earlier Node + React project has solid integration tests and CI but no multi-statement transactions, no locks, no idempotency keys, no authorization layer, and its React code is game UI without a router, server-state cache, forms or tables.

## Options

**A. Rails 8.1 full stack with Hotwire.** Fastest way to ship dense CRUD. Server-rendered forms, CSRF and sessions come for free. No React anywhere, and the API would be a second surface built only for this ADR's sake.

**B. Rails 8.1 JSON API + React/TypeScript SPA, same origin.** Rails owns the domain, persistence, authentication and authorization. The SPA is built with Vite and served by Rails from the same origin, so the session stays in an HttpOnly cookie and CSRF is a header, with no tokens in browser storage and no CORS. The OpenAPI document is generated from request specs and turned into TypeScript types for the SPA.

**C. Node (NestJS) + React/TypeScript.** Single language and the widest keyword match for full-stack job posts. Authorization, tenancy, transactions, job processing and security scanning have to be assembled from separate libraries, most of them new to the author.

| Criterion | A. Rails + Hotwire | B. Rails API + React | C. Node + React |
|---|---|---|---|
| Speed on dense CRUD | best | medium: shared table, form and money input components carry most screens | slowest: more layers to assemble before the first screen |
| Authorization and multi-tenancy | mature (Action Policy or Pundit, `Current` attributes, Postgres RLS) | same as A | available (CASL, manual scoping, RLS) but less conventional |
| Transactions and financial consistency | Active Record transactions, `lock`, isolation levels, CHECK constraints, all proven in prior work | same as A | capable (`transaction`, `FOR UPDATE`), unproven in prior work |
| Background jobs | Solid Queue on Postgres, no Redis | same as A | pg-boss or BullMQ (Redis) |
| Security tooling | Brakeman (framework-aware SAST), bundler-audit, CSRF, CSP, strong params, encrypted attributes built in | A plus `npm audit` for the SPA | generic SAST (CodeQL, Semgrep), helmet, CSRF by hand |
| Test quality | RSpec, FactoryBot, rswag, system tests | RSpec + rswag on the API, Vitest and Playwright on the SPA | Vitest, supertest, Playwright |
| Prior mastery | two projects | two projects on the backend, one on React | one project, without transactions |
| Market signal | Rails only | React/TS plus a strong backend | full-stack TS |

## Decision

Option B. The backend keeps every pattern already proven for this kind of invariant, and the front end puts React and TypeScript in the context the market asks for and prior work lacks: data-heavy screens. The generated contract (OpenAPI to TypeScript types) removes the class of bug that cost the most rework in the earlier Node project, where the API returned fields under two names and the client typed everything as optional.

Pinned toolchain (exact versions live in `mise.toml`, `Gemfile.lock` and `package-lock.json`): Ruby 4.0, Rails 8.1, PostgreSQL 18, Node 24 LTS, React 19, Vite, TanStack Query, React Router. Each additional dependency is justified in the commit that adds it.

## Consequences

Positive
- Domain rules, locks and transactions live in one place, tested without a browser.
- Same origin: cookie session with `HttpOnly`, `Secure`, `SameSite=Lax`, CSRF token in a header, CSP with `script-src 'self'`, no CORS configuration at all.
- One deploy unit: a multi-stage Docker image builds the SPA and copies it into Rails' `public/`.
- The API is a real contract with a published OpenAPI document, useful to integrations and to reviewers.

Negative
- Two toolchains (Bundler and npm) in one repository, two linters, two test runners.
- UI work is slower than Hotwire. Mitigation: a small set of shared components (data table, form field, money input, status badge) used by every module, built when the second screen needs them, not before.
- Logic in the browser needs real browser tests. Playwright covers the money flows end to end, because an earlier project hid four bugs behind request specs.
- The SPA must never compute money. Totals come from the API.

## What would make me change my mind

- If the target shifts to Node backend roles specifically, a new ADR would evaluate porting the API; the SPA and the contract would survive.
- If, after the first two vertical slices, SPA screens cost more than twice the estimate, a new ADR would evaluate Hotwire for back-office screens. Mixing both without that ADR is not allowed.
- If Ruby 4.0 blocks a required gem, Ruby 3.4 is the fallback, recorded in the commit that changes `mise.toml`.

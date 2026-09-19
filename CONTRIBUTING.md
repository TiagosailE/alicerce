# Contributing

## Product

Alicerce is a multi-tenant ERP for small Brazilian distributors. The core is the closed loop purchase, stock, sale and finance, with its consistency rules enforced by the domain and the database. Rails serves a JSON API and a React SPA from the same origin. The interface is in Brazilian Portuguese; code, API and documentation are in English. Scope and roadmap: [docs/scope.md](docs/scope.md).

## Stack

| Piece | Version | Pinned in |
|---|---|---|
| Ruby | 4.0.7 | `.ruby-version` and the `Dockerfile` base image (bump both) |
| Rails | 8.1.3 | `Gemfile.lock` |
| PostgreSQL | 18.6 | `compose.yaml` and the CI service, by digest |
| Node | 24.21.0 | `.node-version` and the `Dockerfile` build image (bump both) |
| TypeScript | 6.0.3 | `frontend/package-lock.json` |
| React / Vite / Tailwind | 19.3 / 8.3 / 4.3 | `frontend/package-lock.json` |

Jobs (Solid Queue, as threads inside Puma) and cache (Solid Cache) live in the primary database. mise reads `.ruby-version` and `.node-version`. `json` stays below 3 until Rails stops passing it positional options.

## Commands

| Task | Command |
|---|---|
| First run: dependencies, database, servers | `bin/setup` |
| Start Rails (:3000) and Vite (:5173) | `bin/dev` |
| Every check that runs locally | `bin/ci` |
| Ruby tests | `bin/rspec` |
| Frontend tests | `npm --prefix frontend test` |
| Browser tests against a running production-like server | `E2E_BASE_URL=http://127.0.0.1:10000 npm --prefix frontend run e2e` |
| Lint | `bin/rubocop`, `npm --prefix frontend run lint` |
| Format and typecheck the frontend | `npm --prefix frontend run format`, `npm --prefix frontend run typecheck` |
| Migrate | `bin/rails db:migrate` |
| Reset the database | `bin/setup --reset --skip-server` |
| Security checks | `bin/brakeman`, `bin/bundler-audit check --update`, `npm --prefix frontend audit` |
| Database only | `docker compose up -d --wait db` |

`bin/setup` starts Postgres through Docker Compose on 127.0.0.1:5433. To use a Postgres you already run, export `PGHOST`, `PGPORT`, `PGUSER` and `PGPASSWORD` first. Every variable the app reads is listed in `.env.example`. Demo seeds arrive with each slice's models.

`bin/ci` runs lint, types, audits, Brakeman, the Ruby and frontend tests, the SPA build and a production header check. CI adds what cannot run locally: the production image started with Postgres (health, headers, Solid Queue, memory budget, a Chromium test that fails on any CSP violation), Trivy, gitleaks over the whole history, dependency review and CodeQL. A daily workflow audits dependencies on `main`.

## Where things live

| Path | Holds |
|---|---|
| `app/controllers/api/v1/` | Thin controllers: authenticate, authorize, call a command or query, render a serializer |
| `app/commands/<context>/` | One class per write use case (`Sales::ApproveOrder`); owns the transaction, locks, state transition and idempotency; returns a `Result` |
| `app/models/<context>/` | Active Record models namespaced by context (`Inventory::Balance` in `inventory_balances`), value objects, state machine tables |
| `app/policies/<context>/` | One policy per model; everything denied unless a rule allows it |
| `app/serializers/<context>/` | Plain Ruby objects that shape API responses to the OpenAPI schemas |
| `app/queries/<context>/` | Read-side queries with filters, sorting and pagination |
| `spec/` | `models`, `commands`, `policies`, `requests/api/v1`, `db` (raw SQL constraint specs), `concurrency` |
| `frontend/src/features/<context>/` | Screens and their components |
| `frontend/src/components/ui/` | Shared primitives used by more than one feature |
| `frontend/src/api/` | Generated OpenAPI types and the typed client |
| `frontend/src/i18n/` | pt-BR strings |
| `docs/adr/` | Architecture decision records |

Contexts: `identity`, `catalog`, `inventory`, `purchasing`, `sales`, `finance`, `audit`. Folders are created by the slice that first needs them; this table says where they go.

## Conventions

Code
- RuboCop (Rails omakase), ESLint with the strict type-checked presets, Prettier. `bin/ci` must be green.
- Comments explain a function or a rule that the code cannot make obvious. No commented-out code.
- A new dependency needs a reason in its commit message: what it does that the standard library or an existing dependency does not.
- No TODO in code: open an issue or do it.

Commits and branches
- Conventional Commits (`feat`, `fix`, `docs`, `test`, `refactor`, `build`, `ci`, `chore`), imperative subject, body explaining why.
- Branch per change: `feat/stock-movements`, `fix/...`, `docs/...`. Small commits that each pass `bin/ci`.
- `main` is protected: pull request, all checks green, linear history, rebase merge.

## Domain invariants

Non-negotiable. Each gets a dedicated test in the slice that implements it; the rules behind them are in [docs/scope.md](docs/scope.md).

1. Stock on hand never goes below zero unless a recorded authorization grants a negative allowance; the database checks `on_hand >= -negative_allowance`.
2. Invoicing and its stock issue are atomic, as are receiving and stock entry, and every reversal.
3. Critical writes are idempotent through an `Idempotency-Key`.
4. Stock changes lock balance rows pessimistically, in ascending `(product_id, warehouse_id)` order.
5. Orders, receipts, invoices and financial titles change state only through their state machine.
6. Money is integer cents with an explicit currency. No floats.

## Security rules for new code

- Every endpoint authorizes through a policy and every tenant query goes through the tenant scope. Records of another organization answer 404, never 403.
- Parameters are permitted explicitly with `params.expect`; never `permit!`.
- No SQL built by string interpolation; use bind parameters.
- No inline scripts or styles and no `dangerouslySetInnerHTML`: the CSP forbids them.
- Secrets only from the environment. Personal data (CPF, CNPJ, e-mail, phone) is filtered from logs and encrypted at rest where it is a document number.
- No external HTTP call inside a database transaction; outbound hosts are allowlisted.
- Uploads are checked by content type, size and name, and stored outside `public/`.
- Money is never computed in the SPA; totals come from the API.

## Pull request checklist

- [ ] `bin/ci` green locally and in CI.
- [ ] New behavior has tests, including the authorization matrix per role and tenant isolation for new endpoints.
- [ ] Migrations are reversible and pass strong_migrations without `safety_assured`, or the pull request explains each use.
- [ ] OpenAPI document and generated TypeScript types updated together.
- [ ] Decisions that are hard to reverse have an ADR.
- [ ] This file updated in the same pull request when a command, path or convention changes.

## Never

- Never update `inventory_balances` outside the inventory commands, and never with `update_column` or `update_all`.
- Never change a document's status with `update!(status:)`; call its transition.
- Never call `unscoped` or `find` on a tenant model outside the tenant scope.
- Never compute with `Float` in Ruby or `number` arithmetic in TypeScript on money.
- Never serve the SPA shell as a static file: the build keeps `index.html` in `frontend/dist` and `SpaController` serves it with the CSP.
- Never add `unsafe-inline` to the CSP, and never add a frontend library that injects `<style>` tags or inline scripts; the browser test in CI fails on it.
- Never turn npm install scripts back on (`ignore-scripts` in `frontend/.npmrc`) without naming the package that needs them.
- Never load the Solid Queue Puma plugin in fork mode on the 512 MB instance.
- Never rescue `StandardError` in a command; expected failures are `Result` codes.
- Never commit `.env` files or keys; `config/credentials` is not used.

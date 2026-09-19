# ADR 0011: Schema-first OpenAPI, validated in request specs, typed client generated for the SPA

- Status: accepted
- Date: 2026-09-19

## Context

`CONTRIBUTING.md` already states the rule: the OpenAPI document is written first, request specs validate every response against it, and the SPA types are generated from it. Slice 1 PR 2 is the first pull request with real endpoints (`/api/v1/session` and the organization switch), so this is where the mechanism has to exist for real, not only as a sentence in a contributing guide. Two failure modes matter more than the tool choice: a response that silently drifts from the documented shape (the SPA breaks at runtime, not at build time), and a document that drifts from the code because nothing forces them to match.

## Options

| | Hand-written types, no schema | `rswag` (specs generate the document) | OpenAPI written first, `committee` validates responses, `openapi-typescript` generates SPA types |
|---|---|---|---|
| Document can drift from the real response | yes, silently | no, generated from what ran | no, `committee` fails the spec on drift |
| Document can drift from what was intended | n/a | yes, whatever the code returns becomes "the contract" | no, the document is the contract, code that violates it fails |
| SPA types can drift from the API | yes | possible, another generation step | no, generated in the same pull request, CI diffs the output |
| Extra runtime dependency | none | `rswag` gem, RSpec-coupled | `committee` (test-only), `openapi-typescript` (dev-only, Node) |
| Works with `config.api_only` and no ActiveModel serializers | yes | yes | yes, `committee` only needs the schema and the Rack response |

## Decision

**The document is authoritative, not generated.** `docs/openapi/openapi.yaml`, OpenAPI 3.0.3, hand-written before or alongside the endpoint. `committee` 5.6 (the current release) raises `OpenAPI3Unsupported` on a `3.1.x` document, so 3.0.3 is the newest version the validator actually accepts; `openapi-typescript` supports both, so this is a constraint from one side of the pipeline, recorded here so nobody upgrades the document to 3.1 and gets a confusing parser error. `operationId` per route, `components/schemas` reused between success and error bodies. Every schema sets `additionalProperties: false` and lists `required`, matching the API contract in `CONTRIBUTING.md`.

**Request specs validate against it.** `spec/support/schema_validation.rb` wraps the `committee` gem: `Committee::Drivers.load_from_file(Rails.root.join("docs/openapi/openapi.yaml"), format: "yaml")` builds one schema for the suite, and `assert_response_schema_confirm` (a small helper, not `committee-rails`, which pulls in an unneeded Rack::Test coupling) checks the actual Rack response of each example against its `operationId`. A response that adds, drops or mistypes a field fails the spec, not a manual review.

**Errors share one schema.** `components/schemas/Error` matches the envelope in `CONTRIBUTING.md` (`code`, `message`, `details`, `request_id`); every documented error response reuses it, so a new endpoint cannot invent a different failure shape.

**Types generated for the SPA.** `npm --prefix frontend run generate:api` runs `openapi-typescript` against the same document into `frontend/src/api/schema.d.ts`, committed, not built on the fly. `bin/ci` regenerates it and fails the build if the working tree then differs (`git diff --exit-code`), the same guard already used for the SPA shell location. The SPA never hand-writes a response type; `frontend/src/api/` will hold one typed `fetch` wrapper reading from `schema.d.ts` once a screen needs it (deferred, no screen exists yet).

**Versioning.** Additive changes stay in `openapi.yaml` under `/api/v1`; a breaking change adds `openapi-v2.yaml` per `CONTRIBUTING.md`'s `/api/v2` rule, not a new major version of this document's own format.

## Consequences

- Every new endpoint costs one more schema block before the controller, not after; this is the point, not overhead.
- `bin/ci` gains two steps: schema validation runs inside `bin/rspec` (no separate step), and a TypeScript generation diff check.
- `committee` only understands the request and response shape; it does not replace request specs asserting status codes, headers or business behavior.
- A hand-written document can still describe a field the code never returns; `committee`'s response validation catches that the first time a spec exercises the path, which is why every endpoint needs at least one request spec per response shape it documents.

## What would make me change my mind

- The document and the code diverging often enough that generating the document from annotated controllers (`rswag`) would cost less review time than it costs contract precision: revisit once slice 1 ships and the pattern has been used more than a handful of times.

import createClient from "openapi-fetch";
import type { components, paths } from "./schema";

type ErrorBody = components["schemas"]["Error"];
interface ErrorEnvelope {
  error: ErrorBody;
}

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly details: Record<string, unknown>;
  readonly requestId: string | null;

  constructor(status: number, body: ErrorBody) {
    super(body.message);
    this.name = "ApiError";
    this.status = status;
    this.code = body.code;
    this.details = body.details;
    this.requestId = body.request_id;
  }
}

let csrfToken = "";

/** Kept in memory, never persisted: refreshed from every session response. */
export function setCsrfToken(token: string) {
  csrfToken = token;
}

/** Every mutating call passes this in `params.header`; GET never needs it. */
export function csrfHeader() {
  return { "X-CSRF-Token": csrfToken };
}

export const api = createClient<paths>({
  // An absolute URL, not just "/api/v1": the Request constructor has no
  // document to resolve a relative one against outside a real browser
  // navigation, which is also why a relative baseUrl silently breaks under
  // Vitest's Node-based fetch, not only here.
  baseUrl: `${window.location.origin}/api/v1`,
  // openapi-fetch otherwise binds globalThis.fetch once at client creation;
  // this indirection reads it fresh per call, so tests that stub fetch
  // after this module has already loaded still take effect.
  fetch: (...args: Parameters<typeof fetch>) => fetch(...args),
});

/**
 * Every feature hook's query/mutation function ends with this: throws an
 * ApiError so TanStack Query treats it as a failure, otherwise unwraps both
 * envelopes (openapi-fetch's own, then the API's `{ data: ... }` shape).
 * `response` alone (no `data`/`error`) means a 204 with no body.
 */
export function unwrap<T>(result: {
  data?: { data: T };
  error?: ErrorEnvelope;
  response: Response;
}): T {
  if (result.error) throw new ApiError(result.response.status, result.error.error);
  return (result.data as { data: T }).data;
}

/** For endpoints that answer 204 on success and only ever the error envelope otherwise. */
export function unwrapEmpty(result: { error?: ErrorEnvelope; response: Response }): void {
  if (result.error) throw new ApiError(result.response.status, result.error.error);
}

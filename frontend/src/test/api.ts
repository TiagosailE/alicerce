import { vi } from "vitest";

/** Helpers for a screen test that talks to the API through a stubbed fetch. */
export function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export function listResponse(data: unknown[], perPage = 25) {
  return jsonResponse({ data, meta: { page: 1, per_page: perPage, total: data.length } });
}

export function errorEnvelope(
  code: string,
  message = code,
  details: Record<string, unknown> = {},
  status = 422,
) {
  return jsonResponse({ error: { code, message, details, request_id: "req-1" } }, status);
}

type Handler = (request: Request) => Response | Promise<Response>;

/** A fetch that answers by "METHOD /path" and fails the test on a request nobody
 * expected, so an unplanned call is never silently ignored. */
export function createFetchMock(handlers: Record<string, Handler>) {
  return vi.fn((input: RequestInfo | URL) => {
    const request = input as Request;
    const path = new URL(request.url).pathname.replace(/^\/api\/v1/, "");
    const key = `${request.method} ${path}`;
    const handler = handlers[key];
    if (!handler) throw new Error(`Unhandled request in test: ${key}`);
    return handler(request);
  });
}

export async function jsonBody(request: Request): Promise<unknown> {
  return request.clone().json();
}

import { ApiError } from "../api/client";

/** One key per user intent (ADR 0005): a form makes a new one when what is being
 * asked changes, and keeps the same one for a retry of the same request. */
export function newIdempotencyKey(): string {
  return globalThis.crypto.randomUUID();
}

/** Whether a failed attempt may be repeated under the same key. It may when the
 * answer never arrived, when the server failed, or when a lock conflicted
 * (409): the request may have committed unseen, and the key lets the server say
 * so instead of doing it twice. Any other answer means "this attempt is over",
 * and the next one is a new intent with a new key. */
export function keepsAttempt(error: unknown): boolean {
  if (!(error instanceof ApiError)) return true;
  return error.status >= 500 || error.status === 409;
}

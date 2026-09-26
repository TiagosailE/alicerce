import { describe, expect, it } from "vitest";
import { ApiError } from "../api/client";
import { keepsAttempt, newIdempotencyKey } from "./idempotency";

function apiError(status: number, code = "x") {
  return new ApiError(status, { code, message: "x", details: {}, request_id: "req-1" });
}

describe("newIdempotencyKey", () => {
  it("makes a different key of the length the API accepts every time", () => {
    const first = newIdempotencyKey();
    const second = newIdempotencyKey();

    expect(first).not.toBe(second);
    expect(first.length).toBeGreaterThanOrEqual(8);
    expect(first.length).toBeLessThanOrEqual(100);
    expect(first).toMatch(/^[A-Za-z0-9._:-]+$/);
  });
});

describe("keepsAttempt", () => {
  it("keeps the key when no answer arrived, so the retry can be recognised", () => {
    expect(keepsAttempt(new TypeError("Failed to fetch"))).toBe(true);
  });

  it.each([500, 502, 503, 409])("keeps the key on a %i", (status) => {
    expect(keepsAttempt(apiError(status))).toBe(true);
  });

  it.each([400, 401, 403, 404, 422, 429])("ends the attempt on a %i", (status) => {
    expect(keepsAttempt(apiError(status))).toBe(false);
  });
});

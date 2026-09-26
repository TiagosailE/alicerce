import { ApiError } from "../api/client";
import { t } from "../i18n";

/** The record was changed by someone else since it was read (409 stale):
 * the edit was refused and nothing was written. */
export function isStale(error: unknown): boolean {
  return error instanceof ApiError && error.code === "stale";
}

/** Appended to any error message shown to a person, so support can find the
 * request in the logs; empty when the failure never reached the API. */
export function requestIdSuffix(error: unknown): string {
  if (error instanceof ApiError && error.requestId) {
    return ` ${t("app.requestIdPrefix")}${error.requestId}`;
  }
  return "";
}

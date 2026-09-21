import { ApiError } from "../api/client";
import { t } from "../i18n";

/** Appended to any error message shown to a person, so support can find the
 * request in the logs; empty when the failure never reached the API. */
export function requestIdSuffix(error: unknown): string {
  if (error instanceof ApiError && error.requestId) {
    return ` ${t("app.requestIdPrefix")}${error.requestId}`;
  }
  return "";
}

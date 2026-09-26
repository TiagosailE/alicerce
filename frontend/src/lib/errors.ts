import { ApiError } from "../api/client";
import { type MessageKey, t } from "../i18n";

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

/** The API reports a validation_failed as details.fields: { field: [kind, ...] }
 * (api-contract skill); empty for any other kind of failure. */
export function apiFieldErrors(error: unknown): Record<string, string[]> {
  if (!(error instanceof ApiError) || error.code !== "validation_failed") return {};
  const fields: unknown = error.details.fields;
  if (!fields || typeof fields !== "object") return {};
  return fields as Record<string, string[]>;
}

/** The message for the first error kind of a field: the form's own text when
 * it names that kind, otherwise its generic one, so nothing is ever silent. */
export function fieldErrorMessage(
  fieldErrors: Record<string, string[]>,
  field: string,
  messages: Record<string, Partial<Record<string, MessageKey>>>,
  generic: MessageKey,
): string | null {
  const kind = fieldErrors[field]?.[0];
  if (!kind) return null;
  const key = messages[field]?.[kind];
  return key ? t(key) : t(generic);
}

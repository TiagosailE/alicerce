import { type MessageKey, t, tf } from "../../i18n";
import type { PurchaseOrderStatus } from "./api";

export const STATUS_KEYS: Record<PurchaseOrderStatus, MessageKey> = {
  draft: "purchasing.statusDraft",
  approved: "purchasing.statusApproved",
  partially_received: "purchasing.statusPartiallyReceived",
  received: "purchasing.statusReceived",
  cancelled: "purchasing.statusCancelled",
};

export const ORDER_STATUSES = Object.keys(STATUS_KEYS) as PurchaseOrderStatus[];

/** Where an order still can go: only these two states are open to receiving. */
export function canReceive(status: PurchaseOrderStatus): boolean {
  return status === "approved" || status === "partially_received";
}

/** A cancellation is possible until the order is complete or already cancelled. */
export function canCancel(status: PurchaseOrderStatus): boolean {
  return status === "draft" || canReceive(status);
}

/** What the state means for the person reading the order, and what they can do
 * about it: someone who cannot write orders is not told to. */
export function statusNote(status: PurchaseOrderStatus, canManage: boolean): MessageKey {
  switch (status) {
    case "draft":
      return canManage ? "purchasing.noteDraft" : "purchasing.noteDraftViewer";
    case "approved":
      return canManage ? "purchasing.noteApproved" : "purchasing.noteApprovedViewer";
    case "partially_received":
      return "purchasing.notePartiallyReceived";
    case "received":
      return "purchasing.noteReceived";
    case "cancelled":
      return "purchasing.noteCancelled";
  }
}

/** The payment terms as a sentence: the singular, the same-day and the
 * one-day cases each read as a person would say them. */
export function termsText(order: {
  installments: number;
  first_due_days: number;
  interval_days: number;
}): string {
  const first = order.first_due_days;
  const when =
    first === 0
      ? t("purchasing.termsWhenReceipt")
      : first === 1
        ? t("purchasing.termsWhenOneDay")
        : tf("purchasing.termsWhenDays", { days: String(first) });
  if (order.installments === 1) return tf("purchasing.termsOne", { when });

  const gap = order.interval_days;
  const rest =
    gap === 0
      ? t("purchasing.termsRestSameDay")
      : gap === 1
        ? t("purchasing.termsRestEveryOneDay")
        : tf("purchasing.termsRestEveryDays", { days: String(gap) });
  return tf("purchasing.termsMany", { installments: String(order.installments), when, rest });
}

/** What a saved draft hands to the page it opens, which then says it was saved. */
export const SAVED_STATE = { saved: true } as const;

export function wasSaved(state: unknown): boolean {
  return typeof state === "object" && state !== null && "saved" in state && state.saved === true;
}

/** The id in an address, or null when it is not a whole number: "novo" or "x"
 * must not become a request for order NaN. */
export function orderIdFromParam(value: string | undefined): number | null {
  return value !== undefined && /^[1-9]\d{0,14}$/.test(value) ? Number(value) : null;
}

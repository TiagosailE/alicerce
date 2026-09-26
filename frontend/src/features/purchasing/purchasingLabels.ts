import type { MessageKey } from "../../i18n";
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

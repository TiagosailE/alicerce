import type { MessageKey } from "../../i18n";
import type { AdjustmentReason } from "./api";

export const REASON_KEYS: Record<AdjustmentReason, MessageKey> = {
  opening_balance: "stock.reasonOpeningBalance",
  count: "stock.reasonCount",
  loss: "stock.reasonLoss",
  damage: "stock.reasonDamage",
  theft: "stock.reasonTheft",
  expiry: "stock.reasonExpiry",
  found: "stock.reasonFound",
  other: "stock.reasonOther",
};

export const ADJUSTMENT_REASONS = Object.keys(REASON_KEYS) as AdjustmentReason[];

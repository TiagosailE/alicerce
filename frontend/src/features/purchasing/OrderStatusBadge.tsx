import { t } from "../../i18n";
import type { PurchaseOrderStatus } from "./api";
import { STATUS_KEYS } from "./purchasingLabels";

// The text says the status; the dot repeats it in color, so the meaning never
// rests on color alone and the text keeps the highest contrast.
const DOT: Record<PurchaseOrderStatus, string> = {
  draft: "bg-idle",
  approved: "bg-info",
  partially_received: "bg-warning",
  received: "bg-success",
  cancelled: "bg-danger",
};

export function OrderStatusBadge({ status }: { status: PurchaseOrderStatus }) {
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full border border-border-strong px-2 py-0.5 text-xs font-medium text-text">
      <span aria-hidden="true" className={`h-2 w-2 rounded-full ${DOT[status]}`} />
      {t(STATUS_KEYS[status])}
    </span>
  );
}

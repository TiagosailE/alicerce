import { t } from "../../i18n";
import type { TitleStatus } from "./api";
import { TITLE_STATUS_KEYS } from "./financeLabels";

// The text says the status; the dot repeats it in color, so the meaning never
// rests on color alone (same treatment as an order's status).
const DOT: Record<TitleStatus, string> = {
  open: "bg-info",
  cancelled: "bg-danger",
};

export function TitleStatusBadge({ status }: { status: TitleStatus }) {
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full border border-border-strong px-2 py-0.5 text-xs font-medium text-text">
      <span aria-hidden="true" className={`h-2 w-2 rounded-full ${DOT[status]}`} />
      {t(TITLE_STATUS_KEYS[status])}
    </span>
  );
}

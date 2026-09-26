import type { MessageKey } from "../../i18n";
import type { TitleStatus } from "./api";

// A record over the enum, so a status the API adds fails the build until it has a label.
export const TITLE_STATUS_KEYS: Record<TitleStatus, MessageKey> = {
  open: "finance.statusOpen",
  cancelled: "finance.statusCancelled",
};

export const TITLE_STATUSES = Object.keys(TITLE_STATUS_KEYS) as TitleStatus[];

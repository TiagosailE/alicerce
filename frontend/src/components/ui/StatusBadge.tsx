import { t } from "../../i18n";

export function StatusBadge({ active }: { active: boolean }) {
  return (
    <span
      className={`rounded-full px-2 py-0.5 text-xs font-medium ${
        active ? "bg-success/15 text-success" : "bg-text-muted/15 text-text-muted"
      }`}
    >
      {active ? t("common.statusActive") : t("common.statusInactive")}
    </span>
  );
}

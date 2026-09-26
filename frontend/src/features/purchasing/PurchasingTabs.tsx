import { NavLink } from "react-router-dom";
import { t } from "../../i18n";

function tabClass({ isActive }: { isActive: boolean }): string {
  return `-mb-px border-b-2 px-3 py-2 text-sm ${isActive ? "border-accent text-text" : "border-transparent text-text-muted hover:text-text"}`;
}

/** The two lists of the purchasing area, orders and receipts. The current one is
 * marked by the link itself, which a screen reader announces as the current page. */
export function PurchasingTabs() {
  return (
    <nav
      aria-label={t("purchasing.tabsLabel")}
      className="mb-5 flex gap-1 border-b border-border-subtle"
    >
      <NavLink to="/compras" end className={tabClass}>
        {t("purchasing.tabOrders")}
      </NavLink>
      <NavLink to="/recebimentos" className={tabClass}>
        {t("purchasing.tabReceipts")}
      </NavLink>
    </nav>
  );
}

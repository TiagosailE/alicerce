import { NavLink } from "react-router-dom";
import { t } from "../../i18n";

const tabClass = ({ isActive }: { isActive: boolean }) =>
  `-mb-px border-b-2 px-3 py-2 text-sm ${isActive ? "border-accent font-medium text-text" : "border-transparent text-text-muted hover:text-text"}`;

/** The two sections of the stock area: the position and the ledger. */
export function StockTabs() {
  return (
    <nav
      aria-label={t("stock.tabsLabel")}
      className="mb-4 flex gap-1 border-b border-border-subtle"
    >
      <NavLink to="/estoque" end className={tabClass}>
        {t("stock.tabBalances")}
      </NavLink>
      <NavLink to="/estoque/movimentacoes" className={tabClass}>
        {t("stock.tabMovements")}
      </NavLink>
    </nav>
  );
}

import type { ReactNode } from "react";
import { Link, NavLink, matchPath, useLocation } from "react-router-dom";
import { BrandMark } from "../ui/BrandMark";
import { Button } from "../ui/Button";
import { Spinner } from "../ui/Spinner";
import { ThemeToggle } from "../ui/ThemeToggle";
import { initials } from "../../lib/initials";
import { t } from "../../i18n";
import { useSignOut } from "../../features/identity/api";

export function AppShell({
  organizationName,
  userName,
  canManageMembers,
  canViewPurchasing,
  canViewPayables,
  children,
}: {
  organizationName: string;
  userName: string;
  canManageMembers: boolean;
  canViewPurchasing: boolean;
  canViewPayables: boolean;
  children: ReactNode;
}) {
  const signOut = useSignOut();
  // The stock area is two pages (/estoque and /estoque/movimentacoes) that
  // share a nav link, while products and warehouses live under the same
  // /estoque prefix and have their own: a prefix match would light up all of
  // them, so the link is active only for the stock area's own two paths.
  const { pathname } = useLocation();
  const stockActive =
    matchPath({ path: "/estoque", end: true }, pathname) !== null ||
    matchPath({ path: "/estoque/movimentacoes", end: false }, pathname) !== null;
  // Purchasing is orders and receipts, two areas that share one nav link.
  const purchasingActive =
    matchPath({ path: "/compras", end: false }, pathname) !== null ||
    matchPath({ path: "/recebimentos", end: false }, pathname) !== null;

  return (
    <div className="flex min-h-screen flex-col bg-surface">
      <header className="flex h-12 items-center gap-3 border-b border-border-subtle bg-surface-raised px-4">
        <div className="flex shrink-0 items-center gap-2 font-display text-text">
          <BrandMark />
          {t("app.name")}
        </div>
        <span className="ml-2 min-w-0 truncate text-sm font-medium text-text">
          {organizationName}
        </span>
        {/* min-w-0 lets this shrink below its content width inside the flex
            row (a flex item's default min-width is auto, not 0); without it,
            three nav links plus a long organization name could push the
            sign-out button off screen with no way to reach it. */}
        <nav className="ml-4 flex min-w-0 items-center gap-3 overflow-x-auto text-sm">
          <Link
            to="/estoque"
            className={`shrink-0 rounded-md px-2 py-1 ${stockActive ? "bg-row-selected text-text" : "text-text-muted hover:bg-row-hover hover:text-text"}`}
            aria-current={stockActive ? "page" : undefined}
          >
            {t("shell.navStock")}
          </Link>
          <NavLink
            to="/estoque/produtos"
            className={({ isActive }) =>
              `shrink-0 rounded-md px-2 py-1 ${isActive ? "bg-row-selected text-text" : "text-text-muted hover:bg-row-hover hover:text-text"}`
            }
          >
            {t("shell.navProducts")}
          </NavLink>
          <NavLink
            to="/estoque/depositos"
            className={({ isActive }) =>
              `shrink-0 rounded-md px-2 py-1 ${isActive ? "bg-row-selected text-text" : "text-text-muted hover:bg-row-hover hover:text-text"}`
            }
          >
            {t("shell.navWarehouses")}
          </NavLink>
          {canViewPurchasing && (
            <Link
              to="/compras"
              className={`shrink-0 rounded-md px-2 py-1 ${purchasingActive ? "bg-row-selected text-text" : "text-text-muted hover:bg-row-hover hover:text-text"}`}
              aria-current={purchasingActive ? "page" : undefined}
            >
              {t("shell.navPurchasing")}
            </Link>
          )}
          {canViewPayables && (
            <NavLink
              to="/financeiro/contas-a-pagar"
              className={({ isActive }) =>
                `shrink-0 rounded-md px-2 py-1 ${isActive ? "bg-row-selected text-text" : "text-text-muted hover:bg-row-hover hover:text-text"}`
              }
            >
              {t("shell.navPayables")}
            </NavLink>
          )}
          <NavLink
            to="/parceiros"
            className={({ isActive }) =>
              `shrink-0 rounded-md px-2 py-1 ${isActive ? "bg-row-selected text-text" : "text-text-muted hover:bg-row-hover hover:text-text"}`
            }
          >
            {t("shell.navPartners")}
          </NavLink>
          {canManageMembers && (
            <NavLink
              to="/membros"
              className={({ isActive }) =>
                `shrink-0 rounded-md px-2 py-1 ${isActive ? "bg-row-selected text-text" : "text-text-muted hover:bg-row-hover hover:text-text"}`
              }
            >
              {t("shell.navMembers")}
            </NavLink>
          )}
        </nav>
        <div className="ml-auto flex shrink-0 items-center gap-3">
          <ThemeToggle />
          <div className="flex items-center gap-2 text-sm text-text">
            <span
              aria-hidden="true"
              className="grid h-6.5 w-6.5 place-items-center rounded-full bg-idle/20 text-xs font-bold"
            >
              {initials(userName)}
            </span>
            {userName}
          </div>
          <Button
            variant="quiet"
            onClick={() => {
              signOut.mutate();
            }}
            disabled={signOut.isPending}
          >
            {signOut.isPending && <Spinner />}
            {t("shell.signOut")}
          </Button>
        </div>
      </header>
      <main className="min-w-0 flex-1 p-5">{children}</main>
    </div>
  );
}

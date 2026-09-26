import { Navigate, Route, Routes } from "react-router-dom";
import { AppShell } from "./components/shell/AppShell";
import { Spinner } from "./components/ui/Spinner";
import { PartnerDetailScreen } from "./features/catalog/PartnerDetailScreen";
import { PartnersScreen } from "./features/catalog/PartnersScreen";
import { ProductDetailScreen } from "./features/catalog/ProductDetailScreen";
import { ProductsScreen } from "./features/catalog/ProductsScreen";
import { HomeScreen } from "./features/home/HomeScreen";
import { useSession } from "./features/identity/api";
import { MembersScreen } from "./features/identity/MembersScreen";
import { StockMovementsScreen } from "./features/inventory/StockMovementsScreen";
import { StockScreen } from "./features/inventory/StockScreen";
import { WarehousesScreen } from "./features/inventory/WarehousesScreen";
import {
  EditPurchaseOrderScreen,
  NewPurchaseOrderScreen,
} from "./features/purchasing/PurchaseOrderFormScreen";
import { PurchaseOrderDetailScreen } from "./features/purchasing/PurchaseOrderDetailScreen";
import { PurchaseOrdersScreen } from "./features/purchasing/PurchaseOrdersScreen";
import { SignInScreen } from "./features/identity/SignInScreen";
import { t } from "./i18n";

export function App() {
  const session = useSession();

  if (session.isPending) {
    return (
      <main className="grid min-h-screen place-items-center bg-canvas">
        <div role="status" className="flex items-center gap-2 text-text-muted">
          <Spinner />
          <h1 className="font-display text-lg">{t("app.name")}</h1>
        </div>
      </main>
    );
  }

  if (session.isError) {
    return (
      <main className="grid min-h-screen place-items-center bg-canvas px-4">
        <div className="text-center">
          <h1 className="font-display mb-3 text-lg text-text">{t("app.name")}</h1>
          <p role="alert" className="mb-3 text-sm text-danger">
            {t("app.loadError")}
          </p>
          <button
            type="button"
            onClick={() => {
              void session.refetch();
            }}
            disabled={session.isFetching}
            className="inline-flex items-center gap-2 text-sm text-accent underline underline-offset-2 disabled:cursor-not-allowed disabled:opacity-45"
          >
            {session.isFetching && <Spinner />}
            {t("app.retry")}
          </button>
        </div>
      </main>
    );
  }

  const { user, membership } = session.data;
  const authenticated = Boolean(user && membership);
  // Mirrors Identity::Capabilities.manage_members? (backend-enforced; this
  // only decides what the SPA offers, never what it accepts).
  const canManageMembers = Boolean(
    user &&
    membership &&
    !user.demo &&
    (membership.role === "owner" || membership.role === "admin"),
  );
  // Mirrors Identity::Capabilities.manage_master_data? (ADR 0008: owner,
  // admin and purchasing write master data; every role, demo included,
  // can read it, so there is no separate "can view" boolean here, only
  // whether the create/edit form or a read-only view renders).
  const canManageMasterData = Boolean(
    user &&
    membership &&
    (membership.role === "owner" ||
      membership.role === "admin" ||
      membership.role === "purchasing"),
  );

  // Mirrors Identity::Capabilities.adjust_stock? (ADR 0016: owner, admin and
  // purchasing record adjustments; every role reads the position and the
  // ledger). Same UX-only rule as above: the API decides.
  const canAdjustStock = canManageMasterData;
  // Mirrors Identity::Capabilities.view_stock_movements? (every role but sales).
  const canViewLedger = Boolean(membership && membership.role !== "sales");
  // Mirrors Identity::Capabilities.view_purchasing? (ADR 0017: owner, admin,
  // purchasing, finance and read_only read purchase orders) and
  // manage_purchasing? (owner, admin and purchasing write them). UX only: the
  // API decides. Not derived from the ledger's rule: the two may diverge.
  const canViewPurchasing = Boolean(
    membership &&
    (membership.role === "owner" ||
      membership.role === "admin" ||
      membership.role === "purchasing" ||
      membership.role === "finance" ||
      membership.role === "read_only"),
  );
  const canManagePurchasing = canManageMasterData;

  return (
    <Routes>
      <Route
        path="/entrar"
        element={authenticated ? <Navigate to="/" replace /> : <SignInScreen />}
      />
      <Route
        path="/*"
        element={
          authenticated && user && membership ? (
            <AppShell
              organizationName={membership.organization.name}
              userName={user.name}
              canManageMembers={canManageMembers}
              canViewPurchasing={canViewPurchasing}
            >
              <Routes>
                <Route path="/" element={<HomeScreen userName={user.name} />} />
                {canManageMembers && (
                  <Route
                    path="/membros"
                    element={
                      <MembersScreen currentRole={membership.role} currentUserId={user.id} />
                    }
                  />
                )}
                <Route
                  path="/estoque"
                  element={<StockScreen canAdjust={canAdjustStock} canViewLedger={canViewLedger} />}
                />
                {canViewLedger && (
                  <Route path="/estoque/movimentacoes" element={<StockMovementsScreen />} />
                )}
                <Route
                  path="/estoque/produtos"
                  element={<ProductsScreen canManage={canManageMasterData} />}
                />
                <Route
                  path="/estoque/produtos/:id"
                  element={<ProductDetailScreen canManage={canManageMasterData} />}
                />
                <Route
                  path="/estoque/depositos"
                  element={<WarehousesScreen canManage={canManageMasterData} />}
                />
                {canViewPurchasing && (
                  <>
                    <Route
                      path="/compras"
                      element={<PurchaseOrdersScreen canManage={canManagePurchasing} />}
                    />
                    {canManagePurchasing && (
                      <>
                        <Route path="/compras/novo" element={<NewPurchaseOrderScreen />} />
                        <Route path="/compras/:id/editar" element={<EditPurchaseOrderScreen />} />
                      </>
                    )}
                    <Route
                      path="/compras/:id"
                      element={<PurchaseOrderDetailScreen canManage={canManagePurchasing} />}
                    />
                  </>
                )}
                <Route
                  path="/parceiros"
                  element={<PartnersScreen canManage={canManageMasterData} />}
                />
                <Route
                  path="/parceiros/:id"
                  element={<PartnerDetailScreen canManage={canManageMasterData} />}
                />
                <Route path="*" element={<Navigate to="/" replace />} />
              </Routes>
            </AppShell>
          ) : (
            <Navigate to="/entrar" replace />
          )
        }
      />
    </Routes>
  );
}

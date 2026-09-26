import { useEffect, useId, useRef, useState } from "react";
import { Button } from "../../components/ui/Button";
import { PaginationControls } from "../../components/ui/PaginationControls";
import { SectionError } from "../../components/ui/SectionError";
import { SectionLoading } from "../../components/ui/SectionLoading";
import { formatMoneyCents, formatQuantity, formatUnitCost } from "../../lib/format";
import { t } from "../../i18n";
import { useStockBalances, useWarehouseOptions } from "./api";
import { StockAdjustmentForm } from "./StockAdjustmentForm";
import { StockTabs } from "./StockTabs";
import { WithheldValue } from "./WithheldValue";

/** The stock position, one row per product and warehouse, and the count
 * adjustment form for whoever may record one (ADR 0016). */
export function StockScreen({
  canAdjust,
  canViewLedger,
}: {
  canAdjust: boolean;
  canViewLedger: boolean;
}) {
  const [page, setPage] = useState(1);
  const [warehouseId, setWarehouseId] = useState("");
  const [q, setQ] = useState("");
  const [adjustOpen, setAdjustOpen] = useState(false);
  const adjustHeadingRef = useRef<HTMLHeadingElement>(null);
  const adjustButtonRef = useRef<HTMLButtonElement>(null);
  const isFirstToggle = useRef(true);
  const warehouses = useWarehouseOptions();
  const balances = useStockBalances(page, {
    warehouseId: warehouseId ? Number(warehouseId) : undefined,
    q: q || undefined,
  });
  const warehouseFilterId = useId();
  const searchId = useId();
  const filtered = warehouseId !== "" || q !== "";

  // The button that opens the panel is replaced by it, so focus is moved on
  // purpose: to the panel's heading when it opens, back to the button when it
  // closes, the same as the products screen's create panel.
  useEffect(() => {
    if (isFirstToggle.current) {
      isFirstToggle.current = false;
      return;
    }
    if (adjustOpen) {
      adjustHeadingRef.current?.focus();
    } else {
      adjustButtonRef.current?.focus();
    }
  }, [adjustOpen]);

  function clearFilters() {
    setPage(1);
    setWarehouseId("");
    setQ("");
  }

  return (
    <div>
      <div className="mb-3 flex items-center justify-between">
        <h1 className="font-display text-2xl text-text">{t("stock.title")}</h1>
        {canAdjust && !adjustOpen && (
          <Button
            ref={adjustButtonRef}
            variant="primary"
            onClick={() => {
              setAdjustOpen(true);
            }}
          >
            {t("stock.adjustButton")}
          </Button>
        )}
      </div>
      <StockTabs showMovements={canViewLedger} />

      {adjustOpen && (
        <div className="mb-5 rounded-md border border-border-subtle bg-surface-raised p-4">
          <h2
            ref={adjustHeadingRef}
            tabIndex={-1}
            className="font-display mb-3 text-base text-text outline-none"
          >
            {t("stock.adjustTitle")}
          </h2>
          {warehouses.isPending && <SectionLoading label={t("stock.adjustLoading")} />}
          {warehouses.isError && (
            <SectionError
              message={t("stock.adjustLoadError")}
              error={warehouses.error}
              onRetry={() => {
                void warehouses.refetch();
              }}
            />
          )}
          {warehouses.data && (
            <StockAdjustmentForm
              warehouses={warehouses.data.data}
              onClose={() => {
                setAdjustOpen(false);
              }}
            />
          )}
        </div>
      )}

      <div className="mb-4 flex flex-wrap items-end gap-3">
        <div>
          <label htmlFor={warehouseFilterId} className="mb-1 block text-sm font-medium text-text">
            {t("stock.filterWarehouseLabel")}
          </label>
          <select
            id={warehouseFilterId}
            value={warehouseId}
            onChange={(event) => {
              setPage(1);
              setWarehouseId(event.target.value);
            }}
            className="h-9 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          >
            <option value="">{t("stock.filterWarehouseAll")}</option>
            {warehouses.data?.data.map((warehouse) => (
              <option key={warehouse.id} value={warehouse.id}>
                {warehouse.name}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor={searchId} className="mb-1 block text-sm font-medium text-text">
            {t("stock.searchLabel")}
          </label>
          <input
            id={searchId}
            type="search"
            placeholder={t("stock.searchPlaceholder")}
            value={q}
            onChange={(event) => {
              setPage(1);
              setQ(event.target.value);
            }}
            className="h-9 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          />
        </div>
      </div>

      {balances.isPending && <SectionLoading label={t("stock.loading")} />}
      {balances.isError && (
        <SectionError
          message={t("stock.loadError")}
          error={balances.error}
          onRetry={() => {
            void balances.refetch();
          }}
        />
      )}
      {balances.data?.data.length === 0 && (
        <div className="text-sm text-text-muted">
          <p className="mb-2">
            {filtered ? t("stock.balancesEmptyFiltered") : t("stock.balancesEmptyNothing")}
          </p>
          {filtered && (
            <Button variant="default" onClick={clearFilters}>
              {t("stock.clearFilters")}
            </Button>
          )}
          {!filtered && canAdjust && !adjustOpen && (
            <Button
              variant="primary"
              onClick={() => {
                setAdjustOpen(true);
              }}
            >
              {t("stock.registerOpening")}
            </Button>
          )}
        </div>
      )}
      {balances.data && balances.data.data.length > 0 && (
        <div>
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-sm">
              <caption className="sr-only">{t("stock.tabBalances")}</caption>
              <thead>
                <tr className="border-b border-border-subtle text-left text-text-muted">
                  <th className="py-2 pr-3 font-medium">{t("stock.tableProduct")}</th>
                  <th className="py-2 pr-3 font-medium">{t("stock.tableWarehouse")}</th>
                  <th className="py-2 pr-3 text-right font-medium">{t("stock.tableOnHand")}</th>
                  <th className="py-2 pr-3 text-right font-medium">{t("stock.tableReserved")}</th>
                  <th className="py-2 pr-3 text-right font-medium">{t("stock.tableAvailable")}</th>
                  <th className="py-2 pr-3 text-right font-medium">{t("stock.tableValue")}</th>
                  <th className="py-2 text-right font-medium">{t("stock.tableLastCost")}</th>
                </tr>
              </thead>
              <tbody>
                {balances.data.data.map((balance) => {
                  const unit = balance.product.stock_unit.code;
                  return (
                    <tr
                      key={balance.id}
                      className="border-b border-border-subtle last:border-0 hover:bg-row-hover"
                    >
                      <td className="py-2 pr-3">
                        <span className="text-text">{balance.product.name}</span>{" "}
                        <span className="num text-xs text-text-muted">{balance.product.sku}</span>
                      </td>
                      <td className="py-2 pr-3 text-text-muted">{balance.warehouse.name}</td>
                      <td className="num py-2 pr-3 text-right text-text">
                        {formatQuantity(balance.on_hand)} {unit}
                      </td>
                      <td className="num py-2 pr-3 text-right text-text-muted">
                        {formatQuantity(balance.reserved)} {unit}
                      </td>
                      <td
                        className={`num py-2 pr-3 text-right ${balance.available.startsWith("-") ? "font-medium text-danger" : "text-text"}`}
                      >
                        {formatQuantity(balance.available)} {unit}
                      </td>
                      <td className="num py-2 pr-3 text-right text-text">
                        {balance.value_cents === null ? (
                          <WithheldValue />
                        ) : (
                          formatMoneyCents(balance.value_cents)
                        )}
                      </td>
                      <td className="num py-2 text-right text-text-muted">
                        {balance.last_unit_cost_cents === null ? (
                          <WithheldValue />
                        ) : (
                          formatUnitCost(balance.last_unit_cost_cents)
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <PaginationControls
            page={balances.data.meta.page}
            perPage={balances.data.meta.per_page}
            total={balances.data.meta.total}
            onPage={setPage}
          />
        </div>
      )}
    </div>
  );
}

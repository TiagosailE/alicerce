import { useId, useState } from "react";
import { Button } from "../../components/ui/Button";
import { PaginationControls } from "../../components/ui/PaginationControls";
import { SectionError } from "../../components/ui/SectionError";
import { SectionLoading } from "../../components/ui/SectionLoading";
import {
  formatDateTime,
  formatMoneyCents,
  formatQuantity,
  formatSignedQuantity,
} from "../../lib/format";
import { t } from "../../i18n";
import { type AdjustmentReason, useStockMovements, useWarehouseOptions } from "./api";
import { StockTabs } from "./StockTabs";
import { WithheldValue } from "./WithheldValue";
import { ADJUSTMENT_REASONS, REASON_KEYS } from "./stockLabels";

/** The movement ledger, newest first (ADR 0016): every row a signed quantity
 * and value, and the balance right after it. Read-only by design. */
export function StockMovementsScreen() {
  const [page, setPage] = useState(1);
  const [warehouseId, setWarehouseId] = useState("");
  const [reason, setReason] = useState("");
  const warehouses = useWarehouseOptions();
  const movements = useStockMovements(page, {
    warehouseId: warehouseId ? Number(warehouseId) : undefined,
    reason: reason ? (reason as AdjustmentReason) : undefined,
  });
  const warehouseFilterId = useId();
  const reasonFilterId = useId();
  const filtered = warehouseId !== "" || reason !== "";

  return (
    <div>
      <h1 className="font-display mb-3 text-2xl text-text">{t("stock.title")}</h1>
      <StockTabs />

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
          <label htmlFor={reasonFilterId} className="mb-1 block text-sm font-medium text-text">
            {t("stock.filterReasonLabel")}
          </label>
          <select
            id={reasonFilterId}
            value={reason}
            onChange={(event) => {
              setPage(1);
              setReason(event.target.value);
            }}
            className="h-9 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          >
            <option value="">{t("stock.filterReasonAll")}</option>
            {ADJUSTMENT_REASONS.map((value) => (
              <option key={value} value={value}>
                {t(REASON_KEYS[value])}
              </option>
            ))}
          </select>
        </div>
      </div>

      {movements.isPending && <SectionLoading label={t("stock.loading")} />}
      {movements.isError && (
        <SectionError
          message={t("stock.loadError")}
          error={movements.error}
          onRetry={() => {
            void movements.refetch();
          }}
        />
      )}
      {movements.data?.data.length === 0 && (
        <div className="text-sm text-text-muted">
          <p className="mb-2">
            {filtered ? t("stock.movementsEmptyFiltered") : t("stock.movementsEmptyNothing")}
          </p>
          {filtered && (
            <Button
              variant="default"
              onClick={() => {
                setPage(1);
                setWarehouseId("");
                setReason("");
              }}
            >
              {t("stock.clearFilters")}
            </Button>
          )}
        </div>
      )}
      {movements.data && movements.data.data.length > 0 && (
        <div>
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-sm">
              <caption className="sr-only">{t("stock.tabMovements")}</caption>
              <thead>
                <tr className="border-b border-border-subtle text-left text-text-muted">
                  <th className="py-2 pr-3 font-medium">{t("stock.tableWhen")}</th>
                  <th className="py-2 pr-3 font-medium">{t("stock.tableProduct")}</th>
                  <th className="py-2 pr-3 font-medium">{t("stock.tableWarehouse")}</th>
                  <th className="py-2 pr-3 font-medium">{t("stock.tableReason")}</th>
                  <th className="py-2 pr-3 text-right font-medium">{t("stock.tableQuantity")}</th>
                  <th className="py-2 pr-3 text-right font-medium">{t("stock.tableValueMoved")}</th>
                  <th className="py-2 pr-3 text-right font-medium">
                    {t("stock.tableBalanceAfter")}
                  </th>
                  <th className="py-2 font-medium">{t("stock.tableActor")}</th>
                </tr>
              </thead>
              <tbody>
                {movements.data.data.map((movement) => {
                  const unit = movement.product.stock_unit.code;
                  return (
                    <tr
                      key={movement.id}
                      className="border-b border-border-subtle last:border-0 hover:bg-row-hover"
                    >
                      <td className="num py-2 pr-3 text-text-muted">
                        {formatDateTime(movement.created_at)}
                      </td>
                      <td className="py-2 pr-3">
                        <span className="text-text">{movement.product.name}</span>{" "}
                        <span className="num text-xs text-text-muted">{movement.product.sku}</span>
                      </td>
                      <td className="py-2 pr-3 text-text-muted">{movement.warehouse.name}</td>
                      <td className="py-2 pr-3 text-text-muted">
                        {movement.reason ? t(REASON_KEYS[movement.reason]) : ""}
                      </td>
                      <td className="num py-2 pr-3 text-right text-text">
                        {formatSignedQuantity(movement.quantity)} {unit}
                      </td>
                      <td className="num py-2 pr-3 text-right text-text">
                        {movement.value_cents === null ? (
                          <WithheldValue />
                        ) : (
                          formatMoneyCents(movement.value_cents)
                        )}
                      </td>
                      <td className="num py-2 pr-3 text-right text-text-muted">
                        {formatQuantity(movement.on_hand_after)} {unit}
                      </td>
                      <td className="py-2 text-text-muted">{movement.actor.name}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <PaginationControls
            page={movements.data.meta.page}
            perPage={movements.data.meta.per_page}
            total={movements.data.meta.total}
            onPage={setPage}
          />
        </div>
      )}
    </div>
  );
}

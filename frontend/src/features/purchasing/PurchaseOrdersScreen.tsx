import { useId } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { Button, buttonClass } from "../../components/ui/Button";
import { PaginationControls } from "../../components/ui/PaginationControls";
import { SectionError } from "../../components/ui/SectionError";
import { SectionLoading } from "../../components/ui/SectionLoading";
import { formatDateTime, formatMoneyCents } from "../../lib/format";
import { t, tf } from "../../i18n";
import { usePurchaseOrders } from "./api";
import { OrderStatusBadge } from "./OrderStatusBadge";
import { ORDER_STATUSES, STATUS_KEYS } from "./purchasingLabels";

const selectClass =
  "h-9 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus";

/** The page in the address: a whole number from 1, anything else is the first. */
function pageFromParam(value: string | null): number {
  return value !== null && /^[1-9]\d{0,8}$/.test(value) ? Number(value) : 1;
}

/** Purchase orders, newest first (ADR 0017). Every amount is what the API
 * stored; the list never adds or rounds anything. The page and the filters live
 * in the address, so coming back from an order lands where the person left, and
 * the view can be shared. */
export function PurchaseOrdersScreen({ canManage }: { canManage: boolean }) {
  const [params, setParams] = useSearchParams();
  const page = pageFromParam(params.get("page"));
  const status = ORDER_STATUSES.find((value) => value === params.get("status"));
  const q = params.get("q") ?? "";
  const orders = usePurchaseOrders(page, { status, q: q.trim() || undefined });
  const statusId = useId();
  const searchId = useId();
  const filtered = status !== undefined || q.trim() !== "";

  function change(next: { page?: number; status?: string; q?: string }) {
    const merged = { page, status: status ?? "", q, ...next };
    const query = new URLSearchParams();
    if (merged.page > 1) query.set("page", String(merged.page));
    if (merged.status) query.set("status", merged.status);
    if (merged.q) query.set("q", merged.q);
    setParams(query, { replace: true });
  }

  const total = orders.data?.meta.total;

  return (
    <div>
      <div className="mb-5 flex items-center justify-between">
        <h1 className="font-display text-2xl text-text">{t("purchasing.title")}</h1>
        {canManage && (
          <Link to="/compras/novo" className={buttonClass("primary")}>
            {t("purchasing.newButton")}
          </Link>
        )}
      </div>

      <div className="mb-4 flex flex-wrap items-end gap-3">
        <div>
          <label htmlFor={statusId} className="mb-1 block text-sm font-medium text-text">
            {t("purchasing.filterStatusLabel")}
          </label>
          <select
            id={statusId}
            value={status ?? ""}
            onChange={(event) => {
              change({ page: 1, status: event.target.value });
            }}
            className={selectClass}
          >
            <option value="">{t("purchasing.filterStatusAll")}</option>
            {ORDER_STATUSES.map((value) => (
              <option key={value} value={value}>
                {t(STATUS_KEYS[value])}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor={searchId} className="mb-1 block text-sm font-medium text-text">
            {t("purchasing.searchLabel")}
          </label>
          <input
            id={searchId}
            type="search"
            placeholder={t("purchasing.searchPlaceholder")}
            value={q}
            onChange={(event) => {
              change({ page: 1, q: event.target.value });
            }}
            className={selectClass}
          />
        </div>
      </div>

      <div aria-busy={orders.isFetching}>
        <p role="status" className="sr-only">
          {total !== undefined &&
            !orders.isPlaceholderData &&
            (total === 1
              ? t("purchasing.resultCountOne")
              : tf("purchasing.resultCountMany", { count: String(total) }))}
        </p>
        {orders.isPending && <SectionLoading label={t("purchasing.loading")} />}
        {orders.isError && (
          <SectionError
            message={t("purchasing.loadError")}
            error={orders.error}
            onRetry={() => {
              void orders.refetch();
            }}
          />
        )}
        {orders.data?.data.length === 0 && !orders.isPlaceholderData && (
          <div className="text-sm text-text-muted">
            <p className="mb-2">
              {filtered
                ? t("purchasing.emptyFiltered")
                : canManage
                  ? t("purchasing.emptyNothing")
                  : t("purchasing.emptyNothingViewer")}
            </p>
            {filtered && (
              <Button
                onClick={() => {
                  change({ page: 1, status: "", q: "" });
                }}
              >
                {t("purchasing.clearFilters")}
              </Button>
            )}
            {!filtered && canManage && (
              <Link to="/compras/novo" className={buttonClass("primary")}>
                {t("purchasing.newButton")}
              </Link>
            )}
          </div>
        )}
        {orders.data && orders.data.data.length > 0 && (
          <div>
            <div className="overflow-x-auto">
              <table className="w-full border-collapse text-sm">
                <caption className="sr-only">{t("purchasing.title")}</caption>
                <thead>
                  <tr className="border-b border-border-subtle text-left text-text-muted">
                    <th className="py-2 pr-3 font-medium">{t("purchasing.tableNumber")}</th>
                    <th className="py-2 pr-3 font-medium">{t("purchasing.tableSupplier")}</th>
                    <th className="py-2 pr-3 font-medium">{t("purchasing.tableStatus")}</th>
                    <th className="py-2 pr-3 font-medium">{t("purchasing.tableCreated")}</th>
                    <th className="py-2 text-right font-medium">{t("purchasing.tableTotal")}</th>
                  </tr>
                </thead>
                <tbody>
                  {orders.data.data.map((order) => (
                    <tr
                      key={order.id}
                      className="border-b border-border-subtle last:border-0 hover:bg-row-hover"
                    >
                      <td className="num py-2 pr-3">
                        <Link
                          to={`/compras/${String(order.id)}`}
                          className="text-accent underline-offset-2 hover:underline"
                        >
                          {order.number}
                        </Link>
                      </td>
                      <td className="py-2 pr-3 text-text">{order.supplier.name}</td>
                      <td className="py-2 pr-3">
                        <OrderStatusBadge status={order.status} />
                      </td>
                      <td className="num py-2 pr-3 text-text-muted">
                        {formatDateTime(order.created_at)}
                      </td>
                      <td className="num py-2 text-right text-text">
                        {formatMoneyCents(order.total_cents)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <PaginationControls
              page={orders.data.meta.page}
              perPage={orders.data.meta.per_page}
              total={orders.data.meta.total}
              onPage={(next) => {
                change({ page: next });
              }}
            />
          </div>
        )}
      </div>
    </div>
  );
}

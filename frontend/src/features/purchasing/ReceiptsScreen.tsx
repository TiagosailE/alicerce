import { useId, useRef } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { Button, buttonClass } from "../../components/ui/Button";
import { PageGone } from "../../components/ui/PageGone";
import { PaginationControls } from "../../components/ui/PaginationControls";
import { SectionError } from "../../components/ui/SectionError";
import { SectionLoading } from "../../components/ui/SectionLoading";
import { formatDate, formatMoneyCents } from "../../lib/format";
import { t, tf } from "../../i18n";
import { idFromParam } from "./purchasingLabels";
import { PurchasingTabs } from "./PurchasingTabs";
import { useReceipts } from "./receiptsApi";

const fieldClass =
  "h-9 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus";

function pageFromParam(value: string | null): number {
  return value !== null && /^[1-9]\d{0,8}$/.test(value) ? Number(value) : 1;
}

/** Receipts, newest first (ADR 0017). What each came to is what the API stored.
 * The page, the search and the order they are narrowed to live in the address,
 * so the view can be shared and coming back lands where the person left. */
export function ReceiptsScreen({ canManage }: { canManage: boolean }) {
  const [params, setParams] = useSearchParams();
  const page = pageFromParam(params.get("page"));
  const q = params.get("q") ?? "";
  const orderId = idFromParam(params.get("order") ?? undefined) ?? undefined;
  const receipts = useReceipts(page, { q: q.trim() || undefined, orderId });
  const searchId = useId();
  const searchRef = useRef<HTMLInputElement>(null);
  const filtered = q.trim() !== "" || orderId !== undefined;
  // Narrowed to one order and nothing else: it simply has no receipts yet.
  const orderOnly = orderId !== undefined && q.trim() === "";

  function change(next: { page?: number; q?: string; order?: number | null }) {
    const merged = { page, q, order: orderId ?? null, ...next };
    const query = new URLSearchParams();
    if (merged.page > 1) query.set("page", String(merged.page));
    if (merged.q) query.set("q", merged.q);
    if (merged.order !== null) query.set("order", String(merged.order));
    setParams(query, { replace: true });
  }

  const list = receipts.data;
  const total = list?.meta.total;
  const settled = list !== undefined && !receipts.isPlaceholderData;
  // The API applies the offset unchecked: a page past the last one is an empty
  // list that still reports a total, which is not the same as having none.
  const pageGone = settled && list.data.length === 0 && list.meta.total > 0;
  const nothing = settled && list.meta.total === 0;

  return (
    <div>
      <h1 className="font-display mb-4 text-2xl text-text">{t("receipts.title")}</h1>
      <PurchasingTabs />

      <div className="mb-4 flex flex-wrap items-end gap-3">
        <div>
          <label htmlFor={searchId} className="mb-1 block text-sm font-medium text-text">
            {t("receipts.searchLabel")}
          </label>
          <input
            ref={searchRef}
            id={searchId}
            type="search"
            placeholder={t("receipts.searchPlaceholder")}
            value={q}
            onChange={(event) => {
              change({ page: 1, q: event.target.value });
            }}
            className={fieldClass}
          />
        </div>
        {orderId !== undefined && (
          <div className="flex items-center gap-2 text-sm text-text-muted">
            <span>{t("receipts.onlyOneOrder")}</span>
            <Button
              onClick={() => {
                change({ page: 1, order: null });
                searchRef.current?.focus();
              }}
            >
              {t("receipts.showAll")}
            </Button>
          </div>
        )}
      </div>

      <div aria-busy={receipts.isFetching}>
        <p role="status" className="sr-only">
          {total !== undefined &&
            !receipts.isPlaceholderData &&
            (total === 1
              ? t("receipts.resultCountOne")
              : tf("receipts.resultCountMany", { count: String(total) }))}
        </p>
        {receipts.isPending && <SectionLoading label={t("receipts.loading")} />}
        {receipts.isError && (
          <SectionError
            message={t("receipts.loadError")}
            error={receipts.error}
            onRetry={() => {
              void receipts.refetch();
            }}
          />
        )}
        {pageGone && (
          <PageGone
            onFirstPage={() => {
              change({ page: 1 });
            }}
          />
        )}
        {nothing && (
          <div className="text-sm text-text-muted">
            <p className="mb-2">
              {orderOnly
                ? t("receipts.emptyOrder")
                : filtered
                  ? t("receipts.emptyFiltered")
                  : canManage
                    ? t("receipts.emptyNothing")
                    : t("receipts.emptyNothingViewer")}
            </p>
            {orderOnly && (
              <Link to={`/compras/${String(orderId)}`} className={buttonClass("default")}>
                {t("receipts.backToOrder")}
              </Link>
            )}
            {filtered && !orderOnly && (
              <Button
                onClick={() => {
                  change({ page: 1, q: "", order: null });
                  searchRef.current?.focus();
                }}
              >
                {t("receipts.clearFilters")}
              </Button>
            )}
            {!filtered && canManage && (
              <Link to="/compras" className={buttonClass("default")}>
                {t("receipts.goToOrders")}
              </Link>
            )}
          </div>
        )}
        {receipts.data && receipts.data.data.length > 0 && (
          <div>
            <div className="overflow-x-auto">
              <table className="w-full border-collapse text-sm">
                <caption className="sr-only">{t("receipts.title")}</caption>
                <thead>
                  <tr className="border-b border-border-subtle text-left text-text-muted">
                    <th className="py-2 pr-3 font-medium">{t("receipts.tableNumber")}</th>
                    <th className="py-2 pr-3 font-medium">{t("receipts.tableOrder")}</th>
                    <th className="py-2 pr-3 font-medium">{t("receipts.tableSupplier")}</th>
                    <th className="py-2 pr-3 font-medium">{t("receipts.tableWarehouse")}</th>
                    <th className="py-2 pr-3 font-medium">{t("receipts.tableDate")}</th>
                    <th className="py-2 text-right font-medium">{t("receipts.tableTotal")}</th>
                  </tr>
                </thead>
                <tbody>
                  {receipts.data.data.map((receipt) => (
                    <tr
                      key={receipt.id}
                      className="border-b border-border-subtle last:border-0 hover:bg-row-hover"
                    >
                      <td className="num py-2 pr-3">
                        <Link
                          to={`/recebimentos/${String(receipt.id)}`}
                          className="text-accent underline-offset-2 hover:underline"
                        >
                          {receipt.number}
                        </Link>
                      </td>
                      <td className="num py-2 pr-3">
                        <Link
                          to={`/compras/${String(receipt.order.id)}`}
                          className="text-accent underline-offset-2 hover:underline"
                        >
                          {receipt.order.number}
                        </Link>
                      </td>
                      <td className="py-2 pr-3 text-text">{receipt.supplier.name}</td>
                      <td className="py-2 pr-3 text-text">{receipt.warehouse.name}</td>
                      <td className="num py-2 pr-3 text-text-muted">
                        {formatDate(receipt.received_on)}
                      </td>
                      <td className="num py-2 text-right text-text">
                        {formatMoneyCents(receipt.total_cents)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <PaginationControls
              page={receipts.data.meta.page}
              perPage={receipts.data.meta.per_page}
              total={receipts.data.meta.total}
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

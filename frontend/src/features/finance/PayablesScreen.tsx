import { Fragment, useId, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { Button } from "../../components/ui/Button";
import { PageGone } from "../../components/ui/PageGone";
import { PaginationControls } from "../../components/ui/PaginationControls";
import { SectionError } from "../../components/ui/SectionError";
import { SectionLoading } from "../../components/ui/SectionLoading";
import { formatDate, formatMoneyCents } from "../../lib/format";
import { t, tf } from "../../i18n";
import { type Title, usePayables } from "./api";
import { TITLE_STATUSES, TITLE_STATUS_KEYS } from "./financeLabels";
import { TitleStatusBadge } from "./TitleStatusBadge";

const fieldClass =
  "h-9 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus";

const COLUMNS = 7;

function pageFromParam(value: string | null): number {
  return value !== null && /^[1-9]\d{0,8}$/.test(value) ? Number(value) : 1;
}

/** Whose installments a control or a table holds, for a screen reader that
 * lists controls and tables apart from the row they sit in. */
function owner(title: Title): { supplier: string; number: string } {
  return { supplier: title.partner.name, number: String(title.receipt?.number ?? "") };
}

/** The installments of one payable, as the API stored them: what each is worth,
 * what has been settled and what is still open. Nothing is added up here. */
function InstallmentsTable({ title }: { title: Title }) {
  return (
    <table className="w-full border-collapse text-sm">
      <caption className="sr-only">
        {title.receipt
          ? tf("payables.installmentsCaption", owner(title))
          : tf("payables.installmentsCaptionNoReceipt", owner(title))}
      </caption>
      <thead>
        <tr className="border-b border-border-subtle text-left text-text-muted">
          <th className="py-1 pr-3 font-medium">{t("payables.colInstallment")}</th>
          <th className="py-1 pr-3 font-medium">{t("payables.colDueOn")}</th>
          <th className="py-1 pr-3 text-right font-medium">{t("payables.colAmount")}</th>
          <th className="py-1 pr-3 text-right font-medium">{t("payables.colSettled")}</th>
          <th className="py-1 text-right font-medium">{t("payables.colOpen")}</th>
        </tr>
      </thead>
      <tbody>
        {title.installments.map((installment) => (
          <tr key={installment.id} className="border-b border-border-subtle last:border-0">
            <td className="num py-1 pr-3 text-text">{installment.number}</td>
            <td className="num py-1 pr-3 text-text">{formatDate(installment.due_on)}</td>
            <td className="num py-1 pr-3 text-right text-text">
              {formatMoneyCents(installment.amount_cents)}
            </td>
            <td className="num py-1 pr-3 text-right text-text-muted">
              {formatMoneyCents(installment.settled_cents)}
            </td>
            <td className="num py-1 text-right text-text">
              {formatMoneyCents(installment.open_cents)}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

/** Payables, newest first (ADR 0017), for the roles that read them. Read-only:
 * every figure is what the API stored, and the page, the status and the search
 * live in the address so the view can be shared. */
export function PayablesScreen() {
  const [params, setParams] = useSearchParams();
  const page = pageFromParam(params.get("page"));
  const status = TITLE_STATUSES.find((value) => value === params.get("status"));
  const q = params.get("q") ?? "";
  const payables = usePayables(page, { status, q: q.trim() || undefined });
  const statusId = useId();
  const searchId = useId();
  const panelPrefix = useId();
  const searchRef = useRef<HTMLInputElement>(null);
  const [opened, setOpened] = useState<ReadonlySet<number>>(new Set());
  const filtered = status !== undefined || q.trim() !== "";

  function change(next: { page?: number; status?: string; q?: string }) {
    const merged = { page, status: status ?? "", q, ...next };
    const query = new URLSearchParams();
    if (merged.page > 1) query.set("page", String(merged.page));
    if (merged.status) query.set("status", merged.status);
    if (merged.q) query.set("q", merged.q);
    setParams(query, { replace: true });
  }

  function toggle(id: number) {
    setOpened((current) => {
      const next = new Set(current);
      if (!next.delete(id)) next.add(id);
      return next;
    });
  }

  const list = payables.data;
  const total = list?.meta.total;
  const settled = list !== undefined && !payables.isPlaceholderData;
  // The API applies the offset unchecked: a page past the last one is an empty
  // list that still reports a total, which is not the same as having none.
  const pageGone = settled && list.data.length === 0 && list.meta.total > 0;
  const nothing = settled && list.meta.total === 0;

  return (
    <div>
      <h1 className="font-display mb-2 text-2xl text-text">{t("payables.title")}</h1>
      <p className="mb-4 text-sm text-text-muted">{t("payables.intro")}</p>

      <div className="mb-4 flex flex-wrap items-end gap-3">
        <div>
          <label htmlFor={statusId} className="mb-1 block text-sm font-medium text-text">
            {t("payables.filterStatusLabel")}
          </label>
          <select
            id={statusId}
            value={status ?? ""}
            onChange={(event) => {
              change({ page: 1, status: event.target.value });
            }}
            className={fieldClass}
          >
            <option value="">{t("payables.filterStatusAll")}</option>
            {TITLE_STATUSES.map((value) => (
              <option key={value} value={value}>
                {t(TITLE_STATUS_KEYS[value])}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor={searchId} className="mb-1 block text-sm font-medium text-text">
            {t("payables.searchLabel")}
          </label>
          <input
            ref={searchRef}
            id={searchId}
            type="search"
            placeholder={t("payables.searchPlaceholder")}
            value={q}
            onChange={(event) => {
              change({ page: 1, q: event.target.value });
            }}
            className={fieldClass}
          />
        </div>
      </div>

      <div aria-busy={payables.isFetching}>
        <p role="status" className="sr-only">
          {total !== undefined &&
            !payables.isPlaceholderData &&
            (total === 1
              ? t("payables.resultCountOne")
              : tf("payables.resultCountMany", { count: String(total) }))}
        </p>
        {payables.isPending && <SectionLoading label={t("payables.loading")} />}
        {payables.isError && (
          <SectionError
            message={t("payables.loadError")}
            error={payables.error}
            onRetry={() => {
              void payables.refetch();
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
              {filtered ? t("payables.emptyFiltered") : t("payables.emptyNothing")}
            </p>
            {filtered && (
              <Button
                onClick={() => {
                  change({ page: 1, status: "", q: "" });
                  searchRef.current?.focus();
                }}
              >
                {t("payables.clearFilters")}
              </Button>
            )}
          </div>
        )}
        {list && list.data.length > 0 && (
          <div>
            <div className="overflow-x-auto">
              <table className="w-full border-collapse text-sm">
                <caption className="sr-only">{t("payables.title")}</caption>
                <thead>
                  <tr className="border-b border-border-subtle text-left text-text-muted">
                    <th className="py-2 pr-3 font-medium">{t("payables.tableSupplier")}</th>
                    <th className="py-2 pr-3 font-medium">{t("payables.tableReceipt")}</th>
                    <th className="py-2 pr-3 font-medium">{t("payables.tableStatus")}</th>
                    <th className="py-2 pr-3 text-right font-medium">{t("payables.tableTotal")}</th>
                    <th className="py-2 pr-3 text-right font-medium">
                      {t("payables.tableSettled")}
                    </th>
                    <th className="py-2 pr-3 text-right font-medium">{t("payables.tableOpen")}</th>
                    <th className="py-2 font-medium">{t("payables.tableInstallments")}</th>
                  </tr>
                </thead>
                <tbody>
                  {list.data.map((title) => {
                    const isOpen = opened.has(title.id);
                    const panelId = `${panelPrefix}-${String(title.id)}`;
                    const count = title.installments.length;
                    return (
                      <Fragment key={title.id}>
                        <tr
                          className={`align-top hover:bg-row-hover ${isOpen ? "" : "border-b border-border-subtle last:border-0"}`}
                        >
                          <td className="py-2 pr-3 text-text">{title.partner.name}</td>
                          <td className="num py-2 pr-3">
                            {title.receipt ? (
                              <Link
                                to={`/recebimentos/${String(title.receipt.id)}`}
                                aria-label={tf("payables.receiptLink", {
                                  number: String(title.receipt.number),
                                })}
                                className="text-accent underline-offset-2 hover:underline"
                              >
                                {title.receipt.number}
                              </Link>
                            ) : (
                              <span className="text-text-muted">{t("payables.noReceipt")}</span>
                            )}
                          </td>
                          <td className="py-2 pr-3">
                            <TitleStatusBadge status={title.status} />
                          </td>
                          <td className="num py-2 pr-3 text-right text-text">
                            {formatMoneyCents(title.total_cents)}
                          </td>
                          <td className="num py-2 pr-3 text-right text-text-muted">
                            {formatMoneyCents(title.settled_cents)}
                          </td>
                          <td className="num py-2 pr-3 text-right text-text">
                            {formatMoneyCents(title.open_cents)}
                          </td>
                          <td className="py-1">
                            <Button
                              variant="quiet"
                              aria-expanded={isOpen}
                              aria-controls={isOpen ? panelId : undefined}
                              onClick={() => {
                                toggle(title.id);
                              }}
                            >
                              <span aria-hidden="true">{isOpen ? "▾" : "▸"}</span>
                              <span>
                                {count === 1
                                  ? t("payables.installmentsOne")
                                  : tf("payables.installmentsMany", { count: String(count) })}{" "}
                                <span className="sr-only">
                                  {title.receipt
                                    ? tf("payables.installmentsOf", owner(title))
                                    : tf("payables.installmentsOfNoReceipt", owner(title))}
                                </span>
                              </span>
                            </Button>
                          </td>
                        </tr>
                        {isOpen && (
                          <tr id={panelId} className="border-b border-border-subtle last:border-0">
                            <td colSpan={COLUMNS} className="bg-surface-raised px-3 pb-3">
                              <InstallmentsTable title={title} />
                            </td>
                          </tr>
                        )}
                      </Fragment>
                    );
                  })}
                </tbody>
              </table>
            </div>
            <PaginationControls
              page={list.meta.page}
              perPage={list.meta.per_page}
              total={list.meta.total}
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

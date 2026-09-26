import { type ReactNode, useEffect } from "react";
import { Link, useLocation, useNavigate, useParams } from "react-router-dom";
import { ApiError } from "../../api/client";
import { SectionError } from "../../components/ui/SectionError";
import { SectionLoading } from "../../components/ui/SectionLoading";
import { StatusMessage, useActionStatus } from "../../components/ui/StatusMessage";
import {
  formatBasisPoints,
  formatDate,
  formatDateTime,
  formatMoneyCents,
  formatQuantity,
} from "../../lib/format";
import { t, tf } from "../../i18n";
import { idFromParam, wasSaved } from "./purchasingLabels";
import { type Title } from "../finance/api";
import { TitleStatusBadge } from "../finance/TitleStatusBadge";
import { useReceipt } from "./receiptsApi";

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <dt className="text-sm font-medium text-text-muted">{label}</dt>
      <dd className="text-sm text-text">{children}</dd>
    </div>
  );
}

function Payable({ title }: { title: Title }) {
  return (
    <section aria-labelledby="payable-heading" className="mt-8">
      <h2 id="payable-heading" className="font-display mb-2 text-lg text-text">
        {t("receipt.payableTitle")}
      </h2>
      <dl className="mb-4 grid max-w-3xl grid-cols-1 gap-4 sm:grid-cols-2">
        <Field label={t("receipt.payableTotal")}>
          <span className="num font-medium">{formatMoneyCents(title.total_cents)}</span>
        </Field>
        <Field label={t("receipt.payableStatus")}>
          <TitleStatusBadge status={title.status} />
        </Field>
      </dl>
      <div className="overflow-x-auto">
        <table className="w-full max-w-xl border-collapse text-sm">
          <caption className="sr-only">{t("receipt.installmentsTitle")}</caption>
          <thead>
            <tr className="border-b border-border-subtle text-left text-text-muted">
              <th className="py-2 pr-3 font-medium">{t("receipt.colInstallment")}</th>
              <th className="py-2 pr-3 font-medium">{t("receipt.colDueOn")}</th>
              <th className="py-2 text-right font-medium">{t("receipt.colAmount")}</th>
            </tr>
          </thead>
          <tbody>
            {title.installments.map((installment) => (
              <tr key={installment.id} className="border-b border-border-subtle last:border-0">
                <td className="num py-2 pr-3 text-text">{installment.number}</td>
                <td className="num py-2 pr-3 text-text">{formatDate(installment.due_on)}</td>
                <td className="num py-2 text-right text-text">
                  {formatMoneyCents(installment.amount_cents)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

/** A receipt as a report (ADR 0017): per line what it was priced with, what it
 * came to and what entered stock, and the payable it opened when the role reads
 * payables. Every figure is what the API stored; nothing is summed here. */
export function ReceiptDetailScreen({ canViewPayables }: { canViewPayables: boolean }) {
  const { id } = useParams<{ id: string }>();
  const receiptId = idFromParam(id);
  const receipt = useReceipt(receiptId);
  const location = useLocation();
  const navigate = useNavigate();
  const saved = wasSaved(location.state);
  const status = useActionStatus(saved ? { kind: "success", text: t("receipt.saved") } : null);
  const current = receipt.data;
  const notFound =
    receiptId === null || (receipt.error instanceof ApiError && receipt.error.status === 404);

  // A history entry keeps its state across a reload: the note is shown once.
  useEffect(() => {
    if (saved) void navigate(location.pathname, { replace: true, state: null });
  }, [saved, navigate, location.pathname]);

  return (
    <div>
      <p className="mb-4">
        <Link to="/recebimentos" className="text-sm text-accent underline-offset-2 hover:underline">
          {t("receipt.backToList")}
        </Link>
      </p>

      {notFound && <p className="text-sm text-text-muted">{t("receipt.notFound")}</p>}
      {!notFound && receipt.isPending && <SectionLoading label={t("receipt.loading")} />}
      {!notFound && receipt.isError && (
        <SectionError
          message={t("receipt.loadError")}
          error={receipt.error}
          onRetry={() => {
            void receipt.refetch();
          }}
        />
      )}

      {current && (
        <div>
          <h1 className="font-display mb-3 text-2xl text-text">
            {tf("receipt.title", { number: String(current.number) })}
          </h1>
          <StatusMessage status={status.status} focusOnShow />

          <dl className="mb-6 grid max-w-3xl grid-cols-1 gap-4 sm:grid-cols-2">
            <Field label={t("receipt.fieldOrder")}>
              <Link
                to={`/compras/${String(current.order.id)}`}
                className="text-accent underline-offset-2 hover:underline"
              >
                {tf("receipt.orderValue", { number: String(current.order.number) })}
              </Link>
            </Field>
            <Field label={t("receipt.fieldSupplier")}>{current.supplier.name}</Field>
            <Field label={t("receipt.fieldWarehouse")}>{current.warehouse.name}</Field>
            <Field label={t("receipt.fieldReceivedOn")}>
              <span className="num">{formatDate(current.received_on)}</span>
            </Field>
            <Field label={t("receipt.fieldInvoice")}>
              {current.supplier_invoice_number ?? t("receipt.notInformed")}
            </Field>
            <Field label={t("receipt.fieldTotal")}>
              <span className="num font-medium">{formatMoneyCents(current.total_cents)}</span>
            </Field>
            <Field label={t("receipt.fieldCreatedBy")}>{current.created_by.name}</Field>
            <Field label={t("receipt.fieldCreatedAt")}>
              <span className="num">{formatDateTime(current.created_at)}</span>
            </Field>
          </dl>

          <h2 className="font-display mb-1 text-lg text-text">{t("receipt.linesTitle")}</h2>
          <p className="mb-2 text-sm text-text-muted">{t("receipt.correctionNote")}</p>
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-sm">
              <caption className="sr-only">{t("receipt.linesTitle")}</caption>
              <thead>
                <tr className="border-b border-border-subtle text-left text-text-muted">
                  <th className="py-2 pr-3 font-medium">{t("receipt.colProduct")}</th>
                  <th className="py-2 pr-3 text-right font-medium">{t("receipt.colReceived")}</th>
                  <th className="py-2 pr-3 text-right font-medium">{t("receipt.colStock")}</th>
                  <th className="py-2 pr-3 text-right font-medium">{t("receipt.colUnitPrice")}</th>
                  <th className="py-2 pr-3 text-right font-medium">{t("receipt.colGross")}</th>
                  <th className="py-2 pr-3 text-right font-medium">{t("receipt.colDiscount")}</th>
                  <th className="py-2 text-right font-medium">{t("receipt.colNet")}</th>
                </tr>
              </thead>
              <tbody>
                {current.lines.map((line) => (
                  <tr key={line.id} className="border-b border-border-subtle last:border-0">
                    <td className="py-2 pr-3">
                      <span className="text-text">{line.product.name}</span>{" "}
                      <span className="num text-xs text-text-muted">{line.product.sku}</span>
                    </td>
                    <td className="num py-2 pr-3 text-right text-text">
                      {formatQuantity(line.quantity)} {line.purchase_unit_code}
                    </td>
                    <td className="num py-2 pr-3 text-right text-text-muted">
                      {formatQuantity(line.stock_quantity)} {line.stock_unit_code}
                    </td>
                    <td className="num py-2 pr-3 text-right text-text">
                      {formatMoneyCents(line.unit_price_cents)}
                    </td>
                    <td className="num py-2 pr-3 text-right text-text">
                      {formatMoneyCents(line.gross_cents)}
                    </td>
                    <td className="num py-2 pr-3 text-right text-text-muted">
                      {formatBasisPoints(line.discount_bp)} ({formatMoneyCents(line.discount_cents)}
                      )
                    </td>
                    <td className="num py-2 text-right text-text">
                      {formatMoneyCents(line.net_cents)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {canViewPayables &&
            (current.payable ? (
              <Payable title={current.payable} />
            ) : (
              <p className="mt-8 text-sm text-text-muted">{t("receipt.payableNone")}</p>
            ))}
        </div>
      )}
    </div>
  );
}

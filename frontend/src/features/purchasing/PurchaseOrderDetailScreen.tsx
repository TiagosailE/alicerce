import { type ReactNode, useEffect, useId, useRef, useState } from "react";
import { Link, useLocation, useNavigate, useParams } from "react-router-dom";
import { ApiError } from "../../api/client";
import { Button, buttonClass } from "../../components/ui/Button";
import { SectionError } from "../../components/ui/SectionError";
import { SectionLoading } from "../../components/ui/SectionLoading";
import { Spinner } from "../../components/ui/Spinner";
import { StatusMessage, useActionStatus } from "../../components/ui/StatusMessage";
import { apiFieldErrors, isStale } from "../../lib/errors";
import {
  formatBasisPoints,
  formatDateTime,
  formatMoneyCents,
  formatQuantity,
} from "../../lib/format";
import { t, tf } from "../../i18n";
import { useApprovePurchaseOrder, useCancelPurchaseOrder, usePurchaseOrder } from "./api";
import { OrderStatusBadge } from "./OrderStatusBadge";
import {
  canCancel,
  canReceive,
  idFromParam,
  statusNote,
  termsText,
  wasSaved,
} from "./purchasingLabels";

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div>
      <dt className="text-sm font-medium text-text-muted">{label}</dt>
      <dd className="text-sm text-text">{children}</dd>
    </div>
  );
}

function approveMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.code === "stale") return t("purchasing.approveStaleError");
    if (error.code === "invalid_transition") return t("purchasing.approveTransitionError");
    if (error.code === "conflict_retry") return t("purchasing.approveConflictError");
    if (error.code === "validation_failed") {
      const fields = apiFieldErrors(error);
      const changed = Object.entries(fields).some(
        ([field, kinds]) => field.endsWith(".conversion") && kinds.includes("changed"),
      );
      return changed
        ? t("purchasing.approveConversionError")
        : t("purchasing.approveValidationError");
    }
  }
  return t("purchasing.approveGenericError");
}

function cancelMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.code === "invalid_transition") return t("purchasing.cancelTransitionError");
    if (error.code === "conflict_retry") return t("purchasing.cancelConflictError");
  }
  return t("purchasing.cancelGenericError");
}

/** A purchase order as a document (ADR 0017): the header and the lines exactly
 * as the API stored them, and the actions its state allows. What the state
 * allows is read from the status the API sent, never worked out here. */
export function PurchaseOrderDetailScreen({
  canManage,
  canViewPayables,
}: {
  canManage: boolean;
  canViewPayables: boolean;
}) {
  const { id } = useParams<{ id: string }>();
  const orderId = idFromParam(id);
  const order = usePurchaseOrder(orderId);
  const approve = useApprovePurchaseOrder();
  const cancel = useCancelPurchaseOrder();
  const location = useLocation();
  const saved = wasSaved(location.state);
  const status = useActionStatus(
    saved ? { kind: "success", text: t("purchasing.saveSuccess") } : null,
  );
  const [confirmingCancel, setConfirmingCancel] = useState(false);
  const cancelTriggerRef = useRef<HTMLButtonElement>(null);
  const cancelBackRef = useRef<HTMLButtonElement>(null);
  const cancelTitleId = useId();
  const cancelBodyId = useId();
  const navigate = useNavigate();
  const current = order.data;
  const notFound =
    orderId === null || (order.error instanceof ApiError && order.error.status === 404);
  const approving = approve.isPending;

  // A history entry keeps its state across a reload: the "saved" note is shown
  // once, and the entry is rewritten without it.
  useEffect(() => {
    if (saved) void navigate(location.pathname, { replace: true, state: null });
  }, [saved, navigate, location.pathname]);

  function closeCancel() {
    setConfirmingCancel(false);
    cancelTriggerRef.current?.focus();
  }

  // The safe answer takes focus, so the dialog is announced and Enter does not
  // cancel by accident; Escape leaves it and returns to the button that opened it.
  useEffect(() => {
    if (!confirmingCancel) return;
    cancelBackRef.current?.focus();
    const closeOnEscape = (event: globalThis.KeyboardEvent) => {
      if (event.key !== "Escape" || cancel.isPending) return;
      setConfirmingCancel(false);
      cancelTriggerRef.current?.focus();
    };
    document.addEventListener("keydown", closeOnEscape);
    return () => {
      document.removeEventListener("keydown", closeOnEscape);
    };
  }, [confirmingCancel, cancel.isPending]);

  return (
    <div>
      <p className="mb-4">
        <Link to="/compras" className="text-sm text-accent underline-offset-2 hover:underline">
          {t("purchasing.backToList")}
        </Link>
      </p>

      {notFound && <p className="text-sm text-text-muted">{t("purchasing.detailNotFound")}</p>}
      {!notFound && order.isPending && <SectionLoading label={t("purchasing.detailLoading")} />}
      {!notFound && order.isError && (
        <SectionError
          message={t("purchasing.detailLoadError")}
          error={order.error}
          onRetry={() => {
            void order.refetch();
          }}
        />
      )}

      {current && (
        <div>
          <div className="mb-3 flex flex-wrap items-center gap-3">
            <h1 className="font-display text-2xl text-text">
              {tf("purchasing.detailTitle", { number: String(current.number) })}
            </h1>
            <OrderStatusBadge status={current.status} />
          </div>
          <p className="mb-4 text-sm text-text-muted">{t(statusNote(current.status, canManage))}</p>
          {current.status !== "draft" && (
            <p className="mb-4">
              <Link
                to={`/recebimentos?order=${String(current.id)}`}
                className="text-sm text-accent underline-offset-2 hover:underline"
              >
                {t("purchasing.linkReceipts")}
              </Link>
            </p>
          )}

          {canManage && (
            <div className="mb-4 flex flex-wrap items-center gap-2">
              {current.status === "draft" && (
                <>
                  <Link
                    to={`/compras/${String(current.id)}/editar`}
                    className={buttonClass("default")}
                  >
                    {t("purchasing.actionEdit")}
                  </Link>
                  <Button
                    variant="primary"
                    disabled={approving}
                    onClick={() => {
                      status.clear();
                      approve.mutate(
                        { id: current.id, revision: current.revision },
                        {
                          onSuccess: () => {
                            status.succeed(t("purchasing.approveSuccess"));
                          },
                          onError: (error) => {
                            status.fail(approveMessage(error), error);
                          },
                        },
                      );
                    }}
                  >
                    {approving && <Spinner />}
                    {approving ? t("purchasing.approving") : t("purchasing.actionApprove")}
                  </Button>
                </>
              )}
              {canReceive(current.status) && (
                <Link
                  to={`/compras/${String(current.id)}/receber`}
                  className={buttonClass("primary")}
                >
                  {t("purchasing.actionReceive")}
                </Link>
              )}
              {canCancel(current.status) && (
                <Button
                  ref={cancelTriggerRef}
                  disabled={approving}
                  aria-expanded={confirmingCancel}
                  aria-controls={confirmingCancel ? cancelBodyId : undefined}
                  onClick={() => {
                    status.clear();
                    setConfirmingCancel(true);
                  }}
                >
                  {t("purchasing.actionCancel")}
                </Button>
              )}
            </div>
          )}

          {confirmingCancel && (
            <div
              role="alertdialog"
              aria-labelledby={cancelTitleId}
              aria-describedby={cancelBodyId}
              className="mb-4 max-w-xl rounded-md border border-border-strong bg-surface-raised p-4"
            >
              <h2 id={cancelTitleId} className="font-display mb-1 text-base text-text">
                {tf("purchasing.cancelConfirmTitle", { number: String(current.number) })}
              </h2>
              <p id={cancelBodyId} className="mb-3 text-sm text-text-muted">
                {current.status === "draft"
                  ? t("purchasing.cancelConfirmBodyDraft")
                  : canViewPayables
                    ? t("purchasing.cancelConfirmBody")
                    : t("purchasing.cancelConfirmBodyNoPayables")}
              </p>
              <div className="flex gap-2">
                <Button
                  variant="primary"
                  disabled={cancel.isPending}
                  onClick={() => {
                    cancel.mutate(current.id, {
                      onSuccess: () => {
                        setConfirmingCancel(false);
                        status.succeed(t("purchasing.cancelSuccess"));
                      },
                      onError: (error) => {
                        setConfirmingCancel(false);
                        status.fail(cancelMessage(error), error);
                      },
                    });
                  }}
                >
                  {cancel.isPending && <Spinner />}
                  {cancel.isPending ? t("purchasing.cancelling") : t("purchasing.cancelConfirm")}
                </Button>
                <Button
                  ref={cancelBackRef}
                  variant="quiet"
                  disabled={cancel.isPending}
                  onClick={closeCancel}
                >
                  {t("purchasing.cancelBack")}
                </Button>
              </div>
            </div>
          )}

          <StatusMessage status={status.status} focusOnShow />
          {isStale(approve.error) && (
            <Button
              className="mb-3"
              onClick={() => {
                void order.refetch().then(() => {
                  approve.reset();
                  status.clear();
                });
              }}
            >
              {t("common.reload")}
            </Button>
          )}

          <dl className="mb-6 grid max-w-3xl grid-cols-1 gap-4 sm:grid-cols-2">
            <Field label={t("purchasing.fieldSupplier")}>{current.supplier.name}</Field>
            <Field label={t("purchasing.fieldDocument")}>
              <span className="num">{current.supplier.document_number}</span>
            </Field>
            <Field label={t("purchasing.fieldTerms")}>{termsText(current)}</Field>
            <Field label={t("purchasing.fieldTotal")}>
              <span className="num font-medium">{formatMoneyCents(current.total_cents)}</span>
            </Field>
            <Field label={t("purchasing.fieldCreatedAt")}>
              <span className="num">{formatDateTime(current.created_at)}</span>
            </Field>
            {current.approved_at && (
              <Field label={t("purchasing.fieldApprovedAt")}>
                <span className="num">{formatDateTime(current.approved_at)}</span>
              </Field>
            )}
            {current.cancelled_at && (
              <Field label={t("purchasing.fieldCancelledAt")}>
                <span className="num">{formatDateTime(current.cancelled_at)}</span>
              </Field>
            )}
            <Field label={t("purchasing.fieldNote")}>
              {current.note ?? t("purchasing.notInformed")}
            </Field>
          </dl>

          <h2 className="font-display mb-2 text-lg text-text">{t("purchasing.linesTitle")}</h2>
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-sm">
              <caption className="sr-only">{t("purchasing.linesTitle")}</caption>
              <thead>
                <tr className="border-b border-border-subtle text-left text-text-muted">
                  <th className="py-2 pr-3 font-medium">{t("purchasing.colProduct")}</th>
                  <th className="py-2 pr-3 text-right font-medium">
                    {t("purchasing.colQuantity")}
                  </th>
                  <th className="py-2 pr-3 text-right font-medium">
                    {t("purchasing.colReceived")}
                  </th>
                  <th className="py-2 pr-3 text-right font-medium">
                    {t("purchasing.colRemaining")}
                  </th>
                  <th className="py-2 pr-3 text-right font-medium">
                    {t("purchasing.colUnitPrice")}
                  </th>
                  <th className="py-2 pr-3 text-right font-medium">
                    {t("purchasing.colDiscount")}
                  </th>
                  <th className="py-2 text-right font-medium">{t("purchasing.colNet")}</th>
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
                      {formatQuantity(line.received_quantity)} {line.purchase_unit_code}
                    </td>
                    <td className="num py-2 pr-3 text-right text-text-muted">
                      {formatQuantity(line.remaining_quantity)} {line.purchase_unit_code}
                    </td>
                    <td className="num py-2 pr-3 text-right text-text">
                      {formatMoneyCents(line.unit_price_cents)}
                    </td>
                    <td className="num py-2 pr-3 text-right text-text-muted">
                      {formatBasisPoints(line.discount_bp)}
                    </td>
                    <td className="num py-2 text-right text-text">
                      {formatMoneyCents(line.net_cents)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

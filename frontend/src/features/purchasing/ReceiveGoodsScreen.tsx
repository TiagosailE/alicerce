import { type SubmitEvent, useEffect, useId, useRef, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { ApiError } from "../../api/client";
import { Button, buttonClass } from "../../components/ui/Button";
import { SectionError } from "../../components/ui/SectionError";
import { SectionLoading } from "../../components/ui/SectionLoading";
import { Spinner } from "../../components/ui/Spinner";
import { apiFieldErrors, requestIdSuffix } from "../../lib/errors";
import {
  dayInZone,
  formatDate,
  formatQuantity,
  isZeroDecimal,
  parseDecimalInput,
  toDecimalInput,
} from "../../lib/format";
import { keepsAttempt, newIdempotencyKey } from "../../lib/idempotency";
import { type MessageKey, t, tf } from "../../i18n";
import { type Warehouse, useActiveWarehouses } from "../inventory/api";
import { type PurchaseOrder, type PurchaseOrderLine, usePurchaseOrder } from "./api";
import { OrderStatusBadge } from "./OrderStatusBadge";
import { canReceive, idFromParam, SAVED_STATE, statusNote, termsText } from "./purchasingLabels";
import { RECEIPT_MAX_LINES, useReceiveGoods } from "./receiptsApi";

const inputClass =
  "h-9 w-full rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus";
const linkClass = "text-sm text-accent underline-offset-2 hover:underline";

// What the API says about a field, by the kind it reports (api-contract skill).
// A kind not named here falls back to a generic text, never silence.
const FIELD_MESSAGES: Record<string, Partial<Record<string, MessageKey>>> = {
  warehouse_id: { inactive: "receiving.fieldErrorWarehouseInactive" },
  received_on: {
    blank: "receiving.fieldErrorDateRequired",
    invalid: "receiving.fieldErrorDateInvalid",
    in_the_future: "receiving.fieldErrorDateFuture",
    before_approval: "receiving.fieldErrorDateBeforeApproval",
  },
  supplier_invoice_number: {
    too_long: "receiving.fieldErrorInvoiceTooLong",
    invalid: "receiving.fieldErrorInvoiceInvalid",
  },
  lines: { blank: "receiving.fieldErrorLinesBlank", too_many: "receiving.fieldErrorLinesTooMany" },
};

const QUANTITY_MESSAGES: Record<string, MessageKey> = {
  not_a_number: "receiving.fieldErrorQuantityNotANumber",
  negative: "receiving.fieldErrorQuantityPositive",
  must_be_positive: "receiving.fieldErrorQuantityPositive",
  too_many_decimals: "receiving.fieldErrorQuantityDecimals",
  too_large: "receiving.fieldErrorQuantityTooLarge",
  quantity_too_small: "receiving.fieldErrorQuantityTooSmall",
  over_receipt: "receiving.fieldErrorOverReceipt",
  not_found: "receiving.fieldErrorLineNotFound",
  duplicate_line: "receiving.fieldErrorLineDuplicate",
};

/** One attempt at receiving: what makes a retry the same request as another
 * (the fields typed), its idempotency key, and which order line each sent line
 * was, because the API names a line by its position in what was sent. */
interface Attempt {
  key: string;
  fields: string;
  lineIds: number[];
}

/** What the review step shows of a line about to be received. */
interface ReviewLine {
  orderLineId: number;
  quantity: string;
  product: string;
  unit: string;
}

/** The API's field errors as one message per field of this form. A line's error
 * is keyed "line:<id>", translated from the position the API reports. */
function serverMessages(error: unknown, lineIds: number[]): Record<string, MessageKey> {
  const messages: Record<string, MessageKey> = {};
  for (const [field, kinds] of Object.entries(apiFieldErrors(error))) {
    const kind = kinds[0] ?? "";
    const line = /^lines\.(\d+)(?:\.\w+)?$/.exec(field);
    if (line) {
      const id = lineIds[Number(line[1])];
      if (id !== undefined) {
        messages[`line:${String(id)}`] = QUANTITY_MESSAGES[kind] ?? "receiving.fieldErrorGeneric";
      }
      continue;
    }
    messages[field] = FIELD_MESSAGES[field]?.[kind] ?? "receiving.fieldErrorGeneric";
  }
  return messages;
}

/** No answer came, or the server failed: the receipt may have been registered. */
function isUncertain(error: unknown): boolean {
  return !(error instanceof ApiError) || error.status >= 500;
}

function bannerMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.code === "invalid_transition") return t("receiving.transitionError");
    if (error.code === "negative_balance") return t("receiving.negativeError");
    if (error.code === "conflict_retry") return t("receiving.conflictError");
    if (error.code === "not_found") return t("receiving.notFoundError");
    if (error.code === "idempotency_key_reused") return t("receiving.reusedError");
    if (error.status === 401) return t("receiving.unauthorizedError");
    if (error.status === 403) return t("receiving.forbiddenError");
    if (error.status === 429) return t("receiving.rateLimited");
  }
  return isUncertain(error) ? t("receiving.uncertainError") : t("receiving.genericError");
}

const RENDERED_FIELDS = new Set([
  "warehouse_id",
  "received_on",
  "supplier_invoice_number",
  "lines",
]);

/** Whether the API's error has something the form shows next to a field. The
 * rest (an idempotency key, an unknown field) goes to the banner. */
function hasUnplaced(error: unknown): boolean {
  return Object.keys(apiFieldErrors(error)).some(
    (field) => !RENDERED_FIELDS.has(field) && !/^lines\.\d+(\.\w+)?$/.test(field),
  );
}

interface Values {
  warehouseId: string;
  receivedOn: string;
  invoice: string;
  quantities: Record<number, string>;
}

/** Receiving goods against an approved order (ADR 0017): which warehouse, which
 * day, what came of each open line. A receipt cannot be undone, so a valid form
 * is reviewed before it is sent. The API works out every amount, the stock that
 * enters and the payable that opens; the form never computes one. */
function ReceiveGoodsForm({
  order,
  warehouses,
  timeZone,
  canViewPayables,
}: {
  order: PurchaseOrder;
  warehouses: Warehouse[];
  timeZone: string;
  canViewPayables: boolean;
}) {
  const receive = useReceiveGoods();
  const navigate = useNavigate();
  // The day is the organization's, the one the API judges "future" and "before
  // the approval" by, not the browser's.
  const today = dayInZone(new Date(), timeZone);
  const approvedOn = order.approved_at ? dayInZone(order.approved_at, timeZone) : undefined;
  const [values, setValues] = useState<Values>(() => ({
    warehouseId: warehouses.length === 1 && warehouses[0] ? String(warehouses[0].id) : "",
    receivedOn: today,
    invoice: "",
    quantities: {},
  }));
  // One message per field, from the form's own check or the API's answer (already
  // translated to this form's fields); editing a field clears only its own.
  const [errors, setErrors] = useState<Record<string, MessageKey>>({});
  const [attempts, setAttempts] = useState(0);
  const [review, setReview] = useState<ReviewLine[] | null>(null);
  const [announcement, setAnnouncement] = useState("");
  // The request that may still be in flight or have committed unseen: a retry of
  // an identical request reuses its key, anything else is a new intent (ADR 0005).
  const attempt = useRef<Attempt | null>(null);
  const formRef = useRef<HTMLFormElement>(null);
  const bannerRef = useRef<HTMLDivElement>(null);
  const linesErrorRef = useRef<HTMLParagraphElement>(null);
  const submitRef = useRef<HTMLButtonElement>(null);
  const reviewBackRef = useRef<HTMLButtonElement>(null);
  // The button that opens the review is not on screen while it is open, so focus
  // goes back to it once the form is shown again, not at the moment of closing.
  const returnFocus = useRef(false);
  const warehouseId = useId();
  const dateId = useId();
  const invoiceId = useId();
  const linesId = useId();
  const reviewTitleId = useId();
  const reviewBodyId = useId();

  const openLines = order.lines.filter((line) => !isZeroDecimal(line.remaining_quantity));
  const messageFor = (field: string): string | null => {
    const key = errors[field];
    return key ? t(key) : null;
  };
  const errorCount = Object.keys(errors).length;
  const fieldErrorsFromApi = receive.isError ? Object.keys(apiFieldErrors(receive.error)) : [];
  const showBanner =
    receive.isError && (fieldErrorsFromApi.length === 0 || hasUnplaced(receive.error));

  // After a failed attempt the person lands on the first field to fix, then on
  // the message about the lines, then on the banner: something always takes
  // focus. The banner is part of the render only once the mutation reports its
  // error, so that is a trigger too.
  useEffect(() => {
    if (attempts === 0) return;
    const invalid = formRef.current?.querySelector<HTMLElement>('[aria-invalid="true"]');
    (invalid ?? linesErrorRef.current ?? bannerRef.current)?.focus();
  }, [attempts, receive.isError]);

  // The safe answer takes focus, so the dialog is announced and Enter does not
  // register by accident; Escape leaves it and returns to the button that opened it.
  useEffect(() => {
    if (review === null) return;
    reviewBackRef.current?.focus();
    const closeOnEscape = (event: globalThis.KeyboardEvent) => {
      if (event.key !== "Escape" || receive.isPending) return;
      returnFocus.current = true;
      setReview(null);
    };
    document.addEventListener("keydown", closeOnEscape);
    return () => {
      document.removeEventListener("keydown", closeOnEscape);
    };
  }, [review, receive.isPending]);

  useEffect(() => {
    if (review === null && returnFocus.current) {
      returnFocus.current = false;
      submitRef.current?.focus();
    }
  }, [review]);

  /** Editing a field answers the error it was showing, and only that one; what
   * was about to be sent is no longer what is on screen, so the review closes. */
  function edited(update: (values: Values) => Values, clears: string[]) {
    setValues(update);
    setReview(null);
    setAnnouncement("");
    setErrors((current) =>
      Object.fromEntries(Object.entries(current).filter(([field]) => !clears.includes(field))),
    );
  }

  function setQuantity(line: PurchaseOrderLine, text: string) {
    edited(
      (current) => ({ ...current, quantities: { ...current.quantities, [line.id]: text } }),
      [`line:${String(line.id)}`, "lines"],
    );
  }

  function fillRemaining() {
    const filled = openLines.slice(0, RECEIPT_MAX_LINES);
    edited(
      (current) => ({
        ...current,
        quantities: Object.fromEntries(
          filled.map((line) => [line.id, toDecimalInput(line.remaining_quantity)]),
        ),
      }),
      [...openLines.map((line) => `line:${String(line.id)}`), "lines"],
    );
    setAnnouncement(
      openLines.length > RECEIPT_MAX_LINES
        ? tf("receiving.filledFirst", { count: String(RECEIPT_MAX_LINES) })
        : t("receiving.filledAll"),
    );
  }

  /** The form's own check: what can be seen by looking at the text. Nothing is
   * sent; a valid form goes to the review. */
  function submit(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    receive.reset();
    const found: Record<string, MessageKey> = {};
    if (values.warehouseId === "") found.warehouse_id = "receiving.fieldErrorWarehouseRequired";
    if (values.receivedOn === "") found.received_on = "receiving.fieldErrorDateRequired";

    const lines: ReviewLine[] = [];
    for (const line of openLines) {
      const text = (values.quantities[line.id] ?? "").trim();
      if (text === "") continue;
      const quantity = parseDecimalInput(text);
      if (quantity === null)
        found[`line:${String(line.id)}`] = "receiving.fieldErrorQuantityNotANumber";
      else if (isZeroDecimal(quantity))
        found[`line:${String(line.id)}`] = "receiving.fieldErrorQuantityPositive";
      else
        lines.push({
          orderLineId: line.id,
          quantity,
          product: line.product.name,
          unit: line.purchase_unit_code,
        });
    }
    // Nothing filled in is one mistake; a line that could not be read is another.
    if (lines.length === 0 && !Object.keys(found).some((field) => field.startsWith("line:")))
      found.lines = "receiving.fieldErrorLinesBlank";
    if (lines.length > RECEIPT_MAX_LINES) found.lines = "receiving.fieldErrorLinesTooMany";

    setErrors(found);
    if (Object.keys(found).length > 0) {
      setAttempts((count) => count + 1);
      return;
    }
    setReview(lines);
  }

  function confirm() {
    if (review === null) return;
    const lines = review.map(({ orderLineId, quantity }) => ({ orderLineId, quantity }));
    const fields = JSON.stringify([
      values.warehouseId,
      values.receivedOn,
      values.invoice.trim(),
      lines,
    ]);
    const previous = attempt.current;
    const current: Attempt =
      previous !== null && previous.fields === fields
        ? previous
        : { key: newIdempotencyKey(), fields, lineIds: lines.map((line) => line.orderLineId) };
    attempt.current = current;

    receive.mutate(
      {
        orderId: order.id,
        idempotencyKey: current.key,
        warehouseId: Number(values.warehouseId),
        receivedOn: values.receivedOn,
        supplierInvoiceNumber: values.invoice,
        lines,
      },
      {
        onSuccess: (receipt) => {
          attempt.current = null;
          void navigate(`/recebimentos/${String(receipt.id)}`, { state: SAVED_STATE });
        },
        onError: (error) => {
          const retryable = keepsAttempt(error);
          if (!retryable) attempt.current = null;
          setErrors(serverMessages(error, current.lineIds));
          // A retryable failure stays on the review, so confirming again is the
          // same request under the same key; any other answer ends the attempt
          // and shows the fields it is about.
          if (!retryable) setReview(null);
          setAttempts((count) => count + 1);
        },
      },
    );
  }

  const warehouseError = messageFor("warehouse_id");
  const dateError = messageFor("received_on");
  const invoiceError = messageFor("supplier_invoice_number");
  const linesError = messageFor("lines");
  const warehouseName =
    warehouses.find((warehouse) => String(warehouse.id) === values.warehouseId)?.name ?? "";
  const dateDescription = [approvedOn ? `${dateId}-hint` : "", dateError ? `${dateId}-error` : ""]
    .filter(Boolean)
    .join(" ");

  return (
    <form ref={formRef} onSubmit={submit} noValidate className="max-w-4xl">
      <p className="mb-4 text-sm text-text-muted">
        {canViewPayables ? t("receiving.intro") : t("receiving.introNoPayable")}
      </p>
      <p className="mb-4 text-sm text-text-muted">{t("receiving.requiredNote")}</p>

      <dl className="mb-5 grid max-w-3xl grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <dt className="text-sm font-medium text-text-muted">{t("receiving.fieldSupplier")}</dt>
          <dd className="text-sm text-text">{order.supplier.name}</dd>
        </div>
        <div>
          <dt className="text-sm font-medium text-text-muted">{t("receiving.fieldTerms")}</dt>
          <dd className="text-sm text-text">{termsText(order)}</dd>
        </div>
      </dl>

      <div className="mb-5 grid grid-cols-1 gap-4 sm:grid-cols-3">
        <div>
          <label htmlFor={warehouseId} className="mb-1 block text-sm font-medium text-text">
            {t("receiving.fieldWarehouse")}
          </label>
          <select
            id={warehouseId}
            value={values.warehouseId}
            onChange={(event) => {
              edited(
                (current) => ({ ...current, warehouseId: event.target.value }),
                ["warehouse_id"],
              );
            }}
            aria-required="true"
            aria-invalid={warehouseError ? true : undefined}
            aria-describedby={warehouseError ? `${warehouseId}-error` : undefined}
            className={inputClass}
          >
            <option value="" disabled>
              {t("receiving.warehousePlaceholder")}
            </option>
            {warehouses.map((warehouse) => (
              <option key={warehouse.id} value={warehouse.id}>
                {warehouse.name}
              </option>
            ))}
          </select>
          {warehouseError && (
            <p id={`${warehouseId}-error`} className="mt-1 text-xs text-danger">
              {warehouseError}
            </p>
          )}
        </div>
        <div>
          <label htmlFor={dateId} className="mb-1 block text-sm font-medium text-text">
            {t("receiving.fieldReceivedOn")}
          </label>
          <input
            id={dateId}
            type="date"
            value={values.receivedOn}
            min={approvedOn}
            max={today}
            onChange={(event) => {
              edited(
                (current) => ({ ...current, receivedOn: event.target.value }),
                ["received_on"],
              );
            }}
            aria-required="true"
            aria-invalid={dateError ? true : undefined}
            aria-describedby={dateDescription || undefined}
            className={`${inputClass} num`}
          />
          {approvedOn && (
            <p id={`${dateId}-hint`} className="mt-1 text-xs text-text-muted">
              {tf("receiving.dateHint", { approved: formatDate(approvedOn) })}
            </p>
          )}
          {dateError && (
            <p id={`${dateId}-error`} className="mt-1 text-xs text-danger">
              {dateError}
            </p>
          )}
        </div>
        <div>
          <label htmlFor={invoiceId} className="mb-1 block text-sm font-medium text-text">
            {t("receiving.fieldInvoice")}
          </label>
          <input
            id={invoiceId}
            type="text"
            maxLength={60}
            value={values.invoice}
            onChange={(event) => {
              edited(
                (current) => ({ ...current, invoice: event.target.value }),
                ["supplier_invoice_number"],
              );
            }}
            aria-invalid={invoiceError ? true : undefined}
            aria-describedby={[`${invoiceId}-hint`, invoiceError ? `${invoiceId}-error` : ""]
              .filter(Boolean)
              .join(" ")}
            className={inputClass}
          />
          <p id={`${invoiceId}-hint`} className="mt-1 text-xs text-text-muted">
            {t("receiving.invoiceHint")}
          </p>
          {invoiceError && (
            <p id={`${invoiceId}-error`} className="mt-1 text-xs text-danger">
              {invoiceError}
            </p>
          )}
        </div>
      </div>

      <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
        <h2 className="font-display text-lg text-text">{t("receiving.linesTitle")}</h2>
        {openLines.length > 0 && (
          <Button onClick={fillRemaining}>{t("receiving.fillRemaining")}</Button>
        )}
      </div>
      <p role="status" className="sr-only">
        {announcement}
      </p>
      {announcement && openLines.length > RECEIPT_MAX_LINES && (
        <p className="mb-2 text-xs text-text-muted">{announcement}</p>
      )}
      {linesError && (
        <p
          ref={linesErrorRef}
          id={`${linesId}-error`}
          tabIndex={-1}
          className="mb-2 text-xs text-danger focus-visible:outline-2 focus-visible:outline-focus"
        >
          {linesError}
        </p>
      )}
      {openLines.length === 0 ? (
        <p className="mb-5 text-sm text-text-muted">{t("receiving.noOpenLines")}</p>
      ) : (
        <div className="mb-5 overflow-x-auto">
          <table className="w-full border-collapse text-sm">
            <caption className="sr-only">{t("receiving.linesTitle")}</caption>
            <thead>
              <tr className="border-b border-border-subtle text-left text-text-muted">
                <th className="py-2 pr-3 font-medium">{t("receiving.colItem")}</th>
                <th className="py-2 pr-3 font-medium">{t("receiving.colProduct")}</th>
                <th className="py-2 pr-3 text-right font-medium">{t("receiving.colRemaining")}</th>
                <th className="py-2 text-right font-medium">{t("receiving.colReceiving")}</th>
              </tr>
            </thead>
            <tbody>
              {openLines.map((line) => {
                const message = messageFor(`line:${String(line.id)}`);
                const fieldId = `${linesId}-line-${String(line.id)}`;
                return (
                  <tr key={line.id} className="border-b border-border-subtle last:border-0">
                    <td className="num py-2 pr-3 text-text-muted">{line.position}</td>
                    <td className="py-2 pr-3">
                      <span className="text-text">{line.product.name}</span>{" "}
                      <span className="num text-xs text-text-muted">{line.product.sku}</span>
                    </td>
                    <td className="num py-2 pr-3 text-right text-text-muted">
                      {formatQuantity(line.remaining_quantity)} {line.purchase_unit_code}
                    </td>
                    <td className="py-2 text-right">
                      <div className="flex items-center justify-end gap-2">
                        <input
                          type="text"
                          inputMode="decimal"
                          value={values.quantities[line.id] ?? ""}
                          onChange={(event) => {
                            setQuantity(line, event.target.value);
                          }}
                          aria-label={tf("receiving.lineQuantityLabel", {
                            position: String(line.position),
                            product: line.product.name,
                          })}
                          aria-invalid={message ? true : undefined}
                          aria-describedby={message ? `${fieldId}-error` : undefined}
                          className={`${inputClass} num w-28 text-right`}
                        />
                        <span className="min-w-8 text-left text-text-muted">
                          {line.purchase_unit_code}
                        </span>
                      </div>
                      {message && (
                        <p id={`${fieldId}-error`} className="mt-1 text-xs text-danger">
                          {message}
                        </p>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {review === null ? (
        <div className="flex items-center gap-3">
          <Button ref={submitRef} type="submit" variant="primary" disabled={openLines.length === 0}>
            {t("receiving.submit")}
          </Button>
          <Link to={`/compras/${String(order.id)}`} className={linkClass}>
            {t("receiving.cancel")}
          </Link>
        </div>
      ) : (
        <div
          role="alertdialog"
          aria-labelledby={reviewTitleId}
          aria-describedby={reviewBodyId}
          className="max-w-xl rounded-md border border-border-strong bg-surface-raised p-4"
        >
          <h2 id={reviewTitleId} className="font-display mb-1 text-base text-text">
            {t("receiving.reviewTitle")}
          </h2>
          <p id={reviewBodyId} className="mb-2 text-sm text-text-muted">
            {tf("receiving.reviewBody", {
              warehouse: warehouseName,
              date: formatDate(values.receivedOn),
              items:
                review.length === 1
                  ? t("receiving.itemsOne")
                  : tf("receiving.itemsMany", { count: String(review.length) }),
            })}
          </p>
          <ul className="mb-3 list-disc pl-5 text-sm text-text">
            {review.map((line) => (
              <li key={line.orderLineId} className="num">
                {tf("receiving.reviewLine", {
                  quantity: formatQuantity(line.quantity),
                  unit: line.unit,
                  product: line.product,
                })}
              </li>
            ))}
          </ul>
          <div className="flex gap-2">
            <Button variant="primary" disabled={receive.isPending} onClick={confirm}>
              {receive.isPending && <Spinner />}
              {receive.isPending ? t("receiving.submitting") : t("receiving.confirm")}
            </Button>
            <Button
              ref={reviewBackRef}
              variant="quiet"
              disabled={receive.isPending}
              onClick={() => {
                returnFocus.current = true;
                setReview(null);
              }}
            >
              {t("receiving.reviewBack")}
            </Button>
          </div>
        </div>
      )}
      {errorCount > 0 && (
        <p role="alert" className="mt-3 text-sm text-danger">
          {errorCount === 1
            ? t("receiving.formErrorSummaryOne")
            : tf("receiving.formErrorSummaryMany", { count: String(errorCount) })}
        </p>
      )}
      {showBanner && (
        <div
          ref={bannerRef}
          tabIndex={-1}
          role="alert"
          className="mt-3 text-sm text-danger focus-visible:outline-2 focus-visible:outline-focus"
        >
          <p>
            {bannerMessage(receive.error)}
            {requestIdSuffix(receive.error)}
          </p>
          {isUncertain(receive.error) && (
            <Link to={`/recebimentos?order=${String(order.id)}`} className={linkClass}>
              {t("purchasing.linkReceipts")}
            </Link>
          )}
        </div>
      )}
    </form>
  );
}

/** An order that cannot receive: what state it is in, and the way back. The
 * message takes focus, since it may have replaced a form the person was filling. */
function NotReceivable({ order }: { order: PurchaseOrder }) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    ref.current?.focus();
  }, []);

  return (
    <div
      ref={ref}
      tabIndex={-1}
      role="alert"
      className="max-w-xl text-sm focus-visible:outline-2 focus-visible:outline-focus"
    >
      <p className="mb-2 flex items-center gap-2 text-danger">
        <OrderStatusBadge status={order.status} />
        {t("receiving.notReceivable")}
      </p>
      <p className="mb-2 text-text-muted">{t(statusNote(order.status, true))}</p>
      <Link to={`/compras/${String(order.id)}`} className={buttonClass("default")}>
        {t("receiving.cancel")}
      </Link>
    </div>
  );
}

export function ReceiveGoodsScreen({
  timeZone,
  canViewPayables,
}: {
  timeZone: string;
  canViewPayables: boolean;
}) {
  const { id } = useParams<{ id: string }>();
  const orderId = idFromParam(id);
  const order = usePurchaseOrder(orderId);
  const current = order.data;
  // The warehouses are only needed for an order that can receive.
  const warehouses = useActiveWarehouses(current !== undefined && canReceive(current.status));
  const notFound =
    orderId === null || (order.error instanceof ApiError && order.error.status === 404);

  return (
    <div>
      <p className="mb-4">
        {current ? (
          <Link to={`/compras/${String(current.id)}`} className={linkClass}>
            {tf("purchasing.backToOrder", { number: String(current.number) })}
          </Link>
        ) : (
          <Link to="/compras" className={linkClass}>
            {t("purchasing.backToList")}
          </Link>
        )}
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
        <h1 className="font-display mb-4 text-2xl text-text">
          {tf("receiving.title", { number: String(current.number) })}
        </h1>
      )}
      {current && !canReceive(current.status) && <NotReceivable order={current} />}
      {current && canReceive(current.status) && (
        <>
          {warehouses.isPending && <SectionLoading label={t("receiving.warehousesLoading")} />}
          {warehouses.isError && (
            <SectionError
              message={t("receiving.warehousesLoadError")}
              error={warehouses.error}
              onRetry={() => {
                void warehouses.refetch();
              }}
            />
          )}
          {warehouses.data?.length === 0 && (
            <div className="max-w-xl text-sm">
              <p className="mb-2 text-text-muted">{t("receiving.warehousesEmpty")}</p>
              <Link to="/estoque/depositos" className={buttonClass("default")}>
                {t("receiving.registerWarehouse")}
              </Link>
            </div>
          )}
          {warehouses.data && warehouses.data.length > 0 && (
            <ReceiveGoodsForm
              order={current}
              warehouses={warehouses.data}
              timeZone={timeZone}
              canViewPayables={canViewPayables}
            />
          )}
        </>
      )}
    </div>
  );
}

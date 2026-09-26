import { type SubmitEvent, useEffect, useId, useRef, useState } from "react";
import { ApiError } from "../../api/client";
import { Button } from "../../components/ui/Button";
import { Spinner } from "../../components/ui/Spinner";
import { apiFieldErrors, isStale, requestIdSuffix } from "../../lib/errors";
import {
  basisPointsToPercentInput,
  centsToReaisInput,
  parseDecimalInput,
  percentToBasisPoints,
  reaisToCents,
  toDecimalInput,
} from "../../lib/format";
import { type MessageKey, t, tf } from "../../i18n";
import type { PurchaseOrder, PurchaseOrderInput } from "./api";
import { ProductPicker, type ProductChoice, SupplierPicker, type SupplierChoice } from "./Pickers";

const inputClass =
  "h-9 w-full rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus";
const numberInputClass = `${inputClass} num text-right`;

interface LineState {
  key: string;
  product: ProductChoice | null;
  quantity: string;
  price: string;
  discount: string;
}

export interface OrderFormValues {
  supplier: SupplierChoice | null;
  installments: string;
  firstDueDays: string;
  intervalDays: string;
  note: string;
  lines: LineState[];
}

function newLine(): LineState {
  return {
    key: globalThis.crypto.randomUUID(),
    product: null,
    quantity: "",
    price: "",
    discount: "",
  };
}

export function emptyOrderValues(): OrderFormValues {
  return {
    supplier: null,
    installments: "1",
    firstDueDays: "30",
    intervalDays: "30",
    note: "",
    lines: [newLine()],
  };
}

/** What an existing draft shows in the form, in the units a person types: reais
 * and percent as text, never computed. */
export function orderToValues(order: PurchaseOrder): OrderFormValues {
  return {
    supplier: { id: order.supplier.id, name: order.supplier.name },
    installments: String(order.installments),
    firstDueDays: String(order.first_due_days),
    intervalDays: String(order.interval_days),
    note: order.note ?? "",
    lines: order.lines.map((line) => ({
      key: globalThis.crypto.randomUUID(),
      product: {
        id: line.product.id,
        name: line.product.name,
        sku: line.product.sku,
        unitCode: line.purchase_unit_code,
      },
      quantity: toDecimalInput(line.quantity),
      price: centsToReaisInput(line.unit_price_cents),
      discount: basisPointsToPercentInput(line.discount_bp),
    })),
  };
}

// What the API says about a field, by the kind it reports (api-contract skill).
// A kind not named here falls back to the field's generic text, never silence.
const SERVER_MESSAGES: Record<string, Partial<Record<string, MessageKey>>> = {
  supplier_id: {
    not_found: "purchasing.fieldErrorSupplierNotFound",
    not_a_supplier: "purchasing.fieldErrorSupplierNotSupplier",
    inactive: "purchasing.fieldErrorSupplierInactive",
  },
  lines: {
    blank: "purchasing.fieldErrorLinesBlank",
    too_many: "purchasing.fieldErrorLinesTooMany",
    total_too_large: "purchasing.fieldErrorLinesTotalTooLarge",
  },
  note: { too_long: "purchasing.fieldErrorNoteTooLong" },
  product_id: {
    not_found: "purchasing.fieldErrorProductNotFound",
    conversion_missing: "purchasing.fieldErrorProductConversion",
    inactive: "purchasing.fieldErrorProductInactive",
  },
  quantity: {
    not_a_number: "purchasing.fieldErrorQuantityNotANumber",
    negative: "purchasing.fieldErrorQuantityMustBePositive",
    must_be_positive: "purchasing.fieldErrorQuantityMustBePositive",
    too_many_decimals: "purchasing.fieldErrorQuantityTooManyDecimals",
    too_large: "purchasing.fieldErrorQuantityTooLarge",
  },
  unit_price_cents: {
    not_a_number: "purchasing.fieldErrorPriceNotANumber",
    out_of_range: "purchasing.fieldErrorPriceOutOfRange",
  },
  discount_bp: {
    not_a_number: "purchasing.fieldErrorDiscountNotANumber",
    out_of_range: "purchasing.fieldErrorDiscountOutOfRange",
  },
};

const GENERIC_MESSAGES: Record<string, MessageKey> = {
  supplier_id: "purchasing.fieldErrorSupplierRequired",
  installments: "purchasing.fieldErrorInstallments",
  first_due_days: "purchasing.fieldErrorDays",
  interval_days: "purchasing.fieldErrorDays",
  lines: "purchasing.fieldErrorLinesBlank",
  note: "purchasing.fieldErrorGeneric",
  product_id: "purchasing.fieldErrorProductRequired",
  quantity: "purchasing.fieldErrorQuantityNotANumber",
  unit_price_cents: "purchasing.fieldErrorPriceNotANumber",
  discount_bp: "purchasing.fieldErrorDiscountNotANumber",
};

/** "lines.2.quantity" is the "quantity" of the third line: the name the
 * messages are keyed by. */
function fieldName(field: string): string {
  return field.replace(/^lines\.\d+\./, "");
}

function serverMessage(fields: Record<string, string[]>, field: string): string | null {
  const kind = fields[field]?.[0];
  if (!kind) return null;
  const name = fieldName(field);
  const key =
    SERVER_MESSAGES[name]?.[kind] ?? GENERIC_MESSAGES[name] ?? "purchasing.fieldErrorGeneric";
  return t(key);
}

// The API's name for each field of the form, so editing a field can say which
// error it answers.
const TOP_FIELDS: Record<keyof OrderFormValues, string> = {
  supplier: "supplier_id",
  installments: "installments",
  firstDueDays: "first_due_days",
  intervalDays: "interval_days",
  note: "note",
  lines: "lines",
};
const LINE_FIELDS = {
  product: "product_id",
  quantity: "quantity",
  price: "unit_price_cents",
  discount: "discount_bp",
} as const;

const WHOLE_NUMBER = /^\d+$/;

/** Everything the form can check by looking at the text, so a mistake is named
 * next to its field before anything is sent. The API checks all of it again. */
function parseForm(values: OrderFormValues): {
  input: PurchaseOrderInput | null;
  errors: Record<string, MessageKey>;
} {
  const errors: Record<string, MessageKey> = {};
  if (!values.supplier) errors.supplier_id = "purchasing.fieldErrorSupplierRequired";

  const installments = values.installments.trim();
  if (!WHOLE_NUMBER.test(installments)) errors.installments = "purchasing.fieldErrorInstallments";
  const firstDueDays = values.firstDueDays.trim();
  if (!WHOLE_NUMBER.test(firstDueDays)) errors.first_due_days = "purchasing.fieldErrorDays";
  const intervalDays = values.intervalDays.trim();
  if (!WHOLE_NUMBER.test(intervalDays)) errors.interval_days = "purchasing.fieldErrorDays";
  if (values.lines.length === 0) errors.lines = "purchasing.fieldErrorLinesBlank";

  const lines = values.lines.map((line, index) => {
    const at = (field: string) => `lines.${String(index)}.${field}`;
    if (!line.product) errors[at("product_id")] = "purchasing.fieldErrorProductRequired";
    const quantity = parseDecimalInput(line.quantity);
    if (quantity === null) errors[at("quantity")] = "purchasing.fieldErrorQuantityNotANumber";
    const cents = reaisToCents(line.price);
    // The API takes whole cents per purchase unit: a fraction of a cent is not a price.
    if (cents === null || cents.includes("."))
      errors[at("unit_price_cents")] = "purchasing.fieldErrorPriceNotANumber";
    const basisPoints = line.discount.trim() === "" ? "0" : percentToBasisPoints(line.discount);
    if (basisPoints === null) errors[at("discount_bp")] = "purchasing.fieldErrorDiscountNotANumber";
    return { line, quantity, cents, basisPoints };
  });

  if (Object.keys(errors).length > 0 || !values.supplier) return { input: null, errors };

  return {
    errors,
    input: {
      supplierId: values.supplier.id,
      installments: Number(installments),
      firstDueDays: Number(firstDueDays),
      intervalDays: Number(intervalDays),
      note: values.note,
      lines: lines.map(({ line, quantity, cents, basisPoints }) => ({
        productId: line.product?.id ?? 0,
        quantity: quantity ?? "",
        unitPriceCents: Number(cents),
        discountBp: Number(basisPoints),
      })),
    },
  };
}

function bannerMessage(error: unknown): string {
  if (isStale(error)) return t("purchasing.updateStaleError");
  if (error instanceof ApiError) {
    if (error.code === "invalid_transition") return t("purchasing.updateTransitionError");
    if (error.status === 429) return t("purchasing.createRateLimited");
  }
  return t("purchasing.createGenericError");
}

/** What a focus move after a change is aimed at: the first control of a line
 * just added, or the add button after a line was removed (the removed line's
 * own button is gone). */
type FocusTarget = { line: string } | "add";

/** The create and edit form of a draft purchase order (ADR 0017). It collects
 * quantities, prices in reais and discounts in percent as text and turns them
 * into the API's representation by text rules; it never shows a total, because
 * money is only ever worked out by the API when the draft is saved. */
export function PurchaseOrderForm({
  initial,
  isPending,
  error,
  onSubmit,
  onCancel,
  onReload,
}: {
  initial: OrderFormValues;
  isPending: boolean;
  error: unknown;
  onSubmit: (input: PurchaseOrderInput) => void;
  onCancel: () => void;
  onReload?: () => void;
}) {
  const [values, setValues] = useState<OrderFormValues>(initial);
  const [clientErrors, setClientErrors] = useState<Record<string, MessageKey>>({});
  // Fields whose answer from the server the person has edited since: their old
  // message no longer describes what is in the field. "lines.*" stands for every
  // line's own fields after a line was removed and the numbers moved up.
  const [edited, setEdited] = useState<ReadonlySet<string>>(new Set());
  const [seenError, setSeenError] = useState(error);
  const [attempts, setAttempts] = useState(0);
  const formRef = useRef<HTMLFormElement>(null);
  const bannerRef = useRef<HTMLDivElement>(null);
  const addRef = useRef<HTMLButtonElement>(null);
  const pendingFocus = useRef<FocusTarget | null>(null);
  const installmentsId = useId();
  const firstDueId = useId();
  const intervalId = useId();
  const noteId = useId();
  const formId = useId();

  if (seenError !== error) {
    setSeenError(error);
    setEdited(new Set());
  }

  const serverFields = apiFieldErrors(error);
  const hasError = error !== null && error !== undefined;
  const isEdited = (field: string) =>
    edited.has(field) || (field.startsWith("lines.") && edited.has("lines.*"));
  const messageFor = (field: string): string | null => {
    const client = clientErrors[field];
    if (client) return t(client);
    return isEdited(field) ? null : serverMessage(serverFields, field);
  };
  const knownField = (field: string) =>
    /^(supplier_id|installments|first_due_days|interval_days|note|lines)$/.test(field) ||
    /^lines\.\d+(\.(product_id|quantity|unit_price_cents|discount_bp))?$/.test(field);
  const unplaced = Object.keys(serverFields).filter((field) => !knownField(field));
  const showBanner = hasError && (Object.keys(serverFields).length === 0 || unplaced.length > 0);

  const errorCount = [
    ...Object.values(TOP_FIELDS),
    ...values.lines.flatMap((_line, index) => [
      `lines.${String(index)}`,
      ...Object.values(LINE_FIELDS).map((field) => `lines.${String(index)}.${field}`),
    ]),
  ].filter((field) => messageFor(field) !== null).length;

  // After a failed attempt (the form's own check or the server's answer) the
  // person lands on the first field to fix, or on the banner when the failure is
  // not about a field, so nothing has to be found by scrolling.
  useEffect(() => {
    if (attempts === 0 && !hasError) return;
    const invalid = formRef.current?.querySelector<HTMLElement>('[aria-invalid="true"]');
    (invalid ?? bannerRef.current)?.focus();
  }, [attempts, error, hasError]);

  useEffect(() => {
    const target = pendingFocus.current;
    if (!target) return;
    pendingFocus.current = null;
    if (target === "add") {
      addRef.current?.focus();
      return;
    }
    formRef.current
      ?.querySelector<HTMLElement>(`[data-line-key="${target.line}"] input[type="search"]`)
      ?.focus();
  }, [values.lines]);

  function fieldsEdited(fields: string[], linesShifted = false) {
    setClientErrors((current) =>
      Object.fromEntries(
        Object.entries(current).filter(
          ([field]) => !fields.includes(field) && !(linesShifted && field.startsWith("lines.")),
        ),
      ),
    );
    setEdited((current) => new Set([...current, ...fields, ...(linesShifted ? ["lines.*"] : [])]));
  }

  function update(next: Partial<OrderFormValues>, linesShifted = false) {
    setValues((current) => ({ ...current, ...next }));
    fieldsEdited(
      (Object.keys(next) as (keyof OrderFormValues)[]).map((name) => TOP_FIELDS[name]),
      linesShifted,
    );
  }

  function updateLine(key: string, next: Partial<Omit<LineState, "key">>) {
    const index = String(values.lines.findIndex((line) => line.key === key));
    setValues((current) => ({
      ...current,
      lines: current.lines.map((line) => (line.key === key ? { ...line, ...next } : line)),
    }));
    fieldsEdited([
      `lines.${index}`,
      ...(Object.keys(next) as (keyof typeof LINE_FIELDS)[]).map(
        (name) => `lines.${index}.${LINE_FIELDS[name]}`,
      ),
    ]);
  }

  function submit(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    const { input, errors } = parseForm(values);
    setClientErrors(errors);
    if (input) {
      onSubmit(input);
      return;
    }
    setAttempts((count) => count + 1);
  }

  const supplierError = messageFor("supplier_id");
  const linesError = messageFor("lines");
  const noteError = messageFor("note");

  return (
    <form ref={formRef} id={formId} onSubmit={submit} noValidate className="max-w-4xl">
      <p className="mb-4 text-sm text-text-muted">{t("purchasing.formRequiredNote")}</p>
      <div className="mb-5 grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <SupplierPicker
            value={values.supplier}
            invalid={supplierError !== null}
            errorId={supplierError ? `${formId}-supplier-error` : undefined}
            onChange={(supplier) => {
              update({ supplier });
            }}
          />
          {supplierError && (
            <p id={`${formId}-supplier-error`} className="mt-1 text-xs text-danger">
              {supplierError}
            </p>
          )}
        </div>
        <div className="grid grid-cols-1 items-end gap-4 sm:grid-cols-3">
          {(
            [
              [installmentsId, "purchasing.fieldInstallments", "installments", values.installments],
              [firstDueId, "purchasing.fieldFirstDue", "first_due_days", values.firstDueDays],
              [intervalId, "purchasing.fieldInterval", "interval_days", values.intervalDays],
            ] as const
          ).map(([id, label, field, value]) => {
            const message = messageFor(field);
            return (
              <div key={field}>
                <label htmlFor={id} className="mb-1 block text-sm font-medium text-text">
                  {t(label)}
                </label>
                <input
                  id={id}
                  type="text"
                  inputMode="numeric"
                  value={value}
                  onChange={(event) => {
                    update(
                      field === "installments"
                        ? { installments: event.target.value }
                        : field === "first_due_days"
                          ? { firstDueDays: event.target.value }
                          : { intervalDays: event.target.value },
                    );
                  }}
                  aria-required="true"
                  aria-invalid={message ? true : undefined}
                  aria-describedby={message ? `${id}-error` : undefined}
                  className={numberInputClass}
                />
                {message && (
                  <p id={`${id}-error`} className="mt-1 text-xs text-danger">
                    {message}
                  </p>
                )}
              </div>
            );
          })}
        </div>
      </div>

      <fieldset
        className="mb-5"
        aria-describedby={linesError ? `${formId}-lines-error` : undefined}
      >
        <legend className="font-display mb-2 text-base text-text">
          {t("purchasing.linesLegend")}
        </legend>
        {linesError && (
          <p id={`${formId}-lines-error`} className="mb-2 text-xs text-danger">
            {linesError}
          </p>
        )}
        <ol className="space-y-3">
          {values.lines.map((line, index) => {
            const at = (field: string) => `lines.${String(index)}.${field}`;
            const productError = messageFor(at("product_id"));
            const quantityError = messageFor(at("quantity"));
            const priceError = messageFor(at("unit_price_cents"));
            const discountError = messageFor(at("discount_bp"));
            const lineError = messageFor(`lines.${String(index)}`);
            const unit = line.product?.unitCode;
            const ids = `${formId}-line-${String(index)}`;
            return (
              <li
                key={line.key}
                data-line-key={line.key}
                className="rounded-md border border-border-subtle bg-surface-raised p-3"
              >
                <div role="group" aria-labelledby={`${ids}-heading`}>
                  <div className="mb-2 flex items-center justify-between">
                    <h2 id={`${ids}-heading`} className="text-sm font-medium text-text">
                      {tf("purchasing.lineHeading", { number: String(index + 1) })}
                    </h2>
                    {values.lines.length > 1 && (
                      <Button
                        variant="quiet"
                        onClick={() => {
                          pendingFocus.current = "add";
                          update(
                            { lines: values.lines.filter((other) => other.key !== line.key) },
                            true,
                          );
                        }}
                      >
                        {tf("purchasing.removeLine", { number: String(index + 1) })}
                      </Button>
                    )}
                  </div>
                  {lineError && <p className="mb-2 text-xs text-danger">{lineError}</p>}
                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    <div>
                      <ProductPicker
                        value={line.product}
                        invalid={productError !== null}
                        errorId={productError ? `${ids}-product-error` : undefined}
                        onChange={(product) => {
                          updateLine(line.key, { product });
                        }}
                      />
                      {productError && (
                        <p id={`${ids}-product-error`} className="mt-1 text-xs text-danger">
                          {productError}
                        </p>
                      )}
                    </div>
                    <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                      <div>
                        <label
                          htmlFor={`${ids}-quantity`}
                          className="mb-1 block text-sm font-medium text-text"
                        >
                          {unit
                            ? tf("purchasing.fieldQuantity", { unit })
                            : t("purchasing.fieldQuantityNoUnit")}
                        </label>
                        <input
                          id={`${ids}-quantity`}
                          type="text"
                          inputMode="decimal"
                          value={line.quantity}
                          onChange={(event) => {
                            updateLine(line.key, { quantity: event.target.value });
                          }}
                          aria-required="true"
                          aria-invalid={quantityError ? true : undefined}
                          aria-describedby={quantityError ? `${ids}-quantity-error` : undefined}
                          className={numberInputClass}
                        />
                        {quantityError && (
                          <p id={`${ids}-quantity-error`} className="mt-1 text-xs text-danger">
                            {quantityError}
                          </p>
                        )}
                      </div>
                      <div>
                        <label
                          htmlFor={`${ids}-price`}
                          className="mb-1 block text-sm font-medium text-text"
                        >
                          {unit
                            ? tf("purchasing.fieldUnitPrice", { unit })
                            : t("purchasing.fieldUnitPriceNoUnit")}
                        </label>
                        <input
                          id={`${ids}-price`}
                          type="text"
                          inputMode="decimal"
                          value={line.price}
                          onChange={(event) => {
                            updateLine(line.key, { price: event.target.value });
                          }}
                          aria-required="true"
                          aria-invalid={priceError ? true : undefined}
                          aria-describedby={priceError ? `${ids}-price-error` : undefined}
                          className={numberInputClass}
                        />
                        {priceError && (
                          <p id={`${ids}-price-error`} className="mt-1 text-xs text-danger">
                            {priceError}
                          </p>
                        )}
                      </div>
                      <div>
                        <label
                          htmlFor={`${ids}-discount`}
                          className="mb-1 block text-sm font-medium text-text"
                        >
                          {t("purchasing.fieldDiscount")}
                        </label>
                        <input
                          id={`${ids}-discount`}
                          type="text"
                          inputMode="decimal"
                          value={line.discount}
                          onChange={(event) => {
                            updateLine(line.key, { discount: event.target.value });
                          }}
                          aria-invalid={discountError ? true : undefined}
                          aria-describedby={discountError ? `${ids}-discount-error` : undefined}
                          className={numberInputClass}
                        />
                        {discountError && (
                          <p id={`${ids}-discount-error`} className="mt-1 text-xs text-danger">
                            {discountError}
                          </p>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
              </li>
            );
          })}
        </ol>
        <Button
          ref={addRef}
          className="mt-3"
          onClick={() => {
            const added = newLine();
            pendingFocus.current = { line: added.key };
            update({ lines: [...values.lines, added] });
          }}
        >
          {t("purchasing.addLine")}
        </Button>
        <p className="mt-2 text-xs text-text-muted">{t("purchasing.totalsNote")}</p>
      </fieldset>

      <div className="mb-5 max-w-xl">
        <label htmlFor={noteId} className="mb-1 block text-sm font-medium text-text">
          {t("purchasing.fieldNoteInput")}
        </label>
        <input
          id={noteId}
          type="text"
          maxLength={1000}
          value={values.note}
          onChange={(event) => {
            update({ note: event.target.value });
          }}
          aria-invalid={noteError ? true : undefined}
          aria-describedby={noteError ? `${noteId}-error` : undefined}
          className={inputClass}
        />
        {noteError && (
          <p id={`${noteId}-error`} className="mt-1 text-xs text-danger">
            {noteError}
          </p>
        )}
      </div>

      <div className="flex items-center gap-3">
        <Button type="submit" variant="primary" disabled={isPending}>
          {isPending && <Spinner />}
          {isPending ? t("purchasing.submitting") : t("purchasing.submit")}
        </Button>
        <Button variant="quiet" onClick={onCancel}>
          {t("purchasing.formCancel")}
        </Button>
      </div>
      {errorCount > 0 && (
        <p role="alert" className="mt-3 text-sm text-danger">
          {errorCount === 1
            ? t("purchasing.formErrorSummaryOne")
            : tf("purchasing.formErrorSummaryMany", { count: String(errorCount) })}
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
            {bannerMessage(error)}
            {requestIdSuffix(error)}
          </p>
          {isStale(error) && onReload && (
            <Button className="mt-2" onClick={onReload}>
              {t("common.reload")}
            </Button>
          )}
        </div>
      )}
    </form>
  );
}

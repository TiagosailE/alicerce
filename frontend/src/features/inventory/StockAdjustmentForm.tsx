import { type ChangeEvent, type RefObject, type SubmitEvent, useId, useRef, useState } from "react";
import { ApiError } from "../../api/client";
import { Button } from "../../components/ui/Button";
import { Spinner } from "../../components/ui/Spinner";
import { apiFieldErrors, fieldErrorMessage, requestIdSuffix } from "../../lib/errors";
import {
  formatMoneyCents,
  formatQuantity,
  formatSignedQuantity,
  formatUnitCost,
  parseDecimalInput,
  reaisToCents,
} from "../../lib/format";
import { type MessageKey, t, tf } from "../../i18n";
import type { Product } from "../catalog/api";
import { type AdjustmentReason, type Warehouse, useAdjustStock, useObservedBalance } from "./api";
import { ADJUSTMENT_REASONS, REASON_KEYS } from "./stockLabels";

const FIELD_ERROR_KEYS: Record<string, Partial<Record<string, MessageKey>>> = {
  counted_quantity: {
    not_a_number: "stock.fieldErrorCountedNotANumber",
    negative: "stock.fieldErrorCountedNegative",
    too_many_decimals: "stock.fieldErrorCountedTooManyDecimals",
    too_large: "stock.fieldErrorCountedTooLarge",
  },
  unit_cost_cents: {
    required: "stock.fieldErrorUnitCostRequired",
    not_applicable: "stock.fieldErrorUnitCostNotApplicable",
    not_a_number: "stock.fieldErrorUnitCostNotANumber",
    negative: "stock.fieldErrorUnitCostNotANumber",
    too_many_decimals: "stock.fieldErrorUnitCostTooManyDecimals",
    too_large: "stock.fieldErrorUnitCostTooLarge",
  },
  reason: {
    incompatible_with_direction: "stock.fieldErrorReasonDirection",
    balance_has_history: "stock.fieldErrorReasonHistory",
  },
  note: { too_long: "stock.fieldErrorNoteTooLong" },
};

/** The fields this form shows an error next to. A validation error on any
 * other field (expected_on_hand, idempotency_key) has nowhere to appear, so it
 * goes to the banner instead of being swallowed. */
const RENDERED_FIELDS = new Set(Object.keys(FIELD_ERROR_KEYS));

function newIdempotencyKey(): string {
  return globalThis.crypto.randomUUID();
}

/** ADR 0005: the key survives what a retry can safely repeat (no answer at
 * all, a server error, a lock conflict) and is replaced after any answer that
 * means "this attempt is over". A stale count is such an answer: the operator
 * has to look at the new balance, so the next count is a new intent. */
function keepsAttempt(error: unknown): boolean {
  if (!(error instanceof ApiError)) return true;
  if (error.code === "stale") return false;
  return error.status >= 500 || error.status === 409;
}

function bannerMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.code === "stale") return t("stock.adjustStaleError");
    if (error.code === "conflict_retry") return t("stock.adjustConflictError");
    if (error.code === "negative_balance") return t("stock.adjustNegativeError");
    if (error.code === "not_found") return t("stock.adjustNotFoundError");
    if (error.code === "idempotency_key_reused") return t("stock.adjustReusedError");
  }
  return t("stock.adjustGenericError");
}

/** Everything that makes one attempt the same request as another: the fields
 * the operator typed and the balance they were counted against. */
interface Attempt {
  key: string;
  expectedOnHand: string;
  fields: string;
}

const inputClass =
  "h-9 w-full rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus";

/** A count adjustment (ADR 0016): what was counted, why, and optionally what
 * an increase cost. The API works out the difference under the balance lock;
 * the screen never computes a quantity or an amount. */
export function StockAdjustmentForm({
  products,
  warehouses,
  onClose,
  productSelectRef,
}: {
  products: Product[];
  warehouses: Warehouse[];
  onClose: () => void;
  productSelectRef?: RefObject<HTMLSelectElement | null>;
}) {
  const adjust = useAdjustStock();
  const [productId, setProductId] = useState("");
  const [warehouseId, setWarehouseId] = useState(
    warehouses.length === 1 && warehouses[0] ? String(warehouses[0].id) : "",
  );
  const [counted, setCounted] = useState("");
  const [reason, setReason] = useState<AdjustmentReason>("count");
  const [unitCost, setUnitCost] = useState("");
  const [note, setNote] = useState("");
  const [countedUnreadable, setCountedUnreadable] = useState(false);
  const [costUnreadable, setCostUnreadable] = useState(false);
  const [announcement, setAnnouncement] = useState("");
  // The request that may still be in flight or have committed unseen. A retry
  // of an identical request reuses its key and its expected balance, so the
  // server can recognise it; anything else is a new intent with a new key.
  const attempt = useRef<Attempt | null>(null);
  const countedRef = useRef<HTMLInputElement>(null);
  const productFieldId = useId();
  const warehouseFieldId = useId();
  const countedId = useId();
  const reasonId = useId();
  const costId = useId();
  const noteId = useId();

  const selectedProduct = products.find((product) => String(product.id) === productId);
  const pairChosen = productId !== "" && warehouseId !== "";
  const observed = useObservedBalance(
    productId ? Number(productId) : undefined,
    warehouseId ? Number(warehouseId) : undefined,
  );
  const unit = selectedProduct?.stock_unit.code ?? "";

  const fieldErrors = adjust.isError ? apiFieldErrors(adjust.error) : {};
  const countedError =
    (countedUnreadable ? t("stock.fieldErrorCountedNotANumber") : null) ??
    fieldErrorMessage(fieldErrors, "counted_quantity", FIELD_ERROR_KEYS, "stock.fieldErrorGeneric");
  const costError =
    (costUnreadable ? t("stock.fieldErrorUnitCostNotANumber") : null) ??
    fieldErrorMessage(fieldErrors, "unit_cost_cents", FIELD_ERROR_KEYS, "stock.fieldErrorGeneric");
  const reasonError = fieldErrorMessage(
    fieldErrors,
    "reason",
    FIELD_ERROR_KEYS,
    "stock.fieldErrorGeneric",
  );
  const noteError = fieldErrorMessage(
    fieldErrors,
    "note",
    FIELD_ERROR_KEYS,
    "stock.fieldErrorGeneric",
  );
  const errorKeys = Object.keys(fieldErrors);
  const showBanner =
    adjust.isError &&
    (errorKeys.length === 0 || errorKeys.some((key) => !RENDERED_FIELDS.has(key)));

  const costCents = unitCost.trim() ? reaisToCents(unitCost.trim()) : null;

  /** Editing a field answers the error it was showing. */
  function changed<T extends HTMLInputElement | HTMLSelectElement>(apply: (value: string) => void) {
    return (event: ChangeEvent<T>) => {
      apply(event.target.value);
      if (adjust.isError) adjust.reset();
    };
  }

  function submit(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    const parsedCounted = parseDecimalInput(counted);
    const costText = unitCost.trim();
    const cents = costText ? reaisToCents(costText) : null;
    setCountedUnreadable(parsedCounted === null);
    setCostUnreadable(costText !== "" && cents === null);
    if (parsedCounted === null || (costText !== "" && cents === null)) return;
    if (observed.data === undefined) return;

    const fields = JSON.stringify([
      productId,
      warehouseId,
      parsedCounted,
      reason,
      note.trim(),
      cents,
    ]);
    const previous = attempt.current;
    const retry = previous !== null && previous.fields === fields;
    const current: Attempt = retry
      ? previous
      : { key: newIdempotencyKey(), expectedOnHand: observed.data, fields };
    attempt.current = current;
    setAnnouncement("");

    adjust.mutate(
      {
        idempotencyKey: current.key,
        productId: Number(productId),
        warehouseId: Number(warehouseId),
        expectedOnHand: current.expectedOnHand,
        countedQuantity: parsedCounted,
        reason,
        note,
        unitCost: cents,
      },
      {
        onSuccess: ({ movement, balance }) => {
          attempt.current = null;
          setCounted("");
          setUnitCost("");
          setNote("");
          // A reason carried over would make the next count fail on direction.
          setReason("count");
          const code = balance.product.stock_unit.code;
          setAnnouncement(
            movement
              ? tf("stock.adjustedSummary", {
                  quantity: formatSignedQuantity(movement.quantity),
                  unit: code,
                  value:
                    movement.value_cents === null
                      ? ""
                      : tf("stock.adjustedValuePart", {
                          value: formatMoneyCents(movement.value_cents),
                        }),
                  onHand: formatQuantity(balance.on_hand),
                })
              : t("stock.adjustedNoDifference"),
          );
          countedRef.current?.focus();
        },
        onError: (error) => {
          if (!keepsAttempt(error)) attempt.current = null;
        },
      },
    );
  }

  return (
    <form onSubmit={submit} noValidate className="max-w-3xl">
      <div className="mb-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <label htmlFor={productFieldId} className="mb-1 block text-sm font-medium text-text">
            {t("stock.fieldProduct")}
          </label>
          <select
            id={productFieldId}
            ref={productSelectRef}
            required
            value={productId}
            onChange={changed(setProductId)}
            className={inputClass}
          >
            <option value="" disabled>
              {t("stock.selectPlaceholder")}
            </option>
            {products.map((product) => (
              <option key={product.id} value={product.id}>
                {product.name} ({product.sku})
                {product.active ? "" : ` (${t("stock.inactiveSuffix")})`}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor={warehouseFieldId} className="mb-1 block text-sm font-medium text-text">
            {t("stock.fieldWarehouse")}
          </label>
          <select
            id={warehouseFieldId}
            required
            value={warehouseId}
            onChange={changed(setWarehouseId)}
            className={inputClass}
          >
            <option value="" disabled>
              {t("stock.selectPlaceholder")}
            </option>
            {warehouses.map((warehouse) => (
              <option key={warehouse.id} value={warehouse.id}>
                {warehouse.name}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor={countedId} className="mb-1 block text-sm font-medium text-text">
            {t("stock.fieldCounted")}
            {unit ? ` (${unit})` : ""}
          </label>
          <input
            id={countedId}
            ref={countedRef}
            type="text"
            inputMode="decimal"
            required
            value={counted}
            onChange={changed((value) => {
              setCounted(value);
              setCountedUnreadable(false);
            })}
            aria-invalid={countedError ? true : undefined}
            aria-describedby={[
              countedError ? `${countedId}-error` : null,
              `${countedId}-observed`,
              `${countedId}-hint`,
            ]
              .filter(Boolean)
              .join(" ")}
            className={`${inputClass} num`}
          />
          <p id={`${countedId}-hint`} className="mt-1 text-xs text-text-muted">
            {t("stock.fieldCountedHint")}
          </p>
          <p id={`${countedId}-observed`} className="num mt-1 text-xs text-text" aria-live="polite">
            {!pairChosen && t("stock.observedPrompt")}
            {pairChosen && observed.isPending && t("stock.observedLoading")}
            {pairChosen && observed.isError && (
              <>
                {t("stock.observedError")}{" "}
                <button
                  type="button"
                  onClick={() => {
                    void observed.refetch();
                  }}
                  className="text-accent underline underline-offset-2"
                >
                  {t("stock.observedRetry")}
                </button>
              </>
            )}
            {pairChosen &&
              observed.data !== undefined &&
              `${t("stock.observedLabel")}: ${formatQuantity(observed.data)} ${unit}`}
          </p>
          {countedError && (
            <p id={`${countedId}-error`} role="alert" className="mt-1 text-xs text-danger">
              {countedError}
            </p>
          )}
        </div>
        <div>
          <label htmlFor={reasonId} className="mb-1 block text-sm font-medium text-text">
            {t("stock.fieldReason")}
          </label>
          <select
            id={reasonId}
            required
            value={reason}
            onChange={changed((value) => {
              setReason(value as AdjustmentReason);
            })}
            aria-invalid={reasonError ? true : undefined}
            aria-describedby={reasonError ? `${reasonId}-error` : undefined}
            className={inputClass}
          >
            {ADJUSTMENT_REASONS.map((value) => (
              <option key={value} value={value}>
                {t(REASON_KEYS[value])}
              </option>
            ))}
          </select>
          {reasonError && (
            <p id={`${reasonId}-error`} role="alert" className="mt-1 text-xs text-danger">
              {reasonError}
            </p>
          )}
        </div>
        <div>
          <label htmlFor={costId} className="mb-1 block text-sm font-medium text-text">
            {t("stock.fieldUnitCost")}
          </label>
          <input
            id={costId}
            type="text"
            inputMode="decimal"
            value={unitCost}
            onChange={changed((value) => {
              setUnitCost(value);
              setCostUnreadable(false);
            })}
            aria-invalid={costError ? true : undefined}
            aria-describedby={[costError ? `${costId}-error` : null, `${costId}-hint`]
              .filter(Boolean)
              .join(" ")}
            className={`${inputClass} num`}
          />
          <p id={`${costId}-hint`} className="mt-1 text-xs text-text-muted">
            {t("stock.fieldUnitCostHint")}
            {costCents !== null &&
              ` ${tf("stock.fieldUnitCostEcho", { value: formatUnitCost(costCents) })}`}
          </p>
          {costError && (
            <p id={`${costId}-error`} role="alert" className="mt-1 text-xs text-danger">
              {costError}
            </p>
          )}
        </div>
        <div>
          <label htmlFor={noteId} className="mb-1 block text-sm font-medium text-text">
            {t("stock.fieldNote")}
          </label>
          <input
            id={noteId}
            type="text"
            maxLength={500}
            value={note}
            onChange={changed(setNote)}
            aria-invalid={noteError ? true : undefined}
            aria-describedby={noteError ? `${noteId}-error` : undefined}
            className={inputClass}
          />
          {noteError && (
            <p id={`${noteId}-error`} role="alert" className="mt-1 text-xs text-danger">
              {noteError}
            </p>
          )}
        </div>
      </div>

      <div className="flex items-center gap-3">
        <Button
          type="submit"
          variant="primary"
          disabled={adjust.isPending}
          aria-disabled={observed.data === undefined || undefined}
          aria-describedby={`${countedId}-observed`}
          className="aria-disabled:cursor-not-allowed aria-disabled:opacity-45"
        >
          {adjust.isPending && <Spinner />}
          {adjust.isPending ? t("stock.submitting") : t("stock.submit")}
        </Button>
        <Button type="button" variant="quiet" onClick={onClose}>
          {t("stock.adjustClose")}
        </Button>
      </div>
      {/* Always mounted, so a screen reader announces the text when it appears. */}
      <p role="status" className="mt-3 text-sm text-success">
        {announcement}
      </p>
      {showBanner && (
        <p role="alert" className="mt-3 text-sm text-danger">
          {bannerMessage(adjust.error)}
          {requestIdSuffix(adjust.error)}
        </p>
      )}
    </form>
  );
}

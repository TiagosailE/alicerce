import { type SubmitEvent, useId, useState } from "react";
import { ApiError } from "../../api/client";
import { Button } from "../../components/ui/Button";
import { Spinner } from "../../components/ui/Spinner";
import { apiFieldErrors, fieldErrorMessage, isStale, requestIdSuffix } from "../../lib/errors";
import { parseDecimalInput, toDecimalInput } from "../../lib/format";
import { type MessageKey, t } from "../../i18n";
import type { Category, Product, ProductInput, Unit } from "./api";

// The API maps a validation_failed error to details.fields: { field: [kind,
// ...] } (api-contract skill); each field here is the Rails attribute name a
// command's Result.invalid reports (the association, not its _id column, for
// category/stock_unit/purchase_unit). Only the combinations this form can
// actually trigger are named; anything else falls back to a generic,
// still-linked-to-the-field message rather than silence.
const FIELD_ERROR_KEYS: Record<string, Partial<Record<string, MessageKey>>> = {
  sku: { blank: "products.fieldErrorSkuBlank", taken: "products.fieldErrorSkuTaken" },
  name: { blank: "products.fieldErrorNameBlank" },
  category: { not_found: "products.fieldErrorCategoryNotFound" },
  stock_unit: {
    blank: "products.fieldErrorStockUnitBlank",
    immutable: "products.fieldErrorStockUnitImmutable",
  },
  purchase_unit: { blank: "products.fieldErrorPurchaseUnitBlank" },
  factor: {
    blank: "products.fieldErrorFactorBlank",
    not_a_number: "products.fieldErrorFactorNotANumber",
    greater_than: "products.fieldErrorFactorGreaterThan",
    less_than: "products.fieldErrorFactorLessThan",
    too_many_decimals: "products.fieldErrorFactorTooManyDecimals",
  },
};

function productErrorMessage(error: unknown, kind: "create" | "update"): string {
  if (isStale(error)) return t("products.updateStaleError");
  if (error instanceof ApiError && error.code === "validation_failed") {
    return kind === "create"
      ? t("products.createValidationError")
      : t("products.updateValidationError");
  }
  return kind === "create" ? t("products.createGenericError") : t("products.updateGenericError");
}

/** Shared by the create form (ProductsScreen) and the edit form
 * (ProductDetailScreen): same fields either way, only the submit label,
 * the active toggle (nothing to activate/deactivate before a product
 * exists) and what happens on success differ. */
export function ProductForm({
  units,
  categories,
  initial,
  submitLabel,
  submittingLabel,
  errorKind,
  isPending,
  isError,
  error,
  showActiveToggle,
  onSubmit,
  onCancel,
}: {
  units: Unit[];
  categories: Category[];
  initial?: Partial<ProductInput & { active: boolean }>;
  submitLabel: string;
  submittingLabel: string;
  errorKind: "create" | "update";
  isPending: boolean;
  isError: boolean;
  error: unknown;
  showActiveToggle: boolean;
  onSubmit: (input: ProductInput & { active: boolean }) => void;
  onCancel?: () => void;
}) {
  const [sku, setSku] = useState(initial?.sku ?? "");
  const [name, setName] = useState(initial?.name ?? "");
  const [categoryId, setCategoryId] = useState(initial?.categoryId?.toString() ?? "");
  // No default unit for a new product: a silently pre-selected first unit
  // would let someone submit without ever choosing one on purpose. An
  // existing product's stored unit has no such ambiguity.
  const [stockUnitId, setStockUnitId] = useState(initial?.stockUnitId?.toString() ?? "");
  const [purchaseUnitId, setPurchaseUnitId] = useState(initial?.purchaseUnitId?.toString() ?? "");
  const [factor, setFactor] = useState(initial?.factor ? toDecimalInput(initial.factor) : "1");
  const [factorUnreadable, setFactorUnreadable] = useState(false);
  const [active, setActive] = useState(initial?.active ?? true);
  const skuId = useId();
  const nameId = useId();
  const categoryFieldId = useId();
  const stockUnitFieldId = useId();
  const purchaseUnitFieldId = useId();
  const factorId = useId();
  const activeId = useId();
  const errorId = useId();
  const skuErrorId = useId();
  const nameErrorId = useId();
  const categoryErrorId = useId();
  const stockUnitErrorId = useId();
  const purchaseUnitErrorId = useId();
  const factorErrorId = useId();

  const fieldErrors = isError ? apiFieldErrors(error) : {};
  const skuError = fieldErrorMessage(
    fieldErrors,
    "sku",
    FIELD_ERROR_KEYS,
    "products.fieldErrorGeneric",
  );
  const nameError = fieldErrorMessage(
    fieldErrors,
    "name",
    FIELD_ERROR_KEYS,
    "products.fieldErrorGeneric",
  );
  const categoryError = fieldErrorMessage(
    fieldErrors,
    "category",
    FIELD_ERROR_KEYS,
    "products.fieldErrorGeneric",
  );
  const stockUnitError = fieldErrorMessage(
    fieldErrors,
    "stock_unit",
    FIELD_ERROR_KEYS,
    "products.fieldErrorGeneric",
  );
  const purchaseUnitError = fieldErrorMessage(
    fieldErrors,
    "purchase_unit",
    FIELD_ERROR_KEYS,
    "products.fieldErrorGeneric",
  );
  const factorError =
    (factorUnreadable ? t("products.fieldErrorFactorNotANumber") : null) ??
    fieldErrorMessage(fieldErrors, "factor", FIELD_ERROR_KEYS, "products.fieldErrorGeneric");
  // The bottom banner is for whatever a field-level message could not
  // explain (a non-validation failure, or a validation_failed with no
  // field this form recognizes); once every reported field already has
  // its own message, repeating the same information at the bottom too
  // would just be noise.
  const hasFieldErrors = Object.keys(fieldErrors).length > 0;

  function submit(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    // Decimal strings travel with a period (ADR 0006) but a pt-BR user types
    // a comma and reads the list's "1.000" as one thousand; the translation
    // is a text rule, not arithmetic, and anything it cannot read stops here
    // instead of being guessed at.
    const parsedFactor = parseDecimalInput(factor);
    if (parsedFactor === null) {
      setFactorUnreadable(true);
      return;
    }
    onSubmit({
      sku,
      name,
      categoryId: categoryId ? Number(categoryId) : null,
      stockUnitId: Number(stockUnitId),
      purchaseUnitId: Number(purchaseUnitId),
      factor: parsedFactor,
      active,
    });
  }

  return (
    <form onSubmit={submit} className="max-w-2xl">
      <div className="mb-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <label htmlFor={skuId} className="mb-1 block text-sm font-medium text-text">
            {t("products.skuLabel")}
          </label>
          <input
            id={skuId}
            type="text"
            required
            value={sku}
            onChange={(event) => {
              setSku(event.target.value);
            }}
            aria-describedby={skuError ? skuErrorId : undefined}
            className="h-9 w-full rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          />
          {skuError && (
            <p id={skuErrorId} role="alert" className="mt-1 text-xs text-danger">
              {skuError}
            </p>
          )}
        </div>
        <div>
          <label htmlFor={nameId} className="mb-1 block text-sm font-medium text-text">
            {t("products.nameLabel")}
          </label>
          <input
            id={nameId}
            type="text"
            required
            value={name}
            onChange={(event) => {
              setName(event.target.value);
            }}
            aria-describedby={nameError ? nameErrorId : undefined}
            className="h-9 w-full rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          />
          {nameError && (
            <p id={nameErrorId} role="alert" className="mt-1 text-xs text-danger">
              {nameError}
            </p>
          )}
        </div>
        <div>
          <label htmlFor={categoryFieldId} className="mb-1 block text-sm font-medium text-text">
            {t("products.categoryLabel")}
          </label>
          <select
            id={categoryFieldId}
            value={categoryId}
            onChange={(event) => {
              setCategoryId(event.target.value);
            }}
            aria-describedby={categoryError ? categoryErrorId : undefined}
            className="h-9 w-full rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          >
            <option value="">{t("products.categoryNone")}</option>
            {categories.map((category) => (
              <option key={category.id} value={category.id}>
                {category.name}
              </option>
            ))}
          </select>
          {categoryError && (
            <p id={categoryErrorId} role="alert" className="mt-1 text-xs text-danger">
              {categoryError}
            </p>
          )}
        </div>
        {showActiveToggle && (
          <div className="flex items-end gap-2 pb-2">
            <input
              id={activeId}
              type="checkbox"
              checked={active}
              onChange={(event) => {
                setActive(event.target.checked);
              }}
              className="h-5 w-5 accent-accent rounded border-border-strong focus-visible:outline-2 focus-visible:outline-focus"
            />
            <label htmlFor={activeId} className="text-sm font-medium text-text">
              {t("products.activeLabel")}
            </label>
          </div>
        )}
        <div>
          <label htmlFor={stockUnitFieldId} className="mb-1 block text-sm font-medium text-text">
            {t("products.stockUnitLabel")}
          </label>
          <select
            id={stockUnitFieldId}
            required
            disabled={initial !== undefined}
            value={stockUnitId}
            onChange={(event) => {
              setStockUnitId(event.target.value);
            }}
            aria-describedby={
              stockUnitError
                ? `${stockUnitErrorId} ${stockUnitFieldId}-hint`
                : `${stockUnitFieldId}-hint`
            }
            className="h-9 w-full rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          >
            <option value="" disabled>
              {t("products.selectUnitPlaceholder")}
            </option>
            {units.map((unit) => (
              <option key={unit.id} value={unit.id}>
                {unit.name} ({unit.code})
              </option>
            ))}
          </select>
          {initial !== undefined && (
            <p id={`${stockUnitFieldId}-hint`} className="mt-1 text-xs text-text-muted">
              {t("products.stockUnitLockedHint")}
            </p>
          )}
          {stockUnitError && (
            <p id={stockUnitErrorId} role="alert" className="mt-1 text-xs text-danger">
              {stockUnitError}
            </p>
          )}
        </div>
        <div>
          <label htmlFor={purchaseUnitFieldId} className="mb-1 block text-sm font-medium text-text">
            {t("products.purchaseUnitLabel")}
          </label>
          <select
            id={purchaseUnitFieldId}
            required
            value={purchaseUnitId}
            onChange={(event) => {
              setPurchaseUnitId(event.target.value);
            }}
            aria-describedby={purchaseUnitError ? purchaseUnitErrorId : undefined}
            className="h-9 w-full rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          >
            <option value="" disabled>
              {t("products.selectUnitPlaceholder")}
            </option>
            {units.map((unit) => (
              <option key={unit.id} value={unit.id}>
                {unit.name} ({unit.code})
              </option>
            ))}
          </select>
          {purchaseUnitError && (
            <p id={purchaseUnitErrorId} role="alert" className="mt-1 text-xs text-danger">
              {purchaseUnitError}
            </p>
          )}
        </div>
        <div>
          <label htmlFor={factorId} className="mb-1 block text-sm font-medium text-text">
            {t("products.factorLabel")}
          </label>
          <input
            id={factorId}
            type="text"
            inputMode="decimal"
            required
            value={factor}
            onChange={(event) => {
              setFactor(event.target.value);
              setFactorUnreadable(false);
            }}
            aria-describedby={
              factorError ? `${factorErrorId} ${factorId}-hint` : `${factorId}-hint`
            }
            className="h-9 w-full rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          />
          <p id={`${factorId}-hint`} className="mt-1 text-xs text-text-muted">
            {t("products.factorHint")}
          </p>
          {factorError && (
            <p id={factorErrorId} role="alert" className="mt-1 text-xs text-danger">
              {factorError}
            </p>
          )}
        </div>
      </div>

      <div className="flex items-center gap-3">
        <Button type="submit" variant="primary" disabled={isPending}>
          {isPending && <Spinner />}
          {isPending ? submittingLabel : submitLabel}
        </Button>
        {onCancel && (
          <Button variant="quiet" type="button" onClick={onCancel} disabled={isPending}>
            {t("products.createCancel")}
          </Button>
        )}
      </div>
      {isError && !hasFieldErrors && (
        <p id={errorId} role="alert" className="mt-2 text-sm text-danger">
          {productErrorMessage(error, errorKind)}
          {requestIdSuffix(error)}
        </p>
      )}
      {isError && hasFieldErrors && requestIdSuffix(error) && (
        <p className="mt-2 text-xs text-text-muted">{requestIdSuffix(error).trim()}</p>
      )}
    </form>
  );
}

export function productToInitial(product: Product): ProductInput & { active: boolean } {
  return {
    sku: product.sku,
    name: product.name,
    categoryId: product.category?.id ?? null,
    stockUnitId: product.stock_unit.id,
    purchaseUnitId: product.unit_conversion.purchase_unit.id,
    factor: product.unit_conversion.factor,
    active: product.active,
  };
}

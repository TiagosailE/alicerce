import { useDeferredValue, useId, useState } from "react";
import { t, tf } from "../../i18n";
import { useProductOptions } from "../catalog/api";
import { useSupplierOptions } from "./api";

const inputClass =
  "h-9 w-full rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus";

export interface SupplierChoice {
  id: number;
  name: string;
}

export interface ProductChoice {
  id: number;
  name: string;
  sku: string;
  /** The unit the product is bought in, from its conversion. */
  unitCode: string;
}

/** A search box over a select: the first page of matches, narrowed by a
 * server-side search, with the chosen one always kept in the list however the
 * search changes after it. */
export function SupplierPicker({
  value,
  onChange,
  errorId,
  invalid,
}: {
  value: SupplierChoice | null;
  onChange: (supplier: SupplierChoice | null) => void;
  errorId?: string;
  invalid: boolean;
}) {
  const [query, setQuery] = useState("");
  const options = useSupplierOptions(useDeferredValue(query.trim()));
  const found = options.data?.data ?? [];
  const choices: SupplierChoice[] =
    value && !found.some((supplier) => supplier.id === value.id)
      ? [value, ...found]
      : found.map(({ id, name }) => ({ id, name }));
  const searchId = useId();
  const selectId = useId();
  const noteId = useId();

  return (
    <div>
      <label htmlFor={searchId} className="mb-1 block text-sm font-medium text-text">
        {t("purchasing.fieldSupplierSearch")}
      </label>
      <input
        id={searchId}
        type="search"
        value={query}
        onChange={(event) => {
          setQuery(event.target.value);
        }}
        className={`${inputClass} mb-2`}
      />
      <label htmlFor={selectId} className="mb-1 block text-sm font-medium text-text">
        {t("purchasing.fieldSupplierSelect")}
      </label>
      <select
        id={selectId}
        value={value ? String(value.id) : ""}
        onChange={(event) => {
          onChange(choices.find((supplier) => String(supplier.id) === event.target.value) ?? null);
        }}
        aria-invalid={invalid ? true : undefined}
        aria-describedby={[errorId, noteId].filter(Boolean).join(" ")}
        className={inputClass}
      >
        <option value="" disabled>
          {t("purchasing.selectPlaceholder")}
        </option>
        {choices.map((supplier) => (
          <option key={supplier.id} value={supplier.id}>
            {supplier.name}
          </option>
        ))}
      </select>
      <p id={noteId} className="mt-1 text-xs text-text-muted" aria-live="polite">
        {options.isError && t("purchasing.suppliersLoadError")}
        {options.data && found.length === 0 && t("purchasing.suppliersEmpty")}
        {options.data &&
          options.data.meta.total > found.length &&
          tf("purchasing.suppliersTruncated", {
            shown: String(found.length),
            total: String(options.data.meta.total),
          })}
      </p>
    </div>
  );
}

export function ProductPicker({
  value,
  onChange,
  errorId,
  invalid,
}: {
  value: ProductChoice | null;
  onChange: (product: ProductChoice | null) => void;
  errorId?: string;
  invalid: boolean;
}) {
  const [query, setQuery] = useState("");
  const options = useProductOptions(useDeferredValue(query.trim()));
  // An inactive product cannot be ordered, so it is not offered.
  const found: ProductChoice[] = (options.data?.data ?? [])
    .filter((product) => product.active)
    .map((product) => ({
      id: product.id,
      name: product.name,
      sku: product.sku,
      unitCode: product.unit_conversion.purchase_unit.code,
    }));
  const choices =
    value && !found.some((product) => product.id === value.id) ? [value, ...found] : found;
  const searchId = useId();
  const selectId = useId();
  const noteId = useId();

  return (
    <div>
      <label htmlFor={searchId} className="mb-1 block text-sm font-medium text-text">
        {t("purchasing.fieldProductSearch")}
      </label>
      <input
        id={searchId}
        type="search"
        value={query}
        onChange={(event) => {
          setQuery(event.target.value);
        }}
        className={`${inputClass} mb-2`}
      />
      <label htmlFor={selectId} className="mb-1 block text-sm font-medium text-text">
        {t("purchasing.fieldProduct")}
      </label>
      <select
        id={selectId}
        value={value ? String(value.id) : ""}
        onChange={(event) => {
          onChange(choices.find((product) => String(product.id) === event.target.value) ?? null);
        }}
        aria-invalid={invalid ? true : undefined}
        aria-describedby={[errorId, noteId].filter(Boolean).join(" ")}
        className={inputClass}
      >
        <option value="" disabled>
          {t("purchasing.selectPlaceholder")}
        </option>
        {choices.map((product) => (
          <option key={product.id} value={product.id}>
            {product.name} ({product.sku})
          </option>
        ))}
      </select>
      <p id={noteId} className="mt-1 text-xs text-text-muted" aria-live="polite">
        {options.isError && t("purchasing.productsLoadError")}
        {options.data && found.length === 0 && t("purchasing.productsEmpty")}
        {options.data &&
          options.data.meta.total > options.data.data.length &&
          tf("purchasing.productsTruncated", {
            shown: String(options.data.data.length),
            total: String(options.data.meta.total),
          })}
      </p>
    </div>
  );
}

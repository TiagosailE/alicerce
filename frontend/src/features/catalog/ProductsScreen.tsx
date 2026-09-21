import { useEffect, useId, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { Button } from "../../components/ui/Button";
import { PaginationControls } from "../../components/ui/PaginationControls";
import { SectionError } from "../../components/ui/SectionError";
import { SectionLoading } from "../../components/ui/SectionLoading";
import { StatusMessage, useActionStatus } from "../../components/ui/StatusMessage";
import { formatQuantity } from "../../lib/format";
import { t } from "../../i18n";
import { useCategories, useCreateProduct, useProducts, useUnits } from "./api";
import { ProductForm } from "./ProductForm";

function StatusBadge({ active }: { active: boolean }) {
  return (
    <span
      className={`rounded-full px-2 py-0.5 text-xs font-medium ${
        active ? "bg-success/15 text-success" : "bg-text-muted/15 text-text-muted"
      }`}
    >
      {active ? t("products.statusActive") : t("products.statusInactive")}
    </span>
  );
}

export function ProductsScreen({ canManage }: { canManage: boolean }) {
  const [page, setPage] = useState(1);
  const [categoryId, setCategoryId] = useState("");
  const [activeFilter, setActiveFilter] = useState("");
  const [q, setQ] = useState("");
  const [createOpen, setCreateOpen] = useState(false);
  const createHeadingRef = useRef<HTMLHeadingElement>(null);
  const newButtonRef = useRef<HTMLButtonElement>(null);
  const isFirstCreateToggle = useRef(true);

  const units = useUnits();
  const categories = useCategories();
  const products = useProducts(page, {
    categoryId: categoryId ? Number(categoryId) : undefined,
    active: activeFilter ? activeFilter === "true" : undefined,
    q: q || undefined,
  });
  const createProduct = useCreateProduct();
  const status = useActionStatus();
  const categoryFilterId = useId();
  const activeFilterId = useId();
  const searchId = useId();

  useEffect(() => {
    if (isFirstCreateToggle.current) {
      isFirstCreateToggle.current = false;
      return;
    }
    if (createOpen) {
      createHeadingRef.current?.focus();
    } else {
      newButtonRef.current?.focus();
    }
  }, [createOpen]);

  function withFilterReset<T>(setter: (value: T) => void) {
    return (value: T) => {
      setPage(1);
      setter(value);
    };
  }

  function closeCreateForm() {
    setCreateOpen(false);
    createProduct.reset();
  }

  return (
    <div>
      <div className="mb-5 flex items-center justify-between">
        <h1 className="font-display text-2xl text-text">{t("products.title")}</h1>
        {canManage && !createOpen && (
          <Button
            ref={newButtonRef}
            variant="primary"
            onClick={() => {
              setCreateOpen(true);
            }}
          >
            {t("products.newButton")}
          </Button>
        )}
      </div>

      {createOpen && (
        <div className="mb-5 rounded-md border border-border-subtle bg-surface-raised p-4">
          <h2
            ref={createHeadingRef}
            tabIndex={-1}
            className="font-display mb-3 text-base text-text outline-none"
          >
            {t("products.createFormTitle")}
          </h2>
          {(units.isPending || categories.isPending) && (
            <SectionLoading label={t("products.loading")} />
          )}
          {(units.isError || categories.isError) && (
            <SectionError
              message={t("products.loadError")}
              error={units.error ?? categories.error}
              onRetry={() => {
                void units.refetch();
                void categories.refetch();
              }}
            />
          )}
          {units.data && categories.data && (
            <ProductForm
              units={units.data.data}
              categories={categories.data.data}
              submitLabel={t("products.createSubmit")}
              submittingLabel={t("products.createSubmitting")}
              errorKind="create"
              isPending={createProduct.isPending}
              isError={createProduct.isError}
              error={createProduct.error}
              showActiveToggle={false}
              onCancel={closeCreateForm}
              onSubmit={(input) => {
                createProduct.mutate(input, {
                  onSuccess: () => {
                    status.succeed(t("products.createSuccess"));
                    closeCreateForm();
                  },
                });
              }}
            />
          )}
        </div>
      )}

      <div className="mb-4 flex flex-wrap items-end gap-3">
        <div>
          <label htmlFor={categoryFilterId} className="mb-1 block text-sm font-medium text-text">
            {t("products.filterCategoryLabel")}
          </label>
          <select
            id={categoryFilterId}
            value={categoryId}
            onChange={(event) => {
              withFilterReset(setCategoryId)(event.target.value);
            }}
            // The create form (once open) has its own "Categoria" field;
            // this distinguishes the two for assistive tech that looks up
            // a control by its accessible name (WCAG 2.5.3 still holds:
            // the visible label text stays a substring of this name).
            aria-label={t("products.filterCategoryAriaLabel")}
            className="h-9 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          >
            <option value="">{t("products.filterCategoryAll")}</option>
            {categories.data?.data.map((category) => (
              <option key={category.id} value={category.id}>
                {category.name}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor={activeFilterId} className="mb-1 block text-sm font-medium text-text">
            {t("products.filterActiveLabel")}
          </label>
          <select
            id={activeFilterId}
            value={activeFilter}
            onChange={(event) => {
              withFilterReset(setActiveFilter)(event.target.value);
            }}
            className="h-9 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          >
            <option value="">{t("products.filterActiveAll")}</option>
            <option value="true">{t("products.filterActiveOnly")}</option>
            <option value="false">{t("products.filterInactiveOnly")}</option>
          </select>
        </div>
        <div>
          <label htmlFor={searchId} className="mb-1 block text-sm font-medium text-text">
            {t("products.searchLabel")}
          </label>
          <input
            id={searchId}
            type="search"
            placeholder={t("products.searchPlaceholder")}
            value={q}
            onChange={(event) => {
              withFilterReset(setQ)(event.target.value);
            }}
            className="h-9 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          />
        </div>
      </div>

      <StatusMessage status={status.status} />

      {products.isPending && <SectionLoading label={t("products.loading")} />}
      {products.isError && (
        <SectionError
          message={t("products.loadError")}
          error={products.error}
          onRetry={() => {
            void products.refetch();
          }}
        />
      )}
      {products.data?.data.length === 0 && (
        <p className="text-sm text-text-muted">{t("products.empty")}</p>
      )}
      {products.data && products.data.data.length > 0 && (
        <div>
          <table className="w-full border-collapse text-sm">
            <caption className="sr-only">{t("products.title")}</caption>
            <thead>
              <tr className="border-b border-border-subtle text-left text-text-muted">
                <th className="py-2 pr-3 font-medium">{t("products.tableSku")}</th>
                <th className="py-2 pr-3 font-medium">{t("products.tableName")}</th>
                <th className="py-2 pr-3 font-medium">{t("products.tableCategory")}</th>
                <th className="py-2 pr-3 font-medium">{t("products.tableUnit")}</th>
                <th className="py-2 pr-3 text-right font-medium">
                  {t("products.tableConversion")}
                </th>
                <th className="py-2 font-medium">{t("products.tableStatus")}</th>
              </tr>
            </thead>
            <tbody>
              {products.data.data.map((product) => (
                <tr
                  key={product.id}
                  className="border-b border-border-subtle last:border-0 hover:bg-row-hover"
                >
                  <td className="py-2 pr-3">
                    <Link
                      to={`/estoque/produtos/${String(product.id)}`}
                      className="text-accent underline-offset-2 hover:underline"
                    >
                      {product.sku}
                    </Link>
                  </td>
                  <td className="py-2 pr-3 text-text">{product.name}</td>
                  <td className="py-2 pr-3 text-text-muted">
                    {product.category?.name ?? t("products.noCategory")}
                  </td>
                  <td className="py-2 pr-3 text-text-muted">{product.stock_unit.code}</td>
                  <td className="num py-2 pr-3 text-right text-text-muted">
                    {formatQuantity(product.unit_conversion.factor)}{" "}
                    {product.unit_conversion.purchase_unit.code}
                  </td>
                  <td className="py-2">
                    <StatusBadge active={product.active} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <PaginationControls
            page={products.data.meta.page}
            perPage={products.data.meta.per_page}
            total={products.data.meta.total}
            onPage={setPage}
          />
        </div>
      )}
    </div>
  );
}

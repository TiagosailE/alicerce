import { Link, useParams } from "react-router-dom";
import { SectionError } from "../../components/ui/SectionError";
import { SectionLoading } from "../../components/ui/SectionLoading";
import { StatusMessage, useActionStatus } from "../../components/ui/StatusMessage";
import { formatQuantity } from "../../lib/format";
import { t } from "../../i18n";
import { useCategories, useProduct, useUnits, useUpdateProduct } from "./api";
import { ProductForm, productToInitial } from "./ProductForm";

function ReadOnlyField({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-sm font-medium text-text-muted">{label}</dt>
      <dd className="text-sm text-text">{value}</dd>
    </div>
  );
}

export function ProductDetailScreen({ canManage }: { canManage: boolean }) {
  const { id } = useParams<{ id: string }>();
  const productId = Number(id);
  const product = useProduct(productId);
  const units = useUnits();
  const categories = useCategories();
  const updateProduct = useUpdateProduct();
  const status = useActionStatus();

  return (
    <div>
      <p className="mb-4">
        <Link
          to="/estoque/produtos"
          className="text-sm text-accent underline-offset-2 hover:underline"
        >
          {t("products.backToList")}
        </Link>
      </p>

      {product.isPending && <SectionLoading label={t("products.detailLoading")} />}
      {product.isError && (
        <SectionError
          message={t("products.detailLoadError")}
          error={product.error}
          onRetry={() => {
            void product.refetch();
          }}
        />
      )}

      {product.data && (
        <div>
          <h1 className="font-display mb-5 text-2xl text-text">{product.data.name}</h1>
          <StatusMessage status={status.status} />

          {canManage && (units.isPending || categories.isPending) && (
            <SectionLoading label={t("products.loading")} />
          )}
          {canManage && (units.isError || categories.isError) && (
            <SectionError
              message={t("products.loadError")}
              error={units.error ?? categories.error}
              onRetry={() => {
                void units.refetch();
                void categories.refetch();
              }}
            />
          )}
          {canManage && units.data && categories.data ? (
            <ProductForm
              units={units.data.data}
              categories={categories.data.data}
              initial={productToInitial(product.data)}
              submitLabel={t("products.updateSubmit")}
              submittingLabel={t("products.updateSubmitting")}
              errorKind="update"
              isPending={updateProduct.isPending}
              isError={updateProduct.isError}
              error={updateProduct.error}
              showActiveToggle
              onSubmit={(input) => {
                updateProduct.mutate(
                  { id: productId, ...input },
                  {
                    onSuccess: () => {
                      status.succeed(t("products.updateSuccess"));
                    },
                  },
                );
              }}
            />
          ) : !canManage ? (
            <dl className="grid max-w-2xl grid-cols-1 gap-4 sm:grid-cols-2">
              <ReadOnlyField label={t("products.skuLabel")} value={product.data.sku} />
              <ReadOnlyField
                label={t("products.categoryLabel")}
                value={product.data.category?.name ?? t("products.noCategory")}
              />
              <ReadOnlyField
                label={t("products.stockUnitLabel")}
                value={`${product.data.stock_unit.name} (${product.data.stock_unit.code})`}
              />
              <ReadOnlyField
                label={t("products.purchaseUnitLabel")}
                value={`${product.data.unit_conversion.purchase_unit.name} (${product.data.unit_conversion.purchase_unit.code})`}
              />
              <ReadOnlyField
                label={t("products.factorLabel")}
                value={formatQuantity(product.data.unit_conversion.factor)}
              />
              <ReadOnlyField
                label={t("products.activeLabel")}
                value={product.data.active ? t("common.statusActive") : t("common.statusInactive")}
              />
            </dl>
          ) : null}
        </div>
      )}
    </div>
  );
}

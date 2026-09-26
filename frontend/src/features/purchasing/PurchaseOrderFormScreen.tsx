import { useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { SectionError } from "../../components/ui/SectionError";
import { SectionLoading } from "../../components/ui/SectionLoading";
import { t, tf } from "../../i18n";
import { useCreatePurchaseOrder, usePurchaseOrder, useUpdatePurchaseOrder } from "./api";
import { emptyOrderValues, orderToValues, PurchaseOrderForm } from "./PurchaseOrderForm";

/** A new draft. Saving opens the order itself, where it can be approved. */
export function NewPurchaseOrderScreen() {
  const create = useCreatePurchaseOrder();
  const navigate = useNavigate();

  return (
    <div>
      <p className="mb-4">
        <Link to="/compras" className="text-sm text-accent underline-offset-2 hover:underline">
          {t("purchasing.backToList")}
        </Link>
      </p>
      <h1 className="font-display mb-5 text-2xl text-text">{t("purchasing.createFormTitle")}</h1>
      <PurchaseOrderForm
        initial={emptyOrderValues()}
        isPending={create.isPending}
        error={create.error}
        onSubmit={(input) => {
          create.mutate(input, {
            onSuccess: (order) => {
              void navigate(`/compras/${String(order.id)}`);
            },
          });
        }}
        onCancel={() => {
          void navigate("/compras");
        }}
      />
    </div>
  );
}

/** Editing a draft, from the revision that was read: someone else's edit in the
 * meantime answers stale, and the form offers to reload what is stored now. */
export function EditPurchaseOrderScreen() {
  const { id } = useParams<{ id: string }>();
  const orderId = Number(id);
  const order = usePurchaseOrder(orderId);
  const update = useUpdatePurchaseOrder();
  const navigate = useNavigate();
  // Remounts the form with the reloaded values, since its fields keep their own state.
  const [formKey, setFormKey] = useState(0);
  const current = order.data;

  return (
    <div>
      <p className="mb-4">
        <Link
          to={`/compras/${String(orderId)}`}
          className="text-sm text-accent underline-offset-2 hover:underline"
        >
          {t("purchasing.backToList")}
        </Link>
      </p>

      {order.isPending && <SectionLoading label={t("purchasing.detailLoading")} />}
      {order.isError && (
        <SectionError
          message={t("purchasing.detailLoadError")}
          error={order.error}
          onRetry={() => {
            void order.refetch();
          }}
        />
      )}
      {current && current.status !== "draft" && (
        <p role="alert" className="text-sm text-danger">
          {t("purchasing.editNotDraft")}
        </p>
      )}
      {current?.status === "draft" && (
        <div>
          <h1 className="font-display mb-5 text-2xl text-text">
            {tf("purchasing.editFormTitle", { number: String(current.number) })}
          </h1>
          <PurchaseOrderForm
            key={formKey}
            initial={orderToValues(current)}
            isPending={update.isPending}
            error={update.error}
            onSubmit={(input) => {
              update.mutate(
                { id: current.id, revision: current.revision, ...input },
                {
                  onSuccess: () => {
                    void navigate(`/compras/${String(current.id)}`);
                  },
                },
              );
            }}
            onCancel={() => {
              void navigate(`/compras/${String(current.id)}`);
            }}
            onReload={() => {
              void order.refetch().then(() => {
                update.reset();
                setFormKey((key) => key + 1);
              });
            }}
          />
        </div>
      )}
    </div>
  );
}

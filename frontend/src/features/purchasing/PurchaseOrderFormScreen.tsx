import { useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { ApiError } from "../../api/client";
import { SectionError } from "../../components/ui/SectionError";
import { SectionLoading } from "../../components/ui/SectionLoading";
import { t, tf } from "../../i18n";
import {
  type PurchaseOrder,
  useCreatePurchaseOrder,
  usePurchaseOrder,
  useUpdatePurchaseOrder,
} from "./api";
import { emptyOrderValues, orderToValues, PurchaseOrderForm } from "./PurchaseOrderForm";
import { orderIdFromParam, SAVED_STATE } from "./purchasingLabels";

const linkClass = "text-sm text-accent underline-offset-2 hover:underline";

/** A new draft. Saving opens the order itself, where it can be approved. */
export function NewPurchaseOrderScreen() {
  const create = useCreatePurchaseOrder();
  const navigate = useNavigate();

  return (
    <div>
      <p className="mb-4">
        <Link to="/compras" className={linkClass}>
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
              void navigate(`/compras/${String(order.id)}`, { state: SAVED_STATE });
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

/** The form for a draft, opened on what was stored when it mounted. The form
 * keeps its own copy of the fields, so the revision it saves against has to be
 * the one those fields were read at, not whatever the query holds by the time
 * the button is pressed: a newer revision fetched in the meantime would let this
 * save overwrite someone else's edit without the stale answer (ADR 0015). */
function EditDraftForm({ order, onReload }: { order: PurchaseOrder; onReload: () => void }) {
  const update = useUpdatePurchaseOrder();
  const navigate = useNavigate();
  const [opened] = useState(() => ({ revision: order.revision, values: orderToValues(order) }));

  return (
    <PurchaseOrderForm
      initial={opened.values}
      isPending={update.isPending}
      error={update.error}
      onSubmit={(input) => {
        update.mutate(
          { id: order.id, revision: opened.revision, ...input },
          {
            onSuccess: () => {
              void navigate(`/compras/${String(order.id)}`, { state: SAVED_STATE });
            },
          },
        );
      }}
      onCancel={() => {
        void navigate(`/compras/${String(order.id)}`);
      }}
      onReload={onReload}
    />
  );
}

/** Editing a draft, from the revision that was read: someone else's edit in the
 * meantime answers stale, and the form offers to reload what is stored now. */
export function EditPurchaseOrderScreen() {
  const { id } = useParams<{ id: string }>();
  const orderId = orderIdFromParam(id);
  const order = usePurchaseOrder(orderId);
  // Remounts the form with the reloaded order, since it keeps its own state.
  const [formKey, setFormKey] = useState(0);
  const current = order.data;
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
          <EditDraftForm
            key={formKey}
            order={current}
            onReload={() => {
              void order.refetch().then((result) => {
                if (result.isSuccess) setFormKey((key) => key + 1);
              });
            }}
          />
        </div>
      )}
    </div>
  );
}

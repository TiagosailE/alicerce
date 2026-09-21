import { useEffect, useId, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { Button } from "../../components/ui/Button";
import { PaginationControls } from "../../components/ui/PaginationControls";
import { SectionError } from "../../components/ui/SectionError";
import { SectionLoading } from "../../components/ui/SectionLoading";
import { StatusBadge } from "../../components/ui/StatusBadge";
import { StatusMessage, useActionStatus } from "../../components/ui/StatusMessage";
import { t } from "../../i18n";
import { useCreatePartner, usePartners } from "./api";
import { PartnerForm, partnerKindLabel } from "./PartnerForm";

function tristateToBoolean(value: string): boolean | undefined {
  return value ? value === "true" : undefined;
}

export function PartnersScreen({ canManage }: { canManage: boolean }) {
  const [page, setPage] = useState(1);
  const [customerFilter, setCustomerFilter] = useState("");
  const [supplierFilter, setSupplierFilter] = useState("");
  const [activeFilter, setActiveFilter] = useState("");
  const [q, setQ] = useState("");
  const [createOpen, setCreateOpen] = useState(false);
  const createHeadingRef = useRef<HTMLHeadingElement>(null);
  const newButtonRef = useRef<HTMLButtonElement>(null);
  const isFirstCreateToggle = useRef(true);

  const partners = usePartners(page, {
    customer: tristateToBoolean(customerFilter),
    supplier: tristateToBoolean(supplierFilter),
    active: tristateToBoolean(activeFilter),
    q: q || undefined,
  });
  const createPartner = useCreatePartner();
  const status = useActionStatus();
  const customerFilterId = useId();
  const supplierFilterId = useId();
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
    createPartner.reset();
  }

  return (
    <div>
      <div className="mb-5 flex items-center justify-between">
        <h1 className="font-display text-2xl text-text">{t("partners.title")}</h1>
        {canManage && !createOpen && (
          <Button
            ref={newButtonRef}
            variant="primary"
            onClick={() => {
              setCreateOpen(true);
            }}
          >
            {t("partners.newButton")}
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
            {t("partners.createFormTitle")}
          </h2>
          <PartnerForm
            submitLabel={t("partners.createSubmit")}
            submittingLabel={t("partners.createSubmitting")}
            errorKind="create"
            isPending={createPartner.isPending}
            isError={createPartner.isError}
            error={createPartner.error}
            showActiveToggle={false}
            onCancel={closeCreateForm}
            onSubmit={(input) => {
              createPartner.mutate(input, {
                onSuccess: () => {
                  status.succeed(t("partners.createSuccess"));
                  closeCreateForm();
                },
              });
            }}
          />
        </div>
      )}

      <div className="mb-4 flex flex-wrap items-end gap-3">
        <div>
          <label htmlFor={customerFilterId} className="mb-1 block text-sm font-medium text-text">
            {t("partners.filterCustomerLabel")}
          </label>
          <select
            id={customerFilterId}
            value={customerFilter}
            onChange={(event) => {
              withFilterReset(setCustomerFilter)(event.target.value);
            }}
            // The create form (once open) has its own "Cliente" checkbox;
            // this distinguishes the two for assistive tech that looks up
            // a control by its accessible name (same reasoning as the
            // products screen's category filter).
            aria-label={t("partners.filterCustomerAriaLabel")}
            className="h-9 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          >
            <option value="">{t("partners.filterAll")}</option>
            <option value="true">{t("partners.filterYes")}</option>
            <option value="false">{t("partners.filterNo")}</option>
          </select>
        </div>
        <div>
          <label htmlFor={supplierFilterId} className="mb-1 block text-sm font-medium text-text">
            {t("partners.filterSupplierLabel")}
          </label>
          <select
            id={supplierFilterId}
            value={supplierFilter}
            onChange={(event) => {
              withFilterReset(setSupplierFilter)(event.target.value);
            }}
            aria-label={t("partners.filterSupplierAriaLabel")}
            className="h-9 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          >
            <option value="">{t("partners.filterAll")}</option>
            <option value="true">{t("partners.filterYes")}</option>
            <option value="false">{t("partners.filterNo")}</option>
          </select>
        </div>
        <div>
          <label htmlFor={activeFilterId} className="mb-1 block text-sm font-medium text-text">
            {t("partners.filterActiveLabel")}
          </label>
          <select
            id={activeFilterId}
            value={activeFilter}
            onChange={(event) => {
              withFilterReset(setActiveFilter)(event.target.value);
            }}
            className="h-9 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          >
            <option value="">{t("partners.filterAll")}</option>
            <option value="true">{t("partners.filterActiveOnly")}</option>
            <option value="false">{t("partners.filterInactiveOnly")}</option>
          </select>
        </div>
        <div>
          <label htmlFor={searchId} className="mb-1 block text-sm font-medium text-text">
            {t("partners.searchLabel")}
          </label>
          <input
            id={searchId}
            type="search"
            placeholder={t("partners.searchPlaceholder")}
            value={q}
            onChange={(event) => {
              withFilterReset(setQ)(event.target.value);
            }}
            className="h-9 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          />
        </div>
      </div>

      <StatusMessage status={status.status} />

      {partners.isPending && <SectionLoading label={t("partners.loading")} />}
      {partners.isError && (
        <SectionError
          message={t("partners.loadError")}
          error={partners.error}
          onRetry={() => {
            void partners.refetch();
          }}
        />
      )}
      {partners.data?.data.length === 0 && (
        <p className="text-sm text-text-muted">{t("partners.empty")}</p>
      )}
      {partners.data && partners.data.data.length > 0 && (
        <div>
          <table className="w-full border-collapse text-sm">
            <caption className="sr-only">{t("partners.title")}</caption>
            <thead>
              <tr className="border-b border-border-subtle text-left text-text-muted">
                <th className="py-2 pr-3 font-medium">{t("partners.tableName")}</th>
                <th className="py-2 pr-3 font-medium">{t("partners.tableDocument")}</th>
                <th className="py-2 pr-3 font-medium">{t("partners.tableKind")}</th>
                <th className="py-2 font-medium">{t("partners.tableStatus")}</th>
              </tr>
            </thead>
            <tbody>
              {partners.data.data.map((partner) => (
                <tr
                  key={partner.id}
                  className="border-b border-border-subtle last:border-0 hover:bg-row-hover"
                >
                  <td className="py-2 pr-3">
                    <Link
                      to={`/parceiros/${String(partner.id)}`}
                      className="text-accent underline-offset-2 hover:underline"
                    >
                      {partner.name}
                    </Link>
                  </td>
                  <td className="py-2 pr-3 text-text-muted">
                    {partner.document_type === "cpf"
                      ? t("partners.documentTypeCpf")
                      : t("partners.documentTypeCnpj")}
                    {": "}
                    {partner.document_number}
                  </td>
                  <td className="py-2 pr-3 text-text-muted">{partnerKindLabel(partner)}</td>
                  <td className="py-2">
                    <StatusBadge active={partner.active} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <PaginationControls
            page={partners.data.meta.page}
            perPage={partners.data.meta.per_page}
            total={partners.data.meta.total}
            onPage={setPage}
          />
        </div>
      )}
    </div>
  );
}

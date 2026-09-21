import { Link, useParams } from "react-router-dom";
import { SectionError } from "../../components/ui/SectionError";
import { SectionLoading } from "../../components/ui/SectionLoading";
import { StatusMessage, useActionStatus } from "../../components/ui/StatusMessage";
import { t } from "../../i18n";
import { usePartner, useUpdatePartner } from "./api";
import { PartnerForm, partnerKindLabel, partnerToInitial } from "./PartnerForm";

function ReadOnlyField({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-sm font-medium text-text-muted">{label}</dt>
      <dd className="text-sm text-text">{value}</dd>
    </div>
  );
}

export function PartnerDetailScreen({ canManage }: { canManage: boolean }) {
  const { id } = useParams<{ id: string }>();
  const partnerId = Number(id);
  const partner = usePartner(partnerId);
  const updatePartner = useUpdatePartner();
  const status = useActionStatus();

  return (
    <div>
      <p className="mb-4">
        <Link to="/parceiros" className="text-sm text-accent underline-offset-2 hover:underline">
          {t("partners.backToList")}
        </Link>
      </p>

      {partner.isPending && <SectionLoading label={t("partners.detailLoading")} />}
      {partner.isError && (
        <SectionError
          message={t("partners.detailLoadError")}
          error={partner.error}
          onRetry={() => {
            void partner.refetch();
          }}
        />
      )}

      {partner.data && (
        <div>
          <h1 className="font-display mb-5 text-2xl text-text">{partner.data.name}</h1>
          <StatusMessage status={status.status} />

          {canManage ? (
            <PartnerForm
              initial={partnerToInitial(partner.data)}
              submitLabel={t("partners.updateSubmit")}
              submittingLabel={t("partners.updateSubmitting")}
              errorKind="update"
              isPending={updatePartner.isPending}
              isError={updatePartner.isError}
              error={updatePartner.error}
              showActiveToggle
              onSubmit={(input) => {
                updatePartner.mutate(
                  { id: partnerId, ...input },
                  {
                    onSuccess: () => {
                      status.succeed(t("partners.updateSuccess"));
                    },
                  },
                );
              }}
            />
          ) : (
            <dl className="grid max-w-2xl grid-cols-1 gap-4 sm:grid-cols-2">
              <ReadOnlyField
                label={t("partners.documentTypeLabel")}
                value={
                  partner.data.document_type === "cpf"
                    ? t("partners.documentTypeCpf")
                    : t("partners.documentTypeCnpj")
                }
              />
              <ReadOnlyField
                label={t("partners.documentNumberLabel")}
                value={partner.data.document_number}
              />
              <ReadOnlyField
                label={t("partners.kindLabel")}
                value={partnerKindLabel(partner.data)}
              />
              <ReadOnlyField
                label={t("partners.emailLabel")}
                value={partner.data.email ?? t("partners.notInformed")}
              />
              <ReadOnlyField
                label={t("partners.phoneLabel")}
                value={partner.data.phone ?? t("partners.notInformed")}
              />
              <ReadOnlyField
                label={t("partners.activeLabel")}
                value={partner.data.active ? t("common.statusActive") : t("common.statusInactive")}
              />
            </dl>
          )}
        </div>
      )}
    </div>
  );
}

import { type SubmitEvent, useId, useState } from "react";
import { ApiError } from "../../api/client";
import { Button } from "../../components/ui/Button";
import { Spinner } from "../../components/ui/Spinner";
import { apiFieldErrors, fieldErrorMessage, isStale, requestIdSuffix } from "../../lib/errors";
import { type MessageKey, t } from "../../i18n";
import type { Partner, PartnerInput } from "./api";

// The API maps a validation_failed error to details.fields: { field: [kind,
// ...] } (api-contract skill); each field here is the Rails attribute name a
// command's Result.invalid reports. "base" is Catalog::Partner's
// cross-field validation (neither customer nor supplier), shown under the
// two checkboxes rather than under a single input.
const FIELD_ERROR_KEYS: Record<string, Partial<Record<string, MessageKey>>> = {
  name: { blank: "partners.fieldErrorNameBlank" },
  document_type: {
    blank: "partners.fieldErrorDocumentTypeBlank",
    inclusion: "partners.fieldErrorDocumentTypeBlank",
  },
  document_number: {
    blank: "partners.fieldErrorDocumentNumberBlank",
    taken: "partners.fieldErrorDocumentNumberTaken",
    invalid: "partners.fieldErrorDocumentNumberInvalid",
  },
  base: { must_be_customer_or_supplier: "partners.fieldErrorMustBeCustomerOrSupplier" },
};

// The backend does not validate email format at all (app/models/catalog/
// partner.rb): a free-text field the API happily stores as typed. This is
// purely a client-side courtesy check, so it needs its own error state
// (form-noValidate turns off the browser's native "invalid email" bubble,
// which has no pt-BR text and no link to this form's error styling) and
// only applies once a submit has actually been attempted, the same way an
// API error only starts showing after the first failed request.
const EMAIL_FORMAT = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function isValidEmail(value: string): boolean {
  return EMAIL_FORMAT.test(value);
}

function partnerErrorMessage(error: unknown, kind: "create" | "update"): string {
  if (isStale(error)) return t("partners.updateStaleError");
  if (error instanceof ApiError && error.code === "validation_failed") {
    return kind === "create"
      ? t("partners.createValidationError")
      : t("partners.updateValidationError");
  }
  return kind === "create" ? t("partners.createGenericError") : t("partners.updateGenericError");
}

/** Shared by the create form (PartnersScreen) and the edit form
 * (PartnerDetailScreen): same fields either way, only the submit label,
 * the active toggle and what happens on success differ (ProductForm's
 * pattern). */
export function PartnerForm({
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
  initial?: Partial<PartnerInput & { active: boolean }>;
  submitLabel: string;
  submittingLabel: string;
  errorKind: "create" | "update";
  isPending: boolean;
  isError: boolean;
  error: unknown;
  showActiveToggle: boolean;
  onSubmit: (input: PartnerInput & { active: boolean }) => void;
  onCancel?: () => void;
}) {
  const [name, setName] = useState(initial?.name ?? "");
  const [documentType, setDocumentType] = useState<"cpf" | "cnpj">(initial?.documentType ?? "cpf");
  const [documentNumber, setDocumentNumber] = useState(initial?.documentNumber ?? "");
  const [email, setEmail] = useState(initial?.email ?? "");
  const [phone, setPhone] = useState(initial?.phone ?? "");
  const [customer, setCustomer] = useState(initial?.customer ?? false);
  const [supplier, setSupplier] = useState(initial?.supplier ?? false);
  const [active, setActive] = useState(initial?.active ?? true);
  const [submitAttempted, setSubmitAttempted] = useState(false);
  const nameId = useId();
  const documentTypeId = useId();
  const documentNumberId = useId();
  const emailId = useId();
  const phoneId = useId();
  const customerId = useId();
  const supplierId = useId();
  const activeId = useId();
  const errorId = useId();
  const nameErrorId = useId();
  const documentTypeErrorId = useId();
  const documentNumberErrorId = useId();
  const customerOrSupplierErrorId = useId();
  const emailErrorId = useId();

  const fieldErrors = isError ? apiFieldErrors(error) : {};
  const nameError = fieldErrorMessage(
    fieldErrors,
    "name",
    FIELD_ERROR_KEYS,
    "partners.fieldErrorGeneric",
  );
  const documentTypeError = fieldErrorMessage(
    fieldErrors,
    "document_type",
    FIELD_ERROR_KEYS,
    "partners.fieldErrorGeneric",
  );
  const documentNumberError = fieldErrorMessage(
    fieldErrors,
    "document_number",
    FIELD_ERROR_KEYS,
    "partners.fieldErrorGeneric",
  );
  const customerOrSupplierError = fieldErrorMessage(
    fieldErrors,
    "base",
    FIELD_ERROR_KEYS,
    "partners.fieldErrorGeneric",
  );
  const emailError =
    submitAttempted && email.trim() && !isValidEmail(email.trim())
      ? t("partners.fieldErrorEmailInvalid")
      : null;
  // The bottom banner is for whatever a field-level message could not
  // explain; once every reported field already has its own message,
  // repeating the same information at the bottom too would just be noise.
  const hasFieldErrors = Object.keys(fieldErrors).length > 0;

  function submit(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitAttempted(true);
    if (email.trim() && !isValidEmail(email.trim())) return;
    onSubmit({
      name,
      documentType,
      documentNumber,
      customer,
      supplier,
      email,
      phone,
      active,
    });
  }

  return (
    <form onSubmit={submit} noValidate className="max-w-2xl">
      <div className="mb-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <label htmlFor={nameId} className="mb-1 block text-sm font-medium text-text">
            {t("partners.nameLabel")}
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
              {t("partners.activeLabel")}
            </label>
          </div>
        )}
        <div>
          <label htmlFor={documentTypeId} className="mb-1 block text-sm font-medium text-text">
            {t("partners.documentTypeLabel")}
          </label>
          <select
            id={documentTypeId}
            required
            value={documentType}
            onChange={(event) => {
              setDocumentType(event.target.value as "cpf" | "cnpj");
            }}
            aria-describedby={documentTypeError ? documentTypeErrorId : undefined}
            className="h-9 w-full rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          >
            <option value="cpf">{t("partners.documentTypeCpf")}</option>
            <option value="cnpj">{t("partners.documentTypeCnpj")}</option>
          </select>
          {documentTypeError && (
            <p id={documentTypeErrorId} role="alert" className="mt-1 text-xs text-danger">
              {documentTypeError}
            </p>
          )}
        </div>
        <div>
          <label htmlFor={documentNumberId} className="mb-1 block text-sm font-medium text-text">
            {t("partners.documentNumberLabel")}
          </label>
          <input
            id={documentNumberId}
            type="text"
            required
            value={documentNumber}
            onChange={(event) => {
              setDocumentNumber(event.target.value);
            }}
            aria-describedby={documentNumberError ? documentNumberErrorId : undefined}
            className="h-9 w-full rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          />
          {documentNumberError && (
            <p id={documentNumberErrorId} role="alert" className="mt-1 text-xs text-danger">
              {documentNumberError}
            </p>
          )}
        </div>
        <div>
          <label htmlFor={emailId} className="mb-1 block text-sm font-medium text-text">
            {t("partners.emailLabel")}
          </label>
          <input
            id={emailId}
            type="email"
            value={email}
            onChange={(event) => {
              setEmail(event.target.value);
            }}
            aria-describedby={emailError ? emailErrorId : undefined}
            className="h-9 w-full rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          />
          {emailError && (
            <p id={emailErrorId} role="alert" className="mt-1 text-xs text-danger">
              {emailError}
            </p>
          )}
        </div>
        <div>
          <label htmlFor={phoneId} className="mb-1 block text-sm font-medium text-text">
            {t("partners.phoneLabel")}
          </label>
          <input
            id={phoneId}
            type="tel"
            value={phone}
            onChange={(event) => {
              setPhone(event.target.value);
            }}
            className="h-9 w-full rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          />
        </div>
        <fieldset className="m-0 border-0 p-0">
          <legend className="mb-1 block text-sm font-medium text-text">
            {t("partners.kindLabel")}
          </legend>
          <div className="flex flex-col gap-2">
            <div className="flex items-center gap-2">
              <input
                id={customerId}
                type="checkbox"
                checked={customer}
                onChange={(event) => {
                  setCustomer(event.target.checked);
                }}
                aria-describedby={customerOrSupplierError ? customerOrSupplierErrorId : undefined}
                className="h-5 w-5 accent-accent rounded border-border-strong focus-visible:outline-2 focus-visible:outline-focus"
              />
              <label htmlFor={customerId} className="text-sm text-text">
                {t("partners.customerLabel")}
              </label>
            </div>
            <div className="flex items-center gap-2">
              <input
                id={supplierId}
                type="checkbox"
                checked={supplier}
                onChange={(event) => {
                  setSupplier(event.target.checked);
                }}
                aria-describedby={customerOrSupplierError ? customerOrSupplierErrorId : undefined}
                className="h-5 w-5 accent-accent rounded border-border-strong focus-visible:outline-2 focus-visible:outline-focus"
              />
              <label htmlFor={supplierId} className="text-sm text-text">
                {t("partners.supplierLabel")}
              </label>
            </div>
          </div>
          {customerOrSupplierError && (
            <p id={customerOrSupplierErrorId} role="alert" className="mt-1 text-xs text-danger">
              {customerOrSupplierError}
            </p>
          )}
        </fieldset>
      </div>

      <div className="flex items-center gap-3">
        <Button type="submit" variant="primary" disabled={isPending}>
          {isPending && <Spinner />}
          {isPending ? submittingLabel : submitLabel}
        </Button>
        {onCancel && (
          <Button variant="quiet" type="button" onClick={onCancel} disabled={isPending}>
            {t("partners.createCancel")}
          </Button>
        )}
      </div>
      {isError && !hasFieldErrors && (
        <p id={errorId} role="alert" className="mt-2 text-sm text-danger">
          {partnerErrorMessage(error, errorKind)}
          {requestIdSuffix(error)}
        </p>
      )}
      {isError && hasFieldErrors && requestIdSuffix(error) && (
        <p className="mt-2 text-xs text-text-muted">{requestIdSuffix(error).trim()}</p>
      )}
    </form>
  );
}

export function partnerToInitial(partner: Partner): PartnerInput & { active: boolean } {
  return {
    name: partner.name,
    documentType: partner.document_type,
    documentNumber: partner.document_number,
    customer: partner.customer,
    supplier: partner.supplier,
    email: partner.email ?? "",
    phone: partner.phone ?? "",
    active: partner.active,
  };
}

/** Mirrors Catalog::Partner's own customer_or_supplier validation: at least
 * one is always true, so "neither" never needs a label. */
export function partnerKindLabel(partner: Pick<Partner, "customer" | "supplier">): string {
  if (partner.customer && partner.supplier) return t("partners.kindBoth");
  if (partner.customer) return t("partners.kindCustomer");
  return t("partners.kindSupplier");
}

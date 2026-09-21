import { type RefObject, type SubmitEvent, useEffect, useId, useRef, useState } from "react";
import { ApiError } from "../../api/client";
import { Button } from "../../components/ui/Button";
import { PaginationControls } from "../../components/ui/PaginationControls";
import { SectionError } from "../../components/ui/SectionError";
import { SectionLoading } from "../../components/ui/SectionLoading";
import { Spinner } from "../../components/ui/Spinner";
import { StatusBadge } from "../../components/ui/StatusBadge";
import { StatusMessage, useActionStatus } from "../../components/ui/StatusMessage";
import { requestIdSuffix } from "../../lib/errors";
import { type MessageKey, t } from "../../i18n";
import { type Warehouse, useCreateWarehouse, useUpdateWarehouse, useWarehouses } from "./api";

// The API maps a validation_failed error to details.fields: { name: [kind,
// ...] } (api-contract skill); name is the only field this form can ever
// reject (blank or a duplicate within the organization).
const FIELD_ERROR_KEYS: Partial<Record<string, MessageKey>> = {
  blank: "warehouses.fieldErrorNameBlank",
  taken: "warehouses.fieldErrorNameTaken",
};

function apiFieldErrors(error: unknown): Record<string, string[]> {
  if (!(error instanceof ApiError) || error.code !== "validation_failed") return {};
  const fields: unknown = error.details.fields;
  if (!fields || typeof fields !== "object") return {};
  return fields as Record<string, string[]>;
}

function nameErrorMessage(error: unknown): string | null {
  const kind = apiFieldErrors(error).name?.[0];
  if (!kind) return null;
  const key = FIELD_ERROR_KEYS[kind];
  return key ? t(key) : t("warehouses.fieldErrorGeneric");
}

function genericErrorMessage(error: unknown, kind: "create" | "update"): string {
  if (error instanceof ApiError && error.code === "validation_failed") {
    return kind === "create"
      ? t("warehouses.createValidationError")
      : t("warehouses.updateValidationError");
  }
  return kind === "create"
    ? t("warehouses.createGenericError")
    : t("warehouses.updateGenericError");
}

function CreateWarehouseForm({
  headingRef,
  mutation,
  onCreated,
  onCancel,
}: {
  headingRef: RefObject<HTMLHeadingElement | null>;
  mutation: ReturnType<typeof useCreateWarehouse>;
  onCreated: () => void;
  onCancel: () => void;
}) {
  const [name, setName] = useState("");
  const nameId = useId();
  const nameErrorId = useId();
  const nameError = mutation.isError ? nameErrorMessage(mutation.error) : null;

  function submit(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    mutation.mutate(name, {
      onSuccess: () => {
        setName("");
        onCreated();
      },
    });
  }

  return (
    <div className="mb-5 rounded-md border border-border-subtle bg-surface-raised p-4">
      <h2
        ref={headingRef}
        tabIndex={-1}
        className="font-display mb-3 text-base text-text outline-none"
      >
        {t("warehouses.createFormTitle")}
      </h2>
      <form onSubmit={submit} className="flex flex-wrap items-end gap-3">
        <div>
          <label htmlFor={nameId} className="mb-1 block text-sm font-medium text-text">
            {t("warehouses.nameLabel")}
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
            className="h-9 w-64 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          />
          {nameError && (
            <p id={nameErrorId} role="alert" className="mt-1 text-xs text-danger">
              {nameError}
            </p>
          )}
        </div>
        <Button type="submit" variant="primary" disabled={mutation.isPending}>
          {mutation.isPending && <Spinner />}
          {mutation.isPending ? t("warehouses.savingButton") : t("warehouses.saveButton")}
        </Button>
        <Button variant="quiet" type="button" onClick={onCancel} disabled={mutation.isPending}>
          {t("warehouses.cancelButton")}
        </Button>
      </form>
      {mutation.isError && !nameError && (
        <p role="alert" className="mt-2 text-sm text-danger">
          {genericErrorMessage(mutation.error, "create")}
          {requestIdSuffix(mutation.error)}
        </p>
      )}
    </div>
  );
}

function WarehouseRow({
  warehouse,
  canManage,
  editing,
  editDisabled,
  onEdit,
  onCancelEdit,
  onSave,
  savePending,
  saveError,
}: {
  warehouse: Warehouse;
  canManage: boolean;
  editing: boolean;
  editDisabled: boolean;
  onEdit: () => void;
  onCancelEdit: () => void;
  onSave: (input: { name: string; active: boolean }) => void;
  savePending: boolean;
  saveError: unknown;
}) {
  const editButtonRef = useRef<HTMLButtonElement>(null);
  const wasEditing = useRef(false);

  // Same reasoning as the create form's focus management: a row toggling
  // into and out of an inline form is not a real navigation, so nothing
  // else moves focus for a keyboard or screen reader user. Only the
  // "return focus to the button that opened it" half lives here: this
  // component stays mounted across the toggle, unlike WarehouseEditRow
  // below, which mounts fresh every time editing starts.
  useEffect(() => {
    if (!editing && wasEditing.current) {
      editButtonRef.current?.focus();
    }
    wasEditing.current = editing;
  }, [editing]);

  if (editing) {
    return (
      <WarehouseEditRow
        warehouse={warehouse}
        onCancelEdit={onCancelEdit}
        onSave={onSave}
        savePending={savePending}
        saveError={saveError}
      />
    );
  }

  return (
    <tr className="border-b border-border-subtle last:border-0 hover:bg-row-hover">
      <td className="py-2 pr-3 text-text">{warehouse.name}</td>
      <td className="py-2 pr-3">
        <StatusBadge active={warehouse.active} />
      </td>
      <td className="py-2">
        {canManage && (
          <Button
            ref={editButtonRef}
            variant="quiet"
            disabled={editDisabled}
            aria-label={`${t("warehouses.editButton")} ${warehouse.name}`}
            onClick={onEdit}
          >
            {t("warehouses.editButton")}
          </Button>
        )}
      </td>
    </tr>
  );
}

// Mounted only while its row is being edited (WarehouseRow renders it
// conditionally): a fresh instance every time, so its own name/active
// state always starts from the current warehouse, with no need to
// resynchronize it from props inside an effect.
function WarehouseEditRow({
  warehouse,
  onCancelEdit,
  onSave,
  savePending,
  saveError,
}: {
  warehouse: Warehouse;
  onCancelEdit: () => void;
  onSave: (input: { name: string; active: boolean }) => void;
  savePending: boolean;
  saveError: unknown;
}) {
  const [name, setName] = useState(warehouse.name);
  const [active, setActive] = useState(warehouse.active);
  const nameId = useId();
  const nameErrorId = useId();
  const activeId = useId();
  const nameInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    nameInputRef.current?.focus();
  }, []);

  const nameError = saveError ? nameErrorMessage(saveError) : null;

  function submit(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    onSave({ name, active });
  }

  return (
    <tr className="border-b border-border-subtle last:border-0 bg-row-hover">
      <td colSpan={3} className="py-2 pr-3">
        <p className="sr-only" role="status">
          {t("warehouses.editingPrefix")}
          {warehouse.name}
        </p>
        <form onSubmit={submit} className="flex flex-wrap items-end gap-3">
          <div>
            <label htmlFor={nameId} className="mb-1 block text-sm font-medium text-text">
              {t("warehouses.nameLabel")}
            </label>
            <input
              id={nameId}
              ref={nameInputRef}
              type="text"
              required
              value={name}
              onChange={(event) => {
                setName(event.target.value);
              }}
              aria-describedby={nameError ? nameErrorId : undefined}
              className="h-9 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
            />
            {nameError && (
              <p id={nameErrorId} role="alert" className="mt-1 text-xs text-danger">
                {nameError}
              </p>
            )}
          </div>
          <div className="flex items-center gap-2 pb-2">
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
              {t("warehouses.activeLabel")}
            </label>
          </div>
          <Button type="submit" variant="primary" disabled={savePending}>
            {savePending && <Spinner />}
            {savePending ? t("warehouses.savingButton") : t("warehouses.saveButton")}
          </Button>
          <Button variant="quiet" type="button" disabled={savePending} onClick={onCancelEdit}>
            {t("warehouses.cancelButton")}
          </Button>
        </form>
        {Boolean(saveError) && !nameError && (
          <p role="alert" className="mt-2 text-xs text-danger">
            {genericErrorMessage(saveError, "update")}
            {requestIdSuffix(saveError)}
          </p>
        )}
      </td>
    </tr>
  );
}

export function WarehousesScreen({ canManage }: { canManage: boolean }) {
  const [page, setPage] = useState(1);
  const [createOpen, setCreateOpen] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);
  const createHeadingRef = useRef<HTMLHeadingElement>(null);
  const newButtonRef = useRef<HTMLButtonElement>(null);
  const isFirstCreateToggle = useRef(true);

  const warehouses = useWarehouses(page);
  const createWarehouse = useCreateWarehouse();
  const updateWarehouse = useUpdateWarehouse();
  const status = useActionStatus();

  // Only one of the create panel and a row's inline edit form can be open
  // at a time (otherwise two "Nome" fields would be on screen with the
  // same label): reading editingId (deliberately left out of the deps
  // array) skips returning focus to the "Novo depósito" button when the
  // create panel closed because a row edit opened instead of a plain
  // cancel, since WarehouseEditRow's own mount effect already moves focus
  // into that form; deps stay [createOpen] alone so a row's own edit
  // starting or ending, which never touches createOpen, does not
  // needlessly re-run this and steal focus back to the button.
  useEffect(() => {
    if (isFirstCreateToggle.current) {
      isFirstCreateToggle.current = false;
      return;
    }
    if (createOpen) {
      createHeadingRef.current?.focus();
    } else if (editingId === null) {
      newButtonRef.current?.focus();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [createOpen]);

  function closeCreateForm() {
    setCreateOpen(false);
    createWarehouse.reset();
  }

  function openCreateForm() {
    cancelEdit();
    setCreateOpen(true);
  }

  function startEdit(id: number) {
    closeCreateForm();
    updateWarehouse.reset();
    setEditingId(id);
  }

  function cancelEdit() {
    updateWarehouse.reset();
    setEditingId(null);
  }

  return (
    <div>
      <div className="mb-5 flex items-center justify-between">
        <h1 className="font-display text-2xl text-text">{t("warehouses.title")}</h1>
        {canManage && !createOpen && (
          <Button ref={newButtonRef} variant="primary" onClick={openCreateForm}>
            {t("warehouses.newButton")}
          </Button>
        )}
      </div>

      {createOpen && (
        <CreateWarehouseForm
          headingRef={createHeadingRef}
          mutation={createWarehouse}
          onCreated={() => {
            status.succeed(t("warehouses.createSuccess"));
            closeCreateForm();
          }}
          onCancel={closeCreateForm}
        />
      )}

      <StatusMessage status={status.status} />

      {warehouses.isPending && <SectionLoading label={t("warehouses.loading")} />}
      {warehouses.isError && (
        <SectionError
          message={t("warehouses.loadError")}
          error={warehouses.error}
          onRetry={() => {
            void warehouses.refetch();
          }}
        />
      )}
      {warehouses.data?.data.length === 0 && (
        <p className="text-sm text-text-muted">{t("warehouses.empty")}</p>
      )}
      {warehouses.data && warehouses.data.data.length > 0 && (
        <div>
          <table className="w-full border-collapse text-sm">
            <caption className="sr-only">{t("warehouses.title")}</caption>
            <thead>
              <tr className="border-b border-border-subtle text-left text-text-muted">
                <th className="py-2 pr-3 font-medium">{t("warehouses.tableName")}</th>
                <th className="py-2 pr-3 font-medium">{t("warehouses.tableStatus")}</th>
                <th className="py-2 font-medium">{t("warehouses.tableActions")}</th>
              </tr>
            </thead>
            <tbody>
              {warehouses.data.data.map((warehouse) => (
                <WarehouseRow
                  key={warehouse.id}
                  warehouse={warehouse}
                  canManage={canManage}
                  editing={editingId === warehouse.id}
                  editDisabled={updateWarehouse.isPending}
                  onEdit={() => {
                    startEdit(warehouse.id);
                  }}
                  onCancelEdit={cancelEdit}
                  onSave={(input) => {
                    updateWarehouse.mutate(
                      { id: warehouse.id, ...input },
                      {
                        onSuccess: () => {
                          status.succeed(t("warehouses.updateSuccess"));
                          setEditingId(null);
                        },
                      },
                    );
                  }}
                  savePending={updateWarehouse.isPending && editingId === warehouse.id}
                  saveError={editingId === warehouse.id ? updateWarehouse.error : null}
                />
              ))}
            </tbody>
          </table>
          <PaginationControls
            page={warehouses.data.meta.page}
            perPage={warehouses.data.meta.per_page}
            total={warehouses.data.meta.total}
            onPage={setPage}
          />
        </div>
      )}
    </div>
  );
}

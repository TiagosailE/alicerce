import { type SubmitEvent, useId, useState } from "react";
import { ApiError } from "../../api/client";
import { Button } from "../../components/ui/Button";
import { Spinner } from "../../components/ui/Spinner";
import { t } from "../../i18n";
import {
  type Member,
  type PendingInvitation,
  type Role,
  useChangeMemberRole,
  useInviteMember,
  useMembers,
  usePendingInvitations,
  useRemoveMember,
  useRevokeInvitation,
} from "./api";

const ALL_ROLES: Role[] = ["owner", "admin", "purchasing", "sales", "finance", "read_only"];

function assignableRoles(isOwner: boolean): Role[] {
  return isOwner ? ALL_ROLES : ALL_ROLES.filter((role) => role !== "owner");
}

function inviteErrorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.code === "already_member") return t("members.alreadyMemberError");
    if (error.code === "owner_required") return t("members.ownerRequiredError");
    if (error.code === "validation_failed") return t("members.inviteValidationError");
  }
  return t("members.inviteGenericError");
}

function changeRoleErrorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.code === "owner_required") return t("members.ownerRequiredError");
    if (error.code === "last_owner") return t("members.lastOwnerError");
  }
  return t("members.changeRoleGenericError");
}

function removeErrorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.code === "owner_required") return t("members.ownerRequiredError");
    if (error.code === "last_owner") return t("members.lastOwnerError");
  }
  return t("members.removeGenericError");
}

function revokeErrorMessage(error: unknown): string {
  if (error instanceof ApiError && error.code === "already_accepted") {
    return t("members.alreadyAcceptedError");
  }
  return t("members.cancelInvitationGenericError");
}

function SectionLoading({ label }: { label: string }) {
  return (
    <div role="status" className="flex items-center gap-2 py-4 text-sm text-text-muted">
      <Spinner />
      {label}
    </div>
  );
}

function SectionError({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <div className="rounded-md border border-border-subtle bg-surface-raised p-4">
      <p role="alert" className="mb-2 text-sm text-danger">
        {message}
      </p>
      <Button onClick={onRetry}>{t("members.retry")}</Button>
    </div>
  );
}

function PaginationControls({
  page,
  perPage,
  total,
  onPage,
}: {
  page: number;
  perPage: number;
  total: number;
  onPage: (page: number) => void;
}) {
  const totalPages = Math.max(1, Math.ceil(total / perPage));
  if (totalPages <= 1) return null;

  return (
    <div className="mt-2 flex items-center justify-end gap-3 text-sm text-text-muted">
      <Button
        variant="quiet"
        disabled={page <= 1}
        onClick={() => {
          onPage(page - 1);
        }}
      >
        {t("members.previousPage")}
      </Button>
      <span className="num">
        {t("members.pagePrefix")}
        {page}
        {t("members.pageSeparator")}
        {totalPages}
      </span>
      <Button
        variant="quiet"
        disabled={page >= totalPages}
        onClick={() => {
          onPage(page + 1);
        }}
      >
        {t("members.nextPage")}
      </Button>
    </div>
  );
}

function MemberRow({
  member,
  isOwner,
  onChangeRole,
  onRemove,
  removePending,
}: {
  member: Member;
  isOwner: boolean;
  onChangeRole: (role: Role) => void;
  onRemove: () => void;
  removePending: boolean;
}) {
  const roleId = useId();
  const manageable = isOwner || member.role !== "owner";

  return (
    <tr className="border-b border-border-subtle last:border-0 hover:bg-row-hover">
      <td className="py-2 pr-3 text-text">{member.user.name}</td>
      <td className="py-2 pr-3 text-text-muted">{member.user.email}</td>
      <td className="py-2 pr-3">
        {manageable ? (
          <>
            <label htmlFor={roleId} className="sr-only">
              {t("members.tableRole")}
            </label>
            <select
              id={roleId}
              value={member.role}
              onChange={(event) => {
                onChangeRole(event.target.value as Role);
              }}
              className="h-8 rounded-md border border-border-strong bg-surface px-2 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
            >
              {assignableRoles(isOwner).map((role) => (
                <option key={role} value={role}>
                  {t(`role.${role}`)}
                </option>
              ))}
            </select>
          </>
        ) : (
          <span className="text-text" title={t("members.ownerRequiredError")}>
            {t(`role.${member.role}`)}
          </span>
        )}
      </td>
      <td className="py-2">
        {manageable && (
          <Button
            variant="quiet"
            disabled={removePending}
            onClick={() => {
              const message = `${t("members.removeConfirmPrefix")}${member.user.name}${t("members.removeConfirmSuffix")}`;
              if (window.confirm(message)) onRemove();
            }}
          >
            {removePending && <Spinner />}
            {t("members.remove")}
          </Button>
        )}
      </td>
    </tr>
  );
}

function MembersTable({
  query,
  isOwner,
  onChangeRole,
  onRemove,
  changeRoleError,
  removeError,
  removePendingId,
  onPage,
}: {
  query: ReturnType<typeof useMembers>;
  isOwner: boolean;
  onChangeRole: (id: number, role: Role) => void;
  onRemove: (id: number) => void;
  changeRoleError: string | null;
  removeError: string | null;
  removePendingId: number | null;
  onPage: (page: number) => void;
}) {
  if (query.isPending) return <SectionLoading label={t("members.loading")} />;
  if (query.isError) {
    return (
      <SectionError
        message={t("members.loadError")}
        onRetry={() => {
          void query.refetch();
        }}
      />
    );
  }

  const { data, meta } = query.data;

  return (
    <div>
      {(changeRoleError ?? removeError) && (
        <p role="alert" className="mb-2 text-sm text-danger">
          {changeRoleError ?? removeError}
        </p>
      )}
      <table className="w-full border-collapse text-sm">
        <thead>
          <tr className="border-b border-border-subtle text-left text-text-muted">
            <th className="py-2 pr-3 font-medium">{t("members.tableName")}</th>
            <th className="py-2 pr-3 font-medium">{t("members.tableEmail")}</th>
            <th className="py-2 pr-3 font-medium">{t("members.tableRole")}</th>
            <th className="py-2 font-medium">{t("members.tableActions")}</th>
          </tr>
        </thead>
        <tbody>
          {data.map((member) => (
            <MemberRow
              key={member.id}
              member={member}
              isOwner={isOwner}
              onChangeRole={(role) => {
                onChangeRole(member.id, role);
              }}
              onRemove={() => {
                onRemove(member.id);
              }}
              removePending={removePendingId === member.id}
            />
          ))}
        </tbody>
      </table>
      <PaginationControls
        page={meta.page}
        perPage={meta.per_page}
        total={meta.total}
        onPage={onPage}
      />
    </div>
  );
}

function InvitationRow({
  invitation,
  onRevoke,
  revokePending,
}: {
  invitation: PendingInvitation;
  onRevoke: () => void;
  revokePending: boolean;
}) {
  return (
    <tr className="border-b border-border-subtle last:border-0 hover:bg-row-hover">
      <td className="py-2 pr-3 text-text">{invitation.email}</td>
      <td className="py-2 pr-3 text-text">{t(`role.${invitation.role}`)}</td>
      <td className="py-2 pr-3 text-text-muted">{invitation.invited_by.name}</td>
      <td className="py-2 pr-3 text-text-muted">
        {new Intl.DateTimeFormat("pt-BR", { dateStyle: "short" }).format(
          new Date(invitation.expires_at),
        )}
      </td>
      <td className="py-2">
        <Button
          variant="quiet"
          disabled={revokePending}
          onClick={() => {
            const message = `${t("members.cancelInvitationConfirmPrefix")}${invitation.email}${t("members.cancelInvitationConfirmSuffix")}`;
            if (window.confirm(message)) onRevoke();
          }}
        >
          {revokePending && <Spinner />}
          {t("members.cancelInvitation")}
        </Button>
      </td>
    </tr>
  );
}

function PendingInvitationsTable({
  query,
  onRevoke,
  revokeError,
  revokePendingId,
  onPage,
}: {
  query: ReturnType<typeof usePendingInvitations>;
  onRevoke: (id: number) => void;
  revokeError: string | null;
  revokePendingId: number | null;
  onPage: (page: number) => void;
}) {
  if (query.isPending) return <SectionLoading label={t("members.loading")} />;
  if (query.isError) {
    return (
      <SectionError
        message={t("members.pendingInvitationsLoadError")}
        onRetry={() => {
          void query.refetch();
        }}
      />
    );
  }

  const { data, meta } = query.data;

  if (data.length === 0) {
    return <p className="text-sm text-text-muted">{t("members.pendingInvitationsEmpty")}</p>;
  }

  return (
    <div>
      {revokeError && (
        <p role="alert" className="mb-2 text-sm text-danger">
          {revokeError}
        </p>
      )}
      <table className="w-full border-collapse text-sm">
        <thead>
          <tr className="border-b border-border-subtle text-left text-text-muted">
            <th className="py-2 pr-3 font-medium">{t("members.tableEmail")}</th>
            <th className="py-2 pr-3 font-medium">{t("members.tableRole")}</th>
            <th className="py-2 pr-3 font-medium">{t("members.tableInvitedBy")}</th>
            <th className="py-2 pr-3 font-medium">{t("members.tableExpiresAt")}</th>
            <th className="py-2 font-medium">{t("members.tableActions")}</th>
          </tr>
        </thead>
        <tbody>
          {data.map((invitation) => (
            <InvitationRow
              key={invitation.id}
              invitation={invitation}
              onRevoke={() => {
                onRevoke(invitation.id);
              }}
              revokePending={revokePendingId === invitation.id}
            />
          ))}
        </tbody>
      </table>
      <PaginationControls
        page={meta.page}
        perPage={meta.per_page}
        total={meta.total}
        onPage={onPage}
      />
    </div>
  );
}

function InviteForm({
  isOwner,
  mutation,
  onClose,
}: {
  isOwner: boolean;
  mutation: ReturnType<typeof useInviteMember>;
  onClose: () => void;
}) {
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<Role>("read_only");
  const emailId = useId();
  const roleId = useId();
  const errorId = useId();

  function submit(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    mutation.mutate(
      { email, role },
      {
        onSuccess: () => {
          setEmail("");
          setRole("read_only");
          onClose();
        },
      },
    );
  }

  return (
    <form
      onSubmit={submit}
      className="mb-5 rounded-md border border-border-subtle bg-surface-raised p-4"
    >
      <h2 className="font-display mb-3 text-base text-text">{t("members.inviteFormTitle")}</h2>
      <div className="mb-3 flex flex-wrap items-end gap-3">
        <div>
          <label htmlFor={emailId} className="mb-1 block text-sm font-medium text-text">
            {t("members.inviteEmailLabel")}
          </label>
          <input
            id={emailId}
            type="email"
            autoComplete="off"
            required
            value={email}
            onChange={(event) => {
              setEmail(event.target.value);
            }}
            aria-describedby={mutation.isError ? errorId : undefined}
            className="h-9 w-64 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          />
        </div>
        <div>
          <label htmlFor={roleId} className="mb-1 block text-sm font-medium text-text">
            {t("members.inviteRoleLabel")}
          </label>
          <select
            id={roleId}
            value={role}
            onChange={(event) => {
              setRole(event.target.value as Role);
            }}
            className="h-9 rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
          >
            {assignableRoles(isOwner).map((r) => (
              <option key={r} value={r}>
                {t(`role.${r}`)}
              </option>
            ))}
          </select>
        </div>
        <Button type="submit" variant="primary" disabled={mutation.isPending}>
          {mutation.isPending && <Spinner />}
          {mutation.isPending ? t("members.inviteSubmitting") : t("members.inviteSubmit")}
        </Button>
        <Button variant="quiet" type="button" onClick={onClose} disabled={mutation.isPending}>
          {t("members.inviteCancel")}
        </Button>
      </div>
      {mutation.isError && (
        <p id={errorId} role="alert" className="text-sm text-danger">
          {inviteErrorMessage(mutation.error)}
        </p>
      )}
    </form>
  );
}

export function MembersScreen({ currentRole }: { currentRole: Role }) {
  const isOwner = currentRole === "owner";
  const [membersPage, setMembersPage] = useState(1);
  const [invitationsPage, setInvitationsPage] = useState(1);
  const [inviteOpen, setInviteOpen] = useState(false);

  const members = useMembers(membersPage);
  const invitations = usePendingInvitations(invitationsPage);
  const inviteMember = useInviteMember();
  const revokeInvitation = useRevokeInvitation();
  const changeMemberRole = useChangeMemberRole();
  const removeMember = useRemoveMember();

  return (
    <div>
      <div className="mb-5 flex items-center justify-between">
        <h1 className="font-display text-2xl text-text">{t("members.title")}</h1>
        {!inviteOpen && (
          <Button
            variant="primary"
            onClick={() => {
              setInviteOpen(true);
            }}
          >
            {t("members.inviteButton")}
          </Button>
        )}
      </div>

      {inviteOpen && (
        <InviteForm
          isOwner={isOwner}
          mutation={inviteMember}
          onClose={() => {
            setInviteOpen(false);
            inviteMember.reset();
          }}
        />
      )}

      <MembersTable
        query={members}
        isOwner={isOwner}
        onChangeRole={(id, role) => {
          changeMemberRole.mutate({ id, role });
        }}
        onRemove={(id) => {
          removeMember.mutate(id);
        }}
        changeRoleError={
          changeMemberRole.isError ? changeRoleErrorMessage(changeMemberRole.error) : null
        }
        removeError={removeMember.isError ? removeErrorMessage(removeMember.error) : null}
        removePendingId={removeMember.isPending ? removeMember.variables : null}
        onPage={setMembersPage}
      />

      <h2 className="font-display mt-8 mb-3 text-lg text-text">
        {t("members.pendingInvitationsTitle")}
      </h2>
      <PendingInvitationsTable
        query={invitations}
        onRevoke={(id) => {
          revokeInvitation.mutate(id);
        }}
        revokeError={revokeInvitation.isError ? revokeErrorMessage(revokeInvitation.error) : null}
        revokePendingId={revokeInvitation.isPending ? revokeInvitation.variables : null}
        onPage={setInvitationsPage}
      />
    </div>
  );
}

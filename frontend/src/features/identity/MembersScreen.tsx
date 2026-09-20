import { type SubmitEvent, useEffect, useId, useRef, useState } from "react";
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

type TableStatus = { kind: "success" | "error"; text: string } | null;

function assignableRoles(isOwner: boolean): Role[] {
  return isOwner ? ALL_ROLES : ALL_ROLES.filter((role) => role !== "owner");
}

function requestIdSuffix(error: unknown): string {
  if (error instanceof ApiError && error.requestId) {
    return ` ${t("members.requestIdPrefix")}${error.requestId}`;
  }
  return "";
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

/** A success/error line for the actions a table's rows trigger (role change,
 * remove, cancel): cleared whenever a new action starts, so it never
 * outlives the attempt it describes or hides behind an unrelated one. */
function useTableStatus() {
  const [status, setStatus] = useState<TableStatus>(null);

  return {
    status,
    clear: () => {
      setStatus(null);
    },
    succeed: (text: string) => {
      setStatus({ kind: "success", text });
    },
    fail: (message: string, error: unknown) => {
      setStatus({ kind: "error", text: `${message}${requestIdSuffix(error)}` });
    },
  };
}

function StatusMessage({ status }: { status: TableStatus }) {
  if (!status) return null;

  return (
    <p
      role={status.kind === "error" ? "alert" : "status"}
      className={`mb-2 text-sm ${status.kind === "error" ? "text-danger" : "text-success"}`}
    >
      {status.text}
    </p>
  );
}

function SectionLoading({ label }: { label: string }) {
  return (
    <div role="status" className="flex items-center gap-2 py-4 text-sm text-text-muted">
      <Spinner />
      {label}
    </div>
  );
}

function SectionError({
  message,
  error,
  onRetry,
}: {
  message: string;
  error: unknown;
  onRetry: () => void;
}) {
  return (
    <div className="rounded-md border border-border-subtle bg-surface-raised p-4">
      <p role="alert" className="mb-1 text-sm text-danger">
        {message}
        {requestIdSuffix(error)}
      </p>
      <Button onClick={onRetry}>{t("app.retry")}</Button>
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
  isSelf,
  pendingRole,
  roleChangePending,
  onChangeRole,
  onRemove,
  removePending,
}: {
  member: Member;
  isOwner: boolean;
  isSelf: boolean;
  pendingRole: Role | null;
  roleChangePending: boolean;
  onChangeRole: (role: Role) => void;
  onRemove: () => void;
  removePending: boolean;
}) {
  const roleId = useId();
  const manageable = isOwner || member.role !== "owner";
  const displayedRole = pendingRole ?? member.role;

  return (
    <tr className="border-b border-border-subtle last:border-0 hover:bg-row-hover">
      <td className="py-2 pr-3 text-text">
        {member.user.name}
        {isSelf && <span className="text-text-muted">{t("members.you")}</span>}
      </td>
      <td className="py-2 pr-3 text-text-muted">{member.user.email}</td>
      <td className="py-2 pr-3">
        {manageable ? (
          <>
            <label htmlFor={roleId} className="sr-only">
              {t("members.roleForPrefix")}
              {member.user.name}
            </label>
            <select
              id={roleId}
              value={displayedRole}
              disabled={roleChangePending}
              onChange={(event) => {
                onChangeRole(event.target.value as Role);
              }}
              className="h-8 rounded-md border border-border-strong bg-surface px-2 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus disabled:cursor-not-allowed disabled:opacity-45"
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
              const suffix = isSelf
                ? t("members.removeSelfConfirmSuffix")
                : t("members.removeConfirmSuffix");
              const message = `${t("members.removeConfirmPrefix")}${member.user.name}${suffix}`;
              if (window.confirm(message)) onRemove();
            }}
          >
            {removePending && <Spinner />}
            {removePending ? t("members.removing") : t("members.remove")}
          </Button>
        )}
      </td>
    </tr>
  );
}

function MembersTable({
  query,
  isOwner,
  currentUserId,
  onChangeRole,
  onRemove,
  status,
  removePendingId,
  pendingRoleChange,
  onPage,
}: {
  query: ReturnType<typeof useMembers>;
  isOwner: boolean;
  currentUserId: number;
  onChangeRole: (id: number, role: Role) => void;
  onRemove: (id: number) => void;
  status: TableStatus;
  removePendingId: number | null;
  pendingRoleChange: { id: number; role: Role } | null;
  onPage: (page: number) => void;
}) {
  if (query.isPending) return <SectionLoading label={t("members.loading")} />;
  if (query.isError) {
    return (
      <SectionError
        message={t("members.loadError")}
        error={query.error}
        onRetry={() => {
          void query.refetch();
        }}
      />
    );
  }

  const { data, meta } = query.data;

  return (
    <div>
      <StatusMessage status={status} />
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">{t("members.title")}</caption>
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
              isSelf={member.user.id === currentUserId}
              pendingRole={pendingRoleChange?.id === member.id ? pendingRoleChange.role : null}
              roleChangePending={pendingRoleChange?.id === member.id}
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
          {revokePending ? t("members.cancelingInvitation") : t("members.cancelInvitation")}
        </Button>
      </td>
    </tr>
  );
}

function PendingInvitationsTable({
  query,
  onRevoke,
  status,
  revokePendingId,
  onPage,
  onInviteClick,
}: {
  query: ReturnType<typeof usePendingInvitations>;
  onRevoke: (id: number) => void;
  status: TableStatus;
  revokePendingId: number | null;
  onPage: (page: number) => void;
  onInviteClick: () => void;
}) {
  if (query.isPending) return <SectionLoading label={t("members.loading")} />;
  if (query.isError) {
    return (
      <SectionError
        message={t("members.pendingInvitationsLoadError")}
        error={query.error}
        onRetry={() => {
          void query.refetch();
        }}
      />
    );
  }

  const { data, meta } = query.data;

  if (data.length === 0) {
    return (
      <div>
        <StatusMessage status={status} />
        <p className="mb-3 text-sm text-text-muted">{t("members.pendingInvitationsEmpty")}</p>
        <Button onClick={onInviteClick}>{t("members.inviteButton")}</Button>
      </div>
    );
  }

  return (
    <div>
      <StatusMessage status={status} />
      <table className="w-full border-collapse text-sm">
        <caption className="sr-only">{t("members.pendingInvitationsTitle")}</caption>
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
  headingRef,
  onInvited,
  onClose,
}: {
  isOwner: boolean;
  mutation: ReturnType<typeof useInviteMember>;
  headingRef: React.RefObject<HTMLHeadingElement | null>;
  onInvited: () => void;
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
          onInvited();
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
      <h2
        ref={headingRef}
        tabIndex={-1}
        className="font-display mb-3 text-base text-text outline-none"
      >
        {t("members.inviteFormTitle")}
      </h2>
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
          {requestIdSuffix(mutation.error)}
        </p>
      )}
    </form>
  );
}

export function MembersScreen({
  currentRole,
  currentUserId,
}: {
  currentRole: Role;
  currentUserId: number;
}) {
  const isOwner = currentRole === "owner";
  const [membersPage, setMembersPage] = useState(1);
  const [invitationsPage, setInvitationsPage] = useState(1);
  const [inviteOpen, setInviteOpen] = useState(false);
  const inviteHeadingRef = useRef<HTMLHeadingElement>(null);
  const inviteButtonRef = useRef<HTMLButtonElement>(null);
  const isFirstInviteToggle = useRef(true);

  const members = useMembers(membersPage);
  const invitations = usePendingInvitations(invitationsPage);
  const inviteMember = useInviteMember();
  const revokeInvitation = useRevokeInvitation();
  const changeMemberRole = useChangeMemberRole();
  const removeMember = useRemoveMember();
  const memberStatus = useTableStatus();
  const invitationStatus = useTableStatus();

  // Moves focus into the form when it opens and back to the button that
  // opens it when it closes, the same reasoning as SignInScreen's step
  // transitions: neither is a full navigation, so nothing else would tell a
  // keyboard or screen reader user the content under their cursor changed.
  // Skips the very first render, where forcing focus onto the button would
  // fight whatever the browser or the user's own navigation already focused.
  useEffect(() => {
    if (isFirstInviteToggle.current) {
      isFirstInviteToggle.current = false;
      return;
    }
    if (inviteOpen) {
      inviteHeadingRef.current?.focus();
    } else {
      inviteButtonRef.current?.focus();
    }
  }, [inviteOpen]);

  function closeInviteForm() {
    setInviteOpen(false);
    inviteMember.reset();
  }

  return (
    <div>
      <div className="mb-5 flex items-center justify-between">
        <h1 className="font-display text-2xl text-text">{t("members.title")}</h1>
        {!inviteOpen && (
          <Button
            ref={inviteButtonRef}
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
          headingRef={inviteHeadingRef}
          onInvited={() => {
            invitationStatus.succeed(t("members.inviteSuccess"));
          }}
          onClose={closeInviteForm}
        />
      )}

      <MembersTable
        query={members}
        isOwner={isOwner}
        currentUserId={currentUserId}
        onChangeRole={(id, role) => {
          memberStatus.clear();
          changeMemberRole.mutate(
            { id, role },
            {
              onSuccess: () => {
                memberStatus.succeed(t("members.changeRoleSuccess"));
              },
              onError: (error) => {
                memberStatus.fail(changeRoleErrorMessage(error), error);
              },
            },
          );
        }}
        onRemove={(id) => {
          memberStatus.clear();
          removeMember.mutate(id, {
            onSuccess: () => {
              memberStatus.succeed(t("members.removeSuccess"));
            },
            onError: (error) => {
              memberStatus.fail(removeErrorMessage(error), error);
            },
          });
        }}
        status={memberStatus.status}
        removePendingId={removeMember.isPending ? removeMember.variables : null}
        pendingRoleChange={changeMemberRole.isPending ? changeMemberRole.variables : null}
        onPage={setMembersPage}
      />

      <h2 className="font-display mt-8 mb-3 text-lg text-text">
        {t("members.pendingInvitationsTitle")}
      </h2>
      <PendingInvitationsTable
        query={invitations}
        onRevoke={(id) => {
          invitationStatus.clear();
          revokeInvitation.mutate(id, {
            onSuccess: () => {
              invitationStatus.succeed(t("members.cancelInvitationSuccess"));
            },
            onError: (error) => {
              invitationStatus.fail(revokeErrorMessage(error), error);
            },
          });
        }}
        status={invitationStatus.status}
        revokePendingId={revokeInvitation.isPending ? revokeInvitation.variables : null}
        onPage={setInvitationsPage}
        onInviteClick={() => {
          setInviteOpen(true);
        }}
      />
    </div>
  );
}

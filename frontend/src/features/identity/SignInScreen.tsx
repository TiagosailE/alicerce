import { type SubmitEvent, useId, useState } from "react";
import { ApiError } from "../../api/client";
import { BrandMark } from "../../components/ui/BrandMark";
import { Button } from "../../components/ui/Button";
import { Spinner } from "../../components/ui/Spinner";
import { t } from "../../i18n";
import { type Membership, useSignIn } from "./api";

function errorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.status === 401) return t("signIn.invalidCredentials");
    if (error.status === 429) return t("signIn.rateLimited");
  }
  return t("signIn.genericError");
}

function organizationsFromError(error: unknown): Membership[] | null {
  if (error instanceof ApiError && error.code === "organization_required") {
    const memberships = error.details.memberships;
    if (Array.isArray(memberships)) return memberships as Membership[];
  }
  return null;
}

export function SignInScreen() {
  const signIn = useSignIn();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [memberships, setMemberships] = useState<Membership[] | null>(null);
  const emailId = useId();
  const passwordId = useId();
  const errorId = useId();

  const pending = signIn.isPending;
  const organizations = memberships ?? organizationsFromError(signIn.error);

  function submitCredentials(event: SubmitEvent<HTMLFormElement>) {
    event.preventDefault();
    signIn.mutate(
      { email, password },
      {
        onError: (error) => {
          const found = organizationsFromError(error);
          if (found) setMemberships(found);
        },
      },
    );
  }

  function chooseOrganization(organizationId: number) {
    signIn.mutate({ email, password, organization_id: organizationId });
  }

  return (
    <main className="grid min-h-screen place-items-center bg-canvas px-4">
      <div className="w-full max-w-sm rounded-md border border-border-subtle bg-surface-raised p-6 shadow-sm">
        <div className="mb-6 flex items-center gap-2">
          <BrandMark />
          <span className="font-display text-lg text-text">{t("app.name")}</span>
        </div>

        {organizations ? (
          <OrganizationPicker
            organizations={organizations}
            pending={pending}
            error={
              signIn.error && !organizationsFromError(signIn.error)
                ? errorMessage(signIn.error)
                : null
            }
            onChoose={chooseOrganization}
            onBack={() => {
              setMemberships(null);
              signIn.reset();
            }}
          />
        ) : (
          <form onSubmit={submitCredentials} noValidate>
            <h1 className="font-display mb-4 text-xl text-text">{t("signIn.title")}</h1>

            <label htmlFor={emailId} className="mb-1 block text-sm font-medium text-text">
              {t("signIn.emailLabel")}
            </label>
            <input
              id={emailId}
              type="email"
              autoComplete="email"
              required
              value={email}
              onChange={(event) => {
                setEmail(event.target.value);
              }}
              className="mb-3 h-9 w-full rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
            />

            <label htmlFor={passwordId} className="mb-1 block text-sm font-medium text-text">
              {t("signIn.passwordLabel")}
            </label>
            <input
              id={passwordId}
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(event) => {
                setPassword(event.target.value);
              }}
              aria-describedby={signIn.isError ? errorId : undefined}
              className="mb-4 h-9 w-full rounded-md border border-border-strong bg-surface px-3 text-sm text-text focus-visible:outline-2 focus-visible:outline-focus"
            />

            {signIn.isError && (
              <p id={errorId} role="alert" className="mb-4 text-sm text-danger">
                {errorMessage(signIn.error)}
              </p>
            )}

            <Button type="submit" variant="primary" className="w-full" disabled={pending}>
              {pending && <Spinner />}
              {pending ? t("signIn.submitting") : t("signIn.submit")}
            </Button>
          </form>
        )}
      </div>
    </main>
  );
}

function OrganizationPicker({
  organizations,
  pending,
  error,
  onChoose,
  onBack,
}: {
  organizations: Membership[];
  pending: boolean;
  error: string | null;
  onChoose: (organizationId: number) => void;
  onBack: () => void;
}) {
  return (
    <div>
      <h1 className="font-display mb-1 text-xl text-text">{t("signIn.chooseOrganizationTitle")}</h1>
      <p className="mb-4 text-sm text-text-muted">{t("signIn.chooseOrganizationHint")}</p>

      {error && (
        <p role="alert" className="mb-3 text-sm text-danger">
          {error}
        </p>
      )}

      <ul className="mb-4 flex flex-col gap-2">
        {organizations.map((membership) => (
          <li key={membership.organization.id}>
            <button
              type="button"
              disabled={pending}
              onClick={() => {
                onChoose(membership.organization.id);
              }}
              className="flex w-full items-center justify-between rounded-md border border-border-subtle px-3 py-2 text-left text-sm hover:bg-row-hover disabled:cursor-not-allowed disabled:opacity-45"
            >
              <span className="font-medium text-text">{membership.organization.name}</span>
              <span className="text-text-muted">{t(`role.${membership.role}`)}</span>
            </button>
          </li>
        ))}
      </ul>

      <Button variant="quiet" onClick={onBack} disabled={pending}>
        {t("signIn.back")}
      </Button>
    </div>
  );
}

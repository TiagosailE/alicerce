import { Navigate, Route, Routes } from "react-router-dom";
import { AppShell } from "./components/shell/AppShell";
import { Spinner } from "./components/ui/Spinner";
import { HomeScreen } from "./features/home/HomeScreen";
import { useSession } from "./features/identity/api";
import { SignInScreen } from "./features/identity/SignInScreen";
import { t } from "./i18n";

export function App() {
  const session = useSession();

  if (session.isPending) {
    return (
      <main className="grid min-h-screen place-items-center bg-canvas">
        <div role="status" className="flex items-center gap-2 text-text-muted">
          <Spinner />
          <h1 className="font-display text-lg">{t("app.name")}</h1>
        </div>
      </main>
    );
  }

  if (session.isError) {
    return (
      <main className="grid min-h-screen place-items-center bg-canvas px-4">
        <div className="text-center">
          <h1 className="font-display mb-3 text-lg text-text">{t("app.name")}</h1>
          <p role="alert" className="mb-3 text-sm text-danger">
            {t("app.loadError")}
          </p>
          <button
            type="button"
            onClick={() => {
              void session.refetch();
            }}
            disabled={session.isFetching}
            className="inline-flex items-center gap-2 text-sm text-accent underline underline-offset-2 disabled:cursor-not-allowed disabled:opacity-45"
          >
            {session.isFetching && <Spinner />}
            {t("app.retry")}
          </button>
        </div>
      </main>
    );
  }

  const { user, membership } = session.data;
  const authenticated = Boolean(user && membership);

  return (
    <Routes>
      <Route
        path="/entrar"
        element={authenticated ? <Navigate to="/" replace /> : <SignInScreen />}
      />
      <Route
        path="/*"
        element={
          authenticated && user && membership ? (
            <AppShell organizationName={membership.organization.name} userName={user.name}>
              <HomeScreen userName={user.name} />
            </AppShell>
          ) : (
            <Navigate to="/entrar" replace />
          )
        }
      />
    </Routes>
  );
}

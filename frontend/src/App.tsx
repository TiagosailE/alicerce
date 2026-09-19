import { t } from "./i18n";

export function App() {
  return (
    <main className="grid min-h-screen place-items-center">
      <div className="text-center">
        <h1 className="text-2xl font-semibold">{t("app.name")}</h1>
        <p className="mt-2 text-sm">{t("app.tagline")}</p>
      </div>
    </main>
  );
}

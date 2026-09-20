import { t } from "../../i18n";

export function HomeScreen({ userName }: { userName: string }) {
  return (
    <div>
      <h1 className="font-display text-2xl text-text">
        {t("home.welcomePrefix")} {userName}
      </h1>
      <p className="mt-2 text-sm text-text-muted">{t("app.tagline")}</p>
    </div>
  );
}

import { requestIdSuffix } from "../../lib/errors";
import { t } from "../../i18n";
import { Button } from "./Button";

export function SectionError({
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

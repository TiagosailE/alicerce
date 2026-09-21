import { t } from "../../i18n";
import { Button } from "./Button";

export function PaginationControls({
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
        {t("app.previousPage")}
      </Button>
      <span className="num">
        {t("app.pagePrefix")}
        {page}
        {t("app.pageSeparator")}
        {totalPages}
      </span>
      <Button
        variant="quiet"
        disabled={page >= totalPages}
        onClick={() => {
          onPage(page + 1);
        }}
      >
        {t("app.nextPage")}
      </Button>
    </div>
  );
}

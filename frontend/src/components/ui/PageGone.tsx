import { t } from "../../i18n";
import { Button } from "./Button";

/** What a list says when the page in the address is past its last one (a shared
 * link, a list that shrank): not "nothing here", since there is something, and
 * a way to the first page. */
export function PageGone({ onFirstPage }: { onFirstPage: () => void }) {
  return (
    <div className="text-sm text-text-muted">
      <p className="mb-2">{t("common.pageGone")}</p>
      <Button onClick={onFirstPage}>{t("common.firstPage")}</Button>
    </div>
  );
}

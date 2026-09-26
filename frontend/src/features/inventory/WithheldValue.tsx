import { t } from "../../i18n";

/** Where the API withholds what stock is worth or cost from this role: a dash
 * for the eye, and the reason for a screen reader, which would otherwise skip
 * or mispronounce a bare dash and leave a blank cell unexplained. */
export function WithheldValue() {
  return (
    <>
      <span aria-hidden="true">-</span>
      <span className="sr-only">{t("stock.restricted")}</span>
    </>
  );
}

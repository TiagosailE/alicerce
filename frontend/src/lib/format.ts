/** Formatting only, never arithmetic (CONTRIBUTING.md, design-system skill):
 * the API sends quantities as decimal strings (ADR 0006); this only changes
 * how one is displayed, it never computes with it. */
export function formatQuantity(value: string): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(Number(value));
}

/** Turns what a pt-BR user typed into the API's decimal string (ADR 0006),
 * by text rules only, never arithmetic. A comma is the decimal separator. A
 * dot followed by exactly three digits is a thousands separator, the way
 * the screens show "1.000"; any other dot is a decimal point ("2.5").
 * Returns null for anything that is not a number. */
export function parseDecimalInput(text: string): string | null {
  const value = text.replace(/\s/g, "");
  if (/^\d+$/.test(value)) return value;
  if (/^\d+,\d+$/.test(value)) return value.replace(",", ".");
  if (/^\d{1,3}(\.\d{3})+(,\d+)?$/.test(value)) return value.replaceAll(".", "").replace(",", ".");
  if (/^\d+\.\d+$/.test(value)) return value;
  return null;
}

/** The inverse for an input's initial value: the API's "1000.000000"
 * becomes "1000" and "0.500000" becomes "0,5", ungrouped so that what the
 * user sees is unambiguous for parseDecimalInput. */
export function toDecimalInput(value: string): string {
  const [whole = "", fraction = ""] = value.split(".");
  const significant = fraction.replace(/0+$/, "");
  return significant ? `${whole},${significant}` : whole;
}

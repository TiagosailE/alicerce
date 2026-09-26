/** Formatting only, never arithmetic (CONTRIBUTING.md, design-system skill):
 * the API sends quantities as decimal strings (ADR 0006); this only changes
 * how one is displayed, it never computes with it. */
export function formatQuantity(value: string): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(Number(value));
}

/** Turns what a pt-BR user typed into the API's decimal string (ADR 0006),
 * by text rules only, never arithmetic. A comma is the decimal separator. A
 * dot followed by exactly three digits is a thousands separator, the way
 * the screens show "1.000", unless the number starts with a zero ("0.500");
 * any other dot is a decimal point ("2.5").
 * Returns null for anything that is not a number. */
export function parseDecimalInput(text: string): string | null {
  const value = text.replace(/\s/g, "");
  if (/^\d+$/.test(value)) return value;
  if (/^\d+,\d+$/.test(value)) return value.replace(",", ".");
  // A group of thousands never starts with a zero: "0.500" is half, not 500.
  if (/^[1-9]\d{0,2}(\.\d{3})+(,\d+)?$/.test(value))
    return value.replaceAll(".", "").replace(",", ".");
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

const moneyFormat = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
const unitCostFormat = new Intl.NumberFormat("pt-BR", {
  style: "currency",
  currency: "BRL",
  minimumFractionDigits: 2,
  maximumFractionDigits: 8,
});

/** Intl reads a decimal string exactly, so the two decimal places between
 * cents and reais are moved as a "E-2" exponent in the text: no division, no
 * float, whatever the size of the amount. */
function centsAsReais(cents: string): string {
  return `${cents}E-2`;
}

/** Integer cents from the API as reais. Formatting only, never arithmetic on
 * money (CONTRIBUTING.md): the amounts arrive already computed. */
export function formatMoneyCents(cents: number): string {
  return moneyFormat.format(centsAsReais(String(cents)) as unknown as number);
}

/** A unit cost, which the API states in cents and may carry a fraction of a
 * cent ("84.990000" is R$ 0,8499), shown in reais with all the places it has. */
export function formatUnitCost(centsPerUnit: string): string {
  return unitCostFormat.format(centsAsReais(centsPerUnit) as unknown as number);
}

/** A movement's quantity with its sign always visible: "+5" and "-3". */
export function formatSignedQuantity(value: string): string {
  return new Intl.NumberFormat("pt-BR", {
    maximumFractionDigits: 6,
    signDisplay: "exceptZero",
  }).format(Number(value));
}

/** What a person typed in reais ("32,50", "0,8499", "1.234,56") as the
 * decimal string of cents the API expects ("3250", "84.99", "123456"), by
 * moving the decimal point two places in the text. No arithmetic, so no
 * rounding: what cannot be represented is left for the API to refuse. */
export function reaisToCents(text: string): string | null {
  const parsed = parseDecimalInput(text.replace(/^\s*R\$\s*/i, ""));
  if (parsed === null) return null;

  const [whole = "0", fraction = ""] = parsed.split(".");
  const padded = fraction.padEnd(2, "0");
  const cents = `${whole}${padded.slice(0, 2)}`.replace(/^0+(?=\d)/, "");
  const rest = padded.slice(2);
  return rest ? `${cents}.${rest}` : cents;
}

/** A timestamp from the API (UTC, ISO 8601) in the browser's own time zone. */
export function formatDateTime(iso: string): string {
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(
    new Date(iso),
  );
}

/** Formatting only, never arithmetic (CONTRIBUTING.md, design-system skill):
 * the API sends quantities as decimal strings (ADR 0006); this only changes
 * how one is displayed, it never computes with it. */
export function formatQuantity(value: string): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(Number(value));
}

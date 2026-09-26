import { ptBR } from "./pt-BR";

export type MessageKey = keyof typeof ptBR;

/** Returns the pt-BR text for a key; unknown keys fail at compile time. */
export function t(key: MessageKey): string {
  return ptBR[key];
}

/** Like t, for a text with named holes: "{quantity} {unit}". A hole with no
 * value is left empty rather than printed as its name. */
export function tf(key: MessageKey, values: Record<string, string>): string {
  return ptBR[key].replace(/\{(\w+)\}/g, (_hole, name: string) => values[name] ?? "");
}

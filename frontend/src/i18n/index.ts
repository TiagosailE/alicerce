import { ptBR } from "./pt-BR";

export type MessageKey = keyof typeof ptBR;

/** Returns the pt-BR text for a key; unknown keys fail at compile time. */
export function t(key: MessageKey): string {
  return ptBR[key];
}

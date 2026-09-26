import type { Title } from "./api";

export function title(overrides: Partial<Title> = {}): Title {
  return {
    id: 70,
    kind: "payable",
    status: "open",
    partner: { id: 3, name: "Cimentos Bahia" },
    receipt: { id: 31, number: 2 },
    total_cents: 382_200,
    settled_cents: 0,
    open_cents: 382_200,
    currency: "BRL",
    created_at: "2026-09-26T13:00:00Z",
    installments: [
      {
        id: 1,
        number: 1,
        due_on: "2026-10-26",
        amount_cents: 191_100,
        settled_cents: 0,
        open_cents: 191_100,
      },
      {
        id: 2,
        number: 2,
        due_on: "2026-11-25",
        amount_cents: 191_100,
        settled_cents: 0,
        open_cents: 191_100,
      },
    ],
    ...overrides,
  };
}

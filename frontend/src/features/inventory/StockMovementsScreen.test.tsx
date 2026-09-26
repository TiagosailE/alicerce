import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { StockMovement } from "./api";
import { StockMovementsScreen } from "./StockMovementsScreen";

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function listResponse(data: unknown[]) {
  return jsonResponse({ data, meta: { page: 1, per_page: 25, total: data.length } });
}

function createFetchMock(
  handlers: Record<string, (request: Request) => Response | Promise<Response>>,
) {
  return vi.fn((input: RequestInfo | URL) => {
    const request = input as Request;
    const path = new URL(request.url).pathname.replace(/^\/api\/v1/, "");
    const key = `${request.method} ${path}`;
    const handler = handlers[key];
    if (!handler) throw new Error(`Unhandled request in test: ${key}`);
    return handler(request);
  });
}

const unit = { id: 1, code: "UN", name: "Unidade", active: true };

function movement(overrides: Partial<StockMovement> = {}): StockMovement {
  return {
    id: 1,
    kind: "adjustment",
    reason: "loss",
    note: null,
    product: { id: 7, sku: "CIM-001", name: "Cimento CP II", stock_unit: unit },
    warehouse: { id: 1, name: "Loja", active: true },
    quantity: "-3.000",
    value_cents: -255,
    currency: "BRL",
    on_hand_after: "12.000",
    value_after_cents: 1020,
    actor: { id: 1, name: "Joana Lima" },
    created_at: "2026-09-26T12:00:00Z",
    ...overrides,
  };
}

function cellText(cells: HTMLElement[], index: number): string {
  const cell = cells[index];
  if (!cell) throw new Error(`no cell at ${String(index)}`);
  return cell.textContent.replace(/\s/g, " ");
}

const defaultHandlers = {
  "GET /warehouses": () =>
    listResponse([
      { id: 1, name: "Loja", active: true },
      { id: 2, name: "Pátio", active: true },
    ]),
};

function renderScreen() {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={["/estoque/movimentacoes"]}>
        <StockMovementsScreen />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("StockMovementsScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("lists the ledger with the sign, the value moved, the balance after and who did it", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /stock_movements": () => listResponse([movement()]),
      }),
    );

    renderScreen();

    const row = (await screen.findByText("Cimento CP II")).closest("tr");
    const cells = within(row as HTMLElement).getAllByRole("cell");
    expect(cells[3]).toHaveTextContent("Perda");
    expect(cells[4]).toHaveTextContent("-3 UN");
    expect(cellText(cells, 5)).toBe("-R$ 2,55");
    expect(cells[6]).toHaveTextContent("12 UN");
    expect(cells[7]).toHaveTextContent("Joana Lima");
  });

  it("shows an empty state", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ ...defaultHandlers, "GET /stock_movements": () => listResponse([]) }),
    );

    renderScreen();

    expect(await screen.findByText("Ainda não há movimentações.")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Limpar filtros" })).not.toBeInTheDocument();
  });

  it("filters by warehouse and by reason, sending them to the API", async () => {
    const seen: string[] = [];
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /stock_movements": (request) => {
          seen.push(new URL(request.url).search);
          return listResponse([movement()]);
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Cimento CP II");
    await user.selectOptions(screen.getByLabelText("Depósito"), "2");
    await user.selectOptions(screen.getByLabelText("Motivo"), "damage");

    await waitFor(() => {
      expect(
        seen.some(
          (search) => search.includes("warehouse_id=2") && search.includes("reason=damage"),
        ),
      ).toBe(true);
    });
  });
});

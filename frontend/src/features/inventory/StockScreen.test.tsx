import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Product } from "../catalog/api";
import type { StockBalance, Warehouse } from "./api";
import { StockScreen } from "./StockScreen";

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function errorEnvelope(
  code: string,
  message: string,
  details: Record<string, unknown> = {},
  status = 422,
) {
  return jsonResponse({ error: { code, message, details, request_id: "req-1" } }, status);
}

function listResponse(
  data: unknown[],
  meta: Partial<{ page: number; per_page: number; total: number }> = {},
) {
  return jsonResponse({ data, meta: { page: 1, per_page: 25, total: data.length, ...meta } });
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

function warehouse(overrides: Partial<Warehouse> = {}): Warehouse {
  return { id: 1, name: "Loja", active: true, ...overrides };
}

function product(overrides: Partial<Product> = {}): Product {
  return {
    id: 7,
    sku: "CIM-001",
    name: "Cimento CP II",
    active: true,
    revision: 0,
    category: null,
    stock_unit: unit,
    unit_conversion: { purchase_unit: unit, factor: "1.000000" },
    ...overrides,
  };
}

function balance(overrides: Partial<StockBalance> = {}): StockBalance {
  return {
    id: 1,
    product: { id: 7, sku: "CIM-001", name: "Cimento CP II", stock_unit: unit },
    warehouse: warehouse(),
    on_hand: "120.500",
    reserved: "20.000",
    available: "100.500",
    value_cents: 391_625,
    currency: "BRL",
    last_unit_cost_cents: "3250.000000",
    ...overrides,
  };
}

function cellText(cells: HTMLElement[], index: number): string {
  const cell = cells[index];
  if (!cell) throw new Error(`no cell at ${String(index)}`);
  return cell.textContent.replace(/\s/g, " ");
}

async function jsonBody(request: Request): Promise<Record<string, unknown>> {
  return (await request.clone().json()) as Record<string, unknown>;
}

const defaultHandlers = {
  "GET /warehouses": () => listResponse([warehouse(), warehouse({ id: 2, name: "Pátio" })]),
  "GET /products": () => listResponse([product()]),
};

function renderScreen(canAdjust = true, canViewLedger = true) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={["/estoque"]}>
        <StockScreen canAdjust={canAdjust} canViewLedger={canViewLedger} />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

async function openForm(user: ReturnType<typeof userEvent.setup>) {
  await user.click(await screen.findByRole("button", { name: "Ajustar estoque" }));
  await screen.findByRole("option", { name: /Cimento CP II/ });
}

async function fillForm(
  user: ReturnType<typeof userEvent.setup>,
  { counted, unitCost }: { counted: string; unitCost?: string },
) {
  await user.selectOptions(screen.getByLabelText("Produto", { selector: "select" }), "7");
  await user.selectOptions(screen.getByLabelText("Depósito", { selector: "form select" }), "1");
  await screen.findByText(/Saldo atual: 120,5 UN/);
  const countedInput = screen.getByLabelText(/Quantidade contada/);
  await user.clear(countedInput);
  await user.type(countedInput, counted);
  if (unitCost !== undefined) {
    const cost = screen.getByLabelText("Custo unitário (R$)");
    await user.clear(cost);
    await user.type(cost, unitCost);
  }
}

describe("StockScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("lists the position with quantities, value and cost formatted for pt-BR", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /stock_balances": () => listResponse([balance()]),
      }),
    );

    renderScreen();

    const row = (await screen.findByText("Cimento CP II")).closest("tr");
    expect(row).not.toBeNull();
    const cells = within(row as HTMLElement).getAllByRole("cell");
    expect(cells[1]).toHaveTextContent("Loja");
    expect(cells[2]).toHaveTextContent("120,5 UN");
    expect(cells[3]).toHaveTextContent("20");
    expect(cells[4]).toHaveTextContent("100,5");
    expect(cellText(cells, 5)).toBe("R$ 3.916,25");
    expect(cellText(cells, 6)).toBe("R$ 32,50");
  });

  it("shows a dash where the API withholds what stock is worth and cost", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /stock_balances": () =>
          listResponse([balance({ value_cents: null, last_unit_cost_cents: null })]),
      }),
    );

    renderScreen(false);

    const row = (await screen.findByText("Cimento CP II")).closest("tr");
    const cells = within(row as HTMLElement).getAllByRole("cell");
    expect(cellText(cells, 4)).toBe("100,5 UN");
    // A dash for the eye, and the reason for a screen reader.
    for (const index of [5, 6]) {
      expect(cellText(cells, index)).toContain("Restrito ao seu perfil");
    }
    const valueCell = cells[5];
    if (!valueCell) throw new Error("no value cell");
    expect(within(valueCell).getByText("-")).toHaveAttribute("aria-hidden", "true");
  });

  it("shows an empty state", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ ...defaultHandlers, "GET /stock_balances": () => listResponse([]) }),
    );

    renderScreen();

    expect(await screen.findByText("Ainda não há estoque registrado.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Registrar saldo inicial" })).toBeInTheDocument();
  });

  it("offers no opening balance to a role that cannot record one", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ ...defaultHandlers, "GET /stock_balances": () => listResponse([]) }),
    );

    renderScreen(false);

    await screen.findByText("Ainda não há estoque registrado.");
    expect(
      screen.queryByRole("button", { name: "Registrar saldo inicial" }),
    ).not.toBeInTheDocument();
  });

  it("tells a filtered empty list from an empty stock, and clears the filters", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /stock_balances": (request) =>
          new URL(request.url).searchParams.get("q") ? listResponse([]) : listResponse([balance()]),
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Cimento CP II");
    await user.type(screen.getByLabelText("Buscar produto"), "zzz");
    expect(
      await screen.findByText("Nenhum saldo encontrado com esses filtros."),
    ).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Limpar filtros" }));

    expect(await screen.findByText("Cimento CP II")).toBeInTheDocument();
    expect(screen.getByLabelText("Buscar produto")).toHaveValue("");
  });

  it("filters by warehouse and by search, sending them to the API", async () => {
    const seen: string[] = [];
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /stock_balances": (request) => {
          seen.push(new URL(request.url).search);
          return listResponse([balance()]);
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Cimento CP II");
    await user.selectOptions(screen.getByLabelText("Depósito"), "2");
    await user.type(screen.getByLabelText("Buscar produto"), "cim");

    await waitFor(() => {
      expect(
        seen.some((search) => search.includes("warehouse_id=2") && search.includes("q=cim")),
      ).toBe(true);
    });
  });

  it("does not offer the adjustment to a role that cannot record one", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /stock_balances": () => listResponse([balance()]),
      }),
    );

    renderScreen(false);

    await screen.findByText("Cimento CP II");
    expect(screen.queryByRole("button", { name: "Ajustar estoque" })).not.toBeInTheDocument();
  });

  it("hides the movements tab from a role that may not read the ledger", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /stock_balances": () => listResponse([balance()]),
      }),
    );

    renderScreen(false, false);

    await screen.findByText("Cimento CP II");
    expect(screen.getByRole("link", { name: "Saldos" })).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Movimentações" })).not.toBeInTheDocument();
  });

  it("does not fetch the product list until the adjustment panel is opened", async () => {
    const products = vi.fn(() => listResponse([product()]));
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /products": products,
        "GET /stock_balances": () => listResponse([balance()]),
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Cimento CP II");
    expect(products).not.toHaveBeenCalled();

    await openForm(user);
    expect(products).toHaveBeenCalledTimes(1);
  });

  it("moves focus to the panel when it opens and back to its button when it closes", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /stock_balances": () => listResponse([balance()]),
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await openForm(user);
    expect(screen.getByRole("heading", { name: "Ajuste por contagem" })).toHaveFocus();

    await user.click(screen.getByRole("button", { name: "Fechar" }));
    expect(screen.getByRole("button", { name: "Ajustar estoque" })).toHaveFocus();
  });

  it("shows a shortfall against reservations in red, with units on reserved and available", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /stock_balances": () =>
          listResponse([balance({ on_hand: "5.000", reserved: "8.000", available: "-3.000" })]),
      }),
    );

    renderScreen();

    const row = (await screen.findByText("Cimento CP II")).closest("tr");
    const cells = within(row as HTMLElement).getAllByRole("cell");
    expect(cellText(cells, 3)).toBe("8 UN");
    expect(cellText(cells, 4)).toBe("-3 UN");
    expect(cells[4]).toHaveClass("text-danger");
  });

  describe("the count adjustment", () => {
    it("sends the count in the API's format with a key and the CSRF token, then reports the result", async () => {
      let request: Request | undefined;
      let body: Record<string, unknown> = {};
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /stock_balances": () => listResponse([balance()]),
          "POST /stock_adjustments": async (incoming) => {
            request = incoming;
            body = await jsonBody(incoming);
            return jsonResponse(
              {
                data: {
                  movement: {
                    id: 1,
                    kind: "adjustment",
                    reason: "opening_balance",
                    note: null,
                    product: { id: 7, sku: "CIM-001", name: "Cimento CP II", stock_unit: unit },
                    warehouse: warehouse(),
                    quantity: "1000.500",
                    value_cents: 3_250_000,
                    currency: "BRL",
                    on_hand_after: "1000.500",
                    value_after_cents: 3_250_000,
                    actor: { id: 1, name: "Joana Lima" },
                    created_at: "2026-09-26T12:00:00Z",
                  },
                  balance: balance({ on_hand: "1000.500" }),
                },
              },
              201,
            );
          },
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      await fillForm(user, { counted: "1.000,5", unitCost: "32,50" });
      await user.selectOptions(
        screen.getByLabelText("Motivo", { selector: "form select" }),
        "opening_balance",
      );
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));

      await waitFor(() => {
        expect(request).toBeDefined();
      });
      expect(body).toMatchObject({
        product_id: 7,
        warehouse_id: 1,
        counted_quantity: "1000.5",
        reason: "opening_balance",
        expected_on_hand: "120.500",
        unit_cost_cents: "3250",
      });
      expect(request?.headers.get("Idempotency-Key")).toMatch(/^[0-9a-f-]{36}$/);
      expect(request?.headers.has("X-CSRF-Token")).toBe(true);
      await waitFor(() => {
        expect(screen.getByRole("status")).toHaveTextContent("Ajuste registrado: +1.000,5 UN");
      });
      expect(screen.getByRole("status")).toHaveTextContent("Em estoque: 1.000,5 UN");
      expect(screen.getByLabelText(/Quantidade contada/)).toHaveValue("");
    });

    it("explains a stale count, shows the balance as it is now, and lets the operator count again", async () => {
      let onHand = "120.500";
      const bodies: Record<string, unknown>[] = [];
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /stock_balances": () => listResponse([balance({ on_hand: onHand })]),
          "POST /stock_adjustments": async (request) => {
            bodies.push(await jsonBody(request));
            if (bodies.length === 1) {
              onHand = "90.000";
              return errorEnvelope("stale", "stale", { current_on_hand: "90.000" }, 409);
            }
            return jsonResponse({
              data: { movement: null, balance: balance({ on_hand: onHand }) },
            });
          },
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      await fillForm(user, { counted: "98" });
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));

      expect(await screen.findByRole("alert")).toHaveTextContent(
        /O saldo mudou depois que você abriu/,
      );
      expect(await screen.findByText(/Saldo atual: 90 UN/)).toBeInTheDocument();

      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));

      await waitFor(() => {
        expect(bodies).toHaveLength(2);
      });
      expect(bodies.map((body) => body.expected_on_hand)).toEqual(["120.500", "90.000"]);
    });

    it("explains a reason that disagrees with the direction, on the reason field", async () => {
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /stock_balances": () => listResponse([balance()]),
          "POST /stock_adjustments": () =>
            errorEnvelope("validation_failed", "invalid", {
              fields: { reason: ["incompatible_with_direction"] },
            }),
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      await fillForm(user, { counted: "200" });
      await user.selectOptions(
        screen.getByLabelText("Motivo", { selector: "form select" }),
        "theft",
      );
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));

      expect(
        await screen.findByText(/perda, avaria, furto e vencimento só reduzem/),
      ).toBeInTheDocument();
    });

    it("retries a request that may have committed with the same key and the same expected balance, even if the balance was reloaded meanwhile", async () => {
      let onHand = "120.500";
      const seen: { key: string | null; body: Record<string, unknown> }[] = [];
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /stock_balances": () => listResponse([balance({ on_hand: onHand })]),
          "POST /stock_adjustments": async (request) => {
            seen.push({
              key: request.headers.get("Idempotency-Key"),
              body: await jsonBody(request),
            });
            if (seen.length === 1) {
              // The request committed on the server but the answer was lost.
              onHand = "98.000";
              return errorEnvelope("internal", "boom", {}, 500);
            }
            return jsonResponse({
              data: { movement: null, balance: balance({ on_hand: onHand }) },
            });
          },
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      await fillForm(user, { counted: "98" });
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));
      await screen.findByRole("alert");
      // The connection comes back and the observed balance refetches.
      window.dispatchEvent(new Event("offline"));
      window.dispatchEvent(new Event("online"));
      await screen.findByText(/Saldo atual: 98 UN/);
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));

      await waitFor(() => {
        expect(seen).toHaveLength(2);
      });
      expect(seen[1]?.key).toBe(seen[0]?.key);
      expect(seen[1]?.body).toEqual(seen[0]?.body);
      expect(seen[1]?.body.expected_on_hand).toBe("120.500");
    });

    it("uses a new key and the new balance when the operator changes what was counted after a failure", async () => {
      const keys: (string | null)[] = [];
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /stock_balances": () => listResponse([balance()]),
          "POST /stock_adjustments": (request) => {
            keys.push(request.headers.get("Idempotency-Key"));
            return keys.length === 1
              ? errorEnvelope("internal", "boom", {}, 500)
              : jsonResponse({ data: { movement: null, balance: balance() } });
          },
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      await fillForm(user, { counted: "98" });
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));
      await screen.findByRole("alert");
      const counted = screen.getByLabelText(/Quantidade contada/);
      await user.clear(counted);
      await user.type(counted, "97");
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));

      await waitFor(() => {
        expect(keys).toHaveLength(2);
      });
      expect(keys[0]).not.toBe(keys[1]);
    });

    it("shows the banner for a validation error on a field the form does not display", async () => {
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /stock_balances": () => listResponse([balance()]),
          "POST /stock_adjustments": () =>
            errorEnvelope("validation_failed", "invalid", {
              fields: { expected_on_hand: ["not_a_number"] },
            }),
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      await fillForm(user, { counted: "10" });
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));

      expect(await screen.findByRole("alert")).toHaveTextContent(
        "Não foi possível registrar o ajuste",
      );
    });

    it("links a field error to its field, and drops it as soon as the operator edits", async () => {
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /stock_balances": () => listResponse([balance()]),
          "POST /stock_adjustments": () =>
            errorEnvelope("validation_failed", "invalid", {
              fields: { reason: ["incompatible_with_direction"] },
            }),
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      await fillForm(user, { counted: "200" });
      await user.selectOptions(
        screen.getByLabelText("Motivo", { selector: "form select" }),
        "theft",
      );
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));

      const reason = screen.getByLabelText("Motivo", { selector: "form select" });
      const error = await screen.findByText(/perda, avaria, furto e vencimento só reduzem/);
      expect(reason).toHaveAttribute("aria-invalid", "true");
      expect(reason.getAttribute("aria-describedby")).toBe(error.id);

      await user.selectOptions(reason, "count");

      expect(
        screen.queryByText(/perda, avaria, furto e vencimento só reduzem/),
      ).not.toBeInTheDocument();
      expect(reason).not.toHaveAttribute("aria-invalid");
    });

    it("echoes how a typed unit cost will be read, so a thousands dot is never a surprise", async () => {
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /stock_balances": () => listResponse([balance()]),
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      await user.type(screen.getByLabelText("Custo unitário (R$)"), "8.499");

      expect(
        screen.getByText(/Será registrado como R\$\s8\.499,00 por unidade\./),
      ).toBeInTheDocument();

      await user.clear(screen.getByLabelText("Custo unitário (R$)"));
      await user.type(screen.getByLabelText("Custo unitário (R$)"), "R$ 0,8499");

      expect(
        screen.getByText(/Será registrado como R\$\s0,8499 por unidade\./),
      ).toBeInTheDocument();
    });

    it("resets the reason after a success, so it cannot carry into a count it does not fit", async () => {
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /stock_balances": () => listResponse([balance()]),
          "POST /stock_adjustments": () =>
            jsonResponse({ data: { movement: null, balance: balance() } }),
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      await fillForm(user, { counted: "10" });
      await user.selectOptions(
        screen.getByLabelText("Motivo", { selector: "form select" }),
        "theft",
      );
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));

      await waitFor(() => {
        expect(screen.getByRole("status")).toHaveTextContent("confere");
      });
      expect(screen.getByLabelText("Motivo", { selector: "form select" })).toHaveValue("count");
      expect(screen.getByLabelText(/Quantidade contada/)).toHaveFocus();
    });

    it("lists an inactive product too, marked as such, since it may still hold stock", async () => {
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /products": () => listResponse([product({ active: false })]),
          "GET /stock_balances": () => listResponse([balance()]),
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);

      expect(
        screen.getByRole("option", { name: "Cimento CP II (CIM-001) (inativo)" }),
      ).toBeInTheDocument();
    });

    it("tells the operator what is missing before the balance can be shown, and offers a retry when it fails", async () => {
      let attempts = 0;
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /stock_balances": (request) => {
            if (!new URL(request.url).searchParams.get("product_id"))
              return listResponse([balance()]);
            attempts += 1;
            return attempts === 1
              ? errorEnvelope("internal", "boom", {}, 500)
              : listResponse([balance()]);
          },
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      expect(
        screen.getByText("Escolha o produto e o depósito para ver o saldo atual."),
      ).toBeInTheDocument();

      await user.selectOptions(screen.getByLabelText("Produto", { selector: "select" }), "7");
      await user.selectOptions(screen.getByLabelText("Depósito", { selector: "form select" }), "1");
      await user.click(await screen.findByRole("button", { name: "Tentar novamente" }));

      expect(await screen.findByText(/Saldo atual: 120,5 UN/)).toBeInTheDocument();
    });

    it("searches products on the server and says when the list is only the first part of the matches", async () => {
      const searches: (string | null)[] = [];
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /products": (request) => {
            searches.push(new URL(request.url).searchParams.get("q"));
            return jsonResponse({ data: [product()], meta: { page: 1, per_page: 50, total: 120 } });
          },
          "GET /stock_balances": () => listResponse([balance()]),
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      expect(
        await screen.findByText("Mostrando 1 de 120 produtos. Refine a busca para ver os demais."),
      ).toBeInTheDocument();

      await user.type(screen.getByLabelText("Buscar produto para contar"), "cim");

      await waitFor(() => {
        expect(searches).toContain("cim");
      });
    });

    it("keeps the chosen product in the picker when the search then narrows to something else", async () => {
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /products": (request) =>
            new URL(request.url).searchParams.get("q") === "zzz"
              ? listResponse([])
              : listResponse([product()]),
          "GET /stock_balances": () => listResponse([balance()]),
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      await user.selectOptions(screen.getByLabelText("Produto", { selector: "select" }), "7");
      await user.type(screen.getByLabelText("Buscar produto para contar"), "zzz");

      expect(await screen.findByText("Nenhum produto encontrado.")).toBeInTheDocument();
      expect(screen.getByLabelText("Produto", { selector: "select" })).toHaveValue("7");
    });

    it("echoes how the counted quantity is read, and never takes 0.500 for five hundred", async () => {
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /stock_balances": () => listResponse([balance()]),
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      await user.selectOptions(screen.getByLabelText("Produto", { selector: "select" }), "7");
      await user.type(screen.getByLabelText(/Quantidade contada/), "0.500");

      expect(screen.getByText("Contagem lida como 0,5 UN.")).toBeInTheDocument();

      await user.clear(screen.getByLabelText(/Quantidade contada/));
      await user.type(screen.getByLabelText(/Quantidade contada/), "12.500");

      expect(screen.getByText("Contagem lida como 12.500 UN.")).toBeInTheDocument();
    });

    it("says nothing was adjusted when the count matches", async () => {
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /stock_balances": () => listResponse([balance()]),
          "POST /stock_adjustments": () =>
            jsonResponse({ data: { movement: null, balance: balance() } }, 200),
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      await fillForm(user, { counted: "120,5" });
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));

      await waitFor(() => {
        expect(screen.getByRole("status")).toHaveTextContent("A contagem confere com o saldo");
      });
    });

    it("stops an unreadable quantity or cost before calling the API", async () => {
      const post = vi.fn(() => jsonResponse({}, 201));
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /stock_balances": () => listResponse([balance()]),
          "POST /stock_adjustments": post,
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      await fillForm(user, { counted: "1,2,3", unitCost: "abc" });
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));

      expect(post).not.toHaveBeenCalled();
      expect(
        await screen.findByText("Informe um número válido, como 12 ou 12,5."),
      ).toBeInTheDocument();
      expect(screen.getByText("Informe um valor válido, como 32,50.")).toBeInTheDocument();
    });

    it("explains a missing cost on the field, and uses a new key for the corrected attempt", async () => {
      const keys: string[] = [];
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /stock_balances": () => listResponse([balance()]),
          "POST /stock_adjustments": (request) => {
            keys.push(request.headers.get("Idempotency-Key") ?? "");
            return keys.length === 1
              ? errorEnvelope("validation_failed", "invalid", {
                  fields: { unit_cost_cents: ["required"] },
                })
              : jsonResponse({ data: { movement: null, balance: balance() } });
          },
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      await fillForm(user, { counted: "10" });
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));
      expect(
        await screen.findByText(/Informe o custo unitário: este produto ainda não tem custo/),
      ).toBeInTheDocument();

      await user.type(screen.getByLabelText("Custo unitário (R$)"), "1,50");
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));

      await waitFor(() => {
        expect(keys).toHaveLength(2);
      });
      expect(keys[0]).not.toBe(keys[1]);
    });

    it.each([
      ["a lock conflict", () => errorEnvelope("conflict_retry", "busy", {}, 409)],
      ["a server error", () => errorEnvelope("internal", "boom", {}, 500)],
    ])(
      "keeps the same key when retrying after %s, so the count is never applied twice",
      async (_name, failure) => {
        const keys: string[] = [];
        vi.stubGlobal(
          "fetch",
          createFetchMock({
            ...defaultHandlers,
            "GET /stock_balances": () => listResponse([balance()]),
            "POST /stock_adjustments": (request) => {
              keys.push(request.headers.get("Idempotency-Key") ?? "");
              return keys.length === 1
                ? failure()
                : jsonResponse({ data: { movement: null, balance: balance() } });
            },
          }),
        );
        const user = userEvent.setup();
        renderScreen();

        await openForm(user);
        await fillForm(user, { counted: "10" });
        await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));
        await screen.findByRole("alert");
        await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));

        await waitFor(() => {
          expect(keys).toHaveLength(2);
        });
        expect(keys[0]).toBe(keys[1]);
      },
    );

    it("keeps the same key after the connection drops", async () => {
      const keys: string[] = [];
      let calls = 0;
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /stock_balances": () => listResponse([balance()]),
          "POST /stock_adjustments": (request) => {
            keys.push(request.headers.get("Idempotency-Key") ?? "");
            calls += 1;
            if (calls === 1) throw new TypeError("Failed to fetch");
            return jsonResponse({ data: { movement: null, balance: balance() } });
          },
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      await fillForm(user, { counted: "10" });
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));
      await screen.findByRole("alert");
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));

      await waitFor(() => {
        expect(keys).toHaveLength(2);
      });
      expect(keys[0]).toBe(keys[1]);
    });

    it("uses a new key for the next count after a success", async () => {
      const keys: string[] = [];
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /stock_balances": () => listResponse([balance()]),
          "POST /stock_adjustments": (request) => {
            keys.push(request.headers.get("Idempotency-Key") ?? "");
            return jsonResponse({ data: { movement: null, balance: balance() } });
          },
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await openForm(user);
      await fillForm(user, { counted: "10" });
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));
      await waitFor(() => {
        expect(screen.getByRole("status")).toHaveTextContent("confere");
      });
      await user.type(screen.getByLabelText(/Quantidade contada/), "11");
      await user.click(screen.getByRole("button", { name: "Registrar ajuste" }));

      await waitFor(() => {
        expect(keys).toHaveLength(2);
      });
      expect(keys[0]).not.toBe(keys[1]);
    });
  });
});

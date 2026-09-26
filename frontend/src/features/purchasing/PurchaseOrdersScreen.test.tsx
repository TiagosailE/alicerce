import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createFetchMock, errorEnvelope, listResponse } from "../../test/api";
import { cellText, nth } from "../../test/dom";
import { PurchaseOrdersScreen } from "./PurchaseOrdersScreen";
import { summary } from "./testData";

function renderScreen(canManage = true) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={["/compras"]}>
        <Routes>
          <Route path="/compras" element={<PurchaseOrdersScreen canManage={canManage} />} />
          <Route path="/compras/novo" element={<h1>Formulário novo</h1>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("PurchaseOrdersScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("lists the orders with number, supplier, status, date and the total the API stored", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /purchase_orders": () =>
          listResponse([
            summary(),
            summary({ id: 8, number: 3, status: "partially_received", total_cents: 1 }),
          ]),
      }),
    );

    renderScreen();

    const row = (await screen.findByRole("link", { name: "4" })).closest("tr");
    const cells = within(row as HTMLElement).getAllByRole("cell");
    expect(nth(cells, 1)).toHaveTextContent("Cimentos Bahia");
    expect(nth(cells, 2)).toHaveTextContent("Rascunho");
    expect(cellText(cells, 4)).toBe("R$ 6.370,00");
    expect(screen.getByRole("link", { name: "4" })).toHaveAttribute("href", "/compras/9");
    expect(within(screen.getByRole("table")).getByText("Recebido em parte")).toBeInTheDocument();
  });

  it("offers a new order only to a role that may write purchasing", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /purchase_orders": () => listResponse([summary()]) }),
    );
    const user = userEvent.setup();
    renderScreen(true);

    await user.click(await screen.findByRole("button", { name: "Novo pedido" }));

    expect(await screen.findByRole("heading", { name: "Formulário novo" })).toBeInTheDocument();
  });

  it("does not offer a new order to a read-only role", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /purchase_orders": () => listResponse([summary()]) }),
    );

    renderScreen(false);

    await screen.findByRole("link", { name: "4" });
    expect(screen.queryByRole("button", { name: "Novo pedido" })).not.toBeInTheDocument();
  });

  it("sends the status and the search to the API, and can clear them", async () => {
    const urls: string[] = [];
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /purchase_orders": (request) => {
          urls.push(request.url);
          return listResponse([]);
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();
    expect(await screen.findByText(/Ainda não há pedidos de compra/)).toBeInTheDocument();

    await user.selectOptions(screen.getByLabelText("Situação"), "approved");
    await user.type(screen.getByLabelText("Buscar"), "bahia");

    await waitFor(() => {
      const last = new URL(urls.at(-1) ?? "");
      expect(last.searchParams.get("status")).toBe("approved");
      expect(last.searchParams.get("q")).toBe("bahia");
    });
    expect(
      await screen.findByText("Nenhum pedido encontrado com esses filtros."),
    ).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Limpar filtros" }));

    await waitFor(() => {
      expect(screen.getByLabelText("Buscar")).toHaveValue("");
    });
    expect(screen.getByLabelText("Situação")).toHaveValue("");
  });

  it("shows a load error with the request id and a retry", async () => {
    let attempt = 0;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /purchase_orders": () => {
          attempt += 1;
          return attempt === 1
            ? errorEnvelope("forbidden", "no", {}, 403)
            : listResponse([summary()]);
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Não foi possível carregar os pedidos.",
    );
    await user.click(screen.getByRole("button", { name: "Tentar novamente" }));

    expect(await screen.findByRole("link", { name: "4" })).toBeInTheDocument();
  });
});

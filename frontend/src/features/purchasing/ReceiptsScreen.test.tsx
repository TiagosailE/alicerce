import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes, useLocation } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createFetchMock, errorEnvelope, listResponse } from "../../test/api";
import { cellText, nth } from "../../test/dom";
import { ReceiptsScreen } from "./ReceiptsScreen";
import { receiptSummary } from "./testData";

function Address() {
  const location = useLocation();
  return <output aria-label="endereço">{location.search}</output>;
}

function renderScreen(canManage = true, path = "/recebimentos") {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[path]}>
        <Address />
        <Routes>
          <Route path="/recebimentos" element={<ReceiptsScreen canManage={canManage} />} />
          <Route path="/compras" element={<h1>Pedidos</h1>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("ReceiptsScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("lists receipts with number, order, supplier, warehouse, day and the total the API stored", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /receipts": () =>
          listResponse([
            receiptSummary(),
            receiptSummary({ id: 32, number: 3, order: { id: 10, number: 5 }, total_cents: 1 }),
          ]),
      }),
    );

    renderScreen();

    const row = (await screen.findByRole("link", { name: "2" })).closest("tr");
    const cells = within(row as HTMLElement).getAllByRole("cell");
    expect(nth(cells, 1)).toHaveTextContent("4");
    expect(nth(cells, 2)).toHaveTextContent("Cimentos Bahia");
    expect(nth(cells, 3)).toHaveTextContent("Loja");
    expect(nth(cells, 4)).toHaveTextContent("26/09/2026");
    expect(cellText(cells, 5)).toBe("R$ 3.822,00");
    expect(screen.getByRole("link", { name: "2" })).toHaveAttribute("href", "/recebimentos/31");
    expect(within(row as HTMLElement).getByRole("link", { name: "4" })).toHaveAttribute(
      "href",
      "/compras/9",
    );
  });

  it("marks the receipts tab as the current page, next to the orders tab", async () => {
    vi.stubGlobal("fetch", createFetchMock({ "GET /receipts": () => listResponse([]) }));

    renderScreen();

    const tabs = await screen.findByRole("navigation", { name: "Compras" });
    expect(within(tabs).getByRole("link", { name: "Recebimentos" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    expect(within(tabs).getByRole("link", { name: "Pedidos" })).not.toHaveAttribute("aria-current");
  });

  it("narrows to one order from the address, says so, and shows all again on request", async () => {
    const urls: string[] = [];
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /receipts": (request) => {
          urls.push(request.url);
          return listResponse([receiptSummary()]);
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen(true, "/recebimentos?order=9&q=bahia&page=2");

    expect(await screen.findByText("Somente os recebimentos de um pedido.")).toBeInTheDocument();
    const first = new URL(urls[0] ?? "");
    expect(first.searchParams.get("order_id")).toBe("9");
    expect(first.searchParams.get("q")).toBe("bahia");
    expect(first.searchParams.get("page")).toBe("2");

    await user.click(screen.getByRole("button", { name: "Ver todos os recebimentos" }));

    await waitFor(() => {
      expect(screen.getByLabelText("endereço")).toHaveTextContent("?q=bahia");
    });
    expect(screen.queryByText("Somente os recebimentos de um pedido.")).not.toBeInTheDocument();
  });

  it("ignores an order or a page in the address that is not a number", async () => {
    const urls: string[] = [];
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /receipts": (request) => {
          urls.push(request.url);
          return listResponse([receiptSummary()]);
        },
      }),
    );

    renderScreen(true, "/recebimentos?order=abc&page=-3");

    await screen.findByRole("link", { name: "2" });
    const first = new URL(urls[0] ?? "");
    expect(first.searchParams.has("order_id")).toBe(false);
    expect(first.searchParams.get("page")).toBe("1");
  });

  it("sends the search to the API", async () => {
    const urls: string[] = [];
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /receipts": (request) => {
          urls.push(request.url);
          return listResponse([]);
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();
    await screen.findByText(/Ainda não há recebimentos/);

    await user.type(screen.getByLabelText("Buscar"), "bahia");

    await waitFor(() => {
      expect(new URL(urls.at(-1) ?? "").searchParams.get("q")).toBe("bahia");
    });
    expect(
      await screen.findByText("Nenhum recebimento encontrado com esses filtros."),
    ).toBeInTheDocument();
  });

  it("points whoever may write to the orders, and tells anyone else there is nothing yet", async () => {
    vi.stubGlobal("fetch", createFetchMock({ "GET /receipts": () => listResponse([]) }));
    renderScreen(true);

    expect(
      await screen.findByText(/Receba a mercadoria de um pedido aprovado/),
    ).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Ver pedidos" })).toHaveAttribute("href", "/compras");
  });

  it("does not point a read-only role to anything", async () => {
    vi.stubGlobal("fetch", createFetchMock({ "GET /receipts": () => listResponse([]) }));
    renderScreen(false);

    expect(await screen.findByText("Ainda não há recebimentos.")).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Ver pedidos" })).not.toBeInTheDocument();
  });

  it("shows a load error with a retry", async () => {
    let attempt = 0;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /receipts": () => {
          attempt += 1;
          return attempt === 1
            ? errorEnvelope("forbidden", "no", {}, 403)
            : listResponse([receiptSummary()]);
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Não foi possível carregar os recebimentos.",
    );
    await user.click(screen.getByRole("button", { name: "Tentar novamente" }));

    expect(await screen.findByRole("link", { name: "2" })).toBeInTheDocument();
  });

  it("says an order has no receipts yet, rather than that a filter matched nothing, and links back to it", async () => {
    vi.stubGlobal("fetch", createFetchMock({ "GET /receipts": () => listResponse([]) }));

    renderScreen(true, "/recebimentos?order=9");

    expect(await screen.findByText("Este pedido ainda não tem recebimentos.")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Voltar ao pedido" })).toHaveAttribute(
      "href",
      "/compras/9",
    );
    expect(screen.queryByRole("button", { name: "Limpar filtros" })).not.toBeInTheDocument();
  });

  it("puts focus back on the search when the order filter is cleared", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /receipts": () => listResponse([receiptSummary()]) }),
    );
    const user = userEvent.setup();
    renderScreen(true, "/recebimentos?order=9");

    await user.click(await screen.findByRole("button", { name: "Ver todos os recebimentos" }));

    expect(screen.getByLabelText("Buscar")).toHaveFocus();
  });
});

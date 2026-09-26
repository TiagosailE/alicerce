import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createFetchMock, errorEnvelope, jsonResponse } from "../../test/api";
import { cellText, nth } from "../../test/dom";
import { ReceiptDetailScreen } from "./ReceiptDetailScreen";
import { title } from "../finance/testData";
import { receipt, receiptLine } from "./testData";

function renderScreen(
  canViewPayables = true,
  entry: string | { pathname: string; state: unknown } = "/recebimentos/31",
) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[entry]}>
        <Routes>
          <Route
            path="/recebimentos/:id"
            element={<ReceiptDetailScreen canViewPayables={canViewPayables} />}
          />
          <Route path="/recebimentos" element={<h1>Lista</h1>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("ReceiptDetailScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("shows the header and every line exactly as the API stored them", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /receipts/31": () => jsonResponse({ data: receipt() }) }),
    );

    renderScreen();

    expect(await screen.findByRole("heading", { name: "Recebimento nº 2" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Pedido nº 4" })).toHaveAttribute("href", "/compras/9");
    expect(screen.getByText("Cimentos Bahia")).toBeInTheDocument();
    expect(screen.getByText("Loja")).toBeInTheDocument();
    expect(screen.getByText("26/09/2026")).toBeInTheDocument();
    expect(screen.getByText("NF 1234")).toBeInTheDocument();
    expect(screen.getByText("Marina Costa")).toBeInTheDocument();
    const total = screen.getByText("Total do recebimento").nextElementSibling as HTMLElement;
    expect(total.textContent.replace(/\s/g, " ")).toBe("R$ 3.822,00");

    const row = screen.getByText("Cimento CP II").closest("tr");
    const cells = within(row as HTMLElement).getAllByRole("cell");
    expect(nth(cells, 1)).toHaveTextContent("120 SC");
    expect(nth(cells, 2)).toHaveTextContent("120 UN");
    expect(cellText(cells, 3)).toBe("R$ 32,50");
    expect(cellText(cells, 4)).toBe("R$ 3.900,00");
    expect(cellText(cells, 5)).toBe("2% (R$ 78,00)");
    expect(cellText(cells, 6)).toBe("R$ 3.822,00");
  });

  it("shows what entered stock in stock units when it differs from what was bought", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /receipts/31": () =>
          jsonResponse({
            data: receipt({
              lines: [
                receiptLine({
                  purchase_unit_code: "MIL",
                  stock_unit_code: "UN",
                  quantity: "5.000",
                  stock_quantity: "5000.000",
                }),
              ],
            }),
          }),
      }),
    );

    renderScreen();

    const row = (await screen.findByText("Cimento CP II")).closest("tr");
    const cells = within(row as HTMLElement).getAllByRole("cell");
    expect(nth(cells, 1)).toHaveTextContent("5 MIL");
    expect(nth(cells, 2)).toHaveTextContent("5.000 UN");
  });

  it("shows the payable it opened, with its installments, to a role that reads payables", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /receipts/31": () => jsonResponse({ data: receipt() }) }),
    );

    renderScreen(true);

    const section = await screen.findByRole("region", { name: "Conta a pagar" });
    expect(within(section).getByText("Aberta")).toBeInTheDocument();
    const rows = within(section).getAllByRole("row");
    expect(rows).toHaveLength(3);
    expect(nth(rows, 1)).toHaveTextContent("1");
    expect(nth(rows, 1)).toHaveTextContent("26/10/2026");
    expect(nth(rows, 2)).toHaveTextContent("25/11/2026");
    expect(cellText(within(nth(rows, 1)).getAllByRole("cell"), 2)).toBe("R$ 1.911,00");
  });

  it("says a receipt opened no payable when it was worth nothing", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /receipts/31": () =>
          jsonResponse({ data: receipt({ payable: null, total_cents: 0 }) }),
      }),
    );

    renderScreen(true);

    expect(
      await screen.findByText("Este recebimento não gerou conta a pagar."),
    ).toBeInTheDocument();
  });

  it("shows nothing about payables to a role that does not read them", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /receipts/31": () => jsonResponse({ data: receipt({ payable: null }) }),
      }),
    );

    renderScreen(false);

    await screen.findByRole("heading", { name: "Recebimento nº 2" });
    expect(screen.queryByText(/conta a pagar/i)).not.toBeInTheDocument();
  });

  it("says once, and moves focus to it, that the receipt was just registered", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /receipts/31": () => jsonResponse({ data: receipt() }) }),
    );

    renderScreen(true, { pathname: "/recebimentos/31", state: { saved: true } });

    const message = await screen.findByText("Recebimento registrado: o estoque foi atualizado.");
    expect(message).toHaveFocus();
  });

  it("says a receipt is not found, with no retry, on a 404 or an address that is not a number", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /receipts/31": () => errorEnvelope("not_found", "x", {}, 404),
      }),
    );

    renderScreen();

    expect(await screen.findByText("Este recebimento não foi encontrado.")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Tentar novamente" })).not.toBeInTheDocument();
  });

  it("does not ask the API for an address that is not a number", async () => {
    renderScreen(true, "/recebimentos/abc");

    expect(await screen.findByText("Este recebimento não foi encontrado.")).toBeInTheDocument();
    expect(fetch).not.toHaveBeenCalled();
  });

  it("says a receipt cannot be undone, and how a mistake is corrected", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /receipts/31": () => jsonResponse({ data: receipt() }) }),
    );

    renderScreen(false);

    expect(await screen.findByText(/Um recebimento não pode ser desfeito/)).toBeInTheDocument();
    expect(screen.getByText(/registre um ajuste de estoque/)).toBeInTheDocument();
  });

  it("labels a cancelled payable as cancelled", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /receipts/31": () =>
          jsonResponse({ data: receipt({ payable: title({ status: "cancelled" }) }) }),
      }),
    );

    renderScreen(true);

    const section = await screen.findByRole("region", { name: "Conta a pagar" });
    expect(within(section).getByText("Cancelada")).toBeInTheDocument();
  });
});

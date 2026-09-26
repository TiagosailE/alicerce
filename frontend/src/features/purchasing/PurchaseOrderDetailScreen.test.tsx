import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createFetchMock, errorEnvelope, jsonBody, jsonResponse } from "../../test/api";
import { cellText, nth } from "../../test/dom";
import { PurchaseOrderDetailScreen } from "./PurchaseOrderDetailScreen";
import { order, orderLine } from "./testData";

function renderScreen(
  canManage = true,
  entry: string | { pathname: string; state: unknown } = "/compras/9",
) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[entry]}>
        <Routes>
          <Route
            path="/compras/:id"
            element={<PurchaseOrderDetailScreen canManage={canManage} />}
          />
          <Route path="/compras/:id/editar" element={<h1>Editar</h1>} />
          <Route path="/compras" element={<h1>Lista</h1>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("PurchaseOrderDetailScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("shows the header and every line exactly as the API stored them", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /purchase_orders/9": () =>
          jsonResponse({
            data: order({
              status: "partially_received",
              lines: [orderLine({ received_quantity: "120.000", remaining_quantity: "80.000" })],
            }),
          }),
      }),
    );

    renderScreen();

    expect(
      await screen.findByRole("heading", { name: "Pedido de compra nº 4" }),
    ).toBeInTheDocument();
    expect(screen.getByText("Recebido em parte")).toBeInTheDocument();
    expect(screen.getByText("Cimentos Bahia")).toBeInTheDocument();
    expect(screen.getByText("NXKE3INSKJRI36")).toBeInTheDocument();
    expect(
      screen.getByText(
        /2 parcelas, a primeira 30 dias após o recebimento e as demais a cada 30 dias/,
      ),
    ).toBeInTheDocument();
    expect(screen.getByText("Entrega na segunda")).toBeInTheDocument();
    const total = screen.getByText("Total do pedido").nextElementSibling as HTMLElement;
    expect(total.textContent.replace(/\s/g, " ")).toBe("R$ 6.370,00");
    const row = screen.getByText("Cimento CP II").closest("tr");
    const cells = within(row as HTMLElement).getAllByRole("cell");
    expect(nth(cells, 1)).toHaveTextContent("200 SC");
    expect(nth(cells, 2)).toHaveTextContent("120 SC");
    expect(nth(cells, 3)).toHaveTextContent("80 SC");
    expect(cellText(cells, 4)).toBe("R$ 32,50");
    expect(nth(cells, 5)).toHaveTextContent("2%");
    expect(cellText(cells, 6)).toBe("R$ 6.370,00");
  });

  it("says an approved order is locked, and offers only what its state allows", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /purchase_orders/9": () =>
          jsonResponse({ data: order({ status: "approved", revision: 1 }) }),
      }),
    );

    renderScreen();

    expect(await screen.findByText(/os itens e os valores estão travados/)).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Editar rascunho" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Aprovar pedido" })).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Cancelar pedido" })).toBeInTheDocument();
  });

  it("offers nothing to change on a closed order, and says why", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /purchase_orders/9": () => jsonResponse({ data: order({ status: "received" }) }),
      }),
    );

    renderScreen();

    expect(await screen.findByText(/Recebido por completo/)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Cancelar pedido" })).not.toBeInTheDocument();
  });

  it("offers no action to a role that may not write purchasing", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /purchase_orders/9": () => jsonResponse({ data: order() }) }),
    );

    renderScreen(false);

    await screen.findByRole("heading", { name: "Pedido de compra nº 4" });
    expect(screen.queryByRole("button", { name: "Aprovar pedido" })).not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Editar rascunho" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Cancelar pedido" })).not.toBeInTheDocument();
  });

  it("approves a draft from the revision that was read, and shows it approved", async () => {
    let body: unknown;
    let approved = false;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /purchase_orders/9": () =>
          jsonResponse({
            data: approved ? order({ status: "approved", revision: 4 }) : order({ revision: 3 }),
          }),
        "POST /purchase_orders/9/approval": async (request) => {
          body = await jsonBody(request);
          approved = true;
          return jsonResponse({ data: order({ status: "approved", revision: 4 }) });
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await user.click(await screen.findByRole("button", { name: "Aprovar pedido" }));

    expect(await screen.findByText("Pedido aprovado.")).toBeInTheDocument();
    expect(body).toEqual({ revision: 3 });
    expect(await screen.findByText(/os itens e os valores estão travados/)).toBeInTheDocument();
  });

  it("answers a stale approval by saying the draft changed, and reloads it on request", async () => {
    let reads = 0;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /purchase_orders/9": () => {
          reads += 1;
          return jsonResponse({
            data: order({ revision: reads === 1 ? 0 : 1, note: reads === 1 ? "Antiga" : "Nova" }),
          });
        },
        "POST /purchase_orders/9/approval": () =>
          errorEnvelope("stale", "stale", { current_revision: 1 }, 409),
      }),
    );
    const user = userEvent.setup();
    renderScreen();
    await user.click(await screen.findByRole("button", { name: "Aprovar pedido" }));

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("O rascunho foi alterado por outra pessoa");
    await user.click(screen.getByRole("button", { name: "Recarregar" }));

    expect(await screen.findByText("Nova")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Recarregar" })).not.toBeInTheDocument();
  });

  it("explains a changed unit conversion, and a plain validation failure, in their own words", async () => {
    let failure: Response = errorEnvelope("validation_failed", "x", {
      fields: { "lines.0.conversion": ["changed"] },
    });
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /purchase_orders/9": () => jsonResponse({ data: order() }),
        "POST /purchase_orders/9/approval": () => failure.clone(),
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await user.click(await screen.findByRole("button", { name: "Aprovar pedido" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "A unidade de compra ou o fator de um produto mudou",
    );

    failure = errorEnvelope("validation_failed", "x", {
      fields: { "lines.0.product_id": ["inactive"] },
    });
    await user.click(screen.getByRole("button", { name: "Aprovar pedido" }));
    expect(await screen.findByText(/não pode ser aprovado como está/)).toBeInTheDocument();
  });

  it("asks before cancelling, says what stays, and cancels", async () => {
    let cancelled = false;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /purchase_orders/9": () =>
          jsonResponse({ data: order({ status: cancelled ? "cancelled" : "approved" }) }),
        "POST /purchase_orders/9/cancellation": () => {
          cancelled = true;
          return jsonResponse({
            data: order({ status: "cancelled", cancelled_at: "2026-09-27T12:00:00Z" }),
          });
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await user.click(await screen.findByRole("button", { name: "Cancelar pedido" }));
    const dialog = screen.getByRole("alertdialog");
    expect(dialog).toHaveTextContent("Cancelar o pedido nº 4?");
    expect(dialog).toHaveTextContent("O que já foi recebido continua no estoque");
    await user.click(within(dialog).getByRole("button", { name: "Voltar" }));
    expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Cancelar pedido" }));
    await user.click(
      within(screen.getByRole("alertdialog")).getByRole("button", { name: "Sim, cancelar pedido" }),
    );

    expect(await screen.findByText("Pedido cancelado.")).toBeInTheDocument();
    expect(screen.getByText(/Cancelado: não recebe mais mercadoria/)).toBeInTheDocument();
    expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument();
  });

  it("says a cancellation was refused because the order is already closed", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /purchase_orders/9": () => jsonResponse({ data: order({ status: "approved" }) }),
        "POST /purchase_orders/9/cancellation": () =>
          errorEnvelope("invalid_transition", "x", {}, 409),
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await user.click(await screen.findByRole("button", { name: "Cancelar pedido" }));
    await user.click(
      within(screen.getByRole("alertdialog")).getByRole("button", { name: "Sim, cancelar pedido" }),
    );

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "já foi recebido por completo ou cancelado",
    );
  });

  it("opens the edit screen for a draft", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /purchase_orders/9": () => jsonResponse({ data: order() }) }),
    );
    const user = userEvent.setup();
    renderScreen();

    await user.click(await screen.findByRole("link", { name: "Editar rascunho" }));

    expect(await screen.findByRole("heading", { name: "Editar" })).toBeInTheDocument();
  });

  it("says what the terms are in words: one installment, on receipt, in one day", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /purchase_orders/9": () =>
          jsonResponse({ data: order({ installments: 1, first_due_days: 0, interval_days: 0 }) }),
      }),
    );

    renderScreen();

    expect(await screen.findByText("1 parcela, no recebimento")).toBeInTheDocument();
  });

  it("tells a role that cannot write what a draft is, without telling it to approve", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /purchase_orders/9": () => jsonResponse({ data: order() }) }),
    );

    renderScreen(false);

    expect(
      await screen.findByText(/Só quem faz compras pode editar e aprovar/),
    ).toBeInTheDocument();
    expect(screen.queryByText(/Aprove o pedido/)).not.toBeInTheDocument();
  });

  it("does not ask the API for an address that is not an order number", async () => {
    renderScreen(true, "/compras/novo");

    expect(await screen.findByText("Este pedido não foi encontrado.")).toBeInTheDocument();
    expect(fetch).not.toHaveBeenCalled();
    expect(screen.queryByRole("button", { name: "Tentar novamente" })).not.toBeInTheDocument();
  });

  it("says an order is not found, with no retry, when the API answers 404", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /purchase_orders/9": () => errorEnvelope("not_found", "x", {}, 404),
      }),
    );

    renderScreen();

    expect(await screen.findByText("Este pedido não foi encontrado.")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Tentar novamente" })).not.toBeInTheDocument();
  });

  it("says once that a draft was saved when it opens right after the save", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /purchase_orders/9": () => jsonResponse({ data: order() }) }),
    );

    renderScreen(true, { pathname: "/compras/9", state: { saved: true } });

    const message = await screen.findByText("Rascunho salvo.");
    expect(message).toHaveFocus();
  });

  it("moves focus to the message when an approval removes its own button", async () => {
    let approved = false;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /purchase_orders/9": () =>
          jsonResponse({ data: approved ? order({ status: "approved" }) : order() }),
        "POST /purchase_orders/9/approval": () => {
          approved = true;
          return jsonResponse({ data: order({ status: "approved", revision: 1 }) });
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await user.click(await screen.findByRole("button", { name: "Aprovar pedido" }));

    expect(await screen.findByText("Pedido aprovado.")).toHaveFocus();
    expect(screen.queryByRole("button", { name: "Aprovar pedido" })).not.toBeInTheDocument();
  });

  it("refreshes an order the approval found already approved, so its buttons catch up", async () => {
    let reads = 0;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /purchase_orders/9": () => {
          reads += 1;
          return jsonResponse({ data: reads === 1 ? order() : order({ status: "approved" }) });
        },
        "POST /purchase_orders/9/approval": () => errorEnvelope("invalid_transition", "x", {}, 409),
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await user.click(await screen.findByRole("button", { name: "Aprovar pedido" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "A tela agora mostra o estado atual",
    );
    await waitFor(() => {
      expect(screen.queryByRole("button", { name: "Aprovar pedido" })).not.toBeInTheDocument();
    });
    expect(screen.getByText(/os itens e os valores estão travados/)).toBeInTheDocument();
  });

  it("puts focus on the safe answer of the cancel dialog, and gives it back on Voltar and on Escape", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /purchase_orders/9": () => jsonResponse({ data: order() }) }),
    );
    const user = userEvent.setup();
    renderScreen();

    await user.click(await screen.findByRole("button", { name: "Cancelar pedido" }));
    const dialog = screen.getByRole("alertdialog");
    expect(dialog).toHaveTextContent("O rascunho será cancelado e não poderá mais ser editado");
    expect(dialog).not.toHaveTextContent("O que já foi recebido continua no estoque");
    expect(within(dialog).getByRole("button", { name: "Voltar" })).toHaveFocus();

    await user.click(within(dialog).getByRole("button", { name: "Voltar" }));
    expect(screen.getByRole("button", { name: "Cancelar pedido" })).toHaveFocus();

    await user.click(screen.getByRole("button", { name: "Cancelar pedido" }));
    expect(screen.getByRole("alertdialog")).toBeInTheDocument();
    await user.keyboard("{Escape}");

    expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Cancelar pedido" })).toHaveFocus();
  });
});

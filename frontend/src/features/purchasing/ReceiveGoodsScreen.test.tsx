import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes, useLocation } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  createFetchMock,
  errorEnvelope,
  jsonBody,
  jsonResponse,
  listResponse,
} from "../../test/api";
import { dayInZone, formatDate } from "../../lib/format";
import { RECEIPT_MAX_LINES } from "./receiptsApi";
import { order, orderLine, receipt } from "./testData";
import { ReceiveGoodsScreen } from "./ReceiveGoodsScreen";

const ZONE = "America/Bahia";

const warehouses = [
  { id: 5, name: "Loja", active: true },
  { id: 6, name: "Pátio", active: true },
];

/** Two open lines and one already received in full. */
function receivableOrder(overrides = {}) {
  return order({
    status: "approved",
    revision: 1,
    approved_at: "2026-09-20T15:00:00Z",
    lines: [
      orderLine({ id: 501, position: 1, quantity: "200.000", remaining_quantity: "200.000" }),
      orderLine({
        id: 502,
        position: 2,
        product: { id: 8, sku: "AREIA-1", name: "Areia média" },
        quantity: "50.000",
        received_quantity: "50.000",
        remaining_quantity: "0.000",
      }),
      orderLine({
        id: 503,
        position: 3,
        product: { id: 9, sku: "BRITA-1", name: "Brita 1" },
        quantity: "200.000",
        received_quantity: "120.000",
        remaining_quantity: "80.000",
      }),
    ],
    ...overrides,
  });
}

function Saved() {
  const location = useLocation();
  return (
    <div>
      <h1>Recebimento registrado</h1>
      <output aria-label="estado">{JSON.stringify(location.state)}</output>
    </div>
  );
}

function renderAt(path = "/compras/9/receber", timeZone = ZONE, canViewPayables = true) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[path]}>
        <Routes>
          <Route
            path="/compras/:id/receber"
            element={<ReceiveGoodsScreen timeZone={timeZone} canViewPayables={canViewPayables} />}
          />
          <Route path="/compras/:id" element={<h1>Pedido</h1>} />
          <Route path="/recebimentos/:id" element={<Saved />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

const base = {
  "GET /warehouses": () => listResponse(warehouses),
};

/** The open lines' quantity inputs are named by their position and product. */
function quantityOf(product: string, position: number) {
  return screen.getByLabelText(`Quantidade a receber, item ${String(position)}: ${product}`);
}

const CIMENTO = ["Cimento CP II", 1] as const;
const BRITA = ["Brita 1", 3] as const;

async function chooseWarehouse(user: ReturnType<typeof userEvent.setup>, name = "Loja") {
  await screen.findByRole("option", { name });
  await user.selectOptions(screen.getByLabelText("Depósito"), name);
}

const review = (user: ReturnType<typeof userEvent.setup>) =>
  user.click(screen.getByRole("button", { name: "Revisar recebimento" }));
const confirm = (user: ReturnType<typeof userEvent.setup>) =>
  user.click(screen.getByRole("button", { name: "Confirmar recebimento" }));

describe("ReceiveGoodsScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("shows only the lines with something left, with how much, and the terms the payable will follow", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
      }),
    );

    renderAt();

    expect(
      await screen.findByRole("heading", { name: "Receber mercadoria do pedido nº 4" }),
    ).toBeInTheDocument();
    expect(
      await screen.findByLabelText(/^Quantidade a receber, item 1: Cimento CP II$/),
    ).toBeInTheDocument();
    expect(quantityOf(...BRITA)).toBeInTheDocument();
    expect(screen.queryByLabelText(/Areia média/)).not.toBeInTheDocument();
    expect(quantityOf(...BRITA).closest("tr")).toHaveTextContent("80 SC");
    expect(
      screen.getByText(/2 parcelas, a primeira 30 dias após o recebimento/),
    ).toBeInTheDocument();
    expect(screen.getByText(/a conta a pagar é aberta em seguida/)).toBeInTheDocument();
  });

  it("does not talk about payables to a role that cannot read them", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
      }),
    );

    renderAt("/compras/9/receber", ZONE, false);

    await screen.findByLabelText(/Quantidade a receber, item 1/);
    expect(screen.queryByText(/conta a pagar/i)).not.toBeInTheDocument();
    expect(screen.getByText(/O estoque entra pelo custo do pedido\./)).toBeInTheDocument();
  });

  it("tells two lines of the same product apart by their item number", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () =>
          jsonResponse({
            data: receivableOrder({
              lines: [
                orderLine({ id: 501, position: 1, remaining_quantity: "10.000" }),
                orderLine({ id: 504, position: 2, remaining_quantity: "20.000" }),
              ],
            }),
          }),
      }),
    );

    renderAt();

    expect(
      await screen.findByLabelText("Quantidade a receber, item 1: Cimento CP II"),
    ).toBeInTheDocument();
    expect(
      screen.getByLabelText("Quantidade a receber, item 2: Cimento CP II"),
    ).toBeInTheDocument();
  });

  it("reviews what is about to be received, with its warning, before it is sent", async () => {
    let posted = false;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
        "POST /purchase_orders/9/receipts": () => {
          posted = true;
          return jsonResponse({ data: receipt() }, 201);
        },
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user);
    await user.type(quantityOf(...CIMENTO), "120");
    await user.type(quantityOf(...BRITA), "1.200");

    await review(user);

    const dialog = screen.getByRole("alertdialog", { name: "Confirmar o recebimento?" });
    expect(dialog).toHaveTextContent("Entra no depósito Loja");
    expect(dialog).toHaveTextContent("2 itens");
    expect(dialog).toHaveTextContent("Um recebimento não pode ser desfeito.");
    expect(within(dialog).getByText("120 SC de Cimento CP II")).toBeInTheDocument();
    expect(within(dialog).getByText("1.200 SC de Brita 1")).toBeInTheDocument();
    expect(within(dialog).getByRole("button", { name: "Voltar e corrigir" })).toHaveFocus();
    expect(posted).toBe(false);
  });

  it("returns from the review to the form on Voltar and on Escape, and closes it when a field is edited", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user);
    await user.type(quantityOf(...CIMENTO), "10");

    await review(user);
    await user.click(screen.getByRole("button", { name: "Voltar e corrigir" }));
    expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Revisar recebimento" })).toHaveFocus();

    await review(user);
    await user.keyboard("{Escape}");
    expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Revisar recebimento" })).toHaveFocus();

    await review(user);
    await user.type(quantityOf(...CIMENTO), "5");
    expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument();
  });

  it("goes to the review, not to the API, when Enter is pressed in a field", async () => {
    let posted = false;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
        "POST /purchase_orders/9/receipts": () => {
          posted = true;
          return jsonResponse({ data: receipt() }, 201);
        },
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user);

    await user.type(quantityOf(...CIMENTO), "10{Enter}");

    expect(screen.getByRole("alertdialog")).toBeInTheDocument();
    expect(posted).toBe(false);
  });

  it("sends only the lines that were filled, under an idempotency key, and opens the receipt", async () => {
    let body: unknown;
    const sent: { key: string | null } = { key: null };
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
        "POST /purchase_orders/9/receipts": async (request) => {
          body = await jsonBody(request);
          sent.key = request.headers.get("Idempotency-Key");
          return jsonResponse({ data: receipt() }, 201);
        },
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user);

    await user.type(quantityOf(...CIMENTO), "120");
    await user.type(screen.getByLabelText("Número da nota do fornecedor (opcional)"), "NF 1234");
    await review(user);
    await confirm(user);

    expect(
      await screen.findByRole("heading", { name: "Recebimento registrado" }),
    ).toBeInTheDocument();
    expect(body).toEqual({
      warehouse_id: 5,
      received_on: dayInZone(new Date(), ZONE),
      supplier_invoice_number: "NF 1234",
      lines: [{ order_line_id: 501, quantity: "120" }],
    });
    expect(sent.key).toHaveLength(36);
    expect(screen.getByLabelText("estado")).toHaveTextContent('{"saved":true}');
  });

  // At any instant at least one of these two zones is on another calendar day than
  // UTC, so a screen that used the browser's or UTC's day fails for one of them.
  it.each(["Pacific/Kiritimati", "Pacific/Pago_Pago"])(
    "starts from the organization's day in %s, and limits the date from the approval to that day",
    async (zone) => {
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...base,
          "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
        }),
      );

      renderAt("/compras/9/receber", zone);

      const date = await screen.findByLabelText("Data do recebimento");
      const today = dayInZone(new Date(), zone);
      const approved = dayInZone("2026-09-20T15:00:00Z", zone);
      expect(date).toHaveValue(today);
      expect(date).toHaveAttribute("max", today);
      expect(date).toHaveAttribute("min", approved);
      expect(date).toHaveAccessibleDescription(
        new RegExp(`A partir de ${formatDate(approved).replaceAll("/", "\\/")}`),
      );
    },
  );

  it("fills every open line with what is left, in the way it is typed, and says so", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
      }),
    );
    const user = userEvent.setup();
    renderAt();

    await user.click(await screen.findByRole("button", { name: "Preencher com o que falta" }));

    expect(quantityOf(...CIMENTO)).toHaveValue("200");
    expect(quantityOf(...BRITA)).toHaveValue("80");
    expect(screen.getByRole("status")).toHaveTextContent(
      "Quantidades preenchidas com o que falta.",
    );
  });

  it("fills only as many lines as one receipt takes, and says the rest goes in another", async () => {
    const many = Array.from({ length: RECEIPT_MAX_LINES + 1 }, (_, index) =>
      orderLine({
        id: 1000 + index,
        position: index + 1,
        product: {
          id: 100 + index,
          sku: `P-${String(index)}`,
          name: `Produto ${String(index + 1)}`,
        },
        remaining_quantity: "3.000",
      }),
    );
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder({ lines: many }) }),
      }),
    );
    const user = userEvent.setup();
    renderAt();

    await user.click(await screen.findByRole("button", { name: "Preencher com o que falta" }));

    expect(screen.getByLabelText("Quantidade a receber, item 50: Produto 50")).toHaveValue("3");
    expect(screen.getByLabelText("Quantidade a receber, item 51: Produto 51")).toHaveValue("");
    expect(screen.getAllByText(/Preenchidos os 50 primeiros itens/).length).toBeGreaterThan(0);
  });

  it("refuses more lines than one receipt takes, and lands on the message about the lines", async () => {
    const many = Array.from({ length: RECEIPT_MAX_LINES + 1 }, (_, index) =>
      orderLine({
        id: 1000 + index,
        position: index + 1,
        product: {
          id: 100 + index,
          sku: `P-${String(index)}`,
          name: `Produto ${String(index + 1)}`,
        },
        remaining_quantity: "3.000",
      }),
    );
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder({ lines: many }) }),
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user);
    for (const line of many) {
      await user.type(
        screen.getByLabelText(
          `Quantidade a receber, item ${String(line.position)}: ${line.product.name}`,
        ),
        "1",
      );
    }

    await review(user);

    const message = screen.getByText(/Um recebimento tem no máximo 50 itens/);
    expect(message).toHaveFocus();
    expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument();
  }, 20000);

  it("names what is wrong before anything is reviewed, and lands on the first field to fix", async () => {
    const fetchMock = createFetchMock({
      ...base,
      "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
    });
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();
    renderAt();
    await screen.findByRole("option", { name: "Loja" });

    await review(user);

    expect(screen.getByText("Escolha o depósito.")).toBeInTheDocument();
    expect(screen.getByText("Informe a quantidade de ao menos um item.")).toBeInTheDocument();
    expect(screen.getByLabelText("Depósito")).toHaveFocus();
    expect(screen.getByRole("alert")).toHaveTextContent(
      "2 campos precisam de correção antes de receber.",
    );
    expect(fetchMock.mock.calls.some(([input]) => (input as Request).method === "POST")).toBe(
      false,
    );
  });

  it("lands on the message about the lines when that is the only thing to fix", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user);

    await review(user);

    expect(screen.getByText("Informe a quantidade de ao menos um item.")).toHaveFocus();
  });

  it("refuses a quantity that is not a number or is zero, next to its line, and clears it on edit", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user);

    await user.type(quantityOf(...CIMENTO), "abc");
    await user.type(quantityOf(...BRITA), "0");
    await review(user);

    expect(screen.getByText("Informe a quantidade com números.")).toBeInTheDocument();
    expect(screen.getByText("A quantidade deve ser maior que zero.")).toBeInTheDocument();
    expect(quantityOf(...CIMENTO)).toHaveFocus();

    await user.clear(quantityOf(...CIMENTO));
    await user.type(quantityOf(...CIMENTO), "5");

    expect(screen.queryByText("Informe a quantidade com números.")).not.toBeInTheDocument();
    expect(screen.getByText("A quantidade deve ser maior que zero.")).toBeInTheDocument();
  });

  it("puts the API's line error on the right order line even when earlier lines were left blank", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
        "POST /purchase_orders/9/receipts": () =>
          errorEnvelope("validation_failed", "x", {
            fields: { "lines.0.quantity": ["over_receipt"] },
          }),
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user);

    await user.type(quantityOf(...BRITA), "500");
    await review(user);
    await confirm(user);

    const message = await screen.findByText("É mais do que falta receber. Confira a quantidade.");
    expect(message.closest("tr")).toHaveTextContent("Brita 1");
    expect(quantityOf(...BRITA)).toHaveAccessibleDescription(/É mais do que falta receber/);
    await waitFor(() => {
      expect(quantityOf(...BRITA)).toHaveFocus();
    });
    expect(quantityOf(...CIMENTO)).not.toHaveAttribute("aria-invalid");
    expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument();
  });

  it("names the date and the invoice number the API refused", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
        "POST /purchase_orders/9/receipts": () =>
          errorEnvelope("validation_failed", "x", {
            fields: {
              received_on: ["before_approval"],
              supplier_invoice_number: ["invalid"],
            },
          }),
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user);
    await user.type(quantityOf(...CIMENTO), "1");

    await review(user);
    await confirm(user);

    expect(
      await screen.findByText("A data não pode ser anterior à aprovação do pedido."),
    ).toBeInTheDocument();
    expect(screen.getByText(/Use só letras, números, espaço e/)).toBeInTheDocument();
    expect(screen.getByRole("alert")).toHaveTextContent("2 campos precisam de correção");
  });

  it("retries an identical request under the same key, and a refused one under a new key", async () => {
    const keys: (string | null)[] = [];
    const answers = [
      () => errorEnvelope("internal_error", "x", {}, 500),
      () =>
        errorEnvelope("validation_failed", "x", {
          fields: { "lines.0.quantity": ["over_receipt"] },
        }),
      () => jsonResponse({ data: receipt() }, 201),
    ];
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
        "POST /purchase_orders/9/receipts": (request) => {
          keys.push(request.headers.get("Idempotency-Key"));
          const answer = answers[keys.length - 1];
          if (!answer) throw new Error("unexpected call");
          return answer();
        },
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user);
    await user.type(quantityOf(...CIMENTO), "10");

    await review(user);
    await confirm(user);
    await screen.findByText(/A resposta não chegou/);
    // The failure that may have committed leaves the review open: confirming again is a retry.
    await confirm(user);
    await screen.findByText("É mais do que falta receber. Confira a quantidade.");
    await review(user);
    await confirm(user);
    await screen.findByRole("heading", { name: "Recebimento registrado" });

    expect(keys).toHaveLength(3);
    expect(keys[1]).toBe(keys[0]);
    expect(keys[2]).not.toBe(keys[1]);
  });

  it("says the receipt may have been registered when no answer arrived, and points to the order's receipts", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
        "POST /purchase_orders/9/receipts": () => errorEnvelope("internal_error", "x", {}, 500),
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user);
    await user.type(quantityOf(...CIMENTO), "10");

    await review(user);
    await confirm(user);

    const banner = await screen.findByText(/o recebimento pode ter sido registrado/);
    expect(
      within(banner.closest("div") as HTMLElement).getByRole("link", {
        name: "Ver recebimentos deste pedido",
      }),
    ).toHaveAttribute("href", "/recebimentos?order=9");
    await waitFor(() => {
      expect(banner.closest("div")).toHaveFocus();
    });
    expect(screen.getByRole("alertdialog")).toBeInTheDocument();
  });

  it("uses a new key when what is sent changes", async () => {
    const keys: (string | null)[] = [];
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
        "POST /purchase_orders/9/receipts": (request) => {
          keys.push(request.headers.get("Idempotency-Key"));
          return errorEnvelope("internal_error", "x", {}, 500);
        },
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user);
    await user.type(quantityOf(...CIMENTO), "10");
    await review(user);
    await confirm(user);
    await screen.findByText(/A resposta não chegou/);

    await user.type(quantityOf(...CIMENTO), "5");
    await review(user);
    await confirm(user);
    await waitFor(() => {
      expect(keys).toHaveLength(2);
    });

    expect(keys[1]).not.toBe(keys[0]);
  });

  it.each([
    [401, "Sua sessão terminou"],
    [403, "Você não tem permissão para receber mercadoria"],
  ])("says what a %i means, not just to try again", async (status, message) => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
        "POST /purchase_orders/9/receipts": () => errorEnvelope("denied", "x", {}, status),
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user);
    await user.type(quantityOf(...CIMENTO), "10");

    await review(user);
    await confirm(user);

    expect(await screen.findByText(new RegExp(message))).toBeInTheDocument();
  });

  it("says a stock balance below zero blocks the receipt", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
        "POST /purchase_orders/9/receipts": () => errorEnvelope("negative_balance", "x"),
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user);
    await user.type(quantityOf(...CIMENTO), "10");

    await review(user);
    await confirm(user);

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "O saldo de um dos produtos está negativo",
    );
    await waitFor(() => {
      expect(screen.getByRole("alert")).toHaveFocus();
    });
    expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument();
  });

  it("drops a stale banner when the form is checked again", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
        "POST /purchase_orders/9/receipts": () => errorEnvelope("negative_balance", "x"),
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user);
    await user.type(quantityOf(...CIMENTO), "10");
    await review(user);
    await confirm(user);
    await screen.findByText(/O saldo de um dos produtos está negativo/);

    await user.clear(quantityOf(...CIMENTO));
    await review(user);

    expect(screen.queryByText(/O saldo de um dos produtos está negativo/)).not.toBeInTheDocument();
  });

  it("refreshes the order, and says what state it is in, when it no longer receives goods", async () => {
    let reads = 0;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => {
          reads += 1;
          return jsonResponse({
            data: reads === 1 ? receivableOrder() : receivableOrder({ status: "cancelled" }),
          });
        },
        "POST /purchase_orders/9/receipts": () => errorEnvelope("invalid_transition", "x", {}, 409),
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user);
    await user.type(quantityOf(...CIMENTO), "10");

    await review(user);
    await confirm(user);

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Este pedido não recebe mercadoria");
    expect(alert).toHaveTextContent("Cancelado");
    expect(alert).toHaveTextContent("Cancelado: não recebe mais mercadoria.");
    await waitFor(() => {
      expect(alert).toHaveFocus();
    });
    expect(screen.queryByRole("button", { name: "Revisar recebimento" })).not.toBeInTheDocument();
  });

  it("does not open for an order that is not approved or partly received", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...base,
        "GET /purchase_orders/9": () => jsonResponse({ data: order({ status: "draft" }) }),
      }),
    );

    renderAt();

    expect(await screen.findByRole("alert")).toHaveTextContent("Este pedido não recebe mercadoria");
    expect(screen.getByRole("link", { name: "Voltar ao pedido" })).toHaveAttribute(
      "href",
      "/compras/9",
    );
    expect(screen.queryByRole("button", { name: "Revisar recebimento" })).not.toBeInTheDocument();
  });

  it("preselects the only active warehouse", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /warehouses": () =>
          listResponse([warehouses[0], { id: 6, name: "Pátio", active: false }]),
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
      }),
    );

    renderAt();

    await screen.findByRole("option", { name: "Loja" });
    expect(screen.getByLabelText("Depósito")).toHaveValue("5");
    expect(screen.queryByRole("option", { name: "Pátio" })).not.toBeInTheDocument();
  });

  it("drops a warehouse the API says is inactive from the list", async () => {
    let reads = 0;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /warehouses": () => {
          reads += 1;
          return listResponse(
            reads === 1 ? warehouses : [warehouses[0], { id: 6, name: "Pátio", active: false }],
          );
        },
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
        "POST /purchase_orders/9/receipts": () =>
          errorEnvelope("validation_failed", "x", { fields: { warehouse_id: ["inactive"] } }),
      }),
    );
    const user = userEvent.setup();
    renderAt();
    await chooseWarehouse(user, "Pátio");
    await user.type(quantityOf(...CIMENTO), "10");

    await review(user);
    await confirm(user);

    expect(await screen.findByText("Este depósito está inativo.")).toBeInTheDocument();
    await waitFor(() => {
      expect(screen.queryByRole("option", { name: "Pátio" })).not.toBeInTheDocument();
    });
  });

  it("says there is no warehouse to receive into, and points to where one is registered", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /warehouses": () => listResponse([{ id: 6, name: "Pátio", active: false }]),
        "GET /purchase_orders/9": () => jsonResponse({ data: receivableOrder() }),
      }),
    );

    renderAt();

    expect(await screen.findByText(/Nenhum depósito ativo/)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Cadastrar depósito" })).toHaveAttribute(
      "href",
      "/estoque/depositos",
    );
    expect(screen.queryByRole("button", { name: "Revisar recebimento" })).not.toBeInTheDocument();
  });

  it("does not ask the API for an address that is not an order number", async () => {
    renderAt("/compras/x/receber");

    expect(await screen.findByText("Este pedido não foi encontrado.")).toBeInTheDocument();
    expect(fetch).not.toHaveBeenCalled();
    expect(screen.queryByLabelText("Depósito")).not.toBeInTheDocument();
  });
});

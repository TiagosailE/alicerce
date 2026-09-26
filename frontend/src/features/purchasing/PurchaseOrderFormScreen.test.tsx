import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, render, screen, waitFor, within } from "@testing-library/react";
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
import { nth } from "../../test/dom";
import { EditPurchaseOrderScreen, NewPurchaseOrderScreen } from "./PurchaseOrderFormScreen";
import { order, orderLine } from "./testData";

const unit = { id: 1, code: "SC", name: "Saco", active: true };

function supplier(overrides: Record<string, unknown> = {}) {
  return {
    id: 3,
    name: "Cimentos Bahia",
    document_type: "cnpj",
    document_number: "NXKE3INSKJRI36",
    customer: false,
    supplier: true,
    active: true,
    ...overrides,
  };
}

function product(overrides: Record<string, unknown> = {}) {
  return {
    id: 7,
    sku: "CIM-001",
    name: "Cimento CP II",
    active: true,
    revision: 0,
    category: null,
    stock_unit: { id: 2, code: "UN", name: "Unidade", active: true },
    unit_conversion: { purchase_unit: unit, factor: "1.000000" },
    ...overrides,
  };
}

const productRequests: URL[] = [];

/** Like the API: with active=true the inactive products are left out. */
const pickers = {
  "GET /partners": () => listResponse([supplier(), supplier({ id: 4, name: "Tintas Rio" })]),
  "GET /products": (request: Request) => {
    const url = new URL(request.url);
    productRequests.push(url);
    const all = [
      product(),
      product({ id: 8, sku: "OLD-001", name: "Produto antigo", active: false }),
    ];
    return listResponse(url.searchParams.get("active") === "true" ? all.slice(0, 1) : all);
  },
};

/** Where a saved draft lands, showing what the save handed to the page. */
function OrderPage() {
  const location = useLocation();
  return (
    <div>
      <h1>Detalhe do pedido</h1>
      <output aria-label="estado">{JSON.stringify(location.state)}</output>
    </div>
  );
}

function renderAt(path: string) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[path]}>
        <Routes>
          <Route path="/compras/novo" element={<NewPurchaseOrderScreen />} />
          <Route path="/compras/:id/editar" element={<EditPurchaseOrderScreen />} />
          <Route path="/compras/:id" element={<OrderPage />} />
          <Route path="/compras" element={<h1>Lista de pedidos</h1>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
  return queryClient;
}

/** The options arrive after the select is on screen, so wait for the one wanted. */
async function chooseSupplier(user: ReturnType<typeof userEvent.setup>, name = "Cimentos Bahia") {
  await screen.findByRole("option", { name });
  await user.selectOptions(screen.getByLabelText("Fornecedor"), name);
}

async function fillFirstLine(
  user: ReturnType<typeof userEvent.setup>,
  values: { quantity: string; price: string; discount?: string },
) {
  await screen.findByRole("option", { name: "Cimento CP II (CIM-001)" });
  await user.selectOptions(screen.getByLabelText("Produto"), "7");
  await user.type(screen.getByLabelText("Quantidade (SC)"), values.quantity);
  await user.type(screen.getByLabelText("Preço por SC (R$)"), values.price);
  if (values.discount) await user.type(screen.getByLabelText("Desconto (%)"), values.discount);
}

describe("NewPurchaseOrderScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
    productRequests.length = 0;
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("turns what was typed into whole cents, basis points and a decimal quantity, and opens the saved draft", async () => {
    let body: unknown;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...pickers,
        "POST /purchase_orders": async (request) => {
          body = await jsonBody(request);
          return jsonResponse({ data: order() }, 201);
        },
      }),
    );
    const user = userEvent.setup();
    renderAt("/compras/novo");

    await chooseSupplier(user);
    await fillFirstLine(user, { quantity: "200", price: "32,50", discount: "2,5" });
    await user.click(screen.getByRole("button", { name: "Salvar rascunho" }));

    expect(await screen.findByRole("heading", { name: "Detalhe do pedido" })).toBeInTheDocument();
    expect(body).toEqual({
      supplier_id: 3,
      installments: 1,
      first_due_days: 30,
      interval_days: 30,
      lines: [{ product_id: 7, quantity: "200", unit_price_cents: 3250, discount_bp: 250 }],
    });
  });

  it("never shows a total: the amounts are worked out by the system when the draft is saved", async () => {
    vi.stubGlobal("fetch", createFetchMock(pickers));
    const user = userEvent.setup();
    renderAt("/compras/novo");

    await fillFirstLine(user, { quantity: "200", price: "32,50", discount: "2" });

    expect(
      screen.getByText("Os totais são calculados pelo sistema quando o pedido é salvo."),
    ).toBeInTheDocument();
    expect(screen.queryByText(/6\.370/)).not.toBeInTheDocument();
  });

  it("names what is wrong next to each field before sending anything", async () => {
    const fetchMock = createFetchMock(pickers);
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();
    renderAt("/compras/novo");
    await screen.findByLabelText("Fornecedor");

    await user.click(screen.getByRole("button", { name: "Salvar rascunho" }));

    expect(screen.getByText("Escolha um fornecedor.")).toBeInTheDocument();
    expect(screen.getByText("Escolha um produto.")).toBeInTheDocument();
    expect(screen.getByText("Informe a quantidade com números.")).toBeInTheDocument();
    expect(
      screen.getByText("Informe o preço em reais, com no máximo 2 casas decimais."),
    ).toBeInTheDocument();
    expect(fetchMock.mock.calls.some(([input]) => (input as Request).method === "POST")).toBe(
      false,
    );
  });

  it("refuses a price with a fraction of a cent, and a discount with more than two places", async () => {
    vi.stubGlobal("fetch", createFetchMock(pickers));
    const user = userEvent.setup();
    renderAt("/compras/novo");
    await chooseSupplier(user);

    await fillFirstLine(user, { quantity: "1", price: "0,8499", discount: "0,001" });
    await user.click(screen.getByRole("button", { name: "Salvar rascunho" }));

    expect(
      screen.getByText("Informe o preço em reais, com no máximo 2 casas decimais."),
    ).toBeInTheDocument();
    expect(
      screen.getByText("Informe o desconto em porcentagem, com no máximo 2 casas decimais."),
    ).toBeInTheDocument();
  });

  it("puts the API's field errors next to the field they are about, by line", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...pickers,
        "POST /purchase_orders": () =>
          errorEnvelope("validation_failed", "x", {
            fields: {
              supplier_id: ["inactive"],
              "lines.0.quantity": ["too_many_decimals"],
              "lines.1.product_id": ["conversion_missing"],
            },
          }),
      }),
    );
    const user = userEvent.setup();
    renderAt("/compras/novo");
    await chooseSupplier(user);
    await fillFirstLine(user, { quantity: "1", price: "1" });
    await user.click(screen.getByRole("button", { name: "Adicionar item" }));
    const second = nth(screen.getAllByRole("listitem"), 1);
    await user.selectOptions(within(second).getByLabelText("Produto"), "7");
    await user.type(within(second).getByLabelText("Quantidade (SC)"), "1");
    await user.type(within(second).getByLabelText("Preço por SC (R$)"), "1");
    await user.click(screen.getByRole("button", { name: "Salvar rascunho" }));

    expect(await screen.findByText("Este fornecedor está inativo.")).toBeInTheDocument();
    expect(screen.getByText("Use no máximo 3 casas decimais.")).toBeInTheDocument();
    expect(
      screen.getByText("Este produto não tem unidade de compra cadastrada."),
    ).toBeInTheDocument();
    expect(
      screen.queryByText("Não foi possível salvar o pedido. Tente novamente."),
    ).not.toBeInTheDocument();
  });

  it("asks the server for active products only, so an inactive one takes no slot and is not counted", async () => {
    vi.stubGlobal("fetch", createFetchMock(pickers));
    renderAt("/compras/novo");

    const select = await screen.findByLabelText("Produto");
    await screen.findByRole("option", { name: "Cimento CP II (CIM-001)" });

    expect(
      within(select).queryByRole("option", { name: /Produto antigo/ }),
    ).not.toBeInTheDocument();
    expect(productRequests.every((url) => url.searchParams.get("active") === "true")).toBe(true);
  });

  it("hands the saved draft's page a note that it was saved", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...pickers,
        "POST /purchase_orders": () => jsonResponse({ data: order() }, 201),
      }),
    );
    const user = userEvent.setup();
    renderAt("/compras/novo");
    await chooseSupplier(user);
    await fillFirstLine(user, { quantity: "1", price: "1" });

    await user.click(screen.getByRole("button", { name: "Salvar rascunho" }));

    expect(await screen.findByLabelText("estado")).toHaveTextContent('{"saved":true}');
  });

  it("says which fields are required, and marks them for a screen reader", async () => {
    vi.stubGlobal("fetch", createFetchMock(pickers));
    renderAt("/compras/novo");
    await screen.findByLabelText("Fornecedor");

    expect(
      screen.getByText("Todos os campos são obrigatórios, exceto a observação e o desconto."),
    ).toBeInTheDocument();
    expect(screen.getByLabelText("Fornecedor")).toHaveAttribute("aria-required", "true");
    expect(screen.getByLabelText("Produto")).toHaveAttribute("aria-required", "true");
    expect(screen.getByLabelText("Parcelas")).toHaveAttribute("aria-required", "true");
    expect(screen.getByLabelText("Desconto (%)")).not.toHaveAttribute("aria-required");
  });

  it("puts each line in a named group, so a repeated field says which item it belongs to", async () => {
    vi.stubGlobal("fetch", createFetchMock(pickers));
    const user = userEvent.setup();
    renderAt("/compras/novo");
    await screen.findByLabelText("Fornecedor");
    await user.click(screen.getByRole("button", { name: "Adicionar item" }));

    const first = screen.getByRole("group", { name: "Item 1" });
    const second = screen.getByRole("group", { name: "Item 2" });

    expect(within(first).getByLabelText("Preço unitário (R$)")).toBeInTheDocument();
    expect(within(second).getByLabelText("Preço unitário (R$)")).toBeInTheDocument();
    expect(screen.getByRole("heading", { level: 2, name: "Item 2" })).toBeInTheDocument();
  });

  it("lands on the first field to fix after a failed save, with one alert instead of one per field", async () => {
    vi.stubGlobal("fetch", createFetchMock(pickers));
    const user = userEvent.setup();
    renderAt("/compras/novo");
    await screen.findByLabelText("Fornecedor");

    await user.click(screen.getByRole("button", { name: "Salvar rascunho" }));

    expect(screen.getByLabelText("Fornecedor")).toHaveFocus();
    const alerts = screen.getAllByRole("alert");
    expect(alerts).toHaveLength(1);
    expect(alerts[0]).toHaveTextContent("4 campos precisam de correção antes de salvar.");
    expect(screen.getByLabelText("Fornecedor")).toHaveAccessibleDescription(
      /Escolha um fornecedor\./,
    );
  });

  it("lands on the field the API refused, and clears its message once the field is edited", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...pickers,
        "POST /purchase_orders": () =>
          errorEnvelope("validation_failed", "x", {
            fields: { "lines.0.quantity": ["too_many_decimals"] },
          }),
      }),
    );
    const user = userEvent.setup();
    renderAt("/compras/novo");
    await chooseSupplier(user);
    await fillFirstLine(user, { quantity: "1", price: "1" });

    await user.click(screen.getByRole("button", { name: "Salvar rascunho" }));

    expect(await screen.findByText("Use no máximo 3 casas decimais.")).toBeInTheDocument();
    await waitFor(() => {
      expect(screen.getByLabelText("Quantidade (SC)")).toHaveFocus();
    });
    expect(screen.getByRole("alert")).toHaveTextContent(
      "1 campo precisa de correção antes de salvar.",
    );

    await user.type(screen.getByLabelText("Quantidade (SC)"), "2");

    expect(screen.queryByText("Use no máximo 3 casas decimais.")).not.toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("clears only the error of the field that was edited, not the others", async () => {
    vi.stubGlobal("fetch", createFetchMock(pickers));
    const user = userEvent.setup();
    renderAt("/compras/novo");
    await screen.findByLabelText("Fornecedor");
    await user.click(screen.getByRole("button", { name: "Salvar rascunho" }));
    expect(screen.getByText("Informe a quantidade com números.")).toBeInTheDocument();

    await user.type(screen.getByLabelText("Quantidade"), "5");

    expect(screen.queryByText("Informe a quantidade com números.")).not.toBeInTheDocument();
    expect(screen.getByText("Escolha um fornecedor.")).toBeInTheDocument();
    expect(screen.getByText("Escolha um produto.")).toBeInTheDocument();
    expect(screen.getByRole("alert")).toHaveTextContent(
      "3 campos precisam de correção antes de salvar.",
    );
  });

  it("drops the API's line errors when a line is removed, since the numbers move up", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...pickers,
        "POST /purchase_orders": () =>
          errorEnvelope("validation_failed", "x", {
            fields: { "lines.1.quantity": ["too_many_decimals"] },
          }),
      }),
    );
    const user = userEvent.setup();
    renderAt("/compras/novo");
    await chooseSupplier(user);
    await fillFirstLine(user, { quantity: "1", price: "1" });
    await user.click(screen.getByRole("button", { name: "Adicionar item" }));
    const second = screen.getByRole("group", { name: "Item 2" });
    await user.selectOptions(within(second).getByLabelText("Produto"), "7");
    await user.type(within(second).getByLabelText("Quantidade (SC)"), "1");
    await user.type(within(second).getByLabelText("Preço por SC (R$)"), "1");
    await user.click(screen.getByRole("button", { name: "Salvar rascunho" }));
    expect(await screen.findByText("Use no máximo 3 casas decimais.")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Remover item 1" }));

    expect(screen.queryByText("Use no máximo 3 casas decimais.")).not.toBeInTheDocument();
  });

  it("does not submit the form when Enter is pressed in a search box", async () => {
    const fetchMock = createFetchMock(pickers);
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();
    renderAt("/compras/novo");
    await screen.findByLabelText("Fornecedor");

    await user.type(screen.getByLabelText("Buscar produto"), "cim{Enter}");
    await user.type(screen.getByLabelText("Buscar fornecedor"), "bah{Enter}");

    expect(screen.queryByText("Escolha um fornecedor.")).not.toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
    expect(screen.getByLabelText("Buscar produto")).toHaveValue("cim");
  });

  it("moves focus to the new line when one is added, and to the add button when one is removed", async () => {
    vi.stubGlobal("fetch", createFetchMock(pickers));
    const user = userEvent.setup();
    renderAt("/compras/novo");
    await screen.findByLabelText("Fornecedor");

    await user.click(screen.getByRole("button", { name: "Adicionar item" }));
    const second = screen.getByRole("group", { name: "Item 2" });
    expect(within(second).getByLabelText("Buscar produto")).toHaveFocus();

    await user.click(screen.getByRole("button", { name: "Remover item 2" }));
    expect(screen.getByRole("button", { name: "Adicionar item" })).toHaveFocus();
  });

  it("adds and removes lines, and keeps at least one", async () => {
    vi.stubGlobal("fetch", createFetchMock(pickers));
    const user = userEvent.setup();
    renderAt("/compras/novo");
    await screen.findByLabelText("Fornecedor");
    expect(screen.queryByRole("button", { name: /Remover item/ })).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Adicionar item" }));
    expect(screen.getAllByRole("listitem")).toHaveLength(2);
    await user.click(screen.getByRole("button", { name: "Remover item 1" }));

    expect(screen.getAllByRole("listitem")).toHaveLength(1);
    expect(screen.queryByRole("button", { name: /Remover item/ })).not.toBeInTheDocument();
  });

  it("says when too many attempts were made", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...pickers,
        "POST /purchase_orders": () => errorEnvelope("rate_limited", "x", {}, 429),
      }),
    );
    const user = userEvent.setup();
    renderAt("/compras/novo");
    await chooseSupplier(user);
    await fillFirstLine(user, { quantity: "1", price: "1" });

    await user.click(screen.getByRole("button", { name: "Salvar rascunho" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Muitas tentativas seguidas");
  });
});

describe("EditPurchaseOrderScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("pre-fills the draft in the units a person types, and saves from the revision it read", async () => {
    let body: unknown;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...pickers,
        "GET /purchase_orders/9": () =>
          jsonResponse({ data: order({ revision: 5, lines: [orderLine({ discount_bp: 250 })] }) }),
        "PATCH /purchase_orders/9": async (request) => {
          body = await jsonBody(request);
          return jsonResponse({ data: order({ revision: 6 }) });
        },
      }),
    );
    const user = userEvent.setup();
    renderAt("/compras/9/editar");

    expect(
      await screen.findByRole("heading", { name: "Editar o rascunho do pedido nº 4" }),
    ).toBeInTheDocument();
    expect(screen.getByLabelText("Quantidade (SC)")).toHaveValue("200");
    expect(screen.getByLabelText("Preço por SC (R$)")).toHaveValue("32,50");
    expect(screen.getByLabelText("Desconto (%)")).toHaveValue("2,5");
    expect(screen.getByLabelText("Parcelas")).toHaveValue("2");
    expect(screen.getByLabelText("Observação")).toHaveValue("Entrega na segunda");

    await user.clear(screen.getByLabelText("Quantidade (SC)"));
    await user.type(screen.getByLabelText("Quantidade (SC)"), "150,5");
    await user.click(screen.getByRole("button", { name: "Salvar rascunho" }));

    expect(await screen.findByRole("heading", { name: "Detalhe do pedido" })).toBeInTheDocument();
    expect(body).toEqual({
      supplier_id: 3,
      installments: 2,
      first_due_days: 30,
      interval_days: 30,
      note: "Entrega na segunda",
      lines: [{ product_id: 7, quantity: "150.5", unit_price_cents: 3250, discount_bp: 250 }],
      revision: 5,
    });
  });

  it("answers a stale save by saying so, and reloads what is stored on request", async () => {
    let reads = 0;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...pickers,
        "GET /purchase_orders/9": () => {
          reads += 1;
          return jsonResponse({
            data: order({ revision: reads, note: reads === 1 ? "Antiga" : "Nova" }),
          });
        },
        "PATCH /purchase_orders/9": () => errorEnvelope("stale", "x", { current_revision: 2 }, 409),
      }),
    );
    const user = userEvent.setup();
    renderAt("/compras/9/editar");
    await screen.findByDisplayValue("Antiga");

    await user.click(screen.getByRole("button", { name: "Salvar rascunho" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Outra pessoa alterou este rascunho",
    );
    await user.click(screen.getByRole("button", { name: "Recarregar" }));

    expect(await screen.findByDisplayValue("Nova")).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("does not open an order that is no longer a draft", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...pickers,
        "GET /purchase_orders/9": () => jsonResponse({ data: order({ status: "approved" }) }),
      }),
    );
    renderAt("/compras/9/editar");

    expect(await screen.findByRole("alert")).toHaveTextContent("Só um rascunho pode ser editado.");
    expect(screen.queryByRole("button", { name: "Salvar rascunho" })).not.toBeInTheDocument();
  });

  it("saves from the revision the form was opened at, not from one fetched while it was open", async () => {
    let reads = 0;
    let body: { revision?: number } = {};
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...pickers,
        "GET /purchase_orders/9": () => {
          reads += 1;
          return jsonResponse({
            data: order({
              revision: reads === 1 ? 5 : 6,
              note: reads === 1 ? "Minha versão" : "De outra pessoa",
            }),
          });
        },
        "PATCH /purchase_orders/9": async (request) => {
          body = (await jsonBody(request)) as { revision?: number };
          return errorEnvelope("stale", "x", { current_revision: 6 }, 409);
        },
      }),
    );
    const user = userEvent.setup();
    const queryClient = renderAt("/compras/9/editar");
    await screen.findByDisplayValue("Minha versão");

    await act(async () => {
      await queryClient.refetchQueries({ queryKey: ["purchasing", "orders", "detail", 9] });
    });
    expect(screen.getByDisplayValue("Minha versão")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Salvar rascunho" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Outra pessoa alterou este rascunho",
    );
    expect(body.revision).toBe(5);
  });

  it("links back to the order it is editing, by its number, and hands the saved page a note", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...pickers,
        "GET /purchase_orders/9": () => jsonResponse({ data: order() }),
        "PATCH /purchase_orders/9": () => jsonResponse({ data: order({ revision: 1 }) }),
      }),
    );
    const user = userEvent.setup();
    renderAt("/compras/9/editar");

    expect(await screen.findByRole("link", { name: "Voltar ao pedido nº 4" })).toHaveAttribute(
      "href",
      "/compras/9",
    );
    await user.click(screen.getByRole("button", { name: "Salvar rascunho" }));

    expect(await screen.findByLabelText("estado")).toHaveTextContent('{"saved":true}');
  });

  it("does not ask the API for an address that is not an order number", async () => {
    renderAt("/compras/x/editar");

    expect(await screen.findByText("Este pedido não foi encontrado.")).toBeInTheDocument();
    expect(fetch).not.toHaveBeenCalled();
  });
});

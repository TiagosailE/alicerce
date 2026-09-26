import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Category, Product, Unit } from "./api";
import { ProductsScreen } from "./ProductsScreen";

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function errorEnvelope(code: string, message: string, details: Record<string, unknown> = {}) {
  return jsonResponse({ error: { code, message, details, request_id: "req-1" } }, 422);
}

function listResponse(
  data: unknown[],
  meta: Partial<{ page: number; per_page: number; total: number }> = {},
) {
  return jsonResponse({
    data,
    meta: { page: 1, per_page: 25, total: data.length, ...meta },
  });
}

function found<T>(element: T | null | undefined): T {
  if (element === null || element === undefined) throw new Error("expected element to exist");
  return element;
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

function unit(overrides: Partial<Unit> = {}): Unit {
  return { id: 1, code: "UN", name: "Unidade", active: true, ...overrides };
}

function category(overrides: Partial<Category> = {}): Category {
  return { id: 1, name: "Cimento e argamassa", active: true, ...overrides };
}

function product(overrides: Partial<Product> = {}): Product {
  return {
    id: 1,
    sku: "TIJ-001",
    name: "Tijolo comum",
    active: true,
    revision: 3,
    category: category(),
    stock_unit: unit(),
    unit_conversion: {
      purchase_unit: unit({ id: 2, code: "MIL", name: "Milheiro" }),
      factor: "1000.000000",
    },
    ...overrides,
  };
}

async function jsonBody(request: Request): Promise<unknown> {
  return request.clone().json();
}

// Scoped because the filter bar has its own "Categoria" select once the
// create form is open, with the identical label.
function createFormCategorySelect() {
  const container = found(screen.getByRole("heading", { name: "Novo produto" }).closest("div"));
  return within(container).getByLabelText("Categoria");
}

function renderScreen(canManage = true) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={["/estoque/produtos"]}>
        <ProductsScreen canManage={canManage} />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

const defaultHandlers = {
  "GET /units": () => listResponse([unit()]),
  "GET /categories": () => listResponse([category()]),
};

describe("ProductsScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("lists products with their category, unit and conversion", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /products": () => listResponse([product()]),
      }),
    );

    renderScreen();

    const row = found(within(await screen.findByRole("table")).getAllByRole("row")[1]);
    expect(within(row).getByText("TIJ-001")).toBeInTheDocument();
    expect(within(row).getByText("Tijolo comum")).toBeInTheDocument();
    expect(within(row).getByText("Cimento e argamassa")).toBeInTheDocument();
    expect(within(row).getByText("UN")).toBeInTheDocument();
    expect(within(row).getByText("1.000 MIL")).toBeInTheDocument();
    expect(within(row).getByText("Ativo")).toBeInTheDocument();
  });

  it("shows the empty state when there are no products", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ ...defaultHandlers, "GET /products": () => listResponse([]) }),
    );

    renderScreen();

    expect(await screen.findByText("Nenhum produto encontrado.")).toBeInTheDocument();
  });

  it("retries loading products after a failed request", async () => {
    let attempt = 0;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /products": () => {
          attempt += 1;
          return attempt === 1
            ? errorEnvelope("forbidden", "not allowed")
            : listResponse([product()]);
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Não foi possível carregar os produtos.");
    expect(alert).toHaveTextContent("ID da requisição: req-1");

    await user.click(screen.getByRole("button", { name: "Tentar novamente" }));

    expect(await screen.findByText("TIJ-001")).toBeInTheDocument();
  });

  it("does not offer creating a product to a role without manage_master_data", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ ...defaultHandlers, "GET /products": () => listResponse([product()]) }),
    );

    renderScreen(false);

    await screen.findByText("TIJ-001");
    expect(screen.queryByRole("button", { name: "Novo produto" })).not.toBeInTheDocument();
  });

  it("filters by category, active state and search", async () => {
    let lastRequestUrl = "";
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /products": (request) => {
          lastRequestUrl = request.url;
          return listResponse([product()]);
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("TIJ-001");
    await user.selectOptions(screen.getByLabelText("Filtrar por categoria"), "1");

    await waitFor(() => {
      expect(new URL(lastRequestUrl).searchParams.get("category_id")).toBe("1");
    });
  });

  it("moves focus into the create form when it opens, and back to the button when it closes", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ ...defaultHandlers, "GET /products": () => listResponse([product()]) }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("TIJ-001");
    await user.click(screen.getByRole("button", { name: "Novo produto" }));

    expect(screen.getByRole("heading", { name: "Novo produto" })).toHaveFocus();

    await user.click(screen.getByRole("button", { name: "Cancelar" }));

    expect(screen.getByRole("button", { name: "Novo produto" })).toHaveFocus();
  });

  it("creates a product with the chosen fields", async () => {
    let requestBody: unknown;
    const post = vi.fn(async (request: Request) => {
      requestBody = await jsonBody(request);
      return jsonResponse({ data: product({ id: 9, sku: "CIM-001", name: "Cimento" }) }, 201);
    });
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /products": () => listResponse([product()]),
        "POST /products": post,
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("TIJ-001");
    await user.click(screen.getByRole("button", { name: "Novo produto" }));
    await user.type(screen.getByLabelText("SKU"), "CIM-001");
    await user.type(screen.getByLabelText("Nome"), "Cimento");
    await user.selectOptions(createFormCategorySelect(), "Cimento e argamassa");
    await user.selectOptions(screen.getByLabelText("Unidade de estoque"), "Unidade (UN)");
    await user.selectOptions(screen.getByLabelText("Unidade de compra"), "Unidade (UN)");
    const factorInput = screen.getByLabelText("Fator de conversão");
    await user.clear(factorInput);
    await user.type(factorInput, "1");
    await user.click(screen.getByRole("button", { name: "Salvar" }));

    expect(post).toHaveBeenCalledTimes(1);
    expect(requestBody).toMatchObject({
      sku: "CIM-001",
      name: "Cimento",
      category_id: 1,
      stock_unit_id: 1,
      purchase_unit_id: 1,
      factor: "1",
    });
    expect(screen.queryByLabelText("SKU")).not.toBeInTheDocument();
    expect(await screen.findByRole("status")).toHaveTextContent("Produto criado.");
  });

  async function fillCreateFormWithFactor(
    user: ReturnType<typeof userEvent.setup>,
    factor: string,
  ) {
    await screen.findByText("TIJ-001");
    await user.click(screen.getByRole("button", { name: "Novo produto" }));
    await user.type(screen.getByLabelText("SKU"), "CIM-001");
    await user.type(screen.getByLabelText("Nome"), "Cimento");
    await user.selectOptions(screen.getByLabelText("Unidade de estoque"), "Unidade (UN)");
    await user.selectOptions(screen.getByLabelText("Unidade de compra"), "Unidade (UN)");
    const factorInput = screen.getByLabelText("Fator de conversão");
    await user.clear(factorInput);
    await user.type(factorInput, factor);
    await user.click(screen.getByRole("button", { name: "Salvar" }));
  }

  it.each([
    ["1.000", "1000"],
    ["2,5", "2.5"],
  ])(
    "sends a factor typed as %s to the API as %s, the way the list displays it",
    async (typed, sent) => {
      let requestBody: unknown;
      const post = vi.fn(async (request: Request) => {
        requestBody = await jsonBody(request);
        return jsonResponse({ data: product({ id: 9 }) }, 201);
      });
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          ...defaultHandlers,
          "GET /products": () => listResponse([product()]),
          "POST /products": post,
        }),
      );
      const user = userEvent.setup();
      renderScreen();

      await fillCreateFormWithFactor(user, typed);

      expect(post).toHaveBeenCalledTimes(1);
      expect(requestBody).toMatchObject({ factor: sent });
    },
  );

  it("stops a factor it cannot read before calling the API", async () => {
    const post = vi.fn(() => jsonResponse({ data: product({ id: 9 }) }, 201));
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /products": () => listResponse([product()]),
        "POST /products": post,
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await fillCreateFormWithFactor(user, "1,2,3");

    expect(post).not.toHaveBeenCalled();
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Informe um número válido, como 1.000 ou 2,5.",
    );
  });

  it("shows the API's decimal-places error on the factor field", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /products": () => listResponse([product()]),
        "POST /products": () =>
          errorEnvelope("validation_failed", "invalid", {
            fields: { factor: ["too_many_decimals"] },
          }),
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await fillCreateFormWithFactor(user, "1,0000004");

    expect(await screen.findByText("Use no máximo 6 casas decimais.")).toBeInTheDocument();
  });

  it("shows a translated error when creation fails validation", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /products": () => listResponse([product()]),
        "POST /products": () => errorEnvelope("validation_failed", "invalid"),
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("TIJ-001");
    await user.click(screen.getByRole("button", { name: "Novo produto" }));
    await user.type(screen.getByLabelText("SKU"), "X");
    await user.type(screen.getByLabelText("Nome"), "X");
    await user.selectOptions(screen.getByLabelText("Unidade de estoque"), "Unidade (UN)");
    await user.selectOptions(screen.getByLabelText("Unidade de compra"), "Unidade (UN)");
    await user.click(screen.getByRole("button", { name: "Salvar" }));

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Verifique os campos do produto.");
    expect(alert).toHaveTextContent("ID da requisição: req-1");
  });

  it("paginates the product list", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /products": (request) => {
          const page = Number(new URL(request.url).searchParams.get("page") ?? "1");
          const data = page === 1 ? [product()] : [product({ id: 2, sku: "CIM-001" })];
          return listResponse(data, { page, per_page: 1, total: 2 });
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    expect(await screen.findByText("TIJ-001")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Página anterior" })).toBeDisabled();

    await user.click(screen.getByRole("button", { name: "Próxima página" }));

    expect(await screen.findByText("CIM-001")).toBeInTheDocument();
  });

  it("links each row to its detail page", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ ...defaultHandlers, "GET /products": () => listResponse([product()]) }),
    );

    renderScreen();

    const link = await screen.findByRole("link", { name: "TIJ-001" });
    expect(link).toHaveAttribute("href", "/estoque/produtos/1");
  });
});

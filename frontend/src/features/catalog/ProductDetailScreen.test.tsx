import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Category, Product, Unit } from "./api";
import { ProductDetailScreen } from "./ProductDetailScreen";

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

function listResponse(data: unknown[]) {
  return jsonResponse({ data, meta: { page: 1, per_page: 100, total: data.length } });
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
    id: 42,
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

const defaultHandlers = {
  "GET /units": () => listResponse([unit()]),
  "GET /categories": () => listResponse([category()]),
};

function renderScreen(canManage = true) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={["/estoque/produtos/42"]}>
        <Routes>
          <Route
            path="/estoque/produtos/:id"
            element={<ProductDetailScreen canManage={canManage} />}
          />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("ProductDetailScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("shows a load error with a retry, then the product once it succeeds", async () => {
    let attempt = 0;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /products/42": () => {
          attempt += 1;
          return attempt === 1
            ? errorEnvelope("forbidden", "not allowed")
            : jsonResponse({ data: product() });
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Não foi possível carregar o produto.");

    await user.click(screen.getByRole("button", { name: "Tentar novamente" }));

    expect(await screen.findByRole("heading", { name: "Tijolo comum" })).toBeInTheDocument();
  });

  it("pre-fills an editable form for a role that can manage master data", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /products/42": () => jsonResponse({ data: product() }),
      }),
    );

    renderScreen(true);

    expect(await screen.findByLabelText("SKU")).toHaveValue("TIJ-001");
    expect(screen.getByLabelText("Nome")).toHaveValue("Tijolo comum");
    expect(screen.getByLabelText("Fator de conversão")).toHaveValue("1000");
    expect(screen.getByLabelText("Ativo")).toBeChecked();
  });

  it("shows a read-only view for a role that cannot manage master data", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /products/42": () => jsonResponse({ data: product() }),
      }),
    );

    renderScreen(false);

    await screen.findByRole("heading", { name: "Tijolo comum" });
    expect(screen.queryByLabelText("SKU")).not.toBeInTheDocument();
    expect(screen.getByText("TIJ-001")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Salvar alterações" })).not.toBeInTheDocument();
  });

  it("updates the product and its unit conversion together", async () => {
    let requestBody: unknown;
    const patch = vi.fn(async (request: Request) => {
      requestBody = await jsonBody(request);
      return jsonResponse({ data: product({ name: "Tijolo 8 furos" }) });
    });
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /products/42": () => jsonResponse({ data: product() }),
        "PATCH /products/42": patch,
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    const nameInput = await screen.findByLabelText("Nome");
    await user.clear(nameInput);
    await user.type(nameInput, "Tijolo 8 furos");
    await user.click(screen.getByRole("button", { name: "Salvar alterações" }));

    expect(patch).toHaveBeenCalledTimes(1);
    expect(requestBody).toMatchObject({ name: "Tijolo 8 furos", active: true, revision: 3 });
    expect(await screen.findByRole("status")).toHaveTextContent("Produto atualizado.");
  });

  it("does not let the stock unit be edited, and says why", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /products/42": () => jsonResponse({ data: product() }),
      }),
    );

    renderScreen();

    expect(await screen.findByLabelText("Unidade de estoque")).toBeDisabled();
    expect(screen.getByText(/não pode ser alterada/)).toBeInTheDocument();
  });

  it("explains a stale save, then reloads the current values and saves with the new revision", async () => {
    let served = 0;
    const bodies: Record<string, unknown>[] = [];
    const patch = vi.fn(async (request: Request) => {
      bodies.push((await jsonBody(request)) as Record<string, unknown>);
      return bodies.length === 1
        ? errorEnvelope("stale", "Stale", { current_revision: 4 }, 409)
        : jsonResponse({ data: product({ name: "Editado por mim", revision: 5 }) });
    });
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        ...defaultHandlers,
        "GET /products/42": () => {
          served += 1;
          return jsonResponse({
            data:
              served === 1 ? product() : product({ name: "Editado por outra pessoa", revision: 4 }),
          });
        },
        "PATCH /products/42": patch,
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    const nameInput = await screen.findByLabelText("Nome");
    await user.clear(nameInput);
    await user.type(nameInput, "Editado por mim");
    await user.click(screen.getByRole("button", { name: "Salvar alterações" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(/alterado por outra pessoa/);
    await user.click(screen.getByRole("button", { name: "Recarregar" }));

    await waitFor(() => {
      expect(screen.getByLabelText("Nome")).toHaveValue("Editado por outra pessoa");
    });
    expect(screen.queryByRole("button", { name: "Recarregar" })).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Salvar alterações" }));

    await waitFor(() => {
      expect(patch).toHaveBeenCalledTimes(2);
    });
    expect(bodies.map((body) => body.revision)).toEqual([3, 4]);
  });
});

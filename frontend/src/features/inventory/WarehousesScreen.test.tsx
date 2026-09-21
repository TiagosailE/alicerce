import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Warehouse } from "./api";
import { WarehousesScreen } from "./WarehousesScreen";

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

function warehouse(overrides: Partial<Warehouse> = {}): Warehouse {
  return { id: 1, name: "Loja", active: true, ...overrides };
}

function found<T>(element: T | null | undefined): T {
  if (element === null || element === undefined) throw new Error("expected element to exist");
  return element;
}

async function jsonBody(request: Request): Promise<unknown> {
  return request.clone().json();
}

function renderScreen(canManage = true) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={["/estoque/depositos"]}>
        <WarehousesScreen canManage={canManage} />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("WarehousesScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("lists warehouses with their status", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /warehouses": () => listResponse([warehouse()]) }),
    );

    renderScreen();

    const row = found(within(await screen.findByRole("table")).getAllByRole("row")[1]);
    expect(within(row).getByText("Loja")).toBeInTheDocument();
    expect(within(row).getByText("Ativo")).toBeInTheDocument();
  });

  it("shows the empty state when there are no warehouses", async () => {
    vi.stubGlobal("fetch", createFetchMock({ "GET /warehouses": () => listResponse([]) }));

    renderScreen();

    expect(await screen.findByText("Nenhum depósito encontrado.")).toBeInTheDocument();
  });

  it("retries loading warehouses after a failed request", async () => {
    let attempt = 0;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /warehouses": () => {
          attempt += 1;
          return attempt === 1
            ? errorEnvelope("forbidden", "not allowed")
            : listResponse([warehouse()]);
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Não foi possível carregar os depósitos.");
    expect(alert).toHaveTextContent("ID da requisição: req-1");

    await user.click(screen.getByRole("button", { name: "Tentar novamente" }));

    expect(await screen.findByText("Loja")).toBeInTheDocument();
  });

  it("does not offer creating or editing a warehouse to a role without manage_master_data", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /warehouses": () => listResponse([warehouse()]) }),
    );

    renderScreen(false);

    await screen.findByText("Loja");
    expect(screen.queryByRole("button", { name: "Novo depósito" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Editar Loja" })).not.toBeInTheDocument();
  });

  it("moves focus into the create form when it opens, and back to the button when it closes", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /warehouses": () => listResponse([warehouse()]) }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Loja");
    await user.click(screen.getByRole("button", { name: "Novo depósito" }));

    expect(screen.getByRole("heading", { name: "Novo depósito" })).toHaveFocus();

    await user.click(screen.getByRole("button", { name: "Cancelar" }));

    expect(screen.getByRole("button", { name: "Novo depósito" })).toHaveFocus();
  });

  it("creates a warehouse with the chosen name", async () => {
    let requestBody: unknown;
    const post = vi.fn(async (request: Request) => {
      requestBody = await jsonBody(request);
      return jsonResponse({ data: warehouse({ id: 9, name: "Pátio" }) }, 201);
    });
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /warehouses": () => listResponse([warehouse()]),
        "POST /warehouses": post,
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Loja");
    await user.click(screen.getByRole("button", { name: "Novo depósito" }));
    await user.type(screen.getByLabelText("Nome"), "Pátio");
    await user.click(screen.getByRole("button", { name: "Salvar" }));

    expect(post).toHaveBeenCalledTimes(1);
    expect(requestBody).toMatchObject({ name: "Pátio" });
    expect(screen.queryByRole("heading", { name: "Novo depósito" })).not.toBeInTheDocument();
    expect(await screen.findByRole("status")).toHaveTextContent("Depósito criado.");
  });

  it("shows a translated error when creation fails validation", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /warehouses": () => listResponse([warehouse()]),
        "POST /warehouses": () =>
          errorEnvelope("validation_failed", "invalid", { fields: { name: ["taken"] } }),
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Loja");
    await user.click(screen.getByRole("button", { name: "Novo depósito" }));
    await user.type(screen.getByLabelText("Nome"), "Loja");
    await user.click(screen.getByRole("button", { name: "Salvar" }));

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Já existe um depósito com esse nome.");
  });

  it("edits a warehouse's name and active state inline", async () => {
    let requestBody: unknown;
    const patch = vi.fn(async (request: Request) => {
      requestBody = await jsonBody(request);
      return jsonResponse({ data: warehouse({ name: "Loja centro", active: false }) });
    });
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /warehouses": () => listResponse([warehouse()]),
        "PATCH /warehouses/1": patch,
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Loja");
    await user.click(screen.getByRole("button", { name: "Editar Loja" }));

    const nameInput = screen.getByLabelText("Nome");
    await user.clear(nameInput);
    await user.type(nameInput, "Loja centro");
    await user.click(screen.getByLabelText("Ativo"));
    await user.click(screen.getByRole("button", { name: "Salvar" }));

    expect(patch).toHaveBeenCalledTimes(1);
    expect(requestBody).toMatchObject({ name: "Loja centro", active: false });
    await waitFor(() => {
      expect(screen.queryByLabelText("Nome")).not.toBeInTheDocument();
    });
    expect(await screen.findByRole("status")).toHaveTextContent("Depósito atualizado.");
  });

  it("cancels an inline edit without saving, returning focus to the edit button", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /warehouses": () => listResponse([warehouse()]) }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Loja");
    await user.click(screen.getByRole("button", { name: "Editar Loja" }));
    await user.click(screen.getByRole("button", { name: "Cancelar" }));

    expect(screen.queryByLabelText("Nome")).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Editar Loja" })).toHaveFocus();
  });

  it("disables editing other rows while a row's save is in flight", async () => {
    let resolvePatch: (value: Response) => void = () => {
      throw new Error("resolvePatch called before assignment");
    };
    const patchPromise = new Promise<Response>((resolve) => {
      resolvePatch = resolve;
    });
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /warehouses": () => listResponse([warehouse(), warehouse({ id: 2, name: "Pátio" })]),
        "PATCH /warehouses/1": () => patchPromise,
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Loja");
    await user.click(screen.getByRole("button", { name: "Editar Loja" }));
    await user.click(screen.getByRole("button", { name: "Salvar" }));

    expect(screen.getByRole("button", { name: "Editar Pátio" })).toBeDisabled();

    resolvePatch(jsonResponse({ data: warehouse() }));
    await waitFor(() => {
      expect(screen.getByRole("button", { name: "Editar Pátio" })).not.toBeDisabled();
    });
  });

  it("closes the create form when a row edit starts, and closes a row edit when the create form opens", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /warehouses": () => listResponse([warehouse()]) }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Loja");
    await user.click(screen.getByRole("button", { name: "Novo depósito" }));
    expect(screen.getByRole("heading", { name: "Novo depósito" })).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Editar Loja" }));
    expect(screen.queryByRole("heading", { name: "Novo depósito" })).not.toBeInTheDocument();
    expect(screen.getByLabelText("Nome")).toHaveFocus();

    await user.click(screen.getByRole("button", { name: "Novo depósito" }));
    expect(screen.queryByLabelText("Ativo")).not.toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Novo depósito" })).toHaveFocus();
  });

  it("paginates the warehouse list", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /warehouses": (request) => {
          const page = Number(new URL(request.url).searchParams.get("page") ?? "1");
          const data = page === 1 ? [warehouse()] : [warehouse({ id: 2, name: "Pátio" })];
          return listResponse(data, { page, per_page: 1, total: 2 });
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    expect(await screen.findByText("Loja")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Página anterior" })).toBeDisabled();

    await user.click(screen.getByRole("button", { name: "Próxima página" }));

    expect(await screen.findByText("Pátio")).toBeInTheDocument();
  });
});

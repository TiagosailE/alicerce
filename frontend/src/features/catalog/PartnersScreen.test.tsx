import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { PartnerSummary } from "./api";
import { PartnersScreen } from "./PartnersScreen";

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

// Scoped because the filter bar has its own "Cliente"/"Fornecedor" selects
// once the create form is open, with the identical visible label (same
// reasoning as the products screen's category filter).
function createFormField(name: string) {
  const container = found(screen.getByRole("heading", { name: "Novo parceiro" }).closest("div"));
  return within(container).getByLabelText(name);
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

function partner(overrides: Partial<PartnerSummary> = {}): PartnerSummary {
  return {
    id: 1,
    name: "Marcos Pereira",
    document_type: "cpf",
    document_number: "52998224725",
    customer: true,
    supplier: false,
    active: true,
    ...overrides,
  };
}

async function jsonBody(request: Request): Promise<unknown> {
  return request.clone().json();
}

function renderScreen(canManage = true) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={["/parceiros"]}>
        <PartnersScreen canManage={canManage} />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("PartnersScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("lists partners with their document and kind", async () => {
    vi.stubGlobal("fetch", createFetchMock({ "GET /partners": () => listResponse([partner()]) }));

    renderScreen();

    const row = found(within(await screen.findByRole("table")).getAllByRole("row")[1]);
    expect(within(row).getByText("Marcos Pereira")).toBeInTheDocument();
    expect(within(row).getByText("CPF: 52998224725")).toBeInTheDocument();
    expect(within(row).getByText("Cliente")).toBeInTheDocument();
    expect(within(row).getByText("Ativo")).toBeInTheDocument();
  });

  it("shows the empty state when there are no partners", async () => {
    vi.stubGlobal("fetch", createFetchMock({ "GET /partners": () => listResponse([]) }));

    renderScreen();

    expect(await screen.findByText("Nenhum parceiro encontrado.")).toBeInTheDocument();
  });

  it("retries loading partners after a failed request", async () => {
    let attempt = 0;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /partners": () => {
          attempt += 1;
          return attempt === 1
            ? errorEnvelope("forbidden", "not allowed")
            : listResponse([partner()]);
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Não foi possível carregar os parceiros.");
    expect(alert).toHaveTextContent("ID da requisição: req-1");

    await user.click(screen.getByRole("button", { name: "Tentar novamente" }));

    expect(await screen.findByText("Marcos Pereira")).toBeInTheDocument();
  });

  it("does not offer creating a partner to a role without manage_master_data", async () => {
    vi.stubGlobal("fetch", createFetchMock({ "GET /partners": () => listResponse([partner()]) }));

    renderScreen(false);

    await screen.findByText("Marcos Pereira");
    expect(screen.queryByRole("button", { name: "Novo parceiro" })).not.toBeInTheDocument();
  });

  it("filters by customer, supplier, active state and search", async () => {
    let lastRequestUrl = "";
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /partners": (request) => {
          lastRequestUrl = request.url;
          return listResponse([partner()]);
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Marcos Pereira");
    await user.selectOptions(screen.getByLabelText("Filtrar por fornecedor"), "true");

    await waitFor(() => {
      expect(new URL(lastRequestUrl).searchParams.get("supplier")).toBe("true");
    });
  });

  it("moves focus into the create form when it opens, and back to the button when it closes", async () => {
    vi.stubGlobal("fetch", createFetchMock({ "GET /partners": () => listResponse([partner()]) }));
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Marcos Pereira");
    await user.click(screen.getByRole("button", { name: "Novo parceiro" }));

    expect(screen.getByRole("heading", { name: "Novo parceiro" })).toHaveFocus();

    await user.click(screen.getByRole("button", { name: "Cancelar" }));

    expect(screen.getByRole("button", { name: "Novo parceiro" })).toHaveFocus();
  });

  it("creates a partner with the chosen fields", async () => {
    let requestBody: unknown;
    const post = vi.fn(async (request: Request) => {
      requestBody = await jsonBody(request);
      return jsonResponse({ data: partner({ id: 9, name: "Fornecedor Novo" }) }, 201);
    });
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /partners": () => listResponse([partner()]), "POST /partners": post }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Marcos Pereira");
    await user.click(screen.getByRole("button", { name: "Novo parceiro" }));
    await user.type(screen.getByLabelText("Nome"), "Fornecedor Novo");
    await user.selectOptions(screen.getByLabelText("Tipo de documento"), "CNPJ");
    await user.type(screen.getByLabelText("Número do documento"), "11222333000181");
    await user.click(createFormField("Fornecedor"));
    await user.click(screen.getByRole("button", { name: "Salvar" }));

    expect(post).toHaveBeenCalledTimes(1);
    expect(requestBody).toMatchObject({
      name: "Fornecedor Novo",
      document_type: "cnpj",
      document_number: "11222333000181",
      customer: false,
      supplier: true,
    });
    expect(screen.queryByLabelText("Nome")).not.toBeInTheDocument();
    expect(await screen.findByRole("status")).toHaveTextContent("Parceiro criado.");
  });

  it("groups the customer/supplier checkboxes under one accessible name", async () => {
    vi.stubGlobal("fetch", createFetchMock({ "GET /partners": () => listResponse([partner()]) }));
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Marcos Pereira");
    await user.click(screen.getByRole("button", { name: "Novo parceiro" }));

    const group = screen.getByRole("group", { name: "Relação" });
    expect(within(group).getByLabelText("Cliente")).toBeInTheDocument();
    expect(within(group).getByLabelText("Fornecedor")).toBeInTheDocument();
  });

  it("rejects an invalid email client-side without submitting, then accepts the fix", async () => {
    const post = vi.fn(() => jsonResponse({ data: partner({ id: 9 }) }, 201));
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /partners": () => listResponse([partner()]), "POST /partners": post }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Marcos Pereira");
    await user.click(screen.getByRole("button", { name: "Novo parceiro" }));
    await user.type(screen.getByLabelText("Nome"), "Alguém");
    await user.type(screen.getByLabelText("Número do documento"), "52998224725");
    await user.type(screen.getByLabelText("E-mail"), "não-é-um-email");
    await user.click(createFormField("Cliente"));
    await user.click(screen.getByRole("button", { name: "Salvar" }));

    expect(await screen.findByText("Informe um e-mail válido.")).toBeInTheDocument();
    expect(post).not.toHaveBeenCalled();

    await user.clear(screen.getByLabelText("E-mail"));
    await user.type(screen.getByLabelText("E-mail"), "alguem@example.com");
    await user.click(screen.getByRole("button", { name: "Salvar" }));

    expect(post).toHaveBeenCalledTimes(1);
    expect(screen.queryByText("Informe um e-mail válido.")).not.toBeInTheDocument();
  });

  it("shows the cross-field error when neither customer nor supplier is checked", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /partners": () => listResponse([partner()]),
        "POST /partners": () =>
          errorEnvelope("validation_failed", "invalid", {
            fields: { base: ["must_be_customer_or_supplier"] },
          }),
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Marcos Pereira");
    await user.click(screen.getByRole("button", { name: "Novo parceiro" }));
    await user.type(screen.getByLabelText("Nome"), "X");
    await user.type(screen.getByLabelText("Número do documento"), "52998224725");
    await user.click(screen.getByRole("button", { name: "Salvar" }));

    expect(
      await screen.findByText("Marque ao menos uma opção: cliente ou fornecedor."),
    ).toBeInTheDocument();
  });

  it("paginates the partner list", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /partners": (request) => {
          const page = Number(new URL(request.url).searchParams.get("page") ?? "1");
          const data = page === 1 ? [partner()] : [partner({ id: 2, name: "Segunda Página" })];
          return listResponse(data, { page, per_page: 1, total: 2 });
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    expect(await screen.findByText("Marcos Pereira")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Página anterior" })).toBeDisabled();

    await user.click(screen.getByRole("button", { name: "Próxima página" }));

    expect(await screen.findByText("Segunda Página")).toBeInTheDocument();
  });

  it("links each row to its detail page", async () => {
    vi.stubGlobal("fetch", createFetchMock({ "GET /partners": () => listResponse([partner()]) }));

    renderScreen();

    const link = await screen.findByRole("link", { name: "Marcos Pereira" });
    expect(link).toHaveAttribute("href", "/parceiros/1");
  });
});

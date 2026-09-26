import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Partner } from "./api";
import { PartnerDetailScreen } from "./PartnerDetailScreen";

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function errorEnvelope(code: string, message: string, details: Record<string, unknown> = {}) {
  return jsonResponse({ error: { code, message, details, request_id: "req-1" } }, 422);
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

function partner(overrides: Partial<Partner> = {}): Partner {
  return {
    id: 42,
    name: "Marcos Pereira",
    document_type: "cpf",
    document_number: "52998224725",
    customer: true,
    supplier: false,
    email: "marcos@example.com",
    phone: "71999990000",
    personal_data_visible: true,
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
      <MemoryRouter initialEntries={["/parceiros/42"]}>
        <Routes>
          <Route path="/parceiros/:id" element={<PartnerDetailScreen canManage={canManage} />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("PartnerDetailScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("shows a load error with a retry, then the partner once it succeeds", async () => {
    let attempt = 0;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /partners/42": () => {
          attempt += 1;
          return attempt === 1
            ? errorEnvelope("forbidden", "not allowed")
            : jsonResponse({ data: partner() });
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Não foi possível carregar o parceiro.");

    await user.click(screen.getByRole("button", { name: "Tentar novamente" }));

    expect(await screen.findByRole("heading", { name: "Marcos Pereira" })).toBeInTheDocument();
  });

  it("pre-fills an editable form for a role that can manage master data", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /partners/42": () => jsonResponse({ data: partner() }) }),
    );

    renderScreen(true);

    expect(await screen.findByLabelText("Nome")).toHaveValue("Marcos Pereira");
    expect(screen.getByLabelText("Número do documento")).toHaveValue("52998224725");
    expect(screen.getByLabelText("E-mail")).toHaveValue("marcos@example.com");
    expect(screen.getByLabelText("Cliente")).toBeChecked();
    expect(screen.getByLabelText("Fornecedor")).not.toBeChecked();
    expect(screen.getByLabelText("Ativo")).toBeChecked();
  });

  it("shows a read-only view for a role that cannot manage master data", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /partners/42": () => jsonResponse({ data: partner() }) }),
    );

    renderScreen(false);

    await screen.findByRole("heading", { name: "Marcos Pereira" });
    expect(screen.queryByLabelText("Nome")).not.toBeInTheDocument();
    expect(screen.getByText("52998224725")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Salvar alterações" })).not.toBeInTheDocument();
  });

  it("says the contact data is restricted, instead of not informed, when the API hides it", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /partners/42": () =>
          jsonResponse({
            data: partner({
              document_number: "***982247**",
              email: null,
              phone: null,
              personal_data_visible: false,
            }),
          }),
      }),
    );

    renderScreen(false);

    await screen.findByRole("heading", { name: "Marcos Pereira" });
    expect(screen.getByText("***982247**")).toBeInTheDocument();
    expect(screen.getAllByText("Restrito ao seu perfil")).toHaveLength(2);
    expect(screen.queryByText("Não informado")).not.toBeInTheDocument();
  });

  it("updates the partner", async () => {
    let requestBody: unknown;
    const patch = vi.fn(async (request: Request) => {
      requestBody = await jsonBody(request);
      return jsonResponse({ data: partner({ name: "Marcos P. Pereira" }) });
    });
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /partners/42": () => jsonResponse({ data: partner() }),
        "PATCH /partners/42": patch,
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    const nameInput = await screen.findByLabelText("Nome");
    await user.clear(nameInput);
    await user.type(nameInput, "Marcos P. Pereira");
    await user.click(screen.getByRole("button", { name: "Salvar alterações" }));

    expect(patch).toHaveBeenCalledTimes(1);
    expect(requestBody).toMatchObject({ name: "Marcos P. Pereira", active: true });
    expect(await screen.findByRole("status")).toHaveTextContent("Parceiro atualizado.");
  });
});

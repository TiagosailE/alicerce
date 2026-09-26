import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { App } from "./App";
import { createFetchMock, listResponse } from "./test/api";

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function sessionAs(role: string) {
  return jsonResponse({
    data: {
      csrf_token: "t",
      user: { id: 1, name: "Joana Lima", email: "joana@canion.example", demo: false },
      membership: {
        role,
        organization: { id: 1, name: "Cânion", time_zone: "America/Bahia", demo: true },
      },
      memberships: [],
    },
  });
}

function renderApp(path = "/") {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[path]}>
        <App />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("App", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("redirects to sign-in when there is no session", async () => {
    vi.mocked(fetch).mockResolvedValue(
      jsonResponse({ data: { csrf_token: "t", user: null, membership: null, memberships: [] } }),
    );

    renderApp();

    expect(await screen.findByRole("heading", { name: "Entrar" })).toBeInTheDocument();
  });

  it("shows the signed-in user's name once a session exists", async () => {
    vi.mocked(fetch).mockResolvedValue(
      jsonResponse({
        data: {
          csrf_token: "t",
          user: { id: 1, name: "Joana Lima", email: "joana@canion.example", demo: false },
          membership: {
            role: "owner",
            organization: { id: 1, name: "Cânion", time_zone: "America/Bahia", demo: true },
          },
          memberships: [],
        },
      }),
    );

    renderApp();

    expect(
      await screen.findByRole("heading", { level: 1, name: /Joana Lima/ }),
    ).toBeInTheDocument();
    expect(screen.getByText("Cânion")).toBeInTheDocument();
  });

  it.each(["owner", "admin", "finance", "read_only"])(
    "lets the %s role open the payables",
    async (role) => {
      vi.stubGlobal(
        "fetch",
        createFetchMock({
          "GET /session": () => sessionAs(role),
          "GET /payables": () => listResponse([]),
        }),
      );

      renderApp("/financeiro/contas-a-pagar");

      expect(
        await screen.findByRole("heading", { level: 1, name: "Contas a pagar" }),
      ).toBeInTheDocument();
      expect(screen.getByRole("link", { name: "Contas a pagar" })).toBeInTheDocument();
    },
  );

  it.each(["purchasing", "sales"])(
    "sends the %s role, who does not read payables, home instead of the payables",
    async (role) => {
      vi.stubGlobal("fetch", createFetchMock({ "GET /session": () => sessionAs(role) }));

      renderApp("/financeiro/contas-a-pagar");

      expect(
        await screen.findByRole("heading", { level: 1, name: /Joana Lima/ }),
      ).toBeInTheDocument();
      expect(screen.queryByRole("heading", { name: "Contas a pagar" })).not.toBeInTheDocument();
      expect(screen.queryByRole("link", { name: "Contas a pagar" })).not.toBeInTheDocument();
    },
  );
});

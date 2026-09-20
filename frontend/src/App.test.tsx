import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { App } from "./App";

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function renderApp() {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={["/"]}>
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
});

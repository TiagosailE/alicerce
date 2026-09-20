import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { SignInScreen } from "./SignInScreen";

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function errorEnvelope(code: string, message: string, details: Record<string, unknown> = {}) {
  return { error: { code, message, details, request_id: "req-1" } };
}

function renderSignIn() {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <SignInScreen />
    </QueryClientProvider>,
  );
}

async function fillCredentials(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText("E-mail"), "joana.lima@canion.example");
  await user.type(screen.getByLabelText("Senha"), "senha-de-teste-longa");
  await user.click(screen.getByRole("button", { name: "Entrar" }));
}

describe("SignInScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("shows a translated error for invalid credentials", async () => {
    vi.mocked(fetch).mockResolvedValue(jsonResponse(errorEnvelope("unauthenticated", "nope"), 401));
    const user = userEvent.setup();
    renderSignIn();

    await fillCredentials(user);

    expect(await screen.findByRole("alert")).toHaveTextContent("E-mail ou senha inválidos.");
  });

  it("shows a translated error when rate limited", async () => {
    vi.mocked(fetch).mockResolvedValue(
      jsonResponse(errorEnvelope("rate_limited", "slow down"), 429),
    );
    const user = userEvent.setup();
    renderSignIn();

    await fillCredentials(user);

    expect(await screen.findByRole("alert")).toHaveTextContent("Muitas tentativas");
  });

  it("offers an organization picker when the account belongs to more than one, then submits the choice", async () => {
    const canionMembership = {
      role: "owner",
      organization: {
        id: 1,
        name: "Cânion Materiais de Construção",
        time_zone: "America/Bahia",
        demo: true,
      },
    };
    const serraMembership = {
      role: "sales",
      organization: {
        id: 2,
        name: "Ferragens Serra Dourada",
        time_zone: "America/Sao_Paulo",
        demo: true,
      },
    };
    const memberships = [canionMembership, serraMembership];
    vi.mocked(fetch).mockResolvedValueOnce(
      jsonResponse(errorEnvelope("organization_required", "choose one", { memberships }), 422),
    );
    const user = userEvent.setup();
    renderSignIn();

    await fillCredentials(user);

    expect(await screen.findByText("Escolha a organização")).toBeInTheDocument();
    expect(screen.getByText("Ferragens Serra Dourada")).toBeInTheDocument();

    vi.mocked(fetch).mockResolvedValueOnce(
      jsonResponse(
        {
          data: {
            csrf_token: "t2",
            user: { id: 1, name: "Joana Lima", email: "joana@canion.example", demo: false },
            membership: { role: "owner", organization: canionMembership.organization },
            memberships,
          },
        },
        201,
      ),
    );

    await user.click(screen.getByRole("button", { name: /Cânion Materiais de Construção/ }));

    const lastCall = vi.mocked(fetch).mock.calls.at(-1);
    if (!lastCall) throw new Error("fetch was not called");
    const requestBody: unknown = JSON.parse(await (lastCall[0] as Request).clone().text());
    expect(requestBody).toMatchObject({ organization_id: 1 });
  });

  it("returns to the credentials form from the organization picker", async () => {
    vi.mocked(fetch).mockResolvedValue(
      jsonResponse(
        errorEnvelope("organization_required", "choose one", {
          memberships: [
            {
              role: "owner",
              organization: { id: 1, name: "Cânion", time_zone: "America/Bahia", demo: true },
            },
          ],
        }),
        422,
      ),
    );
    const user = userEvent.setup();
    renderSignIn();

    await fillCredentials(user);
    expect(await screen.findByText("Escolha a organização")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Voltar" }));

    expect(screen.getByRole("heading", { name: "Entrar" })).toBeInTheDocument();
  });
});

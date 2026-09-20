import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Member, PendingInvitation } from "./api";
import { MembersScreen } from "./MembersScreen";

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function noContent() {
  return new Response(null, { status: 204 });
}

function errorEnvelope(code: string, message: string, details: Record<string, unknown> = {}) {
  return jsonResponse({ error: { code, message, details, request_id: "req-1" } }, 422);
}

function listResponse(data: unknown[]) {
  return jsonResponse({ data, meta: { page: 1, per_page: 25, total: data.length } });
}

/** An element a query already proved exists; narrows away `| null` without `!`. */
function found<T>(element: T | null): T {
  if (element === null) throw new Error("expected element to exist");
  return element;
}

/** Routes a fake fetch by "METHOD /path" against the Request openapi-fetch builds. */
function createFetchMock(handlers: Record<string, () => Response>) {
  return vi.fn((input: RequestInfo | URL) => {
    const request = input as Request;
    const path = new URL(request.url).pathname.replace(/^\/api\/v1/, "");
    const key = `${request.method} ${path}`;
    const handler = handlers[key];
    if (!handler) throw new Error(`Unhandled request in test: ${key}`);
    return handler();
  });
}

function owner(overrides: Partial<Member> = {}): Member {
  return {
    id: 1,
    user: { id: 10, name: "Joana Lima", email: "joana@alicerce.example", demo: false },
    role: "owner",
    ...overrides,
  };
}

function salesMember(overrides: Partial<Member> = {}): Member {
  return {
    id: 2,
    user: { id: 11, name: "Marcos Souza", email: "marcos@alicerce.example", demo: false },
    role: "sales",
    ...overrides,
  };
}

function invitation(overrides: Partial<PendingInvitation> = {}): PendingInvitation {
  return {
    id: 5,
    email: "convidada@alicerce.example",
    role: "finance",
    invited_by: { id: 12, name: "Ana Prado", email: "ana@alicerce.example", demo: false },
    expires_at: "2026-10-01T00:00:00Z",
    ...overrides,
  };
}

function inviteFormRoleSelect() {
  const form = screen.getByRole("heading", { name: "Convidar para a organização" }).closest("form");
  return within(found(form)).getByLabelText("Papel");
}

function renderScreen(currentRole: Member["role"] = "owner") {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MembersScreen currentRole={currentRole} />
    </QueryClientProvider>,
  );
}

describe("MembersScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("lists the organization's members and pending invitations", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /memberships": () => listResponse([owner(), salesMember()]),
        "GET /invitations": () => listResponse([invitation()]),
      }),
    );

    renderScreen();

    expect(await screen.findByText("Joana Lima")).toBeInTheDocument();
    expect(screen.getByText("Marcos Souza")).toBeInTheDocument();
    expect(screen.getByText("convidada@alicerce.example")).toBeInTheDocument();
  });

  it("shows the empty state when there are no pending invitations", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /memberships": () => listResponse([owner()]),
        "GET /invitations": () => listResponse([]),
      }),
    );

    renderScreen();

    expect(await screen.findByText("Nenhum convite pendente.")).toBeInTheDocument();
  });

  it("hides the owner role from an admin, in both the invite form and an owner's row", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /memberships": () => listResponse([owner(), salesMember()]),
        "GET /invitations": () => listResponse([]),
      }),
    );
    const user = userEvent.setup();
    renderScreen("admin");

    await screen.findByText("Joana Lima");
    // The owner's row has no role select or remove button for a non-owner actor.
    const ownerRow = found(screen.getByText("Joana Lima").closest("tr"));
    expect(within(ownerRow).queryByRole("combobox")).not.toBeInTheDocument();
    expect(within(ownerRow).queryByRole("button", { name: "Remover" })).not.toBeInTheDocument();
    expect(within(ownerRow).getByText("Dono(a)")).toBeInTheDocument();

    // The invite form does not offer "Dono(a)" as a role to grant.
    await user.click(screen.getByRole("button", { name: "Convidar pessoa" }));
    const roleSelect = inviteFormRoleSelect();
    const options = within(roleSelect)
      .getAllByRole("option")
      .map((option) => option.textContent);
    expect(options).not.toContain("Dono(a)");
  });

  it("invites a new member with the chosen email and role", async () => {
    const post = vi.fn(() =>
      jsonResponse(
        {
          data: {
            id: 9,
            email: "nova@alicerce.example",
            role: "sales",
            expires_at: "2026-10-08T00:00:00Z",
            token: "raw-token",
          },
        },
        201,
      ),
    );
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /memberships": () => listResponse([owner()]),
        "GET /invitations": () => listResponse([]),
        "POST /invitations": post,
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Joana Lima");
    await user.click(screen.getByRole("button", { name: "Convidar pessoa" }));
    await user.type(screen.getByLabelText("E-mail"), "nova@alicerce.example");
    await user.selectOptions(inviteFormRoleSelect(), "sales");
    await user.click(screen.getByRole("button", { name: "Enviar convite" }));

    expect(post).toHaveBeenCalledTimes(1);
    // The form closes again once the invite succeeds.
    expect(screen.queryByLabelText("E-mail")).not.toBeInTheDocument();
  });

  it("shows a translated error when inviting an existing member", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /memberships": () => listResponse([owner()]),
        "GET /invitations": () => listResponse([]),
        "POST /invitations": () => errorEnvelope("already_member", "already a member"),
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Joana Lima");
    await user.click(screen.getByRole("button", { name: "Convidar pessoa" }));
    await user.type(screen.getByLabelText("E-mail"), "joana@alicerce.example");
    await user.click(screen.getByRole("button", { name: "Enviar convite" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Essa pessoa já faz parte da organização.",
    );
  });

  it("removes a member after confirmation", async () => {
    const del = vi.fn(noContent);
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /memberships": () => listResponse([owner(), salesMember()]),
        "GET /invitations": () => listResponse([]),
        "DELETE /memberships/2": del,
      }),
    );
    const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(true);
    const user = userEvent.setup();
    renderScreen();

    const row = found((await screen.findByText("Marcos Souza")).closest("tr"));
    await user.click(within(row).getByRole("button", { name: "Remover" }));

    expect(confirmSpy).toHaveBeenCalledWith(
      "Remover Marcos Souza da organização? A pessoa perde acesso imediatamente.",
    );
    expect(del).toHaveBeenCalledTimes(1);
  });

  it("does not remove a member when the confirmation is declined", async () => {
    const del = vi.fn(noContent);
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /memberships": () => listResponse([owner(), salesMember()]),
        "GET /invitations": () => listResponse([]),
        "DELETE /memberships/2": del,
      }),
    );
    vi.spyOn(window, "confirm").mockReturnValue(false);
    const user = userEvent.setup();
    renderScreen();

    const row = found((await screen.findByText("Marcos Souza")).closest("tr"));
    await user.click(within(row).getByRole("button", { name: "Remover" }));

    expect(del).not.toHaveBeenCalled();
  });

  it("shows a translated error when removing the organization's only owner", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /memberships": () => listResponse([owner()]),
        "GET /invitations": () => listResponse([]),
        "DELETE /memberships/1": () => errorEnvelope("last_owner", "no owner left"),
      }),
    );
    vi.spyOn(window, "confirm").mockReturnValue(true);
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Joana Lima");
    await user.click(screen.getByRole("button", { name: "Remover" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "A organização precisa de pelo menos um(a) dono(a).",
    );
  });

  it("cancels a pending invitation after confirmation", async () => {
    const del = vi.fn(noContent);
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /memberships": () => listResponse([owner()]),
        "GET /invitations": () => listResponse([invitation()]),
        "DELETE /invitations/5": del,
      }),
    );
    const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(true);
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("convidada@alicerce.example");
    await user.click(screen.getByRole("button", { name: "Cancelar convite" }));

    expect(confirmSpy).toHaveBeenCalledWith("Cancelar o convite para convidada@alicerce.example?");
    expect(del).toHaveBeenCalledTimes(1);
  });

  it("changes a member's role", async () => {
    const patch = vi.fn(() =>
      jsonResponse({ data: { id: 2, user: salesMember().user, role: "finance" } }),
    );
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /memberships": () => listResponse([owner(), salesMember()]),
        "GET /invitations": () => listResponse([]),
        "PATCH /memberships/2": patch,
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    await screen.findByText("Marcos Souza");
    const row = found(screen.getByText("Marcos Souza").closest("tr"));
    await user.selectOptions(within(row).getByRole("combobox"), "finance");

    expect(patch).toHaveBeenCalledTimes(1);
  });
});

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { AppShell } from "./AppShell";

function renderAt(path: string, canViewPayables = false) {
  render(
    <QueryClientProvider client={new QueryClient()}>
      <MemoryRouter initialEntries={[path]}>
        <AppShell
          organizationName="Cânion"
          userName="Marina Costa"
          canManageMembers={false}
          canViewPurchasing
          canViewPayables={canViewPayables}
        >
          <p>conteúdo</p>
        </AppShell>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe("AppShell", () => {
  it.each(["/compras", "/compras/9", "/compras/9/receber", "/recebimentos", "/recebimentos/31"])(
    "marks Compras as the current area on %s",
    (path) => {
      renderAt(path);

      expect(screen.getByRole("link", { name: "Compras" })).toHaveAttribute("aria-current", "page");
    },
  );

  it("does not mark Compras as current elsewhere", () => {
    renderAt("/parceiros");

    expect(screen.getByRole("link", { name: "Compras" })).not.toHaveAttribute("aria-current");
  });

  it("offers Contas a pagar only to a role that reads payables, and marks it on its page", () => {
    renderAt("/financeiro/contas-a-pagar", true);

    expect(screen.getByRole("link", { name: "Contas a pagar" })).toHaveAttribute(
      "aria-current",
      "page",
    );
  });

  it("leaves Contas a pagar out for a role that cannot read payables", () => {
    renderAt("/compras", false);

    expect(screen.queryByRole("link", { name: "Contas a pagar" })).not.toBeInTheDocument();
  });
});

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { AppShell } from "./AppShell";

function renderAt(path: string) {
  render(
    <QueryClientProvider client={new QueryClient()}>
      <MemoryRouter initialEntries={[path]}>
        <AppShell
          organizationName="Cânion"
          userName="Marina Costa"
          canManageMembers={false}
          canViewPurchasing
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
});

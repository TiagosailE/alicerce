import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes, useLocation } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createFetchMock, errorEnvelope, jsonResponse, listResponse } from "../../test/api";
import { cellText, nth } from "../../test/dom";
import { PayablesScreen } from "./PayablesScreen";
import { title } from "./testData";

function Address() {
  const location = useLocation();
  return <output aria-label="endereço">{location.search}</output>;
}

function renderScreen(path = "/financeiro/contas-a-pagar") {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[path]}>
        <Address />
        <Routes>
          <Route path="/financeiro/contas-a-pagar" element={<PayablesScreen />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

// The first installment is settled and the second is not, so the payable's own
// settled and open figures are what its installments add up to.
const partlySettled = title({
  settled_cents: 191_100,
  open_cents: 191_100,
  installments: [
    {
      id: 1,
      number: 1,
      due_on: "2026-10-26",
      amount_cents: 191_100,
      settled_cents: 191_100,
      open_cents: 0,
    },
    {
      id: 2,
      number: 2,
      due_on: "2026-11-25",
      amount_cents: 191_100,
      settled_cents: 0,
      open_cents: 191_100,
    },
  ],
});

const cancelled = title({
  id: 71,
  status: "cancelled",
  partner: { id: 4, name: "Tintas Rio" },
  receipt: { id: 32, number: 3 },
  total_cents: 1_000,
  open_cents: 1_000,
  installments: [
    {
      id: 3,
      number: 1,
      due_on: "2026-10-30",
      amount_cents: 1_000,
      settled_cents: 0,
      open_cents: 1_000,
    },
  ],
});

function listRows() {
  return within(screen.getByRole("table", { name: "Contas a pagar" })).getAllByRole("row");
}

describe("PayablesScreen", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("lists the payables with supplier, receipt, status and the amounts the API stored", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /payables": () => listResponse([partlySettled, cancelled]) }),
    );

    renderScreen();

    const link = await screen.findByRole("link", { name: "Recebimento nº 2" });
    expect(link).toHaveAttribute("href", "/recebimentos/31");
    expect(link).toHaveTextContent("2");
    const [, first, second] = listRows();
    const cells = within(first ?? document.body).getAllByRole("cell");
    expect(nth(cells, 0)).toHaveTextContent("Cimentos Bahia");
    expect(nth(cells, 2)).toHaveTextContent("Aberta");
    expect(cellText(cells, 3)).toBe("R$ 3.822,00");
    expect(cellText(cells, 4)).toBe("R$ 1.911,00");
    expect(cellText(cells, 5)).toBe("R$ 1.911,00");
    expect(within(second ?? document.body).getByText("Cancelada")).toBeInTheDocument();
  });

  it("shows a payable that has no receipt as such, with no link", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /payables": () => listResponse([title({ receipt: null })]) }),
    );

    renderScreen();

    expect(await screen.findByText("Sem recebimento")).toBeInTheDocument();
    expect(screen.queryByRole("link")).not.toBeInTheDocument();
  });

  it("opens the installments of a payable in a row of their own, each as stored", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /payables": () => listResponse([partlySettled]) }),
    );
    const user = userEvent.setup();
    renderScreen();

    const toggle = await screen.findByRole("button", { name: /^2 parcelas/ });
    expect(toggle).toHaveAttribute("aria-expanded", "false");
    expect(toggle).not.toHaveAttribute("aria-controls");
    await user.click(toggle);

    expect(toggle).toHaveAttribute("aria-expanded", "true");
    const panel = document.getElementById(toggle.getAttribute("aria-controls") ?? "");
    const installments = screen.getByRole("table", {
      name: "Parcelas de Cimentos Bahia, recebimento nº 2",
    });
    expect(panel).toContainElement(installments);
    expect(within(panel ?? document.body).getAllByRole("cell")[0]).toHaveAttribute("colspan", "7");
    const rows = within(installments).getAllByRole("row");
    expect(rows).toHaveLength(3);
    expect(nth(rows, 1)).toHaveTextContent("26/10/2026");
    expect(nth(rows, 2)).toHaveTextContent("25/11/2026");
    const first = within(nth(rows, 1)).getAllByRole("cell");
    expect(cellText(first, 2)).toBe("R$ 1.911,00");
    expect(cellText(first, 3)).toBe("R$ 1.911,00");
    expect(cellText(first, 4)).toBe("R$ 0,00");
    const second = within(nth(rows, 2)).getAllByRole("cell");
    expect(cellText(second, 3)).toBe("R$ 0,00");
    expect(cellText(second, 4)).toBe("R$ 1.911,00");

    await user.click(toggle);

    expect(toggle).toHaveAttribute("aria-expanded", "false");
    expect(toggle).not.toHaveAttribute("aria-controls");
    expect(screen.queryByRole("table", { name: /^Parcelas de/ })).not.toBeInTheDocument();
  });

  it("opens and closes the installments from the keyboard, keeping focus on the control", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /payables": () => listResponse([partlySettled]) }),
    );
    const user = userEvent.setup();
    renderScreen();
    const toggle = await screen.findByRole("button", { name: /^2 parcelas/ });

    toggle.focus();
    await user.keyboard("{Enter}");

    expect(toggle).toHaveAttribute("aria-expanded", "true");
    expect(toggle).toHaveFocus();

    await user.keyboard(" ");

    expect(toggle).toHaveAttribute("aria-expanded", "false");
    expect(toggle).toHaveFocus();
  });

  it("keeps each payable's installments open or closed on their own", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /payables": () => listResponse([partlySettled, cancelled]) }),
    );
    const user = userEvent.setup();
    renderScreen();

    await user.click(await screen.findByRole("button", { name: /^2 parcelas/ }));
    await user.click(screen.getByRole("button", { name: /^1 parcela/ }));

    expect(screen.getAllByRole("table", { name: /^Parcelas de/ })).toHaveLength(2);

    await user.click(screen.getByRole("button", { name: /^2 parcelas/ }));

    expect(screen.getAllByRole("table", { name: /^Parcelas de/ })).toHaveLength(1);
    expect(
      screen.getByRole("table", { name: "Parcelas de Tintas Rio, recebimento nº 3" }),
    ).toBeVisible();
  });

  it("names whose installments a control holds, for a screen reader that lists controls apart", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /payables": () => listResponse([partlySettled, cancelled]) }),
    );

    renderScreen();

    expect(
      await screen.findByRole("button", {
        name: "2 parcelas de Cimentos Bahia, recebimento nº 2",
      }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "1 parcela de Tintas Rio, recebimento nº 3" }),
    ).toBeInTheDocument();
  });

  it("leaves the receipt out of the names when the payable has none", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({ "GET /payables": () => listResponse([title({ receipt: null })]) }),
    );
    const user = userEvent.setup();
    renderScreen();

    await user.click(await screen.findByRole("button", { name: "2 parcelas de Cimentos Bahia" }));

    expect(screen.getByRole("table", { name: "Parcelas de Cimentos Bahia" })).toBeInTheDocument();
  });

  it("keeps the page, the status and the search in the address, and sends them to the API", async () => {
    const urls: string[] = [];
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /payables": (request) => {
          urls.push(request.url);
          return listResponse([title()]);
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen("/financeiro/contas-a-pagar?status=open&q=bahia&page=2");

    expect(await screen.findByRole("link", { name: "Recebimento nº 2" })).toBeInTheDocument();
    const first = new URL(urls[0] ?? "");
    expect(first.searchParams.get("status")).toBe("open");
    expect(first.searchParams.get("q")).toBe("bahia");
    expect(first.searchParams.get("page")).toBe("2");
    expect(screen.getByLabelText("Status")).toHaveValue("open");

    await user.selectOptions(screen.getByLabelText("Status"), "cancelled");

    await waitFor(() => {
      expect(screen.getByLabelText("endereço")).toHaveTextContent("?status=cancelled&q=bahia");
    });
  });

  it("reads a status or a page it does not know as no filter and the first page", async () => {
    const urls: string[] = [];
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /payables": (request) => {
          urls.push(request.url);
          return listResponse([title()]);
        },
      }),
    );

    renderScreen("/financeiro/contas-a-pagar?status=weird&page=-2");

    await screen.findByRole("link", { name: "Recebimento nº 2" });
    const first = new URL(urls[0] ?? "");
    expect(first.searchParams.has("status")).toBe(false);
    expect(first.searchParams.get("page")).toBe("1");
  });

  it("explains an empty list, and offers to clear the filters that emptied it", async () => {
    vi.stubGlobal("fetch", createFetchMock({ "GET /payables": () => listResponse([]) }));
    const user = userEvent.setup();
    renderScreen("/financeiro/contas-a-pagar?q=zzz");

    expect(
      await screen.findByText("Nenhuma conta a pagar encontrada com esses filtros."),
    ).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Limpar filtros" }));

    expect(screen.getByLabelText("Buscar")).toHaveFocus();
    expect(await screen.findByText(/Ainda não há contas a pagar/)).toBeInTheDocument();
  });

  it("says a page past the last one is gone, not that there are no payables, and leads to the first", async () => {
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /payables": (request) =>
          new URL(request.url).searchParams.get("page") === "5"
            ? jsonResponse({ data: [], meta: { page: 5, per_page: 25, total: 30 } })
            : listResponse([title()]),
      }),
    );
    const user = userEvent.setup();
    renderScreen("/financeiro/contas-a-pagar?page=5");

    expect(await screen.findByText("Esta página não existe mais.")).toBeInTheDocument();
    expect(screen.queryByText(/Ainda não há contas a pagar/)).not.toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Ir para a primeira página" }));

    expect(await screen.findByRole("link", { name: "Recebimento nº 2" })).toBeInTheDocument();
    expect(screen.getByLabelText("endereço")).toBeEmptyDOMElement();
    expect(screen.queryByText("Esta página não existe mais.")).not.toBeInTheDocument();
  });

  it("says the list is read-only until settlement arrives", async () => {
    vi.stubGlobal("fetch", createFetchMock({ "GET /payables": () => listResponse([title()]) }));

    renderScreen();

    expect(
      await screen.findByText(/A baixa das parcelas chega com o módulo financeiro/),
    ).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /baixar|pagar/i })).not.toBeInTheDocument();
  });

  it("shows a load error with a retry", async () => {
    let attempt = 0;
    vi.stubGlobal(
      "fetch",
      createFetchMock({
        "GET /payables": () => {
          attempt += 1;
          return attempt === 1
            ? errorEnvelope("forbidden", "no", {}, 403)
            : listResponse([title()]);
        },
      }),
    );
    const user = userEvent.setup();
    renderScreen();

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Não foi possível carregar as contas a pagar.",
    );
    await user.click(screen.getByRole("button", { name: "Tentar novamente" }));

    expect(await screen.findByRole("link", { name: "Recebimento nº 2" })).toBeInTheDocument();
  });
});

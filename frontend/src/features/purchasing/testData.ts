import type { PurchaseOrder, PurchaseOrderSummary } from "./api";

export function orderLine(overrides: Partial<PurchaseOrder["lines"][number]> = {}) {
  return {
    id: 501,
    position: 1,
    product: { id: 7, sku: "CIM-001", name: "Cimento CP II" },
    purchase_unit_code: "SC",
    stock_unit_code: "UN",
    factor: "1.000000",
    quantity: "200.000",
    received_quantity: "0.000",
    remaining_quantity: "200.000",
    unit_price_cents: 3250,
    discount_bp: 200,
    gross_cents: 650_000,
    discount_cents: 13_000,
    net_cents: 637_000,
    ...overrides,
  };
}

export function order(overrides: Partial<PurchaseOrder> = {}): PurchaseOrder {
  return {
    id: 9,
    number: 4,
    status: "draft",
    supplier: {
      id: 3,
      name: "Cimentos Bahia",
      document_type: "cnpj",
      document_number: "NXKE3INSKJRI36",
    },
    installments: 2,
    first_due_days: 30,
    interval_days: 30,
    note: "Entrega na segunda",
    total_cents: 637_000,
    currency: "BRL",
    revision: 0,
    personal_data_visible: true,
    approved_at: null,
    cancelled_at: null,
    created_at: "2026-09-26T12:00:00Z",
    lines: [orderLine()],
    ...overrides,
  };
}

export function summary(overrides: Partial<PurchaseOrderSummary> = {}): PurchaseOrderSummary {
  return {
    id: 9,
    number: 4,
    status: "draft",
    supplier: { id: 3, name: "Cimentos Bahia" },
    total_cents: 637_000,
    currency: "BRL",
    created_at: "2026-09-26T12:00:00Z",
    ...overrides,
  };
}

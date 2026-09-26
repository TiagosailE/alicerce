import type { PurchaseOrder, PurchaseOrderSummary } from "./api";
import type { Receipt, ReceiptLine, ReceiptSummary, Title } from "./receiptsApi";

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

export function receiptLine(overrides: Partial<ReceiptLine> = {}): ReceiptLine {
  return {
    id: 801,
    order_line_id: 501,
    product: { id: 7, sku: "CIM-001", name: "Cimento CP II" },
    purchase_unit_code: "SC",
    stock_unit_code: "UN",
    factor: "1.000000",
    unit_price_cents: 3250,
    discount_bp: 200,
    quantity: "120.000",
    stock_quantity: "120.000",
    gross_cents: 390_000,
    discount_cents: 7_800,
    net_cents: 382_200,
    ...overrides,
  };
}

export function title(overrides: Partial<Title> = {}): Title {
  return {
    id: 70,
    kind: "payable",
    status: "open",
    partner: { id: 3, name: "Cimentos Bahia" },
    receipt: { id: 31, number: 2 },
    total_cents: 382_200,
    settled_cents: 0,
    open_cents: 382_200,
    currency: "BRL",
    created_at: "2026-09-26T13:00:00Z",
    installments: [
      {
        id: 1,
        number: 1,
        due_on: "2026-10-26",
        amount_cents: 191_100,
        settled_cents: 0,
        open_cents: 191_100,
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
    ...overrides,
  };
}

export function receipt(overrides: Partial<Receipt> = {}): Receipt {
  return {
    id: 31,
    number: 2,
    status: "posted",
    order: { id: 9, number: 4 },
    supplier: { id: 3, name: "Cimentos Bahia" },
    warehouse: { id: 5, name: "Loja" },
    received_on: "2026-09-26",
    supplier_invoice_number: "NF 1234",
    total_cents: 382_200,
    currency: "BRL",
    created_by: { id: 1, name: "Marina Costa" },
    created_at: "2026-09-26T13:00:00Z",
    lines: [receiptLine()],
    payable: title(),
    ...overrides,
  };
}

export function receiptSummary(overrides: Partial<ReceiptSummary> = {}): ReceiptSummary {
  return {
    id: 31,
    number: 2,
    order: { id: 9, number: 4 },
    supplier: { id: 3, name: "Cimentos Bahia" },
    warehouse: { id: 5, name: "Loja" },
    received_on: "2026-09-26",
    total_cents: 382_200,
    currency: "BRL",
    created_at: "2026-09-26T13:00:00Z",
    ...overrides,
  };
}

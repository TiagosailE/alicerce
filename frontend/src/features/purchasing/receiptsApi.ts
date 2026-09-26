import {
  keepPreviousData,
  type QueryClient,
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import { ApiError, api, csrfHeader, unwrap, unwrapList } from "../../api/client";
import type { components } from "../../api/schema";
import { payablesKey } from "../finance/api";
import { refreshWarehouses, stockKey } from "../inventory/api";

export type Receipt = components["schemas"]["Receipt"];
export type ReceiptSummary = components["schemas"]["ReceiptSummary"];
export type ReceiptLine = components["schemas"]["ReceiptLine"];

const receiptsKey = ["purchasing", "receipts"] as const;
const orderDetailKey = (orderId: number) => ["purchasing", "orders", "detail", orderId] as const;

/** How many lines one receipt takes (Purchasing::Receipt::MAX_LINES): it writes
 * about a dozen rows per line while holding the receipt counter's lock, so a
 * larger order is received in more than one receipt. */
export const RECEIPT_MAX_LINES = 50;

export interface ReceiptFilters {
  q?: string;
  orderId?: number;
}

export function useReceipts(page: number, filters: ReceiptFilters = {}) {
  return useQuery({
    queryKey: [...receiptsKey, "list", { page, ...filters }],
    queryFn: async () =>
      unwrapList<ReceiptSummary>(
        await api.GET("/receipts", {
          params: { query: { page, q: filters.q, order_id: filters.orderId } },
        }),
      ),
    placeholderData: keepPreviousData,
  });
}

/** A receipt by id; a null id (an address that is not a number) asks for nothing. */
export function useReceipt(id: number | null) {
  return useQuery({
    queryKey: [...receiptsKey, "detail", id],
    queryFn: async () =>
      unwrap(await api.GET("/receipts/{id}", { params: { path: { id: id ?? 0 } } })),
    enabled: id !== null,
  });
}

/** What the receive form sends. Quantities are the decimal text the person
 * typed, already turned into the API's representation by text rules. */
export interface ReceiveGoodsInput {
  orderId: number;
  idempotencyKey: string;
  warehouseId: number;
  receivedOn: string;
  supplierInvoiceNumber: string;
  lines: { orderLineId: number; quantity: string }[];
}

/** An answer that says what the form was showing is out of date: fetch the
 * order again so the quantities left and the buttons catch up with what is
 * stored, and the warehouses when one turned out to be inactive. */
function refreshWhenOutdated(queryClient: QueryClient, orderId: number, error: unknown) {
  if (!(error instanceof ApiError)) return;
  const fields = (error.details.fields ?? {}) as Record<string, string[] | undefined>;
  const overReceipt = Object.values(fields).some((kinds) => kinds?.includes("over_receipt"));
  if (error.code === "invalid_transition" || overReceipt) {
    void queryClient.invalidateQueries({ queryKey: orderDetailKey(orderId) });
  }
  if (fields.warehouse_id?.includes("inactive")) refreshWarehouses(queryClient);
}

/** A critical write (ADR 0005): the caller owns the idempotency key (see
 * lib/idempotency), so a retry can never receive the goods twice. */
export function useReceiveGoods() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (input: ReceiveGoodsInput) =>
      unwrap(
        await api.POST("/purchase_orders/{id}/receipts", {
          params: {
            path: { id: input.orderId },
            header: { ...csrfHeader(), "Idempotency-Key": input.idempotencyKey },
          },
          body: {
            warehouse_id: input.warehouseId,
            received_on: input.receivedOn,
            supplier_invoice_number: input.supplierInvoiceNumber.trim() || undefined,
            lines: input.lines.map((line) => ({
              order_line_id: line.orderLineId,
              quantity: line.quantity,
            })),
          },
        }),
      ),
    onSuccess: (receipt) => {
      queryClient.setQueryData([...receiptsKey, "detail", receipt.id], receipt);
      void queryClient.invalidateQueries({ queryKey: receiptsKey });
      void queryClient.invalidateQueries({ queryKey: ["purchasing", "orders"] });
      void queryClient.invalidateQueries({ queryKey: payablesKey });
      void queryClient.invalidateQueries({ queryKey: stockKey });
    },
    onError: (error, input) => {
      refreshWhenOutdated(queryClient, input.orderId, error);
    },
  });
}

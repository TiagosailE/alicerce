import {
  keepPreviousData,
  type QueryClient,
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import { ApiError, api, csrfHeader, unwrap, unwrapList } from "../../api/client";
import type { components } from "../../api/schema";
import type { PartnerSummary } from "../catalog/api";

export type PurchaseOrder = components["schemas"]["PurchaseOrder"];
export type PurchaseOrderSummary = components["schemas"]["PurchaseOrderSummary"];
export type PurchaseOrderLine = components["schemas"]["PurchaseOrderLine"];
export type PurchaseOrderStatus = components["schemas"]["PurchaseOrderStatus"];

const ordersKey = ["purchasing", "orders"] as const;

export interface PurchaseOrderFilters {
  status?: PurchaseOrderStatus;
  q?: string;
}

/** What the order form sends. Every amount is text the person typed, already
 * turned into the API's own representation (whole cents, basis points, a
 * decimal quantity) by text rules; the API works out every total. */
export interface PurchaseOrderInput {
  supplierId: number;
  installments: number;
  firstDueDays: number;
  intervalDays: number;
  note: string;
  lines: {
    productId: number;
    quantity: string;
    unitPriceCents: number;
    discountBp: number;
  }[];
}

function body(input: PurchaseOrderInput) {
  return {
    supplier_id: input.supplierId,
    installments: input.installments,
    first_due_days: input.firstDueDays,
    interval_days: input.intervalDays,
    note: input.note.trim() || undefined,
    lines: input.lines.map((line) => ({
      product_id: line.productId,
      quantity: line.quantity,
      unit_price_cents: line.unitPriceCents,
      discount_bp: line.discountBp,
    })),
  };
}

export function usePurchaseOrders(page: number, filters: PurchaseOrderFilters = {}) {
  return useQuery({
    queryKey: [...ordersKey, "list", { page, ...filters }],
    queryFn: async () =>
      unwrapList<PurchaseOrderSummary>(
        await api.GET("/purchase_orders", {
          params: { query: { page, status: filters.status, q: filters.q } },
        }),
      ),
    placeholderData: keepPreviousData,
  });
}

/** An order by id; a null id (an address that is not a number) asks for nothing. */
export function usePurchaseOrder(id: number | null) {
  return useQuery({
    queryKey: [...ordersKey, "detail", id],
    queryFn: async () =>
      unwrap(await api.GET("/purchase_orders/{id}", { params: { path: { id: id ?? 0 } } })),
    enabled: id !== null,
  });
}

/** A refused transition means the screen is showing a state the order has left:
 * fetch it again so its buttons and status catch up. A stale approval is left
 * out on purpose: the person must reload and see the new conditions themselves
 * before approving them. */
function refreshWhenOutdated(queryClient: QueryClient, id: number, error: unknown) {
  if (error instanceof ApiError && error.code === "invalid_transition") {
    void queryClient.invalidateQueries({ queryKey: [...ordersKey, "detail", id] });
  }
}

/** Active suppliers for a picker, narrowed by a server-side search; the answer
 * says how many matched, so a picker showing the first page can tell the person
 * to refine the search instead of hiding the rest. */
export function useSupplierOptions(q: string) {
  return useQuery({
    queryKey: ["catalog", "partners", "supplier-options", q],
    queryFn: async () =>
      unwrapList<PartnerSummary>(
        await api.GET("/partners", {
          params: { query: { per_page: 50, supplier: true, active: true, q: q || undefined } },
        }),
      ),
    placeholderData: keepPreviousData,
  });
}

export function useCreatePurchaseOrder() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (input: PurchaseOrderInput) =>
      unwrap(
        await api.POST("/purchase_orders", { body: body(input), params: { header: csrfHeader() } }),
      ),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ordersKey });
    },
  });
}

export function useUpdatePurchaseOrder() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({
      id,
      revision,
      ...input
    }: PurchaseOrderInput & { id: number; revision: number }) =>
      unwrap(
        await api.PATCH("/purchase_orders/{id}", {
          params: { path: { id }, header: csrfHeader() },
          body: { ...body(input), revision },
        }),
      ),
    onSuccess: (order) => {
      queryClient.setQueryData([...ordersKey, "detail", order.id], order);
      void queryClient.invalidateQueries({ queryKey: ordersKey });
    },
  });
}

export function useApprovePurchaseOrder() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ id, revision }: { id: number; revision: number }) =>
      unwrap(
        await api.POST("/purchase_orders/{id}/approval", {
          params: { path: { id }, header: csrfHeader() },
          body: { revision },
        }),
      ),
    onSuccess: (order) => {
      queryClient.setQueryData([...ordersKey, "detail", order.id], order);
      void queryClient.invalidateQueries({ queryKey: ordersKey });
    },
    onError: (error, { id }) => {
      refreshWhenOutdated(queryClient, id, error);
    },
  });
}

export function useCancelPurchaseOrder() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (id: number) =>
      unwrap(
        await api.POST("/purchase_orders/{id}/cancellation", {
          params: { path: { id }, header: csrfHeader() },
        }),
      ),
    onSuccess: (order) => {
      queryClient.setQueryData([...ordersKey, "detail", order.id], order);
      void queryClient.invalidateQueries({ queryKey: ordersKey });
    },
    onError: (error, id) => {
      refreshWhenOutdated(queryClient, id, error);
    },
  });
}

import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ApiError, api, csrfHeader, unwrap, unwrapList } from "../../api/client";
import type { components } from "../../api/schema";

export type Warehouse = components["schemas"]["Warehouse"];
type Meta = components["schemas"]["Meta"];

const warehousesListKey = ["inventory", "warehouses"] as const;
const warehousesKey = (page: number) => [...warehousesListKey, { page }] as const;

export function useWarehouses(page: number) {
  return useQuery({
    queryKey: warehousesKey(page),
    queryFn: async () =>
      unwrapList<Warehouse>(await api.GET("/warehouses", { params: { query: { page } } })),
    placeholderData: keepPreviousData,
  });
}

export function useCreateWarehouse() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (name: string) =>
      unwrap(
        await api.POST("/warehouses", {
          body: { name },
          params: { header: csrfHeader() },
        }),
      ),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: warehousesListKey });
    },
  });
}

export function useUpdateWarehouse() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ id, name, active }: { id: number; name: string; active: boolean }) =>
      unwrap(
        await api.PATCH("/warehouses/{id}", {
          params: { path: { id }, header: csrfHeader() },
          body: { name, active },
        }),
      ),
    // Patches every cached list page directly, so the row shows the saved
    // values the instant the edit form closes instead of briefly flashing
    // the pre-edit ones until the invalidated query's refetch resolves.
    onSuccess: (warehouse) => {
      queryClient.setQueriesData<{ data: Warehouse[]; meta: Meta }>(
        { queryKey: warehousesListKey },
        (page) =>
          page
            ? { ...page, data: page.data.map((w) => (w.id === warehouse.id ? warehouse : w)) }
            : page,
      );
      void queryClient.invalidateQueries({ queryKey: warehousesListKey });
    },
  });
}

export type StockBalance = components["schemas"]["StockBalance"];
export type StockMovement = components["schemas"]["StockMovement"];
export type AdjustmentReason = components["schemas"]["AdjustmentReason"];

const stockKey = ["inventory", "stock"] as const;

export interface StockBalanceFilters {
  warehouseId?: number;
  productId?: number;
  q?: string;
}

export interface StockMovementFilters {
  warehouseId?: number;
  reason?: AdjustmentReason;
}

export function useStockBalances(page: number, filters: StockBalanceFilters = {}) {
  return useQuery({
    queryKey: [...stockKey, "balances", { page, ...filters }],
    queryFn: async () =>
      unwrapList<StockBalance>(
        await api.GET("/stock_balances", {
          params: {
            query: {
              page,
              warehouse_id: filters.warehouseId,
              product_id: filters.productId,
              q: filters.q,
            },
          },
        }),
      ),
    placeholderData: keepPreviousData,
  });
}

export function useStockMovements(page: number, filters: StockMovementFilters = {}) {
  return useQuery({
    queryKey: [...stockKey, "movements", { page, ...filters }],
    queryFn: async () =>
      unwrapList<StockMovement>(
        await api.GET("/stock_movements", {
          params: { query: { page, warehouse_id: filters.warehouseId, reason: filters.reason } },
        }),
      ),
    placeholderData: keepPreviousData,
  });
}

/** Every warehouse, for a picker: an organization has a handful. */
export function useWarehouseOptions() {
  return useQuery({
    queryKey: [...warehousesListKey, "options"],
    queryFn: async () =>
      unwrapList<Warehouse>(await api.GET("/warehouses", { params: { query: { per_page: 100 } } })),
  });
}

/** What the balance of one product in one warehouse holds right now, as the
 * count form needs it: shown to the operator and sent back as the balance the
 * count is based on, so a count made against a balance that has moved is
 * refused instead of silently undoing the movement (ADR 0016). A pair with no
 * balance yet holds zero. */
export function useObservedBalance(productId: number | undefined, warehouseId: number | undefined) {
  return useQuery({
    queryKey: [...stockKey, "observed", { productId, warehouseId }],
    enabled: productId !== undefined && warehouseId !== undefined,
    queryFn: async () => {
      const page = unwrapList<StockBalance>(
        await api.GET("/stock_balances", {
          params: { query: { product_id: productId, warehouse_id: warehouseId } },
        }),
      );
      return page.data[0]?.on_hand ?? "0.000";
    },
  });
}

export interface StockAdjustmentInput {
  productId: number;
  warehouseId: number;
  expectedOnHand: string;
  countedQuantity: string;
  reason: AdjustmentReason;
  note: string;
  unitCost: string | null;
}

/** A critical write (ADR 0005): the caller owns the idempotency key, keeps it
 * across a network error, a 5xx or a 409, and replaces it after any other
 * outcome, so a retry can never apply the count twice. */
export function useAdjustStock() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({
      idempotencyKey,
      ...input
    }: StockAdjustmentInput & { idempotencyKey: string }) =>
      unwrap(
        await api.POST("/stock_adjustments", {
          body: {
            product_id: input.productId,
            warehouse_id: input.warehouseId,
            counted_quantity: input.countedQuantity,
            expected_on_hand: input.expectedOnHand,
            reason: input.reason,
            note: input.note.trim() || undefined,
            unit_cost_cents: input.unitCost ?? undefined,
          },
          params: { header: { ...csrfHeader(), "Idempotency-Key": idempotencyKey } },
        }),
      ),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: stockKey });
    },
    // A stale count means the balance moved: look at it again.
    onError: (error) => {
      if (error instanceof ApiError && error.code === "stale") {
        void queryClient.invalidateQueries({ queryKey: stockKey });
      }
    },
  });
}

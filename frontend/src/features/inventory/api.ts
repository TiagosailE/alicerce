import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api, csrfHeader, unwrap, unwrapList } from "../../api/client";
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

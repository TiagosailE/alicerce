import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { api, unwrapList } from "../../api/client";
import type { components } from "../../api/schema";

export type Title = components["schemas"]["Title"];
export type Installment = components["schemas"]["Installment"];
export type TitleStatus = components["schemas"]["TitleStatus"];

/** Every payable query lives under this key, so a receipt that opens one can
 * refresh them all. */
export const payablesKey = ["finance", "payables"] as const;

export interface PayableFilters {
  status?: TitleStatus;
  q?: string;
}

/** Payables, newest first, each with its installments (ADR 0017). Read-only:
 * settlement arrives with the finance slice. */
export function usePayables(page: number, filters: PayableFilters = {}) {
  return useQuery({
    queryKey: [...payablesKey, "list", { page, ...filters }],
    queryFn: async () =>
      unwrapList<Title>(
        await api.GET("/payables", {
          params: { query: { page, status: filters.status, q: filters.q } },
        }),
      ),
    placeholderData: keepPreviousData,
  });
}

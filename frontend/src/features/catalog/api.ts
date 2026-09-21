import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api, csrfHeader, unwrap, unwrapList } from "../../api/client";
import type { components } from "../../api/schema";

export type Unit = components["schemas"]["Unit"];
export type Category = components["schemas"]["Category"];
export type Product = components["schemas"]["Product"];
export type Partner = components["schemas"]["Partner"];

export interface ProductFilters {
  categoryId?: number;
  active?: boolean;
  q?: string;
}

export interface ProductInput {
  sku: string;
  name: string;
  categoryId: number | null;
  stockUnitId: number;
  purchaseUnitId: number;
  factor: string;
}

export interface PartnerFilters {
  customer?: boolean;
  supplier?: boolean;
  active?: boolean;
  q?: string;
}

export interface PartnerInput {
  name: string;
  documentType: "cpf" | "cnpj";
  documentNumber: string;
  customer: boolean;
  supplier: boolean;
  email: string;
  phone: string;
}

const unitsKey = ["catalog", "units"] as const;
const categoriesKey = ["catalog", "categories"] as const;
const productsKey = (page: number, filters: ProductFilters) =>
  ["catalog", "products", { page, ...filters }] as const;
const productKey = (id: number) => ["catalog", "product", id] as const;
const partnersKey = (page: number, filters: PartnerFilters) =>
  ["catalog", "partners", { page, ...filters }] as const;
const partnerKey = (id: number) => ["catalog", "partner", id] as const;

function requestBody(input: ProductInput) {
  return {
    sku: input.sku,
    name: input.name,
    category_id: input.categoryId ?? undefined,
    stock_unit_id: input.stockUnitId,
    purchase_unit_id: input.purchaseUnitId,
    factor: input.factor,
  };
}

// No dedicated management screen yet (deliberately deferred): read-only,
// used to populate the product form's pickers. A large per_page keeps a
// small distributor's whole list on one page without its own pagination UI.
export function useUnits() {
  return useQuery({
    queryKey: unitsKey,
    queryFn: async () =>
      unwrapList<Unit>(await api.GET("/units", { params: { query: { per_page: 100 } } })),
  });
}

export function useCategories() {
  return useQuery({
    queryKey: categoriesKey,
    queryFn: async () =>
      unwrapList<Category>(await api.GET("/categories", { params: { query: { per_page: 100 } } })),
  });
}

export function useProducts(page: number, filters: ProductFilters = {}) {
  return useQuery({
    queryKey: productsKey(page, filters),
    queryFn: async () =>
      unwrapList<Product>(
        await api.GET("/products", {
          params: {
            query: {
              page,
              category_id: filters.categoryId,
              active: filters.active,
              q: filters.q,
            },
          },
        }),
      ),
    placeholderData: keepPreviousData,
  });
}

export function useProduct(id: number) {
  return useQuery({
    queryKey: productKey(id),
    queryFn: async () => unwrap(await api.GET("/products/{id}", { params: { path: { id } } })),
  });
}

export function useCreateProduct() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (input: ProductInput) =>
      unwrap(
        await api.POST("/products", {
          body: requestBody(input),
          params: { header: csrfHeader() },
        }),
      ),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["catalog", "products"] });
    },
  });
}

export function useUpdateProduct() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ id, active, ...input }: ProductInput & { id: number; active: boolean }) =>
      unwrap(
        await api.PATCH("/products/{id}", {
          params: { path: { id }, header: csrfHeader() },
          body: { ...requestBody(input), active },
        }),
      ),
    onSuccess: (product: Product) => {
      queryClient.setQueryData(productKey(product.id), product);
      void queryClient.invalidateQueries({ queryKey: ["catalog", "products"] });
    },
  });
}

function partnerRequestBody(input: PartnerInput) {
  return {
    name: input.name,
    document_type: input.documentType,
    document_number: input.documentNumber,
    customer: input.customer,
    supplier: input.supplier,
    email: input.email.trim() || undefined,
    phone: input.phone.trim() || undefined,
  };
}

export function usePartners(page: number, filters: PartnerFilters = {}) {
  return useQuery({
    queryKey: partnersKey(page, filters),
    queryFn: async () =>
      unwrapList<Partner>(
        await api.GET("/partners", {
          params: {
            query: {
              page,
              customer: filters.customer,
              supplier: filters.supplier,
              active: filters.active,
              q: filters.q,
            },
          },
        }),
      ),
    placeholderData: keepPreviousData,
  });
}

export function usePartner(id: number) {
  return useQuery({
    queryKey: partnerKey(id),
    queryFn: async () => unwrap(await api.GET("/partners/{id}", { params: { path: { id } } })),
  });
}

export function useCreatePartner() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (input: PartnerInput) =>
      unwrap(
        await api.POST("/partners", {
          body: partnerRequestBody(input),
          params: { header: csrfHeader() },
        }),
      ),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["catalog", "partners"] });
    },
  });
}

export function useUpdatePartner() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ id, active, ...input }: PartnerInput & { id: number; active: boolean }) =>
      unwrap(
        await api.PATCH("/partners/{id}", {
          params: { path: { id }, header: csrfHeader() },
          body: { ...partnerRequestBody(input), active },
        }),
      ),
    onSuccess: (partner: Partner) => {
      queryClient.setQueryData(partnerKey(partner.id), partner);
      void queryClient.invalidateQueries({ queryKey: ["catalog", "partners"] });
    },
  });
}

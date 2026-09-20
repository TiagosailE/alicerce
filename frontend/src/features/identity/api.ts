import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api, csrfHeader, setCsrfToken, unwrap, unwrapEmpty, unwrapList } from "../../api/client";
import type { components } from "../../api/schema";

export type SessionData = components["schemas"]["SessionData"];
export type Membership = components["schemas"]["Membership"];
export type Member = components["schemas"]["Member"];
export type PendingInvitation = components["schemas"]["PendingInvitation"];
export type Role = Membership["role"];

const sessionKey = ["identity", "session"] as const;
const membersKey = (page: number) => ["identity", "members", { page }] as const;
const invitationsKey = (page: number) => ["identity", "invitations", { page }] as const;

async function fetchSession(): Promise<SessionData> {
  const data = unwrap(await api.GET("/session"));
  setCsrfToken(data.csrf_token);
  return data;
}

export function useSession() {
  return useQuery({ queryKey: sessionKey, queryFn: fetchSession, staleTime: Infinity });
}

export function useSignIn() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (body: { email: string; password: string; organization_id?: number }) => {
      const data = unwrap(await api.POST("/session", { body, params: { header: csrfHeader() } }));
      setCsrfToken(data.csrf_token);
      return data;
    },
    onSuccess: (data) => queryClient.setQueryData(sessionKey, data),
  });
}

export function useSignOut() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async () => {
      const data = unwrap(await api.DELETE("/session", { params: { header: csrfHeader() } }));
      setCsrfToken(data.csrf_token);
      return data;
    },
    onSuccess: (data) => queryClient.setQueryData(sessionKey, data),
  });
}

export function useMembers(page: number) {
  return useQuery({
    queryKey: membersKey(page),
    queryFn: async () =>
      unwrapList<Member>(await api.GET("/memberships", { params: { query: { page } } })),
    // Keeps the current page's rows on screen while the next page loads,
    // instead of the whole table vanishing behind a spinner on every turn.
    placeholderData: keepPreviousData,
  });
}

export function usePendingInvitations(page: number) {
  return useQuery({
    queryKey: invitationsKey(page),
    queryFn: async () =>
      unwrapList<PendingInvitation>(await api.GET("/invitations", { params: { query: { page } } })),
    placeholderData: keepPreviousData,
  });
}

export function useInviteMember() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (body: { email: string; role: Role }) =>
      unwrap(await api.POST("/invitations", { body, params: { header: csrfHeader() } })),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["identity", "invitations"] });
    },
  });
}

export function useRevokeInvitation() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (id: number) => {
      unwrapEmpty(
        await api.DELETE("/invitations/{id}", { params: { path: { id }, header: csrfHeader() } }),
      );
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["identity", "invitations"] });
    },
  });
}

export function useChangeMemberRole() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ id, role }: { id: number; role: Role }) =>
      unwrap(
        await api.PATCH("/memberships/{id}", {
          params: { path: { id }, header: csrfHeader() },
          body: { role },
        }),
      ),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["identity", "members"] });
    },
  });
}

export function useRemoveMember() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (id: number) => {
      unwrapEmpty(
        await api.DELETE("/memberships/{id}", { params: { path: { id }, header: csrfHeader() } }),
      );
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["identity", "members"] });
    },
  });
}

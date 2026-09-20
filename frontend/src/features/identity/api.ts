import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api, csrfHeader, setCsrfToken, unwrap } from "../../api/client";
import type { components } from "../../api/schema";

export type SessionData = components["schemas"]["SessionData"];
export type Membership = components["schemas"]["Membership"];

const sessionKey = ["identity", "session"] as const;

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

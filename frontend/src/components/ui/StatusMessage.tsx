import { useState } from "react";
import { requestIdSuffix } from "../../lib/errors";

type ActionStatus = { kind: "success" | "error"; text: string } | null;

/** A success/error line for an action a screen triggers (create, update,
 * remove...): cleared whenever a new action starts, so it never outlives
 * the attempt it describes or hides behind an unrelated one. */
export function useActionStatus() {
  const [status, setStatus] = useState<ActionStatus>(null);

  return {
    status,
    clear: () => {
      setStatus(null);
    },
    succeed: (text: string) => {
      setStatus({ kind: "success", text });
    },
    fail: (message: string, error: unknown) => {
      setStatus({ kind: "error", text: `${message}${requestIdSuffix(error)}` });
    },
  };
}

export function StatusMessage({ status }: { status: ActionStatus }) {
  if (!status) return null;

  return (
    <p
      role={status.kind === "error" ? "alert" : "status"}
      className={`mb-2 text-sm ${status.kind === "error" ? "text-danger" : "text-success"}`}
    >
      {status.text}
    </p>
  );
}

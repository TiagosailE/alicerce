import { useEffect, useRef, useState } from "react";
import { requestIdSuffix } from "../../lib/errors";

type ActionStatus = { kind: "success" | "error"; text: string } | null;

/** A success/error line for an action a screen triggers (create, update,
 * remove...): cleared whenever a new action starts, so it never outlives
 * the attempt it describes or hides behind an unrelated one. A screen can
 * start with a message already showing (a save that navigated here). */
export function useActionStatus(initial: ActionStatus = null) {
  const [status, setStatus] = useState<ActionStatus>(initial);

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

/** With focusOnShow the message takes focus when it appears: the button that
 * caused it may have unmounted (an approval removes its own button), and a
 * message inserted with its text already in it is announced unreliably, while
 * a focused one is always read. */
export function StatusMessage({
  status,
  focusOnShow = false,
}: {
  status: ActionStatus;
  focusOnShow?: boolean;
}) {
  const ref = useRef<HTMLParagraphElement>(null);

  useEffect(() => {
    if (focusOnShow && status) ref.current?.focus();
  }, [focusOnShow, status]);

  if (!status) return null;

  return (
    <p
      ref={ref}
      tabIndex={focusOnShow ? -1 : undefined}
      role={status.kind === "error" ? "alert" : "status"}
      className={`mb-2 text-sm focus-visible:outline-2 focus-visible:outline-focus ${status.kind === "error" ? "text-danger" : "text-success"}`}
    >
      {status.text}
    </p>
  );
}

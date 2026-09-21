import { Spinner } from "./Spinner";

export function SectionLoading({ label }: { label: string }) {
  return (
    <div role="status" className="flex items-center gap-2 py-4 text-sm text-text-muted">
      <Spinner />
      {label}
    </div>
  );
}

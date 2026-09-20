/** The hatched brick square from the visual proposal: same motif as the quantity ruler. */
export function BrandMark({ className = "" }: { className?: string }) {
  return (
    <span
      aria-hidden="true"
      className={`inline-block h-4.5 w-4.5 rounded-[2px] border-2 border-accent bg-[repeating-linear-gradient(135deg,var(--accent)_0,var(--accent)_1.5px,transparent_1.5px,transparent_4.5px)] ${className}`}
    />
  );
}

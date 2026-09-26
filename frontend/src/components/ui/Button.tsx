import { type ButtonHTMLAttributes, forwardRef } from "react";

type Variant = "primary" | "default" | "quiet";

const base =
  "inline-flex h-8 items-center justify-center gap-2 whitespace-nowrap rounded-md px-3 text-sm font-medium disabled:cursor-not-allowed disabled:opacity-45";

const variants: Record<Variant, string> = {
  default:
    "border border-border-strong bg-surface-raised hover:bg-row-hover active:bg-row-selected",
  primary:
    "border border-accent bg-accent text-accent-contrast hover:border-accent-hover hover:bg-accent-hover active:border-accent-hover active:bg-accent-hover",
  quiet: "border border-transparent bg-transparent hover:bg-row-hover active:bg-row-selected",
};

/** The look of a button, for a link that navigates: it stays a link (middle
 * click, copy address, announced as a link) and only looks like the action. */
export function buttonClass(variant: Variant = "default", className = ""): string {
  return `${base} ${variants[variant]} ${className}`;
}

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant };

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { variant = "default", className = "", type = "button", ...props },
  ref,
) {
  return <button ref={ref} type={type} className={buttonClass(variant, className)} {...props} />;
});

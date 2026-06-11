"use client";

import type { ButtonHTMLAttributes, ReactNode } from "react";

import { cn } from "@/lib/cn";

type Variant =
  | "primary"
  | "secondary"
  | "ghost"
  | "accent"
  | "danger"
  | "danger-ghost";

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: "md" | "sm" | "icon";
  children?: ReactNode;
}

/** admin.css `.btn` — exact paddings/colors per the hi-fi sheet; default size keeps the
 * 44px min touch target (spec), `sm` is the desktop-dense `.btn.sm`. */
const VARIANTS: Record<Variant, string> = {
  primary: "bg-brand-int text-white hover:bg-brand-int-hover",
  secondary:
    "bg-surface text-text-strong border-border-strong hover:bg-sunken",
  ghost: "bg-transparent text-brand-int hover:bg-sunken",
  accent: "bg-accent text-on-amber hover:bg-accent-hover",
  danger: "bg-danger text-white hover:opacity-90",
  "danger-ghost": "bg-transparent text-danger border-danger/35",
};

export function Button({
  variant = "primary",
  size = "md",
  className,
  type = "button",
  ...props
}: ButtonProps) {
  return (
    <button
      type={type}
      className={cn(
        "inline-flex cursor-pointer items-center justify-center gap-[7px] whitespace-nowrap rounded-md border border-transparent font-semibold transition-[background,transform] duration-150 active:translate-y-px disabled:pointer-events-none disabled:opacity-50",
        size === "md" && "min-h-11 px-4 py-2.5 text-sm",
        size === "sm" && "px-3 py-[7px] text-[13px]",
        size === "icon" && "size-9 p-2",
        VARIANTS[variant],
        className,
      )}
      {...props}
    />
  );
}

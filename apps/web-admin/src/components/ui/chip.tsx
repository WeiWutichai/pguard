"use client";

import type { ButtonHTMLAttributes } from "react";

import { cn } from "@/lib/cn";

export interface ChipProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  active?: boolean;
  /** Optional leading 7px dot (admin.css `.chip-f .d`), colored via className. */
  dot?: string;
}

/** admin.css `.chip-f` — filter pill; active = solid green-900 (dark: brand-int with the
 * dark on-brand ink), exactly the sheet's `.chip-f.on` + its dark override. */
export function Chip({ active, dot, className, children, ...props }: ChipProps) {
  return (
    <button
      type="button"
      aria-pressed={active || undefined}
      className={cn(
        "inline-flex cursor-pointer items-center gap-[7px] rounded-full border px-[13px] py-[7px] text-[13px] font-medium transition-colors duration-150",
        active
          ? "border-green-900 bg-green-900 text-white dark:border-brand-int dark:bg-brand-int dark:text-on-brand"
          : "border-border bg-surface text-muted hover:bg-sunken",
        className,
      )}
      {...props}
    >
      {dot ? <span className={cn("size-[7px] rounded-full", dot)} /> : null}
      {children}
    </button>
  );
}

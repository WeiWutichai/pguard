"use client";

import type { ButtonHTMLAttributes, ReactNode } from "react";

import { cn } from "@/lib/cn";

/** admin.css `.tabs` — the underline row; children are [Tab]s. */
export function Tabs({ className, children }: { className?: string; children: ReactNode }) {
  return (
    <div role="tablist" className={cn("mb-5 flex gap-1 border-b border-border", className)}>
      {children}
    </div>
  );
}

export interface TabProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  active?: boolean;
  /** Mono counter pill (admin.css `.tab .pill`); active pill = green-50 / brand-int
   * (dark: brand-int @ 15% — the sheet's rgba(47,192,137,.15)). */
  count?: ReactNode;
}

export function Tab({ active, count, className, children, ...props }: TabProps) {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={active || undefined}
      className={cn(
        "-mb-px flex cursor-pointer items-center gap-2 border-b-2 px-4 py-[11px] text-sm font-semibold transition-colors duration-150",
        active
          ? "border-brand-int text-brand-int"
          : "border-transparent text-muted hover:text-text",
        className,
      )}
      {...props}
    >
      {children}
      {count !== undefined ? (
        <span
          className={cn(
            "rounded-full px-[7px] py-px font-mono text-[11px]",
            active
              ? "bg-green-50 text-brand-int dark:bg-brand-int/15"
              : "bg-sunken text-muted",
          )}
        >
          {count}
        </span>
      ) : null}
    </button>
  );
}

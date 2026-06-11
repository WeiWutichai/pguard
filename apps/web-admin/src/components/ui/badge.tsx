import type { HTMLAttributes } from "react";

import { cn } from "@/lib/cn";

export type BadgeTone = "green" | "amber" | "red" | "blue" | "gray";

/** admin.css `.bdg` — 11.5px pill; tones map to the semantic bg/fg token pairs (amber's
 * dark-mode fg lifts to amber-300 exactly as the sheet does). */
const TONES: Record<BadgeTone, string> = {
  green: "bg-success-bg text-success",
  amber: "bg-warning-bg text-amber-700 dark:text-amber-300",
  red: "bg-danger-bg text-danger",
  blue: "bg-info-bg text-info",
  gray: "bg-sunken text-muted",
};

export interface BadgeProps extends HTMLAttributes<HTMLSpanElement> {
  tone?: BadgeTone;
  /** Leading 7px status dot (admin.css `.bdg .d`), colored via className e.g. bg-status-active. */
  dot?: string;
}

export function Badge({ tone = "gray", dot, className, children, ...props }: BadgeProps) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 py-1 font-latin text-[11.5px] font-semibold tracking-[0.01em]",
        TONES[tone],
        className,
      )}
      {...props}
    >
      {dot ? <span className={cn("size-[7px] rounded-full", dot)} /> : null}
      {children}
    </span>
  );
}

import type { ReactNode } from "react";

import { cn } from "@/lib/cn";

/** admin.css `.kpi-grid` — hairline-structured 4-up strip (one bordered container,
 * cells separated by border-left, 2-up under 1100px with a top hairline). */
export function KpiGrid({ className, children }: { className?: string; children: ReactNode }) {
  return (
    <div
      className={cn(
        // admin.css breaks at max-width:1100px INCLUSIVE → 4-up only from 1101px.
        "mb-6 grid grid-cols-2 overflow-hidden rounded-lg border border-border bg-surface min-[1101px]:grid-cols-4",
        className,
      )}
    >
      {children}
    </div>
  );
}

export interface KpiCardProps {
  icon?: ReactNode;
  label: ReactNode;
  value: ReactNode;
  caption?: ReactNode;
  delta?: ReactNode;
  deltaDirection?: "up" | "down";
  className?: string;
}

/** admin.css `.kpi` — number-led editorial cell: 12px uppercase inline label, mono 30px
 * value with tabular numerals, muted 13px caption, mono delta colored by direction. */
export function KpiCard({
  icon,
  label,
  value,
  caption,
  delta,
  deltaDirection = "up",
  className,
}: KpiCardProps) {
  return (
    <div
      className={cn(
        "border-l border-border px-5 py-[18px] first:border-l-0 max-[1100px]:nth-[3]:border-l-0 max-[1100px]:nth-[n+3]:border-t",
        className,
      )}
    >
      <div className="flex items-center gap-2">
        {icon ? <span className="flex size-[22px] items-center justify-center text-faint [&_svg]:size-4">{icon}</span> : null}
        <span className="text-xs font-semibold uppercase tracking-[0.04em] text-faint">
          {label}
        </span>
        {delta !== undefined ? (
          <span
            className={cn(
              "ml-auto font-mono text-xs font-semibold",
              deltaDirection === "up" ? "text-success" : "text-danger",
            )}
          >
            {delta}
          </span>
        ) : null}
      </div>
      <div className="mb-[3px] mt-4 font-mono text-[30px] font-semibold tracking-[-0.02em] text-text-strong tabular-nums">
        {value}
      </div>
      {caption ? <div className="text-[13px] text-muted">{caption}</div> : null}
    </div>
  );
}

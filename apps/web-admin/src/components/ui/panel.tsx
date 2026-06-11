import type { ReactNode } from "react";

import { cn } from "@/lib/cn";

/** admin.css `.panel` — hairline-bordered surface card (structure from borders, not glow). */
export function Panel({ className, children }: { className?: string; children: ReactNode }) {
  return (
    <section className={cn("rounded-lg border border-border bg-surface", className)}>
      {children}
    </section>
  );
}

/** admin.css `.panel-head` — 16×20 padded header row with a bottom hairline. */
export function PanelHead({
  title,
  sub,
  className,
  children,
}: {
  title: ReactNode;
  sub?: ReactNode;
  className?: string;
  /** Right-side actions (buttons/filters), pushed to the end. */
  children?: ReactNode;
}) {
  return (
    <header className={cn("flex items-center gap-3 border-b border-border px-5 py-4", className)}>
      <div className="min-w-0">
        <h3 className="text-base font-semibold text-text-strong">{title}</h3>
        {sub ? <p className="text-[12.5px] text-muted">{sub}</p> : null}
      </div>
      {children ? <div className="ml-auto flex items-center gap-2.5">{children}</div> : null}
    </header>
  );
}

/** admin.css `.panel-body` — 18×20 padding. */
export function PanelBody({ className, children }: { className?: string; children: ReactNode }) {
  return <div className={cn("px-5 py-[18px]", className)}>{children}</div>;
}

import type { ReactNode } from "react";

import { cn } from "@/lib/cn";

/** admin.css `.page-intro` — 23px/600 content heading + 14px muted lead, 22px bottom gap. */
export function PageIntro({
  title,
  lead,
  className,
  children,
}: {
  title: ReactNode;
  lead?: ReactNode;
  className?: string;
  /** Right-side actions (refresh button, primary CTA), pushed to the end. */
  children?: ReactNode;
}) {
  return (
    <div className={cn("mb-[22px] flex items-start gap-3", className)}>
      <div className="min-w-0">
        <h2 className="mb-[5px] text-[23px] font-semibold tracking-[-0.01em] text-text-strong">
          {title}
        </h2>
        {lead ? <p className="text-sm text-muted">{lead}</p> : null}
      </div>
      {children ? <div className="ml-auto flex flex-none items-center gap-2.5">{children}</div> : null}
    </div>
  );
}

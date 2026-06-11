"use client";

import { cn } from "@/lib/cn";

export interface PaginationProps {
  page: number;
  pageCount: number;
  onPage: (page: number) => void;
  /** Left-side summary, e.g. "1–20 จาก 384" (i18n-agnostic — caller provides). */
  summary?: React.ReactNode;
  className?: string;
}

/** admin.css `.pagination` — summary left, 32px page squares right; active page = solid
 * green-900 (dark: brand-int + ink), sitting above a top hairline. */
export function Pagination({ page, pageCount, onPage, summary, className }: PaginationProps) {
  if (pageCount <= 1 && !summary) return null;

  // Compact window: first, last, current ±1 (ellipsis between gaps).
  const pages: (number | "…")[] = [];
  for (let p = 1; p <= pageCount; p++) {
    if (p === 1 || p === pageCount || Math.abs(p - page) <= 1) {
      pages.push(p);
    } else if (pages.at(-1) !== "…") {
      pages.push("…");
    }
  }

  return (
    <div
      className={cn(
        "flex items-center justify-between border-t border-border px-5 py-3.5 text-[13px] text-muted",
        className,
      )}
    >
      <span>{summary}</span>
      <div className="flex gap-[5px]">
        {pages.map((p, i) =>
          p === "…" ? (
            <span key={`e${i}`} className="flex size-8 items-center justify-center">
              …
            </span>
          ) : (
            <button
              key={p}
              type="button"
              aria-current={p === page ? "page" : undefined}
              onClick={() => onPage(p)}
              className={cn(
                "flex size-8 cursor-pointer items-center justify-center rounded-md border text-[13px]",
                p === page
                  ? "border-green-900 bg-green-900 text-white dark:border-brand-int dark:bg-brand-int dark:text-on-brand"
                  : "border-border bg-surface hover:bg-sunken",
              )}
            >
              {p}
            </button>
          ),
        )}
      </div>
    </div>
  );
}

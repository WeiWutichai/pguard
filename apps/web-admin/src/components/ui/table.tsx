import type {
  HTMLAttributes,
  TdHTMLAttributes,
  ThHTMLAttributes,
} from "react";

import { cn } from "@/lib/cn";

/** admin.css `table.tbl` wrapped in `.table-wrap` (horizontal overflow guard). */
export function Table({ className, children, ...props }: HTMLAttributes<HTMLTableElement>) {
  return (
    <div className="overflow-x-auto">
      <table className={cn("w-full border-collapse", className)} {...props}>
        {children}
      </table>
    </div>
  );
}

/** admin.css `.tbl th` — 11.5px uppercase tracked header above a hairline. */
export function Th({ className, ...props }: ThHTMLAttributes<HTMLTableCellElement>) {
  return (
    <th
      className={cn(
        "whitespace-nowrap border-b border-border px-4 py-3 text-left text-[11.5px] font-semibold uppercase tracking-[0.04em] text-faint",
        className,
      )}
      {...props}
    />
  );
}

/** admin.css `.tbl td` — 14×16 cells; pair with [Tr] for the hover-sunken row. */
export function Td({ className, ...props }: TdHTMLAttributes<HTMLTableCellElement>) {
  return (
    <td
      className={cn(
        "border-b border-border px-4 py-3.5 align-middle text-sm text-text",
        className,
      )}
      {...props}
    />
  );
}

/** admin.css `.tbl tbody tr` — clickable row, sunken on hover, last row borderless. */
export function Tr({ className, ...props }: HTMLAttributes<HTMLTableRowElement>) {
  return (
    <tr
      className={cn(
        "cursor-pointer hover:bg-sunken last:[&>td]:border-b-0",
        className,
      )}
      {...props}
    />
  );
}

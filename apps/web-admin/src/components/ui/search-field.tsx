"use client";

import type { InputHTMLAttributes } from "react";
import { Search } from "lucide-react";

import { cn } from "@/lib/cn";

export interface SearchFieldProps
  extends Omit<InputHTMLAttributes<HTMLInputElement>, "size"> {
  /** admin.css has two widths: `.search` (topbar, 260px) and `.search-sm` (filters, 220px). */
  size?: "md" | "sm";
  className?: string;
}

/** admin.css `.search` / `.search-sm` — sunken pill with a leading search glyph. */
export function SearchField({ size = "md", className, ...props }: SearchFieldProps) {
  return (
    <label
      className={cn(
        "flex items-center rounded-md border border-border text-faint",
        size === "md" && "w-[260px] gap-[9px] bg-sunken px-[13px] py-2",
        size === "sm" && "w-[220px] gap-2 bg-surface px-3 py-[7px]",
        className,
      )}
    >
      <Search size={16} className="flex-none" />
      <input
        type="search"
        className={cn(
          "w-full border-0 bg-transparent font-sans text-text-strong outline-none placeholder:text-faint",
          size === "md" ? "text-sm" : "text-[13.5px]",
        )}
        {...props}
      />
    </label>
  );
}

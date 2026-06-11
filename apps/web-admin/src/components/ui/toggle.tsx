"use client";

import { cn } from "@/lib/cn";

export interface ToggleProps {
  checked: boolean;
  onChange: (next: boolean) => void;
  disabled?: boolean;
  "aria-label"?: string;
  className?: string;
}

/** admin.css `.tgl` — 44×26 switch, n-300 off / brand-int on, 20px travelling knob. */
export function Toggle({ checked, onChange, disabled, className, ...aria }: ToggleProps) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={aria["aria-label"]}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={cn(
        "relative h-[26px] w-11 flex-none cursor-pointer rounded-full transition-colors duration-200 disabled:cursor-not-allowed disabled:opacity-50",
        checked ? "bg-brand-int" : "bg-n-300",
        className,
      )}
    >
      <span
        className={cn(
          "absolute top-[3px] size-5 rounded-full bg-white shadow-xs transition-[left] duration-200",
          checked ? "left-[21px]" : "left-[3px]",
        )}
      />
    </button>
  );
}

"use client";

import { useId } from "react";

/** The pguard mark (admin-shell.js MARK): shield + location pin on the brand gradient.
 * Gradient stops ride the tokens (brand-int → brand) so even the artwork has no raw hex;
 * the gradient id is per-instance (useId) so two marks on one page stay valid HTML. */
export function PgMark({ size = 28 }: { size?: number }) {
  const id = useId();
  return (
    <svg width={size} height={size * 1.04} viewBox="0 0 100 106" fill="none" aria-hidden>
      <defs>
        <linearGradient id={id} x1="50" y1="4" x2="50" y2="106" gradientUnits="userSpaceOnUse">
          <stop stopColor="var(--brand-int)" />
          <stop offset="1" stopColor="var(--brand)" />
        </linearGradient>
      </defs>
      <path
        d="M50 4 L88 18 V50 C88 78 72 95 50 104 C28 95 12 78 12 50 V18 Z"
        fill={`url(#${id})`}
      />
      <path
        d="M50 30 C41 30 34 37 34 46 C34 58 50 74 50 74 C50 74 66 58 66 46 C66 37 59 30 50 30 Z"
        fill="var(--n-0)"
      />
      <circle cx="50" cy="46" r="7.5" fill="var(--brand-int)" />
    </svg>
  );
}

/** admin.css `.side-top .wm` — 21px bold wordmark, the leading “p” in interactive green. */
export function PgWordmark() {
  return (
    <span className="font-latin text-[21px] font-bold tracking-[-0.03em] text-text-strong">
      <span className="text-brand-int">p</span>guard
    </span>
  );
}

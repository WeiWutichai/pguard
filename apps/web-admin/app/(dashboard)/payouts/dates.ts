/**
 * Date rendering for the SCB bank-file screens — the batch history's two date columns.
 *
 * Lives beside `money.ts` and `download-name.ts`, which are likewise imported by BOTH money streams
 * (guard payouts here, customer refunds in `../refunds`). The two histories render the same two
 * columns off the same contract fields, so one copy of the rules keeps them from drifting — a value
 * date that reads as the 4th on one screen and the 5th on the other is the kind of disagreement an
 * operator has no way to resolve.
 */

import type { Lang } from "@/lib/lang";

/**
 * Format a bare `YYYY-MM-DD` (the SCB value date) as a calendar day.
 *
 * Parsed with an explicit `T00:00:00` = LOCAL midnight: `new Date("2026-09-05")` is UTC midnight,
 * which renders as the 4th for any admin west of Greenwich. The value date is a Bangkok banking day,
 * not an instant, and showing the wrong one on the row that says when the money lands is not a
 * rounding error. An unparseable value falls back to the raw string rather than "Invalid Date".
 */
export function fmtDay(day: string, lang: Lang): string {
  const d = new Date(`${day}T00:00:00`);
  if (Number.isNaN(d.getTime())) return day;
  return d.toLocaleDateString(lang === "th" ? "th-TH" : "en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

/** Format an RFC3339 instant (`created_at`) as day + clock in the admin's own timezone. */
export function fmtInstant(iso: string, lang: Lang): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString(lang === "th" ? "th-TH" : "en-GB", {
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

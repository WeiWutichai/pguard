/** Admin list endpoints are repo-capped (200 rows) — a raw `length` of exactly the cap
 * very likely UNDERSTATES the true total. Render it as "200+" so counts stay honest. */
export const ADMIN_LIST_CAP = 200;

export function fmtCappedCount(n: number | null | undefined): string {
  if (n == null) return "—";
  return n >= ADMIN_LIST_CAP ? `${ADMIN_LIST_CAP}+` : String(n);
}

/** Money formatter for the exact-decimal STRING money fields from the API ("12400.00") — whole
 * baht with thousands separators ("฿12,400"). Returns "฿0" for null/blank/non-finite. */
export function fmtBaht(decimalStr: string | number | null | undefined): string {
  const n = typeof decimalStr === "number" ? decimalStr : parseFloat(decimalStr ?? "0");
  if (!Number.isFinite(n)) return "฿0";
  return `฿${Math.round(n).toLocaleString("en-US")}`;
}

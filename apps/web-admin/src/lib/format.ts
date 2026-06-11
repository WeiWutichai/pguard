/** Admin list endpoints are repo-capped (200 rows) — a raw `length` of exactly the cap
 * very likely UNDERSTATES the true total. Render it as "200+" so counts stay honest. */
export const ADMIN_LIST_CAP = 200;

export function fmtCappedCount(n: number | null | undefined): string {
  if (n == null) return "—";
  return n >= ADMIN_LIST_CAP ? `${ADMIN_LIST_CAP}+` : String(n);
}

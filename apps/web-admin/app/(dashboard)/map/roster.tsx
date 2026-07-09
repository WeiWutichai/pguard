"use client";

// Design §5 "Roster panel" — 320px right rail: header (count), status filter chips,
// scrollable guard card list (avatar + status dot · status/accuracy meta · last-update).
// The design's per-card rating · jobs · distance/ETA need profile/booking/geo endpoints
// that don't exist in v2 yet — cards show only real presence fields (status, GPS accuracy,
// last update) instead of fake numbers; the missing stats are gap-chipped in the detail card.
import { Loader2 } from "lucide-react";
import { useMemo } from "react";

import type { GuardStatus, MapGuard } from "@/components/guard-map";
import { Avatar, Chip } from "@/components/ui";
import { useLanguage } from "@/lib/i18n";
import { useNameResolver } from "@/lib/use-names";
import { cn } from "@/lib/cn";
import {
  AVATAR_STATUS,
  COPY,
  STATUS_DOT,
  STATUS_LABEL_KEY,
  STATUS_ORDER,
  STATUS_TEXT,
  formatAgoShort,
  initials,
  shortId,
} from "./copy";

export type StatusFilter = "all" | GuardStatus;

export function RosterPanel({
  guards,
  counts,
  total,
  loading,
  filter,
  onFilter,
  selectedId,
  onSelect,
}: {
  /** Search + status-filtered list, freshest update first. */
  guards: MapGuard[];
  /** Counts over the full fetched dataset (filter chips show totals, not filtered counts). */
  counts: Record<GuardStatus, number>;
  total: number;
  loading: boolean;
  filter: StatusFilter;
  onFilter: (next: StatusFilter) => void;
  selectedId: string | null;
  onSelect: (id: string) => void;
}) {
  const { t, lang } = useLanguage();
  const c = COPY[lang];
  // Resolve the online guards' ids to real display names (the panel showed raw UUID slices).
  const guardIds = useMemo(() => guards.map((g) => g.guard_id), [guards]);
  const { resolve } = useNameResolver(guardIds, lang);

  return (
    <aside className="flex w-80 flex-none flex-col border-l border-border bg-surface">
      {/* Roster header (design `.roster-head`). */}
      <div className="px-[18px] pb-3 pt-[18px]">
        <h3 className="text-base font-semibold text-text-strong">{c.rosterTitle}</h3>
        <p className="mt-[3px] text-[12.5px] text-muted">{c.inArea(total)}</p>
      </div>

      {/* Filter chips (design `.filter-tabs`) — counts always reflect the whole dataset. */}
      <div className="flex flex-wrap gap-1.5 px-[18px] pb-3">
        <Chip active={filter === "all"} onClick={() => onFilter("all")}>
          {t("common.all")} <b className="font-mono font-semibold">{total}</b>
        </Chip>
        {STATUS_ORDER.map((s) => (
          <Chip key={s} active={filter === s} dot={STATUS_DOT[s]} onClick={() => onFilter(s)}>
            {t(STATUS_LABEL_KEY[s])} <span className="font-mono">{counts[s]}</span>
          </Chip>
        ))}
      </div>

      {/* Guard list (design `.roster-list` / `.gcard`). */}
      <div className="min-h-0 flex-1 overflow-y-auto px-3 pb-4 pt-1">
        {loading ? (
          <div className="flex items-center justify-center gap-2 py-8 text-sm text-muted">
            <Loader2 className="size-4 animate-spin" />
            {t("common.loading")}
          </div>
        ) : guards.length === 0 ? (
          <p className="py-8 text-center text-sm text-muted">{t("map.empty")}</p>
        ) : (
          guards.map((g) => {
            const sel = g.guard_id === selectedId;
            const r = resolve(g.guard_id);
            const name = r.name; // null while the resolver hasn't placed it (unknown / mid-load)
            return (
              <button
                key={g.guard_id}
                type="button"
                onClick={() => onSelect(g.guard_id)}
                aria-pressed={sel}
                className={cn(
                  "flex w-full cursor-pointer items-center gap-3 rounded-md border p-3 text-left transition-colors",
                  sel
                    ? // design `.gcard.sel`: green-50 + green-200; dark = rgba(47,192,137,.1/.3)
                      // — i.e. the dark brand-int token at 10%/30%.
                      "border-green-200 bg-green-50 dark:border-brand-int/30 dark:bg-brand-int/10"
                    : "border-transparent hover:bg-sunken",
                )}
              >
                <Avatar size="lg" status={AVATAR_STATUS[g.status]}>
                  {initials(name ?? g.guard_id)}
                </Avatar>
                <span className="min-w-0 flex-1">
                  <span
                    className={cn(
                      "block truncate text-sm font-semibold text-text-strong",
                      // Real name in the normal face; fall back to the id slice in mono.
                      name ? "" : "font-mono",
                    )}
                  >
                    {name ?? shortId(g.guard_id)}
                  </span>
                  <span className="mt-0.5 flex items-center gap-1.5 text-xs text-muted">
                    <span className={cn("font-semibold", STATUS_TEXT[g.status])}>
                      {t(STATUS_LABEL_KEY[g.status])}
                    </span>
                    {g.accuracy != null && (
                      <>
                        <span aria-hidden>·</span>
                        <span>{c.meters(Math.round(g.accuracy))}</span>
                      </>
                    )}
                  </span>
                </span>
                <span className="flex-none whitespace-nowrap text-right">
                  <span className="block font-mono text-[13px] font-semibold text-text-strong">
                    {formatAgoShort(g.recorded_at, c)}
                  </span>
                  <span className="block text-[10.5px] text-faint">{t("map.lastSeen")}</span>
                </span>
              </button>
            );
          })
        )}
      </div>
    </aside>
  );
}

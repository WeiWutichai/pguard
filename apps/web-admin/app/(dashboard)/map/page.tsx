"use client";

// Live Map (hi-fi spec: Web_Admin_Live_Map) — PageIntro + toolbar (search · online-only),
// map stage with floating status stat-chips (the legend), bottom-left detail card overlay,
// and the 320px online-guards roster rail (filter chips + cards). Data layer is unchanged:
// one `presenceApi.GET /locations` fetch, status derived from the freshness flags, search
// filtering client-side.
import { useCallback, useEffect, useMemo, useState } from "react";
import dynamic from "next/dynamic";
import { AlertTriangle, Loader2, RefreshCw } from "lucide-react";

import type { components } from "@/api/generated/presence";
import type { GuardStatus, MapGuard } from "@/components/guard-map";
import { Button, PageIntro, SearchField, Toggle } from "@/components/ui";
import { presenceApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import { cn } from "@/lib/cn";
import { COPY, STATUS_DOT, STATUS_LABEL_KEY, STATUS_ORDER, formatAgoLong } from "./copy";
import { DetailCard } from "./detail-card";
import { RosterPanel, type StatusFilter } from "./roster";

type GuardLocation = components["schemas"]["GuardLocation"];

// Leaflet map loaded client-only (ssr:false) — it needs `window`. `import type` above is erased,
// so leaflet stays out of the server bundle entirely.
const GuardMap = dynamic(() => import("@/components/guard-map"), {
  ssr: false,
  loading: () => (
    <div className="flex h-full items-center justify-center text-muted">
      <Loader2 className="size-5 animate-spin" />
    </div>
  ),
});

/** 3 statuses derived from the freshness flags: offline (no live session), active (live + fresh),
 *  idle (connected but stale > 5 min, i.e. `is_online && !is_live`). */
function statusOf(loc: GuardLocation): GuardStatus {
  if (!loc.is_online) return "offline";
  return loc.is_live ? "active" : "idle";
}

export default function MapPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];
  const [locations, setLocations] = useState<GuardLocation[]>([]);
  const [onlineOnly, setOnlineOnly] = useState(false);
  const [searchInput, setSearchInput] = useState("");
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);

  // Debounce the guard-id search. This filters CLIENT-SIDE (the `guards` memo below), so it does
  // NOT refetch and intentionally shows no loading spinner — the filter is instant, and flipping
  // `loading` here would stick (the fetch effect doesn't depend on `search`).
  useEffect(() => {
    const id = setTimeout(() => setSearch(searchInput.trim().toLowerCase()), 300);
    return () => clearTimeout(id);
  }, [searchInput]);

  const fetchInto = useCallback(
    (alive: () => boolean) => {
      const query = onlineOnly ? { online_only: true } : {};
      return presenceApi.GET("/locations", { params: { query } }).then(({ data, error }) => {
        if (!alive()) return;
        setHasError(Boolean(error));
        setLocations(error ? [] : (data?.data ?? []));
        setLoading(false);
      });
    },
    [onlineOnly],
  );

  useEffect(() => {
    let alive = true;
    void fetchInto(() => alive);
    return () => {
      alive = false;
    };
  }, [reloadNonce, fetchInto]);

  function reload() {
    setLoading(true);
    setHasError(false);
    setReloadNonce((n) => n + 1);
  }

  // Client-side search filter + status, memoized so the map only re-renders when inputs change.
  const guards = useMemo<MapGuard[]>(
    () =>
      locations
        .filter((l) => (search ? l.guard_id.toLowerCase().includes(search) : true))
        .map((l) => ({ ...l, status: statusOf(l) })),
    [locations, search],
  );

  // Stat-chip / filter-chip counts over the WHOLE fetched dataset (not the search filter).
  const counts = useMemo(() => {
    const acc: Record<GuardStatus, number> = { active: 0, idle: 0, offline: 0 };
    for (const l of locations) acc[statusOf(l)] += 1;
    return acc;
  }, [locations]);

  // Roster list: search + status filter, freshest update first (the design sorts by distance,
  // but no admin-to-guard geo endpoint exists — recency is the honest live-map ordering).
  const rosterGuards = useMemo(
    () =>
      guards
        .filter((g) => statusFilter === "all" || g.status === statusFilter)
        .sort((a, b) => b.recorded_at.localeCompare(a.recorded_at)),
    [guards, statusFilter],
  );

  const latest = useMemo(
    () =>
      locations.reduce<string | null>(
        (acc, l) => (acc === null || l.recorded_at > acc ? l.recorded_at : acc),
        null,
      ),
    [locations],
  );

  const selected = useMemo(
    () => guards.find((g) => g.guard_id === selectedId) ?? null,
    [guards, selectedId],
  );

  return (
    <div>
      <PageIntro
        title={
          lang === "th" ? (
            // Design topbar h1: "แผนที่สด · Live Map" (faint latin suffix).
            <>
              {t("nav.map")} <span className="font-normal text-faint">· Live Map</span>
            </>
          ) : (
            t("nav.map")
          )
        }
        lead={
          latest
            ? `${t("map.subtitle")} · ${t("map.lastSeen")} ${formatAgoLong(latest, c)}`
            : t("map.subtitle")
        }
      >
        <Button variant="secondary" size="sm" onClick={reload}>
          <RefreshCw className="size-4" />
          {t("common.retry")}
        </Button>
      </PageIntro>

      <div className="mb-4 flex flex-wrap items-center gap-4">
        <SearchField
          value={searchInput}
          onChange={(e) => setSearchInput(e.target.value)}
          placeholder={t("map.search")}
          aria-label={t("map.search")}
        />
        <label className="flex cursor-pointer items-center gap-2 text-sm">
          <Toggle
            checked={onlineOnly}
            onChange={(next) => {
              setLoading(true);
              setOnlineOnly(next);
            }}
            aria-label={t("map.onlineOnly")}
          />
          {t("map.onlineOnly")}
        </label>
      </div>

      {hasError && (
        <div
          role="alert"
          className="mb-4 flex items-center gap-2 rounded-md border border-danger/40 bg-danger-bg px-4 py-2 text-sm text-danger"
        >
          <AlertTriangle className="size-4" />
          {t("map.error")}
        </div>
      )}

      {/* Stage + roster (design §4/§5) — map fills the left, 320px guard rail on the right. */}
      <div className="flex h-[68vh] min-h-[480px] overflow-hidden rounded-lg border border-border bg-surface shadow-sm">
        <div className="relative min-w-0 flex-1">
          {loading ? (
            <div className="flex h-full items-center justify-center gap-2 text-muted">
              <Loader2 className="size-5 animate-spin" />
              {t("common.loading")}
            </div>
          ) : (
            <>
              <GuardMap
                guards={guards}
                selectedId={selectedId}
                onSelect={(id) => setSelectedId(id)}
              />

              {/* Floating stat chips (design §4.5) — live counts double as the status legend. */}
              <div className="pointer-events-none absolute left-4 top-4 z-[1000] flex flex-wrap gap-2.5">
                {STATUS_ORDER.map((s) => (
                  <div
                    key={s}
                    className="flex items-center gap-[9px] rounded-md border border-border bg-surface px-3.5 py-[9px] shadow-sm"
                  >
                    <span className={cn("size-[9px] rounded-full", STATUS_DOT[s])} />
                    <span className="font-mono text-base font-semibold text-text-strong">
                      {counts[s]}
                    </span>
                    <span className="whitespace-nowrap text-xs text-muted">
                      {t(STATUS_LABEL_KEY[s])}
                    </span>
                  </div>
                ))}
              </div>

              {selected && (
                <DetailCard guard={selected} onClose={() => setSelectedId(null)} />
              )}
            </>
          )}
        </div>

        <RosterPanel
          guards={rosterGuards}
          counts={counts}
          total={locations.length}
          loading={loading}
          filter={statusFilter}
          onFilter={setStatusFilter}
          selectedId={selectedId}
          onSelect={(id) => setSelectedId((cur) => (cur === id ? null : id))}
        />
      </div>
    </div>
  );
}

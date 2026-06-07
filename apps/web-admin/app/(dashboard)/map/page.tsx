"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import dynamic from "next/dynamic";
import { AlertTriangle, Loader2, RefreshCw, Search } from "lucide-react";

import type { components } from "@/api/generated/presence";
import type { GuardStatus, MapGuard } from "@/components/guard-map";
import { presenceApi } from "@/lib/api";
import { useLanguage, type TKey } from "@/lib/i18n";
import { cn } from "@/lib/cn";

type GuardLocation = components["schemas"]["GuardLocation"];

// Leaflet map loaded client-only (ssr:false) — it needs `window`. `import type` above is erased,
// so leaflet stays out of the server bundle entirely.
const GuardMap = dynamic(() => import("@/components/guard-map"), {
  ssr: false,
  loading: () => (
    <div className="flex h-[62vh] items-center justify-center rounded-xl border border-border bg-surface text-muted">
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

const LEGEND: { status: GuardStatus; color: string; labelKey: TKey }[] = [
  { status: "active", color: "bg-success", labelKey: "map.status.active" },
  { status: "idle", color: "bg-warning", labelKey: "map.status.idle" },
  { status: "offline", color: "bg-muted", labelKey: "map.status.offline" },
];

export default function MapPage() {
  const { t } = useLanguage();
  const [locations, setLocations] = useState<GuardLocation[]>([]);
  const [onlineOnly, setOnlineOnly] = useState(false);
  const [searchInput, setSearchInput] = useState("");
  const [search, setSearch] = useState("");
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

  return (
    <div className="mx-auto max-w-6xl">
      <h1 className="text-2xl font-semibold">{t("map.title")}</h1>
      <p className="mt-1 text-muted">{t("map.subtitle")}</p>

      <div className="mt-5 flex flex-wrap items-center gap-3">
        <div className="relative">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted" />
          <input
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder={t("map.search")}
            className="rounded-lg border border-border bg-surface py-1.5 pl-8 pr-3 text-sm"
          />
        </div>

        <label className="inline-flex cursor-pointer items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={onlineOnly}
            onChange={(e) => {
              setLoading(true);
              setOnlineOnly(e.target.checked);
            }}
            className="size-4 accent-brand"
          />
          {t("map.onlineOnly")}
        </label>

        {/* Legend — the 3 statuses. */}
        <div className="flex items-center gap-3 text-xs text-muted">
          {LEGEND.map((l) => (
            <span key={l.status} className="inline-flex items-center gap-1.5">
              <span className={cn("size-2.5 rounded-full", l.color)} />
              {t(l.labelKey)}
            </span>
          ))}
        </div>

        {!loading && <span className="text-sm text-muted">{guards.length}</span>}

        <button
          type="button"
          onClick={reload}
          className="ml-auto flex items-center gap-1.5 rounded-lg border border-border px-3 py-1.5 text-sm hover:bg-sunken"
        >
          <RefreshCw className="size-4" />
          {t("common.retry")}
        </button>
      </div>

      {hasError && (
        <div
          role="alert"
          className="mt-4 flex items-center gap-2 rounded-lg border border-danger/40 bg-danger/10 px-4 py-2 text-sm text-danger"
        >
          <AlertTriangle className="size-4" />
          {t("map.error")}
        </div>
      )}

      <div className="mt-4">
        {loading ? (
          <div className="flex h-[62vh] items-center justify-center gap-2 rounded-xl border border-border bg-surface text-muted">
            <Loader2 className="size-5 animate-spin" />
            {t("common.loading")}
          </div>
        ) : guards.length === 0 ? (
          <div className="flex h-[62vh] items-center justify-center rounded-xl border border-border bg-surface text-muted">
            {t("map.empty")}
          </div>
        ) : (
          <GuardMap guards={guards} />
        )}
      </div>
    </div>
  );
}

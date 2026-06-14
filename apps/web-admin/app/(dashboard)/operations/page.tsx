"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Activity,
  AlertTriangle,
  Check,
  Clock,
  Loader2,
  MapPin,
  Navigation,
  Radio,
  RefreshCw,
} from "lucide-react";

import type { components as BookingComponents } from "@/api/generated/booking";
import type { components as PresenceComponents } from "@/api/generated/presence";
import {
  Badge,
  Button,
  Chip,
  KpiCard,
  KpiGrid,
  PageIntro,
  Panel,
  SearchField,
} from "@/components/ui";
import { bookingApi, presenceApi, profileApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import { cn } from "@/lib/cn";

import {
  ACTIVE_STATUSES,
  type ActiveStatus,
  COPY,
  type GpsState,
  gpsStateOf,
  relTime,
  TIMELINE,
} from "./copy";
import { OperationDetailModal } from "./operation-detail-modal";

type Booking = BookingComponents["schemas"]["Booking"];
type GuardLocation = PresenceComponents["schemas"]["GuardLocation"];

const GPS_TONE: Record<GpsState, string> = {
  live: "text-success",
  stale: "text-amber-600 dark:text-amber-300",
  offline: "text-muted",
  none: "text-faint",
};

/** Status timeline (accepted → en_route → arrived → pending_completion), current stage lit. */
function Timeline({
  status,
  stageLabel,
}: {
  status: ActiveStatus;
  stageLabel: Record<ActiveStatus, string>;
}) {
  const cur = TIMELINE.indexOf(status);
  return (
    <div className="my-3 flex items-center">
      {TIMELINE.map((stage, i) => {
        const done = i < cur;
        const now = i === cur;
        return (
          <div key={stage} className="relative flex flex-1 flex-col items-center gap-1.5">
            {i < TIMELINE.length - 1 && (
              <span
                className={cn(
                  "absolute left-1/2 top-[9px] h-0.5 w-full",
                  done ? "bg-brand-int" : "bg-border",
                )}
              />
            )}
            <span
              className={cn(
                "z-10 flex size-[18px] items-center justify-center rounded-full border-2",
                done && "border-brand-int bg-brand-int text-white",
                now && "border-amber-500 bg-amber-500 ring-4 ring-amber-500/20",
                !done && !now && "border-border bg-sunken",
              )}
            >
              {done && <Check className="size-2.5" />}
            </span>
            <span
              className={cn(
                "text-[9.5px] font-semibold",
                now ? "text-amber-600 dark:text-amber-300" : "text-muted",
              )}
            >
              {stageLabel[stage]}
            </span>
          </div>
        );
      })}
    </div>
  );
}

export default function OperationsPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [bookings, setBookings] = useState<Booking[]>([]);
  const [locById, setLocById] = useState<Record<string, GuardLocation>>({});
  const [customerNames, setCustomerNames] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);

  const [selected, setSelected] = useState<Booking | null>(null);
  const [statusFilter, setStatusFilter] = useState<ActiveStatus | "all">("all");
  const [query, setQuery] = useState("");

  const fetchInto = useCallback((alive: () => boolean) => {
    // Bookings is authoritative; presence (GPS freshness) + customer names are best-effort
    // enrichment (the board still renders if either degrades).
    return Promise.all([
      bookingApi.GET("/admin/bookings", { params: { query: {} } }),
      presenceApi.GET("/locations", { params: { query: {} } }),
      profileApi.GET("/admin/customer-profiles"),
    ])
      .then(([bRes, lRes, cRes]) => {
        if (!alive()) return;
        setHasError(Boolean(bRes.error));
        setBookings(bRes.error ? [] : (bRes.data?.data ?? []));
        const locs: Record<string, GuardLocation> = {};
        for (const loc of lRes.data?.data ?? []) locs[loc.guard_id] = loc;
        setLocById(locs);
        const names: Record<string, string> = {};
        for (const cust of cRes.data?.data ?? []) {
          if (cust.full_name) names[cust.user_id] = cust.full_name;
        }
        setCustomerNames(names);
        setLoading(false);
      })
      .catch(() => {
        if (!alive()) return;
        setHasError(true);
        setLoading(false);
      });
  }, []);

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

  // Only in-flight bookings belong on the live board.
  const active = useMemo(
    () => bookings.filter((b) => (ACTIVE_STATUSES as readonly string[]).includes(b.status)),
    [bookings],
  );

  const counts = useMemo(() => {
    const by: Record<string, number> = {};
    for (const b of active) by[b.status] = (by[b.status] ?? 0) + 1;
    return by;
  }, [active]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return active.filter((b) => {
      if (statusFilter !== "all" && b.status !== statusFilter) return false;
      if (!q) return true;
      const name = customerNames[b.customer_id] ?? "";
      return [b.id, name, b.address]
        .filter(Boolean)
        .some((v) => String(v).toLowerCase().includes(q));
    });
  }, [active, statusFilter, query, customerNames]);

  return (
    <div>
      <PageIntro
        title={c.title}
        lead={loading || hasError ? t("operations.subtitle") : c.subtitle(String(active.length))}
      >
        <Button variant="secondary" size="sm" onClick={reload}>
          <RefreshCw size={15} />
          {t("common.retry")}
        </Button>
      </PageIntro>

      {hasError && (
        <div
          role="alert"
          className="mb-4 flex items-center gap-2 rounded-lg border border-danger/40 bg-danger-bg px-4 py-2.5 text-sm text-danger"
        >
          <AlertTriangle className="size-4 flex-none" />
          {t("operations.error")}
        </div>
      )}

      <KpiGrid>
        <KpiCard
          icon={<Activity />}
          label={c.kpiActive}
          value={loading ? "…" : String(active.length)}
        />
        <KpiCard
          icon={<Navigation />}
          label={c.kpiEnRoute}
          value={loading ? "…" : String(counts.en_route ?? 0)}
        />
        <KpiCard
          icon={<MapPin />}
          label={c.kpiArrived}
          value={loading ? "…" : String(counts.arrived ?? 0)}
        />
        <KpiCard
          icon={<Clock />}
          label={c.kpiPending}
          value={loading ? "…" : String(counts.pending_completion ?? 0)}
        />
      </KpiGrid>

      <div className="mb-4 flex flex-wrap items-center gap-2.5">
        <Chip active={statusFilter === "all"} onClick={() => setStatusFilter("all")}>
          {t("common.all")}
        </Chip>
        {(["en_route", "arrived", "pending_completion"] as ActiveStatus[]).map((s) => (
          <Chip key={s} active={statusFilter === s} onClick={() => setStatusFilter(s)}>
            {c.statusLabel[s]}
          </Chip>
        ))}
        <SearchField
          size="sm"
          className="ml-auto"
          placeholder={c.searchPlaceholder}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
      </div>

      {loading ? (
        <Panel>
          <div className="flex items-center justify-center gap-2 py-16 text-muted">
            <Loader2 className="size-5 animate-spin" />
            {t("common.loading")}
          </div>
        </Panel>
      ) : filtered.length === 0 ? (
        <Panel>
          <div className="py-16 text-center text-muted">{t("operations.empty")}</div>
        </Panel>
      ) : (
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {filtered.map((b) => {
            const status = b.status as ActiveStatus;
            const loc = b.guard_id ? locById[b.guard_id] : undefined;
            const gps = gpsStateOf(loc);
            return (
              <button
                key={b.id}
                type="button"
                onClick={() => setSelected(b)}
                className="rounded-xl border border-border bg-surface p-4 text-left shadow-xs transition hover:border-border-strong hover:shadow-md"
              >
                <div className="flex items-center gap-3">
                  <div className="relative flex size-[42px] flex-none items-center justify-center rounded-full bg-green-100 font-semibold text-green-800 dark:bg-green-800 dark:text-green-100">
                    {b.guard_id ? b.guard_id.slice(0, 2).toUpperCase() : "—"}
                    <span
                      className={cn(
                        "absolute -bottom-px -right-px size-3 rounded-full border-2 border-surface",
                        gps === "live" && "bg-status-active",
                        gps === "stale" && "bg-amber-500",
                        (gps === "offline" || gps === "none") && "bg-faint",
                      )}
                    />
                  </div>
                  <div className="min-w-0">
                    <div className="truncate font-semibold text-text-strong">
                      {customerNames[b.customer_id] ??
                        `${c.guard} #${b.guard_id?.slice(0, 8) ?? "—"}`}
                    </div>
                    <div className="truncate font-mono text-xs text-muted">
                      #{b.id.slice(0, 8)} ·{" "}
                      {b.guard_id ? `${c.guard} #${b.guard_id.slice(0, 8)}` : "—"}
                    </div>
                  </div>
                  <Badge tone="blue" className="ml-auto flex-none">
                    {c.statusLabel[status]}
                  </Badge>
                </div>

                <Timeline status={status} stageLabel={c.stageLabel} />

                <div className="flex items-center justify-between border-t border-border pt-3">
                  <span className="flex min-w-0 items-center gap-1.5 text-[12.5px] text-muted">
                    <MapPin className="size-3.5 flex-none" />
                    <span className="truncate">{b.address}</span>
                  </span>
                  <span
                    className={cn(
                      "flex flex-none items-center gap-1.5 font-mono text-[11px]",
                      GPS_TONE[gps],
                    )}
                  >
                    <Radio className="size-3" />
                    {gps === "none"
                      ? c.gpsNone
                      : gps === "offline"
                        ? c.gpsOffline
                        : `${gps === "stale" ? c.gpsStale : c.gpsLive} · ${relTime(loc?.recorded_at, lang)}`}
                  </span>
                </div>
              </button>
            );
          })}
        </div>
      )}

      {selected && (
        <OperationDetailModal
          booking={selected}
          heading={
            customerNames[selected.customer_id] ??
            `${c.guard} #${selected.guard_id?.slice(0, 8) ?? "—"}`
          }
          onClose={() => setSelected(null)}
        />
      )}
    </div>
  );
}

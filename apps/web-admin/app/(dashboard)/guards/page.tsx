"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, CircleAlert, CircleCheck, Loader2, RefreshCw, Shield, Star } from "lucide-react";

import type { components as bookingComponents } from "@/api/generated/booking";
import type { components } from "@/api/generated/profile";
import type { components as presenceComponents } from "@/api/generated/presence";
import {
  Avatar,
  Button,
  Chip,
  KpiCard,
  KpiGrid,
  PageIntro,
  Pagination,
  Panel,
  SearchField,
  Table,
  Td,
  Th,
  Tr,
} from "@/components/ui";
import { bookingApi, presenceApi, profileApi, ratingApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import { ADMIN_LIST_CAP, fmtCappedCount } from "@/lib/format";

import { COPY } from "./copy";
import { GuardDetailModal } from "./guard-detail-modal";
import { initialsOf, maskAccount } from "./guard-identity";

type GuardProfile = components["schemas"]["GuardProfile"];
type GuardLocation = presenceComponents["schemas"]["GuardLocation"];
type Booking = bookingComponents["schemas"]["Booking"];

type GuardStatus = "online" | "working" | "offline";
// Live-status dot colors — mirror the filter chips' design dots.
const STATUS_DOT: Record<GuardStatus, string> = {
  online: "bg-status-active",
  working: "bg-status-working",
  offline: "bg-status-offline",
};

// "On a job" = holds an active (assigned, non-terminal) booking — derived from the admin booking
// list, NOT presence. (presence is_online/is_live are connectivity/GPS-freshness, not assignment.)
const ACTIVE_BOOKING_STATUSES = new Set([
  "accepted",
  "en_route",
  "arrived",
  "pending_completion",
]);

/** Design shows 8 rows per page ("1–8 of 384"). Client-side: the admin list endpoint has no
 * pagination params (repo caps it at 200), so paging + search both slice the fetched list. */
const PAGE_SIZE = 8;

export default function GuardsPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];
  const [guards, setGuards] = useState<GuardProfile[]>([]);
  const [loc, setLoc] = useState<GuardLocation[]>([]);
  const [bk, setBk] = useState<Booking[]>([]);
  const [bkCapped, setBkCapped] = useState(false);
  const [avgRating, setAvgRating] = useState<string | null>(null);
  const [docsExpiring, setDocsExpiring] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [selected, setSelected] = useState<GuardProfile | null>(null);
  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<"all" | GuardStatus>("all");
  const [page, setPage] = useState(1);

  // The profile list + the three aggregates the design KPIs/live-status need, in parallel. Each
  // value comes from a real endpoint; a failed sub-call degrades that metric (→ "—") and raises
  // the banner, the rest still render.
  const fetchInto = useCallback((alive: () => boolean) => {
    return Promise.all([
      profileApi.GET("/admin/guard-profiles", {
        params: { query: { approval_status: "approved" } },
      }),
      presenceApi.GET("/locations"),
      ratingApi.GET("/admin/reviews", { params: { query: { limit: 1 } } }),
      profileApi.GET("/admin/documents/expiring"),
      bookingApi.GET("/admin/bookings", { params: { query: { limit: ADMIN_LIST_CAP } } }),
    ]).then(([gp, locs, rev, docs, bookings]) => {
      if (!alive()) return;
      setHasError(
        Boolean(
          gp.error || locs.error || rev.error || docs.error || bookings.error,
        ),
      );
      setGuards(gp.error ? [] : (gp.data?.data ?? []));
      setLoc(locs.error ? [] : (locs.data?.data ?? []));
      setBk(bookings.error ? [] : (bookings.data?.data ?? []));
      setBkCapped(
        !bookings.error && (bookings.data?.data?.length ?? 0) >= ADMIN_LIST_CAP,
      );
      setAvgRating(rev.error ? null : (rev.data?.data?.stats?.average ?? null));
      setDocsExpiring(docs.error ? null : (docs.data?.data?.length ?? 0));
      setLoading(false);
    }).catch(() => {
      // A transport-level failure (gateway down/offline) REJECTS Promise.all — don't get stuck on
      // the spinner; flip loading off + raise the banner (Retry recovers).
      if (alive()) {
        setHasError(true);
        setLoading(false);
      }
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

  // Live status per guard, joined by guard_id (== GuardProfile.user_id): "working" = holds an
  // active booking (booking list), "online" = a presence row reports is_online, else "offline".
  const locMap = useMemo(() => new Map(loc.map((l) => [l.guard_id, l])), [loc]);
  const onJobGuardIds = useMemo(
    () =>
      new Set(
        bk
          .filter((b) => ACTIVE_BOOKING_STATUSES.has(b.status) && b.guard_id)
          .map((b) => b.guard_id as string),
      ),
    [bk],
  );
  const statusOf = useCallback(
    (g: GuardProfile): GuardStatus => {
      if (onJobGuardIds.has(g.user_id)) return "working";
      return locMap.get(g.user_id)?.is_online ? "online" : "offline";
    },
    [onJobGuardIds, locMap],
  );
  const onlineCount = loc.filter((l) => l.is_online).length;

  // Client-side search over the real profile fields + the live-status filter chips.
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return guards.filter((g) => {
      if (statusFilter !== "all" && statusOf(g) !== statusFilter) return false;
      if (!q) return true;
      return [g.user_id, g.account_name, g.previous_workplace, g.bank_name]
        .filter((v): v is string => Boolean(v))
        .some((v) => v.toLowerCase().includes(q));
    });
  }, [guards, query, statusFilter, statusOf]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, pageCount);
  const visible = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);
  const summaryStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const summaryEnd = Math.min(safePage * PAGE_SIZE, filtered.length);

  return (
    <div>
      <PageIntro
        title={c.title}
        lead={loading || hasError ? t("guards.subtitle") : c.subtitle(fmtCappedCount(guards.length))}
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
          {t("guards.error")}
        </div>
      )}

      <KpiGrid>
        <KpiCard
          icon={<CircleCheck />}
          label={c.kpiOnline}
          value={loading ? "—" : String(onlineCount)}
        />
        <KpiCard
          icon={<Shield />}
          label={c.kpiOnJob}
          value={
            loading ? "—" : `${onJobGuardIds.size}${bkCapped ? "+" : ""}`
          }
        />
        <KpiCard icon={<Star />} label={c.kpiAvgRating} value={avgRating ?? "—"} />
        <KpiCard
          icon={<CircleAlert />}
          label={c.kpiDocsExpiring}
          value={fmtCappedCount(docsExpiring)}
        />
      </KpiGrid>

      {/* Filters row — live-status chips driven by presence (joined by guard_id). */}
      <div className="mb-4 flex flex-wrap items-center gap-2.5">
        <Chip
          active={statusFilter === "all"}
          onClick={() => {
            setStatusFilter("all");
            setPage(1);
          }}
        >
          {t("common.all")}
        </Chip>
        <Chip
          active={statusFilter === "online"}
          dot="bg-status-active"
          onClick={() => {
            setStatusFilter("online");
            setPage(1);
          }}
        >
          {c.chipOnline}
        </Chip>
        <Chip
          active={statusFilter === "working"}
          dot="bg-status-working"
          onClick={() => {
            setStatusFilter("working");
            setPage(1);
          }}
        >
          {c.chipOnJob}
        </Chip>
        <Chip
          active={statusFilter === "offline"}
          dot="bg-status-offline"
          onClick={() => {
            setStatusFilter("offline");
            setPage(1);
          }}
        >
          {c.chipOffline}
        </Chip>
        <SearchField
          size="sm"
          className="ml-auto"
          placeholder={c.searchPlaceholder}
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setPage(1);
          }}
        />
      </div>

      <Panel>
        {loading ? (
          <div className="flex items-center justify-center gap-2 py-16 text-muted">
            <Loader2 className="size-5 animate-spin" />
            {t("common.loading")}
          </div>
        ) : filtered.length === 0 ? (
          <div className="py-16 text-center text-muted">{t("guards.empty")}</div>
        ) : (
          <>
            <Table>
              <thead>
                <tr>
                  <Th>{t("guards.col.guard")}</Th>
                  <Th>{c.colStatus}</Th>
                  <Th>{t("guards.col.experience")}</Th>
                  <Th>{t("guards.col.workplace")}</Th>
                  <Th>{t("guards.col.bank")}</Th>
                  <Th aria-label={t("common.view")} />
                </tr>
              </thead>
              <tbody>
                {visible.map((g) => (
                  <Tr key={g.user_id} onClick={() => setSelected(g)}>
                    <Td>
                      <div className="flex items-center gap-3">
                        {/* No live status → no avatar status dot (honest). */}
                        <Avatar>{initialsOf(g.account_name, g.user_id)}</Avatar>
                        <div className="min-w-0">
                          <div className="truncate font-semibold text-text-strong">
                            {g.account_name ?? t("common.none")}
                          </div>
                          <div className="font-mono text-xs text-muted">
                            ID #{g.user_id.slice(0, 8)}
                          </div>
                        </div>
                      </div>
                    </Td>
                    <Td>
                      <StatusBadge status={statusOf(g)} c={c} />
                    </Td>
                    <Td className="font-mono tabular-nums">
                      {g.years_of_experience != null
                        ? `${g.years_of_experience} ${t("applicants.years")}`
                        : t("common.none")}
                    </Td>
                    <Td>{g.previous_workplace ?? t("common.none")}</Td>
                    <Td>
                      {g.bank_name ? (
                        <div>
                          <div>{g.bank_name}</div>
                          <div className="font-mono text-xs text-muted">
                            {maskAccount(g.account_number) ?? t("common.none")}
                          </div>
                        </div>
                      ) : (
                        t("common.none")
                      )}
                    </Td>
                    <Td className="text-right">
                      <Button variant="secondary" size="sm" onClick={() => setSelected(g)}>
                        {t("common.view")}
                      </Button>
                    </Td>
                  </Tr>
                ))}
              </tbody>
            </Table>
            <Pagination
              page={safePage}
              pageCount={pageCount}
              onPage={setPage}
              summary={`${summaryStart}–${summaryEnd} ${c.of} ${filtered.length}`}
            />
          </>
        )}
      </Panel>

      {selected && <GuardDetailModal guard={selected} onClose={() => setSelected(null)} />}
    </div>
  );
}

/** Live-status dot + label for the table's Status column (online / on-a-job / offline). */
function StatusBadge({
  status,
  c,
}: {
  status: GuardStatus;
  c: { chipOnline: string; chipOnJob: string; chipOffline: string };
}) {
  const label =
    status === "working" ? c.chipOnJob : status === "online" ? c.chipOnline : c.chipOffline;
  return (
    <span className="inline-flex items-center gap-1.5 text-sm">
      <span className={`size-2 rounded-full ${STATUS_DOT[status]}`} />
      {label}
    </span>
  );
}

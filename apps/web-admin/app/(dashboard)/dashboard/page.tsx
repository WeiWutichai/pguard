"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  AlertTriangle,
  Banknote,
  EyeOff,
  Loader2,
  RefreshCw,
  Shield,
  ShieldCheck,
  Star,
  Target,
  Users,
} from "lucide-react";
import type { ReactNode } from "react";

import type { components as paymentComponents } from "@/api/generated/payment";
import type { components as presenceComponents } from "@/api/generated/presence";
import type { components } from "@/api/generated/rating";
import { bookingApi, paymentApi, presenceApi, profileApi, ratingApi } from "@/lib/api";
import {
  Badge,
  Button,
  KpiCard,
  KpiGrid,
  PageIntro,
  Panel,
  PanelBody,
  PanelHead,
} from "@/components/ui";
import { useLanguage } from "@/lib/i18n";
import { fmtBaht, fmtCappedCount } from "@/lib/format";

import { COPY } from "./copy";
import { MiniMap } from "./mini-map";

type AdminReview = components["schemas"]["AdminReview"];
type GuardLocation = presenceComponents["schemas"]["GuardLocation"];
type RevenuePoint = paymentComponents["schemas"]["RevenuePoint"];

// The admin guard-profiles list is capped at 200 by the repo; show "200+" rather than a wrong exact.
const LIST_CAP = 200;

// "Active jobs" = assigned + working (non-terminal, post-request) — counted from the admin booking list.
const ACTIVE_BOOKING_STATUSES = new Set([
  "accepted",
  "en_route",
  "arrived",
  "pending_completion",
]);

interface Metrics {
  pending: number | null;
  approved: number | null;
  reviewsTotal: number | null;
  hidden: number | null;
  avg: string | null;
  online: number | null;
  activeJobs: number | null;
  /** True when the booking list hit the 200-row cap, so `activeJobs` is a lower bound (→ "N+"). */
  activeJobsCapped: boolean;
  revenueToday: string | null;
  revenue7d: RevenuePoint[];
  reviews: AdminReview[];
  /** The raw presence fixes (same call that produces `online`) — feeds the mini map. */
  locations: GuardLocation[];
}

const EMPTY: Metrics = {
  pending: null,
  approved: null,
  reviewsTotal: null,
  hidden: null,
  avg: null,
  online: null,
  activeJobs: null,
  activeJobsCapped: false,
  revenueToday: null,
  revenue7d: [],
  reviews: [],
  locations: [],
};

export default function DashboardPage() {
  const { t, lang } = useLanguage();
  const router = useRouter();
  const c = COPY[lang];
  const [m, setM] = useState<Metrics>(EMPTY);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);

  // Fetch every dashboard metric in parallel from the endpoints that actually exist. Each value is
  // derived from a real response (no invented aggregates); a failed sub-call leaves that metric null
  // (renders "—") and raises the error banner — the rest still show.
  const fetchAll = useCallback((alive: () => boolean) => {
    // Local-midnight bounds for the revenue windows (the API takes RFC3339 instants).
    const now = new Date();
    const startToday = new Date(
      now.getFullYear(),
      now.getMonth(),
      now.getDate(),
    ).toISOString();
    const start7d = new Date(
      now.getFullYear(),
      now.getMonth(),
      now.getDate() - 6,
    ).toISOString();
    return Promise.all([
      profileApi.GET("/admin/guard-profiles", {
        params: { query: { approval_status: "pending" } },
      }),
      profileApi.GET("/admin/guard-profiles", {
        params: { query: { approval_status: "approved" } },
      }),
      ratingApi.GET("/admin/reviews", { params: { query: { limit: LIST_CAP } } }),
      presenceApi.GET("/locations", { params: { query: { online_only: true } } }),
      bookingApi.GET("/admin/bookings", { params: { query: { limit: LIST_CAP } } }),
      paymentApi.GET("/admin/reports/revenue", { params: { query: { from: startToday } } }),
      paymentApi.GET("/admin/reports/revenue", { params: { query: { from: start7d } } }),
    ]).then(([pend, appr, rev, online, bookings, revToday, rev7d]) => {
      if (!alive()) return;
      const anyErr =
        pend.error ||
        appr.error ||
        rev.error ||
        online.error ||
        bookings.error ||
        revToday.error ||
        rev7d.error;
      const stats = rev.data?.data?.stats;
      setHasError(Boolean(anyErr));
      setM({
        pending: pend.error ? null : (pend.data?.data?.length ?? 0),
        approved: appr.error ? null : (appr.data?.data?.length ?? 0),
        reviewsTotal: rev.error ? null : (stats?.total ?? 0),
        hidden: rev.error || !stats ? null : Math.max(0, stats.total - stats.visible),
        avg: rev.error ? null : (stats?.average ?? null),
        online: online.error ? null : (online.data?.data?.length ?? 0),
        activeJobs: bookings.error
          ? null
          : (bookings.data?.data ?? []).filter((b) =>
              ACTIVE_BOOKING_STATUSES.has(b.status),
            ).length,
        // The list is capped at 200 (all statuses, newest-first); if it saturated, active jobs
        // beyond the page are unseen, so the count is a lower bound — surfaced as "N+".
        activeJobsCapped:
          !bookings.error && (bookings.data?.data?.length ?? 0) >= LIST_CAP,
        revenueToday: revToday.error ? null : (revToday.data?.data?.total ?? null),
        revenue7d: rev7d.error ? [] : (rev7d.data?.data?.series ?? []),
        reviews: rev.error ? [] : (rev.data?.data?.data ?? []),
        locations: online.error ? [] : (online.data?.data ?? []),
      });
      setLoading(false);
    })
      .catch(() => {
        // openapi-fetch only RESOLVES with { error } on HTTP errors (handled per-source above); a
        // transport-level failure (gateway down/offline/DNS) REJECTS the whole Promise.all. Catch
        // it so the page isn't stuck on the spinner — flip loading off + raise the banner (Retry
        // recovers once the gateway is reachable).
        if (alive()) {
          setHasError(true);
          setLoading(false);
        }
      });
  }, []);

  useEffect(() => {
    let alive = true;
    void fetchAll(() => alive);
    return () => {
      alive = false;
    };
  }, [reloadNonce, fetchAll]);

  function reload() {
    setLoading(true);
    setHasError(false);
    setReloadNonce((n) => n + 1);
  }

  return (
    <div className="mx-auto max-w-6xl">
      <PageIntro title={t("dashboard.title")} lead={c.subtitle}>
        <Button variant="secondary" size="sm" onClick={reload}>
          <RefreshCw className="size-4" />
          {t("common.retry")}
        </Button>
      </PageIntro>

      {hasError && (
        <div
          role="alert"
          className="mb-4 flex items-center gap-2 rounded-lg border border-danger/40 bg-danger-bg px-4 py-2 text-sm text-danger"
        >
          <AlertTriangle className="size-4" />
          {t("dashboard.error")}
        </div>
      )}

      {loading ? (
        <div className="flex items-center justify-center gap-2 rounded-lg border border-border bg-surface py-20 text-muted">
          <Loader2 className="size-5 animate-spin" />
          {t("common.loading")}
        </div>
      ) : (
        <>
          {/* KPI strip — icons render PLAIN/faint per admin.css `.kpi .ic` (its !important beats
              the mockup HTML's inline tints — the stylesheet is the rendered truth). The mockup's 4 design cells first (active jobs + revenue have NO v2
              admin endpoint: honest gap chips, never invented numbers), then the real metrics
              this console already loads (profile + rating) as a second strip row. */}
          <KpiGrid>
            <KpiCard
              icon={<Shield />}
              label={c.kpiActiveJobs}
              value={
                m.activeJobs == null
                  ? "—"
                  : `${m.activeJobs}${m.activeJobsCapped ? "+" : ""}`
              }
            />
            <KpiCard
              icon={<Target />}
              label={t("dashboard.card.onlineGuards")}
              value={m.online == null ? "—" : String(m.online)}
            />
            <KpiCard
              icon={<Banknote />}
              label={c.kpiRevenueToday}
              value={m.revenueToday == null ? "—" : fmtBaht(m.revenueToday)}
            />
            <KpiCard
              icon={<Users />}
              label={c.kpiPendingApprovals}
              value={fmtCappedCount(m.pending)}
            />
            {/* Row 2 — cell borders re-anchored (KpiGrid's built-ins only cover one row of 4). */}
            <KpiCard
              className="border-l-0 border-t"
              icon={<ShieldCheck />}
              label={t("dashboard.card.approvedGuards")}
              value={fmtCappedCount(m.approved)}
            />
            <KpiCard
              className="min-[1101px]:border-t"
              icon={<Star />}
              label={t("dashboard.card.reviews")}
              value={m.reviewsTotal == null ? "—" : String(m.reviewsTotal)}
            />
            <KpiCard
              className="max-[1100px]:border-l-0 min-[1101px]:border-t"
              icon={<Star />}
              label={t("dashboard.card.avgRating")}
              value={m.avg ?? "—"}
            />
            <KpiCard
              className="min-[1101px]:border-t"
              icon={<EyeOff />}
              label={t("dashboard.card.hiddenReviews")}
              value={m.hidden == null ? "—" : String(m.hidden)}
            />
          </KpiGrid>

          <div className="grid gap-4 lg:grid-cols-2">
            {/* Live map — REAL presence fixes (the same /locations response as the KPI). */}
            <Panel>
              <PanelHead
                title={c.mapTitle}
                sub={m.online == null ? "—" : `${m.online} ${c.online}`}
              >
                <Button variant="ghost" size="sm" onClick={() => router.push("/map")}>
                  {c.openFull}
                </Button>
              </PanelHead>
              <PanelBody>
                <MiniMap locations={m.locations} emptyLabel={c.mapEmpty} />
              </PanelBody>
            </Panel>

            {/* Alerts — designed panel, but no v2 admin alerts endpoint exists yet. */}
            <Panel>
              <PanelHead title={c.alertsTitle} />
              <PanelBody>
                <GapNote chip={c.awaitingApi} note={c.alertsGap} />
              </PanelBody>
            </Panel>

            {/* Revenue, last 7 days — REAL daily net-revenue series from the admin reports endpoint. */}
            <Panel>
              <PanelHead title={c.revenueTitle} />
              <PanelBody>
                <Revenue7dChart series={m.revenue7d} />
              </PanelBody>
            </Panel>

            {/* Activity feed — no v2 admin event-feed endpoint exists yet. */}
            <Panel>
              <PanelHead title={c.feedTitle} />
              <PanelBody>
                <GapNote chip={c.awaitingApi} note={c.feedGap} />
              </PanelBody>
            </Panel>

            {/* Real chart: rating distribution from the loaded reviews. */}
            <RatingDistribution reviews={m.reviews} />
          </div>
        </>
      )}
    </div>
  );
}



/** Honest API-gap body for a designed panel/cell with no v2 endpoint — chip + what's
 * missing. Never renders fabricated numbers. */
function GapNote({ chip, note }: { chip: string; note: string }) {
  return (
    <div className="flex min-h-24 flex-col items-start justify-center gap-2">
      <Badge tone="gray">{chip}</Badge>
      <p className="text-sm text-muted">{note}</p>
    </div>
  );
}

/** Hand-rolled 7-day net-revenue bar chart from the admin reports series — no charting dep (matches
 *  the lean hand-rolled style of the rating histogram). Builds the last 7 calendar days and fills
 *  each from the series by date (days with no revenue render as an empty bar). */
function Revenue7dChart({ series }: { series: RevenuePoint[] }) {
  const { lang } = useLanguage();
  const c = COPY[lang];
  const byDate = new Map(series.map((p) => [p.date, parseFloat(p.revenue)]));
  const now = new Date();
  const days = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (6 - i));
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
    return {
      key,
      label: d.toLocaleDateString(lang === "th" ? "th-TH" : "en-GB", {
        weekday: "short",
      }),
      value: byDate.get(key) ?? 0,
    };
  });
  const total = days.reduce((s, d) => s + d.value, 0);
  const max = Math.max(1, ...days.map((d) => d.value));

  if (total === 0) {
    return (
      <div className="flex min-h-24 items-center justify-center py-4 text-sm text-muted">
        {c.revenueEmpty}
      </div>
    );
  }
  return (
    <div>
      <div className="mb-3 text-lg font-semibold text-text-strong tabular-nums">
        {fmtBaht(total)}
      </div>
      <div className="flex h-28 items-end gap-2">
        {days.map((d) => (
          <div key={d.key} className="flex flex-1 flex-col items-center gap-1">
            <div className="flex w-full flex-1 items-end">
              <div
                className="w-full rounded-t bg-brand-int"
                style={{ height: `${Math.max(2, (d.value / max) * 100)}%` }}
                title={fmtBaht(d.value)}
              />
            </div>
            <span className="text-[10px] text-muted">{d.label}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

/** Hand-rolled 1★–5★ histogram from the loaded reviews — no charting dep (lean prod image; the
 *  chart is a few bars). Labeled with the sample size since the list is capped, so it never implies
 *  the full dataset. */
function RatingDistribution({ reviews }: { reviews: AdminReview[] }) {
  const { t } = useLanguage();
  const buckets = [0, 0, 0, 0, 0]; // index 0 = 1★ … index 4 = 5★
  for (const r of reviews) {
    const i = Math.min(5, Math.max(1, Math.round(r.overall_rating))) - 1;
    buckets[i] += 1;
  }
  const max = Math.max(1, ...buckets);

  return (
    <Panel>
      <PanelHead title={t("dashboard.chart.ratingDist")} />
      <PanelBody>
        {reviews.length === 0 ? (
          <div className="py-8 text-center text-sm text-muted">
            {t("dashboard.chart.noReviews")}
          </div>
        ) : (
          <>
            <div className="space-y-2">
              {[5, 4, 3, 2, 1].map((star) => {
                const count = buckets[star - 1];
                return (
                  <div key={star} className="flex items-center gap-2 text-sm">
                    <span className="flex w-8 shrink-0 items-center gap-0.5 text-muted">
                      {star}
                      <Star className="size-3 fill-warning text-warning" />
                    </span>
                    <div className="h-3 flex-1 overflow-hidden rounded-full bg-sunken">
                      <div
                        className="h-full rounded-full bg-brand-int"
                        style={{ width: `${(count / max) * 100}%` }}
                      />
                    </div>
                    <span className="w-8 shrink-0 text-right tabular-nums text-muted">
                      {count}
                    </span>
                  </div>
                );
              })}
            </div>
            <p className="mt-3 text-xs text-muted">
              {t("dashboard.chart.basedOn")} ({reviews.length})
            </p>
          </>
        )}
      </PanelBody>
    </Panel>
  );
}

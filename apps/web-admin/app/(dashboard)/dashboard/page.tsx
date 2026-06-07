"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import type { Route } from "next";
import {
  AlertTriangle,
  Loader2,
  PlugZap,
  RefreshCw,
  ShieldCheck,
  Star,
  UserPlus,
  Wifi,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

import type { components } from "@/api/generated/rating";
import { presenceApi, profileApi, ratingApi } from "@/lib/api";
import { useLanguage, type TKey } from "@/lib/i18n";

type AdminReview = components["schemas"]["AdminReview"];

// The admin guard-profiles list is capped at 200 by the repo; show "200+" rather than a wrong exact.
const LIST_CAP = 200;

interface Metrics {
  pending: number | null;
  approved: number | null;
  reviewsTotal: number | null;
  hidden: number | null;
  avg: string | null;
  online: number | null;
  reviews: AdminReview[];
}

const EMPTY: Metrics = {
  pending: null,
  approved: null,
  reviewsTotal: null,
  hidden: null,
  avg: null,
  online: null,
  reviews: [],
};

export default function DashboardPage() {
  const { t } = useLanguage();
  const [m, setM] = useState<Metrics>(EMPTY);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);

  // Fetch every dashboard metric in parallel from the endpoints that actually exist. Each value is
  // derived from a real response (no invented aggregates); a failed sub-call leaves that metric null
  // (renders "—") and raises the error banner — the rest still show.
  const fetchAll = useCallback((alive: () => boolean) => {
    return Promise.all([
      profileApi.GET("/admin/guard-profiles", {
        params: { query: { approval_status: "pending" } },
      }),
      profileApi.GET("/admin/guard-profiles", {
        params: { query: { approval_status: "approved" } },
      }),
      ratingApi.GET("/admin/reviews", { params: { query: { limit: LIST_CAP } } }),
      presenceApi.GET("/locations", { params: { query: { online_only: true } } }),
    ]).then(([pend, appr, rev, online]) => {
      if (!alive()) return;
      const anyErr = pend.error || appr.error || rev.error || online.error;
      const stats = rev.data?.data?.stats;
      setHasError(Boolean(anyErr));
      setM({
        pending: pend.error ? null : (pend.data?.data?.length ?? 0),
        approved: appr.error ? null : (appr.data?.data?.length ?? 0),
        reviewsTotal: rev.error ? null : (stats?.total ?? 0),
        hidden: rev.error || !stats ? null : Math.max(0, stats.total - stats.visible),
        avg: rev.error ? null : (stats?.average ?? null),
        online: online.error ? null : (online.data?.data?.length ?? 0),
        reviews: rev.error ? [] : (rev.data?.data?.data ?? []),
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
      <div className="flex items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold">{t("dashboard.title")}</h1>
          <p className="mt-1 text-muted">{t("dashboard.subtitle")}</p>
        </div>
        <button
          type="button"
          onClick={reload}
          className="flex items-center gap-1.5 rounded-lg border border-border px-3 py-1.5 text-sm hover:bg-sunken"
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
          {t("dashboard.error")}
        </div>
      )}

      {loading ? (
        <div className="mt-6 flex items-center justify-center gap-2 rounded-xl border border-border bg-surface py-20 text-muted">
          <Loader2 className="size-5 animate-spin" />
          {t("common.loading")}
        </div>
      ) : (
        <>
          {/* Real metric cards (each links to its page). */}
          <div className="mt-5 grid grid-cols-2 gap-3 lg:grid-cols-3">
            <StatCard
              labelKey="dashboard.card.pendingApplicants"
              value={fmtCount(m.pending)}
              icon={UserPlus}
              href="/applicants"
            />
            <StatCard
              labelKey="dashboard.card.approvedGuards"
              value={fmtCount(m.approved)}
              icon={ShieldCheck}
              href="/guards"
            />
            <StatCard
              labelKey="dashboard.card.onlineGuards"
              value={m.online == null ? "—" : String(m.online)}
              icon={Wifi}
              href="/map"
            />
            <StatCard
              labelKey="dashboard.card.reviews"
              value={m.reviewsTotal == null ? "—" : String(m.reviewsTotal)}
              icon={Star}
              href="/reviews"
            />
            <StatCard
              labelKey="dashboard.card.avgRating"
              value={m.avg ?? "—"}
              icon={Star}
              href="/reviews"
            />
            <StatCard
              labelKey="dashboard.card.hiddenReviews"
              value={m.hidden == null ? "—" : String(m.hidden)}
              icon={Star}
              href="/reviews"
            />
          </div>

          {/* Real chart: rating distribution from the loaded reviews. */}
          <div className="mt-6 grid gap-3 lg:grid-cols-2">
            <RatingDistribution reviews={m.reviews} />

            {/* Documented gaps — NO fabricated numbers; these need admin aggregate endpoints. */}
            <div className="rounded-xl border border-border bg-surface p-5">
              <div className="flex items-center gap-2 text-muted">
                <PlugZap className="size-4" />
                <h3 className="text-sm font-medium uppercase">{t("dashboard.gap.heading")}</h3>
              </div>
              <ul className="mt-3 space-y-2 text-sm text-muted">
                <li className="rounded-lg border border-border bg-sunken px-3 py-2">
                  {t("dashboard.gap.customers")}
                </li>
                <li className="rounded-lg border border-border bg-sunken px-3 py-2">
                  {t("dashboard.gap.bookings")}
                </li>
              </ul>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

function fmtCount(n: number | null): string {
  if (n == null) return "—";
  return n >= LIST_CAP ? `${LIST_CAP}+` : String(n);
}

function StatCard({
  labelKey,
  value,
  icon: Icon,
  href,
}: {
  labelKey: TKey;
  value: string;
  icon: LucideIcon;
  href: Route;
}) {
  const { t } = useLanguage();
  return (
    <Link
      href={href}
      className="group rounded-xl border border-border bg-surface px-4 py-3 transition hover:border-brand/50 hover:bg-sunken"
    >
      <div className="flex items-center justify-between">
        <div className="text-xs uppercase text-muted">{t(labelKey)}</div>
        <Icon className="size-4 text-muted group-hover:text-brand" />
      </div>
      <div className="mt-1 text-2xl font-semibold">{value}</div>
    </Link>
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
    <div className="rounded-xl border border-border bg-surface p-5">
      <h3 className="text-sm font-medium uppercase text-muted">{t("dashboard.chart.ratingDist")}</h3>
      {reviews.length === 0 ? (
        <div className="py-8 text-center text-sm text-muted">{t("dashboard.chart.noReviews")}</div>
      ) : (
        <>
          <div className="mt-4 space-y-2">
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
                      className="h-full rounded-full bg-brand"
                      style={{ width: `${(count / max) * 100}%` }}
                    />
                  </div>
                  <span className="w-8 shrink-0 text-right tabular-nums text-muted">{count}</span>
                </div>
              );
            })}
          </div>
          <p className="mt-3 text-xs text-muted">
            {t("dashboard.chart.basedOn")} ({reviews.length})
          </p>
        </>
      )}
    </div>
  );
}

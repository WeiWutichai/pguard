"use client";

import { useCallback, useEffect, useState } from "react";
import { AlertTriangle, Eye, EyeOff, Loader2, RefreshCw, Search, Star } from "lucide-react";

import type { components } from "@/api/generated/rating";
import { ratingApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import { cn } from "@/lib/cn";

type AdminReview = components["schemas"]["AdminReview"];
type AdminReviewStats = components["schemas"]["AdminReviewStats"];

type VisFilter = "all" | "visible" | "hidden";
const RATINGS = [0, 5, 4, 3, 2, 1] as const; // 0 = any

export default function ReviewsPage() {
  const { t } = useLanguage();
  const [reviews, setReviews] = useState<AdminReview[]>([]);
  const [stats, setStats] = useState<AdminReviewStats | null>(null);
  const [rating, setRating] = useState(0);
  const [vis, setVis] = useState<VisFilter>("all");
  const [searchInput, setSearchInput] = useState("");
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [actingId, setActingId] = useState<string | null>(null);
  const [reloadNonce, setReloadNonce] = useState(0);

  // Debounce the free-text search into the query that triggers a fetch. Show the loading state
  // when the debounced value actually changes (parity with the other filters). The early-return
  // guard avoids a stuck spinner when the trimmed value is unchanged (e.g. typed then deleted);
  // the setState calls live in the deferred timeout, not the effect's sync phase.
  useEffect(() => {
    const next = searchInput.trim();
    if (next === search) return;
    const id = setTimeout(() => {
      setLoading(true);
      setSearch(next);
    }, 300);
    return () => clearTimeout(id);
  }, [searchInput, search]);

  const fetchInto = useCallback(
    (alive: () => boolean) => {
      const query: {
        rating?: number;
        is_visible?: boolean;
        search?: string;
      } = {};
      // `rating === 0` is the UI-only "any" sentinel — never sent to the API (contract min is 1).
      if (rating > 0) query.rating = rating;
      if (vis !== "all") query.is_visible = vis === "visible";
      if (search) query.search = search;
      return ratingApi
        .GET("/admin/reviews", { params: { query } })
        .then(({ data, error }) => {
          if (!alive()) return;
          setHasError(Boolean(error));
          // `stats` are UNFILTERED (API contract) — display them as-is, never compute from the
          // filtered `reviews` list.
          setReviews(error ? [] : (data?.data?.data ?? []));
          setStats(error ? null : (data?.data?.stats ?? null));
          setLoading(false);
        });
    },
    [rating, vis, search],
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

  // Optimistic visibility flip + rollback. On success, refetch so the UNFILTERED stats cards stay
  // truthful (and the row reconciles with the active filter) — stats never come from the list.
  async function toggleVisibility(review: AdminReview) {
    const next = !review.is_visible;
    const snapshot = reviews;
    setHasError(false);
    setActingId(review.id);
    setReviews((cur) =>
      cur.map((r) => (r.id === review.id ? { ...r, is_visible: next } : r)),
    );

    const { error } = await ratingApi.PUT("/admin/reviews/{id}/visibility", {
      params: { path: { id: review.id } },
      body: { is_visible: next },
    });

    setActingId(null);
    if (error) {
      setReviews(snapshot); // rollback
      setHasError(true);
      return;
    }
    setReloadNonce((n) => n + 1); // refresh unfiltered stats + reconcile filter
  }

  // Derived from the UNFILTERED stats (the contract exposes total + visible, not hidden);
  // clamped defensively in case a future contract counts non-visible/non-hidden states in total.
  const hidden = stats ? Math.max(0, stats.total - stats.visible) : 0;

  return (
    <div className="mx-auto max-w-6xl">
      <h1 className="text-2xl font-semibold">{t("reviews.title")}</h1>
      <p className="mt-1 text-muted">{t("reviews.subtitle")}</p>

      {/* Stat cards — from the API's UNFILTERED stats. */}
      <div className="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <StatCard label={t("reviews.stats.total")} value={stats ? String(stats.total) : "—"} />
        <StatCard label={t("reviews.stats.visible")} value={stats ? String(stats.visible) : "—"} />
        <StatCard label={t("reviews.stats.hidden")} value={stats ? String(hidden) : "—"} />
        <StatCard
          label={t("reviews.stats.average")}
          value={stats?.average ?? t("common.none")}
        />
      </div>

      {/* Filters. */}
      <div className="mt-5 flex flex-wrap items-center gap-3">
        <select
          value={rating}
          onChange={(e) => {
            setLoading(true);
            setRating(Number(e.target.value));
          }}
          aria-label={t("reviews.filter.rating")}
          className="rounded-lg border border-border bg-surface px-3 py-1.5 text-sm"
        >
          {RATINGS.map((r) => (
            <option key={r} value={r}>
              {r === 0 ? t("reviews.ratingAny") : `${r} ★`}
            </option>
          ))}
        </select>

        <div className="inline-flex overflow-hidden rounded-lg border border-border text-sm">
          {(["all", "visible", "hidden"] as const).map((v) => (
            <button
              key={v}
              type="button"
              onClick={() => {
                setLoading(true);
                setVis(v);
              }}
              className={cn(
                "px-3 py-1.5 font-medium",
                vis === v ? "bg-brand text-brand-fg" : "bg-surface text-muted hover:bg-sunken",
              )}
            >
              {v === "all"
                ? t("common.all")
                : v === "visible"
                  ? t("reviews.visible")
                  : t("reviews.hidden")}
            </button>
          ))}
        </div>

        <div className="relative">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted" />
          <input
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            placeholder={t("reviews.filter.search")}
            className="rounded-lg border border-border bg-surface py-1.5 pl-8 pr-3 text-sm"
          />
        </div>

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
          {t("reviews.error")}
        </div>
      )}

      <div className="mt-4 overflow-hidden rounded-xl border border-border bg-surface">
        {loading ? (
          <div className="flex items-center justify-center gap-2 py-16 text-muted">
            <Loader2 className="size-5 animate-spin" />
            {t("common.loading")}
          </div>
        ) : reviews.length === 0 ? (
          <div className="py-16 text-center text-muted">{t("reviews.empty")}</div>
        ) : (
          <table className="w-full text-left text-sm">
            <thead className="border-b border-border bg-sunken text-xs uppercase text-muted">
              <tr>
                <th className="px-4 py-3 font-medium">{t("reviews.col.guard")}</th>
                <th className="px-4 py-3 font-medium">{t("reviews.col.rating")}</th>
                <th className="px-4 py-3 font-medium">{t("reviews.col.review")}</th>
                <th className="px-4 py-3 font-medium">{t("reviews.col.date")}</th>
                <th className="px-4 py-3 text-right font-medium">{t("reviews.col.actions")}</th>
              </tr>
            </thead>
            <tbody>
              {reviews.map((r) => (
                <tr key={r.id} className="border-b border-border last:border-0">
                  <td className="px-4 py-3 align-top">
                    <div className="font-mono text-xs text-muted">{r.guard_id}</div>
                    <div className="text-xs text-muted">
                      {t("reviews.col.customer")}: {r.customer_id.slice(0, 8)}
                    </div>
                  </td>
                  <td className="px-4 py-3 align-top">
                    <span className="inline-flex items-center gap-1">
                      <Star className="size-3.5 fill-warning text-warning" />
                      {r.overall_rating}
                    </span>
                  </td>
                  <td className="px-4 py-3 align-top">
                    <div className="max-w-md text-pretty">{r.review_text ?? t("common.none")}</div>
                  </td>
                  <td className="px-4 py-3 align-top text-xs text-muted">
                    {r.created_at.slice(0, 10)}
                  </td>
                  <td className="px-4 py-3 align-top text-right">
                    <button
                      type="button"
                      disabled={actingId === r.id}
                      onClick={() => void toggleVisibility(r)}
                      className={cn(
                        "inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-xs font-medium disabled:opacity-60",
                        r.is_visible
                          ? "border-border hover:bg-sunken"
                          : "border-danger/40 text-danger hover:bg-danger/10",
                      )}
                    >
                      {r.is_visible ? (
                        <>
                          <Eye className="size-3.5" />
                          {t("reviews.visible")}
                        </>
                      ) : (
                        <>
                          <EyeOff className="size-3.5" />
                          {t("reviews.hidden")}
                        </>
                      )}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-border bg-surface px-4 py-3">
      <div className="text-xs uppercase text-muted">{label}</div>
      <div className="mt-1 text-2xl font-semibold">{value}</div>
    </div>
  );
}

"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  AlertTriangle,
  Clock,
  EyeOff,
  Loader2,
  MessageCircle,
  RefreshCw,
  Star,
} from "lucide-react";

import type { components } from "@/api/generated/rating";
import { ratingApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import { useNameResolver } from "@/lib/use-names";
import { cn } from "@/lib/cn";
import {
  Avatar,
  Button,
  Chip,
  KpiCard,
  KpiGrid,
  Modal,
  PageIntro,
  Panel,
  SearchField,
  Table,
  Td,
  Th,
  Tr,
} from "@/components/ui";

type AdminReview = components["schemas"]["AdminReview"];
type AdminReviewStats = components["schemas"]["AdminReviewStats"];

type VisFilter = "all" | "visible" | "hidden";
const STAR_FILTERS = [5, 4, 3, 2, 1] as const; // rating 0 = the UI-only "any" sentinel

// Screen-local design copy (exact strings from the hi-fi Reviews mockup) for text the shared
// i18n catalog doesn't carry. Shared keys (nav/common/reviews.*) still come from t().
const COPY = {
  th: {
    sub: "คะแนนและความคิดเห็นจากลูกค้า",
    kpiAvg: "คะแนนเฉลี่ย",
    kpiTotal: "รีวิวทั้งหมด",
    kpiHidden: "ถูกซ่อน",
    kpiMonth: "รีวิวเดือนนี้",
    awaitingApi: "รอ API",
    allRatings: "ทุกคะแนน",
    visAll: "ทั้งหมด",
    visVisible: "แสดง",
    visHidden: "ซ่อน",
    searchPlaceholder: "ค้นหา…",
    colComment: "ความคิดเห็น",
    detailTitle: "รายละเอียดรีวิว",
    reviewedBy: "รีวิวโดย",
    breakdown: "คะแนนแยกหมวด",
    catOverall: "ภาพรวม",
    catPunctuality: "ตรงเวลา",
    catProfessionalism: "มืออาชีพ",
    catCommunication: "การสื่อสาร",
    catAppearance: "การแต่งกาย",
    hideReview: "ซ่อนรีวิว",
    showReview: "แสดงรีวิว",
  },
  en: {
    sub: "Customer ratings & feedback",
    kpiAvg: "Avg rating",
    kpiTotal: "Total reviews",
    kpiHidden: "Hidden",
    kpiMonth: "This month",
    awaitingApi: "awaiting API",
    allRatings: "All ratings",
    visAll: "All",
    visVisible: "Visible",
    visHidden: "Hidden",
    searchPlaceholder: "Search…",
    colComment: "Comment",
    detailTitle: "Review detail",
    reviewedBy: "by",
    breakdown: "Category breakdown",
    catOverall: "Overall",
    catPunctuality: "Punctuality",
    catProfessionalism: "Professionalism",
    catCommunication: "Communication",
    catAppearance: "Appearance",
    hideReview: "Hide review",
    showReview: "Show review",
  },
} as const;

export default function ReviewsPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];
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
  const [selected, setSelected] = useState<AdminReview | null>(null);

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

  // Batch-resolve every guard + customer id on the page to display names in one call (the contract
  // exposes only ids on reviews). Falls back to the short id when a name is unavailable.
  const resolveIds = useMemo(() => {
    const out: string[] = [];
    for (const r of reviews) {
      out.push(r.guard_id, r.customer_id);
    }
    return out;
  }, [reviews]);
  const { resolve } = useNameResolver(resolveIds, lang);

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
      <PageIntro title={t("reviews.title")} lead={c.sub}>
        <Button variant="secondary" size="sm" onClick={reload}>
          <RefreshCw size={15} />
          {t("common.retry")}
        </Button>
      </PageIntro>

      {/* KPI strip — from the API's UNFILTERED stats (total/visible/average + this_month). */}
      <KpiGrid>
        <KpiCard
          icon={<Star />}
          label={c.kpiAvg}
          value={stats?.average ?? t("common.none")}
        />
        <KpiCard
          icon={<MessageCircle />}
          label={c.kpiTotal}
          value={stats ? stats.total.toLocaleString("en-US") : t("common.none")}
          caption={
            <>
              {t("reviews.stats.visible")}{" "}
              <span data-testid="reviews-stat-visible">
                {stats ? String(stats.visible) : t("common.none")}
              </span>
            </>
          }
        />
        <KpiCard
          icon={<EyeOff />}
          label={c.kpiHidden}
          value={stats ? String(hidden) : t("common.none")}
        />
        {/* รีวิวเดือนนี้ — reviews created this calendar month (UNFILTERED stat). */}
        <KpiCard
          icon={<Clock />}
          label={c.kpiMonth}
          value={
            stats ? (
              <span data-testid="reviews-stat-month">{stats.this_month.toLocaleString("en-US")}</span>
            ) : (
              t("common.none")
            )
          }
        />
      </KpiGrid>

      {/* Filters row — mutually-exclusive chip groups + hairline divider + search. */}
      <div className="mb-4 flex flex-wrap items-center gap-2.5">
        <Chip
          active={rating === 0}
          onClick={() => {
            setLoading(true);
            setRating(0);
          }}
        >
          {c.allRatings}
        </Chip>
        {STAR_FILTERS.map((r) => (
          <Chip
            key={r}
            active={rating === r}
            onClick={() => {
              setLoading(true);
              setRating(r);
            }}
          >
            {r}★
          </Chip>
        ))}

        <span aria-hidden className="mx-1 h-6 w-px bg-border" />

        {(["all", "visible", "hidden"] as const).map((v) => (
          <Chip
            key={v}
            data-testid={`reviews-filter-${v}`}
            active={vis === v}
            onClick={() => {
              setLoading(true);
              setVis(v);
            }}
          >
            {v === "all" ? c.visAll : v === "visible" ? c.visVisible : c.visHidden}
          </Chip>
        ))}

        <span className="flex-1" />

        <SearchField
          size="sm"
          value={searchInput}
          onChange={(e) => setSearchInput(e.target.value)}
          placeholder={c.searchPlaceholder}
          aria-label={t("reviews.filter.search")}
        />
      </div>

      {hasError && (
        <div
          role="alert"
          className="mb-4 flex items-center gap-2 rounded-md border border-danger/40 bg-danger-bg px-4 py-2 text-sm text-danger"
        >
          <AlertTriangle className="size-4" />
          {t("reviews.error")}
        </div>
      )}

      <Panel>
        {loading ? (
          <div className="flex items-center justify-center gap-2 py-16 text-muted">
            <Loader2 className="size-5 animate-spin" />
            {t("common.loading")}
          </div>
        ) : reviews.length === 0 ? (
          <div className="py-16 text-center text-muted">{t("reviews.empty")}</div>
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{t("reviews.col.guard")}</Th>
                <Th>{t("reviews.col.customer")}</Th>
                <Th>{t("reviews.col.rating")}</Th>
                <Th>{c.colComment}</Th>
                <Th>{t("reviews.col.date")}</Th>
                <Th>{t("reviews.show")}</Th>
              </tr>
            </thead>
            <tbody>
              {reviews.map((r) => {
                const guard = resolve(r.guard_id);
                const customer = resolve(r.customer_id);
                return (
                <Tr key={r.id} onClick={() => setSelected(r)}>
                  <Td>
                    <span className="flex items-center gap-3">
                      <Avatar>{initials(guard.name ?? r.guard_id)}</Avatar>
                      {/* Names resolved via the admin name-resolver; short-id fallback when absent. */}
                      <span
                        className={cn(
                          "text-xs font-semibold text-text-strong",
                          guard.name ? "" : "font-mono",
                        )}
                        title={r.guard_id}
                      >
                        {guard.label}
                      </span>
                    </span>
                  </Td>
                  <Td
                    className={cn("text-xs text-muted", customer.name ? "" : "font-mono")}
                    title={r.customer_id}
                  >
                    {customer.label}
                  </Td>
                  <Td>
                    <Stars value={r.overall_rating} />
                  </Td>
                  <Td className="max-w-[280px] truncate text-muted" title={r.review_text ?? undefined}>
                    {r.review_text ?? t("common.none")}
                  </Td>
                  <Td className="whitespace-nowrap font-mono text-[13px] text-muted">
                    {shortDate(r.created_at, lang)}
                  </Td>
                  <Td>
                    <VisToggle
                      checked={r.is_visible}
                      disabled={actingId === r.id}
                      testId={`review-toggle-${r.id}`}
                      label={t("reviews.filter.visibility")}
                      onToggle={() => void toggleVisibility(r)}
                    />
                  </Td>
                </Tr>
                );
              })}
            </tbody>
          </Table>
        )}
      </Panel>

      {/* Review detail modal — populated from the already-fetched row (no extra endpoint). */}
      {selected && (
        <Modal
          open
          onClose={() => setSelected(null)}
          title={c.detailTitle}
          footer={
            <>
              <Button
                variant="danger-ghost"
                size="sm"
                onClick={() => {
                  const row = selected;
                  setSelected(null);
                  void toggleVisibility(row);
                }}
              >
                {selected.is_visible ? c.hideReview : c.showReview}
              </Button>
              <Button variant="secondary" size="sm" onClick={() => setSelected(null)}>
                {t("common.close")}
              </Button>
            </>
          }
        >
          <div className="flex items-center gap-3">
            <Avatar size="lg" className="size-[46px] text-base">
              {initials(resolve(selected.guard_id).name ?? selected.guard_id)}
            </Avatar>
            <div className="min-w-0">
              <div
                className={cn(
                  "truncate text-[13px] font-semibold text-text-strong",
                  resolve(selected.guard_id).name ? "" : "font-mono",
                )}
                title={selected.guard_id}
              >
                {resolve(selected.guard_id).label}
              </div>
              <div className="text-[12.5px] text-muted" title={selected.customer_id}>
                {c.reviewedBy} {resolve(selected.customer_id).label} ·{" "}
                {fullDate(selected.created_at, lang)}
              </div>
            </div>
            <div className="ml-auto flex flex-none flex-col items-end gap-1">
              <span className="font-mono text-2xl font-semibold text-text-strong">
                {selected.overall_rating.toFixed(1)}
              </span>
              <Stars value={selected.overall_rating} />
            </div>
          </div>

          <div className="mt-5 rounded-xl bg-sunken px-4 py-3.5 text-[14.5px] leading-[1.6] text-text">
            {selected.review_text ?? t("common.none")}
          </div>

          <div className="mt-5">
            <div className="mb-3.5 text-[13px] font-semibold text-text">{c.breakdown}</div>
            <CatBar label={c.catOverall} value={selected.overall_rating} />
            <CatBar label={c.catPunctuality} value={selected.punctuality} />
            <CatBar label={c.catProfessionalism} value={selected.professionalism} />
            <CatBar label={c.catCommunication} value={selected.communication} />
            <CatBar label={c.catAppearance} value={selected.appearance} />
          </div>
        </Modal>
      )}
    </div>
  );
}

/** Two-character avatar "initials" from the resolved guard name (preferred) — or, when no name is
 * available, the guard UUID prefix as a stable fallback. */
function initials(nameOrId: string): string {
  return nameOrId.slice(0, 2).toUpperCase();
}

/** Table date per the design: abbreviated day+month (e.g. "3 มิ.ย."). Gregorian calendar so the
 * modal year matches the design's CE year, not the th-TH default Buddhist era. */
function shortDate(iso: string, lang: "th" | "en"): string {
  return new Intl.DateTimeFormat(lang === "th" ? "th-TH-u-ca-gregory" : "en-GB", {
    day: "numeric",
    month: "short",
  }).format(new Date(iso));
}

/** Modal date per the design: "3 มิ.ย. 2026". */
function fullDate(iso: string, lang: "th" | "en"): string {
  return new Intl.DateTimeFormat(lang === "th" ? "th-TH-u-ca-gregory" : "en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
  }).format(new Date(iso));
}

/** Design `.stars-sm` — five 14px amber stars, filled up to `value`, outlined after. */
function Stars({ value }: { value: number }) {
  return (
    <span className="inline-flex items-center gap-[2px] text-amber-400">
      {[1, 2, 3, 4, 5].map((i) => (
        <Star key={i} size={14} className={i <= value ? "fill-current" : "fill-none"} />
      ))}
    </span>
  );
}

/** Design `.catbar` — 130px label, amber fill on a sunken track, mono value. Sub-ratings are
 * nullable in the contract; a missing category renders an empty track + em dash (never faked). */
function CatBar({ label, value }: { label: string; value?: number | null }) {
  return (
    <div className="mb-3 flex items-center gap-3 last:mb-0">
      <span className="w-[130px] flex-none text-[13px] text-text">{label}</span>
      <span className="h-2 flex-1 overflow-hidden rounded-[4px] bg-sunken">
        {value != null ? (
          <span
            className="block h-full rounded-[4px] bg-amber-400"
            style={{ width: `${Math.min(100, (value / 5) * 100)}%` }}
          />
        ) : null}
      </span>
      <span className="w-8 flex-none text-right font-mono text-[13px] font-semibold text-text-strong">
        {value != null ? value.toFixed(1) : "—"}
      </span>
    </div>
  );
}

/** Design `.tgl` (44×26 switch) carrying the e2e contract: data-testid="review-toggle-<id>" +
 * aria-pressed. Page-local because the shared ui/Toggle can't take the testid/aria-pressed pair.
 * stopPropagation keeps the toggle from also opening the row's detail modal. */
function VisToggle({
  checked,
  disabled,
  testId,
  label,
  onToggle,
}: {
  checked: boolean;
  disabled?: boolean;
  testId: string;
  label: string;
  onToggle: () => void;
}) {
  return (
    <button
      type="button"
      data-testid={testId}
      aria-pressed={checked}
      aria-label={label}
      disabled={disabled}
      onClick={(e) => {
        e.stopPropagation();
        onToggle();
      }}
      className={cn(
        "relative h-[26px] w-11 flex-none cursor-pointer rounded-full transition-colors duration-200 disabled:cursor-not-allowed disabled:opacity-50",
        checked ? "bg-brand-int" : "bg-n-300",
      )}
    >
      <span
        className={cn(
          "absolute top-[3px] size-5 rounded-full bg-white shadow-xs transition-[left] duration-200",
          checked ? "left-[21px]" : "left-[3px]",
        )}
      />
    </button>
  );
}

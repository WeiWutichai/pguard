"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, Download, Loader2, RefreshCw, TrendingDown, TrendingUp } from "lucide-react";

import type { components as PaymentComponents } from "@/api/generated/payment";
import type { components as BookingComponents } from "@/api/generated/booking";
import { Badge, Button, Chip, PageIntro, Panel, PanelBody, PanelHead } from "@/components/ui";
import { bookingApi, paymentApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import { COPY, fmtBaht, fmtDay, HOUR_BUCKETS, RANGE_DAYS, type RangeDays } from "./copy";

type RevenueReport = PaymentComponents["schemas"]["RevenueReport"];
type BookingsReport = BookingComponents["schemas"]["BookingsReport"];

const CHART_W = 520;
const CHART_H = 180;

export default function ReportsPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [revenue, setRevenue] = useState<RevenueReport | null>(null);
  const [bookings, setBookings] = useState<BookingsReport | null>(null);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [rangeDays, setRangeDays] = useState<RangeDays>(30);
  const [reloadNonce, setReloadNonce] = useState(0);

  const fetchInto = useCallback(
    (days: number, alive: () => boolean) => {
      const to = new Date();
      const from = new Date(to.getTime() - days * 86_400_000);
      const query = { from: from.toISOString(), to: to.toISOString() };
      return Promise.all([
        paymentApi.GET("/admin/reports/revenue", { params: { query } }),
        bookingApi.GET("/admin/reports/bookings", { params: { query } }),
      ])
        .then(([revRes, bkRes]) => {
          if (!alive()) return;
          setHasError(Boolean(revRes.error || bkRes.error));
          setRevenue(revRes.error ? null : (revRes.data?.data ?? null));
          setBookings(bkRes.error ? null : (bkRes.data?.data ?? null));
          setLoading(false);
        })
        .catch(() => {
          if (!alive()) return;
          setHasError(true);
          setLoading(false);
        });
    },
    [],
  );

  useEffect(() => {
    let alive = true;
    void fetchInto(rangeDays, () => alive);
    return () => {
      alive = false;
    };
  }, [rangeDays, reloadNonce, fetchInto]);

  function reload() {
    setLoading(true);
    setHasError(false);
    setReloadNonce((n) => n + 1);
  }

  // --- merged revenue/bookings series (aligned by date) ---
  const chart = useMemo(() => {
    const revMap = new Map((revenue?.series ?? []).map((p) => [p.date, parseFloat(p.revenue)]));
    const bkMap = new Map((bookings?.daily ?? []).map((d) => [d.date, d.count]));
    const dates = [...new Set([...revMap.keys(), ...bkMap.keys()])].sort();
    const revVals = dates.map((d) => revMap.get(d) ?? 0);
    const bkVals = dates.map((d) => bkMap.get(d) ?? 0);
    const maxRev = Math.max(1, ...revVals);
    const maxBk = Math.max(1, ...bkVals);
    const n = dates.length;
    const px = (i: number) => (n <= 1 ? 0 : (i / (n - 1)) * CHART_W);
    const revPts = revVals.map((v, i) => `${px(i)},${CHART_H - (v / maxRev) * CHART_H}`).join(" ");
    const bkPts = bkVals.map((v, i) => `${px(i)},${CHART_H - (v / maxBk) * CHART_H}`).join(" ");
    return { dates, revVals, bkVals, revPts, bkPts };
  }, [revenue, bookings]);

  // --- utilization heatmap grid [dow 0..6][bucket 0..11] ---
  const heat = useMemo(() => {
    const grid: number[][] = Array.from({ length: 7 }, () => Array(12).fill(0));
    for (const cell of bookings?.utilization ?? []) {
      if (cell.dow >= 0 && cell.dow < 7 && cell.bucket >= 0 && cell.bucket < 12) {
        grid[cell.dow][cell.bucket] = cell.hours;
      }
    }
    const max = Math.max(1, ...grid.flat());
    return { grid, max };
  }, [bookings]);

  const mom = revenue?.mom_pct ?? null;
  const isEmpty = !loading && !hasError && chart.dates.length === 0;

  function exportCsv() {
    const revMap = new Map((revenue?.series ?? []).map((p) => [p.date, p.revenue]));
    const bkMap = new Map((bookings?.daily ?? []).map((d) => [d.date, d.count]));
    const rows = [
      ["date", "revenue", "bookings"],
      ...chart.dates.map((d) => [d, revMap.get(d) ?? "0", String(bkMap.get(d) ?? 0)]),
    ];
    const csv = rows.map((r) => r.join(",")).join("\n");
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `pguard-report-${rangeDays}d.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div>
      <PageIntro title={c.title} lead={c.subtitle}>
        <div className="flex gap-2">
          {RANGE_DAYS.map((d) => (
            <Chip key={d} active={rangeDays === d} onClick={() => setRangeDays(d)}>
              {c.rangeLabel(d)}
            </Chip>
          ))}
        </div>
        <Button variant="secondary" size="sm" onClick={exportCsv} disabled={chart.dates.length === 0}>
          <Download size={15} />
          {c.exportCsv}
        </Button>
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
          {t("reports.error")}
        </div>
      )}

      {loading ? (
        <div className="flex items-center justify-center gap-2 py-24 text-muted">
          <Loader2 className="size-5 animate-spin" />
          {t("common.loading")}
        </div>
      ) : (
        <div className="grid items-start gap-[18px] lg:grid-cols-2">
          {/* ---- revenue trend ---- */}
          <Panel>
            <PanelHead title={c.revenueHead}>
              {mom != null && (
                <Badge tone={mom >= 0 ? "green" : "red"}>
                  {mom >= 0 ? <TrendingUp size={13} /> : <TrendingDown size={13} />}
                  {`${mom >= 0 ? "+" : ""}${mom.toFixed(0)}% ${c.momLabel}`}
                </Badge>
              )}
            </PanelHead>
            <PanelBody>
              {isEmpty ? (
                <div className="py-16 text-center text-muted">{t("reports.empty")}</div>
              ) : (
                <>
                  <svg viewBox={`0 0 ${CHART_W} ${CHART_H}`} className="h-auto w-full" role="img">
                    {[0.25, 0.5, 0.75].map((g) => (
                      <line
                        key={g}
                        x1={0}
                        y1={CHART_H * g}
                        x2={CHART_W}
                        y2={CHART_H * g}
                        style={{ stroke: "var(--border)" }}
                        strokeWidth={1}
                      />
                    ))}
                    <polyline
                      points={chart.revPts}
                      fill="none"
                      style={{ stroke: "var(--brand-int)" }}
                      strokeWidth={3}
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    />
                    <polyline
                      points={chart.bkPts}
                      fill="none"
                      style={{ stroke: "var(--amber-400, #f0b429)" }}
                      strokeWidth={2.5}
                      strokeDasharray="4 4"
                      strokeLinecap="round"
                    />
                  </svg>
                  <div className="mt-3 flex items-center gap-4 text-[12.5px] text-muted">
                    <span className="inline-flex items-center gap-1.5">
                      <span className="size-2.5 rounded-sm" style={{ background: "var(--brand-int)" }} />
                      {c.revenueLegend}
                    </span>
                    <span className="inline-flex items-center gap-1.5">
                      <span
                        className="size-2.5 rounded-sm"
                        style={{ background: "var(--amber-400, #f0b429)" }}
                      />
                      {c.bookingsLegend}
                    </span>
                    <span className="ml-auto font-mono text-text-strong">
                      {fmtBaht(revenue?.total)} · {bookings?.total ?? 0} {c.totalBookings}
                    </span>
                  </div>
                </>
              )}
            </PanelBody>
          </Panel>

          {/* ---- bookings by service — honest gap (no service_type in v2) ---- */}
          <Panel>
            <PanelHead title={c.byServiceHead} />
            <PanelBody>
              <div className="flex items-start gap-2 rounded-lg border border-dashed border-border bg-sunken px-4 py-6 text-[12.5px] text-muted">
                <Badge tone="gray">{t("gap.endpoints")}</Badge>
                <span>{c.byServiceGap}</span>
              </div>
            </PanelBody>
          </Panel>

          {/* ---- guard utilization heatmap ---- */}
          <Panel>
            <PanelHead title={c.utilizationHead}>
              <span className="text-[12.5px] text-muted">{c.utilizationUnit}</span>
            </PanelHead>
            <PanelBody>
              <div className="grid gap-1 text-[11px]" style={{ gridTemplateColumns: "auto repeat(12, 1fr)" }}>
                <div />
                {HOUR_BUCKETS.map((h) => (
                  <div key={h} className="text-center text-muted">
                    {h}
                  </div>
                ))}
                {c.dow.map((label, d) => (
                  <FragmentRow key={d}>
                    <div className="flex items-center pr-1.5 text-muted">{label}</div>
                    {Array.from({ length: 12 }, (_, b) => {
                      const pct = Math.round((heat.grid[d][b] / heat.max) * 100);
                      return (
                        <div
                          key={b}
                          className="rounded-[4px]"
                          style={{
                            aspectRatio: "1.4",
                            background: `color-mix(in srgb, var(--brand-int) ${Math.max(6, pct)}%, transparent)`,
                          }}
                          title={`${label} ${b * 2}:00 — ${heat.grid[d][b]}`}
                        />
                      );
                    })}
                  </FragmentRow>
                ))}
              </div>
            </PanelBody>
          </Panel>

          {/* ---- retention cohort ---- */}
          <Panel>
            <PanelHead title={c.retentionHead} />
            <PanelBody>
              {(bookings?.retention ?? []).length === 0 ? (
                <div className="py-10 text-center text-muted">{t("reports.empty")}</div>
              ) : (
                <div className="flex flex-col gap-3">
                  {(bookings?.retention ?? []).map((pt) => (
                    <div key={pt.week} className="flex items-center gap-3">
                      <span className="w-20 text-[12.5px] text-muted">{c.weekLabel(pt.week)}</span>
                      <div className="h-[22px] flex-1 overflow-hidden rounded-md bg-sunken">
                        <div
                          className="h-full rounded-md"
                          style={{
                            width: `${Math.max(0, Math.min(100, pt.pct))}%`,
                            background: "var(--brand-int)",
                          }}
                        />
                      </div>
                      <span className="w-10 text-right font-mono text-[12.5px] font-semibold text-text-strong">
                        {pt.pct.toFixed(0)}%
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </PanelBody>
          </Panel>
        </div>
      )}
    </div>
  );
}

/** A row of heatmap cells — a fragment so each row's label + 12 cells flow into the parent grid. */
function FragmentRow({ children }: { children: React.ReactNode }) {
  return <>{children}</>;
}

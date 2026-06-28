"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, CalendarClock, FileWarning, Loader2, RefreshCw } from "lucide-react";

import type { components as ProfileComponents } from "@/api/generated/profile";
import {
  Badge,
  Button,
  Chip,
  KpiCard,
  KpiGrid,
  PageIntro,
  Panel,
  Table,
  Td,
  Th,
  Tr,
} from "@/components/ui";
import { notificationApi, profileApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import { useNameResolver } from "@/lib/use-names";

import { COPY, type DocType, type WindowKey } from "./copy";

type DocumentExpiry = ProfileComponents["schemas"]["DocumentExpiry"];
type ExpiringBuckets = ProfileComponents["schemas"]["ExpiringDocumentBuckets"];

// The selectable list windows map to the endpoint's `window` query (days). "expired" has no
// dedicated window value (the 7-day window already includes the expired band, soonest-first), so
// it reuses window=7 and the page filters the list to days_left<0 client-side.
const WINDOW_PARAM: Record<WindowKey, 7 | 30 | 90> = {
  expired: 7,
  "7": 7,
  "30": 30,
  "90": 90,
};

export default function ExpiringPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [docs, setDocs] = useState<DocumentExpiry[]>([]);
  // Window-INDEPENDENT bucket counts from the API (disjoint bands) — drive the KPI strip + tab
  // pills so they don't shift as the list filter narrows. Null until the first load succeeds.
  const [buckets, setBuckets] = useState<ExpiringBuckets | null>(null);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [window, setWindow] = useState<WindowKey>("expired");
  const [reminded, setReminded] = useState<Record<string, "sending" | "sent" | "error">>({});

  const fetchInto = useCallback(
    (w: WindowKey, alive: () => boolean) => {
      return profileApi
        .GET("/admin/documents/expiring", {
          params: { query: { window: WINDOW_PARAM[w] } },
        })
        .then((res) => {
          if (!alive()) return;
          setHasError(Boolean(res.error));
          setDocs(res.error ? [] : (res.data?.data?.documents ?? []));
          // Buckets are window-independent — only overwrite on a clean fetch (keep the last good
          // counts on error rather than blanking the KPIs).
          if (!res.error && res.data?.data?.buckets) setBuckets(res.data.data.buckets);
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
    void fetchInto(window, () => alive);
    return () => {
      alive = false;
    };
  }, [window, reloadNonce, fetchInto]);

  function reload() {
    setLoading(true);
    setHasError(false);
    setReloadNonce((n) => n + 1);
  }

  function selectWindow(next: WindowKey) {
    if (next === window) return;
    setLoading(true);
    setWindow(next);
  }

  // Resolve guard ids → display names (one batch call; short-id fallback when a name is absent).
  const guardIds = useMemo(() => docs.map((d) => d.guard_id), [docs]);
  const { resolve } = useNameResolver(guardIds, lang);

  // The endpoint returns the chosen window's docs soonest-first; the "expired" tab reuses the
  // 7-day window so it can show the already-lapsed band, then narrows client-side to days_left<0.
  const visible = useMemo(
    () => (window === "expired" ? docs.filter((d) => d.days_left < 0) : docs),
    [docs, window],
  );

  async function remind(d: DocumentExpiry) {
    setReminded((m) => ({ ...m, [d.id]: "sending" }));
    const label = c.docLabel[d.document_type as DocType] ?? d.document_type;
    const res = await notificationApi.POST("/notifications/send", {
      body: {
        user_id: d.guard_id,
        title: lang === "th" ? "เอกสารใกล้หมดอายุ" : "Document expiring",
        body:
          lang === "th"
            ? `กรุณาอัปโหลด${label}ใหม่ก่อนหมดอายุ`
            : `Please re-upload your ${label} before it expires`,
        notification_type: "system",
      },
    });
    setReminded((m) => ({ ...m, [d.id]: res.error ? "error" : "sent" }));
  }

  // Tab/KPI counts from the API buckets (window-independent). "—" until the first load.
  const TABS: { key: WindowKey; label: string; count: number | null }[] = [
    { key: "expired", label: c.tabExpired, count: buckets?.expired ?? null },
    { key: "7", label: c.tab7, count: buckets?.due_7 ?? null },
    { key: "30", label: c.tab30, count: buckets?.due_30 ?? null },
    { key: "90", label: c.tab90, count: buckets?.due_90 ?? null },
  ];

  return (
    <div>
      <PageIntro title={c.title} lead={t("expiring.subtitle")}>
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
          {t("expiring.error")}
        </div>
      )}

      <KpiGrid>
        <KpiCard
          icon={<FileWarning />}
          label={c.kpiExpired}
          value={buckets ? String(buckets.expired) : "—"}
        />
        <KpiCard
          icon={<CalendarClock />}
          label={c.kpi7}
          value={buckets ? String(buckets.due_7) : "—"}
        />
        <KpiCard
          icon={<CalendarClock />}
          label={c.kpi30}
          value={buckets ? String(buckets.due_30) : "—"}
        />
        <KpiCard
          icon={<CalendarClock />}
          label={c.kpi90}
          value={buckets ? String(buckets.due_90) : "—"}
        />
      </KpiGrid>

      {/* Expiry dates are captured at guard registration; the document image upload remains a
          follow-up — honest note (rows appear as guards submit, not faked). */}
      <div className="mb-4 flex items-start gap-2 rounded-lg border border-border bg-sunken px-4 py-2.5 text-[12.5px] text-muted">
        <Badge tone="gray">{t("gap.endpoints")}</Badge>
        <span>{c.captureGap}</span>
      </div>

      <div className="mb-4 flex flex-wrap items-center gap-2.5">
        {TABS.map((tab) => (
          <Chip key={tab.key} active={window === tab.key} onClick={() => selectWindow(tab.key)}>
            {tab.label} {tab.count == null ? "" : `(${tab.count})`}
          </Chip>
        ))}
      </div>

      <Panel>
        {loading ? (
          <div className="flex items-center justify-center gap-2 py-16 text-muted">
            <Loader2 className="size-5 animate-spin" />
            {t("common.loading")}
          </div>
        ) : visible.length === 0 ? (
          <div className="py-16 text-center text-muted">{t("expiring.empty")}</div>
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{c.colGuard}</Th>
                <Th>{c.colDoc}</Th>
                <Th>{c.colExpiry}</Th>
                <Th>{c.colRemaining}</Th>
                <Th>{c.colReminded}</Th>
                <Th>{""}</Th>
              </tr>
            </thead>
            <tbody>
              {visible.map((d) => {
                // days_left from the API (expiry_date − current_date, computed in SQL).
                const days = d.days_left;
                const tone = days < 0 ? "red" : days <= 30 ? "amber" : "green";
                const state = reminded[d.id];
                const guard = resolve(d.guard_id);
                return (
                  <Tr key={d.id}>
                    <Td title={d.guard_id}>
                      <span
                        className={
                          guard.name
                            ? "font-semibold text-text-strong"
                            : "font-mono font-semibold text-text-strong"
                        }
                      >
                        {guard.label}
                      </span>
                    </Td>
                    <Td>{c.docLabel[d.document_type as DocType] ?? d.document_type}</Td>
                    <Td className="font-mono text-muted tabular-nums">
                      {new Date(d.expiry_date + "T00:00:00Z").toLocaleDateString(
                        lang === "th" ? "th-TH" : "en-GB",
                        { year: "numeric", month: "short", day: "numeric" },
                      )}
                    </Td>
                    <Td>
                      <Badge tone={tone}>{days < 0 ? c.overdue(-days) : c.daysLeft(days)}</Badge>
                    </Td>
                    <Td className="font-mono text-muted tabular-nums">
                      {d.last_reminded_at
                        ? new Date(d.last_reminded_at).toLocaleDateString(
                            lang === "th" ? "th-TH" : "en-GB",
                            { month: "short", day: "numeric" },
                          )
                        : c.never}
                    </Td>
                    <Td>
                      <Button
                        variant="secondary"
                        size="sm"
                        disabled={state === "sending" || state === "sent"}
                        onClick={() => remind(d)}
                      >
                        {state === "sending"
                          ? c.reminding
                          : state === "sent"
                            ? c.reminded
                            : state === "error"
                              ? c.remindError
                              : c.remind}
                      </Button>
                    </Td>
                  </Tr>
                );
              })}
            </tbody>
          </Table>
        )}
      </Panel>
    </div>
  );
}

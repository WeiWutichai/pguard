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

import { COPY, type DocType, daysUntil, type WindowKey, WINDOWS } from "./copy";

type DocumentExpiry = ProfileComponents["schemas"]["DocumentExpiry"];

export default function ExpiringPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [docs, setDocs] = useState<DocumentExpiry[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [window, setWindow] = useState<WindowKey>("expired");
  const [reminded, setReminded] = useState<Record<string, "sending" | "sent" | "error">>({});

  const fetchInto = useCallback((alive: () => boolean) => {
    return profileApi
      .GET("/admin/documents/expiring")
      .then((res) => {
        if (!alive()) return;
        setHasError(Boolean(res.error));
        setDocs(res.error ? [] : (res.data?.data ?? []));
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

  // Bucket counts (a doc falls in the lowest window it qualifies for; KPIs are cumulative
  // like the design — "within 30" includes "within 7").
  const counts = useMemo(() => {
    let expired = 0,
      w7 = 0,
      w30 = 0,
      w90 = 0;
    for (const d of docs) {
      const days = daysUntil(d.expiry_date);
      if (days < 0) expired++;
      else if (days <= 7) w7++;
      else if (days <= 30) w30++;
      else w90++;
    }
    return { expired, w7: w7, w30, w90 };
  }, [docs]);

  const visible = useMemo(() => {
    return docs.filter((d) => {
      const days = daysUntil(d.expiry_date);
      if (window === "expired") return days < 0;
      if (window === "7") return days >= 0 && days <= 7;
      if (window === "30") return days >= 0 && days <= 30;
      return days >= 0 && days <= 90;
    });
  }, [docs, window]);

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

  const TABS: { key: WindowKey; label: string; count: number }[] = [
    { key: "expired", label: c.tabExpired, count: counts.expired },
    { key: "7", label: c.tab7, count: counts.w7 },
    { key: "30", label: c.tab30, count: counts.w30 },
    { key: "90", label: c.tab90, count: counts.w90 },
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
        <KpiCard icon={<FileWarning />} label={c.kpiExpired} value={loading ? "…" : String(counts.expired)} />
        <KpiCard icon={<CalendarClock />} label={c.kpi7} value={loading ? "…" : String(counts.w7)} />
        <KpiCard icon={<CalendarClock />} label={c.kpi30} value={loading ? "…" : String(counts.w30)} />
        <KpiCard icon={<CalendarClock />} label={c.kpi90} value={loading ? "…" : String(counts.w90)} />
      </KpiGrid>

      {/* Expiry dates are captured at guard registration; the document image upload remains a
          follow-up — honest note (rows appear as guards submit, not faked). */}
      <div className="mb-4 flex items-start gap-2 rounded-lg border border-border bg-sunken px-4 py-2.5 text-[12.5px] text-muted">
        <Badge tone="gray">{t("gap.endpoints")}</Badge>
        <span>{c.captureGap}</span>
      </div>

      <div className="mb-4 flex flex-wrap items-center gap-2.5">
        {TABS.map((tab) => (
          <Chip key={tab.key} active={window === tab.key} onClick={() => setWindow(tab.key)}>
            {tab.label} ({tab.count})
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
                const days = daysUntil(d.expiry_date);
                const tone = days < 0 ? "red" : days <= 30 ? "amber" : "green";
                const state = reminded[d.id];
                return (
                  <Tr key={d.id}>
                    <Td className="font-mono font-semibold text-text-strong">#{d.guard_id.slice(0, 8)}</Td>
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

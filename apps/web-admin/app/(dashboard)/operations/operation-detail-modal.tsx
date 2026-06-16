"use client";

import { type ReactNode, useEffect, useState } from "react";
import { AlertTriangle, Camera, Check, Loader2 } from "lucide-react";

import type { components } from "@/api/generated/booking";
import { Button, Modal } from "@/components/ui";
import { bookingApi, notificationApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import { COPY } from "./copy";

type Booking = components["schemas"]["Booking"];
type ProgressReport = components["schemas"]["ProgressReport"];

function StatMini({ label, value }: { label: ReactNode; value: ReactNode }) {
  return (
    <div className="rounded-md bg-sunken px-3.5 py-[13px]">
      <div className="text-[11.5px] text-muted">{label}</div>
      <div className="mt-1 text-[15px] font-semibold text-text-strong">{value}</div>
    </div>
  );
}

/** Live-ops drawer: the guard's hourly check-in trail for one active booking (real —
 * booking `listProgressReports`, admin-readable). Each booked hour shows its report
 * (photo + GPS + note + time) or a "no report" placeholder. Missed-vs-pending can't be
 * told apart without `work_started_at` (not exposed), so unreported hours are shown
 * neutrally. Nudge-guard needs the notification surface (not in the web-admin client) →
 * disabled behind a gap chip; Open map links to the live map. */
export function OperationDetailModal({
  booking,
  heading,
  onClose,
}: {
  booking: Booking;
  heading: string;
  onClose: () => void;
}) {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [reports, setReports] = useState<ProgressReport[]>([]);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);
  const [nudging, setNudging] = useState(false);
  const [nudgeNotice, setNudgeNotice] = useState<{ ok: boolean; text: string } | null>(null);

  // Nudge the assigned guard with a push (admin-only POST /notifications/send). The guard's app is
  // Thai-default, so the notification copy is Thai; the admin-facing result follows the admin's UI.
  async function nudge() {
    if (!booking.guard_id) return;
    setNudging(true);
    setNudgeNotice(null);
    const { error } = await notificationApi.POST("/notifications/send", {
      body: {
        user_id: booking.guard_id,
        title: "เตือนเช็คอิน",
        body: "แอดมินขอให้คุณอัปเดตสถานะงาน",
        notification_type: "system",
      },
    });
    setNudging(false);
    setNudgeNotice(
      error
        ? { ok: false, text: lang === "th" ? "ส่งไม่สำเร็จ" : "Couldn't send" }
        : { ok: true, text: lang === "th" ? "ส่งการเตือนแล้ว" : "Reminder sent" },
    );
  }

  useEffect(() => {
    let alive = true;
    bookingApi
      .GET("/bookings/{id}/progress-reports", { params: { path: { id: booking.id } } })
      .then(({ data, error }) => {
        if (!alive) return;
        setFailed(Boolean(error));
        setReports(error ? [] : (data?.data ?? []));
        setLoading(false);
      })
      .catch(() => {
        if (!alive) return;
        setFailed(true);
        setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, [booking.id]);

  const byHour = new Map(reports.map((r) => [r.hour_number, r]));
  const hours = booking.hours ?? 0;
  const reportedCount = reports.length;

  return (
    <Modal
      open
      onClose={onClose}
      size="lg"
      title={c.detailTitle}
      footer={
        <>
          <Button variant="secondary" size="sm" onClick={onClose}>
            {t("common.close")}
          </Button>
          {nudgeNotice && (
            <span
              className={
                "text-[12.5px] " + (nudgeNotice.ok ? "text-success" : "text-danger")
              }
            >
              {nudgeNotice.text}
            </span>
          )}
          <Button
            variant="primary"
            size="sm"
            disabled={!booking.guard_id || nudging}
            onClick={nudge}
          >
            {nudging ? <Loader2 className="size-4 animate-spin" /> : null}
            {c.nudge}
          </Button>
        </>
      }
    >
      <div className="min-w-0">
        <div className="font-mono text-xs text-muted">#{booking.id.slice(0, 8)}</div>
        <div className="mt-0.5 truncate text-lg font-semibold text-text-strong">{heading}</div>
        <div className="mt-0.5 text-[12.5px] text-muted">{booking.address}</div>
      </div>

      <div className="mt-4 grid grid-cols-3 gap-2">
        <StatMini
          label={c.checkIns}
          value={loading ? "…" : `${reportedCount}/${hours}`}
        />
        <StatMini
          label={c.missed}
          value={
            loading ? (
              "…"
            ) : (
              <span className={hours - reportedCount > 0 ? "text-danger" : undefined}>
                {Math.max(0, hours - reportedCount)}
              </span>
            )
          }
        />
        <StatMini label={c.bookedHours} value={`${hours}${c.hoursUnit}`} />
      </div>

      <div className="mt-4 rounded-lg border border-border">
        <div className="flex items-center gap-2 px-4 py-3">
          <span className="text-xs font-semibold uppercase tracking-[0.04em] text-muted">
            {c.reportsTab}
          </span>
        </div>

        {loading ? (
          <div className="flex items-center justify-center gap-2 py-10 text-muted">
            <Loader2 className="size-5 animate-spin" />
            {t("common.loading")}
          </div>
        ) : failed ? (
          <div
            role="alert"
            className="mx-4 mb-4 flex items-center gap-2 rounded-lg border border-danger/40 bg-danger-bg px-3 py-2 text-[12.5px] text-danger"
          >
            <AlertTriangle className="size-4 flex-none" />
            {t("common.retry")}
          </div>
        ) : hours === 0 ? (
          <div className="px-4 pb-4 text-sm text-muted">{c.noReports}</div>
        ) : (
          <ul className="px-4 pb-2">
            {Array.from({ length: hours }, (_, i) => i + 1).map((h) => {
              const r = byHour.get(h);
              return (
                <li
                  key={h}
                  className="flex items-center gap-3 border-b border-border py-3 last:border-0"
                >
                  <div
                    className={
                      "flex size-7 flex-none items-center justify-center rounded-full font-mono text-[11px] font-semibold " +
                      (r ? "bg-success-bg text-success" : "bg-sunken text-muted")
                    }
                  >
                    {r ? <Check className="size-3.5" /> : h}
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="text-[13.5px] font-semibold text-text-strong">
                      {c.hour} {h}
                      {r ? "" : ` · ${c.missedCheckIn}`}
                    </div>
                    {r && (
                      <div className="truncate font-mono text-[11.5px] text-muted">
                        {new Date(r.created_at).toLocaleTimeString(lang === "th" ? "th-TH" : "en-GB", {
                          hour: "2-digit",
                          minute: "2-digit",
                        })}
                        {r.lat != null && r.lng != null
                          ? ` · ${r.lat.toFixed(3)}, ${r.lng.toFixed(3)}`
                          : ""}
                        {r.note ? ` · ${r.note}` : ""}
                      </div>
                    )}
                  </div>
                  {r?.photo_url ? (
                    // eslint-disable-next-line @next/next/no-img-element -- presigned S3 URL, not a static asset
                    <img
                      src={r.photo_url}
                      alt={`${c.hour} ${h}`}
                      className="size-12 flex-none rounded-md object-cover"
                    />
                  ) : r ? (
                    <Camera className="size-5 flex-none text-faint" />
                  ) : null}
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </Modal>
  );
}

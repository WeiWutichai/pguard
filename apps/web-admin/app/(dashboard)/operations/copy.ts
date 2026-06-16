// Screen-local bilingual copy for the operations (ปฏิบัติการสด) live-ops screen. NEW design
// strings only (Admin - Operations); shared strings via src/lib/i18n.tsx (single-writer).
//
// Contract reality: an "active" job = a booking in one of the in-flight v2 statuses. The
// design's `started` stage and the overdue/elapsed alerts need `work_started_at`, which the
// public Booking response does NOT expose — those render as honest gaps, never computed from
// nothing. GPS freshness is real (presence `is_live`/`is_online`/`recorded_at`); the
// progress-reports drawer is real (booking listProgressReports). Nudge-guard + dispute/refund
// need the notification + payment surfaces (not in the web-admin generated client) → disabled.
import type { Lang } from "@/lib/lang";

/** The in-flight v2 statuses a live-ops board tracks (BookingStatus minus terminal +
 * requested). `accepted` = a guard claimed it; then en_route → arrived → pending_completion. */
export const ACTIVE_STATUSES = ["accepted", "en_route", "arrived", "pending_completion"] as const;
export type ActiveStatus = (typeof ACTIVE_STATUSES)[number];

/** The status timeline stages, in order (the v2 lifecycle — no `started`/`assigned`). */
export const TIMELINE: ActiveStatus[] = ["accepted", "en_route", "arrived", "pending_completion"];

export interface OperationsCopy {
  title: string;
  subtitle: (n: string) => string;
  kpiActive: string;
  kpiEnRoute: string;
  kpiArrived: string;
  kpiPending: string;
  searchPlaceholder: string;
  guard: string;
  gpsLive: string;
  gpsStale: string;
  gpsOffline: string;
  gpsNone: string;
  /** drawer */
  detailTitle: string;
  reportsTab: string;
  checkIns: string;
  missed: string;
  bookedHours: string;
  hour: string;
  noReports: string;
  missedCheckIn: string;
  openMap: string;
  nudge: string;
  hoursUnit: string;
  statusLabel: Record<ActiveStatus, string>;
  stageLabel: Record<ActiveStatus, string>;
  of: string;
}

export const COPY: Record<Lang, OperationsCopy> = {
  th: {
    title: "ปฏิบัติการสด",
    subtitle: (n) => `งานที่กำลังดำเนินอยู่ ${n} งาน`,
    kpiActive: "งานกำลังดำเนิน",
    kpiEnRoute: "กำลังเดินทาง",
    kpiArrived: "ถึงจุดแล้ว",
    kpiPending: "รอยืนยันจบงาน",
    searchPlaceholder: "ค้นหา booking / ลูกค้า / ที่อยู่…",
    guard: "เจ้าหน้าที่",
    gpsLive: "GPS สด",
    gpsStale: "GPS ค้าง",
    gpsOffline: "ออฟไลน์",
    gpsNone: "ไม่มี GPS",
    detailTitle: "ความคืบหน้างาน",
    reportsTab: "รายงานความคืบหน้า",
    checkIns: "เช็คอิน",
    missed: "ขาด",
    bookedHours: "ชั่วโมงที่จอง",
    hour: "ชั่วโมง",
    noReports: "ยังไม่มีการเช็คอิน",
    missedCheckIn: "ไม่มีรายงาน",
    openMap: "เปิดแผนที่",
    nudge: "เตือนเจ้าหน้าที่",
    hoursUnit: "ชม.",
    statusLabel: {
      accepted: "รับงานแล้ว",
      en_route: "กำลังเดินทาง",
      arrived: "ถึงจุดแล้ว",
      pending_completion: "รอยืนยันจบงาน",
    },
    stageLabel: {
      accepted: "รับงาน",
      en_route: "เดินทาง",
      arrived: "ถึง",
      pending_completion: "จบงาน",
    },
    of: "จาก",
  },
  en: {
    title: "Active Operations",
    subtitle: (n) => `${n} jobs in progress`,
    kpiActive: "Active jobs",
    kpiEnRoute: "En route",
    kpiArrived: "Arrived",
    kpiPending: "Pending completion",
    searchPlaceholder: "Search booking / customer / address…",
    guard: "Guard",
    gpsLive: "GPS live",
    gpsStale: "GPS stale",
    gpsOffline: "Offline",
    gpsNone: "No GPS",
    detailTitle: "Job progress",
    reportsTab: "Progress reports",
    checkIns: "Check-ins",
    missed: "Missed",
    bookedHours: "Booked hours",
    hour: "Hour",
    noReports: "No check-ins yet",
    missedCheckIn: "No report",
    openMap: "Open map",
    nudge: "Nudge guard",
    hoursUnit: "h",
    statusLabel: {
      accepted: "Accepted",
      en_route: "En route",
      arrived: "Arrived",
      pending_completion: "Pending completion",
    },
    stageLabel: {
      accepted: "Accepted",
      en_route: "En route",
      arrived: "Arrived",
      pending_completion: "Done",
    },
    of: "of",
  },
};

export type GpsState = "live" | "stale" | "offline" | "none";

/** Map a presence row (or its absence) to a coarse GPS freshness state for the card. */
export function gpsStateOf(
  loc: { is_online?: boolean; is_live?: boolean } | undefined,
): GpsState {
  if (!loc) return "none";
  if (loc.is_live) return "live";
  if (loc.is_online) return "stale";
  return "offline";
}

/** "2 min ago" / "ตอนนี้" style relative label from an ISO timestamp. */
export function relTime(iso: string | undefined, lang: Lang): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  const secs = Math.max(0, Math.round((Date.now() - d.getTime()) / 1000));
  if (secs < 60) return lang === "th" ? `${secs} วินาที` : `${secs}s`;
  const mins = Math.round(secs / 60);
  if (mins < 60) return lang === "th" ? `${mins} นาที` : `${mins}m`;
  const hrs = Math.round(mins / 60);
  return lang === "th" ? `${hrs} ชม.` : `${hrs}h`;
}

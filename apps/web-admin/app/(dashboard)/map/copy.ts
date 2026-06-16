// Screen-local bilingual copy + status maps for the Live Map rebuild (hi-fi spec:
// Web_Admin_Live_Map). src/lib/i18n.tsx is single-writer/shared — NEW design strings live
// here and are selected via useLanguage().lang; existing keys (nav.map, map.*, common.*)
// keep coming from t(). TH strings are verbatim from the design spec.
//
// Honesty note: the design's job-aware status labels ("พร้อมรับงาน/กำลังทำงาน") describe
// booking state we don't have — presence only derives active/idle/offline, so status labels
// reuse the existing map.status.* keys instead of pretending to know job state.
import type { TKey } from "@/lib/i18n";
import type { AvatarStatus } from "@/components/ui";
import type { GuardStatus } from "@/components/guard-map";

export const COPY = {
  th: {
    rosterTitle: "เจ้าหน้าที่ออนไลน์",
    inArea: (n: number) => `${n} คนในพื้นที่`,
    // Short relative time (roster card `.eta .t`).
    agoSec: (n: number) => `${n} วิ`,
    agoMin: (n: number) => `${n} นาที`,
    agoHr: (n: number) => `${n} ชม.`,
    // Long relative time (topbar "อัปเดตล่าสุด เมื่อ 3 วินาทีที่แล้ว" per the design).
    agoLongSec: (n: number) => `เมื่อ ${n} วินาทีที่แล้ว`,
    agoLongMin: (n: number) => `เมื่อ ${n} นาทีที่แล้ว`,
    agoLongHr: (n: number) => `เมื่อ ${n} ชั่วโมงที่แล้ว`,
    meters: (n: number) => `±${n} ม.`,
    gpsAccurate: (n: number) => `GPS แม่นยำ ${n} ม.`,
    gpsNoSignal: "GPS ไม่มีสัญญาณ",
    idLabel: (id: string) => `ID ${id}`,
    statRating: "★ คะแนน",
    statJobs: "งานสำเร็จ",
    statKm: "กม. ห่าง",
    currentJob: "งานปัจจุบัน",
    noCurrentJob: "ไม่มีงานที่กำลังทำ",
    jobStatus: {
      accepted: "รับงานแล้ว",
      en_route: "กำลังเดินทาง",
      arrived: "ถึงจุดแล้ว",
      pending_completion: "รอยืนยันจบงาน",
    },
    chat: "แชต",
    call: "โทรหาเจ้าหน้าที่",
    awaitingApi: "รอ API",
  },
  en: {
    rosterTitle: "Online guards",
    inArea: (n: number) => `${n} in the area`,
    agoSec: (n: number) => `${n}s`,
    agoMin: (n: number) => `${n} min`,
    agoHr: (n: number) => `${n} hr`,
    agoLongSec: (n: number) => `${n} seconds ago`,
    agoLongMin: (n: number) => `${n} minutes ago`,
    agoLongHr: (n: number) => `${n} hours ago`,
    meters: (n: number) => `±${n} m`,
    gpsAccurate: (n: number) => `GPS accurate ${n} m`,
    gpsNoSignal: "GPS no signal",
    idLabel: (id: string) => `ID ${id}`,
    statRating: "★ Rating",
    statJobs: "Jobs done",
    statKm: "km away",
    currentJob: "Current job",
    noCurrentJob: "No active job",
    jobStatus: {
      accepted: "Accepted",
      en_route: "En route",
      arrived: "Arrived",
      pending_completion: "Pending completion",
    },
    chat: "Chat",
    call: "Call guard",
    awaitingApi: "Awaiting API",
  },
} as const;

export type MapCopy = (typeof COPY)[keyof typeof COPY];

/** Active (assigned, non-terminal) booking statuses — a guard's "current job" is one of these.
 * Mirrors the operations board's ACTIVE_STATUSES (BookingStatus minus terminal + requested). */
export const ACTIVE_BOOKING_STATUSES = [
  "accepted",
  "en_route",
  "arrived",
  "pending_completion",
] as const;
export type ActiveBookingStatus = (typeof ACTIVE_BOOKING_STATUSES)[number];

/** Badge tone per active status — matches the canonical bookings/operations palette
 * (bookings/copy.ts STATUS_TONE): on-site/accepted = blue, in-transit = amber, so the
 * detail-card badge reads the same as the bookings table for the same status. */
export const ACTIVE_STATUS_TONE: Record<ActiveBookingStatus, "blue" | "amber"> = {
  accepted: "blue",
  en_route: "amber",
  arrived: "blue",
  pending_completion: "amber",
};

/** Render order everywhere statuses are listed (stat chips, filter chips). */
export const STATUS_ORDER: readonly GuardStatus[] = ["active", "idle", "offline"];

/** Existing shared-i18n labels for the 3 derived presence statuses. */
export const STATUS_LABEL_KEY: Record<GuardStatus, TKey> = {
  active: "map.status.active",
  idle: "map.status.idle",
  offline: "map.status.offline",
};

// Guard live-status tokens (tokens.css --status-*) — idle renders with the amber
// "working" token exactly like the previous build (3 design status colors, 3 statuses).
export const STATUS_DOT: Record<GuardStatus, string> = {
  active: "bg-status-active",
  idle: "bg-status-working",
  offline: "bg-status-offline",
};
export const STATUS_TEXT: Record<GuardStatus, string> = {
  active: "text-status-active",
  idle: "text-status-working",
  offline: "text-status-offline",
};
export const AVATAR_STATUS: Record<GuardStatus, AvatarStatus> = {
  active: "active",
  idle: "working",
  offline: "offline",
};

/** First UUID segment — the only stable display handle we have (no name endpoint). */
export function shortId(id: string): string {
  return id.slice(0, 8);
}

/** Avatar initials stand-in derived from the guard id (profile names are not exposed here). */
export function initials(id: string): string {
  return id.slice(0, 2).toUpperCase();
}

function agoSeconds(iso: string): number {
  return Math.max(0, Math.floor((Date.now() - Date.parse(iso)) / 1000));
}

export function formatAgoShort(iso: string, c: MapCopy): string {
  const s = agoSeconds(iso);
  if (s < 60) return c.agoSec(s);
  const m = Math.floor(s / 60);
  if (m < 60) return c.agoMin(m);
  return c.agoHr(Math.floor(m / 60));
}

export function formatAgoLong(iso: string, c: MapCopy): string {
  const s = agoSeconds(iso);
  if (s < 60) return c.agoLongSec(s);
  const m = Math.floor(s / 60);
  if (m < 60) return c.agoLongMin(m);
  return c.agoLongHr(Math.floor(m / 60));
}

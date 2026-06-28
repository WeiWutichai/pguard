// Screen-local bilingual copy for the calls (สายโทร) screen — a READ-ONLY admin call log
// (calling `GET /admin/calls`). Clicking a row opens a per-call DETAIL view backed by the
// call-events read model (`GET /admin/calls/{id}/events`, #135): the lifecycle + signaling
// TIMELINE (ringing/accepted/connected/ended + offer/answer/ice_candidate/peer_offline).
// Media QUALITY (jitter/loss/bitrate/MOS) is intentionally absent — a signaling relay can't
// observe it (needs SFU/TURN stats); the detail view shows that as an honest note.
import type { Lang } from "@/lib/lang";

/** Lifecycle + signaling step kinds from the call-events read model (calling `CallEventType`). */
export const CALL_EVENT_TYPES = [
  "ringing",
  "accepted",
  "rejected",
  "connected",
  "ended",
  "missed",
  "offer",
  "answer",
  "ice_candidate",
  "peer_offline",
] as const;
export type CallEventTypeKey = (typeof CALL_EVENT_TYPES)[number];

/** Tone for each timeline step (lifecycle milestones colored; signaling steps stay neutral). */
export const EVENT_TONE: Record<CallEventTypeKey, "green" | "amber" | "red" | "blue" | "gray"> = {
  ringing: "gray",
  accepted: "blue",
  rejected: "red",
  connected: "green",
  ended: "green",
  missed: "amber",
  offer: "gray",
  answer: "gray",
  ice_candidate: "gray",
  peer_offline: "amber",
};

export const CALL_STATUSES = [
  "initiated",
  "accepted",
  "connected",
  "ended",
  "rejected",
  "missed",
] as const;
export type CallStatusKey = (typeof CALL_STATUSES)[number];

export const CALL_TONE: Record<CallStatusKey, "green" | "amber" | "red" | "blue" | "gray"> = {
  initiated: "gray",
  accepted: "blue",
  connected: "green",
  ended: "green",
  rejected: "red",
  missed: "amber",
};

export interface CallsCopy {
  title: string;
  subtitle: (n: string) => string;
  kpiTotal: string;
  kpiEnded: string;
  kpiMissed: string;
  kpiAvgDuration: string;
  searchPlaceholder: string;
  colCall: string;
  colCaller: string;
  colCallee: string;
  colType: string;
  colStatus: string;
  colDuration: string;
  colStarted: string;
  typeAudio: string;
  typeVideo: string;
  statusLabel: Record<CallStatusKey, string>;
  of: string;
  // --- per-call detail view (#135 call-events read model) ---
  detailTitle: string;
  detailParticipants: string;
  detailCaller: string;
  detailCallee: string;
  detailBooking: string;
  timelineHead: string;
  loadingTimeline: string;
  timelineError: string;
  noEvents: string;
  eventLabel: Record<CallEventTypeKey, string>;
  /** Honest media-quality gap — the relay can't observe RTP stats (needs SFU/TURN). */
  qualityGap: string;
  /** Caption explaining `peer_offline` / undelivered relays. */
  signalCaption: string;
  viewDetail: string;
}

export const COPY: Record<Lang, CallsCopy> = {
  th: {
    title: "สายโทร",
    subtitle: (n) => `บันทึกการโทรทั้งหมด ${n} สาย`,
    kpiTotal: "สายทั้งหมด",
    kpiEnded: "สำเร็จ",
    kpiMissed: "สายไม่รับ",
    kpiAvgDuration: "ระยะเวลาเฉลี่ย",
    searchPlaceholder: "ค้นหาสาย / ผู้ใช้…",
    colCall: "Call",
    colCaller: "ผู้โทร",
    colCallee: "ผู้รับ",
    colType: "ประเภท",
    colStatus: "สถานะ",
    colDuration: "ระยะเวลา",
    colStarted: "เริ่มเมื่อ",
    typeAudio: "เสียง",
    typeVideo: "วิดีโอ",
    statusLabel: {
      initiated: "เริ่มโทร",
      accepted: "รับสาย",
      connected: "เชื่อมต่อ",
      ended: "จบสาย",
      rejected: "ปฏิเสธ",
      missed: "ไม่รับสาย",
    },
    of: "จาก",
    detailTitle: "รายละเอียดสาย",
    detailParticipants: "คู่สนทนา",
    detailCaller: "ผู้โทร",
    detailCallee: "ผู้รับ",
    detailBooking: "งาน",
    timelineHead: "ไทม์ไลน์การโทร",
    loadingTimeline: "กำลังโหลดไทม์ไลน์…",
    timelineError: "โหลดไทม์ไลน์ไม่สำเร็จ",
    noEvents: "ยังไม่มีเหตุการณ์ในสายนี้",
    eventLabel: {
      ringing: "กำลังเรียก",
      accepted: "รับสาย",
      rejected: "ปฏิเสธ",
      connected: "เชื่อมต่อสำเร็จ",
      ended: "จบสาย",
      missed: "ไม่รับสาย",
      offer: "ส่งคำเชิญ (offer)",
      answer: "ตอบรับ (answer)",
      ice_candidate: "เชื่อมเส้นทาง (ICE)",
      peer_offline: "ปลายทางออฟไลน์",
    },
    qualityGap:
      "คุณภาพสัญญาณ (jitter / packet loss / bitrate / MOS) ยังไม่ได้เก็บ — relay มองไม่เห็นชั้นสื่อ ต้องใช้สถิติจาก SFU/TURN",
    signalCaption: "ขั้นตอนสัญญาณ (offer/answer/ICE) จาก relay — ไม่เก็บเนื้อหา SDP/ICE จริง",
    viewDetail: "ดูไทม์ไลน์",
  },
  en: {
    title: "Calls",
    subtitle: (n) => `${n} call records`,
    kpiTotal: "Total calls",
    kpiEnded: "Completed",
    kpiMissed: "Missed",
    kpiAvgDuration: "Avg duration",
    searchPlaceholder: "Search call / user…",
    colCall: "Call",
    colCaller: "Caller",
    colCallee: "Callee",
    colType: "Type",
    colStatus: "Status",
    colDuration: "Duration",
    colStarted: "Started",
    typeAudio: "Audio",
    typeVideo: "Video",
    statusLabel: {
      initiated: "Initiated",
      accepted: "Accepted",
      connected: "Connected",
      ended: "Ended",
      rejected: "Rejected",
      missed: "Missed",
    },
    of: "of",
    detailTitle: "Call detail",
    detailParticipants: "Participants",
    detailCaller: "Caller",
    detailCallee: "Callee",
    detailBooking: "Booking",
    timelineHead: "Call timeline",
    loadingTimeline: "Loading timeline…",
    timelineError: "Failed to load timeline",
    noEvents: "No events recorded for this call",
    eventLabel: {
      ringing: "Ringing",
      accepted: "Accepted",
      rejected: "Rejected",
      connected: "Connected",
      ended: "Ended",
      missed: "Missed",
      offer: "Offer sent",
      answer: "Answer sent",
      ice_candidate: "ICE candidate",
      peer_offline: "Peer offline",
    },
    qualityGap:
      "Media quality (jitter / packet loss / bitrate / MOS) is not persisted — a signaling relay can't observe the media plane (needs SFU/TURN stats).",
    signalCaption: "Signaling steps (offer/answer/ICE) from the relay — raw SDP/ICE payloads are never stored.",
    viewDetail: "View timeline",
  },
};

/** Format a timeline `detail` object into a short human string (end_reason, relayed to/delivered).
 *  Never renders raw SDP/ICE — the read model carries only small metadata. */
export function fmtEventDetail(detail: Record<string, unknown> | null | undefined): string | null {
  if (!detail || typeof detail !== "object") return null;
  const parts: string[] = [];
  if (typeof detail.end_reason === "string" && detail.end_reason) parts.push(detail.end_reason);
  if (detail.delivered === false) parts.push("undelivered");
  return parts.length ? parts.join(" · ") : null;
}

/** Format `duration_seconds` as m:ss; null/0 → "—". */
export function fmtDuration(secs: number | null | undefined): string {
  if (secs == null || secs <= 0) return "—";
  const m = Math.floor(secs / 60);
  const s = secs % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

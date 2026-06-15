// Screen-local bilingual copy for the calls (สายโทร) screen — a READ-ONLY admin call log
// (calling `GET /admin/calls`). The design's rich per-call timeline / ICE state / signal
// quality / raw WebRTC debug log are NOT persisted (calling is a relay) → out of scope;
// this is the call list + real derived stats.
import type { Lang } from "@/lib/lang";

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
  awaitingApi: string;
  detailGap: string;
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
    awaitingApi: "รอ API",
    detailGap:
      "ไทม์ไลน์/ICE/คุณภาพสัญญาณรายสาย — ยังไม่ได้เก็บ (calling เป็น relay) รอ call-events read model",
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
  },
  en: {
    title: "Calls",
    subtitle: (n) => `${n} call records`,
    kpiTotal: "Total calls",
    kpiEnded: "Completed",
    kpiMissed: "Missed",
    kpiAvgDuration: "Avg duration",
    searchPlaceholder: "Search call / user…",
    awaitingApi: "awaiting API",
    detailGap:
      "Per-call timeline / ICE / signal quality is not persisted (calling is a relay) — awaiting a call-events read model",
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
  },
};

/** Format `duration_seconds` as m:ss; null/0 → "—". */
export function fmtDuration(secs: number | null | undefined): string {
  if (secs == null || secs <= 0) return "—";
  const m = Math.floor(secs / 60);
  const s = secs % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

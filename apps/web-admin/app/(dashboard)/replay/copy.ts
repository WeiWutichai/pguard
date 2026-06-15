// Screen-local bilingual copy for the location-replay (เล่นย้อนเส้นทาง) screen — pick an
// approved guard, fetch their GPS history (presence `GET /guards/{id}/history`, admin-readable),
// and replay the route on the map with a time scrubber. Honest gaps: no from/to time window
// (history is limit/offset only — we fetch the most-recent N), no per-point speed/heading
// (HistoryPoint carries only lat/lng/accuracy/recorded_at), no GeoJSON export, and entry is by
// guard (not by booking — history is keyed by guard_id).
import type { Lang } from "@/lib/lang";

export interface ReplayCopy {
  title: string;
  subtitle: string;
  pickGuard: string;
  pickPlaceholder: string;
  noGuard: string;
  noHistory: string;
  loadingHistory: string;
  play: string;
  pause: string;
  points: string;
  pointOf: (i: number, n: number) => string;
  recordedAt: string;
  accuracy: string;
  awaitingApi: string;
  gapNote: string;
  exp: string;
}

export const COPY: Record<Lang, ReplayCopy> = {
  th: {
    title: "เล่นย้อนเส้นทาง",
    subtitle: "เลือกเจ้าหน้าที่เพื่อดูเส้นทาง GPS ย้อนหลัง",
    pickGuard: "เจ้าหน้าที่",
    pickPlaceholder: "— เลือกเจ้าหน้าที่ —",
    noGuard: "เลือกเจ้าหน้าที่เพื่อเริ่มเล่นย้อนเส้นทาง",
    noHistory: "ไม่มีประวัติ GPS ของเจ้าหน้าที่คนนี้",
    loadingHistory: "กำลังโหลดประวัติ…",
    play: "เล่น",
    pause: "หยุด",
    points: "จุด",
    pointOf: (i, n) => `จุดที่ ${i} จาก ${n}`,
    recordedAt: "เวลา",
    accuracy: "ความแม่นยำ",
    awaitingApi: "รอ API",
    gapNote:
      "เล่นล่าสุดได้สูงสุด 500 จุด — ยังไม่มีช่วงเวลา (from/to) · ไม่มีความเร็ว/ทิศทางรายจุด · เลือกตามเจ้าหน้าที่ (ไม่ใช่ตามงาน)",
    exp: "ปี",
  },
  en: {
    title: "Location Replay",
    subtitle: "Pick a guard to replay their GPS track",
    pickGuard: "Guard",
    pickPlaceholder: "— select a guard —",
    noGuard: "Pick a guard to start replaying their route",
    noHistory: "No GPS history for this guard",
    loadingHistory: "Loading history…",
    play: "Play",
    pause: "Pause",
    points: "points",
    pointOf: (i, n) => `Point ${i} of ${n}`,
    recordedAt: "Time",
    accuracy: "Accuracy",
    awaitingApi: "awaiting API",
    gapNote:
      "Replays the latest ≤500 points — no from/to window · no per-point speed/heading · entry is by guard, not booking",
    exp: "y",
  },
};

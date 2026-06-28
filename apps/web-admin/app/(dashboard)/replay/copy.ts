// Screen-local bilingual copy for the location-replay (เล่นย้อนเส้นทาง) screen. LIVE via
// presence `GET /admin/track/replay` in TWO modes: by JOB (`?booking_id` — the window is derived
// server-side from the booking's accept→terminal events) or by GUARD (`?guard_id&from&to` — a
// time-range window). The route plays on the map with a time scrubber. Honest flag: per-point
// speed/heading are never historized (location_history keeps only lat/lng/accuracy + time).
import type { Lang } from "@/lib/lang";

export interface ReplayCopy {
  title: string;
  subtitle: string;
  modeGuard: string;
  modeJob: string;
  pickGuard: string;
  pickPlaceholder: string;
  bookingLabel: string;
  bookingPlaceholder: string;
  fromLabel: string;
  toLabel: string;
  loadBtn: string;
  noGuard: string;
  noSelection: string;
  noHistory: string;
  notFound: string;
  loadingHistory: string;
  play: string;
  pause: string;
  points: string;
  pointOf: (i: number, n: number) => string;
  windowOpen: string;
  truncatedNote: (n: number) => string;
  speedHeadingNote: string;
  exp: string;
}

export const COPY: Record<Lang, ReplayCopy> = {
  th: {
    title: "เล่นย้อนเส้นทาง",
    subtitle: "ดูเส้นทาง GPS ย้อนหลังตามงาน หรือตามเจ้าหน้าที่ + ช่วงเวลา",
    modeGuard: "ตามเจ้าหน้าที่",
    modeJob: "ตามงาน (Booking)",
    pickGuard: "เจ้าหน้าที่",
    pickPlaceholder: "— เลือกเจ้าหน้าที่ —",
    bookingLabel: "รหัสงาน (Booking ID)",
    bookingPlaceholder: "วาง UUID ของงาน",
    fromLabel: "ตั้งแต่",
    toLabel: "ถึง",
    loadBtn: "โหลดเส้นทาง",
    noGuard: "เลือกเจ้าหน้าที่เพื่อเริ่มเล่นย้อนเส้นทาง",
    noSelection: "เลือกงานหรือเจ้าหน้าที่เพื่อเริ่ม",
    noHistory: "ไม่มีประวัติ GPS ในช่วงนี้",
    notFound: "ไม่พบงานนี้ หรือยังไม่มีข้อมูลการรับงาน/เจ้าหน้าที่",
    loadingHistory: "กำลังโหลดประวัติ…",
    play: "เล่น",
    pause: "หยุด",
    points: "จุด",
    pointOf: (i, n) => `จุดที่ ${i} จาก ${n}`,
    windowOpen: "งานยังดำเนินอยู่ (ช่วงเวลายังไม่ปิด)",
    truncatedNote: (n) => `แสดง ${n} จุดแรก — มีมากกว่านี้ (ลดช่วงเวลาหรือเพิ่ม limit)`,
    speedHeadingNote: "ไม่มีความเร็ว/ทิศทางรายจุด (ระบบเก็บเฉพาะ lat/lng/ความแม่นยำ + เวลา)",
    exp: "ปี",
  },
  en: {
    title: "Location Replay",
    subtitle: "Replay a GPS track by job, or by guard + time range",
    modeGuard: "By guard",
    modeJob: "By job (booking)",
    pickGuard: "Guard",
    pickPlaceholder: "— select a guard —",
    bookingLabel: "Booking ID",
    bookingPlaceholder: "Paste the booking UUID",
    fromLabel: "From",
    toLabel: "To",
    loadBtn: "Load track",
    noGuard: "Pick a guard to start replaying their route",
    noSelection: "Pick a job or a guard to start",
    noHistory: "No GPS history in this window",
    notFound: "Booking not found, or it has no recorded accept/guard yet",
    loadingHistory: "Loading history…",
    play: "Play",
    pause: "Pause",
    points: "points",
    pointOf: (i, n) => `Point ${i} of ${n}`,
    windowOpen: "Job still active (window not yet closed)",
    truncatedNote: (n) => `Showing the first ${n} points — there are more (narrow the window or raise the limit)`,
    speedHeadingNote: "No per-point speed/heading (only lat/lng/accuracy + time are stored)",
    exp: "y",
  },
};

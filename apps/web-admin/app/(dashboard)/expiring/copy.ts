// Screen-local bilingual copy for the document-expiry (เอกสารใกล้หมดอายุ) screen.
// Backed by profile `GET /admin/documents/expiring` (docs expiring within ~90d, incl. expired).
// "Remind" is REAL — it sends the guard a notification via notification `POST /notifications/send`
// (admin-only). Data is empty until the doc-upload + expiry-CAPTURE follow-up populates it (the
// schema/endpoint/screen are real and ready) — honest, never faked. Guard names aren't in v2
// (guard_profiles has no name field) → the guard shows as a short id.
import type { Lang } from "@/lib/lang";

/** Document-type enum (matches profile.document_expiry.document_type). */
export const DOC_TYPES = [
  "id_card",
  "security_license",
  "training_cert",
  "criminal_check",
  "driver_license",
] as const;
export type DocType = (typeof DOC_TYPES)[number];

/** Expiry windows (days). "expired" = already past. */
export const WINDOWS = ["expired", "7", "30", "90"] as const;
export type WindowKey = (typeof WINDOWS)[number];

export interface ExpiringCopy {
  title: string;
  subtitle: string;
  kpiExpired: string;
  kpi7: string;
  kpi30: string;
  kpi90: string;
  tabExpired: string;
  tab7: string;
  tab30: string;
  tab90: string;
  colGuard: string;
  colDoc: string;
  colExpiry: string;
  colRemaining: string;
  colReminded: string;
  remind: string;
  reminded: string;
  reminding: string;
  remindError: string;
  overdue: (n: number) => string;
  daysLeft: (n: number) => string;
  docLabel: Record<DocType, string>;
  captureGap: string;
  never: string;
}

export const COPY: Record<Lang, ExpiringCopy> = {
  th: {
    title: "เอกสารใกล้หมดอายุ",
    subtitle: "แจ้งเตือนเอกสารเจ้าหน้าที่ที่ต้องต่ออายุ",
    kpiExpired: "หมดอายุแล้ว",
    kpi7: "ใกล้หมดใน 7 วัน",
    kpi30: "ใกล้หมดใน 30 วัน",
    kpi90: "ใกล้หมดใน 90 วัน",
    tabExpired: "หมดอายุแล้ว",
    tab7: "ใน 7 วัน",
    tab30: "ใน 30 วัน",
    tab90: "ใน 90 วัน",
    colGuard: "เจ้าหน้าที่",
    colDoc: "ประเภทเอกสาร",
    colExpiry: "วันหมดอายุ",
    colRemaining: "เหลือ",
    colReminded: "เตือนล่าสุด",
    remind: "เตือน",
    reminded: "ส่งแล้ว",
    reminding: "กำลังส่ง…",
    remindError: "ส่งเตือนไม่สำเร็จ",
    overdue: (n) => `เกิน ${n} วัน`,
    daysLeft: (n) => `${n} วัน`,
    docLabel: {
      id_card: "บัตรประชาชน",
      security_license: "ใบอนุญาต รปภ.",
      training_cert: "ใบรับรองการฝึก",
      criminal_check: "ใบตรวจประวัติ",
      driver_license: "ใบขับขี่",
    },
    captureGap:
      "วันหมดอายุจะถูกบันทึกตอนอัปโหลดเอกสาร (flow อัปโหลด+วันหมดอายุยังเป็น follow-up) — จะว่างจนกว่าจะมีข้อมูล",
    never: "—",
  },
  en: {
    title: "Document Expiry",
    subtitle: "Guard documents needing renewal",
    kpiExpired: "Expired",
    kpi7: "Within 7 days",
    kpi30: "Within 30 days",
    kpi90: "Within 90 days",
    tabExpired: "Expired",
    tab7: "7 days",
    tab30: "30 days",
    tab90: "90 days",
    colGuard: "Guard",
    colDoc: "Document",
    colExpiry: "Expiry date",
    colRemaining: "Remaining",
    colReminded: "Last reminded",
    remind: "Remind",
    reminded: "Sent",
    reminding: "Sending…",
    remindError: "Couldn't send reminder",
    overdue: (n) => `${n}d overdue`,
    daysLeft: (n) => `${n} days`,
    docLabel: {
      id_card: "ID Card",
      security_license: "Security License",
      training_cert: "Training Cert",
      criminal_check: "Criminal Check",
      driver_license: "Driver License",
    },
    captureGap:
      "Expiry dates are captured at document upload (the upload+expiry flow is a follow-up) — empty until data exists",
    never: "—",
  },
};

/** Whole days from now until `iso` date (negative = already expired). */
export function daysUntil(iso: string): number {
  const ms = new Date(iso + "T00:00:00Z").getTime() - Date.now();
  return Math.ceil(ms / 86_400_000);
}

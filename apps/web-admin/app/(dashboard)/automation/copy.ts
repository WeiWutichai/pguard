// Screen-local bilingual copy for the automation (กฎอัตโนมัติ) screen.
// Backed by notification `/admin/automation/rules` (CRUD + enable toggle). HONESTY: this is the
// AUTHORING surface only — a stored rule does NOT yet fire. Wiring rule execution into the event
// consumer is a deliberate follow-up (a production-behavior change), so the screen says so with a
// banner rather than implying rules already run. trigger/action keys come from a fixed set the
// backend validates; condition is free text.
import type { Lang } from "@/lib/lang";

export const TRIGGER_KEYS = [
  "missed_checkin",
  "booking_cancelled",
  "low_rating",
  "no_guard_accepted",
  "document_expiring",
  "incomplete_work",
] as const;
export type TriggerKey = (typeof TRIGGER_KEYS)[number];

export const ACTION_KEYS = [
  "notify_admins",
  "charge_fee",
  "flag_guard",
  "expand_radius",
  "notify_guard",
  "auto_refund",
] as const;
export type ActionKey = (typeof ACTION_KEYS)[number];

export interface AutomationCopy {
  title: string;
  subtitle: string;
  executionGap: string;
  newRuleHead: string;
  whenLabel: string;
  ifLabel: string;
  ifPlaceholder: string;
  thenLabel: string;
  saveRule: string;
  activeHead: string;
  ruleCount: (n: number) => string;
  enabled: string;
  delete: string;
  triggerLabel: Record<TriggerKey, string>;
  actionLabel: Record<ActionKey, string>;
}

export const COPY: Record<Lang, AutomationCopy> = {
  th: {
    title: "กฎอัตโนมัติ",
    subtitle: "ทริกเกอร์ เงื่อนไข และการดำเนินการ",
    executionGap:
      "ตอนนี้เป็นการตั้งค่า/บันทึกกฎเท่านั้น — กฎยังไม่ทำงานจริง (การต่อ engine ให้ยิงตาม event เป็น follow-up)",
    newRuleHead: "สร้างกฎใหม่",
    whenLabel: "เมื่อ (ทริกเกอร์)",
    ifLabel: "ถ้า (เงื่อนไข)",
    ifPlaceholder: "เช่น ขาดเกิน 1 รอบ (ไม่บังคับ)",
    thenLabel: "ทำ (การดำเนินการ)",
    saveRule: "บันทึกกฎ",
    activeHead: "กฎที่ใช้งาน",
    ruleCount: (n) => `${n} กฎ`,
    enabled: "เปิดใช้งาน",
    delete: "ลบ",
    triggerLabel: {
      missed_checkin: "เจ้าหน้าที่ขาดเช็คอิน",
      booking_cancelled: "งานถูกยกเลิก",
      low_rating: "รีวิว ≤ 2 ดาว",
      no_guard_accepted: "ไม่มีเจ้าหน้าที่ตอบรับ",
      document_expiring: "เอกสารใกล้หมดอายุ",
      incomplete_work: "งานเสร็จไม่ครบเวลา",
    },
    actionLabel: {
      notify_admins: "แจ้งเตือนทีมแอดมิน",
      charge_fee: "คิดค่าธรรมเนียม",
      flag_guard: "ตั้ง flag เจ้าหน้าที่",
      expand_radius: "ขยายรัศมีค้นหา",
      notify_guard: "ส่งแจ้งเตือนเจ้าหน้าที่",
      auto_refund: "คำนวณคืนเงินอัตโนมัติ",
    },
  },
  en: {
    title: "Automation",
    subtitle: "Triggers, conditions & actions",
    executionGap:
      "Authoring/storage only for now — rules don't fire yet (wiring the engine to dispatch on events is a follow-up)",
    newRuleHead: "New rule",
    whenLabel: "When (trigger)",
    ifLabel: "If (condition)",
    ifPlaceholder: "e.g. missed more than 1 round (optional)",
    thenLabel: "Then (action)",
    saveRule: "Save rule",
    activeHead: "Active rules",
    ruleCount: (n) => `${n} rules`,
    enabled: "Enabled",
    delete: "Delete",
    triggerLabel: {
      missed_checkin: "Guard missed check-in",
      booking_cancelled: "Booking cancelled",
      low_rating: "Review ≤ 2 stars",
      no_guard_accepted: "No guard accepted",
      document_expiring: "Document expiring",
      incomplete_work: "Incomplete work",
    },
    actionLabel: {
      notify_admins: "Notify admin team",
      charge_fee: "Charge a fee",
      flag_guard: "Flag the guard",
      expand_radius: "Expand search radius",
      notify_guard: "Notify the guard",
      auto_refund: "Auto-refund",
    },
  },
};

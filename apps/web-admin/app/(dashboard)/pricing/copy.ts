// Screen-local bilingual copy for the pricing (จัดการราคา) screen — the admin service-catalog
// CRUD (GET/POST/PUT/DELETE /admin/pricing/services). The catalog is STANDALONE: editing a
// rate here does NOT change how bookings are charged yet (bookings keep their server-owned
// base_fee) — a future "charge reads the catalog" integration is a separate decision. The
// design's "Price Rules" tab is explicitly future → a coming-soon gap.
import type { Lang } from "@/lib/lang";

export interface PricingCopy {
  title: string;
  subtitle: (n: string) => string;
  tabServices: string;
  tabRules: string;
  rulesGap: string;
  standaloneNote: string;
  addService: string;
  awaitingApi: string;
  colName: string;
  colBaseFee: string;
  colMinHours: string;
  colNotes: string;
  colStatus: string;
  active: string;
  inactive: string;
  edit: string;
  deactivate: string;
  hoursUnit: string;
  perHour: string;
  // modal
  createTitle: string;
  editTitle: string;
  fieldName: string;
  namePlaceholder: string;
  fieldBaseFee: string;
  feeHint: string;
  fieldMinHours: string;
  hoursHint: string;
  fieldNotes: string;
  notesPlaceholder: string;
  save: string;
  saving: string;
  cancel: string;
  saveError: string;
  of: string;
}

export const COPY: Record<Lang, PricingCopy> = {
  th: {
    title: "จัดการราคา",
    subtitle: (n) => `บริการในแคตตาล็อก ${n} รายการ`,
    tabServices: "บริการ",
    tabRules: "กฎราคา",
    rulesGap: "กฎราคาแบบมีเงื่อนไข — ฟีเจอร์อนาคต (รอ API)",
    standaloneNote:
      "แคตตาล็อกนี้เป็นข้อมูลอ้างอิงสำหรับแอดมิน — การคิดเงินของงานยังใช้ base_fee ของ booking โดยตรง (ยังไม่ผูกกับแคตตาล็อก)",
    addService: "เพิ่มบริการ",
    awaitingApi: "รอ API",
    colName: "บริการ",
    colBaseFee: "ค่าบริการ",
    colMinHours: "ชั่วโมงขั้นต่ำ",
    colNotes: "หมายเหตุ",
    colStatus: "สถานะ",
    active: "ใช้งาน",
    inactive: "ปิดใช้งาน",
    edit: "แก้ไข",
    deactivate: "ปิดใช้งาน",
    hoursUnit: "ชม.",
    perHour: "฿/ชม.",
    createTitle: "เพิ่มบริการ",
    editTitle: "แก้ไขบริการ",
    fieldName: "ชื่อบริการ",
    namePlaceholder: "เช่น รปภ. ประจำหมู่บ้าน",
    fieldBaseFee: "ค่าบริการพื้นฐาน (฿/ชม.)",
    feeHint: "0 ≤ ค่าบริการ ≤ 1,000,000",
    fieldMinHours: "ชั่วโมงขั้นต่ำ",
    hoursHint: "1 ≤ ชม. ≤ 24",
    fieldNotes: "หมายเหตุ",
    notesPlaceholder: "รายละเอียดบริการ…",
    save: "บันทึก",
    saving: "กำลังบันทึก…",
    cancel: "ยกเลิก",
    saveError: "บันทึกไม่สำเร็จ — ตรวจสอบค่าที่กรอก",
    of: "จาก",
  },
  en: {
    title: "Pricing",
    subtitle: (n) => `${n} catalog services`,
    tabServices: "Services",
    tabRules: "Price Rules",
    rulesGap: "Conditional price rules — a future feature (awaiting API)",
    standaloneNote:
      "This catalog is an admin reference — jobs are still charged from the booking's own base_fee (not yet wired to the catalog)",
    addService: "Add service",
    awaitingApi: "awaiting API",
    colName: "Service",
    colBaseFee: "Base fee",
    colMinHours: "Min hours",
    colNotes: "Notes",
    colStatus: "Status",
    active: "Active",
    inactive: "Inactive",
    edit: "Edit",
    deactivate: "Deactivate",
    hoursUnit: "h",
    perHour: "฿/h",
    createTitle: "Add service",
    editTitle: "Edit service",
    fieldName: "Service name",
    namePlaceholder: "e.g. Neighbourhood guard",
    fieldBaseFee: "Base fee (฿/h)",
    feeHint: "0 ≤ fee ≤ 1,000,000",
    fieldMinHours: "Min hours",
    hoursHint: "1 ≤ hours ≤ 24",
    fieldNotes: "Notes",
    notesPlaceholder: "Service details…",
    save: "Save",
    saving: "Saving…",
    cancel: "Cancel",
    saveError: "Save failed — check the values",
    of: "of",
  },
};

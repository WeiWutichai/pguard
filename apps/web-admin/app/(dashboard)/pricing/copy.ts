// Screen-local bilingual copy for the pricing (จัดการราคา) screen — the admin service-catalog
// CRUD (GET/POST/PUT/DELETE /admin/pricing/services). The base RATE is still standalone
// (bookings keep their own server-owned base_fee), but the two money knobs added in migration
// 0010 are NOT: commission_percent + cancellation_fee are SNAPSHOTTED onto every booking at
// creation, so an edit here prices new jobs and never restates a job already booked.
//
// The commission wording is the load-bearing part of this file: it is deducted from the GUARD's
// pay, never added to the customer's bill. Every string that mentions it must say so — an admin
// who reads it the other way will set a number that quietly cuts a guard's wage.
// The design's "Price Rules" tab is explicitly future → a coming-soon gap.
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
  colCommission: string;
  colCancelFee: string;
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
  fieldCommission: string;
  commissionHint: string;
  fieldCancelFee: string;
  cancelFeeHint: string;
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
      "ค่าบริการพื้นฐานของงานยังอ่านจาก base_fee ของ booking โดยตรง — ส่วนคอมมิชชั่นและค่าธรรมเนียมยกเลิกจะถูกคัดลอกไปเก็บไว้ในงานตอนที่ลูกค้าจอง การแก้ที่นี่จึงมีผลกับงานใหม่เท่านั้น ไม่ย้อนไปเปลี่ยนเงินของงานที่จองไปแล้ว",
    addService: "เพิ่มบริการ",
    awaitingApi: "รอ API",
    colName: "บริการ",
    colBaseFee: "ค่าบริการ",
    colMinHours: "ชั่วโมงขั้นต่ำ",
    colCommission: "คอมมิชชั่น",
    colCancelFee: "ค่าธรรมเนียมยกเลิก",
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
    feeHint: "ยังไม่รวม VAT 7% (ระบบบวกให้ตอนคิดเงิน) · 0 ≤ ค่าบริการ ≤ 1,000,000",
    fieldMinHours: "ชั่วโมงขั้นต่ำ",
    hoursHint: "1 ≤ ชม. ≤ 24",
    fieldCommission: "คอมมิชชั่นแพลตฟอร์ม (%)",
    commissionHint:
      "หักจากค่าตอบแทนของ รปภ. ไม่ใช่บวกเพิ่มในบิลลูกค้า — ลูกค้าจ่ายเท่าเดิม แต่ รปภ. ได้รับน้อยลง · 0 ≤ % ≤ 100",
    fieldCancelFee: "ค่าธรรมเนียมยกเลิก (฿)",
    cancelFeeHint:
      "เก็บเมื่อ “ลูกค้า” ยกเลิกก่อนเริ่มงาน สูงสุดไม่เกินยอดที่จ่ายมาแล้ว (ยังไม่จ่าย = ไม่เก็บ) — ถ้า รปภ. ถอนงานเอง คืนเต็มจำนวน · 0 ≤ ฿ ≤ 1,000,000",
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
      "A job's base fee still comes from the booking's own base_fee — but the commission and cancellation fee are copied onto each booking the moment it is created, so editing them here affects NEW bookings only and never rewrites the money of a job already booked.",
    addService: "Add service",
    awaitingApi: "awaiting API",
    colName: "Service",
    colBaseFee: "Base fee",
    colMinHours: "Min hours",
    colCommission: "Commission",
    colCancelFee: "Cancellation fee",
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
    feeHint: "Excludes VAT 7% (added at checkout) · 0 ≤ fee ≤ 1,000,000",
    fieldMinHours: "Min hours",
    hoursHint: "1 ≤ hours ≤ 24",
    fieldCommission: "Platform commission (%)",
    commissionHint:
      "Deducted from the GUARD's pay — not added to the customer's bill. The customer pays the same; the guard receives less · 0 ≤ % ≤ 100",
    fieldCancelFee: "Cancellation fee (฿)",
    cancelFeeHint:
      "Charged when the CUSTOMER cancels before work starts, never more than they already paid (nothing paid → nothing charged). A guard withdrawing still refunds in full · 0 ≤ ฿ ≤ 1,000,000",
    fieldNotes: "Notes",
    notesPlaceholder: "Service details…",
    save: "Save",
    saving: "Saving…",
    cancel: "Cancel",
    saveError: "Save failed — check the values",
    of: "of",
  },
};

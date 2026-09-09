// Screen-local bilingual copy for the guards screen — NEW design strings only, taken
// verbatim from the hi-fi mockup (Admin - Guards). Shared strings (table columns, detail
// labels, common.*) keep using src/lib/i18n.tsx keys — that file is single-writer and is
// NOT edited from this screen.
import type { Lang } from "@/lib/lang";

export interface GuardsCopy {
  title: string;
  /** Design subtitle carries the live count: "เจ้าหน้าที่ที่อนุมัติแล้ว 384 คน". */
  subtitle: (n: string) => string;
  kpiOnline: string;
  kpiOnJob: string;
  kpiAvgRating: string;
  kpiDocsExpiring: string;
  chipOnline: string;
  chipOnJob: string;
  chipOffline: string;
  colStatus: string;
  searchPlaceholder: string;
  /** Honest inline gap chip for design data with no v2 endpoint yet. */
  awaitingApi: string;
  statRating: string;
  statJobs: string;
  statExp: string;
  docsHead: string;
  /** Documents panel: status when a credential type has no stored image, the loading line, and
   *  the "open full" link; `docLabels` maps each `document_type` to its display name. */
  docsNotUploaded: string;
  docsLoading: string;
  docOpen: string;
  /** `Record<GuardDocType, ...>` so adding a doc type forces a label in BOTH locales. */
  docLabels: Record<GuardDocType, string>;
  jobHistory: string;
  suspend: string;
  /** Pagination summary connector: "1–8 จาก 384" / "1–8 of 384". */
  of: string;
  /** Payout panel (guard-payout-panel.tsx) — the ONLY place `tax_id` can be entered. Until this
   *  existed the column was writable only by hand-written SQL, so every guard failed payment's
   *  payability check and the SCB export produced an empty file. */
  payout: {
    head: string;
    /** One-liner under the head: absent/blank field = keep the stored value (COALESCE-merge). */
    mergeHint: string;
    taxId: string;
    /** WHY the national id is the payout-critical field: PromptPay NAT proxy + ภ.ง.ด. TIN. */
    taxIdHint: string;
    bankName: string;
    accountNumber: string;
    accountName: string;
    save: string;
    saving: string;
    saved: string;
    /** Restores the stored values — the only way back once a field has been typed over/blanked
     *  (its old value is no longer on screen to retype). */
    revert: string;
    /** Field-level errors, mirrored from profile's validators so a typo never round-trips. */
    errTaxId: string;
    /** The 13-digit-only check-digit failure — its own message, because "count the digits" and
     *  "re-read the card" are different corrections and the shape here is already right. */
    errTaxIdChecksum: string;
    errMasked: string;
    errCannotClear: string;
    /** Fallback banner when the API returns no typed message. */
    errSave: string;
  };
  /** Deep link from the payout screen's "จ่ายไม่ได้" table (`/guards?guard=<id>`) resolved to a
   *  guard who is not in the approved list — say so instead of showing a bare empty table. */
  deepLinkMissing: string;
}

/** The six guard credential `document_type`s (matches profile.yaml + mobile GuardCredential). */
export const GUARD_DOC_TYPES = [
  "id_card",
  "security_license",
  "training_cert",
  "criminal_check",
  "driver_license",
  "passbook_photo",
] as const;
export type GuardDocType = (typeof GUARD_DOC_TYPES)[number];

export const COPY: Record<Lang, GuardsCopy> = {
  th: {
    title: "พนักงาน รปภ.",
    subtitle: (n) => `เจ้าหน้าที่ที่อนุมัติแล้ว ${n} คน`,
    kpiOnline: "ออนไลน์ตอนนี้",
    kpiOnJob: "กำลังทำงาน",
    kpiAvgRating: "คะแนนเฉลี่ยทีม",
    kpiDocsExpiring: "เอกสารใกล้หมดอายุ",
    chipOnline: "ออนไลน์",
    chipOnJob: "กำลังทำงาน",
    chipOffline: "ออฟไลน์",
    colStatus: "สถานะ",
    searchPlaceholder: "ค้นหา",
    awaitingApi: "รอ API",
    statRating: "คะแนน",
    statJobs: "งานสำเร็จ",
    statExp: "ประสบการณ์",
    docsHead: "เอกสาร",
    docsNotUploaded: "ยังไม่อัปโหลด",
    docsLoading: "กำลังโหลดเอกสาร…",
    docOpen: "เปิดดูเต็ม",
    docLabels: {
      id_card: "บัตรประชาชน",
      security_license: "ใบอนุญาต รปภ.",
      training_cert: "ใบรับรองการฝึก",
      criminal_check: "ผลตรวจประวัติ",
      driver_license: "ใบขับขี่",
      passbook_photo: "หน้าสมุดบัญชี",
    },
    jobHistory: "ดูประวัติงาน",
    suspend: "ระงับบัญชี",
    of: "จาก",
    payout: {
      head: "ข้อมูลสำหรับจ่ายเงิน",
      mergeHint: "เว้นว่าง = คงค่าเดิมไว้ (ลบค่าที่นี่ไม่ได้)",
      taxId: "เลขบัตรประชาชน / เลขผู้เสียภาษี",
      taxIdHint:
        "เลขนี้ใช้เป็นพร้อมเพย์ปลายทาง (NAT) ที่เงินจะโอนเข้า และเป็นเลขผู้เสียภาษีของผู้รับบนหนังสือรับรองหัก ณ ที่จ่าย (ภ.ง.ด.) — ไม่มีเลขนี้ = จ่ายเงินให้ รปภ คนนี้ไม่ได้",
      bankName: "ธนาคาร",
      accountNumber: "เลขที่บัญชี",
      accountName: "ชื่อบัญชี",
      save: "บันทึกข้อมูลจ่ายเงิน",
      saving: "กำลังบันทึก…",
      saved: "บันทึกแล้ว",
      revert: "คืนค่าเดิม",
      errTaxId: "ต้องเป็นตัวเลข 8–20 หลัก (เว้นวรรคหรือขีดคั่นได้)",
      errTaxIdChecksum:
        "เลขบัตรประชาชน 13 หลักนี้ไม่ถูกต้อง (หลักตรวจสอบไม่ตรง) — น่าจะพิมพ์ผิด กรุณาตรวจกับบัตรอีกครั้ง เลขนี้คือพร้อมเพย์ปลายทางที่เงินจะโอนเข้า ถ้าผิดเงินจะเข้าบัญชีคนอื่นและเรียกคืนไม่ได้",
      errMasked: "ค่านี้ถูกปิดบังอยู่ (••••) — พิมพ์เลขเต็มใหม่ทั้งหมด",
      errCannotClear: "ลบค่าเดิมที่นี่ไม่ได้ — ถ้าจะลบต้องให้ รปภ แก้ในแอปของตัวเอง",
      errSave: "บันทึกไม่สำเร็จ",
    },
    deepLinkMissing:
      "ไม่พบ รปภ รายนี้ในรายชื่อที่อนุมัติแล้ว (อาจยังรออนุมัติหรือถูกปฏิเสธ) — ล้างช่องค้นหาเพื่อดูทั้งหมด",
  },
  en: {
    title: "Guards",
    subtitle: (n) => `${n} approved guards`,
    kpiOnline: "Online now",
    kpiOnJob: "On a job",
    kpiAvgRating: "Avg team rating",
    kpiDocsExpiring: "Docs expiring",
    chipOnline: "Online",
    chipOnJob: "On job",
    chipOffline: "Offline",
    colStatus: "Status",
    searchPlaceholder: "Search",
    awaitingApi: "awaiting API",
    statRating: "Rating",
    statJobs: "Jobs",
    statExp: "Exp.",
    docsHead: "Documents",
    docsNotUploaded: "Not uploaded",
    docsLoading: "Loading documents…",
    docOpen: "Open full",
    docLabels: {
      id_card: "ID card",
      security_license: "Security license",
      training_cert: "Training certificate",
      criminal_check: "Criminal record check",
      driver_license: "Driver license",
      passbook_photo: "Bank passbook",
    },
    jobHistory: "Job history",
    suspend: "Suspend",
    of: "of",
    payout: {
      head: "Payout details",
      mergeHint: "Blank = keep the stored value (a field cannot be cleared here)",
      taxId: "National / tax id",
      taxIdHint:
        "This is the PromptPay NAT proxy the transfer is credited to AND the recipient TIN printed on the ภ.ง.ด. withholding certificate — without it this guard cannot be paid at all.",
      bankName: "Bank",
      accountNumber: "Account number",
      accountName: "Account name",
      save: "Save payout details",
      saving: "Saving…",
      saved: "Saved",
      revert: "Revert",
      errTaxId: "Must be 8–20 digits (spaces or hyphens allowed)",
      errTaxIdChecksum:
        "This 13-digit national id fails its own check digit — it looks mistyped. Check it against the card: this is the PromptPay account the transfer is credited to, and money sent to the wrong one cannot be recovered.",
      errMasked: "This value is masked (••••) — retype the full number",
      errCannotClear: "A stored value cannot be cleared here — the guard clears it in their own app",
      errSave: "Failed to save",
    },
    deepLinkMissing:
      "That guard is not in the approved list (still pending, or rejected) — clear the search to see everyone.",
  },
};

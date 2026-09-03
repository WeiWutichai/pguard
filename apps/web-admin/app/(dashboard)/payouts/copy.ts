import type { Lang } from "@/lib/lang";

/** Page copy for the guard-payout (SCB export) screen — Thai default, English parity. */
export const COPY: Record<
  Lang,
  {
    title: string;
    subtitle: string;
    settings: string;
    debitAccount: string;
    feeDebitAccount: string;
    whtRate: string;
    whtForm: string;
    incomeType: string;
    incomeDesc: string;
    save: string;
    saved: string;
    preview: string;
    refresh: string;
    guard: string;
    proxy: string;
    income: string;
    wht: string;
    transfer: string;
    totalTransfer: string;
    totalWht: string;
    recipients: string;
    excludedTitle: string;
    reason: string;
    jobs: string;
    nobody: string;
    exportBtn: string;
    exporting: string;
    exportHint: string;
    loadError: string;
    saveError: string;
    exportError: string;
    nothingToPay: string;
  }
> = {
  th: {
    title: "จ่ายเงิน รปภ (ไฟล์อัปโหลด SCB)",
    subtitle:
      "รวมยอดค้างจ่ายของ รปภ ที่งานเสร็จแล้ว → สร้างไฟล์อัปโหลด SCB Business Net (พร้อมเพย์ + หัก ณ ที่จ่าย ภงด.53)",
    settings: "ตั้งค่าการจ่าย",
    debitAccount: "บัญชีตัดเงินบริษัท",
    feeDebitAccount: "บัญชีหักค่าธรรมเนียม (เว้นว่าง = ใช้บัญชีตัดเงิน)",
    whtRate: "อัตราหัก ณ ที่จ่าย (%)",
    whtForm: "แบบ (ภงด.)",
    incomeType: "ประเภทเงินได้",
    incomeDesc: "คำอธิบายเงินได้",
    save: "บันทึกการตั้งค่า",
    saved: "บันทึกแล้ว",
    preview: "พรีวิวรายการจ่าย",
    refresh: "รีเฟรช",
    guard: "รปภ",
    proxy: "พร้อมเพย์",
    income: "เงินได้",
    wht: "หัก ณ ที่จ่าย",
    transfer: "โอนจริง",
    totalTransfer: "ยอดโอนรวม",
    totalWht: "หัก ณ ที่จ่ายรวม",
    recipients: "จำนวนผู้รับ",
    excludedTitle: "จ่ายไม่ได้ (ต้องแก้ข้อมูลก่อน)",
    reason: "เหตุผล",
    jobs: "งาน",
    nobody: "ไม่มีรายการค้างจ่ายในขณะนี้",
    exportBtn: "สร้างไฟล์อัปโหลด SCB",
    exporting: "กำลังสร้างไฟล์…",
    exportHint: "กดแล้วจะดาวน์โหลดไฟล์ .txt และบันทึกว่าจ่ายแล้ว (กันจ่ายซ้ำ)",
    loadError: "โหลดข้อมูลไม่สำเร็จ",
    saveError: "บันทึกไม่สำเร็จ",
    exportError: "สร้างไฟล์ไม่สำเร็จ",
    nothingToPay: "ไม่มีรายการที่จ่ายได้ในขณะนี้",
  },
  en: {
    title: "Guard payout (SCB upload file)",
    subtitle:
      "Aggregate the unpaid backlog of finished guard jobs → generate the SCB Business Net upload file (PromptPay + ภ.ง.ด.53 WHT).",
    settings: "Payout settings",
    debitAccount: "Company debit account",
    feeDebitAccount: "Fee debit account (blank = use debit account)",
    whtRate: "Withholding rate (%)",
    whtForm: "WHT form",
    incomeType: "Income type",
    incomeDesc: "Income description",
    save: "Save settings",
    saved: "Saved",
    preview: "Payout preview",
    refresh: "Refresh",
    guard: "Guard",
    proxy: "PromptPay",
    income: "Income",
    wht: "WHT",
    transfer: "Transfer",
    totalTransfer: "Total transfer",
    totalWht: "Total WHT",
    recipients: "Recipients",
    excludedTitle: "Cannot pay (fix the profile first)",
    reason: "Reason",
    jobs: "jobs",
    nobody: "No unpaid payouts right now",
    exportBtn: "Generate SCB upload file",
    exporting: "Generating…",
    exportHint: "Downloads a .txt file and records these jobs as paid (prevents double-pay).",
    loadError: "Failed to load",
    saveError: "Failed to save",
    exportError: "Failed to generate the file",
    nothingToPay: "Nothing payable right now",
  },
};

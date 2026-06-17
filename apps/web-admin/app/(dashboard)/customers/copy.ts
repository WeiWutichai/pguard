// Screen-local bilingual copy for the customers screen. NEW design strings only (Admin -
// Customers); shared strings (common.*) keep using src/lib/i18n.tsx (single-writer).
//
// Contract reality (profile.customer_profiles → adminListCustomerProfiles): only full_name,
// address, created_at (+ the total row count) are real. The design's per-customer aggregates
// (bookings count, total spend, account "quality", individual/company type, payment method)
// and the KPI roll-ups have NO v2 endpoint — they render as honest gap chips, exactly like
// the guards screen, never invented numbers.
import type { Lang } from "@/lib/lang";

export interface CustomersCopy {
  title: string;
  /** Subtitle carries the live count: "ลูกค้าที่อนุมัติแล้ว 2,418 คน". */
  subtitle: (n: string) => string;
  kpiTotal: string;
  kpiSpend: string;
  kpiBookings: string;
  kpiRepeat: string;
  chipIndividual: string;
  chipCompany: string;
  searchPlaceholder: string;
  awaitingApi: string;
  colCustomer: string;
  colAddress: string;
  colBookings: string;
  colSpend: string;
  colQuality: string;
  detailTitle: string;
  bookings: string;
  spend: string;
  account: string;
  address: string;
  quality: string;
  payment: string;
  approvalStatus: string;
  signedUp: string;
  approved: string;
  bookingHistory: string;
  suspend: string;
  of: string;
}

export const COPY: Record<Lang, CustomersCopy> = {
  th: {
    title: "ลูกค้า",
    subtitle: (n) => `ลูกค้าที่ส่งโปรไฟล์แล้ว ${n} คน`,
    kpiTotal: "ลูกค้าทั้งหมด",
    kpiSpend: "รายได้สุทธิ (30 วัน)",
    kpiBookings: "การจอง (30 วัน)",
    kpiRepeat: "กลับมาใช้ซ้ำ",
    chipIndividual: "บุคคล",
    chipCompany: "นิติบุคคล",
    searchPlaceholder: "ค้นหาลูกค้า",
    awaitingApi: "รอ API",
    colCustomer: "ลูกค้า",
    colAddress: "ที่อยู่",
    colBookings: "การจอง",
    colSpend: "ใช้จ่ายรวม",
    colQuality: "คุณภาพบัญชี",
    detailTitle: "รายละเอียดลูกค้า",
    bookings: "การจอง",
    spend: "ใช้จ่ายรวม",
    account: "ข้อมูลบัญชี",
    address: "ที่อยู่",
    quality: "คุณภาพบัญชี",
    payment: "วิธีชำระเงิน",
    approvalStatus: "สถานะการอนุมัติ",
    signedUp: "สมัครสมาชิก",
    approved: "อนุมัติแล้ว",
    bookingHistory: "ดูประวัติการจอง",
    suspend: "ระงับบัญชี",
    of: "จาก",
  },
  en: {
    title: "Customers",
    subtitle: (n) => `${n} customers with a profile`,
    kpiTotal: "Total customers",
    kpiSpend: "Net revenue (30d)",
    kpiBookings: "Bookings (30d)",
    kpiRepeat: "Repeat rate",
    chipIndividual: "Individual",
    chipCompany: "Company",
    searchPlaceholder: "Search",
    awaitingApi: "awaiting API",
    colCustomer: "Customer",
    colAddress: "Address",
    colBookings: "Bookings",
    colSpend: "Total spend",
    colQuality: "Quality",
    detailTitle: "Customer detail",
    bookings: "Bookings",
    spend: "Total spend",
    account: "Account",
    address: "Address",
    quality: "Quality",
    payment: "Payment method",
    approvalStatus: "Approval",
    signedUp: "Signed up",
    approved: "Approved",
    bookingHistory: "Booking history",
    suspend: "Suspend",
    of: "of",
  },
};

/** Avatar initials from a customer's name; falls back to the user-id prefix. */
export function customerInitials(name: string | null | undefined, userId: string): string {
  const trimmed = name?.trim();
  if (trimmed) {
    return trimmed
      .split(/\s+/)
      .slice(0, 2)
      .map((p) => p.charAt(0))
      .join("");
  }
  return userId.slice(0, 2).toUpperCase();
}

/** Friendly label for a payment `payment_method` wire value — the validated v2 set is
 * promptpay / credit_card / debit_card / mobile_banking. Falls back to the raw value
 * (de-underscored + capitalized) so an unknown method is shown honestly, never hidden. */
export function paymentMethodLabel(method: string, lang: Lang): string {
  const known: Record<string, { th: string; en: string }> = {
    promptpay: { th: "พร้อมเพย์", en: "PromptPay" },
    credit_card: { th: "บัตรเครดิต", en: "Credit card" },
    debit_card: { th: "บัตรเดบิต", en: "Debit card" },
    mobile_banking: { th: "โมบายแบงก์กิ้ง", en: "Mobile banking" },
  };
  const hit = known[method.toLowerCase()];
  if (hit) return lang === "th" ? hit.th : hit.en;
  const pretty = method.replace(/_/g, " ");
  return pretty.charAt(0).toUpperCase() + pretty.slice(1);
}

/** Localized signup date from the ISO `created_at`. */
export function fmtSignup(iso: string, lang: Lang): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return new Intl.DateTimeFormat(lang === "th" ? "th-TH" : "en-GB", {
    year: "numeric",
    month: "short",
    day: "numeric",
  }).format(d);
}

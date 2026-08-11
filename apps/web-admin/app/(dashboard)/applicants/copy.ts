// Screen-local bilingual copy + display helpers for the ผู้สมัคร (applicants / approval queue)
// screen. NEW design strings only — shared strings (common.*, applicants.*) keep coming from
// src/lib/i18n.tsx, which is single-writer.
//
// Identity on this screen (2026-08-11): an applicant is shown as a PERSON, not as a record. The
// row leads with the best available name — this profile's `full_name`, else the name on the same
// user's OTHER role (the admin name-resolver UNIONs guard + customer profiles) — and falls back to
// the LOGIN phone when there is genuinely no name anywhere. `login_phone` is the account's own
// number (`identity.users.phone`, how they signed up and log in; always present on a live
// account); a customer's `contact_phone` is a DIFFERENT, optional field the customer may type into
// their profile. Reading `contact_phone` as "the applicant's phone" is exactly what made the queue
// show "#5680b50f / —" for a reachable person, so the two are labelled apart here.
import type { Lang } from "@/lib/lang";

export interface ApplicantsCopy {
  title: string;
  lead: string;
  kpiPending: string;
  kpiApproved: string;
  kpiRejected: string;
  kpiAvgTime: string;
  awaitingApi: string;
  typeGuards: string;
  typeCustomers: string;
  statusRejected: string;
  typeGuard: string;
  typeCustomer: string;
  colApplicant: string;
  colType: string;
  colStatus: string;
  /** The OPTIONAL extra contact a customer typed into their profile — NOT the login number. */
  colOtherContact: string;
  /** Header tooltip spelling out that "other contact" is not how you reach the applicant. */
  colOtherContactHint: string;
  colSignedUp: string;
  colCompany: string;
  /** Tooltip on the phone line: this is the number the account signs in with. */
  loginPhoneHint: string;
  view: string;
  avgEmpty: string;
  avgHours: (h: number) => string;
  avgSample: (n: number) => string;
}

export const COPY: Record<Lang, ApplicantsCopy> = {
  th: {
    title: "ผู้สมัคร",
    lead: "อนุมัติเจ้าหน้าที่และลูกค้าใหม่",
    kpiPending: "รออนุมัติ",
    kpiApproved: "อนุมัติแล้ว (รวม)",
    kpiRejected: "ปฏิเสธ",
    kpiAvgTime: "เวลาอนุมัติเฉลี่ย",
    awaitingApi: "รอ API",
    typeGuards: "เจ้าหน้าที่ รปภ.",
    typeCustomers: "ผู้เรียก รปภ.",
    statusRejected: "ปฏิเสธ",
    typeGuard: "เจ้าหน้าที่ รปภ.",
    typeCustomer: "ผู้เรียก รปภ.",
    colApplicant: "ผู้สมัคร",
    colType: "ประเภท",
    colStatus: "สถานะ",
    colOtherContact: "ติดต่อเพิ่มเติม",
    colOtherContactHint: "เบอร์/อีเมลเสริมที่ลูกค้ากรอกเอง — ไม่ใช่เบอร์ที่ใช้เข้าสู่ระบบ",
    colSignedUp: "สมัครเมื่อ",
    colCompany: "บริษัท",
    loginPhoneHint: "เบอร์ที่ใช้สมัครและเข้าสู่ระบบ",
    view: "ดู",
    avgEmpty: "—",
    avgHours: (h: number) => `${h} ชม.`,
    avgSample: (n: number) => `จาก ${n} รายการ`,
  },
  en: {
    title: "Applicants",
    lead: "Approve new guards & customers",
    kpiPending: "Pending",
    kpiApproved: "Approved total",
    kpiRejected: "Rejected",
    kpiAvgTime: "Avg. approval time",
    awaitingApi: "awaiting API",
    typeGuards: "Guards",
    typeCustomers: "Customers",
    statusRejected: "Rejected",
    typeGuard: "Guard",
    typeCustomer: "Customer",
    colApplicant: "Applicant",
    colType: "Type",
    colStatus: "Status",
    colOtherContact: "Other contact",
    colOtherContactHint:
      "Optional phone/email the customer typed in — not the number they log in with",
    colSignedUp: "Signed up",
    colCompany: "Company",
    loginPhoneHint: "The number this account signed up and logs in with",
    view: "View",
    avgEmpty: "—",
    avgHours: (h: number) => `${h}h`,
    avgSample: (n: number) => `over ${n} approved`,
  },
};

/** Localized signup date from the ISO `created_at` ("11 ส.ค. 2026"). Gregorian so the year matches
 *  every other admin screen rather than th-TH's default Buddhist era. Tolerates a missing/invalid
 *  value (an older row, or a service that hasn't shipped the field yet) → em dash. */
export function fmtSignup(iso: string | null | undefined, lang: Lang): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return new Intl.DateTimeFormat(lang === "th" ? "th-TH-u-ca-gregory" : "en-GB", {
    year: "numeric",
    month: "short",
    day: "numeric",
  }).format(d);
}

/** Group a Thai number for reading/dialling: "0828917380" → "082-891-7380" (10-digit mobile) and
 *  "021234567" → "02-123-4567" (9-digit landline). `+66…` is normalised to its 0-prefixed local
 *  form first. Anything else (a foreign number, an oddly-stored value) is returned trimmed, never
 *  mangled. Returns null for an absent/blank number so callers can pick their own fallback. */
export function fmtPhone(raw: string | null | undefined): string | null {
  const trimmed = raw?.trim();
  if (!trimmed) return null;
  const digits = trimmed.replace(/\D/g, "");
  const local = trimmed.startsWith("+66") ? `0${digits.slice(2)}` : digits;
  if (/^0\d{9}$/.test(local)) return `${local.slice(0, 3)}-${local.slice(3, 6)}-${local.slice(6)}`;
  if (/^0\d{8}$/.test(local)) return `${local.slice(0, 2)}-${local.slice(2, 5)}-${local.slice(5)}`;
  return trimmed;
}

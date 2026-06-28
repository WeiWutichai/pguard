// Screen-local bilingual copy for the reports (รายงาน) analytics screen.
// Backed by payment `GET /admin/reports/revenue` + booking `GET /admin/reports/bookings` +
// booking `GET /admin/reports/bookings-by-service`. All four panels are REAL now (revenue trend,
// guard utilization heatmap, retention cohort, AND bookings-by-service-type, #140) — bookings now
// carry a `service_id` linking to the catalog, so the by-service panel groups jobs by service type.
import type { Lang } from "@/lib/lang";

export const RANGE_DAYS = [30, 60, 90] as const;
export type RangeDays = (typeof RANGE_DAYS)[number];

/** 2-hour bucket labels (0 = 00:00). 12 buckets across the day. */
export const HOUR_BUCKETS = Array.from({ length: 12 }, (_, i) => i * 2);

export interface ReportsCopy {
  title: string;
  subtitle: string;
  rangeLabel: (d: number) => string;
  exportCsv: string;
  revenueHead: string;
  revenueLegend: string;
  bookingsLegend: string;
  momLabel: string;
  byServiceHead: string;
  byServiceUnspecified: string;
  byServiceCountUnit: string;
  utilizationHead: string;
  utilizationUnit: string;
  retentionHead: string;
  weekLabel: (n: number) => string;
  dow: string[]; // index 0 = Sunday (Postgres dow)
  totalRevenue: string;
  totalBookings: string;
}

export const COPY: Record<Lang, ReportsCopy> = {
  th: {
    title: "รายงาน",
    subtitle: "วิเคราะห์ผลการดำเนินงาน",
    rangeLabel: (d) => `${d} วัน`,
    exportCsv: "ส่งออก CSV",
    revenueHead: "แนวโน้มรายได้",
    revenueLegend: "รายได้ (สุทธิ)",
    bookingsLegend: "จำนวนงาน",
    momLabel: "เทียบช่วงก่อน",
    byServiceHead: "งานตามประเภทบริการ",
    byServiceUnspecified: "ไม่ระบุประเภท",
    byServiceCountUnit: "งาน",
    utilizationHead: "การใช้งานเจ้าหน้าที่",
    utilizationUnit: "ชม.-คน × ช่วงเวลา",
    retentionHead: "การกลับมาใช้ซ้ำของลูกค้า",
    weekLabel: (n) => `สัปดาห์ ${n}`,
    dow: ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"],
    totalRevenue: "รายได้รวม",
    totalBookings: "งานทั้งหมด",
  },
  en: {
    title: "Reports",
    subtitle: "Operational analytics",
    rangeLabel: (d) => `${d} days`,
    exportCsv: "Export CSV",
    revenueHead: "Revenue trend",
    revenueLegend: "Revenue (net)",
    bookingsLegend: "Bookings",
    momLabel: "vs prior period",
    byServiceHead: "Bookings by service",
    byServiceUnspecified: "Unspecified",
    byServiceCountUnit: "jobs",
    utilizationHead: "Guard utilization",
    utilizationUnit: "guard-hrs × time",
    retentionHead: "Customer retention",
    weekLabel: (n) => `Week ${n}`,
    dow: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
    totalRevenue: "Total revenue",
    totalBookings: "Total bookings",
  },
};

/** Format a satang-free ฿ amount from a decimal STRING (money rule: never parse for storage,
 *  only for display). Thousands separator, no decimals for the headline. */
export function fmtBaht(decimalStr: string | number | null | undefined): string {
  const n = typeof decimalStr === "number" ? decimalStr : parseFloat(decimalStr ?? "0");
  if (!Number.isFinite(n)) return "฿0";
  return `฿${Math.round(n).toLocaleString("en-US")}`;
}

/** Compact ISO day (YYYY-MM-DD) → localized short date. */
export function fmtDay(iso: string, lang: Lang): string {
  return new Date(iso).toLocaleDateString(lang === "th" ? "th-TH" : "en-GB", {
    month: "short",
    day: "numeric",
  });
}

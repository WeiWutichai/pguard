// Screen-local bilingual copy for the reports (รายงาน) analytics screen.
// Backed by payment `GET /admin/reports/revenue` + booking `GET /admin/reports/bookings`.
// Three panels are REAL (revenue trend, guard utilization heatmap, retention cohort); the
// design's "bookings by service type" panel is an HONEST GAP — the v2 booking model has no
// service_type dimension (adding it entails the deferred catalog→charge integration decision).
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
  byServiceGap: string;
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
    byServiceGap:
      "v2 ยังไม่มีมิติ service_type ใน booking (ต้องตัดสินใจเรื่องผูก catalog→ตอนคิดเงินก่อน)",
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
    byServiceGap:
      "v2 has no service_type dimension on bookings yet (needs the deferred catalog→charge decision)",
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

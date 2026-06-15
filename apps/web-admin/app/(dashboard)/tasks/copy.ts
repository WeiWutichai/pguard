// Screen-local bilingual copy for the tasks (จัดการงานทั้งหมด) screen — a table/calendar board
// over ALL bookings with bulk actions. Domain helpers (status enum/tone/labels, money) are
// REUSED from the bookings screen (same entity); only tasks-specific strings live here.
import type { Lang } from "@/lib/lang";

// Pre-arrival statuses a bulk-cancel is legal on (booking.yaml: cancel allowed only
// requested/accepted/en_route — once a guard is on-site the job runs to completion review).
export const CANCELLABLE = ["requested", "accepted", "en_route"] as const;

export interface TasksCopy {
  title: string;
  subtitle: (n: string) => string;
  viewTable: string;
  viewCalendar: string;
  filterAll: string;
  filterUnassigned: string;
  searchPlaceholder: string;
  awaitingApi: string;
  selected: (n: number) => string;
  bulkAssign: string;
  bulkCancel: string;
  bulkRefund: string;
  cancelling: string;
  cancelResult: (ok: number, skipped: number) => string;
  colRequest: string;
  colCustomer: string;
  colGuard: string;
  colStatus: string;
  colScheduled: string;
  colAmount: string;
  unassigned: string;
  assign: string;
  /** calendar weekday short names, Sun→Sat. */
  weekdays: string[];
  of: string;
}

export const COPY: Record<Lang, TasksCopy> = {
  th: {
    title: "จัดการงานทั้งหมด",
    subtitle: (n) => `คำขอจ้างทุกสถานะ ${n} รายการ`,
    viewTable: "ตาราง",
    viewCalendar: "ปฏิทิน",
    filterAll: "ทุกสถานะ",
    filterUnassigned: "ยังไม่จัด",
    searchPlaceholder: "ค้นหา request / ลูกค้า / ที่อยู่…",
    awaitingApi: "รอ API",
    selected: (n) => `เลือก ${n} รายการ`,
    bulkAssign: "มอบหมาย",
    bulkCancel: "ยกเลิก",
    bulkRefund: "คืนเงิน",
    cancelling: "กำลังยกเลิก…",
    cancelResult: (ok, skipped) =>
      `ยกเลิกแล้ว ${ok} รายการ${skipped ? ` · ข้าม ${skipped} (สถานะไม่อนุญาต)` : ""}`,
    colRequest: "Request",
    colCustomer: "ลูกค้า",
    colGuard: "เจ้าหน้าที่",
    colStatus: "สถานะ",
    colScheduled: "นัดหมาย",
    colAmount: "ยอด",
    unassigned: "ยังไม่จัด",
    assign: "มอบหมาย",
    weekdays: ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"],
    of: "จาก",
  },
  en: {
    title: "Tasks",
    subtitle: (n) => `${n} guard requests, all statuses`,
    viewTable: "Table",
    viewCalendar: "Calendar",
    filterAll: "All status",
    filterUnassigned: "Unassigned",
    searchPlaceholder: "Search request / customer / address…",
    awaitingApi: "awaiting API",
    selected: (n) => `${n} selected`,
    bulkAssign: "Assign",
    bulkCancel: "Cancel",
    bulkRefund: "Refund",
    cancelling: "Cancelling…",
    cancelResult: (ok, skipped) =>
      `Cancelled ${ok}${skipped ? ` · skipped ${skipped} (status disallows)` : ""}`,
    colRequest: "Request",
    colCustomer: "Customer",
    colGuard: "Guard",
    colStatus: "Status",
    colScheduled: "Scheduled",
    colAmount: "Amount",
    unassigned: "Unassigned",
    assign: "Assign",
    weekdays: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
    of: "of",
  },
};

// Screen-local bilingual copy for the bookings (จัดการงาน) screen. NEW design strings only,
// taken from the hi-fi mockup (Admin - Bookings); shared strings (common.*) keep using
// src/lib/i18n.tsx (single-writer). Status LABELS map the REAL v2 BookingStatus enum
// (requested/accepted/en_route/arrived/pending_completion/completed/cancelled/declined) —
// the design's chips ("pending"/"assigned"/"started") predate the final state machine, so
// we render the contract's statuses, not the mockup's.
import type { Lang } from "@/lib/lang";

/** The real v2 lifecycle statuses (contract: booking.yaml BookingStatus). */
export const STATUSES = [
  "requested",
  "accepted",
  "en_route",
  "arrived",
  "pending_completion",
  "completed",
  "cancelled",
  "declined",
] as const;
export type BookingStatusKey = (typeof STATUSES)[number];

/** Badge tone per status (admin.css palette intent: in-flight=amber, on-site/accepted=blue,
 * done=green, terminal-bad=red). */
export const STATUS_TONE: Record<BookingStatusKey, "green" | "amber" | "red" | "blue" | "gray"> = {
  requested: "amber",
  accepted: "blue",
  en_route: "amber",
  arrived: "blue",
  pending_completion: "amber",
  completed: "green",
  cancelled: "red",
  declined: "red",
};

/** Cancellation / decline reason CODES (contract: `booking.bookings.cancellation_reason` is a
 * STABLE lowercase snake_case code, never localized text). Customer cancel emits
 * changed_plan|mistake|not_needed|other; guard decline emits emergency|sick|cannot_reach|other —
 * the admin renders both sets from one table. */
export const CANCEL_REASON_CODES = [
  "changed_plan",
  "mistake",
  "not_needed",
  "emergency",
  "sick",
  "cannot_reach",
  "other",
] as const;
export type CancelReasonCode = (typeof CANCEL_REASON_CODES)[number];

/** The statuses that can carry a cancellation reason. */
export function isCancelledStatus(status: string): boolean {
  return status === "cancelled" || status === "declined";
}

export interface BookingCancellation {
  /** The raw wire CODE (not a label) — null for pre-migration rows and legacy bookings. */
  reason: string | null;
  note: string | null;
}

/** Read the cancellation fields off a booking. They ride on the booking JSON as
 * `cancellation_reason` + `cancellation_note`; read STRUCTURALLY (not off the `Booking` type) so
 * this compiles either side of the OpenAPI client regen that adds them, and so a pre-migration
 * row (both NULL) degrades to `{ null, null }` instead of rendering "undefined". */
export function cancellationOf(booking: unknown): BookingCancellation {
  const b = booking as { cancellation_reason?: unknown; cancellation_note?: unknown } | null;
  const reason = typeof b?.cancellation_reason === "string" ? b.cancellation_reason.trim() : "";
  const note = typeof b?.cancellation_note === "string" ? b.cancellation_note.trim() : "";
  return { reason: reason || null, note: note || null };
}

/** Localized label for a reason code. An UNKNOWN code (a newer client shipping a code this
 * build predates) falls back to the raw code — the admin is an internal tool, so a visible
 * `snake_case` code beats silently dropping the reason. */
export function reasonText(code: string, c: BookingsCopy): string {
  return (c.reasonLabel as Partial<Record<string, string>>)[code] ?? code;
}

export interface BookingsCopy {
  title: string;
  /** Subtitle carries the live count: "งานทั้งหมด 27 รายการ". */
  subtitle: (n: string) => string;
  searchPlaceholder: string;
  colBooking: string;
  colCustomer: string;
  colGuard: string;
  colTime: string;
  colAmount: string;
  colStatus: string;
  /** Inline gap chip for design data with no v2 endpoint/field yet. */
  awaitingApi: string;
  assign: string;
  assignTitle: string;
  assignGuardLabel: string;
  assignPick: string;
  assignConfirm: string;
  assignDone: string;
  /** assign failed (409 already-assigned / illegal state, or network). */
  assignError: string;
  noGuardYet: string;
  unassigned: string;
  detailTitle: string;
  total: string;
  duration: string;
  guardsCount: string;
  customer: string;
  assignedGuard: string;
  /** Detail-panel heading when the CUSTOMER cancelled. */
  cancelReason: string;
  /** …and when the GUARD declined. */
  declineReason: string;
  cancellationNote: string;
  /** Terminal booking with no reason on record (cancelled before the field existed). */
  cancellationNone: string;
  reasonLabel: Record<CancelReasonCode, string>;
  hoursUnit: string;
  peopleUnit: string;
  /** Pagination connector: "1–9 จาก 27". */
  of: string;
  statusLabel: Record<BookingStatusKey, string>;
}

export const COPY: Record<Lang, BookingsCopy> = {
  th: {
    title: "จัดการงาน",
    subtitle: (n) => `งานทั้งหมด ${n} รายการ`,
    searchPlaceholder: "ค้นหา booking / ลูกค้า / ที่อยู่…",
    colBooking: "Booking",
    colCustomer: "ลูกค้า",
    colGuard: "เจ้าหน้าที่",
    colTime: "เวลา",
    colAmount: "ยอด",
    colStatus: "สถานะ",
    awaitingApi: "รอ API",
    assign: "มอบหมาย",
    assignTitle: "มอบหมายเจ้าหน้าที่",
    assignGuardLabel: "เลือกเจ้าหน้าที่ (อนุมัติแล้ว)",
    assignPick: "— เลือกเจ้าหน้าที่ —",
    assignConfirm: "มอบหมายเจ้าหน้าที่",
    assignDone: "มอบหมายเจ้าหน้าที่แล้ว",
    assignError: "มอบหมายไม่สำเร็จ — งานนี้อาจมีเจ้าหน้าที่แล้วหรือสถานะไม่อนุญาต",
    noGuardYet: "ยังไม่มีเจ้าหน้าที่ — เลือกด้านล่างเพื่อมอบหมาย",
    unassigned: "ยังไม่มอบหมาย",
    detailTitle: "รายละเอียดงาน",
    total: "ยอดรวม",
    duration: "ระยะเวลา",
    guardsCount: "จำนวน",
    customer: "ลูกค้า",
    assignedGuard: "เจ้าหน้าที่ที่มอบหมาย",
    cancelReason: "เหตุผลที่ลูกค้ายกเลิก",
    declineReason: "เหตุผลที่เจ้าหน้าที่ยกเลิก",
    cancellationNote: "หมายเหตุ",
    cancellationNone: "ไม่ได้ระบุเหตุผล",
    reasonLabel: {
      changed_plan: "เปลี่ยนแผน",
      mistake: "แจ้งผิดพลาด",
      not_needed: "ไม่ต้องการแล้ว",
      emergency: "เหตุฉุกเฉินส่วนตัว",
      sick: "ป่วย",
      cannot_reach: "เดินทางไปไม่ได้",
      other: "อื่นๆ",
    },
    hoursUnit: "ชม.",
    peopleUnit: "คน",
    of: "จาก",
    statusLabel: {
      requested: "รอรับงาน",
      accepted: "รับงานแล้ว",
      en_route: "กำลังเดินทาง",
      arrived: "ถึงจุดแล้ว",
      pending_completion: "รอยืนยันจบงาน",
      completed: "เสร็จสิ้น",
      cancelled: "ยกเลิก",
      declined: "ปฏิเสธงาน",
    },
  },
  en: {
    title: "Bookings",
    subtitle: (n) => `${n} bookings`,
    searchPlaceholder: "Search booking / customer / address…",
    colBooking: "Booking",
    colCustomer: "Customer",
    colGuard: "Guard",
    colTime: "Time",
    colAmount: "Amount",
    colStatus: "Status",
    awaitingApi: "awaiting API",
    assign: "Assign",
    assignTitle: "Assign guard",
    assignGuardLabel: "Pick an approved guard",
    assignPick: "— select a guard —",
    assignConfirm: "Assign guard",
    assignDone: "Guard assigned",
    assignError: "Assign failed — the booking may already have a guard, or its status disallows it",
    noGuardYet: "No guard yet — pick one below to assign",
    unassigned: "Unassigned",
    detailTitle: "Booking detail",
    total: "Total",
    duration: "Duration",
    guardsCount: "Guards",
    customer: "Customer",
    assignedGuard: "Assigned guard",
    cancelReason: "Cancellation reason",
    declineReason: "Decline reason",
    cancellationNote: "Note",
    cancellationNone: "No reason recorded",
    reasonLabel: {
      changed_plan: "Changed plans",
      mistake: "Booked by mistake",
      not_needed: "No longer needed",
      emergency: "Personal emergency",
      sick: "Sick",
      cannot_reach: "Can't reach site",
      other: "Other",
    },
    hoursUnit: "h",
    peopleUnit: "",
    of: "of",
    statusLabel: {
      requested: "Requested",
      accepted: "Accepted",
      en_route: "En route",
      arrived: "Arrived",
      pending_completion: "Pending completion",
      completed: "Completed",
      cancelled: "Cancelled",
      declined: "Declined",
    },
  },
};

/** Booking total = base_fee × hours × guard_count + tip. base_fee/tip arrive as Decimal
 * strings (serde-str on the wire), hours/guard_count as ints. Formatted as ฿ with thousands
 * separators, no decimals (design: "฿1,840"). */
export function bookingTotal(b: {
  base_fee?: string | number | null;
  hours?: number | null;
  guard_count?: number | null;
  tip?: string | number | null;
}): number {
  const base = Number(b.base_fee ?? 0);
  const tip = Number(b.tip ?? 0);
  const hours = b.hours ?? 0;
  const guards = b.guard_count ?? 1;
  const total = base * hours * guards + tip;
  return Number.isFinite(total) ? total : 0;
}

export function fmtBaht(n: number): string {
  return `฿${Math.round(n).toLocaleString("en-US")}`;
}

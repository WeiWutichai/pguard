// Screen-local bilingual copy for the support-tickets (แจ้งปัญหา / ส่งความคิดเห็น) screen —
// the queue of tickets filed from the mobile Help page (profile `GET /admin/support/tickets`).
// Newest first; each row carries the reporter (resolved to a name), the kind, the message, the
// filing time, and the lifecycle status.
import type { Lang } from "@/lib/lang";

export interface TicketsCopy {
  title: string;
  subtitle: (n: string) => string;
  searchPlaceholder: string;
  empty: string;
  error: string;
  colWhen: string;
  colReporter: string;
  colKind: string;
  colMessage: string;
  colStatus: string;
  of: string;
  /** Friendly labels for the ticket `kind`. */
  kindLabel: Record<string, string>;
  /** Friendly labels for the ticket `status`. */
  statusLabel: Record<string, string>;
}

export const COPY: Record<Lang, TicketsCopy> = {
  th: {
    title: "แจ้งปัญหา / ส่งความคิดเห็น",
    subtitle: (n) => `เรื่องที่แจ้งเข้ามา ${n} รายการ`,
    searchPlaceholder: "ค้นหาข้อความ / ผู้แจ้ง…",
    empty: "ยังไม่มีเรื่องแจ้งเข้ามา",
    error: "โหลดรายการไม่สำเร็จ กรุณาลองใหม่",
    colWhen: "เวลา",
    colReporter: "ผู้แจ้ง",
    colKind: "ประเภท",
    colMessage: "ข้อความ",
    colStatus: "สถานะ",
    of: "จาก",
    kindLabel: {
      problem: "แจ้งปัญหา",
      feedback: "ความคิดเห็น",
    },
    statusLabel: {
      open: "ใหม่",
    },
  },
  en: {
    title: "Support Tickets",
    subtitle: (n) => `${n} tickets`,
    searchPlaceholder: "Search message / reporter…",
    empty: "No tickets yet",
    error: "Could not load tickets — please try again",
    colWhen: "When",
    colReporter: "Reporter",
    colKind: "Type",
    colMessage: "Message",
    colStatus: "Status",
    of: "of",
    kindLabel: {
      problem: "Problem",
      feedback: "Feedback",
    },
    statusLabel: {
      open: "Open",
    },
  },
};

export function kindText(kind: string, c: TicketsCopy): string {
  return c.kindLabel[kind] ?? kind;
}

export function statusText(status: string, c: TicketsCopy): string {
  return c.statusLabel[status] ?? status;
}

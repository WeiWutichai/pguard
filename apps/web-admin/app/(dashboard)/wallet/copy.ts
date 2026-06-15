// Screen-local bilingual copy for the wallet (กระเป๋าเงิน) screen — a READ-ONLY admin payment
// ledger built on adminListPayments (prepared ahead of a real payment integration). The
// design's manual refund queue (pending → confirm-with-slip → skip) contradicts the locked v2
// decision that refunds are AUTOMATIC / event-driven, and has no endpoint — it renders as an
// honest gap, never a fake action. Money helpers (fmtBaht) are reused from bookings/copy.
import type { Lang } from "@/lib/lang";

/** payment.payment_status enum (real). */
export const PAYMENT_STATUSES = ["pending", "completed", "refunded"] as const;
export type PaymentStatusKey = (typeof PAYMENT_STATUSES)[number];

export const PAYMENT_TONE: Record<PaymentStatusKey, "green" | "amber" | "blue" | "gray"> = {
  pending: "amber",
  completed: "green",
  refunded: "blue",
};

export interface WalletCopy {
  title: string;
  subtitle: (n: string) => string;
  kpiTotal: string;
  kpiCompleted: string;
  kpiRefunded: string;
  kpiPendingRefunds: string;
  searchPlaceholder: string;
  awaitingApi: string;
  refundQueueGap: string;
  colPayment: string;
  colCustomer: string;
  colGuard: string;
  colAmount: string;
  colStatus: string;
  colRefund: string;
  colPaid: string;
  refundPending: string;
  refundProcessed: string;
  statusLabel: Record<PaymentStatusKey, string>;
  of: string;
}

export const COPY: Record<Lang, WalletCopy> = {
  th: {
    title: "กระเป๋าเงิน",
    subtitle: (n) => `ธุรกรรมการชำระทั้งหมด ${n} รายการ`,
    kpiTotal: "ธุรกรรมทั้งหมด",
    kpiCompleted: "ชำระสำเร็จ",
    kpiRefunded: "คืนเงินแล้ว",
    kpiPendingRefunds: "รอคืนเงิน",
    searchPlaceholder: "ค้นหา payment / ลูกค้า / booking…",
    awaitingApi: "รอ API",
    refundQueueGap:
      "v2 คืนเงินอัตโนมัติแบบ event-driven — ไม่มีคิวอนุมัติคืนเงินด้วยมือ (pending/processed/skipped ของดีไซน์รอ API)",
    colPayment: "Payment",
    colCustomer: "ลูกค้า",
    colGuard: "เจ้าหน้าที่",
    colAmount: "ยอด",
    colStatus: "สถานะ",
    colRefund: "คืนเงิน",
    colPaid: "ชำระเมื่อ",
    refundPending: "รอคืน",
    refundProcessed: "คืนแล้ว",
    statusLabel: { pending: "รอชำระ", completed: "ชำระสำเร็จ", refunded: "คืนเงินแล้ว" },
    of: "จาก",
  },
  en: {
    title: "Wallet & Refunds",
    subtitle: (n) => `${n} payments`,
    kpiTotal: "Total payments",
    kpiCompleted: "Completed",
    kpiRefunded: "Refunded",
    kpiPendingRefunds: "Pending refunds",
    searchPlaceholder: "Search payment / customer / booking…",
    awaitingApi: "awaiting API",
    refundQueueGap:
      "v2 refunds are automatic / event-driven — there is no manual approval queue (the design's pending/processed/skipped tabs await an API)",
    colPayment: "Payment",
    colCustomer: "Customer",
    colGuard: "Guard",
    colAmount: "Amount",
    colStatus: "Status",
    colRefund: "Refund",
    colPaid: "Paid",
    refundPending: "Pending",
    refundProcessed: "Processed",
    statusLabel: { pending: "Pending", completed: "Completed", refunded: "Refunded" },
    of: "of",
  },
};

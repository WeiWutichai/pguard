// Screen-local bilingual copy for the wallet (กระเป๋าเงิน) screen — a READ-ONLY admin payment
// ledger built on adminListPayments. It stays read-only on purpose: a refund is OWED automatically
// (the completion reconcile, a cancellation, the race-lost pre-pay, a duplicate slip), and the
// money then leaves through the SCB bulk file generated on `/refunds` — one place where refunds are
// actually sent, with a batch history and a paid-marker behind it. Acting on a single row here
// would be a second, unrecorded path to the same money. Money helpers (fmtBaht) come from
// bookings/copy.
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
  /** Where a "รอคืน" row on this ledger actually gets paid out — this screen only reports it. */
  refundActionNote: string;
  /** The link's own label (the destination screen, named). */
  refundActionLink: string;
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
    refundActionNote:
      "หน้านี้ดูอย่างเดียว — ยอดที่ขึ้นว่า “รอคืน” จะถูกคืนจริงด้วยการสร้างไฟล์อัปโหลด SCB ที่หน้าคืนเงินลูกค้า (ไฟล์เดียวคืนได้หลายคน มีประวัติไฟล์และกันคืนซ้ำ) รวมถึงกรณีลูกค้าโอนซ้ำที่ไม่ได้อยู่ในตารางนี้",
    refundActionLink: "ไปหน้าคืนเงินลูกค้า",
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
    refundActionNote:
      "This ledger is read-only — a row marked “Pending” is actually refunded by generating the SCB upload file on the customer-refunds screen (one file refunds many customers, with a batch history and a double-refund guard). That screen also covers duplicate transfers, which never appear in this table.",
    refundActionLink: "Open customer refunds",
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

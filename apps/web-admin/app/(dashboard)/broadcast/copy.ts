// Screen-local bilingual copy for the broadcast (ส่งการแจ้งเตือน) screen — admin bulk-send.
// Backed by notification `/admin/broadcasts` (compose/draft/schedule/list) + `/admin/audience-
// counts`. The audience is resolved cross-service from profile (service-JWT). The per-user target
// (#138) is LIVE via the identity admin user-search (GET /admin/users/search — all roles, phone
// masked) + notification /notifications/send. The design's promo/safety notification types are
// NOT in the v2 contract (the enum is system/booking_*/…) → those stay out of scope, never faked.
import type { Lang } from "@/lib/lang";

export const AUDIENCES = ["all", "guards", "customers"] as const;
export type AudienceKey = (typeof AUDIENCES)[number];

export const BROADCAST_STATUSES = ["draft", "scheduled", "sent"] as const;
export type BroadcastStatusKey = (typeof BROADCAST_STATUSES)[number];

export const STATUS_TONE: Record<BroadcastStatusKey, "green" | "amber" | "gray"> = {
  draft: "gray",
  scheduled: "amber",
  sent: "green",
};

export interface BroadcastCopy {
  title: string;
  subtitle: (n: string) => string;
  composeHead: string;
  previewHead: string;
  historyHead: string;
  audienceLabel: string;
  audienceName: Record<AudienceKey, string>;
  // Per-user targeting (live via identity admin user-search + notification /notifications/send).
  perUserHead: string;
  perUserSearch: string;
  perUserSearchHint: string;
  perUserCleared: string;
  perUserNoResults: string;
  perUserLoading: string;
  perUserSearchError: string;
  perUserSendBtn: string;
  perUserSentOk: (name: string) => string;
  perUserNeedTitleBody: string;
  perUserScopeNote: string;
  guardTag: string;
  customerTag: string;
  adminTag: string;
  titleLabel: string;
  titlePlaceholder: string;
  bodyLabel: string;
  bodyPlaceholder: string;
  scheduleLabel: string;
  sendNow: string;
  scheduleLater: string;
  saveDraft: string;
  sendBtn: string;
  scheduleBtn: string;
  recipients: (n: string) => string;
  statusLabel: Record<BroadcastStatusKey, string>;
  previewAppName: string;
  previewNow: string;
  sentOk: (n: string) => string;
  draftOk: string;
  scheduledOk: string;
  scheduleNeeded: string;
}

export const COPY: Record<Lang, BroadcastCopy> = {
  th: {
    title: "ส่งการแจ้งเตือน",
    subtitle: (n) => `ส่งแล้ว ${n} รายการ`,
    composeHead: "เขียนข้อความใหม่",
    previewHead: "ตัวอย่าง",
    historyHead: "ส่งล่าสุด",
    audienceLabel: "กลุ่มเป้าหมาย",
    audienceName: { all: "ผู้ใช้ทั้งหมด", guards: "เฉพาะเจ้าหน้าที่", customers: "เฉพาะลูกค้า" },
    perUserHead: "ส่งถึงผู้ใช้รายคน",
    perUserSearch: "ค้นหาผู้ใช้",
    perUserSearchHint: "พิมพ์ชื่อ เบอร์โทร หรืออีเมลเพื่อค้นหา",
    perUserCleared: "ล้าง",
    perUserNoResults: "ไม่พบผู้ใช้",
    perUserLoading: "กำลังค้นหา…",
    perUserSearchError: "ค้นหาไม่สำเร็จ กรุณาลองใหม่",
    perUserSendBtn: "ส่งถึงคนนี้",
    perUserSentOk: (name) => `ส่งการแจ้งเตือนถึง ${name} แล้ว`,
    perUserNeedTitleBody: "กรอกหัวข้อและเนื้อหาก่อนส่ง",
    perUserScopeNote: "ค้นหาผู้ใช้ทุกบทบาท (เจ้าหน้าที่ · ลูกค้า · แอดมิน) ด้วยชื่อ เบอร์โทร หรืออีเมล",
    guardTag: "เจ้าหน้าที่",
    customerTag: "ลูกค้า",
    adminTag: "แอดมิน",
    titleLabel: "หัวข้อ",
    titlePlaceholder: "เช่น อัปเดตระบบใหม่ 🎉",
    bodyLabel: "เนื้อหา",
    bodyPlaceholder: "ข้อความที่จะส่งถึงผู้ใช้…",
    scheduleLabel: "กำหนดส่ง",
    sendNow: "ส่งทันที",
    scheduleLater: "ตั้งเวลา",
    saveDraft: "บันทึกร่าง",
    sendBtn: "ส่งเลย",
    scheduleBtn: "ตั้งเวลาส่ง",
    recipients: (n) => `${n} คน`,
    statusLabel: { draft: "ร่าง", scheduled: "ตั้งเวลา", sent: "ส่งแล้ว" },
    previewAppName: "pguard · ตอนนี้",
    previewNow: "ตอนนี้",
    sentOk: (n) => `ส่งการแจ้งเตือนถึง ${n} คนแล้ว`,
    draftOk: "บันทึกร่างแล้ว",
    scheduledOk: "ตั้งเวลาส่งแล้ว",
    scheduleNeeded: "กรุณาเลือกเวลาส่งในอนาคต",
  },
  en: {
    title: "Broadcast",
    subtitle: (n) => `${n} broadcasts sent`,
    composeHead: "Compose",
    previewHead: "Preview",
    historyHead: "Sent history",
    audienceLabel: "Target audience",
    audienceName: { all: "All users", guards: "Guards only", customers: "Customers only" },
    perUserHead: "Send to a specific user",
    perUserSearch: "Search user",
    perUserSearchHint: "Type a name, phone, or email to search",
    perUserCleared: "Clear",
    perUserNoResults: "No matching users",
    perUserLoading: "Searching…",
    perUserSearchError: "Search failed — please try again",
    perUserSendBtn: "Send to this user",
    perUserSentOk: (name) => `Notification sent to ${name}`,
    perUserNeedTitleBody: "Add a title and body before sending",
    perUserScopeNote: "Search users across all roles (guards · customers · admins) by name, phone, or email",
    guardTag: "Guard",
    customerTag: "Customer",
    adminTag: "Admin",
    titleLabel: "Title",
    titlePlaceholder: "e.g. New system update 🎉",
    bodyLabel: "Body",
    bodyPlaceholder: "The message users will receive…",
    scheduleLabel: "Schedule",
    sendNow: "Send now",
    scheduleLater: "Schedule",
    saveDraft: "Save draft",
    sendBtn: "Send now",
    scheduleBtn: "Schedule",
    recipients: (n) => `${n} recipients`,
    statusLabel: { draft: "Draft", scheduled: "Scheduled", sent: "Sent" },
    previewAppName: "pguard · now",
    previewNow: "now",
    sentOk: (n) => `Broadcast delivered to ${n} recipients`,
    draftOk: "Draft saved",
    scheduledOk: "Broadcast scheduled",
    scheduleNeeded: "Pick a future send time",
  },
};

/** Format a recipient count: thousands separator, "—" for null/0. */
export function fmtCount(n: number | null | undefined): string {
  if (n == null || n <= 0) return "—";
  return n.toLocaleString("en-US");
}

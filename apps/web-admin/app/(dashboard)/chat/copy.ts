// Screen-local bilingual copy for the chat (แชท) admin moderation screen — a READ-ONLY
// conversation list (chat `GET /admin/conversations`) + a per-conversation message read pane
// (`GET /conversations/{id}/messages`, admin bypasses the participant gate). The design's
// moderation actions (flag / delete message / block user / archive) have no v2 endpoint →
// honest gaps; admins can READ but not act.
import type { Lang } from "@/lib/lang";

export interface ChatCopy {
  title: string;
  subtitle: (n: string) => string;
  searchPlaceholder: string;
  awaitingApi: string;
  moderationGap: string;
  colConversation: string;
  colParticipants: string;
  colStatus: string;
  colLastMessage: string;
  colMessages: string;
  colCreated: string;
  detailTitle: string;
  loadingMessages: string;
  noMessages: string;
  guard: string;
  customer: string;
  system: string;
  of: string;
  // Enriched-render labels.
  imageLabel: string;
  videoLabel: string;
  attachmentUnavailable: string;
  callAudio: string;
  callVideo: string;
  callCompleted: string;
  callMissed: string;
  callRejected: string;
  callDuration: (s: string) => string;
}

export const COPY: Record<Lang, ChatCopy> = {
  th: {
    title: "แชท",
    subtitle: (n) => `บทสนทนาทั้งหมด ${n} รายการ`,
    searchPlaceholder: "ค้นหาบทสนทนา / ผู้ร่วม…",
    awaitingApi: "รอ API",
    moderationGap:
      "ดูได้อย่างเดียว — การกำกับ (ตั้งค่าสถานะ/ลบข้อความ/บล็อก/เก็บถาวร) ยังไม่มี endpoint ใน v2",
    colConversation: "บทสนทนา",
    colParticipants: "ผู้ร่วม",
    colStatus: "สถานะงาน",
    colLastMessage: "ข้อความล่าสุด",
    colMessages: "จำนวนข้อความ",
    colCreated: "เริ่มเมื่อ",
    detailTitle: "ข้อความในบทสนทนา",
    loadingMessages: "กำลังโหลดข้อความ…",
    noMessages: "ยังไม่มีข้อความ",
    guard: "เจ้าหน้าที่",
    customer: "ลูกค้า",
    system: "ระบบ",
    of: "จาก",
    imageLabel: "รูปภาพ",
    videoLabel: "วิดีโอ",
    attachmentUnavailable: "ไฟล์แนบ (เปิดไม่ได้)",
    callAudio: "สายเสียง",
    callVideo: "สายวิดีโอ",
    callCompleted: "รับสาย",
    callMissed: "ไม่ได้รับสาย",
    callRejected: "ปฏิเสธสาย",
    callDuration: (s) => `· ${s}`,
  },
  en: {
    title: "Chat",
    subtitle: (n) => `${n} conversations`,
    searchPlaceholder: "Search conversation / participants…",
    awaitingApi: "awaiting API",
    moderationGap:
      "Read-only — moderation (flag / delete message / block / archive) has no v2 endpoint",
    colConversation: "Conversation",
    colParticipants: "Participants",
    colStatus: "Job status",
    colLastMessage: "Last message",
    colMessages: "Messages",
    colCreated: "Started",
    detailTitle: "Conversation messages",
    loadingMessages: "Loading messages…",
    noMessages: "No messages yet",
    guard: "Guard",
    customer: "Customer",
    system: "System",
    of: "of",
    imageLabel: "Photo",
    videoLabel: "Video",
    attachmentUnavailable: "Attachment (unavailable)",
    callAudio: "Voice call",
    callVideo: "Video call",
    callCompleted: "completed",
    callMissed: "missed",
    callRejected: "rejected",
    callDuration: (s) => `· ${s}`,
  },
};

/** Label a message's sender_role for display. */
export function senderLabel(role: string | null | undefined, c: ChatCopy): string {
  if (role === "guard") return c.guard;
  if (role === "customer") return c.customer;
  return c.system;
}

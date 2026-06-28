// Screen-local bilingual copy for the chat (แชท) admin moderation screen — a conversation list
// (chat `GET /admin/conversations`) + a per-conversation message pane (`GET /admin/conversations/
// {id}/messages`, admin bypasses the participant gate). Phase D (#136/#137) added the WRITE surface:
// redact a message (`DELETE /admin/messages/{id}`), archive/reactivate a conversation
// (`PUT /admin/conversations/{id}/status`), and block/unblock a user from chat
// (`PUT|DELETE /admin/users/{user_id}/block`) — each admin-only, audited, idempotent. Redacted
// messages render as removed; the original content is never re-exposed.
import type { Lang } from "@/lib/lang";

export interface ChatCopy {
  title: string;
  subtitle: (n: string) => string;
  searchPlaceholder: string;
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
  // --- Phase D moderation (#136/#137) ---
  moderationHead: string;
  archiveAction: string;
  reactivateAction: string;
  redactAction: string;
  blockAction: string;
  redactedBadge: string;
  redactedBody: string;
  reasonLabel: string;
  reasonPlaceholder: string;
  cancel: string;
  confirm: string;
  working: string;
  /** Confirm-dialog titles + bodies (some take the target's display name). */
  confirmRedactTitle: string;
  confirmRedactBody: string;
  confirmArchiveTitle: string;
  confirmArchiveBody: string;
  confirmReactivateTitle: string;
  confirmReactivateBody: string;
  confirmBlockTitle: string;
  confirmBlockBody: (name: string) => string;
  actionFailed: string;
  noopHint: string;
  /** Status pill shown when the thread is archived. */
  archivedBadge: string;
}

export const COPY: Record<Lang, ChatCopy> = {
  th: {
    title: "แชท",
    subtitle: (n) => `บทสนทนาทั้งหมด ${n} รายการ`,
    searchPlaceholder: "ค้นหาบทสนทนา / ผู้ร่วม…",
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
    moderationHead: "การกำกับดูแล",
    archiveAction: "เก็บถาวร",
    reactivateAction: "เปิดใช้ใหม่",
    redactAction: "ลบข้อความ",
    blockAction: "บล็อกผู้ใช้",
    redactedBadge: "ถูกลบโดยผู้ดูแล",
    redactedBody: "[ข้อความถูกลบโดยผู้ดูแล]",
    reasonLabel: "เหตุผล (บันทึกในประวัติ)",
    reasonPlaceholder: "ระบุเหตุผล… (ไม่บังคับ)",
    cancel: "ยกเลิก",
    confirm: "ยืนยัน",
    working: "กำลังดำเนินการ…",
    confirmRedactTitle: "ลบข้อความนี้?",
    confirmRedactBody:
      "ข้อความจะถูกซ่อนจากทุกฝ่าย (เก็บไว้เพื่อตรวจสอบเท่านั้น) การกระทำนี้ย้อนกลับไม่ได้",
    confirmArchiveTitle: "เก็บบทสนทนาถาวร?",
    confirmArchiveBody: "ผู้ร่วมจะส่งข้อความใหม่ไม่ได้จนกว่าจะเปิดใช้ใหม่",
    confirmReactivateTitle: "เปิดบทสนทนาใหม่?",
    confirmReactivateBody: "ผู้ร่วมจะกลับมาส่งข้อความได้อีกครั้ง",
    confirmBlockTitle: "บล็อกผู้ใช้จากแชท?",
    confirmBlockBody: (name) => `${name} จะส่งข้อความในทุกบทสนทนาไม่ได้`,
    actionFailed: "ดำเนินการไม่สำเร็จ ลองอีกครั้ง",
    noopHint: "อยู่ในสถานะนี้อยู่แล้ว",
    archivedBadge: "เก็บถาวร",
  },
  en: {
    title: "Chat",
    subtitle: (n) => `${n} conversations`,
    searchPlaceholder: "Search conversation / participants…",
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
    moderationHead: "Moderation",
    archiveAction: "Archive",
    reactivateAction: "Reactivate",
    redactAction: "Redact",
    blockAction: "Block user",
    redactedBadge: "Removed by moderator",
    redactedBody: "[message removed by moderator]",
    reasonLabel: "Reason (recorded in audit log)",
    reasonPlaceholder: "Reason… (optional)",
    cancel: "Cancel",
    confirm: "Confirm",
    working: "Working…",
    confirmRedactTitle: "Redact this message?",
    confirmRedactBody:
      "The message is hidden from all parties (kept in-table for audit only). This cannot be undone.",
    confirmArchiveTitle: "Archive conversation?",
    confirmArchiveBody: "Participants can't send new messages until it's reactivated.",
    confirmReactivateTitle: "Reactivate conversation?",
    confirmReactivateBody: "Participants will be able to send messages again.",
    confirmBlockTitle: "Block user from chat?",
    confirmBlockBody: (name) => `${name} won't be able to send in any conversation.`,
    actionFailed: "Action failed — please try again.",
    noopHint: "Already in this state.",
    archivedBadge: "Archived",
  },
};

/** Label a message's sender_role for display. */
export function senderLabel(role: string | null | undefined, c: ChatCopy): string {
  if (role === "guard") return c.guard;
  if (role === "customer") return c.customer;
  return c.system;
}

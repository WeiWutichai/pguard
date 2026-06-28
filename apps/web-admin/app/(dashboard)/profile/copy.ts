// Screen-local bilingual copy for the admin profile (โปรไฟล์ผู้ดูแล) screen.
// REAL: the identity card (role + user_id from /auth/me via useAuth) and "sign out everywhere"
// (the new self-serve POST /auth/revoke-all). HONEST GAPS (no v2 endpoint): editable name/email,
// change-password, 2FA, the per-session list + per-session revoke, API tokens, and the personal
// activity feed — v2 identity exposes only user_id+role, families/jti aren't listed as devices,
// and there's no per-admin business-action feed. Overlaps settings by design (low-value screen).
import type { Lang } from "@/lib/lang";

export interface ProfileCopy {
  title: string;
  subtitle: string;
  accountHead: string;
  accountSub: string;
  roleLabel: string;
  userIdLabel: string;
  nameLabel: string;
  emailLabel: string;
  changePassword: string;
  save: string;
  twoFaHead: string;
  twoFaSub: string;
  sessionsHead: string;
  signOutAll: string;
  signOutAllSub: string;
  signOutConfirmTitle: string;
  signOutConfirmBody: string;
  confirm: string;
  cancel: string;
  tokensHead: string;
  generate: string;
  activityHead: string;
  gapAccountEdit: string;
  gapSessions: string;
  gapTokens: string;
  gapActivity: string;
  gap2fa: string;
  signOutError: string;
  activitySub: string;
  activityLoading: string;
  activityEmpty: string;
  activityError: string;
  viewAll: string;
}

export const COPY: Record<Lang, ProfileCopy> = {
  th: {
    title: "โปรไฟล์ผู้ดูแล",
    subtitle: "บัญชี ความปลอดภัย และเซสชัน",
    accountHead: "ข้อมูลบัญชี",
    accountSub: "บทบาทและรหัสผู้ใช้ของคุณ",
    roleLabel: "บทบาท",
    userIdLabel: "รหัสผู้ใช้",
    nameLabel: "ชื่อ-นามสกุล",
    emailLabel: "อีเมล",
    changePassword: "เปลี่ยนรหัสผ่าน",
    save: "บันทึก",
    twoFaHead: "ยืนยันตัวตน 2 ขั้น (2FA)",
    twoFaSub: "เพิ่มความปลอดภัยด้วยแอป Authenticator",
    sessionsHead: "ความปลอดภัยของเซสชัน",
    signOutAll: "ออกจากทุกอุปกรณ์",
    signOutAllSub: "เพิกถอนทุกเซสชันทันที — ทุกเครื่อง (รวมเครื่องนี้) ต้องเข้าสู่ระบบใหม่",
    signOutConfirmTitle: "ออกจากทุกอุปกรณ์?",
    signOutConfirmBody:
      "ทุกเซสชันที่ใช้งานอยู่จะถูกเพิกถอนทันที และคุณจะถูกพาไปหน้าเข้าสู่ระบบ",
    confirm: "ออกจากทุกอุปกรณ์",
    cancel: "ยกเลิก",
    tokensHead: "API Tokens",
    generate: "สร้างใหม่",
    activityHead: "กิจกรรมล่าสุดของฉัน",
    gapAccountEdit: "v2 ยังไม่มี endpoint แก้ไขชื่อ/อีเมล/รหัสผ่านของแอดมิน (/auth/me คืนแค่ role + id)",
    gapSessions: "v2 ติดตาม refresh family + jti แต่ยังไม่ได้เปิดเป็นรายการอุปกรณ์/IP",
    gapTokens: "v2 ยังไม่มี personal API token",
    gapActivity: "แสดงกิจกรรมการเข้าถึงข้อมูล (PDPA §30) ของคุณ — ยังไม่ใช่ฟีดเหตุการณ์ธุรกิจเต็มรูป",
    gap2fa: "v2 ยังไม่มี 2FA",
    signOutError: "เพิกถอนเซสชันไม่สำเร็จ กรุณาลองใหม่",
    activitySub: "การเข้าถึงข้อมูลล่าสุดของคุณ",
    activityLoading: "กำลังโหลด…",
    activityEmpty: "ยังไม่มีกิจกรรม",
    activityError: "โหลดกิจกรรมไม่สำเร็จ",
    viewAll: "ดูทั้งหมด",
  },
  en: {
    title: "Admin Profile",
    subtitle: "Account, security & sessions",
    accountHead: "Account details",
    accountSub: "Your role and user ID",
    roleLabel: "Role",
    userIdLabel: "User ID",
    nameLabel: "Full name",
    emailLabel: "Email",
    changePassword: "Change password",
    save: "Save",
    twoFaHead: "Two-factor authentication",
    twoFaSub: "Extra security via an Authenticator app",
    sessionsHead: "Session security",
    signOutAll: "Sign out everywhere",
    signOutAllSub: "Revoke every session at once — all devices (including this one) must sign in again",
    signOutConfirmTitle: "Sign out everywhere?",
    signOutConfirmBody:
      "Every active session is revoked immediately and you'll be sent to the sign-in screen.",
    confirm: "Sign out everywhere",
    cancel: "Cancel",
    tokensHead: "API tokens",
    generate: "Generate",
    activityHead: "My recent activity",
    gapAccountEdit: "v2 has no admin name/email/password edit endpoint (/auth/me returns role + id only)",
    gapSessions: "v2 tracks refresh families + jti but doesn't yet expose them as a device/IP list",
    gapTokens: "v2 has no personal API tokens yet",
    gapActivity: "Shows your PDPA §30 data-access activity — not the full business-action feed yet",
    gap2fa: "v2 has no 2FA yet",
    signOutError: "Couldn't revoke sessions — please try again",
    activitySub: "Your recent data access",
    activityLoading: "Loading…",
    activityEmpty: "No activity yet",
    activityError: "Couldn't load activity",
    viewAll: "View all",
  },
};

// Screen-local bilingual copy for the admin profile (โปรไฟล์ผู้ดูแล) screen.
// REAL (#144): the account card now LOADS name/email from GET /auth/me, SAVES via PUT /auth/me
// (display_name 1–120 + optional email; 409 EMAIL_TAKEN surfaced), and changes the password via
// PUT /auth/password (current + new PIN, SHA-256-hashed client-side); plus the identity card
// (role + user_id) and "sign out everywhere" (POST /auth/revoke-all). HONEST GAPS (no v2 endpoint
// — left for Phase D): 2FA, the per-session device list + per-session revoke, and API tokens.
// The personal feed is the PDPA §30 data-access audit (not the full business-action feed yet).
import type { Lang } from "@/lib/lang";

export interface ProfileCopy {
  title: string;
  subtitle: string;
  accountHead: string;
  accountSub: string;
  roleLabel: string;
  userIdLabel: string;
  nameLabel: string;
  namePlaceholder: string;
  emailLabel: string;
  emailPlaceholder: string;
  changePassword: string;
  save: string;
  accountLoading: string;
  accountLoadError: string;
  savedOk: string;
  saveError: string;
  nameRequired: string;
  emailInvalid: string;
  emailTaken: string;
  // Change-password modal
  pwTitle: string;
  pwIntro: string;
  pwCurrentLabel: string;
  pwNewLabel: string;
  pwConfirmLabel: string;
  pwHint: string;
  pwMismatch: string;
  pwTooShort: string;
  pwWrongCurrent: string;
  pwError: string;
  pwSubmit: string;
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
    namePlaceholder: "เช่น สมชาย ใจดี",
    emailLabel: "อีเมล",
    emailPlaceholder: "you@example.com",
    changePassword: "เปลี่ยนรหัสผ่าน",
    save: "บันทึก",
    accountLoading: "กำลังโหลดข้อมูลบัญชี…",
    accountLoadError: "โหลดข้อมูลบัญชีไม่สำเร็จ",
    savedOk: "บันทึกแล้ว",
    saveError: "บันทึกไม่สำเร็จ กรุณาลองใหม่",
    nameRequired: "กรุณากรอกชื่อ",
    emailInvalid: "รูปแบบอีเมลไม่ถูกต้อง",
    emailTaken: "อีเมลนี้ถูกใช้แล้ว",
    pwTitle: "เปลี่ยนรหัสผ่าน",
    pwIntro: "ยืนยันรหัสผ่านปัจจุบัน แล้วตั้งรหัสใหม่ — ทุกอุปกรณ์อื่นจะถูกออกจากระบบทันที",
    pwCurrentLabel: "รหัสผ่านปัจจุบัน",
    pwNewLabel: "รหัสผ่านใหม่",
    pwConfirmLabel: "ยืนยันรหัสผ่านใหม่",
    pwHint: "อย่างน้อย 6 ตัวอักษร",
    pwMismatch: "รหัสผ่านใหม่ไม่ตรงกัน",
    pwTooShort: "รหัสผ่านใหม่ต้องมีอย่างน้อย 6 ตัวอักษร",
    pwWrongCurrent: "รหัสผ่านปัจจุบันไม่ถูกต้อง",
    pwError: "เปลี่ยนรหัสผ่านไม่สำเร็จ กรุณาลองใหม่",
    pwSubmit: "เปลี่ยนรหัสผ่าน",
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
    namePlaceholder: "e.g. Somchai Jaidee",
    emailLabel: "Email",
    emailPlaceholder: "you@example.com",
    changePassword: "Change password",
    save: "Save",
    accountLoading: "Loading account…",
    accountLoadError: "Couldn't load account details",
    savedOk: "Saved",
    saveError: "Couldn't save — please try again",
    nameRequired: "Name is required",
    emailInvalid: "Invalid email format",
    emailTaken: "That email is already in use",
    pwTitle: "Change password",
    pwIntro: "Confirm your current password, then set a new one — every other device is signed out immediately.",
    pwCurrentLabel: "Current password",
    pwNewLabel: "New password",
    pwConfirmLabel: "Confirm new password",
    pwHint: "At least 6 characters",
    pwMismatch: "New passwords don't match",
    pwTooShort: "New password must be at least 6 characters",
    pwWrongCurrent: "Current password is incorrect",
    pwError: "Couldn't change password — please try again",
    pwSubmit: "Change password",
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

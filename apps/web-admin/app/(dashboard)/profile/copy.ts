// Screen-local bilingual copy for the admin profile (โปรไฟล์ผู้ดูแล) screen.
// LIVE (#144): the account card LOADS name/email from GET /auth/me, SAVES via PUT /auth/me
// (display_name 1–120 + optional email; 409 EMAIL_TAKEN surfaced), and changes the password via
// PUT /auth/password (current + new PIN, SHA-256-hashed client-side); plus the identity card
// (role + user_id) and "sign out everywhere" (POST /auth/revoke-all).
//
// NOW WIRED (#144 identity security): 2FA enrollment (setup→QR→enable→recovery codes→disable),
// per-device SESSION list (GET /auth/sessions + DELETE /auth/sessions/{family_id}), and admin API
// tokens (create-once / list / revoke). The personal feed is the PDPA §30 data-access audit.
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
  // ---- 2FA ----
  twoFaHead: string;
  twoFaSub: string;
  twoFaOn: string;
  twoFaOff: string;
  twoFaUnknown: string;
  twoFaEnable: string;
  twoFaDisable: string;
  twoFaSetupTitle: string;
  twoFaScanIntro: string;
  twoFaSecretLabel: string;
  twoFaCodeLabel: string;
  twoFaCodeHint: string;
  twoFaConfirm: string;
  twoFaSetupError: string;
  twoFaWrongCode: string;
  twoFaAlreadyOn: string;
  twoFaRecoveryTitle: string;
  twoFaRecoveryIntro: string;
  twoFaRecoveryWarn: string;
  twoFaRecoveryDone: string;
  twoFaCopyCodes: string;
  twoFaDisableTitle: string;
  twoFaDisableIntro: string;
  twoFaDisableConfirm: string;
  twoFaDisableError: string;
  twoFaEnabledNow: string;
  twoFaDisabledNow: string;
  // ---- Session security ----
  sessionsHead: string;
  sessionsSub: string;
  signOutAll: string;
  signOutAllSub: string;
  signOutConfirmTitle: string;
  signOutConfirmBody: string;
  confirm: string;
  cancel: string;
  sessionsLoading: string;
  sessionsError: string;
  sessionsEmpty: string;
  thisDevice: string;
  unknownDevice: string;
  lastSeen: string;
  created: string;
  revokeSession: string;
  revokeSessionTitle: string;
  revokeSessionBody: string;
  revokeSessionError: string;
  // ---- API tokens ----
  tokensHead: string;
  tokensSub: string;
  generate: string;
  tokensLoading: string;
  tokensError: string;
  tokensEmpty: string;
  colName: string;
  colPrefix: string;
  colCreated: string;
  colLastUsed: string;
  colStatus: string;
  colActions: string;
  statusActive: string;
  statusRevoked: string;
  neverUsed: string;
  revoke: string;
  createTokenTitle: string;
  createTokenIntro: string;
  tokenNameLabel: string;
  tokenNamePlaceholder: string;
  tokenNameRequired: string;
  createTokenSubmit: string;
  createTokenError: string;
  tokenCreatedTitle: string;
  tokenCreatedIntro: string;
  tokenCreatedWarn: string;
  tokenCopied: string;
  copy: string;
  done: string;
  revokeTokenTitle: string;
  revokeTokenBody: string;
  revokeTokenError: string;
  // ---- Activity ----
  activityHead: string;
  gapActivity: string;
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
    twoFaOn: "เปิดใช้งานอยู่",
    twoFaOff: "ปิดอยู่",
    twoFaUnknown: "ยังไม่ทราบสถานะ",
    twoFaEnable: "เปิดใช้งาน 2FA",
    twoFaDisable: "ปิด 2FA",
    twoFaSetupTitle: "ตั้งค่ายืนยันตัวตน 2 ขั้น",
    twoFaScanIntro:
      "สแกน QR นี้ด้วยแอป Authenticator (เช่น Google Authenticator, 1Password) หรือกรอกคีย์ด้านล่างด้วยมือ แล้วใส่รหัส 6 หลักเพื่อยืนยัน",
    twoFaSecretLabel: "คีย์สำหรับกรอกเอง",
    twoFaCodeLabel: "รหัส 6 หลักจากแอป",
    twoFaCodeHint: "ใส่รหัสที่แสดงในแอป Authenticator ตอนนี้",
    twoFaConfirm: "ยืนยันและเปิดใช้งาน",
    twoFaSetupError: "เริ่มตั้งค่า 2FA ไม่สำเร็จ กรุณาลองใหม่",
    twoFaWrongCode: "รหัสไม่ถูกต้อง กรุณาลองใหม่",
    twoFaAlreadyOn: "บัญชีนี้เปิด 2FA อยู่แล้ว",
    twoFaRecoveryTitle: "รหัสกู้คืน (Recovery codes)",
    twoFaRecoveryIntro:
      "เก็บรหัสเหล่านี้ไว้ในที่ปลอดภัย ใช้เข้าสู่ระบบได้เมื่อไม่มีแอป Authenticator (ใช้ได้ครั้งเดียวต่อรหัส)",
    twoFaRecoveryWarn: "แสดงเพียงครั้งเดียว — บันทึกไว้ตอนนี้ ไม่สามารถดูซ้ำได้",
    twoFaRecoveryDone: "บันทึกแล้ว ปิดหน้าต่าง",
    twoFaCopyCodes: "คัดลอกรหัสทั้งหมด",
    twoFaDisableTitle: "ปิดการยืนยันตัวตน 2 ขั้น",
    twoFaDisableIntro:
      "ยืนยันด้วยรหัส 6 หลักจากแอป หรือรหัสผ่านบัญชี เพื่อปิด 2FA — รหัสกู้คืนทั้งหมดจะถูกลบ",
    twoFaDisableConfirm: "ปิด 2FA",
    twoFaDisableError: "ปิด 2FA ไม่สำเร็จ — รหัส/รหัสผ่านไม่ถูกต้อง",
    twoFaEnabledNow: "เปิด 2FA แล้ว",
    twoFaDisabledNow: "ปิด 2FA แล้ว",
    sessionsHead: "ความปลอดภัยของเซสชัน",
    sessionsSub: "อุปกรณ์ที่เข้าสู่ระบบอยู่",
    signOutAll: "ออกจากทุกอุปกรณ์",
    signOutAllSub: "เพิกถอนทุกเซสชันทันที — ทุกเครื่อง (รวมเครื่องนี้) ต้องเข้าสู่ระบบใหม่",
    signOutConfirmTitle: "ออกจากทุกอุปกรณ์?",
    signOutConfirmBody:
      "ทุกเซสชันที่ใช้งานอยู่จะถูกเพิกถอนทันที และคุณจะถูกพาไปหน้าเข้าสู่ระบบ",
    confirm: "ออกจากทุกอุปกรณ์",
    cancel: "ยกเลิก",
    sessionsLoading: "กำลังโหลดเซสชัน…",
    sessionsError: "โหลดเซสชันไม่สำเร็จ",
    sessionsEmpty: "ไม่มีเซสชันที่ใช้งานอยู่",
    thisDevice: "เครื่องนี้",
    unknownDevice: "อุปกรณ์ไม่ทราบชื่อ",
    lastSeen: "ใช้งานล่าสุด",
    created: "เริ่มเมื่อ",
    revokeSession: "ออกจากระบบ",
    revokeSessionTitle: "ออกจากอุปกรณ์นี้?",
    revokeSessionBody: "เซสชันนี้จะถูกเพิกถอนทันที และอุปกรณ์นั้นต้องเข้าสู่ระบบใหม่",
    revokeSessionError: "เพิกถอนเซสชันไม่สำเร็จ กรุณาลองใหม่",
    tokensHead: "API Tokens",
    tokensSub: "โทเคนสำหรับเรียก API แทนบัญชีของคุณ",
    generate: "สร้างใหม่",
    tokensLoading: "กำลังโหลดโทเคน…",
    tokensError: "โหลดโทเคนไม่สำเร็จ",
    tokensEmpty: "ยังไม่มี API token",
    colName: "ชื่อ",
    colPrefix: "Prefix",
    colCreated: "สร้างเมื่อ",
    colLastUsed: "ใช้ล่าสุด",
    colStatus: "สถานะ",
    colActions: "",
    statusActive: "ใช้งานได้",
    statusRevoked: "ถูกเพิกถอน",
    neverUsed: "ยังไม่เคยใช้",
    revoke: "เพิกถอน",
    createTokenTitle: "สร้าง API token",
    createTokenIntro: "ตั้งชื่อให้จดจำได้ เช่น “บอท CI/CD” หรือ “สคริปต์รายงาน”",
    tokenNameLabel: "ชื่อโทเคน",
    tokenNamePlaceholder: "เช่น บอท CI deploy",
    tokenNameRequired: "กรุณาตั้งชื่อโทเคน",
    createTokenSubmit: "สร้างโทเคน",
    createTokenError: "สร้างโทเคนไม่สำเร็จ กรุณาลองใหม่",
    tokenCreatedTitle: "สร้างโทเคนแล้ว",
    tokenCreatedIntro: "นี่คือโทเคนแบบเต็ม ใช้เป็น Bearer token ในการเรียก API",
    tokenCreatedWarn: "แสดงเพียงครั้งเดียว — คัดลอกและเก็บไว้ตอนนี้ ไม่สามารถดูซ้ำได้",
    tokenCopied: "คัดลอกแล้ว",
    copy: "คัดลอก",
    done: "เสร็จสิ้น",
    revokeTokenTitle: "เพิกถอนโทเคนนี้?",
    revokeTokenBody: "โทเคนจะใช้ไม่ได้ทันที คำขอที่ใช้โทเคนนี้จะถูกปฏิเสธ",
    revokeTokenError: "เพิกถอนโทเคนไม่สำเร็จ กรุณาลองใหม่",
    activityHead: "กิจกรรมล่าสุดของฉัน",
    gapActivity: "แสดงกิจกรรมการเข้าถึงข้อมูล (PDPA §30) ของคุณ — ยังไม่ใช่ฟีดเหตุการณ์ธุรกิจเต็มรูป",
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
    twoFaOn: "Enabled",
    twoFaOff: "Off",
    twoFaUnknown: "Status unknown",
    twoFaEnable: "Enable 2FA",
    twoFaDisable: "Disable 2FA",
    twoFaSetupTitle: "Set up two-factor authentication",
    twoFaScanIntro:
      "Scan this QR with an Authenticator app (Google Authenticator, 1Password, etc.) — or enter the key below by hand — then type the 6-digit code to confirm.",
    twoFaSecretLabel: "Manual-entry key",
    twoFaCodeLabel: "6-digit code from your app",
    twoFaCodeHint: "Enter the code shown in your Authenticator app right now.",
    twoFaConfirm: "Confirm & enable",
    twoFaSetupError: "Couldn't start 2FA setup — please try again",
    twoFaWrongCode: "Incorrect code — please try again",
    twoFaAlreadyOn: "2FA is already enabled on this account",
    twoFaRecoveryTitle: "Recovery codes",
    twoFaRecoveryIntro:
      "Store these somewhere safe. Each one signs you in once if you lose your Authenticator app.",
    twoFaRecoveryWarn: "Shown only once — save them now; they can't be retrieved again.",
    twoFaRecoveryDone: "I've saved them — close",
    twoFaCopyCodes: "Copy all codes",
    twoFaDisableTitle: "Disable two-factor authentication",
    twoFaDisableIntro:
      "Confirm with a 6-digit code from your app or your account password to turn 2FA off — all recovery codes are cleared.",
    twoFaDisableConfirm: "Disable 2FA",
    twoFaDisableError: "Couldn't disable 2FA — wrong code or password",
    twoFaEnabledNow: "2FA enabled",
    twoFaDisabledNow: "2FA disabled",
    sessionsHead: "Session security",
    sessionsSub: "Devices currently signed in",
    signOutAll: "Sign out everywhere",
    signOutAllSub: "Revoke every session at once — all devices (including this one) must sign in again",
    signOutConfirmTitle: "Sign out everywhere?",
    signOutConfirmBody:
      "Every active session is revoked immediately and you'll be sent to the sign-in screen.",
    confirm: "Sign out everywhere",
    cancel: "Cancel",
    sessionsLoading: "Loading sessions…",
    sessionsError: "Couldn't load sessions",
    sessionsEmpty: "No active sessions",
    thisDevice: "This device",
    unknownDevice: "Unknown device",
    lastSeen: "Last seen",
    created: "Started",
    revokeSession: "Sign out",
    revokeSessionTitle: "Sign out this device?",
    revokeSessionBody: "This session is revoked immediately and that device must sign in again.",
    revokeSessionError: "Couldn't revoke that session — please try again",
    tokensHead: "API tokens",
    tokensSub: "Tokens that call the API on behalf of your account",
    generate: "Generate",
    tokensLoading: "Loading tokens…",
    tokensError: "Couldn't load tokens",
    tokensEmpty: "No API tokens yet",
    colName: "Name",
    colPrefix: "Prefix",
    colCreated: "Created",
    colLastUsed: "Last used",
    colStatus: "Status",
    colActions: "",
    statusActive: "Active",
    statusRevoked: "Revoked",
    neverUsed: "Never used",
    revoke: "Revoke",
    createTokenTitle: "Create API token",
    createTokenIntro: "Give it a memorable name, e.g. “CI/CD bot” or “reporting script”.",
    tokenNameLabel: "Token name",
    tokenNamePlaceholder: "e.g. CI deploy bot",
    tokenNameRequired: "Please name the token",
    createTokenSubmit: "Create token",
    createTokenError: "Couldn't create the token — please try again",
    tokenCreatedTitle: "Token created",
    tokenCreatedIntro: "This is the full token — use it as a Bearer token when calling the API.",
    tokenCreatedWarn: "Shown only once — copy and store it now; it can't be retrieved again.",
    tokenCopied: "Copied",
    copy: "Copy",
    done: "Done",
    revokeTokenTitle: "Revoke this token?",
    revokeTokenBody: "The token stops working immediately and any request using it is rejected.",
    revokeTokenError: "Couldn't revoke the token — please try again",
    activityHead: "My recent activity",
    gapActivity: "Shows your PDPA §30 data-access activity — not the full business-action feed yet",
    activitySub: "Your recent data access",
    activityLoading: "Loading…",
    activityEmpty: "No activity yet",
    activityError: "Couldn't load activity",
    viewAll: "View all",
  },
};

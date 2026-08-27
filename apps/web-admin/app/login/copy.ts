// Screen-local bilingual copy for the login screen — exact strings from the hi-fi spec
// (web-audit/Login.md). Shared keys that already exist in src/lib/i18n.tsx
// (login.identifier / login.password / login.submit / login.error) are NOT duplicated here:
// the form keeps using t() for them (single-writer rule on i18n.tsx).
export const COPY = {
  th: {
    heroTitle: "ศูนย์สั่งการความปลอดภัย แบบเรียลไทม์",
    heroTagline:
      "จัดการเจ้าหน้าที่ งาน การเงิน และแผนที่สดของ รปภ. ทั่วเมือง — ทั้งหมดในที่เดียว",
    statGuards: "เจ้าหน้าที่",
    statCustomers: "ลูกค้า",
    statUptime: "อัปไทม์",
    formTitle: "ยินดีต้อนรับกลับ",
    formSubtitle: "เข้าสู่ระบบแผงผู้ดูแล pguard",
    remember: "จดจำฉันไว้",
    forgot: "ลืมรหัสผ่าน?",
    comingSoon: "เร็วๆ นี้ — ยังไม่มี API หลังบ้านสำหรับฟีเจอร์นี้",
    // Second login step when the account has 2FA (TOTP) enabled.
    twoFaTitle: "ยืนยันตัวตนสองชั้น",
    twoFaSubtitle: "กรอกรหัส 6 หลักจากแอป Authenticator",
    twoFaCodeLabel: "รหัสยืนยัน",
    twoFaSubmit: "ยืนยัน",
    twoFaUseRecovery: "ใช้รหัสสำรอง",
    twoFaUseCode: "ใช้รหัสจากแอปแทน",
    twoFaRecoveryLabel: "รหัสสำรอง",
    twoFaError: "รหัสไม่ถูกต้องหรือหมดอายุ กรุณาลองใหม่",
    twoFaBack: "ย้อนกลับ",
  },
  en: {
    heroTitle: "Real-time security operations center",
    heroTagline:
      "Manage guards, jobs, payments, and a live city-wide map — all in one place.",
    statGuards: "Guards",
    statCustomers: "Customers",
    statUptime: "Uptime",
    formTitle: "Welcome back",
    formSubtitle: "Sign in to the pguard admin panel",
    remember: "Remember me",
    forgot: "Forgot password?",
    comingSoon: "Coming soon — no backend endpoint for this yet",
    // Second login step when the account has 2FA (TOTP) enabled.
    twoFaTitle: "Two-factor verification",
    twoFaSubtitle: "Enter the 6-digit code from your authenticator app",
    twoFaCodeLabel: "Verification code",
    twoFaSubmit: "Verify",
    twoFaUseRecovery: "Use a recovery code",
    twoFaUseCode: "Use an authenticator code instead",
    twoFaRecoveryLabel: "Recovery code",
    twoFaError: "Invalid or expired code — please try again",
    twoFaBack: "Back",
  },
} as const;

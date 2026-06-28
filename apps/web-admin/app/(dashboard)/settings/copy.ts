// Screen-local bilingual copy for the settings rebuild — design strings quoted EXACTLY
// from the hi-fi mockup spec (Settings.md). Keys that already exist in src/lib/i18n
// (settings.title/.subtitle/.account/.role/.userId/.language/.session, header.logout)
// are used via t(); i18n.tsx is single-writer, so NEW design copy lives here.
//
// Where the mockup's EN string is missing (nav items 3/6/7 per the spec), the spec's own
// gloss is used: "Payment channels", "Security", "Team & roles".
export const COPY = {
  th: {
    // Left set-nav (design order; "แบรนด์/Branding" omitted — the mockup specs no panel
    // for it, and we don't ship dead links).
    navCompany: "บริษัท",
    navPayments: "ช่องทางชำระเงิน",
    navSms: "SMS · FCM",
    navStorage: "Storage",
    navSecurity: "ความปลอดภัย",
    navTeam: "ทีม & สิทธิ์",
    // Company profile
    companyTitle: "โปรไฟล์บริษัท",
    companySub: "ข้อมูลที่แสดงบนใบเสร็จและในแอป",
    companyName: "ชื่อบริษัท",
    taxId: "เลขผู้เสียภาษี",
    address: "ที่อยู่",
    // Payment gateways
    payTitle: "ช่องทางชำระเงิน",
    paySub: "เปิด/ปิดวิธีชำระเงินที่ลูกค้าใช้ได้",
    payPromptpay: "PromptPay",
    payPromptpaySub: "QR · พร้อมเพย์",
    payCard: "บัตรเครดิต/เดบิต",
    payCardSub: "Omise · 2C2P",
    payWallet: "pguard Wallet",
    payWalletSub: "กระเป๋าเงินในแอป",
    // SMS & notifications
    smsTitle: "SMS & การแจ้งเตือน",
    smsSub: "ผู้ให้บริการ OTP และ push",
    smsProvider: "SMS Provider",
    smsProviderSub: "OTP delivery",
    fcmKey: "FCM Server Key",
    fcmKeySub: "Firebase push",
    // Storage & security
    storageTitle: "ที่จัดเก็บไฟล์ & ความปลอดภัย",
    storageSub: "S3/R2, JWT, OTP TTL, rate limit, CORS",
    bucket: "S3 / R2 Bucket",
    jwtExpiry: "JWT expiry",
    otpTtl: "OTP TTL",
    rateLimit: "Rate limit",
    rateLimitSub: "per IP / min",
    cors: "CORS origins",
    // Team & roles
    teamTitle: "ทีมงาน & สิทธิ์",
    teamSub: "ผู้ดูแลระบบและระดับสิทธิ์",
    invite: "เชิญผู้ดูแล",
    teamGap:
      "รายชื่อทีมและระดับสิทธิ์ต้องใช้ endpoint รายชื่อผู้ดูแล ซึ่งยังไม่มีในสัญญา API ของ v2",
    // Footer
    cancel: "ยกเลิก",
    save: "บันทึกการเปลี่ยนแปลง",
    // Honest gap chip — sections whose backing admin-settings API doesn't exist in v2.
    awaitingApi: "รอ API",
    // Company-profile (live via GET/PUT /admin/org-settings).
    companyLoading: "กำลังโหลด…",
    companySaved: "บันทึกโปรไฟล์บริษัทแล้ว",
    companySaveError: "บันทึกไม่สำเร็จ กรุณาลองใหม่",
    companyLoadError: "โหลดโปรไฟล์บริษัทไม่สำเร็จ",
    taxIdHint: "8–20 หลัก (เว้นวรรค/ขีดได้) — เลขผู้เสียภาษีไทยมี 13 หลัก",
    companyNamePlaceholder: "เช่น บริษัท พีการ์ด ซิเคียวริตี้ จำกัด",
    addressPlaceholder: "ที่อยู่บริษัทบนใบเสร็จ",
    lastSaved: "บันทึกล่าสุด",
    // Honest "managed via env" note for env/secret-backed tabs.
    managedEnv: "ตั้งค่าผ่าน env",
    smsManagedNote:
      "ผู้ให้บริการ OTP และ FCM Server Key ตั้งค่าผ่าน env/secret ของบริการ — ไม่เปิดให้แก้ผ่านหน้าจอ (คีย์ลับไม่ถูกแสดงผ่าน API)",
    storageManagedNote:
      "S3/R2, JWT, OTP TTL, rate limit และ CORS เป็น config ตอน deploy (โหลดตอนเริ่มบริการ) — ไม่มี endpoint สำหรับแก้ค่าเหล่านี้",
    payFutureNote:
      "การเปิด/ปิดช่องทางชำระเงินต้องมี store ในบริการ payment (ยังไม่ได้สร้าง)",
  },
  en: {
    navCompany: "Company",
    navPayments: "Payment channels",
    navSms: "SMS · FCM",
    navStorage: "Storage",
    navSecurity: "Security",
    navTeam: "Team & roles",
    companyTitle: "Company profile",
    companySub: "Shown on receipts and in-app",
    companyName: "Company name",
    taxId: "Tax ID",
    address: "Address",
    payTitle: "Payment gateways",
    paySub: "Toggle available methods",
    payPromptpay: "PromptPay",
    payPromptpaySub: "QR · PromptPay",
    payCard: "Card",
    payCardSub: "Omise · 2C2P",
    payWallet: "pguard Wallet",
    payWalletSub: "In-app wallet",
    smsTitle: "SMS & notifications",
    smsSub: "OTP & push providers",
    smsProvider: "SMS Provider",
    smsProviderSub: "OTP delivery",
    fcmKey: "FCM Server Key",
    fcmKeySub: "Firebase push",
    storageTitle: "Storage & security",
    storageSub: "S3/R2, JWT, OTP TTL, rate limits, CORS",
    bucket: "S3 / R2 Bucket",
    jwtExpiry: "JWT expiry",
    otpTtl: "OTP TTL",
    rateLimit: "Rate limit",
    rateLimitSub: "per IP / min",
    cors: "CORS origins",
    teamTitle: "Team & roles",
    teamSub: "Admins & permission levels",
    invite: "Invite admin",
    teamGap:
      "The team list & permission levels need an admin-list API that is not in the v2 contract yet.",
    cancel: "Cancel",
    save: "Save changes",
    awaitingApi: "Awaiting API",
    companyLoading: "Loading…",
    companySaved: "Company profile saved",
    companySaveError: "Couldn't save — please try again",
    companyLoadError: "Couldn't load the company profile",
    taxIdHint: "8–20 digits (spaces/hyphens allowed) — a Thai TIN is 13 digits",
    companyNamePlaceholder: "e.g. pguard Security Co., Ltd.",
    addressPlaceholder: "Company address shown on receipts",
    lastSaved: "Last saved",
    managedEnv: "managed via env",
    smsManagedNote:
      "The OTP provider and FCM Server Key are configured via service env/secrets — not editable here (secret keys are never exposed via API).",
    storageManagedNote:
      "S3/R2, JWT, OTP TTL, rate limits and CORS are deploy-time config (loaded at service startup) — there is no endpoint to edit them.",
    payFutureNote:
      "Toggling payment channels needs a config store in the payment service (not built yet).",
  },
} as const;

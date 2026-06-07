"use client";

import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from "react";

export type Lang = "th" | "en";

/** Translation keys — both languages must define every key (enforced by the `Record` types). */
const dictionaries = {
  th: {
    "app.title": "pguard แอดมิน",
    "nav.dashboard": "แดชบอร์ด",
    "nav.applicants": "ผู้สมัคร",
    "nav.guards": "เจ้าหน้าที่",
    "nav.customers": "ลูกค้า",
    "nav.map": "แผนที่",
    "nav.reviews": "รีวิว",
    "nav.wallet": "กระเป๋าเงิน",
    "nav.pricing": "ราคา",
    "header.logout": "ออกจากระบบ",
    "login.title": "เข้าสู่ระบบแอดมิน",
    "login.identifier": "อีเมลหรือเบอร์โทร",
    "login.password": "รหัสผ่าน",
    "login.submit": "เข้าสู่ระบบ",
    "login.error": "เข้าสู่ระบบไม่สำเร็จ กรุณาตรวจสอบข้อมูล",
    "applicants.title": "ผู้สมัครเจ้าหน้าที่",
    "applicants.subtitle": "ตรวจสอบและอนุมัติโปรไฟล์เจ้าหน้าที่",
    "applicants.filter": "สถานะ",
    "applicants.approve": "อนุมัติ",
    "applicants.reject": "ปฏิเสธ",
    "applicants.empty": "ไม่มีผู้สมัครในสถานะนี้",
    "applicants.col.guard": "เจ้าหน้าที่",
    "applicants.col.experience": "ประสบการณ์",
    "applicants.col.workplace": "ที่ทำงานเดิม",
    "applicants.col.bank": "บัญชีธนาคาร",
    "applicants.col.actions": "การจัดการ",
    "applicants.years": "ปี",
    "applicants.error": "ดำเนินการไม่สำเร็จ กรุณาลองใหม่",
    "status.pending": "รออนุมัติ",
    "status.approved": "อนุมัติแล้ว",
    "status.rejected": "ปฏิเสธแล้ว",
    "common.loading": "กำลังโหลด…",
    "common.retry": "ลองใหม่",
    "common.none": "—",
    "dashboard.title": "แดชบอร์ด",
    "dashboard.welcome": "ยินดีต้อนรับสู่ pguard แอดมิน",
    "stub.soon": "หน้านี้กำลังจะมาเร็วๆ นี้",
  },
  en: {
    "app.title": "pguard admin",
    "nav.dashboard": "Dashboard",
    "nav.applicants": "Applicants",
    "nav.guards": "Guards",
    "nav.customers": "Customers",
    "nav.map": "Map",
    "nav.reviews": "Reviews",
    "nav.wallet": "Wallet",
    "nav.pricing": "Pricing",
    "header.logout": "Log out",
    "login.title": "Admin sign in",
    "login.identifier": "Email or phone",
    "login.password": "Password",
    "login.submit": "Sign in",
    "login.error": "Sign in failed — please check your details",
    "applicants.title": "Guard applicants",
    "applicants.subtitle": "Review and approve guard profiles",
    "applicants.filter": "Status",
    "applicants.approve": "Approve",
    "applicants.reject": "Reject",
    "applicants.empty": "No applicants in this status",
    "applicants.col.guard": "Guard",
    "applicants.col.experience": "Experience",
    "applicants.col.workplace": "Previous workplace",
    "applicants.col.bank": "Bank account",
    "applicants.col.actions": "Actions",
    "applicants.years": "yrs",
    "applicants.error": "Action failed — please try again",
    "status.pending": "Pending",
    "status.approved": "Approved",
    "status.rejected": "Rejected",
    "common.loading": "Loading…",
    "common.retry": "Retry",
    "common.none": "—",
    "dashboard.title": "Dashboard",
    "dashboard.welcome": "Welcome to pguard admin",
    "stub.soon": "This page is coming soon",
  },
} as const;

export type TKey = keyof (typeof dictionaries)["en"];

interface LanguageContextValue {
  lang: Lang;
  setLang: (lang: Lang) => void;
  t: (key: TKey) => string;
}

const LanguageContext = createContext<LanguageContextValue | null>(null);

const LANG_COOKIE = "lang";

/** Provider seeded with the server-read locale (avoids a hydration mismatch). The toggle writes a
 *  non-sensitive `lang` cookie (locale isn't a secret) so the server renders the same locale next
 *  load. */
export function LanguageProvider({
  initialLang,
  children,
}: {
  initialLang: Lang;
  children: ReactNode;
}) {
  const [lang, setLangState] = useState<Lang>(initialLang);

  const setLang = useCallback((next: Lang) => {
    setLangState(next);
    // 1 year; Lax; Secure; path=/. Not httpOnly — the locale is non-sensitive and read on both
    // ends. Secure per CLAUDE.md cookie rule (browsers tolerate Secure on http://localhost).
    document.cookie = `${LANG_COOKIE}=${next}; path=/; max-age=31536000; SameSite=Lax; Secure`;
  }, []);

  const value = useMemo<LanguageContextValue>(
    () => ({
      lang,
      setLang,
      t: (key) => dictionaries[lang][key] ?? key,
    }),
    [lang, setLang],
  );

  return (
    <LanguageContext.Provider value={value}>
      {children}
    </LanguageContext.Provider>
  );
}

export function useLanguage(): LanguageContextValue {
  const ctx = useContext(LanguageContext);
  if (!ctx) {
    throw new Error("useLanguage must be used within a LanguageProvider");
  }
  return ctx;
}

/** Parse a `lang` cookie value into a valid [Lang], defaulting to Thai (the primary market). */
export function parseLang(value: string | undefined): Lang {
  return value === "en" ? "en" : "th";
}

export { LANG_COOKIE };

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
    "common.close": "ปิด",
    "common.all": "ทั้งหมด",
    "common.view": "ดูรายละเอียด",
    "dashboard.title": "แดชบอร์ด",
    "dashboard.welcome": "ยินดีต้อนรับสู่ pguard แอดมิน",
    "stub.soon": "หน้านี้กำลังจะมาเร็วๆ นี้",
    "guards.title": "เจ้าหน้าที่ที่อนุมัติแล้ว",
    "guards.subtitle": "รายชื่อเจ้าหน้าที่ที่ผ่านการอนุมัติให้รับงาน",
    "guards.empty": "ยังไม่มีเจ้าหน้าที่ที่อนุมัติ",
    "guards.error": "โหลดรายชื่อเจ้าหน้าที่ไม่สำเร็จ",
    "guards.col.guard": "เจ้าหน้าที่",
    "guards.col.experience": "ประสบการณ์",
    "guards.col.workplace": "ที่ทำงานเดิม",
    "guards.col.bank": "บัญชีธนาคาร",
    "guards.detail.title": "รายละเอียดเจ้าหน้าที่",
    "guards.detail.gender": "เพศ",
    "guards.detail.dob": "วันเกิด",
    "guards.detail.accountName": "ชื่อบัญชี",
    "guards.detail.accountNumber": "เลขบัญชี",
    "reviews.title": "รีวิว",
    "reviews.subtitle": "ตรวจสอบและจัดการการมองเห็นรีวิว",
    "reviews.stats.total": "รีวิวทั้งหมด",
    "reviews.stats.visible": "แสดงอยู่",
    "reviews.stats.hidden": "ซ่อนอยู่",
    "reviews.stats.average": "คะแนนเฉลี่ย",
    "reviews.filter.rating": "คะแนน",
    "reviews.filter.visibility": "การมองเห็น",
    "reviews.filter.search": "ค้นหาข้อความรีวิว",
    "reviews.ratingAny": "ทุกคะแนน",
    "reviews.visible": "แสดงอยู่",
    "reviews.hidden": "ซ่อนอยู่",
    "reviews.show": "แสดง",
    "reviews.hide": "ซ่อน",
    "reviews.col.guard": "เจ้าหน้าที่",
    "reviews.col.customer": "ลูกค้า",
    "reviews.col.rating": "คะแนน",
    "reviews.col.review": "รีวิว",
    "reviews.col.date": "วันที่",
    "reviews.col.actions": "การจัดการ",
    "reviews.empty": "ไม่พบรีวิว",
    "reviews.error": "ดำเนินการไม่สำเร็จ กรุณาลองใหม่",
    "map.title": "แผนที่เจ้าหน้าที่",
    "map.subtitle": "ตำแหน่งเจ้าหน้าที่แบบเรียลไทม์",
    "map.search": "ค้นหาเจ้าหน้าที่",
    "map.onlineOnly": "ออนไลน์เท่านั้น",
    "map.status.active": "ใช้งานอยู่",
    "map.status.idle": "ไม่เคลื่อนไหว",
    "map.status.offline": "ออฟไลน์",
    "map.empty": "ไม่มีตำแหน่งเจ้าหน้าที่",
    "map.error": "โหลดตำแหน่งไม่สำเร็จ",
    "map.lastSeen": "อัปเดตล่าสุด",
    "map.accuracy": "ความแม่นยำ",
    "map.loadingMap": "กำลังโหลดแผนที่…",
    "gap.title": "ฟีเจอร์นี้ยังไม่พร้อมใช้งาน",
    "gap.note": "หน้านี้ต้องใช้ endpoint ที่ยังไม่มีในสัญญา API ของ v2 จะใช้งานได้เมื่อ backend เพิ่ม endpoint เหล่านี้",
    "gap.endpoints": "Endpoint ที่ต้องการ",
    "gap.customers": "v2 ยังไม่มี endpoint รายชื่อลูกค้าสำหรับแอดมิน (มีเฉพาะโปรไฟล์ของตัวเอง)",
    "gap.pricing": "v2 คำนวณราคาฝั่งเซิร์ฟเวอร์ตอนชำระเงิน — ยังไม่มี catalog เรตราคาให้แอดมินจัดการ",
    "gap.wallet": "v2 คืนเงินอัตโนมัติแบบ event-driven — ไม่มีขั้นตอน refund ที่แอดมินต้องกดดำเนินการ",
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
    "common.close": "Close",
    "common.all": "All",
    "common.view": "View",
    "dashboard.title": "Dashboard",
    "dashboard.welcome": "Welcome to pguard admin",
    "stub.soon": "This page is coming soon",
    "guards.title": "Approved guards",
    "guards.subtitle": "Guards approved to take jobs",
    "guards.empty": "No approved guards yet",
    "guards.error": "Failed to load guards",
    "guards.col.guard": "Guard",
    "guards.col.experience": "Experience",
    "guards.col.workplace": "Previous workplace",
    "guards.col.bank": "Bank account",
    "guards.detail.title": "Guard detail",
    "guards.detail.gender": "Gender",
    "guards.detail.dob": "Date of birth",
    "guards.detail.accountName": "Account name",
    "guards.detail.accountNumber": "Account number",
    "reviews.title": "Reviews",
    "reviews.subtitle": "Moderate review visibility",
    "reviews.stats.total": "Total reviews",
    "reviews.stats.visible": "Visible",
    "reviews.stats.hidden": "Hidden",
    "reviews.stats.average": "Average rating",
    "reviews.filter.rating": "Rating",
    "reviews.filter.visibility": "Visibility",
    "reviews.filter.search": "Search review text",
    "reviews.ratingAny": "Any rating",
    "reviews.visible": "Visible",
    "reviews.hidden": "Hidden",
    "reviews.show": "Show",
    "reviews.hide": "Hide",
    "reviews.col.guard": "Guard",
    "reviews.col.customer": "Customer",
    "reviews.col.rating": "Rating",
    "reviews.col.review": "Review",
    "reviews.col.date": "Date",
    "reviews.col.actions": "Actions",
    "reviews.empty": "No reviews found",
    "reviews.error": "Action failed — please try again",
    "map.title": "Guard map",
    "map.subtitle": "Live guard locations",
    "map.search": "Search guards",
    "map.onlineOnly": "Online only",
    "map.status.active": "Active",
    "map.status.idle": "Idle",
    "map.status.offline": "Offline",
    "map.empty": "No guard locations",
    "map.error": "Failed to load locations",
    "map.lastSeen": "Last seen",
    "map.accuracy": "Accuracy",
    "map.loadingMap": "Loading map…",
    "gap.title": "Not available yet",
    "gap.note": "This page needs an endpoint that is not in the v2 API contract yet. It will work once the backend adds these endpoints.",
    "gap.endpoints": "Required endpoints",
    "gap.customers": "v2 has no admin customer-list endpoint yet (only the self profile).",
    "gap.pricing": "v2 computes price server-side at charge time — there is no admin rate catalog to manage.",
    "gap.wallet": "v2 refunds are automatic (event-driven) — there is no admin refund step to action.",
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

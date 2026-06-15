// Screen-local bilingual copy for the activity (บันทึกการตรวจสอบ) screen — the PDPA §30
// data-access audit log (profile `GET /admin/access-audit`). HONEST SCOPE: this is a
// data-access trail (who read which PII, and when), NOT the design's full business-action feed
// (approved / refund / check-in events with actor name, IP, payload) — that needs a dedicated
// audit-event sink across services (a documented gap).
import type { Lang } from "@/lib/lang";

export interface ActivityCopy {
  title: string;
  subtitle: (n: string) => string;
  searchPlaceholder: string;
  awaitingApi: string;
  scopeNote: string;
  colWhen: string;
  colAdmin: string;
  colAction: string;
  colTarget: string;
  filterAll: string;
  of: string;
  /** Friendly labels for the recorded actions. */
  actionLabel: Record<string, string>;
}

export const COPY: Record<Lang, ActivityCopy> = {
  th: {
    title: "บันทึกการตรวจสอบ",
    subtitle: (n) => `เหตุการณ์การเข้าถึงข้อมูล ${n} รายการ`,
    searchPlaceholder: "ค้นหา action / target / ผู้ใช้…",
    awaitingApi: "รอ API",
    scopeNote:
      "บันทึกการเข้าถึงข้อมูล (PDPA §30) — ใครอ่านข้อมูลส่วนบุคคลเมื่อไร · ยังไม่ใช่ฟีดเหตุการณ์ธุรกิจเต็มรูป (อนุมัติ/คืนเงิน/เช็คอิน + IP) ที่ต้องมี audit-event sink",
    colWhen: "เวลา",
    colAdmin: "แอดมิน",
    colAction: "การกระทำ",
    colTarget: "ขอบเขต",
    filterAll: "ทั้งหมด",
    of: "จาก",
    actionLabel: {
      admin_list_guard_profiles: "ดูรายชื่อเจ้าหน้าที่",
      admin_list_customer_profiles: "ดูรายชื่อลูกค้า",
    },
  },
  en: {
    title: "Activity Log",
    subtitle: (n) => `${n} data-access events`,
    searchPlaceholder: "Search action / target / user…",
    awaitingApi: "awaiting API",
    scopeNote:
      "Data-access audit (PDPA §30) — who read which PII and when · not the full business-action feed (approved/refund/check-in + IP) which needs a dedicated audit-event sink",
    colWhen: "When",
    colAdmin: "Admin",
    colAction: "Action",
    colTarget: "Scope",
    filterAll: "All",
    of: "of",
    actionLabel: {
      admin_list_guard_profiles: "Listed guard profiles",
      admin_list_customer_profiles: "Listed customer profiles",
    },
  },
};

export function actionText(action: string, c: ActivityCopy): string {
  return c.actionLabel[action] ?? action;
}

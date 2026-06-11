// Screen-local bilingual copy for the guards screen — NEW design strings only, taken
// verbatim from the hi-fi mockup (Admin - Guards). Shared strings (table columns, detail
// labels, common.*) keep using src/lib/i18n.tsx keys — that file is single-writer and is
// NOT edited from this screen.
import type { Lang } from "@/lib/lang";

export interface GuardsCopy {
  title: string;
  /** Design subtitle carries the live count: "เจ้าหน้าที่ที่อนุมัติแล้ว 384 คน". */
  subtitle: (n: number) => string;
  kpiOnline: string;
  kpiOnJob: string;
  kpiAvgRating: string;
  kpiDocsExpiring: string;
  chipOnline: string;
  chipOnJob: string;
  chipOffline: string;
  colStatus: string;
  searchPlaceholder: string;
  /** Honest inline gap chip for design data with no v2 endpoint yet. */
  awaitingApi: string;
  statRating: string;
  statJobs: string;
  statExp: string;
  docsHead: string;
  jobHistory: string;
  suspend: string;
  /** Pagination summary connector: "1–8 จาก 384" / "1–8 of 384". */
  of: string;
}

export const COPY: Record<Lang, GuardsCopy> = {
  th: {
    title: "พนักงาน รปภ.",
    subtitle: (n) => `เจ้าหน้าที่ที่อนุมัติแล้ว ${n} คน`,
    kpiOnline: "ออนไลน์ตอนนี้",
    kpiOnJob: "กำลังทำงาน",
    kpiAvgRating: "คะแนนเฉลี่ยทีม",
    kpiDocsExpiring: "เอกสารใกล้หมดอายุ",
    chipOnline: "ออนไลน์",
    chipOnJob: "กำลังทำงาน",
    chipOffline: "ออฟไลน์",
    colStatus: "สถานะ",
    searchPlaceholder: "ค้นหา",
    awaitingApi: "รอ API",
    statRating: "คะแนน",
    statJobs: "งานสำเร็จ",
    statExp: "ประสบการณ์",
    docsHead: "เอกสาร",
    jobHistory: "ดูประวัติงาน",
    suspend: "ระงับบัญชี",
    of: "จาก",
  },
  en: {
    title: "Guards",
    subtitle: (n) => `${n} approved guards`,
    kpiOnline: "Online now",
    kpiOnJob: "On a job",
    kpiAvgRating: "Avg team rating",
    kpiDocsExpiring: "Docs expiring",
    chipOnline: "Online",
    chipOnJob: "On job",
    chipOffline: "Offline",
    colStatus: "Status",
    searchPlaceholder: "Search",
    awaitingApi: "awaiting API",
    statRating: "Rating",
    statJobs: "Jobs",
    statExp: "Exp.",
    docsHead: "Documents",
    jobHistory: "Job history",
    suspend: "Suspend",
    of: "of",
  },
};

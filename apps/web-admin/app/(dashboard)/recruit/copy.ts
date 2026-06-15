// Screen-local bilingual copy for the recruitment (สรรหาบุคลากร) kanban.
// Backed by profile `GET /admin/recruitment/candidates` + `PUT .../{id}/stage`; the final
// approve/reject reuse the existing guard-profile endpoints. The board has 4 REAL columns:
// the 3 pre-approval pipeline stages (pending guards by recruitment_stage) + Approved
// (approval_status). The design's separate "Onboarded" column is an honest gap — v2 has no
// onboarded state distinct from approved. "Add candidate" is a gap too (guards self-register).
// Guard names aren't in v2 → cards show a short id.
import type { Lang } from "@/lib/lang";

/** The 3 pre-approval pipeline stages (profile.recruitment_stage). */
export const STAGES = ["sourcing", "screened", "docs_verified"] as const;
export type Stage = (typeof STAGES)[number];

/** Kanban columns = the 3 stages + the terminal "approved" (from approval_status). */
export const COLUMNS = [...STAGES, "approved"] as const;
export type Column = (typeof COLUMNS)[number];

export interface RecruitCopy {
  title: string;
  subtitle: string;
  inPipeline: (n: number) => string;
  addCandidate: string;
  addGap: string;
  onboardGap: string;
  colLabel: Record<Column, string>;
  experience: (n: number) => string;
  noExperience: string;
  moveTo: string;
  approve: string;
  reject: string;
  working: string;
  yrs: string;
}

export const COPY: Record<Lang, RecruitCopy> = {
  th: {
    title: "สรรหาบุคลากร",
    subtitle: "ไปป์ไลน์ผู้สมัครเจ้าหน้าที่",
    inPipeline: (n) => `ผู้สมัคร ${n} คนในไปป์ไลน์`,
    addCandidate: "เพิ่มผู้สมัคร",
    addGap: "การเพิ่มผู้สมัครเองยังไม่มีใน v2 (เจ้าหน้าที่สมัครเองผ่านแอป)",
    onboardGap: "v2 ไม่มีสถานะ “เริ่มงาน” แยกจาก “อนุมัติ”",
    colLabel: {
      sourcing: "หาแหล่ง",
      screened: "คัดกรองแล้ว",
      docs_verified: "ตรวจเอกสาร",
      approved: "อนุมัติ",
    },
    experience: (n) => `${n} ปี`,
    noExperience: "ไม่ระบุประสบการณ์",
    moveTo: "ย้ายไป",
    approve: "อนุมัติ",
    reject: "ปฏิเสธ",
    working: "กำลังทำ…",
    yrs: "ปี",
  },
  en: {
    title: "Recruitment",
    subtitle: "Guard recruitment pipeline",
    inPipeline: (n) => `${n} candidates in pipeline`,
    addCandidate: "Add candidate",
    addGap: "Adding candidates manually isn't in v2 (guards self-register via the app)",
    onboardGap: 'v2 has no separate "Onboarded" state distinct from "Approved"',
    colLabel: {
      sourcing: "Sourcing",
      screened: "Screened",
      docs_verified: "Docs verified",
      approved: "Approved",
    },
    experience: (n) => `${n} yrs`,
    noExperience: "Experience N/A",
    moveTo: "Move to",
    approve: "Approve",
    reject: "Reject",
    working: "Working…",
    yrs: "yrs",
  },
};

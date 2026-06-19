"use client";

import { useEffect, useState } from "react";
import type { ReactNode } from "react";

import type { components } from "@/api/generated/profile";
import { Avatar, Badge, Button, Modal } from "@/components/ui";
import { bookingApi, ratingApi } from "@/lib/api";
import { ADMIN_LIST_CAP, fmtCappedCount } from "@/lib/format";
import { useLanguage } from "@/lib/i18n";

import { COPY } from "./copy";
import { GuardDocumentsPanel } from "./guard-documents-panel";
import { initialsOf } from "./guard-identity";

type GuardProfile = components["schemas"]["GuardProfile"];

/** Hi-fi drawer `.stat-mini` — sunken box, 11.5px label over a mono value. Page-local
 * (no ui/ primitive for it; ui/ is single-writer). */
function StatMini({ label, value }: { label: ReactNode; value: ReactNode }) {
  return (
    <div className="rounded-md bg-sunken px-3.5 py-[13px]">
      <div className="text-[11.5px] text-muted">{label}</div>
      <div className="mt-1 font-mono text-[19px] font-semibold text-text-strong tabular-nums">
        {value}
      </div>
    </div>
  );
}

/** Guard detail — same data as before (the full admin-scoped profile, incl. the FULL
 * account number the contract returns to admins; the list keeps the masked form),
 * rebuilt on ui/Modal to the hi-fi drawer's content structure. */
export function GuardDetailModal({
  guard,
  onClose,
  onApprove,
  onReject,
  acting = false,
}: {
  guard: GuardProfile;
  onClose: () => void;
  /** When provided (applicant-review context), the footer shows Approve/Reject instead of the
   *  disabled job-history/suspend actions — so a reviewer can decide without re-finding the row. */
  onApprove?: () => void;
  onReject?: () => void;
  acting?: boolean;
}) {
  const { t, lang } = useLanguage();
  const c = COPY[lang];
  const gap = <Badge tone="gray">{c.awaitingApi}</Badge>;
  const reviewable = Boolean(onApprove || onReject);

  // The guard's overall rating aggregate (admins may read any guard's). Null until loaded or when
  // there are no visible reviews — rendered as "—", never a fake 0.0.
  const [rating, setRating] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    ratingApi
      .GET("/guards/{id}/ratings", { params: { path: { id: guard.user_id } } })
      .then(({ data, error }) => {
        if (alive && !error) setRating(data?.data?.average ?? null);
      })
      .catch(() => {
        // Transport failure — leave the rating as "—" (no unhandled rejection).
      });
    return () => {
      alive = false;
    };
  }, [guard.user_id]);

  // Completed-job count for this guard (the "งานสำเร็จ" stat) — admin booking list filtered to
  // this guard + completed. Null until loaded; rendered cap-honest ("200+") since the admin list
  // is repo-capped. A failed call leaves it "—", never a fabricated 0.
  const [jobsDone, setJobsDone] = useState<number | null>(null);
  useEffect(() => {
    let alive = true;
    bookingApi
      .GET("/admin/bookings", {
        params: { query: { guard_id: guard.user_id, status: "completed", limit: ADMIN_LIST_CAP } },
      })
      .then(({ data, error }) => {
        if (alive && !error) setJobsDone(data?.data?.length ?? 0);
      })
      .catch(() => {
        // Transport failure — leave jobs as "—".
      });
    return () => {
      alive = false;
    };
  }, [guard.user_id]);

  const emergency = [guard.emergency_contact_name, guard.emergency_contact_relationship]
    .filter(Boolean)
    .join(" · ");
  const rows: { key: string; label: string; value: string | null | undefined }[] = [
    { key: "gender", label: t("guards.detail.gender"), value: guard.gender },
    { key: "dob", label: t("guards.detail.dob"), value: guard.date_of_birth },
    { key: "workplace", label: t("guards.col.workplace"), value: guard.previous_workplace },
    { key: "address", label: lang === "th" ? "ที่อยู่" : "Address", value: guard.address },
    {
      key: "emergency",
      label: lang === "th" ? "ผู้ติดต่อฉุกเฉิน" : "Emergency contact",
      value: emergency || null,
    },
    {
      key: "emergency_phone",
      label: lang === "th" ? "เบอร์ฉุกเฉิน" : "Emergency phone",
      value: guard.emergency_contact_phone,
    },
  ];

  return (
    <Modal
      open
      onClose={onClose}
      title={t("guards.detail.title")}
      footer={
        reviewable ? (
          // Applicant-review context: decide right here. Same approve/reject the row triggers.
          <>
            {onReject && (
              <Button
                variant="danger-ghost"
                size="sm"
                disabled={acting}
                onClick={onReject}
              >
                {t("applicants.reject")}
              </Button>
            )}
            {onApprove && (
              <Button size="sm" disabled={acting} onClick={onApprove}>
                {t("applicants.approve")}
              </Button>
            )}
          </>
        ) : (
          <>
            {/* Drawer-foot actions from the design — no job-history / suspend endpoints in
                v2 yet, so they stay disabled behind an honest gap chip (never a fake toast). */}
            {gap}
            <Button variant="secondary" size="sm" disabled>
              {c.jobHistory}
            </Button>
            <Button variant="danger-ghost" size="sm" disabled>
              {c.suspend}
            </Button>
          </>
        )
      }
    >
      {/* Drawer head: avatar + name + full id (the list shows the short form only). */}
      <div className="flex items-center gap-3">
        <Avatar size="lg">
          {initialsOf(guard.full_name ?? guard.account_name, guard.user_id)}
        </Avatar>
        <div className="min-w-0">
          <div className="truncate text-lg font-semibold text-text-strong">
            {guard.full_name ?? guard.account_name ?? t("common.none")}
          </div>
          <div className="truncate font-mono text-xs text-muted">{guard.user_id}</div>
        </div>
      </div>

      {/* Stat line — rating + completed-jobs are real (admin reads); experience is real. */}
      <div className="mt-4 grid grid-cols-3 gap-2">
        <StatMini label={`★ ${c.statRating}`} value={rating ?? "—"} />
        <StatMini label={c.statJobs} value={jobsDone == null ? "—" : fmtCappedCount(jobsDone)} />
        <StatMini
          label={c.statExp}
          value={
            guard.years_of_experience != null
              ? `${guard.years_of_experience} ${t("applicants.years")}`
              : t("common.none")
          }
        />
      </div>

      <dl className="mt-4 text-sm">
        {rows.map((r) => (
          <div
            key={r.key}
            className="flex justify-between gap-4 border-b border-border py-2 last:border-0"
          >
            <dt className="text-muted">{r.label}</dt>
            <dd className="text-right text-text-strong">{r.value ?? t("common.none")}</dd>
          </div>
        ))}
      </dl>

      {/* Documents panel — the guard's six credential images (admin reads via the owner-or-admin
          GET; uploads happen on the guard's mobile screen). Honest "not uploaded" until present. */}
      <GuardDocumentsPanel key={guard.user_id} userId={guard.user_id} />

      {/* Bank panel — real data. Admin detail keeps showing the FULL account number the
          contract returns to admins (the at-a-glance list stays masked — PDPA). */}
      <div className="mt-3 rounded-lg border border-border px-4 py-3">
        <div className="text-xs font-semibold uppercase tracking-[0.04em] text-muted">
          {t("guards.col.bank")}
        </div>
        <div className="mt-1.5 text-sm font-semibold text-text-strong">
          {guard.bank_name ?? t("common.none")}
          {guard.account_number ? (
            <span className="font-mono font-medium"> · {guard.account_number}</span>
          ) : null}
        </div>
        <div className="mt-0.5 text-[12.5px] text-muted">
          {t("guards.detail.accountName")}: {guard.account_name ?? t("common.none")}
        </div>
      </div>
    </Modal>
  );
}

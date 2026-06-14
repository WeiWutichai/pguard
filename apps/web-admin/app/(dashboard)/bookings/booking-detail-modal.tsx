"use client";

import { type ReactNode, useState } from "react";
import { AlertTriangle, Loader2 } from "lucide-react";

import type { components as BookingComponents } from "@/api/generated/booking";
import type { components as ProfileComponents } from "@/api/generated/profile";
import { Badge, Button, Modal } from "@/components/ui";
import { bookingApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import {
  type BookingStatusKey,
  bookingTotal,
  COPY,
  fmtBaht,
  STATUS_TONE,
} from "./copy";

type Booking = BookingComponents["schemas"]["Booking"];
type GuardProfile = ProfileComponents["schemas"]["GuardProfile"];

/** Hi-fi drawer `.stat-mini` — sunken box, small label over a mono value. Page-local
 * (ui/ is single-writer; the guards detail modal uses the same shape). */
function StatMini({ label, value }: { label: ReactNode; value: ReactNode }) {
  return (
    <div className="rounded-md bg-sunken px-3.5 py-[13px]">
      <div className="text-[11.5px] text-muted">{label}</div>
      <div className="mt-1 font-mono text-[17px] font-semibold text-text-strong tabular-nums">
        {value}
      </div>
    </div>
  );
}

/** A short, human label for a guard in the picker / assigned line. GuardProfile carries no
 * dedicated name field — `account_name` is the only person name; otherwise the id prefix. */
function guardLabel(g: GuardProfile, yearsUnit: string): string {
  const name = g.account_name?.trim() || `ID #${g.user_id.slice(0, 8)}`;
  const exp = g.years_of_experience != null ? ` · ${g.years_of_experience}${yearsUnit}` : "";
  return `${name}${exp}`;
}

/** Booking detail + (when the booking is an unassigned `requested` job) the admin guard-assign
 * action. Rebuilt on ui/Modal to the hi-fi drawer's content. On a successful assign the parent
 * refetches (the row flips to `accepted` with the guard set) — `onAssigned` owns that. */
export function BookingDetailModal({
  booking,
  customerName,
  approvedGuards,
  onClose,
  onAssigned,
}: {
  booking: Booking;
  customerName: string | null;
  approvedGuards: GuardProfile[];
  onClose: () => void;
  onAssigned: () => void;
}) {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const status = booking.status as BookingStatusKey;
  const assignable = status === "requested" && !booking.guard_id;

  const [guardId, setGuardId] = useState("");
  const [assigning, setAssigning] = useState(false);
  const [failed, setFailed] = useState(false);

  async function assign() {
    if (!guardId) return;
    setAssigning(true);
    setFailed(false);
    const { error } = await bookingApi.POST("/admin/bookings/{id}/assign", {
      params: { path: { id: booking.id } },
      body: { guard_id: guardId },
    });
    if (error) {
      setFailed(true);
      setAssigning(false);
      return;
    }
    // Backend now owns the booking (accepted + guard set, job_accepted emitted) — let the
    // parent refetch the authoritative list and close.
    onAssigned();
  }

  const yearsUnit = lang === "th" ? " ปี" : "y";

  return (
    <Modal
      open
      onClose={onClose}
      size="lg"
      title={c.detailTitle}
      footer={
        assignable ? (
          <Button variant="primary" size="sm" onClick={assign} disabled={!guardId || assigning}>
            {assigning ? <Loader2 className="size-4 animate-spin" /> : null}
            {c.assignConfirm}
          </Button>
        ) : (
          <Button variant="secondary" size="sm" onClick={onClose}>
            {t("common.close")}
          </Button>
        )
      }
    >
      {/* Head: booking id (mono) + status badge. */}
      <div className="flex items-center gap-3">
        <div className="min-w-0">
          <div className="font-mono text-xs text-muted">#{booking.id.slice(0, 8)}</div>
          <div className="mt-0.5 truncate text-lg font-semibold text-text-strong">
            {c.statusLabel[status] ?? status}
          </div>
        </div>
        <Badge tone={STATUS_TONE[status] ?? "gray"} className="ml-auto">
          {c.statusLabel[status] ?? status}
        </Badge>
      </div>

      {/* Stat line — all derived from real booking fields. */}
      <div className="mt-4 grid grid-cols-3 gap-2">
        <StatMini label={c.total} value={fmtBaht(bookingTotal(booking))} />
        <StatMini label={c.duration} value={`${booking.hours}${c.hoursUnit}`} />
        <StatMini
          label={c.guardsCount}
          value={`${booking.guard_count}${c.peopleUnit ? ` ${c.peopleUnit}` : ""}`}
        />
      </div>

      {/* Customer panel — name (admin customer directory) + address (on the booking). Phone is
          identity-owned, not exposed to this page, so it is omitted (no fake value). */}
      <div className="mt-4 rounded-lg border border-border px-4 py-3">
        <div className="text-xs font-semibold uppercase tracking-[0.04em] text-muted">
          {c.customer}
        </div>
        <div className="mt-1.5 text-sm font-semibold text-text-strong">
          {customerName ?? `ID #${booking.customer_id.slice(0, 8)}`}
        </div>
        <div className="mt-0.5 text-[12.5px] text-muted">{booking.address}</div>
      </div>

      {/* Assigned guard panel — or the assign picker when this is an unassigned requested job. */}
      <div className="mt-3 rounded-lg border border-border px-4 py-3">
        <div className="text-xs font-semibold uppercase tracking-[0.04em] text-muted">
          {c.assignedGuard}
        </div>
        {booking.guard_id ? (
          <div className="mt-1.5 font-mono text-sm text-text-strong">
            #{booking.guard_id.slice(0, 8)}
          </div>
        ) : assignable ? (
          <div className="mt-2">
            <p className="mb-2 text-[12.5px] text-muted">{c.noGuardYet}</p>
            <label className="sr-only" htmlFor="assign-guard">
              {c.assignGuardLabel}
            </label>
            <select
              id="assign-guard"
              value={guardId}
              onChange={(e) => setGuardId(e.target.value)}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm text-text-strong focus:border-brand-int focus:outline-none"
            >
              <option value="">{c.assignPick}</option>
              {approvedGuards.map((g) => (
                <option key={g.user_id} value={g.user_id}>
                  {guardLabel(g, yearsUnit)}
                </option>
              ))}
            </select>
            {failed && (
              <div
                role="alert"
                className="mt-2 flex items-center gap-2 rounded-lg border border-danger/40 bg-danger-bg px-3 py-2 text-[12.5px] text-danger"
              >
                <AlertTriangle className="size-4 flex-none" />
                {c.assignError}
              </div>
            )}
          </div>
        ) : (
          <div className="mt-1.5 text-sm text-muted">{c.unassigned}</div>
        )}
      </div>
    </Modal>
  );
}

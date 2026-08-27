"use client";

import { type ReactNode, useEffect, useState } from "react";
import { AlertTriangle, Loader2 } from "lucide-react";

import type { components as BookingComponents } from "@/api/generated/booking";
import type { components as ProfileComponents } from "@/api/generated/profile";
import type { components as PaymentComponents } from "@/api/generated/payment";
import { Badge, Button, Modal } from "@/components/ui";
import { bookingApi, paymentApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import {
  type BookingStatusKey,
  cancellationOf,
  COPY,
  fmtBaht,
  isCancelledStatus,
  moneyView,
  reasonText,
  STATUS_TONE,
} from "./copy";

type Booking = BookingComponents["schemas"]["Booking"];
type GuardProfile = ProfileComponents["schemas"]["GuardProfile"];
type Payment = PaymentComponents["schemas"]["Payment"];

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
  customerPhone,
  guardName,
  approvedGuards,
  onClose,
  onAssigned,
}: {
  booking: Booking;
  customerName: string | null;
  /** Optional — the bookings page enriches it from the customer directory; other callers omit it. */
  customerPhone?: string | null;
  /** Optional — the bookings page resolves the assigned guard's name; other callers omit it. */
  guardName?: string | null;
  approvedGuards: GuardProfile[];
  onClose: () => void;
  onAssigned: () => void;
}) {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const status = booking.status as BookingStatusKey;
  const assignable = status === "requested" && !booking.guard_id;
  // Why the job ended — only meaningful on the two terminal-bad statuses. The reason is a wire
  // CODE; `reasonText` localizes it (unknown codes show raw, see copy.ts).
  const cancellation = isCancelledStatus(status) ? cancellationOf(booking) : null;

  const [guardId, setGuardId] = useState("");
  const [assigning, setAssigning] = useState(false);
  const [failed, setFailed] = useState(false);

  // Real charged amount: the payment service reconciles ACTUAL hours + refunds, so the booked-hours
  // estimate on the booking row is NOT what was charged. Fetch this booking's payment row (the admin
  // ledger has no booking_id filter → scope to the customer, then match booking_id) and show the
  // reconciled figure + any refund. Falls back to the estimate (clearly labelled) if unavailable.
  // The result is TAGGED with its booking id so a prop change to a new booking shows the estimate
  // (not the previous booking's money) until the new fetch lands — no reset-setState in the effect.
  const [paidRow, setPaidRow] = useState<{ bookingId: string; payment: Payment | null } | null>(null);
  useEffect(() => {
    let alive = true;
    void paymentApi
      .GET("/admin/payments", { params: { query: { customer_id: booking.customer_id } } })
      .then((res) => {
        if (!alive) return;
        const match = (res.data?.data ?? []).find((p) => p.booking_id === booking.id) ?? null;
        setPaidRow({ bookingId: booking.id, payment: match });
      })
      .catch(() => {
        /* ledger read failed → keep the labelled estimate */
      });
    return () => {
      alive = false;
    };
  }, [booking.id, booking.customer_id]);

  const payment = paidRow?.bookingId === booking.id ? paidRow.payment : null;
  const money = moneyView(booking, payment);

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

      {/* Stat line. "Total" shows the RECONCILED charge from the payment row (VAT-inclusive, actual
          hours, net of refund/cancel) — or the booked estimate, clearly labelled, when no payment
          row is available. */}
      <div className="mt-4 grid grid-cols-3 gap-2">
        <StatMini label={money.isEstimate ? c.totalEst : c.total} value={fmtBaht(money.total)} />
        <StatMini label={c.duration} value={`${booking.hours}${c.hoursUnit}`} />
        <StatMini
          label={c.guardsCount}
          value={`${booking.guard_count}${c.peopleUnit ? ` ${c.peopleUnit}` : ""}`}
        />
      </div>

      {/* Refund line — only when the customer actually got money back (overpay on an early finish, or
          the refund on a cancel/decline). The first thing a refund dispute checks next to the reason. */}
      {money.refunded > 0 && (
        <div className="mt-2 flex items-center justify-between rounded-md bg-sunken px-3.5 py-2 text-[12.5px]">
          <span className="text-muted">{c.refunded}</span>
          <span className="font-mono font-semibold tabular-nums text-text-strong">
            {fmtBaht(money.refunded)}
          </span>
        </div>
      )}

      {/* Why it ended — cancelled/declined only. Sits above the parties because on a terminal
          booking it is the first thing an admin (or a refund dispute) needs. */}
      {cancellation && (
        <div className="mt-4 rounded-lg border border-danger/40 px-4 py-3">
          <div className="text-xs font-semibold uppercase tracking-[0.04em] text-danger">
            {status === "declined" ? c.declineReason : c.cancelReason}
          </div>
          {cancellation.reason ? (
            <div
              className="mt-1.5 text-sm font-semibold text-text-strong"
              title={cancellation.reason}
            >
              {reasonText(cancellation.reason, c)}
            </div>
          ) : (
            <div className="mt-1.5 text-sm text-muted">{c.cancellationNone}</div>
          )}
          {cancellation.note && (
            <div className="mt-2">
              <div className="text-[11.5px] text-muted">{c.cancellationNote}</div>
              <p className="mt-0.5 whitespace-pre-wrap break-words text-[12.5px] text-text-strong">
                {cancellation.note}
              </p>
            </div>
          )}
        </div>
      )}

      {/* Customer panel — name + phone (admin customer directory) + the booking address. */}
      <div className="mt-4 rounded-lg border border-border px-4 py-3">
        <div className="text-xs font-semibold uppercase tracking-[0.04em] text-muted">
          {c.customer}
        </div>
        <div className="mt-1.5 text-sm font-semibold text-text-strong">
          {customerName ?? `ID #${booking.customer_id.slice(0, 8)}`}
        </div>
        {customerPhone && (
          <div className="mt-0.5 font-mono text-[12.5px] text-muted">{customerPhone}</div>
        )}
        <div className="mt-0.5 text-[12.5px] text-muted">{booking.address}</div>
      </div>

      {/* Assigned guard panel — or the assign picker when this is an unassigned requested job. */}
      <div className="mt-3 rounded-lg border border-border px-4 py-3">
        <div className="text-xs font-semibold uppercase tracking-[0.04em] text-muted">
          {c.assignedGuard}
        </div>
        {booking.guard_id ? (
          guardName ? (
            <div className="mt-1.5 text-sm font-semibold text-text-strong" title={booking.guard_id}>
              {guardName}
            </div>
          ) : (
            <div
              className="mt-1.5 font-mono text-sm text-text-strong"
              title={booking.guard_id}
            >
              #{booking.guard_id.slice(0, 8)}
            </div>
          )
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

"use client";

import { type ReactNode } from "react";
import { CheckCircle2, Clock } from "lucide-react";

import type { components } from "@/api/generated/profile";
import { Avatar, Badge, Button, Modal } from "@/components/ui";
import { useLanguage } from "@/lib/i18n";

import { COPY, customerInitials, fmtSignup } from "./copy";

type CustomerProfileAdmin = components["schemas"]["CustomerProfileAdmin"];

/** Hi-fi drawer `.stat-mini` — sunken box, small label over a value (shared shape with the
 * guards/bookings detail modals; ui/ is single-writer so it stays page-local). */
function StatMini({ label, value }: { label: ReactNode; value: ReactNode }) {
  return (
    <div className="rounded-md bg-sunken px-3.5 py-[13px]">
      <div className="text-[11.5px] text-muted">{label}</div>
      <div className="mt-1 text-[15px] font-semibold text-text-strong">{value}</div>
    </div>
  );
}

/** Customer detail. Real data: name, address, signup date (created_at). The design's spend /
 * booking-count / quality / payment-method and the approved-date all need cross-service
 * aggregates or identity data this page doesn't have — honest gap chips, never fabricated. */
export function CustomerDetailModal({
  customer,
  onClose,
}: {
  customer: CustomerProfileAdmin;
  onClose: () => void;
}) {
  const { t, lang } = useLanguage();
  const c = COPY[lang];
  const gap = <Badge tone="gray">{c.awaitingApi}</Badge>;

  return (
    <Modal
      open
      onClose={onClose}
      title={c.detailTitle}
      footer={
        <>
          {/* Booking-history + suspend have no v2 endpoint — disabled behind an honest gap. */}
          {gap}
          <Button variant="secondary" size="sm" disabled>
            {c.bookingHistory}
          </Button>
          <Button variant="danger-ghost" size="sm" disabled>
            {c.suspend}
          </Button>
        </>
      }
    >
      {/* Head: avatar + name + full id. */}
      <div className="flex items-center gap-3">
        <Avatar size="lg">{customerInitials(customer.full_name, customer.user_id)}</Avatar>
        <div className="min-w-0">
          <div className="truncate text-lg font-semibold text-text-strong">
            {customer.full_name ?? t("common.none")}
          </div>
          <div className="truncate font-mono text-xs text-muted">{customer.user_id}</div>
        </div>
      </div>

      {/* Stat line — bookings + spend need booking/payment aggregates (gap). */}
      <div className="mt-4 grid grid-cols-2 gap-2">
        <StatMini label={c.bookings} value={gap} />
        <StatMini label={c.spend} value={gap} />
      </div>

      {/* Account — address is real; quality is a derived label with no field (gap). */}
      <div className="mt-4 rounded-lg border border-border px-4 py-3">
        <div className="text-xs font-semibold uppercase tracking-[0.04em] text-muted">
          {c.account}
        </div>
        <dl className="mt-2 text-sm">
          <div className="flex items-start justify-between gap-4 border-b border-border py-2">
            <dt className="text-muted">{c.address}</dt>
            <dd className="max-w-[230px] text-right text-text-strong">
              {customer.address ?? t("common.none")}
            </dd>
          </div>
          <div className="flex items-center justify-between gap-4 py-2">
            <dt className="text-muted">{c.quality}</dt>
            <dd>{gap}</dd>
          </div>
        </dl>
      </div>

      {/* Payment method — no payment data is exposed to this page (gap). */}
      <div className="mt-3 rounded-lg border border-border px-4 py-3">
        <div className="text-xs font-semibold uppercase tracking-[0.04em] text-muted">
          {c.payment}
        </div>
        <div className="mt-2">{gap}</div>
      </div>

      {/* Approval timeline — signup (created_at) is real; the approved date lives in identity
          (not profile), so it stays a gap. */}
      <div className="mt-3 rounded-lg border border-border px-4 py-3">
        <div className="text-xs font-semibold uppercase tracking-[0.04em] text-muted">
          {c.approvalStatus}
        </div>
        <div className="mt-2 flex items-center gap-3 py-1.5 text-sm">
          <CheckCircle2 className="size-5 flex-none text-success" />
          <span className="font-semibold text-text-strong">{c.approved}</span>
          {gap}
        </div>
        <div className="flex items-center gap-3 py-1.5 text-sm text-muted">
          <Clock className="size-5 flex-none" />
          {c.signedUp} · {fmtSignup(customer.created_at, lang)}
        </div>
      </div>
    </Modal>
  );
}

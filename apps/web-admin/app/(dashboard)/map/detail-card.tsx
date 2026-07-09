"use client";

// Design §6 "Detail card overlay" — bottom-left card shown when a guard is selected:
// header (avatar · id · GPS badge · close), 3-col stats grid, current-job strip, actions.
// Real data: presence (id, online/accuracy, last update), the guard's overall rating, the
// completed-job count, and the current active job (admin booking list filtered by guard_id).
// Only km-away (needs a distance calc) and the chat/call actions (no v2 admin channel) remain
// honest "รอ API / Awaiting API" gaps.
import { useEffect, useMemo, useState } from "react";
import { CheckCircle2, MessageSquare, Navigation, Phone, Shield, X } from "lucide-react";

import type { components } from "@/api/generated/booking";
import type { MapGuard } from "@/components/guard-map";
import { Badge, Button } from "@/components/ui";
import { bookingApi, ratingApi } from "@/lib/api";
import { ADMIN_LIST_CAP, fmtCappedCount } from "@/lib/format";
import { useLanguage } from "@/lib/i18n";
import { useNameResolver } from "@/lib/use-names";
import { cn } from "@/lib/cn";
import {
  ACTIVE_BOOKING_STATUSES,
  ACTIVE_STATUS_TONE,
  type ActiveBookingStatus,
  COPY,
  formatAgoShort,
  initials,
  shortId,
} from "./copy";

type Booking = components["schemas"]["Booking"];

export function DetailCard({ guard, onClose }: { guard: MapGuard; onClose: () => void }) {
  const { t, lang } = useLanguage();
  const c = COPY[lang];
  // Resolve the selected guard's id to a real display name (header showed a raw UUID slice).
  const ids = useMemo(() => [guard.guard_id], [guard.guard_id]);
  const { resolve } = useNameResolver(ids, lang);
  const name = resolve(guard.guard_id).name;

  // The selected guard's overall rating (admin-readable). Re-fetched per selection; "—" until
  // loaded or when the guard has no visible reviews (never a fake 0.0).
  const [rating, setRating] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    ratingApi
      .GET("/guards/{id}/ratings", { params: { path: { id: guard.guard_id } } })
      .then(({ data, error }) => {
        if (alive) setRating(!error ? (data?.data?.average ?? null) : null);
      })
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, [guard.guard_id]);

  // The guard's completed-job count (cap-honest "200+") — separate accurate query, so it isn't
  // undercounted by the current-job window below. "—" until loaded / on failure.
  const [jobsDone, setJobsDone] = useState<number | null>(null);
  useEffect(() => {
    let alive = true;
    bookingApi
      .GET("/admin/bookings", {
        params: { query: { guard_id: guard.guard_id, status: "completed", limit: ADMIN_LIST_CAP } },
      })
      .then(({ data, error }) => {
        if (alive && !error) setJobsDone(data?.data?.length ?? 0);
      })
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, [guard.guard_id]);

  // The guard's current active (assigned, non-terminal) job, if any. `undefined` = loading OR
  // not-yet-known (a failed fetch stays here → the strip shows a NEUTRAL label, never the
  // affirmative "no active job"); `null` = a SUCCESSFUL fetch that found none; else the booking.
  // The admin list is `created_at DESC`, and a job's `created_at` is its CREATION time (a
  // future-scheduled job accepted now sorts old) — so we scan the full repo-capped window rather
  // than a small slice, otherwise a high-volume guard's active job could be buried and missed.
  const [currentJob, setCurrentJob] = useState<Booking | null | undefined>(undefined);
  useEffect(() => {
    let alive = true;
    bookingApi
      .GET("/admin/bookings", {
        params: { query: { guard_id: guard.guard_id, limit: ADMIN_LIST_CAP } },
      })
      .then(({ data, error }) => {
        // Only commit on success — on error leave it `undefined` (neutral), mirroring how the
        // rating/jobs stats degrade to "—" instead of asserting an unverified fact.
        if (!alive || error) return;
        const active = (data?.data ?? []).find((b) =>
          (ACTIVE_BOOKING_STATUSES as readonly string[]).includes(b.status),
        );
        setCurrentJob(active ?? null);
      })
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, [guard.guard_id]);

  return (
    <div className="absolute bottom-4 left-4 z-[1100] w-[330px] overflow-hidden rounded-lg border border-border bg-surface shadow-xl">
      {/* Header (design `.dh`). */}
      <div className="flex items-start gap-[13px] p-4">
        <span className="flex size-[54px] flex-none items-center justify-center rounded-[14px] bg-green-100 font-latin text-[19px] font-semibold text-green-800 dark:bg-green-800 dark:text-green-100">
          {initials(name ?? guard.guard_id)}
        </span>
        <div className="min-w-0 flex-1">
          <div
            className={cn(
              "text-[17px] font-semibold leading-tight text-text-strong",
              name ? "" : "font-mono",
            )}
          >
            {name ?? shortId(guard.guard_id)}
          </div>
          <div className="mt-px truncate font-mono text-[11px] text-muted" title={guard.guard_id}>
            {c.idLabel(guard.guard_id)}
          </div>
          <div className="mt-1.5">
            {guard.is_online && guard.accuracy != null ? (
              <Badge tone="green">
                <Navigation className="size-[11px]" />
                {c.gpsAccurate(Math.round(guard.accuracy))}
              </Badge>
            ) : !guard.is_online ? (
              <Badge tone="red">
                <Navigation className="size-[11px]" />
                {c.gpsNoSignal}
              </Badge>
            ) : null}
          </div>
        </div>
        <button
          type="button"
          aria-label={t("common.close")}
          onClick={onClose}
          className="-m-1 flex-none cursor-pointer p-1 text-faint transition-colors hover:text-text"
        >
          <X className="size-[18px]" />
        </button>
      </div>

      {/* Stats grid (design `.stats`) — rating + jobs-done are real (admin reads); km-away still
          needs a distance calc, so it keeps its honest gap chip. */}
      <div className="grid grid-cols-3 border-t border-border">
        <div className="border-r border-border p-3 text-center">
          <div className="text-[15px] font-semibold text-text-strong tabular-nums">
            {rating == null ? "—" : `★ ${rating}`}
          </div>
          <div className="mt-1 text-[10.5px] text-muted">{c.statRating}</div>
        </div>
        <div className="border-r border-border p-3 text-center">
          <div className="text-[15px] font-semibold text-text-strong tabular-nums">
            {jobsDone == null ? "—" : fmtCappedCount(jobsDone)}
          </div>
          <div className="mt-1 text-[10.5px] text-muted">{c.statJobs}</div>
        </div>
        <div className="p-3 text-center">
          <Badge tone="gray">{c.awaitingApi}</Badge>
          <div className="mt-1 text-[10.5px] text-muted">{c.statKm}</div>
        </div>
      </div>

      {/* Current-job strip (design `.job`) — the guard's active assignment from the admin booking
          list, or an honest "no active job" with the last-seen time when none is in flight. The
          icon follows the mockup's two-tone affordance: amber shield on a job (or while loading),
          green check for a confirmed-idle guard. */}
      <div className="flex items-center gap-2.5 bg-sunken px-4 py-[13px]">
        {currentJob === null ? (
          <span className="flex size-[34px] flex-none items-center justify-center rounded-[9px] bg-success-bg text-success">
            <CheckCircle2 className="size-4" />
          </span>
        ) : (
          <span className="flex size-[34px] flex-none items-center justify-center rounded-[9px] bg-warning-bg text-amber-600 dark:text-amber-300">
            <Shield className="size-4" />
          </span>
        )}
        <div className="min-w-0">
          {currentJob ? (
            <>
              <div className="flex items-center gap-2 text-[13px] font-semibold text-text-strong">
                {c.currentJob}
                <Badge tone={ACTIVE_STATUS_TONE[currentJob.status as ActiveBookingStatus]}>
                  {c.jobStatus[currentJob.status as ActiveBookingStatus] ?? currentJob.status}
                </Badge>
              </div>
              <div
                className="mt-0.5 truncate text-[11.5px] text-muted"
                title={currentJob.address}
              >
                #{currentJob.id.slice(0, 8)} · {currentJob.address}
              </div>
            </>
          ) : (
            <>
              <div className="text-[13px] font-semibold text-text-strong">
                {currentJob === undefined ? c.currentJob : c.noCurrentJob}
              </div>
              <div className="mt-0.5 text-[11.5px] text-muted">
                {t("map.lastSeen")} {formatAgoShort(guard.recorded_at, c)}
              </div>
            </>
          )}
        </div>
      </div>

      {/* Actions (design `.acts`) — admin chat/call channels don't exist in v2 yet. */}
      <div className="flex items-center gap-2 px-4 py-[13px]">
        <Button variant="secondary" size="sm" disabled title={c.awaitingApi}>
          <MessageSquare className="size-4" />
          {c.chat}
        </Button>
        <Button variant="primary" size="sm" disabled title={c.awaitingApi} className="flex-[1.3]">
          <Phone className="size-4" />
          {c.call}
        </Button>
      </div>
    </div>
  );
}

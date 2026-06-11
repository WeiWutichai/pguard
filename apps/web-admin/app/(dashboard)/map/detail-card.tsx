"use client";

// Design §6 "Detail card overlay" — bottom-left card shown when a guard is selected:
// header (avatar · id · GPS badge · close), 3-col stats grid, current-job strip, actions.
// Real data here is presence only (id, online/accuracy, last update). The design's rating /
// jobs-done / km-away stats, current-job feed and chat/call actions have no v2 admin
// endpoints — those slots carry honest "รอ API / Awaiting API" gap chips + disabled buttons.
import { MessageSquare, Navigation, Phone, Shield, X } from "lucide-react";

import type { MapGuard } from "@/components/guard-map";
import { Badge, Button } from "@/components/ui";
import { useLanguage } from "@/lib/i18n";
import { COPY, formatAgoShort, initials, shortId } from "./copy";

export function DetailCard({ guard, onClose }: { guard: MapGuard; onClose: () => void }) {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  return (
    <div className="absolute bottom-4 left-4 z-[1100] w-[330px] overflow-hidden rounded-lg border border-border bg-surface shadow-xl">
      {/* Header (design `.dh`). */}
      <div className="flex items-start gap-[13px] p-4">
        <span className="flex size-[54px] flex-none items-center justify-center rounded-[14px] bg-green-100 font-latin text-[19px] font-semibold text-green-800 dark:bg-green-800 dark:text-green-100">
          {initials(guard.guard_id)}
        </span>
        <div className="min-w-0 flex-1">
          <div className="font-mono text-[17px] font-semibold leading-tight text-text-strong">
            {shortId(guard.guard_id)}
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

      {/* Stats grid (design `.stats`) — rating / jobs done / km away have no v2 endpoint yet. */}
      <div className="grid grid-cols-3 border-t border-border">
        {[c.statRating, c.statJobs, c.statKm].map((label) => (
          <div key={label} className="border-r border-border p-3 text-center last:border-r-0">
            <Badge tone="gray">{c.awaitingApi}</Badge>
            <div className="mt-1 text-[10.5px] text-muted">{label}</div>
          </div>
        ))}
      </div>

      {/* Current-job strip (design `.job`) — booking-per-guard data isn't exposed yet. */}
      <div className="flex items-center gap-2.5 bg-sunken px-4 py-[13px]">
        <span className="flex size-[34px] flex-none items-center justify-center rounded-[9px] bg-warning-bg text-amber-600 dark:text-amber-300">
          <Shield className="size-4" />
        </span>
        <div className="min-w-0">
          <div className="flex items-center gap-2 text-[13px] font-semibold text-text-strong">
            {c.currentJob}
            <Badge tone="gray">{c.awaitingApi}</Badge>
          </div>
          <div className="mt-0.5 text-[11.5px] text-muted">
            {t("map.lastSeen")} {formatAgoShort(guard.recorded_at, c)}
          </div>
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

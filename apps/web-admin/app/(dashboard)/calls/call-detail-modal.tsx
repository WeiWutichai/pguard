"use client";

import { useEffect, useMemo, useState } from "react";
import { AlertTriangle, Loader2, Radio } from "lucide-react";

import type { components as CallingComponents } from "@/api/generated/calling";
import { Badge, Modal } from "@/components/ui";
import { callingApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import type { Lang } from "@/lib/lang";
import { useNameResolver } from "@/lib/use-names";

import {
  CALL_TONE,
  type CallEventTypeKey,
  type CallsCopy,
  COPY,
  EVENT_TONE,
  fmtDuration,
  fmtEventDetail,
} from "./copy";

type Call = CallingComponents["schemas"]["Call"];
type CallTimeline = CallingComponents["schemas"]["CallTimeline"];
type CallEvent = CallingComponents["schemas"]["CallEvent"];

/** Per-call DETAIL view (#135). Opened by clicking a call row — fetches the call-events read model
 * (`GET /admin/calls/{id}/events`) and renders the lifecycle + signaling TIMELINE chronologically.
 * The list-row `Call` is passed in for an instant header (the endpoint also returns it fresh).
 * Media QUALITY is intentionally absent (a relay can't observe RTP stats) → shown as an honest
 * note, never fabricated. Names resolve via the shared useNameResolver. */
export function CallDetailModal({ call, onClose }: { call: Call; onClose: () => void }) {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [timeline, setTimeline] = useState<CallTimeline | null>(null);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);

  // The modal mounts fresh per selected call, so initial state (loading=true) already covers the
  // fetch start — no synchronous reset needed (and the lint forbids setState in the effect body).
  useEffect(() => {
    let alive = true;
    callingApi
      .GET("/admin/calls/{id}/events", { params: { path: { id: call.id } } })
      .then(({ data, error }) => {
        if (!alive) return;
        setFailed(Boolean(error));
        setTimeline(error ? null : (data?.data ?? null));
        setLoading(false);
      })
      .catch(() => {
        if (!alive) return;
        setFailed(true);
        setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, [call.id]);

  // The header always has the list-row call; the events feed actor names + both participants.
  const { resolve } = useNameResolver([call.caller_id, call.callee_id], lang);
  const events = useMemo(() => timeline?.events ?? [], [timeline]);
  const status = call.status as keyof typeof CALL_TONE;

  return (
    <Modal open onClose={onClose} size="lg" title={c.detailTitle}>
      <div className="mb-4 flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="font-mono text-xs text-muted">#{call.id.slice(0, 8)}</div>
          <div className="mt-1 flex flex-wrap items-center gap-2 text-sm">
            <Badge tone="gray">{call.call_type === "video" ? c.typeVideo : c.typeAudio}</Badge>
            <Badge tone={CALL_TONE[status] ?? "gray"}>{c.statusLabel[status] ?? call.status}</Badge>
            <span className="font-mono tabular-nums text-muted">{fmtDuration(call.duration_seconds)}</span>
          </div>
        </div>
        <div className="text-right text-[12px] text-muted">
          <div className="font-mono">{call.booking_id.slice(0, 8)}</div>
          <div className="text-[11px]">{c.detailBooking}</div>
        </div>
      </div>

      <div className="mb-4 grid grid-cols-2 gap-3">
        <Participant label={c.detailCaller} id={call.caller_id} name={resolve(call.caller_id).label} />
        <Participant label={c.detailCallee} id={call.callee_id} name={resolve(call.callee_id).label} />
      </div>

      {/* Media-quality honest gap — the relay cannot observe RTP/jitter/loss/MOS (needs SFU/TURN). */}
      <div className="mb-4 flex items-start gap-2 rounded-lg border border-border bg-sunken px-3.5 py-2.5 text-[12px] text-muted">
        <Radio className="mt-px size-4 flex-none" />
        <span>{c.qualityGap}</span>
      </div>

      <div className="mb-2 flex items-center justify-between">
        <h4 className="text-sm font-semibold text-text-strong">{c.timelineHead}</h4>
        {timeline != null && events.length > 0 && (
          <span className="text-[12px] text-muted">{events.length}</span>
        )}
      </div>

      {loading ? (
        <div className="flex items-center justify-center gap-2 py-10 text-muted">
          <Loader2 className="size-5 animate-spin" />
          {c.loadingTimeline}
        </div>
      ) : failed ? (
        <div
          role="alert"
          className="flex items-center gap-2 rounded-lg border border-danger/40 bg-danger-bg px-3 py-2 text-[12.5px] text-danger"
        >
          <AlertTriangle className="size-4 flex-none" />
          {c.timelineError}
        </div>
      ) : events.length === 0 ? (
        <div className="py-8 text-center text-sm text-muted">{c.noEvents}</div>
      ) : (
        <ol className="relative flex flex-col gap-3 border-l border-border pl-4">
          {events.map((ev) => (
            <TimelineRow key={ev.id} event={ev} c={c} lang={lang} />
          ))}
        </ol>
      )}

      <p className="mt-3 text-[11px] text-faint">{c.signalCaption}</p>

      <div className="mt-4 flex justify-end">
        <button
          type="button"
          onClick={onClose}
          className="rounded-md border border-border-strong bg-surface px-3 py-[7px] text-[13px] font-semibold text-text-strong hover:bg-sunken"
        >
          {t("common.close")}
        </button>
      </div>
    </Modal>
  );
}

function Participant({ label, id, name }: { label: string; id: string; name: string }) {
  return (
    <div className="rounded-lg border border-border bg-surface px-3 py-2">
      <div className="text-[11px] text-muted">{label}</div>
      <div className="mt-0.5 truncate text-[13px] font-semibold text-text-strong" title={id}>
        {name}
      </div>
    </div>
  );
}

/** One timeline step — a dot on the rail + the localized event label, time, and any small detail. */
function TimelineRow({ event, c, lang }: { event: CallEvent; c: CallsCopy; lang: Lang }) {
  const type = event.event_type as CallEventTypeKey;
  const tone = EVENT_TONE[type] ?? "gray";
  const detail = fmtEventDetail(event.detail);
  return (
    <li className="relative">
      <span
        className="absolute -left-[21px] top-1 size-2.5 rounded-full ring-2 ring-surface"
        style={{ background: TONE_DOT[tone] }}
      />
      <div className="flex items-center gap-2">
        <Badge tone={tone}>{c.eventLabel[type] ?? type}</Badge>
        <span className="font-mono text-[11.5px] tabular-nums text-muted">
          {new Date(event.occurred_at).toLocaleString(lang === "th" ? "th-TH" : "en-GB", {
            month: "short",
            day: "numeric",
            hour: "2-digit",
            minute: "2-digit",
            second: "2-digit",
          })}
        </span>
        {detail && <span className="text-[11.5px] text-muted">· {detail}</span>}
      </div>
    </li>
  );
}

/** Token-backed dot color per tone (timeline rail markers). */
const TONE_DOT: Record<"green" | "amber" | "red" | "blue" | "gray", string> = {
  green: "var(--success, #16a34a)",
  amber: "var(--amber-400, #f0b429)",
  red: "var(--danger, #dc2626)",
  blue: "var(--info, #2563eb)",
  gray: "var(--border-strong, #94a3b8)",
};

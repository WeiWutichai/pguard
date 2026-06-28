"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import dynamic from "next/dynamic";
import { AlertTriangle, Clock, Info, Loader2, Pause, Play } from "lucide-react";

import type { components as PresenceComponents } from "@/api/generated/presence";
import type { components as ProfileComponents } from "@/api/generated/profile";
import type { ReplayPoint } from "@/components/replay-map";
import { Badge, Button, Chip, Field, Input, PageIntro, Panel } from "@/components/ui";
import { presenceApi, profileApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import { COPY } from "./copy";

type HistoryPoint = PresenceComponents["schemas"]["HistoryPoint"];
type TrackReplay = PresenceComponents["schemas"]["TrackReplay"];
type GuardProfile = ProfileComponents["schemas"]["GuardProfile"];

// Leaflet route map — client-only (ssr:false); `import type ReplayPoint` above is erased so
// leaflet stays out of the server bundle.
const ReplayMap = dynamic(() => import("@/components/replay-map"), {
  ssr: false,
  loading: () => (
    <div className="flex h-full items-center justify-center text-muted">
      <Loader2 className="size-5 animate-spin" />
    </div>
  ),
});

const HISTORY_LIMIT = 1000; // hard cap of the replay endpoint.
const TICK_MS = 600;

type Mode = "guard" | "job";

export default function ReplayPage() {
  const { lang } = useLanguage();
  const c = COPY[lang];

  const [mode, setMode] = useState<Mode>("guard");

  // by-guard selectors
  const [guards, setGuards] = useState<GuardProfile[]>([]);
  const [guardId, setGuardId] = useState("");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");

  // by-job selector
  const [bookingId, setBookingId] = useState("");

  // result
  const [track, setTrack] = useState<TrackReplay | null>(null);
  const [points, setPoints] = useState<HistoryPoint[]>([]);
  const [loadingHistory, setLoadingHistory] = useState(false);
  const [hasError, setHasError] = useState(false);
  const [notFound, setNotFound] = useState(false);
  const [hasLoaded, setHasLoaded] = useState(false);
  const [index, setIndex] = useState(0);
  const [playing, setPlaying] = useState(false);

  // Approved guards for the by-guard picker.
  useEffect(() => {
    let alive = true;
    profileApi
      .GET("/admin/guard-profiles", { params: { query: { approval_status: "approved" } } })
      .then(({ data }) => {
        if (alive) setGuards(data?.data ?? []);
      });
    return () => {
      alive = false;
    };
  }, []);

  const load = useCallback(
    (query: { booking_id?: string; guard_id?: string; from?: string; to?: string }) => {
      setLoadingHistory(true);
      setHasError(false);
      setNotFound(false);
      setPlaying(false);
      setIndex(0);
      setHasLoaded(true);
      presenceApi
        .GET("/admin/track/replay", {
          params: { query: { ...query, limit: HISTORY_LIMIT } },
        })
        .then(({ data, error, response }) => {
          if (error || !data?.data) {
            setNotFound(response?.status === 404);
            setHasError(response?.status !== 404);
            setTrack(null);
            setPoints([]);
            setLoadingHistory(false);
            return;
          }
          // The endpoint returns OLDEST-first already — exactly the replay order.
          setTrack(data.data);
          setPoints(data.data.points ?? []);
          setLoadingHistory(false);
        })
        .catch(() => {
          setHasError(true);
          setTrack(null);
          setPoints([]);
          setLoadingHistory(false);
        });
    },
    [],
  );

  function loadByGuard(id: string) {
    if (!id) return;
    // datetime-local → RFC3339 (optional; blank means the endpoint's default 24h window).
    const fromIso = from ? new Date(from).toISOString() : undefined;
    const toIso = to ? new Date(to).toISOString() : undefined;
    load({ guard_id: id, from: fromIso, to: toIso });
  }

  function loadByJob() {
    const id = bookingId.trim();
    if (!id) return;
    load({ booking_id: id });
  }

  function switchMode(next: Mode) {
    setMode(next);
    setTrack(null);
    setPoints([]);
    setHasLoaded(false);
    setHasError(false);
    setNotFound(false);
    setIndex(0);
    setPlaying(false);
  }

  // Playback ticker — advances the scrubber, stops at the end.
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);
  useEffect(() => {
    if (!playing) return;
    timer.current = setInterval(() => {
      setIndex((i) => {
        if (i >= points.length - 1) {
          setPlaying(false);
          return i;
        }
        return i + 1;
      });
    }, TICK_MS);
    return () => {
      if (timer.current) clearInterval(timer.current);
    };
  }, [playing, points.length]);

  const replayPoints: ReplayPoint[] = points.map((p) => ({ lat: p.lat, lng: p.lng }));
  const cur = points[index];

  return (
    <div>
      <PageIntro title={c.title} lead={c.subtitle} />

      {/* Mode + selectors. */}
      <Panel className="mb-4">
        <div className="flex flex-col gap-4 px-5 py-4">
          <div className="flex gap-2">
            <Chip active={mode === "guard"} onClick={() => switchMode("guard")}>
              {c.modeGuard}
            </Chip>
            <Chip active={mode === "job"} onClick={() => switchMode("job")}>
              {c.modeJob}
            </Chip>
          </div>

          {mode === "guard" ? (
            <div className="flex flex-wrap items-end gap-3">
              <Field label={c.pickGuard} className="mb-0 min-w-64">
                <select
                  value={guardId}
                  onChange={(e) => {
                    setGuardId(e.target.value);
                    setTrack(null);
                    setPoints([]);
                    setHasLoaded(false);
                  }}
                  className="w-full rounded-md border-[1.5px] border-border-strong bg-surface px-[13px] py-[11px] text-[14.5px] text-text-strong focus:border-brand-int focus:outline-none"
                  aria-label={c.pickGuard}
                >
                  <option value="">{c.pickPlaceholder}</option>
                  {guards.map((g) => (
                    <option key={g.user_id} value={g.user_id}>
                      {g.account_name?.trim() || `ID #${g.user_id.slice(0, 8)}`}
                      {g.years_of_experience != null ? ` · ${g.years_of_experience}${c.exp}` : ""}
                    </option>
                  ))}
                </select>
              </Field>
              <Field label={c.fromLabel} className="mb-0">
                <Input
                  type="datetime-local"
                  value={from}
                  onChange={(e) => setFrom(e.target.value)}
                  aria-label={c.fromLabel}
                />
              </Field>
              <Field label={c.toLabel} className="mb-0">
                <Input
                  type="datetime-local"
                  value={to}
                  onChange={(e) => setTo(e.target.value)}
                  aria-label={c.toLabel}
                />
              </Field>
              <Button onClick={() => loadByGuard(guardId)} disabled={!guardId || loadingHistory}>
                <Clock size={15} />
                {c.loadBtn}
              </Button>
            </div>
          ) : (
            <div className="flex flex-wrap items-end gap-3">
              <Field label={c.bookingLabel} className="mb-0 min-w-80 flex-1">
                <Input
                  value={bookingId}
                  onChange={(e) => setBookingId(e.target.value)}
                  placeholder={c.bookingPlaceholder}
                  className="font-mono"
                  aria-label={c.bookingLabel}
                />
              </Field>
              <Button onClick={loadByJob} disabled={!bookingId.trim() || loadingHistory}>
                <Clock size={15} />
                {c.loadBtn}
              </Button>
            </div>
          )}

          {/* Honest flag: per-point speed/heading are never historized. */}
          <div className="flex items-center gap-2 text-[12px] text-muted">
            <Info className="size-3.5 flex-none" />
            <span>{c.speedHeadingNote}</span>
            {track?.window_open ? (
              <Badge tone="amber" className="ml-1">
                {c.windowOpen}
              </Badge>
            ) : null}
            {track?.truncated ? (
              <span className="ml-auto text-amber-700">{c.truncatedNote(track.limit)}</span>
            ) : null}
          </div>
        </div>
      </Panel>

      {hasError && (
        <div
          role="alert"
          className="mb-4 flex items-center gap-2 rounded-lg border border-danger/40 bg-danger-bg px-4 py-2.5 text-sm text-danger"
        >
          <AlertTriangle className="size-4 flex-none" />
          {c.noHistory}
        </div>
      )}

      <Panel>
        <div className="relative h-[460px] w-full overflow-hidden rounded-lg">
          {!hasLoaded ? (
            <div className="flex h-full items-center justify-center text-muted">
              {mode === "guard" ? c.noGuard : c.noSelection}
            </div>
          ) : loadingHistory ? (
            <div className="flex h-full items-center justify-center gap-2 text-muted">
              <Loader2 className="size-5 animate-spin" />
              {c.loadingHistory}
            </div>
          ) : notFound ? (
            <div className="flex h-full items-center justify-center text-muted">{c.notFound}</div>
          ) : points.length === 0 ? (
            <div className="flex h-full items-center justify-center text-muted">{c.noHistory}</div>
          ) : (
            <ReplayMap points={replayPoints} currentIndex={index} />
          )}
        </div>

        {/* Scrubber + playback (only with a loaded track). */}
        {points.length > 0 && (
          <div className="flex items-center gap-4 border-t border-border px-4 py-3">
            <Button
              variant="primary"
              size="sm"
              onClick={() => {
                if (index >= points.length - 1) setIndex(0);
                setPlaying((p) => !p);
              }}
            >
              {playing ? <Pause className="size-4" /> : <Play className="size-4" />}
              {playing ? c.pause : c.play}
            </Button>
            <input
              type="range"
              min={0}
              max={points.length - 1}
              value={index}
              onChange={(e) => {
                setPlaying(false);
                setIndex(Number(e.target.value));
              }}
              className="flex-1 accent-brand-int"
              aria-label="scrubber"
            />
            <div className="min-w-44 text-right font-mono text-xs text-muted tabular-nums">
              {c.pointOf(index + 1, points.length)}
              {cur
                ? ` · ${new Date(cur.recorded_at).toLocaleString(lang === "th" ? "th-TH" : "en-GB", {
                    month: "short",
                    day: "numeric",
                    hour: "2-digit",
                    minute: "2-digit",
                    second: "2-digit",
                  })}`
                : ""}
            </div>
          </div>
        )}
      </Panel>
    </div>
  );
}

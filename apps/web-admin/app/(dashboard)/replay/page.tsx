"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import dynamic from "next/dynamic";
import { AlertTriangle, Loader2, Pause, Play } from "lucide-react";

import type { components as PresenceComponents } from "@/api/generated/presence";
import type { components as ProfileComponents } from "@/api/generated/profile";
import type { ReplayPoint } from "@/components/replay-map";
import { Badge, Button, PageIntro, Panel } from "@/components/ui";
import { presenceApi, profileApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import { COPY } from "./copy";

type HistoryPoint = PresenceComponents["schemas"]["HistoryPoint"];
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

const HISTORY_LIMIT = 500;
const TICK_MS = 600;

export default function ReplayPage() {
  const { lang } = useLanguage();
  const c = COPY[lang];

  const [guards, setGuards] = useState<GuardProfile[]>([]);
  const [guardId, setGuardId] = useState("");
  const [points, setPoints] = useState<HistoryPoint[]>([]);
  const [loadingHistory, setLoadingHistory] = useState(false);
  const [hasError, setHasError] = useState(false);
  const [index, setIndex] = useState(0);
  const [playing, setPlaying] = useState(false);

  // Approved guards for the picker.
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

  const loadHistory = useCallback((id: string) => {
    setLoadingHistory(true);
    setHasError(false);
    setPlaying(false);
    setIndex(0);
    presenceApi
      .GET("/guards/{id}/history", { params: { path: { id }, query: { limit: HISTORY_LIMIT } } })
      .then(({ data, error }) => {
        setHasError(Boolean(error));
        // History is newest-first; replay needs oldest-first.
        setPoints(error ? [] : [...(data?.data ?? [])].reverse());
        setLoadingHistory(false);
      })
      .catch(() => {
        setHasError(true);
        setLoadingHistory(false);
      });
  }, []);

  function pickGuard(id: string) {
    setGuardId(id);
    setPoints([]);
    if (id) loadHistory(id);
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

      {/* Guard picker. */}
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <label className="text-sm font-semibold text-text" htmlFor="replay-guard">
          {c.pickGuard}
        </label>
        <select
          id="replay-guard"
          value={guardId}
          onChange={(e) => pickGuard(e.target.value)}
          className="min-w-64 rounded-lg border border-border bg-surface px-3 py-2 text-sm text-text-strong focus:border-brand-int focus:outline-none"
        >
          <option value="">{c.pickPlaceholder}</option>
          {guards.map((g) => (
            <option key={g.user_id} value={g.user_id}>
              {g.account_name?.trim() || `ID #${g.user_id.slice(0, 8)}`}
              {g.years_of_experience != null ? ` · ${g.years_of_experience}${c.exp}` : ""}
            </option>
          ))}
        </select>
        <span className="ml-auto flex items-center gap-2 text-[12px] text-muted">
          <Badge tone="gray">{c.awaitingApi}</Badge>
          <span className="max-w-md">{c.gapNote}</span>
        </span>
      </div>

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
          {!guardId ? (
            <div className="flex h-full items-center justify-center text-muted">{c.noGuard}</div>
          ) : loadingHistory ? (
            <div className="flex h-full items-center justify-center gap-2 text-muted">
              <Loader2 className="size-5 animate-spin" />
              {c.loadingHistory}
            </div>
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

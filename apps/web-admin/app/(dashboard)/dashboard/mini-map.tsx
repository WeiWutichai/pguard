"use client";

import { useMemo } from "react";

import type { components } from "@/api/generated/presence";
import { cn } from "@/lib/cn";

type GuardLocation = components["schemas"]["GuardLocation"];

// Mockup .mini-map street grid: horizontal lines y=20..260 step 44, vertical x=30..600 step 56.
const H_LINES = [20, 64, 108, 152, 196, 240];
const V_LINES = [30, 86, 142, 198, 254, 310, 366, 422, 478, 534, 590];

interface Pip {
  id: string;
  /** Percent positions inside the panel. */
  x: number;
  y: number;
  /** Discovery-fresh fix (is_live) vs. connected-but-stale. */
  live: boolean;
}

/** Fit the live presence fixes into the panel: bounding box of all points scaled into
 * 8%..92% so edge pips never clip; zero spread (single guard / co-located) centres on
 * that axis. Plain linear fit — at city scale the distortion is invisible at 260px. */
function project(locations: GuardLocation[]): Pip[] {
  if (locations.length === 0) return [];
  let minLat = Infinity;
  let maxLat = -Infinity;
  let minLng = Infinity;
  let maxLng = -Infinity;
  for (const l of locations) {
    if (l.lat < minLat) minLat = l.lat;
    if (l.lat > maxLat) maxLat = l.lat;
    if (l.lng < minLng) minLng = l.lng;
    if (l.lng > maxLng) maxLng = l.lng;
  }
  const spanLat = maxLat - minLat;
  const spanLng = maxLng - minLng;
  return locations.map((l) => {
    const fx = spanLng > 0 ? (l.lng - minLng) / spanLng : 0.5;
    // Screen y grows downward; latitude grows upward — invert.
    const fy = spanLat > 0 ? (maxLat - l.lat) / spanLat : 0.5;
    return {
      id: l.guard_id,
      x: 8 + fx * 84,
      y: 8 + fy * 84,
      live: l.is_live,
    };
  });
}

/** Page-local mini map (no ui/ primitive exists): the mockup's 260px SVG street grid with
 * 14px rotated-square pips, fed by the REAL presence `/locations` fixes the dashboard
 * already loads (`/map` renders the full Leaflet view). */
export function MiniMap({
  locations,
  emptyLabel,
}: {
  locations: GuardLocation[];
  emptyLabel: string;
}) {
  const pips = useMemo(() => project(locations), [locations]);

  return (
    <div className="relative h-[260px] overflow-hidden rounded-md">
      <svg
        className="absolute inset-0 h-full w-full"
        viewBox="0 0 600 260"
        preserveAspectRatio="xMidYMid slice"
        aria-hidden="true"
      >
        {/* Land fill — mockup values verbatim: var(--m-land, #E7ECE7) light / #0C1310 dark
            (no app theme token exists for map land). */}
        <rect width="600" height="260" className="fill-[#E7ECE7] dark:fill-[#0C1310]" />
        {/* Street grid — white 5px stroke, per the mockup spec. */}
        <g className="stroke-white" strokeWidth="5">
          {H_LINES.map((y) => (
            <line key={`h${y}`} x1="0" y1={y} x2="600" y2={y} />
          ))}
          {V_LINES.map((x) => (
            <line key={`v${x}`} x1={x} y1="0" x2={x} y2="260" />
          ))}
        </g>
      </svg>

      {/* Pips: 14px rotated squares (border-radius 50%/50%/50%/2px + rotate 45deg, per the
          mockup). Fresh fixes use status-active, connected-but-stale uses status-working
          (offline never appears — the fetch is online_only). */}
      {pips.map((p) => (
        <span
          key={p.id}
          className={cn(
            "absolute size-3.5 -translate-x-1/2 -translate-y-1/2 rotate-45 border-2",
            // Pip border — mockup verbatim: #fff light / #0C1310 dark.
            "border-white dark:border-[#0C1310]",
            p.live ? "bg-status-active" : "bg-status-working",
          )}
          style={{
            left: `${p.x}%`,
            top: `${p.y}%`,
            borderRadius: "50% 50% 50% 2px",
          }}
        />
      ))}

      {locations.length === 0 ? (
        <div className="absolute inset-0 flex items-center justify-center text-sm text-muted">
          {emptyLabel}
        </div>
      ) : null}
    </div>
  );
}

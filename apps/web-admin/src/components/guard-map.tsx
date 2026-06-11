"use client";

// Leaflet map of live guard locations. Loaded ONLY via `dynamic(..., { ssr: false })` from the
// map page — it must never render on the server (Leaflet needs `window`). This file therefore
// owns ALL the leaflet runtime imports; the page imports only the TYPES from here (`import type`,
// erased at build) + the component lazily, so leaflet never enters the server bundle.
//
// Rebuilt to the hi-fi Live Map spec (§4): teardrop status pins with an active pulse ring,
// hover tooltips, custom zoom/locate controls and a Light/"Dark map" seg toggle. Marker
// colors stay on the tokens.css --status-* vars so light/dark themes flip automatically.
import "leaflet/dist/leaflet.css";
import L from "leaflet";
import { useEffect, useRef, useState } from "react";
import { MapContainer, Marker, TileLayer, Tooltip, useMap } from "react-leaflet";
import { Crosshair, Minus, Plus } from "lucide-react";

import type { components } from "@/api/generated/presence";
import { useLanguage, type TKey } from "@/lib/i18n";
import { cn } from "@/lib/cn";

export type GuardStatus = "active" | "idle" | "offline";
export type MapGuard = components["schemas"]["GuardLocation"] & { status: GuardStatus };

const STATUS_LABEL: Record<GuardStatus, TKey> = {
  active: "map.status.active",
  idle: "map.status.idle",
  offline: "map.status.offline",
};

// Bilingual labels for the map chrome only (shared i18n is single-writer; the design's map
// toggle copy is latin-only "Light" / "Dark map" in both languages).
const CHROME_COPY = {
  th: { zoomIn: "ซูมเข้า", zoomOut: "ซูมออก", locate: "แสดงเจ้าหน้าที่ทั้งหมด" },
  en: { zoomIn: "Zoom in", zoomOut: "Zoom out", locate: "Fit all guards" },
} as const;

// Map-local CSS: the design's `.mk` pin (34px teardrop, rotate 45deg, 2.5px surface ring,
// pulse keyframes for active) + token-themed leaflet tooltip/attribution, all on CSS vars so
// dark mode flips with the theme. The "Dark map" toggle emulates a dark basemap by filtering
// the raster tiles (filter only — no color literals).
const MAP_CSS = `
.pgmk{position:relative;width:34px;height:34px}
.pgmk-pulse{position:absolute;inset:0;border-radius:9999px;background:var(--status-active);animation:pgmk-pulse 2.2s ease-out infinite}
.pgmk-pin{position:relative;display:flex;width:34px;height:34px;align-items:center;justify-content:center;border:2.5px solid var(--bg-surface);border-radius:50% 50% 50% 3px;box-shadow:var(--sh-md);transform:rotate(45deg);transition:transform .12s}
.pgmk-pin svg{transform:rotate(-45deg)}
.pgmk-sel .pgmk-pin{transform:rotate(45deg) scale(1.18)}
.pgmk-pin--active{background:var(--status-active)}
.pgmk-pin--idle{background:var(--status-working)}
.pgmk-pin--offline{background:var(--status-offline)}
@keyframes pgmk-pulse{0%{transform:scale(.6);opacity:.5}100%{transform:scale(2.6);opacity:0}}
.pgmap .leaflet-container{background:var(--bg-sunken);font:inherit}
.pgmap .leaflet-tooltip{background:var(--bg-surface);border:1px solid var(--border);border-radius:var(--r-sm);box-shadow:var(--sh-md);color:var(--text-strong);font-size:11.5px;font-weight:600;padding:5px 10px}
.pgmap .leaflet-tooltip-top:before{border-top-color:var(--border)}
.pgmap .leaflet-control-attribution{background:var(--bg-surface);color:var(--text-muted)}
.pgmap .leaflet-control-attribution a{color:var(--text-muted)}
.pgmap-dark .pgmap-tiles{filter:invert(1) hue-rotate(180deg) brightness(.95) contrast(.9)}
`;

// Shield glyph inside the pin. stroke="#fff" is quoted verbatim from the design spec
// (§4.4 "Stroke: #fff" — the icon stays white on the colored pin in both themes).
const SHIELD_SVG =
  '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3l7 3v5c0 4.5-3 8-7 9-4-1-7-4.5-7-9V6z"/></svg>';

// Module-level icon cache: build each pin variant ONCE (3 statuses × selected), reuse across
// renders + every marker — Leaflet icons are immutable, so caching avoids re-creating DivIcons.
const iconCache = new Map<string, L.DivIcon>();
function iconFor(status: GuardStatus, selected: boolean): L.DivIcon {
  const key = `${status}${selected ? "-sel" : ""}`;
  const cached = iconCache.get(key);
  if (cached) return cached;
  // SECURITY: this html bypasses React escaping. ONLY interpolate static, non-user-controlled
  // values here (status is one of the 3 enum values; SHIELD_SVG is a fixed constant). Never
  // inject any server/guard-provided field into this string.
  const icon = L.divIcon({
    className: "",
    html:
      `<div class="pgmk${selected ? " pgmk-sel" : ""}">` +
      (status === "active" ? '<span class="pgmk-pulse"></span>' : "") +
      `<span class="pgmk-pin pgmk-pin--${status}">${SHIELD_SVG}</span></div>`,
    iconSize: [34, 34],
    iconAnchor: [17, 31],
    tooltipAnchor: [0, -28],
  });
  iconCache.set(key, icon);
  return icon;
}

// Bangkok — a sensible default center when no guard has a location yet.
const DEFAULT_CENTER: [number, number] = [13.7563, 100.5018];

/** Design §4.3 map controls — custom zoom in/out + locate (fit all guards), bottom-right. */
function MapControls({
  guards,
  labels,
}: {
  guards: MapGuard[];
  labels: { zoomIn: string; zoomOut: string; locate: string };
}) {
  const map = useMap();
  const ref = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    const el = ref.current;
    if (el) {
      L.DomEvent.disableClickPropagation(el);
      L.DomEvent.disableScrollPropagation(el);
    }
  }, []);

  function locate() {
    if (guards.length) {
      map.fitBounds(
        L.latLngBounds(guards.map((g) => [g.lat, g.lng] as [number, number])).pad(0.2),
      );
    } else {
      map.setView(DEFAULT_CENTER, 11);
    }
  }

  const btn =
    "flex size-10 cursor-pointer items-center justify-center rounded-md border border-border bg-surface text-text shadow-sm transition-colors hover:bg-sunken";
  return (
    <div className="leaflet-bottom leaflet-right">
      <div ref={ref} className="leaflet-control mb-[18px]! mr-3! flex flex-col gap-2">
        <button type="button" aria-label={labels.zoomIn} onClick={() => map.zoomIn()} className={btn}>
          <Plus className="size-[18px]" />
        </button>
        <button type="button" aria-label={labels.zoomOut} onClick={() => map.zoomOut()} className={btn}>
          <Minus className="size-[18px]" />
        </button>
        <button type="button" aria-label={labels.locate} onClick={locate} className={btn}>
          <Crosshair className="size-[18px]" />
        </button>
      </div>
    </div>
  );
}

/** Pans to the selected guard (roster/marker click) and follows live position updates. */
function PanToSelected({ guard }: { guard?: MapGuard }) {
  const map = useMap();
  useEffect(() => {
    if (guard) map.panTo([guard.lat, guard.lng]);
  }, [map, guard]);
  return null;
}

export default function GuardMap({
  guards,
  selectedId = null,
  onSelect,
}: {
  guards: MapGuard[];
  selectedId?: string | null;
  onSelect?: (id: string) => void;
}) {
  const { t, lang } = useLanguage();
  // Design §4.2 — independent Light/"Dark map" basemap toggle, defaults to Light.
  const [darkMap, setDarkMap] = useState(false);
  const chrome = CHROME_COPY[lang];
  const center: [number, number] = guards.length
    ? [guards[0].lat, guards[0].lng]
    : DEFAULT_CENTER;
  const selected = guards.find((g) => g.guard_id === selectedId);

  return (
    <div className={cn("pgmap relative h-full w-full", darkMap && "pgmap-dark")}>
      <style>{MAP_CSS}</style>
      <MapContainer
        center={center}
        zoom={guards.length ? 11 : 6}
        zoomControl={false}
        scrollWheelZoom
        className="h-full w-full"
      >
        <TileLayer
          className="pgmap-tiles"
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        {guards.map((g) => (
          <Marker
            key={g.guard_id}
            position={[g.lat, g.lng]}
            icon={iconFor(g.status, g.guard_id === selectedId)}
            eventHandlers={onSelect ? { click: () => onSelect(g.guard_id) } : undefined}
          >
            {/* Design `.mk .tip` hover tooltip: "{id} · {status}". */}
            <Tooltip direction="top">
              <span className="font-mono">{g.guard_id.slice(0, 8)}</span>
              {" · "}
              {t(STATUS_LABEL[g.status])}
            </Tooltip>
          </Marker>
        ))}
        <MapControls guards={guards} labels={chrome} />
        <PanToSelected guard={selected} />
      </MapContainer>

      {/* Design `.map-toggle` seg-mini — latin-only "Light"/"Dark map" in both languages. */}
      <div className="absolute right-4 top-4 z-[1000] flex rounded-full border border-border bg-sunken p-[3px] shadow-sm">
        <button type="button" onClick={() => setDarkMap(false)} className={segBtn(!darkMap)}>
          Light
        </button>
        <button type="button" onClick={() => setDarkMap(true)} className={segBtn(darkMap)}>
          Dark map
        </button>
      </div>
    </div>
  );
}

/** Design `.seg-mini` segment button. */
function segBtn(on: boolean): string {
  return cn(
    "cursor-pointer rounded-full px-3 py-1.5 font-latin text-xs font-semibold transition-colors",
    on ? "bg-surface text-text-strong shadow-xs" : "text-muted hover:text-text",
  );
}

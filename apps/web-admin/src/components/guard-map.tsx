"use client";

// Leaflet map of live guard locations. Loaded ONLY via `dynamic(..., { ssr: false })` from the
// map page — it must never render on the server (Leaflet needs `window`). This file therefore
// owns ALL the leaflet runtime imports; the page imports only the TYPES from here (`import type`,
// erased at build) + the component lazily, so leaflet never enters the server bundle.
import "leaflet/dist/leaflet.css";
import L from "leaflet";
import { MapContainer, Marker, Popup, TileLayer } from "react-leaflet";

import type { components } from "@/api/generated/presence";
import { useLanguage, type TKey } from "@/lib/i18n";

export type GuardStatus = "active" | "idle" | "offline";
export type MapGuard = components["schemas"]["GuardLocation"] & { status: GuardStatus };

// Guard live-status tokens (tokens.css --status-*); the divIcon html lands in the DOM, so
// CSS vars resolve there — markers stay token-driven and theme-aware, no raw hex.
const STATUS_COLOR: Record<GuardStatus, string> = {
  active: "var(--status-active)",
  idle: "var(--status-working)",
  offline: "var(--status-offline)",
};
const STATUS_LABEL: Record<GuardStatus, TKey> = {
  active: "map.status.active",
  idle: "map.status.idle",
  offline: "map.status.offline",
};

// Module-level icon cache: build each colored marker ONCE (3 statuses), reuse across renders +
// every marker — Leaflet icons are immutable, so caching avoids re-creating a DivIcon per guard.
const iconCache = new Map<GuardStatus, L.DivIcon>();
function iconFor(status: GuardStatus): L.DivIcon {
  const cached = iconCache.get(status);
  if (cached) return cached;
  // SECURITY: this html bypasses React escaping. ONLY interpolate static, non-user-controlled
  // values here (STATUS_COLOR is a fixed constant keyed by the 3 enum statuses). Never inject any
  // server/guard-provided field into this string.
  const icon = L.divIcon({
    className: "",
    html: `<span style="display:block;width:14px;height:14px;border-radius:9999px;background:${STATUS_COLOR[status]};border:2px solid var(--bg-surface);box-shadow:0 0 0 1px rgba(0,0,0,.25)"></span>`,
    iconSize: [14, 14],
    iconAnchor: [7, 7],
  });
  iconCache.set(status, icon);
  return icon;
}

// Bangkok — a sensible default center when no guard has a location yet.
const DEFAULT_CENTER: [number, number] = [13.7563, 100.5018];

export default function GuardMap({ guards }: { guards: MapGuard[] }) {
  const { t } = useLanguage();
  const center: [number, number] = guards.length
    ? [guards[0].lat, guards[0].lng]
    : DEFAULT_CENTER;

  return (
    <MapContainer
      center={center}
      zoom={guards.length ? 11 : 6}
      scrollWheelZoom
      className="h-[62vh] w-full rounded-xl border border-border"
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      {guards.map((g) => (
        <Marker key={g.guard_id} position={[g.lat, g.lng]} icon={iconFor(g.status)}>
          <Popup>
            <div className="space-y-1 text-xs">
              <div className="font-mono">{g.guard_id}</div>
              <div>{t(STATUS_LABEL[g.status])}</div>
              <div className="text-muted">
                {t("map.lastSeen")}: {g.recorded_at.slice(0, 19).replace("T", " ")}
              </div>
              {g.accuracy != null && (
                <div className="text-muted">
                  {t("map.accuracy")}: ~{Math.round(g.accuracy)} m
                </div>
              )}
            </div>
          </Popup>
        </Marker>
      ))}
    </MapContainer>
  );
}

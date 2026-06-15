"use client";

// Leaflet route map for Location Replay. Loaded ONLY via `dynamic(..., { ssr: false })` — it
// owns the leaflet runtime imports (leaflet needs `window`); the page imports only the TYPE
// (`import type`, erased) so leaflet never enters the server bundle. Mirrors guard-map.tsx.
import "leaflet/dist/leaflet.css";
import L from "leaflet";
import { useEffect } from "react";
import { CircleMarker, MapContainer, Marker, Polyline, TileLayer, useMap } from "react-leaflet";

export interface ReplayPoint {
  lat: number;
  lng: number;
}

const DEFAULT_CENTER: [number, number] = [13.7563, 100.5018];

const MAP_CSS = `
.pgrmap .leaflet-container{background:var(--bg-sunken);font:inherit}
.pgrmap .leaflet-control-attribution{background:var(--bg-surface);color:var(--text-muted)}
.pgrmap .leaflet-control-attribution a{color:var(--text-muted)}
.pgr-dot{width:18px;height:18px;border-radius:50%;background:var(--brand-int);border:3px solid var(--bg-surface);box-shadow:var(--sh-md)}
`;

// The moving "current position" marker — a brand-int dot.
const CURRENT_ICON = L.divIcon({
  className: "",
  html: '<div class="pgr-dot"></div>',
  iconSize: [18, 18],
  iconAnchor: [9, 9],
});

/** Fit the map to the whole route once it loads (or when the guard changes). */
function FitRoute({ points }: { points: ReplayPoint[] }) {
  const map = useMap();
  useEffect(() => {
    if (points.length === 0) {
      map.setView(DEFAULT_CENTER, 11);
      return;
    }
    if (points.length === 1) {
      map.setView([points[0].lat, points[0].lng], 15);
      return;
    }
    map.fitBounds(L.latLngBounds(points.map((p) => [p.lat, p.lng] as [number, number])).pad(0.2));
  }, [map, points]);
  return null;
}

export default function ReplayMap({
  points,
  currentIndex,
}: {
  points: ReplayPoint[];
  currentIndex: number;
}) {
  const cur = points[Math.min(currentIndex, points.length - 1)];
  const line = points.map((p) => [p.lat, p.lng] as [number, number]);
  // The traversed portion of the route (start → current), drawn brighter over the full track.
  const traversed = line.slice(0, Math.max(1, currentIndex + 1));

  return (
    <div className="pgrmap relative h-full w-full">
      <style>{MAP_CSS}</style>
      <MapContainer center={DEFAULT_CENTER} zoom={11} scrollWheelZoom className="h-full w-full">
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        {line.length > 1 && (
          <Polyline positions={line} pathOptions={{ color: "var(--border-strong)", weight: 3, opacity: 0.6 }} />
        )}
        {traversed.length > 1 && (
          <Polyline positions={traversed} pathOptions={{ color: "var(--brand-int)", weight: 4 }} />
        )}
        {line.length > 0 && (
          <CircleMarker
            center={line[0]}
            radius={6}
            pathOptions={{ color: "var(--success)", fillColor: "var(--success)", fillOpacity: 1 }}
          />
        )}
        {cur && <Marker position={[cur.lat, cur.lng]} icon={CURRENT_ICON} />}
        <FitRoute points={points} />
      </MapContainer>
    </div>
  );
}

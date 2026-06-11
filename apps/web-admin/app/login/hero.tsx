"use client";

import { Lock, MapPin } from "lucide-react";

import { useLanguage } from "@/lib/i18n";

import { COPY } from "./copy";

/** Hero stats are STATIC by design — the spec's data note says "hardcoded hero stats:
 * 384 guards, 2,418 customers, 99.2% uptime. No API call." They are brand copy on the
 * pre-auth page (no session → nothing could be fetched), not a live-data section, so no
 * gap chip. Numbers are verbatim from the hi-fi mockup. */
const STATS = [
  { n: "384", label: "statGuards" },
  { n: "2,418", label: "statCustomers" },
  { n: "99.2%", label: "statUptime" },
] as const;

/** Decorative pins (spec: 5 staggered markers anchored right:50px / top:120px, colored
 * green-300 / amber-500 / red — "red" rides the --danger token). Pure decoration. */
const PINS = [
  { x: -10, y: 0, size: 26, cls: "text-green-300", opacity: 0.95 },
  { x: -120, y: 78, size: 21, cls: "text-amber-500", opacity: 0.85 },
  { x: 36, y: 150, size: 19, cls: "text-green-300", opacity: 0.7 },
  { x: -180, y: 216, size: 24, cls: "text-danger", opacity: 0.9 },
  { x: -58, y: 286, size: 17, cls: "text-green-300", opacity: 0.6 },
] as const;

/** Left brand panel of the split login layout (desktop only — hidden below 900px per the
 * spec). Gradient + grid overlay + wordmark + bilingual headline + static stats. */
export function LoginHero() {
  const { lang } = useLanguage();
  const c = COPY[lang];

  return (
    <section
      className="relative hidden flex-col justify-between overflow-hidden p-14 min-[900px]:flex"
      // spec: background linear-gradient(155deg, var(--green-800), var(--green-950))
      style={{ background: "linear-gradient(155deg, var(--green-800), var(--green-950))" }}
    >
      {/* Grid overlay — rgba(255,255,255,.05) hairlines every 42px at opacity .6 (verbatim
          from the spec; fixed white-on-dark artwork, identical in both themes). */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 opacity-60"
        style={{
          backgroundImage:
            "linear-gradient(rgba(255,255,255,.05) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,.05) 1px, transparent 1px)",
          backgroundSize: "42px 42px",
        }}
      />

      {/* Decorative pin cluster */}
      <div aria-hidden className="pointer-events-none absolute right-[50px] top-[120px]">
        {PINS.map((p, i) => (
          <MapPin
            key={i}
            size={p.size}
            className={`absolute ${p.cls}`}
            style={{ left: p.x, top: p.y, opacity: p.opacity }}
          />
        ))}
      </div>

      {/* Lock + wordmark — hero text is #fff on the brand gradient per the spec (theme-stable). */}
      <div className="relative flex items-center gap-2.5 font-latin text-[26px] font-bold tracking-[-0.03em] text-white">
        <Lock size={24} className="text-green-300" aria-hidden />
        <span>
          <span className="text-green-300">p</span>guard
        </span>
      </div>

      <div className="relative">
        <h2 className="max-w-[460px] text-[38px] font-semibold leading-[1.18] tracking-[-0.02em] text-white">
          {c.heroTitle}
        </h2>
        <p className="mt-4 max-w-[420px] text-base text-white opacity-80">{c.heroTagline}</p>
        <div className="mt-[34px] flex gap-[30px]">
          {STATS.map((s) => (
            <div key={s.label}>
              <div className="font-mono text-2xl font-semibold text-white">{s.n}</div>
              <div className="text-xs text-white opacity-70">{c[s.label]}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

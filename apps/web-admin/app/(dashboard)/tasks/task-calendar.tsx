"use client";

import { useMemo } from "react";

import type { components } from "@/api/generated/booking";
import { cn } from "@/lib/cn";
import { useLanguage } from "@/lib/i18n";

import { type BookingStatusKey, STATUS_TONE } from "../bookings/copy";
import { COPY } from "./copy";

type Booking = components["schemas"]["Booking"];

// Calendar chip background per status tone (mirrors the badge palette, lighter).
const CHIP: Record<string, string> = {
  green: "bg-success-bg text-success",
  amber: "bg-warning-bg text-amber-700 dark:text-amber-300",
  red: "bg-danger-bg text-danger",
  blue: "bg-info-bg text-info",
  gray: "bg-sunken text-muted",
};

const MAX_CHIPS = 2;

/** Current-month calendar of bookings keyed by `scheduled_at` day. Read-only planning view;
 * clicking a chip opens the same detail/assign modal as the table. Bookings scheduled in
 * other months don't appear (this is the current month only — a month picker is a follow-up). */
export function TaskCalendar({
  bookings,
  customerNames,
  onSelect,
}: {
  bookings: Booking[];
  customerNames: Record<string, string>;
  onSelect: (b: Booking) => void;
}) {
  const { lang } = useLanguage();
  const c = COPY[lang];

  const { cells, byDay, monthLabel } = useMemo(() => {
    const now = new Date();
    const year = now.getFullYear();
    const month = now.getMonth();
    const today = now.getDate();
    const firstWeekday = new Date(year, month, 1).getDay();
    const daysInMonth = new Date(year, month + 1, 0).getDate();

    const byDay: Record<number, Booking[]> = {};
    for (const b of bookings) {
      const d = new Date(b.scheduled_at);
      if (Number.isNaN(d.getTime())) continue;
      if (d.getFullYear() === year && d.getMonth() === month) {
        (byDay[d.getDate()] ??= []).push(b);
      }
    }

    const cells: ({ day: number; isToday: boolean } | null)[] = [];
    for (let i = 0; i < firstWeekday; i++) cells.push(null);
    for (let day = 1; day <= daysInMonth; day++) cells.push({ day, isToday: day === today });

    const monthLabel = new Intl.DateTimeFormat(lang === "th" ? "th-TH" : "en-GB", {
      month: "long",
      year: "numeric",
    }).format(now);

    return { cells, byDay, monthLabel };
  }, [bookings, lang]);

  return (
    <div>
      <div className="mb-3 text-sm font-semibold text-text-strong">{monthLabel}</div>
      <div className="grid grid-cols-7 gap-2">
        {c.weekdays.map((w) => (
          <div key={w} className="pb-1.5 text-center text-xs font-semibold text-faint">
            {w}
          </div>
        ))}
        {cells.map((cell, i) =>
          cell === null ? (
            <div key={`pad-${i}`} />
          ) : (
            <div
              key={cell.day}
              className="min-h-[96px] rounded-md border border-border bg-surface p-2"
            >
              <div
                className={cn(
                  "mb-1.5 font-mono text-xs",
                  cell.isToday ? "font-bold text-brand-int" : "text-muted",
                )}
              >
                {cell.day}
              </div>
              {(byDay[cell.day] ?? []).slice(0, MAX_CHIPS).map((b) => {
                const tone = STATUS_TONE[b.status as BookingStatusKey] ?? "gray";
                return (
                  <button
                    key={b.id}
                    type="button"
                    onClick={() => onSelect(b)}
                    title={customerNames[b.customer_id] ?? b.address}
                    className={cn(
                      "mb-1 block w-full truncate rounded px-1.5 py-0.5 text-left text-[10.5px]",
                      CHIP[tone],
                    )}
                  >
                    {customerNames[b.customer_id] ?? `#${b.id.slice(0, 6)}`}
                  </button>
                );
              })}
              {(byDay[cell.day]?.length ?? 0) > MAX_CHIPS && (
                <div className="px-1.5 text-[10px] text-faint">
                  +{(byDay[cell.day]?.length ?? 0) - MAX_CHIPS}
                </div>
              )}
            </div>
          ),
        )}
      </div>
    </div>
  );
}

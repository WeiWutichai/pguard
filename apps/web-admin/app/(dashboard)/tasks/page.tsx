"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, CalendarDays, Loader2, RefreshCw, Rows3 } from "lucide-react";

import type { components as BookingComponents } from "@/api/generated/booking";
import type { components as ProfileComponents } from "@/api/generated/profile";
import {
  Badge,
  Button,
  Chip,
  PageIntro,
  Pagination,
  Panel,
  SearchField,
  Table,
  Td,
  Th,
  Tr,
} from "@/components/ui";
import { bookingApi, profileApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import { cn } from "@/lib/cn";

import { BookingDetailModal } from "../bookings/booking-detail-modal";
import {
  type BookingStatusKey,
  bookingTotal,
  COPY as BOOKINGS_COPY,
  fmtBaht,
  STATUS_TONE,
} from "../bookings/copy";
import { CANCELLABLE, COPY } from "./copy";
import { TaskCalendar } from "./task-calendar";

type Booking = BookingComponents["schemas"]["Booking"];
type GuardProfile = ProfileComponents["schemas"]["GuardProfile"];

const PAGE_SIZE = 8;

export default function TasksPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];
  const sLabel = BOOKINGS_COPY[lang].statusLabel;

  const [bookings, setBookings] = useState<Booking[]>([]);
  const [customerNames, setCustomerNames] = useState<Record<string, string>>({});
  const [approvedGuards, setApprovedGuards] = useState<GuardProfile[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);

  const [view, setView] = useState<"table" | "calendar">("table");
  const [onlyUnassigned, setOnlyUnassigned] = useState(false);
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [cancelling, setCancelling] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [detail, setDetail] = useState<Booking | null>(null);

  const fetchInto = useCallback((alive: () => boolean) => {
    return Promise.all([
      bookingApi.GET("/admin/bookings", { params: { query: {} } }),
      profileApi.GET("/admin/customer-profiles"),
      profileApi.GET("/admin/guard-profiles", {
        params: { query: { approval_status: "approved" } },
      }),
    ])
      .then(([bRes, cRes, gRes]) => {
        if (!alive()) return;
        setHasError(Boolean(bRes.error));
        setBookings(bRes.error ? [] : (bRes.data?.data ?? []));
        const names: Record<string, string> = {};
        for (const cust of cRes.data?.data ?? []) {
          if (cust.full_name) names[cust.user_id] = cust.full_name;
        }
        setCustomerNames(names);
        setApprovedGuards(gRes.data?.data ?? []);
        setLoading(false);
      })
      .catch(() => {
        if (!alive()) return;
        setHasError(true);
        setLoading(false);
      });
  }, []);

  useEffect(() => {
    let alive = true;
    void fetchInto(() => alive);
    return () => {
      alive = false;
    };
  }, [reloadNonce, fetchInto]);

  function reload() {
    setLoading(true);
    setHasError(false);
    setReloadNonce((n) => n + 1);
  }

  const bookingById = useMemo(() => new Map(bookings.map((b) => [b.id, b])), [bookings]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return bookings.filter((b) => {
      if (onlyUnassigned && !(b.status === "requested" && !b.guard_id)) return false;
      if (!q) return true;
      const name = customerNames[b.customer_id] ?? "";
      return [b.id, name, b.address]
        .filter(Boolean)
        .some((v) => String(v).toLowerCase().includes(q));
    });
  }, [bookings, onlyUnassigned, query, customerNames]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, pageCount);
  const visible = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);
  const summaryStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const summaryEnd = Math.min(safePage * PAGE_SIZE, filtered.length);

  const visibleIds = visible.map((b) => b.id);
  const allVisibleSelected = visibleIds.length > 0 && visibleIds.every((id) => selected.has(id));

  function toggle(id: string) {
    setSelected((cur) => {
      const next = new Set(cur);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
    setNotice(null);
  }
  function toggleAllVisible() {
    setSelected((cur) => {
      const next = new Set(cur);
      if (allVisibleSelected) visibleIds.forEach((id) => next.delete(id));
      else visibleIds.forEach((id) => next.add(id));
      return next;
    });
    setNotice(null);
  }

  async function bulkCancel() {
    setCancelling(true);
    setNotice(null);
    const ids = [...selected];
    const cancellable = ids.filter((id) =>
      (CANCELLABLE as readonly string[]).includes(bookingById.get(id)?.status ?? ""),
    );
    const skippedPre = ids.length - cancellable.length;
    const results = await Promise.allSettled(
      cancellable.map((id) =>
        bookingApi.PUT("/bookings/{id}/cancel", { params: { path: { id } } }).then(({ error }) => {
          if (error) throw error;
        }),
      ),
    );
    const ok = results.filter((r) => r.status === "fulfilled").length;
    const failed = results.length - ok;
    setNotice(c.cancelResult(ok, skippedPre + failed));
    setSelected(new Set());
    setCancelling(false);
    reload();
  }

  const gap = <Badge tone="gray">{c.awaitingApi}</Badge>;

  return (
    <div>
      <PageIntro
        title={c.title}
        lead={loading || hasError ? t("tasks.subtitle") : c.subtitle(String(bookings.length))}
      >
        <Button variant="secondary" size="sm" onClick={reload}>
          <RefreshCw size={15} />
          {t("common.retry")}
        </Button>
      </PageIntro>

      {hasError && (
        <div
          role="alert"
          className="mb-4 flex items-center gap-2 rounded-lg border border-danger/40 bg-danger-bg px-4 py-2.5 text-sm text-danger"
        >
          <AlertTriangle className="size-4 flex-none" />
          {t("tasks.error")}
        </div>
      )}

      {/* View toggle + filters. */}
      <div className="mb-4 flex flex-wrap items-center gap-2.5">
        <div className="inline-flex rounded-lg border border-border bg-sunken p-[3px]">
          {(
            [
              ["table", c.viewTable, Rows3],
              ["calendar", c.viewCalendar, CalendarDays],
            ] as const
          ).map(([v, label, Icon]) => (
            <button
              key={v}
              type="button"
              onClick={() => setView(v)}
              className={cn(
                "flex items-center gap-1.5 rounded-md px-3.5 py-[7px] text-[13px] font-semibold",
                view === v ? "bg-surface text-text-strong shadow-xs" : "text-muted",
              )}
            >
              <Icon className="size-3.5" />
              {label}
            </button>
          ))}
        </div>
        <Chip active={!onlyUnassigned} onClick={() => setOnlyUnassigned(false)}>
          {c.filterAll}
        </Chip>
        <Chip
          active={onlyUnassigned}
          dot="bg-amber-500"
          onClick={() => {
            setOnlyUnassigned(true);
            setPage(1);
          }}
        >
          {c.filterUnassigned}
        </Chip>
        <SearchField
          size="sm"
          className="ml-auto"
          placeholder={c.searchPlaceholder}
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setPage(1);
          }}
        />
      </div>

      {notice && (
        <div className="mb-4 rounded-lg border border-border bg-sunken px-4 py-2.5 text-sm text-text-strong">
          {notice}
        </div>
      )}

      {/* Bulk action bar — Cancel is real (pre-arrival only); Assign/Refund need per-row /
          payment surfaces, shown as honest disabled gaps. */}
      {view === "table" && selected.size > 0 && (
        <div className="mb-3 flex items-center gap-3 rounded-lg bg-green-900 px-4 py-3 text-white dark:bg-brand-int dark:text-on-brand">
          <span className="font-semibold">{c.selected(selected.size)}</span>
          <div className="ml-auto flex items-center gap-2">
            <span
              title={c.awaitingApi}
              className="cursor-not-allowed rounded-md bg-white/15 px-3 py-1.5 text-[13px] font-semibold opacity-60"
            >
              {c.bulkAssign}
            </span>
            <button
              type="button"
              onClick={bulkCancel}
              disabled={cancelling}
              className="rounded-md bg-white/20 px-3 py-1.5 text-[13px] font-semibold hover:bg-white/30 disabled:opacity-60"
            >
              {cancelling ? c.cancelling : c.bulkCancel}
            </button>
            <span
              title={c.awaitingApi}
              className="cursor-not-allowed rounded-md bg-white/15 px-3 py-1.5 text-[13px] font-semibold opacity-60"
            >
              {c.bulkRefund}
            </span>
          </div>
        </div>
      )}

      {loading ? (
        <Panel>
          <div className="flex items-center justify-center gap-2 py-16 text-muted">
            <Loader2 className="size-5 animate-spin" />
            {t("common.loading")}
          </div>
        </Panel>
      ) : view === "calendar" ? (
        <Panel>
          <div className="p-4">
            <TaskCalendar bookings={filtered} customerNames={customerNames} onSelect={setDetail} />
          </div>
        </Panel>
      ) : filtered.length === 0 ? (
        <Panel>
          <div className="py-16 text-center text-muted">{t("tasks.empty")}</div>
        </Panel>
      ) : (
        <Panel>
          <Table>
            <thead>
              <tr>
                <Th className="w-10">
                  <input
                    type="checkbox"
                    aria-label="select all"
                    checked={allVisibleSelected}
                    onChange={toggleAllVisible}
                    className="size-4 accent-brand-int"
                  />
                </Th>
                <Th>{c.colRequest}</Th>
                <Th>{c.colCustomer}</Th>
                <Th>{c.colGuard}</Th>
                <Th>{c.colStatus}</Th>
                <Th>{c.colScheduled}</Th>
                <Th>{c.colAmount}</Th>
              </tr>
            </thead>
            <tbody>
              {visible.map((b) => {
                const status = b.status as BookingStatusKey;
                const canAssign = status === "requested" && !b.guard_id;
                return (
                  <Tr key={b.id} onClick={() => setDetail(b)}>
                    <Td onClick={(e) => e.stopPropagation()}>
                      <input
                        type="checkbox"
                        aria-label={`select ${b.id.slice(0, 8)}`}
                        checked={selected.has(b.id)}
                        onChange={() => toggle(b.id)}
                        className="size-4 accent-brand-int"
                      />
                    </Td>
                    <Td className="font-mono font-semibold text-text-strong">
                      #{b.id.slice(0, 8)}
                    </Td>
                    <Td>{customerNames[b.customer_id] ?? `ID #${b.customer_id.slice(0, 8)}`}</Td>
                    <Td>
                      {b.guard_id ? (
                        <span className="font-mono text-muted">#{b.guard_id.slice(0, 8)}</span>
                      ) : canAssign ? (
                        <Button
                          variant="secondary"
                          size="sm"
                          onClick={(e) => {
                            e.stopPropagation();
                            setDetail(b);
                          }}
                        >
                          {c.assign}
                        </Button>
                      ) : (
                        <Badge tone="amber">{c.unassigned}</Badge>
                      )}
                    </Td>
                    <Td>
                      <Badge tone={STATUS_TONE[status] ?? "gray"}>{sLabel[status] ?? status}</Badge>
                    </Td>
                    <Td className="font-mono text-muted tabular-nums">
                      {new Date(b.scheduled_at).toLocaleString(lang === "th" ? "th-TH" : "en-GB", {
                        month: "short",
                        day: "numeric",
                        hour: "2-digit",
                        minute: "2-digit",
                      })}
                    </Td>
                    <Td className="font-mono tabular-nums">{fmtBaht(bookingTotal(b))}</Td>
                  </Tr>
                );
              })}
            </tbody>
          </Table>
          <Pagination
            page={safePage}
            pageCount={pageCount}
            onPage={setPage}
            summary={`${summaryStart}–${summaryEnd} ${c.of} ${filtered.length}`}
          />
        </Panel>
      )}

      {/* Make the awaiting-API note for Assign/Refund discoverable even with no selection. */}
      {view === "table" && selected.size === 0 && (
        <div className="mt-3 flex items-center gap-2 text-xs text-muted">
          {gap}
          <span>
            {c.bulkAssign} · {c.bulkRefund}
          </span>
        </div>
      )}

      {detail && (
        <BookingDetailModal
          booking={detail}
          customerName={customerNames[detail.customer_id] ?? null}
          approvedGuards={approvedGuards}
          onClose={() => setDetail(null)}
          onAssigned={() => {
            setDetail(null);
            reload();
          }}
        />
      )}
    </div>
  );
}

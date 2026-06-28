"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, Loader2, RefreshCw } from "lucide-react";

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
import { useNameResolver } from "@/lib/use-names";
import { fmtCappedCount } from "@/lib/format";

import { BookingDetailModal } from "./booking-detail-modal";
import {
  type BookingStatusKey,
  bookingTotal,
  COPY,
  fmtBaht,
  STATUS_TONE,
  STATUSES,
} from "./copy";

type Booking = BookingComponents["schemas"]["Booking"];
type GuardProfile = ProfileComponents["schemas"]["GuardProfile"];

/** Design shows 9 rows per page ("1–9 of 27"). The admin list endpoint is capped at 200 with
 * no pagination params, so paging + status filter + search all slice the fetched list. */
const PAGE_SIZE = 9;

export default function BookingsPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [bookings, setBookings] = useState<Booking[]>([]);
  // customer_id → full_name / contact_phone (admin customer directory; best-effort enrichment).
  const [customerNames, setCustomerNames] = useState<Record<string, string>>({});
  const [customerPhones, setCustomerPhones] = useState<Record<string, string>>({});
  const [approvedGuards, setApprovedGuards] = useState<GuardProfile[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);

  const [selected, setSelected] = useState<Booking | null>(null);
  const [statusFilter, setStatusFilter] = useState<BookingStatusKey | "all">("all");
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);

  const fetchInto = useCallback((alive: () => boolean) => {
    // Bookings is authoritative for this screen; the customer-name + approved-guard reads are
    // best-effort enrichment (the page still works — ids/empty picker — if they fail).
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
        const phones: Record<string, string> = {};
        for (const cust of cRes.data?.data ?? []) {
          if (cust.full_name) names[cust.user_id] = cust.full_name;
          if (cust.contact_phone) phones[cust.user_id] = cust.contact_phone;
        }
        setCustomerNames(names);
        setCustomerPhones(phones);
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

  // Batch-resolve every customer + guard id on the page to real display names in one call (the
  // resolver answers both roles). Customer/guard columns prefer this over the raw UUID slice; the
  // customer-directory enrichment above still backs the modal phone + a name source for search.
  const resolveIds = useMemo(() => {
    const out: string[] = [];
    for (const b of bookings) {
      out.push(b.customer_id);
      if (b.guard_id) out.push(b.guard_id);
    }
    return out;
  }, [bookings]);
  const { resolve } = useNameResolver(resolveIds, lang);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return bookings.filter((b) => {
      if (statusFilter !== "all" && b.status !== statusFilter) return false;
      if (!q) return true;
      const name = resolve(b.customer_id).name ?? customerNames[b.customer_id] ?? "";
      const guardName = b.guard_id ? (resolve(b.guard_id).name ?? "") : "";
      return [b.id, b.customer_id, b.guard_id ?? "", name, guardName, b.address]
        .filter(Boolean)
        .some((v) => String(v).toLowerCase().includes(q));
    });
  }, [bookings, statusFilter, query, customerNames, resolve]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, pageCount);
  const visible = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);
  const summaryStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const summaryEnd = Math.min(safePage * PAGE_SIZE, filtered.length);

  const dtFmt = useMemo(
    () =>
      new Intl.DateTimeFormat(lang === "th" ? "th-TH" : "en-GB", {
        month: "short",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      }),
    [lang],
  );
  const fmtTime = (iso: string) => {
    const d = new Date(iso);
    return Number.isNaN(d.getTime()) ? "—" : dtFmt.format(d);
  };

  return (
    <div>
      <PageIntro
        title={c.title}
        lead={
          loading || hasError ? t("bookings.subtitle") : c.subtitle(fmtCappedCount(bookings.length))
        }
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
          {t("bookings.error")}
        </div>
      )}

      {/* Status filter chips (real v2 statuses) + search. */}
      <div className="mb-4 flex flex-wrap items-center gap-2.5">
        <Chip
          active={statusFilter === "all"}
          onClick={() => {
            setStatusFilter("all");
            setPage(1);
          }}
        >
          {t("common.all")}
        </Chip>
        {STATUSES.map((s) => (
          <Chip
            key={s}
            active={statusFilter === s}
            onClick={() => {
              setStatusFilter(s);
              setPage(1);
            }}
          >
            {c.statusLabel[s]}
          </Chip>
        ))}
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

      <Panel>
        {loading ? (
          <div className="flex items-center justify-center gap-2 py-16 text-muted">
            <Loader2 className="size-5 animate-spin" />
            {t("common.loading")}
          </div>
        ) : filtered.length === 0 ? (
          <div className="py-16 text-center text-muted">{t("bookings.empty")}</div>
        ) : (
          <>
            <Table>
              <thead>
                <tr>
                  <Th>{c.colBooking}</Th>
                  <Th>{c.colCustomer}</Th>
                  <Th>{c.colGuard}</Th>
                  <Th>{c.colTime}</Th>
                  <Th>{c.colAmount}</Th>
                  <Th>{c.colStatus}</Th>
                </tr>
              </thead>
              <tbody>
                {visible.map((b) => {
                  const status = b.status as BookingStatusKey;
                  const canAssign = status === "requested" && !b.guard_id;
                  return (
                    <Tr key={b.id} onClick={() => setSelected(b)}>
                      <Td className="font-mono font-semibold text-text-strong">
                        #{b.id.slice(0, 8)}
                      </Td>
                      <Td>
                        {(() => {
                          const r = resolve(b.customer_id);
                          const label = r.name ?? customerNames[b.customer_id] ?? r.label;
                          return <span title={b.customer_id}>{label}</span>;
                        })()}
                      </Td>
                      <Td>
                        {b.guard_id ? (
                          (() => {
                            const r = resolve(b.guard_id);
                            return r.name ? (
                              <span title={b.guard_id}>{r.name}</span>
                            ) : (
                              <span className="font-mono text-muted" title={b.guard_id}>
                                {r.label}
                              </span>
                            );
                          })()
                        ) : canAssign ? (
                          <Button
                            variant="secondary"
                            size="sm"
                            onClick={(e) => {
                              e.stopPropagation();
                              setSelected(b);
                            }}
                          >
                            {c.assign}
                          </Button>
                        ) : (
                          <span className="text-muted">{t("common.none")}</span>
                        )}
                      </Td>
                      <Td className="font-mono text-muted tabular-nums">
                        {fmtTime(b.scheduled_at)}
                      </Td>
                      <Td className="font-mono tabular-nums">{fmtBaht(bookingTotal(b))}</Td>
                      <Td>
                        <Badge tone={STATUS_TONE[status] ?? "gray"}>
                          {c.statusLabel[status] ?? status}
                        </Badge>
                      </Td>
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
          </>
        )}
      </Panel>

      {selected && (
        <BookingDetailModal
          booking={selected}
          customerName={
            resolve(selected.customer_id).name ?? customerNames[selected.customer_id] ?? null
          }
          customerPhone={customerPhones[selected.customer_id] ?? null}
          guardName={selected.guard_id ? resolve(selected.guard_id).name : null}
          approvedGuards={approvedGuards}
          onClose={() => setSelected(null)}
          onAssigned={() => {
            setSelected(null);
            reload();
          }}
        />
      )}
    </div>
  );
}

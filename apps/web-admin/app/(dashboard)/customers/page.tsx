"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  AlertTriangle,
  CalendarRange,
  Loader2,
  RefreshCw,
  Repeat,
  TrendingUp,
  Users,
} from "lucide-react";

import type { components } from "@/api/generated/profile";
import {
  Avatar,
  Badge,
  Button,
  Chip,
  KpiCard,
  KpiGrid,
  PageIntro,
  Pagination,
  Panel,
  SearchField,
  Table,
  Td,
  Th,
  Tr,
} from "@/components/ui";
import { bookingApi, paymentApi, profileApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import { fmtBaht, fmtCappedCount } from "@/lib/format";

import { COPY, customerInitials } from "./copy";
import { CustomerDetailModal } from "./customer-detail-modal";

type CustomerProfileAdmin = components["schemas"]["CustomerProfileAdmin"];

/** Design shows 7 rows per page ("1–7 of 2,418"). The admin list endpoint is capped at 200
 * with no pagination params, so paging + search both slice the fetched list. */
const PAGE_SIZE = 7;

export default function CustomersPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [customers, setCustomers] = useState<CustomerProfileAdmin[]>([]);
  // Platform 30-day aggregates from the report endpoints (net revenue + booking count); null
  // until loaded / on failure → gap chip. These are platform-activity-this-month metrics, NOT
  // all-time customer roll-ups (labels say "(30 วัน)/(30d)").
  const [monthlySpend, setMonthlySpend] = useState<string | null>(null);
  const [monthlyBookings, setMonthlyBookings] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [selected, setSelected] = useState<CustomerProfileAdmin | null>(null);
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);

  const fetchInto = useCallback((alive: () => boolean) => {
    return Promise.all([
      profileApi.GET("/admin/customer-profiles"),
      // Platform 30-day net revenue + booking count (the two activity KPIs). Both reports default
      // to a 30-day window. A failed report sub-call degrades only its own KPI to a gap chip; the
      // customer list still renders (only a profiles failure raises the page error banner).
      paymentApi.GET("/admin/reports/revenue"),
      bookingApi.GET("/admin/reports/bookings"),
    ]).then(([profiles, revenue, bookings]) => {
      if (!alive()) return;
      setHasError(Boolean(profiles.error));
      setCustomers(profiles.error ? [] : (profiles.data?.data ?? []));
      setMonthlySpend(revenue.error ? null : (revenue.data?.data?.total ?? null));
      setMonthlyBookings(bookings.error ? null : (bookings.data?.data?.total ?? null));
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

  // Client-side search over the real fields (name, address, id).
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return customers;
    return customers.filter((cust) =>
      [cust.full_name, cust.address, cust.user_id]
        .filter((v): v is string => Boolean(v))
        .some((v) => v.toLowerCase().includes(q)),
    );
  }, [customers, query]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, pageCount);
  const visible = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);
  const summaryStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const summaryEnd = Math.min(safePage * PAGE_SIZE, filtered.length);

  // Customer count + the two 30-day platform KPIs (net revenue, bookings) are real; repeat-rate
  // has no scalar endpoint and the per-row spend/bookings columns would need per-customer
  // aggregates (or N per-row calls) — those stay honest gap chips, never invented.
  const gap = <Badge tone="gray">{c.awaitingApi}</Badge>;

  return (
    <div>
      <PageIntro
        title={c.title}
        lead={
          loading || hasError
            ? t("customers.subtitle")
            : c.subtitle(fmtCappedCount(customers.length))
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
          {t("customers.error")}
        </div>
      )}

      <KpiGrid>
        <KpiCard
          icon={<Users />}
          label={c.kpiTotal}
          value={loading || hasError ? gap : fmtCappedCount(customers.length)}
        />
        <KpiCard
          icon={<TrendingUp />}
          label={c.kpiSpend}
          value={monthlySpend == null ? gap : fmtBaht(monthlySpend)}
        />
        <KpiCard
          icon={<CalendarRange />}
          label={c.kpiBookings}
          value={monthlyBookings == null ? gap : monthlyBookings.toLocaleString("en-US")}
        />
        <KpiCard icon={<Repeat />} label={c.kpiRepeat} value={gap} />
      </KpiGrid>

      {/* Type chips (individual/company) need a customer_type field profile doesn't store —
          disabled behind the gap chip; "All" is the only truthful state. */}
      <div className="mb-4 flex flex-wrap items-center gap-2.5">
        <Chip active>{t("common.all")}</Chip>
        <Chip disabled className="opacity-50">
          {c.chipIndividual}
        </Chip>
        <Chip disabled className="opacity-50">
          {c.chipCompany}
        </Chip>
        {gap}
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
          <div className="py-16 text-center text-muted">{t("customers.empty")}</div>
        ) : (
          <>
            <Table>
              <thead>
                <tr>
                  <Th>{c.colCustomer}</Th>
                  <Th>{c.colAddress}</Th>
                  <Th>{c.colBookings}</Th>
                  <Th>{c.colSpend}</Th>
                  <Th>{c.colQuality}</Th>
                </tr>
              </thead>
              <tbody>
                {visible.map((cust) => (
                  <Tr key={cust.user_id} onClick={() => setSelected(cust)}>
                    <Td>
                      <div className="flex items-center gap-3">
                        <Avatar>{customerInitials(cust.full_name, cust.user_id)}</Avatar>
                        <div className="min-w-0">
                          <div className="truncate font-semibold text-text-strong">
                            {cust.full_name ?? t("common.none")}
                          </div>
                          <div className="font-mono text-xs text-muted">
                            ID #{cust.user_id.slice(0, 8)}
                          </div>
                        </div>
                      </div>
                    </Td>
                    <Td className="max-w-[220px] truncate text-muted">
                      {cust.address ?? t("common.none")}
                    </Td>
                    {/* per-customer aggregates have no v2 endpoint */}
                    <Td>{gap}</Td>
                    <Td>{gap}</Td>
                    <Td>{gap}</Td>
                  </Tr>
                ))}
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

      {selected && <CustomerDetailModal customer={selected} onClose={() => setSelected(null)} />}
    </div>
  );
}

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
import { profileApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import { fmtCappedCount } from "@/lib/format";

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
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [selected, setSelected] = useState<CustomerProfileAdmin | null>(null);
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);

  const fetchInto = useCallback((alive: () => boolean) => {
    return profileApi.GET("/admin/customer-profiles").then(({ data, error }) => {
      if (!alive()) return;
      setHasError(Boolean(error));
      setCustomers(error ? [] : (data?.data ?? []));
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

  // Only the total count is a real aggregate; spend / bookings / repeat-rate need
  // payment+booking roll-ups no v2 endpoint serves — honest gap chips, never invented.
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
        <KpiCard icon={<TrendingUp />} label={c.kpiSpend} value={gap} />
        <KpiCard icon={<CalendarRange />} label={c.kpiBookings} value={gap} />
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

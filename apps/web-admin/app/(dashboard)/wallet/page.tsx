"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  AlertTriangle,
  CircleDollarSign,
  Loader2,
  Receipt,
  RefreshCw,
  RotateCcw,
} from "lucide-react";

import type { components } from "@/api/generated/payment";
import {
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
import { paymentApi, profileApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import { fmtBaht } from "../bookings/copy";

import { COPY, PAYMENT_STATUSES, type PaymentStatusKey, PAYMENT_TONE } from "./copy";

type Payment = components["schemas"]["Payment"];

const PAGE_SIZE = 9;

export default function WalletPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [payments, setPayments] = useState<Payment[]>([]);
  const [customerNames, setCustomerNames] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [statusFilter, setStatusFilter] = useState<PaymentStatusKey | "all">("all");
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);

  const fetchInto = useCallback((alive: () => boolean) => {
    return Promise.all([
      paymentApi.GET("/admin/payments", { params: { query: {} } }),
      profileApi.GET("/admin/customer-profiles"),
    ])
      .then(([pRes, cRes]) => {
        if (!alive()) return;
        setHasError(Boolean(pRes.error));
        setPayments(pRes.error ? [] : (pRes.data?.data ?? []));
        const names: Record<string, string> = {};
        for (const cust of cRes.data?.data ?? []) {
          if (cust.full_name) names[cust.user_id] = cust.full_name;
        }
        setCustomerNames(names);
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

  // Real derived counts (no money-sum aggregates — those need a reporting endpoint).
  const stats = useMemo(() => {
    let completed = 0;
    let refunded = 0;
    let pendingRefunds = 0;
    for (const p of payments) {
      if (p.status === "completed") completed++;
      if (p.status === "refunded") refunded++;
      if (p.refund_status === "pending") pendingRefunds++;
    }
    return { total: payments.length, completed, refunded, pendingRefunds };
  }, [payments]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return payments.filter((p) => {
      if (statusFilter !== "all" && p.status !== statusFilter) return false;
      if (!q) return true;
      const name = customerNames[p.customer_id] ?? "";
      return [p.id, p.booking_id, name].filter(Boolean).some((v) => String(v).toLowerCase().includes(q));
    });
  }, [payments, statusFilter, query, customerNames]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, pageCount);
  const visible = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);
  const summaryStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const summaryEnd = Math.min(safePage * PAGE_SIZE, filtered.length);

  return (
    <div>
      <PageIntro
        title={c.title}
        lead={loading || hasError ? t("wallet.subtitle") : c.subtitle(String(payments.length))}
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
          {t("wallet.error")}
        </div>
      )}

      <KpiGrid>
        <KpiCard
          icon={<Receipt />}
          label={c.kpiTotal}
          value={loading ? "…" : String(stats.total)}
        />
        <KpiCard
          icon={<CircleDollarSign />}
          label={c.kpiCompleted}
          value={loading ? "…" : String(stats.completed)}
        />
        <KpiCard
          icon={<RotateCcw />}
          label={c.kpiRefunded}
          value={loading ? "…" : String(stats.refunded)}
        />
        <KpiCard
          icon={<AlertTriangle />}
          label={c.kpiPendingRefunds}
          value={loading ? "…" : String(stats.pendingRefunds)}
        />
      </KpiGrid>

      {/* The design's manual refund queue contradicts v2's auto-refund — honest gap note. */}
      <div className="mb-4 flex items-start gap-2 rounded-lg border border-border bg-sunken px-4 py-2.5 text-[12.5px] text-muted">
        <Badge tone="gray">{c.awaitingApi}</Badge>
        <span>{c.refundQueueGap}</span>
      </div>

      <div className="mb-4 flex flex-wrap items-center gap-2.5">
        <Chip active={statusFilter === "all"} onClick={() => setStatusFilter("all")}>
          {t("common.all")}
        </Chip>
        {PAYMENT_STATUSES.map((s) => (
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
          <div className="py-16 text-center text-muted">{t("wallet.empty")}</div>
        ) : (
          <>
            <Table>
              <thead>
                <tr>
                  <Th>{c.colPayment}</Th>
                  <Th>{c.colCustomer}</Th>
                  <Th>{c.colGuard}</Th>
                  <Th>{c.colAmount}</Th>
                  <Th>{c.colStatus}</Th>
                  <Th>{c.colRefund}</Th>
                  <Th>{c.colPaid}</Th>
                </tr>
              </thead>
              <tbody>
                {visible.map((p) => {
                  const status = p.status as PaymentStatusKey;
                  const paidIso = p.paid_at ?? p.created_at;
                  return (
                    <Tr key={p.id}>
                      <Td className="font-mono font-semibold text-text-strong">#{p.id.slice(0, 8)}</Td>
                      <Td>{customerNames[p.customer_id] ?? `ID #${p.customer_id.slice(0, 8)}`}</Td>
                      <Td className="font-mono text-muted">
                        {p.guard_id ? `#${p.guard_id.slice(0, 8)}` : t("common.none")}
                      </Td>
                      <Td className="font-mono tabular-nums">{fmtBaht(Number(p.amount ?? 0))}</Td>
                      <Td>
                        <Badge tone={PAYMENT_TONE[status] ?? "gray"}>
                          {c.statusLabel[status] ?? status}
                        </Badge>
                      </Td>
                      <Td>
                        {p.refund_status === "pending" ? (
                          <Badge tone="amber">{c.refundPending}</Badge>
                        ) : p.refund_status === "processed" ? (
                          <Badge tone="green">{c.refundProcessed}</Badge>
                        ) : (
                          <span className="text-muted">{t("common.none")}</span>
                        )}
                      </Td>
                      <Td className="font-mono text-muted tabular-nums">
                        {new Date(paidIso).toLocaleDateString(lang === "th" ? "th-TH" : "en-GB", {
                          month: "short",
                          day: "numeric",
                        })}
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
    </div>
  );
}

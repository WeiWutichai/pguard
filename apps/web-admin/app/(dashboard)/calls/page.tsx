"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, Loader2, Phone, PhoneMissed, PhoneOff, RefreshCw, Timer } from "lucide-react";

import type { components as CallingComponents } from "@/api/generated/calling";
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
import { callingApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import { useNameResolver } from "@/lib/use-names";

import { CallDetailModal } from "./call-detail-modal";
import { CALL_STATUSES, CALL_TONE, type CallStatusKey, COPY, fmtDuration } from "./copy";

type Call = CallingComponents["schemas"]["Call"];

const PAGE_SIZE = 10;

export default function CallsPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [calls, setCalls] = useState<Call[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [statusFilter, setStatusFilter] = useState<CallStatusKey | "all">("all");
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState<Call | null>(null);

  const fetchInto = useCallback((alive: () => boolean) => {
    return callingApi
      .GET("/admin/calls", { params: { query: {} } })
      .then((callRes) => {
        if (!alive()) return;
        setHasError(Boolean(callRes.error));
        setCalls(callRes.error ? [] : (callRes.data?.data ?? []));
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

  const stats = useMemo(() => {
    let ended = 0;
    let missed = 0;
    let durSum = 0;
    let durN = 0;
    for (const call of calls) {
      if (call.status === "ended") ended++;
      if (call.status === "missed") missed++;
      if (call.duration_seconds && call.duration_seconds > 0) {
        durSum += call.duration_seconds;
        durN++;
      }
    }
    return { total: calls.length, ended, missed, avg: durN ? Math.round(durSum / durN) : 0 };
  }, [calls]);

  // Batch-resolve both sides of every call (caller + callee — a mix of guards + customers) to real
  // display names in one call; the short id remains the fallback/tooltip.
  const resolveIds = useMemo(() => {
    const out: string[] = [];
    for (const call of calls) {
      out.push(call.caller_id, call.callee_id);
    }
    return out;
  }, [calls]);
  const { resolve } = useNameResolver(resolveIds, lang);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return calls.filter((call) => {
      if (statusFilter !== "all" && call.status !== statusFilter) return false;
      if (!q) return true;
      return [call.id, resolve(call.caller_id).label, resolve(call.callee_id).label]
        .some((v) => v.toLowerCase().includes(q));
    });
  }, [calls, statusFilter, query, resolve]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, pageCount);
  const visible = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);
  const summaryStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const summaryEnd = Math.min(safePage * PAGE_SIZE, filtered.length);

  return (
    <div>
      <PageIntro
        title={c.title}
        lead={loading || hasError ? t("calls.subtitle") : c.subtitle(String(calls.length))}
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
          {t("calls.error")}
        </div>
      )}

      <KpiGrid>
        <KpiCard icon={<Phone />} label={c.kpiTotal} value={loading ? "…" : String(stats.total)} />
        <KpiCard icon={<PhoneOff />} label={c.kpiEnded} value={loading ? "…" : String(stats.ended)} />
        <KpiCard
          icon={<PhoneMissed />}
          label={c.kpiMissed}
          value={loading ? "…" : String(stats.missed)}
        />
        <KpiCard
          icon={<Timer />}
          label={c.kpiAvgDuration}
          value={loading ? "…" : fmtDuration(stats.avg)}
        />
      </KpiGrid>

      <div className="mb-4 flex flex-wrap items-center gap-2.5">
        <Chip active={statusFilter === "all"} onClick={() => setStatusFilter("all")}>
          {t("common.all")}
        </Chip>
        {CALL_STATUSES.map((s) => (
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
          <div className="py-16 text-center text-muted">{t("calls.empty")}</div>
        ) : (
          <>
            <Table>
              <thead>
                <tr>
                  <Th>{c.colCall}</Th>
                  <Th>{c.colCaller}</Th>
                  <Th>{c.colCallee}</Th>
                  <Th>{c.colType}</Th>
                  <Th>{c.colStatus}</Th>
                  <Th>{c.colDuration}</Th>
                  <Th>{c.colStarted}</Th>
                </tr>
              </thead>
              <tbody>
                {visible.map((call) => {
                  const status = call.status as CallStatusKey;
                  return (
                    <Tr key={call.id} onClick={() => setSelected(call)}>
                      <Td className="font-mono font-semibold text-text-strong">
                        #{call.id.slice(0, 8)}
                      </Td>
                      <Td title={call.caller_id}>{resolve(call.caller_id).label}</Td>
                      <Td title={call.callee_id}>{resolve(call.callee_id).label}</Td>
                      <Td>
                        <Badge tone="gray">
                          {call.call_type === "video" ? c.typeVideo : c.typeAudio}
                        </Badge>
                      </Td>
                      <Td>
                        <Badge tone={CALL_TONE[status] ?? "gray"}>
                          {c.statusLabel[status] ?? status}
                        </Badge>
                      </Td>
                      <Td className="font-mono tabular-nums">{fmtDuration(call.duration_seconds)}</Td>
                      <Td className="font-mono text-muted tabular-nums">
                        {new Date(call.started_at).toLocaleString(lang === "th" ? "th-TH" : "en-GB", {
                          month: "short",
                          day: "numeric",
                          hour: "2-digit",
                          minute: "2-digit",
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

      {selected && <CallDetailModal call={selected} onClose={() => setSelected(null)} />}
    </div>
  );
}

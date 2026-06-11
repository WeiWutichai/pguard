"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, CircleAlert, CircleCheck, Loader2, RefreshCw, Shield, Star } from "lucide-react";

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

import { COPY } from "./copy";
import { GuardDetailModal } from "./guard-detail-modal";
import { initialsOf, maskAccount } from "./guard-identity";

type GuardProfile = components["schemas"]["GuardProfile"];

/** Design shows 8 rows per page ("1–8 of 384"). Client-side: the admin list endpoint has no
 * pagination params (repo caps it at 200), so paging + search both slice the fetched list. */
const PAGE_SIZE = 8;

export default function GuardsPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];
  const [guards, setGuards] = useState<GuardProfile[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [selected, setSelected] = useState<GuardProfile | null>(null);
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);

  const fetchInto = useCallback((alive: () => boolean) => {
    return profileApi
      .GET("/admin/guard-profiles", { params: { query: { approval_status: "approved" } } })
      .then(({ data, error }) => {
        if (!alive()) return;
        setHasError(Boolean(error));
        setGuards(error ? [] : (data?.data ?? []));
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

  // Client-side search over the real profile fields (id, holder name, workplace, bank).
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return guards;
    return guards.filter((g) =>
      [g.user_id, g.account_name, g.previous_workplace, g.bank_name]
        .filter((v): v is string => Boolean(v))
        .some((v) => v.toLowerCase().includes(q)),
    );
  }, [guards, query]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, pageCount);
  const visible = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);
  const summaryStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const summaryEnd = Math.min(safePage * PAGE_SIZE, filtered.length);

  // Design value for every KPI + the live-status filters/column needs presence + rating +
  // document aggregates that no v2 endpoint serves for this page yet — honest gap chips,
  // never invented numbers.
  const gap = <Badge tone="gray">{c.awaitingApi}</Badge>;

  return (
    <div>
      <PageIntro
        title={c.title}
        lead={loading || hasError ? t("guards.subtitle") : c.subtitle(guards.length)}
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
          {t("guards.error")}
        </div>
      )}

      <KpiGrid>
        <KpiCard icon={<CircleCheck />} label={c.kpiOnline} value={gap} />
        <KpiCard icon={<Shield />} label={c.kpiOnJob} value={gap} />
        <KpiCard icon={<Star />} label={c.kpiAvgRating} value={gap} />
        <KpiCard icon={<CircleAlert />} label={c.kpiDocsExpiring} value={gap} />
      </KpiGrid>

      {/* Filters row — design's live-status chips need presence data this page doesn't
          have; they stay disabled behind the gap chip ("All" remains the truthful state). */}
      <div className="mb-4 flex flex-wrap items-center gap-2.5">
        <Chip active>{t("common.all")}</Chip>
        <Chip disabled className="opacity-50" dot="bg-status-active">
          {c.chipOnline}
        </Chip>
        <Chip disabled className="opacity-50" dot="bg-status-working">
          {c.chipOnJob}
        </Chip>
        <Chip disabled className="opacity-50" dot="bg-status-offline">
          {c.chipOffline}
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
          <div className="py-16 text-center text-muted">{t("guards.empty")}</div>
        ) : (
          <>
            <Table>
              <thead>
                <tr>
                  <Th>{t("guards.col.guard")}</Th>
                  <Th>{c.colStatus}</Th>
                  <Th>{t("guards.col.experience")}</Th>
                  <Th>{t("guards.col.workplace")}</Th>
                  <Th>{t("guards.col.bank")}</Th>
                  <Th aria-label={t("common.view")} />
                </tr>
              </thead>
              <tbody>
                {visible.map((g) => (
                  <Tr key={g.user_id} onClick={() => setSelected(g)}>
                    <Td>
                      <div className="flex items-center gap-3">
                        {/* No live status → no avatar status dot (honest). */}
                        <Avatar>{initialsOf(g.account_name, g.user_id)}</Avatar>
                        <div className="min-w-0">
                          <div className="truncate font-semibold text-text-strong">
                            {g.account_name ?? t("common.none")}
                          </div>
                          <div className="font-mono text-xs text-muted">
                            ID #{g.user_id.slice(0, 8)}
                          </div>
                        </div>
                      </div>
                    </Td>
                    {/* Live status column — presence data isn't served to this page in v2. */}
                    <Td>{gap}</Td>
                    <Td className="font-mono tabular-nums">
                      {g.years_of_experience != null
                        ? `${g.years_of_experience} ${t("applicants.years")}`
                        : t("common.none")}
                    </Td>
                    <Td>{g.previous_workplace ?? t("common.none")}</Td>
                    <Td>
                      {g.bank_name ? (
                        <div>
                          <div>{g.bank_name}</div>
                          <div className="font-mono text-xs text-muted">
                            {maskAccount(g.account_number) ?? t("common.none")}
                          </div>
                        </div>
                      ) : (
                        t("common.none")
                      )}
                    </Td>
                    <Td className="text-right">
                      <Button variant="secondary" size="sm" onClick={() => setSelected(g)}>
                        {t("common.view")}
                      </Button>
                    </Td>
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

      {selected && <GuardDetailModal guard={selected} onClose={() => setSelected(null)} />}
    </div>
  );
}

"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, Loader2, RefreshCw } from "lucide-react";

import type { components } from "@/api/generated/profile";
import {
  Badge,
  Button,
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
import { useNameResolver } from "@/lib/use-names";

import { COPY, kindText, statusText } from "./copy";

type SupportTicket = components["schemas"]["SupportTicket"];

const PAGE_SIZE = 12;

export default function TicketsPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [rows, setRows] = useState<SupportTicket[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);

  const fetchInto = useCallback((alive: () => boolean) => {
    return profileApi
      .GET("/admin/support/tickets", { params: { query: { limit: 200 } } })
      .then(({ data, error }) => {
        if (!alive()) return;
        setHasError(Boolean(error));
        setRows(error ? [] : (data?.data ?? []));
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

  // Resolve each reporter id → display name. Reporters are guards/customers/admins; profile
  // resolves its own tables and merges admin names from identity. An unknown/deleted id falls
  // back to a short id (the default omitted-fallback).
  const resolveIds = useMemo(() => rows.map((r) => r.user_id), [rows]);
  const { resolve } = useNameResolver(resolveIds, lang);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter((r) =>
      [r.message, r.user_id, resolve(r.user_id).label, kindText(r.kind, c)].some((v) =>
        v.toLowerCase().includes(q),
      ),
    );
  }, [rows, query, c, resolve]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, pageCount);
  const visible = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);
  const summaryStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const summaryEnd = Math.min(safePage * PAGE_SIZE, filtered.length);

  return (
    <div>
      <PageIntro title={c.title} lead={loading || hasError ? c.title : c.subtitle(String(rows.length))}>
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
          {c.error}
        </div>
      )}

      <div className="mb-4 flex flex-wrap items-center gap-2.5">
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
          <div className="py-16 text-center text-muted">{c.empty}</div>
        ) : (
          <>
            <Table>
              <thead>
                <tr>
                  <Th>{c.colWhen}</Th>
                  <Th>{c.colReporter}</Th>
                  <Th>{c.colKind}</Th>
                  <Th>{c.colMessage}</Th>
                  <Th>{c.colStatus}</Th>
                </tr>
              </thead>
              <tbody>
                {visible.map((r) => (
                  <Tr key={r.id}>
                    <Td className="font-mono text-muted tabular-nums whitespace-nowrap">
                      {new Date(r.created_at).toLocaleString(lang === "th" ? "th-TH" : "en-GB", {
                        month: "short",
                        day: "numeric",
                        hour: "2-digit",
                        minute: "2-digit",
                      })}
                    </Td>
                    <Td className="text-muted whitespace-nowrap" title={r.user_id}>
                      {resolve(r.user_id).label}
                    </Td>
                    <Td>
                      <Badge tone={r.kind === "problem" ? "amber" : "blue"}>{kindText(r.kind, c)}</Badge>
                    </Td>
                    <Td className="max-w-md text-text-strong">
                      <span className="line-clamp-3 whitespace-pre-wrap">{r.message}</span>
                    </Td>
                    <Td>
                      <Badge tone={r.status === "open" ? "gray" : "green"}>{statusText(r.status, c)}</Badge>
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
    </div>
  );
}

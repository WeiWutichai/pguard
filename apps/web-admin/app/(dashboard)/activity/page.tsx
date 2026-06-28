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

import { actionText, COPY } from "./copy";

type AccessAuditEntry = components["schemas"]["AccessAuditEntry"];

const PAGE_SIZE = 12;

export default function ActivityPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [rows, setRows] = useState<AccessAuditEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);

  const fetchInto = useCallback((alive: () => boolean) => {
    return profileApi
      .GET("/admin/access-audit", { params: { query: { limit: 200 } } })
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

  // Resolve the acting admin id → display name. Admins have no stored name yet (the flagged
  // identity.display_name follow-up), so the resolver OMITS them and we fall back to "Admin #id";
  // once a guard/customer ever appears here it resolves to their real name.
  const resolveIds = useMemo(() => rows.map((r) => r.accessed_by), [rows]);
  const { resolve } = useNameResolver(resolveIds, lang, "admin");

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter((r) =>
      [r.action, r.target ?? "", r.accessed_by, resolve(r.accessed_by).label, actionText(r.action, c)].some(
        (v) => v.toLowerCase().includes(q),
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
      <PageIntro
        title={c.title}
        lead={loading || hasError ? t("activity.subtitle") : c.subtitle(String(rows.length))}
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
          {t("activity.error")}
        </div>
      )}

      {/* Honest scope note: data-access audit, not the full business-action feed. */}
      <div className="mb-4 flex items-start gap-2 rounded-lg border border-border bg-sunken px-4 py-2.5 text-[12.5px] text-muted">
        <Badge tone="gray">{c.awaitingApi}</Badge>
        <span>{c.scopeNote}</span>
      </div>

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
          <div className="py-16 text-center text-muted">{t("activity.empty")}</div>
        ) : (
          <>
            <Table>
              <thead>
                <tr>
                  <Th>{c.colWhen}</Th>
                  <Th>{c.colAdmin}</Th>
                  <Th>{c.colAction}</Th>
                  <Th>{c.colTarget}</Th>
                </tr>
              </thead>
              <tbody>
                {visible.map((r) => (
                  <Tr key={r.id}>
                    <Td className="font-mono text-muted tabular-nums">
                      {new Date(r.accessed_at).toLocaleString(lang === "th" ? "th-TH" : "en-GB", {
                        month: "short",
                        day: "numeric",
                        hour: "2-digit",
                        minute: "2-digit",
                      })}
                    </Td>
                    <Td className="text-muted" title={r.accessed_by}>
                      {resolve(r.accessed_by).label}
                    </Td>
                    <Td className="font-medium text-text-strong">{actionText(r.action, c)}</Td>
                    <Td className="text-muted">{r.target ?? t("common.none")}</Td>
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

"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, Loader2, RefreshCw } from "lucide-react";

import type { components } from "@/api/generated/chat";
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
import { chatApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import { COPY } from "./copy";
import { ConversationModal } from "./conversation-modal";

type AdminConversation = components["schemas"]["AdminConversation"];

const PAGE_SIZE = 10;

export default function ChatPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [convos, setConvos] = useState<AdminConversation[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [selected, setSelected] = useState<AdminConversation | null>(null);
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);

  const fetchInto = useCallback((alive: () => boolean) => {
    return chatApi.GET("/admin/conversations", { params: { query: {} } }).then(({ data, error }) => {
      if (!alive()) return;
      setHasError(Boolean(error));
      setConvos(error ? [] : (data?.data ?? []));
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

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return convos;
    return convos.filter((cv) =>
      [cv.id, cv.request_id, cv.participants ?? "", cv.last_message ?? ""]
        .some((v) => String(v).toLowerCase().includes(q)),
    );
  }, [convos, query]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, pageCount);
  const visible = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);
  const summaryStart = filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const summaryEnd = Math.min(safePage * PAGE_SIZE, filtered.length);

  return (
    <div>
      <PageIntro
        title={c.title}
        lead={loading || hasError ? t("chat.subtitle") : c.subtitle(String(convos.length))}
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
          {t("chat.error")}
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
          <div className="py-16 text-center text-muted">{t("chat.empty")}</div>
        ) : (
          <>
            <Table>
              <thead>
                <tr>
                  <Th>{c.colConversation}</Th>
                  <Th>{c.colParticipants}</Th>
                  <Th>{c.colStatus}</Th>
                  <Th>{c.colLastMessage}</Th>
                  <Th>{c.colMessages}</Th>
                  <Th>{c.colCreated}</Th>
                </tr>
              </thead>
              <tbody>
                {visible.map((cv) => (
                  <Tr key={cv.id} onClick={() => setSelected(cv)}>
                    <Td className="font-mono font-semibold text-text-strong">#{cv.id.slice(0, 8)}</Td>
                    <Td>{cv.participants ?? t("common.none")}</Td>
                    <Td>
                      {cv.request_status ? (
                        <Badge tone="gray">{cv.request_status}</Badge>
                      ) : (
                        <span className="text-muted">{t("common.none")}</span>
                      )}
                    </Td>
                    <Td className="max-w-[260px] truncate text-muted">
                      {cv.last_message ?? t("common.none")}
                    </Td>
                    <Td className="font-mono tabular-nums">{cv.message_count}</Td>
                    <Td className="font-mono text-muted tabular-nums">
                      {new Date(cv.created_at).toLocaleDateString(lang === "th" ? "th-TH" : "en-GB", {
                        month: "short",
                        day: "numeric",
                      })}
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

      {selected && (
        <ConversationModal
          conversationId={selected.id}
          heading={selected.participants ?? `#${selected.request_id.slice(0, 8)}`}
          onClose={() => setSelected(null)}
          onChanged={() => setReloadNonce((n) => n + 1)}
        />
      )}
    </div>
  );
}

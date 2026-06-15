"use client";

import { useEffect, useState } from "react";
import { AlertTriangle, Loader2 } from "lucide-react";

import type { components } from "@/api/generated/chat";
import { Badge, Button, Modal } from "@/components/ui";
import { chatApi } from "@/lib/api";
import { cn } from "@/lib/cn";
import { useLanguage } from "@/lib/i18n";

import { COPY, senderLabel } from "./copy";

type Message = components["schemas"]["Message"];

/** Read-only message pane for one conversation (admin bypasses the participant gate, so
 * `GET /conversations/{id}/messages` works). Messages align by `sender_role` (guard right,
 * customer left), mirroring the mobile/chat UI. Moderation actions have no v2 endpoint → none. */
export function ConversationModal({
  conversationId,
  heading,
  onClose,
}: {
  conversationId: string;
  heading: string;
  onClose: () => void;
}) {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let alive = true;
    chatApi
      .GET("/conversations/{id}/messages", { params: { path: { id: conversationId } } })
      .then(({ data, error }) => {
        if (!alive) return;
        setFailed(Boolean(error));
        // The list is newest-first; show oldest-first in the pane.
        setMessages(error ? [] : [...(data?.data ?? [])].reverse());
        setLoading(false);
      })
      .catch(() => {
        if (!alive) return;
        setFailed(true);
        setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, [conversationId]);

  return (
    <Modal
      open
      onClose={onClose}
      size="lg"
      title={c.detailTitle}
      footer={
        <Button variant="secondary" size="sm" onClick={onClose}>
          {t("common.close")}
        </Button>
      }
    >
      <div className="mb-3 min-w-0">
        <div className="font-mono text-xs text-muted">#{conversationId.slice(0, 8)}</div>
        <div className="mt-0.5 truncate text-sm font-semibold text-text-strong">{heading}</div>
      </div>

      {loading ? (
        <div className="flex items-center justify-center gap-2 py-10 text-muted">
          <Loader2 className="size-5 animate-spin" />
          {c.loadingMessages}
        </div>
      ) : failed ? (
        <div
          role="alert"
          className="flex items-center gap-2 rounded-lg border border-danger/40 bg-danger-bg px-3 py-2 text-[12.5px] text-danger"
        >
          <AlertTriangle className="size-4 flex-none" />
          {t("common.retry")}
        </div>
      ) : messages.length === 0 ? (
        <div className="py-10 text-center text-sm text-muted">{c.noMessages}</div>
      ) : (
        <div className="flex max-h-[55vh] flex-col gap-2 overflow-y-auto pr-1">
          {messages.map((m) => {
            const mine = m.sender_role === "guard"; // align guard right, customer left
            const system = m.message_type === "system";
            if (system) {
              return (
                <div key={m.id} className="my-1 text-center text-[11.5px] text-faint">
                  {m.content ?? "—"}
                </div>
              );
            }
            return (
              <div key={m.id} className={cn("flex", mine ? "justify-end" : "justify-start")}>
                <div
                  className={cn(
                    "max-w-[78%] rounded-2xl px-3.5 py-2 text-sm",
                    mine ? "bg-brand-int text-white" : "bg-sunken text-text-strong",
                  )}
                >
                  <div className="mb-0.5 text-[10.5px] font-semibold opacity-70">
                    {senderLabel(m.sender_role, c)}
                    {m.message_type !== "text" ? ` · ${m.message_type}` : ""}
                  </div>
                  <div className="whitespace-pre-wrap break-words">{m.content ?? "—"}</div>
                  <div className="mt-0.5 text-right font-mono text-[10px] opacity-60">
                    {new Date(m.created_at).toLocaleTimeString(lang === "th" ? "th-TH" : "en-GB", {
                      hour: "2-digit",
                      minute: "2-digit",
                    })}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      <div className="mt-3 flex items-center gap-2 text-[12px] text-muted">
        <Badge tone="gray">{c.awaitingApi}</Badge>
        <span>{c.moderationGap}</span>
      </div>
    </Modal>
  );
}

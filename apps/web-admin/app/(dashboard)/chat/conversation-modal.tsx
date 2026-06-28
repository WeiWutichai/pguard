"use client";

import { useEffect, useMemo, useState } from "react";
import { AlertTriangle, FileWarning, Loader2, PhoneCall, PhoneMissed, Video } from "lucide-react";

import type { components } from "@/api/generated/chat";
import { Badge, Button, Modal } from "@/components/ui";
import { chatApi } from "@/lib/api";
import { cn } from "@/lib/cn";
import { useLanguage } from "@/lib/i18n";
import type { Lang } from "@/lib/lang";
import { useNameResolver } from "@/lib/use-names";

import { type ChatCopy, COPY, senderLabel } from "./copy";

type EnrichedMessage = components["schemas"]["AdminEnrichedMessage"];

/** Read-only ENRICHED message pane for one conversation (admin bypasses the participant gate via
 * `GET /admin/conversations/{id}/messages`). Each row arrives pre-parsed by the chat service into
 * a render `kind` — so the admin sees the real content (image thumbnail, video indicator, parsed
 * call event, text) instead of a raw attachment UUID / call JSON. Messages align by `sender_role`
 * (guard right, customer left). Sender names resolve via the Phase-A useNameResolver. Moderation
 * actions have no v2 endpoint → none. */
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

  const [messages, setMessages] = useState<EnrichedMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let alive = true;
    chatApi
      .GET("/admin/conversations/{id}/messages", { params: { path: { id: conversationId } } })
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

  // Resolve each sender id → display name (guards/customers; admins/unknown fall back to short id).
  const senderIds = useMemo(() => messages.map((m) => m.sender_id), [messages]);
  const { resolve } = useNameResolver(senderIds, lang);

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
            // call-event / system rows render centered (no bubble); media + text use bubbles.
            if (m.kind === "call-event" || m.kind === "system" || m.kind === "unknown") {
              return (
                <div key={m.id} className="my-1 flex items-center justify-center gap-1.5 text-center text-[11.5px] text-faint">
                  {m.kind === "call-event" && m.call_event ? <CallLine event={m.call_event} c={c} /> : null}
                  {m.kind !== "call-event" ? <span>{m.text ?? "—"}</span> : null}
                  <span className="font-mono opacity-60">{fmtTime(m.created_at, lang)}</span>
                </div>
              );
            }
            const mine = m.sender_role === "guard"; // align guard right, customer left
            const name = resolve(m.sender_id).label;
            return (
              <div key={m.id} className={cn("flex", mine ? "justify-end" : "justify-start")}>
                <div
                  className={cn(
                    "max-w-[78%] rounded-2xl px-3.5 py-2 text-sm",
                    mine ? "bg-brand-int text-white" : "bg-sunken text-text-strong",
                  )}
                >
                  <div className="mb-0.5 text-[10.5px] font-semibold opacity-70" title={m.sender_id}>
                    {name} · {senderLabel(m.sender_role, c)}
                  </div>
                  <MessageBody msg={m} c={c} />
                  <div className="mt-0.5 text-right font-mono text-[10px] opacity-60">
                    {fmtTime(m.created_at, lang)}
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

/** Render an enriched message's body by its parsed `kind`. */
function MessageBody({ msg, c }: { msg: EnrichedMessage; c: ChatCopy }) {
  if (msg.kind === "image" || msg.kind === "video") {
    const att = msg.attachment;
    if (!att) {
      // Resolution failed but the raw id is echoed — show that there WAS an attachment.
      return (
        <span className="flex items-center gap-1.5 opacity-90">
          <FileWarning className="size-4 flex-none" />
          {c.attachmentUnavailable}
        </span>
      );
    }
    if (att.is_video || msg.kind === "video") {
      return (
        <a
          href={att.url}
          target="_blank"
          rel="noopener noreferrer"
          className="flex items-center gap-1.5 underline decoration-dotted underline-offset-2"
        >
          <Video className="size-4 flex-none" />
          {c.videoLabel}
        </a>
      );
    }
    return (
      <a href={att.url} target="_blank" rel="noopener noreferrer" className="block">
        {/* eslint-disable-next-line @next/next/no-img-element -- presigned external object URL */}
        <img
          src={att.url}
          alt={c.imageLabel}
          className="mt-0.5 max-h-48 max-w-full rounded-lg object-cover"
          loading="lazy"
        />
      </a>
    );
  }
  // text (and any bubble fallthrough)
  return <div className="whitespace-pre-wrap break-words">{msg.text ?? "—"}</div>;
}

/** Render a parsed call-summary system row: "Voice call · rejected · 1m 12s". */
function CallLine({
  event,
  c,
}: {
  event: NonNullable<EnrichedMessage["call_event"]>;
  c: ChatCopy;
}) {
  const typeLabel = event.call_type === "video" ? c.callVideo : c.callAudio;
  const outcomeLabel =
    event.outcome === "completed" ? c.callCompleted : event.outcome === "missed" ? c.callMissed : c.callRejected;
  const Icon = event.outcome === "missed" || event.outcome === "rejected" ? PhoneMissed : PhoneCall;
  return (
    <span className="flex items-center gap-1.5 font-medium text-muted">
      <Icon className="size-3.5 flex-none" />
      {typeLabel} · {outcomeLabel}
      {event.duration_seconds != null && event.duration_seconds > 0
        ? ` ${c.callDuration(fmtDuration(event.duration_seconds))}`
        : ""}
    </span>
  );
}

function fmtTime(iso: string, lang: Lang): string {
  return new Date(iso).toLocaleTimeString(lang === "th" ? "th-TH" : "en-GB", {
    hour: "2-digit",
    minute: "2-digit",
  });
}

/** Whole-second duration → "1m 12s" / "45s". */
function fmtDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return m > 0 ? `${m}m ${s}s` : `${s}s`;
}

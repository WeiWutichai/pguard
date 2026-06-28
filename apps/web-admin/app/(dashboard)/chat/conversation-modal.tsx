"use client";

import { useEffect, useMemo, useState } from "react";
import {
  AlertTriangle,
  Archive,
  ArchiveRestore,
  FileWarning,
  Loader2,
  PhoneCall,
  PhoneMissed,
  Trash2,
  UserX,
  Video,
} from "lucide-react";

import type { components } from "@/api/generated/chat";
import { Badge, Button, Modal, Textarea } from "@/components/ui";
import { chatApi } from "@/lib/api";
import { cn } from "@/lib/cn";
import { useLanguage } from "@/lib/i18n";
import type { Lang } from "@/lib/lang";
import { useNameResolver } from "@/lib/use-names";

import { type ChatCopy, COPY, senderLabel } from "./copy";

type EnrichedMessage = components["schemas"]["AdminEnrichedMessage"];

/** A pending moderation action awaiting confirmation. Carries everything the confirm dialog and the
 * eventual mutation need. `reason` is collected in the dialog and posted to the audit log. */
type PendingAction =
  | { kind: "redact"; messageId: string }
  | { kind: "archive" }
  | { kind: "reactivate" }
  | { kind: "block"; userId: string; name: string };

/** Read + MODERATE one conversation. Reads the enriched message pane (admin bypasses the
 * participant gate via `GET /admin/conversations/{id}/messages`), renders each row by its parsed
 * `kind` (image/video/call-event/text; redacted rows show as removed), and exposes the Phase-D
 * moderation writes (#136/#137): per-message redact, conversation archive/reactivate, per-sender
 * block — each behind a confirm dialog, audited + idempotent. Sender names resolve via the shared
 * useNameResolver. `onChanged` lets the list refresh after a state-changing action. */
export function ConversationModal({
  conversationId,
  heading,
  onClose,
  onChanged,
}: {
  conversationId: string;
  heading: string;
  onClose: () => void;
  onChanged?: () => void;
}) {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [messages, setMessages] = useState<EnrichedMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);

  // Conversation moderation status is not on the list row → unknown until the admin acts. `null`
  // means unknown (both archive + reactivate offered); after a successful write it reflects truth.
  const [archived, setArchived] = useState<boolean | null>(null);
  const [pending, setPending] = useState<PendingAction | null>(null);

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

  // The distinct senders, for the block menu (a conversation has a guard + a customer).
  const blockTargets = useMemo(() => {
    const seen = new Map<string, string>();
    for (const m of messages) {
      if (m.sender_role === "guard" || m.sender_role === "customer") {
        if (!seen.has(m.sender_id)) seen.set(m.sender_id, resolve(m.sender_id).label);
      }
    }
    return Array.from(seen, ([id, name]) => ({ id, name }));
  }, [messages, resolve]);

  // Apply the confirmed action against the right endpoint; reflect the result locally + refresh list.
  async function runAction(action: PendingAction, reason: string): Promise<boolean> {
    const body = reason.trim() ? { reason: reason.trim() } : undefined;
    if (action.kind === "redact") {
      const { error } = await chatApi.DELETE("/admin/messages/{id}", {
        params: { path: { id: action.messageId } },
        body,
      });
      if (error) return false;
      // Reflect the redaction in place (suppress content, mark removed) — never re-fetch the original.
      setMessages((cur) =>
        cur.map((m) =>
          m.id === action.messageId
            ? { ...m, redacted: true, kind: "redacted", text: null, attachment: null, call_event: null }
            : m,
        ),
      );
      onChanged?.();
      return true;
    }
    if (action.kind === "archive" || action.kind === "reactivate") {
      const next = action.kind === "archive" ? "archived" : "active";
      const { error } = await chatApi.PUT("/admin/conversations/{id}/status", {
        params: { path: { id: conversationId } },
        body: { moderation_status: next, ...(body ?? {}) },
      });
      if (error) return false;
      setArchived(action.kind === "archive");
      onChanged?.();
      return true;
    }
    // block
    const { error } = await chatApi.PUT("/admin/users/{user_id}/block", {
      params: { path: { user_id: action.userId } },
      body,
    });
    if (error) return false;
    onChanged?.();
    return true;
  }

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
      <div className="mb-3 flex items-start justify-between gap-3 min-w-0">
        <div className="min-w-0">
          <div className="font-mono text-xs text-muted">#{conversationId.slice(0, 8)}</div>
          <div className="mt-0.5 truncate text-sm font-semibold text-text-strong">{heading}</div>
        </div>
        {archived === true && <Badge tone="amber">{c.archivedBadge}</Badge>}
      </div>

      {/* --- Moderation toolbar (Phase D) — conversation-level + per-user actions --- */}
      <div className="mb-3 flex flex-wrap items-center gap-2 rounded-lg border border-border bg-sunken px-3 py-2.5">
        <span className="mr-1 text-[12px] font-semibold text-muted">{c.moderationHead}</span>
        {archived === true ? (
          <Button variant="secondary" size="sm" onClick={() => setPending({ kind: "reactivate" })}>
            <ArchiveRestore size={14} />
            {c.reactivateAction}
          </Button>
        ) : (
          <Button variant="secondary" size="sm" onClick={() => setPending({ kind: "archive" })}>
            <Archive size={14} />
            {c.archiveAction}
          </Button>
        )}
        {blockTargets.map((tgt) => (
          <Button
            key={tgt.id}
            variant="danger-ghost"
            size="sm"
            onClick={() => setPending({ kind: "block", userId: tgt.id, name: tgt.name })}
            title={tgt.id}
          >
            <UserX size={14} />
            {c.blockAction}: {tgt.name}
          </Button>
        ))}
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
            const isRedacted = m.redacted || m.kind === "redacted";
            // call-event / system / redacted rows render centered (no bubble); media + text use bubbles.
            if (m.kind === "call-event" || m.kind === "system" || m.kind === "unknown" || (isRedacted && m.kind === "redacted")) {
              return (
                <div key={m.id} className="my-1 flex items-center justify-center gap-1.5 text-center text-[11.5px] text-faint">
                  {m.kind === "call-event" && m.call_event ? <CallLine event={m.call_event} c={c} /> : null}
                  {isRedacted ? (
                    <span className="italic">{c.redactedBody}</span>
                  ) : m.kind !== "call-event" ? (
                    <span>{m.text ?? "—"}</span>
                  ) : null}
                  <span className="font-mono opacity-60">{fmtTime(m.created_at, lang)}</span>
                </div>
              );
            }
            const mine = m.sender_role === "guard"; // align guard right, customer left
            const name = resolve(m.sender_id).label;
            return (
              <div key={m.id} className={cn("group flex", mine ? "justify-end" : "justify-start")}>
                <div className="flex items-end gap-1.5">
                  {/* Redact action sits beside the bubble; hidden until hover, suppressed once redacted. */}
                  {mine && !isRedacted && (
                    <RedactButton c={c} onClick={() => setPending({ kind: "redact", messageId: m.id })} />
                  )}
                  <div
                    className={cn(
                      "max-w-[78%] rounded-2xl px-3.5 py-2 text-sm",
                      isRedacted
                        ? "border border-dashed border-border bg-transparent text-faint italic"
                        : mine
                          ? "bg-brand-int text-white"
                          : "bg-sunken text-text-strong",
                    )}
                  >
                    <div className="mb-0.5 flex items-center gap-1.5 text-[10.5px] font-semibold opacity-70" title={m.sender_id}>
                      {name} · {senderLabel(m.sender_role, c)}
                      {isRedacted && <Badge tone="red">{c.redactedBadge}</Badge>}
                    </div>
                    {isRedacted ? (
                      <div className="whitespace-pre-wrap break-words">{c.redactedBody}</div>
                    ) : (
                      <MessageBody msg={m} c={c} />
                    )}
                    <div className="mt-0.5 text-right font-mono text-[10px] opacity-60">
                      {fmtTime(m.created_at, lang)}
                    </div>
                  </div>
                  {!mine && !isRedacted && (
                    <RedactButton c={c} onClick={() => setPending({ kind: "redact", messageId: m.id })} />
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {pending && (
        <ConfirmAction
          action={pending}
          c={c}
          onCancel={() => setPending(null)}
          onConfirm={(reason) => runAction(pending, reason)}
          onDone={() => setPending(null)}
        />
      )}
    </Modal>
  );
}

/** A small hover-revealed redact button beside a message bubble. */
function RedactButton({ c, onClick }: { c: ChatCopy; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      title={c.redactAction}
      aria-label={c.redactAction}
      className="flex size-7 flex-none items-center justify-center rounded-md text-faint opacity-0 transition-opacity hover:bg-danger-bg hover:text-danger group-hover:opacity-100"
    >
      <Trash2 size={14} />
    </button>
  );
}

/** Confirm dialog for a moderation action — a nested Modal with an optional audited-reason field.
 * Runs the mutation on confirm; on failure shows an inline error and stays open for a retry. */
function ConfirmAction({
  action,
  c,
  onCancel,
  onConfirm,
  onDone,
}: {
  action: PendingAction;
  c: ChatCopy;
  onCancel: () => void;
  onConfirm: (reason: string) => Promise<boolean>;
  onDone: () => void;
}) {
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(false);

  const { title, body, danger } = describe(action, c);

  async function submit() {
    setBusy(true);
    setError(false);
    const ok = await onConfirm(reason);
    setBusy(false);
    if (ok) onDone();
    else setError(true);
  }

  return (
    <Modal
      open
      onClose={busy ? () => {} : onCancel}
      title={title}
      footer={
        <>
          <Button variant="secondary" size="sm" onClick={onCancel} disabled={busy}>
            {c.cancel}
          </Button>
          <Button variant={danger ? "danger" : "primary"} size="sm" onClick={submit} disabled={busy}>
            {busy && <Loader2 className="size-4 animate-spin" />}
            {busy ? c.working : c.confirm}
          </Button>
        </>
      }
    >
      <p className="mb-3 text-sm text-text">{body}</p>
      <label className="mb-1.5 block text-[12.5px] font-semibold text-muted">{c.reasonLabel}</label>
      <Textarea
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        placeholder={c.reasonPlaceholder}
        disabled={busy}
        rows={2}
      />
      {error && (
        <div
          role="alert"
          className="mt-3 flex items-center gap-2 rounded-lg border border-danger/40 bg-danger-bg px-3 py-2 text-[12.5px] text-danger"
        >
          <AlertTriangle className="size-4 flex-none" />
          {c.actionFailed}
        </div>
      )}
    </Modal>
  );
}

/** Localized title/body + destructive flag for a pending action. */
function describe(action: PendingAction, c: ChatCopy): { title: string; body: string; danger: boolean } {
  switch (action.kind) {
    case "redact":
      return { title: c.confirmRedactTitle, body: c.confirmRedactBody, danger: true };
    case "archive":
      return { title: c.confirmArchiveTitle, body: c.confirmArchiveBody, danger: false };
    case "reactivate":
      return { title: c.confirmReactivateTitle, body: c.confirmReactivateBody, danger: false };
    case "block":
      return { title: c.confirmBlockTitle, body: c.confirmBlockBody(action.name), danger: true };
  }
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

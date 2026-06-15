"use client";

import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import { AlertTriangle, Bell, Clock, Loader2, RefreshCw, Send, Shield, Users } from "lucide-react";

import type { components as NotificationComponents } from "@/api/generated/notification";
import {
  Badge,
  Button,
  Chip,
  Field,
  Input,
  PageIntro,
  Panel,
  PanelBody,
  PanelHead,
  Textarea,
} from "@/components/ui";
import { notificationApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import {
  type AudienceKey,
  AUDIENCES,
  type BroadcastStatusKey,
  COPY,
  fmtCount,
  STATUS_TONE,
} from "./copy";

type Broadcast = NotificationComponents["schemas"]["Broadcast"];
type AudienceCounts = NotificationComponents["schemas"]["AudienceCounts"];

const AUDIENCE_ICON: Record<AudienceKey, ReactNode> = {
  all: <Bell size={18} />,
  guards: <Shield size={18} />,
  customers: <Users size={18} />,
};

export default function BroadcastPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [broadcasts, setBroadcasts] = useState<Broadcast[]>([]);
  const [counts, setCounts] = useState<AudienceCounts | null>(null);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);

  // composer
  const [audience, setAudience] = useState<AudienceKey>("all");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [scheduleMode, setScheduleMode] = useState<"now" | "later">("now");
  const [scheduledAt, setScheduledAt] = useState("");
  const [posting, setPosting] = useState(false);
  const [feedback, setFeedback] = useState<string | null>(null);

  const fetchInto = useCallback((alive: () => boolean) => {
    return Promise.all([
      notificationApi.GET("/admin/broadcasts", { params: { query: { limit: 100 } } }),
      notificationApi.GET("/admin/audience-counts"),
    ])
      .then(([listRes, countRes]) => {
        if (!alive()) return;
        setHasError(Boolean(listRes.error));
        setBroadcasts(listRes.error ? [] : (listRes.data?.data ?? []));
        setCounts(countRes.error ? null : (countRes.data?.data ?? null));
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

  const countFor = (a: AudienceKey): number | null =>
    counts ? (a === "all" ? counts.all : a === "guards" ? counts.guards : counts.customers) : null;

  const sentCount = useMemo(
    () => broadcasts.filter((b) => b.status === "sent").length,
    [broadcasts],
  );

  const canSubmit = title.trim().length > 0 && body.trim().length > 0 && !posting;

  async function submit(mode: "now" | "draft" | "scheduled") {
    if (!canSubmit) return;
    setFeedback(null);
    let iso: string | undefined;
    if (mode === "scheduled") {
      const ts = scheduledAt ? new Date(scheduledAt).getTime() : NaN;
      if (Number.isNaN(ts) || ts <= Date.now()) {
        setFeedback(c.scheduleNeeded);
        return;
      }
      iso = new Date(ts).toISOString();
    }
    setPosting(true);
    const res = await notificationApi.POST("/admin/broadcasts", {
      body: { audience, title: title.trim(), body: body.trim(), mode, scheduled_at: iso },
    });
    setPosting(false);
    if (res.error) {
      setHasError(true);
      setFeedback(t("broadcast.error"));
      return;
    }
    const recipients = res.data?.data?.recipient_count ?? 0;
    setFeedback(
      mode === "now" ? c.sentOk(fmtCount(recipients)) : mode === "draft" ? c.draftOk : c.scheduledOk,
    );
    setTitle("");
    setBody("");
    setScheduledAt("");
    setScheduleMode("now");
    reload();
  }

  return (
    <div>
      <PageIntro
        title={c.title}
        lead={loading || hasError ? t("broadcast.subtitle") : c.subtitle(String(sentCount))}
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
          {t("broadcast.error")}
        </div>
      )}

      <div className="grid items-start gap-5 lg:grid-cols-[1.3fr_1fr]">
        {/* ---- compose ---- */}
        <Panel>
          <PanelHead title={c.composeHead} />
          <PanelBody>
            <Field label={c.audienceLabel}>
              <div className="flex flex-col gap-2">
                {AUDIENCES.map((a) => {
                  const on = audience === a;
                  return (
                    <button
                      key={a}
                      type="button"
                      onClick={() => setAudience(a)}
                      aria-pressed={on}
                      className={[
                        "flex items-center gap-3 rounded-xl border px-4 py-3 text-left transition-colors",
                        on
                          ? "border-brand-int bg-sunken text-text-strong"
                          : "border-border bg-surface text-muted hover:bg-sunken",
                      ].join(" ")}
                    >
                      <span
                        className={[
                          "flex size-9 flex-none items-center justify-center rounded-[11px]",
                          on ? "bg-brand-int text-white" : "bg-sunken text-muted",
                        ].join(" ")}
                      >
                        {AUDIENCE_ICON[a]}
                      </span>
                      <span className="text-sm font-semibold">{c.audienceName[a]}</span>
                      <span className="ml-auto font-mono text-xs text-muted tabular-nums">
                        {fmtCount(countFor(a))}
                      </span>
                    </button>
                  );
                })}
                {/* Per-user target isn't in the v2 contract — honest gap, never faked. */}
                <div className="flex items-center gap-2 rounded-xl border border-dashed border-border px-4 py-2.5 text-xs text-muted">
                  <Badge tone="gray">{t("gap.endpoints")}</Badge>
                  <span>{c.specificUserGap}</span>
                </div>
              </div>
            </Field>

            <Field label={c.titleLabel}>
              <Input
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder={c.titlePlaceholder}
                maxLength={120}
              />
            </Field>

            <Field label={c.bodyLabel}>
              <Textarea
                rows={3}
                value={body}
                onChange={(e) => setBody(e.target.value)}
                placeholder={c.bodyPlaceholder}
                maxLength={500}
              />
            </Field>

            <Field label={c.scheduleLabel} className="mb-0">
              <div className="flex flex-wrap items-center gap-3">
                <div className="flex gap-2">
                  <Chip active={scheduleMode === "now"} onClick={() => setScheduleMode("now")}>
                    {c.sendNow}
                  </Chip>
                  <Chip active={scheduleMode === "later"} onClick={() => setScheduleMode("later")}>
                    {c.scheduleLater}
                  </Chip>
                </div>
                {scheduleMode === "later" && (
                  <Input
                    type="datetime-local"
                    value={scheduledAt}
                    onChange={(e) => setScheduledAt(e.target.value)}
                    className="flex-1"
                  />
                )}
              </div>
            </Field>
          </PanelBody>

          <div className="flex items-center justify-end gap-2.5 border-t border-border px-5 py-3.5">
            {feedback && <span className="mr-auto text-xs text-muted">{feedback}</span>}
            <Button
              variant="secondary"
              size="sm"
              disabled={!canSubmit}
              onClick={() => submit("draft")}
            >
              {c.saveDraft}
            </Button>
            <Button
              size="sm"
              disabled={!canSubmit}
              onClick={() => submit(scheduleMode === "later" ? "scheduled" : "now")}
            >
              {posting ? (
                <Loader2 className="size-4 animate-spin" />
              ) : scheduleMode === "later" ? (
                <Clock size={15} />
              ) : (
                <Send size={15} />
              )}
              {scheduleMode === "later" ? c.scheduleBtn : c.sendBtn}
            </Button>
          </div>
        </Panel>

        {/* ---- preview + history ---- */}
        <div className="flex flex-col gap-5">
          <Panel>
            <PanelHead title={c.previewHead} />
            <PanelBody>
              <div className="flex justify-center rounded-xl bg-sunken p-6">
                <div className="flex w-[280px] gap-3 rounded-2xl bg-surface p-3.5 shadow-lg">
                  <span className="flex size-9 flex-none items-center justify-center rounded-[10px] bg-green-900 text-white">
                    <Bell size={18} />
                  </span>
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-[13.5px] font-semibold text-text-strong">
                      {title.trim() || c.titleLabel}
                    </div>
                    <div className="mt-0.5 line-clamp-3 text-[12.5px] text-muted">
                      {body.trim() || c.bodyPlaceholder}
                    </div>
                    <div className="mt-1 text-[10.5px] text-faint">{c.previewAppName}</div>
                  </div>
                </div>
              </div>
            </PanelBody>
          </Panel>

          <Panel>
            <PanelHead title={c.historyHead} />
            {loading ? (
              <div className="flex items-center justify-center gap-2 py-12 text-muted">
                <Loader2 className="size-5 animate-spin" />
                {t("common.loading")}
              </div>
            ) : broadcasts.length === 0 ? (
              <div className="py-12 text-center text-muted">{t("broadcast.empty")}</div>
            ) : (
              <ul>
                {broadcasts.map((b) => {
                  const status = b.status as BroadcastStatusKey;
                  const when = b.sent_at ?? b.scheduled_at ?? b.created_at;
                  return (
                    <li
                      key={b.id}
                      className="flex items-center gap-3 border-b border-border px-4 py-3 last:border-b-0"
                    >
                      <span className="flex size-9 flex-none items-center justify-center rounded-[10px] bg-sunken text-muted">
                        <Send size={16} />
                      </span>
                      <div className="min-w-0 flex-1">
                        <div className="truncate text-[13.5px] font-semibold text-text-strong">
                          {b.title}
                        </div>
                        <div className="mt-0.5 text-[11.5px] text-muted">
                          {c.audienceName[b.audience as AudienceKey] ?? b.audience}
                          {b.recipient_count > 0 &&
                            ` · ${c.recipients(fmtCount(b.recipient_count))}`}
                        </div>
                      </div>
                      <Badge tone={STATUS_TONE[status] ?? "gray"}>
                        {c.statusLabel[status] ?? status}
                      </Badge>
                      <span className="ml-1 font-mono text-[11.5px] text-faint tabular-nums">
                        {new Date(when).toLocaleDateString(lang === "th" ? "th-TH" : "en-GB", {
                          month: "short",
                          day: "numeric",
                        })}
                      </span>
                    </li>
                  );
                })}
              </ul>
            )}
          </Panel>
        </div>
      </div>
    </div>
  );
}

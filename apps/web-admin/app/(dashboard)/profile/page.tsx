"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { KeyRound, Loader2, LogOut, ShieldCheck } from "lucide-react";

import type { components } from "@/api/generated/profile";
import { identityApi, profileApi } from "@/lib/api";
import { useAuth } from "@/components/auth-provider";
import { useLanguage } from "@/lib/i18n";
import {
  Badge,
  Button,
  Field,
  Input,
  Modal,
  PageIntro,
  Panel,
  PanelBody,
  PanelHead,
  Toggle,
} from "@/components/ui";

import { COPY as ACTIVITY_COPY, actionText } from "../activity/copy";
import { COPY } from "./copy";

type AccessAuditEntry = components["schemas"]["AccessAuditEntry"];

/** Cap of self-activity rows shown in the profile card (full log lives at /activity). */
const SELF_ACTIVITY_LIMIT = 6;

/**
 * Admin profile — account, security & sessions. HONESTY RULE (mirrors settings): the only live
 * surfaces are the identity card (role + user_id from /auth/me via useAuth) and the real
 * "sign out everywhere" action (POST /auth/revoke-all). Every designed surface with no v2 API —
 * editable name/email, change-password, 2FA, the per-session device list, API tokens, the
 * personal activity feed — renders its structure with a gray gap chip + disabled controls,
 * never fake values.
 */
export default function ProfilePage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];
  const ac = ACTIVITY_COPY[lang];
  const user = useAuth();
  const router = useRouter();

  const [confirmOpen, setConfirmOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(false);

  // ---- My recent activity (PDPA §30 data-access audit, filtered to self) ----
  // The access-audit endpoint has no `accessed_by` server filter, so fetch a recent page and keep
  // only this admin's own rows. Best-effort enrichment — never blocks the page.
  const [activity, setActivity] = useState<AccessAuditEntry[]>([]);
  const [activityLoading, setActivityLoading] = useState(true);
  const [activityError, setActivityError] = useState(false);

  const loadActivity = useCallback(
    (alive: () => boolean) =>
      profileApi
        .GET("/admin/access-audit", { params: { query: { limit: 200 } } })
        .then(({ data, error: err }) => {
          if (!alive()) return;
          setActivityError(Boolean(err));
          setActivity(err ? [] : (data?.data ?? []));
          setActivityLoading(false);
        })
        .catch(() => {
          if (!alive()) return;
          setActivityError(true);
          setActivityLoading(false);
        }),
    [],
  );

  useEffect(() => {
    let alive = true;
    void loadActivity(() => alive);
    return () => {
      alive = false;
    };
  }, [loadActivity]);

  const myActivity = useMemo(
    () => activity.filter((r) => r.accessed_by === user.user_id).slice(0, SELF_ACTIVITY_LIMIT),
    [activity, user.user_id],
  );

  async function signOutEverywhere() {
    setBusy(true);
    setError(false);
    // Revokes ALL sessions incl. this one + clears our cookies → always bounce to /login.
    // On a transient failure, surface it (the session may still be valid) rather than silently
    // pretending we signed out.
    const res = await identityApi.POST("/auth/revoke-all", {});
    if (res.error) {
      setBusy(false);
      setError(true);
      return;
    }
    router.replace("/login");
    router.refresh();
  }

  const gapChip = <Badge tone="gray">{t("gap.endpoints")}</Badge>;

  return (
    <div className="mx-auto max-w-5xl">
      <PageIntro title={c.title} lead={c.subtitle} />

      <div className="grid items-start gap-5 lg:grid-cols-[300px_1fr]">
        {/* ---- identity card (REAL: role + id) ---- */}
        <div className="flex flex-col gap-[18px]">
          <Panel>
            <PanelBody className="flex flex-col items-center py-7 text-center">
              <span className="mb-4 flex size-[88px] items-center justify-center rounded-full bg-green-50 text-green-800 dark:bg-green-800 dark:text-green-100">
                <ShieldCheck size={36} />
              </span>
              <div className="text-lg font-semibold text-text-strong">{t("shell.adminName")}</div>
              <div className="mt-3">
                <Badge tone="green">{user.role}</Badge>
              </div>
              <div className="mt-3.5 break-all font-mono text-[11.5px] text-faint">
                {user.user_id}
              </div>
            </PanelBody>
          </Panel>

          {/* My recent activity — LIVE: PDPA §30 data-access audit filtered to this admin. */}
          <Panel>
            <PanelHead title={c.activityHead} sub={c.activitySub}>
              <Link href="/activity" className="text-[12.5px] font-medium text-brand-int hover:underline">
                {c.viewAll}
              </Link>
            </PanelHead>
            <PanelBody className="py-1">
              {activityLoading ? (
                <div className="flex items-center gap-2 py-3 text-[12.5px] text-muted">
                  <Loader2 className="size-4 animate-spin" />
                  {c.activityLoading}
                </div>
              ) : activityError ? (
                <p className="py-3 text-[12.5px] text-danger" role="alert">
                  {c.activityError}
                </p>
              ) : myActivity.length === 0 ? (
                <p className="py-3 text-[12.5px] text-muted">{c.activityEmpty}</p>
              ) : (
                <ul className="divide-y divide-border">
                  {myActivity.map((r) => (
                    <li key={r.id} className="flex items-start gap-2 py-2.5">
                      <div className="min-w-0 flex-1">
                        <div className="truncate text-[13px] font-medium text-text-strong">
                          {actionText(r.action, ac)}
                        </div>
                        {r.target ? (
                          <div className="truncate text-[11.5px] text-muted">{r.target}</div>
                        ) : null}
                      </div>
                      <time className="flex-none font-mono text-[11px] text-faint tabular-nums">
                        {new Date(r.accessed_at).toLocaleString(lang === "th" ? "th-TH" : "en-GB", {
                          month: "short",
                          day: "numeric",
                          hour: "2-digit",
                          minute: "2-digit",
                        })}
                      </time>
                    </li>
                  ))}
                </ul>
              )}
              <p className="mt-1 pb-1 text-[11px] text-faint">{c.gapActivity}</p>
            </PanelBody>
          </Panel>
        </div>

        {/* ---- right column ---- */}
        <div className="flex flex-col gap-[18px]">
          {/* Account details — name/email/password edit has no v2 endpoint. */}
          <Panel>
            <PanelHead title={c.accountHead} sub={c.accountSub}>
              {gapChip}
            </PanelHead>
            <PanelBody>
              <div className="grid gap-x-4 sm:grid-cols-2">
                <Field label={c.nameLabel}>
                  <Input disabled aria-label={c.nameLabel} />
                </Field>
                <Field label={c.emailLabel}>
                  <Input disabled aria-label={c.emailLabel} />
                </Field>
              </div>
              <p className="mb-3 text-[12px] text-muted">{c.gapAccountEdit}</p>
              <div className="flex gap-2.5">
                <Button variant="secondary" disabled>
                  <KeyRound size={15} />
                  {c.changePassword}
                </Button>
                <Button disabled>{c.save}</Button>
              </div>
            </PanelBody>
          </Panel>

          {/* 2FA — not in v2. */}
          <Panel>
            <PanelHead title={c.twoFaHead} sub={c.twoFaSub}>
              {gapChip}
            </PanelHead>
            <PanelBody className="flex items-center">
              <span className="text-[12.5px] text-muted">{c.gap2fa}</span>
              <span className="ml-auto">
                <Toggle checked={false} disabled onChange={() => {}} aria-label={c.twoFaHead} />
              </span>
            </PanelBody>
          </Panel>

          {/* Session security — REAL "sign out everywhere"; the per-device list is a gap. */}
          <Panel>
            <PanelHead title={c.sessionsHead}>
              <Button variant="danger-ghost" size="sm" onClick={() => setConfirmOpen(true)}>
                <LogOut size={15} />
                {c.signOutAll}
              </Button>
            </PanelHead>
            <PanelBody>
              <p className="text-sm text-text-strong">{c.signOutAllSub}</p>
              <div className="mt-3 flex items-start gap-2 rounded-lg border border-dashed border-border bg-sunken px-4 py-3 text-[12.5px] text-muted">
                <Badge tone="gray">{t("gap.endpoints")}</Badge>
                <span>{c.gapSessions}</span>
              </div>
              {error && (
                <p role="alert" className="mt-3 text-sm text-danger">
                  {c.signOutError}
                </p>
              )}
            </PanelBody>
          </Panel>

          {/* API tokens — not in v2. */}
          <Panel>
            <PanelHead title={c.tokensHead}>
              {gapChip}
              <Button variant="secondary" size="sm" disabled>
                {c.generate}
              </Button>
            </PanelHead>
            <PanelBody>
              <p className="text-[12.5px] text-muted">{c.gapTokens}</p>
            </PanelBody>
          </Panel>
        </div>
      </div>

      <Modal
        open={confirmOpen}
        onClose={() => setConfirmOpen(false)}
        title={c.signOutConfirmTitle}
      >
        <p className="text-sm text-muted">{c.signOutConfirmBody}</p>
        <div className="mt-5 flex justify-end gap-2.5">
          <Button variant="secondary" onClick={() => setConfirmOpen(false)} disabled={busy}>
            {c.cancel}
          </Button>
          <Button variant="danger-ghost" onClick={signOutEverywhere} disabled={busy}>
            <LogOut size={15} />
            {c.confirm}
          </Button>
        </div>
      </Modal>
    </div>
  );
}

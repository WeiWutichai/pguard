"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { KeyRound, LogOut, ShieldCheck } from "lucide-react";

import { identityApi } from "@/lib/api";
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

import { COPY } from "./copy";

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
  const user = useAuth();
  const router = useRouter();

  const [confirmOpen, setConfirmOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(false);

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

          {/* My recent activity — no per-admin feed in v2. */}
          <Panel>
            <PanelHead title={c.activityHead}>{gapChip}</PanelHead>
            <PanelBody>
              <p className="text-[12.5px] text-muted">{c.gapActivity}</p>
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

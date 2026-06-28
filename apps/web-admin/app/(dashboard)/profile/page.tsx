"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { KeyRound, Loader2, LogOut, ShieldCheck } from "lucide-react";

import type { components } from "@/api/generated/profile";
import { identityApi, profileApi } from "@/lib/api";
import { useAuth } from "@/components/auth-provider";
import { useLanguage } from "@/lib/i18n";
import { sha256Hex } from "@/lib/hash";
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

/** Minimum new-password length (mirrors a sensible PIN floor; the wire shape is SHA-256 hex). */
const MIN_PASSWORD_LEN = 6;

/** Lightweight email shape check (server is authoritative; this is a fast client guard). */
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Admin profile — account, security & sessions.
 *
 * LIVE (#144): the account card LOADS display_name + email from GET /auth/me and SAVES via
 * PUT /auth/me (display_name 1–120 + optional email; a 409 `EMAIL_TAKEN` is surfaced inline);
 * the password is changed via PUT /auth/password (current + new PIN, SHA-256-hashed client-side
 * — the server then revokes every OTHER session and clears THIS browser's cookies, so we bounce
 * to /login on success). Plus the identity card (role + id from useAuth) and "sign out everywhere"
 * (POST /auth/revoke-all). HONEST GAPS (no v2 endpoint — Phase D): 2FA, the per-session device
 * list, API tokens. The personal feed is the PDPA §30 data-access audit, filtered to self.
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

  // ---- Account details (#144) — LIVE: load from /auth/me, save via PUT /auth/me. ----
  // Seed from the AuthProvider's /auth/me (already resolved server-side), then re-fetch so an edit
  // made in another tab is reflected. The fields are fully controlled from load onward.
  const [name, setName] = useState(user.display_name ?? "");
  const [email, setEmail] = useState(user.email ?? "");
  const [accountLoading, setAccountLoading] = useState(true);
  const [accountLoadError, setAccountLoadError] = useState(false);
  const [saving, setSaving] = useState(false);
  const [saveMsg, setSaveMsg] = useState<{ kind: "ok" | "err"; text: string } | null>(null);
  const [fieldErr, setFieldErr] = useState<{ name?: string; email?: string }>({});

  useEffect(() => {
    let alive = true;
    identityApi
      .GET("/auth/me", {})
      .then(({ data, error: err }) => {
        if (!alive) return;
        if (err || !data?.data) {
          setAccountLoadError(true);
        } else {
          setName(data.data.display_name ?? "");
          setEmail(data.data.email ?? "");
        }
        setAccountLoading(false);
      })
      .catch(() => {
        if (!alive) return;
        setAccountLoadError(true);
        setAccountLoading(false);
      });
    return () => {
      alive = false;
    };
  }, []);

  async function saveAccount() {
    setSaveMsg(null);
    const trimmedName = name.trim();
    const trimmedEmail = email.trim();
    const errs: { name?: string; email?: string } = {};
    if (trimmedName.length === 0) errs.name = c.nameRequired;
    if (trimmedEmail.length > 0 && !EMAIL_RE.test(trimmedEmail)) errs.email = c.emailInvalid;
    setFieldErr(errs);
    if (errs.name || errs.email) return;

    setSaving(true);
    const res = await identityApi.PUT("/auth/me", {
      // Empty email clears it server-side (omit/null/"" → cleared per the contract).
      body: { display_name: trimmedName, email: trimmedEmail || null },
    });
    setSaving(false);
    if (res.error) {
      // 409 EMAIL_TAKEN → inline on the email field; everything else → generic save error.
      if (res.response?.status === 409) {
        setFieldErr((p) => ({ ...p, email: c.emailTaken }));
        return;
      }
      setSaveMsg({ kind: "err", text: c.saveError });
      return;
    }
    // Reflect the saved values + nudge the shell (sidebar/topbar read display_name from /auth/me).
    if (res.data?.data) {
      setName(res.data.data.display_name ?? "");
      setEmail(res.data.data.email ?? "");
    }
    setSaveMsg({ kind: "ok", text: c.savedOk });
    router.refresh();
  }

  // ---- Change password (#144) — LIVE: PUT /auth/password (current + new, SHA-256 hex). ----
  const [pwOpen, setPwOpen] = useState(false);
  const [pwCurrent, setPwCurrent] = useState("");
  const [pwNew, setPwNew] = useState("");
  const [pwConfirm, setPwConfirm] = useState("");
  const [pwBusy, setPwBusy] = useState(false);
  const [pwError, setPwError] = useState<string | null>(null);

  function openPw() {
    setPwCurrent("");
    setPwNew("");
    setPwConfirm("");
    setPwError(null);
    setPwOpen(true);
  }

  async function submitPassword() {
    setPwError(null);
    if (pwNew.length < MIN_PASSWORD_LEN) {
      setPwError(c.pwTooShort);
      return;
    }
    if (pwNew !== pwConfirm) {
      setPwError(c.pwMismatch);
      return;
    }
    setPwBusy(true);
    // SHA-256-hash both client-side (the identity contract: current_password + new_pin_hash are the
    // 64-hex SHA-256 of the PIN; the raw PIN never leaves the browser).
    const [currentHash, newHash] = await Promise.all([sha256Hex(pwCurrent), sha256Hex(pwNew)]);
    const res = await identityApi.PUT("/auth/password", {
      body: { current_password: currentHash, new_pin_hash: newHash },
    });
    setPwBusy(false);
    if (res.error) {
      // Wrong current password → generic 401 (no enumeration); show the specific hint.
      setPwError(res.response?.status === 401 ? c.pwWrongCurrent : c.pwError);
      return;
    }
    // Server cleared THIS browser's cookies + revoked other sessions → re-authenticate.
    router.replace("/login");
    router.refresh();
  }

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
  const displayName = name.trim() || t("shell.adminName");

  return (
    <div className="mx-auto max-w-5xl">
      <PageIntro title={c.title} lead={c.subtitle} />

      <div className="grid items-start gap-5 lg:grid-cols-[300px_1fr]">
        {/* ---- identity card (REAL: name + role + id) ---- */}
        <div className="flex flex-col gap-[18px]">
          <Panel>
            <PanelBody className="flex flex-col items-center py-7 text-center">
              <span className="mb-4 flex size-[88px] items-center justify-center rounded-full bg-green-50 text-green-800 dark:bg-green-800 dark:text-green-100">
                <ShieldCheck size={36} />
              </span>
              <div className="text-lg font-semibold text-text-strong">{displayName}</div>
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
          {/* Account details — LIVE: load/save name + email via /auth/me. */}
          <Panel>
            <PanelHead title={c.accountHead} sub={c.accountSub} />
            <PanelBody>
              {accountLoading ? (
                <div className="flex items-center gap-2 py-3 text-[12.5px] text-muted">
                  <Loader2 className="size-4 animate-spin" />
                  {c.accountLoading}
                </div>
              ) : accountLoadError ? (
                <p className="py-3 text-[12.5px] text-danger" role="alert">
                  {c.accountLoadError}
                </p>
              ) : (
                <>
                  <div className="grid gap-x-4 sm:grid-cols-2">
                    <Field label={c.nameLabel} error={fieldErr.name}>
                      <Input
                        value={name}
                        onChange={(e) => {
                          setName(e.target.value);
                          setFieldErr((p) => ({ ...p, name: undefined }));
                          setSaveMsg(null);
                        }}
                        placeholder={c.namePlaceholder}
                        maxLength={120}
                        error={Boolean(fieldErr.name)}
                        aria-label={c.nameLabel}
                      />
                    </Field>
                    <Field label={c.emailLabel} error={fieldErr.email}>
                      <Input
                        type="email"
                        value={email}
                        onChange={(e) => {
                          setEmail(e.target.value);
                          setFieldErr((p) => ({ ...p, email: undefined }));
                          setSaveMsg(null);
                        }}
                        placeholder={c.emailPlaceholder}
                        error={Boolean(fieldErr.email)}
                        aria-label={c.emailLabel}
                      />
                    </Field>
                  </div>
                  <div className="flex items-center gap-2.5">
                    {saveMsg && (
                      <span
                        className={
                          "mr-auto text-xs " +
                          (saveMsg.kind === "ok" ? "text-success" : "text-danger")
                        }
                        role={saveMsg.kind === "err" ? "alert" : undefined}
                      >
                        {saveMsg.text}
                      </span>
                    )}
                    <Button variant="secondary" onClick={openPw} disabled={saving}>
                      <KeyRound size={15} />
                      {c.changePassword}
                    </Button>
                    <Button onClick={saveAccount} disabled={saving}>
                      {saving ? <Loader2 className="size-4 animate-spin" /> : null}
                      {c.save}
                    </Button>
                  </div>
                </>
              )}
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

      {/* ---- change-password modal (#144) ---- */}
      <Modal open={pwOpen} onClose={() => setPwOpen(false)} title={c.pwTitle}>
        <p className="mb-4 text-sm text-muted">{c.pwIntro}</p>
        <Field label={c.pwCurrentLabel}>
          <Input
            type="password"
            autoComplete="current-password"
            value={pwCurrent}
            onChange={(e) => setPwCurrent(e.target.value)}
            aria-label={c.pwCurrentLabel}
          />
        </Field>
        <Field label={c.pwNewLabel} hint={c.pwHint}>
          <Input
            type="password"
            autoComplete="new-password"
            value={pwNew}
            onChange={(e) => setPwNew(e.target.value)}
            aria-label={c.pwNewLabel}
          />
        </Field>
        <Field label={c.pwConfirmLabel} className="mb-0">
          <Input
            type="password"
            autoComplete="new-password"
            value={pwConfirm}
            onChange={(e) => setPwConfirm(e.target.value)}
            aria-label={c.pwConfirmLabel}
          />
        </Field>
        {pwError && (
          <p role="alert" className="mt-3 text-sm text-danger">
            {pwError}
          </p>
        )}
        <div className="mt-5 flex justify-end gap-2.5">
          <Button variant="secondary" onClick={() => setPwOpen(false)} disabled={pwBusy}>
            {c.cancel}
          </Button>
          <Button onClick={submitPassword} disabled={pwBusy || !pwCurrent || !pwNew || !pwConfirm}>
            {pwBusy ? <Loader2 className="size-4 animate-spin" /> : <KeyRound size={15} />}
            {c.pwSubmit}
          </Button>
        </div>
      </Modal>

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

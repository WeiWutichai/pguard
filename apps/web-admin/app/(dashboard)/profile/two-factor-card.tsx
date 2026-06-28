"use client";

import { useState } from "react";
import { Copy, Loader2, ShieldCheck } from "lucide-react";

import { identityApi } from "@/lib/api";
import { sha256Hex } from "@/lib/hash";
import { Badge, Button, Field, Input, Modal, Panel, PanelBody, PanelHead, QrCode } from "@/components/ui";

import type { ProfileCopy } from "./copy";

/**
 * Two-factor (TOTP) enrollment + disable (#144). Two-step flow against identity:
 *   POST /auth/2fa/setup   → { otpauth_uri, secret }  (render QR; 409 ⇒ already enabled)
 *   POST /auth/2fa/enable  → { recovery_codes[] }      (shown ONCE)
 *   POST /auth/2fa/disable → confirm with a TOTP code OR the account password
 *
 * The contract has no read endpoint for 2FA state (no flag on /auth/me), so state is "unknown"
 * until the admin acts: a 409 on setup resolves it to "enabled"; a successful enable/disable
 * flips it. We surface that honestly rather than guessing.
 */

type TwoFaState = "unknown" | "on" | "off";

export function TwoFactorCard({ c }: { c: ProfileCopy }) {
  const [state, setState] = useState<TwoFaState>("unknown");
  const [flash, setFlash] = useState<string | null>(null);

  // setup modal
  const [setupOpen, setSetupOpen] = useState(false);
  const [provisioning, setProvisioning] = useState(false);
  const [otpauthUri, setOtpauthUri] = useState("");
  const [secret, setSecret] = useState("");
  const [code, setCode] = useState("");
  const [enabling, setEnabling] = useState(false);
  const [setupError, setSetupError] = useState<string | null>(null);

  // recovery-codes modal
  const [recoveryOpen, setRecoveryOpen] = useState(false);
  const [recoveryCodes, setRecoveryCodes] = useState<string[]>([]);
  const [codesCopied, setCodesCopied] = useState(false);

  // disable modal
  const [disableOpen, setDisableOpen] = useState(false);
  const [disableCode, setDisableCode] = useState("");
  const [disablePw, setDisablePw] = useState("");
  const [disabling, setDisabling] = useState(false);
  const [disableError, setDisableError] = useState<string | null>(null);

  async function openSetup() {
    setSetupError(null);
    setCode("");
    setOtpauthUri("");
    setSecret("");
    setSetupOpen(true);
    setProvisioning(true);
    const res = await identityApi.POST("/auth/2fa/setup", {});
    setProvisioning(false);
    if (res.error) {
      // 409 ⇒ already enabled: reflect that and close the setup.
      if (res.response?.status === 409) {
        setState("on");
        setSetupOpen(false);
        setFlash(c.twoFaAlreadyOn);
        return;
      }
      setSetupError(c.twoFaSetupError);
      return;
    }
    setOtpauthUri(res.data?.data?.otpauth_uri ?? "");
    setSecret(res.data?.data?.secret ?? "");
  }

  async function confirmEnable() {
    setSetupError(null);
    const trimmed = code.trim();
    if (!/^\d{6}$/.test(trimmed)) {
      setSetupError(c.twoFaWrongCode);
      return;
    }
    setEnabling(true);
    const res = await identityApi.POST("/auth/2fa/enable", { body: { code: trimmed } });
    setEnabling(false);
    if (res.error) {
      setSetupError(res.response?.status === 401 ? c.twoFaWrongCode : c.twoFaSetupError);
      return;
    }
    setState("on");
    setSetupOpen(false);
    setFlash(c.twoFaEnabledNow);
    setRecoveryCodes(res.data?.data?.recovery_codes ?? []);
    setCodesCopied(false);
    setRecoveryOpen(true);
  }

  function openDisable() {
    setDisableError(null);
    setDisableCode("");
    setDisablePw("");
    setDisableOpen(true);
  }

  async function confirmDisable() {
    setDisableError(null);
    const codeTrim = disableCode.trim();
    const pwTrim = disablePw.trim();
    if (!codeTrim && !pwTrim) {
      setDisableError(c.twoFaDisableError);
      return;
    }
    setDisabling(true);
    // Per the contract: EITHER a live TOTP code OR the account password (SHA-256 hex, login shape).
    const body: { code?: string | null; password?: string | null } = {};
    if (codeTrim) body.code = codeTrim;
    if (pwTrim) body.password = await sha256Hex(pwTrim);
    const res = await identityApi.POST("/auth/2fa/disable", { body });
    setDisabling(false);
    if (res.error) {
      setDisableError(c.twoFaDisableError);
      return;
    }
    setState("off");
    setDisableOpen(false);
    setFlash(c.twoFaDisabledNow);
  }

  async function copyCodes() {
    try {
      await navigator.clipboard.writeText(recoveryCodes.join("\n"));
      setCodesCopied(true);
    } catch {
      /* clipboard blocked — the codes are still visible to copy by hand */
    }
  }

  const stateBadge =
    state === "on" ? (
      <Badge tone="green">{c.twoFaOn}</Badge>
    ) : state === "off" ? (
      <Badge tone="gray">{c.twoFaOff}</Badge>
    ) : (
      <Badge tone="gray">{c.twoFaUnknown}</Badge>
    );

  return (
    <Panel>
      <PanelHead title={c.twoFaHead} sub={c.twoFaSub}>
        {stateBadge}
      </PanelHead>
      <PanelBody className="flex flex-wrap items-center gap-3">
        <span className="text-[12.5px] text-muted">
          {state === "on" ? c.twoFaSub : c.twoFaScanIntro.split(" — ")[0]}
        </span>
        <span className="ml-auto flex items-center gap-2.5">
          {flash && <span className="text-xs text-success">{flash}</span>}
          {state === "on" ? (
            <Button variant="danger-ghost" size="sm" onClick={openDisable}>
              {c.twoFaDisable}
            </Button>
          ) : (
            <Button variant="secondary" size="sm" onClick={openSetup}>
              <ShieldCheck size={15} />
              {c.twoFaEnable}
            </Button>
          )}
        </span>
      </PanelBody>

      {/* ---- setup (QR + confirm) ---- */}
      <Modal open={setupOpen} onClose={() => setSetupOpen(false)} title={c.twoFaSetupTitle}>
        <p className="mb-4 text-sm text-muted">{c.twoFaScanIntro}</p>
        {provisioning ? (
          <div className="flex items-center justify-center gap-2 py-10 text-sm text-muted">
            <Loader2 className="size-5 animate-spin" />
          </div>
        ) : otpauthUri ? (
          <>
            <div className="mb-4 flex justify-center">
              <div className="rounded-lg border border-border bg-white p-3">
                <QrCode value={otpauthUri} size={188} />
              </div>
            </div>
            <Field label={c.twoFaSecretLabel} className="mb-4">
              <Input value={secret} readOnly className="font-mono tracking-wide" aria-label={c.twoFaSecretLabel} />
            </Field>
            <Field label={c.twoFaCodeLabel} hint={c.twoFaCodeHint} className="mb-0">
              <Input
                inputMode="numeric"
                autoComplete="one-time-code"
                maxLength={6}
                value={code}
                onChange={(e) => {
                  setCode(e.target.value.replace(/\D/g, ""));
                  setSetupError(null);
                }}
                placeholder="123456"
                className="font-mono tracking-[0.3em]"
                aria-label={c.twoFaCodeLabel}
              />
            </Field>
          </>
        ) : null}
        {setupError && (
          <p role="alert" className="mt-3 text-sm text-danger">
            {setupError}
          </p>
        )}
        <div className="mt-5 flex justify-end gap-2.5">
          <Button variant="secondary" onClick={() => setSetupOpen(false)} disabled={enabling}>
            {c.cancel}
          </Button>
          <Button onClick={confirmEnable} disabled={enabling || provisioning || code.length !== 6}>
            {enabling ? <Loader2 className="size-4 animate-spin" /> : <ShieldCheck size={15} />}
            {c.twoFaConfirm}
          </Button>
        </div>
      </Modal>

      {/* ---- recovery codes (shown ONCE) ---- */}
      <Modal
        open={recoveryOpen}
        onClose={() => setRecoveryOpen(false)}
        title={c.twoFaRecoveryTitle}
      >
        <p className="mb-2 text-sm text-muted">{c.twoFaRecoveryIntro}</p>
        <div className="mb-3 flex items-start gap-2 rounded-lg border border-warning-bg bg-warning-bg px-4 py-3 text-[12.5px] text-amber-700 dark:text-amber-300">
          <Badge tone="amber">!</Badge>
          <span>{c.twoFaRecoveryWarn}</span>
        </div>
        <ul className="mb-4 grid grid-cols-2 gap-2 rounded-lg border border-border bg-sunken p-4 font-mono text-[13px] text-text-strong">
          {recoveryCodes.map((rc) => (
            <li key={rc} className="tabular-nums tracking-wide">
              {rc}
            </li>
          ))}
        </ul>
        <div className="flex items-center justify-end gap-2.5">
          {codesCopied && <span className="mr-auto text-xs text-success">{c.tokenCopied}</span>}
          <Button variant="secondary" onClick={copyCodes}>
            <Copy size={15} />
            {c.twoFaCopyCodes}
          </Button>
          <Button onClick={() => setRecoveryOpen(false)}>{c.twoFaRecoveryDone}</Button>
        </div>
      </Modal>

      {/* ---- disable ---- */}
      <Modal open={disableOpen} onClose={() => setDisableOpen(false)} title={c.twoFaDisableTitle}>
        <p className="mb-4 text-sm text-muted">{c.twoFaDisableIntro}</p>
        <Field label={c.twoFaCodeLabel}>
          <Input
            inputMode="numeric"
            autoComplete="one-time-code"
            maxLength={6}
            value={disableCode}
            onChange={(e) => {
              setDisableCode(e.target.value.replace(/\D/g, ""));
              setDisableError(null);
            }}
            placeholder="123456"
            className="font-mono tracking-[0.3em]"
            aria-label={c.twoFaCodeLabel}
          />
        </Field>
        <Field label={c.pwCurrentLabel} className="mb-0">
          <Input
            type="password"
            autoComplete="current-password"
            value={disablePw}
            onChange={(e) => {
              setDisablePw(e.target.value);
              setDisableError(null);
            }}
            aria-label={c.pwCurrentLabel}
          />
        </Field>
        {disableError && (
          <p role="alert" className="mt-3 text-sm text-danger">
            {disableError}
          </p>
        )}
        <div className="mt-5 flex justify-end gap-2.5">
          <Button variant="secondary" onClick={() => setDisableOpen(false)} disabled={disabling}>
            {c.cancel}
          </Button>
          <Button
            variant="danger-ghost"
            onClick={confirmDisable}
            disabled={disabling || (!disableCode.trim() && !disablePw.trim())}
          >
            {disabling ? <Loader2 className="size-4 animate-spin" /> : null}
            {c.twoFaDisableConfirm}
          </Button>
        </div>
      </Modal>
    </Panel>
  );
}

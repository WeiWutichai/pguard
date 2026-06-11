"use client";

import { useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { LogOut, Plus } from "lucide-react";

import { identityApi } from "@/lib/api";
import { useAuth } from "@/components/auth-provider";
import { useLanguage } from "@/lib/i18n";
import { cn } from "@/lib/cn";
import {
  Badge,
  Button,
  Field,
  Input,
  PageIntro,
  Panel,
  PanelBody,
  PanelHead,
  Select,
  Toggle,
} from "@/components/ui";

import { COPY } from "./copy";

/**
 * Settings — rebuilt to the hi-fi mockup (sticky set-nav rail + paneled sections with
 * Field/Toggle rows). HONESTY RULE: every designed section here (company profile, payment
 * gateways, SMS/FCM, storage & security, team & roles) has NO backing v2 admin-settings
 * API — each renders its designed structure with a gray "รอ API / Awaiting API" chip and
 * disabled controls, never fake values. The only live logic is preserved from the previous
 * page: account/session info from /auth/me, the TH/EN language toggle (locale cookie), and
 * the cookie-revoking logout.
 */
export default function SettingsPage() {
  const { lang, setLang, t } = useLanguage();
  const c = COPY[lang];
  const user = useAuth(); // server-resolved /auth/me (no extra fetch, no localStorage)
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [active, setActive] = useState("account");

  async function logout() {
    setBusy(true);
    // Best-effort server revoke (clears httpOnly auth cookies); CSRF marker added by lib/api.ts.
    // ALWAYS bounce to /login even if the revoke fails — the cookies may already be invalid, so a
    // guaranteed local sign-out is the safe behavior (mirrors topbar.tsx).
    try {
      await identityApi.POST("/auth/logout", {});
    } finally {
      router.replace("/login");
      router.refresh();
    }
  }

  // Design's set-nav (220px rail). "Storage" and "ความปลอดภัย/Security" are separate links
  // in the mockup but the spec'd panel is combined — both anchor to #storage.
  const NAV = [
    { id: "account", target: "account", label: t("settings.account") },
    { id: "company", target: "company", label: c.navCompany },
    { id: "payments", target: "payments", label: c.navPayments },
    { id: "sms", target: "sms", label: c.navSms },
    { id: "storage", target: "storage", label: c.navStorage },
    { id: "security", target: "storage", label: c.navSecurity },
    { id: "team", target: "team", label: c.navTeam },
  ] as const;

  const gapChip = <Badge tone="gray">{c.awaitingApi}</Badge>;

  return (
    <div className="mx-auto max-w-5xl">
      <PageIntro title={t("settings.title")} lead={t("settings.subtitle")} />

      <div className="flex items-start gap-6">
        {/* set-nav — sticky 220px text rail (active = green-50/green-800, dark brand-int). */}
        <nav
          aria-label={t("settings.title")}
          className="sticky top-0 hidden w-[220px] flex-none flex-col gap-0.5 self-start lg:flex"
        >
          {NAV.map((item) => (
            <a
              key={item.id}
              href={`#${item.target}`}
              onClick={() => setActive(item.id)}
              className={cn(
                "rounded-sm px-3 py-2 text-[13.5px] font-medium text-muted hover:bg-sunken",
                active === item.id &&
                  "bg-green-50 font-semibold text-green-800 dark:bg-brand-int/12 dark:text-brand-int",
              )}
            >
              {item.label}
            </a>
          ))}
        </nav>

        <div className="min-w-0 flex-1 space-y-4">
          {/* Account & session — REAL data/logic kept from the previous page. */}
          <section id="account" className="scroll-mt-5">
            <Panel>
              <PanelHead title={t("settings.account")} sub={t("settings.session")} />
              <PanelBody className="py-1">
                <KvRow label={t("settings.role")} end>
                  <span className="text-sm font-medium text-text-strong">{user.role}</span>
                </KvRow>
                <KvRow label={t("settings.userId")} end>
                  <span className="break-all font-mono text-xs text-muted">{user.user_id}</span>
                </KvRow>
                <KvRow label={t("settings.language")} end>
                  <PillSelect
                    aria-label={t("settings.language")}
                    value={lang}
                    onChange={setLang}
                    options={[
                      { value: "th", label: "ไทย" },
                      { value: "en", label: "EN" },
                    ]}
                  />
                </KvRow>
                <KvRow label={t("settings.session")} end>
                  <Button variant="danger-ghost" size="sm" disabled={busy} onClick={logout}>
                    <LogOut size={15} />
                    {t("header.logout")}
                  </Button>
                </KvRow>
              </PanelBody>
            </Panel>
          </section>

          {/* Company profile — no /v1 admin settings endpoint → structure + gap chip. */}
          <section id="company" className="scroll-mt-5">
            <Panel>
              <PanelHead title={c.companyTitle} sub={c.companySub}>
                {gapChip}
              </PanelHead>
              <PanelBody>
                <div className="grid gap-x-4 sm:grid-cols-2">
                  <Field label={c.companyName}>
                    <Input disabled aria-label={c.companyName} />
                  </Field>
                  <Field label={c.taxId}>
                    <Input disabled aria-label={c.taxId} />
                  </Field>
                </div>
                <Field label={c.address} className="mb-0">
                  <Input disabled aria-label={c.address} />
                </Field>
              </PanelBody>
            </Panel>
          </section>

          {/* Payment gateways — no payment-config admin endpoint → disabled toggles. */}
          <section id="payments" className="scroll-mt-5">
            <Panel>
              <PanelHead title={c.payTitle} sub={c.paySub}>
                {gapChip}
              </PanelHead>
              <PanelBody className="py-1">
                <KvRow label={c.payPromptpay} sub={c.payPromptpaySub} end>
                  <Toggle checked disabled onChange={noop} aria-label={c.payPromptpay} />
                </KvRow>
                <KvRow label={c.payCard} sub={c.payCardSub} end>
                  <Toggle checked disabled onChange={noop} aria-label={c.payCard} />
                </KvRow>
                <KvRow label={c.payWallet} sub={c.payWalletSub} end>
                  <Toggle checked disabled onChange={noop} aria-label={c.payWallet} />
                </KvRow>
              </PanelBody>
            </Panel>
          </section>

          {/* SMS & notifications — provider/secret config has no v2 API (secrets are never
              exposed via API anyway) → disabled select + empty masked field. */}
          <section id="sms" className="scroll-mt-5">
            <Panel>
              <PanelHead title={c.smsTitle} sub={c.smsSub}>
                {gapChip}
              </PanelHead>
              <PanelBody className="py-1">
                <KvRow label={c.smsProvider} sub={c.smsProviderSub}>
                  <Select disabled aria-label={c.smsProvider} defaultValue="" className="max-w-60">
                    <option value="">—</option>
                    <option>INET (สหไอที)</option>
                    <option>Twilio</option>
                    <option>ThaiBulkSMS</option>
                  </Select>
                </KvRow>
                <KvRow label={c.fcmKey} sub={c.fcmKeySub}>
                  <Input type="password" disabled aria-label={c.fcmKey} className="max-w-[300px]" />
                </KvRow>
              </PanelBody>
            </Panel>
          </section>

          {/* Storage & security — bucket/JWT/OTP TTL/rate-limit/CORS are deploy-time env
              config with no admin endpoint → designed controls, disabled, no fake values. */}
          <section id="storage" className="scroll-mt-5">
            <Panel>
              <PanelHead title={c.storageTitle} sub={c.storageSub}>
                {gapChip}
              </PanelHead>
              <PanelBody className="py-1">
                <KvRow label={c.bucket}>
                  <Input disabled aria-label={c.bucket} className="max-w-[300px]" />
                </KvRow>
                <KvRow label={c.jwtExpiry}>
                  <PillSelect
                    aria-label={c.jwtExpiry}
                    value="1h"
                    disabled
                    options={[
                      { value: "15m", label: "15m" },
                      { value: "1h", label: "1h" },
                      { value: "24h", label: "24h" },
                    ]}
                  />
                </KvRow>
                <KvRow label={c.otpTtl}>
                  <PillSelect
                    aria-label={c.otpTtl}
                    value="5 min"
                    disabled
                    options={[
                      { value: "5 min", label: "5 min" },
                      { value: "10 min", label: "10 min" },
                    ]}
                  />
                </KvRow>
                <KvRow label={c.rateLimit} sub={c.rateLimitSub}>
                  <Input
                    disabled
                    inputMode="numeric"
                    aria-label={c.rateLimit}
                    className="max-w-[120px]"
                  />
                </KvRow>
                <KvRow label={c.cors}>
                  <Input disabled aria-label={c.cors} className="max-w-[300px]" />
                </KvRow>
              </PanelBody>
            </Panel>
          </section>

          {/* Team & roles — the design's 4-member list is mock data; v2 has no admin-list/
              role API, so no rows are faked. */}
          <section id="team" className="scroll-mt-5">
            <Panel>
              <PanelHead title={c.teamTitle} sub={c.teamSub}>
                {gapChip}
              </PanelHead>
              <PanelBody>
                <p className="text-sm text-muted">{c.teamGap}</p>
                <Button variant="secondary" size="sm" disabled className="mt-3.5">
                  <Plus size={15} />
                  {c.invite}
                </Button>
              </PanelBody>
            </Panel>
          </section>

          {/* Footer actions — designed Cancel/Save pair; disabled until a settings API
              exists (nothing on this page is saveable; the language toggle applies live). */}
          <div className="flex items-center justify-end gap-2.5 pt-0.5">
            {gapChip}
            <Button variant="secondary" disabled>
              {c.cancel}
            </Button>
            <Button disabled>{c.save}</Button>
          </div>
        </div>
      </div>
    </div>
  );
}

function noop() {}

/** Design's `.kv` row — 200px label column (13.5px/600 + 11.5px muted sub) | control. */
function KvRow({
  label,
  sub,
  end,
  children,
}: {
  label: string;
  sub?: string;
  /** Right-align the control (the design puts toggles/values at the row end). */
  end?: boolean;
  children: ReactNode;
}) {
  return (
    <div className="flex items-center gap-4 border-b border-border py-3.5 last:border-b-0">
      <div className="w-[200px] flex-none">
        <div className="text-[13.5px] font-semibold text-text-strong">{label}</div>
        {sub ? <div className="text-[11.5px] text-muted">{sub}</div> : null}
      </div>
      <div className={cn("flex min-w-0 flex-1 items-center gap-2.5", end && "justify-end")}>
        {children}
      </div>
    </div>
  );
}

/** Design's `.pillsel` — sunken segmented pills; active pill lifts to surface + sh-xs.
 * Page-local (no ui/ primitive yet; ui/ is single-writer for other agents). */
function PillSelect<T extends string>({
  options,
  value,
  onChange,
  disabled,
  "aria-label": ariaLabel,
}: {
  options: readonly { value: T; label: string }[];
  value: T;
  onChange?: (next: T) => void;
  disabled?: boolean;
  "aria-label"?: string;
}) {
  return (
    <div className="inline-flex gap-1 rounded-full bg-sunken p-[3px]" role="group" aria-label={ariaLabel}>
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          disabled={disabled}
          aria-pressed={o.value === value}
          onClick={onChange ? () => onChange(o.value) : undefined}
          className={cn(
            "cursor-pointer rounded-full border-0 px-3 py-[5px] font-latin text-[12.5px] font-semibold transition-colors duration-150 disabled:cursor-not-allowed",
            o.value === value ? "bg-surface text-text-strong shadow-xs" : "text-muted",
          )}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

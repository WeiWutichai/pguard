"use client";

import { useCallback, useEffect, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { Loader2, LogOut, Plus, Save } from "lucide-react";

import { identityApi, profileApi } from "@/lib/api";
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
  Textarea,
  Toggle,
} from "@/components/ui";

import { COPY } from "./copy";

/**
 * Settings — rebuilt to the hi-fi mockup (sticky set-nav rail + paneled sections with
 * Field/Toggle rows). LIVE now: the COMPANY PROFILE form is wired to profile
 * GET/PUT /admin/org-settings (load + save), plus the account/session card, the TH/EN
 * language toggle (locale cookie), and the cookie-revoking logout.
 * HONESTY RULE (the rest): SMS/FCM + Storage/Security are deploy-time env/secret config with
 * no editable endpoint (and secrets are never surfaced) → a "managed via env" note. Payment
 * channels + Team/roles need stores that don't exist in v2 yet → honest gap notes. None fakes
 * a value.
 */
export default function SettingsPage() {
  const { lang, setLang, t } = useLanguage();
  const c = COPY[lang];
  const user = useAuth(); // server-resolved /auth/me (no extra fetch, no localStorage)
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [active, setActive] = useState("account");

  // ---- Company profile (live: GET/PUT /admin/org-settings) ----
  const [companyName, setCompanyName] = useState("");
  const [taxId, setTaxId] = useState("");
  const [address, setAddress] = useState("");
  const [orgUpdatedAt, setOrgUpdatedAt] = useState<string | null>(null);
  const [orgLoading, setOrgLoading] = useState(true);
  const [orgLoadError, setOrgLoadError] = useState(false);
  const [orgSaving, setOrgSaving] = useState(false);
  const [orgFeedback, setOrgFeedback] = useState<{ kind: "ok" | "err"; text: string } | null>(null);

  const loadOrg = useCallback((alive: () => boolean) => {
    return profileApi
      .GET("/admin/org-settings")
      .then(({ data, error }) => {
        if (!alive()) return;
        if (error || !data?.data) {
          setOrgLoadError(Boolean(error));
          setOrgLoading(false);
          return;
        }
        setCompanyName(data.data.company_name ?? "");
        setTaxId(data.data.tax_id ?? "");
        setAddress(data.data.address ?? "");
        setOrgUpdatedAt(data.data.updated_at ?? null);
        setOrgLoadError(false);
        setOrgLoading(false);
      })
      .catch(() => {
        if (!alive()) return;
        setOrgLoadError(true);
        setOrgLoading(false);
      });
  }, []);

  useEffect(() => {
    let alive = true;
    void loadOrg(() => alive);
    return () => {
      alive = false;
    };
  }, [loadOrg]);

  async function saveOrg() {
    setOrgSaving(true);
    setOrgFeedback(null);
    // Send blanks as null so an emptied field clears (the backend treats all fields optional).
    const res = await profileApi.PUT("/admin/org-settings", {
      body: {
        company_name: companyName.trim() || null,
        tax_id: taxId.trim() || null,
        address: address.trim() || null,
      },
    });
    setOrgSaving(false);
    if (res.error || !res.data?.data) {
      setOrgFeedback({ kind: "err", text: c.companySaveError });
      return;
    }
    setCompanyName(res.data.data.company_name ?? "");
    setTaxId(res.data.data.tax_id ?? "");
    setAddress(res.data.data.address ?? "");
    setOrgUpdatedAt(res.data.data.updated_at ?? null);
    setOrgFeedback({ kind: "ok", text: c.companySaved });
  }

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

          {/* Company profile — LIVE via profile GET/PUT /admin/org-settings. */}
          <section id="company" className="scroll-mt-5">
            <Panel>
              <PanelHead title={c.companyTitle} sub={c.companySub}>
                {orgUpdatedAt ? (
                  <span className="text-[11.5px] text-muted">
                    {c.lastSaved}:{" "}
                    {new Date(orgUpdatedAt).toLocaleString(lang === "th" ? "th-TH" : "en-GB", {
                      dateStyle: "medium",
                      timeStyle: "short",
                    })}
                  </span>
                ) : null}
              </PanelHead>
              <PanelBody>
                {orgLoading ? (
                  <div className="flex items-center gap-2 py-2 text-sm text-muted">
                    <Loader2 className="size-4 animate-spin" />
                    {c.companyLoading}
                  </div>
                ) : (
                  <>
                    {orgLoadError && (
                      <p role="alert" className="mb-3 text-sm text-danger">
                        {c.companyLoadError}
                      </p>
                    )}
                    <div className="grid gap-x-4 sm:grid-cols-2">
                      <Field label={c.companyName}>
                        <Input
                          value={companyName}
                          onChange={(e) => setCompanyName(e.target.value)}
                          placeholder={c.companyNamePlaceholder}
                          maxLength={500}
                          aria-label={c.companyName}
                        />
                      </Field>
                      <Field label={c.taxId} hint={c.taxIdHint}>
                        <Input
                          value={taxId}
                          onChange={(e) => setTaxId(e.target.value)}
                          inputMode="numeric"
                          maxLength={20}
                          aria-label={c.taxId}
                        />
                      </Field>
                    </div>
                    <Field label={c.address} className="mb-0">
                      <Textarea
                        rows={2}
                        value={address}
                        onChange={(e) => setAddress(e.target.value)}
                        placeholder={c.addressPlaceholder}
                        maxLength={500}
                        aria-label={c.address}
                      />
                    </Field>
                  </>
                )}
              </PanelBody>
              <div className="flex items-center justify-end gap-2.5 border-t border-border px-5 py-3.5">
                {orgFeedback && (
                  <span
                    className={cn(
                      "mr-auto text-xs",
                      orgFeedback.kind === "ok" ? "text-success" : "text-danger",
                    )}
                  >
                    {orgFeedback.text}
                  </span>
                )}
                <Button size="sm" onClick={saveOrg} disabled={orgLoading || orgSaving}>
                  {orgSaving ? <Loader2 className="size-4 animate-spin" /> : <Save size={15} />}
                  {c.save}
                </Button>
              </div>
            </Panel>
          </section>

          {/* Payment gateways — toggling channels needs a payment-service config store that
              doesn't exist in v2 yet → disabled toggles + honest gap note (never faked ON). */}
          <section id="payments" className="scroll-mt-5">
            <Panel>
              <PanelHead title={c.payTitle} sub={c.paySub}>
                {gapChip}
              </PanelHead>
              <PanelBody className="py-1">
                {/* Unchecked on purpose: a checked state would imply a real config value
                    that no endpoint backs (the mockup's ON states are demo data). */}
                <KvRow label={c.payPromptpay} sub={c.payPromptpaySub} end>
                  <Toggle checked={false} disabled onChange={noop} aria-label={c.payPromptpay} />
                </KvRow>
                <KvRow label={c.payCard} sub={c.payCardSub} end>
                  <Toggle checked={false} disabled onChange={noop} aria-label={c.payCard} />
                </KvRow>
                <KvRow label={c.payWallet} sub={c.payWalletSub} end>
                  <Toggle checked={false} disabled onChange={noop} aria-label={c.payWallet} />
                </KvRow>
                <ManagedNote text={c.payFutureNote} chip={gapChip} />
              </PanelBody>
            </Panel>
          </section>

          {/* SMS & notifications — provider name is service env; the FCM key is a SECRET that is
              never surfaced via API. No editable store by design → "managed via env" note. */}
          <section id="sms" className="scroll-mt-5">
            <Panel>
              <PanelHead title={c.smsTitle} sub={c.smsSub}>
                <Badge tone="gray">{c.managedEnv}</Badge>
              </PanelHead>
              <PanelBody>
                <p className="text-[12.5px] text-muted">{c.smsManagedNote}</p>
              </PanelBody>
            </Panel>
          </section>

          {/* Storage & security — bucket/JWT/OTP TTL/rate-limit/CORS are deploy-time env config
              loaded fail-fast at startup; secrets are never surfaced → "managed via env" note. */}
          <section id="storage" className="scroll-mt-5">
            <Panel>
              <PanelHead title={c.storageTitle} sub={c.storageSub}>
                <Badge tone="gray">{c.managedEnv}</Badge>
              </PanelHead>
              <PanelBody>
                <p className="text-[12.5px] text-muted">{c.storageManagedNote}</p>
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

          {/* No global footer Save/Cancel: the only saveable section (Company) saves inline;
              every other section is env-managed or a documented gap. */}
        </div>
      </div>
    </div>
  );
}

function noop() {}

/** A small inline "managed via env / future store" note row under a gap-chipped section. */
function ManagedNote({ text, chip }: { text: string; chip: ReactNode }) {
  return (
    <div className="mt-2 flex items-start gap-2 border-t border-border pt-3 text-[12px] text-muted">
      {chip}
      <span>{text}</span>
    </div>
  );
}

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
  /** `null` = no selection (gap-chipped sections must not fake a configured value). */
  value: T | null;
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

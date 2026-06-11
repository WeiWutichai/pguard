"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";

import { identityApi } from "@/lib/api";
import { ThemeToggle } from "@/components/shell/theme-toggle";
import { Button } from "@/components/ui/button";
import { Field, Input } from "@/components/ui/input";
import { cn } from "@/lib/cn";
import { useLanguage } from "@/lib/i18n";

import { COPY } from "./copy";
import { LoginHero } from "./hero";

/**
 * Admin sign-in — hi-fi split layout (brand hero left, 380px form card right; stacks below
 * 900px where the hero hides, per the spec).
 *
 * AUTH FLOW (unchanged): POSTs the gateway login (cookie path) — on success identity sets the
 * httpOnly `access_token` / `refresh_token` cookies (we never read tokens from the body), then
 * we soft-navigate (`router.replace` + `router.refresh`) so the (dashboard) server layout
 * re-runs and re-resolves the session from the just-set cookie. Errors are generic
 * (no account enumeration), rendered with role="alert".
 *
 * Mockup deltas (honest gaps — identity exposes only /auth/{register,login,refresh,logout,me}):
 * - The mockup's tab bar (เข้าสู่ระบบ / ลืมรหัสผ่าน / ตั้งรหัสใหม่ / 2FA) and the forgot/reset/2FA
 *   views are view-switcher demo affordances with no backend → omitted; only the login view ships.
 * - "ลืมรหัสผ่าน?" link is in the spec's login view → kept, disabled, title "เร็วๆ นี้".
 * - "จดจำฉันไว้" checkbox: the real login body has no remember_me flag → same disabled treatment.
 * - The field stays `identifier` (email OR phone, existing t() key), not the mockup's email-only.
 */
export function LoginForm() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];
  const router = useRouter();
  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(false);
    const { error: apiError } = await identityApi.POST("/auth/login", {
      body: { identifier, password },
    });
    if (apiError) {
      setError(true);
      setBusy(false);
      return;
    }
    router.replace("/dashboard");
    router.refresh();
  }

  return (
    <main className="grid min-h-screen bg-app min-[900px]:grid-cols-[1.05fr_1fr]">
      {/* Fixed lang/theme seg-mini overlay (spec: top 20px / right 24px) */}
      <div className="fixed right-6 top-5 z-20 flex items-center gap-2">
        <LangToggle />
        <ThemeToggle />
      </div>

      <LoginHero />

      <section className="flex items-center justify-center p-10 max-[900px]:p-5">
        <div className="w-full max-w-[380px]">
          <h1 className="mb-1.5 text-[25px] font-semibold tracking-[-0.01em] text-text-strong">
            {c.formTitle}
          </h1>
          <p className="mb-7 text-sm text-muted">{c.formSubtitle}</p>

          <form onSubmit={onSubmit}>
            <Field label={t("login.identifier")}>
              <Input
                type="text"
                autoComplete="username"
                value={identifier}
                onChange={(e) => setIdentifier(e.target.value)}
                required
              />
            </Field>
            <Field label={t("login.password")}>
              <Input
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </Field>

            {/* Remember row — both affordances exist in the hi-fi but have no backend yet
                (no remember_me in the login body; no password-reset endpoint) → rendered
                disabled with an honest "เร็วๆ นี้" title, never silently fake. */}
            <div className="mb-4 flex items-center justify-between">
              <span title={c.comingSoon} className="inline-flex">
                <button
                  type="button"
                  role="checkbox"
                  aria-checked="false"
                  disabled
                  title={c.comingSoon}
                  className="flex cursor-not-allowed items-center gap-[9px] text-[13.5px] text-text opacity-55"
                >
                  <span
                    aria-hidden
                    className="size-5 flex-none rounded-[6px] border-[1.5px] border-border-strong bg-surface"
                  />
                  {c.remember}
                </button>
              </span>
              <span title={c.comingSoon} className="inline-flex">
                <button
                  type="button"
                  disabled
                  title={c.comingSoon}
                  className="cursor-not-allowed text-[13.5px] font-semibold text-brand-int opacity-55"
                >
                  {c.forgot}
                </button>
              </span>
            </div>

            {error && (
              <p className="mb-3 text-sm text-danger" role="alert">
                {t("login.error")}
              </p>
            )}

            <Button type="submit" disabled={busy} className="w-full py-[13px]">
              {t("login.submit")}
            </Button>
          </form>
        </div>
      </section>
    </main>
  );
}

/** Fixed top-right seg-mini language switcher — page-local twin of the topbar seg (the shell
 * topbar isn't mounted on the public login route, and ui/ is single-writer). */
function LangToggle() {
  const { lang, setLang } = useLanguage();
  return (
    <div
      className="inline-flex flex-none rounded-full border border-border bg-sunken p-[3px]"
      role="group"
      aria-label="language"
    >
      {(["th", "en"] as const).map((l) => (
        <button
          key={l}
          type="button"
          aria-pressed={lang === l}
          onClick={() => setLang(l)}
          className={cn(
            "cursor-pointer rounded-full px-3 py-1.5 font-latin text-xs font-semibold",
            lang === l ? "bg-surface text-text-strong shadow-xs" : "text-muted",
          )}
        >
          {l === "th" ? "ไทย" : "EN"}
        </button>
      ))}
    </div>
  );
}

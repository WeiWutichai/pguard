"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Globe, LogOut, PlugZap, UserCircle } from "lucide-react";

import { identityApi } from "@/lib/api";
import { useAuth } from "@/components/auth-provider";
import { useLanguage } from "@/lib/i18n";
import { cn } from "@/lib/cn";

export default function SettingsPage() {
  const { lang, setLang, t } = useLanguage();
  const user = useAuth(); // server-resolved /auth/me (no extra fetch, no localStorage)
  const router = useRouter();
  const [busy, setBusy] = useState(false);

  async function logout() {
    setBusy(true);
    // Best-effort server revoke (clears httpOnly auth cookies); CSRF marker added by lib/api.ts.
    // ALWAYS bounce to /login even if the revoke fails — the cookies may already be invalid, so a
    // guaranteed local sign-out is the safe behavior (mirrors header.tsx).
    try {
      await identityApi.POST("/auth/logout", {});
    } finally {
      router.replace("/login");
      router.refresh();
    }
  }

  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="text-2xl font-semibold">{t("settings.title")}</h1>
      <p className="mt-1 text-muted">{t("settings.subtitle")}</p>

      {/* Account — from /auth/me (AuthProvider context). */}
      <section className="mt-6 rounded-xl border border-border bg-surface p-5">
        <div className="flex items-center gap-2">
          <UserCircle className="size-5 text-muted" />
          <h2 className="text-lg font-semibold">{t("settings.account")}</h2>
        </div>
        <dl className="mt-3 space-y-2 text-sm">
          <div className="flex justify-between gap-4 border-b border-border py-1.5">
            <dt className="text-muted">{t("settings.role")}</dt>
            <dd className="font-medium">{user.role}</dd>
          </div>
          <div className="flex justify-between gap-4 py-1.5">
            <dt className="text-muted">{t("settings.userId")}</dt>
            <dd className="font-mono text-xs">{user.user_id}</dd>
          </div>
        </dl>
      </section>

      {/* Language — reuses the i18n toggle (locale cookie, not localStorage). */}
      <section className="mt-4 rounded-xl border border-border bg-surface p-5">
        <div className="flex items-center gap-2">
          <Globe className="size-5 text-muted" />
          <h2 className="text-lg font-semibold">{t("settings.language")}</h2>
        </div>
        <div
          className="mt-3 inline-flex overflow-hidden rounded-lg border border-border text-sm font-medium"
          role="group"
          aria-label={t("settings.language")}
        >
          {(["th", "en"] as const).map((l) => (
            <button
              key={l}
              type="button"
              onClick={() => setLang(l)}
              className={cn(
                "px-4 py-1.5 uppercase",
                lang === l ? "bg-brand text-brand-fg" : "bg-surface text-muted hover:bg-sunken",
              )}
            >
              {l}
            </button>
          ))}
        </div>
      </section>

      {/* Documented gap: no admin profile-edit or app-config API in v2 yet. */}
      <section className="mt-4 rounded-xl border border-border bg-surface p-5">
        <div className="flex items-center gap-2 text-muted">
          <PlugZap className="size-5" />
          <p className="text-sm">{t("settings.gap")}</p>
        </div>
      </section>

      {/* Session. */}
      <section className="mt-4 rounded-xl border border-border bg-surface p-5">
        <h2 className="text-lg font-semibold">{t("settings.session")}</h2>
        <button
          type="button"
          onClick={logout}
          disabled={busy}
          className={cn(
            "mt-3 flex items-center gap-1.5 rounded-lg border border-danger px-3 py-1.5 text-sm font-medium text-danger hover:bg-danger/10",
            busy && "opacity-60",
          )}
        >
          <LogOut className="size-4" />
          {t("header.logout")}
        </button>
      </section>
    </div>
  );
}

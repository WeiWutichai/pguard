"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { LogIn, ShieldCheck } from "lucide-react";

import { identityApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import { cn } from "@/lib/cn";

/**
 * Admin sign-in form. POSTs the gateway login (cookie path): on success identity sets the httpOnly
 * `access_token` / `refresh_token` cookies (we never read tokens from the body). We then
 * soft-navigate (`router.replace` + `router.refresh`) so the (dashboard) server layout re-runs and
 * re-resolves the session from the just-set cookie. Errors are generic (no account enumeration).
 */
export function LoginForm() {
  const { t } = useLanguage();
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
    <main className="flex min-h-screen items-center justify-center bg-sunken p-4">
      <div className="w-full max-w-sm rounded-2xl border border-border bg-surface p-8 shadow-sm">
        <div className="mb-6 flex items-center gap-2 text-brand">
          <ShieldCheck className="size-7" />
          <span className="text-lg font-semibold text-text">{t("app.title")}</span>
        </div>
        <h1 className="mb-6 text-xl font-semibold">{t("login.title")}</h1>
        <form onSubmit={onSubmit} className="flex flex-col gap-4">
          <label className="flex flex-col gap-1 text-sm">
            <span className="font-medium">{t("login.identifier")}</span>
            <input
              type="text"
              autoComplete="username"
              value={identifier}
              onChange={(e) => setIdentifier(e.target.value)}
              required
              className="rounded-lg border border-border px-3 py-2 outline-none focus:border-brand"
            />
          </label>
          <label className="flex flex-col gap-1 text-sm">
            <span className="font-medium">{t("login.password")}</span>
            <input
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              className="rounded-lg border border-border px-3 py-2 outline-none focus:border-brand"
            />
          </label>
          {error && (
            <p className="text-sm text-danger" role="alert">
              {t("login.error")}
            </p>
          )}
          <button
            type="submit"
            disabled={busy}
            className={cn(
              "mt-2 flex items-center justify-center gap-2 rounded-lg bg-brand px-4 py-2 font-medium text-brand-fg",
              busy && "opacity-60",
            )}
          >
            <LogIn className="size-4" />
            {t("login.submit")}
          </button>
        </form>
      </div>
    </main>
  );
}

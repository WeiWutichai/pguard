"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { LogIn } from "lucide-react";

import { identityApi } from "@/lib/api";
import { PgMark, PgWordmark } from "@/components/shell/logo";
import { Button } from "@/components/ui/button";
import { Field, Input } from "@/components/ui/input";
import { useLanguage } from "@/lib/i18n";

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
    <main className="flex min-h-screen items-center justify-center bg-app p-4">
      <div className="w-full max-w-sm rounded-2xl border border-border bg-surface p-8 shadow-sm">
        <div className="mb-6 flex items-center gap-2.5">
          <PgMark size={28} />
          <PgWordmark />
        </div>
        <h1 className="mb-6 text-xl font-semibold text-text-strong">{t("login.title")}</h1>
        <form onSubmit={onSubmit} className="flex flex-col">
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
          {error && (
            <p className="mb-3 text-sm text-danger" role="alert">
              {t("login.error")}
            </p>
          )}
          <Button type="submit" disabled={busy} className="mt-1 w-full">
            <LogIn className="size-4" />
            {t("login.submit")}
          </Button>
        </form>
      </div>
    </main>
  );
}

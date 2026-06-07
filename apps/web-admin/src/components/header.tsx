"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { LogOut, UserCircle } from "lucide-react";

import { identityApi } from "@/lib/api";
import { useAuth } from "@/components/auth-provider";
import { useLanguage } from "@/lib/i18n";
import { cn } from "@/lib/cn";

export function Header() {
  const { lang, setLang, t } = useLanguage();
  const user = useAuth();
  const router = useRouter();
  const [busy, setBusy] = useState(false);

  async function logout() {
    setBusy(true);
    // Best-effort server revoke (clears the auth cookies). The CSRF middleware adds
    // X-Requested-With; credentials:'include' sends the cookie. Always bounce to /login after.
    await identityApi.POST("/auth/logout", {});
    router.replace("/login");
    router.refresh();
  }

  return (
    <header className="flex h-14 shrink-0 items-center justify-end gap-3 border-b border-border bg-surface px-5">
      <div
        className="inline-flex overflow-hidden rounded-lg border border-border text-xs font-medium"
        role="group"
        aria-label="language"
      >
        {(["th", "en"] as const).map((l) => (
          <button
            key={l}
            type="button"
            onClick={() => setLang(l)}
            className={cn(
              "px-3 py-1.5 uppercase",
              lang === l ? "bg-brand text-brand-fg" : "bg-surface text-muted",
            )}
          >
            {l}
          </button>
        ))}
      </div>

      <span className="flex items-center gap-1.5 text-sm text-muted">
        <UserCircle className="size-5" />
        <span className="max-w-[10rem] truncate">{user.role}</span>
      </span>

      <button
        type="button"
        onClick={logout}
        disabled={busy}
        className={cn(
          "flex items-center gap-1.5 rounded-lg border border-border px-3 py-1.5 text-sm font-medium hover:bg-sunken",
          busy && "opacity-60",
        )}
        title={t("header.logout")}
      >
        <LogOut className="size-4" />
        {t("header.logout")}
      </button>
    </header>
  );
}

"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { Bell, ChevronDown, CircleUser, LogOut, Settings } from "lucide-react";

import { identityApi } from "@/lib/api";
import { useAuth } from "@/components/auth-provider";
import { Button } from "@/components/ui/button";
import { Modal } from "@/components/ui/modal";
import { SearchField } from "@/components/ui/search-field";
import { cn } from "@/lib/cn";
import { useLanguage, type TKey } from "@/lib/i18n";

/** Route → topbar title (the shell's per-page heading). Longest prefix wins. */
const TITLES: readonly [string, TKey][] = [
  ["/dashboard", "nav.dashboard"],
  ["/operations", "nav.operations"],
  ["/map", "nav.map"],
  ["/applicants", "nav.applicants"],
  ["/guards", "nav.guards"],
  ["/customers", "nav.customers"],
  ["/reviews", "nav.reviews"],
  ["/tasks", "nav.tasks"],
  ["/bookings", "nav.bookings"],
  ["/wallet", "nav.wallet"],
  ["/pricing", "nav.pricing"],
  ["/calls", "nav.calls"],
  ["/chat", "nav.chat"],
  ["/broadcast", "nav.broadcast"],
  ["/expiring", "nav.expiring"],
  ["/recruit", "nav.recruit"],
  ["/reports", "nav.reports"],
  ["/automation", "nav.automation"],
  ["/replay", "nav.replay"],
  ["/activity", "nav.activity"],
  ["/settings", "nav.settings"],
  ["/profile", "nav.profile"],
];

/** admin.css `.topbar` — 62px bar: page title · search (260px) · bell · TH/EN segment ·
 * user menu popover with the CSRF-guarded logout behind a confirm dialog. */
export function Topbar() {
  const { lang, setLang, t } = useLanguage();
  const user = useAuth();
  const router = useRouter();
  const pathname = usePathname();

  const [menuOpen, setMenuOpen] = useState(false);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  // Close the popover on any outside click (mirrors admin-shell.js).
  useEffect(() => {
    if (!menuOpen) return;
    const close = (e: MouseEvent) => {
      if (!menuRef.current?.contains(e.target as Node)) setMenuOpen(false);
    };
    document.addEventListener("click", close);
    return () => document.removeEventListener("click", close);
  }, [menuOpen]);

  const title = TITLES.find(([p]) => pathname === p || pathname.startsWith(`${p}/`))?.[1];

  async function logout() {
    setBusy(true);
    // Best-effort server revoke (clears the auth cookies). The CSRF middleware adds
    // X-Requested-With; credentials:'include' sends the cookie. ALWAYS bounce to /login —
    // even if the revoke fails the cookies may already be invalid.
    try {
      await identityApi.POST("/auth/logout", {});
    } finally {
      router.replace("/login");
      router.refresh();
    }
  }

  const initials = user.role.slice(0, 2).toUpperCase();

  return (
    <header className="flex h-[62px] flex-none items-center gap-4 border-b border-border bg-surface px-6">
      <div className="min-w-0">
        <h1 className="truncate text-[19px] font-semibold text-text-strong">
          {title ? t(title) : t("app.title")}
        </h1>
      </div>

      <div className="flex-1" />

      {/* Visual parity with the shell; global search wiring is a later slice. */}
      <SearchField placeholder={t("shell.search")} aria-label={t("shell.search")} />

      <button
        type="button"
        aria-label={t("shell.notifications")}
        className="flex size-[38px] flex-none cursor-pointer items-center justify-center rounded-md border border-border bg-surface text-muted hover:bg-sunken"
      >
        <Bell size={18} />
      </button>

      <div
        className="inline-flex flex-none rounded-full border border-border bg-sunken p-[3px]"
        role="group"
        aria-label="language"
      >
        {(["th", "en"] as const).map((l) => (
          <button
            key={l}
            type="button"
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

      <div className="relative flex-none" ref={menuRef}>
        <button
          type="button"
          aria-haspopup="menu"
          aria-expanded={menuOpen}
          onClick={() => setMenuOpen((v) => !v)}
          className="flex cursor-pointer items-center gap-[7px] rounded-full border border-border bg-surface py-1 pl-1 pr-[9px] text-muted hover:bg-sunken"
        >
          <span className="flex size-[30px] items-center justify-center rounded-full bg-green-100 font-latin text-xs font-semibold text-green-800 dark:bg-green-800 dark:text-green-100">
            {initials}
          </span>
          <ChevronDown size={15} />
        </button>

        {menuOpen ? (
          <div
            role="menu"
            className="absolute right-0 top-[calc(100%+8px)] z-60 w-[248px] rounded-lg border border-border bg-surface p-2 shadow-lg"
          >
            <div className="flex items-center gap-[11px] px-2.5 pb-3 pt-2.5">
              <span className="flex size-[42px] items-center justify-center rounded-full bg-green-100 font-latin text-[15px] font-semibold text-green-800 dark:bg-green-800 dark:text-green-100">
                {initials}
              </span>
              <div className="min-w-0">
                <div className="truncate text-sm font-semibold text-text-strong">
                  {t("shell.adminName")}
                </div>
                <div className="truncate text-[11px] text-muted">{user.role}</div>
              </div>
            </div>
            <Link
              href="/profile"
              role="menuitem"
              onClick={() => setMenuOpen(false)}
              className="flex items-center gap-[11px] rounded-sm p-2.5 text-sm text-text hover:bg-sunken"
            >
              <CircleUser size={16} />
              {t("nav.profile")}
            </Link>
            <Link
              href="/settings"
              role="menuitem"
              onClick={() => setMenuOpen(false)}
              className="flex items-center gap-[11px] rounded-sm p-2.5 text-sm text-text hover:bg-sunken"
            >
              <Settings size={16} />
              {t("nav.settings")}
            </Link>
            <div className="mx-1 my-1.5 h-px bg-border" />
            <button
              type="button"
              role="menuitem"
              onClick={() => {
                setMenuOpen(false);
                setConfirmOpen(true);
              }}
              className="flex w-full cursor-pointer items-center gap-[11px] rounded-sm p-2.5 text-sm text-danger hover:bg-sunken"
            >
              <LogOut size={16} />
              {t("header.logout")}
            </button>
          </div>
        ) : null}
      </div>

      <Modal
        open={confirmOpen}
        onClose={() => setConfirmOpen(false)}
        title={t("logout.confirmTitle")}
        footer={
          <>
            <Button variant="secondary" size="sm" onClick={() => setConfirmOpen(false)}>
              {t("logout.cancel")}
            </Button>
            <Button variant="danger" size="sm" disabled={busy} onClick={logout}>
              {t("header.logout")}
            </Button>
          </>
        }
      >
        <p className="text-[13.5px] leading-relaxed text-muted">{t("logout.confirmBody")}</p>
      </Modal>
    </header>
  );
}

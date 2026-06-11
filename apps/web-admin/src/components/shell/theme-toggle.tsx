"use client";

import { useSyncExternalStore } from "react";
import { Moon, Sun } from "lucide-react";

import { cn } from "@/lib/cn";
import { useLanguage } from "@/lib/i18n";

type Theme = "light" | "dark";

// Tiny external store over the <html data-theme> attribute + the hi-fi shell's `pg_theme`
// localStorage key (admin-shell.js): app/layout.tsx restores it before paint, and
// useSyncExternalStore keeps hydration safe (server snapshot is always "light").
const listeners = new Set<() => void>();

function getTheme(): Theme {
  return document.documentElement.getAttribute("data-theme") === "dark" ? "dark" : "light";
}

function setTheme(t: Theme) {
  if (t === "dark") document.documentElement.setAttribute("data-theme", "dark");
  else document.documentElement.removeAttribute("data-theme");
  try {
    localStorage.setItem("pg_theme", t);
  } catch {
    /* private mode — theme just won't persist */
  }
  listeners.forEach((l) => l());
}

function subscribe(cb: () => void) {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

/** admin.css `.seg-mini` ☀/☾ pair (sidebar foot). */
export function ThemeToggle() {
  const { t } = useLanguage();
  const theme = useSyncExternalStore(subscribe, getTheme, () => "light" as Theme);

  const seg = (value: Theme, icon: React.ReactNode, label: string) => (
    <button
      type="button"
      aria-label={label}
      aria-pressed={theme === value}
      onClick={() => setTheme(value)}
      className={cn(
        "cursor-pointer rounded-full px-3 py-1.5 font-latin text-xs font-semibold",
        theme === value
          ? "bg-surface text-text-strong shadow-xs"
          : "text-muted",
      )}
    >
      {icon}
    </button>
  );

  return (
    <div className="inline-flex flex-none rounded-full border border-border bg-sunken p-[3px]">
      {seg("light", <Sun size={13} />, t("shell.themeLight"))}
      {seg("dark", <Moon size={13} />, t("shell.themeDark"))}
    </div>
  );
}

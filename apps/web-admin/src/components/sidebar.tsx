"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { Route } from "next";
import {
  LayoutDashboard,
  UserPlus,
  Shield,
  Users,
  Map as MapIcon,
  Star,
  Wallet,
  Tag,
  Activity,
  Settings,
  type LucideIcon,
} from "lucide-react";

import { cn } from "@/lib/cn";
import { useLanguage, type TKey } from "@/lib/i18n";

interface NavItem {
  href: Route;
  icon: LucideIcon;
  label: TKey;
}

// Dashboard, applicants, guards, reviews, map, and settings are fully built; customers/pricing/
// wallet/activity are intentional "API-gap" pages (their admin endpoints aren't in the v2
// contracts yet — see ApiGapPage). All nav items stay visible so the gaps are surfaced, not hidden.
const NAV: readonly NavItem[] = [
  { href: "/dashboard", icon: LayoutDashboard, label: "nav.dashboard" },
  { href: "/applicants", icon: UserPlus, label: "nav.applicants" },
  { href: "/guards", icon: Shield, label: "nav.guards" },
  { href: "/customers", icon: Users, label: "nav.customers" },
  { href: "/map", icon: MapIcon, label: "nav.map" },
  { href: "/reviews", icon: Star, label: "nav.reviews" },
  { href: "/wallet", icon: Wallet, label: "nav.wallet" },
  { href: "/pricing", icon: Tag, label: "nav.pricing" },
  { href: "/activity", icon: Activity, label: "nav.activity" },
  { href: "/settings", icon: Settings, label: "nav.settings" },
];

export function Sidebar() {
  const pathname = usePathname();
  const { t } = useLanguage();

  return (
    <aside className="flex w-60 shrink-0 flex-col border-r border-border bg-surface">
      <div className="flex items-center gap-2 border-b border-border px-5 py-4 text-brand">
        <Shield className="size-6" />
        <span className="font-semibold text-text">{t("app.title")}</span>
      </div>
      <nav className="flex flex-1 flex-col gap-1 p-3">
        {NAV.map(({ href, icon: Icon, label }) => {
          const active = pathname === href || pathname.startsWith(`${href}/`);
          return (
            <Link
              key={href}
              href={href}
              className={cn(
                "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium text-muted transition-colors hover:bg-sunken hover:text-text",
                active && "bg-brand/10 text-brand hover:bg-brand/10 hover:text-brand",
              )}
            >
              <Icon className="size-4" />
              {t(label)}
            </Link>
          );
        })}
      </nav>
    </aside>
  );
}

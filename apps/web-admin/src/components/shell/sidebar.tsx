"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { Route } from "next";
import {
  Activity,
  Briefcase,
  ChartLine,
  CircleUser,
  FileText,
  LayoutDashboard,
  ListChecks,
  Map as MapIcon,
  MessageSquare,
  Phone,
  Route as RouteIcon,
  Send,
  Settings,
  Shield,
  Star,
  Tag,
  TriangleAlert,
  User,
  UserPlus,
  Users,
  Wallet,
  Workflow,
  type LucideIcon,
} from "lucide-react";

import { useAuth } from "@/components/auth-provider";
import { cn } from "@/lib/cn";
import { useLanguage, type TKey } from "@/lib/i18n";

import { PgMark, PgWordmark } from "./logo";
import { ThemeToggle } from "./theme-toggle";

interface NavItem {
  href: Route;
  icon: LucideIcon;
  label: TKey;
}
interface NavGroup {
  label: TKey;
  items: readonly NavItem[];
}

// The hi-fi shell's 4 nav groups (admin-shell.js NAV), 1:1 — built screens route to their
// real pages; screens awaiting their rebuild slice route to a ComingSoonPage (never a dead
// link). The mockup's count badges were sample data, so they are omitted until each screen
// has a real source to count from.
const GROUPS: readonly NavGroup[] = [
  {
    label: "nav.group.overview",
    items: [
      { href: "/dashboard", icon: LayoutDashboard, label: "nav.dashboard" },
      { href: "/operations", icon: Activity, label: "nav.operations" },
      { href: "/map", icon: MapIcon, label: "nav.map" },
      { href: "/applicants", icon: Users, label: "nav.applicants" },
      { href: "/guards", icon: Shield, label: "nav.guards" },
      { href: "/customers", icon: User, label: "nav.customers" },
      { href: "/reviews", icon: Star, label: "nav.reviews" },
    ],
  },
  {
    label: "nav.group.finance",
    items: [
      { href: "/tasks", icon: ListChecks, label: "nav.tasks" },
      { href: "/bookings", icon: Briefcase, label: "nav.bookings" },
      { href: "/wallet", icon: Wallet, label: "nav.wallet" },
      { href: "/pricing", icon: Tag, label: "nav.pricing" },
    ],
  },
  {
    label: "nav.group.comms",
    items: [
      { href: "/calls", icon: Phone, label: "nav.calls" },
      { href: "/chat", icon: MessageSquare, label: "nav.chat" },
      { href: "/broadcast", icon: Send, label: "nav.broadcast" },
    ],
  },
  {
    label: "nav.group.system",
    items: [
      { href: "/expiring", icon: TriangleAlert, label: "nav.expiring" },
      { href: "/recruit", icon: UserPlus, label: "nav.recruit" },
      { href: "/reports", icon: ChartLine, label: "nav.reports" },
      { href: "/automation", icon: Workflow, label: "nav.automation" },
      { href: "/replay", icon: RouteIcon, label: "nav.replay" },
      { href: "/activity", icon: FileText, label: "nav.activity" },
      { href: "/settings", icon: Settings, label: "nav.settings" },
      { href: "/profile", icon: CircleUser, label: "nav.profile" },
    ],
  },
];

/** admin.css `.side` — 248px surface column: logo top, scrollable grouped nav, foot with
 * the admin identity + theme toggle. Active item = solid green-900 (dark: brand-int). */
export function Sidebar() {
  const pathname = usePathname();
  const { t } = useLanguage();
  const user = useAuth();

  return (
    <aside className="flex w-[248px] shrink-0 flex-col border-r border-border bg-surface">
      <div className="flex items-center gap-2.5 px-[18px] pb-3.5 pt-5">
        <PgMark size={28} />
        <PgWordmark />
      </div>

      <nav className="min-h-0 flex-1 overflow-y-auto px-3 pb-3 pt-1.5">
        {GROUPS.map((group) => (
          <div key={group.label}>
            <div className="px-2.5 pb-1.5 pt-3.5 font-latin text-[10.5px] font-semibold uppercase tracking-[0.1em] text-faint">
              {t(group.label)}
            </div>
            {group.items.map(({ href, icon: Icon, label }) => {
              const active = pathname === href || pathname.startsWith(`${href}/`);
              return (
                <Link
                  key={href}
                  href={href}
                  aria-current={active ? "page" : undefined}
                  className={cn(
                    "flex items-center gap-[11px] rounded-sm px-[11px] py-[9px] text-sm font-medium",
                    active
                      ? "bg-green-900 text-white dark:bg-brand-int dark:text-on-brand"
                      : "text-muted hover:bg-sunken hover:text-text",
                  )}
                >
                  <Icon className="size-[18px] flex-none opacity-85" />
                  <span className="min-w-0 flex-1 truncate">{t(label)}</span>
                </Link>
              );
            })}
          </div>
        ))}
      </nav>

      <div className="flex items-center gap-2.5 border-t border-border p-3">
        <span className="flex size-[34px] flex-none items-center justify-center rounded-full bg-green-100 font-latin text-[13px] font-semibold text-green-800 dark:bg-green-800 dark:text-green-100">
          {user.role.slice(0, 2).toUpperCase()}
        </span>
        <div className="min-w-0 flex-1">
          <div className="truncate text-[13px] font-semibold text-text-strong">
            {t("shell.adminName")}
          </div>
          <div className="truncate text-[11px] text-muted">{user.role}</div>
        </div>
        <ThemeToggle />
      </div>
    </aside>
  );
}

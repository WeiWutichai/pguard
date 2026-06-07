"use client";

import { useLanguage } from "@/lib/i18n";

export default function DashboardPage() {
  const { t } = useLanguage();
  return (
    <div>
      <h1 className="text-2xl font-semibold">{t("dashboard.title")}</h1>
      <p className="mt-2 text-muted">{t("dashboard.welcome")}</p>
    </div>
  );
}

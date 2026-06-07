"use client";

import { Construction } from "lucide-react";

import { useLanguage, type TKey } from "@/lib/i18n";

/** Placeholder for nav destinations not built in this slice (Guards/Customers/Map/…). */
export function StubPage({ titleKey }: { titleKey: TKey }) {
  const { t } = useLanguage();
  return (
    <div className="flex flex-col items-center justify-center gap-3 py-24 text-center text-muted">
      <Construction className="size-10" />
      <h1 className="text-xl font-semibold text-text">{t(titleKey)}</h1>
      <p>{t("stub.soon")}</p>
    </div>
  );
}

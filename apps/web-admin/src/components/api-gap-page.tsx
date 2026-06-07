"use client";

import { PlugZap } from "lucide-react";

import { useLanguage, type TKey } from "@/lib/i18n";

/**
 * Honest placeholder for an admin workflow whose backend endpoint does NOT exist in the v2 API
 * contract yet (web-admin slice 2). Unlike the generic "coming soon" stub, this names *why*
 * (the per-page `reasonKey`) and the exact missing operationIds, so the gap is documented in the
 * UI itself — these pages become real once the backend adds the listed endpoints. (The v1 admin
 * had these; v2 either hasn't built them or deliberately removed the concept — see PROGRESS.)
 */
export function ApiGapPage({
  titleKey,
  reasonKey,
  endpoints,
}: {
  titleKey: TKey;
  reasonKey: TKey;
  endpoints: readonly string[];
}) {
  const { t } = useLanguage();
  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="text-2xl font-semibold">{t(titleKey)}</h1>

      <div className="mt-6 rounded-xl border border-border bg-surface p-8 text-center">
        <PlugZap className="mx-auto size-10 text-muted" />
        <p className="mt-4 text-lg font-medium">{t("gap.title")}</p>
        <p className="mx-auto mt-2 max-w-md text-sm text-muted">{t(reasonKey)}</p>
        <p className="mx-auto mt-1 max-w-md text-sm text-muted">{t("gap.note")}</p>

        <div className="mx-auto mt-5 max-w-md text-left">
          <div className="text-xs font-medium uppercase text-muted">{t("gap.endpoints")}</div>
          <ul className="mt-2 space-y-1">
            {endpoints.map((e) => (
              <li
                key={e}
                className="rounded-md border border-border bg-sunken px-3 py-1.5 font-mono text-xs text-muted"
              >
                {e}
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
}

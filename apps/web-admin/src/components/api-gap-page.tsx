"use client";

import { PlugZap } from "lucide-react";

import { PageIntro } from "@/components/ui/page-intro";
import { Panel } from "@/components/ui/panel";
import { useLanguage, type Lang, type TKey } from "@/lib/i18n";

/** Screen-local bilingual design copy (the mockups' topbar title/lead for each gap page). */
type Bilingual = Readonly<Record<Lang, string>>;

/**
 * Honest placeholder for an admin workflow whose backend endpoint does NOT exist in the v2 API
 * contract yet (web-admin slice 2). Unlike the generic "coming soon" stub, this names *why*
 * (the per-page `reasonKey`) and the exact missing operationIds, so the gap is documented in the
 * UI itself — these pages become real once the backend adds the listed endpoints. (The v1 admin
 * had these; v2 either hasn't built them or deliberately removed the concept — see PROGRESS.)
 *
 * Styled to the design's empty-state pattern (admin.css `.empty`, mirroring ComingSoonPage):
 * Panel + 88px sunken icon tile + heading + muted note + the endpoint list. The heading and the
 * literal endpoint strings stay visible — e2e (gap-pages.spec.ts) asserts both.
 */
export function ApiGapPage({
  titleKey,
  reasonKey,
  endpoints,
  title,
  lead,
}: {
  titleKey: TKey;
  reasonKey: TKey;
  endpoints: readonly string[];
  /** Designed page title override where the mockup differs from the nav label. */
  title?: Bilingual;
  /** Designed page lead/subtitle from the mockup. */
  lead?: Bilingual;
}) {
  const { lang, t } = useLanguage();
  return (
    <div className="mx-auto max-w-3xl">
      <PageIntro title={title ? title[lang] : t(titleKey)} lead={lead ? lead[lang] : undefined} />

      <Panel className="px-5 py-14 text-center">
        <div className="mx-auto mb-[18px] flex size-[88px] items-center justify-center rounded-full bg-sunken text-faint">
          <PlugZap size={32} />
        </div>
        <h4 className="mb-1.5 text-[17px] font-semibold text-text-strong">{t("gap.title")}</h4>
        <p className="mx-auto max-w-md text-sm text-muted">{t(reasonKey)}</p>
        <p className="mx-auto mt-1 max-w-md text-sm text-muted">{t("gap.note")}</p>

        <div className="mx-auto mt-6 max-w-md text-left">
          <div className="text-xs font-semibold uppercase tracking-[0.04em] text-faint">
            {t("gap.endpoints")}
          </div>
          <ul className="mt-2 space-y-1.5">
            {endpoints.map((e) => (
              <li
                key={e}
                className="rounded-md border border-border bg-sunken px-3 py-2 font-mono text-xs text-muted"
              >
                {e}
              </li>
            ))}
          </ul>
        </div>
      </Panel>
    </div>
  );
}

"use client";

import { Hourglass } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { useLanguage, type TKey } from "@/lib/i18n";

/** Placeholder for hi-fi screens whose rebuild slice hasn't shipped yet (admin.css
 * `.empty` styling). Distinct from ApiGapPage: that one means "the v2 API doesn't exist";
 * this one means "the screen is on the roadmap". Nav shows both so nothing is a dead link. */
export function ComingSoonPage({ titleKey }: { titleKey: TKey }) {
  const { t } = useLanguage();

  return (
    <section className="rounded-lg border border-border bg-surface px-5 py-14 text-center">
      <div className="mx-auto mb-[18px] flex size-[88px] items-center justify-center rounded-full bg-sunken text-faint">
        <Hourglass size={32} />
      </div>
      <h4 className="mb-1.5 text-[17px] font-semibold text-text-strong">
        {t(titleKey)} — {t("soon.title")}
      </h4>
      <p className="mx-auto mb-[18px] max-w-md text-sm text-muted">{t("soon.note")}</p>
      <Badge tone="amber">{t("soon.badge")}</Badge>
    </section>
  );
}

"use client";

import { useCallback, useEffect, useState } from "react";
import { AlertTriangle, CalendarCog, Loader2, Plus, RefreshCw, Tag } from "lucide-react";

import type { components } from "@/api/generated/booking";
import {
  Badge,
  Button,
  PageIntro,
  Panel,
  Table,
  Td,
  Th,
  Tr,
} from "@/components/ui";
import { bookingApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import { cn } from "@/lib/cn";
import { fmtBaht } from "../bookings/copy";

import { COPY } from "./copy";
import { ServiceModal } from "./service-modal";

type ServiceCatalogItem = components["schemas"]["ServiceCatalogItem"];

export default function PricingPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [services, setServices] = useState<ServiceCatalogItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [tab, setTab] = useState<"services" | "rules">("services");
  // null = closed; { service } = edit; { service: null } = create.
  const [editing, setEditing] = useState<{ service: ServiceCatalogItem | null } | null>(null);

  const fetchInto = useCallback((alive: () => boolean) => {
    return bookingApi.GET("/admin/pricing/services").then(({ data, error }) => {
      if (!alive()) return;
      setHasError(Boolean(error));
      setServices(error ? [] : (data?.data ?? []));
      setLoading(false);
    });
  }, []);

  useEffect(() => {
    let alive = true;
    void fetchInto(() => alive);
    return () => {
      alive = false;
    };
  }, [reloadNonce, fetchInto]);

  function reload() {
    setLoading(true);
    setHasError(false);
    setReloadNonce((n) => n + 1);
  }

  async function deactivate(id: string) {
    await bookingApi.DELETE("/admin/pricing/services/{id}", { params: { path: { id } } });
    reload();
  }

  const activeCount = services.filter((s) => s.is_active).length;

  return (
    <div>
      <PageIntro
        title={c.title}
        lead={loading || hasError ? t("pricing.subtitle") : c.subtitle(String(activeCount))}
      >
        <Button variant="secondary" size="sm" onClick={reload}>
          <RefreshCw size={15} />
          {t("common.retry")}
        </Button>
        {tab === "services" && (
          <Button variant="primary" size="sm" onClick={() => setEditing({ service: null })}>
            <Plus size={15} />
            {c.addService}
          </Button>
        )}
      </PageIntro>

      {hasError && (
        <div
          role="alert"
          className="mb-4 flex items-center gap-2 rounded-lg border border-danger/40 bg-danger-bg px-4 py-2.5 text-sm text-danger"
        >
          <AlertTriangle className="size-4 flex-none" />
          {t("pricing.error")}
        </div>
      )}

      {/* Tabs. */}
      <div className="mb-4 inline-flex rounded-lg border border-border bg-sunken p-[3px]">
        {(
          [
            ["services", c.tabServices, Tag],
            ["rules", c.tabRules, CalendarCog],
          ] as const
        ).map(([v, label, Icon]) => (
          <button
            key={v}
            type="button"
            onClick={() => setTab(v)}
            className={cn(
              "flex items-center gap-1.5 rounded-md px-3.5 py-[7px] text-[13px] font-semibold",
              tab === v ? "bg-surface text-text-strong shadow-xs" : "text-muted",
            )}
          >
            <Icon className="size-3.5" />
            {label}
          </button>
        ))}
      </div>

      {tab === "rules" ? (
        <Panel>
          <div className="flex flex-col items-center gap-2 py-16 text-center text-muted">
            <Badge tone="gray">{c.awaitingApi}</Badge>
            <p className="max-w-md text-sm">{c.rulesGap}</p>
          </div>
        </Panel>
      ) : (
        <>
          {/* Standalone-catalog note (editing a rate doesn't change charging yet). */}
          <div className="mb-4 flex items-start gap-2 rounded-lg border border-border bg-sunken px-4 py-2.5 text-[12.5px] text-muted">
            <Badge tone="gray">{c.awaitingApi}</Badge>
            <span>{c.standaloneNote}</span>
          </div>

          <Panel>
            {loading ? (
              <div className="flex items-center justify-center gap-2 py-16 text-muted">
                <Loader2 className="size-5 animate-spin" />
                {t("common.loading")}
              </div>
            ) : services.length === 0 ? (
              <div className="py-16 text-center text-muted">{t("pricing.empty")}</div>
            ) : (
              <Table>
                <thead>
                  <tr>
                    <Th>{c.colName}</Th>
                    <Th>{c.colBaseFee}</Th>
                    <Th>{c.colMinHours}</Th>
                    <Th>{c.colNotes}</Th>
                    <Th>{c.colStatus}</Th>
                    <Th aria-label={c.edit} />
                  </tr>
                </thead>
                <tbody>
                  {services.map((s) => (
                    <Tr key={s.id} onClick={() => setEditing({ service: s })}>
                      <Td>
                        <div className="font-semibold text-text-strong">{s.name_th}</div>
                        <div className="text-xs text-muted">{s.name_en}</div>
                      </Td>
                      <Td className="font-mono tabular-nums">
                        {fmtBaht(Number(s.base_fee ?? 0))}
                        <span className="text-muted"> {c.perHour}</span>
                      </Td>
                      <Td className="font-mono tabular-nums">
                        {s.min_hours} {c.hoursUnit}
                      </Td>
                      <Td className="max-w-[220px] truncate text-muted">
                        {s.notes ?? t("common.none")}
                      </Td>
                      <Td>
                        {s.is_active ? (
                          <Badge tone="green">{c.active}</Badge>
                        ) : (
                          <Badge tone="gray">{c.inactive}</Badge>
                        )}
                      </Td>
                      <Td className="text-right" onClick={(e) => e.stopPropagation()}>
                        <div className="flex justify-end gap-2">
                          <Button
                            variant="secondary"
                            size="sm"
                            onClick={() => setEditing({ service: s })}
                          >
                            {c.edit}
                          </Button>
                          {s.is_active && (
                            <Button
                              variant="danger-ghost"
                              size="sm"
                              onClick={() => deactivate(s.id)}
                            >
                              {c.deactivate}
                            </Button>
                          )}
                        </div>
                      </Td>
                    </Tr>
                  ))}
                </tbody>
              </Table>
            )}
          </Panel>
        </>
      )}

      {editing && (
        <ServiceModal
          service={editing.service}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            reload();
          }}
        />
      )}
    </div>
  );
}

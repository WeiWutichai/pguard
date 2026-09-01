"use client";

import { useCallback, useEffect, useState } from "react";
import { AlertTriangle, Download, Loader2, RefreshCw, Save } from "lucide-react";

import type { components } from "@/api/generated/payment";
import {
  Badge,
  Button,
  Field,
  Input,
  KpiCard,
  KpiGrid,
  PageIntro,
  Panel,
  PanelBody,
  PanelHead,
  Table,
  Td,
  Th,
  Tr,
} from "@/components/ui";
import { paymentApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import { COPY } from "./copy";

type PayoutConfig = components["schemas"]["PayoutConfig"];
type PayoutPreview = components["schemas"]["PayoutPreview"];

export default function PayoutsPage() {
  const { lang } = useLanguage();
  const c = COPY[lang];

  const [config, setConfig] = useState<PayoutConfig | null>(null);
  const [preview, setPreview] = useState<PayoutPreview | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [saving, setSaving] = useState(false);
  const [savedFlash, setSavedFlash] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [banner, setBanner] = useState<string | null>(null);

  const load = useCallback((alive: () => boolean = () => true) => {
    return Promise.all([
      paymentApi.GET("/admin/payouts/config"),
      paymentApi.GET("/admin/payouts/preview"),
    ])
      .then(([cfg, prev]) => {
        if (!alive()) return;
        if (cfg.error || prev.error) {
          setLoadError(true);
        } else {
          setLoadError(false);
          setConfig(cfg.data?.data ?? null);
          setPreview(prev.data?.data ?? null);
        }
        setLoading(false);
      })
      .catch(() => {
        if (!alive()) return;
        setLoadError(true);
        setLoading(false);
      });
  }, []);

  useEffect(() => {
    let alive = true;
    void load(() => alive);
    return () => {
      alive = false;
    };
  }, [load]);

  const reload = () => {
    setLoading(true);
    void load();
  };

  const field = (key: keyof PayoutConfig, value: string) =>
    setConfig((prev) => (prev ? { ...prev, [key]: value } : prev));

  const save = async () => {
    if (!config) return;
    setSaving(true);
    setBanner(null);
    const res = await paymentApi.PUT("/admin/payouts/config", {
      body: {
        debit_account: config.debit_account ?? null,
        fee_debit_account: config.fee_debit_account ?? null,
        wht_rate_percent: config.wht_rate_percent ?? null,
        wht_form_type_code: config.wht_form_type_code ?? null,
        wht_income_type_code: config.wht_income_type_code ?? null,
        wht_income_desc: config.wht_income_desc ?? null,
      },
    });
    setSaving(false);
    if (res.error) {
      setBanner(c.saveError);
    } else {
      setConfig(res.data?.data ?? config);
      setSavedFlash(true);
      setTimeout(() => setSavedFlash(false), 2000);
      void load();
    }
  };

  const runExport = async () => {
    setExporting(true);
    setBanner(null);
    const res = await paymentApi.POST("/admin/payouts/export", { parseAs: "text" });
    setExporting(false);
    if (res.error || typeof res.data !== "string") {
      setBanner(c.exportError);
      return;
    }
    const blob = new Blob([res.data], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `SCB_payout_${new Date().toISOString().slice(0, 10)}.txt`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
    void load(); // the paid jobs drop out of the backlog
  };

  const recipients = preview?.recipients ?? [];
  const excluded = preview?.excluded ?? [];
  const nothingToPay = recipients.length === 0;

  return (
    <div className="space-y-6">
      <PageIntro title={c.title} lead={c.subtitle} />

      {loadError && (
        <div className="flex items-center gap-2 rounded-lg border border-red-300/50 bg-red-50/60 px-4 py-3 text-sm text-red-700 dark:bg-red-950/30 dark:text-red-300">
          <AlertTriangle className="size-4" /> {c.loadError}
        </div>
      )}
      {banner && (
        <div className="flex items-center gap-2 rounded-lg border border-amber-300/50 bg-amber-50/60 px-4 py-3 text-sm text-amber-800 dark:bg-amber-950/30 dark:text-amber-300">
          <AlertTriangle className="size-4" /> {banner}
        </div>
      )}

      {/* ── Settings ─────────────────────────────────────────── */}
      <Panel>
        <PanelHead title={c.settings} />
        <PanelBody>
          {config && (
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label={c.debitAccount}>
                <Input
                  value={config.debit_account ?? ""}
                  onChange={(e) => field("debit_account", e.target.value)}
                  inputMode="numeric"
                  placeholder="1234567890"
                />
              </Field>
              <Field label={c.feeDebitAccount}>
                <Input
                  value={config.fee_debit_account ?? ""}
                  onChange={(e) => field("fee_debit_account", e.target.value)}
                  inputMode="numeric"
                />
              </Field>
              <Field label={c.whtRate}>
                <Input
                  value={config.wht_rate_percent ?? ""}
                  onChange={(e) => field("wht_rate_percent", e.target.value)}
                  inputMode="decimal"
                  placeholder="3"
                />
              </Field>
              <Field label={c.whtForm}>
                <Input
                  value={config.wht_form_type_code ?? ""}
                  onChange={(e) => field("wht_form_type_code", e.target.value)}
                  placeholder="53"
                />
              </Field>
              <Field label={c.incomeDesc}>
                <Input
                  value={config.wht_income_desc ?? ""}
                  onChange={(e) => field("wht_income_desc", e.target.value)}
                />
              </Field>
            </div>
          )}
          <div className="mt-4 flex items-center gap-3">
            <Button onClick={save} disabled={saving || !config}>
              {saving ? <Loader2 className="size-4 animate-spin" /> : <Save className="size-4" />}
              {c.save}
            </Button>
            {savedFlash && (
              <span className="text-sm text-emerald-600 dark:text-emerald-400">{c.saved}</span>
            )}
          </div>
        </PanelBody>
      </Panel>

      {/* ── Preview + export ─────────────────────────────────── */}
      <Panel>
        <PanelHead title={c.preview}>
          <div className="flex items-center gap-2">
            <Button variant="ghost" onClick={reload} disabled={loading}>
              <RefreshCw className={`size-4 ${loading ? "animate-spin" : ""}`} />
              {c.refresh}
            </Button>
            <Button onClick={runExport} disabled={exporting || loading || nothingToPay}>
              {exporting ? (
                <Loader2 className="size-4 animate-spin" />
              ) : (
                <Download className="size-4" />
              )}
              {exporting ? c.exporting : c.exportBtn}
            </Button>
          </div>
        </PanelHead>
        <PanelBody>
          <KpiGrid>
            <KpiCard label={c.recipients} value={String(preview?.recipient_count ?? 0)} />
            <KpiCard label={c.totalTransfer} value={`฿${preview?.total_transfer ?? "0.00"}`} />
            <KpiCard label={c.totalWht} value={`฿${preview?.total_wht ?? "0.00"}`} />
          </KpiGrid>

          <p className="mt-2 text-xs text-neutral-500">{c.exportHint}</p>

          {loading ? (
            <div className="flex items-center justify-center py-10 text-neutral-400">
              <Loader2 className="size-6 animate-spin" />
            </div>
          ) : nothingToPay ? (
            <p className="py-8 text-center text-sm text-neutral-500">{c.nobody}</p>
          ) : (
            <Table className="mt-4">
              <thead>
                <Tr>
                  <Th>{c.guard}</Th>
                  <Th>{c.proxy}</Th>
                  <Th className="text-right">{c.income}</Th>
                  <Th className="text-right">{c.wht}</Th>
                  <Th className="text-right">{c.transfer}</Th>
                </Tr>
              </thead>
              <tbody>
                {recipients.map((r, i) => (
                  <Tr key={i}>
                    <Td>{r.name}</Td>
                    <Td className="font-mono text-xs">{r.proxy_masked}</Td>
                    <Td className="text-right tabular-nums">฿{r.income}</Td>
                    <Td className="text-right tabular-nums text-amber-600 dark:text-amber-400">
                      ฿{r.wht}
                    </Td>
                    <Td className="text-right font-semibold tabular-nums">฿{r.transfer}</Td>
                  </Tr>
                ))}
              </tbody>
            </Table>
          )}

          {excluded.length > 0 && (
            <div className="mt-6">
              <div className="mb-2 flex items-center gap-2 text-sm font-medium text-red-600 dark:text-red-400">
                <AlertTriangle className="size-4" /> {c.excludedTitle} ({excluded.length})
              </div>
              <Table>
                <thead>
                  <Tr>
                    <Th>{c.guard}</Th>
                    <Th>{c.reason}</Th>
                    <Th className="text-right">{c.jobs}</Th>
                  </Tr>
                </thead>
                <tbody>
                  {excluded.map((g) => (
                    <Tr key={g.guard_id}>
                      <Td className="font-mono text-xs">{g.guard_id.slice(0, 8)}</Td>
                      <Td>
                        <Badge tone="red">{g.reason}</Badge>
                      </Td>
                      <Td className="text-right tabular-nums">{g.job_count}</Td>
                    </Tr>
                  ))}
                </tbody>
              </Table>
            </div>
          )}
        </PanelBody>
      </Panel>
    </div>
  );
}

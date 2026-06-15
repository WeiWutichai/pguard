"use client";

import { useCallback, useEffect, useState } from "react";
import { AlertTriangle, ArrowRight, Loader2, RefreshCw, Trash2, Zap } from "lucide-react";

import type { components as NotificationComponents } from "@/api/generated/notification";
import {
  Badge,
  Button,
  Field,
  Input,
  PageIntro,
  Panel,
  PanelBody,
  PanelHead,
  Select,
  Toggle,
} from "@/components/ui";
import { notificationApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import {
  ACTION_KEYS,
  type ActionKey,
  COPY,
  TRIGGER_KEYS,
  type TriggerKey,
} from "./copy";

type AutomationRule = NotificationComponents["schemas"]["AutomationRule"];

export default function AutomationPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [rules, setRules] = useState<AutomationRule[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [busy, setBusy] = useState<string | null>(null);

  // builder
  const [trigger, setTrigger] = useState<TriggerKey>(TRIGGER_KEYS[0]);
  const [condition, setCondition] = useState("");
  const [action, setAction] = useState<ActionKey>(ACTION_KEYS[0]);
  const [saving, setSaving] = useState(false);

  const fetchInto = useCallback((alive: () => boolean) => {
    return notificationApi
      .GET("/admin/automation/rules")
      .then((res) => {
        if (!alive()) return;
        setHasError(Boolean(res.error));
        setRules(res.error ? [] : (res.data?.data ?? []));
        setLoading(false);
      })
      .catch(() => {
        if (!alive()) return;
        setHasError(true);
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
    setReloadNonce((n) => n + 1);
  }

  async function saveRule() {
    setSaving(true);
    setHasError(false);
    const res = await notificationApi.POST("/admin/automation/rules", {
      body: {
        trigger_key: trigger,
        condition_text: condition.trim() || undefined,
        action_key: action,
        is_enabled: true,
      },
    });
    setSaving(false);
    if (res.error) {
      setHasError(true);
      return;
    }
    setCondition("");
    reload();
  }

  async function toggle(rule: AutomationRule) {
    setBusy(rule.id);
    await notificationApi.PUT("/admin/automation/rules/{id}", {
      params: { path: { id: rule.id } },
      body: { is_enabled: !rule.is_enabled },
    });
    setBusy(null);
    reload();
  }

  async function remove(id: string) {
    setBusy(id);
    await notificationApi.DELETE("/admin/automation/rules/{id}", {
      params: { path: { id } },
    });
    setBusy(null);
    reload();
  }

  return (
    <div>
      <PageIntro title={c.title} lead={t("automation.subtitle")}>
        <Button variant="secondary" size="sm" onClick={reload}>
          <RefreshCw size={15} />
          {t("common.retry")}
        </Button>
      </PageIntro>

      {/* Authoring-only — rules don't fire yet. Honest, prominent. */}
      <div className="mb-4 flex items-start gap-2 rounded-lg border border-border bg-sunken px-4 py-2.5 text-[12.5px] text-muted">
        <Badge tone="gray">{t("gap.endpoints")}</Badge>
        <span>{c.executionGap}</span>
      </div>

      {hasError && (
        <div
          role="alert"
          className="mb-4 flex items-center gap-2 rounded-lg border border-danger/40 bg-danger-bg px-4 py-2.5 text-sm text-danger"
        >
          <AlertTriangle className="size-4 flex-none" />
          {t("automation.error")}
        </div>
      )}

      {/* ---- builder ---- */}
      <Panel className="mb-[18px]">
        <PanelHead title={c.newRuleHead} />
        <PanelBody>
          <div className="grid items-end gap-3 md:grid-cols-[1fr_1fr_1fr_auto]">
            <Field label={c.whenLabel} className="mb-0">
              <Select value={trigger} onChange={(e) => setTrigger(e.target.value as TriggerKey)}>
                {TRIGGER_KEYS.map((k) => (
                  <option key={k} value={k}>
                    {c.triggerLabel[k]}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label={c.ifLabel} className="mb-0">
              <Input
                value={condition}
                onChange={(e) => setCondition(e.target.value)}
                placeholder={c.ifPlaceholder}
                maxLength={120}
              />
            </Field>
            <Field label={c.thenLabel} className="mb-0">
              <Select value={action} onChange={(e) => setAction(e.target.value as ActionKey)}>
                {ACTION_KEYS.map((k) => (
                  <option key={k} value={k}>
                    {c.actionLabel[k]}
                  </option>
                ))}
              </Select>
            </Field>
            <Button onClick={saveRule} disabled={saving}>
              {saving ? <Loader2 className="size-4 animate-spin" /> : <Zap size={15} />}
              {c.saveRule}
            </Button>
          </div>
        </PanelBody>
      </Panel>

      {/* ---- active rules ---- */}
      <Panel>
        <PanelHead title={c.activeHead}>
          <span className="text-[12.5px] text-muted">{c.ruleCount(rules.length)}</span>
        </PanelHead>
        {loading ? (
          <div className="flex items-center justify-center gap-2 py-16 text-muted">
            <Loader2 className="size-5 animate-spin" />
            {t("common.loading")}
          </div>
        ) : rules.length === 0 ? (
          <div className="py-16 text-center text-muted">{t("automation.empty")}</div>
        ) : (
          <ul>
            {rules.map((rule) => {
              const working = busy === rule.id;
              return (
                <li
                  key={rule.id}
                  className="flex flex-wrap items-center gap-3 border-b border-border px-5 py-4 last:border-b-0"
                >
                  <div className="flex flex-1 flex-wrap items-center gap-2">
                    <span className="inline-flex items-center gap-1.5 rounded-md bg-info-bg px-3 py-1.5 text-[13px] font-medium text-info">
                      <Zap size={13} />
                      {c.triggerLabel[rule.trigger_key as TriggerKey] ?? rule.trigger_key}
                    </span>
                    {rule.condition_text && (
                      <>
                        <ArrowRight size={15} className="text-faint" />
                        <span className="rounded-md bg-sunken px-3 py-1.5 text-[13px] text-muted">
                          {rule.condition_text}
                        </span>
                      </>
                    )}
                    <ArrowRight size={15} className="text-faint" />
                    <span className="rounded-md bg-success-bg px-3 py-1.5 text-[13px] font-medium text-success">
                      {c.actionLabel[rule.action_key as ActionKey] ?? rule.action_key}
                    </span>
                  </div>
                  <Toggle
                    checked={rule.is_enabled}
                    disabled={working}
                    onChange={() => toggle(rule)}
                    aria-label={c.enabled}
                  />
                  <Button
                    variant="danger-ghost"
                    size="sm"
                    disabled={working}
                    onClick={() => remove(rule.id)}
                    aria-label={c.delete}
                  >
                    <Trash2 size={15} />
                  </Button>
                </li>
              );
            })}
          </ul>
        )}
      </Panel>
    </div>
  );
}

"use client";

import { useCallback, useEffect, useState } from "react";
import { AlertTriangle, Loader2, RefreshCw, ShieldCheck, X } from "lucide-react";

import type { components } from "@/api/generated/profile";
import { profileApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

type GuardProfile = components["schemas"]["GuardProfile"];

/** Show only the last 4 of an account number in the list (the admin can open the detail modal for
 *  the full value the contract returns). PDPA-friendly at-a-glance display. */
function maskAccount(account: string | null | undefined): string | null {
  if (!account) return null;
  const tail = account.slice(-4);
  return account.length <= 4 ? account : `••••${tail}`;
}

export default function GuardsPage() {
  const { t } = useLanguage();
  const [guards, setGuards] = useState<GuardProfile[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [selected, setSelected] = useState<GuardProfile | null>(null);

  const fetchInto = useCallback((alive: () => boolean) => {
    return profileApi
      .GET("/admin/guard-profiles", { params: { query: { approval_status: "approved" } } })
      .then(({ data, error }) => {
        if (!alive()) return;
        setHasError(Boolean(error));
        setGuards(error ? [] : (data?.data ?? []));
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

  return (
    <div className="mx-auto max-w-5xl">
      <h1 className="text-2xl font-semibold">{t("guards.title")}</h1>
      <p className="mt-1 text-muted">{t("guards.subtitle")}</p>

      <div className="mt-5 flex items-center gap-3">
        {!loading && <span className="text-sm text-muted">{guards.length}</span>}
        <button
          type="button"
          onClick={reload}
          className="ml-auto flex items-center gap-1.5 rounded-lg border border-border px-3 py-1.5 text-sm hover:bg-sunken"
        >
          <RefreshCw className="size-4" />
          {t("common.retry")}
        </button>
      </div>

      {hasError && (
        <div
          role="alert"
          className="mt-4 flex items-center gap-2 rounded-lg border border-danger/40 bg-danger/10 px-4 py-2 text-sm text-danger"
        >
          <AlertTriangle className="size-4" />
          {t("guards.error")}
        </div>
      )}

      <div className="mt-4 overflow-hidden rounded-xl border border-border bg-surface">
        {loading ? (
          <div className="flex items-center justify-center gap-2 py-16 text-muted">
            <Loader2 className="size-5 animate-spin" />
            {t("common.loading")}
          </div>
        ) : guards.length === 0 ? (
          <div className="py-16 text-center text-muted">{t("guards.empty")}</div>
        ) : (
          <table className="w-full text-left text-sm">
            <thead className="border-b border-border bg-sunken text-xs uppercase text-muted">
              <tr>
                <th className="px-4 py-3 font-medium">{t("guards.col.guard")}</th>
                <th className="px-4 py-3 font-medium">{t("guards.col.experience")}</th>
                <th className="px-4 py-3 font-medium">{t("guards.col.workplace")}</th>
                <th className="px-4 py-3 font-medium">{t("guards.col.bank")}</th>
                <th className="px-4 py-3 text-right font-medium">{t("guards.col.guard")}</th>
              </tr>
            </thead>
            <tbody>
              {guards.map((g) => (
                <tr key={g.user_id} className="border-b border-border last:border-0">
                  <td className="px-4 py-3 align-top">
                    <div className="font-mono text-xs text-muted">{g.user_id}</div>
                    {g.gender && <div className="text-xs text-muted">{g.gender}</div>}
                  </td>
                  <td className="px-4 py-3 align-top">
                    {g.years_of_experience != null
                      ? `${g.years_of_experience} ${t("applicants.years")}`
                      : t("common.none")}
                  </td>
                  <td className="px-4 py-3 align-top">{g.previous_workplace ?? t("common.none")}</td>
                  <td className="px-4 py-3 align-top">
                    {g.bank_name ? (
                      <div>
                        <div>{g.bank_name}</div>
                        <div className="font-mono text-xs text-muted">
                          {maskAccount(g.account_number) ?? t("common.none")}
                        </div>
                      </div>
                    ) : (
                      t("common.none")
                    )}
                  </td>
                  <td className="px-4 py-3 align-top text-right">
                    <button
                      type="button"
                      onClick={() => setSelected(g)}
                      className="rounded-lg border border-border px-3 py-1.5 text-xs font-medium hover:bg-sunken"
                    >
                      {t("common.view")}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {selected && <GuardDetail guard={selected} onClose={() => setSelected(null)} />}
    </div>
  );
}

function GuardDetail({ guard, onClose }: { guard: GuardProfile; onClose: () => void }) {
  const { t } = useLanguage();
  // Close on Escape (modal a11y).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const rows: { key: string; label: string; value: string | null | undefined }[] = [
    { key: "gender", label: t("guards.detail.gender"), value: guard.gender },
    { key: "dob", label: t("guards.detail.dob"), value: guard.date_of_birth },
    {
      key: "experience",
      label: t("guards.col.experience"),
      value:
        guard.years_of_experience != null
          ? `${guard.years_of_experience} ${t("applicants.years")}`
          : null,
    },
    { key: "workplace", label: t("guards.col.workplace"), value: guard.previous_workplace },
    { key: "bank", label: t("guards.col.bank"), value: guard.bank_name },
    { key: "accountName", label: t("guards.detail.accountName"), value: guard.account_name },
    // Admin detail view shows the FULL account number the contract returns to admins.
    { key: "accountNumber", label: t("guards.detail.accountNumber"), value: guard.account_number },
  ];
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      role="dialog"
      aria-modal="true"
      onClick={onClose}
    >
      <div
        className="w-full max-w-md rounded-xl border border-border bg-surface p-6 shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-2">
            <ShieldCheck className="size-5 text-success" />
            <h2 className="text-lg font-semibold">{t("guards.detail.title")}</h2>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label={t("common.close")}
            autoFocus
            className="rounded-lg p-1 text-muted hover:bg-sunken"
          >
            <X className="size-5" />
          </button>
        </div>
        <div className="mt-1 font-mono text-xs text-muted">{guard.user_id}</div>
        <dl className="mt-4 space-y-2 text-sm">
          {rows.map((r) => (
            <div
              key={r.key}
              className="flex justify-between gap-4 border-b border-border py-1.5 last:border-0"
            >
              <dt className="text-muted">{r.label}</dt>
              <dd className="text-right">{r.value ?? t("common.none")}</dd>
            </div>
          ))}
        </dl>
      </div>
    </div>
  );
}

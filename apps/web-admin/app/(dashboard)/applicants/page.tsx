"use client";

import { useCallback, useEffect, useState } from "react";
import { Check, X, AlertTriangle, RefreshCw, Loader2 } from "lucide-react";

import type { components } from "@/api/generated/profile";
import { profileApi } from "@/lib/api";
import { useLanguage, type TKey } from "@/lib/i18n";
import { cn } from "@/lib/cn";

type GuardProfile = components["schemas"]["GuardProfile"];
type ApprovalStatus = components["schemas"]["ApprovalStatus"];

const STATUSES: readonly ApprovalStatus[] = ["pending", "approved", "rejected"];
const STATUS_LABEL: Record<ApprovalStatus, TKey> = {
  pending: "status.pending",
  approved: "status.approved",
  rejected: "status.rejected",
};

export default function ApplicantsPage() {
  const { t } = useLanguage();
  const [status, setStatus] = useState<ApprovalStatus>("pending");
  const [profiles, setProfiles] = useState<GuardProfile[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [actingId, setActingId] = useState<string | null>(null);
  const [reloadNonce, setReloadNonce] = useState(0);

  // Fetch + apply the result via a promise callback (NOT synchronously) so the effect that calls
  // this never sets state during its synchronous phase (react-hooks/set-state-in-effect). The
  // `alive` guard drops a stale response if the filter changed mid-flight.
  const fetchInto = useCallback((s: ApprovalStatus, alive: () => boolean) => {
    return profileApi
      .GET("/admin/guard-profiles", { params: { query: { approval_status: s } } })
      .then(({ data, error }) => {
        if (!alive()) return;
        setHasError(Boolean(error));
        setProfiles(error ? [] : (data?.data ?? []));
        setLoading(false);
      });
  }, []);

  // Re-runs on filter change AND on an explicit reload (reloadNonce). The cleanup flips `alive`
  // false, so a response from a superseded run (filter switched, or a stale retry) is dropped.
  useEffect(() => {
    let alive = true;
    void fetchInto(status, () => alive);
    return () => {
      alive = false;
    };
  }, [status, reloadNonce, fetchInto]);

  function selectStatus(next: ApprovalStatus) {
    if (next === status) return;
    setLoading(true); // event handler — synchronous setState here is fine
    setStatus(next);
  }

  function reload() {
    setLoading(true);
    setHasError(false);
    setReloadNonce((n) => n + 1); // re-run the alive-guarded effect
  }

  // Approve/reject only run from the `pending` view, so the row LEAVES the list on success →
  // optimistic remove, rollback (restore the snapshot) + error banner on failure. This is an
  // event handler, so the synchronous setState calls are fine.
  async function act(userId: string, action: "approve" | "reject") {
    const snapshot = profiles;
    setHasError(false);
    setActingId(userId);
    setProfiles((cur) => cur.filter((p) => p.user_id !== userId));

    const { error } =
      action === "approve"
        ? await profileApi.POST("/admin/guard-profiles/{user_id}/approve", {
            params: { path: { user_id: userId } },
          })
        : await profileApi.POST("/admin/guard-profiles/{user_id}/reject", {
            params: { path: { user_id: userId } },
            body: {},
          });

    setActingId(null);
    if (error) {
      setProfiles(snapshot); // rollback
      setHasError(true);
    }
  }

  return (
    <div className="mx-auto max-w-5xl">
      <h1 className="text-2xl font-semibold">{t("applicants.title")}</h1>
      <p className="mt-1 text-muted">{t("applicants.subtitle")}</p>

      <div className="mt-5 flex items-center gap-3">
        <div className="inline-flex overflow-hidden rounded-lg border border-border text-sm">
          {STATUSES.map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => selectStatus(s)}
              className={cn(
                "px-4 py-1.5 font-medium",
                status === s
                  ? "bg-brand text-brand-fg"
                  : "bg-surface text-muted hover:bg-sunken",
              )}
            >
              {t(STATUS_LABEL[s])}
            </button>
          ))}
        </div>
        {!loading && (
          <span className="text-sm text-muted">
            {profiles.length} {t(STATUS_LABEL[status])}
          </span>
        )}
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
          {t("applicants.error")}
        </div>
      )}

      <div className="mt-4 overflow-hidden rounded-xl border border-border bg-surface">
        {loading ? (
          <div className="flex items-center justify-center gap-2 py-16 text-muted">
            <Loader2 className="size-5 animate-spin" />
            {t("common.loading")}
          </div>
        ) : profiles.length === 0 ? (
          <div className="py-16 text-center text-muted">{t("applicants.empty")}</div>
        ) : (
          <table className="w-full text-left text-sm">
            <thead className="border-b border-border bg-sunken text-xs uppercase text-muted">
              <tr>
                <th className="px-4 py-3 font-medium">{t("applicants.col.guard")}</th>
                <th className="px-4 py-3 font-medium">{t("applicants.col.experience")}</th>
                <th className="px-4 py-3 font-medium">{t("applicants.col.workplace")}</th>
                <th className="px-4 py-3 font-medium">{t("applicants.col.bank")}</th>
                <th className="px-4 py-3 text-right font-medium">{t("applicants.col.actions")}</th>
              </tr>
            </thead>
            <tbody>
              {profiles.map((p) => (
                <tr key={p.user_id} className="border-b border-border last:border-0">
                  <td className="px-4 py-3 align-top">
                    <div className="font-mono text-xs text-muted">{p.user_id}</div>
                    {p.gender && <div className="text-xs text-muted">{p.gender}</div>}
                    {p.date_of_birth && (
                      <div className="text-xs text-muted">{p.date_of_birth}</div>
                    )}
                  </td>
                  <td className="px-4 py-3 align-top">
                    {p.years_of_experience != null
                      ? `${p.years_of_experience} ${t("applicants.years")}`
                      : t("common.none")}
                  </td>
                  <td className="px-4 py-3 align-top">
                    {p.previous_workplace ?? t("common.none")}
                  </td>
                  <td className="px-4 py-3 align-top">
                    {p.bank_name ? (
                      <div>
                        <div>{p.bank_name}</div>
                        <div className="font-mono text-xs text-muted">
                          {p.account_number ?? t("common.none")}
                        </div>
                        {p.account_name && (
                          <div className="text-xs text-muted">{p.account_name}</div>
                        )}
                      </div>
                    ) : (
                      t("common.none")
                    )}
                  </td>
                  <td className="px-4 py-3 align-top text-right">
                    {status === "pending" ? (
                      <div className="inline-flex gap-2">
                        <button
                          type="button"
                          data-testid={`applicant-approve-${p.user_id}`}
                          disabled={actingId === p.user_id}
                          onClick={() => void act(p.user_id, "approve")}
                          className="inline-flex items-center gap-1 rounded-lg bg-success px-3 py-1.5 text-xs font-medium text-white disabled:opacity-60"
                        >
                          <Check className="size-3.5" />
                          {t("applicants.approve")}
                        </button>
                        <button
                          type="button"
                          data-testid={`applicant-reject-${p.user_id}`}
                          disabled={actingId === p.user_id}
                          onClick={() => void act(p.user_id, "reject")}
                          className="inline-flex items-center gap-1 rounded-lg border border-danger px-3 py-1.5 text-xs font-medium text-danger disabled:opacity-60"
                        >
                          <X className="size-3.5" />
                          {t("applicants.reject")}
                        </button>
                      </div>
                    ) : (
                      <span className="text-xs text-muted">
                        {t(STATUS_LABEL[p.approval_status])}
                      </span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

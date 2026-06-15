"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, Check, Loader2, RefreshCw, X } from "lucide-react";

import type { components as ProfileComponents } from "@/api/generated/profile";
import { Badge, Button, PageIntro, Select } from "@/components/ui";
import { profileApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import { COLUMNS, type Column, COPY, type Stage, STAGES } from "./copy";

type RecruitCandidate = ProfileComponents["schemas"]["RecruitCandidate"];

export default function RecruitPage() {
  const { t, lang } = useLanguage();
  const c = COPY[lang];

  const [candidates, setCandidates] = useState<RecruitCandidate[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [busy, setBusy] = useState<string | null>(null);

  const fetchInto = useCallback((alive: () => boolean) => {
    return profileApi
      .GET("/admin/recruitment/candidates")
      .then((res) => {
        if (!alive()) return;
        setHasError(Boolean(res.error));
        setCandidates(res.error ? [] : (res.data?.data ?? []));
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

  // A candidate's board column: finalized → its approval column; pending → its pipeline stage.
  const columnOf = (cand: RecruitCandidate): Column | null => {
    if (cand.approval_status === "approved") return "approved";
    if (cand.approval_status === "rejected") return null; // off-board
    return (STAGES as readonly string[]).includes(cand.recruitment_stage)
      ? (cand.recruitment_stage as Stage)
      : "screened";
  };

  const byColumn = useMemo(() => {
    const map: Record<Column, RecruitCandidate[]> = {
      sourcing: [],
      screened: [],
      docs_verified: [],
      approved: [],
    };
    for (const cand of candidates) {
      const col = columnOf(cand);
      if (col) map[col].push(cand);
    }
    return map;
  }, [candidates]);

  const pipelineCount = candidates.filter((x) => x.approval_status !== "rejected").length;

  async function moveStage(userId: string, stage: Stage) {
    setBusy(userId);
    await profileApi.PUT("/admin/recruitment/candidates/{user_id}/stage", {
      params: { path: { user_id: userId } },
      body: { stage },
    });
    setBusy(null);
    reload();
  }

  async function decide(userId: string, action: "approve" | "reject") {
    setBusy(userId);
    const path = `/admin/guard-profiles/{user_id}/${action}` as
      | "/admin/guard-profiles/{user_id}/approve"
      | "/admin/guard-profiles/{user_id}/reject";
    await profileApi.POST(path, { params: { path: { user_id: userId } } });
    setBusy(null);
    reload();
  }

  return (
    <div>
      <PageIntro
        title={c.title}
        lead={loading || hasError ? t("recruit.subtitle") : c.inPipeline(pipelineCount)}
      >
        {/* Manual candidate creation has no v2 endpoint — honest disabled CTA + gap chip. */}
        <Badge tone="gray">{t("gap.endpoints")}</Badge>
        <Button variant="secondary" size="sm" disabled title={c.addGap}>
          {c.addCandidate}
        </Button>
        <Button variant="secondary" size="sm" onClick={reload}>
          <RefreshCw size={15} />
          {t("common.retry")}
        </Button>
      </PageIntro>

      {hasError && (
        <div
          role="alert"
          className="mb-4 flex items-center gap-2 rounded-lg border border-danger/40 bg-danger-bg px-4 py-2.5 text-sm text-danger"
        >
          <AlertTriangle className="size-4 flex-none" />
          {t("recruit.error")}
        </div>
      )}

      {loading ? (
        <div className="flex items-center justify-center gap-2 py-24 text-muted">
          <Loader2 className="size-5 animate-spin" />
          {t("common.loading")}
        </div>
      ) : pipelineCount === 0 ? (
        <div className="rounded-lg border border-border bg-surface py-20 text-center text-muted">
          {t("recruit.empty")}
        </div>
      ) : (
        <div className="grid items-start gap-3.5 md:grid-cols-2 xl:grid-cols-4">
          {COLUMNS.map((col) => (
            <div key={col} className="rounded-xl bg-sunken p-3">
              <div className="flex items-center gap-2 px-1.5 pb-3 pt-1 text-[13px] font-semibold text-text-strong">
                <span>{c.colLabel[col]}</span>
                <span className="ml-auto rounded-full bg-surface px-2 py-0.5 font-mono text-[11px] text-muted">
                  {byColumn[col].length}
                </span>
              </div>
              <div className="flex flex-col gap-2.5">
                {byColumn[col].map((cand) => {
                  const working = busy === cand.user_id;
                  const isApproved = col === "approved";
                  return (
                    <div
                      key={cand.user_id}
                      className="rounded-md border border-border bg-surface p-3 shadow-xs"
                    >
                      <div className="font-mono text-[13.5px] font-semibold text-text-strong">
                        #{cand.user_id.slice(0, 8)}
                      </div>
                      <div className="mt-1 text-[12px] text-muted">
                        {cand.years_of_experience != null
                          ? c.experience(cand.years_of_experience)
                          : c.noExperience}
                      </div>
                      {!isApproved && (
                        <div className="mt-3 flex flex-col gap-2">
                          <Select
                            aria-label={c.moveTo}
                            value={cand.recruitment_stage}
                            disabled={working}
                            onChange={(e) => moveStage(cand.user_id, e.target.value as Stage)}
                          >
                            {STAGES.map((s) => (
                              <option key={s} value={s}>
                                {c.colLabel[s]}
                              </option>
                            ))}
                          </Select>
                          <div className="flex gap-2">
                            <Button
                              size="sm"
                              disabled={working}
                              onClick={() => decide(cand.user_id, "approve")}
                            >
                              {working ? <Loader2 className="size-4 animate-spin" /> : <Check size={15} />}
                              {c.approve}
                            </Button>
                            <Button
                              variant="danger-ghost"
                              size="sm"
                              disabled={working}
                              onClick={() => decide(cand.user_id, "reject")}
                            >
                              <X size={15} />
                              {c.reject}
                            </Button>
                          </div>
                        </div>
                      )}
                      {isApproved && (
                        <div className="mt-2">
                          <Badge tone="green">{c.colLabel.approved}</Badge>
                        </div>
                      )}
                    </div>
                  );
                })}
                {byColumn[col].length === 0 && (
                  <div className="px-1.5 py-4 text-center text-[12px] text-faint">—</div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Onboarded column isn't a distinct v2 state — honest note. */}
      <p className="mt-4 text-[12px] text-muted">{c.onboardGap}</p>
    </div>
  );
}

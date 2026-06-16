"use client";

import { useCallback, useEffect, useState } from "react";
import {
  AlertTriangle,
  Check,
  CheckCircle2,
  Clock,
  Eye,
  Inbox,
  Loader2,
  RefreshCw,
  Timer,
  X,
  XCircle,
} from "lucide-react";

import type { components } from "@/api/generated/profile";
import { profileApi } from "@/lib/api";
import { GuardDetailModal } from "../guards/guard-detail-modal";
import { initialsOf } from "../guards/guard-identity";
import { useLanguage, type TKey } from "@/lib/i18n";
import { fmtCappedCount } from "@/lib/format";
import {
  Avatar,
  Badge,
  Button,
  KpiCard,
  KpiGrid,
  PageIntro,
  Pagination,
  Panel,
  Tab,
  Table,
  Tabs,
  Td,
  Th,
  Tr,
} from "@/components/ui";

type GuardProfile = components["schemas"]["GuardProfile"];
type ApprovalStatus = components["schemas"]["ApprovalStatus"];

const STATUSES: readonly ApprovalStatus[] = ["pending", "approved", "rejected"];

// pending/approved reuse the existing i18n keys (they already equal the design copy);
// rejected differs (design chip says "ปฏิเสธ", i18n has "ปฏิเสธแล้ว") so it lives in COPY.
const STATUS_TKEY: Partial<Record<ApprovalStatus, TKey>> = {
  pending: "status.pending",
  approved: "status.approved",
};

// Design status badges: amber/green/red pill with a 7px dot (admin.css `.bdg .d`).
const STATUS_TONE: Record<ApprovalStatus, "amber" | "green" | "red"> = {
  pending: "amber",
  approved: "green",
  rejected: "red",
};
const STATUS_DOT: Record<ApprovalStatus, string> = {
  pending: "bg-amber-500", // design: dot var(--amber-500)
  approved: "bg-success",
  rejected: "bg-danger",
};

// Screen-local design copy (exact TH/EN strings from the hi-fi spec). Shared i18n.tsx is
// single-writer — new design copy must NOT be added there.
const COPY = {
  th: {
    title: "ผู้สมัคร",
    lead: "อนุมัติเจ้าหน้าที่และลูกค้าใหม่",
    kpiPending: "รออนุมัติ",
    kpiApproved: "อนุมัติแล้ว (รวม)",
    kpiRejected: "ปฏิเสธ",
    kpiAvgTime: "เวลาอนุมัติเฉลี่ย",
    awaitingApi: "รอ API",
    customersGap: "ผู้เรียก รปภ. — รอ API",
    statusRejected: "ปฏิเสธ",
    typeGuard: "เจ้าหน้าที่ รปภ.",
    colApplicant: "ผู้สมัคร",
    colType: "ประเภท",
    colStatus: "สถานะ",
    view: "ดู",
  },
  en: {
    title: "Applicants",
    lead: "Approve new guards & customers",
    kpiPending: "Pending",
    kpiApproved: "Approved total",
    kpiRejected: "Rejected",
    kpiAvgTime: "Avg. approval time",
    awaitingApi: "awaiting API",
    customersGap: "Customers — awaiting API",
    statusRejected: "Rejected",
    typeGuard: "Guard",
    colApplicant: "Applicant",
    colType: "Type",
    colStatus: "Status",
    view: "View",
  },
} as const;

// Design paginates the list at 12 rows ("แสดง 1–12 จาก 12 รายการ"). Pagination is
// CLIENT-SIDE over the already-fetched list — the admin list endpoint has no page param.
const PAGE_SIZE = 12;

export default function ApplicantsPage() {
  const { t, lang } = useLanguage();
  const copy = COPY[lang];
  const [status, setStatus] = useState<ApprovalStatus>("pending");
  const [profiles, setProfiles] = useState<GuardProfile[]>([]);
  // Per-status counts, cached from each tab's last successful fetch. Tab pills + KPI
  // values only show a number once that status' data has actually been loaded — counts
  // for unvisited tabs stay undefined (shown as "—"), never faked.
  const [counts, setCounts] = useState<Partial<Record<ApprovalStatus, number>>>({});
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [actingId, setActingId] = useState<string | null>(null);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [page, setPage] = useState(1);
  // The applicant whose full profile is open in the review modal (null = closed).
  const [selected, setSelected] = useState<GuardProfile | null>(null);

  function statusLabel(s: ApprovalStatus): string {
    const key = STATUS_TKEY[s];
    return key ? t(key) : copy.statusRejected;
  }

  // Fetch + apply the result via a promise callback (NOT synchronously) so the effect that calls
  // this never sets state during its synchronous phase (react-hooks/set-state-in-effect). The
  // `alive` guard drops a stale response if the filter changed mid-flight.
  const fetchInto = useCallback((s: ApprovalStatus, alive: () => boolean) => {
    return profileApi
      .GET("/admin/guard-profiles", { params: { query: { approval_status: s } } })
      .then(({ data, error }) => {
        if (!alive()) return;
        const list = error ? [] : (data?.data ?? []);
        setHasError(Boolean(error));
        setProfiles(list);
        setCounts((cur) => ({ ...cur, [s]: error ? undefined : list.length }));
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
    setPage(1);
    setStatus(next);
  }

  function reload() {
    setLoading(true);
    setHasError(false);
    setPage(1);
    setReloadNonce((n) => n + 1); // re-run the alive-guarded effect
  }

  // Approve/reject only run from the `pending` view, so the row LEAVES the list on success →
  // optimistic remove (list + cached count), rollback (restore both snapshots) + error banner on
  // failure. This is an event handler, so the synchronous setState calls are fine.
  async function act(userId: string, action: "approve" | "reject") {
    const snapshot = profiles;
    const countsSnapshot = counts;
    setHasError(false);
    setActingId(userId);
    setProfiles((cur) => cur.filter((p) => p.user_id !== userId));
    // Decrement the CURRENT tab's count: approve/reject are only reachable from `pending`
    // (both the row actions and the modal footer gate on pending), so `status` is the right bucket.
    setCounts((cur) => ({ ...cur, [status]: Math.max(0, (cur[status] ?? 1) - 1) }));

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
      setCounts(countsSnapshot);
      setHasError(true);
    }
  }

  // Client-side pagination window, clamped so the optimistic remove of the last row on a
  // trailing page can never strand the view on an empty page.
  const total = profiles.length;
  const pageCount = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const curPage = Math.min(page, pageCount);
  const pageRows = profiles.slice((curPage - 1) * PAGE_SIZE, curPage * PAGE_SIZE);
  const from = total === 0 ? 0 : (curPage - 1) * PAGE_SIZE + 1;
  const to = Math.min(curPage * PAGE_SIZE, total);
  const summary =
    lang === "th" ? `แสดง ${from}–${to} จาก ${total} รายการ` : `Showing ${from}–${to} of ${total}`;

  return (
    <div className="mx-auto max-w-6xl">
      <PageIntro title={copy.title} lead={copy.lead}>
        <Button variant="secondary" size="sm" onClick={reload}>
          <RefreshCw className="size-4" />
          {t("common.retry")}
        </Button>
      </PageIntro>

      {/* KPI strip (design: pending / approved total / rejected / avg approval time).
          Counts come from the loaded lists only; avg approval time has NO endpoint
          (needs /profile/approvals stats with created_at→approved_at) → honest gap chip. */}
      <KpiGrid>
        <KpiCard
          icon={<Clock />}
          label={copy.kpiPending}
          value={counts.pending == null ? t("common.none") : fmtCappedCount(counts.pending)}
        />
        <KpiCard
          icon={<CheckCircle2 />}
          label={copy.kpiApproved}
          value={counts.approved == null ? t("common.none") : fmtCappedCount(counts.approved)}
        />
        <KpiCard
          icon={<XCircle />}
          label={copy.kpiRejected}
          value={counts.rejected == null ? t("common.none") : fmtCappedCount(counts.rejected)}
        />
        <KpiCard
          icon={<Timer />}
          label={copy.kpiAvgTime}
          value={<Badge tone="gray">{copy.awaitingApi}</Badge>}
        />
      </KpiGrid>

      {/* Status tabs; pills show counts only once that tab's data has loaded. The design
          also tabs guard vs CUSTOMER applicants — v2 has no customer-approval endpoint,
          so the customers tab is an honest gap chip instead of a dead tab. */}
      <Tabs>
        {STATUSES.map((s) => (
          <Tab key={s} active={status === s} count={counts[s] == null ? undefined : fmtCappedCount(counts[s])} onClick={() => selectStatus(s)}>
            {statusLabel(s)}
          </Tab>
        ))}
        <Badge tone="gray" className="ml-1 self-center">
          {copy.customersGap}
        </Badge>
      </Tabs>

      {hasError && (
        <div
          role="alert"
          className="mb-4 flex items-center gap-2 rounded-md border border-danger/35 bg-danger-bg px-4 py-2.5 text-sm text-danger"
        >
          <AlertTriangle className="size-4 flex-none" />
          {t("applicants.error")}
          <Button variant="danger-ghost" size="sm" className="ml-auto" onClick={reload}>
            {t("common.retry")}
          </Button>
        </div>
      )}

      <Panel>
        {loading ? (
          <div className="flex items-center justify-center gap-2 py-16 text-muted">
            <Loader2 className="size-5 animate-spin" />
            {t("common.loading")}
          </div>
        ) : total === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16">
            <span className="flex size-12 items-center justify-center rounded-full bg-sunken text-faint">
              <Inbox className="size-6" />
            </span>
            <p className="text-sm text-muted">{t("applicants.empty")}</p>
          </div>
        ) : (
          <>
            <Table>
              <thead>
                <tr>
                  <Th>{copy.colApplicant}</Th>
                  <Th>{copy.colType}</Th>
                  <Th>{t("applicants.col.experience")}</Th>
                  <Th>{t("applicants.col.workplace")}</Th>
                  <Th>{t("applicants.col.bank")}</Th>
                  <Th>{copy.colStatus}</Th>
                  <Th className="text-right">{t("applicants.col.actions")}</Th>
                </tr>
              </thead>
              <tbody>
                {pageRows.map((p) => (
                  <Tr key={p.user_id} className="cursor-default">
                    <Td>
                      {/* Design `.cell-user`: avatar + name + ID sub. Registration now captures
                          full_name → it leads; the short id is the mono sub (a guard registered
                          before name capture falls back to the short id as the name). */}
                      <div className="flex items-center gap-[11px]">
                        <Avatar>{initialsOf(p.full_name ?? p.account_name, p.user_id)}</Avatar>
                        <div className="min-w-0">
                          <div className="truncate text-sm font-medium text-text-strong">
                            {p.full_name ?? `#${p.user_id.slice(0, 8)}`}
                          </div>
                          <div className="font-mono text-xs text-muted">
                            #{p.user_id.slice(0, 8)}
                          </div>
                        </div>
                      </div>
                    </Td>
                    <Td>
                      <Badge tone="blue">{copy.typeGuard}</Badge>
                    </Td>
                    <Td>
                      {p.years_of_experience != null
                        ? `${p.years_of_experience} ${t("applicants.years")}`
                        : t("common.none")}
                    </Td>
                    <Td>{p.previous_workplace ?? t("common.none")}</Td>
                    <Td>
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
                    </Td>
                    <Td>
                      <Badge tone={STATUS_TONE[p.approval_status]} dot={STATUS_DOT[p.approval_status]}>
                        {statusLabel(p.approval_status)}
                      </Badge>
                    </Td>
                    <Td className="text-right">
                      <div className="inline-flex gap-2">
                        {/* View the full profile to inspect before deciding (all statuses). */}
                        <Button
                          variant="secondary"
                          size="sm"
                          data-testid={`applicant-view-${p.user_id}`}
                          onClick={() => setSelected(p)}
                        >
                          <Eye className="size-3.5" />
                          {copy.view}
                        </Button>
                        {status === "pending" && (
                          <>
                            <Button
                              size="sm"
                              data-testid={`applicant-approve-${p.user_id}`}
                              disabled={actingId === p.user_id}
                              onClick={() => void act(p.user_id, "approve")}
                            >
                              <Check className="size-3.5" />
                              {t("applicants.approve")}
                            </Button>
                            <Button
                              variant="danger-ghost"
                              size="sm"
                              data-testid={`applicant-reject-${p.user_id}`}
                              disabled={actingId === p.user_id}
                              onClick={() => void act(p.user_id, "reject")}
                            >
                              <X className="size-3.5" />
                              {t("applicants.reject")}
                            </Button>
                          </>
                        )}
                      </div>
                    </Td>
                  </Tr>
                ))}
              </tbody>
            </Table>
            <Pagination page={curPage} pageCount={pageCount} onPage={setPage} summary={summary} />
          </>
        )}
      </Panel>

      {/* View the applicant's full profile before deciding — reuses the guards detail modal.
          For a pending applicant the modal footer also offers Approve/Reject (decide in place);
          finalized applicants are view-only. */}
      {selected && (
        <GuardDetailModal
          guard={selected}
          onClose={() => setSelected(null)}
          acting={actingId === selected.user_id}
          onApprove={
            selected.approval_status === "pending"
              ? () => {
                  void act(selected.user_id, "approve");
                  setSelected(null);
                }
              : undefined
          }
          onReject={
            selected.approval_status === "pending"
              ? () => {
                  void act(selected.user_id, "reject");
                  setSelected(null);
                }
              : undefined
          }
        />
      )}
    </div>
  );
}

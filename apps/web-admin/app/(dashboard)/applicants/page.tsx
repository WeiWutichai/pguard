"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
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
import { shortId, useNameResolver } from "@/lib/use-names";
import { COPY, fmtPhone, fmtSignup } from "./copy";
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

type GuardProfileAdmin = components["schemas"]["GuardProfileAdmin"];
type CustomerProfileAdmin = components["schemas"]["CustomerProfileAdmin"];
type ApprovalStatus = components["schemas"]["ApprovalStatus"];

const STATUSES: readonly ApprovalStatus[] = ["pending", "approved", "rejected"];

/** Which applicant population is shown — guards or customers (ผู้เรียก รปภ.). */
type EntityType = "guard" | "customer";

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

// Design paginates the list at 12 rows ("แสดง 1–12 จาก 12 รายการ"). Pagination is
// CLIENT-SIDE over the already-fetched list — the admin list endpoints have no page param.
const PAGE_SIZE = 12;

/**
 * The `.cell-user` identity block: avatar + who this applicant IS, in the order an admin can act
 * on. The name leads when we have one — from THIS profile, or (via the name resolver, which UNIONs
 * guard + customer profiles) from the same person's OTHER role. With no name anywhere the LOGIN
 * PHONE leads instead: a number an admin can dial reads as a real person, whereas a bare
 * "#5680b50f" reads as a broken record. The short id stays as the last line either way — it is
 * how an admin cross-references this applicant on every other screen.
 *
 * `phone` is `login_phone` (the account's own number from identity), never a customer's optional
 * `contact_phone`.
 */
function ApplicantIdentity({
  name,
  phone,
  userId,
  hint,
  initialsName,
}: {
  name: string | null;
  phone: string | null | undefined;
  userId: string;
  hint: string;
  /** Only seeds the avatar initials — a name we are NOT confident enough to display as the
   *  applicant's own (a guard's bank account holder). Never reaches the identity lines. */
  initialsName?: string | null;
}) {
  const short = shortId(userId);
  const phoneText = fmtPhone(phone);
  // Name → phone → short id. The phone only repeats on its own line when a name took the lead.
  const primary = name ?? phoneText ?? short;
  const primaryIsPhone = !name && phoneText != null;
  return (
    <div className="flex items-center gap-[11px]">
      <Avatar>{initialsOf(name ?? initialsName, userId)}</Avatar>
      <div className="min-w-0">
        <div
          className={
            primaryIsPhone
              ? "truncate font-mono text-sm font-medium tabular-nums text-text-strong"
              : "truncate text-sm font-medium text-text-strong"
          }
          title={primaryIsPhone ? hint : undefined}
        >
          {primary}
        </div>
        {name && phoneText && (
          <div className="font-mono text-xs tabular-nums text-muted" title={hint}>
            {phoneText}
          </div>
        )}
        {primary !== short && <div className="font-mono text-xs text-faint">{short}</div>}
      </div>
    </div>
  );
}

export default function ApplicantsPage() {
  const { t, lang } = useLanguage();
  const copy = COPY[lang];
  const [entity, setEntity] = useState<EntityType>("guard");
  const [status, setStatus] = useState<ApprovalStatus>("pending");
  const [guards, setGuards] = useState<GuardProfileAdmin[]>([]);
  const [customers, setCustomers] = useState<CustomerProfileAdmin[]>([]);
  // Per-(entity,status) counts, cached from each tab's last successful fetch. Tab pills + KPI
  // values only show a number once that status' data has actually been loaded — counts for
  // unvisited tabs stay undefined (shown as "—"), never faked.
  const [counts, setCounts] = useState<
    Record<EntityType, Partial<Record<ApprovalStatus, number>>>
  >({ guard: {}, customer: {} });
  // Avg guard approval turnaround (guard-only metric per contract) — null until loaded.
  const [avg, setAvg] = useState<components["schemas"]["AvgApprovalTime"] | null>(null);
  const [loading, setLoading] = useState(true);
  const [hasError, setHasError] = useState(false);
  const [actingId, setActingId] = useState<string | null>(null);
  const [reloadNonce, setReloadNonce] = useState(0);
  const [page, setPage] = useState(1);
  // The guard whose full profile is open in the review modal (null = closed). Customers reuse no
  // modal here — they're approved/rejected inline (no customer detail modal yet).
  const [selected, setSelected] = useState<GuardProfileAdmin | null>(null);

  function statusLabel(s: ApprovalStatus): string {
    const key = STATUS_TKEY[s];
    return key ? t(key) : copy.statusRejected;
  }

  // Fetch the current (entity, status) page + apply via a promise callback (NOT synchronously) so
  // the calling effect never sets state during its synchronous phase (react-hooks/set-state-in-
  // effect). The `alive` guard drops a stale response if the filter changed mid-flight.
  const fetchInto = useCallback(
    (e: EntityType, s: ApprovalStatus, alive: () => boolean) => {
      const req =
        e === "guard"
          ? profileApi
              .GET("/admin/guard-profiles", { params: { query: { approval_status: s } } })
              .then(({ data, error }) => ({
                error,
                list: (error ? [] : (data?.data ?? [])) as GuardProfileAdmin[],
              }))
          : profileApi
              .GET("/admin/customer-profiles", { params: { query: { approval_status: s } } })
              .then(({ data, error }) => ({
                error,
                list: (error ? [] : (data?.data ?? [])) as CustomerProfileAdmin[],
              }));
      return req.then(({ error, list }) => {
        if (!alive()) return;
        setHasError(Boolean(error));
        if (e === "guard") setGuards(list as GuardProfileAdmin[]);
        else setCustomers(list as CustomerProfileAdmin[]);
        setCounts((cur) => ({
          ...cur,
          [e]: { ...cur[e], [s]: error ? undefined : list.length },
        }));
        setLoading(false);
      });
    },
    [],
  );

  // Avg approval time loads once (guard-only metric, filter-independent). Refreshed on reload.
  const fetchAvg = useCallback((alive: () => boolean) => {
    return profileApi.GET("/admin/applicants/avg-approval-time").then(({ data, error }) => {
      if (!alive()) return;
      setAvg(error ? null : (data?.data ?? null));
    });
  }, []);

  // PENDING counts for BOTH populations, from the dedicated count endpoint — so the Guards AND
  // Customers tabs show their applicant numbers on arrival. Without this, a count only appeared
  // after you clicked that tab (its list fetch is what filled the cache), so the Customers tab was
  // permanently blank until visited — the reported "หน้าแอดมินไม่แสดงจำนวนผู้สมัคร". The per-tab list
  // fetch still overwrites its own (entity, pending) entry, so the number stays authoritative.
  const fetchPendingCounts = useCallback((alive: () => boolean) => {
    return profileApi.GET("/admin/applicants/pending-count").then(({ data, error }) => {
      if (!alive() || error) return;
      const c = data?.data;
      if (!c) return;
      setCounts((cur) => ({
        guard: { ...cur.guard, pending: c.guards },
        customer: { ...cur.customer, pending: c.customers },
      }));
    });
  }, []);

  // Re-runs on entity/status change AND on an explicit reload (reloadNonce). The cleanup flips
  // `alive` false, so a response from a superseded run (filter switched, stale retry) is dropped.
  useEffect(() => {
    let alive = true;
    void fetchInto(entity, status, () => alive);
    void fetchAvg(() => alive);
    void fetchPendingCounts(() => alive);
    return () => {
      alive = false;
    };
  }, [entity, status, reloadNonce, fetchInto, fetchAvg, fetchPendingCounts]);

  function selectEntity(next: EntityType) {
    if (next === entity) return;
    setLoading(true);
    setPage(1);
    setEntity(next);
  }

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
    const guardSnapshot = guards;
    const customerSnapshot = customers;
    const countsSnapshot = counts;
    setHasError(false);
    setActingId(userId);
    if (entity === "guard") setGuards((cur) => cur.filter((p) => p.user_id !== userId));
    else setCustomers((cur) => cur.filter((p) => p.user_id !== userId));
    // Decrement the CURRENT (entity,status) count: approve/reject are only reachable from
    // `pending`, so `status` is the right bucket.
    setCounts((cur) => ({
      ...cur,
      [entity]: { ...cur[entity], [status]: Math.max(0, (cur[entity][status] ?? 1) - 1) },
    }));

    const { error } = await runAction(entity, userId, action);

    setActingId(null);
    if (error) {
      setGuards(guardSnapshot); // rollback
      setCustomers(customerSnapshot);
      setCounts(countsSnapshot);
      setHasError(true);
    }
  }

  // Dispatch the approve/reject mutation to the correct entity's endpoints (guard vs customer
  // mirrors). Reject carries an (empty) body so the optional-reason contract is satisfied.
  function runAction(e: EntityType, userId: string, action: "approve" | "reject") {
    if (e === "guard") {
      return action === "approve"
        ? profileApi.POST("/admin/guard-profiles/{user_id}/approve", {
            params: { path: { user_id: userId } },
          })
        : profileApi.POST("/admin/guard-profiles/{user_id}/reject", {
            params: { path: { user_id: userId } },
            body: {},
          });
    }
    return action === "approve"
      ? profileApi.POST("/admin/customer-profiles/{user_id}/approve", {
          params: { path: { user_id: userId } },
        })
      : profileApi.POST("/admin/customer-profiles/{user_id}/reject", {
          params: { path: { user_id: userId } },
          body: {},
        });
  }

  const entityCounts = counts[entity];

  // The rows for the active entity (typed union resolved per branch in render).
  const total = entity === "guard" ? guards.length : customers.length;
  const pageCount = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const curPage = Math.min(page, pageCount);
  const from = total === 0 ? 0 : (curPage - 1) * PAGE_SIZE + 1;
  const to = Math.min(curPage * PAGE_SIZE, total);
  const summary =
    lang === "th" ? `แสดง ${from}–${to} จาก ${total} รายการ` : `Showing ${from}–${to} of ${total}`;

  const guardRows = useMemo(
    () => guards.slice((curPage - 1) * PAGE_SIZE, curPage * PAGE_SIZE),
    [guards, curPage],
  );
  const customerRows = useMemo(
    () => customers.slice((curPage - 1) * PAGE_SIZE, curPage * PAGE_SIZE),
    [customers, curPage],
  );

  // Resolve every loaded applicant id → display name in ONE batch call (the same hook the other
  // admin lists use). The resolver UNIONs guard + customer profiles, so a customer who skipped the
  // optional name at signup still shows the name on their guard profile (and vice versa) instead
  // of a bare short id. Best-effort enrichment: a failed resolve just leaves `name` null and the
  // row falls back to the login phone.
  const applicantIds = useMemo(
    () => (entity === "guard" ? guards : customers).map((p) => p.user_id),
    [entity, guards, customers],
  );
  const { resolve } = useNameResolver(applicantIds, lang);

  /** Best name for a row: this profile's own `full_name` wins, then the resolver's cross-role name
   *  (`.name`, NOT `.label` — the label's "ลูกค้า #5680b50f" fallback is the broken-record string
   *  this screen exists to avoid). Null when nobody anywhere knows this person's name. */
  const bestName = useCallback(
    (userId: string, ownName: string | null | undefined): string | null =>
      ownName?.trim() || resolve(userId).name,
    [resolve],
  );

  // Avg approval time KPI value (em-dash + sample caption when no approvals yet).
  const avgValue =
    avg && avg.avg_hours != null ? copy.avgHours(avg.avg_hours) : copy.avgEmpty;
  const avgCaption =
    avg && avg.sample_size > 0 ? copy.avgSample(avg.sample_size) : undefined;

  return (
    <div className="mx-auto max-w-6xl">
      <PageIntro title={copy.title} lead={copy.lead}>
        <Button variant="secondary" size="sm" onClick={reload}>
          <RefreshCw className="size-4" />
          {t("common.retry")}
        </Button>
      </PageIntro>

      {/* KPI strip (design: pending / approved total / rejected / avg approval time).
          Counts come from the active entity's loaded lists; avg approval time comes from the
          dedicated endpoint (guard-only metric — em-dash + no caption until a guard is approved). */}
      <KpiGrid>
        <KpiCard
          icon={<Clock />}
          label={copy.kpiPending}
          value={entityCounts.pending == null ? t("common.none") : fmtCappedCount(entityCounts.pending)}
        />
        <KpiCard
          icon={<CheckCircle2 />}
          label={copy.kpiApproved}
          value={entityCounts.approved == null ? t("common.none") : fmtCappedCount(entityCounts.approved)}
        />
        <KpiCard
          icon={<XCircle />}
          label={copy.kpiRejected}
          value={entityCounts.rejected == null ? t("common.none") : fmtCappedCount(entityCounts.rejected)}
        />
        <KpiCard
          icon={<Timer />}
          label={copy.kpiAvgTime}
          value={<span data-testid="applicants-avg-approval">{avgValue}</span>}
          caption={avgCaption}
        />
      </KpiGrid>

      {/* Entity tabs — Guards vs Customers (ผู้เรียก รปภ.). The pending count rides each tab's
          loaded data; switching refetches the active status for that population. */}
      <Tabs>
        <Tab
          active={entity === "guard"}
          count={counts.guard.pending == null ? undefined : fmtCappedCount(counts.guard.pending)}
          onClick={() => selectEntity("guard")}
        >
          {copy.typeGuards}
        </Tab>
        <Tab
          active={entity === "customer"}
          count={counts.customer.pending == null ? undefined : fmtCappedCount(counts.customer.pending)}
          onClick={() => selectEntity("customer")}
        >
          {copy.typeCustomers}
        </Tab>
      </Tabs>

      {/* Status tabs; pills show counts only once that status' data has loaded for the entity. */}
      <Tabs>
        {STATUSES.map((s) => (
          <Tab
            key={s}
            active={status === s}
            count={entityCounts[s] == null ? undefined : fmtCappedCount(entityCounts[s])}
            onClick={() => selectStatus(s)}
          >
            {statusLabel(s)}
          </Tab>
        ))}
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
        ) : entity === "guard" ? (
          <>
            <Table>
              <thead>
                <tr>
                  <Th>{copy.colApplicant}</Th>
                  <Th>{copy.colType}</Th>
                  <Th>{copy.colSignedUp}</Th>
                  <Th>{t("applicants.col.experience")}</Th>
                  <Th>{t("applicants.col.workplace")}</Th>
                  <Th>{t("applicants.col.bank")}</Th>
                  <Th>{copy.colStatus}</Th>
                  <Th className="text-right">{t("applicants.col.actions")}</Th>
                </tr>
              </thead>
              <tbody>
                {guardRows.map((p) => (
                  <Tr key={p.user_id} className="cursor-default">
                    <Td>
                      {/* Name (own, else cross-role) → login phone → short id. `account_name` is
                          the bank ACCOUNT HOLDER — often the guard, sometimes a relative — so it
                          stays the avatar-initials backstop it always was and never claims to be
                          the applicant's name. */}
                      <ApplicantIdentity
                        name={bestName(p.user_id, p.full_name)}
                        phone={p.login_phone}
                        userId={p.user_id}
                        hint={copy.loginPhoneHint}
                        initialsName={p.account_name}
                      />
                    </Td>
                    <Td>
                      <Badge tone="blue">{copy.typeGuard}</Badge>
                    </Td>
                    <Td className="whitespace-nowrap text-muted tabular-nums">
                      {fmtSignup(p.created_at, lang)}
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
        ) : (
          <>
            <Table>
              <thead>
                <tr>
                  <Th>{copy.colApplicant}</Th>
                  <Th>{copy.colType}</Th>
                  <Th>{copy.colSignedUp}</Th>
                  <Th title={copy.colOtherContactHint}>{copy.colOtherContact}</Th>
                  <Th>{copy.colCompany}</Th>
                  <Th>{copy.colStatus}</Th>
                  <Th className="text-right">{t("applicants.col.actions")}</Th>
                </tr>
              </thead>
              <tbody>
                {customerRows.map((p) => (
                  <Tr key={p.user_id} className="cursor-default">
                    <Td>
                      {/* full_name is optional at signup for customers, so this is the row that
                          used to read "#5680b50f" — the cross-role name and the login phone are
                          what make it a person again. */}
                      <ApplicantIdentity
                        name={bestName(p.user_id, p.full_name)}
                        phone={p.login_phone}
                        userId={p.user_id}
                        hint={copy.loginPhoneHint}
                      />
                    </Td>
                    <Td>
                      <Badge tone="gray">{copy.typeCustomer}</Badge>
                    </Td>
                    <Td className="whitespace-nowrap text-muted tabular-nums">
                      {fmtSignup(p.created_at, lang)}
                    </Td>
                    <Td>
                      {/* The OPTIONAL extra the customer typed in — deliberately NOT the identity
                          line above. Conflating the two is what hid the applicant's real number. */}
                      <div>
                        <div>{fmtPhone(p.contact_phone) ?? p.email ?? t("common.none")}</div>
                        {p.contact_phone && p.email && (
                          <div className="text-xs text-muted">{p.email}</div>
                        )}
                      </div>
                    </Td>
                    <Td>{p.company_name ?? t("common.none")}</Td>
                    <Td>
                      <Badge tone={STATUS_TONE[p.approval_status]} dot={STATUS_DOT[p.approval_status]}>
                        {statusLabel(p.approval_status)}
                      </Badge>
                    </Td>
                    <Td className="text-right">
                      <div className="inline-flex gap-2">
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

      {/* View the guard applicant's full profile before deciding — reuses the guards detail modal.
          For a pending applicant the modal footer also offers Approve/Reject (decide in place);
          finalized applicants are view-only. (Customers have no detail modal yet → inline only.) */}
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

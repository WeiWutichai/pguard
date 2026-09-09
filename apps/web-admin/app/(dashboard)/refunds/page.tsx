"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { AlertTriangle, Ban, Download, List, Loader2, RefreshCw } from "lucide-react";

import type { components } from "@/api/generated/payment";
import type { BadgeTone } from "@/components/ui";
import {
  Badge,
  Button,
  Field,
  Input,
  KpiCard,
  KpiGrid,
  Modal,
  PageIntro,
  Panel,
  PanelBody,
  PanelHead,
  Pagination,
  Table,
  Td,
  Textarea,
  Th,
  Tr,
} from "@/components/ui";
import { paymentApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import { MAX_NOTE_CHARS } from "../payouts/copy";
import { fmtDay, fmtInstant } from "../payouts/dates";
import { saveText } from "../payouts/download-file";
import { fallbackDownloadName, parseContentDispositionFilename } from "../payouts/download-name";
import { sumDecimalStrings } from "../payouts/money";
import { RefundBatchDetailModal } from "./batch-detail-modal";
import {
  COPY,
  MAX_SELECTED_CUSTOMERS,
  type RefundBatchStatusValue,
  type RefundBatchStep,
} from "./copy";

type RefundPreview = components["schemas"]["RefundPreview"];
type RefundBatch = components["schemas"]["RefundBatch"];

/** History rows per page — the API pages server-side (`limit`/`offset` + a `total`). */
const BATCH_PAGE_SIZE = 10;

/**
 * Status → badge tone. The history is a list an admin SCANS, so the colour has to carry the state
 * before the words are read: green = the money moved, red = the bank said no, amber = we are waiting
 * on the bank, blue = generated and still in the admin's hands, grey = voided, i.e. no longer a live
 * claim on the account. Identical to the payout history's mapping on purpose — the two screens are
 * read by the same person, minutes apart.
 */
const STATUS_TONE: Record<RefundBatchStatusValue, BadgeTone> = {
  generated: "blue",
  uploaded: "amber",
  confirmed: "green",
  rejected: "red",
  voided: "gray",
};

/**
 * Which steps the status endpoint will accept FROM each state — a mirror of `is_legal(from, to)` in
 * `services/payment/src/domain/batch_status.rs` (minus the `→ voided` edges, which live in
 * [VOIDABLE] because voiding is its own endpoint).
 *
 * The backend is still the authority; this table exists so the UI never offers a button that can
 * only end in a 409. `confirmed` and `voided` are terminal, and `rejected` has nowhere to go but a
 * void — the bank refused the file, so the honest next move is to return the money to the queue.
 */
const NEXT_STEPS: Record<RefundBatchStatusValue, readonly RefundBatchStep[]> = {
  generated: ["uploaded"],
  uploaded: ["confirmed", "rejected"],
  confirmed: [],
  rejected: [],
  voided: [],
};

/** The `(Generated | Uploaded | Rejected) → Voided` edges of the same table. A CONFIRMED batch is
 *  money that already left the account: un-marking it would refund those customers twice. */
const VOIDABLE: Record<RefundBatchStatusValue, boolean> = {
  generated: true,
  uploaded: true,
  rejected: true,
  confirmed: false,
  voided: false,
};

/** What the confirm dialog is open for. `null` = closed; the batch rides along so the copy can name
 *  the file and its amount (a void must be confirmed against a number, not an abstraction). */
type BatchAction =
  | { kind: "step"; batch: RefundBatch; step: RefundBatchStep }
  | { kind: "void"; batch: RefundBatch };

/** The name the SERVER chose for a refund file, falling back to a date stamp under the REFUND stem
 *  (`../payouts/download-name`) — one parser, one fallback shape, two streams. */
const downloadNameFrom = (res: { response?: Response }): string =>
  parseContentDispositionFilename(res.response?.headers.get("content-disposition")) ??
  fallbackDownloadName("refund");

/** The day window the preview/export are narrowed to ("" = open end) — the days the money became
 *  owed, not the days the bookings ran. */
type Window = { from: string; to: string };

const EMPTY_WINDOW: Window = { from: "", to: "" };

/** The typed message a 400/409 carries (e.g. "ยังไม่ได้ตั้งบัญชีตัดเงินบริษัท"), when present. */
const apiMessage = (err: unknown): string | null => {
  const message = (err as { error?: { message?: unknown } } | undefined)?.error?.message;
  return typeof message === "string" && message.trim() ? message : null;
};

/**
 * Stream ① — the money the platform owes CUSTOMERS back, exported as its own SCB Business Net file.
 *
 * A sibling of the guard-payout screen rather than a tab on it: one `BCHDET` carries exactly one
 * product code, so a refund can never ride in a payout file, and the two have separate batch tables,
 * separate histories and separate paid-markers. What they DO share is deliberately imported, never
 * re-implemented — the `Content-Disposition` parser, the decimal subtotal helper, the date
 * formatters, the note cap, and the debit-account settings themselves (which stay on the payout
 * screen: one form, one place to get the company's bank details wrong).
 *
 * The refund file carries NO withholding: the money is the customer's own coming back, not
 * assessable income, so `wht = 0` on every line and the writer emits no WHT certificate at all.
 * That is why this screen has no ภ.ง.ด. controls and asks for no tax id.
 */
export default function RefundsPage() {
  const { lang } = useLanguage();
  const c = COPY[lang];

  const [preview, setPreview] = useState<RefundPreview | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [banner, setBanner] = useState<string | null>(null);
  /** The window being edited in the filter row. */
  const [window, setWindow] = useState<Window>(EMPTY_WINDOW);
  /** The window the loaded preview actually reflects — what an export must be run with. */
  const [appliedWindow, setAppliedWindow] = useState<Window>(EMPTY_WINDOW);
  /** The customers ticked to refund — many customers ride ONE SCB file. */
  const [selected, setSelected] = useState<Set<string>>(new Set());

  // ── Batch history ────────────────────────────────────────────────────────────────────────
  // Kept in its own loading/error pair rather than folded into the preview's: the history is the
  // place an admin comes when the export went wrong, so it has to render even when the preview
  // (a heavier query across profile) is failing.
  const [batches, setBatches] = useState<RefundBatch[]>([]);
  const [batchTotal, setBatchTotal] = useState(0);
  const [batchPage, setBatchPage] = useState(1);
  const [batchLoading, setBatchLoading] = useState(true);
  /** Monotonic id of the newest history fetch — see `loadBatches` (last request wins). */
  const batchReq = useRef(0);
  const [batchError, setBatchError] = useState(false);
  /** The batch whose stored file is being re-fetched (one row's spinner, not the page's). */
  const [downloadingId, setDownloadingId] = useState<string | null>(null);
  /** Errors raised BY the history panel (a failed re-download). Its own banner, shown inside the
   *  panel: the page-level one sits above two long tables, so an admin who just clicked a button
   *  down here would never see the reason it did nothing. */
  const [historyBanner, setHistoryBanner] = useState<string | null>(null);
  /** The batch whose per-obligation drill-down is open (`null` = closed). Only `id`, `file_ref` and
   *  `status` are read from it — all effectively immutable while the modal is up — so it does not
   *  matter that a refresh rebuilds the row it came from. */
  const [detailBatch, setDetailBatch] = useState<RefundBatch | null>(null);
  /** The open confirm dialog — a status step or a void. */
  const [action, setAction] = useState<BatchAction | null>(null);
  const [actionNote, setActionNote] = useState("");
  const [actionBusy, setActionBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const load = useCallback((win: Window, alive: () => boolean = () => true) => {
    return paymentApi
      .GET("/admin/refunds/preview", {
        params: { query: { from: win.from || undefined, to: win.to || undefined } },
      })
      .then((res) => {
        if (!alive()) return;
        if (res.error) {
          setLoadError(true);
        } else {
          setLoadError(false);
          const data = res.data?.data ?? null;
          setPreview(data);
          setAppliedWindow(win);
          // Default to refunding everyone refundable in the window; the admin unticks to narrow.
          setSelected(new Set((data?.recipients ?? []).map((r) => r.customer_id)));
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
    void load(EMPTY_WINDOW, () => alive);
    return () => {
      alive = false;
    };
  }, [load]);

  const reload = (win: Window = appliedWindow) => {
    setLoading(true);
    setBanner(null);
    void load(win);
  };

  /**
   * Fetch one page of the refund-file history.
   *
   * Takes no copy (`c`) so it stays referentially stable across a language toggle — the error is a
   * flag, rendered in the current locale. Sets NO state synchronously (the spinner is raised by the
   * callers, exactly as `reload` does for `load`): this runs from an effect, and a synchronous
   * setState there is a cascading render.
   */
  const loadBatches = useCallback((page: number, alive: () => boolean = () => true) => {
    // Last request wins. Two paths fetch this list (the page effect and the explicit refreshes
    // after an export / a status change), so a slow reply for page 1 could otherwise land after the
    // reply for page 2 and leave the rows disagreeing with the pager under them.
    const seq = ++batchReq.current;
    return paymentApi
      .GET("/admin/refunds/batches", {
        params: { query: { limit: BATCH_PAGE_SIZE, offset: (page - 1) * BATCH_PAGE_SIZE } },
      })
      .then((res) => {
        if (!alive() || seq !== batchReq.current) return;
        if (res.error) {
          setBatchError(true);
        } else {
          setBatchError(false);
          setBatches(res.data?.data?.batches ?? []);
          setBatchTotal(res.data?.data?.total ?? 0);
        }
        setBatchLoading(false);
      })
      .catch(() => {
        if (!alive() || seq !== batchReq.current) return;
        setBatchError(true);
        setBatchLoading(false);
      });
  }, []);

  useEffect(() => {
    let alive = true;
    void loadBatches(batchPage, () => alive);
    return () => {
      alive = false;
    };
  }, [loadBatches, batchPage]);

  /** Re-fetch a page of history with the spinner up. */
  const refreshBatches = (page: number = batchPage) => {
    setBatchLoading(true);
    void loadBatches(page);
  };

  /** Jump the history back to page 1, where a just-created batch lands (newest first). */
  const showLatestHistory = () => {
    setBatchLoading(true);
    setBatchPage(1);
    // Already on page 1 → the state does not change, so the effect will NOT re-fire; fetch here.
    if (batchPage === 1) void loadBatches(1);
  };

  const recipients = useMemo(() => preview?.recipients ?? [], [preview]);
  const excluded = preview?.excluded ?? [];
  const picked = useMemo(
    () => recipients.filter((r) => selected.has(r.customer_id)),
    [recipients, selected],
  );
  const allPicked = recipients.length > 0 && picked.length === recipients.length;
  const nothingPicked = picked.length === 0;
  /** One file names at most `MAX_SELECTED_CUSTOMERS` customers (the server 400s a longer list, and
   *  refunds nobody) — caught at the keyboard so the admin splits the run instead of losing it. */
  const overCap = picked.length > MAX_SELECTED_CUSTOMERS;

  const toggle = (customerId: string) =>
    setSelected((prev) => {
      const next = new Set(prev);
      if (!next.delete(customerId)) next.add(customerId);
      return next;
    });

  const toggleAll = () =>
    setSelected(allPicked ? new Set() : new Set(recipients.map((r) => r.customer_id)));

  const runExport = async () => {
    if (nothingPicked || overCap) return;
    setExporting(true);
    setBanner(null);
    // One file, many customers: send exactly the ticked ids + the window the preview was built
    // with, so the persisted refunded-markers cover the same rows the admin just saw.
    const res = await paymentApi.POST("/admin/refunds/export", {
      body: {
        customer_ids: picked.map((r) => r.customer_id),
        from: appliedWindow.from || null,
        to: appliedWindow.to || null,
      },
      parseAs: "text",
    });
    setExporting(false);
    if (res.error || typeof res.data !== "string") {
      setBanner(apiMessage(res.error) ?? c.exportError);
      return;
    }
    // Save under the name the SERVER chose (`SCB_file_reference_<file ref>.txt`, doc line 58) —
    // that string is the bank's reference for this batch and the `refund_batches.file_ref` row, so
    // it is the only thing tying the file on disk to what we just marked refunded.
    saveText(res.data, downloadNameFrom(res));
    reload(); // the settled obligations drop out of the backlog
    showLatestHistory(); // …and turn up in the history as a new `generated` batch
  };

  /**
   * Re-download the STORED text of an already-generated file.
   *
   * The export is a one-way door — it marks the obligations processed and streams the file once — so
   * a failed download used to leave those customers marked refunded with no file to refund them.
   * This is the way back: the same bytes, under the same bank reference, never regenerated.
   */
  const redownload = async (batch: RefundBatch) => {
    setDownloadingId(batch.id);
    setHistoryBanner(null);
    const res = await paymentApi.GET("/admin/refunds/batches/{id}/file", {
      params: { path: { id: batch.id } },
      parseAs: "text",
    });
    setDownloadingId(null);
    if (res.error || typeof res.data !== "string") {
      setHistoryBanner(apiMessage(res.error) ?? c.downloadError);
      return;
    }
    saveText(res.data, downloadNameFrom(res));
  };

  const openAction = (next: BatchAction) => {
    setAction(next);
    setActionNote("");
    setActionError(null);
  };

  /** Dismiss the dialog — but never out from under an in-flight write, or the admin is left not
   *  knowing whether the void landed. */
  const closeAction = () => {
    if (!actionBusy) setAction(null);
  };

  const trimmedNote = actionNote.trim();
  /** A void without a reason is refused by the server (400) and is meaningless six months later. */
  const actionReady = action !== null && (action.kind !== "void" || trimmedNote.length > 0);

  const submitAction = async () => {
    if (!action || !actionReady) return;
    setActionBusy(true);
    setActionError(null);
    const res =
      action.kind === "void"
        ? await paymentApi.POST("/admin/refunds/batches/{id}/void", {
            params: { path: { id: action.batch.id } },
            body: { reason: trimmedNote },
          })
        : await paymentApi.POST("/admin/refunds/batches/{id}/status", {
            params: { path: { id: action.batch.id } },
            body: { status: action.step, note: trimmedNote || null },
          });
    setActionBusy(false);
    if (res.error) {
      // A 409 here means the row on screen is stale — another tab (or another admin) already moved
      // this batch on. Show the server's own Thai message and reload the page of history, so the
      // buttons on offer match what the batch actually is now.
      setActionError(apiMessage(res.error) ?? c.actionError);
      refreshBatches();
      return;
    }
    setAction(null);
    refreshBatches();
    // A void hands every obligation in the batch back to the refundable backlog — refresh the
    // preview too so those customers visibly REAPPEAR above, instead of the admin having to trust
    // that they did.
    if (action.kind === "void") reload();
  };

  // Server-side paging (`limit`/`offset` + `total`), so the page never holds more than one screen of
  // history however many files have been generated.
  const batchPageCount = Math.max(1, Math.ceil(batchTotal / BATCH_PAGE_SIZE));
  const batchFrom = batchTotal === 0 ? 0 : (batchPage - 1) * BATCH_PAGE_SIZE + 1;
  const batchTo = Math.min(batchPage * BATCH_PAGE_SIZE, batchTotal);
  const actionTitle =
    action === null
      ? ""
      : action.kind === "void"
        ? c.voidTitle
        : c.recordTitle(c.statusLabels[action.step]);

  return (
    <div className="space-y-6">
      <PageIntro title={c.title} lead={c.subtitle} />

      {loadError && (
        <div
          role="alert"
          className="flex items-center gap-2 rounded-lg border border-danger/40 bg-danger-bg px-4 py-3 text-sm text-danger"
        >
          <AlertTriangle className="size-4 shrink-0" /> {c.loadError}
        </div>
      )}
      {banner && (
        <div
          role="alert"
          className="flex items-center gap-2 rounded-lg border border-amber-300/50 bg-amber-50/60 px-4 py-3 text-sm text-amber-800 dark:bg-amber-950/30 dark:text-amber-300"
        >
          <AlertTriangle className="size-4 shrink-0" /> {banner}
        </div>
      )}

      {/* ── What this file is, and where its settings live ────
          No settings form of its own, on purpose: the debit account and the fee-charge code are
          ONE set of company bank details shared by both money streams, and a second form editing
          the same rows is how the two end up disagreeing. The link goes to the screen that owns
          them. The ภ.ง.ด. block is absent for a stronger reason — a refund carries no withholding
          at all, so those settings are not merely elsewhere, they are inapplicable. */}
      <Panel>
        <PanelBody className="space-y-2 text-[12.5px] text-muted">
          <p>{c.scopeNote}</p>
          <p>{c.noWhtNote}</p>
          <p>
            {c.configNote}{" "}
            <Link href="/payouts" className="font-medium text-brand-int hover:underline">
              {c.configLink}
            </Link>
          </p>
        </PanelBody>
      </Panel>

      {/* ── Preview + export ─────────────────────────────────── */}
      <Panel>
        <PanelHead title={c.preview}>
          <div className="flex items-center gap-2">
            <Button variant="ghost" onClick={() => reload()} disabled={loading}>
              <RefreshCw className={`size-4 ${loading ? "animate-spin" : ""}`} />
              {c.refresh}
            </Button>
            <Button onClick={runExport} disabled={exporting || loading || nothingPicked || overCap}>
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
          {/* Day window — which obligations the run covers (when the money became owed) */}
          <div className="mb-5 flex flex-wrap items-end gap-3">
            <Field label={c.dateFrom} className="mb-0">
              <Input
                type="date"
                value={window.from}
                max={window.to || undefined}
                onChange={(e) => setWindow((w) => ({ ...w, from: e.target.value }))}
                className="w-44"
              />
            </Field>
            <Field label={c.dateTo} className="mb-0">
              <Input
                type="date"
                value={window.to}
                min={window.from || undefined}
                onChange={(e) => setWindow((w) => ({ ...w, to: e.target.value }))}
                className="w-44"
              />
            </Field>
            <Button variant="secondary" onClick={() => reload(window)} disabled={loading}>
              {c.applyFilter}
            </Button>
            {(appliedWindow.from || appliedWindow.to) && (
              <Button
                variant="ghost"
                onClick={() => {
                  setWindow(EMPTY_WINDOW);
                  reload(EMPTY_WINDOW);
                }}
                disabled={loading}
              >
                {c.clearFilter}
              </Button>
            )}
          </div>

          <KpiGrid>
            <KpiCard
              label={c.recipients}
              value={String(picked.length)}
              caption={c.ofTotal(preview?.recipient_count ?? 0)}
            />
            <KpiCard
              label={c.totalAmount}
              value={`฿${sumDecimalStrings(picked.map((r) => r.amount))}`}
              caption={c.selectedOnly}
            />
            <KpiCard
              label={c.obligations}
              value={String(picked.reduce((n, r) => n + r.obligation_count, 0))}
              caption={c.selectedOnly}
            />
          </KpiGrid>

          <p className="mt-2 text-xs text-neutral-500">{c.exportHint}</p>

          {loading ? (
            <div className="flex items-center justify-center py-10 text-neutral-400">
              <Loader2 className="size-6 animate-spin" />
            </div>
          ) : recipients.length === 0 ? (
            <p className="py-8 text-center text-sm text-neutral-500">{c.nobody}</p>
          ) : (
            <>
              <Table className="mt-4">
                <thead>
                  <Tr>
                    <Th className="w-10">
                      <input
                        type="checkbox"
                        aria-label={c.selectAll}
                        checked={allPicked}
                        onChange={toggleAll}
                        className="size-4 accent-brand-int"
                      />
                    </Th>
                    <Th>{c.customer}</Th>
                    <Th>{c.proxy}</Th>
                    <Th className="text-right">{c.obligations}</Th>
                    <Th className="text-right">{c.amount}</Th>
                  </Tr>
                </thead>
                <tbody>
                  {recipients.map((r) => (
                    <Tr key={r.customer_id}>
                      <Td>
                        <input
                          type="checkbox"
                          aria-label={`${c.selectOne} ${r.name}`}
                          checked={selected.has(r.customer_id)}
                          onChange={() => toggle(r.customer_id)}
                          className="size-4 accent-brand-int"
                        />
                      </Td>
                      <Td title={r.customer_id}>{r.name}</Td>
                      <Td className="font-mono text-xs">{r.proxy_masked}</Td>
                      <Td className="text-right tabular-nums">{r.obligation_count}</Td>
                      <Td className="text-right font-semibold tabular-nums">฿{r.amount}</Td>
                    </Tr>
                  ))}
                </tbody>
              </Table>
              {nothingPicked && (
                <p className="mt-3 text-sm text-amber-700 dark:text-amber-400">{c.pickSomeone}</p>
              )}
              {overCap && (
                <p role="alert" className="mt-3 text-sm text-danger">
                  {c.tooManyCustomers(MAX_SELECTED_CUSTOMERS)}
                </p>
              )}
            </>
          )}

          {excluded.length > 0 && (
            <div className="mt-6">
              <div className="mb-2 flex items-center gap-2 text-sm font-medium text-red-600 dark:text-red-400">
                <AlertTriangle className="size-4" /> {c.excludedTitle} ({excluded.length})
              </div>
              {/* Unlike the payout screen's excluded table, these ids are NOT links: the fix for a
                  missing PromptPay destination is the customer's own registration phone, which no
                  admin screen can edit, and `/customers` takes no id parameter — a link that landed
                  on an unfiltered list would look like a remedy and be none. The full id is shown
                  so an operator can still carry the row into a support ticket or the DB. */}
              <p className="mb-2 text-xs text-neutral-500">{c.excludedHint}</p>
              <Table>
                <thead>
                  <Tr>
                    <Th>{c.customer}</Th>
                    <Th>{c.reason}</Th>
                    <Th className="text-right">{c.obligations}</Th>
                  </Tr>
                </thead>
                <tbody>
                  {excluded.map((x) => (
                    <Tr key={x.customer_id}>
                      <Td className="font-mono text-xs" title={x.customer_id}>
                        {x.customer_id.slice(0, 8)}
                      </Td>
                      <Td>
                        <Badge tone="red">{x.reason}</Badge>
                      </Td>
                      <Td className="text-right tabular-nums">{x.obligation_count}</Td>
                    </Tr>
                  ))}
                </tbody>
              </Table>
            </div>
          )}
        </PanelBody>
      </Panel>

      {/* ── Batch history ────────────────────────────────────
          What happened to the refund files we already generated. The export is a one-way door: it
          marks the obligations processed and streams the file once, so without this an admin whose
          download failed would have customers marked refunded and no file to refund them with. */}
      <Panel>
        <PanelHead title={c.history} sub={c.historyHint}>
          <Button variant="ghost" onClick={() => refreshBatches()} disabled={batchLoading}>
            <RefreshCw className={`size-4 ${batchLoading ? "animate-spin" : ""}`} />
            {c.refresh}
          </Button>
        </PanelHead>

        {historyBanner && (
          <p
            role="alert"
            className="flex items-center gap-2 border-b border-border px-5 py-3 text-sm text-danger"
          >
            <AlertTriangle className="size-4 shrink-0" /> {historyBanner}
          </p>
        )}

        {batchError ? (
          <p className="px-5 py-8 text-center text-sm text-danger">{c.historyError}</p>
        ) : batchLoading && batches.length === 0 ? (
          <div className="flex items-center justify-center py-10 text-neutral-400">
            <Loader2 className="size-6 animate-spin" />
          </div>
        ) : batches.length === 0 ? (
          <p className="px-5 py-8 text-center text-sm text-neutral-500">{c.historyEmpty}</p>
        ) : (
          <>
            <Table>
              <thead>
                <Tr>
                  <Th>{c.fileRef}</Th>
                  <Th>{c.valueDate}</Th>
                  <Th className="text-right">{c.people}</Th>
                  <Th className="text-right">{c.totalAmount}</Th>
                  <Th>{c.status}</Th>
                  <Th>{c.createdAt}</Th>
                  <Th className="text-right">{c.actions}</Th>
                </Tr>
              </thead>
              <tbody>
                {batches.map((b) => {
                  // Only the steps the lifecycle actually allows from THIS row's state get a
                  // button — a control that can only ever answer 409 is worse than no control.
                  const steps = NEXT_STEPS[b.status] ?? [];
                  const canVoid = VOIDABLE[b.status] ?? false;
                  const downloading = downloadingId === b.id;
                  return (
                    <Tr key={b.id}>
                      {/* The bank's reference for the batch — the string on the file in the admin's
                          Downloads folder and in the SCB Business Net portal. */}
                      <Td className="font-mono text-xs" title={b.system_ref}>
                        {b.file_ref}
                      </Td>
                      <Td className="whitespace-nowrap tabular-nums">{fmtDay(b.value_date, lang)}</Td>
                      <Td className="text-right tabular-nums">{b.recipient_count}</Td>
                      <Td className="text-right font-semibold tabular-nums">฿{b.total_amount}</Td>
                      <Td>
                        <Badge tone={STATUS_TONE[b.status] ?? "gray"}>
                          {c.statusLabels[b.status] ?? b.status}
                        </Badge>
                        {/* Recording the bank's message / the void reason is pointless unless it is
                            shown back — this is where an admin finds out WHY a file bounced. */}
                        {b.void_reason ? (
                          <p className="mt-1 max-w-[15rem] text-xs text-muted">
                            {c.voidedReasonPrefix}: {b.void_reason}
                          </p>
                        ) : null}
                        {b.status_note ? (
                          <p className="mt-1 max-w-[15rem] text-xs text-muted">{b.status_note}</p>
                        ) : null}
                      </Td>
                      <Td className="whitespace-nowrap text-muted tabular-nums">
                        {fmtInstant(b.created_at, lang)}
                      </Td>
                      <Td>
                        <div className="flex flex-wrap items-center justify-end gap-2">
                          {/* Offered on EVERY row, `confirmed` included: a confirmed batch is
                              exactly where the per-customer release matters, because the whole-file
                              void is (correctly) gone by then. */}
                          <Button size="sm" variant="ghost" onClick={() => setDetailBatch(b)}>
                            <List className="size-4" />
                            {c.detail.viewItems}
                          </Button>
                          <Button
                            size="sm"
                            variant="secondary"
                            onClick={() => void redownload(b)}
                            disabled={!b.has_file || downloading}
                            title={b.has_file ? undefined : c.noStoredFile}
                          >
                            {downloading ? (
                              <Loader2 className="size-4 animate-spin" />
                            ) : (
                              <Download className="size-4" />
                            )}
                            {c.redownload}
                          </Button>
                          {steps.map((step) => (
                            <Button
                              key={step}
                              size="sm"
                              variant="ghost"
                              onClick={() => openAction({ kind: "step", batch: b, step })}
                            >
                              {c.stepLabels[step]}
                            </Button>
                          ))}
                          {canVoid && (
                            <Button
                              size="sm"
                              variant="danger-ghost"
                              onClick={() => openAction({ kind: "void", batch: b })}
                            >
                              <Ban className="size-4" />
                              {c.voidBtn}
                            </Button>
                          )}
                        </div>
                      </Td>
                    </Tr>
                  );
                })}
              </tbody>
            </Table>
            <Pagination
              page={batchPage}
              pageCount={batchPageCount}
              onPage={(p) => {
                setBatchLoading(true);
                setBatchPage(p);
              }}
              summary={c.listSummary(batchFrom, batchTo, batchTotal)}
            />
          </>
        )}
      </Panel>

      {/* ── Confirm a status step / a void ───────────────────
          Deliberately a modal and NOT window.confirm: a browser dialog cannot carry the required
          reason, cannot say what voiding costs, and blocks automation (Playwright/e2e). The void
          confirm stays disabled until a non-blank reason is typed — that IS the friction. */}
      <Modal open={action !== null} onClose={closeAction} title={actionTitle}>
        {action && (
          <>
            <p className="font-mono text-xs text-faint">{action.batch.file_ref}</p>
            {action.kind === "void" ? (
              <>
                <p className="mt-3 rounded-lg border border-danger/35 bg-danger-bg px-3.5 py-3 text-sm text-danger">
                  {c.voidWarning(action.batch.recipient_count, action.batch.total_amount)}
                </p>
                <Field label={c.voidReason} required hint={c.voidReasonHint} className="mt-4 mb-0">
                  <Textarea
                    value={actionNote}
                    onChange={(e) => setActionNote(e.target.value)}
                    placeholder={c.voidReasonPlaceholder}
                    maxLength={MAX_NOTE_CHARS}
                    autoFocus
                  />
                </Field>
              </>
            ) : (
              <>
                {/* `confirmed` is NOT like the other steps and must not share their reassuring copy.
                    Recording `uploaded`/`rejected` really is just writing down what the bank did —
                    both are reversible into a void, nothing about the money moves. Confirming is
                    the one-way door: it makes the batch terminal, which removes the whole-file void
                    and leaves every obligation in it permanently marked refunded. A mis-click on
                    the wrong history row, or an eager click before the bank has actually settled,
                    cannot be undone at batch level — only per customer, from the drill-down, which
                    is why the warning names that as the remaining recourse. */}
                {action.step === "confirmed" ? (
                  <p className="mt-3 rounded-lg border border-danger/35 bg-danger-bg px-3.5 py-3 text-sm text-danger">
                    {c.confirmedWarning}
                  </p>
                ) : (
                  <p className="mt-3 text-sm text-muted">
                    {c.recordBody(c.statusLabels[action.step])}
                  </p>
                )}
                <Field label={c.noteLabel} hint={c.noteHint} className="mt-4 mb-0">
                  <Textarea
                    value={actionNote}
                    onChange={(e) => setActionNote(e.target.value)}
                    maxLength={MAX_NOTE_CHARS}
                  />
                </Field>
              </>
            )}
            {actionError && (
              <p role="alert" className="mt-3 text-sm text-danger">
                {actionError}
              </p>
            )}
            <div className="mt-5 flex justify-end gap-2.5">
              <Button variant="secondary" onClick={closeAction} disabled={actionBusy}>
                {action.kind === "void" ? c.keepFile : c.cancel}
              </Button>
              <Button
                // The confirm button carries the weight of the step: red for a void, amber for
                // `confirmed` (irreversible, but a GOOD outcome — red would read as "the bank
                // refused"), plain primary for the two reversible records.
                variant={
                  action.kind === "void"
                    ? "danger"
                    : action.step === "confirmed"
                      ? "accent"
                      : "primary"
                }
                onClick={() => void submitAction()}
                disabled={actionBusy || !actionReady}
              >
                {actionBusy ? (
                  <Loader2 className="size-4 animate-spin" />
                ) : action.kind === "void" ? (
                  <Ban className="size-4" />
                ) : null}
                {action.kind === "void" ? c.voidConfirm : c.stepLabels[action.step]}
              </Button>
            </div>
          </>
        )}
      </Modal>

      {/* ── One file's obligations + the per-customer release ──
          The everyday partial failure: SCB accepts the FILE and still fails a credit line (a
          PromptPay proxy the customer never linked). The batch is honestly confirmed, so the
          whole-file void is gone — this is the only way that money gets back into the queue. */}
      <RefundBatchDetailModal
        // Remount per file: every open then starts from a clean slate — no stale items, tick-list
        // or typed reason carried over from the last file — without the modal resetting its own
        // state inside an effect.
        key={detailBatch?.id ?? "closed"}
        batch={detailBatch}
        onClose={() => setDetailBatch(null)}
        onReleased={() => {
          // Both lists, for the same reason the whole-batch void refreshes both: the released
          // customers must visibly REAPPEAR in the backlog rather than being taken on trust, and
          // the history row's counts came from the items that just changed.
          refreshBatches();
          reload();
        }}
      />
    </div>
  );
}

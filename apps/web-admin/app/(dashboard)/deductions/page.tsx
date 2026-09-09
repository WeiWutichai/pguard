"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import {
  AlertTriangle,
  Ban,
  Download,
  Landmark,
  List,
  Loader2,
  RefreshCw,
} from "lucide-react";

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
import { signOfDecimalString } from "../payouts/money";
import { DeductionBatchDetailModal } from "./batch-detail-modal";
import {
  COPY,
  CUT_COMPONENTS,
  DEFERRED_BUG_COMPONENTS,
  LEDGER_PAGE_SIZE,
  type CutComponent,
  type DeductionBatchStatusValue,
  type DeductionBatchStep,
} from "./copy";
import { TaxReports } from "./tax-reports";

type DeductionPreview = components["schemas"]["DeductionPreview"];
type DeductionBatch = components["schemas"]["DeductionBatch"];
type PreviewCutJob = components["schemas"]["PreviewCutJob"];

/** History rows per page — the API pages server-side (`limit`/`offset` + a `total`). */
const BATCH_PAGE_SIZE = 10;

/**
 * Status → badge tone. The history is a list an admin SCANS, so the colour has to carry the state
 * before the words are read: green = the money moved, red = the bank said no, amber = we are waiting
 * on the bank, blue = generated and still in the admin's hands, grey = voided, i.e. no longer a live
 * claim on the account. Identical to the payout and refund histories' mapping on purpose — the three
 * screens are read by the same person, minutes apart.
 */
const STATUS_TONE: Record<DeductionBatchStatusValue, BadgeTone> = {
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
 * void — the bank refused the file, so the honest next move is to return the jobs to the backlog.
 */
const NEXT_STEPS: Record<DeductionBatchStatusValue, readonly DeductionBatchStep[]> = {
  generated: ["uploaded"],
  uploaded: ["confirmed", "rejected"],
  confirmed: [],
  rejected: [],
  voided: [],
};

/** The `(Generated | Uploaded | Rejected) → Voided` edges of the same table. A CONFIRMED batch is
 *  money that already reached the revenue account: un-marking it would sweep the same cut twice. */
const VOIDABLE: Record<DeductionBatchStatusValue, boolean> = {
  generated: true,
  uploaded: true,
  rejected: true,
  confirmed: false,
  voided: false,
};

/** What the confirm dialog is open for. `null` = closed; the batch rides along so the copy can name
 *  the file and its amount (a void must be confirmed against a number, not an abstraction). */
type BatchAction =
  | { kind: "step"; batch: DeductionBatch; step: DeductionBatchStep }
  | { kind: "void"; batch: DeductionBatch };

/** The name the SERVER chose for a sweep file, falling back to a date stamp under the DEDUCTION
 *  stem (`../payouts/download-name`) — one parser, one fallback shape, three streams. */
const downloadNameFrom = (res: { response?: Response }): string =>
  parseContentDispositionFilename(res.response?.headers.get("content-disposition")) ??
  fallbackDownloadName("deduction");

/** The day window the preview/export are narrowed to ("" = open end) — the days the jobs were
 *  SETTLED, which is when their cut became final, not the days the bookings ran. */
type Window = { from: string; to: string };

const EMPTY_WINDOW: Window = { from: "", to: "" };

/** The typed message a 400/409 carries (e.g. "ยังไม่ได้ตั้งบัญชีรับรายได้บริษัท"), when present. */
const apiMessage = (err: unknown): string | null => {
  const message = (err as { error?: { message?: unknown } } | undefined)?.error?.message;
  return typeof message === "string" && message.trim() ? message : null;
};

/**
 * A failed preview, kept as more than a boolean.
 *
 * The aggregation is BOUNDED (`MAX_SWEEP_BACKLOG_ROWS`, `services/payment/src/repo/mod.rs`) and
 * refuses an over-wide window with a typed 400 rather than truncating — a money total that is short
 * looks exactly like a correct one. That refusal is an ACTION the admin can take, not a breakage, so
 * it must not render as the same flat "failed to load" a dead service does. `clientFault` carries the
 * distinction (400 = we asked for too much) and `message` the server's own Thai sentence, shown
 * underneath our bilingual explanation rather than instead of it.
 */
type PreviewError = { message: string | null; clientFault: boolean };

/** A money figure, or an em dash when the PREVIEW itself did not load. Never "฿0.00" as a stand-in:
 *  the contract makes every amount required, so the only reason one is absent is that there are no
 *  numbers at all — and a confident zero is the one reading an admin must never be given. */
const baht = (amount: string | null): string => (amount === null ? "—" : `฿${amount}`);

/**
 * One component's total across the window.
 *
 * An exhaustive `switch` rather than an index by key: the day a sixth component is added to the
 * contract this stops compiling, instead of quietly leaving new money out of the breakdown while the
 * grand total keeps including it — a table whose rows do not add up to its own total is exactly the
 * failure this screen exists to prevent.
 *
 * Returns a bare `string` with NO `?? "0.00"`: every one of these is `required` in the contract, so a
 * missing amount is now a build error rather than a row that renders a confident ฿0.00 for money the
 * server never sent. That fallback was a lie in the only direction that matters here — it made an
 * absent figure indistinguishable from a genuinely zero one.
 */
function componentTotal(preview: DeductionPreview, key: CutComponent): string {
  switch (key) {
    case "commission":
      return preview.commission_total;
    case "cancellation_fee":
      return preview.cancellation_fee_total;
    case "tip":
      return preview.tip_total;
    case "unpaid_guard_share":
      return preview.unpaid_guard_share_total;
    case "rounding_adjustment":
      return preview.rounding_adjustment_total;
  }
}

/** The same five components on ONE job's ledger row. Same exhaustiveness argument as above. */
function jobComponent(job: PreviewCutJob, key: CutComponent): string {
  switch (key) {
    case "commission":
      return job.commission;
    case "cancellation_fee":
      return job.cancellation_fee;
    case "tip":
      return job.tip;
    case "unpaid_guard_share":
      return job.unpaid_guard_share;
    case "rounding_adjustment":
      return job.rounding_adjustment;
  }
}

/**
 * Stream ② — **ยอดที่โดนหักเข้าระบบ**, the platform's own cut, swept into the company revenue
 * account by its own SCB file (product `OAT`).
 *
 * A sibling of the guard-payout and customer-refund screens rather than a tab on either: one
 * `BCHDET` carries exactly one product code, so a sweep can never ride in a payout or refund file,
 * and the three have separate batch tables, separate histories and separate paid-markers. What they
 * DO share is imported, never re-implemented — the `Content-Disposition` parser, the download
 * helper, the decimal subtotal, the date formatters, the note cap, and the company bank details
 * themselves (which stay on the payout screen: one form, one place to get them wrong).
 *
 * THE DESIGN POINT THIS SCREEN EXISTS TO MAKE VISIBLE, and which no future "simplification" should
 * undo: the file sweeps what the platform KEEPS, and NOTHING ELSE. The 7% VAT charged to customers
 * and the tax withheld from guards sit in the same receiving account and are the Revenue
 * Department's money — a liability from the moment we take it, remitted by e-filing (ภ.พ.30
 * monthly, ภ.ง.ด.3/53 by the 7th of the following month), never by a bulk transfer file. Sweeping
 * either into the revenue account would move the department's money into company income. So they are
 * shown here ALONGSIDE the cut, explicitly excluded from its total, and they get REPORTS instead —
 * see [TaxReports].
 *
 * The cut itself is shown ITEMISED for the same reason. Two of its five components (`tip`,
 * `unpaid_guard_share`) exist only because of known, DEFERRED bugs; they contribute real money
 * today, so the report has to show them honestly, but folded into a single lump sum an admin would
 * never learn that part of "revenue" is two defects — and the day either is fixed the total would
 * move for no visible reason.
 *
 * THE THIRD FIGURE, and the newest: what was BILLED and never COLLECTED. The completion reconcile
 * can settle a job ABOVE what the customer pre-paid (an added tip, a corrected `base_fee`) and
 * captures nothing for the difference, so part of the cut those five components add up to is not in
 * the bank. The contract therefore subtracts it — `billed_cut_total − uncollected_total =
 * total_amount` — and this screen shows all three lines rather than only the smaller answer. It has
 * to: the account being debited is the same one holding the Revenue Department's VAT and the guards'
 * unpaid income, so sweeping money that never arrived draws down precisely what is not ours, and an
 * admin reconciling the bank credit against a silently-shrunk figure would have no way to see why.
 */
export default function DeductionsPage() {
  const { lang } = useLanguage();
  const c = COPY[lang];

  const [preview, setPreview] = useState<DeductionPreview | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<PreviewError | null>(null);
  const [exporting, setExporting] = useState(false);
  const [banner, setBanner] = useState<string | null>(null);
  /** The window being edited in the filter row. */
  const [window, setWindow] = useState<Window>(EMPTY_WINDOW);
  /** The window the loaded preview actually reflects — what an export must be run with. */
  const [appliedWindow, setAppliedWindow] = useState<Window>(EMPTY_WINDOW);
  /** Which page of the (client-paged) per-job ledger is on screen. */
  const [ledgerPage, setLedgerPage] = useState(1);

  // ── Batch history ────────────────────────────────────────────────────────────────────────
  // Kept in its own loading/error pair rather than folded into the preview's: the history is the
  // place an admin comes when the export went wrong, so it has to render even when the preview
  // (a heavier aggregation over every settled job in the window) is failing.
  const [batches, setBatches] = useState<DeductionBatch[]>([]);
  const [batchTotal, setBatchTotal] = useState(0);
  const [batchPage, setBatchPage] = useState(1);
  const [batchLoading, setBatchLoading] = useState(true);
  /** Monotonic id of the newest history fetch — see `loadBatches` (last request wins). */
  const batchReq = useRef(0);
  const [batchError, setBatchError] = useState(false);
  /** The batch whose stored file is being re-fetched (one row's spinner, not the page's). */
  const [downloadingId, setDownloadingId] = useState<string | null>(null);
  /** Errors raised BY the history panel (a failed re-download). Its own banner, shown inside the
   *  panel: the page-level one sits above several long tables, so an admin who just clicked a
   *  button down here would never see the reason it did nothing. */
  const [historyBanner, setHistoryBanner] = useState<string | null>(null);
  /** The batch whose per-job drill-down is open (`null` = closed). */
  const [detailBatch, setDetailBatch] = useState<DeductionBatch | null>(null);
  /** The open confirm dialog — a status step or a void. */
  const [action, setAction] = useState<BatchAction | null>(null);
  const [actionNote, setActionNote] = useState("");
  const [actionBusy, setActionBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const load = useCallback((win: Window, alive: () => boolean = () => true) => {
    return paymentApi
      .GET("/admin/deductions/preview", {
        params: { query: { from: win.from || undefined, to: win.to || undefined } },
      })
      .then((res) => {
        if (!alive()) return;
        if (res.error) {
          // A 400 is the service refusing the WINDOW (too wide to buffer, or malformed) — something
          // the admin can fix. Anything else is a breakage they cannot. The preview is dropped
          // either way: leaving the previous window's numbers on screen under a new date range
          // would be a total that describes a set of jobs nobody asked for.
          setLoadError({
            message: apiMessage(res.error),
            clientFault: res.response?.status === 400,
          });
          setPreview(null);
        } else {
          setLoadError(null);
          setPreview(res.data?.data ?? null);
          setAppliedWindow(win);
          setLedgerPage(1);
        }
        setLoading(false);
      })
      .catch(() => {
        if (!alive()) return;
        // No response at all (the request never completed) — never the admin's window.
        setLoadError({ message: null, clientFault: false });
        setPreview(null);
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
   * Fetch one page of the sweep-file history.
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
      .GET("/admin/deductions/batches", {
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

  // Every `preview?.…` below guards the PREVIEW being absent (not loaded, or a failed fetch), which
  // is a real state. None of them guards a missing FIELD any more: the contract marks all of these
  // `required`, so a field that went missing is now a compile error rather than a ฿0.00 an admin
  // would reconcile a bank transfer against.
  const jobs = useMemo(() => preview?.jobs ?? [], [preview]);
  const excluded = preview?.excluded ?? [];
  const jobCount = preview?.job_count ?? 0;
  const excludedCount = preview?.excluded_count ?? 0;
  /** The three figures of one visible sum: `billedCut − uncollected = totalAmount`. */
  const billedCut = preview?.billed_cut_total ?? null;
  const uncollected = preview?.uncollected_total ?? null;
  const totalAmount = preview?.total_amount ?? null;
  /** No destination configured → the export is refused server-side, so it is refused here too, with
   *  the reason and the way to fix it instead of a 400 the admin has to decode. */
  const creditAccount = preview?.credit_account_masked ?? null;
  const nothingToSweep = jobCount === 0;
  /** There IS billed-but-unpaid money in this window, so the line explaining it has to be raised.
   *  Decided on the decimal TEXT — a float round-trip has no business gating a money warning. */
  const hasUncollected = uncollected !== null && signOfDecimalString(uncollected) > 0;
  /**
   * Jobs in the window, but nothing the bank would carry.
   *
   * NEW with the uncollected split: the five components are all non-negative except the rounding
   * drift, so before it the total could only be ≥ 0 — now a window whose bills were never collected
   * can net to zero or below, and `transfer_bound_rejection` refuses it (SCB's credit-line minimum
   * is ฿0.01). Refusing it HERE, with the reason, is the difference between an admin reading "widen
   * the window" and an admin reading a raw 400 after the click.
   */
  const netPositive = totalAmount !== null && signOfDecimalString(totalAmount) > 0;
  const netNotPositive = preview !== null && !nothingToSweep && !netPositive;
  /** Everything the server checks before it will write a file, checked here first — so the button is
   *  dark for a stated reason instead of being a click into a 400. */
  const canExport = preview !== null && creditAccount !== null && !nothingToSweep && netPositive;

  const ledgerPageCount = Math.max(1, Math.ceil(jobs.length / LEDGER_PAGE_SIZE));
  const ledgerSlice = useMemo(
    () => jobs.slice((ledgerPage - 1) * LEDGER_PAGE_SIZE, ledgerPage * LEDGER_PAGE_SIZE),
    [jobs, ledgerPage],
  );

  const runExport = async () => {
    if (!canExport) return;
    setExporting(true);
    setBanner(null);
    // The WHOLE window, deliberately — an `OAT` file credits one destination, so there is nobody to
    // choose between, and a half-swept day would leave the rest looking unswept for a reason nobody
    // could reconstruct. The window sent is the one the preview was built with, so the jobs marked
    // swept are the ones the admin just read.
    const res = await paymentApi.POST("/admin/deductions/export", {
      body: {
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
    // Save under the name the SERVER chose (`SCB_file_reference_<file ref>.txt`) — that string is
    // the bank's reference for this batch and the `deduction_batches.file_ref` row, so it is the
    // only thing tying the file on disk to what we just marked swept.
    saveText(res.data, downloadNameFrom(res));
    reload(); // the swept jobs drop out of the backlog
    showLatestHistory(); // …and turn up in the history as a new `generated` batch
  };

  /**
   * Re-download the STORED text of an already-generated file.
   *
   * The export is a one-way door — it marks the jobs swept and streams the file once — so a failed
   * download used to leave those jobs recorded as collected with no file to collect them. This is
   * the way back: the same bytes, under the same bank reference, never regenerated.
   */
  const redownload = async (batch: DeductionBatch) => {
    setDownloadingId(batch.id);
    setHistoryBanner(null);
    const res = await paymentApi.GET("/admin/deductions/batches/{id}/file", {
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
    const id = action.batch.id;
    setActionBusy(true);
    setActionError(null);
    const res =
      action.kind === "void"
        ? await paymentApi.POST("/admin/deductions/batches/{id}/void", {
            params: { path: { id } },
            body: { reason: trimmedNote },
          })
        : await paymentApi.POST("/admin/deductions/batches/{id}/status", {
            params: { path: { id } },
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
    // A void hands every job in the batch back to the sweepable backlog — refresh the preview too so
    // those jobs visibly REAPPEAR above, instead of the admin having to trust that they did.
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

      {/* A failed preview, told apart from a REFUSED one. The bounded aggregation answers an
          over-wide window with a typed 400 rather than a truncated total, which is an instruction
          ("narrow the window"), not a fault — so the bilingual explanation is what the admin reads,
          and the service's own Thai sentence (which names the actual cap) sits under it as detail
          rather than being the whole message an English-reading operator gets. */}
      {loadError && (
        <div
          role="alert"
          className="flex items-start gap-2 rounded-lg border border-danger/40 bg-danger-bg px-4 py-3 text-sm text-danger"
        >
          <AlertTriangle className="mt-0.5 size-4 shrink-0" />
          <div>
            <p className="font-medium">{c.loadError}</p>
            {loadError.clientFault && <p className="mt-1">{c.loadErrorWindowHint}</p>}
            {loadError.message && (
              <p className="mt-1 text-xs opacity-90">{loadError.message}</p>
            )}
          </div>
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

      {/* ── What this file is ─────────────────────────────────
          Deliberately the first thing on the page, and deliberately loud. The other two screens
          send money to third parties; this one moves the company's money between the company's own
          accounts, and an admin who reads it as a third payout file will upload the wrong thing to
          SCB. The tax sentence is here rather than only beside the reports because this is where
          someone would be tempted to "also sweep the VAT while we are at it". */}
      <Panel>
        <PanelBody className="space-y-2 text-[12.5px] text-muted">
          <p className="flex items-start gap-2 font-medium text-text-strong">
            <Landmark className="mt-0.5 size-4 shrink-0 text-brand-int" />
            <span>{c.oatIntro}</span>
          </p>
          <p>{c.scopeNote}</p>
          <p>{c.taxNote}</p>
          <p>
            {c.configNote}{" "}
            <Link href="/payouts" className="font-medium text-brand-int hover:underline">
              {c.configLink}
            </Link>
          </p>
        </PanelBody>
      </Panel>

      {/* ── 1. The cut, itemised ─────────────────────────────── */}
      <Panel>
        <PanelHead title={c.cutPanel} sub={c.cutPanelHint}>
          <Button variant="ghost" onClick={() => reload()} disabled={loading}>
            <RefreshCw className={`size-4 ${loading ? "animate-spin" : ""}`} />
            {c.refresh}
          </Button>
        </PanelHead>
        <PanelBody>
          {/* Day window — which jobs the run covers (when their cut became final) */}
          <div className="mb-2 flex flex-wrap items-end gap-3">
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
          <p className="mb-5 text-xs text-faint">{c.dateHint}</p>

          {loading ? (
            <div className="flex items-center justify-center py-10 text-neutral-400">
              <Loader2 className="size-6 animate-spin" />
            </div>
          ) : (
            <>
              <KpiGrid className="grid-cols-2 min-[1101px]:grid-cols-2">
                <KpiCard label={c.totalCut} value={baht(totalAmount)} caption={c.totalCutCaption} />
                <KpiCard label={c.jobs} value={String(jobCount)} caption={c.inWindow} />
              </KpiGrid>

              {/* ── The breakdown ────────────────────────────────
                  The point of the whole screen. Five rows that sum to the BILLED cut, with the two
                  deferred-bug components flagged: an admin reading one lump sum would never learn
                  that part of what looks like revenue is a gratuity we billed and never paid on,
                  and a multi-guard booking we billed for N and paid for one. The footer then takes
                  the billed cut down to what the file actually transfers — see below. */}
              <h4 className="mb-2 text-sm font-semibold text-text-strong">{c.breakdown}</h4>
              <Table>
                <thead>
                  <Tr>
                    <Th>{c.component}</Th>
                    <Th className="text-right">{c.amount}</Th>
                  </Tr>
                </thead>
                <tbody>
                  {CUT_COMPONENTS.map((key) => {
                    const deferredBug = DEFERRED_BUG_COMPONENTS.includes(key);
                    return (
                      <Tr key={key}>
                        <Td>
                          <span className="flex flex-wrap items-center gap-2">
                            <span className="font-medium text-text-strong">
                              {c.componentLabels[key]}
                            </span>
                            {deferredBug && (
                              <Badge tone="amber">{c.deferredBugBadge}</Badge>
                            )}
                          </span>
                          <p className="mt-1 max-w-[46rem] text-xs text-muted">
                            {c.componentNotes[key]}
                          </p>
                        </Td>
                        <Td className="text-right font-semibold tabular-nums align-top">
                          {preview ? `฿${componentTotal(preview, key)}` : "—"}
                        </Td>
                      </Tr>
                    );
                  })}
                </tbody>
                {/* ── The arithmetic, spelled out ───────────────────
                    The five rows above no longer ARE the transfer. `billed_cut_total −
                    uncollected_total = total_amount`, and all three lines are shown because the
                    difference is real money: a bill that settled above what the customer pre-paid,
                    whose extra was never charged. Letting the KPI quietly shrink instead would leave
                    an admin reconciling a bank credit against a figure with an unexplained hole in
                    it — and this file debits the account that also holds the Revenue Department's
                    VAT and the guards' unpaid income, so an over-sweep draws down money that is not
                    the company's.
                    `cursor-default`/`hover:bg-transparent` because these are not rows anyone acts
                    on; [Tr] is styled for the clickable body rows above. */}
                <tfoot>
                  <Tr className="cursor-default hover:bg-transparent">
                    {/* A rule above the sum: [Tr] strips the bottom border off the LAST body row, so
                        without this the five components and their total would run together. */}
                    <Td className="border-t border-border">
                      <span className="font-medium text-text-strong">{c.billedCut}</span>
                      <p className="mt-1 max-w-[46rem] text-xs text-muted">{c.billedCutNote}</p>
                    </Td>
                    <Td className="border-t border-border text-right font-semibold tabular-nums align-top">
                      {baht(billedCut)}
                    </Td>
                  </Tr>
                  <Tr className="cursor-default hover:bg-transparent">
                    <Td>
                      <span className="flex flex-wrap items-center gap-2">
                        <span className="font-medium text-text-strong">{c.uncollected}</span>
                        <Badge tone="amber">{c.uncollectedBadge}</Badge>
                      </span>
                      <p className="mt-1 max-w-[46rem] text-xs text-muted">{c.uncollectedNote}</p>
                    </Td>
                    {/* Written with its MINUS SIGN when there is one, because that is what it does
                        to the line below. A bare positive number in a column of positives would read
                        as a sixth thing being added. */}
                    <Td
                      className={`text-right font-semibold tabular-nums align-top ${
                        hasUncollected ? "text-amber-700 dark:text-amber-300" : ""
                      }`}
                    >
                      {uncollected === null
                        ? "—"
                        : hasUncollected
                          ? `−฿${uncollected}`
                          : `฿${uncollected}`}
                    </Td>
                  </Tr>
                  <Tr className="cursor-default hover:bg-transparent">
                    <Td className="border-t-2 border-border">
                      <span className="font-semibold text-text-strong">{c.netToSweep}</span>
                      <p className="mt-1 max-w-[46rem] text-xs text-muted">{c.netToSweepNote}</p>
                    </Td>
                    <Td className="border-t-2 border-border text-right text-base font-semibold tabular-nums align-top text-text-strong">
                      {baht(totalAmount)}
                    </Td>
                  </Tr>
                </tfoot>
              </Table>

              {/* Raised ONLY when there is uncollected money — a standing warning about a figure
                  that is ฿0.00 on every ordinary window would be tuned out by the time it mattered. */}
              {hasUncollected && (
                <p className="mt-3 flex items-start gap-2 rounded-lg border border-warning/40 bg-warning-bg px-4 py-3 text-[12.5px] text-amber-800 dark:text-amber-300">
                  <AlertTriangle className="mt-0.5 size-4 shrink-0" />
                  <span>{c.uncollectedCallout}</span>
                </p>
              )}

              {/* ── What is NOT swept ────────────────────────────
                  Same account, not our money. Shown as its own block, outside the breakdown table,
                  so it can never be mistaken for a sixth component of the total. */}
              <div className="mt-6 rounded-lg border border-info/35 bg-info-bg px-4 py-3.5">
                <h4 className="text-sm font-semibold text-info">{c.notSweptTitle}</h4>
                <p className="mt-1 text-[12.5px] text-info/90">{c.notSweptIntro}</p>
                <dl className="mt-3 grid gap-3 sm:grid-cols-2">
                  <div>
                    <dt className="text-xs font-semibold uppercase tracking-[0.04em] text-info/80">
                      {c.vatNotSwept}
                    </dt>
                    <dd className="font-mono text-lg font-semibold tabular-nums text-info">
                      {baht(preview?.vat_not_swept ?? null)}
                    </dd>
                    <dd className="text-xs text-info/90">{c.vatNotSweptNote}</dd>
                  </div>
                  <div>
                    <dt className="text-xs font-semibold uppercase tracking-[0.04em] text-info/80">
                      {c.guardIncomeNotSwept}
                    </dt>
                    <dd className="font-mono text-lg font-semibold tabular-nums text-info">
                      {baht(preview?.guard_income_not_swept ?? null)}
                    </dd>
                    <dd className="text-xs text-info/90">{c.guardIncomeNotSweptNote}</dd>
                  </div>
                </dl>
              </div>

              {/* ── Excluded jobs ───────────────────────────────
                  A count with a reason, always — an under-reported cut must never be mistaken for a
                  complete one. */}
              {excludedCount > 0 && (
                <div className="mt-6">
                  <div className="mb-2 flex items-center gap-2 text-sm font-medium text-red-600 dark:text-red-400">
                    <AlertTriangle className="size-4" /> {c.excludedTitle} ({excludedCount})
                  </div>
                  <p className="mb-2 text-xs text-neutral-500">{c.excludedIntro}</p>
                  {excludedCount > excluded.length && (
                    <p className="mb-2 text-xs text-neutral-500">
                      {c.excludedTruncated(excluded.length, excludedCount)}
                    </p>
                  )}
                  <Table>
                    <thead>
                      <Tr>
                        <Th>{c.booking}</Th>
                        <Th>{c.payment}</Th>
                        <Th>{c.reason}</Th>
                      </Tr>
                    </thead>
                    <tbody>
                      {excluded.map((x) => (
                        <Tr key={x.payment_id}>
                          {/* Ids, not links: `/bookings` takes no id parameter, so a link would land
                              on an unfiltered list and look like a remedy while being none. The full
                              id is in the tooltip, for a ticket or the DB. */}
                          <Td className="font-mono text-xs" title={x.booking_id}>
                            {x.booking_id.slice(0, 8)}
                          </Td>
                          <Td className="font-mono text-xs" title={x.payment_id}>
                            {x.payment_id.slice(0, 8)}
                          </Td>
                          <Td>
                            <span className="flex flex-wrap items-center gap-2">
                              <Badge tone="red">{c.excludedCodeLabels[x.code]}</Badge>
                              {/* The server's own Thai sentence — it says what to do about THIS
                                  job, which the code alone cannot. */}
                              <span className="text-xs text-muted">{x.reason}</span>
                            </span>
                          </Td>
                        </Tr>
                      ))}
                    </tbody>
                  </Table>
                </div>
              )}

              {/* ── The per-job ledger ──────────────────────────── */}
              {jobs.length > 0 && (
                <div className="mt-6">
                  <h4 className="text-sm font-semibold text-text-strong">{c.ledgerTitle}</h4>
                  <p className="mb-2 text-xs text-muted">{c.ledgerIntro}</p>
                  {preview?.jobs_truncated && (
                    <p className="mb-2 text-xs text-neutral-500">
                      {c.ledgerTruncated(jobs.length, jobCount)}
                    </p>
                  )}
                  <Table>
                    <thead>
                      <Tr>
                        <Th>{c.settledOn}</Th>
                        <Th>{c.booking}</Th>
                        {CUT_COMPONENTS.map((key) => (
                          <Th key={key} className="text-right" title={c.componentLabels[key]}>
                            {c.componentShort[key]}
                          </Th>
                        ))}
                        {/* Its own column rather than a sixth component: it is SUBTRACTED, and a
                            negative in a row of positives is how a per-job amount stops matching
                            the columns beside it for no visible reason. */}
                        <Th className="text-right" title={c.uncollectedNote}>
                          {c.uncollectedShort}
                        </Th>
                        <Th className="text-right">{c.amount}</Th>
                      </Tr>
                    </thead>
                    <tbody>
                      {ledgerSlice.map((job) => {
                        const jobUncollected = signOfDecimalString(job.uncollected) > 0;
                        return (
                          <Tr key={job.payment_id}>
                            <Td className="whitespace-nowrap tabular-nums">
                              {fmtDay(job.settled_on, lang)}
                            </Td>
                            <Td className="font-mono text-xs" title={job.booking_id}>
                              {job.booking_id.slice(0, 8)}
                            </Td>
                            {CUT_COMPONENTS.map((key) => (
                              <Td key={key} className="text-right tabular-nums">
                                {jobComponent(job, key)}
                              </Td>
                            ))}
                            <Td
                              className={`text-right tabular-nums ${
                                jobUncollected ? "font-semibold text-amber-700 dark:text-amber-300" : ""
                              }`}
                            >
                              {jobUncollected ? `−${job.uncollected}` : job.uncollected}
                            </Td>
                            {/* May be NEGATIVE — a job really can net down against the sweep. Shown
                                as it comes, never clamped: the file's total is what has to be
                                positive, not each row. */}
                            <Td className="text-right font-semibold tabular-nums">฿{job.amount}</Td>
                          </Tr>
                        );
                      })}
                    </tbody>
                  </Table>
                  <Pagination
                    page={ledgerPage}
                    pageCount={ledgerPageCount}
                    onPage={setLedgerPage}
                    summary={c.listSummary(
                      (ledgerPage - 1) * LEDGER_PAGE_SIZE + 1,
                      Math.min(ledgerPage * LEDGER_PAGE_SIZE, jobs.length),
                      jobs.length,
                    )}
                  />
                </div>
              )}

              {nothingToSweep && (
                <p className="py-8 text-center text-sm text-neutral-500">{c.nothingToSweep}</p>
              )}
            </>
          )}
        </PanelBody>
      </Panel>

      {/* ── 2. The OAT sweep file ─────────────────────────────
          Its own panel, and visually the "company account" one: the destination is spelled out
          before the button, because the single thing that distinguishes this file from the other
          two is where its money lands. */}
      <Panel className="border-brand-int/40">
        <PanelHead title={c.exportPanel} sub={c.exportPanelHint}>
          <Button onClick={() => void runExport()} disabled={exporting || loading || !canExport}>
            {exporting ? (
              <Loader2 className="size-4 animate-spin" />
            ) : (
              <Download className="size-4" />
            )}
            {exporting ? c.exporting : c.exportBtn}
          </Button>
        </PanelHead>
        <PanelBody>
          {/* THREE states, not two. `creditAccount` is read out of the PREVIEW, so a preview that
              failed (or has not landed yet) also has no destination — and saying "no revenue account
              is configured" then would send an admin to change a setting that is perfectly fine.
              A failed preview says so; a pending one says nothing (the panel above already has the
              spinner). Only a LOADED preview with no account gets the configure-it alert. */}
          {preview === null ? (
            loadError ? (
              <p role="alert" className="text-sm text-danger">
                {c.loadError}
              </p>
            ) : null
          ) : creditAccount === null ? (
            // First, because it is the blocker that survives every window: no destination, no file,
            // whatever the cut comes to — and it is the only one with a settings link to follow.
            <p
              role="alert"
              className="flex items-start gap-2 rounded-lg border border-danger/40 bg-danger-bg px-4 py-3 text-sm text-danger"
            >
              <AlertTriangle className="mt-0.5 size-4 shrink-0" />
              <span>
                {c.noDestination}{" "}
                <Link href="/payouts" className="font-medium underline">
                  {c.configLink}
                </Link>
              </span>
            </p>
          ) : netNotPositive ? (
            /* Jobs, but nothing the bank would carry — new since the cut started deducting what was
               billed and never collected. Stated HERE with its own remedy (a WIDER window, the
               opposite of the too-many-rows one) rather than left to arrive as a raw 400 after the
               click, which is when an admin would reach for a NARROWER window and make it worse. */
            <p
              role="alert"
              className="flex items-start gap-2 rounded-lg border border-warning/40 bg-warning-bg px-4 py-3 text-sm text-amber-800 dark:text-amber-300"
            >
              <AlertTriangle className="mt-0.5 size-4 shrink-0" />
              <span>{c.netNotPositive}</span>
            </p>
          ) : (
            <div className="flex flex-wrap items-center gap-x-6 gap-y-2">
              <span className="flex items-center gap-2 text-sm">
                <Landmark className="size-4 text-brand-int" />
                <span className="text-muted">{c.destination}</span>
                <span className="font-mono font-semibold text-text-strong">{creditAccount}</span>
              </span>
              <span className="flex items-center gap-2 text-sm">
                <span className="text-muted">{c.totalCut}</span>
                <span className="font-mono text-lg font-semibold tabular-nums text-text-strong">
                  {baht(totalAmount)}
                </span>
                <span className="text-muted">
                  · {jobCount} {c.jobs}
                </span>
              </span>
              {/* Repeated beside the button, not only up in the breakdown: this is the last thing
                  read before a one-way click, and the figure being LOWER than the billed cut is
                  exactly what an admin would otherwise notice for the first time on a bank
                  statement. */}
              {hasUncollected && uncollected !== null && (
                <span className="flex items-center gap-2 text-sm text-amber-700 dark:text-amber-300">
                  <span>{c.uncollected}</span>
                  <span className="font-mono font-semibold tabular-nums">−฿{uncollected}</span>
                  <Badge tone="amber">{c.uncollectedBadge}</Badge>
                </span>
              )}
            </div>
          )}
          <p className="mt-3 text-xs text-neutral-500">{c.exportHint}</p>
        </PanelBody>
      </Panel>

      {/* ── Batch history ────────────────────────────────────
          What happened to the sweep files we already generated. The export is a one-way door: it
          marks the jobs swept and streams the file once, so without this an admin whose download
          failed would have a cut recorded as collected and no file to collect it with. */}
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
                  <Th>{c.creditedTo}</Th>
                  <Th className="text-right">{c.jobCount}</Th>
                  <Th className="text-right">{c.totalCut}</Th>
                  <Th>{c.status}</Th>
                  <Th>{c.createdAt}</Th>
                  <Th className="text-right">{c.actions}</Th>
                </Tr>
              </thead>
              <tbody>
                {batches.map((b) => {
                  // Only the steps the lifecycle actually allows from THIS row's state get a
                  // button — a control that can only ever answer 409 is worse than no control.
                  // No `b.status &&` guard any more: `status` is `required` in the contract, so a
                  // row without one is a compile error, not a silent "no actions available".
                  const steps = NEXT_STEPS[b.status];
                  const canVoid = VOIDABLE[b.status];
                  const downloading = downloadingId === b.id;
                  return (
                    <Tr key={b.id}>
                      {/* The bank's reference for the batch — the string on the file in the admin's
                          Downloads folder and in the SCB Business Net portal. */}
                      <Td className="font-mono text-xs" title={b.system_ref}>
                        {b.file_ref}
                      </Td>
                      <Td className="whitespace-nowrap tabular-nums">
                        {fmtDay(b.value_date, lang)}
                      </Td>
                      {/* SNAPSHOTTED at generation, not read from today's config: the settings may
                          have been edited since, and a generated money file must still say where its
                          money actually went. */}
                      <Td className="font-mono text-xs">{b.credit_account}</Td>
                      <Td className="text-right tabular-nums">{b.job_count}</Td>
                      <Td className="text-right font-semibold tabular-nums">฿{b.total_amount}</Td>
                      <Td>
                        <Badge tone={STATUS_TONE[b.status]}>{c.statusLabels[b.status]}</Badge>
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
                          {/* Offered on EVERY row, `confirmed` included — but as a LEDGER, not as a
                              remedy. A confirmed sweep moved its whole total on one credit line, so
                              the drill-down's release is refused there (409
                              `DEDUCTION_BATCH_CONFIRMED`) and the modal says why; what stays useful
                              on a confirmed row is reading which jobs the file collected. */}
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

      {/* ── 3. The two tax reports ───────────────────────────── */}
      <TaxReports />

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
                  {c.voidWarning(action.batch.job_count, action.batch.total_amount)}
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
                    and leaves every job in it permanently marked swept. The same warning the payout
                    and refund screens carry, for the same reason. */}
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

      {/* ── One file's jobs + the per-job release ─────────────
          Not the other two screens' "the bank bounced a credit line" case — an OAT file has ONE
          line. This is for a job that should never have been swept, and the money already moved in
          full, so releasing one leaves the revenue account over-swept until a correcting transfer.
          The modal says so. */}
      <DeductionBatchDetailModal
        // Remount per file: every open then starts from a clean slate — no stale items, tick-list
        // or typed reason carried over from the last file — without the modal resetting its own
        // state inside an effect.
        key={detailBatch?.id ?? "closed"}
        batch={detailBatch}
        onClose={() => setDetailBatch(null)}
        onReleased={() => {
          // Both lists, for the same reason the whole-batch void refreshes both: the released jobs
          // must visibly REAPPEAR in the backlog rather than being taken on trust, and the history
          // row's counts came from the items that just changed.
          refreshBatches();
          reload();
        }}
      />
    </div>
  );
}

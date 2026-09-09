"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { AlertTriangle, Ban, Download, List, Loader2, RefreshCw, Save } from "lucide-react";

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
  Select,
  Table,
  Td,
  Textarea,
  Th,
  Toggle,
  Tr,
} from "@/components/ui";
import { paymentApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import { BatchDetailModal } from "./batch-detail-modal";
import {
  COPY,
  FEE_CHARGE_CODES,
  MAX_NOTE_CHARS,
  WHT_FORM_CODES,
  type BatchStatusValue,
  type BatchStep,
} from "./copy";
import { fmtDay, fmtInstant } from "./dates";
import { saveText } from "./download-file";
import { fallbackDownloadName, parseContentDispositionFilename } from "./download-name";
import { sumDecimalStrings } from "./money";

type PayoutConfig = components["schemas"]["PayoutConfig"];
type PayoutPreview = components["schemas"]["PayoutPreview"];
type PayoutBatch = components["schemas"]["PayoutBatch"];

/** History rows per page — the API pages server-side (`limit`/`offset` + a `total`). */
const BATCH_PAGE_SIZE = 10;

/**
 * Status → badge tone. The history is a list an admin SCANS, so the colour has to carry the state
 * before the words are read: green = the money moved, red = the bank said no, amber = we are
 * waiting on the bank, blue = generated and still in the admin's hands, grey = voided, i.e. no
 * longer a live claim on the account.
 */
const STATUS_TONE: Record<BatchStatusValue, BadgeTone> = {
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
 * void — the bank refused the file, so the honest next move is to return the work to the backlog.
 */
const NEXT_STEPS: Record<BatchStatusValue, readonly BatchStep[]> = {
  generated: ["uploaded"],
  uploaded: ["confirmed", "rejected"],
  confirmed: [],
  rejected: [],
  voided: [],
};

/** The `(Generated | Uploaded | Rejected) → Voided` edges of the same table. A CONFIRMED batch is
 *  money that already left the account: un-marking it would pay those guards twice. */
const VOIDABLE: Record<BatchStatusValue, boolean> = {
  generated: true,
  uploaded: true,
  rejected: true,
  confirmed: false,
  voided: false,
};

/** What the confirm dialog is open for. `null` = closed; the batch rides along so the copy can name
 *  the file and its amount (a void must be confirmed against a number, not an abstraction). */
type BatchAction =
  | { kind: "step"; batch: PayoutBatch; step: BatchStep }
  | { kind: "void"; batch: PayoutBatch };

/** The name the SERVER chose for a payout file, falling back to the date stamp. See
 *  ./download-name.ts — the filename is what ties a file on disk to its `payout_batches` row. */
const downloadNameFrom = (res: { response?: Response }): string =>
  parseContentDispositionFilename(res.response?.headers.get("content-disposition")) ??
  fallbackDownloadName();

/** The finished-job day window the preview/export are narrowed to ("" = open end). */
type Window = { from: string; to: string };

const EMPTY_WINDOW: Window = { from: "", to: "" };

/**
 * An emptied decimal box → `null` ("keep the stored value"), anything else through untouched.
 *
 * The money/rate settings are exact decimals on the server (`rust_decimal::Decimal`), so `""` is
 * not an empty value there, it is a body that fails to deserialise before any of payment's own
 * validation runs. Neither field can be cleared through this API by design, so "keep" is also the
 * only honest reading of a blanked box.
 */
const blankToNull = (value: string | null | undefined): string | null =>
  value && value.trim() !== "" ? value : null;

/** The typed message a 400/409 carries (e.g. "ยังไม่ได้ตั้งเลขผู้เสียภาษีบริษัท"), when present. */
const apiMessage = (err: unknown): string | null => {
  const message = (err as { error?: { message?: unknown } } | undefined)?.error?.message;
  return typeof message === "string" && message.trim() ? message : null;
};

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
  /** The window being edited in the filter row. */
  const [window, setWindow] = useState<Window>(EMPTY_WINDOW);
  /** The window the loaded preview actually reflects — what an export must be run with. */
  const [appliedWindow, setAppliedWindow] = useState<Window>(EMPTY_WINDOW);
  /** The guards ticked to pay — many guards ride ONE SCB file. */
  const [selected, setSelected] = useState<Set<string>>(new Set());

  // ── Batch history ────────────────────────────────────────────────────────────────────────
  // Kept in its own loading/error pair rather than folded into the preview's: the history is the
  // place an admin comes when the export went wrong, so it has to render even when the preview
  // (a heavier query across profile) is failing.
  const [batches, setBatches] = useState<PayoutBatch[]>([]);
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
  /** The batch whose per-job drill-down is open (`null` = closed). Only `id` and `file_ref` are
   *  read from it — both immutable — so it does not matter that a refresh rebuilds the row it
   *  came from while the modal is up. */
  const [detailBatch, setDetailBatch] = useState<PayoutBatch | null>(null);
  /** The open confirm dialog — a status step or a void. */
  const [action, setAction] = useState<BatchAction | null>(null);
  const [actionNote, setActionNote] = useState("");
  const [actionBusy, setActionBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const load = useCallback((win: Window, alive: () => boolean = () => true) => {
    return Promise.all([
      paymentApi.GET("/admin/payouts/config"),
      paymentApi.GET("/admin/payouts/preview", {
        params: { query: { from: win.from || undefined, to: win.to || undefined } },
      }),
    ])
      .then(([cfg, prev]) => {
        if (!alive()) return;
        if (cfg.error || prev.error) {
          setLoadError(true);
        } else {
          setLoadError(false);
          setConfig(cfg.data?.data ?? null);
          const data = prev.data?.data ?? null;
          setPreview(data);
          setAppliedWindow(win);
          // Default to paying everyone payable in the window; the admin unticks to narrow.
          setSelected(new Set((data?.recipients ?? []).map((r) => r.guard_id)));
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
   * Fetch one page of the payout-file history.
   *
   * Takes no copy (`c`) so it stays referentially stable across a language toggle — the error is a
   * flag, rendered in the current locale. Sets NO state synchronously (the spinner is raised by the
   * callers, exactly as `reload` does for `load`): this runs from an effect, and a synchronous
   * setState there is a cascading render.
   */
  const loadBatches = useCallback((page: number, alive: () => boolean = () => true) => {
    // Last request wins. Two paths fetch this list (the page effect and the explicit refreshes
    // after an export / a status change), so a slow reply for page 1 could otherwise land after
    // the reply for page 2 and leave the rows disagreeing with the pager under them.
    const seq = ++batchReq.current;
    return paymentApi
      .GET("/admin/payouts/batches", {
        params: {
          query: { limit: BATCH_PAGE_SIZE, offset: (page - 1) * BATCH_PAGE_SIZE },
        },
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

  const field = (key: keyof PayoutConfig, value: string) =>
    setConfig((prev) => (prev ? { ...prev, [key]: value } : prev));

  /** The two non-string settings get their own setters rather than going through `field`, whose
   *  computed key erases the field's type — `fee_charge_code` is a two-value enum SCB validates
   *  and `sms_notify` is a boolean, and neither may be written as a loose string. */
  const setFeeCharge = (value: string) =>
    setConfig((prev) => (prev ? { ...prev, fee_charge_code: value === "BEN" ? "BEN" : "OUR" } : prev));
  const setSmsNotify = (next: boolean) =>
    setConfig((prev) => (prev ? { ...prev, sms_notify: next } : prev));

  const save = async () => {
    if (!config) return;
    setSaving(true);
    setBanner(null);
    const res = await paymentApi.PUT("/admin/payouts/config", {
      body: {
        debit_account: config.debit_account ?? null,
        fee_debit_account: config.fee_debit_account ?? null,
        // Through `blankToNull` for the same reason as the decimals below, and for one more: the
        // server validates a NON-null revenue account as a real SCB account (10 digits + §14 check
        // digit), so submitting `""` from an untouched box would 400 the whole save on a field the
        // admin never edited. Null is the API's own "keep what you have".
        revenue_account: blankToNull(config.revenue_account),
        // The two decimals go through `blankToNull`: the server parses these into an exact
        // `Decimal`, so an empty string is not "unset", it is a body serde cannot deserialise —
        // a 422 whose message says nothing an operator can act on. Null is the API's own "keep
        // what you have", which is exactly what an emptied box should mean here (the contract is
        // explicit that neither field can be CLEARED through this endpoint, only changed).
        wht_rate_percent: blankToNull(config.wht_rate_percent),
        max_transfer_per_txn: blankToNull(config.max_transfer_per_txn),
        wht_form_type_code: config.wht_form_type_code ?? null,
        wht_income_type_code: config.wht_income_type_code ?? null,
        wht_income_desc: config.wht_income_desc ?? null,
        fee_charge_code: config.fee_charge_code ?? null,
        // `?? null`, never `|| null`: `false` is a real, meaningful value here (SMS off) and
        // must not be turned into "keep the stored value" by a falsy test.
        sms_notify: config.sms_notify ?? null,
      },
    });
    setSaving(false);
    if (res.error) {
      setBanner(apiMessage(res.error) ?? c.saveError);
    } else {
      setConfig(res.data?.data ?? config);
      setSavedFlash(true);
      setTimeout(() => setSavedFlash(false), 2000);
      reload();
    }
  };

  // The ภ.ง.ด. form the file will carry. A stored value outside the SCB list (legacy row, or a
  // hand-edit from the free-text days) stays selected and is flagged rather than snapped to a
  // default — which form is owed is the user's tax call, and quietly changing it would be worse
  // than showing it is wrong.
  const whtFormCode = config?.wht_form_type_code ?? "";
  const whtFormKnown = (WHT_FORM_CODES as readonly string[]).includes(whtFormCode);

  const recipients = useMemo(() => preview?.recipients ?? [], [preview]);
  const excluded = preview?.excluded ?? [];
  const picked = useMemo(
    () => recipients.filter((r) => selected.has(r.guard_id)),
    [recipients, selected],
  );
  const allPicked = recipients.length > 0 && picked.length === recipients.length;
  const nothingPicked = picked.length === 0;

  const toggle = (guardId: string) =>
    setSelected((prev) => {
      const next = new Set(prev);
      if (!next.delete(guardId)) next.add(guardId);
      return next;
    });

  const toggleAll = () =>
    setSelected(allPicked ? new Set() : new Set(recipients.map((r) => r.guard_id)));

  const runExport = async () => {
    if (nothingPicked) return;
    setExporting(true);
    setBanner(null);
    // One file, many guards: send exactly the ticked ids + the window the preview was built with,
    // so the persisted paid-markers cover the same rows the admin just saw.
    const res = await paymentApi.POST("/admin/payouts/export", {
      body: {
        guard_ids: picked.map((r) => r.guard_id),
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
    // that string is the bank's reference for this batch and the `payout_batches.file_ref` row,
    // so it is the only thing tying the file on disk to what we just marked paid. See
    // ./download-name.ts; the date-stamped name is the fallback when the header is unusable.
    saveText(res.data, downloadNameFrom(res));
    reload(); // the paid jobs drop out of the backlog
    showLatestHistory(); // …and turn up in the history as a new `generated` batch
  };

  /**
   * Re-download the STORED text of an already-generated file.
   *
   * The export is a one-way door — it marks the bookings paid and streams the file once — so a
   * failed download used to leave that work paid with no file to pay it with. This is the way back:
   * the same bytes, under the same bank reference, never regenerated.
   */
  const redownload = async (batch: PayoutBatch) => {
    setDownloadingId(batch.id);
    setHistoryBanner(null);
    const res = await paymentApi.GET("/admin/payouts/batches/{id}/file", {
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
        ? await paymentApi.POST("/admin/payouts/batches/{id}/void", {
            params: { path: { id: action.batch.id } },
            body: { reason: trimmedNote },
          })
        : await paymentApi.POST("/admin/payouts/batches/{id}/status", {
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
    // A void hands every booking in the batch back to the payable backlog — refresh the preview too
    // so those guards visibly REAPPEAR above, instead of the admin having to trust that they did.
    if (action.kind === "void") reload();
  };

  // Server-side paging (`limit`/`offset` + `total`), so the page never holds more than one screen
  // of history however many files have been generated.
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
              {/* The PLATFORM-CUT sweep's destination — the one company bank detail on this form
                  that no file generated from THIS screen ever touches. It lives here anyway because
                  a second settings form editing the same `payout_config` row is how the two end up
                  disagreeing (the same reason the refund screen keeps none), and the hint carries
                  where it is actually spent. Left unset, `/deductions` says so up front rather than
                  letting the export be where an admin finds out. */}
              <Field
                label={c.revenueAccount}
                hint={c.revenueAccountHint}
                className="sm:col-span-2"
              >
                <Input
                  value={config.revenue_account ?? ""}
                  onChange={(e) => field("revenue_account", e.target.value)}
                  inputMode="numeric"
                  placeholder="1234567890"
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
              {/* Closed list, not free text: SCB only accepts the seven TBWHTType codes
                  (CPX_Toolkit_Reverse_Engineering.md:142-155) and they are non-contiguous, so a
                  typed "3" produced a file the bank rejects. A stored code outside the list is
                  kept as an extra, flagged option — we never silently rewrite a tax setting. */}
              <Field label={c.whtForm} hint={c.whtFormHint}>
                <Select
                  value={whtFormCode}
                  error={!whtFormKnown}
                  onChange={(e) => field("wht_form_type_code", e.target.value)}
                >
                  {whtFormCode === "" && <option value="">{c.whtFormUnset}</option>}
                  {whtFormCode !== "" && !whtFormKnown && (
                    <option value={whtFormCode}>{c.whtFormUnknown(whtFormCode)}</option>
                  )}
                  {WHT_FORM_CODES.map((code) => (
                    <option key={code} value={code}>
                      {c.whtFormLabels[code]}
                    </option>
                  ))}
                </Select>
              </Field>
              <Field label={c.incomeDesc}>
                <Input
                  value={config.wht_income_desc ?? ""}
                  onChange={(e) => field("wht_income_desc", e.target.value)}
                />
              </Field>
              {/* TXNDET field 8, mandatory on EVERY credit line (doc:1721 writes it, doc:1915
                  requires it unconditionally) — so it is a two-value picker, never a blank-able
                  box. The hint carries the ledger consequence rather than the definition: `BEN`
                  has the bank take its fee out of the credit, leaving the guard with less than
                  `payout_batch_items.transfer_amount` says we paid, permanently. */}
              <Field label={c.feeCharge} hint={c.feeChargeHint}>
                <Select
                  value={config.fee_charge_code ?? "OUR"}
                  onChange={(e) => setFeeCharge(e.target.value)}
                >
                  {FEE_CHARGE_CODES.map((code) => (
                    <option key={code} value={code}>
                      {c.feeChargeLabels[code]}
                    </option>
                  ))}
                </Select>
              </Field>
              {/* A guard over this cap is EXCLUDED from the file with a reason, not truncated —
                  which is why the number has to be visible on the screen where that exclusion is
                  read, or the "จ่ายไม่ได้" row naming a bound nobody can see is a dead end. */}
              <Field label={c.maxTransfer} hint={c.maxTransferHint}>
                <Input
                  value={config.max_transfer_per_txn ?? ""}
                  onChange={(e) => field("max_transfer_per_txn", e.target.value)}
                  inputMode="decimal"
                  placeholder="2000000"
                />
              </Field>
              {/* Opt-in, and OFF by default: turning it on both costs money (the bank bills per
                  SMS) and discloses the guard's phone number to SCB. The toggle's state is read
                  out beside it — a bare switch tells an operator nothing about which way is on. */}
              <Field label={c.smsNotify} hint={c.smsNotifyHint} className="sm:col-span-2">
                <div className="flex items-center gap-3">
                  <Toggle
                    checked={config.sms_notify ?? false}
                    onChange={setSmsNotify}
                    aria-label={c.smsNotify}
                  />
                  <span className="text-sm text-muted">
                    {config.sms_notify ? c.smsNotifyOn : c.smsNotifyOff}
                  </span>
                </div>
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
            <Button variant="ghost" onClick={() => reload()} disabled={loading}>
              <RefreshCw className={`size-4 ${loading ? "animate-spin" : ""}`} />
              {c.refresh}
            </Button>
            <Button onClick={runExport} disabled={exporting || loading || nothingPicked}>
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
          {/* Day window — which finished jobs the run covers */}
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
              label={c.totalTransfer}
              value={`฿${sumDecimalStrings(picked.map((r) => r.transfer))}`}
              caption={c.selectedOnly}
            />
            <KpiCard
              label={c.totalWht}
              value={`฿${sumDecimalStrings(picked.map((r) => r.wht))}`}
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
                    <Th>{c.guard}</Th>
                    <Th>{c.proxy}</Th>
                    <Th className="text-right">{c.jobs}</Th>
                    <Th className="text-right">{c.income}</Th>
                    <Th className="text-right">{c.wht}</Th>
                    <Th className="text-right">{c.transfer}</Th>
                  </Tr>
                </thead>
                <tbody>
                  {recipients.map((r) => (
                    <Tr key={r.guard_id}>
                      <Td>
                        <input
                          type="checkbox"
                          aria-label={`${c.selectOne} ${r.name}`}
                          checked={selected.has(r.guard_id)}
                          onChange={() => toggle(r.guard_id)}
                          className="size-4 accent-brand-int"
                        />
                      </Td>
                      <Td>{r.name}</Td>
                      <Td className="font-mono text-xs">{r.proxy_masked}</Td>
                      <Td className="text-right tabular-nums">{r.job_count}</Td>
                      <Td className="text-right tabular-nums">฿{r.income}</Td>
                      <Td className="text-right tabular-nums text-amber-600 dark:text-amber-400">
                        ฿{r.wht}
                      </Td>
                      <Td className="text-right font-semibold tabular-nums">฿{r.transfer}</Td>
                    </Tr>
                  ))}
                </tbody>
              </Table>
              {nothingPicked && (
                <p className="mt-3 text-sm text-amber-700 dark:text-amber-400">{c.pickSomeone}</p>
              )}
            </>
          )}

          {excluded.length > 0 && (
            <div className="mt-6">
              <div className="mb-2 flex items-center gap-2 text-sm font-medium text-red-600 dark:text-red-400">
                <AlertTriangle className="size-4" /> {c.excludedTitle} ({excluded.length})
              </div>
              {/* Without this the table was a dead end: an id + a Thai reason and no way to act.
                  Every row now deep-links to that guard's detail modal (?guard=<id>), which is
                  where the tax id / bank block is entered — the fix for the reason shown. */}
              <p className="mb-2 text-xs text-neutral-500">{c.excludedHint}</p>
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
                      <Td>
                        <Link
                          href={`/guards?guard=${g.guard_id}`}
                          aria-label={`${c.fixGuard} ${g.guard_id}`}
                          // The full id lives nowhere else on this screen — hover reveals it so an
                          // operator can still cross-check the row against the DB/support ticket.
                          title={g.guard_id}
                          className="font-mono text-xs font-medium text-brand-int hover:underline"
                        >
                          {g.guard_id.slice(0, 8)}
                        </Link>
                      </Td>
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

      {/* ── Batch history ────────────────────────────────────
          What happened to the files we already generated. Before this the export was a one-way
          door: it marked the bookings paid, streamed the file once, and the admin had no record
          of the run at all — a lost download meant work paid for with no file to pay it with. */}
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
                      {/* The bank's reference for the batch — the string on the file in the
                          admin's Downloads folder and in the SCB Business Net portal. */}
                      <Td className="font-mono text-xs" title={b.system_ref}>
                        {b.file_ref}
                      </Td>
                      <Td className="whitespace-nowrap tabular-nums">
                        {fmtDay(b.value_date, lang)}
                      </Td>
                      <Td className="text-right tabular-nums">{b.recipient_count}</Td>
                      <Td className="text-right font-semibold tabular-nums">฿{b.total_amount}</Td>
                      <Td>
                        <Badge tone={STATUS_TONE[b.status] ?? "gray"}>
                          {c.statusLabels[b.status] ?? b.status}
                        </Badge>
                        {/* Recording the bank's message / the void reason is pointless unless it
                            is shown back — this is where an admin finds out WHY a file bounced. */}
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
                              exactly where the per-guard release matters, because the whole-file
                              void is (correctly) gone by then. */}
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => setDetailBatch(b)}
                          >
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
                {/* `confirmed` is NOT like the other steps and must not share their reassuring
                    copy. Recording `uploaded`/`rejected` really is just writing down what the
                    bank did — both are reversible into a void, nothing about the money moves.
                    Confirming is the one-way door: it makes the batch terminal, which removes the
                    whole-file void and leaves every booking in it permanently marked จ่ายแล้ว. A
                    mis-click on the wrong history row, or an eager click before the bank has
                    actually settled, cannot be undone at batch level — only per guard, from the
                    drill-down, which is why the warning names that as the remaining recourse. */}
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

      {/* ── One file's jobs + the per-guard release ──────────
          The everyday partial failure: SCB accepts the FILE and still fails a credit line (an
          unregistered PromptPay proxy). The batch is honestly confirmed, so the whole-file void is
          gone — this is the only way those guards get back into the payable queue. */}
      <BatchDetailModal
        // Remount per file (same pattern as the guard payout panel): every open then starts from
        // a clean slate — no stale items, tick-list or typed reason carried over from the last
        // file — without the modal resetting its own state inside an effect.
        key={detailBatch?.id ?? "closed"}
        batch={detailBatch}
        onClose={() => setDetailBatch(null)}
        onReleased={() => {
          // Both lists, for the same reason the whole-batch void refreshes both: the released
          // guards must visibly REAPPEAR in the backlog above rather than being taken on trust,
          // and the history row's counts came from the items that just changed.
          refreshBatches();
          reload();
        }}
      />
    </div>
  );
}

"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, Loader2, Undo2 } from "lucide-react";

import type { components } from "@/api/generated/payment";
import { Badge, Button, Field, Modal, Table, Td, Textarea, Th, Tr } from "@/components/ui";
import { paymentApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import { useNameResolver } from "@/lib/use-names";

import { MAX_NOTE_CHARS } from "../payouts/copy";
import { sumDecimalStrings } from "../payouts/money";
import { COPY, MAX_RELEASE_SOURCES, type RefundSourceKind } from "./copy";

type RefundBatch = components["schemas"]["RefundBatch"];
type RefundBatchDetail = components["schemas"]["RefundBatchDetail"];
type RefundBatchItem = components["schemas"]["RefundBatchItem"];
type RefundSourceRef = components["schemas"]["RefundSourceRef"];

/**
 * One CUSTOMER's share of a refund file — the unit the bank actually succeeds or fails at.
 *
 * The API's items are per OBLIGATION (that is the paid-marker's grain: one row per owing source row,
 * which is what makes a refund payable again), but the file returns one `TXNDET` credit line per
 * customer covering everything they are owed across both lanes. So when SCB reports a failed credit
 * it is failing this whole line, and the admin is never in a position to say "2 of this customer's 3
 * refunds bounced". Grouping here is what makes the tick-list match the bank's report; `sources` is
 * the flattening the release endpoint is then given.
 */
interface CustomerLine {
  customerId: string;
  /** The obligations behind this line, as the `(kind, id)` PAIRS the endpoint names them by — a
   *  bare id would be ambiguous, `payments` and `payment_slips` having separate id spaces. */
  sources: RefundSourceRef[];
  /** Which lanes this line draws on, first-seen order — shown so an admin reading the bank's
   *  report can tell an overpay refund from a duplicate transfer without opening the DB. */
  kinds: RefundSourceKind[];
  amount: string;
  /** False = already handed back to the queue: history, not something to release again. */
  live: boolean;
}

/**
 * Group a batch's per-obligation items into per-customer lines, splitting each customer by state.
 *
 * A customer can legitimately appear TWICE — once live, once released — after an earlier partial
 * release, or after the bank failed one file and a later one settled part of the same backlog.
 * Rolling those together would show a single row whose amount is neither what is still refunded nor
 * what came back, and would let the admin tick a line that is half history. First-seen order is kept
 * (the API returns items in insertion order, so it reads like the file), live lines first.
 */
export function groupItemsByCustomer(items: readonly RefundBatchItem[]): CustomerLine[] {
  const lines = new Map<string, CustomerLine>();
  for (const item of items) {
    const live = !item.voided_at;
    const key = `${item.customer_id}:${live ? "live" : "released"}`;
    const existing = lines.get(key);
    if (existing) {
      existing.sources.push({ source_kind: item.source_kind, source_id: item.source_id });
      existing.amount = sumDecimalStrings([existing.amount, item.amount]);
      if (!existing.kinds.includes(item.source_kind)) existing.kinds.push(item.source_kind);
    } else {
      lines.set(key, {
        customerId: item.customer_id,
        sources: [{ source_kind: item.source_kind, source_id: item.source_id }],
        kinds: [item.source_kind],
        amount: item.amount,
        live,
      });
    }
  }
  const all = Array.from(lines.values());
  return [...all.filter((l) => l.live), ...all.filter((l) => !l.live)];
}

/** The typed message a 400/404/409 carries, when present — the API's own words beat a generic one. */
const apiMessage = (err: unknown): string | null => {
  const message = (err as { error?: { message?: unknown } } | undefined)?.error?.message;
  return typeof message === "string" && message.trim() ? message : null;
};

/**
 * The drill-down for ONE generated refund file: which customers it paid back, and the way to hand a
 * bounced transfer to the refundable queue.
 *
 * WHY THIS EXISTS. SCB can accept a bulk file and still fail individual credit lines — an
 * unregistered PromptPay proxy is the everyday case, and it is MORE likely here than on the payout
 * side: a guard is onboarded with their banking details checked, whereas a customer's destination is
 * simply the phone they signed up with. The file is structurally fine, so the batch is honestly
 * `confirmed`, and `confirmed` is terminal: the whole-file void is (correctly) refused, because
 * un-marking it would refund the customers who DID get their money a second time. This is the
 * remedy, with the same friction as the batch void — a real modal (never `window.confirm`, which
 * cannot carry a reason and blocks automation), a mandatory reason, and the consequence spelled out
 * against a live total of what is ticked.
 */
export function RefundBatchDetailModal({
  batch,
  onClose,
  onReleased,
}: {
  /** The history row being drilled into; `null` = closed. Carries `file_ref` so the modal is
   *  anchored to a named file before the items have loaded. */
  batch: RefundBatch | null;
  onClose: () => void;
  /** A release landed: the caller refreshes the history AND the refundable preview, so the
   *  customers just released visibly REAPPEAR in the backlog instead of being taken on trust. */
  onReleased: () => void;
}) {
  const { lang } = useLanguage();
  const copy = COPY[lang];
  const c = copy.detail;

  const [detail, setDetail] = useState<RefundBatchDetail | null>(null);
  // Starts true and is only ever turned OFF: this component is mounted with `key={batch.id}` (see
  // the call site), so every open is a fresh instance whose first render is the fetch's spinner.
  // That keying is what lets the effect below reset nothing synchronously — a synchronous setState
  // in an effect is a cascading render, and the one thing worse than a spinner here would be
  // showing the PREVIOUS file's customers under this file's name.
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  /** Customer ids ticked for release — LIVE lines only (a released line has nothing to give back). */
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [flash, setFlash] = useState<string | null>(null);

  const batchId = batch?.id ?? null;

  /**
   * (Re-)read this file's items. Sets no state synchronously — it is called from an effect, where a
   * synchronous setState is a cascading render — and carries no "still mounted?" guard on purpose:
   * the component is remounted per file (`key={batch.id}`), so a late reply belongs to an instance
   * that has already been discarded and can never overwrite the rows on screen.
   */
  const fetchDetail = useCallback(() => {
    if (!batchId) return Promise.resolve();
    return paymentApi
      .GET("/admin/refunds/batches/{id}", { params: { path: { id: batchId } } })
      .then((res) => {
        if (res.error || !res.data?.data) {
          setLoadError(true);
        } else {
          setLoadError(false);
          setDetail(res.data.data);
        }
        setLoading(false);
      })
      .catch(() => {
        setLoadError(true);
        setLoading(false);
      });
  }, [batchId]);

  // Fetch on open. Depends on the id (through `fetchDetail`) and not on the batch object, so
  // re-rendering the parent — which rebuilds the batch rows after every refresh — does not re-fetch
  // the open modal.
  useEffect(() => {
    void fetchDetail();
  }, [fetchDetail]);

  const lines = useMemo(() => groupItemsByCustomer(detail?.items ?? []), [detail]);
  const liveLines = useMemo(() => lines.filter((l) => l.live), [lines]);

  // Names, not uuids: the admin is matching these rows against the bank's failure report, which
  // names people. Best-effort — the resolver falls back to a short id and never blocks the screen.
  const customerIds = useMemo(() => lines.map((l) => l.customerId), [lines]);
  const { resolve } = useNameResolver(customerIds, lang);

  const pickedLines = useMemo(
    () => liveLines.filter((l) => picked.has(l.customerId)),
    [liveLines, picked],
  );
  const pickedSources = useMemo(() => pickedLines.flatMap((l) => l.sources), [pickedLines]);
  const pickedTotal = sumDecimalStrings(pickedLines.map((l) => l.amount));
  const allPicked = liveLines.length > 0 && pickedLines.length === liveLines.length;
  /** The endpoint is all-or-nothing, so an over-cap list would release NOTHING — caught here. */
  const overCap = pickedSources.length > MAX_RELEASE_SOURCES;
  const trimmedReason = reason.trim();
  const ready = pickedSources.length > 0 && trimmedReason.length > 0 && !overCap;

  const toggle = (customerId: string) =>
    setPicked((prev) => {
      const next = new Set(prev);
      if (!next.delete(customerId)) next.add(customerId);
      return next;
    });

  const toggleAll = () =>
    setPicked(allPicked ? new Set() : new Set(liveLines.map((l) => l.customerId)));

  /** Never dismiss out from under an in-flight release, or the admin is left not knowing whether
   *  that money went back in the queue. Also guards the scrim click and Escape. */
  const close = useCallback(() => {
    if (!busy) onClose();
  }, [busy, onClose]);

  const release = async () => {
    if (!batchId || !ready) return;
    setBusy(true);
    setError(null);
    setFlash(null);
    const res = await paymentApi.POST("/admin/refunds/batches/{id}/items/void", {
      params: { path: { id: batchId } },
      body: { sources: pickedSources, reason: trimmedReason },
    });
    setBusy(false);
    if (res.error || !res.data?.data) {
      // A 404/409 here means the rows on screen are stale — another admin (or another tab) already
      // released one of them. The server's own Thai message is the useful one; the generic string
      // is the fallback. Nothing was released (the endpoint is all-or-nothing), so re-read the items
      // SILENTLY — the error must stay on screen, but the table under it has to stop describing a
      // state that no longer exists.
      setError(apiMessage(res.error) ?? c.releaseError);
      void fetchDetail();
      return;
    }
    // The response IS the updated detail, so the table re-renders from what actually landed rather
    // than from an optimistic guess about which rows moved.
    setFlash(c.releasedFlash(pickedLines.length));
    setDetail(res.data.data);
    setPicked(new Set());
    setReason("");
    onReleased();
  };

  return (
    <Modal open={batch !== null} onClose={close} title={c.title} size="lg">
      {batch && (
        <>
          <p className="font-mono text-xs text-faint">{c.subtitle(batch.file_ref)}</p>
          {/* The file's own state, repeated here from the row: a release means one thing on a
              `generated` file (it never went to the bank) and quite another on a `confirmed` one
              (the money moved for everyone else), and the admin should not have to remember which
              row they clicked. Reuses the history's labels so the two can never disagree. */}
          <p className="mt-1 text-xs text-muted">
            {copy.status}: {copy.statusLabels[batch.status] ?? batch.status}
          </p>
          <p className="mt-3 rounded-lg border border-border bg-sunken px-3.5 py-3 text-[12.5px] text-muted">
            {c.releaseIntro}
          </p>

          {loadError ? (
            <p role="alert" className="py-8 text-center text-sm text-danger">
              {c.error}
            </p>
          ) : loading ? (
            <p className="flex items-center justify-center gap-2 py-8 text-sm text-muted">
              <Loader2 className="size-4 animate-spin" /> {c.loading}
            </p>
          ) : lines.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted">{c.empty}</p>
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
                        disabled={liveLines.length === 0 || busy}
                        onChange={toggleAll}
                        className="size-4 accent-brand-int"
                      />
                    </Th>
                    <Th>{c.colCustomer}</Th>
                    <Th className="text-right">{c.colObligations}</Th>
                    <Th>{c.colKinds}</Th>
                    <Th className="text-right">{c.colAmount}</Th>
                    <Th>{c.colState}</Th>
                  </Tr>
                </thead>
                <tbody>
                  {lines.map((line) => {
                    const who = resolve(line.customerId);
                    return (
                      <Tr
                        // A customer can hold both a live and a released line — the state is part of
                        // the identity of the row, so it is part of the key.
                        key={`${line.customerId}:${line.live}`}
                        className={line.live ? undefined : "opacity-60"}
                      >
                        <Td>
                          {line.live ? (
                            <input
                              type="checkbox"
                              aria-label={`${c.selectCustomer} ${who.label}`}
                              checked={picked.has(line.customerId)}
                              disabled={busy}
                              onChange={() => toggle(line.customerId)}
                              className="size-4 accent-brand-int"
                            />
                          ) : null}
                        </Td>
                        <Td title={who.title}>{who.label}</Td>
                        <Td className="text-right tabular-nums">{line.sources.length}</Td>
                        <Td>
                          <span className="flex flex-wrap gap-1">
                            {line.kinds.map((kind) => (
                              <Badge key={kind} tone={kind === "slip" ? "amber" : "blue"}>
                                {c.sourceKindLabels[kind]}
                              </Badge>
                            ))}
                          </span>
                        </Td>
                        <Td className="text-right font-semibold tabular-nums">฿{line.amount}</Td>
                        <Td>
                          <Badge tone={line.live ? "green" : "gray"}>
                            {line.live ? c.statePaid : c.stateReleased}
                          </Badge>
                        </Td>
                      </Tr>
                    );
                  })}
                </tbody>
              </Table>

              {liveLines.length > 0 && (
                <div className="mt-4">
                  <p className="text-sm font-semibold text-text-strong">
                    {c.selectedSummary(pickedLines.length, pickedSources.length, pickedTotal)}
                  </p>
                  {pickedLines.length === 0 ? (
                    <p className="mt-1 text-xs text-muted">{c.nothingSelected}</p>
                  ) : (
                    <>
                      <p className="mt-2 rounded-lg border border-danger/35 bg-danger-bg px-3.5 py-3 text-sm text-danger">
                        {c.releaseWarning}
                      </p>
                      {overCap && (
                        <p role="alert" className="mt-2 text-sm text-danger">
                          {c.tooMany(MAX_RELEASE_SOURCES)}
                        </p>
                      )}
                      <Field
                        label={c.releaseReason}
                        required
                        hint={c.releaseReasonHint}
                        className="mt-4 mb-0"
                      >
                        <Textarea
                          value={reason}
                          onChange={(e) => setReason(e.target.value)}
                          placeholder={c.releaseReasonPlaceholder}
                          maxLength={MAX_NOTE_CHARS}
                        />
                      </Field>
                    </>
                  )}
                </div>
              )}
            </>
          )}

          {error && (
            <p role="alert" className="mt-3 flex items-center gap-2 text-sm text-danger">
              <AlertTriangle className="size-4 shrink-0" /> {error}
            </p>
          )}
          {flash && <p className="mt-3 text-sm text-brand-int">{flash}</p>}

          <div className="mt-5 flex justify-end gap-2.5">
            <Button variant="secondary" onClick={close} disabled={busy}>
              {c.close}
            </Button>
            {liveLines.length > 0 && (
              <Button variant="danger" onClick={() => void release()} disabled={busy || !ready}>
                {busy ? <Loader2 className="size-4 animate-spin" /> : <Undo2 className="size-4" />}
                {busy ? c.releasing : c.releaseBtn}
              </Button>
            )}
          </div>
        </>
      )}
    </Modal>
  );
}

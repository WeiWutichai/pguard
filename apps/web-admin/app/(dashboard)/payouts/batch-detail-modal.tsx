"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, Loader2, Undo2 } from "lucide-react";

import type { components } from "@/api/generated/payment";
import { Badge, Button, Field, Modal, Table, Td, Textarea, Th, Tr } from "@/components/ui";
import { paymentApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import { useNameResolver } from "@/lib/use-names";

import { COPY, MAX_NOTE_CHARS, MAX_RELEASE_ITEMS } from "./copy";
import { sumDecimalStrings } from "./money";

type PayoutBatch = components["schemas"]["PayoutBatch"];
type PayoutBatchDetail = components["schemas"]["PayoutBatchDetail"];
type PayoutBatchItem = components["schemas"]["PayoutBatchItem"];

/**
 * One GUARD's share of a payout file — the unit the bank actually succeeds or fails at.
 *
 * The API's items are per BOOKING (that is the paid-marker's grain: one row per job, which is what
 * makes a job payable again), but the file pays one `TXNDET` credit line per guard covering all
 * their jobs. So when SCB reports a failed credit it is failing this whole line, and the admin is
 * never in a position to say "job 2 of 3 bounced". Grouping here is what makes the tick-list match
 * the bank's report; `bookingIds` is the flattening the endpoint is then given.
 */
interface GuardLine {
  guardId: string;
  /** The bookings behind this line — LIVE ones for a payable line, the released ones otherwise. */
  bookingIds: string[];
  income: string;
  wht: string;
  transfer: string;
  /** False = already handed back to the queue: history, not something to release again. */
  live: boolean;
}

/**
 * Group a batch's per-booking items into per-guard lines, splitting each guard by state.
 *
 * A guard can legitimately appear TWICE — once live, once released — after an earlier partial
 * release, or after the bank failed one file and a later one paid part of the same backlog. Rolling
 * those together would show a single row whose amount is neither what is still paid nor what came
 * back, and would let the admin tick a line that is half history. First-seen order is kept (the API
 * returns items in insertion order, so it reads like the file), live lines first.
 */
export function groupItemsByGuard(items: readonly PayoutBatchItem[]): GuardLine[] {
  const lines = new Map<string, GuardLine>();
  for (const item of items) {
    const live = !item.voided_at;
    const key = `${item.guard_id}:${live ? "live" : "released"}`;
    const existing = lines.get(key);
    if (existing) {
      existing.bookingIds.push(item.booking_id);
      existing.income = sumDecimalStrings([existing.income, item.income]);
      existing.wht = sumDecimalStrings([existing.wht, item.wht]);
      existing.transfer = sumDecimalStrings([existing.transfer, item.transfer_amount]);
    } else {
      lines.set(key, {
        guardId: item.guard_id,
        bookingIds: [item.booking_id],
        income: item.income,
        wht: item.wht,
        transfer: item.transfer_amount,
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
 * The drill-down for ONE generated payout file: which guards it paid, and the way to hand a
 * bounced transfer back to the payable queue.
 *
 * WHY THIS EXISTS. SCB can accept a bulk file and still fail individual credit lines — an
 * unregistered PromptPay proxy is the everyday case. The file is structurally fine, so the batch is
 * honestly `confirmed`, and `confirmed` is terminal: the whole-file void is (correctly) refused,
 * because un-marking it would re-pay the guards who DID get their money. Before the per-item
 * endpoint, that left a hand-written UPDATE in production as the only remedy for a guard whose
 * money never arrived. This is that remedy, with the same friction as the batch void: a real modal
 * (never `window.confirm`, which cannot carry a reason and blocks automation), a mandatory reason,
 * and the consequence spelled out against a live total of what is ticked.
 */
export function BatchDetailModal({
  batch,
  onClose,
  onReleased,
}: {
  /** The history row being drilled into; `null` = closed. Carries `file_ref` so the modal is
   *  anchored to a named file before the items have loaded. */
  batch: PayoutBatch | null;
  onClose: () => void;
  /** A release landed: the caller refreshes the history AND the payable preview, so the guards
   *  just released visibly REAPPEAR in the backlog instead of the admin having to trust they did. */
  onReleased: () => void;
}) {
  const { lang } = useLanguage();
  const copy = COPY[lang];
  const c = copy.detail;

  const [detail, setDetail] = useState<PayoutBatchDetail | null>(null);
  // Starts true and is only ever turned OFF: this component is mounted with `key={batch.id}` (see
  // the call site), so every open is a fresh instance whose first render is the fetch's spinner.
  // That keying is what lets the effect below reset nothing synchronously — a synchronous setState
  // in an effect is a cascading render, and the one thing worse than a spinner here would be
  // showing the PREVIOUS file's guards under this file's name.
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  /** Guard ids ticked for release — LIVE lines only (a released line has nothing left to give back). */
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [flash, setFlash] = useState<string | null>(null);

  const batchId = batch?.id ?? null;

  /**
   * (Re-)read this file's items. Sets no state synchronously — it is called from an effect, where
   * a synchronous setState is a cascading render — and carries no "still mounted?" guard on
   * purpose: the component is remounted per file (`key={batch.id}`), so a late reply belongs to an
   * instance that has already been discarded and can never overwrite the rows on screen.
   */
  const fetchDetail = useCallback(() => {
    if (!batchId) return Promise.resolve();
    return paymentApi
      .GET("/admin/payouts/batches/{id}", { params: { path: { id: batchId } } })
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
  // re-rendering the parent — which rebuilds the batch rows after every refresh — does not
  // re-fetch the open modal.
  useEffect(() => {
    void fetchDetail();
  }, [fetchDetail]);

  const lines = useMemo(() => groupItemsByGuard(detail?.items ?? []), [detail]);
  const liveLines = useMemo(() => lines.filter((l) => l.live), [lines]);

  // Names, not uuids: the admin is matching these rows against the bank's failure report, which
  // names people. Best-effort — the resolver falls back to a short id and never blocks the screen.
  const guardIds = useMemo(() => lines.map((l) => l.guardId), [lines]);
  const { resolve } = useNameResolver(guardIds, lang);

  const pickedLines = useMemo(
    () => liveLines.filter((l) => picked.has(l.guardId)),
    [liveLines, picked],
  );
  const pickedBookingIds = useMemo(
    () => pickedLines.flatMap((l) => l.bookingIds),
    [pickedLines],
  );
  const pickedTotal = sumDecimalStrings(pickedLines.map((l) => l.transfer));
  const allPicked = liveLines.length > 0 && pickedLines.length === liveLines.length;
  /** The endpoint is all-or-nothing, so an over-cap list would release NOTHING — caught here. */
  const overCap = pickedBookingIds.length > MAX_RELEASE_ITEMS;
  const trimmedReason = reason.trim();
  const ready = pickedBookingIds.length > 0 && trimmedReason.length > 0 && !overCap;

  const toggle = (guardId: string) =>
    setPicked((prev) => {
      const next = new Set(prev);
      if (!next.delete(guardId)) next.add(guardId);
      return next;
    });

  const toggleAll = () =>
    setPicked(allPicked ? new Set() : new Set(liveLines.map((l) => l.guardId)));

  /** Never dismiss out from under an in-flight release, or the admin is left not knowing whether
   *  those jobs went back in the queue. Also guards the scrim click and Escape. */
  const close = useCallback(() => {
    if (!busy) onClose();
  }, [busy, onClose]);

  const release = async () => {
    if (!batchId || !ready) return;
    setBusy(true);
    setError(null);
    setFlash(null);
    const res = await paymentApi.POST("/admin/payouts/batches/{id}/items/void", {
      params: { path: { id: batchId } },
      body: { booking_ids: pickedBookingIds, reason: trimmedReason },
    });
    setBusy(false);
    if (res.error || !res.data?.data) {
      // A 404/409 here means the rows on screen are stale — another admin (or another tab) already
      // released one of them. The server's own Thai message is the useful one; the generic string
      // is the fallback. Nothing was released (the endpoint is all-or-nothing), so re-read the
      // items SILENTLY — the error must stay on screen, but the table under it has to stop
      // describing a state that no longer exists.
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
                    <Th>{c.colGuard}</Th>
                    <Th className="text-right">{c.colJobs}</Th>
                    <Th className="text-right">{c.colIncome}</Th>
                    <Th className="text-right">{c.colWht}</Th>
                    <Th className="text-right">{c.colTransfer}</Th>
                    <Th>{c.colState}</Th>
                  </Tr>
                </thead>
                <tbody>
                  {lines.map((line) => {
                    const who = resolve(line.guardId);
                    return (
                      <Tr
                        // A guard can hold both a live and a released line — the state is part of
                        // the identity of the row, so it is part of the key.
                        key={`${line.guardId}:${line.live}`}
                        className={line.live ? undefined : "opacity-60"}
                      >
                        <Td>
                          {line.live ? (
                            <input
                              type="checkbox"
                              aria-label={`${c.selectGuard} ${who.label}`}
                              checked={picked.has(line.guardId)}
                              disabled={busy}
                              onChange={() => toggle(line.guardId)}
                              className="size-4 accent-brand-int"
                            />
                          ) : null}
                        </Td>
                        <Td title={who.title}>{who.label}</Td>
                        <Td className="text-right tabular-nums">{line.bookingIds.length}</Td>
                        <Td className="text-right tabular-nums">฿{line.income}</Td>
                        <Td className="text-right tabular-nums text-amber-600 dark:text-amber-400">
                          ฿{line.wht}
                        </Td>
                        <Td className="text-right font-semibold tabular-nums">฿{line.transfer}</Td>
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
                    {c.selectedSummary(pickedLines.length, pickedBookingIds.length, pickedTotal)}
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
                          {c.tooMany(MAX_RELEASE_ITEMS)}
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
                {busy ? (
                  <Loader2 className="size-4 animate-spin" />
                ) : (
                  <Undo2 className="size-4" />
                )}
                {busy ? c.releasing : c.releaseBtn}
              </Button>
            )}
          </div>
        </>
      )}
    </Modal>
  );
}

"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, Loader2, Lock, Undo2 } from "lucide-react";

import type { components } from "@/api/generated/payment";
import { Badge, Button, Field, Modal, Table, Td, Textarea, Th, Tr } from "@/components/ui";
import { paymentApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import { MAX_NOTE_CHARS } from "../payouts/copy";
import { signOfDecimalString, sumDecimalStrings } from "../payouts/money";
import { COPY, CUT_COMPONENTS, MAX_RELEASE_JOBS, type CutComponent } from "./copy";

type DeductionBatch = components["schemas"]["DeductionBatch"];
type DeductionBatchDetail = components["schemas"]["DeductionBatchDetail"];
type DeductionBatchItem = components["schemas"]["DeductionBatchItem"];

/**
 * One component of a ledger row.
 *
 * An exhaustive `switch` rather than an index into the item: the day a sixth component is added to
 * the contract, this stops compiling instead of silently dropping the new money from every row.
 * Every one of these is `required` in the contract, so the return is a bare `string` — a missing
 * amount is a build error now, not a chip that quietly disappears from a row it belongs on.
 */
function componentOf(item: DeductionBatchItem, key: CutComponent): string {
  switch (key) {
    case "commission":
      return item.commission;
    case "cancellation_fee":
      return item.cancellation_fee;
    case "tip":
      return item.tip;
    case "unpaid_guard_share":
      return item.unpaid_guard_share;
    case "rounding_adjustment":
      return item.rounding_adjustment;
  }
}

/** Which components actually carry money on this row — the chips that explain the row's amount.
 *  A zero contributes nothing to the cut and would only crowd the cell. */
function contributingComponents(item: DeductionBatchItem): CutComponent[] {
  return CUT_COMPONENTS.filter((key) => signOfDecimalString(componentOf(item, key)) !== 0);
}

/** The typed message a 400/404/409 carries, when present — the API's own words beat a generic one. */
const apiMessage = (err: unknown): string | null => {
  const message = (err as { error?: { message?: unknown } } | undefined)?.error?.message;
  return typeof message === "string" && message.trim() ? message : null;
};

/**
 * The drill-down for ONE generated sweep file: which jobs' cuts it collected, and the way to hand a
 * job that should never have been collected back to the backlog.
 *
 * WHY THIS EXISTS, and why it is NOT the same remedy as on the other two screens. There, the trigger
 * is a credit line the bank failed (an unregistered PromptPay proxy): the file is fine, the batch is
 * honestly `confirmed`, and one recipient's money has to go back in the queue. An `OAT` file has ONE
 * credit line, so the bank either takes the whole sweep or it does not — a per-line failure is not a
 * thing here. The trigger instead is a JOB that should not have been in the sweep at all (a
 * disputed booking, a job swept before its own correction landed).
 *
 * WHICH IS ALSO WHY IT STOPS AT `confirmed`, the exact OPPOSITE of the other two screens. There, one
 * credit line per recipient means an individual PromptPay credit can bounce inside a file the bank
 * accepted, so releasing that one item on a `confirmed` batch is the whole point. Here `confirmed`
 * means the single summed credit landed in the revenue account, so a released job would go back into
 * the backlog and the NEXT sweep would move its cut a second time — real double-movement of company
 * money. `repo::void_deduction_batch_items` refuses it with a 409 (`DEDUCTION_BATCH_CONFIRMED`), and
 * this modal must never be the place an admin discovers that: on a confirmed file the tick column,
 * the reason box and the release button are all GONE, replaced by the two remedies that do exist (a
 * whole-file void if the money never moved, an accounting adjustment if it did). The ledger itself
 * stays readable — which jobs a confirmed file collected is exactly what someone is here to check.
 *
 * Same friction as the batch void: a real modal (never `window.confirm`, which cannot carry a reason
 * and blocks automation), a mandatory reason, and the consequence stated against a live total.
 */
export function DeductionBatchDetailModal({
  batch,
  onClose,
  onReleased,
}: {
  /** The history row being drilled into; `null` = closed. Carries `file_ref` so the modal is
   *  anchored to a named file before the items have loaded. */
  batch: DeductionBatch | null;
  onClose: () => void;
  /** A release landed: the caller refreshes the history AND the preview, so the released jobs
   *  visibly REAPPEAR in the backlog instead of being taken on trust. */
  onReleased: () => void;
}) {
  const { lang } = useLanguage();
  const copy = COPY[lang];
  const c = copy.detail;

  const [detail, setDetail] = useState<DeductionBatchDetail | null>(null);
  // Starts true and is only ever turned OFF: this component is mounted with `key={batch.id}` (see
  // the call site), so every open is a fresh instance whose first render is the fetch's spinner.
  // That keying is what lets the effect below reset nothing synchronously — a synchronous setState
  // in an effect is a cascading render, and the one thing worse than a spinner here would be
  // showing the PREVIOUS file's jobs under this file's name.
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  /** Payment ids ticked for release — LIVE rows only (a released row has nothing to give back). */
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [flash, setFlash] = useState<string | null>(null);

  const batchId = batch?.id ?? null;
  /**
   * Whether ANY release control is offered at all.
   *
   * The one asymmetry between this drill-down and the payout/refund ones. A `confirmed` sweep has
   * already moved its whole total on a single credit line, so the endpoint answers a release with a
   * 409 — the control is therefore not disabled-but-present, it is absent, with the reason and the
   * two real remedies in its place. Read off the batch the caller already has, so the answer is on
   * screen before the items land (and stays right if the fetch fails).
   */
  const releasable = batch !== null && batch.status !== "confirmed";

  /**
   * (Re-)read this file's items. Sets no state synchronously — it is called from an effect, where a
   * synchronous setState is a cascading render — and carries no "still mounted?" guard on purpose:
   * the component is remounted per file (`key={batch.id}`), so a late reply belongs to an instance
   * that has already been discarded and can never overwrite the rows on screen.
   */
  const fetchDetail = useCallback(() => {
    if (!batchId) return Promise.resolve();
    return paymentApi
      .GET("/admin/deductions/batches/{id}", { params: { path: { id: batchId } } })
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

  // Live rows first, released rows after, each block keeping the order the API returned (insertion
  // order, so it reads like the file). Unlike the refund file there is nothing to group: the ledger
  // is already one row per job, which is exactly the grain the release endpoint names.
  const items = useMemo(() => {
    const all = detail?.items ?? [];
    return [...all.filter((i) => !i.voided_at), ...all.filter((i) => i.voided_at)];
  }, [detail]);
  const liveItems = useMemo(() => items.filter((i) => !i.voided_at), [items]);

  const pickedItems = useMemo(
    () => liveItems.filter((i) => picked.has(i.payment_id)),
    [liveItems, picked],
  );
  const pickedTotal = sumDecimalStrings(pickedItems.map((i) => i.amount));
  const allPicked = liveItems.length > 0 && pickedItems.length === liveItems.length;
  /** The endpoint is all-or-nothing, so an over-cap list would release NOTHING — caught here. */
  const overCap = pickedItems.length > MAX_RELEASE_JOBS;
  const trimmedReason = reason.trim();
  const ready = releasable && pickedItems.length > 0 && trimmedReason.length > 0 && !overCap;

  const toggle = (paymentId: string) =>
    setPicked((prev) => {
      const next = new Set(prev);
      if (!next.delete(paymentId)) next.add(paymentId);
      return next;
    });

  const toggleAll = () => setPicked(allPicked ? new Set() : new Set(liveItems.map((i) => i.payment_id)));

  /** Never dismiss out from under an in-flight release, or the admin is left not knowing whether
   *  those jobs went back in the backlog. Also guards the scrim click and Escape. */
  const close = useCallback(() => {
    if (!busy) onClose();
  }, [busy, onClose]);

  const release = async () => {
    if (!batchId || !ready) return;
    setBusy(true);
    setError(null);
    setFlash(null);
    const res = await paymentApi.POST("/admin/deductions/batches/{id}/items/void", {
      params: { path: { id: batchId } },
      body: {
        payment_ids: pickedItems.map((i) => i.payment_id),
        reason: trimmedReason,
      },
    });
    setBusy(false);
    if (res.error || !res.data?.data) {
      // A 404/409 here means the rows on screen are stale — another admin (or another tab) already
      // released one of them. The server's own Thai message is the useful one; the generic string is
      // the fallback. Nothing was released (the endpoint is all-or-nothing), so re-read the items
      // SILENTLY — the error must stay on screen, but the table under it has to stop describing a
      // state that no longer exists.
      setError(apiMessage(res.error) ?? c.releaseError);
      void fetchDetail();
      return;
    }
    // The response IS the updated detail, so the table re-renders from what actually landed rather
    // than from an optimistic guess about which rows moved.
    setFlash(c.releasedFlash(pickedItems.length));
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
          {/* The file's own state, repeated here from the row: it is what decides whether a release
              is even on offer, and the admin should not have to remember which row they clicked.
              Reuses the history's labels so the two can never disagree. */}
          <p className="mt-1 text-xs text-muted">
            {copy.status}: {copy.statusLabels[batch.status]}
          </p>
          {/* TWO different notices, never both. On a releasable file: what the release is for. On a
              confirmed one: why it is gone and what to do instead — stated up front, so nobody hunts
              for a control that was removed. */}
          {releasable ? (
            <p className="mt-3 rounded-lg border border-border bg-sunken px-3.5 py-3 text-[12.5px] text-muted">
              {c.releaseIntro}
            </p>
          ) : (
            <div className="mt-3 rounded-lg border border-warning/40 bg-warning-bg px-3.5 py-3 text-amber-800 dark:text-amber-300">
              <p className="flex items-start gap-2 text-sm font-semibold">
                <Lock className="mt-0.5 size-4 shrink-0" />
                {c.confirmedTitle}
              </p>
              <p className="mt-1.5 text-[12.5px]">{c.confirmedNoRelease}</p>
            </div>
          )}

          {loadError ? (
            <p role="alert" className="py-8 text-center text-sm text-danger">
              {c.error}
            </p>
          ) : loading ? (
            <p className="flex items-center justify-center gap-2 py-8 text-sm text-muted">
              <Loader2 className="size-4 animate-spin" /> {c.loading}
            </p>
          ) : items.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted">{c.empty}</p>
          ) : (
            <>
              <Table className="mt-4">
                <thead>
                  <Tr>
                    {/* The whole tick column is absent on a confirmed file, not merely disabled: an
                        empty checkbox invites a click, and the click has nowhere to go. */}
                    {releasable && (
                      <Th className="w-10">
                        <input
                          type="checkbox"
                          aria-label={c.selectAll}
                          checked={allPicked}
                          disabled={liveItems.length === 0 || busy}
                          onChange={toggleAll}
                          className="size-4 accent-brand-int"
                        />
                      </Th>
                    )}
                    <Th>{c.colBooking}</Th>
                    <Th>{c.colComponents}</Th>
                    <Th className="text-right">{c.colUncollected}</Th>
                    <Th className="text-right">{c.colAmount}</Th>
                    <Th>{c.colState}</Th>
                  </Tr>
                </thead>
                <tbody>
                  {items.map((item) => {
                    const live = !item.voided_at;
                    const paymentId = item.payment_id;
                    const uncollected = signOfDecimalString(item.uncollected) > 0;
                    return (
                      <Tr
                        // The row's identity is the ledger row's own id, not the payment: a payment
                        // released and swept again by a LATER file appears once here, but keying on
                        // the batch item is the only id guaranteed unique inside this batch.
                        key={item.id}
                        className={live ? undefined : "opacity-60"}
                      >
                        {releasable && (
                          <Td>
                            {live ? (
                              <input
                                type="checkbox"
                                aria-label={`${c.selectJob} ${item.booking_id}`}
                                checked={picked.has(paymentId)}
                                disabled={busy}
                                onChange={() => toggle(paymentId)}
                                className="size-4 accent-brand-int"
                              />
                            ) : null}
                          </Td>
                        )}
                        {/* No link: `/bookings` takes no id parameter, and a link landing on an
                            unfiltered list would look like a way in and be none. The full id is in
                            the tooltip so it can be carried into a ticket or the DB. */}
                        <Td className="font-mono text-xs" title={item.booking_id}>
                          {item.booking_id.slice(0, 8)}
                        </Td>
                        <Td>
                          <span className="flex flex-wrap gap-1">
                            {contributingComponents(item).map((key) => (
                              <Badge key={key} tone="gray" title={copy.componentLabels[key]}>
                                {copy.componentShort[key]}
                              </Badge>
                            ))}
                          </span>
                        </Td>
                        {/* SUBTRACTED from the row's own amount — the ledger has to explain why a
                            job's cut is smaller than the chips beside it add up to. Signed, so it
                            never reads as a sixth thing being collected. */}
                        <Td
                          className={`text-right tabular-nums ${
                            uncollected ? "font-semibold text-amber-700 dark:text-amber-300" : ""
                          }`}
                        >
                          {uncollected ? `−${item.uncollected}` : item.uncollected}
                        </Td>
                        <Td className="text-right font-semibold tabular-nums">฿{item.amount}</Td>
                        <Td>
                          <Badge tone={live ? "green" : "gray"}>
                            {live ? c.stateSwept : c.stateReleased}
                          </Badge>
                        </Td>
                      </Tr>
                    );
                  })}
                </tbody>
              </Table>

              {releasable && liveItems.length > 0 && (
                <div className="mt-4">
                  <p className="text-sm font-semibold text-text-strong">
                    {c.selectedSummary(pickedItems.length, pickedTotal)}
                  </p>
                  {pickedItems.length === 0 ? (
                    <p className="mt-1 text-xs text-muted">{c.nothingSelected}</p>
                  ) : (
                    <>
                      <p className="mt-2 rounded-lg border border-danger/35 bg-danger-bg px-3.5 py-3 text-sm text-danger">
                        {c.releaseWarning}
                      </p>
                      {overCap && (
                        <p role="alert" className="mt-2 text-sm text-danger">
                          {c.tooMany(MAX_RELEASE_JOBS)}
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
            {releasable && liveItems.length > 0 && (
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

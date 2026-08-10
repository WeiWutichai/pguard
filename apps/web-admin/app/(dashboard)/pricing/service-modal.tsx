"use client";

import { useState } from "react";
import { AlertTriangle, Loader2 } from "lucide-react";

import type { components } from "@/api/generated/booking";
import { Button, Field, Input, Modal, Textarea } from "@/components/ui";
import { bookingApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import { COPY } from "./copy";

type ServiceCatalogItem = components["schemas"]["ServiceCatalogItem"];

/** Create/edit modal for a catalog service. `service = null` → create. Money goes on the wire as
 * exact decimal strings (money rule); min_hours as a number. Server re-validates (the source of
 * truth); the client validates first for a fast, clear error.
 *
 * The two money knobs pull in OPPOSITE directions and are easy to mix up, so the helper text
 * under each is not decoration: `commission_percent` comes OUT OF THE GUARD's pay (the customer's
 * bill is untouched), while `cancellation_fee` is charged TO THE CUSTOMER. Both are snapshotted
 * onto a booking at creation — saving here re-prices future jobs only. */
export function ServiceModal({
  service,
  onClose,
  onSaved,
}: {
  service: ServiceCatalogItem | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { lang } = useLanguage();
  const c = COPY[lang];

  // Single service name (the redesign dropped the TH/EN split) — sent as both name_th + name_en.
  const [name, setName] = useState(service?.name_th ?? "");
  const [baseFee, setBaseFee] = useState(service?.base_fee ?? "230");
  const [minHours, setMinHours] = useState(String(service?.min_hours ?? 4));
  // Both default to "0" on create — the no-op value (no cut taken, free cancellation), so a
  // service added without a deliberate choice never quietly docks a guard's pay.
  const [commission, setCommission] = useState(service?.commission_percent ?? "0");
  const [cancelFee, setCancelFee] = useState(service?.cancellation_fee ?? "0");
  const [saving, setSaving] = useState(false);
  const [failed, setFailed] = useState(false);
  const [notes, setNotes] = useState(service?.notes ?? "");

  const fee = Number(baseFee);
  const hrs = Number(minHours);
  const pct = Number(commission);
  const cancel = Number(cancelFee);
  const pctValid = Number.isFinite(pct) && pct >= 0 && pct <= 100;
  const cancelValid = Number.isFinite(cancel) && cancel >= 0 && cancel <= 1_000_000;
  const valid =
    name.trim() !== "" &&
    Number.isFinite(fee) &&
    fee >= 0 &&
    fee <= 1_000_000 &&
    Number.isInteger(hrs) &&
    hrs >= 1 &&
    hrs <= 24 &&
    pctValid &&
    cancelValid;

  async function save() {
    if (!valid) {
      setFailed(true);
      return;
    }
    setSaving(true);
    setFailed(false);
    const body = {
      name_th: name.trim(),
      name_en: name.trim(),
      // exact decimal string on the wire (money rule); normalize to 2dp.
      base_fee: fee.toFixed(2),
      min_hours: hrs,
      commission_percent: pct.toFixed(2),
      cancellation_fee: cancel.toFixed(2),
      notes: notes.trim() ? notes.trim() : null,
    };
    const { error } = service
      ? await bookingApi.PUT("/admin/pricing/services/{id}", {
          params: { path: { id: service.id } },
          body,
        })
      : await bookingApi.POST("/admin/pricing/services", { body });
    if (error) {
      setFailed(true);
      setSaving(false);
      return;
    }
    onSaved();
  }

  return (
    <Modal
      open
      onClose={onClose}
      title={service ? c.editTitle : c.createTitle}
      footer={
        <>
          <Button variant="secondary" size="sm" onClick={onClose}>
            {c.cancel}
          </Button>
          <Button variant="primary" size="sm" onClick={save} disabled={!valid || saving}>
            {saving ? <Loader2 className="size-4 animate-spin" /> : null}
            {saving ? c.saving : c.save}
          </Button>
        </>
      }
    >
      <Field label={c.fieldName} required>
        <Input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder={c.namePlaceholder}
          maxLength={120}
        />
      </Field>
      <div className="grid grid-cols-2 gap-3">
        <Field label={c.fieldBaseFee} hint={c.feeHint}>
          <Input
            type="number"
            min={0}
            max={1_000_000}
            step="0.01"
            value={baseFee}
            onChange={(e) => setBaseFee(e.target.value)}
          />
        </Field>
        <Field label={c.fieldMinHours} hint={c.hoursHint}>
          <Input
            type="number"
            min={1}
            max={24}
            step={1}
            value={minHours}
            onChange={(e) => setMinHours(e.target.value)}
          />
        </Field>
        {/* Commission is the one field an admin can misread as "add it to the bill", so the
            hint spells out whose money it comes from. Both keep the sibling fields' plain
            hint-only convention — the footer alert is what flags an out-of-range value. */}
        <Field label={c.fieldCommission} hint={c.commissionHint}>
          <Input
            type="number"
            min={0}
            max={100}
            step="0.01"
            value={commission}
            error={!pctValid}
            onChange={(e) => setCommission(e.target.value)}
          />
        </Field>
        <Field label={c.fieldCancelFee} hint={c.cancelFeeHint}>
          <Input
            type="number"
            min={0}
            max={1_000_000}
            step="0.01"
            value={cancelFee}
            error={!cancelValid}
            onChange={(e) => setCancelFee(e.target.value)}
          />
        </Field>
      </div>
      <Field label={c.fieldNotes}>
        <Textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          placeholder={c.notesPlaceholder}
          maxLength={2000}
        />
      </Field>

      {failed && (
        <div
          role="alert"
          className="flex items-center gap-2 rounded-lg border border-danger/40 bg-danger-bg px-3 py-2 text-[12.5px] text-danger"
        >
          <AlertTriangle className="size-4 flex-none" />
          {c.saveError}
        </div>
      )}
    </Modal>
  );
}

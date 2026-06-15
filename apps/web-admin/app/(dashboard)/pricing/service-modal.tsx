"use client";

import { useState } from "react";
import { AlertTriangle, Loader2 } from "lucide-react";

import type { components } from "@/api/generated/booking";
import { Button, Field, Input, Modal, Textarea } from "@/components/ui";
import { bookingApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import { COPY } from "./copy";

type ServiceCatalogItem = components["schemas"]["ServiceCatalogItem"];

/** Create/edit modal for a catalog service. `service = null` → create. base_fee is sent as a
 * decimal string (money rule); min_hours as a number. Server re-validates (the source of
 * truth); the client validates first for a fast, clear error. */
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

  const [nameTh, setNameTh] = useState(service?.name_th ?? "");
  const [nameEn, setNameEn] = useState(service?.name_en ?? "");
  const [baseFee, setBaseFee] = useState(service?.base_fee ?? "");
  const [minHours, setMinHours] = useState(String(service?.min_hours ?? 1));
  const [notes, setNotes] = useState(service?.notes ?? "");
  const [saving, setSaving] = useState(false);
  const [failed, setFailed] = useState(false);

  const fee = Number(baseFee);
  const hrs = Number(minHours);
  const valid =
    nameTh.trim() !== "" &&
    nameEn.trim() !== "" &&
    Number.isFinite(fee) &&
    fee >= 0 &&
    fee <= 1_000_000 &&
    Number.isInteger(hrs) &&
    hrs >= 1 &&
    hrs <= 24;

  async function save() {
    if (!valid) {
      setFailed(true);
      return;
    }
    setSaving(true);
    setFailed(false);
    const body = {
      name_th: nameTh.trim(),
      name_en: nameEn.trim(),
      // exact decimal string on the wire (money rule); normalize to 2dp.
      base_fee: fee.toFixed(2),
      min_hours: hrs,
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
      <Field label={c.fieldNameTh} required>
        <Input value={nameTh} onChange={(e) => setNameTh(e.target.value)} maxLength={120} />
      </Field>
      <Field label={c.fieldNameEn} required>
        <Input value={nameEn} onChange={(e) => setNameEn(e.target.value)} maxLength={120} />
      </Field>
      <div className="grid grid-cols-2 gap-3">
        <Field label={c.fieldBaseFee} required>
          <Input
            type="number"
            min={0}
            max={1_000_000}
            step="0.01"
            value={baseFee}
            onChange={(e) => setBaseFee(e.target.value)}
          />
        </Field>
        <Field label={c.fieldMinHours} required>
          <Input
            type="number"
            min={1}
            max={24}
            step={1}
            value={minHours}
            onChange={(e) => setMinHours(e.target.value)}
          />
        </Field>
      </div>
      <Field label={c.fieldNotes}>
        <Textarea value={notes} onChange={(e) => setNotes(e.target.value)} maxLength={2000} />
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

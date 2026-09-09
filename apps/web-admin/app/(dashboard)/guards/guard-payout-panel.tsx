"use client";

import { useState } from "react";
import { Loader2, Save } from "lucide-react";

import type { components } from "@/api/generated/profile";
import { Button, Field, Input } from "@/components/ui";
import { profileApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";

import { COPY, type GuardsCopy } from "./copy";

type GuardProfile = components["schemas"]["GuardProfile"];
type UpdateGuardPayoutRequest = components["schemas"]["UpdateGuardPayoutRequest"];

/**
 * The guard's PAYOUT block — national/tax id + bank — written through
 * `PUT /admin/guard-profiles/{user_id}/payout` (admin-only, PDPA §30-audited server-side).
 *
 * This panel is the reason the SCB guard-payout export can pay anybody: mobile registration never
 * asks for `tax_id`, and it is BOTH the PromptPay NAT proxy the money is credited to and the
 * ภ.ง.ด. recipient TIN. Until an operator can type it in, every guard fails payment's payability
 * check and lands in the payout screen's "จ่ายไม่ได้" table — which is exactly where the admin
 * clicks through to get here.
 *
 * It replaces the old read-only bank box in the detail modal: same fields, same admin-only FULL
 * (unmasked) values the contract returns to admins, now editable. Mounted with `key={user_id}` by
 * the modal so a different guard gets fresh state — no synchronous reset in an effect.
 */
export function GuardPayoutPanel({
  guard,
  onSaved,
}: {
  guard: GuardProfile;
  /** Hand the saved (unmasked) profile back so the list row behind the modal stops being stale. */
  onSaved?: (profile: GuardProfile) => void;
}) {
  const { lang } = useLanguage();
  const c = COPY[lang].payout;

  // `baseline` is what the server currently holds; `form` is what the operator has typed. The two
  // diverging is the ONLY thing we send (see `save`) — a COALESCE-merge endpoint must never be fed
  // fields nobody touched, or an untouched masked read-back would overwrite a real value.
  const [baseline, setBaseline] = useState<FormState>(() => seed(guard));
  const [form, setForm] = useState<FormState>(() => seed(guard));
  const [saving, setSaving] = useState(false);
  const [savedFlash, setSavedFlash] = useState(false);
  const [banner, setBanner] = useState<string | null>(null);

  const errors = fieldErrors(form, baseline, c);
  /** The fields we will actually SEND: touched AND non-empty (a blank is a no-op, not a delete). */
  const changed = FIELDS.filter((f) => form[f].trim() !== baseline[f] && form[f].trim() !== "");
  /** Any divergence at all — incl. a blank the endpoint cannot express, which is why Revert exists. */
  const dirty = FIELDS.some((f) => form[f] !== baseline[f]);
  const blocked = FIELDS.some((f) => errors[f]);

  const set = (field: PayoutField, value: string) =>
    setForm((prev) => ({ ...prev, [field]: value }));

  const save = async () => {
    // Only the fields that actually changed to a non-empty value. Absent = "keep what you have"
    // on this endpoint, so an untouched field costs nothing and a blanked one is NOT a delete
    // (the API cannot express a clear — `errCannotClear` says so before we get here).
    const body: UpdateGuardPayoutRequest = {};
    for (const f of changed) body[f] = form[f].trim();
    if (Object.keys(body).length === 0 || blocked) return;

    setSaving(true);
    setBanner(null);
    const res = await profileApi.PUT("/admin/guard-profiles/{user_id}/payout", {
      params: { path: { user_id: guard.user_id } },
      body,
    });
    setSaving(false);
    if (res.error) {
      // Show the API's own typed message ("tax_id must be 8–20 digits", "…looks masked", the 404)
      // — same approach as the payouts screen; the generic string is only the fallback.
      setBanner(apiMessage(res.error) ?? c.errSave);
      return;
    }
    // The response is the FULL profile as stored, so re-seed from it: the operator sees exactly
    // what landed (their separators normalised or not), and the panel goes clean.
    const saved = res.data?.data;
    if (saved) {
      setBaseline(seed(saved));
      setForm(seed(saved));
      onSaved?.(saved);
    }
    setSavedFlash(true);
    setTimeout(() => setSavedFlash(false), 2000);
  };

  return (
    <div className="mt-3 rounded-lg border border-border px-4 py-3">
      <div className="text-xs font-semibold uppercase tracking-[0.04em] text-muted">{c.head}</div>
      <p className="mt-1 text-[12px] text-muted">{c.mergeHint}</p>

      <div className="mt-3">
        <Field label={c.taxId} hint={c.taxIdHint} error={errors.tax_id}>
          <Input
            value={form.tax_id}
            error={Boolean(errors.tax_id)}
            onChange={(e) => set("tax_id", e.target.value)}
            inputMode="numeric"
            maxLength={MAX_TAX_ID_LEN}
            placeholder="1234567890123"
            className="font-mono"
          />
        </Field>
      </div>

      <div className="grid gap-x-4 sm:grid-cols-2">
        <Field label={c.bankName} error={errors.bank_name}>
          <Input
            value={form.bank_name}
            error={Boolean(errors.bank_name)}
            onChange={(e) => set("bank_name", e.target.value)}
            maxLength={MAX_TEXT_LEN}
          />
        </Field>
        <Field label={c.accountNumber} error={errors.account_number}>
          <Input
            value={form.account_number}
            error={Boolean(errors.account_number)}
            onChange={(e) => set("account_number", e.target.value)}
            inputMode="numeric"
            maxLength={MAX_ACCOUNT_NUMBER_LEN}
            className="font-mono"
          />
        </Field>
        <Field label={c.accountName} error={errors.account_name} className="sm:col-span-2">
          <Input
            value={form.account_name}
            error={Boolean(errors.account_name)}
            onChange={(e) => set("account_name", e.target.value)}
            maxLength={MAX_TEXT_LEN}
          />
        </Field>
      </div>

      {banner && (
        <p role="alert" className="mb-3 text-[12.5px] text-danger">
          {banner}
        </p>
      )}

      <div className="flex items-center gap-3">
        <Button size="sm" onClick={save} disabled={saving || blocked || changed.length === 0}>
          {saving ? <Loader2 className="size-4 animate-spin" /> : <Save className="size-4" />}
          {saving ? c.saving : c.save}
        </Button>
        {/* The way back out of a blanked/typed-over field: once the box is empty the stored value
            is no longer on screen to retype, and Save is (correctly) refusing to no-op it. */}
        {dirty && (
          <Button
            variant="ghost"
            size="sm"
            disabled={saving}
            onClick={() => {
              setForm(baseline);
              setBanner(null);
            }}
          >
            {c.revert}
          </Button>
        )}
        {savedFlash && <span className="text-[12.5px] text-brand-int">{c.saved}</span>}
      </div>
    </div>
  );
}

/** The four columns `PUT …/payout` writes, in render order. */
const FIELDS = ["tax_id", "bank_name", "account_number", "account_name"] as const;
type PayoutField = (typeof FIELDS)[number];
type FormState = Record<PayoutField, string>;

/** Mirrors of profile's own bounds (domain/validate.rs) so the browser rejects a typo before the
 *  round-trip; the server stays the authority (its typed message wins in the banner). */
const MAX_TEXT_LEN = 500;
const MAX_ACCOUNT_NUMBER_LEN = 34;
const MAX_TAX_ID_LEN = 20;
/** `domain::mask::MASK_CHAR` — the placeholder a masked read carries. */
const MASK_CHAR = "*";

/** Current stored values as an all-strings form state (null/undefined → ""). */
function seed(guard: GuardProfile): FormState {
  return {
    tax_id: guard.tax_id ?? "",
    bank_name: guard.bank_name ?? "",
    account_number: guard.account_number ?? "",
    account_name: guard.account_name ?? "",
  };
}

/**
 * Per-field blocking errors. Four shapes, all of which the server would reject (or silently
 * mis-store) if we let them through:
 *  - a **masked** value (`*`): the admin list returns unmasked values, but the owner-facing reads
 *    mask `tax_id`/`account_number`, so an edited masked string can only be a read-back — profile
 *    400s it (`…looks masked — resend the full …`) and we say so before spending the round-trip.
 *  - a **blanked** field that had a stored value: this endpoint COALESCE-merges, so a blank is a
 *    no-op, not a delete. Saying "it kept the old value" after the fact would be a lie; block it.
 *  - a **malformed tax id**: 8–20 digits after stripping spaces/hyphens, no letters.
 *  - a 13-digit tax id whose **check digit does not match** — see [taxIdChecksumOk].
 *
 * The two tax-id verdicts are deliberately SEPARATE messages: "not 8–20 digits" and "the digits
 * are right but the number is not a real national id" send an operator to different places (count
 * the digits vs. re-read the card), and one message covering both would read as pedantry.
 */
function fieldErrors(
  form: FormState,
  baseline: FormState,
  c: GuardsCopy["payout"],
): Partial<Record<PayoutField, string>> {
  const errors: Partial<Record<PayoutField, string>> = {};
  for (const f of FIELDS) {
    const value = form[f].trim();
    if (value === "" && baseline[f] !== "") errors[f] = c.errCannotClear;
    else if (value.includes(MASK_CHAR)) errors[f] = c.errMasked;
  }
  const taxId = form.tax_id.trim();
  if (!errors.tax_id && taxId !== "") {
    if (!taxIdLooksValid(taxId)) errors.tax_id = c.errTaxId;
    else if (!taxIdChecksumOk(taxId)) errors.tax_id = c.errTaxIdChecksum;
  }
  return errors;
}

/** Shape mirror of profile `validate::validate_tax_id`: digits (spaces/hyphens allowed
 *  as separators), 8–20 digits, raw length within `MAX_TAX_ID_LEN`. */
function taxIdLooksValid(raw: string): boolean {
  const value = raw.trim();
  if (value.length > MAX_TAX_ID_LEN) return false;
  if (!/^[\d -]+$/.test(value)) return false;
  const digits = value.replace(/\D/g, "");
  return digits.length >= 8 && digits.length <= MAX_TAX_ID_LEN;
}

/**
 * Mirror of profile `validate::validate_guard_tax_id`'s second half — the Thai national-ID mod-11
 * check digit, applied ONLY at exactly 13 digits:
 *
 * ```text
 * sum   = Σ digit[i] × (13 − i)   over the first TWELVE digits (weights 13 → 2)
 * check = (11 − (sum mod 11)) mod 10
 * valid iff check == digit[12]
 * ```
 *
 * WHY THE CLIENT BOTHERS. This field is the guard's PromptPay `NAT` destination, not a reference:
 * a 13-digit id mistyped off a photocopied ID card is still 13 digits, so it passes every shape
 * check, resolves to a valid proxy, and credits a STRANGER irreversibly — while the booking is
 * stamped paid, so the real guard is never paid for that work either. Catching it at the keystroke
 * is worth the duplication; the server stays the authority (its typed Thai message wins in the
 * banner) and this is only ever a convenience, never the gate.
 *
 * LENGTH-CONDITIONAL for the same reason profile's is: only 13 digits is a citizen id. An 8–12 or
 * 14–20 digit tax id is not a `NAT` proxy at all, so the citizen checksum has no authority over it
 * — and the COMPANY tax id on the org-settings screen is never checked this way (a juristic-person
 * TIN is a different number that happens to share the length; see profile's `validate_tax_id`).
 */
function taxIdChecksumOk(raw: string): boolean {
  const digits = raw.replace(/\D/g, "");
  if (digits.length !== 13) return true; // not a national id → this rule does not apply
  let sum = 0;
  for (let i = 0; i < 12; i += 1) sum += Number(digits[i]) * (13 - i);
  return (11 - (sum % 11)) % 10 === Number(digits[12]);
}

/** The typed message a 400/404 carries (e.g. "tax_id must be 8–20 digits"), when present. Same
 *  helper shape the payouts screen uses — the API's own words beat a generic banner. */
function apiMessage(err: unknown): string | null {
  const message = (err as { error?: { message?: unknown } } | undefined)?.error?.message;
  return typeof message === "string" && message.trim() ? message : null;
}

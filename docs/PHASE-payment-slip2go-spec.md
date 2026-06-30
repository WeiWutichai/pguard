# PHASE — Real payment via Slip2Go (PromptPay transfer + slip verification)

> **STATUS: APPROVED — implementing.** Official API docs obtained (Slip2Go API v1.2,
> `docs/Slip2Go+API+Documentation.pdf`). The `[NEEDS DOCS]` unknowns are resolved below. The API
> SECRET + sandbox base URL come next (wire as config: `SLIP2GO_API_SECRET`, `SLIP2GO_BASE_URL`).

## RESOLVED — Slip2Go API v1.2 (from the official PDF)

- **Base URL:** `https://connect.slip2go.com/api` (the docs' `{apiUrl}` = `connect.slip2go.com`).
  Make it config (`SLIP2GO_BASE_URL`) so a sandbox URL can override it.
- **Auth:** header `Authorization: Bearer {apiSecret}`. Plus an IP whitelist on Slip2Go's side
  (default `*`, cap 10 IPs) — the VPS egress IP must be whitelisted in their dashboard.
- **Verify endpoints (consume quota):**
  - `POST /verify-slip/qr-image/info` — **multipart**: `file` (slip image) + `payload` (JSON
    conditions). The server decodes the QR from the image. ← USE THIS (customer just picks the slip photo).
  - `POST /verify-slip/qr-code/info` — JSON `{ payload: { qrCode, checkCondition? } }` when the app
    already decoded the slip QR. (alternative; not the primary path.)
- **Free re-read (NO quota):** `GET /verify-slip/{referenceId}` — re-fetch a previously verified slip.
  Use for idempotent re-display / re-confirmation without spending quota.
- **Account/quota:** `GET /account/info` → `{ quotaLimit, quotaRemaining, creditRemaining, package,
  packageExpiredDate, autoRenewalPackage }`. Use for a low-quota alert + an admin readout.
- **Conditions** (`checkCondition` / `payload`, all OPTIONAL — the server does the checks for us):
  - `checkReceiver: [ { accountType?, accountNameTH?, accountNameEN?, accountNumber? } ]` — verify the
    money went to OUR account. Array = OR ("matched only 1 condition → valid"); partial match. Pass our
    receiving account number. accountType `"01004"` etc.; **don't add prefixes / spaces**.
  - `checkAmount: { type: "eq"|"gte"|"lte", amount }` — verify the transfer amount. Use **`gte` =
    estimate** (accept overpay; underpay rejected). `amount` is a string, no `0`/`,`.
  - `checkDuplicate: true` — Slip2Go flags a re-used slip (per shop). We ALSO dedupe by referenceId/
    transRef on our side (belt-and-suspenders — see §2).
  - `checkDate: { type, date }` — optional (transfer date window, GMT ISO).
- **Response:** `{ code, message, data }`. **`code "200000"` = "Slip found"** (success). `data`:
  `{ referenceId (UUID), decode, transRef, dateTime, amount (Number), ref1/2/3, receiver{ account{ name,
  bank{ account }, proxy{ type, account } }, bank{ id, name } }, sender{ account{...}, bank{...} } }`.
  A non-`200000` code (slip invalid / condition not matched / duplicate / quota) → treat as FAIL and
  surface `message`. (The PDF enumerates only the 2000xx success codes; branch on `code === "200000"`
  for success, else fail. FLAG: confirm the exact failure codes with Slip2Go for precise UX messages.)

## 0. What this changes

pguard's payment is currently a **simulated** gateway: `POST /payments` (createPayment) charges the
server-computed estimate at guard-accept and tags it `payment_method = "prepaid"` — **no real money
moves** (see `services/payment/src/api/mod.rs:33`). This phase makes it the **first real money path**
using the Thai-standard **PromptPay transfer + slip verification** model. Slip2Go is NOT a card
gateway — it **verifies that a transfer slip is genuine** (anti-fraud) and returns the amount /
sender / receiver / ref. The money lands in **our own PromptPay/bank account**; Slip2Go only confirms.

The existing **PRE-PAY → gate `en_route` → reconcile-on-completion** flow is kept verbatim; slip-verify
simply replaces the `"prepaid"` auto-mark as the thing that stamps `paid_at`.

## 1. Flow

```
guard accepts → booking unpaid (existing PRE-PAY gate, 409 PAYMENT_REQUIRED on en_route)
  → customer payment screen: PromptPay QR (OUR account, exact amount) + amount + ref
  → customer transfers in their bank app (scans QR) → gets a slip
  → customer uploads the slip (image / its QR payload)
  → payment service → Slip2Go verify
       checks: valid==true · amount ≥ estimate · receiver == OUR account · transRef NOT reused
  → pass → stamp paid_at, payment_method="promptpay_slip", store transRef + slip S3 key
          → emit payment.completed (existing event → booking learns it's paid → en_route allowed)
  → fail → typed error (amount mismatch / wrong receiver / reused / invalid slip) → retry
completion → existing reconcile (fewer actual hours → overpay). PromptPay can't auto-refund,
            so the overpay goes to the ADMIN REFUND QUEUE (already built) for a manual transfer.
```

## 2. Backend (payment service) — ~1.5–2 days

- **`slip2go_client.rs`** — a `SlipVerifier` trait (+ `HttpSlipVerifier` reqwest impl, API-key auth) so
  the handler is testable with a stub (mirror the existing `BookingReader` pattern in
  `booking_client.rs`). **[NEEDS DOCS]** exact endpoint, auth header, request encoding (image multipart
  vs base64 vs QR-payload — prefer base64/QR-payload), response field names.
- **Migration** `payment/0004_slip_payment.sql`:
  - `payment.payment_slips` (or columns on `payments`): `trans_ref TEXT UNIQUE` (the dedupe key — a
    reused slip → unique-violation → reject), `slip_key TEXT` (S3), `sender TEXT`, `receiver TEXT`,
    `verified_at TIMESTAMPTZ`.
  - extend the `payment_method` set with `promptpay_slip`.
- **Endpoints:**
  - `POST /payments/{id}/slip` — own-only (the booking's customer). Body = the slip (multipart image
    OR `{ image_base64 }` / `{ qr_payload }`). Verify → validate → on success stamp paid + emit
    `payment.completed`. **Idempotent**: re-submitting the same accepted slip = no-op returning paid;
    a different valid slip after paid = no-op.
  - (optional) `GET /payments/{id}/promptpay` — returns the QR payload + amount (or generate
    client-side; PromptPay QR is an EMVCo standard we can build offline from our PromptPay id + amount —
    avoids depending on Slip2Go's gen-QR).
- **Validation (anti-fraud — the core value):** `valid==true` · `amount ≥ estimate` (underpay reject;
  overpay accept → reconcile) · `receiver == RECEIVING_PROMPTPAY_ID` (reject slips to any other account)
  · `trans_ref` unseen (reject reuse) · optional `timestamp` within a window.
- **Config / secrets** (→ `infra/.env.staging`, see `[[staging-deploy-ops]]` conventions):
  `SLIP2GO_API_KEY`, `RECEIVING_PROMPTPAY_ID`, `SLIP_AMOUNT_TOLERANCE`.
- **S3**: store the slip image private (same pattern as guard documents) for audit/PDPA.
- **Events**: reuse `payment.completed` — **no new event** (the booking already consumes it to allow
  en_route).

## 3. Gateway — ~0.25 day
- `/payments/{id}/slip` already routes to payment via `/payments/`. Add a **`BodyCap::Large` carve-out**
  for it (slip image upload; the 1 MiB default would 413) — mirror the avatar/chat carve-outs in
  `services/api-gateway/src/domain/routing.rs`.

## 4. Mobile (customer) — ~1.5–2 days
- **Payment screen** (replaces the simulated auto-prepay): show the **PromptPay QR + amount + ref**,
  a "ฉันโอนแล้ว / I've paid" CTA.
- **Slip upload**: image picker (gallery/camera) or QR scan → `POST /payments/{id}/slip` → await verify
  → success: proceed (booking goes en_route-eligible); fail: show the typed error + retry. Reuse the
  magic-byte-MIME multipart pattern from the avatar/document upload.
- **QR generation**: render the PromptPay EMVCo payload client-side (our PromptPay id + amount) OR from
  `GET /payments/{id}/promptpay`.

## 5. Anti-fraud / edge cases (the real cost — bake into tests)
reused slip (dedupe) · underpay (reject) / overpay (accept → manual refund) · wrong receiver · fake/
altered slip (Slip2Go's job, but enforce `valid`) · stale slip (window) · double-submit (idempotent) ·
**Slip2Go outage** → retry + a clear "verifying…" state; fallback = an admin manual-verify action
(don't hard-block the customer forever).

## 6. Rollout & testing
- **Feature flag** `PAYMENT_PROVIDER = simulated | slip2go` — keep the `"prepaid"` simulated path as a
  fallback / for dev; flip per-env.
- **Tests**: stub `SlipVerifier` → unit-test the validation matrix (amount/receiver/dedupe/idempotency)
  with NO external calls; a contract test against Slip2Go's **sandbox** once we have a key.
- **Go-live**: sandbox → one small real-money test → enable.

## 7. Open questions for Slip2Go (ask before implementing) — **[NEEDS DOCS]**
1. Verify endpoint URL + auth header (API key? bearer?).
2. Request format: image multipart vs base64 vs the slip's QR payload — which is most reliable/cheapest?
3. Response schema: exact field names for `valid`, `amount`, `sender`, `receiver`, `transRef`, `timestamp`.
4. Rate limits / per-verify pricing / monthly quota.
5. Sandbox/test mode + sample test slips.
6. Do they push webhooks, or is it synchronous request/response only? (assume synchronous.)
7. PromptPay QR generation — use theirs or generate offline?

## 8. Effort summary
- Code, once docs + sandbox key are in hand: **~3–5 dev-days** (backend client+endpoint+dedupe, gateway
  cap, mobile QR+slip-upload, edge-case tests).
- **Long pole = external**: obtaining Slip2Go's official API docs + a sandbox key (contact: 090-236-9994
  · LINE @slip2go-support · slip2go.cs@gmail.com).
- Architecture fit: **clean** — slots into the existing PRE-PAY/reconcile flow; refunds reuse the
  already-built admin refund queue.

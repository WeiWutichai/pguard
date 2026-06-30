-- pguard payment-service — REAL money path: PromptPay/bank transfer + Slip2Go slip verification.
--
-- THE MONEY PATH. v2's `POST /payments` is a SIMULATED gateway (tags `prepaid`, no real money).
-- This migration backs the REAL path: a customer transfers to OUR PromptPay/bank account, then
-- uploads the transfer slip; the payment service verifies it with Slip2Go and stamps the booking
-- paid. Slip2Go confirms the slip is genuine + the amount/receiver; the money lands in our own
-- account (Slip2Go is NOT a card gateway).
--
-- WHY a dedicated dedupe table (belt-and-suspenders over Slip2Go's `checkDuplicate`): a verified
-- slip carries a globally-unique bank `transRef` and a Slip2Go `referenceId` (UUID). We store BOTH
-- with a UNIQUE constraint so ONE slip can NEVER pay TWO bookings — even if Slip2Go's per-shop
-- duplicate check is bypassed or a race slips through, the UNIQUE INSERT is the atomic, last-line
-- guard (a second use → unique-violation → the slip is rejected). This is OUR-side anti-fraud,
-- independent of the external check.
--
-- Per-service schema ownership: ONLY payment-service writes schema `payment`. NO cross-service FKs
-- (`booking_id`/`customer_id` are bare UUIDs). `payment_id` references payment.payments (same
-- schema) so a slip is bound 1:1 to the payment row it settled.
--
-- All money columns are NUMERIC (never float) — exact decimal, `rust_decimal::Decimal` end-to-end.

-- The verified-slip record: one row per accepted slip. Written in the SAME transaction as the
-- payment row's paid-stamp + the `payment.completed` outbox event (transactional outbox), so a
-- verified slip and the charge it settled either both commit or neither does.
CREATE TABLE payment.payment_slips (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- The payment this slip settled (1:1). Same-schema reference — payment owns both rows.
    payment_id    UUID NOT NULL REFERENCES payment.payments(id) ON DELETE CASCADE,
    -- Booking the slip paid (bare UUID, owned by booking — audit/lookup convenience, no FK).
    booking_id    UUID NOT NULL,
    -- Slip2Go's verification id (UUID). UNIQUE: re-using the SAME Slip2Go reference cannot pay a
    -- second booking. Also the key for the FREE re-read (GET /verify-slip/{referenceId}).
    reference_id  TEXT NOT NULL,
    -- The bank transfer reference printed on the slip (globally unique per real transfer). UNIQUE:
    -- the PRIMARY our-side dedupe — one real transfer settles at most one booking.
    trans_ref     TEXT NOT NULL,
    -- The verified transfer amount Slip2Go returned (exact decimal). For audit; the charge is the
    -- server estimate, never this client-influenced number — we only assert amount >= estimate.
    amount        NUMERIC(12,2) NOT NULL,
    -- The S3 key of the stored slip image (PRIVATE bucket, like guard documents — PDPA/audit).
    slip_key      TEXT NOT NULL,
    verified_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- DEDUPE GUARDS — the atomic anti-fraud last line. A slip's transRef OR its Slip2Go referenceId
-- may appear at most once across ALL bookings. The handler does an INSERT; a unique-violation on
-- EITHER means "this slip already paid something" → reject (typed SLIP_DUPLICATE error). Inline
-- (the table is empty at creation; later additive indexes on populated tables use CONCURRENTLY).
CREATE UNIQUE INDEX uq_payment_slips_trans_ref    ON payment.payment_slips (trans_ref);
CREATE UNIQUE INDEX uq_payment_slips_reference_id ON payment.payment_slips (reference_id);

-- Look up the slip for a payment (idempotent re-confirm of an accepted slip).
CREATE INDEX idx_payment_slips_payment ON payment.payment_slips (payment_id);

-- The `payment_method` column is free TEXT (no enum) — the REAL path records `promptpay_slip`
-- (the SIMULATED path keeps `prepaid`). No DDL needed for the column itself; documented here so
-- the allowed value set is discoverable alongside the schema: 'prepaid' | 'promptpay_slip'.
COMMENT ON COLUMN payment.payments.payment_method IS
    'How the charge was settled: ''prepaid'' (simulated gateway) | ''promptpay_slip'' (real Slip2Go-verified transfer).';

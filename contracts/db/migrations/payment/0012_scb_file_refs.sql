-- pguard payment-service — ONE SCB reference space for ALL THREE money streams.
--
-- THE DEFECT THIS FIXES. Every stream that leaves the platform over SCB Business Net derives its
-- file reference from the SAME clock: `batch_ref` is a 12-digit `DDMMYYHHMMSS` Bangkok stamp
-- (BCHDET field 1) and `file_ref` is that stamp plus the product code (HEADER field 1). Stream ①
-- (customer refunds) and stream ③ (guard payout) BOTH ride PromptPay, so both stamp the product
-- `PPY` — which means a refund export and a payout export committed in the same Bangkok second emit
-- byte-identical HEADER field 1 AND byte-identical BCHDET field 1.
--
-- Migration 0010 already judged that hazard worth a unique index and a typed 409, and migration 0011
-- shipped the same guard for refunds from day one. But `uq_payout_batches_file_ref` and
-- `uq_refund_batches_file_ref` live on DIFFERENT TABLES and cannot see each other, so the
-- cross-stream collision passes both: two files go to the bank carrying the references SCB de-dups
-- on, and which one the bank keeps is not ours to decide. The reasoning behind those indexes does
-- not stop at a table boundary — the BANK's key space is global, so ours has to be too.
--
-- WHY A SHARED RESERVATION TABLE rather than a wider per-table index or a longer ref:
--   * it is the only shape that also covers stream ② (the platform-cut sweep to the company revenue
--     account) the day it lands — that file is `OAT`, so its file_ref differs by product suffix
--     while its BATCH ref collides exactly as the other two do;
--   * `batch_ref` is capped at 12 characters by the toolkit (doc line 1993 — BCHDET field 1), so
--     making the reference itself wider/random is not available to us;
--   * it needs no cross-table trigger and no advisory lock: a PRIMARY KEY plus a UNIQUE is the whole
--     mechanism, and it is enforced by the database rather than by every future caller remembering.
--
-- HOW IT IS USED. Both export paths reserve INSIDE the transaction that writes their batch, before
-- committing. A unique violation rolls the WHOLE transaction back — no batch header, no paid-marker
-- rows, no `refund_status` advanced — and surfaces as the SAME typed Thai 409 the intra-stream
-- collision already returns, because it is the same situation and the same remedy: the admin clicks
-- again a second later with a fresh stamp. The per-table unique indexes STAY: belt and braces is
-- cheap on the money path, and dropping them would silently widen the window between this table
-- being created and every writer being taught to use it.
--
-- Per-service schema ownership: ONLY payment writes schema `payment`. No cross-service FKs.
-- IDEMPOTENT (CLAUDE.md): CREATE … IF NOT EXISTS + a duplicate_object catch, so applying it twice is
-- a no-op, and it is safe WITHOUT --single-transaction.

CREATE TABLE IF NOT EXISTS payment.scb_file_refs (
    -- HEADER field 1 — `batch_ref || product_code` (e.g. `070926120000PPY`). The PRIMARY KEY is the
    -- reservation: the first stream to commit this second owns the reference.
    file_ref   TEXT        PRIMARY KEY,
    -- BCHDET field 1 — the bare 12-digit Bangkok stamp, WITHOUT the product code.
    batch_ref  TEXT        NOT NULL,
    -- Which money stream took it (see the CHECK below) — so an operator reading this table can tell
    -- at a glance which export a reference belongs to without joining two batch tables.
    stream     TEXT        NOT NULL,
    -- The `payout_batches.id` / `refund_batches.id` that reserved it. POLYMORPHIC, therefore NO FK:
    -- the row it points at lives in one of several tables (the same reason
    -- `refund_batch_items.source_id` carries none). Nullable so a future caller may reserve a
    -- reference before it knows its batch id.
    batch_id   UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The vocabulary is closed to the three streams of the bank-export phase: ① customer refunds,
-- ② the platform-cut sweep (`deduction` — not built yet, listed here so the table does not need a
-- migration on the day it lands), ③ guard payout. A stream we cannot name is a money file we cannot
-- attribute.
DO $$ BEGIN
    ALTER TABLE payment.scb_file_refs
        ADD CONSTRAINT chk_scb_file_refs_stream
            CHECK (stream IN ('payout', 'refund', 'deduction'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- THE BATCH REF IS ITS OWN KEY, not just a column of the file ref. Two files can differ in
-- `file_ref` (different product suffixes — a `PPY` refund and an `OAT` sweep) and still carry the
-- SAME `BCHDET` field 1, which is the reference the bank de-dups a batch on. Guarding only the file
-- ref would leave exactly that pair through.
--
-- NOT `CONCURRENTLY` (matching 0007/0009/0010/0011's plain-index style): the table is empty at
-- creation and is written once per generated file by an admin export, so the brief lock is free —
-- while a failed CONCURRENTLY build would leave an INVALID index that a re-apply's `IF NOT EXISTS`
-- silently skips, i.e. the de-dup guard permanently off on a money table.
--
-- If this statement FAILS with a uniqueness error, the database already holds two reservations
-- sharing a batch ref — the bug above already happened. That must be looked at by a human (which
-- file did the bank take?), so it is left to fail loudly rather than de-duplicating money rows on
-- its own initiative.
CREATE UNIQUE INDEX IF NOT EXISTS uq_scb_file_refs_batch_ref
    ON payment.scb_file_refs (batch_ref);

COMMENT ON TABLE  payment.scb_file_refs IS
    'The SHARED reservation of SCB batch/file references across every money stream (① customer refunds, ② the platform-cut sweep, ③ guard payout). The per-table uniques on payout_batches/refund_batches cannot see each other, and two PromptPay streams stamped in the same Bangkok second produce identical HEADER field 1 and BCHDET field 1 — the references the bank de-dups on. Reserved inside the exporting transaction, so a collision rolls the whole export back with nothing marked paid/processed.';
COMMENT ON COLUMN payment.scb_file_refs.file_ref IS
    'HEADER field 1 = batch_ref || product code (e.g. 070926120000PPY). PRIMARY KEY — first stream to commit this second owns it.';
COMMENT ON COLUMN payment.scb_file_refs.batch_ref IS
    'BCHDET field 1 — the bare 12-digit DDMMYYHHMMSS Bangkok stamp. UNIQUE in its own right: two streams with different product suffixes still collide here, and this is the batch reference the bank de-dups on.';
COMMENT ON COLUMN payment.scb_file_refs.stream IS
    'Which money stream reserved the reference: payout (③ guards), refund (① customers), deduction (② the platform-cut sweep, not built yet).';
COMMENT ON COLUMN payment.scb_file_refs.batch_id IS
    'The payout_batches.id / refund_batches.id that reserved this reference. Polymorphic, so deliberately no FK.';

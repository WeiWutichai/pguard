-- pguard payment-service — index for the admin refund queue (dashboard "คิวคืนเงิน" signal).
--
-- The admin refund queue (`GET /admin/refunds/queue`) lists payments awaiting refund action /
-- in-progress — rows where `refund_status` is set (a settle left a refund owed) — newest first,
-- optionally narrowed to one workflow state. A partial index on the refund-bearing rows keeps the
-- list + count cheap as the (mostly NULL-refund_status) payments table grows.
--
-- CONCURRENTLY (CLAUDE.md "Data"): payment.payments is production-relevant (the money path), so
-- the additive index never holds a write lock. CONCURRENTLY cannot run inside a txn block — the
-- migration runner must apply this file with autocommit (no wrapping BEGIN/COMMIT).
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_payments_refund_queue
    ON payment.payments (refund_status, created_at DESC)
    WHERE refund_status IS NOT NULL;

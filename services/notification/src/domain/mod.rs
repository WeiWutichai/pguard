//! PURE domain logic — no DB, no HTTP. 100% unit-testable.
//!
//! - [`mapping`] — turn an incoming `pguard.events.*` event into a [`NotificationPlan`].
//! - [`checkin`] — the hourly check-in reminder rules (ledger routing + DUE rule + push copy).
//! - `idempotency` — an in-memory model of the at-least-once dedupe the DB enforces
//!   (via `notification.processed_events`), used to unit-test the consumer's decision
//!   logic without a database. Test-only.

pub mod checkin;
pub mod mapping;

#[cfg(test)]
pub mod idempotency;

pub use checkin::CheckinLedgerOp;
pub use mapping::{
    dispatch_plan_for_guard, payment_completed_plans, plan_for_event, NotificationPlan,
};

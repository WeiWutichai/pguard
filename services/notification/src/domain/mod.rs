//! PURE domain logic — no DB, no HTTP. 100% unit-testable.
//!
//! - [`mapping`] — turn an incoming `pguard.events.*` event into a [`NotificationPlan`].
//! - `idempotency` — an in-memory model of the at-least-once dedupe the DB enforces
//!   (via `notification.processed_events`), used to unit-test the consumer's decision
//!   logic without a database. Test-only.

pub mod mapping;

#[cfg(test)]
pub mod idempotency;

pub use mapping::{dispatch_plan_for_guard, plan_for_event, NotificationPlan};

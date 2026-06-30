//! PURE domain logic — no DB, no HTTP, no NATS. 100% unit-testable.
//!
//! v2 is PRE-PAY then SETTLE:
//! - [`pricing::expected_total`] — the PRE-PAY estimate (`base_fee × hours × guard_count + tip`),
//!   computed entirely from the booking's server-owned inputs (never a client body).
//! - [`pricing::is_payable_status`] — which booking statuses admit a fresh pre-pay (post-accept,
//!   pre-complete).
//! - [`pricing::reconcile`] — on completion, diff the actual-hours bill (`post_pay_charge`)
//!   against the pre-paid amount → refund the overpay or record the shortfall (the base is never
//!   double-charged).
//! - [`pricing::post_pay_charge`] — the actual-hours bill (base prorated to worked hours + flat
//!   tip); the reconcile SETTLE target.
//! - [`proration`] — `compute_proration` (ported verbatim from v1), reused by `post_pay_charge`.

pub mod pricing;
pub mod proration;
pub mod slip;

pub use pricing::{expected_total, is_payable_status, reconcile, Reconciliation};

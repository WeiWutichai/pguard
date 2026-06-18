//! PURE domain logic — no DB, no HTTP, no NATS. 100% unit-testable.
//!
//! - [`pricing`] — `post_pay_charge` (the POST-PAY bill: base prorated to worked hours + flat
//!   tip, raised on completion). Builds on the module-internal `expected_total`.
//! - [`proration`] — `compute_proration` (ported verbatim from v1), reused by `post_pay_charge`.

pub mod pricing;
pub mod proration;

pub use pricing::post_pay_charge;

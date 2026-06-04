//! PURE domain logic — no DB, no HTTP, no NATS. 100% unit-testable.
//!
//! - [`proration`] — `compute_proration` (ported verbatim from v1), the heart of the
//!   refund-on-completion math.
//! - [`validation`] — payment-method + amount validation (positive, under cap).
//! - [`is_payable_status`] — the pure rule for whether a booking status admits a charge.

pub mod proration;
pub mod validation;

pub use proration::{compute_proration, Proration};
pub use validation::validate_payment;

/// The booking status (as the internal read reports it) must be `accepted` for a charge to
/// be legitimate: the guard has committed but work has not progressed past payment. Pure so
/// the rule lives in one place and is unit-testable without a DB.
///
/// Kept as a free function over `&str` (the internal read returns status as text) — the
/// payment service has no need to depend on booking's status enum.
pub fn is_payable_status(status: &str) -> bool {
    status == "accepted"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_accepted_is_payable() {
        assert!(is_payable_status("accepted"));
        for s in [
            "requested",
            "declined",
            "en_route",
            "arrived",
            "completed",
            "cancelled",
            "",
            "ACCEPTED",
        ] {
            assert!(!is_payable_status(s), "{s} must not be payable");
        }
    }
}

//! PURE payment-request validation — no DB/HTTP/NATS. 100% unit-testable.
//!
//! Ported from v1 `validate_payment_request` (`../guard-dispatch/services/booking/
//! src/service.rs` ~line 2088): a valid payment method + a positive amount. v2 adds an
//! upper cap (defensive — a client cannot submit an absurd amount; the authoritative
//! booking price is a tracked follow-up since v2 booking has no price column yet).
//!
//! ALL money is [`rust_decimal::Decimal`] — never `f64` (CLAUDE.md money rules).

use rust_decimal::Decimal;

/// Accepted payment methods (mirrors v1's `valid_methods`).
pub const VALID_PAYMENT_METHODS: [&str; 4] =
    ["promptpay", "credit_card", "debit_card", "mobile_banking"];

/// Upper bound on a single charge (THB). Defensive cap against a client submitting an
/// absurd amount. Until v2 booking carries an authoritative price column, the amount is
/// client-supplied + validated here; deriving it from the booking price is a tracked
/// follow-up. Kept generous (1,000,000 THB) so legitimate long bookings are never blocked.
pub const MAX_PAYMENT_AMOUNT: Decimal = Decimal::from_parts(1_000_000, 0, 0, false, 0);

/// Why a payment request was rejected (pure error — the API layer maps it to a 400).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AmountError {
    InvalidMethod,
    NonPositive,
    AboveCap,
    TooManyDecimals,
}

impl AmountError {
    /// A generic, non-enumerating client message (CLAUDE.md money rules / §9). Deliberately
    /// does NOT echo the submitted value or list internal limits.
    pub fn message(self) -> &'static str {
        match self {
            AmountError::InvalidMethod => "Invalid payment method",
            AmountError::NonPositive => "Payment amount must be positive",
            AmountError::AboveCap => "Payment amount exceeds the allowed limit",
            AmountError::TooManyDecimals => "Payment amount must have at most 2 decimal places",
        }
    }
}

/// Validate a payment method + amount. `amount` must be `> 0`, `<= MAX_PAYMENT_AMOUNT`, and
/// have at most 2 decimal places — otherwise the `NUMERIC(12,2)` column would silently
/// re-scale it and the charged amount would differ from what the client submitted.
pub fn validate_payment(method: &str, amount: Decimal) -> Result<(), AmountError> {
    if !VALID_PAYMENT_METHODS.contains(&method) {
        return Err(AmountError::InvalidMethod);
    }
    if amount <= Decimal::ZERO {
        return Err(AmountError::NonPositive);
    }
    if amount.scale() > 2 {
        return Err(AmountError::TooManyDecimals);
    }
    if amount > MAX_PAYMENT_AMOUNT {
        return Err(AmountError::AboveCap);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dec(s: &str) -> Decimal {
        s.parse().unwrap()
    }

    #[test]
    fn accepts_valid_method_and_amount() {
        for m in VALID_PAYMENT_METHODS {
            assert!(validate_payment(m, dec("100.00")).is_ok(), "method {m}");
        }
    }

    #[test]
    fn rejects_unknown_method() {
        assert_eq!(
            validate_payment("bitcoin", dec("100.00")),
            Err(AmountError::InvalidMethod)
        );
    }

    #[test]
    fn rejects_zero_and_negative() {
        assert_eq!(
            validate_payment("promptpay", Decimal::ZERO),
            Err(AmountError::NonPositive)
        );
        assert_eq!(
            validate_payment("promptpay", dec("-1")),
            Err(AmountError::NonPositive)
        );
    }

    #[test]
    fn rejects_above_cap() {
        let over = MAX_PAYMENT_AMOUNT + dec("0.01");
        assert_eq!(
            validate_payment("promptpay", over),
            Err(AmountError::AboveCap)
        );
    }

    #[test]
    fn accepts_exactly_at_cap() {
        assert!(validate_payment("promptpay", MAX_PAYMENT_AMOUNT).is_ok());
    }

    #[test]
    fn messages_do_not_echo_amount() {
        // Generic, non-enumerating messages only (no internal leak).
        assert_eq!(
            AmountError::NonPositive.message(),
            "Payment amount must be positive"
        );
        assert_eq!(
            AmountError::AboveCap.message(),
            "Payment amount exceeds the allowed limit"
        );
        assert_eq!(
            AmountError::InvalidMethod.message(),
            "Invalid payment method"
        );
    }

    #[test]
    fn max_payment_amount_is_one_million() {
        assert_eq!(MAX_PAYMENT_AMOUNT, dec("1000000"));
    }

    #[test]
    fn rejects_more_than_two_decimal_places() {
        // NUMERIC(12,2) would silently round these — reject so the charge is exact.
        for s in ["400.999", "0.001", "100.005"] {
            assert_eq!(
                validate_payment("promptpay", dec(s)),
                Err(AmountError::TooManyDecimals),
                "{s} must be rejected"
            );
        }
        // Exactly 2 dp (and fewer) are fine.
        assert!(validate_payment("promptpay", dec("400.99")).is_ok());
        assert!(validate_payment("promptpay", dec("400.5")).is_ok());
        assert!(validate_payment("promptpay", dec("400")).is_ok());
    }
}

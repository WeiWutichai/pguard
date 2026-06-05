//! PURE pricing logic — no DB/HTTP/NATS. 100% unit-testable.
//!
//! The authoritative total a charge must cover, computed ENTIRELY from the booking's
//! server-owned inputs (`base_fee × hours × guard_count + tip`) — never from the client's
//! request body (CLAUDE.md money rules: money is server-computed). This closes the v1 hole
//! where the charge `amount` was client-supplied with only a positive/cap check.
//!
//! ALL money is [`rust_decimal::Decimal`] — never `f64`.

use rust_decimal::Decimal;

/// The authoritative total for a booking: `base_fee × hours × guard_count + tip`.
///
/// All inputs come from the authoritative booking read (`base_fee`/`guard_count`/`tip` are
/// server-owned columns; `hours` is the booked duration). Rounded to 2 dp to match the
/// `NUMERIC(12,2)` columns. `hours`/`guard_count` are clamped to `>= 0` defensively (the
/// booking layer already enforces `hours >= 1`, `guard_count 1..=20`).
pub fn expected_total(base_fee: Decimal, hours: i32, guard_count: i32, tip: Decimal) -> Decimal {
    let hours = Decimal::from(hours.max(0));
    let guards = Decimal::from(guard_count.max(0));
    (base_fee * hours * guards + tip).round_dp(2)
}

/// Whether a submitted `amount` is acceptable for an authoritative `expected` total.
///
/// The customer may pay AT LEAST the expected total — the surplus is treated as an
/// additional tip (the spec's "± allow tip"). They can never pay LESS (that is the money
/// safety property: a client can't undercut the server-computed price). An exact match is
/// the common case.
pub fn amount_covers_expected(amount: Decimal, expected: Decimal) -> bool {
    amount >= expected
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dec(s: &str) -> Decimal {
        s.parse().unwrap()
    }

    #[test]
    fn expected_total_is_base_times_hours_times_guards_plus_tip() {
        // 500/hr × 4h × 2 guards + 100 tip = 4100.00
        assert_eq!(expected_total(dec("500"), 4, 2, dec("100")), dec("4100.00"));
    }

    #[test]
    fn expected_total_single_guard_no_tip() {
        // 500/hr × 3h × 1 = 1500.00
        assert_eq!(
            expected_total(dec("500"), 3, 1, Decimal::ZERO),
            dec("1500.00")
        );
    }

    #[test]
    fn expected_total_rounds_to_two_dp() {
        // 33.333/hr × 3h × 1 + 0 = 99.999 → 100.00
        assert_eq!(
            expected_total(dec("33.333"), 3, 1, Decimal::ZERO),
            dec("100.00")
        );
    }

    #[test]
    fn expected_total_clamps_negative_inputs() {
        // Defensive: negative hours/guards never produce a negative or surprising total.
        assert_eq!(
            expected_total(dec("500"), -4, 1, Decimal::ZERO),
            Decimal::ZERO
        );
        assert_eq!(
            expected_total(dec("500"), 4, -2, Decimal::ZERO),
            Decimal::ZERO
        );
    }

    #[test]
    fn amount_covers_expected_accepts_exact_and_surplus() {
        let expected = dec("4100.00");
        assert!(
            amount_covers_expected(dec("4100.00"), expected),
            "exact is fine"
        );
        assert!(
            amount_covers_expected(dec("4200.00"), expected),
            "paying more (extra tip) is allowed"
        );
    }

    #[test]
    fn amount_covers_expected_rejects_undercharge() {
        let expected = dec("4100.00");
        assert!(
            !amount_covers_expected(dec("4099.99"), expected),
            "a client must never pay less than the authoritative total"
        );
        assert!(!amount_covers_expected(dec("0.01"), expected));
    }
}

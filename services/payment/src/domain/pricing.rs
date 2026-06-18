//! PURE pricing logic — no DB/HTTP/NATS. 100% unit-testable.
//!
//! The authoritative total a charge must cover, computed ENTIRELY from the booking's
//! server-owned inputs (`base_fee × hours × guard_count + tip`) — never from the client's
//! request body (CLAUDE.md money rules: money is server-computed). This closes the v1 hole
//! where the charge `amount` was client-supplied with only a positive/cap check.
//!
//! ALL money is [`rust_decimal::Decimal`] — never `f64`.

use rust_decimal::Decimal;

use super::proration::compute_proration;

/// The amount a customer owes under POST-PAY (the bill is raised on completion for the hours
/// ACTUALLY worked, not pre-paid for the booked hours): the base portion
/// (`base_fee × booked_hours × guard_count`) prorated to the worked hours, PLUS the full tip.
///
/// A tip is a flat gratuity and is NEVER prorated. The base proration reuses the verbatim-v1
/// [`compute_proration`] (overtime clamped to booked, negatives clamped to zero). `actual_seconds
/// = None` means the guard never started — unreachable once requesting completion requires a
/// start (booking enforces `work_started_at` before `pending_completion`), so this is a defensive
/// branch that keeps the full booked base. Rounded to 2 dp to match the `NUMERIC(12,2)` columns.
pub fn post_pay_charge(
    base_fee: Decimal,
    booked_hours: i32,
    guard_count: i32,
    tip: Decimal,
    actual_seconds: Option<i64>,
) -> Decimal {
    // base × booked × guards (tip excluded here — added flat below).
    let booked_base = expected_total(base_fee, booked_hours, guard_count, Decimal::ZERO);
    let base_due = match actual_seconds {
        Some(secs) => compute_proration(booked_base, booked_hours, secs).final_amount,
        None => booked_base,
    };
    (base_due + tip.max(Decimal::ZERO)).round_dp(2)
}

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
    fn post_pay_charges_full_total_when_actual_equals_booked() {
        // 500 × 4h × 1 + 0 tip, worked exactly 4h (14400s) → 2000.00.
        assert_eq!(
            post_pay_charge(dec("500"), 4, 1, Decimal::ZERO, Some(14400)),
            dec("2000.00")
        );
    }

    #[test]
    fn post_pay_prorates_the_base_to_worked_hours() {
        // Worked 2h of 4h → base 1000.00 (no tip).
        assert_eq!(
            post_pay_charge(dec("500"), 4, 1, Decimal::ZERO, Some(7200)),
            dec("1000.00")
        );
    }

    #[test]
    fn post_pay_keeps_the_tip_flat_not_prorated() {
        // Worked 2h of 4h with a 100 tip → base 1000 + FULL 100 tip = 1100.00 (tip not halved).
        assert_eq!(
            post_pay_charge(dec("500"), 4, 1, dec("100"), Some(7200)),
            dec("1100.00")
        );
    }

    #[test]
    fn post_pay_zero_worked_charges_only_the_tip() {
        // No hours worked → base 0, but the chosen tip still stands.
        assert_eq!(
            post_pay_charge(dec("500"), 4, 1, dec("100"), Some(0)),
            dec("100.00")
        );
    }

    #[test]
    fn post_pay_clamps_overtime_to_booked() {
        // Worked 6h on a 4h booking → clamped to 4h; no overtime billed.
        assert_eq!(
            post_pay_charge(dec("500"), 4, 2, Decimal::ZERO, Some(21600)),
            dec("4000.00") // 500 × 4 × 2
        );
    }

    #[test]
    fn post_pay_none_actual_keeps_full_booked_base() {
        // Defensive (unreachable in the normal flow): no start recorded → full booked base + tip.
        assert_eq!(
            post_pay_charge(dec("500"), 4, 1, dec("50"), None),
            dec("2050.00")
        );
    }

    #[test]
    fn post_pay_non_divisible_proration_rounds_then_adds_flat_tip() {
        // Pins the compose-then-round behavior at the post_pay_charge boundary (the base is
        // rounded to 2dp, prorated, rounded again, THEN the flat tip is added — never a
        // repeating decimal + tip):
        // base 33.34 × 3h = 100.02; worked 1h of 3h → 100.02/3 = 33.34; + flat tip 5 = 38.34.
        assert_eq!(
            post_pay_charge(dec("33.34"), 3, 1, dec("5"), Some(3600)),
            dec("38.34")
        );
        // base 33.3333 × 3h → 100.00 (2dp); ×1/3 → 33.33 (2dp); + flat tip 10 = 43.33.
        assert_eq!(
            post_pay_charge(dec("33.3333"), 3, 1, dec("10"), Some(3600)),
            dec("43.33")
        );
    }
}

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

/// Booking statuses a PRE-PAY charge is allowed against. v2 is PRE-PAY: the customer pays the
/// ESTIMATE once a guard has ACCEPTED, and that payment GATES the booking's `en_route` transition.
/// So payment is accepted from `accepted` onward but before the job is finished — `requested`
/// (no guard yet), `declined`/`cancelled` (dead), and `completed` (the reconcile path settles
/// that, not a fresh pre-pay) are all rejected. `pending_completion` (the guard requested
/// completion, the customer has not confirmed) still admits a late pre-pay defensively. Pure.
pub fn is_payable_status(status: &str) -> bool {
    matches!(
        status,
        "accepted" | "en_route" | "arrived" | "pending_completion"
    )
}

/// A booking that is DEAD in a negative sense: the guard withdrew (`declined`) or the customer
/// `cancelled`. Used by the pay path to catch a pay-vs-cancel RACE: if a fresh pre-pay committed
/// against a booking that had ALREADY gone terminal, the cancellation event was consumed (as a
/// NoOp) before the payment row existed, so `refund_on_cancellation` never saw it — the pay path
/// re-reads the booking after committing and compensates with an immediate full refund. Pure.
pub fn is_negative_terminal(status: &str) -> bool {
    matches!(status, "declined" | "cancelled")
}

/// The result of reconciling the actual-hours bill against the PRE-PAID amount on completion.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reconciliation {
    /// `actual == paid` — nothing to settle (the estimate matched the worked hours exactly).
    Even,
    /// `actual < paid` — refund the excess to the customer (emit `refund_processed`).
    Refund {
        final_amount: Decimal,
        refund: Decimal,
    },
    /// `actual > paid` — the customer owes more (e.g. a tip bump); record the delta as an extra
    /// charge. The base is NEVER re-charged; `extra` is only the difference above the pre-paid.
    Extra {
        final_amount: Decimal,
        extra: Decimal,
    },
}

/// RECONCILE the actual-hours bill against what was PRE-PAID, on booking completion.
///
/// v2 is PRE-PAY then SETTLE: the customer already paid `paid_amount` up front (the estimate for
/// the booked hours). On completion we recompute the bill for the hours ACTUALLY worked
/// ([`post_pay_charge`] — base prorated to worked hours + the flat tip) and diff it against the
/// pre-paid amount. The base is never double-charged; only the difference moves:
///  - `actual < paid` → REFUND the difference to the customer.
///  - `actual > paid` → record the shortfall as an EXTRA charge owed.
///  - equal → nothing to do.
///
/// All amounts are exact `Decimal`, rounded to 2 dp (matching the `NUMERIC(12,2)` columns).
pub fn reconcile(
    paid_amount: Decimal,
    base_fee: Decimal,
    booked_hours: i32,
    guard_count: i32,
    tip: Decimal,
    actual_seconds: Option<i64>,
) -> Reconciliation {
    let actual = post_pay_charge(base_fee, booked_hours, guard_count, tip, actual_seconds);
    match actual.cmp(&paid_amount) {
        std::cmp::Ordering::Equal => Reconciliation::Even,
        std::cmp::Ordering::Less => Reconciliation::Refund {
            final_amount: actual,
            refund: (paid_amount - actual).round_dp(2),
        },
        std::cmp::Ordering::Greater => Reconciliation::Extra {
            final_amount: actual,
            extra: (actual - paid_amount).round_dp(2),
        },
    }
}

/// The amount a customer owes for the hours ACTUALLY worked (the reconcile SETTLE target, and —
/// before PRE-PAY — the legacy POST-PAY bill): the base portion
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
    fn negative_terminal_is_only_declined_or_cancelled() {
        assert!(is_negative_terminal("declined"));
        assert!(is_negative_terminal("cancelled"));
        // NOT negative-terminal: payable/active states, completion, and unknowns must never
        // trigger the compensating refund (a legit paid booking advancing to en_route/arrived).
        for s in [
            "requested",
            "accepted",
            "en_route",
            "arrived",
            "pending_completion",
            "completed",
            "",
        ] {
            assert!(
                !is_negative_terminal(s),
                "{s} must not be negative-terminal"
            );
        }
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
    fn payable_status_gates_pre_pay_to_post_accept_pre_complete() {
        // PRE-PAY is allowed once a guard accepted, up to (defensively) pending_completion.
        for s in ["accepted", "en_route", "arrived", "pending_completion"] {
            assert!(is_payable_status(s), "{s} should be payable");
        }
        // No guard yet / dead / already-settled → not a fresh pre-pay.
        for s in ["requested", "declined", "cancelled", "completed", "weird"] {
            assert!(!is_payable_status(s), "{s} must NOT be payable");
        }
    }

    #[test]
    fn reconcile_refunds_the_overpay_when_actual_less_than_paid() {
        // Pre-paid the full estimate 500×4×1 + 0 = 2000.00; worked only 2h → actual 1000.00.
        // → refund 1000.00, final_amount 1000.00.
        let r = reconcile(dec("2000.00"), dec("500"), 4, 1, Decimal::ZERO, Some(7200));
        assert_eq!(
            r,
            Reconciliation::Refund {
                final_amount: dec("1000.00"),
                refund: dec("1000.00"),
            }
        );
    }

    #[test]
    fn reconcile_is_even_when_actual_equals_paid() {
        // Pre-paid 2000.00; worked the full 4h → actual 2000.00. Nothing to settle.
        let r = reconcile(dec("2000.00"), dec("500"), 4, 1, Decimal::ZERO, Some(14400));
        assert_eq!(r, Reconciliation::Even);
    }

    #[test]
    fn reconcile_charges_the_delta_when_actual_exceeds_paid() {
        // Customer pre-paid 2000.00 with NO tip, then completed with a 300 tip bump → actual
        // 500×4×1 + 300 = 2300.00. The base is NOT re-charged; only the 300 delta is owed.
        let r = reconcile(dec("2000.00"), dec("500"), 4, 1, dec("300"), Some(14400));
        assert_eq!(
            r,
            Reconciliation::Extra {
                final_amount: dec("2300.00"),
                extra: dec("300.00"),
            }
        );
    }

    #[test]
    fn reconcile_full_estimate_no_work_refunds_only_the_base() {
        // Pre-paid 500×4×1 + 100 tip = 2100.00; guard worked 0h → actual = tip-only 100.00.
        // Refund the entire base 2000.00 (the flat tip stands).
        let r = reconcile(dec("2100.00"), dec("500"), 4, 1, dec("100"), Some(0));
        assert_eq!(
            r,
            Reconciliation::Refund {
                final_amount: dec("100.00"),
                refund: dec("2000.00"),
            }
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

//! PURE pricing logic — no DB/HTTP/NATS. 100% unit-testable.
//!
//! The authoritative total a charge must cover, computed ENTIRELY from the booking's
//! server-owned inputs (`base_fee × hours × guard_count + tip`, plus VAT) — never from the
//! client's request body (CLAUDE.md money rules: money is server-computed). This closes the v1
//! hole where the charge `amount` was client-supplied with only a positive/cap check.
//!
//! VAT (2026-08-10 decision): catalog prices are VAT-EXCLUSIVE and 7% is ADDED on top, so the
//! customer pays MORE than before. [`expected_total`] therefore returns the GRAND TOTAL and is the
//! ONE funnel every charge goes through (pre-pay, the slip minimum check, the PromptPay QR amount)
//! — keep it that way, or the three would drift.
//!
//! ALL money is [`rust_decimal::Decimal`] — never `f64`.

use rust_decimal::Decimal;

use super::proration::compute_proration;

/// Thai VAT — 7%, in ONE place. Every VAT figure in the service derives from this constant
/// ([`vat_on`] adds it to a VAT-exclusive base, [`vat_within`] extracts it from a VAT-inclusive
/// gross); nothing else may hard-code 0.07 or `× 1.07`.
///
/// `from_parts(7, 0, 0, false, 2)` is the exact decimal `0.07` (a `const fn`, so this is a real
/// compile-time constant — never a float literal).
pub const VAT_RATE: Decimal = Decimal::from_parts(7, 0, 0, false, 2);

/// A bill split into what the service costs and what the Revenue Department is owed.
///
/// INVARIANT: `subtotal + vat == grand_total`, exactly (no independent rounding — VAT is always
/// derived FROM the subtotal it is charged on, then added, so the parts always reconstruct the
/// whole). Persisted verbatim onto `payment.payments` (`subtotal`/`vat_amount`) alongside the
/// charged amount, which is what a Thai tax invoice (ใบกำกับภาษี) must print.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PriceBreakdown {
    /// VAT-EXCLUSIVE service cost: `base_fee × hours × guard_count + tip`.
    pub subtotal: Decimal,
    /// 7% VAT on `subtotal`, rounded to 2 dp.
    pub vat: Decimal,
    /// `subtotal + vat` — what the customer actually pays.
    pub grand_total: Decimal,
}

impl PriceBreakdown {
    /// Build the split for a VAT-EXCLUSIVE `subtotal` (clamped to `>= 0`): add VAT on top.
    pub fn from_subtotal(subtotal: Decimal) -> Self {
        let subtotal = subtotal.max(Decimal::ZERO).round_dp(2);
        let vat = vat_on(subtotal);
        PriceBreakdown {
            subtotal,
            vat,
            grand_total: subtotal + vat,
        }
    }

    /// Split a VAT-INCLUSIVE `gross` the other way round: carve the VAT out of it. Used for money
    /// that is RETAINED out of an already-VAT-inclusive payment (the cancellation fee) — the
    /// customer paid VAT on that money, so keeping 107% of it as revenue would be pocketing the
    /// Revenue Department's share.
    pub fn from_gross(gross: Decimal) -> Self {
        let gross = gross.max(Decimal::ZERO).round_dp(2);
        let vat = vat_within(gross);
        PriceBreakdown {
            subtotal: gross - vat,
            vat,
            grand_total: gross,
        }
    }
}

/// VAT to ADD on top of a VAT-exclusive `subtotal`: `subtotal × 7%`, rounded to 2 dp.
pub fn vat_on(subtotal: Decimal) -> Decimal {
    (subtotal * VAT_RATE).round_dp(2)
}

/// VAT already INSIDE a VAT-inclusive `gross`: `gross × 7/107`, rounded to 2 dp.
pub fn vat_within(gross: Decimal) -> Decimal {
    (gross * VAT_RATE / (Decimal::ONE + VAT_RATE)).round_dp(2)
}

/// The money terms a charge is written with: the VAT split the customer is billed, plus the
/// booking's commission / cancellation-fee SNAPSHOT carried onto the payment row.
///
/// Snapshotting matters twice over: editing the service catalog later must never rewrite the money
/// of a job already booked, and the refund path (an event consumer, no HTTP) must be able to price
/// a cancellation without reading booking's schema.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ChargeTerms {
    /// What the customer is charged now, split for the tax invoice.
    pub breakdown: PriceBreakdown,
    /// Per-service commission %, deducted from the GUARD's pay (the customer pays the same either
    /// way). Clamped to `0..=100`.
    pub commission_percent: Decimal,
    /// What a CUSTOMER cancellation of this booking costs. Clamped to `>= 0`.
    pub cancellation_fee: Decimal,
}

impl ChargeTerms {
    /// Assemble the terms, CLAMPING the booking-supplied snapshot defensively (`commission_percent`
    /// into `0..=100`, `cancellation_fee` to `>= 0`). booking enforces the same via CHECK
    /// constraints, but payment must not depend on another service for its own integrity — and a
    /// pre-migration booking sends nothing at all, which the caller maps to zero.
    pub fn new(
        breakdown: PriceBreakdown,
        commission_percent: Decimal,
        cancellation_fee: Decimal,
    ) -> Self {
        ChargeTerms {
            breakdown,
            commission_percent: commission_percent
                .clamp(Decimal::ZERO, Decimal::ONE_HUNDRED)
                .round_dp(2),
            cancellation_fee: cancellation_fee.max(Decimal::ZERO).round_dp(2),
        }
    }
}

/// The cancellation fee actually retained when the CUSTOMER cancels: `min(fee, amount_paid)`.
///
/// "Take what is there, never leave a debt" — the platform keeps at most what the customer has
/// already transferred, so a cancellation can never turn into an invoice. Nothing paid → nothing
/// charged. Both inputs are clamped to `>= 0` defensively. Pure.
///
/// A GUARD withdrawal (`booking.declined`) never reaches this: the customer did nothing wrong, so
/// the refund is FULL (see `repo::refund_on_cancellation`).
pub fn cancellation_fee_charged(fee: Decimal, amount_paid: Decimal) -> Decimal {
    fee.max(Decimal::ZERO)
        .min(amount_paid.max(Decimal::ZERO))
        .round_dp(2)
}

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
/// Every arm carries the SETTLED [`PriceBreakdown`] (`grand_total` = the final bill, VAT included)
/// so the repo can persist the recomputed split next to `final_amount` — the tax invoice must show
/// the VAT on what was actually worked, not on the original estimate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reconciliation {
    /// `actual == paid` — nothing to settle (the estimate matched the worked hours exactly).
    Even { settled: PriceBreakdown },
    /// `actual < paid` — refund the excess to the customer (emit `refund_processed`).
    Refund {
        settled: PriceBreakdown,
        refund: Decimal,
    },
    /// `actual > paid` — the customer owes more (e.g. a tip bump); record the delta as an extra
    /// charge. The base is NEVER re-charged; `extra` is only the difference above the pre-paid.
    Extra {
        settled: PriceBreakdown,
        extra: Decimal,
    },
}

/// RECONCILE the actual-hours bill against what was PRE-PAID, on booking completion.
///
/// v2 is PRE-PAY then SETTLE: the customer already paid `paid_amount` up front (the VAT-inclusive
/// estimate for the booked hours). On completion we recompute the bill for the hours ACTUALLY
/// worked ([`settled_breakdown`] — the SUBTOTAL prorated to worked hours, then VAT recomputed on
/// that prorated subtotal) and diff its grand total against the pre-paid amount. The base is never
/// double-charged; only the difference moves:
///  - `actual < paid` → REFUND the difference to the customer.
///  - `actual > paid` → record the shortfall as an EXTRA charge owed.
///  - equal → nothing to do.
///
/// VAT is deliberately NOT prorated on its own: proportioning the subtotal and the VAT separately
/// would let the two round apart, so the persisted `subtotal + vat_amount` would no longer add up
/// to `final_amount`. VAT is always re-derived from the settled subtotal.
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
    let settled = settled_breakdown(base_fee, booked_hours, guard_count, tip, actual_seconds);
    match settled.grand_total.cmp(&paid_amount) {
        std::cmp::Ordering::Equal => Reconciliation::Even { settled },
        std::cmp::Ordering::Less => Reconciliation::Refund {
            settled,
            refund: (paid_amount - settled.grand_total).round_dp(2),
        },
        std::cmp::Ordering::Greater => Reconciliation::Extra {
            settled,
            extra: (settled.grand_total - paid_amount).round_dp(2),
        },
    }
}

/// The full bill (subtotal + VAT) for the hours ACTUALLY worked — the reconcile SETTLE target.
/// VAT is computed FROM the prorated subtotal, never prorated on its own (see [`reconcile`]).
pub fn settled_breakdown(
    base_fee: Decimal,
    booked_hours: i32,
    guard_count: i32,
    tip: Decimal,
    actual_seconds: Option<i64>,
) -> PriceBreakdown {
    PriceBreakdown::from_subtotal(post_pay_subtotal(
        base_fee,
        booked_hours,
        guard_count,
        tip,
        actual_seconds,
    ))
}

/// The VAT-EXCLUSIVE amount a customer owes for the hours ACTUALLY worked: the base portion
/// (`base_fee × booked_hours × guard_count`) prorated to the worked hours, PLUS the full tip.
///
/// A tip is a flat gratuity and is NEVER prorated. The base proration reuses the verbatim-v1
/// [`compute_proration`] (overtime clamped to booked, negatives clamped to zero). `actual_seconds
/// = None` means the guard never started — unreachable once requesting completion requires a
/// start (booking enforces `work_started_at` before `pending_completion`), so this is a defensive
/// branch that keeps the full booked base. Rounded to 2 dp to match the `NUMERIC(12,2)` columns.
pub fn post_pay_subtotal(
    base_fee: Decimal,
    booked_hours: i32,
    guard_count: i32,
    tip: Decimal,
    actual_seconds: Option<i64>,
) -> Decimal {
    // base × booked × guards (tip excluded here — added flat below).
    let booked_base = subtotal(base_fee, booked_hours, guard_count, Decimal::ZERO);
    let base_due = match actual_seconds {
        Some(secs) => compute_proration(booked_base, booked_hours, secs).final_amount,
        None => booked_base,
    };
    (base_due + tip.max(Decimal::ZERO)).round_dp(2)
}

/// The GRAND TOTAL for a booking — `base_fee × hours × guard_count + tip`, **plus 7% VAT**.
///
/// THE one funnel: the pre-pay charge, the slip's minimum-amount check and the PromptPay QR amount
/// all call this, so they can never quote different figures. All inputs come from the authoritative
/// booking read (`base_fee`/`guard_count`/`tip` are server-owned columns; `hours` is the booked
/// duration). Callers that need the split for the tax invoice use [`price_breakdown`].
pub fn expected_total(base_fee: Decimal, hours: i32, guard_count: i32, tip: Decimal) -> Decimal {
    price_breakdown(base_fee, hours, guard_count, tip).grand_total
}

/// The full estimate split — `subtotal` (VAT-exclusive), `vat`, and the `grand_total` the customer
/// pays. Persisted alongside the charge so the receipt can print a Thai tax invoice.
pub fn price_breakdown(
    base_fee: Decimal,
    hours: i32,
    guard_count: i32,
    tip: Decimal,
) -> PriceBreakdown {
    PriceBreakdown::from_subtotal(subtotal(base_fee, hours, guard_count, tip))
}

/// The VAT-EXCLUSIVE service cost: `base_fee × hours × guard_count + tip`, rounded to 2 dp to
/// match the `NUMERIC(12,2)` columns. `hours`/`guard_count` are clamped to `>= 0` defensively (the
/// booking layer already enforces `hours >= 1`, `guard_count 1..=20`).
pub fn subtotal(base_fee: Decimal, hours: i32, guard_count: i32, tip: Decimal) -> Decimal {
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

    // ----- VAT constant + the split -----

    #[test]
    fn vat_rate_is_exactly_seven_percent() {
        // The ONE constant every VAT figure derives from — an exact decimal, not a float.
        assert_eq!(VAT_RATE, dec("0.07"));
    }

    #[test]
    fn vat_on_a_round_subtotal() {
        // 2000.00 × 7% = 140.00 → grand total 2140.00.
        let b = PriceBreakdown::from_subtotal(dec("2000.00"));
        assert_eq!(b.subtotal, dec("2000.00"));
        assert_eq!(b.vat, dec("140.00"));
        assert_eq!(b.grand_total, dec("2140.00"));
    }

    #[test]
    fn vat_on_an_awkward_subtotal_rounds_and_still_reconstructs() {
        // 1234.57 × 7% = 86.4199 → 86.42 (half-up at 2dp); the parts must still add up EXACTLY to
        // the grand total (this is the property the persisted subtotal/vat_amount rely on).
        let b = PriceBreakdown::from_subtotal(dec("1234.57"));
        assert_eq!(b.vat, dec("86.42"));
        assert_eq!(b.grand_total, dec("1320.99"));
        assert_eq!(b.subtotal + b.vat, b.grand_total);

        // 333.33 × 7% = 23.3331 → 23.33 (rounds DOWN — the other side of the midpoint).
        let c = PriceBreakdown::from_subtotal(dec("333.33"));
        assert_eq!(c.vat, dec("23.33"));
        assert_eq!(c.grand_total, dec("356.66"));
        assert_eq!(c.subtotal + c.vat, c.grand_total);
    }

    #[test]
    fn vat_within_carves_out_of_a_vat_inclusive_gross() {
        // A retained cancellation fee is carved OUT of VAT-inclusive money: 107.00 gross holds
        // 7.00 VAT (107 × 7/107), leaving 100.00 of actual platform revenue.
        let b = PriceBreakdown::from_gross(dec("107.00"));
        assert_eq!(b.vat, dec("7.00"));
        assert_eq!(b.subtotal, dec("100.00"));
        assert_eq!(b.grand_total, dec("107.00"));
        // The parts reconstruct the gross exactly even when the division doesn't land on 2dp:
        // 500 × 7/107 = 32.7102... → 32.71, leaving 467.29.
        let c = PriceBreakdown::from_gross(dec("500.00"));
        assert_eq!(c.vat, dec("32.71"));
        assert_eq!(c.subtotal + c.vat, dec("500.00"));
    }

    #[test]
    fn adding_then_carving_vat_round_trips() {
        // add-on-top then carve-back-out returns the original base (the two helpers agree).
        let added = PriceBreakdown::from_subtotal(dec("2000.00"));
        let carved = PriceBreakdown::from_gross(added.grand_total);
        assert_eq!(carved.subtotal, dec("2000.00"));
        assert_eq!(carved.vat, dec("140.00"));
    }

    #[test]
    fn breakdown_clamps_negative_inputs_to_zero() {
        // Neither direction can ever produce negative money (nothing owed → no VAT either).
        for b in [
            PriceBreakdown::from_subtotal(dec("-10")),
            PriceBreakdown::from_gross(dec("-10")),
        ] {
            assert_eq!(b.subtotal, Decimal::ZERO);
            assert_eq!(b.vat, Decimal::ZERO);
            assert_eq!(b.grand_total, Decimal::ZERO);
        }
    }

    // ----- the estimate (grand total) -----

    #[test]
    fn expected_total_is_base_times_hours_times_guards_plus_tip_plus_vat() {
        // 500/hr × 4h × 2 guards + 100 tip = 4100.00 subtotal, +7% VAT 287.00 = 4387.00 charged.
        assert_eq!(subtotal(dec("500"), 4, 2, dec("100")), dec("4100.00"));
        assert_eq!(expected_total(dec("500"), 4, 2, dec("100")), dec("4387.00"));

        let b = price_breakdown(dec("500"), 4, 2, dec("100"));
        assert_eq!(b.subtotal, dec("4100.00"));
        assert_eq!(b.vat, dec("287.00"));
        assert_eq!(b.grand_total, dec("4387.00"));
    }

    #[test]
    fn expected_total_is_the_one_funnel_for_every_charge_path() {
        // Pre-pay, the slip minimum check and the PromptPay QR all charge THIS number; it must be
        // the breakdown's grand total, never the bare subtotal (a VAT-free quote would underpay).
        let b = price_breakdown(dec("500"), 3, 1, Decimal::ZERO);
        assert_eq!(
            expected_total(dec("500"), 3, 1, Decimal::ZERO),
            b.grand_total
        );
        assert_ne!(expected_total(dec("500"), 3, 1, Decimal::ZERO), b.subtotal);
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
        // 500/hr × 3h × 1 = 1500.00 + 105.00 VAT = 1605.00.
        assert_eq!(
            expected_total(dec("500"), 3, 1, Decimal::ZERO),
            dec("1605.00")
        );
    }

    #[test]
    fn expected_total_rounds_to_two_dp() {
        // 33.333/hr × 3h × 1 + 0 = 99.999 → subtotal 100.00, VAT 7.00 → 107.00.
        assert_eq!(subtotal(dec("33.333"), 3, 1, Decimal::ZERO), dec("100.00"));
        assert_eq!(
            expected_total(dec("33.333"), 3, 1, Decimal::ZERO),
            dec("107.00")
        );
    }

    #[test]
    fn expected_total_clamps_negative_inputs() {
        // Defensive: negative hours/guards never produce a negative or surprising total (and no
        // VAT is charged on nothing).
        assert_eq!(
            expected_total(dec("500"), -4, 1, Decimal::ZERO),
            Decimal::ZERO
        );
        assert_eq!(
            expected_total(dec("500"), 4, -2, Decimal::ZERO),
            Decimal::ZERO
        );
    }

    // ----- the actual-hours bill -----

    #[test]
    fn post_pay_charges_full_subtotal_when_actual_equals_booked() {
        // 500 × 4h × 1 + 0 tip, worked exactly 4h (14400s) → subtotal 2000.00, grand 2140.00.
        assert_eq!(
            post_pay_subtotal(dec("500"), 4, 1, Decimal::ZERO, Some(14400)),
            dec("2000.00")
        );
        assert_eq!(
            settled_breakdown(dec("500"), 4, 1, Decimal::ZERO, Some(14400)).grand_total,
            dec("2140.00")
        );
    }

    #[test]
    fn post_pay_prorates_the_subtotal_and_recomputes_vat_on_it() {
        // Worked 2h of 4h → subtotal 1000.00, VAT recomputed on THAT (70.00) → 1070.00.
        // NB: half of the original VAT (140/2 = 70.00) agrees here — the point is that the VAT is
        // DERIVED, so subtotal + vat always reconstructs grand_total exactly.
        let b = settled_breakdown(dec("500"), 4, 1, Decimal::ZERO, Some(7200));
        assert_eq!(b.subtotal, dec("1000.00"));
        assert_eq!(b.vat, dec("70.00"));
        assert_eq!(b.grand_total, dec("1070.00"));
        assert_eq!(b.subtotal + b.vat, b.grand_total);
    }

    #[test]
    fn prorated_vat_never_drifts_from_its_base() {
        // The rounding trap this design avoids: 3h booked at 100.00/h, worked 1h → subtotal
        // 100.00/3 → 100.00 (base 100 × 3 = 300 → /3 = 100.00), VAT 7.00. Prorating the VAT
        // INDEPENDENTLY (21.00/3 = 7.00) happens to agree here, but for 7h it does not:
        // subtotal 700/7 = 100.00 → VAT 7.00, whereas 49.00/7 = 7.00. Assert the invariant that
        // makes the persisted split trustworthy in ALL cases instead of enumerating them.
        for secs in [0_i64, 1234, 3600, 7200, 12345, 14400, 99999] {
            for hours in [1_i32, 3, 7, 24] {
                let b = settled_breakdown(dec("333.33"), hours, 2, dec("55.55"), Some(secs));
                assert_eq!(
                    b.subtotal + b.vat,
                    b.grand_total,
                    "split must reconstruct the total (hours={hours}, secs={secs})"
                );
                assert_eq!(
                    b.vat,
                    vat_on(b.subtotal),
                    "VAT is always derived from the settled subtotal"
                );
            }
        }
    }

    #[test]
    fn post_pay_keeps_the_tip_flat_not_prorated() {
        // Worked 2h of 4h with a 100 tip → base 1000 + FULL 100 tip = 1100.00 subtotal (tip not
        // halved), VAT 77.00 → 1177.00.
        assert_eq!(
            post_pay_subtotal(dec("500"), 4, 1, dec("100"), Some(7200)),
            dec("1100.00")
        );
        assert_eq!(
            settled_breakdown(dec("500"), 4, 1, dec("100"), Some(7200)).grand_total,
            dec("1177.00")
        );
    }

    #[test]
    fn post_pay_zero_worked_charges_only_the_tip() {
        // No hours worked → base 0, but the chosen tip still stands (and is VAT-able).
        assert_eq!(
            post_pay_subtotal(dec("500"), 4, 1, dec("100"), Some(0)),
            dec("100.00")
        );
        assert_eq!(
            settled_breakdown(dec("500"), 4, 1, dec("100"), Some(0)).grand_total,
            dec("107.00")
        );
    }

    #[test]
    fn post_pay_clamps_overtime_to_booked() {
        // Worked 6h on a 4h booking → clamped to 4h; no overtime billed.
        assert_eq!(
            post_pay_subtotal(dec("500"), 4, 2, Decimal::ZERO, Some(21600)),
            dec("4000.00") // 500 × 4 × 2
        );
    }

    #[test]
    fn post_pay_none_actual_keeps_full_booked_base() {
        // Defensive (unreachable in the normal flow): no start recorded → full booked base + tip.
        assert_eq!(
            post_pay_subtotal(dec("500"), 4, 1, dec("50"), None),
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

    // ----- reconcile (VAT-inclusive, against the VAT-inclusive pre-pay) -----

    #[test]
    fn reconcile_refunds_the_overpay_when_actual_less_than_paid() {
        // Pre-paid the full estimate 500×4×1 + VAT = 2140.00; worked only 2h → settled 1070.00.
        // → refund 1070.00 (the customer gets the unused VAT back too).
        let r = reconcile(dec("2140.00"), dec("500"), 4, 1, Decimal::ZERO, Some(7200));
        assert_eq!(
            r,
            Reconciliation::Refund {
                settled: PriceBreakdown {
                    subtotal: dec("1000.00"),
                    vat: dec("70.00"),
                    grand_total: dec("1070.00"),
                },
                refund: dec("1070.00"),
            }
        );
    }

    #[test]
    fn reconcile_is_even_when_actual_equals_paid() {
        // Pre-paid 2140.00; worked the full 4h → settled 2140.00. Nothing to settle.
        let r = reconcile(dec("2140.00"), dec("500"), 4, 1, Decimal::ZERO, Some(14400));
        assert_eq!(
            r,
            Reconciliation::Even {
                settled: PriceBreakdown {
                    subtotal: dec("2000.00"),
                    vat: dec("140.00"),
                    grand_total: dec("2140.00"),
                },
            }
        );
    }

    #[test]
    fn reconcile_charges_the_delta_when_actual_exceeds_paid() {
        // Customer pre-paid 2140.00 with NO tip, then completed with a 300 tip bump → settled
        // subtotal 2300, VAT 161.00 → 2461.00. The base is NOT re-charged; only the delta is owed
        // (321.00 = the 300 tip + its 21.00 VAT).
        let r = reconcile(dec("2140.00"), dec("500"), 4, 1, dec("300"), Some(14400));
        assert_eq!(
            r,
            Reconciliation::Extra {
                settled: PriceBreakdown {
                    subtotal: dec("2300.00"),
                    vat: dec("161.00"),
                    grand_total: dec("2461.00"),
                },
                extra: dec("321.00"),
            }
        );
    }

    #[test]
    fn reconcile_full_estimate_no_work_refunds_only_the_base() {
        // Pre-paid (500×4×1 + 100 tip) + VAT = 2247.00; guard worked 0h → settled = tip-only
        // 100.00 + 7.00 VAT = 107.00. Refund the entire base+its VAT = 2140.00 (the flat tip stands).
        let r = reconcile(dec("2247.00"), dec("500"), 4, 1, dec("100"), Some(0));
        assert_eq!(
            r,
            Reconciliation::Refund {
                settled: PriceBreakdown {
                    subtotal: dec("100.00"),
                    vat: dec("7.00"),
                    grand_total: dec("107.00"),
                },
                refund: dec("2140.00"),
            }
        );
    }

    #[test]
    fn post_pay_non_divisible_proration_rounds_then_adds_flat_tip() {
        // Pins the compose-then-round behavior at the subtotal boundary (the base is rounded to
        // 2dp, prorated, rounded again, THEN the flat tip is added — never a repeating decimal +
        // tip): base 33.34 × 3h = 100.02; worked 1h of 3h → 100.02/3 = 33.34; + flat tip 5 = 38.34.
        assert_eq!(
            post_pay_subtotal(dec("33.34"), 3, 1, dec("5"), Some(3600)),
            dec("38.34")
        );
        // base 33.3333 × 3h → 100.00 (2dp); ×1/3 → 33.33 (2dp); + flat tip 10 = 43.33; VAT on
        // that awkward figure = 3.03 (43.33 × 0.07 = 3.0331) → 46.36 charged.
        assert_eq!(
            post_pay_subtotal(dec("33.3333"), 3, 1, dec("10"), Some(3600)),
            dec("43.33")
        );
        let b = settled_breakdown(dec("33.3333"), 3, 1, dec("10"), Some(3600));
        assert_eq!(b.vat, dec("3.03"));
        assert_eq!(b.grand_total, dec("46.36"));
    }

    // ----- cancellation fee -----

    #[test]
    fn cancellation_fee_is_charged_in_full_when_the_customer_paid_more() {
        // Paid 2140.00, fee 300 → the whole fee is retained.
        assert_eq!(
            cancellation_fee_charged(dec("300"), dec("2140.00")),
            dec("300.00")
        );
    }

    #[test]
    fn cancellation_fee_is_clamped_to_what_was_actually_paid() {
        // "Take what is there, never leave a debt": a 500 fee against a 321.00 payment retains
        // 321.00 — the customer is never invoiced for the difference.
        assert_eq!(
            cancellation_fee_charged(dec("500"), dec("321.00")),
            dec("321.00")
        );
        // Exactly equal → the whole payment is retained, nothing refunded.
        assert_eq!(
            cancellation_fee_charged(dec("321.00"), dec("321.00")),
            dec("321.00")
        );
    }

    #[test]
    fn cancellation_fee_on_a_zero_payment_charges_nothing() {
        // Nothing paid (an unpaid cancel, or a zero-priced booking) → nothing to take.
        assert_eq!(
            cancellation_fee_charged(dec("500"), Decimal::ZERO),
            Decimal::ZERO
        );
        // And a zero fee never charges, however much was paid.
        assert_eq!(
            cancellation_fee_charged(Decimal::ZERO, dec("2140.00")),
            Decimal::ZERO
        );
    }

    #[test]
    fn cancellation_fee_clamps_negative_inputs() {
        // Defensive: a corrupt/negative snapshot can never hand money BACK out of the fee path.
        assert_eq!(
            cancellation_fee_charged(dec("-100"), dec("2140.00")),
            Decimal::ZERO
        );
        assert_eq!(
            cancellation_fee_charged(dec("300"), dec("-5")),
            Decimal::ZERO
        );
    }

    #[test]
    fn retained_fee_splits_out_its_vat_so_revenue_is_not_overstated() {
        // The fee is carved out of VAT-INCLUSIVE money, so the platform's share of a 321.00 fee is
        // 300.00 with 21.00 owed to the Revenue Department — not the whole 321.00.
        let kept = PriceBreakdown::from_gross(cancellation_fee_charged(dec("321"), dec("2140.00")));
        assert_eq!(kept.grand_total, dec("321.00"));
        assert_eq!(kept.vat, dec("21.00"));
        assert_eq!(kept.subtotal, dec("300.00"));
    }

    // ----- charge terms (the booking snapshot payment persists) -----

    #[test]
    fn charge_terms_clamp_the_booking_snapshot() {
        let b = price_breakdown(dec("500"), 4, 1, Decimal::ZERO);
        // A sane snapshot passes through (rounded to the column's scale).
        let t = ChargeTerms::new(b, dec("12.5"), dec("300"));
        assert_eq!(t.commission_percent, dec("12.50"));
        assert_eq!(t.cancellation_fee, dec("300.00"));
        assert_eq!(t.breakdown.grand_total, dec("2140.00"));

        // Out-of-range values are clamped rather than trusted (payment does not depend on
        // booking's CHECK constraints for its own integrity).
        assert_eq!(
            ChargeTerms::new(b, dec("-5"), dec("-1")).commission_percent,
            Decimal::ZERO
        );
        assert_eq!(
            ChargeTerms::new(b, dec("-5"), dec("-1")).cancellation_fee,
            Decimal::ZERO
        );
        assert_eq!(
            ChargeTerms::new(b, dec("140"), Decimal::ZERO).commission_percent,
            dec("100")
        );
    }

    #[test]
    fn commission_never_changes_what_the_customer_pays() {
        // The commission is deducted from the GUARD's pay; the customer's grand total is identical
        // at 0% and at 30% (the split lives entirely on the payout side).
        let b = price_breakdown(dec("500"), 4, 1, Decimal::ZERO);
        let free = ChargeTerms::new(b, Decimal::ZERO, Decimal::ZERO);
        let taxed = ChargeTerms::new(b, dec("30"), dec("300"));
        assert_eq!(free.breakdown.grand_total, taxed.breakdown.grand_total);
    }
}

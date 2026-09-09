//! PURE per-job settlement — no DB, no HTTP. The ONE place that says where a customer's money
//! WENT, and therefore the one place that computes **ยอดที่โดนหักเข้าระบบ**, the platform's own cut
//! (stream ②). 100% unit-testable.
//!
//! # What the platform's cut is — and what it deliberately is NOT
//!
//! The cut is what the platform KEEPS: the commission deducted from the guard's pay, the
//! cancellation fee retained when a customer backs out, the tip, and the billed-but-unpaid share of
//! a multi-guard booking — LESS anything billed and never collected (see below). That figure — and
//! only that figure — is swept into the company revenue account by the `OAT` file.
//!
//! It excludes two things sitting in the very same bank account that are NOT ours:
//!
//!  * **VAT (7%)** is collected FOR the Revenue Department. It is a LIABILITY the moment we take it,
//!    not income — the repo already encodes this (`NET_REVENUE_EXPR` subtracts `vat_amount`, with
//!    the reasoning inline). It is remitted MONTHLY via **ภ.พ.30** e-filing.
//!  * **The WHT withheld from guards** (`payout_batch_items.wht`) is likewise the Revenue
//!    Department's money, remitted via **ภ.ง.ด.3/53** e-filing by the 7th of the following month.
//!
//! Sweeping either into the revenue account would move the Revenue Department's money into company
//! income, and the shortfall would surface later as a tax liability with no cash behind it. VAT and
//! WHT get REPORTS that back a filing, never a transfer file. Do not "simplify" [`platform_cut`] by
//! folding them in.
//!
//! # Two components are in the cut only because of KNOWN, DEFERRED bugs
//!
//! Whoever fixes these must expect this figure to change:
//!
//!  * **[`JobSettlement::tip`]** — the customer is billed a gratuity (`pricing::subtotal` adds it)
//!    that the guard never receives (`payout::compute_payout` pays `base_fee × hours` only). Today
//!    the platform keeps 100% of every tip. When the tip reaches the guard, this component becomes 0
//!    and the guard's payout grows by the same amount.
//!  * **[`JobSettlement::unpaid_guard_share`]** — a booking can be billed for up to 20 guards while
//!    `booking.bookings` carries a single `guard_id`, so exactly ONE guard is ever paid. The other
//!    `guard_count − 1` shares are billed and kept. When multi-guard assignments land, this becomes
//!    0 and those shares become payouts.
//!
//! Both were deliberately left unfixed (decision 2026-09-07) — but they DO contribute to the cut
//! today, so the sweep and the reports show them honestly, itemised, rather than folding them into
//! "commission" where nobody would ever find them again.
//!
//! # BILLED IS NOT COLLECTED — and only COLLECTED money may be swept
//!
//! The completion reconcile has an `Extra` arm: when the settled bill comes out ABOVE the pre-paid
//! amount (a tip added after the pre-pay, or a `base_fee` corrected between charge and reconcile),
//! it records the HIGHER `final_amount` and the delta is never captured — `repo` says so in as many
//! words ("a real gateway would capture the extra here"). That delta is [`JobSettlement::uncollected`]:
//! money the customer OWES, not money in the bank.
//!
//! The receiving account also holds the VAT owed to the Revenue Department and the guard income not
//! yet paid out. So a sweep computed off the SETTLED BILL would move baht that never arrived, drawing
//! the account down by exactly the amount that is not ours — the shortfall surfacing later as a tax
//! liability or a payout that cannot be funded.
//!
//! [`JobSettlement::platform_cut`] therefore DEDUCTS `uncollected`, rather than every component being
//! re-based on the collected amount. That is the honest split, not merely the convenient one: the
//! guard is paid their whole `income` and the Revenue Department is owed its whole `vat` whatever the
//! customer transferred, so the entire shortfall falls on the platform's own share. Pro-rating the
//! components would instead shave the guard's pay and the tax liability to cover a customer's unpaid
//! bill — and it would make `commission` stop meaning "the commission deducted from the guard", which
//! is the number `payout_batch_items` was built from.
//!
//! The per-job cut is therefore SIGNED, exactly like [`JobSettlement::rounding_adjustment`] (see
//! migration 0013: "a job with a negative TOTAL simply nets off against the rest of the sweep. The
//! FILE total is what must be positive"). It is deliberately NOT clamped at zero per job: on a job
//! billed ฿107 more than was collected of which ฿100 is tip and ฿7 is VAT, the account is ฿7 SHORT,
//! and a clamp would leave that ฿7 hole while reporting a clean ฿0. The non-negativity that matters
//! is the FILE's, and `scb_export::transfer_bound_rejection` already refuses a sweep whose total is
//! not a transferable amount.
//!
//! # The invariant
//!
//! Every settled job must reconstruct EXACTLY, to the satang, what the customer ACTUALLY TRANSFERRED:
//!
//! ```text
//! customer_paid
//!     = refunded + vat + guard_transfer + wht + platform_cut
//!  where platform_cut = commission + cancellation_fee + tip + unpaid_guard_share
//!                       + rounding_adjustment − uncollected
//! ```
//!
//! [`JobSettlement::reconciles`] is that equation, and it is a real check rather than an identity:
//! the left side is built from `amount`/`overpaid_amount`, the right side from `refund_amount`,
//! `vat_amount`, `subtotal`, `final_amount` and the pricing snapshot — seven columns written by four
//! different settle paths. It is what catches a settle path that updates one and forgets another.
//!
//! Written the other way round it is the same statement with `uncollected` on the money-IN side —
//! `customer_paid + uncollected = refunded + vat + guard_transfer + wht + `[`JobSettlement::billed_cut`]
//! — which is how an accountant reading the ledger reconciles the BILL. Both forms are asserted.

use rust_decimal::Decimal;

/// One hundred, as an exact decimal — every percentage here divides by it.
const HUNDRED: Decimal = Decimal::from_parts(100, 0, 0, false, 0);

/// The pay basis for ONE guard on one job: `base_fee × hours`, rounded to 2 dp.
///
/// NO `guard_count` and NO tip, matching the guard-earnings model the guard already sees on their
/// screen — a payout must never disagree with what the guard was shown. `hours` is the ACTUAL worked
/// hours once the job is reconciled (`payments.actual_hours`), else the booked hours.
///
/// It lives HERE, not in [`crate::domain::payout`], because two different code paths depend on it
/// being the same number: the payout DEDUCTS a commission from it, and the sweep SWEEPS that same
/// commission. If the two ever computed the gross differently, the money would not add up and
/// nothing would say so.
pub fn guard_gross(base_fee: Decimal, hours: Decimal) -> Decimal {
    (base_fee * hours).round_dp(2)
}

/// The commission in BAHT taken out of `gross`: `gross × percent / 100`, rounded to 2 dp.
///
/// `None` (or a job that predates commissions) → 0%; the percentage is clamped to `0..=100`
/// defensively — booking has the same CHECK, but payment must not depend on another service's
/// constraints for its own integrity.
pub fn commission_on(gross: Decimal, commission_percent: Option<Decimal>) -> Decimal {
    let pct = commission_percent
        .unwrap_or(Decimal::ZERO)
        .clamp(Decimal::ZERO, HUNDRED);
    (gross * pct / HUNDRED).round_dp(2)
}

/// WHY a settled payment cannot be split — i.e. why it is EXCLUDED from the sweep and the reports,
/// rather than counted as zero.
///
/// This is the whole point of the type. A report that quietly treats a NULL snapshot column as 0
/// under-reports the platform's cut, which is the one direction a money report must never be wrong
/// in; the admin sees an honest "N jobs unknown, and here is why" instead. Each variant carries a
/// stable machine `code` (the preview groups by it) and a Thai `reason` (the admin reads it).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SnapshotGap {
    /// The job's money is not final yet — no `final_amount`, so the reconcile (or the cancellation
    /// settle) has not run. Its cut is not knowable, and will be on the next run.
    NotSettled,
    /// `subtotal`/`vat_amount` are NULL: the charge predates the VAT split (migration 0005). The
    /// VAT-exclusive bill cannot be recovered, so neither can the cut.
    NoVatSplit,
    /// One of `base_fee`/`booked_hours`/`guard_count`/`tip`/`commission_amount` is NULL: the charge
    /// predates the pricing snapshot (migration 0013). NOT recoverable — `subtotal = base × hours ×
    /// guards + tip` is one equation in four unknowns, and booking's current row is not what this
    /// job was billed on. See the migration header.
    NoPricingSnapshot,
    /// The stored columns do not add up (a component came out negative, or the reconstruction missed
    /// `customer_paid`). Never expected; surfaced rather than swallowed, because a money row that
    /// does not reconcile must be looked at by a human, not swept.
    DoesNotReconcile,
}

impl SnapshotGap {
    /// Stable machine code — the preview groups its exclusion counts by this, and a UI keys off it.
    pub const fn code(self) -> &'static str {
        match self {
            Self::NotSettled => "NOT_SETTLED",
            Self::NoVatSplit => "NO_VAT_SPLIT",
            Self::NoPricingSnapshot => "NO_PRICING_SNAPSHOT",
            Self::DoesNotReconcile => "DOES_NOT_RECONCILE",
        }
    }

    /// The Thai sentence the admin reads on the preview screen. It says what is missing AND what
    /// (if anything) can be done about it — "ข้อมูลไม่ครบ" alone would leave an admin re-clicking.
    pub const fn reason_th(self) -> &'static str {
        match self {
            Self::NotSettled => {
                "งานนี้ยังไม่ปิดยอด (ยังไม่ได้คิดเงินตามชั่วโมงจริง) — ยอดหักจะคำนวณได้หลังงานปิด"
            }
            Self::NoVatSplit => {
                "รายการนี้เกิดก่อนระบบแยกภาษีมูลค่าเพิ่ม จึงแยกยอดหักออกจาก VAT ไม่ได้ — ไม่นำมารวมในไฟล์"
            }
            Self::NoPricingSnapshot => {
                "รายการนี้เกิดก่อนระบบเก็บฐานราคา (ค่าบริการ/ชั่วโมง/จำนวน รปภ/ทิป/ค่าคอมมิชชั่น) \
                 จึงคำนวณยอดหักย้อนหลังไม่ได้ — ไม่นำมารวมในไฟล์"
            }
            Self::DoesNotReconcile => {
                "ยอดเงินของรายการนี้กระทบยอดไม่ตรง (ลูกค้าจ่าย ≠ ผลรวมของส่วนย่อย) — ต้องให้คนตรวจก่อน ไม่นำมารวมในไฟล์"
            }
        }
    }
}

/// The settled money state of ONE payment row, exactly as the database stores it — the INPUT to
/// [`split`]. Every `Option` here is a real "unknown", never a zero (see [`SnapshotGap`]).
///
/// Deliberately a plain struct of stored columns rather than a `PaymentResponse`: the split must be
/// derivable from what is PERSISTED, so that a historical export is reproducible. Anything that
/// needed a cross-service read would put us back where migration 0013 started.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SettledPayment {
    /// The charged bill (VAT-INCLUSIVE) — `payments.amount`.
    pub amount: Decimal,
    /// Money transferred ABOVE the charged bill (a slip overpay) — `payments.overpaid_amount`.
    pub overpaid: Decimal,
    /// The settled bill (VAT-INCLUSIVE) — `payments.final_amount`. `None` = not settled yet.
    pub final_amount: Option<Decimal>,
    /// What goes back to the customer — `payments.refund_amount`.
    pub refund_amount: Option<Decimal>,
    /// The VAT-EXCLUSIVE settled bill — `payments.subtotal`.
    pub subtotal: Option<Decimal>,
    /// The VAT inside the settled bill — `payments.vat_amount`.
    pub vat_amount: Option<Decimal>,
    /// `true` when the row is `refunded`, i.e. the job was CANCELLED/declined and never ran. The
    /// whole shape of the split changes: no guard was paid, so the only thing kept is the retained
    /// cancellation fee.
    pub cancelled: bool,
    /// ฿/hour/guard — `payments.base_fee` (migration 0013).
    pub base_fee: Option<Decimal>,
    /// The billed duration — `payments.booked_hours`.
    pub booked_hours: Option<i32>,
    /// How many guards were BILLED for — `payments.guard_count`.
    pub guard_count: Option<i32>,
    /// The flat gratuity billed — `payments.tip`.
    pub tip: Option<Decimal>,
    /// The commission in baht deducted from the guard's pay — `payments.commission_amount`.
    pub commission_amount: Option<Decimal>,
    /// Hours actually worked, clamped and rounded to 2 dp — `payments.actual_hours`. `None` (the
    /// guard never started) falls back to the booked hours, matching what the bill charged.
    pub actual_hours: Option<Decimal>,
    /// Tax withheld from the guard on this job — `payout_batch_items.wht`, or ZERO while the job has
    /// not yet ridden a payout file. Zero then means "nothing withheld YET", so the split shows the
    /// guard's whole income as still-owed `guard_transfer`; it does not move the cut either way.
    pub wht_withheld: Decimal,
}

/// WHERE one job's money went — the full split, every component named, nothing lumped together.
///
/// Read it as a balance: the left of [`Self::reconciles`] is what came IN from the customer, the
/// right is everywhere it went. [`Self::platform_cut`] is the part that is ours.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct JobSettlement {
    /// What the customer actually transferred: the charged bill plus any slip overpay.
    pub customer_paid: Decimal,
    /// What the customer is owed back (may still be sitting in the refund queue).
    pub refunded: Decimal,
    /// Billed but NOT collected — the completion reconcile's `Extra` arm, where the settled bill
    /// came out above the pre-paid amount (a tip added after the pre-pay, or a re-priced `base_fee`)
    /// and the delta was never captured. It is a RECEIVABLE, not money in the bank, so it is
    /// DEDUCTED from [`Self::platform_cut`]: the guard's income and the Revenue Department's VAT are
    /// owed in full regardless, so the whole shortfall falls on the platform's own share. See the
    /// module doc.
    pub uncollected: Decimal,
    /// VAT on the SETTLED bill. The Revenue Department's, remitted via ภ.พ.30 — never swept.
    pub vat: Decimal,
    /// The guard's assessable income for this job: `guard_gross − commission`. What the ภ.ง.ด.
    /// certificate records, and what `payout_batch_items.income` carries.
    pub guard_income: Decimal,
    /// Tax withheld from `guard_income`. The Revenue Department's, remitted via ภ.ง.ด.3/53 — never
    /// swept. Zero until the job rides a payout file.
    pub wht: Decimal,
    /// What actually reaches the guard's account: `guard_income − wht`.
    pub guard_transfer: Decimal,
    /// PLATFORM CUT — commission deducted from the guard's pay.
    pub commission: Decimal,
    /// PLATFORM CUT — the VAT-EXCLUSIVE part of a retained cancellation fee. The fee is retained out
    /// of VAT-inclusive money, so keeping all of it would be pocketing the Revenue Department's 7%.
    pub cancellation_fee: Decimal,
    /// PLATFORM CUT — the tip. In the cut only because of a KNOWN, DEFERRED bug (see the module doc).
    pub tip: Decimal,
    /// PLATFORM CUT — the billed-but-unpaid share of a multi-guard booking. In the cut only because
    /// of a KNOWN, DEFERRED bug (see the module doc).
    pub unpaid_guard_share: Decimal,
    /// PLATFORM CUT — the satang of drift between prorating on the UNROUNDED worked-hours ratio (the
    /// customer's bill) and paying on `actual_hours` ROUNDED to 2 dp (the guard's gross). The ONLY
    /// component that may be NEGATIVE: on an unlucky rounding the platform is genuinely a couple of
    /// baht out of pocket, and inventing a zero there would invent income.
    pub rounding_adjustment: Decimal,
}

impl JobSettlement {
    /// What the platform EARNED on this job per the settled BILL — the five named components, before
    /// asking whether the customer actually transferred the money.
    ///
    /// Reported (as the preview's per-component totals) and reconciled against, but never SWEPT: see
    /// [`Self::platform_cut`], which is the figure the `OAT` file carries.
    pub fn billed_cut(&self) -> Decimal {
        self.commission
            + self.cancellation_fee
            + self.tip
            + self.unpaid_guard_share
            + self.rounding_adjustment
    }

    /// **ยอดที่โดนหักเข้าระบบ** — what the platform may actually TAKE OUT of the receiving account for
    /// this job, and exactly what the `OAT` sweep transfers.
    ///
    /// [`Self::billed_cut`] MINUS [`Self::uncollected`]. Billing is not collecting: the reconcile's
    /// `Extra` arm records a settled bill above the pre-payment and never captures the delta, so
    /// sweeping the billed figure would move baht that never arrived — out of an account that also
    /// holds the Revenue Department's VAT and the guards' unpaid income. See the module doc for why
    /// the whole shortfall lands here rather than being pro-rated across the components, and why the
    /// per-job figure is signed rather than clamped.
    ///
    /// NOT VAT and NOT WHT: both are the Revenue Department's money, remitted by e-filing. See the
    /// module doc before adding a term here.
    pub fn platform_cut(&self) -> Decimal {
        self.billed_cut() - self.uncollected
    }

    /// The right-hand side of the invariant: every destination the money the customer ACTUALLY
    /// TRANSFERRED reached.
    pub fn reconstructed(&self) -> Decimal {
        self.refunded + self.vat + self.guard_transfer + self.wht + self.platform_cut()
    }

    /// THE INVARIANT: what actually came in equals everywhere it went, to the satang. See the module
    /// doc — the billed form (`customer_paid + uncollected == … + billed_cut`) is the same equation
    /// rearranged, and both are asserted in the tests.
    pub fn reconciles(&self) -> bool {
        self.reconstructed() == self.customer_paid
    }
}

/// Split one settled payment into where its money went. PURE.
///
/// Two shapes, because a cancelled job and a worked job are genuinely different events:
///
///  * **CANCELLED** (`payments.status = 'refunded'`) — no guard was paid, so there is no gross, no
///    commission, no tip kept and no unpaid guard share: the customer's money either went back or
///    was retained as the cancellation fee. The retained part is the row's own `subtotal` (the
///    cancellation settle rewrites the split to the fee's VAT split, so `subtotal` IS the
///    VAT-exclusive fee), and no migration-0013 snapshot is needed — which is why a historical
///    cancellation still reports correctly.
///  * **WORKED** — the settled `subtotal` splits into the guard's gross, the tip, the unpaid guard
///    shares and the rounding drift; the commission comes out of the gross.
///
/// Anything that cannot be split honestly returns a [`SnapshotGap`] — the caller EXCLUDES that job
/// and counts it, and never treats it as zero.
pub fn split(p: &SettledPayment) -> Result<JobSettlement, SnapshotGap> {
    // The bill has to be FINAL. A `completed` payment is `completed` from the moment of pre-pay, so
    // without this an in-progress job would be swept on its estimate and could never be corrected.
    let final_amount = p.final_amount.ok_or(SnapshotGap::NotSettled)?;
    // The VAT split is what separates our money from the Revenue Department's. Without it there is
    // no way to know which part of the bill is sweepable.
    let (subtotal, vat) = match (p.subtotal, p.vat_amount) {
        (Some(s), Some(v)) => (s, v),
        _ => return Err(SnapshotGap::NoVatSplit),
    };

    let customer_paid = p.amount + p.overpaid;
    let refunded = p.refund_amount.unwrap_or(Decimal::ZERO);
    // Billed above what was collected (the reconcile's `Extra` arm). Never negative: a settled bill
    // BELOW what was received always leaves a `refund_amount`, so anything negative here is money
    // that vanished — caught by the reconcile check at the end rather than silently absorbed.
    let uncollected = final_amount + refunded - customer_paid;

    let settled = if p.cancelled {
        // The whole retained amount is the cancellation fee, VAT already carved out of it.
        JobSettlement {
            customer_paid,
            refunded,
            uncollected,
            vat,
            guard_income: Decimal::ZERO,
            wht: Decimal::ZERO,
            guard_transfer: Decimal::ZERO,
            commission: Decimal::ZERO,
            cancellation_fee: subtotal,
            tip: Decimal::ZERO,
            unpaid_guard_share: Decimal::ZERO,
            rounding_adjustment: Decimal::ZERO,
        }
    } else {
        // A worked job needs the pricing snapshot; a NULL here is "unknown", never zero.
        let (Some(base_fee), Some(booked_hours), Some(guard_count), Some(tip), Some(commission)) = (
            p.base_fee,
            p.booked_hours,
            p.guard_count,
            p.tip,
            p.commission_amount,
        ) else {
            return Err(SnapshotGap::NoPricingSnapshot);
        };

        // The guard's pay basis: ACTUAL worked hours once reconciled, else the booked hours (the
        // defensive branch where the guard never started — the bill kept the full booked base).
        let hours = p
            .actual_hours
            .unwrap_or_else(|| Decimal::from(booked_hours.max(0)));
        let gross = guard_gross(base_fee, hours);
        let guard_income = gross - commission;
        let guard_transfer = guard_income - p.wht_withheld;

        // The (guard_count − 1) shares that are billed and never paid. Computed DIRECTLY from the
        // same gross the one paid guard receives — not as a leftover — so it stays a number an
        // accountant can check rather than a bucket everything unexplained falls into.
        let extra_guards = Decimal::from((guard_count - 1).max(0));
        let unpaid_guard_share = gross * extra_guards;

        // Whatever is left of the settled VAT-exclusive bill after the guard's gross, the tip and
        // the unpaid shares. A few satang of proration-rounding drift, either sign.
        let rounding_adjustment = subtotal - gross - tip - unpaid_guard_share;

        JobSettlement {
            customer_paid,
            refunded,
            uncollected,
            vat,
            guard_income,
            wht: p.wht_withheld,
            guard_transfer,
            commission,
            cancellation_fee: Decimal::ZERO,
            tip,
            unpaid_guard_share,
            rounding_adjustment,
        }
    };

    // Every NAMED component is money the platform genuinely kept, so none of them may be negative
    // (`rounding_adjustment` is the documented exception). A negative one means the stored columns
    // disagree with each other — a human question, not a number to sweep.
    if settled.commission < Decimal::ZERO
        || settled.cancellation_fee < Decimal::ZERO
        || settled.tip < Decimal::ZERO
        || settled.unpaid_guard_share < Decimal::ZERO
        || settled.guard_income < Decimal::ZERO
        || settled.refunded < Decimal::ZERO
        || settled.uncollected < Decimal::ZERO
        || !settled.reconciles()
    {
        return Err(SnapshotGap::DoesNotReconcile);
    }
    Ok(settled)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::pricing::{self, PriceBreakdown};
    use crate::domain::proration::compute_proration;

    fn d(s: &str) -> Decimal {
        s.parse().expect("decimal literal")
    }

    /// Build the SettledPayment a WORKED job leaves behind, by walking the ACTUAL production settle
    /// path: pre-pay charges `price_breakdown(...)`, the completion reconcile recomputes the bill
    /// from the worked seconds (`pricing::reconcile`) and rewrites `subtotal`/`vat_amount`/
    /// `final_amount`/`refund_amount`/`actual_hours`, and `commission_amount` is written from the
    /// same `guard_gross`∘`commission_on` pair the payout deducts with.
    ///
    /// Going through `pricing` rather than hand-computing the expected columns is the whole point:
    /// the property tests below then measure the REAL rounding behaviour of the money path, not a
    /// restatement of `split`'s own arithmetic.
    fn worked_job(
        base_fee: &str,
        booked_hours: i32,
        guard_count: i32,
        tip: &str,
        commission_percent: &str,
        worked_seconds: i64,
        wht_rate_percent: &str,
    ) -> SettledPayment {
        worked_job_billed_over(
            base_fee,
            booked_hours,
            guard_count,
            tip,
            tip,
            commission_percent,
            worked_seconds,
            wht_rate_percent,
        )
    }

    /// The same walk, but the customer PRE-PAID for `prepaid_tip` and the job SETTLED at `tip` — the
    /// reconcile's `Extra` arm when `tip > prepaid_tip`.
    ///
    /// This is the shape that makes B1 reachable and it is a REAL path, not a contrived one: the
    /// customer adds a gratuity after paying, `reconcile_on_completion` recomputes the bill from the
    /// booking's CURRENT tip, writes the higher `final_amount` — and the repo captures nothing ("a
    /// real gateway would capture the extra here"). `base_fee` moves the same comparison the same
    /// way; the tip is simply the cheapest way to express it through the real pricing functions.
    #[allow(clippy::too_many_arguments)]
    fn worked_job_billed_over(
        base_fee: &str,
        booked_hours: i32,
        guard_count: i32,
        prepaid_tip: &str,
        tip: &str,
        commission_percent: &str,
        worked_seconds: i64,
        wht_rate_percent: &str,
    ) -> SettledPayment {
        let base_fee = d(base_fee);
        let tip = d(tip);
        let charged = PriceBreakdown::from_subtotal(pricing::subtotal(
            base_fee,
            booked_hours,
            guard_count,
            d(prepaid_tip),
        ));
        let settled = pricing::settled_breakdown(
            base_fee,
            booked_hours,
            guard_count,
            tip,
            Some(worked_seconds),
        );
        let booked_base = pricing::subtotal(base_fee, booked_hours, guard_count, Decimal::ZERO);
        let actual_hours =
            compute_proration(booked_base, booked_hours, worked_seconds).actual_hours;
        let commission = commission_on(
            guard_gross(base_fee, actual_hours),
            Some(d(commission_percent)),
        );
        let refund = (charged.grand_total - settled.grand_total).max(Decimal::ZERO);
        // What the payout would withhold from this job's income, so the reconciliation is complete.
        let income = guard_gross(base_fee, actual_hours) - commission;
        let wht = (income * d(wht_rate_percent) / HUNDRED).round_dp(2);
        SettledPayment {
            amount: charged.grand_total,
            overpaid: Decimal::ZERO,
            final_amount: Some(settled.grand_total),
            refund_amount: (refund > Decimal::ZERO).then_some(refund),
            subtotal: Some(settled.subtotal),
            vat_amount: Some(settled.vat),
            cancelled: false,
            base_fee: Some(base_fee),
            booked_hours: Some(booked_hours),
            guard_count: Some(guard_count),
            tip: Some(tip),
            commission_amount: Some(commission),
            actual_hours: Some(actual_hours),
            wht_withheld: wht,
        }
    }

    /// Build the SettledPayment a CANCELLED job leaves behind, walking `repo::refund_on_cancellation`
    /// verbatim: retain `min(fee, amount)` VAT-inclusive, refund the rest, and rewrite the split to
    /// the fee's own VAT carve-out.
    fn cancelled_job(charged: &str, fee: &str, overpaid: &str) -> SettledPayment {
        let charged = d(charged);
        let overpaid = d(overpaid);
        let fee_charged = pricing::cancellation_fee_charged(d(fee), charged);
        let kept = PriceBreakdown::from_gross(fee_charged);
        let refund = (charged - fee_charged).max(Decimal::ZERO) + overpaid;
        SettledPayment {
            amount: charged,
            overpaid,
            final_amount: Some(fee_charged),
            refund_amount: (refund > Decimal::ZERO).then_some(refund),
            subtotal: Some(kept.subtotal),
            vat_amount: Some(kept.vat),
            cancelled: true,
            // A cancelled row still carries its snapshot (pre-pay wrote it) — `split` must not need
            // it, which is what keeps a HISTORICAL cancellation reportable.
            base_fee: None,
            booked_hours: None,
            guard_count: None,
            tip: None,
            commission_amount: None,
            actual_hours: None,
            wht_withheld: Decimal::ZERO,
        }
    }

    // ----- the two shared helpers the payout also deducts with -----

    #[test]
    fn the_gross_and_the_commission_are_the_payouts_own_arithmetic() {
        // 500 ฿/h × 4h = 2000 gross; 10% commission = 200; the guard's income is 1800.
        assert_eq!(guard_gross(d("500"), d("4")), d("2000.00"));
        assert_eq!(commission_on(d("2000.00"), Some(d("10"))), d("200.00"));
        // No commission snapshot, or a job that predates commissions → 0%, never a guessed default.
        assert_eq!(commission_on(d("2000.00"), None), Decimal::ZERO);
        // Out-of-range percentages are clamped, not trusted: payment must not depend on booking's
        // CHECK constraints for its own integrity.
        assert_eq!(commission_on(d("2000.00"), Some(d("-5"))), Decimal::ZERO);
        assert_eq!(commission_on(d("2000.00"), Some(d("999"))), d("2000.00"));
        // Rounded to the satang (the NUMERIC(12,2) columns), banker's like the rest of the path.
        assert_eq!(commission_on(d("333.33"), Some(d("7.5"))), d("25.00"));
    }

    /// The one that makes the whole feature honest: `compute_payout` (what the guard is PAID) and
    /// the sweep (what the platform KEEPS) must derive the gross and the commission from the same
    /// two functions, or the money silently stops adding up.
    #[test]
    fn the_payout_and_the_sweep_agree_on_the_gross_and_the_commission() {
        let base = d("437.50");
        let hours = d("3.25");
        let pct = d("12.5");
        let paid = crate::domain::payout::compute_payout(base, hours, Some(pct), d("3"));
        let gross = guard_gross(base, hours);
        let commission = commission_on(gross, Some(pct));
        assert_eq!(
            paid.income,
            gross - commission,
            "payout income == gross − the commission the sweep takes"
        );
    }

    // ----- the split itself -----

    #[test]
    fn a_plain_completed_job_splits_into_guard_pay_commission_and_vat() {
        // 500 ฿/h × 4h × 1 guard, no tip, 10% commission, worked the full 4h, 3% WHT.
        let s = split(&worked_job("500", 4, 1, "0", "10", 4 * 3600, "3")).expect("splits");
        assert_eq!(s.customer_paid, d("2140.00"), "2000 + 7% VAT");
        assert_eq!(s.refunded, Decimal::ZERO);
        assert_eq!(s.vat, d("140.00"));
        assert_eq!(s.guard_income, d("1800.00"), "2000 gross − 200 commission");
        assert_eq!(s.wht, d("54.00"), "3% of 1800");
        assert_eq!(s.guard_transfer, d("1746.00"));
        assert_eq!(s.commission, d("200.00"));
        assert_eq!(s.tip, Decimal::ZERO);
        assert_eq!(s.unpaid_guard_share, Decimal::ZERO);
        assert_eq!(s.rounding_adjustment, Decimal::ZERO);
        // THE CUT: the commission alone. NOT the VAT (140) and NOT the WHT (54).
        assert_eq!(s.platform_cut(), d("200.00"));
        assert!(s.reconciles());
    }

    /// The two DEFERRED BUGS, priced. This test exists so that whoever fixes either one sees exactly
    /// which figure moves: fix the tip and 100.00 leaves the cut for the guard; fix guard_count and
    /// 2000.00 does.
    #[test]
    fn the_tip_and_the_unpaid_guard_shares_are_in_the_cut_and_named_as_such() {
        // 500 ฿/h × 4h × 2 guards + 100 tip, 10% commission, full hours.
        let s = split(&worked_job("500", 4, 2, "100", "10", 4 * 3600, "3")).expect("splits");
        assert_eq!(s.customer_paid, d("4387.00"), "4100 + 7% VAT");
        assert_eq!(s.guard_income, d("1800.00"), "ONE guard, no tip in the pay");
        assert_eq!(s.tip, d("100.00"), "billed to the customer, kept by us");
        assert_eq!(
            s.unpaid_guard_share,
            d("2000.00"),
            "the second guard's whole share — nobody is paid it"
        );
        assert_eq!(s.commission, d("200.00"));
        assert_eq!(s.platform_cut(), d("2300.00"), "200 + 100 + 2000");
        assert!(s.reconciles());
        // The Revenue Department's two shares are OUTSIDE the cut, always.
        assert_eq!(s.vat, d("287.00"));
        assert_eq!(s.wht, d("54.00"));
    }

    #[test]
    fn a_prorated_job_puts_the_unworked_hours_back_and_keeps_the_whole_tip() {
        // Booked 4h at 500, worked 2h, 100 tip (never prorated), 10% commission.
        let s = split(&worked_job("500", 4, 1, "100", "10", 2 * 3600, "3")).expect("splits");
        assert_eq!(s.customer_paid, d("2247.00"), "(2000 + 100) + 7%");
        assert_eq!(s.refunded, d("1070.00"), "2247 − (1100 + 77)");
        assert_eq!(
            s.vat,
            d("77.00"),
            "VAT on the SETTLED 1100, not on the estimate"
        );
        assert_eq!(s.guard_income, d("900.00"), "1000 gross − 100 commission");
        assert_eq!(s.tip, d("100.00"), "a tip is flat — never prorated");
        assert_eq!(s.platform_cut(), d("200.00"), "100 commission + 100 tip");
        assert!(s.reconciles());
    }

    #[test]
    fn a_cancelled_job_keeps_only_the_fee_net_of_its_own_vat() {
        // Charged 2140 (VAT-inclusive), a 500 cancellation fee retained.
        let s = split(&cancelled_job("2140.00", "500.00", "0")).expect("splits");
        assert_eq!(s.customer_paid, d("2140.00"));
        assert_eq!(s.refunded, d("1640.00"));
        assert_eq!(s.cancellation_fee, d("467.29"), "500 − the 7/107 inside it");
        assert_eq!(
            s.vat,
            d("32.71"),
            "the Revenue Department's share of the fee"
        );
        assert_eq!(s.guard_income, Decimal::ZERO, "no guard was paid");
        assert_eq!(s.tip, Decimal::ZERO, "a cancelled job's tip is refunded");
        assert_eq!(s.platform_cut(), d("467.29"));
        assert!(s.reconciles());
    }

    #[test]
    fn a_fully_refunded_cancellation_keeps_nothing_at_all() {
        // The race-lost pre-pay compensator and a guard withdrawal both land here: full refund,
        // an all-zero split, and NOTHING to sweep.
        let s = split(&cancelled_job("2140.00", "0", "0")).expect("splits");
        assert_eq!(s.refunded, d("2140.00"));
        assert_eq!(s.platform_cut(), Decimal::ZERO);
        assert_eq!(s.vat, Decimal::ZERO);
        assert!(s.reconciles());
    }

    #[test]
    fn a_slip_overpay_is_returned_and_never_becomes_platform_cut() {
        // The customer transferred 200 more than the bill; the reconcile refunds it.
        let mut p = worked_job("500", 4, 1, "0", "10", 4 * 3600, "3");
        p.overpaid = d("200.00");
        p.refund_amount = Some(d("200.00"));
        let s = split(&p).expect("splits");
        assert_eq!(s.customer_paid, d("2340.00"), "2140 charged + 200 overpaid");
        assert_eq!(s.refunded, d("200.00"));
        assert_eq!(
            s.platform_cut(),
            d("200.00"),
            "the commission, NOT the overpay"
        );
        assert!(s.reconciles());
    }

    /// **B1 — THE SWEEP MAY NOT MOVE MONEY THAT NEVER ARRIVED.** The reconcile's `Extra` arm records
    /// a settled bill ABOVE the pre-payment and captures nothing, so a cut computed off the settled
    /// bill would draw the receiving account down by baht the customer never transferred — and that
    /// account also holds the Revenue Department's VAT and the guards' unpaid income.
    ///
    /// Walked through the REAL pricing path: pre-pay with no tip, settle with one.
    #[test]
    fn a_billed_but_uncollected_extra_is_deducted_from_the_cut_and_never_swept() {
        // 500 ฿/h × 4h, 10% commission, full hours; the customer pre-paid with NO tip and the job
        // settled with a ฿100 one → ฿107 (tip + its VAT) was billed and never collected.
        let p = worked_job_billed_over("500", 4, 1, "0", "100", "10", 4 * 3600, "3");
        let s = split(&p).expect("splits");
        assert_eq!(s.customer_paid, d("2140.00"), "2000 + 7%, no tip");
        assert_eq!(s.uncollected, d("107.00"), "the ฿100 tip and its ฿7 VAT");
        assert_eq!(s.refunded, Decimal::ZERO, "an Extra arm refunds nothing");
        // What the settled BILL earned…
        assert_eq!(s.billed_cut(), d("300.00"), "200 commission + 100 tip");
        // …and what may actually be TAKEN OUT of the account.
        assert_eq!(
            s.platform_cut(),
            d("193.00"),
            "300 earned − 107 billed and never collected"
        );
        // The guard and the Revenue Department are owed IN FULL regardless — the whole shortfall
        // lands on the platform's own share, which is what makes the deduction the honest split.
        assert_eq!(s.guard_transfer, d("1746.00"));
        assert_eq!(s.vat, d("147.00"), "VAT on the SETTLED 2100");
        assert_eq!(s.wht, d("54.00"));
        assert!(
            s.reconciles(),
            "what actually came in == everywhere it went"
        );
        // The BILLED form of the same identity, which is how the ledger reads.
        assert_eq!(
            s.refunded + s.vat + s.guard_transfer + s.wht + s.billed_cut(),
            s.customer_paid + s.uncollected
        );

        // …and the extreme: only half the settled bill was ever collected, so the cut goes NEGATIVE
        // and the sweep takes ฿870 LESS out of the account. Clamping that to zero would leave the
        // account short by exactly that much while reporting a clean ฿0 — see the module doc.
        let mut half = worked_job("500", 4, 1, "0", "10", 4 * 3600, "3");
        half.amount = d("1070.00");
        let s = split(&half).expect("splits");
        assert_eq!(s.customer_paid, d("1070.00"));
        assert_eq!(s.uncollected, d("1070.00"));
        assert_eq!(
            s.billed_cut(),
            d("200.00"),
            "the commission was still earned"
        );
        assert_eq!(s.platform_cut(), d("-870.00"));
        assert!(s.reconciles());
    }

    /// THE ROUNDING CASE, and why `rounding_adjustment` may be negative. 1.995 worked hours: the
    /// customer's bill prorates on the UNROUNDED ratio (997.50) while the guard is paid off
    /// `actual_hours` rounded to 2.00 (1000.00 gross). The platform is ฿2.50 out of pocket, and
    /// saying so is the only honest answer — clamping to zero would invent ฿2.50 of income.
    #[test]
    fn an_unlucky_proration_rounding_leaves_the_platform_marginally_out_of_pocket() {
        let p = worked_job("500", 2, 1, "0", "0", 7182, "0"); // 7182s = 1.995 h
        assert_eq!(
            p.actual_hours,
            Some(d("2.00")),
            "rounded to the NUMERIC(6,2)"
        );
        assert_eq!(
            p.subtotal,
            Some(d("997.50")),
            "billed on the unrounded ratio"
        );
        let s = split(&p).expect("splits");
        assert_eq!(s.guard_income, d("1000.00"), "paid on the ROUNDED hours");
        assert_eq!(s.rounding_adjustment, d("-2.50"));
        assert_eq!(
            s.platform_cut(),
            d("-2.50"),
            "a real, tiny loss on this job"
        );
        assert!(s.reconciles(), "and the money still adds up exactly");
    }

    // ----- the exclusion ladder: a gap is never a zero -----

    #[test]
    fn every_kind_of_missing_data_excludes_the_job_instead_of_counting_it_as_zero() {
        let base = worked_job("500", 4, 1, "0", "10", 4 * 3600, "3");

        // Not settled yet — the reconcile has not run, so the cut is not knowable.
        let mut p = base.clone();
        p.final_amount = None;
        assert_eq!(split(&p), Err(SnapshotGap::NotSettled));

        // Pre-VAT-split row (migration 0005): our money cannot be told from the Revenue Department's.
        for (subtotal, vat) in [(None, Some(d("140.00"))), (Some(d("2000.00")), None)] {
            let mut p = base.clone();
            p.subtotal = subtotal;
            p.vat_amount = vat;
            assert_eq!(split(&p), Err(SnapshotGap::NoVatSplit));
        }

        // Pre-snapshot row (migration 0013): EACH of the five columns alone is enough to exclude.
        // Written as five separate mutations on purpose — an `unwrap_or(ZERO)` slipped into any one
        // of them would under-report the cut, and only this loop would notice.
        let clear: [fn(&mut SettledPayment); 5] = [
            |p| p.base_fee = None,
            |p| p.booked_hours = None,
            |p| p.guard_count = None,
            |p| p.tip = None,
            |p| p.commission_amount = None,
        ];
        for clear_one in clear {
            let mut p = base.clone();
            clear_one(&mut p);
            assert_eq!(split(&p), Err(SnapshotGap::NoPricingSnapshot));
        }

        // …but a CANCELLED job needs none of that snapshot, which is what keeps a historical
        // cancellation reportable.
        assert!(split(&cancelled_job("2140.00", "500.00", "0")).is_ok());

        // Columns that disagree with each other are a human question, never a swept number.
        let mut broken = base.clone();
        broken.subtotal = Some(d("99999.00"));
        assert_eq!(split(&broken), Err(SnapshotGap::DoesNotReconcile));
        assert!(!SnapshotGap::NoPricingSnapshot.reason_th().is_empty());
        assert_eq!(SnapshotGap::NotSettled.code(), "NOT_SETTLED");
    }

    // ----- the INVARIANT, over many generated combinations -----

    /// PROPERTY TEST — the point of the whole module. Over ~8000 generated jobs spanning every
    /// pricing dimension (fee, booked hours, guard count, tip, commission rate, worked seconds
    /// including partial and over-run, WHT rate) AND both reconcile directions (a job that refunds
    /// and a job whose settled bill was billed OVER the pre-payment — the `Extra` arm), the split
    /// must reconstruct what the customer ACTUALLY TRANSFERRED, exactly, to the satang.
    ///
    /// A deterministic sweep of the space rather than a random one: a money invariant that only
    /// holds on the seeds CI happened to draw is not an invariant, and a failure has to be
    /// reproducible from the test name alone.
    #[test]
    fn the_invariant_holds_across_the_whole_pricing_space() {
        let fees = ["1.00", "137.50", "500", "999.99"];
        let hours = [1, 3, 8];
        let guards = [1, 2, 20];
        let tips = ["0", "0.01", "137.37"];
        let commissions = ["0", "3.33", "15", "100"];
        let whts = ["0", "3", "5"];
        // Worked seconds per booked hour: none, an odd fraction that forces the 2 dp rounding, an
        // exact match, and an over-run (clamped to booked — overtime never adds to the bill).
        let worked = [0i64, 1793, 3600, 4200];
        // What the customer had ALREADY PAID when the job settled: the same tip (the ordinary path)
        // and NO tip (the tip was added afterwards → the reconcile's `Extra` arm bills more than was
        // collected). B1 lives in the second column, so the space has to contain it.
        let prepaid = ["same", "0"];

        let mut checked = 0usize;
        let mut saw_negative_drift = false;
        let mut saw_refund = false;
        let mut saw_uncollected = false;
        let mut saw_negative_cut = false;
        for fee in fees {
            for &h in &hours {
                for &g in &guards {
                    for tip in tips {
                        for pct in commissions {
                            for wht in whts {
                                for &per_hour in &worked {
                                    for pre in prepaid {
                                        let prepaid_tip = if pre == "same" { tip } else { pre };
                                        let secs = per_hour * h as i64;
                                        let p = worked_job_billed_over(
                                            fee,
                                            h,
                                            g,
                                            prepaid_tip,
                                            tip,
                                            pct,
                                            secs,
                                            wht,
                                        );
                                        let ctx = format!(
                                            "fee={fee} h={h} g={g} tip={tip} prepaid={prepaid_tip} \
                                             pct={pct} wht={wht} secs={secs}"
                                        );
                                        let s = split(&p).unwrap_or_else(|e| {
                                            panic!("{ctx} did not split: {e:?}")
                                        });
                                        // THE INVARIANT — what actually arrived, split exactly.
                                        assert!(
                                            s.reconciles(),
                                            "{ctx}: {} != {}",
                                            s.reconstructed(),
                                            s.customer_paid
                                        );
                                        // …and the BILLED form of the same equation, which is how
                                        // the ledger and the preview's component totals read.
                                        assert_eq!(
                                            s.refunded
                                                + s.vat
                                                + s.guard_transfer
                                                + s.wht
                                                + s.billed_cut(),
                                            s.customer_paid + s.uncollected,
                                            "{ctx}: the billed identity"
                                        );
                                        // The cut is the four named components plus the drift, LESS
                                        // what was billed and never collected — and it never
                                        // contains VAT or WHT, whatever the inputs.
                                        assert_eq!(
                                            s.platform_cut(),
                                            s.commission
                                                + s.cancellation_fee
                                                + s.tip
                                                + s.unpaid_guard_share
                                                + s.rounding_adjustment
                                                - s.uncollected,
                                            "{ctx}"
                                        );
                                        // Billing and collecting cannot BOTH be short: a settled
                                        // bill under the pre-payment refunds, one over it is
                                        // uncollected, never both at once.
                                        assert!(
                                            s.refunded == Decimal::ZERO
                                                || s.uncollected == Decimal::ZERO,
                                            "{ctx}: refund {} and uncollected {} together",
                                            s.refunded,
                                            s.uncollected
                                        );
                                        // The unpaid share is (N−1) whole guard shares, always.
                                        assert_eq!(
                                            s.unpaid_guard_share,
                                            (s.guard_income + s.commission) * Decimal::from(g - 1),
                                            "{ctx}: the unpaid share is (N−1) × the paid gross"
                                        );
                                        // The drift is what its name says: satang, not money.
                                        assert!(
                                            s.rounding_adjustment.abs()
                                                <= d("0.01") * Decimal::from(g)
                                                    + Decimal::from_str_exact(fee)
                                                        .unwrap_or_default()
                                                        * d("0.005")
                                                        * Decimal::from(g),
                                            "{ctx}: drift {} is too large to be rounding",
                                            s.rounding_adjustment
                                        );
                                        saw_negative_drift |= s.rounding_adjustment < Decimal::ZERO;
                                        saw_refund |= s.refunded > Decimal::ZERO;
                                        saw_uncollected |= s.uncollected > Decimal::ZERO;
                                        saw_negative_cut |= s.platform_cut() < Decimal::ZERO;
                                        checked += 1;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        assert!(checked > 6000, "swept {checked} combinations");
        // The space actually EXERCISED the interesting cases, rather than quietly covering only the
        // happy path — a property test that never sees a refund, a negative drift or an UNCOLLECTED
        // extra charge proves less than it looks like it does.
        assert!(saw_refund, "the sweep included prorated (refunding) jobs");
        assert!(
            saw_negative_drift,
            "the sweep included a rounding that leaves the platform out of pocket"
        );
        assert!(
            saw_uncollected,
            "the sweep included an `Extra`-arm job billed above what was collected — B1"
        );
        assert!(
            saw_negative_cut,
            "…including one where the uncollected extra exceeds the cut, so the job nets DOWN the \
             sweep instead of being clamped to a ฿0 that would leave the account short"
        );
    }

    /// The same invariant over the CANCELLATION space — a different shape entirely (no guard, no
    /// snapshot), so it gets its own sweep rather than riding the one above.
    #[test]
    fn the_invariant_holds_for_every_cancellation_shape() {
        let charged = ["0", "0.01", "107.00", "2140.00", "99999.99"];
        let fees = ["0", "0.01", "500.00", "2140.00", "999999.00"];
        let overpays = ["0", "0.01", "350.00"];
        for c in charged {
            for f in fees {
                for o in overpays {
                    let p = cancelled_job(c, f, o);
                    let s =
                        split(&p).unwrap_or_else(|e| panic!("charged={c} fee={f} over={o}: {e:?}"));
                    assert!(s.reconciles(), "charged={c} fee={f} over={o}");
                    // A cancellation keeps the fee and NOTHING else — no commission, no tip, no
                    // guard share, and never more than what was actually paid ("take what is there,
                    // never leave a debt").
                    assert_eq!(s.platform_cut(), s.cancellation_fee);
                    assert!(s.cancellation_fee <= s.customer_paid);
                    assert_eq!(s.guard_transfer, Decimal::ZERO);
                    assert_eq!(s.wht, Decimal::ZERO);
                }
            }
        }
    }
}

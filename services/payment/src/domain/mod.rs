//! PURE domain logic — no DB, no HTTP, no NATS. 100% unit-testable.
//!
//! v2 is PRE-PAY then SETTLE, and (since 2026-08-10) every customer-facing figure is
//! VAT-INCLUSIVE — catalog prices are VAT-exclusive and 7% is added on top:
//! - [`pricing::VAT_RATE`] — the ONE VAT constant; nothing else hard-codes 7%.
//! - [`pricing::expected_total`] — the PRE-PAY estimate as a GRAND TOTAL
//!   (`base_fee × hours × guard_count + tip`, + VAT), computed entirely from the booking's
//!   server-owned inputs (never a client body). The single funnel for the pre-pay charge, the
//!   slip's minimum-amount check and the PromptPay QR amount.
//! - [`pricing::price_breakdown`] — that estimate split into `subtotal` / `vat` / `grand_total`,
//!   persisted on the payment row for the Thai tax invoice.
//! - [`pricing::is_payable_status`] — which booking statuses admit a fresh pre-pay (post-accept,
//!   pre-complete).
//! - [`pricing::reconcile`] — on completion, diff the actual-hours bill
//!   ([`pricing::settled_breakdown`]) against the pre-paid amount → refund the overpay or record
//!   the shortfall (the base is never double-charged). VAT is recomputed FROM the prorated
//!   subtotal, never prorated on its own.
//! - [`pricing::cancellation_fee_charged`] — `min(fee, amount_paid)` when the CUSTOMER cancels.
//! - [`pricing::ChargeTerms`] — the commission / cancellation-fee snapshot payment carries from
//!   the booking onto the payment row.
//! - [`proration`] — `compute_proration` (ported verbatim from v1), reused by the settle subtotal.
//! - [`settlement`] — where ONE job's money actually WENT: the customer's payment split into the
//!   guard's income, the VAT, the WHT, the refund and **ยอดที่โดนหักเข้าระบบ** (the platform's own
//!   cut, stream ②). Carries the invariant that the parts reconstruct the whole, to the satang, and
//!   owns `guard_gross`/`commission_on` — the two helpers [`payout`] deducts with and the sweep
//!   sweeps with, so the guard's pay and the platform's cut can never disagree.
//! - [`csv`] — the server-side CSV writer (RFC 4180 quoting + a UTF-8 BOM + formula neutralisation)
//!   behind the two tax reports an accountant opens in a spreadsheet.

pub mod batch_status;
pub mod csv;
pub mod deduction;
pub mod payout;
pub mod pricing;
pub mod promptpay;
pub mod proration;
pub mod refund_export;
pub mod scb_export;
pub mod settlement;
pub mod slip;
pub mod thai_id;

pub use pricing::{
    cancellation_fee_charged, expected_total, is_negative_terminal, is_payable_status, reconcile,
    ChargeTerms, PriceBreakdown, PricingInputs, Reconciliation,
};

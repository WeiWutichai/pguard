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

pub mod pricing;
pub mod promptpay;
pub mod proration;
pub mod slip;

pub use pricing::{
    cancellation_fee_charged, expected_total, is_negative_terminal, is_payable_status,
    price_breakdown, reconcile, ChargeTerms, PriceBreakdown, Reconciliation,
};

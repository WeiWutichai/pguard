//! API layer — thin Axum transport handlers. PRE-PAY: the customer-facing `POST /payments`
//! (createPayment) charges the server-computed ESTIMATE once a guard has accepted; that payment
//! gates the booking's en_route. This layer also serves the READ surface — a customer's own
//! payment + ledger, the admin cross-user ledger + revenue report, and the service-JWT'd PDPA
//! data export. THE MONEY PATH.
//!
//! Handlers are generic over [`PaymentDeps`] so the `AuthUser` guard + role/authz gates are
//! unit-testable with a lightweight state, mirroring rating's seam.

use axum::extract::{Multipart, Path, Query, State};
use axum::Json;
use chrono::{TimeDelta, Utc};
use rust_decimal::prelude::ToPrimitive;
use rust_decimal::Decimal;
use uuid::Uuid;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;
use shared::service_jwt::ServiceCaller;

use crate::booking_client::BookingReader;
use crate::config::PaymentProvider;
use crate::domain;
use crate::domain::promptpay as promptpay_domain;
use crate::domain::slip as slip_domain;
use crate::models::{
    AdminListPaymentsQuery, CreatePaymentRequest, CustomerSpend, PaymentResponse,
    PromptPayResponse, RefundQueueQuery, RefundQueueResponse, ReportRangeQuery, RevenueReport,
};
use crate::repo;
use crate::repo::{PrePayOutcome, SlipPayOutcome};
use crate::slip2go_client::{
    SlipConditions, SlipVerifier, SLIP_AMOUNT_TOO_LOW_CODE, SLIP_WRONG_RECEIVER_CODE,
};
use crate::state::PaymentDeps;

pub mod payouts;
use crate::state::PaymentInternalDeps;

/// The recorded `payment_method` for a PRE-PAY charge. v2's gateway is simulated and there is no
/// real card-on-file step yet, so a successful pre-pay is tagged `prepaid`; a real gateway
/// integration would replace this with the captured method (PromptPay/card/…).
const PREPAID_METHOD: &str = "prepaid";

/// The money terms for a charge, assembled from the AUTHORITATIVE booking read: the VAT-inclusive
/// estimate split for the tax invoice, plus the booking's commission / cancellation-fee SNAPSHOT.
///
/// Both snapshot fields are absent on a booking created before those columns existed (or served by
/// a booking deploy that predates them) — `None` means "no such term", i.e. zero, and
/// [`domain::ChargeTerms::new`] additionally clamps whatever arrives into range. Copying them onto
/// the payment row is what lets the guard-earnings ledger show the deducted commission, and lets
/// the cancellation consumer (a NATS handler with no HTTP) price a cancellation without a
/// cross-service read.
fn charge_terms(booking: &crate::models::InternalBooking) -> domain::ChargeTerms {
    domain::ChargeTerms::new(
        domain::price_breakdown(
            booking.base_fee,
            booking.hours,
            booking.guard_count,
            booking.tip,
        ),
        booking.commission_percent.unwrap_or(Decimal::ZERO),
        booking.cancellation_fee.unwrap_or(Decimal::ZERO),
    )
}

/// The typed 409 both pay paths return when the booking has gone terminal under them and the
/// stranded charge is being refunded — the app localizes on the code and shows the Thai message.
fn booking_cancelled_refunding() -> AppError {
    AppError::ConflictCode {
        code: "BOOKING_CANCELLED",
        message: "การจองถูกยกเลิกแล้ว ระบบกำลังคืนเงินให้เต็มจำนวน".to_string(),
    }
}

/// Pay-vs-cancel RACE compensation. If `status` is negative-terminal (a guard withdrew or the
/// customer cancelled), issue the idempotent full-refund compensator for a stranded pre-pay and
/// return `true` (the caller surfaces [`booking_cancelled_refunding`]); return `false` otherwise.
///
/// Safe + idempotent on EVERY call: `repo::refund_race_lost_prepay` NoOps unless a live `completed`
/// charge exists for the booking (status='completed' guard). Called on every exit that can strand a
/// charge on a since-terminal booking: the fresh `Created` commit, an idempotent `AlreadyPaid`, AND
/// a retry that now finds the booking non-payable — the last one recovers the double-fault where a
/// `Created` charge's own compensating re-read failed (booking briefly down), which no cancellation
/// event will ever refund (it was consumed as a NoOp before the payment row existed).
async fn compensate_if_terminal<S: PaymentDeps>(
    state: &S,
    booking_id: Uuid,
    status: &str,
) -> Result<bool, AppError> {
    if !domain::is_negative_terminal(status) {
        return Ok(false);
    }
    repo::refund_race_lost_prepay(state.db(), booking_id, Uuid::new_v4()).await?;
    Ok(true)
}

/// POST /payments — PRE-PAY a booking's estimate (createPayment). THE MONEY PATH (write).
///
/// v2 is PRE-PAY: after a guard ACCEPTS, the customer pays the estimate up front, which GATES the
/// booking's en_route (booking learns it is paid by consuming `payment.completed`). Discipline
/// (CLAUDE.md — never trust the client; money is server-computed):
///  1. role=customer.
///  2. VERIFY against the authoritative booking (service-JWT'd internal read): the caller must be
///     the booking's customer AND the booking must be in a payable state (post-accept,
///     pre-complete).
///  3. The amount is the SERVER-computed estimate `base_fee × hours × guard_count + tip` from the
///     booking's own pricing, **plus 7% VAT** — exact `Decimal`, NEVER an f64, NEVER the client
///     body. The VAT split and the booking's commission/cancellation-fee snapshot are persisted
///     alongside the charge (tax invoice + the cancellation refund's fee basis).
///  4. Idempotent per booking (DB UNIQUE partial index): a repeat is a no-op returning the
///     existing payment (no second charge, no second `payment.completed`).
#[tracing::instrument(skip(state, req), fields(user = %user.user_id))]
pub async fn create_payment<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Json(req): Json<CreatePaymentRequest>,
) -> Result<Json<ApiResponse<PaymentResponse>>, AppError> {
    if user.role != "customer" {
        return Err(AppError::Forbidden(
            "Only customers can pay for a booking".to_string(),
        ));
    }

    // Feature flag: the SIMULATED auto-mark is only available under PAYMENT_PROVIDER=simulated.
    // Under slip2go the customer MUST settle via a verified slip (`POST /payments/{id}/slip`); the
    // simulated path would mint money out of thin air, so reject it (typed 409).
    if state.slip_config().provider == PaymentProvider::Slip2Go {
        return Err(AppError::ConflictCode {
            code: "SLIP_REQUIRED",
            message: "Pay by uploading a verified transfer slip".to_string(),
        });
    }

    // (1) authoritative verification — the charge trusts the booking, not the body.
    let booking = state.booking_reader().get_booking(req.booking_id).await?;

    if booking.customer_id != user.user_id {
        // Generic 403 — never reveal whether the booking exists / belongs to someone else.
        return Err(AppError::Forbidden(
            "You can only pay for your own booking".to_string(),
        ));
    }
    if !domain::is_payable_status(&booking.status) {
        // Pay-vs-cancel double-fault recovery: if the booking has gone negative-terminal but still
        // carries a stranded live charge (an earlier Created's compensating re-read failed), refund
        // it now so the customer's natural retry recovers the money instead of only 409ing.
        if compensate_if_terminal(&state, req.booking_id, &booking.status).await? {
            return Err(booking_cancelled_refunding());
        }
        // Typed so the app localizes (a raw English 409 was showing under the Thai pay screen).
        return Err(AppError::ConflictCode {
            code: "BOOKING_NOT_PAYABLE",
            message: "This booking is not awaiting payment".to_string(),
        });
    }

    // (2) SERVER-computed terms from the booking's own pricing (never the client body): the
    //     VAT-INCLUSIVE grand total to charge, its split, and the commission/cancellation snapshot.
    let terms = charge_terms(&booking);
    let estimate = terms.breakdown.grand_total;

    // (3) idempotent pre-pay + payment.completed outbox event, in ONE tx. A repeat is a no-op.
    let outcome = repo::prepay_idempotent(
        state.db(),
        req.booking_id,
        user.user_id,
        booking.guard_id,
        &terms,
        PREPAID_METHOD,
        Uuid::new_v4(),
    )
    .await?;

    let payment = match outcome {
        PrePayOutcome::Created(p) => {
            // Pay-vs-cancel race guard: this fresh charge just committed. If the booking has since
            // gone terminal (guard withdrew / customer cancelled on another device), the cancellation
            // event may have been consumed BEFORE this row existed, so nothing would ever refund it
            // (silent money limbo — deep-review HIGH). Re-read and compensate with an immediate full
            // refund, then tell the customer their money is being returned (typed → app localizes).
            let latest = state.booking_reader().get_booking(req.booking_id).await?;
            if compensate_if_terminal(&state, req.booking_id, &latest.status).await? {
                return Err(booking_cancelled_refunding());
            }
            tracing::info!(payment_id = %p.id, amount = %estimate, "pre-pay charged (estimate)");
            p
        }
        PrePayOutcome::AlreadyPaid(p) => {
            // Idempotent: the booking was already pre-paid. Re-check the terminal race here too — an
            // earlier Created's compensating re-read may have failed (booking briefly down), and a
            // retry lands on this arm; the compensator is idempotent (status='completed' guard).
            let latest = state.booking_reader().get_booking(req.booking_id).await?;
            if compensate_if_terminal(&state, req.booking_id, &latest.status).await? {
                return Err(booking_cancelled_refunding());
            }
            tracing::info!(payment_id = %p.id, "pre-pay no-op (already paid)");
            p
        }
    };

    Ok(Json(ApiResponse::success(payment)))
}

/// Max slip-upload body the route accepts (10 MiB image + a margin for multipart framing). The
/// gateway carves a matching `BodyCap::Large` for `/payments/{id}/slip`.
pub const MAX_SLIP_BODY_BYTES: usize = 12 * 1024 * 1024;

/// POST /payments/{id}/slip — the REAL money path: pay a booking with a Slip2Go-verified transfer
/// slip. `{id}` is the BOOKING id. OWN-ONLY (the booking's customer). Multipart body: `file` (the
/// slip image). THE MONEY PATH (write).
///
/// Discipline (CLAUDE.md — never trust the client; money is server-computed):
///  1. role=customer; feature flag = slip2go (else 409 — the slip path is off / simulated).
///  2. Verify against the authoritative booking (service-JWT'd internal read): the caller must be
///     the booking's customer AND the booking must be in a payable state.
///  3. The amount to cover is the SERVER-computed estimate (`base_fee × hours × guards + tip`,
///     VAT INCLUDED), exact `Decimal` — NEVER from the client.
///  4. Send the slip to Slip2Go with conditions `{ checkReceiver:[OUR account], checkAmount:gte
///     estimate, checkDuplicate }`. On `code==200000`, RE-VALIDATE on our side (defence in depth):
///     amount ≥ estimate, receiver == RECEIVING_ACCOUNT.
///  5. Atomic our-side dedupe + paid-stamp + `payment.completed` (the UNIQUE trans_ref/reference_id
///     means a slip can NEVER pay two bookings). Idempotent: re-submitting the SAME accepted slip
///     returns paid (no double-charge). A non-200000 / failed re-validation → a TYPED error.
///  6. Store the slip image privately in S3 (PDPA — like guard documents).
#[tracing::instrument(skip(state, multipart), fields(user = %user.user_id, booking_id = %id))]
pub async fn pay_with_slip<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    multipart: Multipart,
) -> Result<Json<ApiResponse<PaymentResponse>>, AppError> {
    if user.role != "customer" {
        return Err(AppError::Forbidden(
            "Only customers can pay for a booking".to_string(),
        ));
    }
    // Feature flag: the slip path is only live under PAYMENT_PROVIDER=slip2go. Under the simulated
    // default it is off (clients use `POST /payments`); reject to avoid an inconsistent half-config.
    if state.slip_config().provider != PaymentProvider::Slip2Go {
        return Err(AppError::ConflictCode {
            code: "SLIP_DISABLED",
            message: "Slip payment is not enabled".to_string(),
        });
    }

    // (1) authoritative verification — the charge trusts the booking, not the body. OWN-ONLY.
    let booking = state.booking_reader().get_booking(id).await?;
    if booking.customer_id != user.user_id {
        // Generic 403 — never reveal whether the booking exists / belongs to someone else.
        return Err(AppError::Forbidden(
            "You can only pay for your own booking".to_string(),
        ));
    }
    if !domain::is_payable_status(&booking.status) {
        // Pay-vs-cancel double-fault recovery (see create_payment): a stranded live charge on a
        // now-terminal booking is refunded here, so a retry after the slip path's own compensating
        // re-read failed recovers the money instead of only 409ing BOOKING_NOT_PAYABLE.
        if compensate_if_terminal(&state, id, &booking.status).await? {
            return Err(booking_cancelled_refunding());
        }
        // Typed so the app localizes (a raw English 409 was showing under the Thai slip screen).
        return Err(AppError::ConflictCode {
            code: "BOOKING_NOT_PAYABLE",
            message: "This booking is not awaiting payment".to_string(),
        });
    }

    // (2) SERVER-computed terms (never the client). The slip must cover at least the grand total —
    //     the SAME VAT-inclusive figure the PromptPay QR quotes, so a customer who scans the QR and
    //     pays exactly that always clears this check.
    let terms = charge_terms(&booking);
    let estimate = terms.breakdown.grand_total;

    // (3) read the slip image (magic-byte validated — size before bytes; declared must match).
    let (declared_mime, bytes) = parse_slip_form(multipart).await?;
    let canonical_mime = slip_domain::validate_slip_upload(&declared_mime, bytes.len(), &bytes)?;

    // (4) verify with Slip2Go: our receiving account + a `gte` estimate + checkDuplicate. The
    //     amount is a plain string (no comma/0-pad), per the API.
    // Our RECEIVING_ACCOUNT is a PromptPay PROXY, so tell Slip2Go the account TYPE — without it
    // Slip2Go treats the bare number as a bank account and returns 200401 "Recipient Account Not
    // Match" against the slip's PromptPay receiver (even for a correct payment via our QR). A mobile
    // proxy is Slip2Go type "02001" (PromptPay MSISDN, per the docs). National-id PromptPay has no
    // documented type code yet → None (omit; add it when a national-id receiver is configured).
    let receiver_account_type =
        match promptpay_domain::classify_proxy(&state.slip_config().receiving_account) {
            Some(promptpay_domain::PromptPayProxy::Mobile) => Some("02001".to_string()),
            _ => None,
        };
    let conditions = SlipConditions {
        receiver_account: state.slip_config().receiving_account.clone(),
        receiver_account_type,
        min_amount: estimate.to_string(),
    };
    let verified = state
        .slip_verifier()
        .verify(bytes.clone(), canonical_mime, &conditions)
        .await?;

    // (5) RE-VALIDATE on our side — never trust the external check alone (defence in depth).
    //     amount ≥ estimate (overpay accepted; underpay rejected).
    if verified.amount < estimate {
        return Err(AppError::ConflictCode {
            code: SLIP_AMOUNT_TOO_LOW_CODE,
            message: format!(
                "Slip amount {} is less than the required {estimate}",
                verified.amount
            ),
        });
    }
    //     receiver == OUR account. A slip carries MORE than one receiver identifier — the bank
    //     account AND the PromptPay proxy (phone/national-id). A payment via OUR PromptPay QR
    //     matches on the PROXY (== RECEIVING_ACCOUNT) while the underlying bank account is a
    //     different number, so accept the slip if ANY identifier matches; reject a slip paid to a
    //     wholly different account, or one with no receiver at all.
    let receiving = &state.slip_config().receiving_account;
    let receiver_ok = verified
        .receiver_accounts
        .iter()
        .any(|r| accounts_match(r, receiving));
    if !receiver_ok {
        return Err(AppError::ConflictCode {
            code: SLIP_WRONG_RECEIVER_CODE,
            message: "This slip was not paid to our account".to_string(),
        });
    }

    // (6) store the slip image privately (PDPA), THEN settle. The S3 key is server-generated.
    let ext = slip_domain::mime_to_extension(canonical_mime);
    let slip_key = format!("payment/{id}/slips/{}.{ext}", Uuid::new_v4());
    state.s3().upload(&slip_key, bytes, canonical_mime).await?;

    // (7) atomic: dedupe (UNIQUE trans_ref/reference_id) + paid-stamp + payment.completed outbox.
    let outcome = repo::pay_with_slip(
        state.db(),
        id,
        user.user_id,
        booking.guard_id,
        &terms,
        &verified.reference_id,
        &verified.trans_ref,
        verified.amount,
        &slip_key,
        Uuid::new_v4(),
    )
    .await;

    let outcome = match outcome {
        Ok(o) => o,
        Err(e) => {
            // The settle failed (e.g. the slip already paid ANOTHER booking → SLIP_DUPLICATE).
            // The just-uploaded object is now orphaned — best-effort delete (mirrors profile's
            // upload→DB-write compensation).
            state.s3().delete_best_effort(&slip_key).await;
            return Err(e);
        }
    };

    let payment = match outcome {
        SlipPayOutcome::Created(p) => {
            // Pay-vs-cancel race guard (the slip path's window is seconds — Slip2Go verify + S3 —
            // so the booking can go terminal between the payable-check and this commit). Re-read; if
            // the booking is now declined/cancelled, compensate with an immediate full refund and
            // tell the customer their money is coming back, instead of leaving a live charge on a
            // dead booking that no cancellation event will ever refund (deep-review HIGH).
            let latest = state.booking_reader().get_booking(id).await?;
            if compensate_if_terminal(&state, id, &latest.status).await? {
                return Err(booking_cancelled_refunding());
            }
            tracing::info!(payment_id = %p.id, amount = %estimate, trans_ref = %verified.trans_ref, "slip verified → paid");
            p
        }
        SlipPayOutcome::AlreadyPaid(p) => {
            // Idempotent: the booking was already paid and the SAME accepted slip was re-submitted.
            // The new object is unused — clean it up. Re-check the terminal race too (a retry may
            // land here after a Created compensation re-read failed; the compensator is idempotent).
            state.s3().delete_best_effort(&slip_key).await;
            let latest = state.booking_reader().get_booking(id).await?;
            if compensate_if_terminal(&state, id, &latest.status).await? {
                return Err(booking_cancelled_refunding());
            }
            tracing::info!(payment_id = %p.id, "slip pay no-op (already paid)");
            p
        }
        SlipPayOutcome::ExtraTransferRecorded(_p) => {
            // A SECOND, DIFFERENT verified transfer for an already-paid booking (a customer
            // double-pay). It was recorded as an unapplied, refundable slip — do NOT delete the S3
            // image (it is the evidence for that refund). Surface a typed conflict so the double
            // transfer is visible + refundable, instead of a silent 200 that loses the money.
            tracing::warn!(booking_id = %id, trans_ref = %verified.trans_ref, amount = %verified.amount, "extra transfer recorded for an already-paid booking (refundable)");
            return Err(AppError::ConflictCode {
                code: "ALREADY_PAID_EXTRA_TRANSFER",
                message: "การจองนี้ชำระเงินแล้ว ระบบบันทึกยอดที่โอนเพิ่มไว้เพื่อคืนเงินให้".to_string(),
            });
        }
    };

    Ok(Json(ApiResponse::success(payment)))
}

/// Compare two account identifiers for the receiver check, tolerant of slip formatting: Thai bank
/// slips often mask the middle (`xxx-x-x1234-x`) or insert separators. We keep ONLY the digits of
/// each (dropping `x`/`X` mask chars, dashes, spaces), then require either an exact match OR a
/// suffix match (one's digit-tail equals the other's) — a masked slip only ever exposes a SUFFIX,
/// so a digit-suffix match is the strongest assertion available. Pure.
fn accounts_match(slip_account: &str, our_account: &str) -> bool {
    let norm = |s: &str| -> String { s.chars().filter(|c| c.is_ascii_digit()).collect::<String>() };
    let a = norm(slip_account);
    let b = norm(our_account);
    if a.is_empty() || b.is_empty() {
        return false;
    }
    a == b || a.ends_with(&b) || b.ends_with(&a)
}

/// Parse the slip multipart: a single `file` part (bytes + declared content-type). The bytes are
/// bounded by the route's `DefaultBodyLimit`. Mirrors profile's `parse_avatar_form`.
async fn parse_slip_form(mut multipart: Multipart) -> Result<(String, Vec<u8>), AppError> {
    let mut declared_mime: Option<String> = None;
    let mut file: Option<Vec<u8>> = None;
    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| AppError::BadRequest(format!("Failed to read multipart: {e}")))?
    {
        if field.name().unwrap_or("") == "file" {
            declared_mime = field.content_type().map(|s| s.to_string());
            file = Some(
                field
                    .bytes()
                    .await
                    .map_err(|e| AppError::BadRequest(format!("Failed to read file: {e}")))?
                    .to_vec(),
            );
        }
    }
    let file = file.ok_or_else(|| AppError::BadRequest("file is required".to_string()))?;
    let declared_mime = declared_mime.unwrap_or_else(|| "application/octet-stream".to_string());
    Ok((declared_mime, file))
}

/// GET /payments/{id}/promptpay — the PromptPay transfer instructions for a booking. `{id}` is the
/// BOOKING id. OWN-ONLY (the booking's customer). Returns the server-side estimate (the amount to
/// transfer), our receiving account (formatted for display), and the authoritative EMVCo PromptPay
/// `qr_payload` the mobile renders as a QR. THE MONEY PATH (read — tells the customer where to pay).
///
/// Discipline (CLAUDE.md — never trust the client; money is server-computed):
///  1. role=customer; feature flag = slip2go (else 409 SLIP_DISABLED — the PromptPay/slip path is
///     off; under the simulated default there is nowhere to transfer, the client uses POST /payments).
///  2. Verify against the authoritative booking (service-JWT'd internal read): the caller must be
///     the booking's customer AND the booking must be in a payable state.
///  3. The amount is the SAME server-computed estimate the slip + prepay handlers use
///     (`domain::expected_total` — `base_fee × hours × guards + tip`, VAT INCLUDED), exact
///     `Decimal`. One funnel: the QR, the charge and the slip's minimum can never quote different
///     figures.
///  4. The `qr_payload` is built SERVER-SIDE (`domain::promptpay`) from `RECEIVING_ACCOUNT` + that
///     estimate — the ONE authoritative place; the client never composes a payload. If
///     `RECEIVING_ACCOUNT` is not a PromptPay-addressable proxy (a phone or national/tax id), this
///     is a server config error (a bank account cannot be a PromptPay QR).
///
/// No DB write, no Slip2Go call — purely informational (the customer pays in their bank app, then
/// settles via `POST /payments/{id}/slip`).
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn get_promptpay<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<PromptPayResponse>>, AppError> {
    if user.role != "customer" {
        return Err(AppError::Forbidden(
            "Only customers can pay for a booking".to_string(),
        ));
    }
    // Feature flag: PromptPay/slip is only live under PAYMENT_PROVIDER=slip2go. Under the simulated
    // default there is nowhere to transfer (the client uses POST /payments) → a clear typed 409.
    if state.slip_config().provider != PaymentProvider::Slip2Go {
        return Err(AppError::ConflictCode {
            code: "SLIP_DISABLED",
            message: "Slip payment is not enabled".to_string(),
        });
    }

    // (1) authoritative verification — trust the booking, not the body. OWN-ONLY.
    let booking = state.booking_reader().get_booking(id).await?;
    if booking.customer_id != user.user_id {
        // Generic 403 — never reveal whether the booking exists / belongs to someone else.
        return Err(AppError::Forbidden(
            "You can only pay for your own booking".to_string(),
        ));
    }
    if !domain::is_payable_status(&booking.status) {
        return Err(AppError::Conflict(
            "This booking is not awaiting payment".to_string(),
        ));
    }

    // (2) SERVER-computed estimate — the SAME one the slip + prepay handlers charge.
    let estimate = domain::expected_total(
        booking.base_fee,
        booking.hours,
        booking.guard_count,
        booking.tip,
    );

    // (3) authoritative EMVCo PromptPay payload built server-side from OUR account + the estimate.
    let receiving_account = &state.slip_config().receiving_account;
    let qr_payload = promptpay_domain::build_promptpay_payload(receiving_account, estimate)?;

    // Amount in satang (×100), exact (never an f64): the estimate is 2-dp money, so ×100 is whole.
    let amount_satang = (estimate.round_dp(2) * Decimal::from(100))
        .to_i64()
        .ok_or_else(|| AppError::Internal("amount out of range".to_string()))?;

    Ok(Json(ApiResponse::success(PromptPayResponse {
        amount: estimate,
        amount_satang,
        receiving_account: promptpay_domain::format_account_for_display(receiving_account),
        qr_payload,
    })))
}

/// GET /payments/{id} — fetch one payment the caller owns (or admin).
#[tracing::instrument(skip(state), fields(user = %user.user_id, payment_id = %id))]
pub async fn get_payment<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<PaymentResponse>>, AppError> {
    let payment = repo::get_payment(state.db(), id).await?;
    if payment.customer_id != user.user_id && user.role != "admin" {
        // Generic 403 (no resource enumeration).
        return Err(AppError::Forbidden("Not your payment".to_string()));
    }
    Ok(Json(ApiResponse::success(payment)))
}

/// GET /payments — list the caller's payments (as the paying customer).
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn list_payments<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<PaymentResponse>>>, AppError> {
    // List read → replica (C5.3); single get_payment stays on the primary (money read).
    let items = repo::list_payments(state.db_read(), user.user_id).await?;
    Ok(Json(ApiResponse::success(items)))
}

/// GET /payments/earnings — the assigned guard's earning basis: their completed jobs with the
/// clamped `actual_hours` worked and the `commission_percent` deducted from that job. GUARD-ONLY
/// (own jobs, keyed on the JWT `sub`). The guard app pairs each `booking_id` with the `base_fee`
/// from its booking feed and pays `base_fee × actual_hours` (booked hours as a fallback when
/// `actual_hours` is NULL) LESS the commission — so a job that finished early (and was
/// overpay-refunded to the customer) pays the guard for the hours ACTUALLY worked, no longer the
/// full booked estimate that overstated it, and the deduction is visible instead of unexplained.
/// The commission comes out of the guard's pay only; it never changed what the customer paid. VAT
/// is not part of this figure — the guard is paid on the VAT-exclusive service price.
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn guard_earnings<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<crate::models::GuardEarningRow>>>, AppError> {
    if user.role != "guard" {
        return Err(AppError::Forbidden(
            "Only guards have an earnings ledger".to_string(),
        ));
    }
    let items = repo::guard_earnings(state.db_read(), user.user_id).await?;
    Ok(Json(ApiResponse::success(items)))
}

/// Valid `?status=` filter values for the admin ledger (the payment.payment_status enum).
const PAYMENT_STATUSES: &[&str] = &["pending", "completed", "refunded"];

/// GET /admin/payments — admin cross-user payment ledger (READ-ONLY). Admin only (the edge
/// proves identity, not role). Optional `status` filter + limit/offset; replica read. This is
/// a reporting surface prepared ahead of a real payment integration — there is intentionally
/// NO manual refund-process endpoint here (v2 refunds are event-driven; see PROGRESS notes).
#[tracing::instrument(skip(state, q), fields(user = %user.user_id))]
pub async fn admin_list_payments<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<AdminListPaymentsQuery>,
) -> Result<Json<ApiResponse<Vec<PaymentResponse>>>, AppError> {
    if user.role != "admin" {
        return Err(AppError::Forbidden(
            "This action requires the admin role".to_string(),
        ));
    }
    let status = match q.status.as_deref() {
        None => None,
        Some(s) if PAYMENT_STATUSES.contains(&s) => Some(s),
        Some(_) => return Err(AppError::BadRequest("invalid status filter".to_string())),
    };
    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let offset = q.offset.unwrap_or(0).max(0);
    let items =
        repo::admin_list_payments(state.db_read(), status, q.customer_id, limit, offset).await?;
    Ok(Json(ApiResponse::success(items)))
}

/// Valid `?status=` filter values for the refund queue (the `refund_status` workflow states).
const REFUND_STATUSES: &[&str] = &["pending", "processed"];

/// GET /admin/refunds/queue — admin refund queue: payments awaiting refund action / in progress
/// (`refund_status` set), newest first. Admin only (the edge proves identity, not role). Optional
/// `status` filter (`pending` = awaiting action, `processed` = done; omitted → both) + limit/offset;
/// replica read. Returns the page of refunds PLUS the total `count` matching the same filter (the
/// dashboard "แจ้งเตือน / คิวคืนเงิน" badge — independent of the page window). v2 refunds are
/// event-driven (a settle sets `refund_status='pending'`); this is the READ surface that surfaces
/// them — there is intentionally no manual refund-process action here yet.
#[tracing::instrument(skip(state, q), fields(user = %user.user_id))]
pub async fn admin_refund_queue<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<RefundQueueQuery>,
) -> Result<Json<ApiResponse<RefundQueueResponse>>, AppError> {
    if user.role != "admin" {
        return Err(AppError::Forbidden(
            "This action requires the admin role".to_string(),
        ));
    }
    let status = match q.status.as_deref() {
        None => None,
        Some(s) if REFUND_STATUSES.contains(&s) => Some(s),
        Some(_) => return Err(AppError::BadRequest("invalid status filter".to_string())),
    };
    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let offset = q.offset.unwrap_or(0).max(0);
    let refunds = repo::admin_list_refund_queue(state.db_read(), status, limit, offset).await?;
    let count = repo::admin_count_refund_queue(state.db_read(), status).await?;
    Ok(Json(ApiResponse::success(RefundQueueResponse {
        refunds,
        count,
    })))
}

/// Default analytics window when `from`/`to` are omitted, and the hard cap on its length.
const REPORT_DEFAULT_DAYS: i64 = 30;
const REPORT_MAX_DAYS: i64 = 366;

/// Resolve the `[from, to)` window: default last 30 days ending now; `from` clamped so the
/// window never exceeds a year (bounds the aggregation scan). Shared shape with booking's report.
fn report_range(q: &ReportRangeQuery) -> (chrono::DateTime<Utc>, chrono::DateTime<Utc>) {
    let to = q.to.unwrap_or_else(Utc::now);
    let from = q
        .from
        .unwrap_or_else(|| to - TimeDelta::days(REPORT_DEFAULT_DAYS));
    let earliest = to - TimeDelta::days(REPORT_MAX_DAYS);
    (from.max(earliest).min(to), to)
}

/// GET /admin/reports/revenue?from=&to= — daily net-revenue series + MoM vs the prior window.
/// Admin only. Read from the replica (pure analytics, no read-after-write).
#[tracing::instrument(skip(state, q), fields(user = %user.user_id))]
pub async fn admin_revenue_report<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<ReportRangeQuery>,
) -> Result<Json<ApiResponse<RevenueReport>>, AppError> {
    if user.role != "admin" {
        return Err(AppError::Forbidden(
            "This action requires the admin role".to_string(),
        ));
    }
    let (from, to) = report_range(&q);
    let series = repo::revenue_series(state.db_read(), from, to).await?;
    let total: Decimal = series.iter().map(|p| p.revenue).sum();
    // MoM: the immediately-preceding equal-length window.
    let len = to - from;
    let prev_total = repo::revenue_total(state.db_read(), from - len, from).await?;
    let mom_pct = if prev_total == Decimal::ZERO {
        None
    } else {
        ((total - prev_total) / prev_total * Decimal::from(100)).to_f64()
    };
    Ok(Json(ApiResponse::success(RevenueReport {
        series,
        total,
        prev_total,
        mom_pct,
    })))
}

/// GET /admin/reports/customer-spend — per-customer lifetime spend (summed completed-payment
/// effective amount), for the web-admin customers page. Admin only. Read from the replica (pure
/// analytics, no read-after-write). Each customer's `total` is exact-decimal → JSON string.
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn admin_customer_spend_report<S: PaymentDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<CustomerSpend>>>, AppError> {
    if user.role != "admin" {
        return Err(AppError::Forbidden(
            "This action requires the admin role".to_string(),
        ));
    }
    let rows = repo::customer_spend(state.db_read()).await?;
    Ok(Json(ApiResponse::success(rows)))
}

// ----- GET /internal/users/{user_id}/export (PDPA §19/§32 data export) -----

/// Export a user's OWN payments for a cross-service data export. `ServiceCaller`-gated (only
/// identity's aggregator reaches this) and scoped strictly to the path `user_id`.
#[tracing::instrument(skip(state), fields(caller = %caller.service, user = %user_id))]
pub async fn internal_export_user<S: PaymentInternalDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
    Path(user_id): Path<Uuid>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    let payments = repo::export_user_payments(state.db_read(), user_id).await?;
    Ok(Json(ApiResponse::success(payments)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::booking_client::BookingReader;
    use crate::models::InternalBooking;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::{get, post};
    use axum::Router;
    use jsonwebtoken::{DecodingKey, EncodingKey};
    use shared::auth::{encode_jwt_with_key, HasJwtSecret};
    use sqlx::postgres::PgPoolOptions;
    use std::sync::Arc;
    use std::time::Duration;
    use tower::ServiceExt;

    const SECRET: &str = "user-secret-at-least-64-characters-long-for-the-hs256-payment-test!!!";

    use crate::config::{PaymentProvider, SlipPaymentConfig};
    use crate::s3::S3Client;
    use crate::slip2go_client::{SlipConditions, SlipVerifier, VerifiedSlip};

    /// Stub booking reader — canned booking (or NotFound), no HTTP. Lets the createPayment
    /// role/authz gates be tested hermetically (mirrors rating's `StubReader`).
    #[derive(Clone)]
    struct StubReader {
        booking: Option<InternalBooking>,
    }
    impl BookingReader for StubReader {
        async fn get_booking(&self, _booking_id: Uuid) -> Result<InternalBooking, AppError> {
            self.booking
                .clone()
                .ok_or_else(|| AppError::NotFound("Booking not found".to_string()))
        }
    }

    /// Stub profile reader — canned guard PII + org block, no real profile HTTP (the payout
    /// aggregation is tested hermetically). Default = no guard / empty org.
    #[derive(Clone, Default)]
    struct StubProfileReader {
        guard: Option<crate::profile_client::GuardPayoutProfile>,
        /// Per-guard PII, keyed by guard id — a payout batch pays MANY different people, each with
        /// their own name/tax id. Falls back to `guard` for the single-guard cases.
        guards: std::collections::HashMap<Uuid, crate::profile_client::GuardPayoutProfile>,
        org: Option<crate::profile_client::OrgTaxInfo>,
    }
    impl crate::profile_client::ProfileReader for StubProfileReader {
        async fn get_guard_payout_profile(
            &self,
            guard_id: Uuid,
        ) -> Result<crate::profile_client::GuardPayoutProfile, AppError> {
            self.guards
                .get(&guard_id)
                .cloned()
                .or_else(|| self.guard.clone())
                .ok_or_else(|| AppError::NotFound("Guard not found".to_string()))
        }
        async fn get_org_settings(&self) -> Result<crate::profile_client::OrgTaxInfo, AppError> {
            Ok(self
                .org
                .clone()
                .unwrap_or(crate::profile_client::OrgTaxInfo {
                    company_name: None,
                    tax_id: None,
                    address: None,
                }))
        }
    }

    /// Stub slip verifier — returns a canned [`VerifiedSlip`] or a canned typed rejection, with NO
    /// real API call (the verify endpoint's success/fail + our-side re-validation are tested
    /// hermetically). `AppError` isn't `Clone`, so the rejection is held as a Cloneable
    /// `(code, message)` and reconstructed per call.
    #[derive(Clone)]
    enum StubVerifier {
        Ok(VerifiedSlip),
        Rejected { code: &'static str, message: String },
    }
    impl SlipVerifier for StubVerifier {
        async fn verify(
            &self,
            _image: Vec<u8>,
            _content_type: &str,
            _conditions: &SlipConditions,
        ) -> Result<VerifiedSlip, AppError> {
            match self {
                StubVerifier::Ok(v) => Ok(v.clone()),
                StubVerifier::Rejected { code, message } => Err(AppError::ConflictCode {
                    code,
                    message: message.clone(),
                }),
            }
        }
    }
    impl StubVerifier {
        fn ok(v: VerifiedSlip) -> Self {
            StubVerifier::Ok(v)
        }
        fn rejected(code: &'static str, msg: &str) -> Self {
            StubVerifier::Rejected {
                code,
                message: msg.to_string(),
            }
        }
    }

    /// A throwaway S3 client (never reached in the hermetic reject-path tests — they fail before
    /// the S3 upload). Built from dummy values; an actual call would error harmlessly.
    fn stub_s3() -> S3Client {
        S3Client::new(
            reqwest::Client::new(),
            "http://127.0.0.1:1".to_string(),
            None,
            "pguard".to_string(),
            "us-east-1".to_string(),
            "k".to_string(),
            "s".to_string(),
        )
    }

    #[derive(Clone)]
    struct TestDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
        redis: redis::aio::ConnectionManager,
        reader: StubReader,
        verifier: StubVerifier,
        profile: StubProfileReader,
        s3: S3Client,
        slip_config: SlipPaymentConfig,
    }

    impl HasJwtSecret for TestDeps {
        fn jwt_secret(&self) -> &str {
            SECRET
        }
        fn decoding_key(&self) -> &DecodingKey {
            &self.dec
        }
        fn redis_conn(&self) -> &redis::aio::ConnectionManager {
            &self.redis
        }
    }
    impl PaymentDeps for TestDeps {
        type Reader = StubReader;
        type Verifier = StubVerifier;
        type Profile = StubProfileReader;
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn booking_reader(&self) -> &StubReader {
            &self.reader
        }
        fn profile_reader(&self) -> &StubProfileReader {
            &self.profile
        }
        fn slip_verifier(&self) -> &StubVerifier {
            &self.verifier
        }
        fn s3(&self) -> &S3Client {
            &self.s3
        }
        fn slip_config(&self) -> &SlipPaymentConfig {
            &self.slip_config
        }
    }

    /// Build the payment router over a lightweight test state. The `AuthUser` extractor requires
    /// a real `redis::aio::ConnectionManager` (the jti blocklist), which can't be constructed
    /// without connecting. So these router tests are hermetic by default and only run when a test
    /// Redis is provided via `TEST_REDIS_URL` (falling back to `REDIS_CACHE_URL`); `None` → the
    /// caller SKIPs. The role/authz reject paths fail at the gate before any DB read, so the
    /// (invalid) lazy pool is never touched.
    async fn router(booking: Option<InternalBooking>) -> Option<Router> {
        // Default deps: simulated provider (so `POST /payments` is allowed), an always-ok verifier
        // (unused by the non-slip routes).
        build_router(
            booking,
            StubVerifier::ok(sample_verified("0140315796")),
            sim_config(),
        )
        .await
    }

    /// The slip-path config under PAYMENT_PROVIDER=slip2go, receiver = `1234567890`.
    fn slip2go_config() -> SlipPaymentConfig {
        SlipPaymentConfig {
            provider: PaymentProvider::Slip2Go,
            receiving_account: "1234567890".to_string(),
        }
    }
    /// The default simulated config (the slip path is off).
    fn sim_config() -> SlipPaymentConfig {
        SlipPaymentConfig {
            provider: PaymentProvider::Simulated,
            receiving_account: String::new(),
        }
    }

    /// A canned verified slip paying our `1234567890` account the FULL VAT-inclusive estimate for
    /// [`payable_booking`] (2000.00 subtotal + 140.00 VAT = 2140.00) — enough to clear the
    /// minimum-amount re-validation.
    fn sample_verified(trans_ref: &str) -> VerifiedSlip {
        VerifiedSlip {
            reference_id: Uuid::new_v4().to_string(),
            trans_ref: trans_ref.to_string(),
            amount: "2140.00".parse().unwrap(),
            receiver_accounts: vec!["1234567890".to_string()],
        }
    }

    async fn build_router(
        booking: Option<InternalBooking>,
        verifier: StubVerifier,
        slip_config: SlipPaymentConfig,
    ) -> Option<Router> {
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .ok()?;
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool");
        let deps = TestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            db,
            redis,
            reader: StubReader { booking },
            verifier,
            profile: StubProfileReader::default(),
            s3: stub_s3(),
            slip_config,
        };
        Some(
            Router::new()
                .route("/payments", post(create_payment::<TestDeps>))
                .route("/payments/{id}/promptpay", get(get_promptpay::<TestDeps>))
                .route("/payments/{id}/slip", post(pay_with_slip::<TestDeps>))
                .route("/admin/payments", get(admin_list_payments::<TestDeps>))
                .route("/admin/refunds/queue", get(admin_refund_queue::<TestDeps>))
                .route(
                    "/admin/reports/revenue",
                    get(admin_revenue_report::<TestDeps>),
                )
                .route(
                    "/admin/reports/customer-spend",
                    get(admin_customer_spend_report::<TestDeps>),
                )
                .route(
                    "/admin/payouts/preview",
                    get(crate::api::payouts::preview::<TestDeps>),
                )
                .route(
                    "/admin/payouts/export",
                    post(crate::api::payouts::export::<TestDeps>),
                )
                .with_state(deps),
        )
    }

    /// Build a multipart `file` body with a tiny valid JPEG (magic bytes) for the slip route.
    fn slip_multipart_body() -> (String, Body) {
        let boundary = "BOUNDARYpguardslip";
        let jpeg: &[u8] = &[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
        let mut body = Vec::new();
        body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
        body.extend_from_slice(
            b"Content-Disposition: form-data; name=\"file\"; filename=\"slip.jpg\"\r\n",
        );
        body.extend_from_slice(b"Content-Type: image/jpeg\r\n\r\n");
        body.extend_from_slice(jpeg);
        body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
        (
            format!("multipart/form-data; boundary={boundary}"),
            Body::from(body),
        )
    }

    fn customer_token(user_id: Uuid, role: &str) -> String {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, _jti) = encode_jwt_with_key(user_id, role, 0, &ek, 15).unwrap();
        tok
    }

    /// A payable booking (guard accepted) owned by `customer_id`, priced 500×4×1 + 0 = 2000.00
    /// subtotal → 2140.00 charged with 7% VAT. Carries a 10% commission + a 300 cancellation fee
    /// snapshot (neither changes what the customer pays).
    fn payable_booking(customer_id: Uuid) -> InternalBooking {
        InternalBooking {
            customer_id,
            guard_id: Some(Uuid::new_v4()),
            status: "accepted".to_string(),
            hours: 4,
            base_fee: "500".parse().unwrap(),
            guard_count: 1,
            tip: rust_decimal::Decimal::ZERO,
            commission_percent: Some("10.00".parse().unwrap()),
            cancellation_fee: Some("300.00".parse().unwrap()),
        }
    }

    fn create_payment_req(booking_id: Uuid) -> Body {
        Body::from(serde_json::json!({ "booking_id": booking_id }).to_string())
    }

    async fn post_payment(app: Router, tok: Option<&str>, body: Body) -> StatusCode {
        let mut b = Request::builder()
            .method("POST")
            .uri("/payments")
            .header("content-type", "application/json");
        if let Some(t) = tok {
            b = b.header("authorization", format!("Bearer {t}"));
        }
        app.oneshot(b.body(body).unwrap()).await.unwrap().status()
    }

    // ----- POST /payments (createPayment — PRE-PAY): role + authz gates -----

    #[tokio::test]
    async fn create_payment_rejects_missing_token() {
        let Some(app) = router(Some(payable_booking(Uuid::new_v4()))).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // No bearer → 401 (the service validates, not just the gateway edge).
        assert_eq!(
            post_payment(app, None, create_payment_req(Uuid::new_v4())).await,
            StatusCode::UNAUTHORIZED
        );
    }

    #[tokio::test]
    async fn create_payment_rejects_non_customer() {
        // A guard must not pay for a booking (role gate, before any booking read).
        let Some(app) = router(Some(payable_booking(Uuid::new_v4()))).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = customer_token(Uuid::new_v4(), "guard");
        assert_eq!(
            post_payment(app, Some(&tok), create_payment_req(Uuid::new_v4())).await,
            StatusCode::FORBIDDEN
        );
    }

    #[tokio::test]
    async fn create_payment_rejects_paying_someone_elses_booking() {
        // Caller is a customer, but the authoritative booking belongs to a DIFFERENT customer →
        // 403, decided against the booking read (never the body), before any DB write.
        let Some(app) = router(Some(payable_booking(Uuid::new_v4()))).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = customer_token(Uuid::new_v4(), "customer");
        assert_eq!(
            post_payment(app, Some(&tok), create_payment_req(Uuid::new_v4())).await,
            StatusCode::FORBIDDEN
        );
    }

    #[tokio::test]
    async fn create_payment_rejects_non_payable_status() {
        // Owner matches, but the booking is not in a payable state (no guard yet) → 409, before
        // any DB write. Proves the estimate path is GATED on an accepted booking.
        let me = Uuid::new_v4();
        let mut booking = payable_booking(me);
        booking.status = "requested".to_string();
        booking.guard_id = None;
        let Some(app) = router(Some(booking)).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = customer_token(me, "customer");
        assert_eq!(
            post_payment(app, Some(&tok), create_payment_req(Uuid::new_v4())).await,
            StatusCode::CONFLICT
        );
    }

    #[tokio::test]
    async fn create_payment_estimate_ignores_client_amount() {
        // The request body has NO amount field — the estimate is computed SERVER-SIDE from the
        // booking (proved by the pure `domain::expected_total` tests). Here we assert a body that
        // tries to smuggle an `amount` is simply ignored (still parses to the same request).
        let me = Uuid::new_v4();
        let Some(app) = router(Some(payable_booking(me))).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let tok = customer_token(me, "customer");
        // Owner matches + booking payable → the handler proceeds past authz to the DB write. The
        // lazy pool is invalid, so the write errors (500), NOT a 4xx — i.e. the client `amount`
        // was never validated/honored; the flow reached the server-priced charge. (The actual
        // charge + estimate value are covered by the repo DB test + the domain unit tests.)
        let body = Body::from(
            serde_json::json!({ "booking_id": Uuid::new_v4(), "amount": "1.00" }).to_string(),
        );
        let status = post_payment(app, Some(&tok), body).await;
        assert_eq!(
            status,
            StatusCode::INTERNAL_SERVER_ERROR,
            "authz passed and the client amount was ignored; the flow reached the server-priced DB write"
        );
    }

    // ----- POST /payments/{id}/slip (REAL money path): authz + verify + re-validation -----

    /// POST the slip route with a CUSTOM verifier result + provider config, returning (status,
    /// the `error.code` if any). Hermetic — the StubVerifier makes NO real API call.
    async fn run_slip(
        booking: Option<InternalBooking>,
        verifier: StubVerifier,
        cfg: SlipPaymentConfig,
        tok: Option<&str>,
        booking_id: Uuid,
    ) -> Option<(StatusCode, String)> {
        let app = build_router(booking, verifier, cfg).await?;
        let (content_type, body) = slip_multipart_body();
        let mut b = Request::builder()
            .method("POST")
            .uri(format!("/payments/{booking_id}/slip"))
            .header("content-type", content_type);
        if let Some(t) = tok {
            b = b.header("authorization", format!("Bearer {t}"));
        }
        let res = app.oneshot(b.body(body).unwrap()).await.unwrap();
        let status = res.status();
        let bytes = axum::body::to_bytes(res.into_body(), 64 * 1024)
            .await
            .unwrap();
        let code = serde_json::from_slice::<serde_json::Value>(&bytes)
            .ok()
            .and_then(|v| v["error"]["code"].as_str().map(|s| s.to_string()))
            .unwrap_or_default();
        Some((status, code))
    }

    #[tokio::test]
    async fn slip_rejects_missing_token() {
        let Some((status, _)) = run_slip(
            Some(payable_booking(Uuid::new_v4())),
            StubVerifier::ok(sample_verified("tr1")),
            slip2go_config(),
            None,
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(status, StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn slip_rejects_non_customer() {
        let Some((status, _)) = run_slip(
            Some(payable_booking(Uuid::new_v4())),
            StubVerifier::ok(sample_verified("tr1")),
            slip2go_config(),
            Some(&customer_token(Uuid::new_v4(), "guard")),
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(status, StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn slip_own_only_rejects_other_customers_booking() {
        // Caller is a customer, but the authoritative booking belongs to a DIFFERENT customer →
        // 403, decided against the booking read, BEFORE any verify / S3 / DB write.
        let booking = payable_booking(Uuid::new_v4()); // owned by someone else
        let Some((status, _)) = run_slip(
            Some(booking),
            StubVerifier::ok(sample_verified("tr1")),
            slip2go_config(),
            Some(&customer_token(Uuid::new_v4(), "customer")),
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(
            status,
            StatusCode::FORBIDDEN,
            "a customer cannot pay someone else's booking with a slip"
        );
    }

    #[tokio::test]
    async fn slip_disabled_under_simulated_provider() {
        // Under the simulated default the slip path is OFF → typed 409 SLIP_DISABLED (before the
        // booking read / verify).
        let me = Uuid::new_v4();
        let Some((status, code)) = run_slip(
            Some(payable_booking(me)),
            StubVerifier::ok(sample_verified("tr1")),
            sim_config(),
            Some(&customer_token(me, "customer")),
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(status, StatusCode::CONFLICT);
        assert_eq!(code, "SLIP_DISABLED");
    }

    #[tokio::test]
    async fn slip_non_200000_is_typed_rejection_not_paid() {
        // Slip2Go rejected the slip (non-200000) → the StubVerifier returns the typed
        // SLIP_VERIFY_FAILED; the handler surfaces it (409), the booking is NOT paid (no DB write
        // reached — the lazy pool is never touched).
        let me = Uuid::new_v4();
        let Some((status, code)) = run_slip(
            Some(payable_booking(me)),
            StubVerifier::rejected(
                crate::slip2go_client::SLIP_VERIFY_FAILED_CODE,
                "Slip not found",
            ),
            slip2go_config(),
            Some(&customer_token(me, "customer")),
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(status, StatusCode::CONFLICT);
        assert_eq!(code, "SLIP_VERIFY_FAILED");
    }

    #[tokio::test]
    async fn slip_underpay_is_rejected_by_our_revalidation() {
        // Slip2Go said 200000 but the verified amount is BELOW the server estimate → our-side
        // re-validation rejects with SLIP_AMOUNT_TOO_LOW, before any S3/DB write. The booking
        // prices to 500×4×1 = 2000.00 + 7% VAT = 2140.00, so a slip for the OLD (VAT-free) 2000.00
        // is now an underpay — the VAT must be collected, not silently absorbed.
        let me = Uuid::new_v4();
        let mut v = sample_verified("tr-underpay");
        v.amount = "2000.00".parse().unwrap();
        let Some((status, code)) = run_slip(
            Some(payable_booking(me)),
            StubVerifier::ok(v),
            slip2go_config(),
            Some(&customer_token(me, "customer")),
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(status, StatusCode::CONFLICT);
        assert_eq!(code, SLIP_AMOUNT_TOO_LOW_CODE);
    }

    #[tokio::test]
    async fn slip_wrong_receiver_is_rejected() {
        // 200000 + sufficient amount, but the slip was paid to a DIFFERENT account → our-side
        // receiver check rejects with SLIP_WRONG_RECEIVER (before any S3/DB write).
        let me = Uuid::new_v4();
        let mut v = sample_verified("tr-wrong");
        v.receiver_accounts = vec!["9999999999".to_string()];
        let Some((status, code)) = run_slip(
            Some(payable_booking(me)),
            StubVerifier::ok(v),
            slip2go_config(),
            Some(&customer_token(me, "customer")),
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(status, StatusCode::CONFLICT);
        assert_eq!(code, SLIP_WRONG_RECEIVER_CODE);
    }

    #[tokio::test]
    async fn slip_missing_receiver_is_rejected() {
        // A 200000 with NO receiver on the slip → treated as a receiver mismatch (we can't prove
        // the money came to us) → SLIP_WRONG_RECEIVER.
        let me = Uuid::new_v4();
        let mut v = sample_verified("tr-noreceiver");
        v.receiver_accounts = Vec::new();
        let Some((status, code)) = run_slip(
            Some(payable_booking(me)),
            StubVerifier::ok(v),
            slip2go_config(),
            Some(&customer_token(me, "customer")),
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(status, StatusCode::CONFLICT);
        assert_eq!(code, SLIP_WRONG_RECEIVER_CODE);
    }

    #[tokio::test]
    async fn slip_promptpay_proxy_match_passes_receiver_gate() {
        // THE PromptPay case (RECEIVING_ACCOUNT is a phone/proxy): the slip carries a bank account
        // that does NOT equal our account PLUS the proxy that DOES. The bank-only match would have
        // rejected this legitimate payment as SLIP_WRONG_RECEIVER; matching ANY identifier lets it
        // through. Proven by reaching the settle (500 from the dead S3/DB), NOT a 409 wrong-receiver.
        let me = Uuid::new_v4();
        let mut v = sample_verified("tr-proxy");
        // slip2go_config()'s receiving_account is `1234567890`; the bank account differs, the proxy
        // matches — the fixed receiver gate accepts on the proxy.
        v.receiver_accounts = vec!["9999999999".to_string(), "1234567890".to_string()];
        let Some((status, code)) = run_slip(
            Some(payable_booking(me)),
            StubVerifier::ok(v),
            slip2go_config(),
            Some(&customer_token(me, "customer")),
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_ne!(
            code, SLIP_WRONG_RECEIVER_CODE,
            "a proxy match must NOT be rejected as wrong-receiver"
        );
        assert_eq!(
            status,
            StatusCode::INTERNAL_SERVER_ERROR,
            "receiver gate passed on the proxy → flow reached the S3/DB settle"
        );
    }

    #[tokio::test]
    async fn slip_rejects_non_payable_booking() {
        // Owner matches, slip would verify, but the booking is not payable (no guard yet) → 409
        // CONFLICT before verify/S3/DB.
        let me = Uuid::new_v4();
        let mut booking = payable_booking(me);
        booking.status = "requested".to_string();
        booking.guard_id = None;
        let Some((status, _)) = run_slip(
            Some(booking),
            StubVerifier::ok(sample_verified("tr1")),
            slip2go_config(),
            Some(&customer_token(me, "customer")),
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(status, StatusCode::CONFLICT);
    }

    #[tokio::test]
    async fn slip_accepted_reaches_settle_write() {
        // The happy path past all gates + verify + re-validation + S3 + the settle write. With the
        // lazy/invalid DB pool the settle errors at the DB (500) — proving the flow REACHED the
        // server-priced settle (the S3 stub points at a dead host but the upload precedes the DB
        // write; either way a non-4xx proves authz/verify/re-validation all PASSED). The real
        // paid+event + dedupe + idempotency are covered by the DATABASE_URL-gated repo tests.
        let me = Uuid::new_v4();
        let Some((status, _)) = run_slip(
            Some(payable_booking(me)),
            StubVerifier::ok(sample_verified("tr-ok")),
            slip2go_config(),
            Some(&customer_token(me, "customer")),
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(
            status,
            StatusCode::INTERNAL_SERVER_ERROR,
            "all gates + verify + re-validation passed; the flow reached the S3/DB settle"
        );
    }

    // ----- GET /payments/{id}/promptpay (where-to-pay read): authz + feature flag + payload -----

    /// The slip2go config with a PromptPay-addressable receiving account (a mobile number) so the
    /// QR payload can be built. The plain slip tests keep using `1234567890` (receiver-match only).
    fn promptpay_config() -> SlipPaymentConfig {
        SlipPaymentConfig {
            provider: PaymentProvider::Slip2Go,
            receiving_account: "0812345678".to_string(),
        }
    }

    /// GET the promptpay route over a custom booking + provider config, returning (status, the JSON
    /// body). Hermetic — no booking HTTP (StubReader), no DB/S3/Slip2Go reached on the success path.
    async fn run_promptpay(
        booking: Option<InternalBooking>,
        cfg: SlipPaymentConfig,
        tok: Option<&str>,
        booking_id: Uuid,
    ) -> Option<(StatusCode, serde_json::Value)> {
        let app = build_router(booking, StubVerifier::ok(sample_verified("tr1")), cfg).await?;
        let mut b = Request::builder()
            .method("GET")
            .uri(format!("/payments/{booking_id}/promptpay"));
        if let Some(t) = tok {
            b = b.header("authorization", format!("Bearer {t}"));
        }
        let res = app.oneshot(b.body(Body::empty()).unwrap()).await.unwrap();
        let status = res.status();
        let bytes = axum::body::to_bytes(res.into_body(), 64 * 1024)
            .await
            .unwrap();
        let json = serde_json::from_slice::<serde_json::Value>(&bytes).unwrap_or_default();
        Some((status, json))
    }

    #[tokio::test]
    async fn promptpay_rejects_missing_token() {
        let Some((status, _)) = run_promptpay(
            Some(payable_booking(Uuid::new_v4())),
            promptpay_config(),
            None,
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(status, StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn promptpay_rejects_non_customer() {
        let Some((status, _)) = run_promptpay(
            Some(payable_booking(Uuid::new_v4())),
            promptpay_config(),
            Some(&customer_token(Uuid::new_v4(), "guard")),
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(status, StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn promptpay_own_only_rejects_other_customers_booking() {
        // Caller is a customer, but the authoritative booking belongs to a DIFFERENT customer → 403.
        let Some((status, _)) = run_promptpay(
            Some(payable_booking(Uuid::new_v4())), // owned by someone else
            promptpay_config(),
            Some(&customer_token(Uuid::new_v4(), "customer")),
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(status, StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn promptpay_disabled_under_simulated_provider() {
        // Under the simulated default there is nowhere to transfer → typed 409 SLIP_DISABLED.
        let me = Uuid::new_v4();
        let Some((status, json)) = run_promptpay(
            Some(payable_booking(me)),
            sim_config(),
            Some(&customer_token(me, "customer")),
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(status, StatusCode::CONFLICT);
        assert_eq!(json["error"]["code"], "SLIP_DISABLED");
    }

    #[tokio::test]
    async fn promptpay_rejects_non_payable_booking() {
        // Owner matches, but the booking has no guard yet (not payable) → 409, before pricing.
        let me = Uuid::new_v4();
        let mut booking = payable_booking(me);
        booking.status = "requested".to_string();
        booking.guard_id = None;
        let Some((status, _)) = run_promptpay(
            Some(booking),
            promptpay_config(),
            Some(&customer_token(me, "customer")),
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(status, StatusCode::CONFLICT);
    }

    #[tokio::test]
    async fn promptpay_returns_server_estimate_account_and_valid_qr() {
        // Happy path: the booking prices 500×4×1 + 0 = 2000.00 subtotal, +7% VAT = 2140.00 to
        // transfer. The response carries that exact GRAND TOTAL (string), 214000 satang, the
        // display-formatted account, and a QR payload that contains the PromptPay AID + the
        // 2140.00 amount field — proving the QR is built SERVER-SIDE from the same one estimate
        // the charge uses, VAT included (no DB/S3/Slip2Go touched).
        let me = Uuid::new_v4();
        let Some((status, json)) = run_promptpay(
            Some(payable_booking(me)),
            promptpay_config(),
            Some(&customer_token(me, "customer")),
            Uuid::new_v4(),
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(status, StatusCode::OK);
        let data = &json["data"];
        assert_eq!(
            data["amount"], "2140.00",
            "exact VAT-inclusive estimate as a money string (raw Decimal serde-str, like the prepay path — the QR's tag-54 carries the 2-dp form)"
        );
        assert_eq!(data["amount_satang"], 214000, "estimate in satang");
        assert_eq!(
            data["receiving_account"], "081-234-5678",
            "account formatted for display"
        );
        let qr = data["qr_payload"].as_str().expect("qr_payload string");
        assert!(
            qr.contains(crate::domain::promptpay::PROMPTPAY_AID),
            "QR carries the PromptPay AID"
        );
        assert!(qr.contains("54072140.00"), "QR amount field = the estimate");
    }

    #[test]
    fn accounts_match_handles_exact_suffix_and_masked() {
        assert!(accounts_match("1234567890", "1234567890"), "exact");
        assert!(accounts_match("xxx-x-x7890", "1234567890"), "masked suffix");
        assert!(
            accounts_match("1234567890", "x7890"),
            "our value is a suffix"
        );
        assert!(!accounts_match("9999999999", "1234567890"), "different");
        assert!(!accounts_match("", "1234567890"), "empty slip account");
        assert!(!accounts_match("1234567890", ""), "empty our account");
    }

    #[tokio::test]
    async fn admin_list_payments_rejects_non_admin() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A customer must not read the cross-user payment ledger (every customer's money).
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/payments")
                    .header(
                        "authorization",
                        format!("Bearer {}", customer_token(Uuid::new_v4(), "customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn admin_refund_queue_rejects_non_admin() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A customer must not read the cross-user refund queue (every customer's owed refunds).
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/refunds/queue")
                    .header(
                        "authorization",
                        format!("Bearer {}", customer_token(Uuid::new_v4(), "customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn admin_revenue_report_rejects_non_admin() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A customer must not read cross-user revenue analytics.
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/reports/revenue")
                    .header(
                        "authorization",
                        format!("Bearer {}", customer_token(Uuid::new_v4(), "customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn admin_customer_spend_report_rejects_non_admin() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A customer must not read cross-user per-customer spend analytics.
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/reports/customer-spend")
                    .header(
                        "authorization",
                        format!("Bearer {}", customer_token(Uuid::new_v4(), "customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    // ----- guard payout: WHO gets paid in one SCB file -----

    /// POST /admin/payouts/export with an optional JSON body (None = no body at all).
    async fn post_payout_export(app: Router, token: &str, body: Option<&str>) -> StatusCode {
        let req = Request::builder()
            .method("POST")
            .uri("/admin/payouts/export")
            .header("authorization", format!("Bearer {token}"));
        let req = match body {
            Some(json) => req
                .header("content-type", "application/json")
                .body(Body::from(json.to_string()))
                .unwrap(),
            None => req.body(Body::empty()).unwrap(),
        };
        app.oneshot(req).await.unwrap().status()
    }

    #[tokio::test]
    async fn payout_endpoints_reject_non_admin() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A customer must not see who the platform pays — nor trigger a money file.
        let res = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/payouts/preview")
                    .header(
                        "authorization",
                        format!("Bearer {}", customer_token(Uuid::new_v4(), "customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);

        let guard_tok = customer_token(Uuid::new_v4(), "guard");
        assert_eq!(
            post_payout_export(app, &guard_tok, None).await,
            StatusCode::FORBIDDEN,
            "a guard cannot pay themselves"
        );
    }

    #[tokio::test]
    async fn payout_export_rejects_an_empty_or_oversized_guard_selection() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let admin = customer_token(Uuid::new_v4(), "admin");
        // Ticking NOBODY must not silently fall back to paying the whole backlog → 400, decided
        // before any DB read (the test pool is intentionally unusable).
        assert_eq!(
            post_payout_export(app.clone(), &admin, Some(r#"{"guard_ids":[]}"#)).await,
            StatusCode::BAD_REQUEST
        );
        let too_many: Vec<String> = (0..crate::domain::payout::MAX_SELECTED_GUARDS + 1)
            .map(|_| format!("\"{}\"", Uuid::new_v4()))
            .collect();
        assert_eq!(
            post_payout_export(
                app,
                &admin,
                Some(&format!("{{\"guard_ids\":[{}]}}", too_many.join(","))),
            )
            .await,
            StatusCode::BAD_REQUEST,
            "an absurdly long selection is refused"
        );
    }

    #[tokio::test]
    async fn payout_export_rejects_an_inverted_window() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let admin = customer_token(Uuid::new_v4(), "admin");
        assert_eq!(
            post_payout_export(
                app.clone(),
                &admin,
                Some(r#"{"from":"2026-09-30","to":"2026-09-01"}"#),
            )
            .await,
            StatusCode::BAD_REQUEST
        );
        // Same gate on the read-only preview (query params).
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/payouts/preview?from=2026-09-30&to=2026-09-01")
                    .header("authorization", format!("Bearer {admin}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::BAD_REQUEST);
    }

    /// END-TO-END, real Postgres: ONE export file pays MANY guards. Three guards have unpaid
    /// reconciled jobs; the admin ticks two of them; the generated SCB text must carry one TXNDET
    /// (+ WHTCER) PER TICKED GUARD inside a single batch whose BCHDET/TRAILR totals sum every
    /// transfer — and only the ticked guards' bookings may be marked paid. DATABASE_URL + test
    /// Redis gated.
    #[tokio::test]
    async fn payout_export_pays_many_guards_in_one_file() {
        let (Ok(db_url), Ok(redis_url)) = (
            std::env::var("DATABASE_URL"),
            std::env::var("TEST_REDIS_URL").or_else(|_| std::env::var("REDIS_CACHE_URL")),
        ) else {
            eprintln!("SKIP: DATABASE_URL / TEST_REDIS_URL not set (hermetic default)");
            return;
        };
        let Ok(db) = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&db_url)
            .await
        else {
            eprintln!("SKIP: DATABASE_URL not reachable");
            return;
        };
        let Ok(redis) = shared::redis_client::create_connection_manager(&redis_url).await else {
            eprintln!("SKIP: test Redis not reachable");
            return;
        };

        // ── seed: guard A with TWO finished jobs, guard B with one, guard C (no tax id) with one.
        let (guard_a, guard_b, guard_c) = (Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
        let jobs = [
            (Uuid::new_v4(), guard_a, "2", "10"),
            (Uuid::new_v4(), guard_a, "1", "10"),
            (Uuid::new_v4(), guard_b, "3", "0"),
            (Uuid::new_v4(), guard_c, "2", "0"),
        ];
        for (booking_id, guard_id, hours, commission) in jobs {
            crate::repo::prepay_idempotent(
                &db,
                booking_id,
                Uuid::new_v4(),
                Some(guard_id),
                &crate::domain::ChargeTerms::new(
                    crate::domain::PriceBreakdown::from_subtotal("2000".parse().unwrap()),
                    commission.parse().unwrap(),
                    rust_decimal::Decimal::ZERO,
                ),
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay");
            // RECONCILE: stamp the actual hours worked → the job becomes payable to the guard.
            sqlx::query(
                "UPDATE payment.payments SET actual_hours = $2::numeric, commission_percent = $3::numeric \
                 WHERE booking_id = $1",
            )
            .bind(booking_id)
            .bind(hours)
            .bind(commission)
            .execute(&db)
            .await
            .expect("reconcile");
        }

        // company debit account + a 3% withholding rate.
        crate::repo::upsert_payout_config(
            &db,
            &crate::models::UpdatePayoutConfigRequest {
                debit_account: Some("1234567890".to_string()),
                fee_debit_account: None,
                wht_form_type_code: None,
                wht_pay_type_code: None,
                wht_income_type_code: None,
                wht_income_desc: None,
                wht_rate_percent: Some("3".parse().unwrap()),
            },
            Uuid::new_v4(),
        )
        .await
        .expect("payout config");

        let pii = |name: &str, tax_id: Option<&str>| crate::profile_client::GuardPayoutProfile {
            full_name: Some(name.to_string()),
            tax_id: tax_id.map(str::to_string),
            address: Some("99 Rama IX Rd, Bangkok".to_string()),
            phone: None,
        };
        let profile = StubProfileReader {
            guard: None,
            guards: [
                (guard_a, pii("รปภ เอ", Some("1111111111111"))),
                (guard_b, pii("รปภ บี", Some("2222222222222"))),
                (guard_c, pii("รปภ ซี", None)), // no tax id, no phone → not payable
            ]
            .into_iter()
            .collect(),
            org: Some(crate::profile_client::OrgTaxInfo {
                company_name: Some("PGuard Co., Ltd.".to_string()),
                tax_id: Some("0105551234567".to_string()),
                address: Some("1 Sathorn Rd, Bangkok".to_string()),
            }),
        };
        let deps = TestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            db: db.clone(),
            redis,
            reader: StubReader {
                booking: Some(payable_booking(Uuid::new_v4())), // base_fee 500/hr
            },
            verifier: StubVerifier::ok(sample_verified("0140315796")),
            profile,
            s3: stub_s3(),
            slip_config: sim_config(),
        };
        let app = Router::new()
            .route(
                "/admin/payouts/export",
                post(crate::api::payouts::export::<TestDeps>),
            )
            .with_state(deps);

        // ── export, ticking A and B only (C is unpayable AND unticked).
        let admin = customer_token(Uuid::new_v4(), "admin");
        let res = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/admin/payouts/export")
                    .header("authorization", format!("Bearer {admin}"))
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"guard_ids":["{guard_a}","{guard_b}"]}}"#
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK, "the batch generates");
        let bytes = axum::body::to_bytes(res.into_body(), 256 * 1024)
            .await
            .expect("body");
        let file = String::from_utf8(bytes.to_vec()).expect("UTF-8, no BOM");
        let lines: Vec<&str> = file.split("\r\n").collect();

        // HEADER, BCHDET, (TXNDET + WHTCER) × 2 guards, TRAILR
        assert_eq!(lines.len(), 7, "two guards ride ONE file: {file}");
        let txn: Vec<&Vec<&str>> = Vec::new();
        let _ = txn;
        let credits: Vec<Vec<&str>> = lines
            .iter()
            .filter(|l| l.starts_with("TXNDET"))
            .map(|l| l.split('|').collect())
            .collect();
        assert_eq!(credits.len(), 2, "one credit line PER GUARD");

        // A: (500×2−10%) + (500×1−10%) = 900 + 450 = 1350 income; 3% WHT 27.00 + 13.50 = 40.50;
        //    transfer 1309.50 — the guard's TWO jobs are summed into ONE transfer.
        // B: 500×3 = 1500 income; 45.00 WHT; 1455.00 transfer.
        let by_proxy = |proxy: &str| -> Vec<&str> {
            credits
                .iter()
                .find(|c| c[2] == proxy)
                .unwrap_or_else(|| panic!("no credit for {proxy} in {file}"))
                .clone()
        };
        let a = by_proxy("1111111111111");
        assert_eq!(a[6], "1309.50", "guard A: both jobs in one transfer");
        assert_eq!(a[13], "รปภ เอ");
        assert_eq!(a[19], "40.50", "guard A withheld tax");
        let b = by_proxy("2222222222222");
        assert_eq!(b[6], "1455.00");
        assert_eq!(b[19], "45.00");

        let bch: Vec<&str> = lines[1].split('|').collect();
        assert_eq!(bch[6], "2764.50", "batch total = 1309.50 + 1455.00");
        assert_eq!(bch[7], "2", "two credits in the batch");
        let trailer: Vec<&str> = lines[6].split('|').collect();
        assert_eq!(trailer, vec!["TRAILR", "1", "2", "2764.50"]);
        assert_eq!(
            file.matches("WHTCER").count(),
            2,
            "one ภ.ง.ด. certificate per paid guard"
        );

        // ── paid-markers: only the TICKED guards' jobs (3 of them) are marked paid; C stays unpaid.
        let paid: Vec<(Uuid, Uuid)> = sqlx::query_as(
            "SELECT booking_id, guard_id FROM payment.payout_batch_items WHERE guard_id = ANY($1)",
        )
        .bind(vec![guard_a, guard_b, guard_c])
        .fetch_all(&db)
        .await
        .expect("markers");
        assert_eq!(paid.len(), 3, "A's two jobs + B's one job are marked paid");
        assert!(
            !paid.iter().any(|(_, g)| *g == guard_c),
            "an unticked guard is never marked paid"
        );

        // ── re-running the same selection pays nothing twice (the backlog is empty for A+B).
        let again = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/admin/payouts/export")
                    .header("authorization", format!("Bearer {admin}"))
                    .header("content-type", "application/json")
                    .body(Body::from(format!(
                        r#"{{"guard_ids":["{guard_a}","{guard_b}"]}}"#
                    )))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            again.status(),
            StatusCode::BAD_REQUEST,
            "nothing left to pay for those guards"
        );

        // cleanup (items cascade with their batch).
        let booking_ids: Vec<Uuid> = jobs.iter().map(|(b, _, _, _)| *b).collect();
        let _ = sqlx::query(
            "DELETE FROM payment.payout_batches WHERE id IN \
             (SELECT batch_id FROM payment.payout_batch_items WHERE booking_id = ANY($1))",
        )
        .bind(&booking_ids)
        .execute(&db)
        .await;
        let _ = sqlx::query("DELETE FROM payment.payout_batch_items WHERE booking_id = ANY($1)")
            .bind(&booking_ids)
            .execute(&db)
            .await;
        let _ = sqlx::query(
            "DELETE FROM payment.outbox WHERE payload->'payload'->>'booking_id' = ANY($1)",
        )
        .bind(
            booking_ids
                .iter()
                .map(|b| b.to_string())
                .collect::<Vec<_>>(),
        )
        .execute(&db)
        .await;
        let _ = sqlx::query("DELETE FROM payment.payments WHERE booking_id = ANY($1)")
            .bind(&booking_ids)
            .execute(&db)
            .await;
    }
}

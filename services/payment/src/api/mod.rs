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

pub mod deductions;
pub mod payouts;
pub mod refunds;
pub mod reports;
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
        // The four multiplicands, carried through verbatim — `ChargeTerms` derives the VAT split
        // from them, so the persisted `subtotal` can never contradict the snapshot stored beside it.
        domain::PricingInputs {
            base_fee: booking.base_fee,
            booked_hours: booking.hours,
            guard_count: booking.guard_count,
            tip: booking.tip,
        },
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
/// proves identity, not role). Optional `status` filter + limit/offset; replica read.
///
/// READ-ONLY because refunds LEAVE AS A BATCH, not because they are automatic: they are sent
/// through `POST /admin/refunds/export` ([`crate::api::refunds`]) — one SCB upload file — which is
/// also the only thing that advances a refund to `processed`. There is deliberately no per-row
/// refund action on this ledger; [`admin_refund_queue`] below is the refund READ surface.
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
/// dashboard "แจ้งเตือน / คิวคืนเงิน" badge — independent of the page window).
///
/// This is the READ surface only, and it shows LANE A alone (`payment.payments`). The money actually
/// LEAVES through `/admin/refunds/export` ([`crate::api::refunds`]), which covers both lanes —
/// lane B is the duplicate-transfer `payment.payment_slips` row, which this queue has never listed.
/// A settle still only ever sets `refund_status = 'pending'`; the export is what advances it to
/// `'processed'`. (This doc used to claim v2 refunds were "event-driven" and needed no manual step.
/// They were not: nothing wrote `'processed'` at all, so the queue could only ever grow.)
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

    /// Stub profile reader — canned guard/customer PII + org block, no real profile HTTP (both the
    /// payout and the refund aggregation are tested hermetically). Default = nobody on file / empty
    /// org, so an aggregation over an unseeded id exercises the NotFound exclusion arm.
    #[derive(Clone, Default)]
    struct StubProfileReader {
        guard: Option<crate::profile_client::GuardPayoutProfile>,
        /// Per-guard PII, keyed by guard id — a payout batch pays MANY different people, each with
        /// their own name/tax id. Falls back to `guard` for the single-guard cases.
        guards: std::collections::HashMap<Uuid, crate::profile_client::GuardPayoutProfile>,
        /// Per-customer refund PII, keyed by customer id. No `customer` fallback on purpose: a
        /// refund test that forgets to seed a customer must hit the EXCLUSION path, not silently
        /// borrow someone else's phone and send them the money.
        customers: std::collections::HashMap<Uuid, crate::profile_client::CustomerPayoutProfile>,
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
        async fn get_customer_payout_profile(
            &self,
            customer_id: Uuid,
        ) -> Result<crate::profile_client::CustomerPayoutProfile, AppError> {
            self.customers
                .get(&customer_id)
                .cloned()
                .ok_or_else(|| AppError::NotFound("Customer not found".to_string()))
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
                // Stream ① customer refunds, mounted exactly as main.rs does, so the admin gate on
                // each route is exercised by the same router the service serves.
                .route(
                    "/admin/refunds/preview",
                    get(crate::api::refunds::preview::<TestDeps>),
                )
                .route(
                    "/admin/refunds/export",
                    post(crate::api::refunds::export::<TestDeps>),
                )
                .route(
                    "/admin/refunds/batches",
                    get(crate::api::refunds::list_batches::<TestDeps>),
                )
                .route(
                    "/admin/refunds/batches/{id}",
                    get(crate::api::refunds::get_batch::<TestDeps>),
                )
                .route(
                    "/admin/refunds/batches/{id}/file",
                    get(crate::api::refunds::get_batch_file::<TestDeps>),
                )
                .route(
                    "/admin/refunds/batches/{id}/status",
                    post(crate::api::refunds::set_batch_status::<TestDeps>),
                )
                .route(
                    "/admin/refunds/batches/{id}/void",
                    post(crate::api::refunds::void_batch::<TestDeps>),
                )
                .route(
                    "/admin/refunds/batches/{id}/items/void",
                    post(crate::api::refunds::void_batch_items::<TestDeps>),
                )
                .route(
                    "/admin/reports/revenue",
                    get(admin_revenue_report::<TestDeps>),
                )
                .route(
                    "/admin/reports/customer-spend",
                    get(admin_customer_spend_report::<TestDeps>),
                )
                .route(
                    "/admin/payouts/config",
                    axum::routing::put(crate::api::payouts::put_config::<TestDeps>),
                )
                .route(
                    "/admin/payouts/preview",
                    get(crate::api::payouts::preview::<TestDeps>),
                )
                .route(
                    "/admin/payouts/export",
                    post(crate::api::payouts::export::<TestDeps>),
                )
                // The batch-lifecycle routes, mounted exactly as main.rs does, so the role gate on
                // each of them is exercised by the same router the service serves.
                .route(
                    "/admin/payouts/batches",
                    get(crate::api::payouts::list_batches::<TestDeps>),
                )
                .route(
                    "/admin/payouts/batches/{id}",
                    get(crate::api::payouts::get_batch::<TestDeps>),
                )
                .route(
                    "/admin/payouts/batches/{id}/file",
                    get(crate::api::payouts::get_batch_file::<TestDeps>),
                )
                .route(
                    "/admin/payouts/batches/{id}/status",
                    post(crate::api::payouts::set_batch_status::<TestDeps>),
                )
                .route(
                    "/admin/payouts/batches/{id}/void",
                    post(crate::api::payouts::void_batch::<TestDeps>),
                )
                .route(
                    "/admin/payouts/batches/{id}/items/void",
                    post(crate::api::payouts::void_batch_items::<TestDeps>),
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

    /// POST an export (`uri` — the payout's or the refund's) and hand back the whole response,
    /// retrying into the next second if the file-ref unique refused it.
    ///
    /// `batch_ref` is a timestamp at ONE-SECOND resolution, so two exports committed in the same
    /// Bangkok second collide on `uq_payout_batches_file_ref` / `uq_refund_batches_file_ref` — BY
    /// DESIGN: two files must never share the customer transaction refs SCB de-dups on. These tests
    /// run in PARALLEL against one database, so they hit exactly that collision, and the honest
    /// remedy is the admin's own — the loser's transaction rolled back with nothing marked, so
    /// clicking again a moment later is safe. The retry lives HERE, in the test, and deliberately not
    /// in the request path. Both streams share the helper so neither can quietly stop retrying.
    async fn export_retrying_ref_collision(
        app: &Router,
        uri: &str,
        token: &str,
        body: String,
    ) -> axum::response::Response {
        const ATTEMPTS: u32 = 4;
        let mut last = None;
        for attempt in 0..ATTEMPTS {
            let res = app
                .clone()
                .oneshot(
                    Request::builder()
                        .method("POST")
                        .uri(uri)
                        .header("authorization", format!("Bearer {token}"))
                        .header("content-type", "application/json")
                        .body(Body::from(body.clone()))
                        .unwrap(),
                )
                .await
                .unwrap();
            if res.status() != StatusCode::CONFLICT || attempt == ATTEMPTS - 1 {
                return res;
            }
            last = Some(res.status());
            // Past the second boundary — plus JITTER, because two colliding callers that both sleep
            // exactly one second simply collide again in the next one. A UUID is the randomness
            // already to hand; `% 900` keeps the whole wait inside 1.0-1.9s.
            let jitter = (Uuid::new_v4().as_u128() % 900) as u64;
            tokio::time::sleep(Duration::from_millis(1000 + jitter)).await;
        }
        unreachable!("the loop returns on the last attempt, got {last:?}")
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

    /// GET/POST one of the batch-lifecycle routes with a bearer token (and a body for the POSTs —
    /// axum runs the `Json` extractor before the handler's role gate, so an empty body would be a
    /// 415 that proves nothing about the gate).
    async fn call_batch_route(
        app: Router,
        method: &str,
        uri: &str,
        token: &str,
        body: Option<&str>,
    ) -> StatusCode {
        let req = Request::builder()
            .method(method)
            .uri(uri)
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

    /// The payout HISTORY is the record of who the platform paid, and the lifecycle actions move
    /// money back into the payable backlog — neither may be reachable by a customer or a guard.
    #[tokio::test]
    async fn payout_batch_endpoints_reject_non_admin() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let id = Uuid::new_v4();
        for role in ["customer", "guard"] {
            let tok = customer_token(Uuid::new_v4(), role);
            for (method, uri, body) in [
                ("GET", "/admin/payouts/batches".to_string(), None),
                ("GET", format!("/admin/payouts/batches/{id}"), None),
                ("GET", format!("/admin/payouts/batches/{id}/file"), None),
                (
                    "POST",
                    format!("/admin/payouts/batches/{id}/status"),
                    Some(r#"{"status":"uploaded"}"#),
                ),
                (
                    "POST",
                    format!("/admin/payouts/batches/{id}/void"),
                    Some(r#"{"reason":"ยกเลิก"}"#),
                ),
            ] {
                assert_eq!(
                    call_batch_route(app.clone(), method, &uri, &tok, body).await,
                    StatusCode::FORBIDDEN,
                    "{role} must not reach {method} {uri}"
                );
            }
        }
    }

    /// The two request-body rules that must hold BEFORE any DB read (the test pool is deliberately
    /// unusable, so a 400 here proves the check ran first): a void needs a real reason, and `voided`
    /// is not a status the generic endpoint may set.
    #[tokio::test]
    async fn payout_batch_lifecycle_validates_the_body_before_touching_the_db() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let admin = customer_token(Uuid::new_v4(), "admin");
        let id = Uuid::new_v4();
        let status_uri = format!("/admin/payouts/batches/{id}/status");
        let void_uri = format!("/admin/payouts/batches/{id}/void");

        // A blank reason is useless six months later — and the void it would justify puts every
        // booking in the batch back in the payable backlog.
        for blank in [r#"{"reason":""}"#, r#"{"reason":"   "}"#] {
            assert_eq!(
                call_batch_route(app.clone(), "POST", &void_uri, &admin, Some(blank)).await,
                StatusCode::BAD_REQUEST,
                "a void needs a reason"
            );
        }
        // Voiding through the generic status endpoint would flip the header WITHOUT un-marking the
        // items — the bookings would be unpayable forever, which is the bug void exists to fix.
        assert_eq!(
            call_batch_route(
                app.clone(),
                "POST",
                &status_uri,
                &admin,
                Some(r#"{"status":"voided"}"#)
            )
            .await,
            StatusCode::BAD_REQUEST,
            "voiding has its own endpoint"
        );
        assert_eq!(
            call_batch_route(
                app,
                "POST",
                &status_uri,
                &admin,
                Some(r#"{"status":"settled"}"#)
            )
            .await,
            StatusCode::BAD_REQUEST,
            "an unknown status is refused, not stored"
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

    #[tokio::test]
    async fn payout_config_rejects_an_unknown_wht_form_code() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let admin = customer_token(Uuid::new_v4(), "admin");
        let put = |body: &str| {
            let req = Request::builder()
                .method("PUT")
                .uri("/admin/payouts/config")
                .header("authorization", format!("Bearer {admin}"))
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap();
            app.clone().oneshot(req)
        };
        // The seven ภ.ง.ด. codes are NOT a range (01/03/04/11/12/13/53) — `02` looks plausible and
        // is not one of them. Rejected BEFORE the DB write (the test pool is unusable), so reaching
        // a 400 here also proves the validation runs at save time.
        for bad in [
            r#"{"wht_form_type_code":"02"}"#,
            r#"{"wht_form_type_code":"3"}"#,
        ] {
            assert_eq!(
                put(bad).await.unwrap().status(),
                StatusCode::BAD_REQUEST,
                "{bad} must not be storable"
            );
        }
        // A negative per-transaction cap would exclude every guard from every future batch.
        assert_eq!(
            put(r#"{"max_transfer_per_txn":"-1"}"#)
                .await
                .unwrap()
                .status(),
            StatusCode::BAD_REQUEST
        );
    }

    #[tokio::test]
    async fn payout_export_rejects_a_back_dated_value_date() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let admin = customer_token(Uuid::new_v4(), "admin");
        // Two days back is in the past in EVERY timezone reading (Bangkok is never more than a day
        // ahead of UTC). SCB rejects a back-dated batch outright, so we refuse before generating.
        let past = (Utc::now() - chrono::Duration::days(2)).date_naive();
        assert_eq!(
            post_payout_export(app, &admin, Some(&format!(r#"{{"value_date":"{past}"}}"#))).await,
            StatusCode::BAD_REQUEST,
            "a back-dated value date is refused before any DB read"
        );
    }

    /// END-TO-END, real Postgres + Redis: the guard's LOGIN PHONE only reaches SCB when an operator
    /// opted in, a VOID is visible to the very next export, and one bounced credit line can be
    /// returned to the backlog on its own — over the real HTTP routes.
    ///
    /// Three defects meet here, which is why they share a test: the phone populated for the
    /// PromptPay `MOB` fallback was silently also being sent as an SMS-notify number (SCB bills per
    /// SMS, and nobody asked the guard); the backlog was read from the read REPLICA, so a void
    /// followed by an immediate export could not see the bookings it had just released; and a single
    /// failed credit line had no remedy short of voiding the whole file. DATABASE_URL + test Redis
    /// gated.
    #[tokio::test]
    async fn payout_sms_opt_in_void_visibility_and_single_item_return() {
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

        // ── one guard, one finished job: 500/hr × 2h, no commission → income 1000, 3% WHT 30.00,
        //    transfer 970.00.
        let guard_id = Uuid::new_v4();
        let booking_id = Uuid::new_v4();
        crate::repo::prepay_idempotent(
            &db,
            booking_id,
            Uuid::new_v4(),
            Some(guard_id),
            &crate::domain::ChargeTerms::new(
                // 500 ฿/h × 4h × 1 guard, no tip → a VAT-exclusive subtotal of 2000.
                crate::domain::PricingInputs {
                    base_fee: "500".parse().unwrap(),
                    booked_hours: 4,
                    guard_count: 1,
                    tip: rust_decimal::Decimal::ZERO,
                },
                rust_decimal::Decimal::ZERO,
                rust_decimal::Decimal::ZERO,
            ),
            "promptpay",
            Uuid::new_v4(),
        )
        .await
        .expect("pre-pay");
        sqlx::query(
            "UPDATE payment.payments SET actual_hours = 2, commission_percent = 0 \
             WHERE booking_id = $1",
        )
        .bind(booking_id)
        .execute(&db)
        .await
        .expect("reconcile");

        /// Save the payout config with the SMS opt-in either way (everything else stays as stored).
        async fn set_sms(db: &sqlx::PgPool, on: bool) {
            crate::repo::upsert_payout_config(
                db,
                &crate::models::UpdatePayoutConfigRequest {
                    debit_account: Some("1234567896".to_string()),
                    fee_debit_account: None,
                    revenue_account: None,
                    wht_form_type_code: None,
                    wht_pay_type_code: None,
                    wht_income_type_code: None,
                    wht_income_desc: None,
                    wht_rate_percent: Some("3".parse().unwrap()),
                    max_transfer_per_txn: None,
                    fee_charge_code: None,
                    sms_notify: Some(on),
                },
                Uuid::new_v4(),
            )
            .await
            .expect("payout config");
        }
        set_sms(&db, false).await;

        // The guard has BOTH a valid national id (→ the `NAT` destination) and a phone. The phone is
        // the thing under test: it must address nothing and notify nobody unless asked.
        let profile = StubProfileReader {
            guard: None,
            customers: Default::default(),
            guards: [(
                guard_id,
                crate::profile_client::GuardPayoutProfile {
                    full_name: Some("รปภ มีเบอร์".to_string()),
                    // 111111111111 → sum 90, 90 mod 11 = 2, check (11−2) mod 10 = 9.
                    tax_id: Some("1111111111119".to_string()),
                    address: Some("99 Rama IX Rd, Bangkok".to_string()),
                    phone: Some("081-234-5678".to_string()),
                },
            )]
            .into_iter()
            .collect(),
            org: Some(crate::profile_client::OrgTaxInfo {
                company_name: Some("PGuard Co., Ltd.".to_string()),
                tax_id: Some("0105551234567".to_string()),
                address: Some("1 Sathorn Rd, Bangkok".to_string()),
            }),
        };
        let app = Router::new()
            .route(
                "/admin/payouts/export",
                post(crate::api::payouts::export::<TestDeps>),
            )
            .route(
                "/admin/payouts/batches/{id}/items/void",
                post(crate::api::payouts::void_batch_items::<TestDeps>),
            )
            .with_state(TestDeps {
                dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
                db: db.clone(),
                redis,
                reader: StubReader {
                    booking: Some(payable_booking(Uuid::new_v4())),
                },
                verifier: StubVerifier::ok(sample_verified("0140315796")),
                profile,
                s3: stub_s3(),
                slip_config: sim_config(),
            });
        let admin = customer_token(Uuid::new_v4(), "admin");

        /// Export just this guard and return the file's single TXNDET, split into fields.
        async fn credit_line(app: &Router, admin: &str, guard_id: Uuid) -> Vec<String> {
            let res = export_retrying_ref_collision(
                app,
                "/admin/payouts/export",
                admin,
                format!(r#"{{"guard_ids":["{guard_id}"]}}"#),
            )
            .await;
            assert_eq!(res.status(), StatusCode::OK, "the batch generates");
            let bytes = axum::body::to_bytes(res.into_body(), 256 * 1024)
                .await
                .expect("body");
            let file = String::from_utf8(bytes.to_vec()).expect("UTF-8, no BOM");
            file.split("\r\n")
                .find(|l| l.starts_with("TXNDET"))
                .unwrap_or_else(|| panic!("no credit line in {file}"))
                .split('|')
                .map(str::to_string)
                .collect()
        }

        // ── opted OUT (the default): the money is addressed by the national id, and the phone
        //    appears NOWHERE — no notify flag, no number. SCB bills per SMS, and that number is the
        //    guard's login phone.
        let txn = credit_line(&app, &admin, guard_id).await;
        assert_eq!(txn[2], "1111111111119", "addressed by the NAT proxy");
        assert_eq!(txn[3], "NAT");
        assert_eq!(
            txn[8], "OUR",
            "field 8 (fee charge) is mandatory on every credit row and must not be blank"
        );
        assert_eq!(txn[9], "N", "SMS notify OFF by default");
        assert_eq!(
            txn[10], "",
            "…and the login phone never leaves the platform"
        );
        assert!(
            !txn.iter().any(|f| f.contains("0812345678")),
            "the phone appears nowhere in the credit line: {txn:?}"
        );

        // ── void the batch, then export again IMMEDIATELY. Read from a lagging replica this would
        //    find nothing to pay (400) — the void would look like it did nothing.
        let batch_id: Uuid = sqlx::query_scalar(
            "SELECT batch_id FROM payment.payout_batch_items WHERE booking_id = $1",
        )
        .bind(booking_id)
        .fetch_one(&db)
        .await
        .expect("the first batch");
        crate::repo::void_payout_batch(&db, batch_id, Uuid::new_v4(), "ยังไม่ได้อัปโหลด")
            .await
            .expect("void");

        // ── now opted IN: the same phone that could not be sent before rides fields 9/10.
        set_sms(&db, true).await;
        let txn = credit_line(&app, &admin, guard_id).await;
        assert_eq!(txn[9], "Y", "the operator asked for the SMS");
        assert_eq!(txn[10], "0812345678", "digits only, dashes stripped");
        assert_eq!(txn[2], "1111111111119", "…and the destination is unchanged");

        // ── the PER-ITEM return, over the real route, on the batch just generated.
        let second_batch: Uuid = sqlx::query_scalar(
            "SELECT batch_id FROM payment.payout_batch_items \
              WHERE booking_id = $1 AND voided_at IS NULL",
        )
        .bind(booking_id)
        .fetch_one(&db)
        .await
        .expect("the second batch");
        let items_void = |body: String| {
            let app = app.clone();
            let admin = admin.clone();
            async move {
                app.oneshot(
                    Request::builder()
                        .method("POST")
                        .uri(format!("/admin/payouts/batches/{second_batch}/items/void"))
                        .header("authorization", format!("Bearer {admin}"))
                        .header("content-type", "application/json")
                        .body(Body::from(body))
                        .unwrap(),
                )
                .await
                .unwrap()
            }
        };
        // An empty tick-list must NOT be read as "all of them" — that is the whole-batch action.
        assert_eq!(
            items_void(r#"{"booking_ids":[],"reason":"ว่าง"}"#.to_string())
                .await
                .status(),
            StatusCode::BAD_REQUEST
        );
        // …and the reason is mandatory, exactly like the whole-batch void's.
        assert_eq!(
            items_void(format!(
                r#"{{"booking_ids":["{booking_id}"],"reason":"   "}}"#
            ))
            .await
            .status(),
            StatusCode::BAD_REQUEST
        );
        let ok = items_void(format!(
            r#"{{"booking_ids":["{booking_id}"],"reason":"ธนาคารแจ้งว่าพร้อมเพย์ปลายทางไม่ผูกบัญชี"}}"#
        ))
        .await;
        assert_eq!(ok.status(), StatusCode::OK, "the failed line goes back");
        // A second attempt is a typed 409, not a silent success (their page may be stale).
        assert_eq!(
            items_void(format!(
                r#"{{"booking_ids":["{booking_id}"],"reason":"กดซ้ำ"}}"#
            ))
            .await
            .status(),
            StatusCode::CONFLICT
        );
        // The booking really is payable again — and its batch was left alone.
        let (live, status): (i64, String) = sqlx::query_as(
            "SELECT (SELECT count(*) FROM payment.payout_batch_items \
                      WHERE booking_id = $1 AND voided_at IS NULL), \
                    (SELECT status FROM payment.payout_batches WHERE id = $2)",
        )
        .bind(booking_id)
        .bind(second_batch)
        .fetch_one(&db)
        .await
        .expect("state");
        assert_eq!(live, 0, "no live paid-marker → back in the backlog");
        assert_eq!(status, "generated", "the batch's own status is untouched");

        // Leave the shared singleton config as we found it (other tests read the same row).
        set_sms(&db, false).await;
        let batches: Vec<Uuid> = sqlx::query_scalar(
            "SELECT DISTINCT batch_id FROM payment.payout_batch_items WHERE booking_id = $1",
        )
        .bind(booking_id)
        .fetch_all(&db)
        .await
        .unwrap_or_default();
        let _ = sqlx::query("DELETE FROM payment.money_audit WHERE target_id = ANY($1)")
            .bind(&batches)
            .execute(&db)
            .await;
        // The SHARED bank-reference reservation (migration 0012) is polymorphic, so no FK cascade
        // releases it — a test deleting its batches releases their references by hand.
        let _ = sqlx::query("DELETE FROM payment.scb_file_refs WHERE batch_id = ANY($1)")
            .bind(&batches)
            .execute(&db)
            .await;
        let _ = sqlx::query("DELETE FROM payment.payout_batches WHERE id = ANY($1)")
            .bind(&batches)
            .execute(&db)
            .await;
        let _ = sqlx::query("DELETE FROM payment.payout_batch_items WHERE booking_id = $1")
            .bind(booking_id)
            .execute(&db)
            .await;
        let _ =
            sqlx::query("DELETE FROM payment.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(booking_id.to_string())
                .execute(&db)
                .await;
        let _ = sqlx::query("DELETE FROM payment.payments WHERE booking_id = $1")
            .bind(booking_id)
            .execute(&db)
            .await;
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

        // ── seed: guard A with TWO finished jobs, guard B with one, guard C (no tax id) with one,
        //    guard D with one ABSURD job (500/hr × 5000h) that busts the ฿2,000,000 per-transaction
        //    cap — D is ticked but must be excluded, not written as a line SCB would reject.
        //    Guard F is ticked too and has a perfectly-shaped 13-digit tax id whose CHECK DIGIT is
        //    wrong — PromptPay would credit whoever really owns that number, so F must be excluded.
        //    Guard E has NO tax id but DOES have a phone — the PromptPay `MOB` fallback. Under a
        //    withholding rate (3% here) they are still excluded, but for the TAX reason, never for
        //    "no PromptPay": see the preview assertion at the end.
        let (guard_a, guard_b, guard_c, guard_d, guard_e, guard_f) = (
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
        );
        let jobs = [
            (Uuid::new_v4(), guard_a, "2", "10"),
            (Uuid::new_v4(), guard_a, "1", "10"),
            (Uuid::new_v4(), guard_b, "3", "0"),
            (Uuid::new_v4(), guard_c, "2", "0"),
            (Uuid::new_v4(), guard_d, "5000", "0"),
            (Uuid::new_v4(), guard_e, "2", "0"),
            (Uuid::new_v4(), guard_f, "2", "0"),
        ];
        for (booking_id, guard_id, hours, commission) in jobs {
            crate::repo::prepay_idempotent(
                &db,
                booking_id,
                Uuid::new_v4(),
                Some(guard_id),
                &crate::domain::ChargeTerms::new(
                    // 500 ฿/h × 4h × 1 guard, no tip → a VAT-exclusive subtotal of 2000.
                    crate::domain::PricingInputs {
                        base_fee: "500".parse().unwrap(),
                        booked_hours: 4,
                        guard_count: 1,
                        tip: rust_decimal::Decimal::ZERO,
                    },
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

        // company debit account + a 3% withholding rate. The account must pass SCB's §14 check
        // digit (`scb_export::is_valid_scb_account`) — the export refuses to build a file on an
        // account the bank would bounce at the batch header, so filler like `1234567890` fails.
        crate::repo::upsert_payout_config(
            &db,
            &crate::models::UpdatePayoutConfigRequest {
                debit_account: Some("1234567896".to_string()),
                fee_debit_account: None,
                revenue_account: None,
                wht_form_type_code: None,
                wht_pay_type_code: None,
                wht_income_type_code: None,
                wht_income_desc: None,
                wht_rate_percent: Some("3".parse().unwrap()),
                max_transfer_per_txn: None, // keeps the stored/default ฿2,000,000 cap
                fee_charge_code: None,      // keeps the stored/default `OUR`
                sms_notify: None,           // keeps the stored/default OFF
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
            customers: Default::default(),
            guards: [
                // The tax ids are GENUINELY VALID Thai national ids — the export re-checks the
                // mod-11 digit before it will send money to one (a mistyped id credits a stranger),
                // so a lazy `111…1` fixture would now be excluded rather than paid. Working:
                //   111111111111 → sum 90,  90 mod 11 = 2 → check (11−2) mod 10 = 9
                //   222222222222 → sum 180, 180 mod 11 = 4 → check 7
                //   333333333333 → sum 270, 270 mod 11 = 6 → check 5
                (guard_a, pii("รปภ เอ", Some("1111111111119"))),
                (guard_b, pii("รปภ บี", Some("2222222222227"))),
                (guard_c, pii("รปภ ซี", None)), // no tax id, no phone → not payable
                (guard_d, pii("รปภ ดี", Some("3333333333335"))), // payable PII, over-cap amount
                // E: no tax id but a PHONE. `resolve_proxy` falls back to the `MOB` proxy, so the
                // money HAS a destination — the only thing missing is the TIN the ภ.ง.ด.
                // certificate needs. The SMS-notify opt-in must never touch this: the phone here
                // ADDRESSES the transfer, it does not notify anyone.
                (
                    guard_e,
                    crate::profile_client::GuardPayoutProfile {
                        full_name: Some("รปภ อี".to_string()),
                        tax_id: None,
                        address: Some("99 Rama IX Rd, Bangkok".to_string()),
                        phone: Some("081-234-5678".to_string()),
                    },
                ),
                // …and the typo: `123456789012` needs check digit 1, not 3.
                (guard_f, pii("รปภ เอฟ", Some("1234567890123"))),
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
            // **B2**: booking's LIVE row deliberately carries a DIFFERENT `base_fee` (฿9,999/h) from
            // the ฿500/h every payment row snapshotted at pre-pay. The payout must price off the
            // SNAPSHOT — payment's own column, the very one stream ② sweeps the cut from — so every
            // amount asserted below stays a ฿500/h figure. If the aggregation ever went back to
            // booking's current column, the guard would be paid off one number while the sweep took
            // `subtotal − guard_income` off another, and this whole file's totals would move.
            //
            // In fact the stub is never CALLED here: `aggregate` only asks booking about rows whose
            // snapshot is NULL, and there are none.
            reader: StubReader {
                booking: Some(InternalBooking {
                    base_fee: "9999".parse().unwrap(),
                    ..payable_booking(Uuid::new_v4())
                }),
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
            // The preview is mounted on the SAME state so the exclusion REASONS can be read back:
            // the file alone only shows who was paid, and "excluded" is where a guard whose
            // PromptPay resolved fine is told apart from one who has no destination at all.
            .route(
                "/admin/payouts/preview",
                get(crate::api::payouts::preview::<TestDeps>),
            )
            .with_state(deps);

        // ── export, ticking A, B and D (C is unpayable AND unticked; D is ticked but over the cap;
        //    E is ticked and has a MOB-only destination but no TIN).
        let admin = customer_token(Uuid::new_v4(), "admin");
        let res = export_retrying_ref_collision(
            &app,
            "/admin/payouts/export",
            &admin,
            format!(
                r#"{{"guard_ids":["{guard_a}","{guard_b}","{guard_d}","{guard_e}","{guard_f}"]}}"#
            ),
        )
        .await;
        assert_eq!(res.status(), StatusCode::OK, "the batch generates");
        let bytes = axum::body::to_bytes(res.into_body(), 256 * 1024)
            .await
            .expect("body");
        let file = String::from_utf8(bytes.to_vec()).expect("UTF-8, no BOM");
        let lines: Vec<&str> = file.split("\r\n").collect();

        // HEADER, BCHDET, (TXNDET + WHTCER + WHTDET) × 2 guards, TRAILR. The certificate is TWO
        // physical records (doc line 2592), so a paid guard contributes three lines, not two.
        assert_eq!(lines.len(), 9, "two guards ride ONE file: {file}");
        let txn: Vec<&Vec<&str>> = Vec::new();
        let _ = txn;
        let credits: Vec<Vec<&str>> = lines
            .iter()
            .filter(|l| l.starts_with("TXNDET"))
            .map(|l| l.split('|').collect())
            .collect();
        assert_eq!(credits.len(), 2, "one credit line PER PAYABLE GUARD");
        assert!(
            !file.contains("3333333333335"),
            "the over-cap guard is EXCLUDED, never written as an over-limit line: {file}"
        );
        assert!(
            !file.contains("1234567890123"),
            "a national id that fails the check digit never becomes a destination: {file}"
        );

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
        let a = by_proxy("1111111111119");
        assert_eq!(a[6], "1309.50", "guard A: both jobs in one transfer");
        assert_eq!(a[13], "รปภ เอ");
        assert_eq!(a[19], "40.50", "guard A withheld tax");
        let b = by_proxy("2222222222227");
        assert_eq!(b[6], "1455.00");
        assert_eq!(b[19], "45.00");

        let bch: Vec<&str> = lines[1].split('|').collect();
        assert_eq!(bch[6], "2764.50", "batch total = 1309.50 + 1455.00");
        assert_eq!(bch[7], "2", "two credits in the batch");
        assert!(
            bch[1].chars().count() <= 12,
            "the customer batch ref is capped at 12 chars: {}",
            bch[1]
        );
        // HEADER field 1 = batchRef & productCode (doc line 1420), NOT the download filename.
        let header: Vec<&str> = lines[0].split('|').collect();
        assert_eq!(header[1], format!("{}PPY", bch[1]));
        let trailer: Vec<&str> = lines[8].split('|').collect();
        assert_eq!(trailer, vec!["TRAILR", "1", "2", "2764.50"]);
        assert_eq!(
            file.matches("WHTCER").count(),
            2,
            "one ภ.ง.ด. certificate per paid guard"
        );
        assert_eq!(
            file.matches("\r\nWHTDET|").count(),
            2,
            "each certificate's income detail is its OWN record"
        );
        // Every customer transaction ref is unique within the file (the batch ref is folded in).
        let refs: std::collections::HashSet<&str> = credits.iter().map(|c| c[1]).collect();
        assert_eq!(refs.len(), 2, "customer txn refs are unique per file");
        // sms_notify is OFF (the stored default), so no credit line may carry a notify number —
        // asserted on the FIELDS, not on the whole text, because field 2 of a phone-addressed
        // (`MOB`) line legitimately IS a phone number.
        for c in &credits {
            assert_eq!(c[9], "N", "SMS notify off by default: {c:?}");
            assert_eq!(c[10], "", "…and no notify number: {c:?}");
        }

        // ── paid-markers: only the TICKED guards' jobs (3 of them) are marked paid; C stays unpaid.
        let paid: Vec<(Uuid, Uuid)> = sqlx::query_as(
            "SELECT booking_id, guard_id FROM payment.payout_batch_items WHERE guard_id = ANY($1)",
        )
        .bind(vec![guard_a, guard_b, guard_c, guard_d, guard_e, guard_f])
        .fetch_all(&db)
        .await
        .expect("markers");
        assert_eq!(paid.len(), 3, "A's two jobs + B's one job are marked paid");
        assert!(
            !paid.iter().any(|(_, g)| *g == guard_c),
            "an unticked guard is never marked paid"
        );
        for (label, excluded) in [
            ("over-cap", guard_d),
            ("MOB proxy, no TIN", guard_e),
            ("bad check digit", guard_f),
        ] {
            assert!(
                !paid.iter().any(|(_, g)| *g == excluded),
                "an EXCLUDED guard ({label}) is never marked paid — their job stays in the backlog"
            );
        }

        // ── THE MOB FALLBACK IS ALIVE. Guard E has no tax id, only a phone. The SMS-notify opt-in
        //    gates the NOTIFY fields and nothing else, so `resolve_proxy` must still fall back to
        //    that phone as the `MOB` DESTINATION — had the gate been applied one line too early
        //    (`resolve_proxy(tax_id, sms_notify.then(phone))`), E would lose their destination and
        //    the money with it.
        //
        //    The proof is WHICH reason the preview gives. E is excluded either way under a 3%
        //    withholding rate — `ValidWHTMandatory` requires the recipient's TIN on every
        //    certificate (doc line 2582), so paying them would bounce the whole file — but the
        //    reason must be the TAX one. "ไม่มีพร้อมเพย์" here would mean the destination never
        //    resolved, i.e. the fallback is broken.
        let preview = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/payouts/preview")
                    .header("authorization", format!("Bearer {admin}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(preview.status(), StatusCode::OK);
        let body = axum::body::to_bytes(preview.into_body(), 4 * 1024 * 1024)
            .await
            .expect("preview body");
        let preview: serde_json::Value = serde_json::from_slice(&body).expect("preview json");
        let reason_for = |guard: Uuid| -> String {
            preview["data"]["excluded"]
                .as_array()
                .expect("excluded list")
                .iter()
                .find(|e| e["guard_id"].as_str() == Some(&guard.to_string()))
                .unwrap_or_else(|| panic!("no exclusion for {guard} in {preview}"))
                .get("reason")
                .and_then(|r| r.as_str())
                .unwrap_or_default()
                .to_string()
        };
        let e_reason = reason_for(guard_e);
        assert!(
            e_reason.contains("หัก ณ ที่จ่าย"),
            "guard E is held back by the WHT certificate, not by the transfer rail: {e_reason}"
        );
        assert!(
            !e_reason.contains("ไม่มีพร้อมเพย์"),
            "the phone STILL addresses the money — the MOB fallback is not gated by sms_notify: \
             {e_reason}"
        );
        // …and the contrast: guard C has neither id nor phone, so THEY are the "no PromptPay" case.
        let c_reason = reason_for(guard_c);
        assert!(
            c_reason.contains("ไม่มีพร้อมเพย์"),
            "no id and no phone = no destination at all: {c_reason}"
        );

        // ── the batch STORED the exact bytes it streamed. This is what closes the one-way door:
        //    the download the admin just lost can be fetched again from
        //    `/admin/payouts/batches/{id}/file` instead of the bookings being paid-forever with no
        //    file. `recipient_count` counts GUARDS (2), not the bookings they cover (3).
        let (batch_id, stored, recipients, status): (Uuid, Option<String>, i32, String) =
            sqlx::query_as(
                "SELECT b.id, b.file_text, b.recipient_count, b.status FROM payment.payout_batches b \
                 WHERE b.id = (SELECT batch_id FROM payment.payout_batch_items WHERE guard_id = $1)",
            )
            .bind(guard_b)
            .fetch_one(&db)
            .await
            .expect("the generated batch");
        assert_eq!(
            stored.as_deref(),
            Some(file.as_str()),
            "the stored file is byte-for-byte what was downloaded"
        );
        assert_eq!(
            recipients, 2,
            "two GUARDS, though they cover three bookings"
        );
        assert_eq!(status, "generated");
        // …and the money-action log has the export, written in the batch's own transaction.
        let audits: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM payment.money_audit \
             WHERE target_kind = 'payout_batch' AND target_id = $1 AND action = 'payout_batch_exported'",
        )
        .bind(batch_id)
        .fetch_one(&db)
        .await
        .expect("audit");
        assert_eq!(audits, 1, "one audit row per export");

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

        // cleanup (items cascade with their batch; the audit log is append-only in the service, so
        // the test clears its own rows by hand).
        let booking_ids: Vec<Uuid> = jobs.iter().map(|(b, _, _, _)| *b).collect();
        let _ = sqlx::query("DELETE FROM payment.money_audit WHERE target_id = $1")
            .bind(batch_id)
            .execute(&db)
            .await;
        let _ = sqlx::query(
            "DELETE FROM payment.scb_file_refs WHERE batch_id IN \
             (SELECT batch_id FROM payment.payout_batch_items WHERE booking_id = ANY($1))",
        )
        .bind(&booking_ids)
        .execute(&db)
        .await;
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

    // ----- customer refunds: the queue that money can finally leave -----

    #[tokio::test]
    async fn refund_endpoints_reject_non_admin() {
        let Some(app) = router(None).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A customer must not be able to see who is owed money — nor trigger a money file, nor walk
        // one through the bank, nor un-settle one. Every route the service mounts is listed, so a new
        // one added without a role gate fails here rather than in production.
        let customer = customer_token(Uuid::new_v4(), "customer");
        let batch = Uuid::new_v4();
        // The bodies are WELL-FORMED on purpose: a body that fails to deserialize would 422 before
        // the handler runs, so the test would pass without ever proving the role gate exists.
        for (method, uri, body) in [
            ("GET", "/admin/refunds/preview".to_string(), "{}"),
            ("POST", "/admin/refunds/export".to_string(), "{}"),
            ("GET", "/admin/refunds/batches".to_string(), "{}"),
            ("GET", format!("/admin/refunds/batches/{batch}"), "{}"),
            ("GET", format!("/admin/refunds/batches/{batch}/file"), "{}"),
            (
                "POST",
                format!("/admin/refunds/batches/{batch}/status"),
                r#"{"status":"uploaded"}"#,
            ),
            (
                "POST",
                format!("/admin/refunds/batches/{batch}/void"),
                r#"{"reason":"ยกเลิก"}"#,
            ),
            (
                "POST",
                format!("/admin/refunds/batches/{batch}/items/void"),
                r#"{"sources":[{"source_kind":"payment","source_id":"00000000-0000-0000-0000-000000000001"}],"reason":"ตีกลับ"}"#,
            ),
        ] {
            let uri = uri.as_str();
            let res = app
                .clone()
                .oneshot(
                    Request::builder()
                        .method(method)
                        .uri(uri)
                        .header("authorization", format!("Bearer {customer}"))
                        .header("content-type", "application/json")
                        .body(Body::from(body))
                        .unwrap(),
                )
                .await
                .unwrap();
            assert_eq!(res.status(), StatusCode::FORBIDDEN, "{method} {uri}");
        }
    }

    /// END-TO-END, real Postgres: ONE refund file returns money to MANY customers, over BOTH lanes,
    /// and actually DRAINS the queue.
    ///
    /// This is the test the whole phase exists for. Before it, `refund_status` only ever moved to
    /// `'pending'` — the customer got a push saying their money was on the way and nothing ever left
    /// the building. So the assertions walk the entire money path over the real routes:
    ///  * a LANE-A obligation (a settle's `payments.refund_amount`) and a LANE-B one (a duplicate
    ///    `payment_slips` transfer) both ride the SAME file — a lane left out is unrefunded money;
    ///  * a customer with two obligations gets ONE credit line summing them;
    ///  * a customer with no resolvable phone is EXCLUDED with a Thai reason and their obligation is
    ///    NOT marked processed;
    ///  * the emitted file carries NO `WHTCER` and NO `WHTDET` — a refund is returned capital, not
    ///    assessable income, and issuing a tax certificate for it would be a wrong filing;
    ///  * a second export finds nothing left to send.
    /// DATABASE_URL + test Redis gated.
    #[tokio::test]
    async fn refund_export_returns_money_to_many_customers_over_both_lanes() {
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

        // ── seed. A: a lane-A overpay AND a lane-B duplicate transfer (one credit line, summed).
        //    B: a lane-B duplicate only. C: a lane-A refund but NO phone on file — unrefundable, and
        //    the whole point of the exclusion ladder. D: a lane-A refund whose stored phone carries a
        //    country code, so it normalises to THIRTEEN digits — the value SCB would stamp `NAT` and
        //    PromptPay to whoever owns that national id.
        let (cust_a, cust_b, cust_c, cust_d) = (
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
        );
        let (bk_a1, bk_a2, bk_b, bk_c, bk_d) = (
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
            Uuid::new_v4(),
        );
        let bookings = [bk_a1, bk_a2, bk_b, bk_c, bk_d];

        /// Insert a completed pre-pay for `booking` owned by `customer`; returns the payment id.
        async fn prepay(db: &sqlx::PgPool, booking: Uuid, customer: Uuid) -> Uuid {
            let out = crate::repo::prepay_idempotent(
                db,
                booking,
                customer,
                Some(Uuid::new_v4()),
                &crate::domain::ChargeTerms::new(
                    // 500 ฿/h × 4h × 1 guard, no tip → a VAT-exclusive subtotal of 2000.
                    crate::domain::PricingInputs {
                        base_fee: "500".parse().unwrap(),
                        booked_hours: 4,
                        guard_count: 1,
                        tip: rust_decimal::Decimal::ZERO,
                    },
                    rust_decimal::Decimal::ZERO,
                    rust_decimal::Decimal::ZERO,
                ),
                "promptpay",
                Uuid::new_v4(),
            )
            .await
            .expect("pre-pay");
            match out {
                crate::repo::PrePayOutcome::Created(p)
                | crate::repo::PrePayOutcome::AlreadyPaid(p) => p.id,
            }
        }
        // Lane A: the settle left money owed (what `reconcile_on_completion` /
        // `refund_on_cancellation` / `refund_race_lost_prepay` all leave behind).
        async fn owe(db: &sqlx::PgPool, payment_id: Uuid, amount: &str) {
            sqlx::query(
                "UPDATE payment.payments SET refund_amount = $2::numeric, \
                        refund_status = 'pending' WHERE id = $1",
            )
            .bind(payment_id)
            .bind(amount)
            .execute(db)
            .await
            .expect("queue the refund");
        }
        // Lane B: a SECOND, real transfer for an already-paid booking, recorded UNAPPLIED.
        async fn duplicate_transfer(
            db: &sqlx::PgPool,
            payment_id: Uuid,
            booking: Uuid,
            amount: &str,
        ) -> Uuid {
            let unique = Uuid::new_v4().simple().to_string();
            sqlx::query_scalar(
                "INSERT INTO payment.payment_slips \
                     (payment_id, booking_id, reference_id, trans_ref, amount, slip_key, applied, refund_status) \
                 VALUES ($1, $2, $3, $4, $5::numeric, $6, FALSE, 'pending') RETURNING id",
            )
            .bind(payment_id)
            .bind(booking)
            .bind(format!("ref-{unique}"))
            .bind(format!("txn-{unique}"))
            .bind(amount)
            .bind(format!("slips/{unique}.jpg"))
            .fetch_one(db)
            .await
            .expect("record the duplicate transfer")
        }

        let pay_a1 = prepay(&db, bk_a1, cust_a).await;
        owe(&db, pay_a1, "640.00").await;
        let pay_a2 = prepay(&db, bk_a2, cust_a).await;
        let slip_a = duplicate_transfer(&db, pay_a2, bk_a2, "2140.00").await;
        let pay_b = prepay(&db, bk_b, cust_b).await;
        let slip_b = duplicate_transfer(&db, pay_b, bk_b, "500.00").await;
        let pay_c = prepay(&db, bk_c, cust_c).await;
        owe(&db, pay_c, "120.00").await;
        let pay_d = prepay(&db, bk_d, cust_d).await;
        owe(&db, pay_d, "77.00").await;

        // The company debit account must pass SCB's §14 check digit — the export refuses to build a
        // file on an account the bank would bounce at the batch header.
        crate::repo::upsert_payout_config(
            &db,
            &crate::models::UpdatePayoutConfigRequest {
                debit_account: Some("1234567896".to_string()),
                fee_debit_account: None,
                revenue_account: None,
                wht_form_type_code: None,
                wht_pay_type_code: None,
                wht_income_type_code: None,
                wht_income_desc: None,
                wht_rate_percent: None,
                max_transfer_per_txn: None,
                fee_charge_code: None,
                sms_notify: None,
            },
            Uuid::new_v4(),
        )
        .await
        .expect("payout config");

        let customer_pii =
            |name: &str, phone: Option<&str>| crate::profile_client::CustomerPayoutProfile {
                full_name: Some(name.to_string()),
                phone: phone.map(str::to_string),
                address: Some("99 Rama IX Rd, Bangkok".to_string()),
            };
        let profile = StubProfileReader {
            guard: None,
            guards: Default::default(),
            customers: [
                (cust_a, customer_pii("ลูกค้า เอ", Some("081-234-5678"))),
                (cust_b, customer_pii("ลูกค้า บี", Some("0899999999"))),
                // C has no `contact_phone` and identity resolved nothing either — profile returns
                // `phone: null`, so there is no PromptPay destination at all.
                (cust_c, customer_pii("ลูกค้า ซี", None)),
                // D's phone was saved with the country code. Digits-only it is `0066812345678` —
                // THIRTEEN digits. SCB stamps a proxy type from the length alone, so this would have
                // gone out as a `NAT` credit to the citizen who really owns that id: irreversible,
                // with D's obligation marked `processed` and D no longer even visible in the queue.
                (cust_d, customer_pii("ลูกค้า ดี", Some("0066-81-234-5678"))),
            ]
            .into_iter()
            .collect(),
            // Deliberately UNSET: a refund file emits no certificate, so it must build with no
            // company tax block whatsoever. If the export ever starts reading org-settings, this
            // test fails — which is the intent.
            org: None,
        };
        let app = Router::new()
            .route(
                "/admin/refunds/export",
                post(crate::api::refunds::export::<TestDeps>),
            )
            .route(
                "/admin/refunds/preview",
                get(crate::api::refunds::preview::<TestDeps>),
            )
            .with_state(TestDeps {
                dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
                db: db.clone(),
                redis,
                reader: StubReader {
                    booking: Some(payable_booking(Uuid::new_v4())),
                },
                verifier: StubVerifier::ok(sample_verified("0140315796")),
                profile,
                s3: stub_s3(),
                slip_config: sim_config(),
            });
        let admin = customer_token(Uuid::new_v4(), "admin");

        // ── PREVIEW first: it is what the admin ticks from, and it must describe exactly the backlog
        //    the export then writes.
        let preview: serde_json::Value = {
            let res = app
                .clone()
                .oneshot(
                    Request::builder()
                        .uri("/admin/refunds/preview")
                        .header("authorization", format!("Bearer {admin}"))
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap();
            assert_eq!(res.status(), StatusCode::OK);
            let bytes = axum::body::to_bytes(res.into_body(), 1024 * 1024)
                .await
                .expect("body");
            serde_json::from_slice(&bytes).expect("json")
        };
        let excluded = preview["data"]["excluded"]
            .as_array()
            .expect("excluded array");
        let c_row = excluded
            .iter()
            .find(|e| e["customer_id"] == serde_json::json!(cust_c.to_string()))
            .unwrap_or_else(|| panic!("customer C must be excluded: {preview}"));
        assert!(
            c_row["reason"]
                .as_str()
                .is_some_and(|r| r.contains("พร้อมเพย์")),
            "the reason names the missing destination, in Thai: {c_row}"
        );
        // …and D — whose phone EXISTS but is not a Thai mobile — is excluded too, with a reason that
        // tells the admin to CORRECT the number rather than to chase the customer.
        let d_row = excluded
            .iter()
            .find(|e| e["customer_id"] == serde_json::json!(cust_d.to_string()))
            .unwrap_or_else(|| panic!("customer D must be excluded: {preview}"));
        assert!(
            d_row["reason"].as_str().is_some_and(|r| r.contains("มือถือ")),
            "a 13-digit stored phone must be refused as a destination, in Thai: {d_row}"
        );
        assert!(
            !preview["data"]["recipients"]
                .as_array()
                .expect("recipients")
                .iter()
                .any(|r| r["customer_id"] == serde_json::json!(cust_d.to_string())),
            "a customer whose phone cannot receive PromptPay is never a recipient: {preview}"
        );
        // The proxy is PII and this is a list screen — it is masked to its last 4.
        let a_preview = preview["data"]["recipients"]
            .as_array()
            .expect("recipients")
            .iter()
            .find(|r| r["customer_id"] == serde_json::json!(cust_a.to_string()))
            .unwrap_or_else(|| panic!("customer A is refundable: {preview}"))
            .clone();
        assert_eq!(a_preview["amount"], serde_json::json!("2780.00"));
        assert_eq!(a_preview["obligation_count"], serde_json::json!(2));
        assert_eq!(a_preview["proxy_masked"], serde_json::json!("******5678"));

        // ── EXPORT, ticking A, B, C and D. C and D are unrefundable and must simply drop out —
        //    including from the paid-markers, which are built from the same filtered pass.
        let res = export_retrying_ref_collision(
            &app,
            "/admin/refunds/export",
            &admin,
            format!(r#"{{"customer_ids":["{cust_a}","{cust_b}","{cust_c}","{cust_d}"]}}"#),
        )
        .await;
        assert_eq!(res.status(), StatusCode::OK, "the batch generates");
        let bytes = axum::body::to_bytes(res.into_body(), 256 * 1024)
            .await
            .expect("body");
        let file = String::from_utf8(bytes.to_vec()).expect("UTF-8, no BOM");
        let lines: Vec<&str> = file.split("\r\n").collect();

        // NO CERTIFICATE ANYWHERE. A refund is returned capital, not assessable income — issuing a
        // ภ.ง.ด. for it would be a wrong government filing, and this is exactly the kind of thing a
        // future refactor "restores for completeness".
        assert!(
            !file.contains("WHTCER") && !file.contains("WHTDET"),
            "a refund file must carry no withholding records at all: {file}"
        );
        // HEADER + BCHDET + one TXNDET per refundable customer + TRAILR.
        assert_eq!(lines.len(), 5, "two customers ride ONE file: {file}");
        let credits: Vec<Vec<&str>> = lines
            .iter()
            .filter(|l| l.starts_with("TXNDET"))
            .map(|l| l.split('|').collect())
            .collect();
        assert_eq!(credits.len(), 2, "one credit line PER REFUNDABLE CUSTOMER");

        let by_proxy = |proxy: &str| -> Vec<&str> {
            credits
                .iter()
                .find(|c| c[2] == proxy)
                .unwrap_or_else(|| panic!("no credit for {proxy} in {file}"))
                .clone()
        };
        // A: 640.00 (lane A) + 2140.00 (lane B) = 2780.00 in ONE credit line, addressed by the
        // registration phone as a 10-digit `MOB` proxy.
        let a = by_proxy("0812345678");
        assert_eq!(a[3], "MOB", "a customer is refunded on their phone");
        assert_eq!(a[6], "2780.00", "BOTH lanes summed into one transfer");
        assert_eq!(a[13], "ลูกค้า เอ");
        assert_eq!(a[17], "N", "no withholding flag");
        assert_eq!(a[19], "", "…and no withheld amount");
        assert!(
            a[1].starts_with("RF"),
            "the refund stream's own transaction-ref prefix keeps it distinct from a payout \
             generated in the same second: {a:?}"
        );
        let b = by_proxy("0899999999");
        assert_eq!(b[6], "500.00", "customer B's duplicate transfer alone");

        let bch: Vec<&str> = lines[1].split('|').collect();
        assert_eq!(bch[6], "3280.00", "batch total = 2780.00 + 500.00");
        assert_eq!(bch[7], "2", "two credits in the batch");
        let trailer: Vec<&str> = lines[4].split('|').collect();
        assert_eq!(trailer[3], "3280.00", "the trailer agrees with the batch");

        // ── THE QUEUE IS ACTUALLY DRAINED — the thing that never used to happen.
        for id in [pay_a1] {
            let status: Option<String> =
                sqlx::query_scalar("SELECT refund_status FROM payment.payments WHERE id = $1")
                    .bind(id)
                    .fetch_one(&db)
                    .await
                    .expect("read");
            assert_eq!(status.as_deref(), Some("processed"), "lane A closed");
        }
        for id in [slip_a, slip_b] {
            let status: Option<String> =
                sqlx::query_scalar("SELECT refund_status FROM payment.payment_slips WHERE id = $1")
                    .bind(id)
                    .fetch_one(&db)
                    .await
                    .expect("read");
            assert_eq!(status.as_deref(), Some("processed"), "lane B closed");
        }
        // …and the EXCLUDED customer's money is untouched: still owed, still visible in the queue.
        for (label, id) in [("C (no phone)", pay_c), ("D (13-digit phone)", pay_d)] {
            let status: Option<String> =
                sqlx::query_scalar("SELECT refund_status FROM payment.payments WHERE id = $1")
                    .bind(id)
                    .fetch_one(&db)
                    .await
                    .expect("read");
            assert_eq!(
                status.as_deref(),
                Some("pending"),
                "excluded customer {label} must NEVER be marked refunded — that would lose their money"
            );
            let marked: i64 = sqlx::query_scalar(
                "SELECT count(*) FROM payment.refund_batch_items \
                  WHERE source_kind = 'payment' AND source_id = $1",
            )
            .bind(id)
            .fetch_one(&db)
            .await
            .expect("count markers");
            assert_eq!(marked, 0, "excluded customer {label} contributes NO item");
        }

        // ── a SECOND export of the same tick-list has nothing left to send.
        let again = export_retrying_ref_collision(
            &app,
            "/admin/refunds/export",
            &admin,
            format!(r#"{{"customer_ids":["{cust_a}","{cust_b}"]}}"#),
        )
        .await;
        assert_eq!(
            again.status(),
            StatusCode::BAD_REQUEST,
            "the backlog is empty — no second file, and certainly no second transfer"
        );

        // Clean up everything this test wrote.
        let batch_ids: Vec<Uuid> = sqlx::query_scalar(
            "SELECT DISTINCT batch_id FROM payment.refund_batch_items WHERE booking_id = ANY($1)",
        )
        .bind(&bookings[..])
        .fetch_all(&db)
        .await
        .unwrap_or_default();
        let _ = sqlx::query("DELETE FROM payment.money_audit WHERE target_id = ANY($1)")
            .bind(&batch_ids)
            .execute(&db)
            .await;
        let _ = sqlx::query("DELETE FROM payment.scb_file_refs WHERE batch_id = ANY($1)")
            .bind(&batch_ids)
            .execute(&db)
            .await;
        let _ = sqlx::query("DELETE FROM payment.refund_batches WHERE id = ANY($1)")
            .bind(&batch_ids)
            .execute(&db)
            .await;
        let _ = sqlx::query("DELETE FROM payment.payment_slips WHERE booking_id = ANY($1)")
            .bind(&bookings[..])
            .execute(&db)
            .await;
        let _ = sqlx::query(
            "DELETE FROM payment.outbox WHERE payload->'payload'->>'booking_id' = ANY($1)",
        )
        .bind(bookings.iter().map(|b| b.to_string()).collect::<Vec<_>>())
        .execute(&db)
        .await;
        let _ = sqlx::query("DELETE FROM payment.payments WHERE booking_id = ANY($1)")
            .bind(&bookings[..])
            .execute(&db)
            .await;
    }
}

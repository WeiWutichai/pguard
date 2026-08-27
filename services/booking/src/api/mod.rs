//! API layer — thin Axum transport handlers. No business logic beyond role gating +
//! orchestration of `repo`; the state machine + event mapping live in `domain` (pure),
//! and the atomic status+outbox write lives in `repo::transition`.
//!
//! Handlers are generic over [`BookingDeps`] so the `AuthUser` guard is unit-testable
//! with a lightweight state (no live DB/NATS), mirroring notification's seam pattern.

use axum::extract::{Multipart, Path, Query, State};
use axum::Json;
use chrono::{TimeDelta, Utc};
use uuid::Uuid;

use futures::StreamExt;

use shared::auth::AuthUser;
use shared::error::AppError;
use shared::models::ApiResponse;
use shared::service_jwt::ServiceCaller;

use crate::discovery_client::{
    BusyGuardsReader, CatalogGuard, GuardCatalog, PresenceReader, RatingReader,
};
use crate::domain::progress;
use crate::domain::state::BookingStatus;
use crate::domain::{
    validate_cancellation, validate_cancellation_fee, validate_commission_percent, Cancellation,
    PricingSnapshot, ReasonSet,
};
use crate::models::{
    AdminListBookingsQuery, AssignGuardRequest, AvailableGuard, AvailableGuardsQuery,
    BookingResponse, BookingsReport, CancelBookingRequest, CreateBookingRequest,
    CreateServiceRequest, CustomerBookingStat, DeclineBookingRequest, InternalBooking,
    ListProgressReportsQuery, NewProgressReport, OpenJobsQuery, OverdueCheckinsQuery,
    OverdueCheckinsResponse, ProgressReportResponse, PublicServiceItem, ReportRangeQuery,
    RetentionPoint, ReviewCompletionRequest, ServiceCatalogItem, StartJobRequest,
    UpdateServiceRequest,
};
use crate::repo;
use crate::state::{BookingDeps, BookingInternalDeps, DiscoveryDeps};

/// Max concurrent rating-summary lookups when building the discovery list (bounds fan-out
/// to the rating service while keeping the page snappy).
const MAX_CONCURRENT_RATING: usize = 8;

/// Upper bound on a single booking's duration (defensive against absurd values flowing
/// into proration/payment).
const MAX_BOOKING_HOURS: i32 = 168; // 1 week
/// Guard-count bounds (mirror the DB CHECK + v1's 1..=20).
const MAX_GUARD_COUNT: i32 = 20;

/// Upper bound on the customer-supplied booking `address` (deep-review MED #10). Counted in
/// CHARACTERS (`chars().count()`, not bytes — Thai is multi-byte, so a byte cap would give Thai
/// users a third of the room; mirrors `domain::cancellation::MAX_CANCELLATION_NOTE_CHARS`). The
/// address fans out to every discovering guard and into the `booking.requested` event, so an
/// unbounded one is an amplification vector; the DB `chk_bookings_address_len` is the backstop.
const MAX_ADDRESS_CHARS: usize = 512;

/// Upper bound on the customer-supplied `tip` (deep-review LOW #33). The tip column is
/// `NUMERIC(12,2)` (max 9,999,999,999.99); an uncapped value ≥ 10^10 passes handler validation
/// then overflows the column (Postgres 22003) and surfaces as an opaque 500 instead of a typed
/// 400. Mirrors `MAX_SERVICE_BASE_FEE` / `domain::pricing::MAX_CANCELLATION_FEE`.
const MAX_TIP: i64 = 1_000_000;

/// Check-in multipart body cap — a little above the 10MB photo limit for multipart framing;
/// `domain::progress::validate_photo_upload` is the precise per-photo check. Set as
/// `DefaultBodyLimit` on the progress-reports route in main.rs (Axum's default is ~2MB).
pub const MAX_CHECK_IN_BODY_BYTES: usize = 12 * 1024 * 1024;

/// House limit/offset pagination (chat/rating/notification convention: default 50, max 200).
const DEFAULT_PAGE_LIMIT: i64 = 50;
const MAX_PAGE_LIMIT: i64 = 200;

/// Clamp optional limit/offset query params to the house bounds.
fn page(limit: Option<i64>, offset: Option<i64>) -> (i64, i64) {
    (
        limit.unwrap_or(DEFAULT_PAGE_LIMIT).clamp(1, MAX_PAGE_LIMIT),
        offset.unwrap_or(0).max(0),
    )
}

const ROLE_GUARD: &str = "guard";
const ROLE_CUSTOMER: &str = "customer";
const ROLE_ADMIN: &str = "admin";

/// Gate a handler to a broad role (or admin). The repo then enforces the SPECIFIC owner
/// (assigned-guard / request-owner) inside the row lock — this is only the coarse role check.
fn require_role(user: &AuthUser, role: &str) -> Result<bool, AppError> {
    let is_admin = user.role == ROLE_ADMIN;
    if user.role != role && !is_admin {
        return Err(AppError::Forbidden(format!("Only {role}s can do this")));
    }
    Ok(is_admin)
}

/// Transition a booking to `new_status` on behalf of `actor`. `repo::transition` enforces,
/// inside the row-locked tx, that `actor` is the actor the transition requires (assigned guard
/// / request owner; `is_admin` overrides). A fresh correlation id is generated for the event.
async fn do_transition<S: BookingDeps>(
    state: &S,
    id: Uuid,
    actor: Uuid,
    is_admin: bool,
    new_status: BookingStatus,
    assign_guard: Option<Uuid>,
    cancellation: Option<Cancellation>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    let booking = repo::transition(
        state.db(),
        id,
        actor,
        is_admin,
        new_status,
        assign_guard,
        cancellation,
        Uuid::new_v4(),
    )
    .await?;
    Ok(Json(ApiResponse::success(booking)))
}

/// POST /bookings — a customer creates a booking request (status = requested).
#[tracing::instrument(skip(state, req), fields(user = %user.user_id))]
pub async fn create_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Json(req): Json<CreateBookingRequest>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    if user.role != "customer" {
        return Err(AppError::Forbidden(
            "Only customers can create bookings".to_string(),
        ));
    }
    // Address: required + bounded (deep-review MED #10). Non-empty after trim (an all-whitespace
    // address is no address), and capped in CHARACTERS so a ~1 MB TEXT can't fan out to every
    // guard / into the booking.requested event. Both are typed 400s.
    if req.address.trim().is_empty() {
        return Err(AppError::BadRequest("address is required".to_string()));
    }
    if req.address.chars().count() > MAX_ADDRESS_CHARS {
        return Err(AppError::BadRequest(format!(
            "address must be at most {MAX_ADDRESS_CHARS} characters"
        )));
    }
    if req.hours <= 0 || req.hours > MAX_BOOKING_HOURS {
        return Err(AppError::BadRequest(format!(
            "hours must be between 1 and {MAX_BOOKING_HOURS}"
        )));
    }
    // Pricing inputs: default guard_count → 1, tip → 0. Validate before persisting so the
    // money path (expected_total = base_fee × hours × guard_count + tip) never sees junk.
    let guard_count = req.guard_count.unwrap_or(1);
    if !(1..=MAX_GUARD_COUNT).contains(&guard_count) {
        return Err(AppError::BadRequest(format!(
            "guard_count must be between 1 and {MAX_GUARD_COUNT}"
        )));
    }
    let tip = req.tip.unwrap_or(rust_decimal::Decimal::ZERO);
    if tip < rust_decimal::Decimal::ZERO {
        return Err(AppError::BadRequest("tip must not be negative".to_string()));
    }
    // Upper-bound the tip BEFORE it reaches the NUMERIC(12,2) column: an uncapped ≥ 10^10 value
    // overflows to an opaque 500 (deep-review LOW #33). Then normalize to the money 2dp
    // convention so what is stored/echoed matches every other money field.
    if tip > rust_decimal::Decimal::from(MAX_TIP) {
        return Err(AppError::BadRequest(format!(
            "tip must be at most {MAX_TIP}"
        )));
    }
    let tip = crate::domain::money_scale(tip);
    // Scheduled time must be in the FUTURE (C4) — server-authoritative (the customer's device
    // clock is never trusted). A past/now `scheduled_at` is 400 `SCHEDULED_IN_PAST`.
    crate::domain::scheduling::validate_scheduled_at(req.scheduled_at, Utc::now())?;
    // Optional site coordinates: both-or-neither, in range (feeds open-job radius discovery).
    progress::validate_coords(req.lat, req.lng)?;
    // Optional catalog service: when picked, the booking's money is resolved SERVER-SIDE from
    // the active catalog entry (never the client body — never trust a client-sent fee), and the
    // service's min_hours floor is enforced. Absent → base_fee falls to the column DEFAULT
    // (back-compat, unchanged) and the snapshot is 0/0. A missing/inactive service id is 404.
    //
    // The commission + cancellation fee are SNAPSHOT here, not looked up later: the catalog is
    // admin-editable, and a booking's terms must be the ones in force the moment it was made.
    let pricing = match req.service_id {
        None => None,
        Some(service_id) => {
            let service = repo::get_active_service(state.db(), service_id)
                .await?
                .ok_or_else(|| AppError::NotFound("Service not found or inactive".to_string()))?;
            if req.hours < service.min_hours {
                return Err(AppError::BadRequest(format!(
                    "hours must be at least {} (below the service minimum)",
                    service.min_hours
                )));
            }
            Some(PricingSnapshot {
                base_fee: service.base_fee,
                commission_percent: service.commission_percent,
                cancellation_fee: service.cancellation_fee,
            })
        }
    };
    // A fresh correlation id threads the booking.requested event (atomic with the insert via
    // the outbox) through the relay → NATS → notification (data-push to online guards).
    let booking = repo::create_booking(
        state.db(),
        user.user_id,
        &req,
        guard_count,
        tip,
        pricing,
        Uuid::new_v4(),
    )
    .await?;
    Ok(Json(ApiResponse::success(booking)))
}

/// POST /bookings/{id}/accept — a guard accepts → status = accepted, guard_id = caller.
/// Enqueues `pguard.events.booking.job_accepted` in the same transaction (outbox).
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn accept_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    let is_admin = require_role(&user, ROLE_GUARD)?;
    // A guard may hold multiple jobs, but never two that OVERLAP in time (a physical guard is at one
    // place at a time; 9–18 then 19–22 is fine, a second 9–18 is not). Reject an accept that overlaps
    // an assignment this guard already holds. Admins act on behalf, so they bypass.
    if !is_admin && repo::guard_has_overlapping_active_job(state.db(), user.user_id, id).await? {
        return Err(AppError::ConflictCode {
            code: "GUARD_BUSY",
            message: "You already have a job during this time window — pick a non-overlapping one."
                .to_string(),
        });
    }
    do_transition(
        &state,
        id,
        user.user_id,
        is_admin,
        BookingStatus::Accepted,
        Some(user.user_id),
        None,
    )
    .await
}

/// PUT /bookings/{id}/decline — the ASSIGNED guard withdraws after accepting → declined.
///
/// The body carries a MANDATORY reason from the GUARD code set (`emergency` | `sick` |
/// `cannot_reach` | `other`); a customer code is a 400 `CANCEL_REASON_REQUIRED`, and `other`
/// additionally requires a note (`CANCEL_NOTE_REQUIRED`). The customer is told WHY their guard
/// withdrew — and a paid pre-arrival withdraw is full-refunded — so the reason is not optional
/// UX polish: it is the record behind the refund.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, booking_id = %id))]
pub async fn decline_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(req): Json<DeclineBookingRequest>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    let is_admin = require_role(&user, ROLE_GUARD)?;
    let cancellation = validate_cancellation(
        ReasonSet::GuardDecline,
        req.reason.as_deref(),
        req.note.as_deref(),
    )?;
    do_transition(
        &state,
        id,
        user.user_id,
        is_admin,
        BookingStatus::Declined,
        None,
        Some(cancellation),
    )
    .await
}

/// PUT /bookings/{id}/en-route — the assigned guard is en route (outbox event).
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn en_route_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    let is_admin = require_role(&user, ROLE_GUARD)?;
    do_transition(
        &state,
        id,
        user.user_id,
        is_admin,
        BookingStatus::EnRoute,
        None,
        None,
    )
    .await
}

/// PUT /bookings/{id}/arrived — the assigned guard has arrived at the site (outbox event).
///
/// PROXIMITY-GATED (G4): the OPTIONAL JSON body carries the guard's GPS fix for the 120m arrive
/// geofence (`domain::geo`, enforced inside the repo's row lock via `repo::arrive_job`). Same
/// `Option<Json<..>>` shape + coord validation as [`start_booking`]: an old build's empty body
/// (no JSON content-type) extracts as `None` → no fix, which 409s `GPS_REQUIRED` on a pinned
/// booking (fail closed) and passes on a legacy address-only one; a far fix is 409 `NOT_AT_SITE`.
/// Admin bypasses the fence. Coordinates are validated here (both-or-neither + ranges) so the
/// repo only ever sees a sane pair.
#[tracing::instrument(skip(state, body), fields(user = %user.user_id, booking_id = %id))]
pub async fn arrived_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    body: Option<Json<StartJobRequest>>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    let is_admin = require_role(&user, ROLE_GUARD)?;
    let (guard_gps, accuracy_m) = match body {
        None => (None, None),
        Some(Json(req)) => (progress::validate_coords(req.lat, req.lng)?, req.accuracy_m),
    };
    let booking = repo::arrive_job(
        state.db(),
        id,
        user.user_id,
        is_admin,
        guard_gps,
        accuracy_m,
        Uuid::new_v4(),
    )
    .await?;
    Ok(Json(ApiResponse::success(booking)))
}

/// PUT /bookings/{id}/start — the assigned guard starts the job (stamps `work_started_at`,
/// the proration basis). Status stays `arrived`; no event.
///
/// The OPTIONAL JSON body carries the guard's GPS fix for the 50m start geofence
/// (`domain::geo`, enforced inside the repo's row lock). `Option<Json<..>>`: an old app
/// build's empty body (no JSON content-type) extracts as `None` → no fix — which still
/// 409s `GPS_REQUIRED` on a pinned booking (fail closed) and passes on a legacy
/// address-only one. Coordinates are validated here (both-or-neither + ranges, the same
/// `validate_coords` as create-booking) so the repo only ever sees a sane pair.
#[tracing::instrument(skip(state, body), fields(user = %user.user_id, booking_id = %id))]
pub async fn start_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    body: Option<Json<StartJobRequest>>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    let is_admin = require_role(&user, ROLE_GUARD)?;
    let (guard_gps, accuracy_m) = match body {
        None => (None, None),
        Some(Json(req)) => (progress::validate_coords(req.lat, req.lng)?, req.accuracy_m),
    };
    let booking = repo::start_job(
        state.db(),
        id,
        user.user_id,
        is_admin,
        guard_gps,
        accuracy_m,
    )
    .await?;
    Ok(Json(ApiResponse::success(booking)))
}

/// PUT /bookings/{id}/complete — the assigned guard REQUESTS completion → `pending_completion`
/// (the customer then reviews). The job must have been started. No event yet.
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn complete_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    let is_admin = require_role(&user, ROLE_GUARD)?;
    do_transition(
        &state,
        id,
        user.user_id,
        is_admin,
        BookingStatus::PendingCompletion,
        None,
        None,
    )
    .await
}

/// PUT /bookings/{id}/review-completion — the CUSTOMER reviews the guard's completion request:
/// `approve` → completed (emits `booking.completed` → payment proration) or `reject` → arrived
/// (the guard finishes the job).
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, booking_id = %id))]
pub async fn review_completion<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(req): Json<ReviewCompletionRequest>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    let is_admin = require_role(&user, ROLE_CUSTOMER)?;
    let target = match req.action.as_str() {
        "approve" => BookingStatus::Completed,
        "reject" => BookingStatus::Arrived,
        _ => {
            return Err(AppError::BadRequest(
                "action must be 'approve' or 'reject'".to_string(),
            ))
        }
    };
    do_transition(&state, id, user.user_id, is_admin, target, None, None).await
}

/// PUT /bookings/{id}/cancel — the customer (or admin) cancels a PRE-ARRIVAL booking → cancelled.
///
/// The body carries a MANDATORY reason from the CUSTOMER code set (`changed_plan` | `mistake` |
/// `not_needed` | `other`); a guard code is a 400 `CANCEL_REASON_REQUIRED`, and `other`
/// additionally requires a note (`CANCEL_NOTE_REQUIRED`). A paid pre-arrival cancel is
/// full-refunded by payment's cancellation consumer, so the reason is the record behind the money.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, booking_id = %id))]
pub async fn cancel_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(req): Json<CancelBookingRequest>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    let is_admin = require_role(&user, ROLE_CUSTOMER)?;
    let cancellation = validate_cancellation(
        ReasonSet::CustomerCancel,
        req.reason.as_deref(),
        req.note.as_deref(),
    )?;
    do_transition(
        &state,
        id,
        user.user_id,
        is_admin,
        BookingStatus::Cancelled,
        None,
        Some(cancellation),
    )
    .await
}

/// PUT /bookings/{id}/cancel-after-decline — the CUSTOMER acknowledges a guard withdrawal (E).
///
/// When the assigned guard withdraws pre-arrival the booking goes to terminal `declined` (with
/// the guard's decline reason already recorded on the row and already delivered on the
/// `booking.declined` event). The customer must be able to ACK that into terminal `cancelled` so
/// "both parties done" is a real end state — otherwise their live screen sits on a `declined` job
/// with no forward action (a redirect loop). The state machine special-cases this ONE edge out of
/// an otherwise-terminal status (`required_actor(Declined, Cancelled) = RequestOwner`).
///
/// This is a pure ACK, NOT a customer cancellation: it carries NO reason from the client and
/// passes `None` cancellation, so the transition's `COALESCE` deliberately PRESERVES the guard's
/// decline reason/note (they "already stand" as the authoritative record of why the job did not
/// happen — overwriting them would leave a mismatched reason/note pair). It only flips the status
/// and emits `booking.cancelled`. That event reaches payment's cancellation consumer, which only
/// refunds a `completed` row — the earlier `booking.declined` already issued any refund, so this
/// second event is a NoOp (no double refund).
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn cancel_after_decline<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    let is_admin = require_role(&user, ROLE_CUSTOMER)?;
    do_transition(
        &state,
        id,
        user.user_id,
        is_admin,
        BookingStatus::Cancelled,
        None,
        None,
    )
    .await
}

/// GET /bookings/{id} — fetch one booking the caller participates in.
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn get_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    let booking = repo::get_booking(state.db(), id).await?;
    let is_participant =
        booking.customer_id == user.user_id || booking.guard_id == Some(user.user_id);
    // An OPEN job (unassigned + still `requested`) is already guard-discoverable via
    // `GET /bookings/open`, so any guard may read its detail to decide whether to accept — without
    // this, tapping an incoming job before accepting 403s ("Not a participant"). Once a guard claims
    // it (guard_id set) or it leaves `requested`, only the participants can read it.
    //
    // DIRECTED OFFER (C3, deep-review LOW #27/#28): a booking targeted at ONE guard must stay
    // confined to that guard — discovery hides it and `accept` 403s a non-target, but the detail
    // read used to leak the customer's address/coords/schedule to ANY guard who knew the UUID. So
    // a directed booking is "open-readable" ONLY by its own target; an undirected (truly open)
    // requested booking stays readable by any guard, as before.
    let is_open_for_guard = user.role == ROLE_GUARD
        && booking.guard_id.is_none()
        && booking.status == "requested"
        && (booking.target_guard_id.is_none() || booking.target_guard_id == Some(user.user_id));
    if !is_participant && !is_open_for_guard {
        return Err(AppError::Forbidden(
            "Not a participant in this booking".to_string(),
        ));
    }
    Ok(Json(ApiResponse::success(booking)))
}

/// GET /bookings — list the caller's bookings (as customer or assigned guard).
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn list_bookings<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<BookingResponse>>>, AppError> {
    // List read → replica (C5.3). Single-booking get_booking stays on the primary (it can be
    // a read-after-write).
    let items = repo::list_bookings(state.db_read(), user.user_id).await?;
    Ok(Json(ApiResponse::success(items)))
}

/// GET /bookings/open — open-job discovery: `requested` bookings with no guard yet, which
/// the calling guard can claim via accept. Guard-only (admin may browse — a read-only
/// moderation view). Optional `lat`/`lng`/`radius_km` geo filter (validated in pure
/// domain); without coordinates the list is newest-first. A SEPARATE endpoint —
/// `GET /bookings` (the participant list) keeps its exact semantics.
#[tracing::instrument(skip(state, query), fields(user = %user.user_id))]
pub async fn list_open_bookings<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(query): Query<OpenJobsQuery>,
) -> Result<Json<ApiResponse<Vec<BookingResponse>>>, AppError> {
    require_role(&user, ROLE_GUARD)?;
    let geo = progress::validate_open_jobs_query(query.lat, query.lng, query.radius_km)?;
    let (limit, offset) = page(query.limit, query.offset);
    // Discovery is a pure list read → replica (C5.3), like list_bookings. Excludes jobs THIS guard
    // has skipped so a passed-on offer doesn't keep reappearing.
    let items = repo::list_open_bookings(state.db_read(), user.user_id, geo, limit, offset).await?;
    Ok(Json(ApiResponse::success(items)))
}

/// POST /bookings/{id}/skip — the guard PASSES on an open offer. Server-tracked so discovery stops
/// re-offering it to THIS guard; the booking stays open for others (NOT a cancellation).
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn skip_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    require_role(&user, ROLE_GUARD)?;
    repo::skip_job(state.db(), user.user_id, id).await?;
    Ok(Json(ApiResponse::success(
        serde_json::json!({ "skipped": true }),
    )))
}

/// GET /admin/bookings — admin cross-user booking list (optional `status`/`search`/`guard_id`/
/// `customer_id` filters, paginated). Admin-only. Unlike `GET /bookings` (the caller's participant
/// list) this drops the owner scope entirely; `guard_id`/`customer_id` are explicit drill-downs
/// into one guard's jobs or one customer's bookings. List read → replica (C5.3). NOTE: booking has no PDPA read-audit
/// table yet — the addresses exposed here are lower-sensitivity than profile's bank numbers;
/// an equivalent §30 audit is a tracked follow-up (needs a booking access_audit migration).
#[tracing::instrument(skip(state, query), fields(user = %user.user_id))]
pub async fn admin_list_bookings<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(query): Query<AdminListBookingsQuery>,
) -> Result<Json<ApiResponse<Vec<BookingResponse>>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    // Validate the status filter against the enum (unknown → 400, never a raw enum cast 500).
    let status = match query.status.as_deref() {
        None => None,
        Some(s) => Some(
            s.parse::<BookingStatus>()
                .map_err(|_| AppError::BadRequest("invalid status filter".to_string()))?,
        ),
    };
    let (limit, offset) = page(query.limit, query.offset);
    let items = repo::admin_list_bookings(
        state.db_read(),
        status,
        query.search.as_deref(),
        query.guard_id,
        query.customer_id,
        limit,
        offset,
    )
    .await?;
    Ok(Json(ApiResponse::success(items)))
}

/// Default analytics window when `from`/`to` are omitted, and the hard cap on its length.
const REPORT_DEFAULT_DAYS: i64 = 30;
const REPORT_MAX_DAYS: i64 = 366;

/// Resolve the `[from, to)` analytics window: default last 30 days ending now; clamp so it
/// never exceeds a year (bounds the aggregation scan). Mirrors payment's `report_range`.
fn report_range(q: &ReportRangeQuery) -> (chrono::DateTime<Utc>, chrono::DateTime<Utc>) {
    let to = q.to.unwrap_or_else(Utc::now);
    let from = q
        .from
        .unwrap_or_else(|| to - TimeDelta::days(REPORT_DEFAULT_DAYS));
    let earliest = to - TimeDelta::days(REPORT_MAX_DAYS);
    (from.max(earliest).min(to), to)
}

/// GET /admin/reports/bookings?from=&to= — composite booking analytics (volume trend +
/// utilization heatmap + retention cohort). Admin only; replica read (pure analytics).
#[tracing::instrument(skip(state, q), fields(user = %user.user_id))]
pub async fn admin_bookings_report<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<ReportRangeQuery>,
) -> Result<Json<ApiResponse<BookingsReport>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    let (from, to) = report_range(&q);
    let daily = repo::bookings_daily(state.db_read(), from, to).await?;
    let utilization = repo::utilization(state.db_read(), from, to).await?;
    let (base, w1, w2, w4, w8, w12) = repo::retention_counts(state.db_read(), from, to).await?;
    let pct = |n: i64| {
        if base == 0 {
            0.0
        } else {
            (n as f64) / (base as f64) * 100.0
        }
    };
    let retention = vec![
        RetentionPoint {
            week: 0,
            pct: if base == 0 { 0.0 } else { 100.0 },
        },
        RetentionPoint {
            week: 1,
            pct: pct(w1),
        },
        RetentionPoint {
            week: 2,
            pct: pct(w2),
        },
        RetentionPoint {
            week: 4,
            pct: pct(w4),
        },
        RetentionPoint {
            week: 8,
            pct: pct(w8),
        },
        RetentionPoint {
            week: 12,
            pct: pct(w12),
        },
    ];
    let total = daily.iter().map(|d| d.count).sum();
    Ok(Json(ApiResponse::success(BookingsReport {
        daily,
        utilization,
        retention,
        total,
    })))
}

/// GET /admin/reports/customer-bookings — per-customer lifetime booking aggregates (total /
/// completed / cancelled) for the web-admin customers page. Admin only; replica read (pure
/// aggregation). No window param — this is the lifetime-per-customer view.
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn admin_customer_bookings_report<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<CustomerBookingStat>>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    let stats = repo::customer_booking_stats(state.db_read()).await?;
    Ok(Json(ApiResponse::success(stats)))
}

/// GET /admin/checkins/overdue — active jobs whose next scheduled hourly check-in is OVERDUE
/// (the dashboard "เช็คอินที่ขาด" / missed-check-ins alert). A job is in progress when
/// `status = 'arrived'` AND `work_started_at` is stamped; hour `N` opens at
/// `work_started_at + (N−1)h`. Each row is a job with ≥ 1 owed-but-unfiled past-due hour:
/// `due_at` is the oldest such gap's open time, `missed_count` how many gaps. `total` is the
/// count of ALL such jobs (independent of the page) for the alert badge. Admin only (else 403);
/// list read → replica (pure cross-user aggregation). House limit/offset pagination,
/// oldest-overdue first.
#[tracing::instrument(skip(state, query), fields(user = %user.user_id))]
pub async fn admin_overdue_checkins<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(query): Query<OverdueCheckinsQuery>,
) -> Result<Json<ApiResponse<OverdueCheckinsResponse>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    let (limit, offset) = page(query.limit, query.offset);
    let items = repo::overdue_checkins(state.db_read(), limit, offset).await?;
    let total = repo::overdue_checkins_count(state.db_read()).await?;
    Ok(Json(ApiResponse::success(OverdueCheckinsResponse {
        items,
        total,
    })))
}

/// POST /admin/bookings/{id}/assign — an admin assigns a guard to an UNASSIGNED `requested`
/// booking. It lands in `accepted` with `guard_id` set (the same end-state as a guard
/// self-accept), firing `pguard.events.booking.job_accepted` atomically via the outbox (the
/// notification consumer routes it to the guard). Admin-only. A booking that already has a
/// guard returns 409 (the repo's ClaimUnassigned conflict) — reassignment is out of scope (a
/// separate transition class + a displaced-guard event). NOTE: the target `guard_id` is NOT
/// validated to be a real approved guard here — the web-admin sends ids from the admin guard
/// list; a point-lookup validation is a follow-up (it needs a profile `/internal/guards/{id}`
/// endpoint — the existing catalog list is capped at 100, so membership checks are unsafe).
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, booking_id = %id))]
pub async fn admin_assign_guard<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(req): Json<AssignGuardRequest>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    // Admin is the ACTOR, but the assigned guard is the request's target (not the actor): the
    // Requested→Accepted (ClaimUnassigned) transition binds `assign_guard` independently and
    // rejects an already-assigned booking with 409.
    do_transition(
        &state,
        id,
        user.user_id,
        true,
        BookingStatus::Accepted,
        Some(req.guard_id),
        None,
    )
    .await
}

/// GET /services — the customer-facing service picker: ACTIVE catalog services only,
/// projected to the narrow [`PublicServiceItem`] — `notes` is surfaced as the customer-facing
/// package description; `is_active`/timestamps stay admin-only. NOT admin-gated: any authenticated
/// user (the customer booking app) may read it, like the other customer discovery endpoints.
/// List read → replica.
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn list_services<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<PublicServiceItem>>>, AppError> {
    let items = repo::list_active_services(state.db_read()).await?;
    Ok(Json(ApiResponse::success(items)))
}

// ----- Service catalog (admin pricing CRUD; standalone — not wired to the charge path) -----

/// Max base fee a catalog entry may carry (defensive; mirrors the booking pricing bounds).
const MAX_SERVICE_BASE_FEE: i64 = 1_000_000;
const MAX_SERVICE_NOTES_LEN: usize = 2000;

/// Validate the editable fields shared by create + update.
///
/// Returns the NORMALIZED `(commission_percent, cancellation_fee)` — the pure
/// `domain::pricing` validators round both to their columns' 2-dp scale, so the caller must
/// persist what comes back rather than what the admin sent (otherwise Postgres rounds silently
/// and the response echoes a value that is not what was stored). Both are typed 400s
/// (`COMMISSION_PERCENT_INVALID` / `CANCELLATION_FEE_INVALID`) so the admin UI localizes them.
fn validate_service_fields(
    name_th: &str,
    name_en: &str,
    base_fee: rust_decimal::Decimal,
    min_hours: i32,
    notes: Option<&str>,
    commission_percent: rust_decimal::Decimal,
    cancellation_fee: rust_decimal::Decimal,
) -> Result<(rust_decimal::Decimal, rust_decimal::Decimal), AppError> {
    if name_th.trim().is_empty() || name_en.trim().is_empty() {
        return Err(AppError::BadRequest(
            "name_th and name_en are required".to_string(),
        ));
    }
    if base_fee < rust_decimal::Decimal::ZERO
        || base_fee > rust_decimal::Decimal::from(MAX_SERVICE_BASE_FEE)
    {
        return Err(AppError::BadRequest(format!(
            "base_fee must be between 0 and {MAX_SERVICE_BASE_FEE}"
        )));
    }
    if !(1..=24).contains(&min_hours) {
        return Err(AppError::BadRequest(
            "min_hours must be between 1 and 24".to_string(),
        ));
    }
    if notes.is_some_and(|n| n.len() > MAX_SERVICE_NOTES_LEN) {
        return Err(AppError::BadRequest("notes too long".to_string()));
    }
    Ok((
        validate_commission_percent(commission_percent)?,
        validate_cancellation_fee(cancellation_fee)?,
    ))
}

/// GET /admin/pricing/services — list the service catalog (admin). Read → replica.
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn admin_list_services<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<ServiceCatalogItem>>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    let items = repo::list_services(state.db_read()).await?;
    Ok(Json(ApiResponse::success(items)))
}

/// POST /admin/pricing/services — create a catalog service (admin).
#[tracing::instrument(skip(state, req), fields(user = %user.user_id))]
pub async fn admin_create_service<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Json(mut req): Json<CreateServiceRequest>,
) -> Result<Json<ApiResponse<ServiceCatalogItem>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    // Write the NORMALIZED money knobs back onto the request — that is what gets persisted.
    (req.commission_percent, req.cancellation_fee) = validate_service_fields(
        &req.name_th,
        &req.name_en,
        req.base_fee,
        req.min_hours,
        req.notes.as_deref(),
        req.commission_percent,
        req.cancellation_fee,
    )?;
    let item = repo::create_service(state.db(), &req).await?;
    Ok(Json(ApiResponse::success(item)))
}

/// PUT /admin/pricing/services/{id} — replace a catalog service's editable fields (admin).
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, service_id = %id))]
pub async fn admin_update_service<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(mut req): Json<UpdateServiceRequest>,
) -> Result<Json<ApiResponse<ServiceCatalogItem>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    // Same normalization as create. Changing these knobs only affects bookings made AFTER the
    // edit — every existing booking carries its own snapshot (migration 0010).
    (req.commission_percent, req.cancellation_fee) = validate_service_fields(
        &req.name_th,
        &req.name_en,
        req.base_fee,
        req.min_hours,
        req.notes.as_deref(),
        req.commission_percent,
        req.cancellation_fee,
    )?;
    let item = repo::update_service(state.db(), id, &req).await?;
    Ok(Json(ApiResponse::success(item)))
}

/// DELETE /admin/pricing/services/{id} — soft-delete (deactivate) a catalog service (admin).
#[tracing::instrument(skip(state), fields(user = %user.user_id, service_id = %id))]
pub async fn admin_delete_service<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<ServiceCatalogItem>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    let item = repo::deactivate_service(state.db(), id).await?;
    Ok(Json(ApiResponse::success(item)))
}

/// POST /bookings/{id}/progress-reports — the ASSIGNED guard's hourly check-in
/// (multipart: photo + GPS + hour_number + note).
///
/// Order: coarse role gate → participation/assignment pre-flight (BEFORE the multipart body
/// is even buffered — a non-participant never makes the server read a 10MB photo) → parse →
/// state/hour + DUPLICATE-HOUR pre-flight (before the S3 upload, so the designed-for guard
/// retry of an already-filed hour orphans nothing) → photo validation (size before magic
/// bytes) → S3 upload under a SERVER-generated key → atomic insert + outbox. The repo
/// re-validates every gate inside the row lock (authoritative; the pre-flights are
/// advisory), and a race that fails the in-lock re-check triggers a best-effort delete of
/// the just-uploaded object — only a crash in that window can orphan one.
///
/// NO admin bypass: a check-in is the guard's first-person attestation of presence — the
/// coarse gate here rejects every non-guard role (including admin), and the repo enforces
/// `actor == guard_id` strictly.
#[tracing::instrument(skip(state, multipart), fields(user = %user.user_id, booking_id = %id))]
pub async fn create_progress_report<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    multipart: Multipart,
) -> Result<Json<ApiResponse<ProgressReportResponse>>, AppError> {
    if user.role != ROLE_GUARD {
        return Err(AppError::Forbidden(
            "Only the assigned guard can check in".to_string(),
        ));
    }

    // ----- pre-flight (advisory; the repo re-checks inside the row lock) -----
    let core = repo::get_booking_core(state.db(), id).await?;
    if core.customer_id != user.user_id && core.guard_id != Some(user.user_id) {
        return Err(AppError::Forbidden(
            "Not a participant in this booking".to_string(),
        ));
    }
    if core.guard_id != Some(user.user_id) {
        return Err(AppError::Forbidden(
            "Only the assigned guard can check in".to_string(),
        ));
    }

    let form = parse_check_in_form(multipart).await?;

    // State/hour legality + duplicate-hour — both advisory, both BEFORE the S3 upload so
    // rejected attempts (incl. the spec's idempotent guard-retry 409) upload nothing.
    progress::validate_check_in(
        core.status,
        core.work_started_at,
        core.hours,
        form.hour_number,
        chrono::Utc::now(),
    )?;
    if repo::progress_report_exists(state.db(), id, form.hour_number).await? {
        return Err(AppError::ConflictCode {
            code: progress::DUPLICATE_CHECK_IN_CODE,
            message: format!("A check-in for hour {} already exists", form.hour_number),
        });
    }

    // ----- photo validation (size BEFORE magic bytes) + server-generated key + upload -----
    let canonical_mime =
        progress::validate_photo_upload(&form.declared_mime, form.photo.len(), &form.photo)?;
    let ext = progress::mime_to_extension(canonical_mime);
    let photo_key = format!("booking/{id}/checkins/{}.{ext}", Uuid::new_v4());
    state
        .s3()
        .upload(&photo_key, form.photo, canonical_mime)
        .await?;

    // ----- atomic insert + outbox (the authoritative gates re-run inside the tx) -----
    let report = NewProgressReport {
        hour_number: form.hour_number,
        photo_key,
        lat: form.lat,
        lng: form.lng,
        accuracy_m: form.accuracy_m,
        note: form.note,
    };
    let row =
        match repo::create_progress_report(state.db(), id, user.user_id, &report, Uuid::new_v4())
            .await
        {
            Ok(row) => row,
            Err(e) => {
                // A concurrent duplicate / late state change failed the in-lock re-check
                // after we uploaded — compensate so the object doesn't orphan.
                state.s3().delete_best_effort(&report.photo_key).await;
                return Err(e);
            }
        };
    let photo_url = state.s3().download_url(&row.photo_key);
    Ok(Json(ApiResponse::success(
        ProgressReportResponse::from_row(row, photo_url),
    )))
}

/// The parsed + field-validated check-in form (photo buffered, bounded by the route's
/// `DefaultBodyLimit`).
struct CheckInForm {
    hour_number: i32,
    photo: Vec<u8>,
    declared_mime: String,
    lat: Option<f64>,
    lng: Option<f64>,
    accuracy_m: Option<f32>,
    note: Option<String>,
}

/// Parse the check-in multipart parts and run the FIELD-level validations: required
/// hour_number + photo, GPS both-or-neither in range, note trimmed + capped, junk accuracy
/// sanitized to `None` (presence precedent). Booking-level legality stays in the handler.
async fn parse_check_in_form(mut multipart: Multipart) -> Result<CheckInForm, AppError> {
    let mut hour_number: Option<i32> = None;
    let mut photo: Option<Vec<u8>> = None;
    let mut declared_mime: Option<String> = None;
    let mut lat: Option<f64> = None;
    let mut lng: Option<f64> = None;
    let mut accuracy_m: Option<f32> = None;
    let mut note: Option<String> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| AppError::BadRequest(format!("Failed to read multipart: {e}")))?
    {
        match field.name().unwrap_or("") {
            "hour_number" => {
                let text = field
                    .text()
                    .await
                    .map_err(|e| AppError::BadRequest(format!("Invalid hour_number: {e}")))?;
                hour_number = Some(text.trim().parse::<i32>().map_err(|_| {
                    AppError::BadRequest("hour_number must be an integer".to_string())
                })?);
            }
            "lat" => lat = Some(parse_f64_field(field, "lat").await?),
            "lng" => lng = Some(parse_f64_field(field, "lng").await?),
            "accuracy" => {
                let text = field
                    .text()
                    .await
                    .map_err(|e| AppError::BadRequest(format!("Invalid accuracy: {e}")))?;
                accuracy_m =
                    Some(text.trim().parse::<f32>().map_err(|_| {
                        AppError::BadRequest("accuracy must be a number".to_string())
                    })?);
            }
            "note" => {
                let text = field
                    .text()
                    .await
                    .map_err(|e| AppError::BadRequest(format!("Invalid note: {e}")))?;
                let trimmed = text.trim();
                if !trimmed.is_empty() {
                    progress::validate_note(trimmed)?;
                    note = Some(trimmed.to_string());
                }
            }
            "photo" => {
                declared_mime = field.content_type().map(|s| s.to_string());
                photo = Some(
                    field
                        .bytes()
                        .await
                        .map_err(|e| AppError::BadRequest(format!("Failed to read photo: {e}")))?
                        .to_vec(),
                );
            }
            _ => {}
        }
    }

    let hour_number =
        hour_number.ok_or_else(|| AppError::BadRequest("hour_number is required".to_string()))?;
    let photo = photo.ok_or_else(|| AppError::BadRequest("photo is required".to_string()))?;
    let declared_mime = declared_mime.unwrap_or_else(|| "application/octet-stream".to_string());
    // GPS is optional (guard may be offline at capture) but must be a valid pair when sent.
    progress::validate_coords(lat, lng)?;

    Ok(CheckInForm {
        hour_number,
        photo,
        declared_mime,
        lat,
        lng,
        accuracy_m: progress::sanitize_accuracy(accuracy_m),
        note,
    })
}

/// Parse one multipart text part as `f64` (for the optional GPS fields).
async fn parse_f64_field(
    field: axum::extract::multipart::Field<'_>,
    name: &str,
) -> Result<f64, AppError> {
    let text = field
        .text()
        .await
        .map_err(|e| AppError::BadRequest(format!("Invalid {name}: {e}")))?;
    text.trim()
        .parse::<f64>()
        .map_err(|_| AppError::BadRequest(format!("{name} must be a number")))
}

/// GET /bookings/{id}/progress-reports — a booking's check-in reports, hour order, each
/// with a FRESHLY presigned photo URL (the stored key is re-signed per read; signed URLs
/// are never persisted as the source of truth). Participants only — the customer (owner)
/// and the assigned guard; admin bypasses (same gate as `get_booking`, so a missing
/// booking is 404 and a non-participant 403, consistent with the rest of this service).
/// Primary-pool read: a guard lists right after checking in (read-after-write).
#[tracing::instrument(skip(state, query), fields(user = %user.user_id, booking_id = %id))]
pub async fn list_progress_reports<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Query(query): Query<ListProgressReportsQuery>,
) -> Result<Json<ApiResponse<Vec<ProgressReportResponse>>>, AppError> {
    let core = repo::get_booking_core(state.db(), id).await?;
    if user.role != ROLE_ADMIN
        && core.customer_id != user.user_id
        && core.guard_id != Some(user.user_id)
    {
        return Err(AppError::Forbidden(
            "Not a participant in this booking".to_string(),
        ));
    }
    let (limit, offset) = page(query.limit, query.offset);
    let rows = repo::list_progress_reports(state.db(), id, limit, offset).await?;
    let items: Vec<ProgressReportResponse> = rows
        .into_iter()
        .map(|row| {
            let url = state.s3().download_url(&row.photo_key);
            ProgressReportResponse::from_row(row, url)
        })
        .collect();
    Ok(Json(ApiResponse::success(items)))
}

/// GET /available-guards — discovery: the approved guard catalog (from profile) restricted to
/// guards who are currently ONLINE (live per presence — "พร้อมรับงาน"), enriched with each
/// guard's live rating summary (from rating). booking owns discovery but none of the catalog,
/// reviews, or live presence, so it reads all three owners over service-JWT and aggregates here.
///
/// ONLINE filter (the fix): an approved guard is only offered when presence reports them LIVE
/// (`is_online` AND a fresh GPS fix). An offline-but-approved guard is dropped.
///
/// BUSY filter (the fix): a guard who already holds an ACTIVE assignment (a booking in
/// accepted/en_route/arrived/pending_completion assigned to them) is dropped too — a guard
/// working a job must never be offered for another. This reads booking's OWN schema
/// (`repo::busy_guard_ids`), so it FAILS-CLOSED: an error there means booking's own DB is down
/// (the rest of the service is failing anyway), so we propagate rather than risk offering a busy
/// guard.
///
/// FAIL-OPEN on presence: if the presence consult errors/times out, the ONLINE filter is skipped
/// (with a warning) — a presence hiccup must never blank discovery and block every booking. The
/// BUSY filter still applies. The happy path filters by both.
///
/// Best-effort on ratings: a guard whose rating lookup fails still appears (with no average /
/// zero count) — one slow dependency never blanks the whole list. Rating lookups run
/// concurrently (bounded) and preserve the catalog's order.
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn available_guards<S: DiscoveryDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(window): Query<AvailableGuardsQuery>,
) -> Result<Json<ApiResponse<Vec<AvailableGuard>>>, AppError> {
    let guards = state.guard_catalog().list_approved_guards().await?;
    let rater = state.rating_reader();

    // The set of guards to EXCLUDE. With a time window (customer already picked the slot), exclude
    // only guards whose assignment OVERLAPS it — a guard busy 9–18 is still offered for 19–22. Without
    // a window, fall back to excluding any-active-job guard (back-compat). FAIL-CLOSED: propagate the
    // error — this is a local DB read, and silently offering a busy guard would double-book them.
    let busy = match (window.scheduled_at, window.hours) {
        (Some(start), Some(hours)) if hours > 0 => {
            state
                .busy_guards()
                .busy_guard_ids_overlapping(start, hours)
                .await?
        }
        _ => state.busy_guards().busy_guard_ids().await?,
    };

    // Consult presence for who is currently LIVE and WHERE. `None` => FAIL-OPEN: presence was
    // unreachable, so we do NOT apply the online filter (showing the approved list beats blocking
    // all bookings) — and, with no positions, the nearest-first sort is skipped too. The value is
    // a map guard_id → live (lat, lng): membership drives the online filter, the coords the sort.
    let online: Option<std::collections::HashMap<Uuid, (f64, f64)>> =
        match state.presence_reader().online_guard_locations().await {
            Ok(map) => Some(map),
            Err(e) => {
                tracing::warn!(
                "presence online-guards lookup failed: {e}; FAIL-OPEN (skipping the online filter)"
            );
                None
            }
        };

    // The MEETUP point (the booking's site pin), validated both-or-neither + in range. When
    // present, the surviving guards are sorted nearest-to-meetup by their live positions (C2).
    let meetup = progress::validate_coords(window.lat, window.lng)?;

    // Drop BUSY guards always; drop offline guards when presence answered (keep all online on
    // fail-open). Filtering BEFORE the rating fan-out also means we never spend rating lookups on
    // guards we're about to hide.
    let filtered: Vec<_> = guards
        .into_iter()
        .filter(|g| !busy.contains(&g.user_id))
        .filter(|g| online.as_ref().is_none_or(|m| m.contains_key(&g.user_id)))
        .collect();

    // Pair each surviving guard with its distance to the meetup (None when there is no meetup
    // point, or the guard's live position is unknown — e.g. presence fail-open), then sort
    // NEAREST-first (C2). The sort is STABLE, so with no meetup — or on tied distances — the
    // catalog order is preserved (backward compatible); guards with no known location sort last.
    let mut prepared: Vec<(CatalogGuard, Option<f64>)> = filtered
        .into_iter()
        .map(|g| {
            let distance_m = meetup.and_then(|(mlat, mlng)| {
                online
                    .as_ref()
                    .and_then(|m| m.get(&g.user_id))
                    .map(|&(glat, glng)| {
                        crate::domain::geo::haversine_meters(mlat, mlng, glat, glng)
                    })
            });
            (g, distance_m)
        })
        .collect();
    if meetup.is_some() {
        prepared.sort_by(|(_, da), (_, db)| match (da, db) {
            (Some(x), Some(y)) => x.partial_cmp(y).unwrap_or(std::cmp::Ordering::Equal),
            (Some(_), None) => std::cmp::Ordering::Less,
            (None, Some(_)) => std::cmp::Ordering::Greater,
            (None, None) => std::cmp::Ordering::Equal,
        });
    }

    // Each entry carries whether its rating lookup fell back (best-effort), so we can emit a
    // single aggregate signal for a degraded list rather than only per-guard warns.
    let merged: Vec<(AvailableGuard, bool)> = futures::stream::iter(prepared)
        .map(|(g, distance_m)| async move {
            let (summary, ok) = match rater.guard_summary(g.user_id).await {
                Ok(s) => (s, true),
                Err(e) => {
                    // Best-effort: a per-guard rating failure must not fail the whole list.
                    tracing::warn!(guard_id = %g.user_id, "rating summary failed: {e}; defaulting");
                    (Default::default(), false)
                }
            };
            let guard = AvailableGuard {
                guard_id: g.user_id,
                display_name: g.full_name,
                avatar_url: g.avatar_url,
                years_of_experience: g.years_of_experience,
                average_rating: summary.average,
                review_count: summary.count,
                has_documents: g.has_documents,
                documents: g.documents,
                distance_m,
            };
            (guard, !ok)
        })
        .buffered(MAX_CONCURRENT_RATING)
        .collect()
        .await;

    let rating_failures = merged.iter().filter(|(_, failed)| *failed).count();
    if rating_failures > 0 {
        tracing::warn!(
            rating_failures,
            total = merged.len(),
            "discovery returned with degraded ratings (rating service unreachable for some guards)"
        );
    }
    let items: Vec<AvailableGuard> = merged.into_iter().map(|(g, _)| g).collect();

    Ok(Json(ApiResponse::success(items)))
}

// ----- GET /internal/bookings/{id} (service-to-service) -----

/// Internal read used by the payment service to make the money decision against the
/// authoritative booking — never trusting a client-supplied customer/guard/status. Guarded
/// by [`ServiceCaller`] (a valid service-JWT); v1 had no auth on cross-service reads.
/// Returns only `{ id, customer_id, guard_id, status, hours }`. Generic over
/// [`BookingInternalDeps`] so the guard is unit-testable (mirrors identity's
/// `internal_revoke_all`).
#[tracing::instrument(skip(state), fields(caller = %caller.service, booking_id = %id))]
pub async fn get_internal_booking<S: BookingInternalDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<InternalBooking>>, AppError> {
    let booking = repo::get_internal(state.db(), id).await?;
    Ok(Json(ApiResponse::success(booking)))
}

// ----- GET /internal/users/{user_id}/export (PDPA §19/§32 data export) -----

/// Export a user's OWN bookings (as the customer OR the assigned guard) for a cross-service
/// data export. `ServiceCaller`-gated and scoped strictly to the path `user_id`.
#[tracing::instrument(skip(state), fields(caller = %caller.service, user = %user_id))]
pub async fn internal_export_user<S: BookingInternalDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
    Path(user_id): Path<Uuid>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    let bookings = repo::export_user_bookings(state.db_read(), user_id).await?;
    Ok(Json(ApiResponse::success(bookings)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::{get, post, put};
    use axum::Router;
    use jsonwebtoken::DecodingKey;
    use shared::auth::HasJwtSecret;
    use sqlx::postgres::PgPoolOptions;
    use std::sync::Arc;
    use std::time::Duration;
    use tower::ServiceExt;

    const SECRET: &str = "user-secret-at-least-64-characters-long-for-the-hs256-booking-test!!!";

    /// Stub S3 client — presigning is pure (no network until an actual PUT), so the auth/
    /// role-gate tests need no live MinIO (mirrors chat's `s3_stub`).
    fn s3_stub() -> crate::s3::S3Client {
        crate::s3::S3Client::new(
            reqwest::Client::new(),
            "http://localhost:9000".to_string(),
            None,
            "test".to_string(),
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
        s3: crate::s3::S3Client,
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
    impl BookingDeps for TestDeps {
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn s3(&self) -> &crate::s3::S3Client {
            &self.s3
        }
    }

    /// Build the booking router over a lightweight test state. The `AuthUser` extractor
    /// requires `HasJwtSecret`, which mandates a real [`redis::aio::ConnectionManager`]
    /// for the jti revocation blocklist — there is no public way to construct one without
    /// connecting. So, exactly like the repo's real-DB test, these router tests are
    /// hermetic by default and only run when a test Redis is provided via `TEST_REDIS_URL`
    /// (falling back to `REDIS_CACHE_URL`). Returns `None` → the caller SKIPs.
    ///
    /// The auth-reject paths never query Redis (they fail at token parse/decode first), so
    /// a reachable Redis is enough; its contents are irrelevant.
    async fn router() -> Option<Router> {
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .ok()?;
        // Lazy pool to a closed port — never connects unless a handler queries (rejected
        // requests short-circuit at the AuthUser guard before any DB access).
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool");
        let deps = TestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            db,
            redis,
            s3: s3_stub(),
        };
        Some(routes(deps))
    }

    /// The route table under test — same shape as prod (main.rs), so the literal-segment
    /// `/bookings/open` beside `/bookings/{id}` exercises the static-wins routing.
    fn routes(deps: TestDeps) -> Router {
        Router::new()
            .route("/bookings", post(create_booking::<TestDeps>))
            .route("/bookings/{id}/accept", post(accept_booking::<TestDeps>))
            .route("/bookings/{id}/decline", put(decline_booking::<TestDeps>))
            .route("/bookings/{id}/en-route", put(en_route_booking::<TestDeps>))
            .route("/bookings/{id}/arrived", put(arrived_booking::<TestDeps>))
            .route("/bookings/{id}/start", put(start_booking::<TestDeps>))
            .route("/bookings/{id}/complete", put(complete_booking::<TestDeps>))
            .route(
                "/bookings/{id}/review-completion",
                put(review_completion::<TestDeps>),
            )
            .route("/bookings/{id}/cancel", put(cancel_booking::<TestDeps>))
            .route(
                "/bookings/{id}/cancel-after-decline",
                put(cancel_after_decline::<TestDeps>),
            )
            .route("/bookings/{id}/skip", post(skip_booking::<TestDeps>))
            .route("/bookings/open", get(list_open_bookings::<TestDeps>))
            .route("/bookings/{id}", get(get_booking::<TestDeps>))
            .route(
                "/bookings/{id}/progress-reports",
                post(create_progress_report::<TestDeps>).get(list_progress_reports::<TestDeps>),
            )
            .route("/admin/bookings", get(admin_list_bookings::<TestDeps>))
            .route(
                "/admin/bookings/{id}/assign",
                post(admin_assign_guard::<TestDeps>),
            )
            .route(
                "/admin/reports/bookings",
                get(admin_bookings_report::<TestDeps>),
            )
            .route(
                "/admin/reports/customer-bookings",
                get(admin_customer_bookings_report::<TestDeps>),
            )
            .route(
                "/admin/pricing/services",
                get(admin_list_services::<TestDeps>),
            )
            .route("/services", get(list_services::<TestDeps>))
            .with_state(deps)
    }

    /// Like [`router`], but over the REAL database (for the IDOR matrix that needs seeded
    /// rows). Gated on BOTH `DATABASE_URL` and a test Redis — `None` → the caller SKIPs.
    async fn router_with_real_db() -> Option<(Router, sqlx::PgPool)> {
        let db_url = std::env::var("DATABASE_URL").ok()?;
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .ok()?;
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&db_url)
            .await
            .ok()?;
        let deps = TestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            db: db.clone(),
            redis,
            s3: s3_stub(),
        };
        Some((routes(deps), db))
    }

    fn create_body() -> Body {
        // A FUTURE time — the create handler rejects a past/now scheduled_at (SCHEDULED_IN_PAST),
        // so a fixed date would go stale. now + 1 day keeps it valid forever.
        let sched = (chrono::Utc::now() + chrono::Duration::days(1)).to_rfc3339();
        Body::from(
            serde_json::json!({
                "address": "1 Test Rd",
                "scheduled_at": sched,
                "hours": 4
            })
            .to_string(),
        )
    }

    #[tokio::test]
    async fn create_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/bookings")
                    .header("content-type", "application/json")
                    .body(create_body())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn create_rejects_invalid_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/bookings")
                    .header("authorization", "Bearer not.a.valid.jwt")
                    .header("content-type", "application/json")
                    .body(create_body())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    /// A create-booking body with the given field overrides, otherwise valid (future
    /// scheduled_at). Used by the input-validation tests below (they run BEFORE any DB access, so
    /// the hermetic `router()` — closed-port lazy pool — is enough).
    fn create_body_with(overrides: serde_json::Value) -> Body {
        let sched = (chrono::Utc::now() + chrono::Duration::days(1)).to_rfc3339();
        let mut body = serde_json::json!({
            "address": "1 Test Rd",
            "scheduled_at": sched,
            "hours": 4,
        });
        for (k, v) in overrides.as_object().expect("object").clone() {
            body[k] = v;
        }
        Body::from(body.to_string())
    }

    async fn create_status(app: Router, body: Body) -> StatusCode {
        app.oneshot(
            Request::builder()
                .method("POST")
                .uri("/bookings")
                .header(
                    "authorization",
                    format!("Bearer {}", user_token("customer")),
                )
                .header("content-type", "application/json")
                .body(body)
                .unwrap(),
        )
        .await
        .unwrap()
        .status()
    }

    /// MED #10: an over-long address is a typed 400 (before any DB access), bounding the TEXT that
    /// fans out to every guard + into the booking.requested event. Redis-gated.
    #[tokio::test]
    async fn create_rejects_oversized_address() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let long = "x".repeat(MAX_ADDRESS_CHARS + 1);
        let status = create_status(
            app,
            create_body_with(serde_json::json!({ "address": long })),
        )
        .await;
        assert_eq!(
            status,
            StatusCode::BAD_REQUEST,
            "over-cap address must be 400, not a 500/200"
        );
    }

    /// An all-whitespace address is no address → typed 400 (before any DB access). Redis-gated.
    #[tokio::test]
    async fn create_rejects_blank_address() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let status = create_status(
            app,
            create_body_with(serde_json::json!({ "address": "   " })),
        )
        .await;
        assert_eq!(
            status,
            StatusCode::BAD_REQUEST,
            "a blank address must be 400"
        );
    }

    /// LOW #33: a tip past the cap is a typed 400 instead of the NUMERIC(12,2) overflow 500 an
    /// uncapped value would raise on INSERT. Runs before any DB access. Redis-gated.
    #[tokio::test]
    async fn create_rejects_oversized_tip() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // 10^10 overflows NUMERIC(12,2); well past MAX_TIP. As a JSON string (money wire shape).
        let status = create_status(
            app,
            create_body_with(serde_json::json!({ "tip": "10000000000" })),
        )
        .await;
        assert_eq!(
            status,
            StatusCode::BAD_REQUEST,
            "over-cap tip must be a typed 400, not a 500"
        );
    }

    #[tokio::test]
    async fn accept_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let id = Uuid::new_v4();
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/bookings/{id}/accept"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    // ----- lifecycle api-layer authz: the broad role gate (require_role) -----
    //
    // These assert the coarse role check each lifecycle handler runs BEFORE the repo: a
    // valid token of the WRONG role is rejected (403) before any DB access (the lazy pool
    // points at a closed port, so a 403 here also proves no query was attempted). The
    // FINER ownership authz (assigned-guard vs request-owner) lives in `repo::transition`
    // / `repo::start_job` and is covered by the DB-gated repo tests. Redis-gated for the
    // same reason as the other router tests (AuthUser needs a reachable revocation store).

    /// Send a lifecycle request to `subpath` with a freshly-minted valid token for `role`.
    /// `body` is the JSON request body (empty for the bodiless endpoints).
    async fn lifecycle_req(
        app: Router,
        method: &str,
        subpath: &str,
        role: &str,
        body: Body,
    ) -> StatusCode {
        let id = Uuid::new_v4();
        let mut builder = Request::builder()
            .method(method)
            .uri(format!("/bookings/{id}/{subpath}"))
            .header("authorization", format!("Bearer {}", user_token(role)));
        // These endpoints deserialize a JSON body (review-completion's verdict, cancel/decline's
        // MANDATORY reason); give them the right content-type so the Json extractor succeeds and
        // execution reaches the handler's role gate — extractors run BEFORE the handler body.
        if matches!(subpath, "review-completion" | "cancel" | "decline") {
            builder = builder.header("content-type", "application/json");
        }
        app.oneshot(builder.body(body).unwrap())
            .await
            .unwrap()
            .status()
    }

    /// A valid cancel/decline body for the role gate tests (the reason only has to survive
    /// deserialization — validation runs AFTER the role check).
    fn reason_body(reason: &str) -> Body {
        Body::from(serde_json::json!({ "reason": reason }).to_string())
    }

    #[tokio::test]
    async fn decline_rejects_non_guard() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // a customer cannot drive a guard-only transition
        let status = lifecycle_req(app, "PUT", "decline", "customer", reason_body("sick")).await;
        assert_eq!(status, StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn en_route_rejects_non_guard() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let status = lifecycle_req(app, "PUT", "en-route", "customer", Body::empty()).await;
        assert_eq!(status, StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn start_rejects_non_guard() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let status = lifecycle_req(app, "PUT", "start", "customer", Body::empty()).await;
        assert_eq!(status, StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn complete_rejects_non_guard() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let status = lifecycle_req(app, "PUT", "complete", "customer", Body::empty()).await;
        assert_eq!(status, StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn cancel_rejects_non_customer() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // a guard cannot cancel a customer's booking (the body is well-formed: the 403 is the
        // ROLE gate, not the reason validation, which runs after it)
        let status =
            lifecycle_req(app, "PUT", "cancel", "guard", reason_body("changed_plan")).await;
        assert_eq!(status, StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn cancel_after_decline_rejects_non_customer() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // The customer ACK (E) is a no-body, customer-auth endpoint: a GUARD is rejected at the
        // ROLE gate BEFORE any DB access (the lazy pool at a closed port is never reached). Also
        // exercises the new route (`/bookings/{id}/cancel-after-decline`) in the prod-shaped table.
        let status =
            lifecycle_req(app, "PUT", "cancel-after-decline", "guard", Body::empty()).await;
        assert_eq!(status, StatusCode::FORBIDDEN);
    }

    // ----- the MANDATORY cancellation reason (api-layer validation, before any DB access) -----

    /// Send a cancel/decline body with a valid token for `role` and return (status, error code).
    /// The lazy pool points at a closed port, so a 400 here also proves the reason was rejected
    /// BEFORE the repo was ever called.
    async fn cancellation_req(
        app: Router,
        subpath: &str,
        role: &str,
        body: serde_json::Value,
    ) -> (StatusCode, String) {
        let id = Uuid::new_v4();
        let res = app
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/bookings/{id}/{subpath}"))
                    .header("authorization", format!("Bearer {}", user_token(role)))
                    .header("content-type", "application/json")
                    .body(Body::from(body.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        let status = res.status();
        let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value =
            serde_json::from_slice(&bytes).unwrap_or(serde_json::json!({}));
        let code = json["error"]["code"]
            .as_str()
            .unwrap_or_default()
            .to_string();
        (status, code)
    }

    #[tokio::test]
    async fn cancel_requires_a_customer_reason() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // No reason at all → the typed code the app localizes.
        let (status, code) =
            cancellation_req(app, "cancel", "customer", serde_json::json!({})).await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(code, "CANCEL_REASON_REQUIRED");
    }

    #[tokio::test]
    async fn cancel_rejects_a_guard_reason_code() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // "sick" is the GUARD vocabulary — invalid on the customer's endpoint.
        let (status, code) = cancellation_req(
            app,
            "cancel",
            "customer",
            serde_json::json!({ "reason": "sick" }),
        )
        .await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(code, "CANCEL_REASON_REQUIRED");
    }

    #[tokio::test]
    async fn decline_rejects_a_customer_reason_code() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let (status, code) = cancellation_req(
            app,
            "decline",
            "guard",
            serde_json::json!({ "reason": "changed_plan" }),
        )
        .await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(code, "CANCEL_REASON_REQUIRED");
    }

    #[tokio::test]
    async fn other_reason_requires_a_note() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let (status, code) = cancellation_req(
            app,
            "cancel",
            "customer",
            serde_json::json!({ "reason": "other", "note": "   " }),
        )
        .await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
        assert_eq!(code, "CANCEL_NOTE_REQUIRED");
    }

    #[tokio::test]
    async fn review_completion_rejects_non_customer() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // a guard cannot approve/reject their own completion request
        let body = Body::from(serde_json::json!({ "action": "approve" }).to_string());
        let status = lifecycle_req(app, "PUT", "review-completion", "guard", body).await;
        assert_eq!(status, StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn admin_list_bookings_rejects_non_admin() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A customer must not read the cross-user booking list (other customers' addresses).
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/bookings")
                    .header(
                        "authorization",
                        format!("Bearer {}", user_token("customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn admin_bookings_report_rejects_non_admin() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A customer must not read cross-user booking analytics.
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/reports/bookings")
                    .header(
                        "authorization",
                        format!("Bearer {}", user_token("customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn admin_customer_bookings_report_rejects_non_admin() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A customer must not read cross-user per-customer booking aggregates. The 403 here
        // also proves the lazy pool (closed port) was never touched.
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/reports/customer-bookings")
                    .header(
                        "authorization",
                        format!("Bearer {}", user_token("customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn admin_list_services_rejects_non_admin() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A guard must not read/manage the pricing catalog.
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/pricing/services")
                    .header("authorization", format!("Bearer {}", user_token("guard")))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn public_services_requires_auth() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // The customer-facing picker is authenticated (no anonymous reads) — a missing token
        // is 401 at the AuthUser guard, before any DB access (the lazy pool is never touched).
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/services")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn admin_assign_guard_rejects_non_admin() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A guard must not self-assign via the admin path (valid body so execution reaches the
        // handler's admin gate; the 403 proves it never touched the DB).
        let id = Uuid::new_v4();
        let body = Body::from(serde_json::json!({ "guard_id": Uuid::new_v4() }).to_string());
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/admin/bookings/{id}/assign"))
                    .header("authorization", format!("Bearer {}", user_token("guard")))
                    .header("content-type", "application/json")
                    .body(body)
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn cancel_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let id = Uuid::new_v4();
        let res = app
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/bookings/{id}/cancel"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn start_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let id = Uuid::new_v4();
        let res = app
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/bookings/{id}/start"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    // ----- progress reports + open-job discovery: hermetic gate tests -----
    //
    // These run over the LAZY pool (closed port): a 401/403/400 also proves the request was
    // rejected before any DB access — and the s3 stub proves no S3 traffic either (the
    // photo path is never reached). Redis-gated like the other AuthUser router tests.

    /// A minimal multipart request shell (empty body) — the gates under test all fire
    /// BEFORE the body is parsed, which is itself part of the contract (a rejected caller
    /// never makes the server buffer a photo).
    fn multipart_req(method: &str, uri: String, token: Option<String>) -> Request<Body> {
        let mut builder = Request::builder()
            .method(method)
            .uri(uri)
            .header("content-type", "multipart/form-data; boundary=x");
        if let Some(tok) = token {
            builder = builder.header("authorization", format!("Bearer {tok}"));
        }
        builder.body(Body::empty()).unwrap()
    }

    #[tokio::test]
    async fn progress_report_post_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let id = Uuid::new_v4();
        let res = app
            .oneshot(multipart_req(
                "POST",
                format!("/bookings/{id}/progress-reports"),
                None,
            ))
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn progress_report_post_rejects_non_guard_before_db() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let id = Uuid::new_v4();
        let res = app
            .oneshot(multipart_req(
                "POST",
                format!("/bookings/{id}/progress-reports"),
                Some(user_token("customer")),
            ))
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn progress_report_post_has_no_admin_bypass() {
        // A check-in is the assigned guard's first-person attestation — even an admin's
        // valid token is rejected at the coarse gate (before any DB/S3 access).
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let id = Uuid::new_v4();
        let res = app
            .oneshot(multipart_req(
                "POST",
                format!("/bookings/{id}/progress-reports"),
                Some(user_token("admin")),
            ))
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn list_progress_reports_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let id = Uuid::new_v4();
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(format!("/bookings/{id}/progress-reports"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn open_jobs_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/bookings/open")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn open_jobs_static_route_wins_and_rejects_non_guard() {
        // PHASE spec §C: confirm `/bookings/open` is NOT swallowed by `/bookings/{id}`.
        // A customer hitting the open handler gets the role-gate 403; had the request been
        // routed to get_booking, `Path<Uuid>` would reject the literal "open" with a 400.
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/bookings/open")
                    .header(
                        "authorization",
                        format!("Bearer {}", user_token("customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::FORBIDDEN,
            "403 from the open-jobs role gate proves the static route won (a {{id}} parse \
             failure would be 400)"
        );
    }

    #[tokio::test]
    async fn open_jobs_validates_geo_before_db() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // lat without lng / radius without coords / zero radius — all 400 BEFORE any DB
        // access (the lazy pool would otherwise 500).
        for bad in [
            "/bookings/open?lat=13.75",
            "/bookings/open?radius_km=5",
            "/bookings/open?lat=13.75&lng=100.5&radius_km=0",
            "/bookings/open?lat=91&lng=0",
        ] {
            let res = app
                .clone()
                .oneshot(
                    Request::builder()
                        .method("GET")
                        .uri(bad)
                        .header("authorization", format!("Bearer {}", user_token("guard")))
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap();
            assert_eq!(res.status(), StatusCode::BAD_REQUEST, "uri: {bad}");
        }
    }

    // ----- progress reports: router-level IDOR matrix (real DB + Redis; hermetic SKIP) -----

    /// Mint a token for a SPECIFIC user id (the IDOR matrix needs participant tokens).
    fn user_token_for(user_id: Uuid, role: &str) -> String {
        use shared::auth::encode_jwt_with_key;
        let ek = jsonwebtoken::EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, _jti) = encode_jwt_with_key(user_id, role, 0, &ek, 15).unwrap();
        tok
    }

    /// GET /bookings/{id} authz: a guard may read an OPEN (unassigned + `requested`) job (it's
    /// already in their discovery feed) so tapping an incoming card doesn't 403; once it's claimed
    /// or a stranger customer asks, only the participants can read it. DB-gated (SKIPs hermetically).
    #[tokio::test]
    async fn get_booking_lets_a_guard_read_an_open_job() {
        let Some((app, db)) = router_with_real_db().await else {
            eprintln!("SKIP: no DATABASE_URL + Redis (hermetic default)");
            return;
        };
        let customer = Uuid::new_v4();
        let open = repo::create_booking(
            &db,
            customer,
            &CreateBookingRequest {
                address: "9 Open Job Rd".to_string(),
                scheduled_at: chrono::Utc::now(),
                hours: 4,
                service_id: None,
                target_guard_id: None,
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            Uuid::new_v4(),
        )
        .await
        .expect("create open");

        let get = |token: String, id: Uuid| {
            let app = app.clone();
            async move {
                app.oneshot(
                    Request::builder()
                        .method("GET")
                        .uri(format!("/bookings/{id}"))
                        .header("authorization", format!("Bearer {token}"))
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap()
                .status()
            }
        };

        // A non-participant GUARD reads the OPEN job → 200 (discoverable + claimable).
        assert_eq!(
            get(user_token_for(Uuid::new_v4(), "guard"), open.id).await,
            StatusCode::OK,
            "a guard can read an open job before accepting"
        );
        // A non-participant CUSTOMER still cannot → 403.
        assert_eq!(
            get(user_token_for(Uuid::new_v4(), "customer"), open.id).await,
            StatusCode::FORBIDDEN,
            "a stranger customer cannot read someone's open job"
        );
        // The owner customer → 200.
        assert_eq!(
            get(user_token_for(customer, "customer"), open.id).await,
            StatusCode::OK,
            "the owner reads their booking"
        );

        // Once a guard CLAIMS it, another guard can no longer read it (no longer open).
        let claimer = Uuid::new_v4();
        repo::transition(
            &db,
            open.id,
            claimer,
            false,
            BookingStatus::Accepted,
            Some(claimer),
            None,
            Uuid::new_v4(),
        )
        .await
        .expect("accept");
        assert_eq!(
            get(user_token_for(Uuid::new_v4(), "guard"), open.id).await,
            StatusCode::FORBIDDEN,
            "a stranger guard cannot read a CLAIMED job"
        );
        assert_eq!(
            get(user_token_for(claimer, "guard"), open.id).await,
            StatusCode::OK,
            "the assigned guard reads their job"
        );
    }

    /// GET /bookings/{id} authz for a DIRECTED offer (C3, deep-review LOW #27/#28): a booking
    /// targeted at ONE guard is readable ONLY by that guard (plus the owner customer), NOT by every
    /// guard the way an UNDIRECTED open job is — mirroring the discovery + accept confinement so the
    /// customer's address/coords/schedule don't leak to a non-target who happens to know the UUID.
    /// DB-gated (SKIPs hermetically).
    #[tokio::test]
    async fn get_booking_confines_a_directed_offer_to_its_target() {
        let Some((app, db)) = router_with_real_db().await else {
            eprintln!("SKIP: no DATABASE_URL + Redis (hermetic default)");
            return;
        };
        let customer = Uuid::new_v4();
        let target = Uuid::new_v4();
        let directed = repo::create_booking(
            &db,
            customer,
            &CreateBookingRequest {
                address: "11 Directed Rd".to_string(),
                scheduled_at: chrono::Utc::now(),
                hours: 4,
                service_id: None,
                target_guard_id: Some(target),
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            Uuid::new_v4(),
        )
        .await
        .expect("create directed");

        let get = |token: String, id: Uuid| {
            let app = app.clone();
            async move {
                app.oneshot(
                    Request::builder()
                        .method("GET")
                        .uri(format!("/bookings/{id}"))
                        .header("authorization", format!("Bearer {token}"))
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap()
                .status()
            }
        };

        // A NON-target guard must NOT read the directed offer (the leak the fix closes) — even
        // though an UNDIRECTED requested job of the same shape would be readable by any guard.
        assert_eq!(
            get(user_token_for(Uuid::new_v4(), "guard"), directed.id).await,
            StatusCode::FORBIDDEN,
            "a non-target guard must not read a directed offer"
        );
        // The DIRECTED TARGET reads it pre-accept (so tapping their directed card works).
        assert_eq!(
            get(user_token_for(target, "guard"), directed.id).await,
            StatusCode::OK,
            "the directed target may read the offer before accepting"
        );
        // The owner customer reads it; a stranger customer cannot.
        assert_eq!(
            get(user_token_for(customer, "customer"), directed.id).await,
            StatusCode::OK,
            "the owner reads their booking"
        );
        assert_eq!(
            get(user_token_for(Uuid::new_v4(), "customer"), directed.id).await,
            StatusCode::FORBIDDEN,
            "a stranger customer cannot read someone's directed booking"
        );
    }

    /// Full-router IDOR matrix for the progress-report endpoints (chat-style). Needs a
    /// MIGRATED database (0004) + Redis; SKIPs hermetically otherwise. Run:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///   TEST_REDIS_URL=redis://localhost:6379 \
    ///     cargo test -p pguard-booking -- progress_reports_idor_matrix --nocapture
    #[tokio::test]
    async fn progress_reports_idor_matrix() {
        let Some((app, db)) = router_with_real_db().await else {
            eprintln!("SKIP: no DATABASE_URL + TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };

        // Seed: a booking with an assigned guard (accepted is enough for the READ gate).
        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let stranger = Uuid::new_v4();
        let created = repo::create_booking(
            &db,
            customer,
            &CreateBookingRequest {
                address: "1 IDOR Matrix Rd".to_string(),
                scheduled_at: chrono::Utc::now(),
                hours: 4,
                service_id: None,
                target_guard_id: None,
                guard_count: None,
                tip: None,
                lat: None,
                lng: None,
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            Uuid::new_v4(),
        )
        .await
        .expect("create");
        repo::transition(
            &db,
            created.id,
            guard,
            false,
            BookingStatus::Accepted,
            Some(guard),
            None,
            Uuid::new_v4(),
        )
        .await
        .expect("accept");

        let get_reports = |token: String, id: Uuid| {
            let app = app.clone();
            async move {
                app.oneshot(
                    Request::builder()
                        .method("GET")
                        .uri(format!("/bookings/{id}/progress-reports"))
                        .header("authorization", format!("Bearer {token}"))
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap()
                .status()
            }
        };

        // GET matrix: stranger → 403 (generic; no report content leaks); participants → 200;
        // admin → 200 (read-side moderation bypass, mirroring get_booking).
        assert_eq!(
            get_reports(user_token_for(stranger, "guard"), created.id).await,
            StatusCode::FORBIDDEN,
            "stranger guard must not read another job's check-ins"
        );
        assert_eq!(
            get_reports(user_token_for(stranger, "customer"), created.id).await,
            StatusCode::FORBIDDEN,
            "another customer must not read this job's check-ins"
        );
        assert_eq!(
            get_reports(user_token_for(customer, "customer"), created.id).await,
            StatusCode::OK,
            "the booking's customer reads their job's check-ins"
        );
        assert_eq!(
            get_reports(user_token_for(guard, "guard"), created.id).await,
            StatusCode::OK,
            "the assigned guard reads their own check-ins"
        );
        assert_eq!(
            get_reports(user_token_for(stranger, "admin"), created.id).await,
            StatusCode::OK,
            "admin read bypass (moderation)"
        );
        // Missing booking → 404 for everyone (booking's house pattern: get_booking is
        // fetch-then-gate; booking ids are unguessable UUIDv4s).
        assert_eq!(
            get_reports(user_token_for(stranger, "guard"), Uuid::new_v4()).await,
            StatusCode::NOT_FOUND
        );

        // POST: a stranger guard is 403 at the pre-flight — BEFORE the multipart body is
        // read (empty body never reaches the parser) and before any S3 traffic (stub).
        let res = app
            .clone()
            .oneshot(multipart_req(
                "POST",
                format!("/bookings/{}/progress-reports", created.id),
                Some(user_token_for(stranger, "guard")),
            ))
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::FORBIDDEN,
            "stranger guard cannot check in on another guard's job"
        );

        // POST duplicate hour: 409 at the advisory pre-flight, BEFORE any S3 upload — the
        // s3 stub points at a closed/dummy endpoint, so a 409 (not 500) also proves no
        // upload was attempted for the spec's idempotent guard-retry path. Drive the
        // booking to in-progress, file hour 1 via the repo, then retry hour 1 over HTTP
        // with a real multipart body (valid tiny JPEG).
        // PRE-PAY gate: the booking must be paid before en_route (the payment.completed
        // consumer stamps this in prod).
        sqlx::query("UPDATE booking.bookings SET paid_at = now() WHERE id = $1")
            .bind(created.id)
            .execute(&db)
            .await
            .expect("mark paid");
        for status in [BookingStatus::EnRoute, BookingStatus::Arrived] {
            repo::transition(
                &db,
                created.id,
                guard,
                false,
                status,
                None,
                None,
                Uuid::new_v4(),
            )
            .await
            .unwrap_or_else(|e| panic!("transition to {status}: {e:?}"));
        }
        repo::start_job(&db, created.id, guard, false, None, None)
            .await
            .expect("start");
        repo::create_progress_report(
            &db,
            created.id,
            guard,
            &NewProgressReport {
                hour_number: 1,
                photo_key: format!("booking/{}/checkins/{}.jpg", created.id, Uuid::new_v4()),
                lat: None,
                lng: None,
                accuracy_m: None,
                note: None,
            },
            Uuid::new_v4(),
        )
        .await
        .expect("seed hour-1 report");

        const TINY_JPEG: &[u8] = &[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
        let mut body = Vec::new();
        body.extend_from_slice(
            b"--BNDRY\r\nContent-Disposition: form-data; name=\"hour_number\"\r\n\r\n1\r\n",
        );
        body.extend_from_slice(
            b"--BNDRY\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"p.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n",
        );
        body.extend_from_slice(TINY_JPEG);
        body.extend_from_slice(b"\r\n--BNDRY--\r\n");
        let res = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/bookings/{}/progress-reports", created.id))
                    .header("content-type", "multipart/form-data; boundary=BNDRY")
                    .header(
                        "authorization",
                        format!("Bearer {}", user_token_for(guard, "guard")),
                    )
                    .body(Body::from(body))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::CONFLICT,
            "duplicate-hour retry must 409 at the pre-flight (a 500 here would mean an S3 \
             upload was attempted against the stub)"
        );
        // ...and the body carries the machine-readable sub-code so the mobile client can
        // absorb the idempotent retry without matching on the English message.
        let body = axum::body::to_bytes(res.into_body(), 1 << 20)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(
            v["error"]["code"],
            crate::domain::progress::DUPLICATE_CHECK_IN_CODE,
            "pre-flight duplicate 409 must carry the DUPLICATE_CHECK_IN sub-code"
        );

        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
            .bind(created.id)
            .execute(&db)
            .await;
    }

    // ----- proximity: start is NO LONGER geofenced; ARRIVE is (G4) -----

    /// A test site pin (Bangkok) + a point `meters` due north of it — pure-latitude offsets
    /// make the haversine near-exact so the fence distances are dialled in precisely
    /// (mirrors the `domain::geo` unit-test helper).
    const START_SITE: (f64, f64) = (13.7563, 100.5018);
    fn north_of_site(meters: f64) -> (f64, f64) {
        let deg_per_m = 180.0 / (std::f64::consts::PI * 6_371_000.0);
        (START_SITE.0 + meters * deg_per_m, START_SITE.1)
    }

    /// `start` validates the GPS body BEFORE any DB access: `lat` without `lng` (and
    /// out-of-range coordinates) are 400 at the handler — the lazy pool (closed port)
    /// would 500 if a query were attempted. Redis-gated like the other router tests.
    #[tokio::test]
    async fn start_validates_gps_body_before_db() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let id = Uuid::new_v4();
        for bad in [
            serde_json::json!({ "lat": 13.75 }),
            serde_json::json!({ "lng": 100.5 }),
            serde_json::json!({ "lat": 91.0, "lng": 100.5 }),
            serde_json::json!({ "lat": 13.75, "lng": 180.5 }),
        ] {
            let res = app
                .clone()
                .oneshot(
                    Request::builder()
                        .method("PUT")
                        .uri(format!("/bookings/{id}/start"))
                        .header("authorization", format!("Bearer {}", user_token("guard")))
                        .header("content-type", "application/json")
                        .body(Body::from(bad.to_string()))
                        .unwrap(),
                )
                .await
                .unwrap();
            assert_eq!(res.status(), StatusCode::BAD_REQUEST, "body: {bad}");
        }
    }

    /// Drive a fresh, PAID booking to `stop_at` over the real DB via `repo::transition` (which is
    /// NOT geofenced — the proximity gate lives only on the guard's own `PUT /arrived` handler),
    /// so the seed lands in the requested pre-state regardless of the site pin. `coords` pins the
    /// site. Used by both the start (→ arrived) and arrive (→ en_route) geofence tests.
    async fn seed_to(
        db: &sqlx::PgPool,
        coords: Option<(f64, f64)>,
        guard: Uuid,
        stop_at: BookingStatus,
    ) -> Uuid {
        let created = repo::create_booking(
            db,
            Uuid::new_v4(),
            &CreateBookingRequest {
                address: "5 Geofence Rd".to_string(),
                scheduled_at: chrono::Utc::now(),
                hours: 4,
                service_id: None,
                target_guard_id: None,
                guard_count: None,
                tip: None,
                lat: coords.map(|c| c.0),
                lng: coords.map(|c| c.1),
            },
            1,
            rust_decimal::Decimal::ZERO,
            None,
            Uuid::new_v4(),
        )
        .await
        .expect("create");
        // PRE-PAY gate: paid before en_route (the payment.completed consumer in prod).
        sqlx::query("UPDATE booking.bookings SET paid_at = now() WHERE id = $1")
            .bind(created.id)
            .execute(db)
            .await
            .expect("mark paid");
        // Accepted → EnRoute → (Arrived): stop once `stop_at` is reached.
        let path = [
            (BookingStatus::Accepted, Some(guard)),
            (BookingStatus::EnRoute, None),
            (BookingStatus::Arrived, None),
        ];
        for (status, assign) in path {
            repo::transition(
                db,
                created.id,
                guard,
                false,
                status,
                assign,
                None,
                Uuid::new_v4(),
            )
            .await
            .unwrap_or_else(|e| panic!("transition to {status}: {e:?}"));
            if status == stop_at {
                break;
            }
        }
        created.id
    }

    /// A `{ lat, lng, accuracy_m? }` GPS body value for the start/arrive tests.
    fn gps_body(p: (f64, f64), acc: Option<f32>) -> serde_json::Value {
        let mut v = serde_json::json!({ "lat": p.0, "lng": p.1 });
        if let Some(a) = acc {
            v["accuracy_m"] = serde_json::json!(a);
        }
        v
    }

    /// PUT a bodiless-or-GPS transition (`/start` or `/arrived`) as `actor`/`role`; `gps` None
    /// sends an EMPTY body with no content-type — exactly what an old app build sends (extracts as
    /// `None`). Returns `(status, json_body)`.
    async fn put_gps_transition(
        app: &Router,
        id: Uuid,
        actor: Uuid,
        role: &str,
        action: &str,
        gps: Option<serde_json::Value>,
    ) -> (StatusCode, serde_json::Value) {
        let mut builder = Request::builder()
            .method("PUT")
            .uri(format!("/bookings/{id}/{action}"))
            .header(
                "authorization",
                format!("Bearer {}", user_token_for(actor, role)),
            );
        let body = match gps {
            Some(v) => {
                builder = builder.header("content-type", "application/json");
                Body::from(v.to_string())
            }
            None => Body::empty(),
        };
        let res = app
            .clone()
            .oneshot(builder.body(body).unwrap())
            .await
            .unwrap();
        let status = res.status();
        let bytes = axum::body::to_bytes(res.into_body(), 1 << 20)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        (status, v)
    }

    /// START is NO LONGER geofenced (G4 moved the proximity gate to ARRIVAL). Over the real router
    /// (real DB + Redis; hermetic SKIP): a PINNED, arrived booking starts even from a fix FAR
    /// outside the old 50m fence — and with NO GPS at all — as long as the start-time gate passes;
    /// `work_started_at` is stamped and any provided fix is still persisted as audit evidence. An
    /// UNPINNED legacy booking starts with no GPS too. Run:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///   TEST_REDIS_URL=redis://localhost:6379 \
    ///     cargo test -p pguard-booking -- start_is_ungated --nocapture
    #[tokio::test]
    async fn start_is_ungated_after_arrival() {
        let Some((app, db)) = router_with_real_db().await else {
            eprintln!("SKIP: no DATABASE_URL + TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };

        let guard = Uuid::new_v4();
        let pinned = seed_to(&db, Some(START_SITE), guard, BookingStatus::Arrived).await;

        // FAR fix (500m out) that the OLD 50m start fence would have rejected → now 200 (start is
        // ungated); `work_started_at` is stamped and the provided fix is still persisted.
        let (status, v) = put_gps_transition(
            &app,
            pinned,
            guard,
            "guard",
            "start",
            Some(gps_body(north_of_site(500.0), None)),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "start is no longer geofenced: {v}");
        assert!(
            v["data"]["work_started_at"].is_string(),
            "work_started_at must be stamped, got: {v}"
        );
        let started_at = v["data"]["work_started_at"].as_str().unwrap().to_string();
        let glat: Option<f64> =
            sqlx::query_scalar("SELECT work_started_lat FROM booking.bookings WHERE id = $1")
                .bind(pinned)
                .fetch_one(&db)
                .await
                .expect("read work_started_lat");
        assert!(
            glat.is_some(),
            "the provided start fix is still persisted (audit)"
        );

        // IDEMPOTENT RETRY with NO GPS on the already-started booking → 200, clock unchanged.
        let (status, v) = put_gps_transition(&app, pinned, guard, "guard", "start", None).await;
        assert_eq!(
            status,
            StatusCode::OK,
            "GPS-less retry of a started job must 200: {v}"
        );
        assert_eq!(
            v["data"]["work_started_at"].as_str(),
            Some(started_at.as_str()),
            "the retry must not re-stamp the proration clock"
        );

        // A PINNED booking started with NO GPS at all → 200 (start no longer needs a fix). A
        // DIFFERENT guard: the first still holds the overlapping job (same-guard accept 409s).
        let guard2 = Uuid::new_v4();
        let pinned_no_gps = seed_to(&db, Some(START_SITE), guard2, BookingStatus::Arrived).await;
        let (status, v) =
            put_gps_transition(&app, pinned_no_gps, guard2, "guard", "start", None).await;
        assert_eq!(
            status,
            StatusCode::OK,
            "pinned start with no GPS is allowed now: {v}"
        );

        // UNPINNED legacy booking (no site coordinates) + no GPS → 200.
        let guard3 = Uuid::new_v4();
        let unpinned = seed_to(&db, None, guard3, BookingStatus::Arrived).await;
        let (status, v) = put_gps_transition(&app, unpinned, guard3, "guard", "start", None).await;
        assert_eq!(
            status,
            StatusCode::OK,
            "unpinned booking starts without GPS: {v}"
        );

        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = ANY($1)")
            .bind(vec![pinned, pinned_no_gps, unpinned])
            .execute(&db)
            .await;
    }

    /// The ARRIVE geofence (PUT /bookings/{id}/arrived), end-to-end over the router (real DB +
    /// Redis; hermetic SKIP): a PINNED en_route booking rejects a far fix (409 `NOT_AT_SITE`) and a
    /// missing fix (409 `GPS_REQUIRED` — an old build's EMPTY body extracts as `None`) WITHOUT
    /// advancing status, accepts an in-fence fix (200, status `arrived`, the fix persisted). An
    /// UNPINNED booking arrives with no GPS. Admin BYPASSES the fence (a far fix still 200s). Run:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///   TEST_REDIS_URL=redis://localhost:6379 \
    ///     cargo test -p pguard-booking -- arrived_geofence --nocapture
    #[tokio::test]
    async fn arrived_geofence_matrix() {
        let Some((app, db)) = router_with_real_db().await else {
            eprintln!("SKIP: no DATABASE_URL + TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };

        let guard = Uuid::new_v4();
        let pinned = seed_to(&db, Some(START_SITE), guard, BookingStatus::EnRoute).await;

        // OUTSIDE the fence (400m out, no accuracy) → 409 NOT_AT_SITE; status stays en_route.
        let (status, v) = put_gps_transition(
            &app,
            pinned,
            guard,
            "guard",
            "arrived",
            Some(gps_body(north_of_site(400.0), None)),
        )
        .await;
        assert_eq!(status, StatusCode::CONFLICT, "far fix must be rejected");
        assert_eq!(
            v["error"]["code"],
            crate::domain::geo::NOT_AT_SITE_CODE,
            "arrive geofence 409 must carry NOT_AT_SITE, got: {v}"
        );

        // Pinned + NO GPS (empty body, old build) → 409 GPS_REQUIRED (fail closed).
        let (status, v) = put_gps_transition(&app, pinned, guard, "guard", "arrived", None).await;
        assert_eq!(
            status,
            StatusCode::CONFLICT,
            "pinned + no fix must be rejected"
        );
        assert_eq!(
            v["error"]["code"],
            crate::domain::geo::GPS_REQUIRED_CODE,
            "missing-fix 409 must carry GPS_REQUIRED, got: {v}"
        );
        // ...neither rejection advanced the status.
        let st: String =
            sqlx::query_scalar("SELECT status::text FROM booking.bookings WHERE id = $1")
                .bind(pinned)
                .fetch_one(&db)
                .await
                .expect("read status");
        assert_eq!(
            st, "en_route",
            "a geofence-rejected arrive must not advance status"
        );

        // INSIDE the fence (100m out but ±30m accuracy widens 120 → 150) → 200, status `arrived`,
        // the fix persisted (audit evidence of on-site presence).
        let (status, v) = put_gps_transition(
            &app,
            pinned,
            guard,
            "guard",
            "arrived",
            Some(gps_body(north_of_site(100.0), Some(30.0))),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "in-fence fix must arrive: {v}");
        assert_eq!(
            v["data"]["status"],
            serde_json::json!("arrived"),
            "status must be arrived: {v}"
        );
        let (alat, aacc): (Option<f64>, Option<f32>) = sqlx::query_as(
            "SELECT arrived_lat, arrived_accuracy_m FROM booking.bookings WHERE id = $1",
        )
        .bind(pinned)
        .fetch_one(&db)
        .await
        .expect("read persisted arrived fix");
        assert!(alat.is_some(), "the accepted arrive fix must be persisted");
        assert_eq!(aacc, Some(30.0), "the reported accuracy must be persisted");

        // UNPINNED booking (no site coordinates) + no GPS → 200 (geofence skips).
        let guard2 = Uuid::new_v4();
        let unpinned = seed_to(&db, None, guard2, BookingStatus::EnRoute).await;
        let (status, v) =
            put_gps_transition(&app, unpinned, guard2, "guard", "arrived", None).await;
        assert_eq!(
            status,
            StatusCode::OK,
            "unpinned booking arrives without GPS: {v}"
        );

        // ADMIN bypass: a far fix on a pinned booking still 200s (support acting off-site). The
        // admin actor is not the assigned guard — is_admin bypasses participation + fence.
        let guard3 = Uuid::new_v4();
        let pinned_admin = seed_to(&db, Some(START_SITE), guard3, BookingStatus::EnRoute).await;
        let (status, v) = put_gps_transition(
            &app,
            pinned_admin,
            Uuid::new_v4(),
            "admin",
            "arrived",
            Some(gps_body(north_of_site(999.0), None)),
        )
        .await;
        assert_eq!(
            status,
            StatusCode::OK,
            "admin bypasses the arrive fence: {v}"
        );
        assert_eq!(
            v["data"]["status"],
            serde_json::json!("arrived"),
            "admin arrive advances: {v}"
        );

        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = ANY($1)")
            .bind(vec![pinned, unpinned, pinned_admin])
            .execute(&db)
            .await;
    }

    /// `GET /admin/bookings?guard_id=&customer_id=` narrows the cross-user list to one guard's
    /// jobs / one customer's bookings (the admin drill-down behind the web-admin guard- and
    /// customer-detail screens). Fresh per-run UUIDs mean each filter matches exactly its seeded
    /// row, so we can assert an exact id set even against a shared DB. Needs a MIGRATED database
    /// + Redis; SKIPs hermetically otherwise. Run:
    ///   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    ///   TEST_REDIS_URL=redis://localhost:6379 \
    ///     cargo test -p pguard-booking -- admin_list_bookings_filters --nocapture
    #[tokio::test]
    async fn admin_list_bookings_filters_by_guard_and_customer() {
        let Some((app, db)) = router_with_real_db().await else {
            eprintln!("SKIP: no DATABASE_URL + TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };

        // Two customers; booking A is assigned to guard G, booking B stays unassigned.
        let customer_a = Uuid::new_v4();
        let customer_b = Uuid::new_v4();
        let guard_g = Uuid::new_v4();
        let mk = |customer: Uuid, addr: &'static str| {
            let db = db.clone();
            async move {
                repo::create_booking(
                    &db,
                    customer,
                    &CreateBookingRequest {
                        address: addr.to_string(),
                        scheduled_at: chrono::Utc::now(),
                        hours: 4,
                        service_id: None,
                        target_guard_id: None,
                        guard_count: None,
                        tip: None,
                        lat: None,
                        lng: None,
                    },
                    1,
                    rust_decimal::Decimal::ZERO,
                    None,
                    Uuid::new_v4(),
                )
                .await
                .expect("create")
            }
        };
        let booking_a = mk(customer_a, "1 Filter A Rd").await;
        let booking_b = mk(customer_b, "2 Filter B Rd").await;
        repo::transition(
            &db,
            booking_a.id,
            guard_g,
            false,
            BookingStatus::Accepted,
            Some(guard_g),
            None,
            Uuid::new_v4(),
        )
        .await
        .expect("assign guard_g to booking A");

        // Fetch /admin/bookings with a query and return the set of returned booking ids.
        let ids_for = |query: String| {
            let app = app.clone();
            async move {
                let res = app
                    .oneshot(
                        Request::builder()
                            .method("GET")
                            .uri(format!("/admin/bookings?{query}"))
                            .header("authorization", format!("Bearer {}", user_token("admin")))
                            .body(Body::empty())
                            .unwrap(),
                    )
                    .await
                    .unwrap();
                assert_eq!(res.status(), StatusCode::OK, "query: {query}");
                let body = axum::body::to_bytes(res.into_body(), 1 << 20)
                    .await
                    .unwrap();
                let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
                v["data"]
                    .as_array()
                    .expect("data array")
                    .iter()
                    .map(|b| b["id"].as_str().unwrap().to_string())
                    .collect::<Vec<_>>()
            }
        };

        // guard_id=G → exactly booking A (fresh UUID → no other rows match).
        let by_guard = ids_for(format!("guard_id={guard_g}")).await;
        assert_eq!(
            by_guard,
            vec![booking_a.id.to_string()],
            "guard_id filter must return only that guard's booking"
        );

        // customer_id=B → exactly booking B.
        let by_customer = ids_for(format!("customer_id={customer_b}")).await;
        assert_eq!(
            by_customer,
            vec![booking_b.id.to_string()],
            "customer_id filter must return only that customer's booking"
        );

        // Combined guard_id=G & customer_id=B → empty (A is G's but customer A's).
        let combined = ids_for(format!("guard_id={guard_g}&customer_id={customer_b}")).await;
        assert!(
            combined.is_empty(),
            "AND of mismatched guard/customer filters returns nothing, got {combined:?}"
        );

        let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = ANY($1)")
            .bind(vec![booking_a.id, booking_b.id])
            .execute(&db)
            .await;
    }

    // ----- internal read: service-JWT guard (no Redis/DB needed) -----

    const SERVICE_SECRET: &str =
        "service-secret-at-least-64-characters-long-for-internal-hs256-test!!";

    #[derive(Clone)]
    struct InternalDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
    }

    impl shared::service_jwt::HasServiceJwt for InternalDeps {
        fn service_decoding_key(&self) -> &DecodingKey {
            &self.dec
        }
    }
    impl BookingInternalDeps for InternalDeps {
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
    }

    /// Build the internal router over a lightweight test state. The `ServiceCaller`
    /// extractor only needs the service decoding key — no Redis, no live DB. Rejected
    /// requests short-circuit at the guard before any DB access, so a lazy pool to a
    /// closed port is safe (mirrors identity's internal_revoke_all test).
    fn internal_router() -> Router {
        let db = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://invalid:invalid@127.0.0.1:1/none")
            .expect("lazy pool");
        let deps = InternalDeps {
            dec: Arc::new(DecodingKey::from_secret(SERVICE_SECRET.as_bytes())),
            db,
        };
        Router::new()
            .route(
                "/internal/bookings/{id}",
                get(get_internal_booking::<InternalDeps>),
            )
            .with_state(deps)
    }

    const INTERNAL_URI: &str = "/internal/bookings/00000000-0000-0000-0000-000000000001";

    #[tokio::test]
    async fn internal_read_rejects_missing_token() {
        let res = internal_router()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(INTERNAL_URI)
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn internal_read_rejects_invalid_token() {
        let res = internal_router()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(INTERNAL_URI)
                    .header("authorization", "Bearer not.a.valid.jwt")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn internal_read_accepts_valid_service_token() {
        // A valid service-JWT (as minted by the payment service) must pass the guard. The
        // handler then queries the (unreachable) DB, so the response is NOT 401 — proving
        // auth was accepted before any DB access.
        use jsonwebtoken::EncodingKey;
        use shared::service_jwt::encode_service_jwt;
        let ek = EncodingKey::from_secret(SERVICE_SECRET.as_bytes());
        let tok = encode_service_jwt("payment", &ek, 60).unwrap();
        let res = internal_router()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(INTERNAL_URI)
                    .header("authorization", format!("Bearer {tok}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_ne!(
            res.status(),
            StatusCode::UNAUTHORIZED,
            "valid service token must pass the guard"
        );
    }

    // ----- /available-guards discovery aggregation (stub readers; Redis-gated for AuthUser) -----

    use crate::discovery_client::{
        BusyGuardsReader, CatalogGuard, GuardCatalog, GuardRatingSummary, PresenceReader,
        RatingReader,
    };
    use std::collections::{HashMap, HashSet};

    /// A live-set stub value from ids, all at a throwaway origin coord: the filter / order / merge
    /// tests don't pass a meetup point, so the exact position is irrelevant (the nearest-first
    /// sort has its own test, [`available_guards_sorts_nearest_to_meetup`], with real coordinates).
    fn live_at_origin<const N: usize>(ids: [Uuid; N]) -> HashMap<Uuid, (f64, f64)> {
        ids.into_iter().map(|id| (id, (0.0, 0.0))).collect()
    }

    /// Catalog stub — returns a canned approved-guard list, no HTTP.
    #[derive(Clone)]
    struct StubCatalog {
        guards: Vec<CatalogGuard>,
    }
    impl GuardCatalog for StubCatalog {
        async fn list_approved_guards(&self) -> Result<Vec<CatalogGuard>, AppError> {
            Ok(self.guards.clone())
        }
    }

    /// A minimal catalog guard for the filter/order tests that don't care about the
    /// name/avatar (those default to `None`); the merge test constructs `CatalogGuard`
    /// explicitly to assert the name + presigned avatar thread through.
    fn catalog_guard(user_id: Uuid, years_of_experience: Option<i32>) -> CatalogGuard {
        CatalogGuard {
            user_id,
            full_name: None,
            avatar_url: None,
            years_of_experience,
            has_documents: None,
            documents: None,
        }
    }

    /// Presence stub — `online` maps each LIVE guard to its position (guard_id → (lat, lng));
    /// `down=true` makes the consult ERROR so the handler's FAIL-OPEN path (unfiltered list) is
    /// exercised. Membership drives the online filter; the coords drive the nearest-first sort.
    #[derive(Clone)]
    struct StubPresence {
        online: HashMap<Uuid, (f64, f64)>,
        down: bool,
    }
    impl PresenceReader for StubPresence {
        async fn online_guard_locations(&self) -> Result<HashMap<Uuid, (f64, f64)>, AppError> {
            if self.down {
                Err(AppError::Internal("presence unreachable".to_string()))
            } else {
                Ok(self.online.clone())
            }
        }
    }

    /// Busy-guards stub — `busy` is the set of guards holding an active assignment (excluded
    /// from discovery); `down=true` makes the lookup ERROR so the handler's FAIL-CLOSED path
    /// (propagate the error) is exercised.
    #[derive(Clone)]
    struct StubBusy {
        busy: HashSet<Uuid>,
        down: bool,
    }
    impl BusyGuardsReader for StubBusy {
        async fn busy_guard_ids(&self) -> Result<HashSet<Uuid>, AppError> {
            if self.down {
                Err(AppError::Internal("booking DB unreachable".to_string()))
            } else {
                Ok(self.busy.clone())
            }
        }

        async fn busy_guard_ids_overlapping(
            &self,
            _window_start: chrono::DateTime<chrono::Utc>,
            _window_hours: i32,
        ) -> Result<HashSet<Uuid>, AppError> {
            // The stub ignores the window (tests drive the busy set directly); same fail-closed path.
            self.busy_guard_ids().await
        }
    }

    /// Rating stub — returns avg 4.50/count 2 for `good`, and ERRORS for any other guard so
    /// the handler's best-effort default (None/0) path is exercised.
    #[derive(Clone)]
    struct StubRater {
        good: Uuid,
    }
    impl RatingReader for StubRater {
        async fn guard_summary(&self, guard_id: Uuid) -> Result<GuardRatingSummary, AppError> {
            if guard_id == self.good {
                Ok(GuardRatingSummary {
                    average: Some("4.50".parse().unwrap()),
                    count: 2,
                })
            } else {
                Err(AppError::Internal("rating unreachable".to_string()))
            }
        }
    }

    #[derive(Clone)]
    struct DiscoveryTestDeps {
        dec: Arc<DecodingKey>,
        redis: redis::aio::ConnectionManager,
        catalog: StubCatalog,
        rater: StubRater,
        presence: StubPresence,
        busy: StubBusy,
    }
    impl HasJwtSecret for DiscoveryTestDeps {
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
    impl crate::state::DiscoveryDeps for DiscoveryTestDeps {
        type Catalog = StubCatalog;
        type Rating = StubRater;
        type Presence = StubPresence;
        type Busy = StubBusy;
        fn guard_catalog(&self) -> &StubCatalog {
            &self.catalog
        }
        fn rating_reader(&self) -> &StubRater {
            &self.rater
        }
        fn presence_reader(&self) -> &StubPresence {
            &self.presence
        }
        fn busy_guards(&self) -> &StubBusy {
            &self.busy
        }
    }

    /// No guard is busy (the common case for the catalog+rating+online tests). The
    /// active-assignment exclusion is exercised by its own tests via [`discovery_router_with`].
    fn no_busy() -> StubBusy {
        StubBusy {
            busy: HashSet::new(),
            down: false,
        }
    }

    async fn discovery_router(
        catalog: StubCatalog,
        rater: StubRater,
        presence: StubPresence,
    ) -> Option<Router> {
        discovery_router_with(catalog, rater, presence, no_busy()).await
    }

    async fn discovery_router_with(
        catalog: StubCatalog,
        rater: StubRater,
        presence: StubPresence,
        busy: StubBusy,
    ) -> Option<Router> {
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .ok()?;
        // available_guards reads only the (stubbed) ports — no live pool needed.
        let deps = DiscoveryTestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            redis,
            catalog,
            rater,
            presence,
            busy,
        };
        Some(
            Router::new()
                .route(
                    "/available-guards",
                    get(available_guards::<DiscoveryTestDeps>),
                )
                .with_state(deps),
        )
    }

    fn user_token(role: &str) -> String {
        use shared::auth::encode_jwt_with_key;
        let ek = jsonwebtoken::EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, _jti) = encode_jwt_with_key(Uuid::new_v4(), role, 0, &ek, 15).unwrap();
        tok
    }

    #[tokio::test]
    async fn available_guards_rejects_missing_token() {
        let app = discovery_router(
            StubCatalog { guards: vec![] },
            StubRater {
                good: Uuid::new_v4(),
            },
            StubPresence {
                online: HashMap::new(),
                down: false,
            },
        )
        .await;
        let Some(app) = app else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/available-guards")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn available_guards_merges_catalog_and_ratings_best_effort() {
        let good = Uuid::new_v4(); // has a rating
        let bad = Uuid::new_v4(); // rating lookup errors → best-effort default
        let catalog = StubCatalog {
            guards: vec![
                CatalogGuard {
                    user_id: good,
                    full_name: Some("Somchai Jaidee".to_string()),
                    avatar_url: Some("https://minio.example/presigned-good".to_string()),
                    years_of_experience: Some(5),
                    has_documents: Some(true),
                    documents: None,
                },
                CatalogGuard {
                    user_id: bad,
                    full_name: None,
                    avatar_url: None,
                    years_of_experience: None,
                    has_documents: Some(false),
                    documents: None,
                },
            ],
        };
        // Both guards are online so this test stays focused on the catalog+rating merge.
        let online = live_at_origin([good, bad]);
        let Some(app) = discovery_router(
            catalog,
            StubRater { good },
            StubPresence {
                online,
                down: false,
            },
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/available-guards")
                    .header(
                        "authorization",
                        format!("Bearer {}", user_token("customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        let body = axum::body::to_bytes(res.into_body(), 1 << 20)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let data = v["data"].as_array().expect("data array");
        assert_eq!(data.len(), 2, "both approved guards listed");
        // Order preserved (catalog order): good first, then bad.
        assert_eq!(data[0]["guard_id"], serde_json::json!(good));
        assert_eq!(data[0]["average_rating"], serde_json::json!("4.50"));
        assert_eq!(data[0]["review_count"], serde_json::json!(2));
        assert_eq!(data[0]["years_of_experience"], serde_json::json!(5));
        // The catalog's name + presigned avatar + documents boolean thread through to the
        // selection card.
        assert_eq!(data[0]["display_name"], serde_json::json!("Somchai Jaidee"));
        assert_eq!(
            data[0]["avatar_url"],
            serde_json::json!("https://minio.example/presigned-good")
        );
        assert_eq!(data[0]["has_documents"], serde_json::json!(true));
        // The guard whose rating lookup failed still appears, with best-effort defaults.
        assert_eq!(data[1]["guard_id"], serde_json::json!(bad));
        assert!(
            data[1]["average_rating"].is_null(),
            "no rating → null average"
        );
        assert_eq!(data[1]["review_count"], serde_json::json!(0));
        // Absent name/avatar are OMITTED from the JSON (skip_serializing_if), not null keys.
        assert!(
            data[1].get("display_name").is_none(),
            "no name → key omitted"
        );
        assert!(
            data[1].get("avatar_url").is_none(),
            "no avatar → key omitted"
        );
        assert_eq!(
            data[1]["has_documents"],
            serde_json::json!(false),
            "profile said no documents → explicit false"
        );
    }

    #[tokio::test]
    async fn available_guards_omits_unknown_has_documents() {
        // An OLDER profile that doesn't emit `has_documents` (CatalogGuard defaults to None)
        // must produce an OMITTED key — never a false "no documents" claim — during a
        // mixed-version deploy window.
        let g = Uuid::new_v4();
        let catalog = StubCatalog {
            guards: vec![catalog_guard(g, None)],
        };
        let Some(app) = discovery_router(
            catalog,
            StubRater { good: g },
            StubPresence {
                online: live_at_origin([g]),
                down: false,
            },
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/available-guards")
                    .header(
                        "authorization",
                        format!("Bearer {}", user_token("customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        let body = axum::body::to_bytes(res.into_body(), 1 << 20)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let data = v["data"].as_array().expect("data array");
        assert_eq!(data.len(), 1);
        assert!(
            data[0].get("has_documents").is_none(),
            "unknown documents state → key omitted (tri-state), not false"
        );
    }

    #[tokio::test]
    async fn available_guards_passes_through_per_type_documents() {
        // profile supplies the per-credential presence breakdown; discovery must pass it through
        // VERBATIM so the customer sees WHICH credential TYPES are on file (never the files).
        let g = Uuid::new_v4();
        let catalog = StubCatalog {
            guards: vec![CatalogGuard {
                user_id: g,
                full_name: None,
                avatar_url: None,
                years_of_experience: None,
                has_documents: Some(false),
                documents: Some(crate::models::GuardDocuments {
                    id_card: true,
                    security_license: true,
                    training_cert: false,
                    criminal_check: true,
                    driver_license: false,
                }),
            }],
        };
        let Some(app) = discovery_router(
            catalog,
            StubRater { good: g },
            StubPresence {
                online: live_at_origin([g]),
                down: false,
            },
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/available-guards")
                    .header(
                        "authorization",
                        format!("Bearer {}", user_token("customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        let body = axum::body::to_bytes(res.into_body(), 1 << 20)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let docs = &v["data"][0]["documents"];
        assert_eq!(docs["id_card"], serde_json::json!(true));
        assert_eq!(docs["security_license"], serde_json::json!(true));
        assert_eq!(docs["training_cert"], serde_json::json!(false));
        assert_eq!(docs["criminal_check"], serde_json::json!(true));
        assert_eq!(docs["driver_license"], serde_json::json!(false));
    }

    /// Issue the discovery request and return the `data` guard_ids as a `Vec<String>`, or `None`
    /// if the hermetic Redis dependency is absent (caller SKIPs).
    async fn discovery_guard_ids(
        catalog: StubCatalog,
        rater: StubRater,
        presence: StubPresence,
    ) -> Option<Vec<String>> {
        let app = discovery_router(catalog, rater, presence).await?;
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/available-guards")
                    .header(
                        "authorization",
                        format!("Bearer {}", user_token("customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        let body = axum::body::to_bytes(res.into_body(), 1 << 20)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        Some(
            v["data"]
                .as_array()
                .expect("data array")
                .iter()
                .map(|g| g["guard_id"].as_str().expect("guard_id").to_string())
                .collect(),
        )
    }

    /// The fix: an OFFLINE approved guard (not in presence's live set) is excluded; an ONLINE
    /// one is included.
    #[tokio::test]
    async fn available_guards_excludes_offline_includes_online() {
        let online_guard = Uuid::new_v4();
        let offline_guard = Uuid::new_v4();
        let catalog = StubCatalog {
            guards: vec![
                catalog_guard(online_guard, Some(3)),
                catalog_guard(offline_guard, Some(7)),
            ],
        };
        let Some(ids) = discovery_guard_ids(
            catalog,
            StubRater { good: online_guard },
            StubPresence {
                online: live_at_origin([online_guard]), // only the online guard is live
                down: false,
            },
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(ids, vec![online_guard.to_string()], "offline guard dropped");
    }

    /// FAIL-OPEN: when the presence consult errors, the FULL approved list is returned
    /// (unfiltered) — a presence hiccup must never block all bookings.
    #[tokio::test]
    async fn available_guards_fails_open_when_presence_down() {
        let a = Uuid::new_v4();
        let b = Uuid::new_v4();
        let catalog = StubCatalog {
            guards: vec![catalog_guard(a, Some(1)), catalog_guard(b, Some(2))],
        };
        let Some(ids) = discovery_guard_ids(
            catalog,
            StubRater { good: a },
            StubPresence {
                online: HashMap::new(), // would exclude EVERYONE if it were consulted...
                down: true,             // ...but presence is down → fail-open → show all
            },
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(
            ids,
            vec![a.to_string(), b.to_string()],
            "presence down → fail-open: all approved guards shown unfiltered"
        );
    }

    /// Like [`discovery_guard_ids`] but with an explicit busy-guards stub (the active-assignment
    /// exclusion). Returns the `data` guard_ids, or `None` if Redis is absent (caller SKIPs).
    async fn discovery_guard_ids_with(
        catalog: StubCatalog,
        rater: StubRater,
        presence: StubPresence,
        busy: StubBusy,
    ) -> Option<Vec<String>> {
        let app = discovery_router_with(catalog, rater, presence, busy).await?;
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/available-guards")
                    .header(
                        "authorization",
                        format!("Bearer {}", user_token("customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        let body = axum::body::to_bytes(res.into_body(), 1 << 20)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        Some(
            v["data"]
                .as_array()
                .expect("data array")
                .iter()
                .map(|g| g["guard_id"].as_str().expect("guard_id").to_string())
                .collect(),
        )
    }

    /// The discovery fix: a BUSY guard (one holding an active assignment) is EXCLUDED even though
    /// they are approved AND online — a guard already working a job must never be offered. The
    /// FREE online guard is still listed.
    #[tokio::test]
    async fn available_guards_excludes_busy_with_active_assignment() {
        let free = Uuid::new_v4();
        let busy_guard = Uuid::new_v4();
        let catalog = StubCatalog {
            guards: vec![
                catalog_guard(free, Some(2)),
                catalog_guard(busy_guard, Some(9)),
            ],
        };
        let Some(ids) = discovery_guard_ids_with(
            catalog,
            StubRater { good: free },
            // Both online — so the ONLY reason busy_guard is hidden is the active-assignment filter.
            StubPresence {
                online: live_at_origin([free, busy_guard]),
                down: false,
            },
            StubBusy {
                busy: HashSet::from([busy_guard]),
                down: false,
            },
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        assert_eq!(
            ids,
            vec![free.to_string()],
            "the guard with an active assignment is excluded; only the free guard is offered"
        );
    }

    /// FAIL-CLOSED on the busy lookup: unlike presence (fail-open), an error reading booking's own
    /// schema for active assignments propagates as 500 — a local-DB outage must not silently offer
    /// a possibly-busy guard (which would let two customers book the same guard).
    #[tokio::test]
    async fn available_guards_fails_closed_when_busy_lookup_errors() {
        let a = Uuid::new_v4();
        let catalog = StubCatalog {
            guards: vec![catalog_guard(a, Some(1))],
        };
        let Some(app) = discovery_router_with(
            catalog,
            StubRater { good: a },
            StubPresence {
                online: live_at_origin([a]),
                down: false,
            },
            StubBusy {
                busy: HashSet::new(),
                down: true, // booking DB unreachable
            },
        )
        .await
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/available-guards")
                    .header(
                        "authorization",
                        format!("Bearer {}", user_token("customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::INTERNAL_SERVER_ERROR,
            "a busy-lookup error must fail closed (never offer a possibly-busy guard)"
        );
    }

    /// C2: with a MEETUP point in the query, the discovery list is sorted NEAREST-first by the
    /// guards' live positions, and each entry carries `distance_m`. The catalog lists the FAR
    /// guard first, so a near-first result proves the server re-sorted. Redis-gated (AuthUser) →
    /// hermetic SKIP.
    #[tokio::test]
    async fn available_guards_sorts_nearest_to_meetup() {
        let near = Uuid::new_v4();
        let far = Uuid::new_v4();
        // Catalog lists FAR first — the server must reorder to near-first.
        let catalog = StubCatalog {
            guards: vec![catalog_guard(far, Some(1)), catalog_guard(near, Some(2))],
        };
        let presence = StubPresence {
            online: HashMap::from([(near, north_of_site(100.0)), (far, north_of_site(2000.0))]),
            down: false,
        };
        let Some(app) = discovery_router(catalog, StubRater { good: near }, presence).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(format!(
                        "/available-guards?lat={}&lng={}",
                        START_SITE.0, START_SITE.1
                    ))
                    .header(
                        "authorization",
                        format!("Bearer {}", user_token("customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        let body = axum::body::to_bytes(res.into_body(), 1 << 20)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let data = v["data"].as_array().expect("data array");
        assert_eq!(data.len(), 2);
        // Nearest first (near before far) despite the reversed catalog order.
        assert_eq!(
            data[0]["guard_id"],
            serde_json::json!(near),
            "nearest guard sorts first"
        );
        assert_eq!(
            data[1]["guard_id"],
            serde_json::json!(far),
            "farther guard sorts last"
        );
        // distance_m is present and ascending (~100m then ~2000m).
        let d0 = data[0]["distance_m"]
            .as_f64()
            .expect("distance_m on nearest");
        let d1 = data[1]["distance_m"]
            .as_f64()
            .expect("distance_m on farther");
        assert!((d0 - 100.0).abs() < 5.0, "nearest ~100m, got {d0}");
        assert!((d1 - 2000.0).abs() < 20.0, "farther ~2000m, got {d1}");
        assert!(d0 < d1, "distances must be ascending");
    }

    /// Without a meetup point in the query, discovery keeps the CATALOG order and OMITS
    /// `distance_m` — backward compatible, even when the guards have distinct live positions.
    #[tokio::test]
    async fn available_guards_omits_distance_without_meetup() {
        let a = Uuid::new_v4();
        let b = Uuid::new_v4();
        let catalog = StubCatalog {
            guards: vec![catalog_guard(a, Some(1)), catalog_guard(b, Some(2))],
        };
        // Distinct coords, but no meetup in the query → the server must NOT sort or emit distance.
        let presence = StubPresence {
            online: HashMap::from([(a, north_of_site(2000.0)), (b, north_of_site(50.0))]),
            down: false,
        };
        let Some(app) = discovery_router(catalog, StubRater { good: a }, presence).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/available-guards")
                    .header(
                        "authorization",
                        format!("Bearer {}", user_token("customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK);
        let body = axum::body::to_bytes(res.into_body(), 1 << 20)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let data = v["data"].as_array().expect("data array");
        // Catalog order preserved (a before b) despite b being physically nearer some point.
        assert_eq!(data[0]["guard_id"], serde_json::json!(a));
        assert_eq!(data[1]["guard_id"], serde_json::json!(b));
        // distance_m omitted from the JSON (skip_serializing_if), not a null key.
        assert!(
            data[0].get("distance_m").is_none(),
            "no meetup → distance_m omitted"
        );
    }

    // ----- Catalog field validation (hermetic — no DB) -----

    /// The shared create/update validator DELEGATES the two money knobs to the pure
    /// `domain::pricing` rules (their own exhaustive tests live there) and returns the
    /// NORMALIZED pair the handler persists. This asserts the wiring: a bad commission /
    /// cancellation fee is a TYPED 400 the admin UI can localize, and a good one comes back
    /// rounded to the columns' 2-dp scale rather than being silently rounded by Postgres.
    #[test]
    fn service_fields_validate_and_normalize_the_money_knobs() {
        let ok = |pct: &str, fee: &str| {
            validate_service_fields(
                "ชื่อ",
                "name",
                "230.00".parse().unwrap(),
                3,
                None,
                pct.parse().unwrap(),
                fee.parse().unwrap(),
            )
        };

        let (pct, fee) = ok("12.506", "150.004").expect("in-range values are accepted");
        assert_eq!(pct, "12.51".parse::<rust_decimal::Decimal>().unwrap());
        assert_eq!(fee, "150.00".parse::<rust_decimal::Decimal>().unwrap());

        for bad in ["-1", "100.01"] {
            let err = ok(bad, "0").expect_err("out-of-range commission must be refused");
            assert!(
                matches!(
                    err,
                    AppError::BadRequestCode {
                        code: crate::domain::pricing::COMMISSION_PERCENT_INVALID_CODE,
                        ..
                    }
                ),
                "commission {bad} → typed 400, got {err:?}"
            );
        }
        let err = ok("0", "-0.01").expect_err("a negative cancellation fee must be refused");
        assert!(
            matches!(
                err,
                AppError::BadRequestCode {
                    code: crate::domain::pricing::CANCELLATION_FEE_INVALID_CODE,
                    ..
                }
            ),
            "negative fee → typed 400, got {err:?}"
        );
    }

    /// The WIRE shape of the two snapshot fields, which mobile + web-admin parse: money is a
    /// JSON STRING (the workspace `serde-str` money rule, like `base_fee`/`tip`), and a
    /// pre-migration-0010 booking sends `null` — never a silently-invented `0`, which would tell
    /// a client "these terms were agreed" about a booking that never saw them. Hermetic.
    #[test]
    fn booking_snapshot_serializes_as_money_strings_or_null() {
        let mut booking = BookingResponse {
            id: Uuid::new_v4(),
            customer_id: Uuid::new_v4(),
            guard_id: None,
            status: "requested".to_string(),
            address: "1 Wire Rd".to_string(),
            scheduled_at: Utc::now(),
            hours: 4,
            base_fee: "230.00".parse().unwrap(),
            guard_count: 1,
            tip: rust_decimal::Decimal::ZERO,
            lat: None,
            lng: None,
            target_guard_id: None,
            work_started_at: None,
            paid_at: None,
            actual_seconds: None,
            cancellation_reason: None,
            cancellation_note: None,
            commission_percent: Some("12.50".parse().unwrap()),
            cancellation_fee: Some("150.00".parse().unwrap()),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };
        let v = serde_json::to_value(&booking).expect("serialize");
        assert_eq!(v["commission_percent"], serde_json::json!("12.50"));
        assert_eq!(v["cancellation_fee"], serde_json::json!("150.00"));

        booking.commission_percent = None;
        booking.cancellation_fee = None;
        let v = serde_json::to_value(&booking).expect("serialize");
        assert!(v["commission_percent"].is_null(), "pre-0010 booking → null");
        assert!(v["cancellation_fee"].is_null(), "pre-0010 booking → null");
    }

    // ----- Service catalog → charge-path wiring (full router; real DB + Redis) -----

    /// End-to-end over the router: `GET /services` is reachable by a NON-admin customer (no
    /// admin gate) and lists the seeded ACTIVE service; `POST /bookings` with that
    /// `service_id` uses the catalog's `base_fee` (not the column default) and enforces its
    /// `min_hours` floor (below-min → 400); an unknown/inactive `service_id` → 404; a booking
    /// WITHOUT a `service_id` still works (back-compat) and snapshots 0/0; and the catalog's
    /// `commission_percent`/`cancellation_fee` land on the booking it was created from. Gated on
    /// DATABASE_URL + Redis (hermetic SKIP otherwise).
    #[tokio::test]
    async fn services_list_and_booking_charge_wiring() {
        let Some((app, db)) = router_with_real_db().await else {
            eprintln!("SKIP: no DATABASE_URL + TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };

        // Seed one active service (min 3h, ฿230/hr, 12.5% commission, ฿150 cancellation fee)
        // and one deactivated service.
        let marker = Uuid::new_v4().to_string();
        let active = repo::create_service(
            &db,
            &CreateServiceRequest {
                name_th: format!("th-{marker}"),
                name_en: format!("en-{marker}"),
                base_fee: "230.00".parse().unwrap(),
                min_hours: 3,
                commission_percent: "12.50".parse().unwrap(),
                cancellation_fee: "150.00".parse().unwrap(),
                notes: Some(format!("desc-{marker}")),
            },
        )
        .await
        .expect("seed active");
        let inactive = repo::create_service(
            &db,
            &CreateServiceRequest {
                name_th: format!("th-x-{marker}"),
                name_en: format!("en-x-{marker}"),
                base_fee: "999.00".parse().unwrap(),
                min_hours: 1,
                commission_percent: rust_decimal::Decimal::ZERO,
                cancellation_fee: rust_decimal::Decimal::ZERO,
                notes: None,
            },
        )
        .await
        .expect("seed inactive");
        repo::deactivate_service(&db, inactive.id)
            .await
            .expect("deactivate");

        let customer = Uuid::new_v4();

        // GET /services as a NON-admin customer → 200, lists the active (not the inactive) one.
        let res = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/services")
                    .header(
                        "authorization",
                        format!("Bearer {}", user_token_for(customer, "customer")),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::OK,
            "the customer-facing picker is NOT admin-gated"
        );
        let body = axum::body::to_bytes(res.into_body(), 1 << 20)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let data = v["data"].as_array().expect("data array");
        let active_entry = data
            .iter()
            .find(|s| s["id"] == serde_json::json!(active.id))
            .expect("active service is listed");
        assert_eq!(active_entry["base_fee"], serde_json::json!("230.00"));
        assert_eq!(active_entry["min_hours"], serde_json::json!(3));
        // notes is surfaced as the customer-facing package description (the picker shows it).
        assert_eq!(
            active_entry["notes"],
            serde_json::json!(format!("desc-{marker}")),
            "notes is the customer-facing description"
        );
        // is_active stays admin-only — never leaked to the customer projection.
        assert!(
            active_entry.get("is_active").is_none(),
            "is_active is admin-only"
        );
        assert!(
            !data
                .iter()
                .any(|s| s["id"] == serde_json::json!(inactive.id)),
            "a deactivated service is not offered to customers"
        );

        // POST /bookings: helper to create as the customer with an optional service_id + hours.
        let create = |service_id: Option<Uuid>, hours: i32| {
            let app = app.clone();
            let token = user_token_for(customer, "customer");
            async move {
                // Future scheduled_at — SCHEDULED_IN_PAST rejects past/now at create.
                let sched = (chrono::Utc::now() + chrono::Duration::days(1)).to_rfc3339();
                let mut body = serde_json::json!({
                    "address": "1 Charge Wiring Rd",
                    "scheduled_at": sched,
                    "hours": hours,
                });
                if let Some(sid) = service_id {
                    body["service_id"] = serde_json::json!(sid);
                }
                app.oneshot(
                    Request::builder()
                        .method("POST")
                        .uri("/bookings")
                        .header("authorization", format!("Bearer {token}"))
                        .header("content-type", "application/json")
                        .body(Body::from(body.to_string()))
                        .unwrap(),
                )
                .await
                .unwrap()
            }
        };

        // (a) valid service_id, hours ≥ min_hours → 200; booking carries the CATALOG base_fee.
        let res = create(Some(active.id), 4).await;
        assert_eq!(res.status(), StatusCode::OK, "valid service booking");
        let body = axum::body::to_bytes(res.into_body(), 1 << 20)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let booking_id: Uuid = serde_json::from_value(v["data"]["id"].clone()).unwrap();
        assert_eq!(
            v["data"]["base_fee"],
            serde_json::json!("230.00"),
            "the booking's base_fee is the catalog rate"
        );
        // …and so are the two money knobs — SNAPSHOT onto the booking, visible to the apps.
        assert_eq!(
            v["data"]["commission_percent"],
            serde_json::json!("12.50"),
            "the catalog's commission is snapshot onto the booking"
        );
        assert_eq!(
            v["data"]["cancellation_fee"],
            serde_json::json!("150.00"),
            "the catalog's cancellation fee is snapshot onto the booking"
        );

        // (b) below the service minimum → 400 (and no booking is created).
        let res = create(Some(active.id), 2).await;
        assert_eq!(
            res.status(),
            StatusCode::BAD_REQUEST,
            "hours below the service min_hours is rejected"
        );

        // (c) unknown/inactive service_id → 404.
        assert_eq!(
            create(Some(Uuid::new_v4()), 4).await.status(),
            StatusCode::NOT_FOUND,
            "unknown service_id is 404"
        );
        assert_eq!(
            create(Some(inactive.id), 4).await.status(),
            StatusCode::NOT_FOUND,
            "an inactive service_id is 404"
        );

        // (d) back-compat: no service_id still works (200; server-owned default base_fee) and
        // snapshots real ZEROES — "no cut, no fee" — never NULL (NULL is only a pre-0010 row).
        let res = create(None, 1).await;
        assert_eq!(res.status(), StatusCode::OK, "no service_id still works");
        let body = axum::body::to_bytes(res.into_body(), 1 << 20)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let plain_id: Uuid = serde_json::from_value(v["data"]["id"].clone()).unwrap();
        assert_eq!(
            v["data"]["commission_percent"],
            serde_json::json!("0.00"),
            "no service → a real 0 commission, not null"
        );
        assert_eq!(
            v["data"]["cancellation_fee"],
            serde_json::json!("0.00"),
            "no service → a real 0 cancellation fee, not null"
        );

        // (e) editing the catalog AFTERWARDS must not move the money of the booking already
        // made — the whole reason the values are snapshot rather than looked up.
        repo::update_service(
            &db,
            active.id,
            &UpdateServiceRequest {
                name_th: format!("th-{marker}"),
                name_en: format!("en-{marker}"),
                base_fee: "230.00".parse().unwrap(),
                min_hours: 3,
                commission_percent: "40.00".parse().unwrap(),
                cancellation_fee: "900.00".parse().unwrap(),
                notes: Some(format!("desc-{marker}")),
            },
        )
        .await
        .expect("raise the commission after the fact");
        let after = repo::get_booking(&db, booking_id)
            .await
            .expect("re-read the booking made under the OLD terms");
        assert_eq!(
            after.commission_percent,
            Some("12.50".parse().unwrap()),
            "raising the catalog commission must not restate what the guard earned"
        );
        assert_eq!(
            after.cancellation_fee,
            Some("150.00".parse().unwrap()),
            "raising the catalog cancellation fee must not re-price an existing booking"
        );

        // cleanup
        for id in [booking_id, plain_id] {
            let _ = sqlx::query("DELETE FROM booking.bookings WHERE id = $1")
                .bind(id)
                .execute(&db)
                .await;
        }
        for id in [active.id, inactive.id] {
            let _ = sqlx::query("DELETE FROM booking.service_catalog WHERE id = $1")
                .bind(id)
                .execute(&db)
                .await;
        }
    }
}

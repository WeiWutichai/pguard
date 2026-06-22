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

use crate::discovery_client::{GuardCatalog, PresenceReader, RatingReader};
use crate::domain::progress;
use crate::domain::state::BookingStatus;
use crate::models::{
    AdminListBookingsQuery, AssignGuardRequest, AvailableGuard, BookingResponse, BookingsReport,
    CreateBookingRequest, CreateServiceRequest, CustomerBookingStat, InternalBooking,
    ListProgressReportsQuery, NewProgressReport, OpenJobsQuery, ProgressReportResponse,
    PublicServiceItem, ReportRangeQuery, RetentionPoint, ReviewCompletionRequest,
    ServiceCatalogItem, UpdateServiceRequest,
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
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    let booking = repo::transition(
        state.db(),
        id,
        actor,
        is_admin,
        new_status,
        assign_guard,
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
    // Optional site coordinates: both-or-neither, in range (feeds open-job radius discovery).
    progress::validate_coords(req.lat, req.lng)?;
    // Optional catalog service: when picked, the booking's base_fee is resolved SERVER-SIDE
    // from the active catalog entry (never the client body — never trust a client-sent fee),
    // and the service's min_hours floor is enforced. Absent → base_fee falls to the column
    // DEFAULT (back-compat, unchanged). A missing/inactive service id is 404.
    let base_fee = match req.service_id {
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
            Some(service.base_fee)
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
        base_fee,
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
    do_transition(
        &state,
        id,
        user.user_id,
        is_admin,
        BookingStatus::Accepted,
        Some(user.user_id),
    )
    .await
}

/// PUT /bookings/{id}/decline — the ASSIGNED guard withdraws after accepting → declined.
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn decline_booking<S: BookingDeps>(
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
        BookingStatus::Declined,
        None,
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
    )
    .await
}

/// PUT /bookings/{id}/arrived — the assigned guard has arrived (outbox event).
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn arrived_booking<S: BookingDeps>(
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
        BookingStatus::Arrived,
        None,
    )
    .await
}

/// PUT /bookings/{id}/start — the assigned guard starts the job (stamps `work_started_at`,
/// the proration basis). Status stays `arrived`; no event.
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn start_booking<S: BookingDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> Result<Json<ApiResponse<BookingResponse>>, AppError> {
    let is_admin = require_role(&user, ROLE_GUARD)?;
    let booking = repo::start_job(state.db(), id, user.user_id, is_admin).await?;
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
    do_transition(&state, id, user.user_id, is_admin, target, None).await
}

/// PUT /bookings/{id}/cancel — the customer (or admin) cancels a PRE-ARRIVAL booking → cancelled.
#[tracing::instrument(skip(state), fields(user = %user.user_id, booking_id = %id))]
pub async fn cancel_booking<S: BookingDeps>(
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
    if booking.customer_id != user.user_id && booking.guard_id != Some(user.user_id) {
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
    // Discovery is a pure list read → replica (C5.3), like list_bookings.
    let items = repo::list_open_bookings(state.db_read(), geo, limit, offset).await?;
    Ok(Json(ApiResponse::success(items)))
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
fn validate_service_fields(
    name_th: &str,
    name_en: &str,
    base_fee: rust_decimal::Decimal,
    min_hours: i32,
    notes: Option<&str>,
) -> Result<(), AppError> {
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
    Ok(())
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
    Json(req): Json<CreateServiceRequest>,
) -> Result<Json<ApiResponse<ServiceCatalogItem>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    validate_service_fields(
        &req.name_th,
        &req.name_en,
        req.base_fee,
        req.min_hours,
        req.notes.as_deref(),
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
    Json(req): Json<UpdateServiceRequest>,
) -> Result<Json<ApiResponse<ServiceCatalogItem>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    validate_service_fields(
        &req.name_th,
        &req.name_en,
        req.base_fee,
        req.min_hours,
        req.notes.as_deref(),
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
/// FAIL-OPEN on presence: if the presence consult errors/times out, the whole approved list is
/// returned UNFILTERED (with a warning) — a presence hiccup must never blank discovery and block
/// every booking. The happy path filters by online.
///
/// Best-effort on ratings: a guard whose rating lookup fails still appears (with no average /
/// zero count) — one slow dependency never blanks the whole list. Rating lookups run
/// concurrently (bounded) and preserve the catalog's order.
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn available_guards<S: DiscoveryDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<AvailableGuard>>>, AppError> {
    let guards = state.guard_catalog().list_approved_guards().await?;
    let rater = state.rating_reader();

    // Consult presence for who is currently LIVE. `None` => FAIL-OPEN: presence was unreachable,
    // so we do NOT filter (showing the full approved list beats blocking all bookings).
    let online: Option<std::collections::HashSet<Uuid>> = match state
        .presence_reader()
        .online_guard_ids()
        .await
    {
        Ok(set) => Some(set),
        Err(e) => {
            tracing::warn!(
                    "presence online-guards lookup failed: {e}; FAIL-OPEN (returning unfiltered approved list)"
                );
            None
        }
    };

    // Drop offline guards when presence answered; keep all on fail-open. Filtering BEFORE the
    // rating fan-out also means we never spend rating lookups on guards we're about to hide.
    let filtered: Vec<_> = guards
        .into_iter()
        .filter(|g| online.as_ref().is_none_or(|set| set.contains(&g.user_id)))
        .collect();

    // Each entry carries whether its rating lookup fell back (best-effort), so we can emit a
    // single aggregate signal for a degraded list rather than only per-guard warns.
    let merged: Vec<(AvailableGuard, bool)> = futures::stream::iter(filtered)
        .map(|g| async move {
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
                years_of_experience: g.years_of_experience,
                average_rating: summary.average,
                review_count: summary.count,
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
        Body::from(
            serde_json::json!({
                "address": "1 Test Rd",
                "scheduled_at": "2026-06-04T10:00:00Z",
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
        // review-completion deserializes a JSON body; give it the right content-type so the
        // Json extractor succeeds and execution reaches the handler's role gate.
        if subpath == "review-completion" {
            builder = builder.header("content-type", "application/json");
        }
        app.oneshot(builder.body(body).unwrap())
            .await
            .unwrap()
            .status()
    }

    #[tokio::test]
    async fn decline_rejects_non_guard() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // a customer cannot drive a guard-only transition
        let status = lifecycle_req(app, "PUT", "decline", "customer", Body::empty()).await;
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
        // a guard cannot cancel a customer's booking
        let status = lifecycle_req(app, "PUT", "cancel", "guard", Body::empty()).await;
        assert_eq!(status, StatusCode::FORBIDDEN);
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
        for status in [BookingStatus::EnRoute, BookingStatus::Arrived] {
            repo::transition(&db, created.id, guard, false, status, None, Uuid::new_v4())
                .await
                .unwrap_or_else(|e| panic!("transition to {status}: {e:?}"));
        }
        repo::start_job(&db, created.id, guard, false)
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
        CatalogGuard, GuardCatalog, GuardRatingSummary, PresenceReader, RatingReader,
    };
    use std::collections::HashSet;

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

    /// Presence stub — `online` is the LIVE id set returned by the consult; `down=true` makes
    /// the consult ERROR so the handler's FAIL-OPEN path (unfiltered list) is exercised.
    #[derive(Clone)]
    struct StubPresence {
        online: HashSet<Uuid>,
        down: bool,
    }
    impl PresenceReader for StubPresence {
        async fn online_guard_ids(&self) -> Result<HashSet<Uuid>, AppError> {
            if self.down {
                Err(AppError::Internal("presence unreachable".to_string()))
            } else {
                Ok(self.online.clone())
            }
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
        fn guard_catalog(&self) -> &StubCatalog {
            &self.catalog
        }
        fn rating_reader(&self) -> &StubRater {
            &self.rater
        }
        fn presence_reader(&self) -> &StubPresence {
            &self.presence
        }
    }

    async fn discovery_router(
        catalog: StubCatalog,
        rater: StubRater,
        presence: StubPresence,
    ) -> Option<Router> {
        let redis_url = std::env::var("TEST_REDIS_URL")
            .or_else(|_| std::env::var("REDIS_CACHE_URL"))
            .ok()?;
        let redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .ok()?;
        // available_guards never touches the DB (only the readers) — no pool needed.
        let deps = DiscoveryTestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            redis,
            catalog,
            rater,
            presence,
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
                online: HashSet::new(),
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
                    years_of_experience: Some(5),
                },
                CatalogGuard {
                    user_id: bad,
                    years_of_experience: None,
                },
            ],
        };
        // Both guards are online so this test stays focused on the catalog+rating merge.
        let online = HashSet::from([good, bad]);
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
        // The guard whose rating lookup failed still appears, with best-effort defaults.
        assert_eq!(data[1]["guard_id"], serde_json::json!(bad));
        assert!(
            data[1]["average_rating"].is_null(),
            "no rating → null average"
        );
        assert_eq!(data[1]["review_count"], serde_json::json!(0));
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
                CatalogGuard {
                    user_id: online_guard,
                    years_of_experience: Some(3),
                },
                CatalogGuard {
                    user_id: offline_guard,
                    years_of_experience: Some(7),
                },
            ],
        };
        let Some(ids) = discovery_guard_ids(
            catalog,
            StubRater { good: online_guard },
            StubPresence {
                online: HashSet::from([online_guard]), // only the online guard is live
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
            guards: vec![
                CatalogGuard {
                    user_id: a,
                    years_of_experience: Some(1),
                },
                CatalogGuard {
                    user_id: b,
                    years_of_experience: Some(2),
                },
            ],
        };
        let Some(ids) = discovery_guard_ids(
            catalog,
            StubRater { good: a },
            StubPresence {
                online: HashSet::new(), // would exclude EVERYONE if it were consulted...
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

    // ----- Service catalog → charge-path wiring (full router; real DB + Redis) -----

    /// End-to-end over the router: `GET /services` is reachable by a NON-admin customer (no
    /// admin gate) and lists the seeded ACTIVE service; `POST /bookings` with that
    /// `service_id` uses the catalog's `base_fee` (not the column default) and enforces its
    /// `min_hours` floor (below-min → 400); an unknown/inactive `service_id` → 404; and a
    /// booking WITHOUT a `service_id` still works (back-compat). Gated on DATABASE_URL +
    /// Redis (hermetic SKIP otherwise).
    #[tokio::test]
    async fn services_list_and_booking_charge_wiring() {
        let Some((app, db)) = router_with_real_db().await else {
            eprintln!("SKIP: no DATABASE_URL + TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };

        // Seed one active service (min 3h, ฿230/hr) and one deactivated service.
        let marker = Uuid::new_v4().to_string();
        let active = repo::create_service(
            &db,
            &CreateServiceRequest {
                name_th: format!("th-{marker}"),
                name_en: format!("en-{marker}"),
                base_fee: "230.00".parse().unwrap(),
                min_hours: 3,
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
                let mut body = serde_json::json!({
                    "address": "1 Charge Wiring Rd",
                    "scheduled_at": "2026-07-01T10:00:00Z",
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

        // (d) back-compat: no service_id still works (200; server-owned default base_fee).
        let res = create(None, 1).await;
        assert_eq!(res.status(), StatusCode::OK, "no service_id still works");
        let body = axum::body::to_bytes(res.into_body(), 1 << 20)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let plain_id: Uuid = serde_json::from_value(v["data"]["id"].clone()).unwrap();

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

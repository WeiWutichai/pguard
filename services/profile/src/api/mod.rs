//! API layer — thin Axum transport handlers. No business logic beyond role gating +
//! orchestration of `domain` (pure decisions) + `repo` (DB).
//!
//! Handlers are generic over [`ProfileDeps`] so the `AuthUser` guard + the role gates are
//! unit-testable with a lightweight state (no live DB), mirroring booking's seam.

use axum::extract::{FromRequestParts, Multipart, Path, Query, State};
use axum::http::request::Parts;
use axum::http::HeaderMap;
use axum::Json;
use serde::Deserialize;
use uuid::Uuid;

use jsonwebtoken::EncodingKey;
use shared::auth::{
    decode_profile_token, encode_profile_token, AuthUser, HasJwtSecret, PROFILE_PURPOSE_CUSTOMER,
    PROFILE_PURPOSE_GUARD, PROFILE_PURPOSE_GUARD_DOC,
};
use shared::error::AppError;
use shared::models::{ApiResponse, ApprovalStatus};
use shared::service_jwt::ServiceCaller;

use crate::domain::documents;
use crate::domain::mask::mask_account_number;
use crate::domain::validate;
use crate::models::{
    AccessAuditRow, AdminListAccessAuditQuery, CustomerProfileAdminResponse,
    CustomerProfileResponse, DocumentExpiryRow, GuardAvatarResponse, GuardDocumentExpiry,
    GuardDocumentResponse, GuardProfileResponse, GuardProfileSubmitResponse, InternalGuard,
    MyProfile, PublicGuardProfile, RecipientsQuery, RecipientsResponse, RecruitCandidate,
    RejectRequest, SetDocumentExpiryRequest, StageRequest, UpsertCustomerProfileRequest,
    UpsertGuardProfileRequest, EXPIRING_DOCUMENT_TYPES,
};
use crate::repo;
use crate::state::{BookingAuthz, ProfileDeps, ProfileInternalDeps};

/// Hard cap on the internal catalog response. NOT paginated yet — a roster beyond this is
/// truncated (the handler logs a warn so the truncation is observable). Cursor pagination is
/// a tracked follow-up once the approved-guard count approaches this.
const INTERNAL_GUARDS_LIMIT: i64 = 100;

/// Hard cap on the broadcast-recipient response (mirrors [`INTERNAL_GUARDS_LIMIT`]). A larger
/// audience is truncated — broadcast is best-effort fan-out, not an exactly-once guarantee.
const RECIPIENTS_LIMIT: i64 = 5000;

const ROLE_GUARD: &str = "guard";
const ROLE_CUSTOMER: &str = "customer";
const ROLE_ADMIN: &str = "admin";

/// Require the caller to hold `expected_role`, else a generic 403. The message names the
/// REQUIRED role, never the caller's — no role enumeration.
fn require_role(user: &AuthUser, expected_role: &str) -> Result<(), AppError> {
    if user.role != expected_role {
        return Err(AppError::Forbidden(format!(
            "This action requires the {expected_role} role"
        )));
    }
    Ok(())
}

// ============================================================================
// Dual-auth for profile submission (profile_token OR logged-in AuthUser)
// ----------------------------------------------------------------------------
// `POST /profile/{guard,customer}` accepts EITHER a single-use, purpose-scoped
// `profile_token` (initial registration — the user is NOT logged in yet) OR a
// standard `AuthUser` (a later self-edit by a logged-in user). The resolver tries
// the profile_token first: only a token whose `purpose` matches THIS route decodes
// (purpose isolation — a guard token fails on the customer route and vice-versa),
// and it is consumed single-use via Redis GETDEL. A non-profile Bearer (an access
// token has no `purpose`) falls through to the standard `AuthUser` path, which also
// covers cookie+CSRF and the role gate. EITHER way we only learn the `user_id`;
// the profile schema is the only thing written — `users.role` (identity-owned) is
// never touched here (no cross-schema write).

/// Extract `Authorization: Bearer <token>`.
fn bearer_token(headers: &HeaderMap) -> Option<String> {
    headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer ").map(|t| t.to_string()))
}

/// Resolve the writer's `user_id` from EITHER a single-use `profile_token` of `purpose`
/// OR a logged-in `AuthUser` holding `role`. See the module note above.
async fn resolve_profile_writer<S: HasJwtSecret + Send + Sync>(
    parts: &mut Parts,
    state: &S,
    purpose: &str,
    role: &str,
) -> Result<Uuid, AppError> {
    // 1) profile_token path — only if the Bearer decodes as a profile token of THIS purpose.
    //    A wrong-purpose token does NOT decode here, so it is NOT consumed (it stays usable
    //    on its correct route) — it simply falls through to (2) and is rejected there.
    if let Some(tok) = bearer_token(&parts.headers) {
        if let Ok((user_id, jti)) = decode_profile_token(&tok, state.decoding_key(), purpose) {
            // GETDEL is the ATOMIC single-use claim (mirrors identity register): two concurrent
            // submissions of the same token → exactly one winner, the other gets nil → 401.
            // The token is consumed here in the extractor, i.e. BEFORE the repo write. A
            // transient write failure (500) therefore burns the token — the deliberate, simpler
            // trade-off (atomicity + replay-safety over retry-after-partial-failure), consistent
            // with identity register's consume-before-UPSERT. Recovery is re-OTP → re-register
            // (a still-pending phone re-registers fine and yields a fresh profile_token).
            let mut redis = state.redis_conn().clone();
            let status: Option<String> = redis::cmd("GETDEL")
                .arg(format!("profile_jti:{jti}"))
                .query_async(&mut redis)
                .await?;
            return match status.as_deref() {
                Some("valid") => Ok(user_id),
                _ => Err(AppError::Unauthorized(
                    "Profile token is invalid, expired, or already used".to_string(),
                )),
            };
        }
    }
    // 2) logged-in user path — standard AuthUser (Bearer or cookie + CSRF + revocation),
    //    role-gated. A non-profile Bearer / cookie / wrong-role all resolve here.
    let user = AuthUser::from_request_parts(parts, state).await?;
    if user.role != role {
        return Err(AppError::Forbidden(format!(
            "This action requires the {role} role"
        )));
    }
    Ok(user.user_id)
}

/// Authorized writer of a GUARD profile: a `guard_profile` token OR a logged-in guard.
pub struct GuardProfileWriter {
    pub user_id: Uuid,
}

impl<S> FromRequestParts<S> for GuardProfileWriter
where
    S: HasJwtSecret + Send + Sync,
{
    type Rejection = AppError;
    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let user_id =
            resolve_profile_writer(parts, state, PROFILE_PURPOSE_GUARD, ROLE_GUARD).await?;
        Ok(Self { user_id })
    }
}

/// Authorized writer of a CUSTOMER profile: a `customer_profile` token OR a logged-in customer.
pub struct CustomerProfileWriter {
    pub user_id: Uuid,
}

impl<S> FromRequestParts<S> for CustomerProfileWriter
where
    S: HasJwtSecret + Send + Sync,
{
    type Rejection = AppError;
    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let user_id =
            resolve_profile_writer(parts, state, PROFILE_PURPOSE_CUSTOMER, ROLE_CUSTOMER).await?;
        Ok(Self { user_id })
    }
}

/// Authorized writer of a guard's DOCUMENT IMAGES — EITHER a short-lived `guard_doc_upload` token
/// (registration, BEFORE approval) OR a logged-in guard (post-approval). The token is decoded +
/// purpose-checked but **NOT consumed** (multi-use within its short TTL, so a guard can upload all
/// their credential images in one session); it grants nothing beyond writing its own `sub`'s
/// documents. Own-only is enforced by the handler (resolved `user_id` must equal the path id).
pub struct GuardDocWriter {
    /// The resolved caller's user_id (the registration token's `sub`, or the logged-in user).
    pub user_id: Uuid,
    /// `true` when the caller is an ADMIN — who may upload a document on behalf of ANY guard (the
    /// "guard forgot to attach" staff override). The guard own-only and registration-token paths
    /// are `false`. Admin writes are audit-logged by the handler.
    pub is_admin: bool,
}

impl<S> FromRequestParts<S> for GuardDocWriter
where
    S: HasJwtSecret + Send + Sync,
{
    type Rejection = AppError;
    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        // 1) guard_doc_upload token (registration) — signature + purpose + expiry only, no Redis
        //    consume (multi-use). A wrong-purpose / non-profile Bearer falls through to (2).
        if let Some(tok) = bearer_token(&parts.headers) {
            if let Ok((user_id, _jti)) =
                decode_profile_token(&tok, state.decoding_key(), PROFILE_PURPOSE_GUARD_DOC)
            {
                return Ok(Self {
                    user_id,
                    is_admin: false,
                });
            }
        }
        // 2) logged-in guard (own docs) OR admin (any guard's docs — the forgot-to-attach override).
        let user = AuthUser::from_request_parts(parts, state).await?;
        if user.role != ROLE_GUARD && user.role != ROLE_ADMIN {
            return Err(AppError::Forbidden(
                "This action requires the guard or admin role".to_string(),
            ));
        }
        Ok(Self {
            user_id: user.user_id,
            is_admin: user.role == ROLE_ADMIN,
        })
    }
}

/// Apply the shared field validators to a guard-profile write. Maps the pure validators'
/// `String` errors to `BadRequest`.
fn validate_guard_req(req: &UpsertGuardProfileRequest) -> Result<(), AppError> {
    validate::validate_years_of_experience(req.years_of_experience)
        .map_err(AppError::BadRequest)?;
    validate::validate_text(req.gender.as_deref(), "gender", validate::MAX_TEXT_LEN)
        .map_err(AppError::BadRequest)?;
    validate::validate_text(
        req.previous_workplace.as_deref(),
        "previous_workplace",
        validate::MAX_TEXT_LEN,
    )
    .map_err(AppError::BadRequest)?;
    validate::validate_text(
        req.bank_name.as_deref(),
        "bank_name",
        validate::MAX_TEXT_LEN,
    )
    .map_err(AppError::BadRequest)?;
    validate::validate_text(
        req.account_name.as_deref(),
        "account_name",
        validate::MAX_TEXT_LEN,
    )
    .map_err(AppError::BadRequest)?;
    validate::validate_text(
        req.account_number.as_deref(),
        "account_number",
        validate::MAX_ACCOUNT_NUMBER_LEN,
    )
    .map_err(AppError::BadRequest)?;
    // v1-parity registration fields.
    for (val, field) in [
        (req.full_name.as_deref(), "full_name"),
        (req.address.as_deref(), "address"),
        (
            req.emergency_contact_name.as_deref(),
            "emergency_contact_name",
        ),
        (
            req.emergency_contact_relationship.as_deref(),
            "emergency_contact_relationship",
        ),
    ] {
        validate::validate_text(val, field, validate::MAX_TEXT_LEN)
            .map_err(AppError::BadRequest)?;
    }
    validate::validate_thai_phone(
        req.emergency_contact_phone.as_deref(),
        "emergency_contact_phone",
    )
    .map_err(AppError::BadRequest)?;
    Ok(())
}

/// Mask a guard profile's account number IN PLACE for an owner-facing read (PDPA). Admin
/// reads skip this and return the full value.
fn mask_guard_response(mut profile: GuardProfileResponse) -> GuardProfileResponse {
    profile.account_number = profile.account_number.as_deref().map(mask_account_number);
    profile
}

// ----- POST /profile/guard — upsert own guard profile -----

#[tracing::instrument(skip(state, writer, req), fields(user = %writer.user_id))]
pub async fn upsert_guard_profile<S: ProfileDeps>(
    State(state): State<S>,
    writer: GuardProfileWriter,
    Json(req): Json<UpsertGuardProfileRequest>,
) -> Result<Json<ApiResponse<GuardProfileSubmitResponse>>, AppError> {
    validate_guard_req(&req)?;
    // Writes ONLY the profile schema (approval_status defaults to 'pending'); identity owns
    // the account role/state and is never touched here. Owner read-back is masked (PDPA).
    let profile = repo::upsert_guard_profile(state.db(), writer.user_id, &req).await?;
    // Capture any document expiry dates that rode along (registration's doc step). Best-effort —
    // see [`apply_document_expiries`] — so it never fails the profile submit.
    apply_document_expiries(&state, writer.user_id, &req).await;
    // Mint a short-lived, MULTI-use, own-scoped doc-upload token so the (still-pending) guard can
    // upload their credential images right after this submit — admins MUST see the documents
    // BEFORE approving (registration is pre-approval; the guard cannot log in yet). The row now
    // exists, so the subsequent `POST …/documents` writes land on it.
    let enc = EncodingKey::from_secret(state.jwt_secret().as_bytes());
    let (doc_upload_token, _jti) = encode_profile_token(
        writer.user_id,
        PROFILE_PURPOSE_GUARD_DOC,
        &enc,
        DOC_UPLOAD_TOKEN_MINUTES,
    )?;
    Ok(Json(ApiResponse::success(GuardProfileSubmitResponse {
        profile: mask_guard_response(profile),
        doc_upload_token,
    })))
}

/// Lifetime of the guard document-upload token minted at profile submit — the registration window
/// for uploading credential images. Short, since the guard uploads immediately after submitting.
const DOC_UPLOAD_TOKEN_MINUTES: i64 = 30;

/// Capture the OPTIONAL document expiry dates that ride a guard-profile write (the registration
/// doc step folds them into the profile submit because the single-use `profile_token` authorizes
/// exactly ONE write). Metadata only; the document IMAGE upload is still deferred. Best-effort:
/// an unknown type or non-future date is skipped + logged, and a failed upsert is logged but
/// NEVER fails the profile write (the user chose non-blocking capture). Feeds the admin
/// "expiring documents" surface. Upserted on (guard_id, document_type), so a later edit overwrites.
async fn apply_document_expiries<S: ProfileDeps>(
    state: &S,
    guard_id: Uuid,
    req: &UpsertGuardProfileRequest,
) {
    let Some(expiries) = req.document_expiries.as_ref() else {
        return;
    };
    let today = chrono::Utc::now().date_naive();
    // Cap the work: only the 5 known types can ever persist (the table is UNIQUE per (guard,type)
    // → ON CONFLICT collapses dupes), so a pathologically large array behind the single-use token
    // can't fan out into unbounded primary-DB upserts.
    if expiries.len() > EXPIRING_DOCUMENT_TYPES.len() {
        tracing::warn!(n = expiries.len(), "document_expiries over cap; truncating");
    }
    for e in expiries.iter().take(EXPIRING_DOCUMENT_TYPES.len()) {
        if !document_expiry_is_capturable(&e.document_type, e.expiry_date, today) {
            tracing::warn!(document_type = %e.document_type, expiry_date = %e.expiry_date, "skipping invalid document expiry");
            continue;
        }
        if let Err(err) =
            repo::upsert_document_expiry(state.db(), guard_id, &e.document_type, e.expiry_date)
                .await
        {
            tracing::warn!(error = %err, document_type = %e.document_type, "document expiry upsert failed (non-fatal)");
        }
    }
}

/// PURE skip rule for a captured document expiry: a known type with a non-past date. Lenient at
/// the boundary (accepts `today`) so a client "tomorrow" that maps to server-`today` via a
/// timezone skew is NOT silently dropped; only strictly-past dates + unknown types are rejected.
fn document_expiry_is_capturable(
    document_type: &str,
    expiry_date: chrono::NaiveDate,
    today: chrono::NaiveDate,
) -> bool {
    EXPIRING_DOCUMENT_TYPES.contains(&document_type) && expiry_date >= today
}

// ----- PUT /profile/guard — update own guard profile -----

#[tracing::instrument(skip(state, req), fields(user = %user.user_id))]
pub async fn update_guard_profile<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Json(req): Json<UpsertGuardProfileRequest>,
) -> Result<Json<ApiResponse<GuardProfileResponse>>, AppError> {
    require_role(&user, ROLE_GUARD)?;
    validate_guard_req(&req)?;
    let profile = repo::update_guard_profile(state.db(), user.user_id, &req).await?;
    apply_document_expiries(&state, user.user_id, &req).await;
    Ok(Json(ApiResponse::success(mask_guard_response(profile))))
}

// ----- POST /profile/customer — upsert own customer profile -----

#[tracing::instrument(skip(state, writer, req), fields(user = %writer.user_id))]
pub async fn upsert_customer_profile<S: ProfileDeps>(
    State(state): State<S>,
    writer: CustomerProfileWriter,
    Json(req): Json<UpsertCustomerProfileRequest>,
) -> Result<Json<ApiResponse<CustomerProfileResponse>>, AppError> {
    validate::validate_text(
        req.full_name.as_deref(),
        "full_name",
        validate::MAX_TEXT_LEN,
    )
    .map_err(AppError::BadRequest)?;
    validate::validate_text(req.address.as_deref(), "address", validate::MAX_TEXT_LEN)
        .map_err(AppError::BadRequest)?;
    // v1-parity registration fields.
    validate::validate_text(
        req.company_name.as_deref(),
        "company_name",
        validate::MAX_TEXT_LEN,
    )
    .map_err(AppError::BadRequest)?;
    validate::validate_email(req.email.as_deref()).map_err(AppError::BadRequest)?;
    validate::validate_thai_phone(req.contact_phone.as_deref(), "contact_phone")
        .map_err(AppError::BadRequest)?;
    // Writes ONLY the customer profile schema — never identity's. The FIRST creation also
    // emits `user.approved` (outbox, same tx in repo): customers are auto-approved on their
    // first profile submission and identity flips its own approval_status on consume. Guards
    // keep the admin-review path (`/admin/guard-profiles/{id}/approve`).
    let profile = repo::upsert_customer_profile(state.db(), writer.user_id, &req).await?;
    Ok(Json(ApiResponse::success(profile)))
}

// ----- GET /guards/{id}/public — customer-readable guard mini-profile (live-tracking map) -----

/// Authorize a guard mini-profile read. `admin` → any; `guard` → self only; `customer` → only a
/// guard on their ACTIVE booking (the event-derived `profile.guard_assignments` read-model);
/// any other role → 403. A customer WITHOUT an active booking gets 403 (NOT 404) so they cannot
/// probe arbitrary guard ids by a status-code differential — mirrors presence's location gate.
async fn authorize_guard_profile_read<S: ProfileDeps>(
    state: &S,
    user: &AuthUser,
    guard_id: Uuid,
) -> Result<(), AppError> {
    match user.role.as_str() {
        ROLE_ADMIN => Ok(()),
        ROLE_GUARD => {
            if user.user_id == guard_id {
                Ok(())
            } else {
                Err(AppError::Forbidden(
                    "Guards can only read their own profile".to_string(),
                ))
            }
        }
        ROLE_CUSTOMER => {
            if state
                .booking_authz()
                .has_active_booking(user.user_id, guard_id)
                .await?
            {
                Ok(())
            } else {
                Err(AppError::Forbidden(
                    "You can only view a guard assigned to your active booking".to_string(),
                ))
            }
        }
        _ => Err(AppError::Forbidden("Not authorized".to_string())),
    }
}

/// GET /guards/{id}/public — the assigned guard's MINI-profile (name + experience) for the
/// customer live-tracking map. IDOR-gated (see [`authorize_guard_profile_read`]) THEN
/// approval-gated in the repo (un-approved/unknown guard → 404, so neither the gate nor the read
/// reveals a guard outside the caller's bookings). Returns ONLY `{ user_id, full_name,
/// years_of_experience }` — never the bank/address/DOB/emergency-contact PII. The authz read-model
/// is on the primary (no replica lag on the security gate); the profile read uses the replica.
#[tracing::instrument(skip(state), fields(user = %user.user_id, guard = %guard_id))]
pub async fn get_public_guard_profile<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(guard_id): Path<Uuid>,
) -> Result<Json<ApiResponse<PublicGuardProfile>>, AppError> {
    authorize_guard_profile_read(&state, &user, guard_id).await?;
    let profile = repo::get_public_guard_profile(state.db_read(), guard_id)
        .await?
        .ok_or_else(|| AppError::NotFound("Guard not found".to_string()))?;
    Ok(Json(ApiResponse::success(profile)))
}

// ----- POST/GET /profile/guard/{user_id}/documents — guard credential image upload/read -----

/// Hard body cap for a document upload (12 MiB) — set as the route's `DefaultBodyLimit` and
/// mirrored by the gateway's `BodyCap::Large`. Slightly above the 10 MiB image cap to allow for
/// multipart framing overhead.
pub const MAX_DOCUMENT_BODY_BYTES: usize = 12 * 1024 * 1024;

/// POST `/profile/guard/{user_id}/documents` — a guard uploads ONE of their own credential images
/// (id_card / security_license / training_cert / criminal_check / driver_license / passbook_photo).
/// Auth: a registration `guard_doc_upload` token (pre-approval) OR a logged-in guard — **own docs
/// only** (no admin bypass on WRITE — first-person credential attestation). The image is magic-byte
/// validated, stored under a server-generated UUID key, and the key written to the matching `*_key`
/// column. Returns a short-lived presigned GET URL.
#[tracing::instrument(skip(state, multipart, writer), fields(user = %writer.user_id, target = %user_id))]
pub async fn upload_guard_document<S: ProfileDeps>(
    State(state): State<S>,
    writer: GuardDocWriter,
    Path(user_id): Path<Uuid>,
    multipart: Multipart,
) -> Result<Json<ApiResponse<GuardDocumentResponse>>, AppError> {
    // Auth: a registration `guard_doc_upload` token / a logged-in guard (OWN docs only) — OR an
    // ADMIN, who may upload on behalf of ANY guard (the "guard forgot to attach" staff override).
    if !writer.is_admin && user_id != writer.user_id {
        return Err(AppError::Forbidden(
            "You can only upload your own documents".to_string(),
        ));
    }

    let (document_type, declared_mime, bytes) = parse_document_form(multipart).await?;

    // Accountability: an admin writing/replacing a credential on a guard's behalf is the one
    // exception to first-person attestation. Record it in the SAME durable, admin-queryable sink
    // as the §30 read-audit (GET /admin/access-audit) — fail-loud (before any S3 work) so a
    // credential is never substituted un-audited — plus a live log line.
    if writer.is_admin && user_id != writer.user_id {
        let audit_target = format!("{user_id}/{document_type}");
        repo::record_access(
            state.db(),
            writer.user_id,
            "admin_upload_guard_document",
            Some(&audit_target),
        )
        .await?;
        tracing::info!(
            admin = %writer.user_id,
            target = %user_id,
            %document_type,
            "admin uploaded a guard document on the guard's behalf"
        );
    }

    // Map the document_type to its column FIRST (closed allowlist; unknown → 400) so an unknown
    // type is rejected before any S3 work, and the column name is never client-controlled.
    let column = documents::key_column_for(&document_type)
        .ok_or_else(|| AppError::BadRequest(format!("unknown document_type: {document_type}")))?;

    // Validate the image (size BEFORE magic bytes; declared must match detected).
    let canonical_mime = documents::validate_document_upload(&declared_mime, bytes.len(), &bytes)?;
    let ext = documents::mime_to_extension(canonical_mime);
    let key = format!("profile/{user_id}/documents/{}.{ext}", Uuid::new_v4());

    state.s3().upload(&key, bytes, canonical_mime).await?;

    // Persist the key; on failure compensate so the object doesn't orphan.
    if let Err(e) = repo::update_document_key(state.db(), user_id, column, &key).await {
        state.s3().delete_best_effort(&key).await;
        return Err(e);
    }

    Ok(Json(ApiResponse::success(GuardDocumentResponse {
        document_type,
        download_url: state.s3().download_url(&key),
    })))
}

/// GET `/profile/guard/{user_id}/documents?document_type=...` — a presigned URL for ONE stored
/// document. Read auth is OWNER-OR-ADMIN (an admin must be able to verify a guard's credentials);
/// 404 when the document type is valid but not yet uploaded (key NULL) or the guard has no profile.
#[tracing::instrument(skip(state), fields(user = %user.user_id, target = %user_id))]
pub async fn get_guard_document<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(user_id): Path<Uuid>,
    Query(q): Query<GuardDocumentQuery>,
) -> Result<Json<ApiResponse<GuardDocumentResponse>>, AppError> {
    // Owner or admin.
    if user.role != ROLE_ADMIN && user.user_id != user_id {
        return Err(AppError::Forbidden(
            "You can only read your own documents".to_string(),
        ));
    }
    let column = documents::key_column_for(&q.document_type).ok_or_else(|| {
        AppError::BadRequest(format!("unknown document_type: {}", q.document_type))
    })?;
    let key = repo::get_document_key(state.db_read(), user_id, column)
        .await?
        .ok_or_else(|| AppError::NotFound("Document not uploaded".to_string()))?;
    Ok(Json(ApiResponse::success(GuardDocumentResponse {
        document_type: q.document_type,
        download_url: state.s3().download_url(&key),
    })))
}

/// Query for the document GET (`?document_type=id_card`).
#[derive(Debug, Deserialize)]
pub struct GuardDocumentQuery {
    pub document_type: String,
}

// ----- GET/PUT /profile/guard/{user_id}/document-expiries — owner/admin view + edit -----

/// GET `/profile/guard/{user_id}/document-expiries` — the guard's recorded credential expiry dates.
/// OWNER-OR-ADMIN read (a guard sees their own on the "My documents" screen; an admin sees any).
#[tracing::instrument(skip(state), fields(user = %user.user_id, target = %user_id))]
pub async fn list_guard_document_expiries<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(user_id): Path<Uuid>,
) -> Result<Json<ApiResponse<Vec<GuardDocumentExpiry>>>, AppError> {
    if user.role != ROLE_ADMIN && user.user_id != user_id {
        return Err(AppError::Forbidden(
            "You can only read your own document expiries".to_string(),
        ));
    }
    let rows = repo::list_document_expiries(state.db_read(), user_id).await?;
    let out = rows
        .into_iter()
        .map(|r| GuardDocumentExpiry {
            document_type: r.document_type,
            expiry_date: r.expiry_date,
        })
        .collect();
    Ok(Json(ApiResponse::success(out)))
}

/// PUT `/profile/guard/{user_id}/document-expiry` — set/replace ONE credential's expiry date.
/// OWNER-OR-ADMIN: a guard edits their OWN (post-approval), an admin may edit ANY guard's (audited).
/// The `document_type` must be an expiring credential (the passbook has none) → else 400.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, target = %user_id))]
pub async fn set_guard_document_expiry<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(user_id): Path<Uuid>,
    Json(req): Json<SetDocumentExpiryRequest>,
) -> Result<Json<ApiResponse<GuardDocumentExpiry>>, AppError> {
    let is_admin = user.role == ROLE_ADMIN;
    if !is_admin && user.user_id != user_id {
        return Err(AppError::Forbidden(
            "You can only edit your own document expiries".to_string(),
        ));
    }
    if !EXPIRING_DOCUMENT_TYPES.contains(&req.document_type.as_str()) {
        return Err(AppError::BadRequest(format!(
            "document_type '{}' has no expiry date",
            req.document_type
        )));
    }
    // Accountability: an admin editing a guard's expiry on their behalf is recorded in the durable
    // §30 audit sink (fail-loud), like the admin doc upload.
    if is_admin && user.user_id != user_id {
        let audit_target = format!("{user_id}/{}", req.document_type);
        repo::record_access(
            state.db(),
            user.user_id,
            "admin_set_document_expiry",
            Some(&audit_target),
        )
        .await?;
    }
    let row =
        repo::upsert_document_expiry(state.db(), user_id, &req.document_type, req.expiry_date)
            .await?;
    Ok(Json(ApiResponse::success(GuardDocumentExpiry {
        document_type: row.document_type,
        expiry_date: row.expiry_date,
    })))
}

// ----- POST/GET /profile/guard/{user_id}/avatar — guard self-uploaded profile picture -----

/// The `guard_profiles` column holding the avatar's S3 key. A fixed `&'static str` (never client-
/// controlled), passed to the same allowlisted key-column repo helpers as the credential docs.
const AVATAR_KEY_COLUMN: &str = "avatar_key";

/// POST `/profile/guard/{user_id}/avatar` — a guard uploads/replaces their OWN profile picture.
/// Auth: logged-in guard, **own avatar only** (no admin bypass on write). Image magic-byte
/// validated (JPEG/PNG/WEBP ≤10 MiB, same gate as credential docs), stored under a server-generated
/// UUID key, the key written to `avatar_key`. Returns a short-lived presigned GET URL.
#[tracing::instrument(skip(state, multipart), fields(user = %user.user_id, target = %user_id))]
pub async fn upload_guard_avatar<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(user_id): Path<Uuid>,
    multipart: Multipart,
) -> Result<Json<ApiResponse<GuardAvatarResponse>>, AppError> {
    require_role(&user, ROLE_GUARD)?;
    // IDOR: a guard sets ONLY their own avatar (path id must equal the caller).
    if user_id != user.user_id {
        return Err(AppError::Forbidden(
            "You can only upload your own avatar".to_string(),
        ));
    }

    let (declared_mime, bytes) = parse_avatar_form(multipart).await?;

    // Validate the image (size BEFORE magic bytes; declared must match detected) — shares the
    // credential-doc validator (image-only allowlist).
    let canonical_mime = documents::validate_document_upload(&declared_mime, bytes.len(), &bytes)?;
    let ext = documents::mime_to_extension(canonical_mime);
    // Key MUST stay within RFC-3986 unreserved chars (UUID + fixed prefix + whitelisted ext): the
    // staging edge serves presigned GETs via an nginx `/minio-files/` prefix-strip that
    // re-canonicalizes the path, so a key with reserved/encoded bytes would diverge from the
    // SigV4-signed path → 403.
    let key = format!("profile/{user_id}/avatar/{}.{ext}", Uuid::new_v4());

    state.s3().upload(&key, bytes, canonical_mime).await?;

    // Persist the key (reuses the allowlisted key-column writer); compensate on DB failure so the
    // object doesn't orphan.
    if let Err(e) = repo::update_document_key(state.db(), user_id, AVATAR_KEY_COLUMN, &key).await {
        state.s3().delete_best_effort(&key).await;
        return Err(e);
    }

    Ok(Json(ApiResponse::success(GuardAvatarResponse {
        avatar_url: state.s3().download_url(&key),
    })))
}

/// GET `/profile/guard/{user_id}/avatar` — a presigned URL for the stored avatar. Read auth is
/// OWNER-OR-ADMIN; 404 when no avatar is set (key NULL) or the guard has no profile.
#[tracing::instrument(skip(state), fields(user = %user.user_id, target = %user_id))]
pub async fn get_guard_avatar<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(user_id): Path<Uuid>,
) -> Result<Json<ApiResponse<GuardAvatarResponse>>, AppError> {
    if user.role != ROLE_ADMIN && user.user_id != user_id {
        return Err(AppError::Forbidden(
            "You can only read your own avatar".to_string(),
        ));
    }
    let key = repo::get_document_key(state.db_read(), user_id, AVATAR_KEY_COLUMN)
        .await?
        .ok_or_else(|| AppError::NotFound("Avatar not set".to_string()))?;
    Ok(Json(ApiResponse::success(GuardAvatarResponse {
        avatar_url: state.s3().download_url(&key),
    })))
}

/// Parse the avatar multipart: a single `file` part (bytes + declared content-type). Bounded by
/// the route's `DefaultBodyLimit`.
async fn parse_avatar_form(mut multipart: Multipart) -> Result<(String, Vec<u8>), AppError> {
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

/// Parse the document multipart parts: required `document_type` (text) + `file` (bytes + declared
/// content-type). The bytes are bounded by the route's `DefaultBodyLimit`.
async fn parse_document_form(
    mut multipart: Multipart,
) -> Result<(String, String, Vec<u8>), AppError> {
    let mut document_type: Option<String> = None;
    let mut declared_mime: Option<String> = None;
    let mut file: Option<Vec<u8>> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| AppError::BadRequest(format!("Failed to read multipart: {e}")))?
    {
        match field.name().unwrap_or("") {
            "document_type" => {
                let text = field
                    .text()
                    .await
                    .map_err(|e| AppError::BadRequest(format!("Invalid document_type: {e}")))?;
                document_type = Some(text.trim().to_string());
            }
            "file" => {
                declared_mime = field.content_type().map(|s| s.to_string());
                file = Some(
                    field
                        .bytes()
                        .await
                        .map_err(|e| AppError::BadRequest(format!("Failed to read file: {e}")))?
                        .to_vec(),
                );
            }
            _ => {}
        }
    }

    let document_type = document_type
        .ok_or_else(|| AppError::BadRequest("document_type is required".to_string()))?;
    let file = file.ok_or_else(|| AppError::BadRequest("file is required".to_string()))?;
    let declared_mime = declared_mime.unwrap_or_else(|| "application/octet-stream".to_string());
    Ok((document_type, declared_mime, file))
}

// ----- GET /profile/me — the caller's own profile (account number MASKED) -----

#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn get_my_profile<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<MyProfile>>, AppError> {
    // A guard sees their guard profile (masked); a customer sees their customer profile.
    // Admins have no self-profile in this slice → 404 (they manage others, not self).
    match user.role.as_str() {
        ROLE_GUARD => {
            let profile = repo::get_guard_profile(state.db(), user.user_id)
                .await?
                .ok_or_else(|| AppError::NotFound("Profile not found".to_string()))?;
            Ok(Json(ApiResponse::success(MyProfile::Guard(
                mask_guard_response(profile),
            ))))
        }
        ROLE_CUSTOMER => {
            let profile = repo::get_customer_profile(state.db(), user.user_id)
                .await?
                .ok_or_else(|| AppError::NotFound("Profile not found".to_string()))?;
            Ok(Json(ApiResponse::success(MyProfile::Customer(profile))))
        }
        _ => Err(AppError::NotFound("Profile not found".to_string())),
    }
}

// ----- GET /admin/guard-profiles?approval_status=... — admin list (FULL bank) -----

#[derive(Debug, Deserialize)]
pub struct ListQuery {
    /// Optional filter: pending | approved | rejected. An unknown value → 400.
    pub approval_status: Option<String>,
}

#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn admin_list_guard_profiles<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<ListQuery>,
) -> Result<Json<ApiResponse<Vec<GuardProfileResponse>>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    let status = match q.approval_status.as_deref() {
        None => None,
        Some(s) => Some(
            s.parse::<ApprovalStatus>()
                .map_err(|_| AppError::BadRequest("invalid approval_status filter".to_string()))?,
        ),
    };
    // Admin sees the FULL account number (not masked) — onboarding review needs it.
    // List read → replica (C5.3); the §30 read-audit below is a WRITE → primary.
    let profiles = repo::list_guard_profiles(state.db_read(), status).await?;
    // PDPA §30: record this admin read of personal data (who accessed what).
    repo::record_access(
        state.db(),
        user.user_id,
        "admin_list_guard_profiles",
        q.approval_status.as_deref(),
    )
    .await?;
    Ok(Json(ApiResponse::success(profiles)))
}

// ----- GET /admin/customer-profiles — admin list (cross-user) -----

/// List every customer profile for the admin surface. Admin-only (the edge proves identity,
/// not role — authz is this service's job). No filter param: customer approval is not stored
/// in profile (it lives in identity; customers auto-approve on first profile insert), so a
/// `?approval_status` filter would be meaningless against this table — see the guard list for
/// the filtered variant. Mirrors [`admin_list_guard_profiles`]: list read on the replica
/// (C5.3), PDPA §30 read-audit WRITE on the primary. No masking — customer profiles hold no
/// bank field (`full_name`/`address` are the only PII, returned as-is like the owner read).
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn admin_list_customer_profiles<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<CustomerProfileAdminResponse>>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    let profiles = repo::list_customer_profiles(state.db_read()).await?;
    // PDPA §30: record this admin read of personal data (who accessed what). No filter to log.
    repo::record_access(
        state.db(),
        user.user_id,
        "admin_list_customer_profiles",
        None,
    )
    .await?;
    Ok(Json(ApiResponse::success(profiles)))
}

// ----- GET /admin/access-audit — PDPA §30 data-access audit log (admin) -----

/// List the data-access audit trail (admin). Admin-only. Optional `action` filter + limit/offset,
/// newest first; read from the replica. NOTE: this is the §30 access trail (who read what PII),
/// NOT a full business-action feed — the design's broader "activity" stream (approved/refund/
/// check-in events with actor/IP/payload) would need a dedicated audit-event sink (out of scope).
/// Reading the audit log is itself NOT audited (it would recurse).
#[tracing::instrument(skip(state, q), fields(user = %user.user_id))]
pub async fn admin_list_access_audit<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Query(q): Query<AdminListAccessAuditQuery>,
) -> Result<Json<ApiResponse<Vec<AccessAuditRow>>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let offset = q.offset.unwrap_or(0).max(0);
    let rows = repo::list_access_audit(state.db_read(), q.action.as_deref(), limit, offset).await?;
    Ok(Json(ApiResponse::success(rows)))
}

// ----- GET /internal/guards (service-to-service catalog) -----

/// Internal read used by booking's discovery (`/available-guards`) to list the APPROVED
/// guard catalog. Guarded by [`ServiceCaller`] (a valid service-JWT) — never reachable from
/// the public edge (the gateway blocks `/internal/`). Returns only `{ user_id,
/// years_of_experience }` (least-privilege — no bank/PII over the wire). Generic over
/// [`ProfileInternalDeps`] so the guard is unit-testable (mirrors booking's internal read).
#[tracing::instrument(skip(state), fields(caller = %caller.service))]
pub async fn internal_list_guards<S: ProfileInternalDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
) -> Result<Json<ApiResponse<Vec<InternalGuard>>>, AppError> {
    let guards = repo::list_approved_guards(state.db_read(), INTERNAL_GUARDS_LIMIT).await?;
    // Surface the (un-paginated) truncation so a roster that outgrows the cap is observable
    // rather than silently dropping guards from discovery.
    if guards.len() as i64 >= INTERNAL_GUARDS_LIMIT {
        tracing::warn!(
            limit = INTERNAL_GUARDS_LIMIT,
            "approved-guard catalog hit the cap; discovery results truncated (no pagination yet)"
        );
    }
    Ok(Json(ApiResponse::success(guards)))
}

// ----- GET /internal/users/{user_id}/export (PDPA §19/§32 data export) -----

/// Export the user's OWN profile data for a cross-service data export. `ServiceCaller`-gated
/// (only identity's aggregator, holding a valid service-JWT, reaches this) and scoped
/// strictly to the path `user_id`, so it can never return another user's rows.
#[tracing::instrument(skip(state), fields(caller = %caller.service, user = %user_id))]
pub async fn internal_export_user<S: ProfileInternalDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
    Path(user_id): Path<Uuid>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    let data = repo::export_user_data(state.db_read(), user_id).await?;
    Ok(Json(ApiResponse::success(data)))
}

/// Horizon for the expiring-documents surface: include docs expiring within ~90 days (plus any
/// already expired). The client buckets into expired / 7 / 30 / 90.
const DOC_EXPIRY_HORIZON_DAYS: i64 = 90;

// ----- Recruitment pipeline (admin "recruit" surface) -----

/// GET /admin/recruitment/candidates — every guard as a pipeline candidate (lean, no PII).
/// Admin only; replica read. The kanban groups pending guards by `recruitment_stage` and
/// finalized ones by `approval_status` (approve/reject reuse the existing guard endpoints).
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn admin_list_candidates<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<RecruitCandidate>>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    let rows = repo::list_recruitment_candidates(state.db_read()).await?;
    Ok(Json(ApiResponse::success(rows)))
}

/// PUT /admin/recruitment/candidates/{user_id}/stage — move a PENDING candidate to a pipeline
/// stage. Admin only. A finalized (approved/rejected) candidate → 409; unknown stage → 400.
#[tracing::instrument(skip(state, req), fields(user = %user.user_id, target = %user_id))]
pub async fn admin_set_candidate_stage<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(user_id): Path<Uuid>,
    Json(req): Json<StageRequest>,
) -> Result<Json<ApiResponse<RecruitCandidate>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    let candidate = repo::set_recruitment_stage(state.db(), user_id, &req.stage).await?;
    Ok(Json(ApiResponse::success(candidate)))
}

// ----- GET /admin/documents/expiring — guard documents needing renewal (admin) -----

/// List guard documents expiring within the horizon (incl. already-expired), soonest first.
/// Admin only (else 403); replica read. Rows are populated by the guard profile submit
/// (`POST /profile/guard`, which folds in the registration doc step's expiry dates).
#[tracing::instrument(skip(state), fields(user = %user.user_id))]
pub async fn admin_list_expiring_documents<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
) -> Result<Json<ApiResponse<Vec<DocumentExpiryRow>>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    let rows = repo::list_expiring_documents(state.db_read(), DOC_EXPIRY_HORIZON_DAYS).await?;
    Ok(Json(ApiResponse::success(rows)))
}

// ----- GET /internal/profiles/recipients (broadcast audience for notification) -----

/// Resolve the `user_id`s for a broadcast audience (`all|guards|customers`). `ServiceCaller`-
/// gated (only notification's bulk-send, holding a valid service-JWT, reaches this — the
/// gateway blocks `/internal/`). notification owns no user/role registry, so it asks profile
/// (which owns the guard/customer profile tables). Least-privilege — returns only `user_id`s,
/// never names/PII. Bounded by [`RECIPIENTS_LIMIT`]; a larger roster is truncated (logged).
#[tracing::instrument(skip(state), fields(caller = %caller.service))]
pub async fn internal_list_recipients<S: ProfileInternalDeps>(
    State(state): State<S>,
    caller: ServiceCaller,
    Query(q): Query<RecipientsQuery>,
) -> Result<Json<ApiResponse<RecipientsResponse>>, AppError> {
    let audience = match q.audience.as_str() {
        "all" | "guards" | "customers" => q.audience.clone(),
        other => {
            return Err(AppError::BadRequest(format!(
                "audience must be all|guards|customers (got {other})"
            )))
        }
    };
    let user_ids = repo::recipient_ids(state.db_read(), &audience, RECIPIENTS_LIMIT).await?;
    if user_ids.len() as i64 >= RECIPIENTS_LIMIT {
        tracing::warn!(
            limit = RECIPIENTS_LIMIT,
            %audience,
            "broadcast recipient roster hit the cap; audience truncated (no pagination yet)"
        );
    }
    Ok(Json(ApiResponse::success(RecipientsResponse {
        count: user_ids.len() as i64,
        audience,
        user_ids,
    })))
}

// ----- POST /admin/guard-profiles/{user_id}/approve | /reject -----

#[tracing::instrument(skip(state), fields(admin = %user.user_id, target_user = %user_id))]
pub async fn admin_approve_guard<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(user_id): Path<Uuid>,
) -> Result<Json<ApiResponse<GuardProfileResponse>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    // The approve emits `user.approved` atomically (outbox) → identity flips its own
    // `users.approval_status` so the guard can finally log in. `role = guard` (this route).
    let profile =
        repo::set_approval_status(state.db(), user_id, ApprovalStatus::Approved, ROLE_GUARD)
            .await?;
    Ok(Json(ApiResponse::success(profile)))
}

#[tracing::instrument(skip(state, body), fields(admin = %user.user_id, target_user = %user_id))]
pub async fn admin_reject_guard<S: ProfileDeps>(
    State(state): State<S>,
    user: AuthUser,
    Path(user_id): Path<Uuid>,
    body: Option<Json<RejectRequest>>,
) -> Result<Json<ApiResponse<GuardProfileResponse>>, AppError> {
    require_role(&user, ROLE_ADMIN)?;
    if let Some(Json(RejectRequest { reason: Some(r) })) = &body {
        // Reason is contextual metadata, not PII — safe to log; persisting it is a follow-up.
        tracing::info!(reason = %r, "guard profile rejected with reason");
    }
    let profile =
        repo::set_approval_status(state.db(), user_id, ApprovalStatus::Rejected, ROLE_GUARD)
            .await?;
    Ok(Json(ApiResponse::success(profile)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::{get, post, put};
    use axum::Router;
    use jsonwebtoken::{DecodingKey, EncodingKey};
    use shared::auth::{encode_jwt_with_key, HasJwtSecret};
    use sqlx::postgres::PgPoolOptions;
    use std::sync::Arc;
    use std::time::Duration;
    use tower::ServiceExt;

    const SECRET: &str = "user-secret-at-least-64-characters-long-for-the-hs256-profile-test!!!";

    /// Hermetic IDOR-authz stub: `has_active_booking` returns a fixed answer without touching a
    /// DB, so the public-profile customer gate (allow vs deny) is testable with a closed lazy pool.
    #[derive(Clone)]
    struct StubAuthz {
        allow: bool,
    }
    impl crate::state::BookingAuthz for StubAuthz {
        async fn has_active_booking(
            &self,
            _customer_id: Uuid,
            _guard_id: Uuid,
        ) -> Result<bool, AppError> {
            Ok(self.allow)
        }
    }

    #[derive(Clone)]
    struct TestDeps {
        dec: Arc<DecodingKey>,
        db: sqlx::PgPool,
        redis: redis::aio::ConnectionManager,
        authz: StubAuthz,
        s3: crate::s3::S3Client,
    }

    /// Dummy S3 client for tests — does no I/O until a presigned URL is actually hit; the
    /// role/IDOR rejection paths never reach `s3()`.
    fn test_s3() -> crate::s3::S3Client {
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
    impl ProfileDeps for TestDeps {
        type Authz = StubAuthz;
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
        fn booking_authz(&self) -> &StubAuthz {
            &self.authz
        }
        fn s3(&self) -> &crate::s3::S3Client {
            &self.s3
        }
    }

    /// Build the profile router over a lightweight test state. The `AuthUser` extractor
    /// requires `HasJwtSecret`, which mandates a real [`redis::aio::ConnectionManager`]
    /// for the jti revocation blocklist — there is no public way to construct one without
    /// connecting. So, exactly like booking's router tests, these are hermetic by default
    /// and only run when a test Redis is provided via `TEST_REDIS_URL` (falling back to
    /// `REDIS_CACHE_URL`). Returns `None` → the caller SKIPs.
    ///
    /// Auth-reject and role-gate paths short-circuit before any DB access, so the lazy pool
    /// to a closed port is never connected (a wrong-role 403 fails at `require_role`, a
    /// missing/invalid token 401 fails at the extractor — both before `repo`).
    async fn router() -> Option<Router> {
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
            authz: StubAuthz { allow: false },
            s3: test_s3(),
        };
        Some(
            Router::new()
                .route("/profile/guard", post(upsert_guard_profile::<TestDeps>))
                .route("/profile/guard", put(update_guard_profile::<TestDeps>))
                .route(
                    "/profile/customer",
                    post(upsert_customer_profile::<TestDeps>),
                )
                .route("/profile/me", get(get_my_profile::<TestDeps>))
                .route(
                    "/guards/{id}/public",
                    get(get_public_guard_profile::<TestDeps>),
                )
                .route(
                    "/profile/guard/{user_id}/documents",
                    post(upload_guard_document::<TestDeps>).get(get_guard_document::<TestDeps>),
                )
                .route(
                    "/profile/guard/{user_id}/avatar",
                    post(upload_guard_avatar::<TestDeps>).get(get_guard_avatar::<TestDeps>),
                )
                .route(
                    "/admin/guard-profiles",
                    get(admin_list_guard_profiles::<TestDeps>),
                )
                .route(
                    "/admin/customer-profiles",
                    get(admin_list_customer_profiles::<TestDeps>),
                )
                .route(
                    "/admin/access-audit",
                    get(admin_list_access_audit::<TestDeps>),
                )
                .route(
                    "/admin/documents/expiring",
                    get(admin_list_expiring_documents::<TestDeps>),
                )
                .route(
                    "/admin/recruitment/candidates",
                    get(admin_list_candidates::<TestDeps>),
                )
                .route(
                    "/admin/guard-profiles/{user_id}/approve",
                    post(admin_approve_guard::<TestDeps>),
                )
                .route(
                    "/admin/guard-profiles/{user_id}/reject",
                    post(admin_reject_guard::<TestDeps>),
                )
                .with_state(deps),
        )
    }

    fn token(role: &str) -> String {
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, _) = encode_jwt_with_key(Uuid::new_v4(), role, 0, &ek, 60).unwrap();
        tok
    }

    /// A token plus the `user_id` it was minted for — for the guard-self path, where the route's
    /// `{id}` must equal the caller.
    fn token_with_id(role: &str) -> (String, Uuid) {
        let uid = Uuid::new_v4();
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, _) = encode_jwt_with_key(uid, role, 0, &ek, 60).unwrap();
        (tok, uid)
    }

    fn guard_body() -> Body {
        Body::from(serde_json::json!({ "gender": "male" }).to_string())
    }

    // ----- document-expiry skip rule (pure; no DB/Redis) -----

    #[test]
    fn document_expiry_capturable_rule() {
        use chrono::NaiveDate;
        let today = NaiveDate::from_ymd_opt(2030, 6, 15).unwrap();
        let tomorrow = NaiveDate::from_ymd_opt(2030, 6, 16).unwrap();
        let yesterday = NaiveDate::from_ymd_opt(2030, 6, 14).unwrap();
        // known type + future → capture.
        assert!(document_expiry_is_capturable("id_card", tomorrow, today));
        // boundary: `today` is accepted (lenient — guards the client/server TZ-skew off-by-one).
        assert!(document_expiry_is_capturable(
            "driver_license",
            today,
            today
        ));
        // strictly past → dropped.
        assert!(!document_expiry_is_capturable("id_card", yesterday, today));
        // unknown type (e.g. the excluded passbook) → dropped even if future.
        assert!(!document_expiry_is_capturable(
            "passbook_photo",
            tomorrow,
            today
        ));
    }

    // ----- 401: missing / invalid token -----

    #[tokio::test]
    async fn upsert_guard_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/profile/guard")
                    .header("content-type", "application/json")
                    .body(guard_body())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn upsert_guard_rejects_invalid_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/profile/guard")
                    .header("authorization", "Bearer not.a.valid.jwt")
                    .header("content-type", "application/json")
                    .body(guard_body())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn me_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/profile/me")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    // ----- 403: wrong-role token hits the role gate (before any DB access) -----

    #[tokio::test]
    async fn upsert_guard_rejects_customer_role() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/profile/guard")
                    .header("authorization", format!("Bearer {}", token(ROLE_CUSTOMER)))
                    .header("content-type", "application/json")
                    .body(guard_body())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::FORBIDDEN,
            "a customer must not upsert a guard profile"
        );
    }

    #[tokio::test]
    async fn admin_list_rejects_guard_role() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/guard-profiles")
                    .header("authorization", format!("Bearer {}", token(ROLE_GUARD)))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::FORBIDDEN,
            "a guard must not list the admin onboarding queue"
        );
    }

    #[tokio::test]
    async fn admin_access_audit_rejects_non_admin() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A guard must not read the data-access audit trail.
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/access-audit")
                    .header("authorization", format!("Bearer {}", token(ROLE_GUARD)))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn admin_list_customers_rejects_non_admin() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A customer (not admin) must not list every customer's PII (name/address).
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/customer-profiles")
                    .header("authorization", format!("Bearer {}", token(ROLE_CUSTOMER)))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::FORBIDDEN,
            "a customer must not list the admin customer directory"
        );
    }

    #[tokio::test]
    async fn admin_recruitment_candidates_rejects_non_admin() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A guard must not read the cross-user recruitment pipeline.
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/recruitment/candidates")
                    .header("authorization", format!("Bearer {}", token(ROLE_CUSTOMER)))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn admin_expiring_docs_rejects_non_admin() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A guard must not read the cross-user expiring-documents surface.
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/admin/documents/expiring")
                    .header("authorization", format!("Bearer {}", token(ROLE_GUARD)))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn admin_approve_rejects_guard_role() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let id = Uuid::new_v4();
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/admin/guard-profiles/{id}/approve"))
                    .header("authorization", format!("Bearer {}", token(ROLE_GUARD)))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    // ----- GET /guards/{id}/public — IDOR gate (customer needs an active booking) -----

    /// Router exposing ONLY the public guard-profile route over a TestDeps whose authz stub
    /// returns `allow`. Redis-gated like [`router`] (the `AuthUser` extractor needs Redis); the
    /// lazy DB pool is to a closed port, so a request that PASSES the gate 500s at the repo
    /// (proving the gate let it through) while a DENIED request 403s before any DB access.
    async fn public_profile_router(allow: bool) -> Option<Router> {
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
            authz: StubAuthz { allow },
            s3: test_s3(),
        };
        Some(
            Router::new()
                .route(
                    "/guards/{id}/public",
                    get(get_public_guard_profile::<TestDeps>),
                )
                .with_state(deps),
        )
    }

    fn get_with_bearer(uri: &str, token: &str) -> Request<Body> {
        Request::builder()
            .method("GET")
            .uri(uri)
            .header("authorization", format!("Bearer {token}"))
            .body(Body::empty())
            .unwrap()
    }

    #[tokio::test]
    async fn public_profile_rejects_missing_token() {
        let Some(app) = public_profile_router(true).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(format!("/guards/{}/public", Uuid::new_v4()))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn public_profile_customer_without_active_booking_is_forbidden() {
        let Some(app) = public_profile_router(false).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // Customer, no active booking with this guard → 403 (NOT 404 — no existence probe), and
        // the deny short-circuits before any DB read.
        let res = app
            .oneshot(get_with_bearer(
                &format!("/guards/{}/public", Uuid::new_v4()),
                &token(ROLE_CUSTOMER),
            ))
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::FORBIDDEN,
            "a customer with no active booking must not read a guard's profile"
        );
    }

    #[tokio::test]
    async fn public_profile_customer_with_active_booking_passes_authz() {
        let Some(app) = public_profile_router(true).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // Customer WITH an active booking passes the gate → reaches the repo (500s on the closed
        // lazy pool). NOT 401/403 proves authz let it through.
        let res = app
            .oneshot(get_with_bearer(
                &format!("/guards/{}/public", Uuid::new_v4()),
                &token(ROLE_CUSTOMER),
            ))
            .await
            .unwrap();
        assert_ne!(res.status(), StatusCode::UNAUTHORIZED);
        assert_ne!(
            res.status(),
            StatusCode::FORBIDDEN,
            "a customer with an active booking must pass the IDOR gate"
        );
    }

    #[tokio::test]
    async fn public_profile_guard_reading_other_is_forbidden() {
        let Some(app) = public_profile_router(false).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A guard may read only their OWN profile; a different guard id → 403 (the guard branch
        // never consults booking authz).
        let res = app
            .oneshot(get_with_bearer(
                &format!("/guards/{}/public", Uuid::new_v4()),
                &token(ROLE_GUARD),
            ))
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn public_profile_guard_reading_self_passes_authz() {
        let Some(app) = public_profile_router(false).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A guard reading their OWN id passes the gate (booking authz=false is irrelevant on the
        // guard branch) → reaches the repo (500 on the closed pool).
        let (tok, uid) = token_with_id(ROLE_GUARD);
        let res = app
            .oneshot(get_with_bearer(&format!("/guards/{uid}/public"), &tok))
            .await
            .unwrap();
        assert_ne!(res.status(), StatusCode::UNAUTHORIZED);
        assert_ne!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn public_profile_admin_passes_authz() {
        let Some(app) = public_profile_router(false).await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // Admin → any guard, no booking required → reaches the repo (500 on the closed pool).
        let res = app
            .oneshot(get_with_bearer(
                &format!("/guards/{}/public", Uuid::new_v4()),
                &token(ROLE_ADMIN),
            ))
            .await
            .unwrap();
        assert_ne!(res.status(), StatusCode::UNAUTHORIZED);
        assert_ne!(res.status(), StatusCode::FORBIDDEN);
    }

    // ----- POST/GET /profile/guard/{id}/documents — upload auth + IDOR gate -----

    /// Build a minimal `multipart/form-data` POST (text fields only) so the `Multipart` extractor
    /// succeeds and the handler's role/IDOR gate runs (those reject before file parsing).
    fn multipart_post(uri: &str, token: &str, fields: &[(&str, &str)]) -> Request<Body> {
        const B: &str = "TESTBOUNDARY";
        let mut body = String::new();
        for (name, value) in fields {
            body.push_str(&format!(
                "--{B}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n"
            ));
        }
        body.push_str(&format!("--{B}--\r\n"));
        Request::builder()
            .method("POST")
            .uri(uri)
            .header("authorization", format!("Bearer {token}"))
            .header("content-type", format!("multipart/form-data; boundary={B}"))
            .body(Body::from(body))
            .unwrap()
    }

    #[tokio::test]
    async fn document_upload_rejects_missing_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let res = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/profile/guard/{}/documents", Uuid::new_v4()))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn document_upload_rejects_customer_role() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let (tok, uid) = token_with_id(ROLE_CUSTOMER);
        let res = app
            .oneshot(multipart_post(
                &format!("/profile/guard/{uid}/documents"),
                &tok,
                &[("document_type", "id_card")],
            ))
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::FORBIDDEN,
            "only a guard may upload documents"
        );
    }

    #[tokio::test]
    async fn document_upload_idor_rejects_other_guard() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A guard uploading to a DIFFERENT guard's path → 403 (own-docs-only, no admin bypass).
        let (tok, _uid) = token_with_id(ROLE_GUARD);
        let res = app
            .oneshot(multipart_post(
                &format!("/profile/guard/{}/documents", Uuid::new_v4()),
                &tok,
                &[("document_type", "id_card")],
            ))
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::FORBIDDEN,
            "a guard must not upload another guard's documents"
        );
    }

    #[tokio::test]
    async fn document_upload_guard_self_passes_role_and_idor() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // Own path + guard role pass the gate → the handler proceeds to parse, where the missing
        // file is a 400 (NOT 401/403). Proves the role + IDOR gate let the owner through.
        let (tok, uid) = token_with_id(ROLE_GUARD);
        let res = app
            .oneshot(multipart_post(
                &format!("/profile/guard/{uid}/documents"),
                &tok,
                &[("document_type", "id_card")], // no file part
            ))
            .await
            .unwrap();
        assert_ne!(res.status(), StatusCode::UNAUTHORIZED);
        assert_ne!(res.status(), StatusCode::FORBIDDEN);
        assert_eq!(res.status(), StatusCode::BAD_REQUEST, "file is required");
    }

    #[tokio::test]
    async fn document_get_rejects_other_non_admin() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A guard reading ANOTHER guard's document → 403 (read is owner-or-admin).
        let (tok, _uid) = token_with_id(ROLE_GUARD);
        let res = app
            .oneshot(get_with_bearer(
                &format!(
                    "/profile/guard/{}/documents?document_type=id_card",
                    Uuid::new_v4()
                ),
                &tok,
            ))
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    // ----- avatar (mirrors the document upload/read gates: own-only write, owner-or-admin read) -----

    #[tokio::test]
    async fn avatar_upload_rejects_customer_role() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let (tok, uid) = token_with_id(ROLE_CUSTOMER);
        let res = app
            .oneshot(multipart_post(
                &format!("/profile/guard/{uid}/avatar"),
                &tok,
                &[],
            ))
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::FORBIDDEN,
            "only a guard may upload an avatar"
        );
    }

    #[tokio::test]
    async fn avatar_upload_idor_rejects_other_guard() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A guard uploading to a DIFFERENT guard's avatar path → 403 (own-only, no admin bypass).
        let (tok, _uid) = token_with_id(ROLE_GUARD);
        let res = app
            .oneshot(multipart_post(
                &format!("/profile/guard/{}/avatar", Uuid::new_v4()),
                &tok,
                &[],
            ))
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::FORBIDDEN,
            "a guard must not set another guard's avatar"
        );
    }

    #[tokio::test]
    async fn avatar_upload_guard_self_passes_role_and_idor() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // Own path + guard role pass the gate → the handler proceeds to parse, where the missing
        // file is a 400 (NOT 401/403). Proves the role + IDOR gate let the owner through.
        let (tok, uid) = token_with_id(ROLE_GUARD);
        let res = app
            .oneshot(multipart_post(
                &format!("/profile/guard/{uid}/avatar"),
                &tok,
                &[],
            ))
            .await
            .unwrap();
        assert_ne!(res.status(), StatusCode::UNAUTHORIZED);
        assert_ne!(res.status(), StatusCode::FORBIDDEN);
        assert_eq!(res.status(), StatusCode::BAD_REQUEST, "file is required");
    }

    #[tokio::test]
    async fn avatar_get_rejects_other_non_admin() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A guard reading ANOTHER guard's avatar → 403 (read is owner-or-admin).
        let (tok, _uid) = token_with_id(ROLE_GUARD);
        let res = app
            .oneshot(get_with_bearer(
                &format!("/profile/guard/{}/avatar", Uuid::new_v4()),
                &tok,
            ))
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    // ----- registration doc-upload token (pre-approval): guard uploads BEFORE admin review -----

    #[tokio::test]
    async fn document_upload_accepts_registration_doc_token() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A `guard_doc_upload` token for THIS user (multi-use, NOT Redis-tracked) is accepted on
        // its OWN documents path → the gate passes, so the handler proceeds to parse, where the
        // missing file is a 400 (NOT 401/403). Proves a not-yet-approved guard can upload.
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let uid = Uuid::new_v4();
        let (tok, _jti) = encode_profile_token(uid, PROFILE_PURPOSE_GUARD_DOC, &ek, 30).unwrap();
        let res = app
            .oneshot(multipart_post(
                &format!("/profile/guard/{uid}/documents"),
                &tok,
                &[("document_type", "id_card")], // no file part
            ))
            .await
            .unwrap();
        assert_ne!(res.status(), StatusCode::UNAUTHORIZED);
        assert_ne!(res.status(), StatusCode::FORBIDDEN);
        assert_eq!(res.status(), StatusCode::BAD_REQUEST, "file is required");
    }

    #[tokio::test]
    async fn document_upload_doc_token_idor_rejects_other_guard() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A doc token minted for user A must NOT upload to user B's documents path (own-only).
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, _jti) =
            encode_profile_token(Uuid::new_v4(), PROFILE_PURPOSE_GUARD_DOC, &ek, 30).unwrap();
        let res = app
            .oneshot(multipart_post(
                &format!("/profile/guard/{}/documents", Uuid::new_v4()),
                &tok,
                &[("document_type", "id_card")],
            ))
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn document_upload_admin_can_upload_for_any_guard() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // An admin may upload a document on behalf of ANY guard (forgot-to-attach override) — the
        // gate passes for a DIFFERENT user_id, so the handler proceeds to parse, where the missing
        // file is a 400 (NOT 401/403). Proves admin is NOT blocked by the own-only IDOR check.
        let (tok, _uid) = token_with_id(ROLE_ADMIN);
        let res = app
            .oneshot(multipart_post(
                &format!("/profile/guard/{}/documents", Uuid::new_v4()),
                &tok,
                &[("document_type", "id_card")], // no file part
            ))
            .await
            .unwrap();
        assert_ne!(res.status(), StatusCode::UNAUTHORIZED);
        assert_ne!(res.status(), StatusCode::FORBIDDEN);
        assert_eq!(res.status(), StatusCode::BAD_REQUEST, "file is required");
    }

    #[tokio::test]
    async fn document_expiries_get_idor_rejects_other_guard() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A guard reads ONLY their own expiries — another guard's path → 403 (before any DB read).
        let (tok, _uid) = token_with_id(ROLE_GUARD);
        let res = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(format!(
                        "/profile/guard/{}/document-expiries",
                        Uuid::new_v4()
                    ))
                    .header("authorization", format!("Bearer {tok}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn document_expiry_put_idor_rejects_other_guard() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // A guard edits ONLY their own expiry — another guard's path → 403 (before any DB write).
        let (tok, _uid) = token_with_id(ROLE_GUARD);
        let res = app
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/profile/guard/{}/document-expiry", Uuid::new_v4()))
                    .header("authorization", format!("Bearer {tok}"))
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{"document_type":"id_card","expiry_date":"2028-01-01"}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::FORBIDDEN);
    }

    #[tokio::test]
    async fn document_expiry_put_rejects_non_expiring_type() {
        let Some(app) = router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        // Own guard, but the passbook has no expiry → 400 (validated BEFORE any DB write).
        let (tok, uid) = token_with_id(ROLE_GUARD);
        let res = app
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/profile/guard/{uid}/document-expiry"))
                    .header("authorization", format!("Bearer {tok}"))
                    .header("content-type", "application/json")
                    .body(Body::from(
                        r#"{"document_type":"passbook_photo","expiry_date":"2028-01-01"}"#,
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::BAD_REQUEST);
    }

    // ----- dual-auth: single-use, purpose-isolated profile_token -----

    use redis::AsyncCommands;
    use shared::auth::{encode_profile_token, PROFILE_PURPOSE_GUARD};

    /// Router (guard + customer POST routes) plus the live Redis conn, so the profile_token
    /// tests can seed/inspect the single-use `profile_jti` marker. Redis-gated like `router()`.
    async fn token_router() -> Option<(Router, redis::aio::ConnectionManager)> {
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
            redis: redis.clone(),
            authz: StubAuthz { allow: false },
            s3: test_s3(),
        };
        let app = Router::new()
            .route("/profile/guard", post(upsert_guard_profile::<TestDeps>))
            .route(
                "/profile/customer",
                post(upsert_customer_profile::<TestDeps>),
            )
            .with_state(deps);
        Some((app, redis))
    }

    fn post_with_bearer(uri: &str, token: &str, body: Body) -> Request<Body> {
        Request::builder()
            .method("POST")
            .uri(uri)
            .header("authorization", format!("Bearer {token}"))
            .header("content-type", "application/json")
            .body(body)
            .unwrap()
    }

    fn customer_body() -> Body {
        Body::from(serde_json::json!({ "full_name": "Somchai" }).to_string())
    }

    /// A valid `guard_profile` token authorizes the guard route (NOT 401/403 — it reaches the
    /// repo, which 500s on the closed lazy pool) and is single-use: the second presentation is
    /// rejected 401 (the jti was consumed via GETDEL). NB this also documents the deliberate
    /// consume-on-extract trade-off — the first call's repo write FAILED (500) yet the token is
    /// still burned, so reuse 401s (atomicity over retry-after-partial-failure; see the resolver).
    #[tokio::test]
    async fn guard_profile_token_is_accepted_and_single_use() {
        let Some((app, mut redis)) = token_router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, jti) =
            encode_profile_token(Uuid::new_v4(), PROFILE_PURPOSE_GUARD, &ek, 15).unwrap();
        let _: () = redis
            .set_ex(format!("profile_jti:{jti}"), "valid", 600)
            .await
            .expect("seed jti");

        let res = app
            .clone()
            .oneshot(post_with_bearer("/profile/guard", &tok, guard_body()))
            .await
            .unwrap();
        assert_ne!(
            res.status(),
            StatusCode::UNAUTHORIZED,
            "valid token must pass auth"
        );
        assert_ne!(
            res.status(),
            StatusCode::FORBIDDEN,
            "purpose grants the route"
        );

        // Second use of the same token → jti already consumed → 401.
        let res2 = app
            .oneshot(post_with_bearer("/profile/guard", &tok, guard_body()))
            .await
            .unwrap();
        assert_eq!(
            res2.status(),
            StatusCode::UNAUTHORIZED,
            "profile_token is single-use"
        );
    }

    /// Purpose isolation: a `guard_profile` token on the CUSTOMER route is rejected (401), and
    /// crucially the token is NOT consumed — it must remain usable on its correct guard route.
    #[tokio::test]
    async fn guard_profile_token_rejected_on_customer_route_and_not_consumed() {
        let Some((app, mut redis)) = token_router().await else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, jti) =
            encode_profile_token(Uuid::new_v4(), PROFILE_PURPOSE_GUARD, &ek, 15).unwrap();
        let key = format!("profile_jti:{jti}");
        let _: () = redis.set_ex(&key, "valid", 600).await.expect("seed jti");

        let res = app
            .oneshot(post_with_bearer("/profile/customer", &tok, customer_body()))
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::UNAUTHORIZED,
            "a guard token must not authorize the customer route"
        );

        // The token must still be live (purpose mismatch does not burn it).
        let still_valid: bool = redis.exists(&key).await.expect("exists check");
        assert!(
            still_valid,
            "a purpose-mismatched token must NOT be consumed"
        );
        let _: () = redis.del(&key).await.unwrap_or(());
    }

    /// End-to-end boundary proof (DATABASE_URL + Redis): a guard submits their profile with a
    /// `profile_token` (NOT logged in) — the guard_profiles row is written, while the
    /// identity-owned `identity.users.role` is left untouched (no cross-schema write). Gated on
    /// both a real Postgres (identity 0001+0003 + profile 0001 migrated) and a test Redis.
    #[tokio::test]
    async fn profile_token_writes_profile_but_not_identity_role() {
        let Ok(db_url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL required for the boundary test");
            return;
        };
        let Ok(redis_url) =
            std::env::var("TEST_REDIS_URL").or_else(|_| std::env::var("REDIS_CACHE_URL"))
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&db_url)
            .await
            .expect("connect Postgres");
        let mut redis = shared::redis_client::create_connection_manager(&redis_url)
            .await
            .expect("redis conn");

        // Seed an identity user (role=guard, pending) — as identity's register would.
        let uid = Uuid::new_v4();
        let phone: String = format!(
            "0{}",
            uid.simple()
                .to_string()
                .chars()
                .filter(|c| c.is_ascii_digit())
                .take(9)
                .collect::<String>()
        );
        sqlx::query(
            "INSERT INTO identity.users (id, phone, password_hash, role, approval_status) \
             VALUES ($1, $2, 'x', 'guard', 'pending'::identity.approval_status)",
        )
        .bind(uid)
        .bind(&phone)
        .execute(&pool)
        .await
        .expect("seed identity user");

        // Router over the REAL pool; issue + seed a single-use guard profile_token.
        let deps = TestDeps {
            dec: Arc::new(DecodingKey::from_secret(SECRET.as_bytes())),
            db: pool.clone(),
            redis: redis.clone(),
            authz: StubAuthz { allow: false },
            s3: test_s3(),
        };
        let app = Router::new()
            .route("/profile/guard", post(upsert_guard_profile::<TestDeps>))
            .with_state(deps);
        let ek = EncodingKey::from_secret(SECRET.as_bytes());
        let (tok, jti) = encode_profile_token(uid, PROFILE_PURPOSE_GUARD, &ek, 15).unwrap();
        let _: () = redis
            .set_ex(format!("profile_jti:{jti}"), "valid", 600)
            .await
            .expect("seed jti");

        let res = app
            .oneshot(post_with_bearer(
                "/profile/guard",
                &tok,
                Body::from(serde_json::json!({ "years_of_experience": 3 }).to_string()),
            ))
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::OK,
            "profile_token submission succeeds"
        );

        // The profile row was written...
        let (count,): (i64,) = sqlx::query_as(
            "SELECT count(*)::bigint FROM profile.guard_profiles WHERE user_id = $1",
        )
        .bind(uid)
        .fetch_one(&pool)
        .await
        .expect("count profile");
        assert_eq!(count, 1, "guard profile written");

        // ...and the identity-owned role is UNCHANGED (no cross-schema write).
        let (role,): (String,) =
            sqlx::query_as("SELECT role::text FROM identity.users WHERE id = $1")
                .bind(uid)
                .fetch_one(&pool)
                .await
                .expect("read role");
        assert_eq!(role, "guard", "profile must NOT touch identity.users.role");

        // cleanup
        let _ = sqlx::query("DELETE FROM profile.guard_profiles WHERE user_id = $1")
            .bind(uid)
            .execute(&pool)
            .await;
        let _ = sqlx::query("DELETE FROM identity.users WHERE id = $1")
            .bind(uid)
            .execute(&pool)
            .await;
    }

    // ----- internal guard catalog: service-JWT guard (no Redis/DB needed) -----

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
    impl ProfileInternalDeps for InternalDeps {
        fn db(&self) -> &sqlx::PgPool {
            &self.db
        }
    }

    /// Internal router over a lightweight state. The `ServiceCaller` extractor only needs the
    /// service decoding key — no Redis, no live DB. Rejected requests short-circuit at the
    /// guard before any DB access (mirrors booking's internal_router test).
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
                "/internal/guards",
                get(internal_list_guards::<InternalDeps>),
            )
            .route(
                "/internal/profiles/recipients",
                get(internal_list_recipients::<InternalDeps>),
            )
            .with_state(deps)
    }

    #[tokio::test]
    async fn internal_guards_rejects_missing_token() {
        let res = internal_router()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/internal/guards")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn internal_guards_rejects_invalid_token() {
        let res = internal_router()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/internal/guards")
                    .header("authorization", "Bearer not.a.valid.jwt")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn internal_guards_accepts_valid_service_token() {
        // A valid service-JWT (as minted by booking) must pass the guard; the handler then
        // queries the (unreachable) DB, so the response is NOT 401 — proving auth passed.
        use shared::service_jwt::encode_service_jwt;
        let ek = EncodingKey::from_secret(SERVICE_SECRET.as_bytes());
        let tok = encode_service_jwt("booking", &ek, 60).unwrap();
        let res = internal_router()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/internal/guards")
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

    // ----- internal broadcast-recipients: service-JWT guard (no Redis/DB needed) -----

    #[tokio::test]
    async fn internal_recipients_rejects_missing_token() {
        let res = internal_router()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/internal/profiles/recipients?audience=guards")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn internal_recipients_accepts_valid_service_token() {
        // A valid service-JWT (as minted by notification) must pass the guard; the handler then
        // queries the (unreachable) DB, so the response is NOT 401 — proving auth passed.
        use shared::service_jwt::encode_service_jwt;
        let ek = EncodingKey::from_secret(SERVICE_SECRET.as_bytes());
        let tok = encode_service_jwt("notification", &ek, 60).unwrap();
        let res = internal_router()
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri("/internal/profiles/recipients?audience=all")
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
}

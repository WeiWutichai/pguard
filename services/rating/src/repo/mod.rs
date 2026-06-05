//! Repository layer — the ONLY place that touches the `rating` schema.
//!
//! Uses runtime `sqlx::query`/`query_as` (not the compile-time `query!` macro): the
//! scaffold has no DATABASE_URL / offline `.sqlx` cache at build time (mirrors the other
//! slices). The anchor write is [`submit_review_tx`]: the review row AND its
//! `rating.submitted` outbox event are written in ONE transaction (CLAUDE.md "Cross-tx
//! consistency: transactional outbox").

use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde_json::Value;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::{topics, EventEnvelope};

use crate::domain::{self, RatingSummary};
use crate::models::{
    AdminReviewResponse, AdminReviewStats, AdminReviewsResponse, CreateReviewRequest,
    ReviewResponse,
};

/// Public review projection (no customer identity exposed).
const REVIEW_COLUMNS: &str = "id, guard_id, overall_rating, punctuality, professionalism, \
     communication, appearance, review_text, created_at";

/// Admin review projection (adds assignment/customer ids + visibility).
const ADMIN_COLUMNS: &str = "id, assignment_id, customer_id, guard_id, overall_rating, \
     punctuality, professionalism, communication, appearance, review_text, is_visible, created_at";

// ----- Outbox row (for the relay) -----

/// One unpublished outbox row, as the relay reads it.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct OutboxRow {
    pub id: Uuid,
    pub topic: String,
    /// The serialized `EventEnvelope` (JSONB).
    pub payload: Value,
}

// ----- Writes -----

/// Submit a review: INSERT the row AND enqueue `pguard.events.rating.submitted` into the
/// outbox in ONE transaction. `guard_id`/`customer_id`/`assignment_id` come from the
/// AUTHORITATIVE booking read (verified by the caller), never the request body. The DB
/// `UNIQUE(assignment_id)` enforces one-review-per-assignment: a duplicate → `Conflict`.
/// Ratings are narrowed to `i16` (validated `1..=5` upstream, so the cast is lossless).
#[tracing::instrument(skip(db, req), fields(guard_id = %guard_id, assignment_id = %assignment_id))]
#[allow(clippy::too_many_arguments)]
pub async fn submit_review_tx(
    db: &sqlx::PgPool,
    guard_id: Uuid,
    customer_id: Uuid,
    assignment_id: Uuid,
    req: &CreateReviewRequest,
    correlation_id: Uuid,
) -> Result<Uuid, AppError> {
    let mut tx = db.begin().await?;

    // 1) the business change. ON CONFLICT (assignment_id) maps the duplicate to a clean 409
    //    (DO NOTHING returns no row → we detect it and report Conflict).
    let inserted: Option<Uuid> = sqlx::query_scalar(
        "INSERT INTO rating.guard_reviews \
           (guard_id, customer_id, assignment_id, overall_rating, punctuality, \
            professionalism, communication, appearance, review_text) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) \
         ON CONFLICT (assignment_id) DO NOTHING \
         RETURNING id",
    )
    .bind(guard_id)
    .bind(customer_id)
    .bind(assignment_id)
    .bind(req.overall_rating as i16)
    .bind(req.punctuality.map(|v| v as i16))
    .bind(req.professionalism.map(|v| v as i16))
    .bind(req.communication.map(|v| v as i16))
    .bind(req.appearance.map(|v| v as i16))
    .bind(req.review_text.as_deref())
    .fetch_optional(&mut *tx)
    .await?;

    let Some(review_id) = inserted else {
        tx.rollback().await?;
        return Err(AppError::Conflict(
            "A review already exists for this assignment".to_string(),
        ));
    };

    // 2) the event — SAME transaction (transactional outbox). Payload matches the AsyncAPI
    //    `EnvelopeOf_RatingRef` + notification's consumer: { rating_id, booking_id, guard_id, score }.
    let payload = serde_json::json!({
        "rating_id": review_id,
        "booking_id": assignment_id,
        "guard_id": guard_id,
        "score": req.overall_rating,
    });
    enqueue_outbox(&mut tx, topics::RATING_SUBMITTED, payload, correlation_id).await?;

    tx.commit().await?;
    Ok(review_id)
}

/// Toggle a review's visibility (admin moderation). 404 if the review does not exist.
pub async fn set_visibility(
    db: &sqlx::PgPool,
    review_id: Uuid,
    is_visible: bool,
) -> Result<(), AppError> {
    let result = sqlx::query(
        "UPDATE rating.guard_reviews SET is_visible = $1, updated_at = now() WHERE id = $2",
    )
    .bind(is_visible)
    .bind(review_id)
    .execute(db)
    .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound("Review not found".to_string()));
    }
    Ok(())
}

// ----- Reads -----

/// A guard's public ratings: the VISIBLE reviews (newest first, bounded) + the aggregate
/// summary. Both filter `is_visible = true` so admin-hidden reviews never surface.
pub async fn guard_ratings(
    db: &sqlx::PgPool,
    guard_id: Uuid,
    limit: i64,
) -> Result<(RatingSummary, Vec<ReviewResponse>), AppError> {
    let summary = guard_summary(db, guard_id).await?;
    let sql = format!(
        "SELECT {REVIEW_COLUMNS} FROM rating.guard_reviews \
         WHERE guard_id = $1 AND is_visible = true \
         ORDER BY created_at DESC LIMIT $2"
    );
    let reviews = sqlx::query_as::<_, ReviewResponse>(&sql)
        .bind(guard_id)
        .bind(limit.clamp(1, 200))
        .fetch_all(db)
        .await?;
    Ok((summary, reviews))
}

/// Aggregate a guard's VISIBLE overall ratings into `{ count, average }`. The visibility
/// filter lives in the SQL; the aggregation math is the pure [`domain::compute_summary`].
pub async fn guard_summary(db: &sqlx::PgPool, guard_id: Uuid) -> Result<RatingSummary, AppError> {
    let scores: Vec<i16> = sqlx::query_scalar(
        "SELECT overall_rating FROM rating.guard_reviews \
         WHERE guard_id = $1 AND is_visible = true",
    )
    .bind(guard_id)
    .fetch_all(db)
    .await?;
    let scores: Vec<i32> = scores.into_iter().map(i32::from).collect();
    Ok(domain::compute_summary(&scores))
}

/// PDPA §19/§32 data export: ALL reviews AUTHORED by the user (as the reviewing customer),
/// regardless of admin visibility — it is the user's own content. Scoped to `customer_id`.
pub async fn export_user_reviews(db: &sqlx::PgPool, customer_id: Uuid) -> Result<Value, AppError> {
    #[allow(clippy::type_complexity)]
    let rows: Vec<(
        Uuid,
        Uuid,
        Uuid,
        i16,
        Option<i16>,
        Option<i16>,
        Option<i16>,
        Option<i16>,
        Option<String>,
        bool,
        DateTime<Utc>,
        DateTime<Utc>,
    )> = sqlx::query_as(
        "SELECT id, guard_id, assignment_id, overall_rating, punctuality, professionalism, \
                communication, appearance, review_text, is_visible, created_at, updated_at \
         FROM rating.guard_reviews WHERE customer_id = $1 ORDER BY created_at DESC",
    )
    .bind(customer_id)
    .fetch_all(db)
    .await?;

    let reviews: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            let (
                id,
                guard_id,
                assignment_id,
                overall,
                punct,
                prof,
                comm,
                appear,
                text,
                is_visible,
                created_at,
                updated_at,
            ) = r;
            serde_json::json!({
                "id": id,
                "guard_id": guard_id,
                "assignment_id": assignment_id,
                "overall_rating": overall,
                "punctuality": punct,
                "professionalism": prof,
                "communication": comm,
                "appearance": appear,
                "review_text": text,
                "is_visible": is_visible,
                "created_at": created_at,
                "updated_at": updated_at,
            })
        })
        .collect();
    Ok(Value::Array(reviews))
}

/// Admin moderation list: reviews matching the (optional) filters + the total + GLOBAL
/// stats. The stats are computed on the UNFILTERED dataset (v1 rule — the cards reflect the
/// whole dataset, not the current filter). Dynamic WHERE binds all user values as `$n`
/// (never `format!` with user input); only the constant column list is interpolated.
pub async fn list_admin_reviews(
    db: &sqlx::PgPool,
    guard_id: Option<Uuid>,
    rating: Option<i32>,
    is_visible: Option<bool>,
    search: Option<&str>,
    limit: i64,
    offset: i64,
) -> Result<AdminReviewsResponse, AppError> {
    let limit = limit.clamp(1, 200);
    let offset = offset.max(0);
    let search = search.map(|s| s.trim()).filter(|s| !s.is_empty());

    // Build the WHERE with positional binds. Order of pushes MUST match the bind order below.
    let mut clauses: Vec<String> = Vec::new();
    let mut idx = 0;
    if guard_id.is_some() {
        idx += 1;
        clauses.push(format!("guard_id = ${idx}"));
    }
    if rating.is_some() {
        idx += 1;
        clauses.push(format!("overall_rating = ${idx}"));
    }
    if is_visible.is_some() {
        idx += 1;
        clauses.push(format!("is_visible = ${idx}"));
    }
    if search.is_some() {
        idx += 1;
        clauses.push(format!("review_text ILIKE ${idx}"));
    }
    let where_sql = if clauses.is_empty() {
        String::new()
    } else {
        format!("WHERE {}", clauses.join(" AND "))
    };
    let limit_idx = idx + 1;
    let offset_idx = idx + 2;

    let list_sql = format!(
        "SELECT {ADMIN_COLUMNS} FROM rating.guard_reviews {where_sql} \
         ORDER BY created_at DESC LIMIT ${limit_idx} OFFSET ${offset_idx}"
    );
    let count_sql = format!("SELECT COUNT(*) FROM rating.guard_reviews {where_sql}");

    let mut list_q = sqlx::query_as::<_, AdminReviewResponse>(&list_sql);
    let mut count_q = sqlx::query_scalar::<_, i64>(&count_sql);
    if let Some(g) = guard_id {
        list_q = list_q.bind(g);
        count_q = count_q.bind(g);
    }
    if let Some(r) = rating {
        list_q = list_q.bind(r as i16);
        count_q = count_q.bind(r as i16);
    }
    if let Some(v) = is_visible {
        list_q = list_q.bind(v);
        count_q = count_q.bind(v);
    }
    if let Some(s) = search {
        let pattern = format!("%{s}%");
        list_q = list_q.bind(pattern.clone());
        count_q = count_q.bind(pattern);
    }
    list_q = list_q.bind(limit).bind(offset);

    let data = list_q.fetch_all(db).await?;
    let total = count_q.fetch_one(db).await?;

    // Global (unfiltered) stats.
    let (s_total, s_visible, s_avg): (Option<i64>, Option<i64>, Option<Decimal>) = sqlx::query_as(
        "SELECT COUNT(*), COUNT(*) FILTER (WHERE is_visible = true), AVG(overall_rating) \
         FROM rating.guard_reviews",
    )
    .fetch_one(db)
    .await?;
    let stats = AdminReviewStats {
        total: s_total.unwrap_or(0),
        visible: s_visible.unwrap_or(0),
        average: s_avg.map(|d| d.round_dp(2)),
    };

    Ok(AdminReviewsResponse {
        data,
        total,
        limit,
        offset,
        stats,
    })
}

// ----- Outbox helpers + relay support -----

/// Insert one outbox row (a fully-formed EventEnvelope) inside the caller's transaction.
async fn enqueue_outbox(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    topic: &str,
    payload: Value,
    correlation_id: Uuid,
) -> Result<(), AppError> {
    let envelope = EventEnvelope::new(topic, correlation_id, payload);
    let envelope_json = serde_json::to_value(&envelope)
        .map_err(|e| AppError::Internal(format!("serialize event envelope: {e}")))?;
    sqlx::query("INSERT INTO rating.outbox (topic, payload) VALUES ($1, $2)")
        .bind(topic)
        .bind(&envelope_json)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

/// Fetch up to `limit` unpublished outbox rows, oldest first.
pub async fn fetch_unpublished(db: &sqlx::PgPool, limit: i64) -> Result<Vec<OutboxRow>, AppError> {
    let rows = sqlx::query_as::<_, OutboxRow>(
        "SELECT id, topic, payload FROM rating.outbox \
         WHERE published_at IS NULL ORDER BY created_at LIMIT $1",
    )
    .bind(limit)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Stamp one outbox row published (called only after a successful NATS publish).
pub async fn mark_published(db: &sqlx::PgPool, id: Uuid) -> Result<(), AppError> {
    sqlx::query("UPDATE rating.outbox SET published_at = now() WHERE id = $1")
        .bind(id)
        .execute(db)
        .await?;
    Ok(())
}

#[cfg(test)]
mod db_tests {
    use super::*;
    use sqlx::postgres::PgPoolOptions;
    use std::time::Duration;

    async fn pool() -> Option<sqlx::PgPool> {
        let url = std::env::var("DATABASE_URL").ok()?;
        PgPoolOptions::new()
            .acquire_timeout(Duration::from_secs(5))
            .connect(&url)
            .await
            .ok()
    }

    fn review(overall: i32) -> CreateReviewRequest {
        CreateReviewRequest {
            overall_rating: overall,
            punctuality: Some(4),
            professionalism: None,
            communication: None,
            appearance: None,
            review_text: Some("great".to_string()),
        }
    }

    /// submit → exactly one review row + one rating.submitted outbox event; a second submit
    /// for the same assignment → Conflict (one-per-assignment). DATABASE_URL-gated.
    #[tokio::test]
    async fn submit_is_one_per_assignment_and_emits_event() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let guard_id = Uuid::new_v4();
        let customer_id = Uuid::new_v4();
        let assignment_id = Uuid::new_v4();
        let correlation = Uuid::new_v4();

        let id = submit_review_tx(
            &pool,
            guard_id,
            customer_id,
            assignment_id,
            &review(5),
            correlation,
        )
        .await
        .expect("submit");

        // exactly one rating.submitted event carrying the right ids/score
        let events: Vec<Value> = sqlx::query_scalar(
            "SELECT payload->'payload' FROM rating.outbox \
             WHERE topic = $1 AND payload->'payload'->>'booking_id' = $2",
        )
        .bind(topics::RATING_SUBMITTED)
        .bind(assignment_id.to_string())
        .fetch_all(&pool)
        .await
        .expect("events");
        assert_eq!(events.len(), 1, "exactly one rating.submitted event");
        assert_eq!(events[0]["guard_id"], serde_json::json!(guard_id));
        assert_eq!(events[0]["rating_id"], serde_json::json!(id));
        assert_eq!(events[0]["score"], serde_json::json!(5));

        // second submit for the same assignment → Conflict (one-per-assignment)
        let dup = submit_review_tx(
            &pool,
            guard_id,
            customer_id,
            assignment_id,
            &review(3),
            Uuid::new_v4(),
        )
        .await;
        assert!(
            matches!(dup, Err(AppError::Conflict(_))),
            "duplicate must be a Conflict"
        );

        // still exactly one review row
        let count: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM rating.guard_reviews WHERE assignment_id = $1",
        )
        .bind(assignment_id)
        .fetch_one(&pool)
        .await
        .expect("count");
        assert_eq!(count, 1, "one-per-assignment enforced");

        cleanup(&pool, assignment_id, guard_id).await;
    }

    /// Admin hiding a review removes it from the public summary + list (is_visible filter).
    /// DATABASE_URL-gated.
    #[tokio::test]
    async fn hidden_review_drops_from_public_summary() {
        let Some(pool) = pool().await else {
            eprintln!("SKIP: DATABASE_URL not set (hermetic default)");
            return;
        };
        let guard_id = Uuid::new_v4();
        let a1 = Uuid::new_v4();
        let a2 = Uuid::new_v4();

        let r1 = submit_review_tx(
            &pool,
            guard_id,
            Uuid::new_v4(),
            a1,
            &review(5),
            Uuid::new_v4(),
        )
        .await
        .expect("r1");
        submit_review_tx(
            &pool,
            guard_id,
            Uuid::new_v4(),
            a2,
            &review(3),
            Uuid::new_v4(),
        )
        .await
        .expect("r2");

        // both visible → count 2, avg 4.00
        let (summary, reviews) = guard_ratings(&pool, guard_id, 50).await.expect("ratings");
        assert_eq!(summary.count, 2);
        assert_eq!(summary.average, Some("4.00".parse().unwrap()));
        assert_eq!(reviews.len(), 2);

        // hide r1 (the 5) → public summary now count 1, avg 3.00; admin stats still see both
        set_visibility(&pool, r1, false).await.expect("hide");
        let (summary, reviews) = guard_ratings(&pool, guard_id, 50)
            .await
            .expect("ratings after hide");
        assert_eq!(summary.count, 1, "hidden review excluded from public count");
        assert_eq!(summary.average, Some("3.00".parse().unwrap()));
        assert_eq!(reviews.len(), 1);

        let admin = list_admin_reviews(&pool, Some(guard_id), None, None, None, 50, 0)
            .await
            .expect("admin list");
        assert_eq!(admin.total, 2, "admin sees hidden + visible");

        cleanup(&pool, a1, guard_id).await;
        cleanup(&pool, a2, guard_id).await;
    }

    async fn cleanup(pool: &sqlx::PgPool, assignment_id: Uuid, guard_id: Uuid) {
        let _ =
            sqlx::query("DELETE FROM rating.outbox WHERE payload->'payload'->>'booking_id' = $1")
                .bind(assignment_id.to_string())
                .execute(pool)
                .await;
        let _ = sqlx::query("DELETE FROM rating.guard_reviews WHERE guard_id = $1")
            .bind(guard_id)
            .execute(pool)
            .await;
    }
}

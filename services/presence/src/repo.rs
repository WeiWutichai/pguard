//! Repository — the only sqlx in presence. Owns the `presence.location_history` retention
//! purge (PDPA §7.3 / the headline v1 gap: sensitive GPS history had no retention at all).

use chrono::{DateTime, Utc};
use sqlx::PgPool;

/// Delete location-history rows older than `cutoff`; returns the number purged. The
/// `idx_location_history_recorded_at` BRIN index makes this range-delete efficient on the
/// high-volume append-only store.
pub async fn purge_older_than(pool: &PgPool, cutoff: DateTime<Utc>) -> Result<u64, sqlx::Error> {
    let res = sqlx::query("DELETE FROM presence.location_history WHERE recorded_at < $1")
        .bind(cutoff)
        .execute(pool)
        .await?;
    Ok(res.rows_affected())
}

#[cfg(test)]
mod tests {
    //! DB-gated proof of the retention purge: seed an OLD + a RECENT row, purge at a 90-day
    //! cutoff, assert the old row is deleted and the recent kept. Gated on `DATABASE_URL`
    //! (a migrated DB with presence 0001 applied); hermetic SKIP otherwise, so `cargo test`
    //! stays offline-safe. Run:
    //!   DATABASE_URL=postgres://pguard:pguard_dev_pw@localhost:5433/pguard \
    //!     cargo test -p pguard-presence -- purge --nocapture
    use super::*;
    use chrono::Duration;
    use sqlx::postgres::PgPoolOptions;
    use uuid::Uuid;

    #[tokio::test]
    async fn purge_deletes_old_keeps_recent() {
        let Ok(db_url) = std::env::var("DATABASE_URL") else {
            eprintln!("SKIP: DATABASE_URL required for the presence retention purge test");
            return;
        };
        let pool = PgPoolOptions::new()
            .acquire_timeout(std::time::Duration::from_secs(5))
            .connect(&db_url)
            .await
            .expect("connect real Postgres");

        let user_id = Uuid::new_v4();
        let now = Utc::now();
        let old_at = now - Duration::days(100);
        let recent_at = now - Duration::days(1);

        for (at, lat) in [(old_at, 13.7), (recent_at, 13.8)] {
            sqlx::query(
                "INSERT INTO presence.location_history (user_id, latitude, longitude, recorded_at) \
                 VALUES ($1, $2, $3, $4)",
            )
            .bind(user_id)
            .bind(lat)
            .bind(100.5)
            .bind(at)
            .execute(&pool)
            .await
            .expect("seed location_history");
        }

        let cutoff = now - Duration::days(90);
        let purged = purge_older_than(&pool, cutoff).await.expect("purge");
        assert!(purged >= 1, "at least the seeded old row is purged");

        let remaining: i64 =
            sqlx::query_scalar("SELECT count(*) FROM presence.location_history WHERE user_id = $1")
                .bind(user_id)
                .fetch_one(&pool)
                .await
                .expect("count remaining");
        assert_eq!(remaining, 1, "recent row kept, old row purged");

        let _ = sqlx::query("DELETE FROM presence.location_history WHERE user_id = $1")
            .bind(user_id)
            .execute(&pool)
            .await;
    }
}

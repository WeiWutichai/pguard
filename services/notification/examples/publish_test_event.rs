//! Dev helper: publish a test `pguard.events.booking.job_accepted` envelope to NATS so
//! the notification consumer can be exercised end-to-end.
//!
//! Usage:
//!   cargo run -p pguard-notification --example publish_test_event [-- <event_id_uuid>]
//!
//! Re-running with the SAME event_id proves idempotency (consumer dedupes → no new row).
//! A fresh event_id produces a new notification. NATS_URL defaults to nats://localhost:4222.

use serde_json::json;
use shared_events::{topics, EventEnvelope};
use uuid::Uuid;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let nats_url =
        std::env::var("NATS_URL").unwrap_or_else(|_| "nats://localhost:4222".to_string());

    // Fixed default id so two runs with no arg collide (idempotency demo).
    let event_id = match std::env::args().nth(1) {
        Some(s) => Uuid::parse_str(&s)?,
        None => Uuid::parse_str("11111111-1111-1111-1111-111111111111")?,
    };
    // Fixed customer so all test notifications land on one recipient (easy to query).
    let customer_id = Uuid::parse_str("22222222-2222-2222-2222-222222222222")?;

    let envelope = EventEnvelope {
        event_id,
        event_type: topics::BOOKING_JOB_ACCEPTED.to_string(),
        occurred_at: chrono::Utc::now(),
        correlation_id: Uuid::new_v4(),
        // Dev helper publishes outside any request span → no producer trace to carry.
        traceparent: None,
        payload: json!({
            "customer_id": customer_id,
            "guard_id": Uuid::new_v4(),
            "booking_id": Uuid::new_v4(),
        }),
    };

    let client = async_nats::connect(&nats_url).await?;
    let bytes = serde_json::to_vec(&envelope)?;
    client
        .publish(envelope.event_type.clone(), bytes.into())
        .await?;
    client.flush().await?;

    println!(
        "published event_id={} type={} recipient(customer_id)={} -> {}",
        envelope.event_id, envelope.event_type, customer_id, nats_url
    );
    Ok(())
}

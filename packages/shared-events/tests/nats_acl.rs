//! Gated integration test for the NATS subject-permission ACL (`infra/docker/nats.conf`).
//!
//! Proves the ACL is ENFORCED by the broker, not just syntactically valid: a producer may
//! publish its own bounded-context subjects but is denied a foreign context, and a
//! consumer-only service may publish nothing.
//!
//! Gated (skips when unset) on:
//!   - `NATS_AUTHZ_URL`      — an AUTH-enabled broker running `infra/docker/nats.conf`
//!   - `NATS_AUTHZ_PASSWORD` — the password every per-service user is configured with for the
//!     test broker (the test connects as several users with this one shared value; production
//!     uses a DISTINCT password per user).
//!
//! CI starts that broker (a 2nd nats on :4223 with all `NATS_*_PASSWORD` set to one value) in
//! the `rust-integration` job; locally, see the run command in the PR / SECRET-ROTATION docs.
//! Hermetic `cargo test` (no env) SKIPs, so the suite stays green without a broker.

use std::time::Duration;

const STREAM: &str = "PGUARD_EVENTS";
const SUBJECTS: &str = "pguard.events.>";

fn authz_env() -> Option<(String, String)> {
    let url = std::env::var("NATS_AUTHZ_URL").ok()?;
    let pass = std::env::var("NATS_AUTHZ_PASSWORD").ok()?;
    Some((url, pass))
}

async fn jetstream_as(url: &str, user: &str, pass: &str) -> async_nats::jetstream::Context {
    let client = async_nats::ConnectOptions::new()
        .user_and_password(user.to_string(), pass.to_string())
        .connect(url)
        .await
        .unwrap_or_else(|e| panic!("connect as {user}: {e}"));
    async_nats::jetstream::new(client)
}

/// Ensure the shared stream exists (any JS-permitted user may `get_or_create`).
async fn ensure_stream(js: &async_nats::jetstream::Context) {
    js.get_or_create_stream(async_nats::jetstream::stream::Config {
        name: STREAM.to_string(),
        subjects: vec![SUBJECTS.to_string()],
        ..Default::default()
    })
    .await
    .expect("get_or_create stream (JS control plane)");
}

/// `true` if a JetStream publish to `subject` is DENIED — either the publish call errors, or the
/// ack never arrives (an ACL-blocked publish is dropped by the broker, so the ack times out).
async fn publish_denied(js: &async_nats::jetstream::Context, subject: &str) -> bool {
    match js.publish(subject.to_string(), vec![1, 2, 3].into()).await {
        Err(_) => true,
        Ok(ack) => tokio::time::timeout(Duration::from_secs(2), ack)
            .await
            .map(|r| r.is_err()) // resolved with an error → denied
            .unwrap_or(true), // timed out → no ack → denied (dropped by the ACL)
    }
}

/// `true` if a JetStream publish to `subject` is ALLOWED (ack returns OK within the timeout).
async fn publish_allowed(js: &async_nats::jetstream::Context, subject: &str) -> bool {
    match js.publish(subject.to_string(), vec![1, 2, 3].into()).await {
        Err(_) => false,
        Ok(ack) => matches!(
            tokio::time::timeout(Duration::from_secs(2), ack).await,
            Ok(Ok(_))
        ),
    }
}

#[tokio::test]
async fn producer_publishes_own_context_but_is_denied_a_foreign_one() {
    let Some((url, pass)) = authz_env() else {
        eprintln!("SKIP: NATS_AUTHZ_URL/NATS_AUTHZ_PASSWORD not set (no auth broker)");
        return;
    };
    let js = jetstream_as(&url, "booking", &pass).await;
    ensure_stream(&js).await;

    assert!(
        publish_allowed(&js, "pguard.events.booking.job_accepted").await,
        "booking MUST be able to publish its own context"
    );
    assert!(
        publish_denied(&js, "pguard.events.payment.completed").await,
        "booking MUST NOT be able to forge a payment event"
    );
    assert!(
        publish_denied(&js, "pguard.events.user.compromised").await,
        "booking MUST NOT be able to forge a user.compromised event"
    );
}

#[tokio::test]
async fn consumer_only_service_cannot_publish_any_event() {
    let Some((url, pass)) = authz_env() else {
        eprintln!("SKIP: NATS_AUTHZ_URL/NATS_AUTHZ_PASSWORD not set (no auth broker)");
        return;
    };
    // notification is a durable CONSUMER over `pguard.events.>` — it has JS control perms (so it
    // can bind its consumer) but NO data-publish permission at all.
    let js = jetstream_as(&url, "notification", &pass).await;
    ensure_stream(&js).await; // JS control allowed

    assert!(
        publish_denied(&js, "pguard.events.booking.job_accepted").await,
        "consumer-only notification MUST NOT publish any event subject"
    );
    assert!(
        publish_denied(&js, "pguard.events.notification.anything").await,
        "there is no notification.* context — and notification publishes nothing anyway"
    );
}

#[tokio::test]
async fn identity_is_consumer_only_cannot_forge_user_events() {
    let Some((url, pass)) = authz_env() else {
        eprintln!("SKIP: NATS_AUTHZ_URL/NATS_AUTHZ_PASSWORD not set (no auth broker)");
        return;
    };
    // identity CONSUMES user.* (durable) but publishes nothing over NATS in production
    // (revocation is DB/Redis). It must NOT be able to forge a `user.approved` (login bypass)
    // or `user.compromised` (mass-revoke), even though it holds EVENT_SIGNING_SECRET.
    let js = jetstream_as(&url, "identity", &pass).await;
    ensure_stream(&js).await; // JS control allowed (it binds durable consumers)

    assert!(
        publish_denied(&js, "pguard.events.user.approved").await,
        "identity MUST NOT forge user.approved (login bypass)"
    );
    assert!(
        publish_denied(&js, "pguard.events.user.compromised").await,
        "identity MUST NOT forge user.compromised (mass-revoke)"
    );
}

#[tokio::test]
async fn profile_owns_the_user_context_for_the_approval_loop() {
    let Some((url, pass)) = authz_env() else {
        eprintln!("SKIP: NATS_AUTHZ_URL/NATS_AUTHZ_PASSWORD not set (no auth broker)");
        return;
    };
    // profile is the producer of `user.approved` (approval→login loop) — its data publish is
    // scoped to `pguard.events.user.>`, and a foreign context is denied.
    let js = jetstream_as(&url, "profile", &pass).await;
    ensure_stream(&js).await;

    assert!(
        publish_allowed(&js, "pguard.events.user.approved").await,
        "profile MUST publish user.approved"
    );
    assert!(
        publish_denied(&js, "pguard.events.booking.completed").await,
        "profile MUST NOT forge a booking event"
    );
}

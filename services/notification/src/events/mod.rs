//! Event layer — the NATS JetStream consumer that turns `pguard.events.*` into
//! notifications. This is the heart of Phase 1: booking et al. no longer write the
//! notification schema; they emit events and this subscribes.

use futures::StreamExt;
use serde_json::Value;
use tracing::Instrument;
use uuid::Uuid;

use shared::error::AppError;
use shared_events::{topics, EventEnvelope};

use crate::domain;
use crate::fcm::PushMessage;
use crate::repo::{self, Processed};
use crate::state::AppState;

/// JetStream stream + durable consumer names.
const STREAM: &str = "PGUARD_EVENTS";
const SUBJECTS: &str = "pguard.events.>";
const DURABLE: &str = "notification";

/// Connect to NATS JetStream and run the consume loop until the stream ends or errors.
/// Spawned as a background task by `main`; resilient (logs and returns on fatal error).
pub async fn run_consumer(state: AppState, nats_url: &str) -> Result<(), AppError> {
    let client = shared_events::connect(nats_url)
        .await
        .map_err(|e| AppError::Internal(format!("NATS connect failed: {e}")))?;
    let jetstream = async_nats::jetstream::new(client);

    let stream = jetstream
        .get_or_create_stream(async_nats::jetstream::stream::Config {
            name: STREAM.to_string(),
            subjects: vec![SUBJECTS.to_string()],
            ..Default::default()
        })
        .await
        .map_err(|e| AppError::Internal(format!("ensure stream failed: {e}")))?;

    let consumer = stream
        .get_or_create_consumer(
            DURABLE,
            async_nats::jetstream::consumer::pull::Config {
                durable_name: Some(DURABLE.to_string()),
                ..Default::default()
            },
        )
        .await
        .map_err(|e| AppError::Internal(format!("ensure consumer failed: {e}")))?;

    let mut messages = consumer
        .messages()
        .await
        .map_err(|e| AppError::Internal(format!("consume failed: {e}")))?;

    tracing::info!(
        stream = STREAM,
        subjects = SUBJECTS,
        "notification consumer started"
    );

    while let Some(item) = messages.next().await {
        let message = match item {
            Ok(m) => m,
            Err(e) => {
                tracing::warn!("NATS message error: {e}");
                continue;
            }
        };

        // Report this durable consumer's backlog (lag) to Prometheus.
        if let Ok(info) = message.info() {
            observability::record_consumer_lag(DURABLE, info.pending);
        }

        // Verify the HMAC signature BEFORE any dedupe/business logic — a forged/unsigned event
        // is dropped (acked so it can't redeliver), counted, and NEVER applied. Fail-closed.
        if !shared_events::verify_message(message.headers.as_ref(), message.payload.as_ref()) {
            observability::record_rejected_event(DURABLE);
            tracing::warn!("dropping event with missing/invalid signature (forged?)");
            let _ = message.ack().await;
            continue;
        }

        match handle_event(&state, message.payload.as_ref()).await {
            Ok(()) => {
                if let Err(e) = message.ack().await {
                    tracing::warn!("ack failed: {e}");
                }
            }
            Err(e) => {
                // Do not ack → JetStream will redeliver; the idempotency ledger makes
                // reprocessing safe.
                tracing::error!("event handling failed (will redeliver): {e}");
            }
        }
    }

    Ok(())
}

/// Parse one envelope, then process it inside a span carrying the event identity +
/// `correlation_id`. The span is REPARENTED on the producer's `traceparent` (carried in the
/// envelope) so a booking→NATS→notification flow is one distributed trace in Tempo (C5.1).
async fn handle_event(state: &AppState, payload: &[u8]) -> Result<(), AppError> {
    let envelope: EventEnvelope<Value> = serde_json::from_slice(payload)
        .map_err(|e| AppError::BadRequest(format!("invalid event envelope: {e}")))?;

    let span = tracing::info_span!(
        "notification.handle_event",
        event_type = %envelope.event_type,
        event_id = %envelope.event_id,
        correlation_id = %envelope.correlation_id,
    );
    if let Some(tp) = envelope.traceparent.as_deref() {
        observability::set_parent_from_traceparent(&span, tp);
    }
    process(state, envelope).instrument(span).await
}

/// Dedupe + persist atomically, then push (best-effort). Runs inside the event span.
async fn process(state: &AppState, envelope: EventEnvelope<Value>) -> Result<(), AppError> {
    // A new booking is a FAN-OUT (one event → every online guard), not the single-recipient
    // `plan_for_event` path. Route it to its own dispatcher (presence consult + per-guard claim).
    if envelope.event_type == topics::BOOKING_REQUESTED {
        return fan_out_dispatch(state, &envelope).await;
    }

    // A successful PRE-PAY notifies BOTH parties (the customer "ชำระเงินสำเร็จ" + the guard
    // "ลูกค้าชำระเงินแล้ว"), so it is DUAL-recipient, not the single-recipient `plan_for_event`
    // path. Route it to its own dispatcher (per-(event, recipient) idempotent claims).
    if envelope.event_type == topics::PAYMENT_COMPLETED {
        return payment_completed_dispatch(state, &envelope).await;
    }

    let plan = domain::plan_for_event(&envelope.event_type, &envelope.payload);
    // Maintain the hourly check-in reminder ledger (N3a) from the booking lifecycle events that
    // already flow here — atomically with the event_id claim (so a redelivery is a no-op, never a
    // double reset/wipe). Independent of `plan`: `booking.progress_reported` notifies no one yet
    // carries a ledger op (record the check-in), `booking.arrived` carries both.
    let ledger_op = domain::checkin::ledger_op_for_event(&envelope.event_type, &envelope.payload);

    match repo::process_event(
        &state.db,
        envelope.event_id,
        &envelope.event_type,
        plan.as_ref(),
        ledger_op.as_ref(),
    )
    .await?
    {
        Processed::Created(recipient) => {
            if let Some(plan) = plan {
                let tokens = repo::user_tokens(&state.db, recipient).await?;
                state
                    .pusher
                    .push(&PushMessage {
                        tokens,
                        title: plan.title,
                        body: plan.body,
                        data: plan.data,
                    })
                    .await?;
            }
        }
        Processed::Ignored => tracing::debug!("no notification mapping; marked processed"),
        Processed::Duplicate => tracing::debug!("duplicate event; skipped"),
    }
    Ok(())
}

/// Dispatch path for `booking.requested`. TWO routings, decided by `target_guard_id` on the event
/// (always present per the producer — `Some` = DIRECTED OFFER to one guard, `null`/absent = OPEN
/// first-come):
///   * DIRECTED (C3): push the "new job hired to you" alert to ONLY that guard, BYPASSING presence /
///     online gating entirely — a directed-but-offline guard must still be alerted, and no OTHER
///     online guard may receive a directed offer (a broadcast would defeat the directed hire).
///   * OPEN: consult presence for the set of ONLINE guards and fan the "new job nearby" alert to
///     each. Both routings write a `notification_logs` row + an FCM data push `{ type: "new_job",
///     booking_id }` and are IDEMPOTENT per-(booking, guard) via the `dispatch_recipients` claim, so
///     a JetStream redelivery re-claims nothing and double-pushes no one.
///
/// Resilience (OPEN only): if presence is UNREACHABLE we log + skip the fan-out and return `Ok(())`
/// so the message is ACKED — never crash the consumer / nack-storm on a presence hiccup. NOTE: this
/// means the proactive PUSH for that booking is DROPPED, not retried — the per-(event,guard) ledger
/// only fills in guards across redeliveries when the message NACKs, which this fail-soft path does
/// not. That is acceptable: the booking stays discoverable via the pull-based `GET /bookings/open`
/// (the guard app also refetches on resume / go-online), so the guard still finds the job — only the
/// push alert is missed. The DIRECTED path does not consult presence, so it has no such failure mode.
/// Per-guard push failures are best-effort in both routings (logged, not fatal): the in-app log row
/// is already committed, and one bad device token must not abort the whole dispatch.
async fn fan_out_dispatch(
    state: &AppState,
    envelope: &EventEnvelope<Value>,
) -> Result<(), AppError> {
    let Some(booking_id) = uuid_field(&envelope.payload, "booking_id") else {
        // No booking_id to dispatch for → nothing to do. Ack (no recipient is routable, so a
        // redelivery would behave identically — not a transient error).
        tracing::warn!("booking.requested missing booking_id; skipping dispatch");
        return Ok(());
    };

    // Resolve the recipient set + copy variant. DIRECTED short-circuits presence entirely; OPEN
    // consults presence (fail-soft) and caps the broadcast.
    let (targets, directed) = if let Some(target_guard) =
        uuid_field(&envelope.payload, "target_guard_id")
    {
        // DIRECTED OFFER: exactly one guard, regardless of online status.
        (vec![target_guard], true)
    } else {
        // OPEN first-come: consult presence (service-JWT'd). FAIL-SOFT: on error, log + skip the
        // fan-out (ack), never nack-storm. Geo radius is intentionally NOT applied — broadcasting to
        // ALL online guards matches the radius-less open-jobs query (geo-filtering by the event's
        // lat/lng is a follow-up).
        let online = match state.presence_client.online_guard_ids().await {
            Ok(ids) => ids,
            Err(e) => {
                tracing::warn!(booking = %booking_id, "presence unreachable; skipping new-job fan-out: {e}");
                return Ok(());
            }
        };

        if online.is_empty() {
            tracing::info!(booking = %booking_id, "no online guards; new-job dispatch is a no-op");
            return Ok(());
        }

        // Bound the broadcast: with no geo radius this fans out to EVERY online guard, so cap the
        // batch (geo-filtering by the event's lat/lng is the real fix — a follow-up). Beyond the
        // cap, log + truncate rather than run an unbounded per-guard DB+FCM loop.
        const MAX_FANOUT_GUARDS: usize = 1000;
        let online: Vec<Uuid> = if online.len() > MAX_FANOUT_GUARDS {
            tracing::warn!(
                booking = %booking_id, total = online.len(), cap = MAX_FANOUT_GUARDS,
                "online-guard fan-out exceeds cap; truncating (add geo-filtering)"
            );
            online.into_iter().take(MAX_FANOUT_GUARDS).collect()
        } else {
            online
        };
        (online, false)
    };

    let (pushed, claim_failed) = dispatch_to_guards(
        targets,
        booking_id,
        directed,
        // Per-guard atomic claim + log (DB). `false` → already dispatched to this guard for this
        // event (idempotent). Returns `Err` only on a real DB fault.
        |guard_id, plan: domain::NotificationPlan| async move {
            repo::claim_dispatch_recipient(
                &state.db,
                envelope.event_id,
                booking_id,
                guard_id,
                &plan,
            )
            .await
        },
        // Per-guard push (FCM). Best-effort: a push failure must not fail the batch.
        |guard_id, plan: domain::NotificationPlan| async move {
            let tokens = repo::user_tokens(&state.db, guard_id)
                .await
                .unwrap_or_default();
            state
                .pusher
                .push(&PushMessage {
                    tokens,
                    title: plan.title,
                    body: plan.body,
                    data: plan.data,
                })
                .await
        },
    )
    .await;
    tracing::info!(booking = %booking_id, dispatched = pushed, directed, "new-job dispatch complete");
    if claim_failed {
        // NACK so JetStream redelivers and the unclaimed guards get filled in; the per-(event,guard)
        // ledger dedupes the guards already dispatched, so redelivery only covers the gaps.
        return Err(AppError::Internal(
            "new-job dispatch: a guard claim failed — redeliver".to_string(),
        ));
    }
    Ok(())
}

/// DUAL-recipient path for `payment.completed` (PRE-PAY): notify the customer ("ชำระเงินสำเร็จ")
/// AND the guard ("ลูกค้าชำระเงินแล้ว"). Each recipient is claimed with a per-(event, recipient)
/// idempotent claim (same primitive as the fan-out), so a JetStream redelivery double-pushes
/// neither party. A push failure is best-effort (logged, not fatal): the in-app log row is already
/// committed and one bad device token must not abort the other recipient.
///
/// Resilience: a missing `booking_id`/`customer_id` (unroutable) is ACKED — a redelivery would
/// behave identically (not a transient error). Per-recipient DB-claim faults log + continue.
async fn payment_completed_dispatch(
    state: &AppState,
    envelope: &EventEnvelope<Value>,
) -> Result<(), AppError> {
    let Some(booking_id) = uuid_field(&envelope.payload, "booking_id") else {
        tracing::warn!("payment.completed missing booking_id; skipping dispatch");
        return Ok(());
    };
    let plans = domain::payment_completed_plans(&envelope.payload);
    if plans.is_empty() {
        tracing::warn!("payment.completed missing customer_id; nothing to dispatch");
        return Ok(());
    }

    let mut claim_failed = false;
    for plan in plans {
        let recipient = plan.recipient_id;
        // Per-(event, recipient) claim → idempotent across redeliveries.
        let won = match repo::claim_dispatch_recipient(
            &state.db,
            envelope.event_id,
            booking_id,
            recipient,
            &plan,
        )
        .await
        {
            Ok(won) => won,
            Err(e) => {
                // A transient claim error must NOT be swallowed with an ack — the recipient (e.g. the
                // guard whose payment push un-gates "Go en route") would lose the notification
                // permanently. Mark the batch failed so it NACKs + redelivers; the per-(event,
                // recipient) ledger keeps already-claimed recipients idempotent (deep-review).
                tracing::warn!(recipient = %recipient, booking = %booking_id, "payment.completed claim failed: {e}");
                claim_failed = true;
                continue;
            }
        };
        if !won {
            continue; // already notified this recipient for this event (idempotent)
        }
        let tokens = repo::user_tokens(&state.db, recipient)
            .await
            .unwrap_or_default();
        if let Err(e) = state
            .pusher
            .push(&PushMessage {
                tokens,
                title: plan.title,
                body: plan.body,
                data: plan.data,
            })
            .await
        {
            tracing::warn!(recipient = %recipient, booking = %booking_id, "payment.completed push failed: {e}");
        }
    }
    if claim_failed {
        // NACK → JetStream redelivers; the ledger dedupes the recipients that already succeeded.
        return Err(AppError::Internal(
            "payment.completed dispatch: a recipient claim failed — redeliver".to_string(),
        ));
    }
    Ok(())
}

/// Pure-ish dispatch core: for each target guard, build the dispatch plan, CLAIM it (per-(event,
/// guard) idempotency), and on a won claim PUSH it. Returns the number of guards newly dispatched.
/// `directed` selects the copy variant — the DIRECTED-offer "hired to you" plan vs the OPEN
/// "new job nearby" broadcast plan; the push `data` shape is identical either way. Decoupled from
/// `AppState` via the two closures so the consumer's dispatch decision (dedupe + best-effort push,
/// one bad guard never aborts the batch) is unit-testable with in-memory doubles — the same
/// philosophy as the `SeenSet`-backed `consume` test double for the single-recipient path.
async fn dispatch_to_guards<C, CF, P, PF>(
    online: Vec<Uuid>,
    booking_id: Uuid,
    directed: bool,
    claim: C,
    push: P,
) -> (usize, bool)
where
    C: Fn(Uuid, domain::NotificationPlan) -> CF,
    CF: std::future::Future<Output = Result<bool, AppError>>,
    P: Fn(Uuid, domain::NotificationPlan) -> PF,
    PF: std::future::Future<Output = Result<(), AppError>>,
{
    let mut pushed = 0usize;
    let mut claim_failed = false;
    for guard_id in online {
        let plan = if directed {
            domain::directed_dispatch_plan_for_guard(guard_id, booking_id)
        } else {
            domain::dispatch_plan_for_guard(guard_id, booking_id)
        };
        let won = match claim(guard_id, plan.clone()).await {
            Ok(won) => won,
            Err(e) => {
                // A DB error claiming ONE guard must not abort the fan-out (the other guards still
                // get their push); log, continue, but REMEMBER the failure so the caller NACKs and a
                // redelivery actually fills the unclaimed guards — the ledger dedupes the rest
                // (deep-review: the old "redelivery fills in later" never happened, the batch acked).
                tracing::warn!(guard = %guard_id, booking = %booking_id, "dispatch claim failed: {e}");
                claim_failed = true;
                continue;
            }
        };
        if !won {
            continue; // already dispatched to this guard for this event (idempotent)
        }
        if let Err(e) = push(guard_id, plan).await {
            // Best-effort: the in-app log row is committed; a push failure must not fail the batch.
            tracing::warn!(guard = %guard_id, booking = %booking_id, "new-job push failed: {e}");
        }
        pushed += 1;
    }
    (pushed, claim_failed)
}

/// Parse a UUID string field out of an event payload (consumer-side helper, mirrors the pure
/// `mapping::uuid_field`).
fn uuid_field(payload: &Value, key: &str) -> Option<Uuid> {
    payload
        .get(key)?
        .as_str()
        .and_then(|s| Uuid::parse_str(s).ok())
}

#[cfg(test)]
mod tests {
    use super::dispatch_to_guards;
    use crate::domain::idempotency::SeenSet;
    use crate::domain::plan_for_event;
    use crate::presence_client::OnlineGuardsReader;
    use serde_json::{json, Value};
    use shared::error::AppError;
    use shared_events::topics;
    use std::collections::{HashMap, HashSet};
    use std::sync::Mutex;
    use uuid::Uuid;

    /// Models the consumer's per-event decision (claim THEN map) — the same two steps
    /// `repo::process_event` performs atomically against `processed_events` +
    /// `notification_logs`. Returns the notification title, or `None` for a duplicate or
    /// an unmapped event.
    fn consume(
        seen: &mut SeenSet,
        event_type: &str,
        event_id: Uuid,
        payload: &Value,
    ) -> Option<String> {
        if !seen.claim(event_id) {
            return None; // duplicate (at-least-once redelivery) → skip
        }
        plan_for_event(event_type, payload).map(|p| p.title)
    }

    /// Integration-style consumer dedupe test, using the in-memory claim as a test
    /// double for the DB/NATS at-least-once path.
    #[test]
    fn redelivery_of_same_event_is_deduped() {
        let mut seen = SeenSet::new();
        let event_id = Uuid::new_v4();
        let payload = json!({ "customer_id": Uuid::new_v4(), "booking_id": Uuid::new_v4() });

        assert!(
            consume(&mut seen, topics::BOOKING_JOB_ACCEPTED, event_id, &payload).is_some(),
            "first delivery notifies"
        );
        assert!(
            consume(&mut seen, topics::BOOKING_JOB_ACCEPTED, event_id, &payload).is_none(),
            "redelivery of the same event_id is deduped"
        );
    }

    #[test]
    fn distinct_events_each_notify() {
        let mut seen = SeenSet::new();
        let payload = json!({ "customer_id": Uuid::new_v4(), "guard_id": Uuid::new_v4(), "booking_id": Uuid::new_v4() });
        assert!(consume(
            &mut seen,
            topics::BOOKING_JOB_ACCEPTED,
            Uuid::new_v4(),
            &payload
        )
        .is_some());
        assert!(consume(&mut seen, topics::BOOKING_ARRIVED, Uuid::new_v4(), &payload).is_some());
    }

    // ----- FAN-OUT (booking.requested → all online guards) -----

    /// Stub presence reader: returns a fixed online set, or simulates "presence unreachable".
    struct StubPresence {
        guards: Vec<Uuid>,
        reachable: bool,
    }

    #[async_trait::async_trait]
    impl OnlineGuardsReader for StubPresence {
        async fn online_guard_ids(&self) -> Result<Vec<Uuid>, AppError> {
            if self.reachable {
                Ok(self.guards.clone())
            } else {
                Err(AppError::Internal("presence down".to_string()))
            }
        }
    }

    /// In-memory test double for the DB `dispatch_recipients` claim (PK on (event_id, recipient))
    /// plus the FCM pusher: records which guards were pushed and the data each got. The claim is the
    /// `HashSet::insert` semantics of `INSERT ... ON CONFLICT DO NOTHING` — exactly like `SeenSet`
    /// models `processed_events` for the single-recipient path.
    #[derive(Default)]
    struct Fanout {
        claimed: Mutex<HashSet<(Uuid, Uuid)>>, // (event_id, guard_id) already dispatched
        pushed: Mutex<Vec<(Uuid, Value)>>,     // (guard_id, push data) actually delivered
    }

    /// Run the real fan-out engine against the doubles for one (event, booking) delivery. Mirrors
    /// `fan_out_dispatch`'s presence-consult → per-guard claim → push, minus the live AppState.
    async fn deliver(
        fanout: &Fanout,
        presence: &StubPresence,
        event_id: Uuid,
        booking_id: Uuid,
    ) -> usize {
        // presence-consult with the same FAIL-SOFT contract as fan_out_dispatch.
        let online = match presence.online_guard_ids().await {
            Ok(ids) => ids,
            Err(_) => return 0, // presence unreachable → skip fan-out, no crash, no push
        };
        dispatch_to_guards(
            online,
            booking_id,
            false, // OPEN broadcast copy
            |guard_id, _plan| async move {
                // Won the claim iff this (event, guard) was not already recorded.
                Ok(fanout.claimed.lock().unwrap().insert((event_id, guard_id)))
            },
            |guard_id, plan| async move {
                fanout.pushed.lock().unwrap().push((guard_id, plan.data));
                Ok(())
            },
        )
        .await
        .0
    }

    #[tokio::test]
    async fn booking_requested_pushes_new_job_to_each_online_guard() {
        let g1 = Uuid::new_v4();
        let g2 = Uuid::new_v4();
        let g3 = Uuid::new_v4();
        let presence = StubPresence {
            guards: vec![g1, g2, g3],
            reachable: true,
        };
        let fanout = Fanout::default();
        let booking = Uuid::new_v4();

        let pushed = deliver(&fanout, &presence, Uuid::new_v4(), booking).await;
        assert_eq!(pushed, 3, "every online guard is dispatched");

        // Each guard got exactly one new_job push carrying the booking_id.
        let by_guard: HashMap<Uuid, Value> =
            fanout.pushed.lock().unwrap().iter().cloned().collect();
        for g in [g1, g2, g3] {
            let data = by_guard.get(&g).expect("guard must be pushed");
            assert_eq!(data["type"], "new_job");
            assert_eq!(data["booking_id"], json!(booking.to_string()));
            assert_eq!(data["target_role"], "guard");
        }
    }

    #[tokio::test]
    async fn presence_down_skips_fan_out_without_crashing() {
        let presence = StubPresence {
            guards: vec![Uuid::new_v4(), Uuid::new_v4()],
            reachable: false, // presence unreachable
        };
        let fanout = Fanout::default();

        // Must NOT panic; returns 0 dispatched and pushes nobody (the message would still be acked).
        let pushed = deliver(&fanout, &presence, Uuid::new_v4(), Uuid::new_v4()).await;
        assert_eq!(pushed, 0, "presence-down → no fan-out");
        assert!(
            fanout.pushed.lock().unwrap().is_empty(),
            "no push when presence is unreachable"
        );
    }

    #[tokio::test]
    async fn redelivery_does_not_double_push_any_guard() {
        let g1 = Uuid::new_v4();
        let g2 = Uuid::new_v4();
        let presence = StubPresence {
            guards: vec![g1, g2],
            reachable: true,
        };
        let fanout = Fanout::default();
        let event_id = Uuid::new_v4(); // SAME event_id on redelivery
        let booking = Uuid::new_v4();

        let first = deliver(&fanout, &presence, event_id, booking).await;
        assert_eq!(first, 2, "first delivery dispatches both guards");

        // JetStream redelivers the SAME event_id → every (event, guard) is already claimed → 0 new.
        let second = deliver(&fanout, &presence, event_id, booking).await;
        assert_eq!(second, 0, "redelivery dispatches no one (idempotent)");

        // Exactly two pushes total despite two deliveries — no guard double-notified.
        assert_eq!(
            fanout.pushed.lock().unwrap().len(),
            2,
            "each guard pushed exactly once across redelivery"
        );
    }

    #[tokio::test]
    async fn directed_offer_pushes_only_the_target_guard_with_directed_copy() {
        // DIRECTED path (C3): the dispatch engine is handed exactly ONE guard (the caller resolved
        // `target_guard_id` and bypassed presence), `directed = true`. It must push that guard once
        // with the DIRECTED copy — never any other guard, and never gated on online status.
        let target = Uuid::new_v4();
        let booking = Uuid::new_v4();
        let event_id = Uuid::new_v4();
        // Capture (guard, title, data) so we can assert the routing AND the directed copy. Bind
        // references so the per-guard `async move` closures capture a `&Mutex` (Copy), keeping them
        // `Fn` — the same borrowing shape as the `deliver` helper's `&Fanout`.
        let pushed: Mutex<Vec<(Uuid, String, Value)>> = Mutex::new(Vec::new());
        let claimed: Mutex<HashSet<(Uuid, Uuid)>> = Mutex::new(HashSet::new());
        let pushed_ref = &pushed;
        let claimed_ref = &claimed;

        let (count, claim_failed) = dispatch_to_guards(
            vec![target],
            booking,
            true, // DIRECTED
            |guard_id, _plan| async move {
                Ok(claimed_ref.lock().unwrap().insert((event_id, guard_id)))
            },
            |guard_id, plan| async move {
                pushed_ref
                    .lock()
                    .unwrap()
                    .push((guard_id, plan.title, plan.data));
                Ok(())
            },
        )
        .await;

        assert_eq!(count, 1, "exactly the one directed guard is dispatched");
        assert!(!claim_failed);
        let pushes = pushed.lock().unwrap();
        assert_eq!(pushes.len(), 1, "only the target guard is pushed");
        let (g, title, data) = &pushes[0];
        assert_eq!(*g, target, "the DIRECTED guard is the recipient");
        assert_eq!(title, "มีงานจ้างใหม่สำหรับคุณ", "directed copy is used");
        // Same push `data` shape as a broadcast so the mobile deep-links identically.
        assert_eq!(data["type"], "new_job");
        assert_eq!(data["booking_id"], json!(booking.to_string()));
        assert_eq!(data["target_role"], "guard");
    }
}

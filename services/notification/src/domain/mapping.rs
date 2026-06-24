//! PURE event → notification mapping. No DB/HTTP imports.
//!
//! Given an event topic + its JSON payload, decide **who** to notify and with **what**
//! copy. This replaces v1's 10 `spawn_notification` call sites in booking (each a direct
//! cross-schema INSERT) — now booking just emits an event and this maps it. Returns
//! `None` when an event produces no user notification (e.g. `user.compromised`, or a
//! payload missing its recipient).

use serde_json::Value;
use uuid::Uuid;

use shared_events::topics;

use crate::models::NotificationType;

/// What the consumer should persist + push for one event. Pure data.
#[derive(Debug, Clone, PartialEq)]
pub struct NotificationPlan {
    pub recipient_id: Uuid,
    pub notification_type: NotificationType,
    pub title: String,
    pub body: String,
    /// Stored as the notification payload. Carries `target_role` (when known) so the
    /// read API can filter by guard/customer, mirroring v1 `payload->>'target_role'`.
    pub data: Value,
}

/// Parse a UUID string field out of an event payload.
fn uuid_field(payload: &Value, key: &str) -> Option<Uuid> {
    payload
        .get(key)?
        .as_str()
        .and_then(|s| Uuid::parse_str(s).ok())
}

/// Build the stored payload: target_role (for filtering) + a few reference ids carried
/// through from the source event + the originating event_type (for client routing).
fn build_data(target_role: Option<&str>, event_type: &str, payload: &Value) -> Value {
    let mut m = serde_json::Map::new();
    if let Some(role) = target_role {
        m.insert("target_role".to_string(), Value::String(role.to_string()));
    }
    m.insert(
        "event_type".to_string(),
        Value::String(event_type.to_string()),
    );
    for key in ["booking_id", "conversation_id", "payment_id", "rating_id"] {
        if let Some(v) = payload.get(key) {
            m.insert(key.to_string(), v.clone());
        }
    }
    Value::Object(m)
}

/// Build the per-guard dispatch plan for a `booking.requested` fan-out: one online guard gets the
/// "new job nearby" alert. PURE (no DB/HTTP) so the fan-out copy + push `data` shape is
/// unit-testable. This is the FAN-OUT counterpart to [`plan_for_event`] (which maps a single
/// recipient): the consumer calls this once per online guard, mirroring the `incoming_call` push
/// shape — `data` carries `type: "new_job"` + the `booking_id` so the mobile can deep-link to the
/// open job. `target_role: "guard"` so the read API filters it to guards.
//
// NOTE: broadcasting to ALL online guards (no geo radius) is intentional for now — it matches the
// radius-less open-jobs query. Geo-filtering by the booking's lat/lng (carried on the event) is a
// documented follow-up; the consumer would rank/filter the online set before calling this.
pub fn dispatch_plan_for_guard(guard_id: Uuid, booking_id: Uuid) -> NotificationPlan {
    let mut data = serde_json::Map::new();
    data.insert("type".to_string(), Value::String("new_job".to_string()));
    data.insert(
        "target_role".to_string(),
        Value::String("guard".to_string()),
    );
    data.insert(
        "event_type".to_string(),
        Value::String(topics::BOOKING_REQUESTED.to_string()),
    );
    data.insert(
        "booking_id".to_string(),
        Value::String(booking_id.to_string()),
    );
    NotificationPlan {
        recipient_id: guard_id,
        notification_type: NotificationType::BookingCreated,
        title: "งานใหม่ใกล้คุณ".to_string(),
        body: "New job nearby".to_string(),
        data: Value::Object(data),
    }
}

/// Build the DUAL-recipient plans for `payment.completed` (PRE-PAY): the customer is told the
/// payment succeeded ("ชำระเงินสำเร็จ") and the guard is told the customer paid
/// ("ลูกค้าชำระเงินแล้ว"). PURE (no DB/HTTP) so the copy + per-recipient `data` shape is
/// unit-testable, mirroring [`dispatch_plan_for_guard`]. The consumer dispatches each plan with a
/// per-(event, recipient) idempotent claim. The guard plan is omitted when the event carries no
/// `guard_id` (defensive — a pre-paid booking always has an accepted guard). Returns `[]` when the
/// `customer_id` is missing (nothing routable).
pub fn payment_completed_plans(payload: &Value) -> Vec<NotificationPlan> {
    let Some(customer_id) = uuid_field(payload, "customer_id") else {
        return Vec::new();
    };
    let mut plans = vec![NotificationPlan {
        recipient_id: customer_id,
        notification_type: NotificationType::System,
        title: "ชำระเงินสำเร็จ".to_string(),
        body: "ชำระเงินสำเร็จ".to_string(),
        data: build_data(Some("customer"), topics::PAYMENT_COMPLETED, payload),
    }];
    if let Some(guard_id) = uuid_field(payload, "guard_id") {
        plans.push(NotificationPlan {
            recipient_id: guard_id,
            notification_type: NotificationType::System,
            title: "ลูกค้าชำระเงินแล้ว".to_string(),
            body: "ลูกค้าชำระเงินแล้ว".to_string(),
            data: build_data(Some("guard"), topics::PAYMENT_COMPLETED, payload),
        });
    }
    plans
}

/// Map an event to a [`NotificationPlan`], or `None` if it should not notify anyone.
pub fn plan_for_event(event_type: &str, payload: &Value) -> Option<NotificationPlan> {
    let make = |recipient: Uuid,
                role: Option<&'static str>,
                notification_type: NotificationType,
                title: &str,
                body: &str| NotificationPlan {
        recipient_id: recipient,
        notification_type,
        title: title.to_string(),
        body: body.to_string(),
        data: build_data(role, event_type, payload),
    };

    match event_type {
        topics::BOOKING_JOB_ACCEPTED => Some(make(
            uuid_field(payload, "customer_id")?,
            Some("customer"),
            NotificationType::GuardAssigned,
            "เจ้าหน้าที่ตอบรับแล้ว",
            "เจ้าหน้าที่ตอบรับงานของคุณแล้ว",
        )),
        topics::BOOKING_DECLINED => Some(make(
            uuid_field(payload, "customer_id")?,
            Some("customer"),
            NotificationType::System,
            "เจ้าหน้าที่ปฏิเสธงาน",
            "กำลังค้นหาเจ้าหน้าที่ใหม่ให้คุณ",
        )),
        topics::BOOKING_GUARD_EN_ROUTE => Some(make(
            uuid_field(payload, "customer_id")?,
            Some("customer"),
            NotificationType::GuardEnRoute,
            "เจ้าหน้าที่กำลังเดินทาง",
            "เจ้าหน้าที่กำลังเดินทางไปยังจุดนัดหมาย",
        )),
        topics::BOOKING_ARRIVED => Some(make(
            uuid_field(payload, "customer_id")?,
            Some("customer"),
            NotificationType::GuardArrived,
            "เจ้าหน้าที่ถึงแล้ว",
            "เจ้าหน้าที่มาถึงจุดนัดหมายแล้ว",
        )),
        topics::BOOKING_COMPLETED => Some(make(
            uuid_field(payload, "guard_id")?,
            Some("guard"),
            NotificationType::BookingCompleted,
            "งานเสร็จสมบูรณ์",
            "งานของคุณเสร็จสมบูรณ์แล้ว",
        )),
        topics::BOOKING_CANCELLED => {
            // Prefer the assigned guard; fall back to the customer if no guard yet.
            if let Some(guard_id) = uuid_field(payload, "guard_id") {
                Some(make(
                    guard_id,
                    Some("guard"),
                    NotificationType::BookingCancelled,
                    "งานถูกยกเลิก",
                    "ลูกค้ายกเลิกงานแล้ว",
                ))
            } else {
                Some(make(
                    uuid_field(payload, "customer_id")?,
                    Some("customer"),
                    NotificationType::BookingCancelled,
                    "งานถูกยกเลิก",
                    "งานของคุณถูกยกเลิกแล้ว",
                ))
            }
        }
        // payment.completed is DUAL-recipient (PRE-PAY: tell the customer AND the guard), so it is
        // NOT a single-recipient `plan_for_event` mapping — the consumer routes it to
        // `payment_completed_plans` (per-recipient idempotent claims, like the fan-out path).
        topics::PAYMENT_COMPLETED => None,
        topics::RATING_SUBMITTED => Some(make(
            uuid_field(payload, "guard_id")?,
            Some("guard"),
            NotificationType::System,
            "มีรีวิวใหม่",
            "คุณได้รับคะแนนรีวิวใหม่",
        )),
        topics::CHAT_MESSAGE_SENT => Some(make(
            uuid_field(payload, "recipient_id")?,
            None,
            NotificationType::ChatMessage,
            "ข้อความใหม่",
            "คุณมีข้อความใหม่",
        )),
        // Ring the CALLEE on an incoming call. The data carries everything the mobile needs to
        // open the incoming-call screen and answer: `type=incoming_call` + the call_id + call_type
        // + caller_id. The field names mirror the AsyncAPI `calling.*` envelope EXACTLY: the
        // producer (calling `repo::enqueue_event`) emits `call_id` (per `EnvelopeOf_CallRef`), NOT
        // `id` — reading `id` here silently dropped the call_id from the push so the callee could
        // never open the call screen. The OTHER calling.* events (accepted/rejected/ended) are
        // still in-call signaling, not a push — left unmapped below.
        topics::CALLING_INITIATED => {
            let mut data = build_data(None, event_type, payload);
            if let Value::Object(ref mut m) = data {
                m.insert(
                    "type".to_string(),
                    Value::String("incoming_call".to_string()),
                );
                for k in ["call_id", "call_type", "caller_id"] {
                    if let Some(v) = payload.get(k) {
                        m.insert(k.to_string(), v.clone());
                    }
                }
            }
            Some(NotificationPlan {
                recipient_id: uuid_field(payload, "callee_id")?,
                notification_type: NotificationType::System,
                title: "สายเรียกเข้า".to_string(),
                body: "คุณมีสายเรียกเข้า แตะเพื่อรับสาย".to_string(),
                data,
            })
        }
        // No user notification: force-revoke is identity's concern; the remaining calling.* events
        // and any unmapped/under-specified topic are intentionally ignored (claimed, not pushed).
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn job_accepted_notifies_customer() {
        let customer = Uuid::new_v4();
        let payload = json!({ "customer_id": customer, "guard_id": Uuid::new_v4(), "booking_id": Uuid::new_v4() });
        let plan = plan_for_event(topics::BOOKING_JOB_ACCEPTED, &payload).expect("should map");
        assert_eq!(plan.recipient_id, customer);
        assert_eq!(plan.notification_type, NotificationType::GuardAssigned);
        assert_eq!(plan.data["target_role"], "customer");
        assert_eq!(plan.data["booking_id"], json!(payload["booking_id"]));
    }

    #[test]
    fn completed_notifies_guard() {
        let guard = Uuid::new_v4();
        let payload = json!({ "customer_id": Uuid::new_v4(), "guard_id": guard, "booking_id": Uuid::new_v4() });
        let plan = plan_for_event(topics::BOOKING_COMPLETED, &payload).expect("should map");
        assert_eq!(plan.recipient_id, guard);
        assert_eq!(plan.notification_type, NotificationType::BookingCompleted);
        assert_eq!(plan.data["target_role"], "guard");
    }

    #[test]
    fn rating_notifies_guard() {
        let guard = Uuid::new_v4();
        let rate = json!({ "guard_id": guard, "booking_id": Uuid::new_v4(), "rating_id": Uuid::new_v4(), "score": 5 });
        assert_eq!(
            plan_for_event(topics::RATING_SUBMITTED, &rate)
                .unwrap()
                .recipient_id,
            guard
        );
    }

    #[test]
    fn payment_completed_is_not_single_recipient() {
        // PRE-PAY: payment.completed is DUAL-recipient; `plan_for_event` deliberately returns None
        // (the consumer routes it to `payment_completed_plans`).
        let pay = json!({ "customer_id": Uuid::new_v4(), "guard_id": Uuid::new_v4(), "booking_id": Uuid::new_v4(), "payment_id": Uuid::new_v4(), "amount": "500.00" });
        assert!(plan_for_event(topics::PAYMENT_COMPLETED, &pay).is_none());
    }

    #[test]
    fn payment_completed_plans_notify_both_customer_and_guard() {
        let customer = Uuid::new_v4();
        let guard = Uuid::new_v4();
        let pay = json!({ "customer_id": customer, "guard_id": guard, "booking_id": Uuid::new_v4(), "payment_id": Uuid::new_v4(), "amount": "500.00" });
        let plans = payment_completed_plans(&pay);
        assert_eq!(plans.len(), 2, "PRE-PAY notifies BOTH parties");
        // Customer first: "ชำระเงินสำเร็จ".
        assert_eq!(plans[0].recipient_id, customer);
        assert_eq!(plans[0].title, "ชำระเงินสำเร็จ");
        assert_eq!(plans[0].data["target_role"], "customer");
        // Guard second: "ลูกค้าชำระเงินแล้ว".
        assert_eq!(plans[1].recipient_id, guard);
        assert_eq!(plans[1].title, "ลูกค้าชำระเงินแล้ว");
        assert_eq!(plans[1].data["target_role"], "guard");
    }

    #[test]
    fn payment_completed_plans_omit_guard_when_absent() {
        // Defensive: no guard_id → only the customer is notified (no panic, no empty guard push).
        let customer = Uuid::new_v4();
        let pay =
            json!({ "customer_id": customer, "booking_id": Uuid::new_v4(), "amount": "500.00" });
        let plans = payment_completed_plans(&pay);
        assert_eq!(plans.len(), 1);
        assert_eq!(plans[0].recipient_id, customer);
    }

    #[test]
    fn payment_completed_plans_empty_without_customer() {
        // No customer_id → nothing routable.
        let pay = json!({ "guard_id": Uuid::new_v4(), "booking_id": Uuid::new_v4() });
        assert!(payment_completed_plans(&pay).is_empty());
    }

    #[test]
    fn chat_message_notifies_recipient() {
        let recipient = Uuid::new_v4();
        let payload = json!({ "recipient_id": recipient, "sender_id": Uuid::new_v4(), "conversation_id": Uuid::new_v4(), "message_id": Uuid::new_v4() });
        let plan = plan_for_event(topics::CHAT_MESSAGE_SENT, &payload).expect("should map");
        assert_eq!(plan.recipient_id, recipient);
        assert_eq!(plan.notification_type, NotificationType::ChatMessage);
    }

    #[test]
    fn cancelled_prefers_guard_then_customer() {
        let guard = Uuid::new_v4();
        let customer = Uuid::new_v4();
        let with_guard =
            json!({ "guard_id": guard, "customer_id": customer, "booking_id": Uuid::new_v4() });
        assert_eq!(
            plan_for_event(topics::BOOKING_CANCELLED, &with_guard)
                .unwrap()
                .recipient_id,
            guard
        );
        let no_guard = json!({ "customer_id": customer, "booking_id": Uuid::new_v4() });
        assert_eq!(
            plan_for_event(topics::BOOKING_CANCELLED, &no_guard)
                .unwrap()
                .recipient_id,
            customer
        );
    }

    #[test]
    fn user_compromised_is_not_a_notification() {
        let payload =
            json!({ "user_id": Uuid::new_v4(), "reason": "refresh_token_reuse_detected" });
        assert!(plan_for_event(topics::USER_COMPROMISED, &payload).is_none());
    }

    #[test]
    fn missing_recipient_yields_none() {
        // job_accepted with no customer_id → cannot route → None (not a panic).
        let payload = json!({ "guard_id": Uuid::new_v4(), "booking_id": Uuid::new_v4() });
        assert!(plan_for_event(topics::BOOKING_JOB_ACCEPTED, &payload).is_none());
    }

    #[test]
    fn unknown_topic_yields_none() {
        assert!(plan_for_event("pguard.events.bogus.event", &json!({})).is_none());
    }

    #[test]
    fn calling_initiated_rings_the_callee() {
        let callee = Uuid::new_v4();
        let caller = Uuid::new_v4();
        let call_id = Uuid::new_v4();
        // Use the EXACT envelope the producer emits (calling `repo::enqueue_event`): the call_id
        // rides as `call_id` (AsyncAPI `EnvelopeOf_CallRef`), NEVER `id`. A prior version of this
        // test used `id`, masking that the mapper read the wrong field → the push shipped without
        // a call_id and the callee could never open the call screen.
        let payload = json!({
            "call_id": call_id,
            "caller_id": caller,
            "callee_id": callee,
            "booking_id": Uuid::new_v4(),
            "call_type": "video",
            "status": "initiated",
        });
        let plan = plan_for_event(topics::CALLING_INITIATED, &payload).expect("should map");
        assert_eq!(plan.recipient_id, callee, "the CALLEE is rung");
        assert_eq!(plan.data["type"], "incoming_call");
        assert_eq!(
            plan.data["call_id"],
            json!(call_id),
            "the call_id MUST ride in the push"
        );
        assert_eq!(
            plan.data["call_type"], "video",
            "call_type is forwarded for audio/video init"
        );
        assert_eq!(plan.data["caller_id"], json!(caller));
    }

    #[test]
    fn dispatch_plan_carries_new_job_and_booking() {
        // The fan-out per-guard alert: data { type: "new_job", booking_id } + the localized copy,
        // mirroring the incoming_call push shape. target_role=guard so the read API filters it.
        let guard = Uuid::new_v4();
        let booking = Uuid::new_v4();
        let plan = dispatch_plan_for_guard(guard, booking);
        assert_eq!(plan.recipient_id, guard);
        assert_eq!(plan.notification_type, NotificationType::BookingCreated);
        assert_eq!(plan.data["type"], "new_job");
        assert_eq!(plan.data["booking_id"], json!(booking.to_string()));
        assert_eq!(plan.data["target_role"], "guard");
        assert_eq!(plan.data["event_type"], topics::BOOKING_REQUESTED);
        assert_eq!(plan.title, "งานใหม่ใกล้คุณ");
        assert_eq!(plan.body, "New job nearby");
    }

    #[test]
    fn calling_initiated_without_callee_is_ignored() {
        // No callee_id to route to → None (not a panic), like the other recipient-less events.
        assert!(plan_for_event(topics::CALLING_INITIATED, &json!({})).is_none());
        // The non-initiated calling.* events stay unmapped (in-call signaling, not push).
        let p = json!({ "callee_id": Uuid::new_v4(), "id": Uuid::new_v4() });
        assert!(plan_for_event(topics::CALLING_ACCEPTED, &p).is_none());
        assert!(plan_for_event(topics::CALLING_ENDED, &p).is_none());
    }
}

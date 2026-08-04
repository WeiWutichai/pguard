//! PURE booking state machine. No DB/HTTP imports — 100% unit-testable.
//!
//! Ported (and adapted) from v1 `../guard-dispatch/services/booking/src/service.rs`
//! (`update_assignment_status` + the `assignment_status` enum). v2 collapses v1's two-enum,
//! per-guard-offer model into ONE first-come lifecycle:
//!
//! ```text
//!   requested ─accept→ accepted ─en_route→ en_route ─arrived→ arrived ─complete→ pending_completion
//!      │                  │                                                            │  ▲
//!      │ (no guard yet)   └─decline→ declined (assigned guard withdraws)        approve│  │reject
//!      └─────────────── cancel ────────────► cancelled (PRE-ARRIVAL only)              ▼  │
//!                                                                                  completed
//! ```
//! - `accept` CLAIMS an unassigned booking (first-come) — there is no per-guard offer, so
//!   `decline` is the ASSIGNED guard withdrawing PRE-ARRIVAL (`accepted → declined` or
//!   `en_route → declined`), not a refusal of an open request. A paid en_route withdraw is
//!   full-refunded to the customer (payment's cancellation consumer); once ARRIVED, no self-withdraw.
//! - `complete` (by the guard) requests completion → `pending_completion`; the CUSTOMER then
//!   approves (`→ completed`, emits `booking.completed`) or rejects (`→ arrived`).
//! - `cancel` is allowed only PRE-ARRIVAL (requested/accepted/en_route) — once work has begun
//!   at the site the booking runs to completion review.
//! - `start` (set `work_started_at`) does NOT change status (stays `arrived`); it is a guarded
//!   side-effect in the repo, not a status transition.

use std::fmt;
use std::str::FromStr;

/// Machine-readable `error.code` for the PRE-PAY gate 409: an `accepted → en_route` attempted
/// on a booking that has not been paid (`paid_at` is NULL). Clients (the mobile pay-step) branch
/// on this sub-code — see `AppError::ConflictCode` — to route the customer to payment instead of
/// surfacing the English message. A booking learns it is paid by consuming
/// `pguard.events.payment.completed` (which stamps `paid_at`).
pub const PAYMENT_REQUIRED_CODE: &str = "PAYMENT_REQUIRED";

/// Machine-readable `error.code` for the START-CHECK-IN gate 409: an `arrived → pending_completion`
/// (the guard's completion request) attempted before the guard has filed ANY check-in. The
/// start-of-work check-in is a first-person on-site attestation, so a job with zero reports has no
/// evidence the guard was ever present — completing it is refused server-side (the mobile UI also
/// gates the button, but that is UX-only and bypassable). Clients branch on this sub-code to show a
/// "file the start check-in first" message instead of the generic conflict copy.
pub const CHECK_IN_REQUIRED_CODE: &str = "CHECK_IN_REQUIRED";

/// The booking lifecycle status. Serialized snake_case to match the Postgres enum
/// `booking.booking_status` (NOT `sqlx::Type` — the repo binds [`BookingStatus::as_db_str`]
/// with a `::booking.booking_status` cast and reads the column back as text).
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BookingStatus {
    Requested,
    Accepted,
    Declined,
    EnRoute,
    Arrived,
    PendingCompletion,
    Completed,
    Cancelled,
}

impl BookingStatus {
    /// The snake_case label matching the Postgres enum variant.
    pub fn as_db_str(self) -> &'static str {
        match self {
            BookingStatus::Requested => "requested",
            BookingStatus::Accepted => "accepted",
            BookingStatus::Declined => "declined",
            BookingStatus::EnRoute => "en_route",
            BookingStatus::Arrived => "arrived",
            BookingStatus::PendingCompletion => "pending_completion",
            BookingStatus::Completed => "completed",
            BookingStatus::Cancelled => "cancelled",
        }
    }

    /// A terminal status admits no further transitions.
    pub fn is_terminal(self) -> bool {
        matches!(
            self,
            BookingStatus::Declined | BookingStatus::Completed | BookingStatus::Cancelled
        )
    }
}

impl fmt::Display for BookingStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_db_str())
    }
}

impl FromStr for BookingStatus {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "requested" => Ok(BookingStatus::Requested),
            "accepted" => Ok(BookingStatus::Accepted),
            "declined" => Ok(BookingStatus::Declined),
            "en_route" => Ok(BookingStatus::EnRoute),
            "arrived" => Ok(BookingStatus::Arrived),
            "pending_completion" => Ok(BookingStatus::PendingCompletion),
            "completed" => Ok(BookingStatus::Completed),
            "cancelled" => Ok(BookingStatus::Cancelled),
            other => Err(format!("unknown booking status: {other}")),
        }
    }
}

/// WHO is allowed to drive a given (legal) transition — the authz dimension the repo enforces
/// inside the row lock (the API layer only gates the broad role; OWNERSHIP is decided here).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RequiredActor {
    /// `accept` claims an UNASSIGNED booking (the booking must have no guard yet).
    ClaimUnassigned,
    /// Only the booking's assigned guard (en_route/arrived/complete/decline).
    AssignedGuard,
    /// Only the booking's owner — the customer (cancel / review-completion).
    RequestOwner,
}

/// The actor class permitted to drive `from → to`, or `None` if the transition is ILLEGAL.
/// This is the SINGLE source of truth for both legality ([`can_transition`] derives from it)
/// and ownership authz (the repo maps the class onto the concrete guard/customer id). Pure.
pub fn required_actor(from: BookingStatus, to: BookingStatus) -> Option<RequiredActor> {
    use BookingStatus::*;
    use RequiredActor::*;
    if from.is_terminal() {
        return None;
    }
    match (from, to) {
        (Requested, Accepted) => Some(ClaimUnassigned),
        // assigned-guard execution path + withdrawal
        (Accepted, EnRoute) | (EnRoute, Arrived) | (Arrived, PendingCompletion) => {
            Some(AssignedGuard)
        }
        // guard withdrawal — legal PRE-ARRIVAL (accepted OR en_route). A paid en_route booking is
        // FULL-REFUNDED to the customer by payment's cancellation-refund consumer. Once ARRIVED
        // (on-site) the guard can no longer self-withdraw — the job runs to completion review.
        (Accepted, Declined) | (EnRoute, Declined) => Some(AssignedGuard),
        // customer review of the guard's completion request
        (PendingCompletion, Completed) | (PendingCompletion, Arrived) => Some(RequestOwner),
        // cancellation: PRE-ARRIVAL active states only (a guard is not yet on-site)
        (Requested, Cancelled) | (Accepted, Cancelled) | (EnRoute, Cancelled) => Some(RequestOwner),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::BookingStatus::*;
    use super::*;

    /// `true` iff `from → to` is a legal lifecycle move — derived from [`required_actor`]
    /// (the prod authz path is the single source of truth; this just asserts legality).
    ///
    /// Happy path: `requested → accepted → en_route → arrived → pending_completion → completed`.
    /// Branches: `accepted`/`en_route → declined` (assigned guard withdraws pre-arrival);
    /// `pending_completion →
    /// arrived` (customer rejects completion); `cancelled` from any PRE-ARRIVAL active state.
    fn can_transition(from: BookingStatus, to: BookingStatus) -> bool {
        required_actor(from, to).is_some()
    }

    #[test]
    fn happy_path_transitions_are_valid() {
        assert!(can_transition(Requested, Accepted));
        assert!(can_transition(Accepted, EnRoute));
        assert!(can_transition(EnRoute, Arrived));
        assert!(can_transition(Arrived, PendingCompletion));
        assert!(can_transition(PendingCompletion, Completed));
    }

    #[test]
    fn decline_is_assigned_guard_withdrawing_before_arrival() {
        assert!(can_transition(Accepted, Declined));
        // ...and also en_route: the guard can still back out before reaching the site (a paid
        // booking is refunded by payment's cancellation consumer).
        assert!(can_transition(EnRoute, Declined));
        // NOT from an unassigned request (v2 has no per-guard offer to decline).
        assert!(!can_transition(Requested, Declined));
        // ...but never once ARRIVED (on-site): the job runs to completion review.
        assert!(!can_transition(Arrived, Declined));
    }

    #[test]
    fn customer_review_branches() {
        assert!(can_transition(PendingCompletion, Completed)); // approve
        assert!(can_transition(PendingCompletion, Arrived)); // reject → guard finishes
                                                             // a guard cannot jump arrived straight to completed (must go via review)
        assert!(!can_transition(Arrived, Completed));
    }

    #[test]
    fn cancel_is_pre_arrival_only() {
        assert!(can_transition(Requested, Cancelled));
        assert!(can_transition(Accepted, Cancelled));
        assert!(can_transition(EnRoute, Cancelled));
        // once on-site / in review, no cancel — the job runs to completion review.
        assert!(!can_transition(Arrived, Cancelled));
        assert!(!can_transition(PendingCompletion, Cancelled));
    }

    #[test]
    fn skipping_states_is_invalid() {
        assert!(!can_transition(Requested, EnRoute));
        assert!(!can_transition(Requested, Arrived));
        assert!(!can_transition(Accepted, Arrived));
        assert!(!can_transition(Accepted, PendingCompletion));
        assert!(!can_transition(EnRoute, PendingCompletion));
        assert!(!can_transition(EnRoute, Completed));
        assert!(!can_transition(Arrived, Completed));
    }

    #[test]
    fn terminal_states_admit_no_transitions() {
        for terminal in [Declined, Completed, Cancelled] {
            assert!(terminal.is_terminal());
            for to in [
                Requested,
                Accepted,
                Declined,
                EnRoute,
                Arrived,
                PendingCompletion,
                Completed,
                Cancelled,
            ] {
                assert!(
                    !can_transition(terminal, to),
                    "{terminal} → {to} must be rejected (terminal)"
                );
            }
        }
    }

    #[test]
    fn pending_completion_is_not_terminal() {
        assert!(!PendingCompletion.is_terminal());
    }

    #[test]
    fn backwards_and_self_transitions_are_invalid() {
        assert!(!can_transition(Accepted, Requested));
        assert!(!can_transition(Arrived, EnRoute));
        assert!(!can_transition(Accepted, Accepted));
        assert!(!can_transition(EnRoute, EnRoute));
        assert!(!can_transition(Completed, PendingCompletion));
    }

    #[test]
    fn required_actor_maps_each_legal_transition() {
        use RequiredActor::*;
        assert_eq!(required_actor(Requested, Accepted), Some(ClaimUnassigned));
        assert_eq!(required_actor(Accepted, EnRoute), Some(AssignedGuard));
        assert_eq!(required_actor(EnRoute, Arrived), Some(AssignedGuard));
        assert_eq!(
            required_actor(Arrived, PendingCompletion),
            Some(AssignedGuard)
        );
        assert_eq!(required_actor(Accepted, Declined), Some(AssignedGuard));
        assert_eq!(
            required_actor(PendingCompletion, Completed),
            Some(RequestOwner)
        );
        assert_eq!(
            required_actor(PendingCompletion, Arrived),
            Some(RequestOwner)
        );
        assert_eq!(required_actor(Accepted, Cancelled), Some(RequestOwner));
        // illegal → None (and therefore can_transition false)
        assert_eq!(required_actor(Arrived, Completed), None);
        assert_eq!(required_actor(Arrived, Cancelled), None);
        assert_eq!(required_actor(Completed, Cancelled), None);
    }

    #[test]
    fn claim_unassigned_maps_to_exactly_one_transition() {
        // SECURITY INVARIANT: the repo's participation gate lets a NON-participant past only
        // when required_actor == ClaimUnassigned (the first-come accept). That is safe only
        // because exactly ONE transition — (Requested → Accepted) — has that class. If a future
        // edit adds another ClaimUnassigned arm, non-participants could drive it; this test
        // fails loudly so the gate is revisited.
        let all = [
            Requested,
            Accepted,
            Declined,
            EnRoute,
            Arrived,
            PendingCompletion,
            Completed,
            Cancelled,
        ];
        let mut claims = Vec::new();
        for from in all {
            for to in all {
                if required_actor(from, to) == Some(RequiredActor::ClaimUnassigned) {
                    claims.push((from, to));
                }
            }
        }
        assert_eq!(
            claims,
            vec![(Requested, Accepted)],
            "ClaimUnassigned must map to exactly (Requested → Accepted); got {claims:?}"
        );
    }

    #[test]
    fn reason_bearing_targets_match_their_actor_class() {
        // The mandatory cancel/decline reason has TWO vocabularies, split by WHO ends the job:
        // the customer cancels (RequestOwner → cancelled), the assigned guard withdraws
        // (AssignedGuard → declined). If a future edit let, say, a guard drive `cancelled`, the
        // endpoint would hand the wrong code set to `validate_cancellation` — fail loudly here.
        use crate::domain::cancellation::{set_for_target, ReasonSet};
        let all = [
            Requested,
            Accepted,
            Declined,
            EnRoute,
            Arrived,
            PendingCompletion,
            Completed,
            Cancelled,
        ];
        for from in all {
            for to in all {
                let Some(actor) = required_actor(from, to) else {
                    continue;
                };
                match set_for_target(to) {
                    Some(ReasonSet::CustomerCancel) => assert_eq!(
                        actor,
                        RequiredActor::RequestOwner,
                        "{from} → {to} carries the CUSTOMER reason set, so only the request \
                         owner may drive it"
                    ),
                    Some(ReasonSet::GuardDecline) => assert_eq!(
                        actor,
                        RequiredActor::AssignedGuard,
                        "{from} → {to} carries the GUARD reason set, so only the assigned \
                         guard may drive it"
                    ),
                    // Every other legal transition is reasonless (the happy path).
                    None => assert!(
                        !matches!(to, Cancelled | Declined),
                        "{from} → {to} ends the job without work but carries no reason set"
                    ),
                }
            }
        }
    }

    #[test]
    fn db_str_roundtrips_through_from_str() {
        for s in [
            Requested,
            Accepted,
            Declined,
            EnRoute,
            Arrived,
            PendingCompletion,
            Completed,
            Cancelled,
        ] {
            let parsed: BookingStatus = s.as_db_str().parse().unwrap();
            assert_eq!(parsed, s);
        }
        assert!("bogus".parse::<BookingStatus>().is_err());
    }
}

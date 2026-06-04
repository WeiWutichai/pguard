//! PURE booking state machine. No DB/HTTP imports — 100% unit-testable.
//!
//! Ported (and tightened) from v1 `../guard-dispatch/services/booking/src/service.rs`
//! (the `update_assignment_status` transition `match`, lines ~652-665). v1 spread the
//! lifecycle across two enums (`request_status` + `assignment_status`); v2 collapses it
//! to one ordered status per booking with a single source-of-truth transition table here.

use std::fmt;
use std::str::FromStr;

/// The booking lifecycle status. Serialized as snake_case to match the Postgres enum
/// `booking.booking_status` (deliberately NOT `sqlx::Type` — the repo binds
/// [`BookingStatus::as_db_str`] with a `::booking.booking_status` cast and reads the
/// column back as text, keeping `domain` free of any DB derives).
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BookingStatus {
    Requested,
    Accepted,
    Declined,
    EnRoute,
    Arrived,
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
            "completed" => Ok(BookingStatus::Completed),
            "cancelled" => Ok(BookingStatus::Cancelled),
            other => Err(format!("unknown booking status: {other}")),
        }
    }
}

/// Pure transition guard. Returns `true` iff `from → to` is a legal lifecycle move.
///
/// Happy path: `requested → accepted → en_route → arrived → completed`.
/// Branches: `requested → declined`; any non-terminal, non-`requested` active state may
/// be `cancelled` (the customer cancels an in-flight booking).
pub fn can_transition(from: BookingStatus, to: BookingStatus) -> bool {
    use BookingStatus::*;
    // A terminal status (declined/completed/cancelled) admits no further moves.
    if from.is_terminal() {
        return false;
    }
    match (from, to) {
        // dispatch
        (Requested, Accepted) => true,
        (Requested, Declined) => true,
        // execution
        (Accepted, EnRoute) => true,
        (EnRoute, Arrived) => true,
        (Arrived, Completed) => true,
        // cancellation: any active post-request state (a guard is committed) may be
        // cancelled; `requested` is withdrawn the same way.
        (Requested, Cancelled)
        | (Accepted, Cancelled)
        | (EnRoute, Cancelled)
        | (Arrived, Cancelled) => true,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::BookingStatus::*;
    use super::*;

    #[test]
    fn happy_path_transitions_are_valid() {
        assert!(can_transition(Requested, Accepted));
        assert!(can_transition(Accepted, EnRoute));
        assert!(can_transition(EnRoute, Arrived));
        assert!(can_transition(Arrived, Completed));
    }

    #[test]
    fn decline_and_cancel_branches_are_valid() {
        assert!(can_transition(Requested, Declined));
        assert!(can_transition(Requested, Cancelled));
        assert!(can_transition(Accepted, Cancelled));
        assert!(can_transition(EnRoute, Cancelled));
        assert!(can_transition(Arrived, Cancelled));
    }

    #[test]
    fn skipping_states_is_invalid() {
        // cannot jump straight to arrived/completed
        assert!(!can_transition(Requested, EnRoute));
        assert!(!can_transition(Requested, Arrived));
        assert!(!can_transition(Accepted, Arrived));
        assert!(!can_transition(Accepted, Completed));
        assert!(!can_transition(EnRoute, Completed));
    }

    #[test]
    fn terminal_states_admit_no_transitions() {
        for terminal in [Declined, Completed, Cancelled] {
            assert!(terminal.is_terminal());
            for to in [Accepted, EnRoute, Arrived, Completed, Cancelled, Requested] {
                assert!(
                    !can_transition(terminal, to),
                    "{terminal} → {to} must be rejected (terminal)"
                );
            }
        }
    }

    #[test]
    fn backwards_and_self_transitions_are_invalid() {
        assert!(!can_transition(Accepted, Requested));
        assert!(!can_transition(Arrived, EnRoute));
        assert!(!can_transition(Accepted, Accepted));
        assert!(!can_transition(EnRoute, EnRoute));
    }

    #[test]
    fn declined_after_accept_is_invalid() {
        // decline is only a response to a fresh request, never after acceptance.
        assert!(!can_transition(Accepted, Declined));
        assert!(!can_transition(EnRoute, Declined));
    }

    #[test]
    fn db_str_roundtrips_through_from_str() {
        for s in [
            Requested, Accepted, Declined, EnRoute, Arrived, Completed, Cancelled,
        ] {
            let parsed: BookingStatus = s.as_db_str().parse().unwrap();
            assert_eq!(parsed, s);
        }
        assert!("bogus".parse::<BookingStatus>().is_err());
    }
}

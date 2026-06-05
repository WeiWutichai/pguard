//! Guard-approval state machine (pure). An admin moves a guard profile through the
//! approval lifecycle; this module decides which moves are LEGAL, separate from the DB
//! write (which lives in `repo::set_approval_status`).
//!
//! Lifecycle (CLAUDE.md "REUSE ApprovalStatus"): the shared [`ApprovalStatus`] enum is
//! the source of truth. A fresh guard profile is created `Pending`. From `Pending` an
//! admin may `Approve` or `Reject`. Approved/Rejected are terminal in THIS slice — a
//! re-review flow (reopen) is a deferred follow-up; modelling it now would invite an
//! admin to silently flip a decision with no audit trail.

use shared::models::ApprovalStatus;

/// Whether an admin transition from `current` to `target` is allowed.
///
/// Only `Pending → Approved` and `Pending → Rejected` are legal. Everything else
/// (including a no-op `X → X` and any move out of a terminal state) is rejected so the
/// caller returns a `Conflict` rather than silently rewriting a finalized decision.
pub fn can_transition(current: ApprovalStatus, target: ApprovalStatus) -> bool {
    matches!(
        (current, target),
        (ApprovalStatus::Pending, ApprovalStatus::Approved)
            | (ApprovalStatus::Pending, ApprovalStatus::Rejected)
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pending_can_be_approved() {
        assert!(can_transition(
            ApprovalStatus::Pending,
            ApprovalStatus::Approved
        ));
    }

    #[test]
    fn pending_can_be_rejected() {
        assert!(can_transition(
            ApprovalStatus::Pending,
            ApprovalStatus::Rejected
        ));
    }

    #[test]
    fn approved_is_terminal() {
        assert!(!can_transition(
            ApprovalStatus::Approved,
            ApprovalStatus::Rejected
        ));
        assert!(!can_transition(
            ApprovalStatus::Approved,
            ApprovalStatus::Approved
        ));
        assert!(!can_transition(
            ApprovalStatus::Approved,
            ApprovalStatus::Pending
        ));
    }

    #[test]
    fn rejected_is_terminal() {
        assert!(!can_transition(
            ApprovalStatus::Rejected,
            ApprovalStatus::Approved
        ));
        assert!(!can_transition(
            ApprovalStatus::Rejected,
            ApprovalStatus::Pending
        ));
    }

    #[test]
    fn pending_to_pending_is_noop_and_rejected() {
        assert!(!can_transition(
            ApprovalStatus::Pending,
            ApprovalStatus::Pending
        ));
    }
}

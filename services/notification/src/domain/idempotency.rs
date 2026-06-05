//! Idempotency primitives (pure).
//!
//! Under JetStream at-least-once delivery the same event can arrive more than once.
//! The live consumer dedupes via the `notification.processed_events` primary key
//! (`INSERT ... ON CONFLICT DO NOTHING`). [`SeenSet`] models exactly that semantics
//! in memory so the consumer's decision logic is testable without a database.

use std::collections::HashSet;
use uuid::Uuid;

/// In-memory dedupe ledger mirroring `notification.processed_events` (PK on event_id).
#[derive(Debug, Default)]
pub struct SeenSet {
    seen: HashSet<Uuid>,
}

impl SeenSet {
    pub fn new() -> Self {
        Self::default()
    }

    /// Claim an event id. Returns `true` if newly seen (caller should process it),
    /// `false` if it was already claimed (duplicate). Mirrors a successful
    /// `INSERT ... ON CONFLICT DO NOTHING` returning `rows_affected == 1`.
    pub fn claim(&mut self, event_id: Uuid) -> bool {
        self.seen.insert(event_id)
    }

    pub fn contains(&self, event_id: Uuid) -> bool {
        self.seen.contains(&event_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_claim_succeeds_redelivery_is_duplicate() {
        let mut seen = SeenSet::new();
        let id = Uuid::new_v4();
        assert!(seen.claim(id), "first delivery must be claimed");
        assert!(
            !seen.claim(id),
            "redelivery of the same id must be a duplicate"
        );
        assert!(seen.contains(id));
    }

    #[test]
    fn distinct_ids_are_independent() {
        let mut seen = SeenSet::new();
        assert!(seen.claim(Uuid::new_v4()));
        assert!(seen.claim(Uuid::new_v4()));
    }
}

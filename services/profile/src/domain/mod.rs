//! Pure domain logic — NO sqlx/axum/redis/reqwest/tokio imports allowed here
//! (CLAUDE.md "Domain logic in `domain/`"). 100% unit-testable in isolation.
//!
//! Holds the PDPA bank-account masking, the guard-approval state transition, and the
//! field validators the handlers apply before touching the repo.

pub mod approval;
pub mod documents;
pub mod mask;
pub mod validate;

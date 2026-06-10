//! PURE domain logic — no DB, no HTTP, no NATS. 100% unit-testable.
//!
//! - [`state`] — the booking lifecycle state machine ([`can_transition`]).
//! - [`events`] — map a status change to the `pguard.events.booking.*` event it emits
//!   ([`event_for_status`]), the producer counterpart to notification's mapper.
//! - [`progress`] — hourly check-in rules (state gate, hour window, photo validation) +
//!   open-job discovery query validation.

pub mod events;
pub mod progress;
pub mod state;

pub use events::{event_for_progress_report, event_for_status, CompletionInfo, EventMapping};

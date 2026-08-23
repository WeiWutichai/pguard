//! PURE domain logic — no DB, no HTTP, no NATS. 100% unit-testable.
//!
//! - [`state`] — the booking lifecycle state machine ([`can_transition`]).
//! - [`events`] — map a status change to the `pguard.events.booking.*` event it emits
//!   ([`event_for_status`]), the producer counterpart to notification's mapper.
//! - [`progress`] — hourly check-in rules (state gate, hour window, photo validation) +
//!   open-job discovery query validation.
//! - [`geo`] — start-work geofence (haversine + the 50m fence with capped accuracy allowance).
//! - [`scheduling`] — server-authoritative time gates keyed off `scheduled_at`: reject creating a
//!   booking in the past ([`scheduling::validate_scheduled_at`]) and starting one before its
//!   scheduled window opens ([`scheduling::validate_start_time`]).
//! - [`cancellation`] — the mandatory cancel/decline reason codes + their validator (the two
//!   endpoints have DIFFERENT vocabularies).
//! - [`pricing`] — the per-service commission + cancellation fee: what an admin may STORE
//!   ([`validate_commission_percent`], [`validate_cancellation_fee`]) and the
//!   [`PricingSnapshot`] a booking copies from the catalog at creation.

pub mod cancellation;
pub mod events;
pub mod geo;
pub mod pricing;
pub mod progress;
pub mod scheduling;
pub mod state;

pub use cancellation::{validate_cancellation, Cancellation, ReasonSet};
pub use events::{
    event_for_booking_requested, event_for_progress_report, event_for_status, CompletionInfo,
    EventMapping,
};
pub use pricing::{validate_cancellation_fee, validate_commission_percent, PricingSnapshot};

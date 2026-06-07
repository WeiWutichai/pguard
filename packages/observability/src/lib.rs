//! Telemetry shared by every pguard service (CLAUDE.md → Observability decision:
//! OpenTelemetry traces across services → Tempo, plus Prometheus metrics).
//!
//! Wiring per service (`main.rs`):
//! ```ignore
//! let _telemetry = observability::init_telemetry(SERVICE_NAME); // bind to flush on exit
//! let app = Router::new()
//!     .route("/metrics", axum::routing::get(observability::metrics_handler))
//!     // ... routes ...
//!     .layer(axum::middleware::from_fn(observability::telemetry_middleware));
//! ```
//!
//! Outbound service→service calls inject the trace context with [`inject_context`];
//! NATS producers stamp [`current_traceparent`] into the event envelope and consumers
//! reparent with [`set_parent_from_traceparent`]. Together these make a
//! booking→payment→notification flow one trace in Tempo.

mod metrics;
mod middleware;
mod propagation;
mod telemetry;

pub use metrics::{metrics_handler, record_consumer_lag, record_rejected_event};
pub use middleware::{edge_telemetry_middleware, telemetry_middleware};
pub use propagation::{
    current_traceparent, inject_context, set_parent_from_traceparent, trace_headers,
};
pub use telemetry::{init_telemetry, OtelGuard};

//! Telemetry setup shared by every service.
//!
//! v2 scaffold: structured logging via `tracing-subscriber` with `RUST_LOG`
//! filtering. The CLAUDE.md "Observability" decision (OpenTelemetry traces across
//! services → Tempo + Loki) plugs in here next: add an OTLP layer exporting to the
//! collector defined in `infra/observability/otel-collector-config.yaml`, plus
//! W3C trace-context propagation on outbound HTTP/NATS calls.

use std::sync::atomic::{AtomicBool, Ordering};

use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

static INITIALISED: AtomicBool = AtomicBool::new(false);

/// Initialise the global tracing subscriber for `service_name`.
///
/// Idempotent: safe to call once per process (subsequent calls are no-ops), which
/// also makes it safe to call from tests. Reads the `RUST_LOG` env filter, falling
/// back to `info`.
pub fn init_telemetry(service_name: &str) {
    // Guard against double-init (the global subscriber can only be set once).
    if INITIALISED.swap(true, Ordering::SeqCst) {
        return;
    }

    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));

    tracing_subscriber::registry()
        .with(filter)
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!(service = service_name, "telemetry initialised");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn init_is_idempotent() {
        // Should not panic on repeated calls.
        init_telemetry("test-service");
        init_telemetry("test-service");
    }
}

//! Prometheus metrics — a process-wide recorder plus the `/metrics` text endpoint each
//! service mounts. The HTTP request rate / latency / error-rate series are emitted by
//! [`crate::telemetry_middleware`]; NATS consumer lag is reported by the consuming
//! services via [`record_consumer_lag`]. Prometheus scrapes each service's `/metrics`
//! (see `infra/observability/prometheus.yml`).

use std::sync::{Once, OnceLock};

use metrics_exporter_prometheus::{Matcher, PrometheusBuilder, PrometheusHandle};

/// Guards the one-time install so the global recorder and its render handle are set
/// together, atomically — `Once::call_once` serializes concurrent first-callers (a plain
/// `HANDLE.get()` check would let two threads race and desync the global recorder from the
/// stored handle).
static INSTALL: Once = Once::new();
/// The rendered-metrics handle, set once when the recorder is installed.
static HANDLE: OnceLock<PrometheusHandle> = OnceLock::new();

/// Latency histogram buckets (seconds) — tuned for sub-ms→multi-second request spread so
/// the p99 panel is meaningful across fast cache reads and slow cross-service fan-outs.
const LATENCY_BUCKETS: &[f64] = &[
    0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0,
];

/// Install the global Prometheus recorder and stash its render handle. Idempotent: only
/// the first call wins (subsequent calls — e.g. repeated `init_telemetry` in tests — are
/// no-ops). Uses `build_recorder()` (no background upkeep task) so it is safe to call
/// outside a Tokio runtime.
pub(crate) fn install_recorder() {
    INSTALL.call_once(|| {
        let builder = PrometheusBuilder::new()
            .set_buckets_for_metric(
                Matcher::Full("http_request_duration_seconds".to_string()),
                LATENCY_BUCKETS,
            )
            .expect("valid latency buckets");

        let recorder = builder.build_recorder();
        let handle = recorder.handle();

        // Store the handle ONLY if this recorder actually became the process global, so
        // `/metrics` never renders an orphan recorder that no metric writes to.
        if metrics::set_global_recorder(recorder).is_ok() {
            let _ = HANDLE.set(handle);
        }
    });
}

/// Render the current registry in Prometheus text format (empty before install).
pub(crate) fn render() -> String {
    HANDLE
        .get()
        .map(PrometheusHandle::render)
        .unwrap_or_default()
}

/// Axum handler for `GET /metrics` — the registry in Prometheus exposition format with the
/// matching `Content-Type` (some scrapers are strict). Returns empty (200) before install.
pub async fn metrics_handler() -> impl axum::response::IntoResponse {
    (
        [(
            axum::http::header::CONTENT_TYPE,
            "text/plain; version=0.0.4; charset=utf-8",
        )],
        render(),
    )
}

/// Report a JetStream durable consumer's pending-message backlog (lag). Consuming services
/// call this per delivered message with `message.info().pending`.
pub fn record_consumer_lag(durable: &str, pending: u64) {
    metrics::gauge!("nats_consumer_pending", "durable" => durable.to_string()).set(pending as f64);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn install_is_idempotent_and_renders() {
        install_recorder();
        install_recorder();
        // Render should not panic and the handle must be present after install.
        let _ = render();
        assert!(HANDLE.get().is_some());
    }
}

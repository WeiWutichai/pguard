//! `init_telemetry` — install the tracing subscriber, the OTLP span exporter (→ collector
//! → Tempo), the W3C propagator, and the Prometheus recorder. Idempotent and safe to call
//! from tests.
//!
//! **OTLP export is gated on `OTEL_EXPORTER_OTLP_ENDPOINT`.** With the env set (dev-up,
//! docker, prod) spans batch-export to the collector. With it unset (unit tests, local
//! without the stack) the service logs only — no exporter, no Tokio-runtime requirement,
//! so plain `#[test]` init stays green. Sampling ratio comes from `OTEL_TRACES_SAMPLER_ARG`
//! (0.0–1.0, default 1.0), parent-based so a sampled upstream keeps the whole trace.

use std::sync::atomic::{AtomicBool, Ordering};

use opentelemetry::trace::TracerProvider as _;
use opentelemetry::KeyValue;
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::propagation::TraceContextPropagator;
use opentelemetry_sdk::trace::{Sampler, TracerProvider as SdkTracerProvider};
use opentelemetry_sdk::Resource;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

static INITIALISED: AtomicBool = AtomicBool::new(false);

/// Flushes the OTLP exporter on drop. Bind it in `main` (`let _telemetry = init_telemetry(...)`)
/// so spans buffered in the batch processor are exported if `main` returns. Logging-only
/// init yields an inert guard.
#[must_use = "bind the guard (`let _telemetry = ...`) so spans are flushed on shutdown"]
pub struct OtelGuard {
    provider: Option<SdkTracerProvider>,
}

impl Drop for OtelGuard {
    fn drop(&mut self) {
        if let Some(provider) = self.provider.take() {
            // Best-effort flush of any buffered spans.
            let _ = provider.shutdown();
        }
    }
}

/// Initialise telemetry for `service_name`. Idempotent (subsequent calls are no-ops and
/// return an inert guard). See the module docs for the OTLP gating + sampling envs.
pub fn init_telemetry(service_name: &str) -> OtelGuard {
    if INITIALISED.swap(true, Ordering::SeqCst) {
        return OtelGuard { provider: None };
    }

    // Process-wide Prometheus recorder (for `/metrics`).
    crate::metrics::install_recorder();

    // W3C trace-context propagation across services + NATS.
    opentelemetry::global::set_text_map_propagator(TraceContextPropagator::new());

    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));
    let fmt_layer = tracing_subscriber::fmt::layer();

    match otlp_endpoint() {
        Some(endpoint) => {
            let exporter = opentelemetry_otlp::SpanExporter::builder()
                .with_tonic()
                .with_endpoint(&endpoint)
                .build()
                .expect("build OTLP span exporter"); // startup-only

            let provider = SdkTracerProvider::builder()
                .with_batch_exporter(exporter, opentelemetry_sdk::runtime::Tokio)
                .with_sampler(sampler_from_env())
                .with_resource(Resource::new(vec![KeyValue::new(
                    "service.name",
                    service_name.to_string(),
                )]))
                .build();

            let tracer = provider.tracer("pguard");
            let otel_layer = tracing_opentelemetry::layer().with_tracer(tracer);

            tracing_subscriber::registry()
                .with(filter)
                .with(fmt_layer)
                .with(otel_layer)
                .init();

            tracing::info!(
                service = service_name,
                endpoint = %endpoint,
                "telemetry initialised (OTLP trace export on)"
            );
            OtelGuard {
                provider: Some(provider),
            }
        }
        None => {
            tracing_subscriber::registry()
                .with(filter)
                .with(fmt_layer)
                .init();
            tracing::info!(
                service = service_name,
                "telemetry initialised (logging only; set OTEL_EXPORTER_OTLP_ENDPOINT to export traces)"
            );
            OtelGuard { provider: None }
        }
    }
}

/// The configured OTLP gRPC endpoint, or `None` when unset/empty (→ logging-only).
fn otlp_endpoint() -> Option<String> {
    std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT")
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

/// Parent-based ratio sampler from `OTEL_TRACES_SAMPLER_ARG` (default 1.0 = sample all).
/// Parent-based so a decision made upstream propagates through the whole trace.
fn sampler_from_env() -> Sampler {
    let ratio = std::env::var("OTEL_TRACES_SAMPLER_ARG")
        .ok()
        .and_then(|s| s.trim().parse::<f64>().ok())
        .map(|r| r.clamp(0.0, 1.0))
        .unwrap_or(1.0);
    Sampler::ParentBased(Box::new(Sampler::TraceIdRatioBased(ratio)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn init_is_idempotent() {
        // Env unset → logging-only path (no Tokio runtime needed). Repeated calls no-op.
        let _g1 = init_telemetry("test-service");
        let _g2 = init_telemetry("test-service");
    }

    #[test]
    fn sampler_defaults_to_all_when_unset() {
        // Just exercises the parse/clamp path; constructing the sampler must not panic.
        let _ = sampler_from_env();
    }
}

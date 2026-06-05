//! The per-request telemetry middleware every service mounts. One pass does two jobs:
//!
//! 1. **Inbound trace-context** — [`telemetry_middleware`] parents this request's span on
//!    the caller's W3C `traceparent` (service→service), so a handler's spans and any event
//!    it emits continue the upstream trace. [`edge_telemetry_middleware`] does NOT —- it
//!    starts a fresh ROOT trace, for the public edge (the gateway) where the caller is an
//!    untrusted client: adopting its `traceparent` would let it forge the `trace_id` and
//!    (via the parent-based sampler) force 100% sampling, bypassing `OTEL_TRACES_SAMPLER_ARG`.
//! 2. **HTTP metrics** — `http_requests_total{method,route,status}` (rate + error rate)
//!    and `http_request_duration_seconds{method,route}` (p99 latency). The `route` label
//!    is the *matched* path template (`/bookings/{id}`), never the concrete id, so
//!    cardinality stays bounded.
//!
//! On a 5xx response the span's OTel status is set to error so Tempo's red/failed-span
//! filtering and service-graph error edges work (metrics count it regardless).

use std::time::Instant;

use axum::extract::MatchedPath;
use axum::http::Request;
use axum::middleware::Next;
use axum::response::Response;
use tracing::field::Empty;
use tracing::Instrument;

use crate::propagation::set_parent_from_headers;

/// Backend middleware: continues the caller's trace by extracting the inbound `traceparent`.
/// Mount on internal services — `.layer(from_fn(observability::telemetry_middleware))`.
pub async fn telemetry_middleware(req: Request<axum::body::Body>, next: Next) -> Response {
    record(req, next, true).await
}

/// Edge middleware: starts a FRESH ROOT trace, ignoring any client-supplied `traceparent`.
/// Mount only at the public edge (api-gateway) — see the trust-boundary note in the module
/// docs. The gateway then injects its own context to downstream services.
pub async fn edge_telemetry_middleware(req: Request<axum::body::Body>, next: Next) -> Response {
    record(req, next, false).await
}

/// Shared body: build the server span (rooted per `extract_parent`), run the request, then
/// record metrics + span status.
async fn record(req: Request<axum::body::Body>, next: Next, extract_parent: bool) -> Response {
    let method = req.method().clone();
    // Matched route template keeps the metrics label cardinality bounded.
    let route = req
        .extensions()
        .get::<MatchedPath>()
        .map(|m| m.as_str().to_string())
        .unwrap_or_else(|| "unmatched".to_string());

    let span = tracing::info_span!(
        "http.request",
        otel.kind = "server",
        otel.name = %format!("{method} {route}"),
        http.request.method = %method,
        http.route = %route,
        http.response.status_code = Empty,
        otel.status_code = Empty,
    );
    // Backends continue the caller's trace; the edge starts a fresh root (untrusted client).
    if extract_parent {
        set_parent_from_headers(&span, req.headers());
    }

    let method_label = method.to_string();
    let route_label = route.clone();

    let start = Instant::now();
    let response = next.run(req).instrument(span.clone()).await;
    let elapsed = start.elapsed().as_secs_f64();
    let status = response.status().as_u16();

    span.record("http.response.status_code", status);
    // Mark the span as an OTel error span on 5xx so Tempo error filtering / service-graph
    // error edges light up (metrics already label the status independently).
    if status >= 500 {
        span.record("otel.status_code", "error");
    }

    metrics::counter!(
        "http_requests_total",
        "method" => method_label.clone(),
        "route" => route_label.clone(),
        "status" => status.to_string(),
    )
    .increment(1);
    metrics::histogram!(
        "http_request_duration_seconds",
        "method" => method_label,
        "route" => route_label,
    )
    .record(elapsed);

    response
}

#[cfg(test)]
mod tests {
    use axum::routing::get;
    use axum::Router;
    use tower::ServiceExt; // oneshot

    /// Proves the middleware records the **matched route template** (`/x/{id}`), not the
    /// concrete path — i.e. `MatchedPath` is visible inside a `Router::layer` middleware,
    /// so metric label cardinality stays bounded. Also exercises the full metrics path.
    #[tokio::test]
    async fn middleware_records_matched_route_template() {
        crate::metrics::install_recorder();

        let app = Router::new()
            .route("/x/{id}", get(|| async { "ok" }))
            .layer(axum::middleware::from_fn(super::telemetry_middleware));

        let resp = app
            .oneshot(
                axum::http::Request::builder()
                    .uri("/x/12345")
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), 200);

        let rendered = crate::metrics::render();
        assert!(
            rendered.contains("route=\"/x/{id}\""),
            "metrics must use the matched route template, got:\n{rendered}"
        );
        assert!(
            !rendered.contains("/x/12345"),
            "concrete id must not leak into a metric label:\n{rendered}"
        );
    }
}

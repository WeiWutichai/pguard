//! W3C trace-context propagation — the glue that makes a booking→payment→notification
//! flow a single distributed trace.
//!
//! Two carriers:
//! - **HTTP headers** (`axum::http::HeaderMap`) for synchronous service→service calls
//!   (gateway→booking, booking→profile/rating, payment→booking, …).
//! - **NATS events** carry the `traceparent` *inside the event envelope*
//!   ([`shared_events::EventEnvelope::traceparent`]). The envelope is serialized into the
//!   transactional outbox at request time — i.e. while the producer's request span is
//!   current — so [`current_traceparent`] captures the right context even though the relay
//!   publishes it later, decoupled in time.
//!
//! All inject/extract goes through the process-global propagator installed by
//! [`crate::init_telemetry`] (`TraceContextPropagator`). When telemetry is logging-only
//! (no OTLP endpoint configured) the current span has no valid OTel context and these
//! helpers degrade to no-ops returning `None`.

use std::collections::HashMap;

use opentelemetry::propagation::{Extractor, Injector};
use opentelemetry::trace::TraceContextExt;
use opentelemetry::Context;
use tracing::Span;
use tracing_opentelemetry::OpenTelemetrySpanExt;

/// Injector over an `axum::http::HeaderMap` (== `http::HeaderMap`, the type reqwest uses).
struct HeaderInjector<'a>(&'a mut axum::http::HeaderMap);

impl Injector for HeaderInjector<'_> {
    fn set(&mut self, key: &str, value: String) {
        if let (Ok(name), Ok(val)) = (
            axum::http::HeaderName::from_bytes(key.as_bytes()),
            axum::http::HeaderValue::from_str(&value),
        ) {
            self.0.insert(name, val);
        }
    }
}

/// Extractor over an incoming request's `HeaderMap`.
struct HeaderExtractor<'a>(&'a axum::http::HeaderMap);

impl Extractor for HeaderExtractor<'_> {
    fn get(&self, key: &str) -> Option<&str> {
        self.0.get(key).and_then(|v| v.to_str().ok())
    }
    fn keys(&self) -> Vec<&str> {
        self.0.keys().map(|k| k.as_str()).collect()
    }
}

/// Injector/Extractor over a plain string map (used to read the `traceparent` value out
/// for an event envelope, and to feed it back in on the consumer side).
struct MapInjector<'a>(&'a mut HashMap<String, String>);

impl Injector for MapInjector<'_> {
    fn set(&mut self, key: &str, value: String) {
        self.0.insert(key.to_string(), value);
    }
}

struct MapExtractor<'a>(&'a HashMap<String, String>);

impl Extractor for MapExtractor<'_> {
    fn get(&self, key: &str) -> Option<&str> {
        self.0.get(key).map(String::as_str)
    }
    fn keys(&self) -> Vec<&str> {
        self.0.keys().map(String::as_str).collect()
    }
}

/// Inject the **current** span's trace context into outbound HTTP `headers` (adds a W3C
/// `traceparent`). Call this when building a service→service request so the callee parents
/// its work under the caller's trace. No-op when there's no active OTel context.
pub fn inject_context(headers: &mut axum::http::HeaderMap) {
    let cx = Span::current().context();
    opentelemetry::global::get_text_map_propagator(|prop| {
        prop.inject_context(&cx, &mut HeaderInjector(headers));
    });
}

/// A fresh `HeaderMap` carrying the current span's trace context — ergonomic for reqwest:
/// `client.get(url).headers(observability::trace_headers())`. Empty when there's no active
/// trace. (`reqwest::header::HeaderMap` is the same `http::HeaderMap` type.)
pub fn trace_headers() -> axum::http::HeaderMap {
    let mut headers = axum::http::HeaderMap::new();
    inject_context(&mut headers);
    headers
}

/// The W3C `traceparent` string for the current span, or `None` when there's no valid
/// active trace (logging-only mode / outside any sampled span). Stamped into
/// [`shared_events::EventEnvelope`] at construction time so it rides through NATS.
pub fn current_traceparent() -> Option<String> {
    let cx = Span::current().context();
    if !cx.span().span_context().is_valid() {
        return None;
    }
    let mut carrier = HashMap::new();
    opentelemetry::global::get_text_map_propagator(|prop| {
        prop.inject_context(&cx, &mut MapInjector(&mut carrier));
    });
    carrier.remove("traceparent")
}

/// Build an OTel [`Context`] from a W3C `traceparent` carried on an event envelope.
/// Crate-internal: callers reparent via [`set_parent_from_traceparent`].
pub(crate) fn context_from_traceparent(traceparent: &str) -> Context {
    let mut carrier = HashMap::new();
    carrier.insert("traceparent".to_string(), traceparent.to_string());
    opentelemetry::global::get_text_map_propagator(|prop| prop.extract(&MapExtractor(&carrier)))
}

/// Parent `span` on the trace carried by an incoming request's `headers` (server side).
/// Crate-internal: used by the backend [`crate::telemetry_middleware`]; the edge variant
/// deliberately skips this so an untrusted client can't supply the trace context.
pub(crate) fn set_parent_from_headers(span: &Span, headers: &axum::http::HeaderMap) {
    let cx = opentelemetry::global::get_text_map_propagator(|prop| {
        prop.extract(&HeaderExtractor(headers))
    });
    span.set_parent(cx);
}

/// Parent `span` on the trace carried by an event envelope's `traceparent` (NATS consumer
/// side). No-op-ish when `traceparent` is empty/invalid (parent becomes a no-op context).
pub fn set_parent_from_traceparent(span: &Span, traceparent: &str) {
    span.set_parent(context_from_traceparent(traceparent));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn header_extractor_reads_keys_and_values() {
        let mut headers = axum::http::HeaderMap::new();
        headers.insert(
            "traceparent",
            axum::http::HeaderValue::from_static(
                "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01",
            ),
        );
        let ex = HeaderExtractor(&headers);
        assert_eq!(
            ex.get("traceparent"),
            Some("00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01")
        );
        assert!(ex.keys().contains(&"traceparent"));
    }

    #[test]
    fn current_traceparent_is_none_without_active_trace() {
        // No OTLP layer installed in unit tests → no valid span context → None (degrades
        // gracefully so producers never emit a bogus traceparent).
        assert!(current_traceparent().is_none());
    }

    #[test]
    fn inject_context_is_a_noop_without_active_trace() {
        let mut headers = axum::http::HeaderMap::new();
        inject_context(&mut headers);
        assert!(headers.get("traceparent").is_none());
    }

    /// The core cross-service invariant: a `traceparent` injected by a producer (into an
    /// envelope / outbound headers) extracts back to the SAME trace id on the consumer side.
    /// This is exactly what stitches gateway→booking→NATS→notification into one trace.
    #[test]
    fn traceparent_round_trips_trace_id_across_the_wire() {
        use opentelemetry::trace::{
            SpanContext, SpanId, TraceContextExt, TraceFlags, TraceId, TraceState,
        };
        use opentelemetry::Context;
        use std::collections::HashMap;

        opentelemetry::global::set_text_map_propagator(
            opentelemetry_sdk::propagation::TraceContextPropagator::new(),
        );

        let trace_id = TraceId::from_hex("0af7651916cd43dd8448eb211c80319c").unwrap();
        let span_id = SpanId::from_hex("b7ad6b7169203331").unwrap();
        let sc = SpanContext::new(
            trace_id,
            span_id,
            TraceFlags::SAMPLED,
            true,
            TraceState::default(),
        );
        let producer_cx = Context::new().with_remote_span_context(sc);

        // Producer side: inject (what current_traceparent / inject_context do).
        let mut carrier = HashMap::new();
        opentelemetry::global::get_text_map_propagator(|p| {
            p.inject_context(&producer_cx, &mut MapInjector(&mut carrier))
        });
        let tp = carrier.remove("traceparent").expect("traceparent injected");

        // Consumer side: extract (what set_parent_from_traceparent does).
        let extracted = context_from_traceparent(&tp);
        assert!(extracted.span().span_context().is_valid());
        assert_eq!(
            extracted.span().span_context().trace_id(),
            trace_id,
            "trace id must survive the producer→consumer hop"
        );
    }
}

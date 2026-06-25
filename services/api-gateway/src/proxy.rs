//! Reverse-proxy I/O: forward an inbound axum request to an upstream via reqwest and
//! translate the upstream response back.
//!
//! Responsibilities (the pure rules live in `domain::headers`):
//!   - Buffer the request body with a [`MAX_BODY_BYTES`] cap (DoS guard → 413).
//!   - Strip hop-by-hop + client-supplied `x-user-*` headers, then inject the trusted
//!     `X-User-Id` / `X-User-Role` from the edge-verified token (if any).
//!   - Forward method + filtered headers + body to `{base}{forward_path}{?query}`.
//!   - Map upstream-unreachable → 502, oversized body → 413.

use axum::body::Body;
use axum::extract::Request;
use axum::http::{HeaderMap, HeaderName, HeaderValue, StatusCode};
use axum::response::Response;

use crate::auth::VerifiedUser;
use crate::domain::headers::{is_hop_by_hop, is_spoofable_identity};

/// Default buffered request-body cap (1 MiB) — the value used for every route except the
/// upload carve-outs (see `domain::routing::BodyCap`). Also reused by the WS proxy as the
/// per-frame cap (`wsproxy::MAX_CLIENT_FRAME_BYTES`); the carve-out raises the REST body cap
/// per-route via [`forward`]'s `max_body_bytes` argument and does NOT touch this const, so
/// the WS frame cap stays 1 MiB. `BodyCap::DEFAULT_BYTES` is pinned equal to this by a test.
pub const MAX_BODY_BYTES: usize = 1024 * 1024;

/// Proxy-stage failures, each with a distinct public HTTP status. Kept separate from
/// `shared::error::AppError` so "upstream unreachable" maps to **502** (not 500) and an
/// oversized body maps to **413**.
#[derive(Debug)]
pub enum ProxyError {
    /// Request body exceeded [`MAX_BODY_BYTES`] → 413.
    BodyTooLarge,
    /// Upstream connect/send/read failed → 502.
    Upstream,
}

impl ProxyError {
    pub fn status(&self) -> StatusCode {
        match self {
            ProxyError::BodyTooLarge => StatusCode::PAYLOAD_TOO_LARGE,
            ProxyError::Upstream => StatusCode::BAD_GATEWAY,
        }
    }

    /// Generic, leak-free client message.
    pub fn message(&self) -> &'static str {
        match self {
            ProxyError::BodyTooLarge => "Request body too large",
            ProxyError::Upstream => "Upstream service unavailable",
        }
    }
}

/// Build the upstream request headers from the inbound ones:
///   - drop hop-by-hop headers,
///   - drop ANY client-supplied `x-user-*` (anti-spoofing),
///   - then inject trusted identity headers when the request was authenticated.
///
/// Returns a fresh `reqwest::header::HeaderMap`. Authorization is preserved (backends
/// re-validate — defense in depth).
fn build_forward_headers(
    inbound: &HeaderMap,
    user: Option<&VerifiedUser>,
) -> reqwest::header::HeaderMap {
    let mut out = reqwest::header::HeaderMap::new();
    for (name, value) in inbound.iter() {
        let n = name.as_str();
        // Drop client-supplied W3C trace context at the edge: the gateway is the trust
        // boundary and re-injects its OWN context (a client must not forge the downstream
        // trace_id or force sampling). Stripped here so it holds even in logging-only mode.
        if n.eq_ignore_ascii_case("traceparent") || n.eq_ignore_ascii_case("tracestate") {
            continue;
        }
        if is_hop_by_hop(n) || is_spoofable_identity(n) {
            continue;
        }
        if let (Ok(hn), Ok(hv)) = (
            reqwest::header::HeaderName::from_bytes(name.as_ref()),
            reqwest::header::HeaderValue::from_bytes(value.as_bytes()),
        ) {
            out.append(hn, hv);
        }
    }

    // Inject trusted identity (only valid header values; user_id is a UUID, role is a
    // small ascii enum — both always parse, but guard anyway to keep the request path
    // free of unwrap/expect).
    if let Some(u) = user {
        if let Ok(v) = reqwest::header::HeaderValue::from_str(&u.user_id.to_string()) {
            out.insert(reqwest::header::HeaderName::from_static("x-user-id"), v);
        }
        if let Ok(v) = reqwest::header::HeaderValue::from_str(&u.role) {
            out.insert(reqwest::header::HeaderName::from_static("x-user-role"), v);
        }
    }

    out
}

/// Forward `request` to `{base_url}{forward_path}{?query}` and return the translated
/// upstream response. `user` is `Some` for authenticated (protected) routes.
///
/// `forward_path` already has the `/v1` prefix stripped (see `domain::routing`).
/// `max_body_bytes` is the per-route body cap from the route decision
/// (`domain::routing::BodyCap::bytes`) — [`MAX_BODY_BYTES`] for all but the upload carve-outs.
#[tracing::instrument(skip(http, request, user), fields(base_url, forward_path))]
pub async fn forward(
    http: &reqwest::Client,
    base_url: &str,
    forward_path: &str,
    query: Option<&str>,
    request: Request,
    user: Option<&VerifiedUser>,
    max_body_bytes: usize,
) -> Result<Response, ProxyError> {
    let (parts, body) = request.into_parts();
    let method = parts.method.clone();

    // Buffer the body with the route's hard cap. `to_bytes` with a limit returns Err when the
    // body exceeds it (or when declared Content-Length is too large) → 413.
    let body_bytes = axum::body::to_bytes(body, max_body_bytes)
        .await
        .map_err(|_| ProxyError::BodyTooLarge)?;

    let mut fwd_headers = build_forward_headers(&parts.headers, user);
    // Inject the edge's W3C trace context so the backend continues THIS trace. The gateway
    // span is a fresh root (edge_telemetry_middleware ignores any client traceparent) and
    // build_forward_headers strips client trace-context headers, so the downstream parent is
    // always the gateway's.
    observability::inject_context(&mut fwd_headers);

    let url = match query {
        Some(q) if !q.is_empty() => format!("{base_url}{forward_path}?{q}"),
        _ => format!("{base_url}{forward_path}"),
    };

    let reqwest_method =
        reqwest::Method::from_bytes(method.as_str().as_bytes()).unwrap_or(reqwest::Method::GET);

    let upstream_resp = http
        .request(reqwest_method, &url)
        .headers(fwd_headers)
        .body(body_bytes.to_vec())
        .send()
        .await
        .map_err(|e| {
            // Log upstream + path only — never the query string (it may carry params).
            tracing::warn!(error = %e, upstream = %base_url, path = %forward_path, "upstream request failed");
            ProxyError::Upstream
        })?;

    translate_response(upstream_resp).await
}

/// Translate a reqwest upstream response into an axum response: copy status + headers
/// (minus hop-by-hop) + body.
async fn translate_response(resp: reqwest::Response) -> Result<Response, ProxyError> {
    let status = StatusCode::from_u16(resp.status().as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);

    // Copy response headers, dropping hop-by-hop (transfer-encoding etc. would corrupt
    // the re-framed body).
    let mut out_headers = HeaderMap::new();
    for (name, value) in resp.headers().iter() {
        if is_hop_by_hop(name.as_str()) {
            continue;
        }
        if let (Ok(hn), Ok(hv)) = (
            HeaderName::from_bytes(name.as_ref()),
            HeaderValue::from_bytes(value.as_bytes()),
        ) {
            out_headers.append(hn, hv);
        }
    }

    let body_bytes = resp.bytes().await.map_err(|e| {
        tracing::warn!(error = %e, "reading upstream body failed");
        ProxyError::Upstream
    })?;

    let mut response = Response::new(Body::from(body_bytes));
    *response.status_mut() = status;
    *response.headers_mut() = out_headers;
    Ok(response)
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::header::AUTHORIZATION;
    use uuid::Uuid;

    fn inbound(pairs: &[(&str, &str)]) -> HeaderMap {
        let mut h = HeaderMap::new();
        for (k, v) in pairs {
            h.insert(
                HeaderName::from_bytes(k.as_bytes()).unwrap(),
                HeaderValue::from_str(v).unwrap(),
            );
        }
        h
    }

    #[test]
    fn forward_headers_strip_hop_by_hop() {
        let h = inbound(&[
            ("connection", "keep-alive"),
            ("content-type", "application/json"),
        ]);
        let out = build_forward_headers(&h, None);
        assert!(out.get("connection").is_none(), "hop-by-hop dropped");
        assert_eq!(out.get("content-type").unwrap(), "application/json");
    }

    #[test]
    fn forward_headers_strip_client_x_user_then_inject_trusted() {
        // Client tries to spoof X-User-Id/Role; gateway must drop them and inject the
        // verified identity instead.
        let h = inbound(&[
            ("x-user-id", "00000000-0000-0000-0000-000000000000"),
            ("x-user-role", "admin"),
        ]);
        let id = Uuid::new_v4();
        let user = VerifiedUser {
            user_id: id,
            role: "customer".to_string(),
        };
        let out = build_forward_headers(&h, Some(&user));
        assert_eq!(out.get("x-user-id").unwrap(), &id.to_string());
        assert_eq!(out.get("x-user-role").unwrap(), "customer");
    }

    #[test]
    fn forward_headers_drop_client_x_user_when_unauthenticated() {
        // Public route (no verified user): client-supplied x-user-* must still be
        // stripped so a backend never sees a forged identity from the edge.
        let h = inbound(&[("x-user-id", "spoofed"), ("x-user-role", "admin")]);
        let out = build_forward_headers(&h, None);
        assert!(out.get("x-user-id").is_none());
        assert!(out.get("x-user-role").is_none());
    }

    #[test]
    fn forward_headers_preserve_authorization() {
        let h = inbound(&[("authorization", "Bearer tok")]);
        let out = build_forward_headers(&h, None);
        assert_eq!(out.get(AUTHORIZATION.as_str()).unwrap(), "Bearer tok");
    }

    #[test]
    fn forward_headers_strip_client_trace_context() {
        // Edge trust boundary: a client must not control the downstream trace context
        // (forge trace_id / force sampling). The gateway re-injects its own.
        let h = inbound(&[
            (
                "traceparent",
                "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01",
            ),
            ("tracestate", "vendor=value"),
            ("content-type", "application/json"),
        ]);
        let out = build_forward_headers(&h, None);
        assert!(
            out.get("traceparent").is_none(),
            "client traceparent stripped at edge"
        );
        assert!(
            out.get("tracestate").is_none(),
            "client tracestate stripped at edge"
        );
        assert_eq!(out.get("content-type").unwrap(), "application/json");
    }

    // ----- ephemeral-upstream proxy integration (no Redis required) -----

    use axum::extract::Request;
    use axum::response::IntoResponse;
    use axum::routing::any;
    use axum::Router;

    /// Spin a tiny in-process axum upstream on an OS-assigned port. It echoes back the
    /// path it received and the trusted X-User-* headers it saw, so the test can assert
    /// the gateway stripped `/v1` and injected identity.
    async fn spawn_echo_upstream() -> String {
        async fn echo(req: Request) -> axum::response::Response {
            let path = req.uri().path().to_string();
            let query = req.uri().query().unwrap_or("").to_string();
            let uid = req
                .headers()
                .get("x-user-id")
                .and_then(|v| v.to_str().ok())
                .unwrap_or("")
                .to_string();
            let role = req
                .headers()
                .get("x-user-role")
                .and_then(|v| v.to_str().ok())
                .unwrap_or("")
                .to_string();
            // Drain the request body before responding. A real backend reads the body; if
            // this handler replied while the client (the gateway via reqwest) was still
            // writing a large body, HTTP/1.1 could reset the connection → a flaky
            // `ProxyError::Upstream` on the multi-MiB carve-out tests.
            let body_len = axum::body::to_bytes(req.into_body(), 64 * 1024 * 1024)
                .await
                .map(|b| b.len())
                .unwrap_or(0);
            let body = serde_json::json!({
                "got_path": path,
                "got_query": query,
                "x_user_id": uid,
                "x_user_role": role,
                "got_body_len": body_len,
            });
            let mut resp = axum::Json(body).into_response();
            resp.headers_mut()
                .insert("x-upstream-marker", HeaderValue::from_static("echo-ok"));
            resp
        }

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app = Router::new().route("/{*rest}", any(echo));
        tokio::spawn(async move {
            let _ = axum::serve(listener, app).await;
        });
        format!("http://{addr}")
    }

    fn gateway_request(method: &str, headers: &[(&str, &str)], body: &str) -> Request {
        let mut b = Request::builder()
            .method(method)
            .uri("http://gateway.local/v1/otp/request");
        for (k, v) in headers {
            b = b.header(*k, *v);
        }
        b.body(Body::from(body.to_string())).unwrap()
    }

    #[tokio::test]
    async fn forward_proxies_body_strips_v1_and_injects_user() {
        let base = spawn_echo_upstream().await;
        let http = reqwest::Client::new();
        let id = Uuid::new_v4();
        let user = VerifiedUser {
            user_id: id,
            role: "guard".to_string(),
        };

        // Client tries to spoof identity; gateway must drop it and inject the verified one.
        let req = gateway_request(
            "POST",
            &[
                ("content-type", "application/json"),
                ("x-user-id", "spoofed"),
                ("x-user-role", "admin"),
            ],
            r#"{"phone":"0812345678"}"#,
        );

        // forward_path is the post-/v1-strip path the router produced.
        let resp = forward(
            &http,
            &base,
            "/otp/request",
            Some("lang=th"),
            req,
            Some(&user),
            MAX_BODY_BYTES,
        )
        .await
        .expect("forward succeeds");

        assert_eq!(resp.status(), StatusCode::OK);
        assert_eq!(
            resp.headers().get("x-upstream-marker").unwrap(),
            "echo-ok",
            "upstream response headers proxied back"
        );

        let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(
            json["got_path"], "/otp/request",
            "/v1 stripped before forward"
        );
        assert_eq!(json["got_query"], "lang=th", "query forwarded");
        assert_eq!(
            json["x_user_id"],
            id.to_string(),
            "trusted X-User-Id injected"
        );
        assert_eq!(json["x_user_role"], "guard", "trusted X-User-Role injected");
        assert_ne!(json["x_user_id"], "spoofed", "client spoof dropped");
    }

    #[tokio::test]
    async fn forward_unreachable_upstream_is_502() {
        let http = reqwest::Client::builder()
            .connect_timeout(std::time::Duration::from_millis(200))
            .build()
            .unwrap();
        // Reserved-for-docs TEST-NET-1 address; connection will fail/time out fast.
        let req = gateway_request("GET", &[], "");
        let res = forward(
            &http,
            "http://192.0.2.1:9",
            "/otp/request",
            None,
            req,
            None,
            MAX_BODY_BYTES,
        )
        .await;
        match res {
            Err(ProxyError::Upstream) => {}
            other => panic!("expected ProxyError::Upstream, got {other:?}"),
        }
        assert_eq!(ProxyError::Upstream.status(), StatusCode::BAD_GATEWAY);
    }

    #[tokio::test]
    async fn forward_rejects_oversized_body() {
        let http = reqwest::Client::new();
        // Body just over the 1 MiB default cap — unchanged behaviour for normal routes.
        let big = "x".repeat(MAX_BODY_BYTES + 1);
        let req = Request::builder()
            .method("POST")
            .uri("http://gateway.local/v1/otp/request")
            .body(Body::from(big))
            .unwrap();
        let res = forward(
            &http,
            "http://127.0.0.1:1",
            "/otp/request",
            None,
            req,
            None,
            MAX_BODY_BYTES,
        )
        .await;
        match res {
            Err(ProxyError::BodyTooLarge) => {}
            other => panic!("expected ProxyError::BodyTooLarge, got {other:?}"),
        }
        assert_eq!(
            ProxyError::BodyTooLarge.status(),
            StatusCode::PAYLOAD_TOO_LARGE
        );
    }

    // ----- per-route body cap (carve-out) -----

    use crate::domain::routing::BodyCap;

    /// The edge default and the WS frame cap must never drift: `BodyCap::Default` is THE
    /// 1 MiB value, and `wsproxy::MAX_CLIENT_FRAME_BYTES` is `proxy::MAX_BODY_BYTES`.
    #[test]
    fn default_body_cap_equals_max_body_bytes() {
        assert_eq!(BodyCap::DEFAULT_BYTES, MAX_BODY_BYTES);
        assert_eq!(BodyCap::Default.bytes(), MAX_BODY_BYTES);
        assert_eq!(BodyCap::Large.bytes(), 12 * 1024 * 1024);
        assert_eq!(BodyCap::Chat.bytes(), 30 * 1024 * 1024);
    }

    /// A 5 MiB body — over the 1 MiB default but under the 12 MiB carve-out — reaches the
    /// upstream when forwarded with the `Large` cap (the check-in / profile upload path).
    #[tokio::test]
    async fn forward_large_cap_admits_body_over_default() {
        let base = spawn_echo_upstream().await;
        let http = reqwest::Client::new();
        let body = "x".repeat(5 * 1024 * 1024);
        let req = Request::builder()
            .method("POST")
            .uri("http://gateway.local/v1/bookings/abc/progress-reports")
            .header("content-type", "application/octet-stream")
            .body(Body::from(body))
            .unwrap();
        let resp = forward(
            &http,
            &base,
            "/bookings/abc/progress-reports",
            None,
            req,
            None,
            BodyCap::Large.bytes(),
        )
        .await
        .expect("5 MiB body under the 12 MiB cap forwards");
        assert_eq!(resp.status(), StatusCode::OK, "upstream received the body");
    }

    /// A 13 MiB body exceeds the `Large` cap → 413 (the single-image carve-out is bounded, not
    /// open). The check-in / profile-upload routes ride this cap.
    #[tokio::test]
    async fn forward_large_cap_still_rejects_over_12mib() {
        let http = reqwest::Client::new();
        let body = "x".repeat(BodyCap::LARGE_BYTES + 1);
        let req = Request::builder()
            .method("POST")
            .uri("http://gateway.local/v1/bookings/abc/progress-reports")
            .body(Body::from(body))
            .unwrap();
        let res = forward(
            &http,
            "http://127.0.0.1:1",
            "/bookings/abc/progress-reports",
            None,
            req,
            None,
            BodyCap::Large.bytes(),
        )
        .await;
        match res {
            Err(ProxyError::BodyTooLarge) => {}
            other => panic!("expected ProxyError::BodyTooLarge, got {other:?}"),
        }
    }

    /// A 13 MiB chat attachment — over the 12 MiB single-image cap but UNDER the 30 MiB chat cap
    /// — now reaches the upstream (the raised cap is the whole point of the bug fix).
    #[tokio::test]
    async fn forward_chat_cap_admits_body_over_12mib() {
        let base = spawn_echo_upstream().await;
        let http = reqwest::Client::new();
        let body = "x".repeat(13 * 1024 * 1024);
        let req = Request::builder()
            .method("POST")
            .uri("http://gateway.local/v1/attachments")
            .header("content-type", "application/octet-stream")
            .body(Body::from(body))
            .unwrap();
        let resp = forward(
            &http,
            &base,
            "/attachments",
            None,
            req,
            None,
            BodyCap::Chat.bytes(),
        )
        .await
        .expect("13 MiB body under the 30 MiB chat cap forwards");
        assert_eq!(resp.status(), StatusCode::OK, "upstream received the body");
    }

    /// A 31 MiB body exceeds even the raised `Chat` cap → 413 (still bounded, not open — kept
    /// well below the chat service's 200 MiB video contract).
    #[tokio::test]
    async fn forward_chat_cap_still_rejects_over_30mib() {
        let http = reqwest::Client::new();
        let body = "x".repeat(BodyCap::CHAT_BYTES + 1);
        let req = Request::builder()
            .method("POST")
            .uri("http://gateway.local/v1/attachments")
            .body(Body::from(body))
            .unwrap();
        let res = forward(
            &http,
            "http://127.0.0.1:1",
            "/attachments",
            None,
            req,
            None,
            BodyCap::Chat.bytes(),
        )
        .await;
        match res {
            Err(ProxyError::BodyTooLarge) => {}
            other => panic!("expected ProxyError::BodyTooLarge, got {other:?}"),
        }
    }
}

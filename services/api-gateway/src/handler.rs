//! The single catch-all edge handler: resolve → rate-limit → auth → proxy.
//!
//! Flow per request (CLAUDE.md "JWT validation at edge, rate limit, route"):
//!   1. [`domain::routing::resolve`] the path → Block (404) / NotFound (404) / Proxy.
//!   2. Per-IP rate limit for the route's tier → 429 + `Retry-After` on exceed
//!      (fail-OPEN on Redis error).
//!   3. For PROTECTED routes, validate the access token at the edge (jti + trv + CSRF).
//!   4. Strip `/v1`, inject trusted `X-User-*`, forward to the upstream; 502 if down.
//!
//! Every error is returned as a generic [`ApiResponse`] envelope (no internal leakage).

use axum::extract::{ConnectInfo, State};
use axum::http::{HeaderMap, HeaderName, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use std::net::SocketAddr;

use shared::error::AppError;
use shared::models::ApiResponse;

use crate::domain::ratelimit::RateDecision;
use crate::domain::routing::{resolve, RouteDecision};
use crate::state::AppState;
use crate::{auth, proxy, ratelimit};

/// Middleware: stamp the fixed [`security_headers`](crate::domain::headers::security_headers)
/// on every response — proxied, gateway-originated error, `/healthz`, and CORS responses
/// alike. Mounted as the OUTERMOST layer so it runs last on the response path. `insert`
/// (not `append`) so a header can't be duplicated/forged from upstream.
pub async fn security_headers_mw(
    request: axum::extract::Request,
    next: axum::middleware::Next,
) -> Response {
    let mut resp = next.run(request).await;
    let headers = resp.headers_mut();
    // `from_static` is infallible: `security_headers()` guarantees lowercase names + valid
    // constant values (asserted by a domain test), so this never panics in the request path.
    for (name, value) in crate::domain::headers::security_headers() {
        headers.insert(
            HeaderName::from_static(name),
            HeaderValue::from_static(value),
        );
    }
    resp
}

/// Build a generic `ApiResponse` error body (`{ success:false, error:"…" }`) with a
/// status. Used for all gateway-originated errors so the edge contract is uniform.
fn err(status: StatusCode, message: &str) -> Response {
    let body = ApiResponse::<()> {
        success: false,
        data: None,
        error: Some(message.to_string()),
    };
    (status, Json(body)).into_response()
}

/// Convert an edge-auth [`AppError`] into an `ApiResponse` error response, preserving
/// its status (401/403) but not its internal detail beyond the safe message.
fn auth_err(e: AppError) -> Response {
    let resp = e.into_response();
    let status = resp.status();
    let msg = match status {
        StatusCode::UNAUTHORIZED => "Unauthorized",
        StatusCode::FORBIDDEN => "Forbidden",
        _ => "Request rejected",
    };
    err(status, msg)
}

/// Catch-all handler mounted on `/{*path}`. Owns the full edge pipeline.
#[tracing::instrument(skip_all, fields(method = %request.method(), path = %request.uri().path()))]
pub async fn gateway(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    request: axum::extract::Request,
) -> Response {
    let method = request.method().clone();
    let uri = request.uri().clone();
    let path = uri.path();
    let query = uri.query();

    // 1. Resolve the route (pure).
    let decision = resolve(path);
    let (upstream, forward_path, public, tier) = match decision {
        // 404 for both Block and NotFound — Block uses 404 (not 403) so the existence
        // of /internal endpoints isn't revealed (ports v1's `return 404`).
        RouteDecision::Block | RouteDecision::NotFound => {
            return err(StatusCode::NOT_FOUND, "Not found");
        }
        RouteDecision::Proxy {
            upstream,
            forward_path,
            public,
            tier,
        } => (upstream, forward_path, public, tier),
    };

    let headers: HeaderMap = request.headers().clone();
    let ip = ratelimit::client_ip(&headers, peer);

    // 2. Per-IP rate limit (fail-OPEN on Redis error).
    {
        let mut redis = state.redis_conn.clone();
        if let RateDecision::Deny { retry_after_secs } =
            ratelimit::check(&mut redis, &state.limits, tier, &ip).await
        {
            let mut resp = err(StatusCode::TOO_MANY_REQUESTS, "Rate limit exceeded");
            if let Ok(v) = HeaderValue::from_str(&retry_after_secs.to_string()) {
                resp.headers_mut().insert("retry-after", v);
            }
            return resp;
        }
    }

    // 3. Edge auth for protected routes (jti + trv + CSRF). Public routes skip this.
    let user = if public {
        None
    } else {
        let mut redis = state.redis_conn.clone();
        match auth::validate(&headers, &method, &state.jwt_config, &mut redis).await {
            Ok(u) => Some(u),
            Err(e) => return auth_err(e),
        }
    };

    // 4. Forward (strip /v1 already done by `resolve`; identity injected in proxy).
    let Some(base_url) = state.routes.base_url(upstream) else {
        // Should never happen — UpstreamTable inserts every variant. Treat as 502.
        tracing::error!(upstream = upstream.as_str(), "no base URL for upstream");
        return err(StatusCode::BAD_GATEWAY, "Upstream service unavailable");
    };

    match proxy::forward(
        &state.http,
        base_url,
        &forward_path,
        query,
        request,
        user.as_ref(),
    )
    .await
    {
        Ok(resp) => resp,
        Err(pe) => err(pe.status(), pe.message()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn err_builds_apiresponse_envelope() {
        let resp = err(StatusCode::NOT_FOUND, "Not found");
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn err_body_has_success_false_and_error() {
        let resp = err(StatusCode::TOO_MANY_REQUESTS, "Rate limit exceeded");
        let body = axum::body::to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(json["success"], false);
        assert_eq!(json["error"], "Rate limit exceeded");
    }

    #[test]
    fn auth_err_maps_unauthorized_to_401() {
        let resp = auth_err(AppError::Unauthorized("x".into()));
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    }

    #[test]
    fn auth_err_maps_forbidden_to_403() {
        let resp = auth_err(AppError::Forbidden("x".into()));
        assert_eq!(resp.status(), StatusCode::FORBIDDEN);
    }

    // ----- security headers land on EVERY response (incl. errors) -----

    #[tokio::test]
    async fn security_headers_mw_stamps_ok_and_error_responses() {
        async fn ok() -> &'static str {
            "ok"
        }
        let app = Router::new()
            .route("/ok", any_route(ok))
            .layer(axum::middleware::from_fn(security_headers_mw));

        // 200 path — all expected headers present with hardened values.
        let resp = app
            .clone()
            .oneshot(
                AxumRequest::builder()
                    .uri("/ok")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        assert_eq!(resp.headers().get("x-frame-options").unwrap(), "DENY");
        assert_eq!(
            resp.headers().get("x-content-type-options").unwrap(),
            "nosniff"
        );
        assert!(resp.headers().contains_key("content-security-policy"));
        assert!(resp.headers().contains_key("strict-transport-security"));

        // 404 path (no matching route) — headers must STILL be stamped on the error response.
        let resp404 = app
            .oneshot(
                AxumRequest::builder()
                    .uri("/nope")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp404.status(), StatusCode::NOT_FOUND);
        assert_eq!(resp404.headers().get("x-frame-options").unwrap(), "DENY");
    }

    // ----- full-pipeline integration (Redis-gated) -----
    //
    // Drives a request THROUGH the gateway router (route resolve → rate limit → edge
    // auth → proxy) against an ephemeral in-process upstream. Redis-gated: skips when
    // TEST_REDIS_URL / REDIS_CACHE_URL is unset (hermetic default).

    use axum::body::Body;
    use axum::extract::Request as AxumRequest;
    use axum::routing::any as any_route;
    use axum::Router;
    use jsonwebtoken::EncodingKey;
    use redis::AsyncCommands;
    use std::net::SocketAddr;
    use tower::ServiceExt; // oneshot
    use uuid::Uuid;

    const TEST_SECRET: &str = "test-secret-key-at-least-64-chars-long-for-testing-purposes-only!!";

    async fn spawn_echo_upstream() -> String {
        async fn echo(req: AxumRequest) -> axum::response::Response {
            let path = req.uri().path().to_string();
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
            axum::Json(serde_json::json!({
                "got_path": path, "x_user_id": uid, "x_user_role": role,
            }))
            .into_response()
        }
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app = Router::new().route("/{*rest}", any_route(echo));
        tokio::spawn(async move {
            let _ = axum::serve(listener, app).await;
        });
        format!("http://{addr}")
    }

    fn build_test_state(redis: redis::aio::MultiplexedConnection, booking_url: &str) -> AppState {
        use shared::config::JwtConfig;
        let jwt_config = JwtConfig {
            secret: TEST_SECRET.to_string(),
            expiry_minutes: 15,
            encoding_key: EncodingKey::from_secret(TEST_SECRET.as_bytes()),
            decoding_key: jsonwebtoken::DecodingKey::from_secret(TEST_SECRET.as_bytes()),
        };
        // Point the booking upstream at the echo server; other upstreams keep defaults.
        // No process-env mutation (avoids races between parallel tests).
        let routes = crate::state::UpstreamTable::from_env()
            .with_override(crate::domain::routing::Upstream::Booking, booking_url);

        AppState {
            http: reqwest::Client::new(),
            redis_conn: redis,
            jwt_config,
            routes,
            // High limits so the test isn't throttled.
            limits: crate::domain::ratelimit::Limits {
                otp_per_min: 10_000,
                auth_per_sec: 10_000,
                api_per_sec: 10_000,
            },
            status_tx: tokio::sync::broadcast::channel(16).0,
            allowed_origins: std::sync::Arc::from(vec!["http://localhost:3000".to_string()]),
        }
    }

    fn test_router(state: AppState) -> Router {
        // Mirrors main.rs's router shape: catch-all on the gateway handler. (The real
        // /healthz route is gateway-owned and not exercised here.)
        Router::new()
            .route("/{*path}", any_route(gateway))
            .with_state(state)
    }

    #[tokio::test]
    async fn full_pipeline_protected_route_strips_v1_and_injects_user() {
        let Ok(redis_url) =
            std::env::var("TEST_REDIS_URL").or_else(|_| std::env::var("REDIS_CACHE_URL"))
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let conn = redis::Client::open(redis_url)
            .unwrap()
            .get_multiplexed_tokio_connection()
            .await
            .unwrap();

        let upstream = spawn_echo_upstream().await;
        let state = build_test_state(conn.clone(), &upstream);

        // Mint a valid access token for a protected route (/v1/bookings → booking).
        let user_id = Uuid::new_v4();
        let ek = EncodingKey::from_secret(TEST_SECRET.as_bytes());
        let (token, _jti) =
            shared::auth::encode_jwt_with_key(user_id, "customer", 0, &ek, 60).unwrap();
        // Ensure no stale trv marker.
        let mut c = conn.clone();
        let _: () = c.del(format!("user_trv:{user_id}")).await.unwrap();

        let req = AxumRequest::builder()
            .method("GET")
            .uri("/v1/bookings/abc")
            .header("authorization", format!("Bearer {token}"))
            // Client spoof attempt must be stripped.
            .header("x-user-id", "spoofed")
            .header("x-user-role", "admin")
            .body(Body::empty())
            .unwrap();

        let router = test_router(state);
        let resp = router.oneshot(with_connect_info(req)).await.unwrap();

        assert_eq!(resp.status(), StatusCode::OK, "protected route proxied");
        let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(json["got_path"], "/bookings/abc", "/v1 stripped end-to-end");
        assert_eq!(
            json["x_user_id"],
            user_id.to_string(),
            "verified id injected"
        );
        assert_eq!(json["x_user_role"], "customer", "verified role injected");

        let _: () = c.del(format!("user_trv:{user_id}")).await.unwrap();
    }

    #[tokio::test]
    async fn full_pipeline_protected_route_without_token_is_401() {
        let Ok(redis_url) =
            std::env::var("TEST_REDIS_URL").or_else(|_| std::env::var("REDIS_CACHE_URL"))
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let conn = redis::Client::open(redis_url)
            .unwrap()
            .get_multiplexed_tokio_connection()
            .await
            .unwrap();
        let upstream = spawn_echo_upstream().await;
        let router = test_router(build_test_state(conn, &upstream));

        let req = AxumRequest::builder()
            .method("GET")
            .uri("/v1/bookings/abc")
            .body(Body::empty())
            .unwrap();
        let resp = router.oneshot(with_connect_info(req)).await.unwrap();
        assert_eq!(
            resp.status(),
            StatusCode::UNAUTHORIZED,
            "no token → 401 at edge"
        );
    }

    #[tokio::test]
    async fn internal_path_is_404_through_router() {
        // Pure-routable, no Redis needed beyond state construction — but state needs a
        // Redis conn, so gate this too for consistency.
        let Ok(redis_url) =
            std::env::var("TEST_REDIS_URL").or_else(|_| std::env::var("REDIS_CACHE_URL"))
        else {
            eprintln!("SKIP: no TEST_REDIS_URL/REDIS_CACHE_URL (hermetic default)");
            return;
        };
        let conn = redis::Client::open(redis_url)
            .unwrap()
            .get_multiplexed_tokio_connection()
            .await
            .unwrap();
        let upstream = spawn_echo_upstream().await;
        let router = test_router(build_test_state(conn, &upstream));

        let req = AxumRequest::builder()
            .method("POST")
            .uri("/v1/notifications/internal/push")
            .body(Body::empty())
            .unwrap();
        let resp = router.oneshot(with_connect_info(req)).await.unwrap();
        assert_eq!(
            resp.status(),
            StatusCode::NOT_FOUND,
            "/internal blocked at edge (404, not 403)"
        );
    }

    /// Inject a `ConnectInfo<SocketAddr>` extension so the handler's `ConnectInfo`
    /// extractor resolves under `oneshot` (which doesn't run the connect-info layer).
    fn with_connect_info(mut req: AxumRequest) -> AxumRequest {
        let addr: SocketAddr = "127.0.0.1:12345".parse().unwrap();
        req.extensions_mut()
            .insert(axum::extract::ConnectInfo(addr));
        req
    }
}

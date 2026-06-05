//! Cross-service data-export client (PDPA §19 access / §32 portability).
//!
//! identity owns no business data — it ORCHESTRATES. This client mints a short-lived
//! service-JWT and concurrently GETs each data owner's `/internal/users/{id}/export`
//! (profile, booking, payment, rating), returning a per-section result. Mirrors booking's
//! `discovery_client`: concurrent, order-preserving, and **best-effort** — a failing
//! downstream yields a `null` section marked `"error"` so one outage never blanks the whole
//! export (PDPA: the user should still get what's retrievable). Trace context propagates via
//! `observability::trace_headers` (C5.1), so the fan-out is one trace.

use futures::stream::{self, StreamExt};
use jsonwebtoken::EncodingKey;
use serde::Deserialize;
use serde_json::Value;
use uuid::Uuid;

use shared::service_jwt::encode_service_jwt;

/// Max concurrent in-flight section fetches.
const FANOUT_CONCURRENCY: usize = 4;

/// A data-owning upstream exposing `GET /internal/users/{id}/export`.
#[derive(Clone)]
pub struct ExportUpstream {
    /// Section key in the export envelope, e.g. `"profile"`, `"bookings"`.
    pub section: &'static str,
    /// Base URL (no trailing slash), e.g. `http://profile:3002`.
    pub base_url: String,
}

/// One section's outcome. `data` is the service's payload (or `Value::Null` on failure);
/// `status` is `"ok"` or `"error"` for `_meta.sections`.
pub struct Section {
    pub name: &'static str,
    pub data: Value,
    pub status: &'static str,
}

/// Deserialize side of each service's `{ success, data }` envelope.
#[derive(Deserialize)]
struct Envelope {
    data: Option<Value>,
}

/// Mints service-JWTs and fans out to the data owners' internal export reads. Cloneable
/// (held in `AppState`); `reqwest::Client` is internally ref-counted + connection-pooled.
#[derive(Clone)]
pub struct ExportClient {
    http: reqwest::Client,
    service_encoding_key: EncodingKey,
    service_ttl_secs: i64,
    upstreams: Vec<ExportUpstream>,
}

impl ExportClient {
    pub fn new(
        http: reqwest::Client,
        service_encoding_key: EncodingKey,
        service_ttl_secs: i64,
        upstreams: Vec<ExportUpstream>,
    ) -> Self {
        Self {
            http,
            service_encoding_key,
            service_ttl_secs,
            upstreams,
        }
    }

    /// Concurrently fetch every section for `user_id`. Order-preserving + best-effort: a
    /// section that can't be fetched comes back `null`/`"error"` rather than failing the set.
    pub async fn collect(&self, user_id: Uuid) -> Vec<Section> {
        // One service-JWT for the whole fan-out (short-lived; the export is one operation).
        let token = match encode_service_jwt(
            "identity",
            &self.service_encoding_key,
            self.service_ttl_secs,
        ) {
            Ok(t) => t,
            Err(e) => {
                tracing::error!("data-export: could not mint service token: {e}");
                return self
                    .upstreams
                    .iter()
                    .map(|u| Section {
                        name: u.section,
                        data: Value::Null,
                        status: "error",
                    })
                    .collect();
            }
        };
        let trace = observability::trace_headers();

        stream::iter(self.upstreams.clone())
            .map(|u| {
                let http = self.http.clone();
                let token = token.clone();
                let trace = trace.clone();
                async move {
                    let url = format!("{}/internal/users/{user_id}/export", u.base_url);
                    let result = http
                        .get(&url)
                        .headers(trace)
                        .header("Authorization", format!("Bearer {token}"))
                        .send()
                        .await;
                    match result {
                        Ok(resp) if resp.status().is_success() => {
                            match resp.json::<Envelope>().await {
                                Ok(env) => Section {
                                    name: u.section,
                                    data: env.data.unwrap_or(Value::Null),
                                    status: "ok",
                                },
                                Err(e) => {
                                    tracing::warn!(
                                        section = u.section,
                                        "data-export decode error: {e}"
                                    );
                                    Section {
                                        name: u.section,
                                        data: Value::Null,
                                        status: "error",
                                    }
                                }
                            }
                        }
                        Ok(resp) => {
                            tracing::warn!(
                                section = u.section,
                                status = %resp.status(),
                                "data-export upstream non-success"
                            );
                            Section {
                                name: u.section,
                                data: Value::Null,
                                status: "error",
                            }
                        }
                        Err(e) => {
                            tracing::warn!(section = u.section, "data-export transport error: {e}");
                            Section {
                                name: u.section,
                                data: Value::Null,
                                status: "error",
                            }
                        }
                    }
                }
            })
            .buffered(FANOUT_CONCURRENCY)
            .collect()
            .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::routing::get;
    use axum::Json;
    use jsonwebtoken::EncodingKey;

    /// Spin a tiny in-process upstream that replies with `{ success, data }` (200) or a 500.
    async fn spawn_upstream(ok: bool) -> String {
        let app = axum::Router::new().route(
            "/internal/users/{user_id}/export",
            get(move || async move {
                if ok {
                    Json(serde_json::json!({ "success": true, "data": { "hello": "world" } }))
                        .into_response()
                } else {
                    (axum::http::StatusCode::INTERNAL_SERVER_ERROR, "boom").into_response()
                }
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            let _ = axum::serve(listener, app).await;
        });
        format!("http://{addr}")
    }

    use axum::response::IntoResponse;

    /// The core aggregator contract: fan-out is ORDER-PRESERVING and BEST-EFFORT — a healthy
    /// section is `ok` with data, a 5xx section and an unreachable section are each `error`
    /// with null data, and one failure never blanks the others.
    #[tokio::test]
    async fn collect_is_order_preserving_and_best_effort() {
        let ok_url = spawn_upstream(true).await;
        let err_url = spawn_upstream(false).await;
        // Reserved TEST-NET-1 — connection fails fast → transport error section.
        let dead_url = "http://192.0.2.1:9".to_string();

        let client = ExportClient::new(
            reqwest::Client::builder()
                .connect_timeout(std::time::Duration::from_millis(200))
                .build()
                .unwrap(),
            EncodingKey::from_secret(b"test-secret"),
            60,
            vec![
                ExportUpstream {
                    section: "profile",
                    base_url: ok_url,
                },
                ExportUpstream {
                    section: "bookings",
                    base_url: err_url,
                },
                ExportUpstream {
                    section: "payments",
                    base_url: dead_url,
                },
            ],
        );

        let sections = client.collect(Uuid::new_v4()).await;
        let names: Vec<&str> = sections.iter().map(|s| s.name).collect();
        assert_eq!(
            names,
            ["profile", "bookings", "payments"],
            "order preserved"
        );
        assert_eq!(sections[0].status, "ok");
        assert_eq!(sections[0].data["hello"], "world");
        assert_eq!(sections[1].status, "error", "5xx → degraded");
        assert!(sections[1].data.is_null());
        assert_eq!(sections[2].status, "error", "unreachable → degraded");
        assert!(sections[2].data.is_null());
    }
}

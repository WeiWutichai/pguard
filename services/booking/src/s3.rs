//! S3/MinIO object store — upload + presigned download, with our OWN AWS SigV4 (query-string)
//! presigner over `reqwest`. Ported from `services/chat/src/s3.rs` (the house S3 pattern) for
//! check-in photos; extracting a shared crate is a noted follow-up, duplication is deliberate
//! for this slice (PHASE spec §B4). This avoids pulling the heavy `aws-sdk-s3` tree; the
//! workspace lists `reqwest` + `sha2` + `hmac` precisely for these signed URLs.
//!
//! Why presign per-host (no post-hoc host rewrite): a SigV4 presigned URL signs the `host`
//! header, so the URL MUST be hit on the same host it was signed for. We therefore sign UPLOADS
//! against the INTERNAL endpoint (the server reaches MinIO internally) and DOWNLOAD URLs against
//! the PUBLIC endpoint (the client reaches MinIO publicly) — never a `replacen` that would break
//! the signature (a v1 footgun). The bucket/credentials are never exposed; clients only ever see
//! a short-lived (1h) signed GET URL.
//!
//! Path-style addressing (`{endpoint}/{bucket}/{key}`) — MinIO's default and R2-compatible.

use chrono::{DateTime, Utc};
use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};

use shared::error::AppError;

/// Presigned download URL lifetime — 1 hour (CLAUDE.md / spec).
pub const DOWNLOAD_TTL_SECS: u64 = 3600;
/// Presigned upload URL lifetime — short; the server uses it immediately.
const UPLOAD_TTL_SECS: u64 = 300;

const ALGORITHM: &str = "AWS4-HMAC-SHA256";
const SERVICE: &str = "s3";
/// Presigned PUT/GET sign the payload as UNSIGNED so we don't hash the whole body.
const UNSIGNED_PAYLOAD: &str = "UNSIGNED-PAYLOAD";

type HmacSha256 = Hmac<Sha256>;

/// S3/MinIO client config + the SigV4 presigner. Cheap to clone (held in `AppState`).
#[derive(Clone)]
pub struct S3Client {
    http: reqwest::Client,
    /// Internal endpoint the server uses to PUT objects, e.g. `http://localhost:9000`.
    endpoint: String,
    /// Public endpoint clients use for GET, e.g. `https://cdn.pguard.app`. Falls back to
    /// `endpoint` when unset (single-host dev).
    public_endpoint: String,
    bucket: String,
    region: String,
    access_key: String,
    secret_key: String,
}

impl S3Client {
    pub fn new(
        http: reqwest::Client,
        endpoint: String,
        public_endpoint: Option<String>,
        bucket: String,
        region: String,
        access_key: String,
        secret_key: String,
    ) -> Self {
        let endpoint = endpoint.trim_end_matches('/').to_string();
        let public_endpoint = public_endpoint
            .map(|s| s.trim_end_matches('/').to_string())
            .unwrap_or_else(|| endpoint.clone());
        Self {
            http,
            endpoint,
            public_endpoint,
            bucket,
            region,
            access_key,
            secret_key,
        }
    }

    /// Upload `data` to `key` (server → MinIO over the internal endpoint). Uses a short-lived
    /// presigned PUT so the body is sent unsigned (no full-body hash).
    pub async fn upload(
        &self,
        key: &str,
        data: Vec<u8>,
        content_type: &str,
    ) -> Result<(), AppError> {
        let url = self.presign(&self.endpoint, "PUT", key, UPLOAD_TTL_SECS, Utc::now());
        let resp = self
            .http
            .put(&url)
            .header(reqwest::header::CONTENT_TYPE, content_type)
            .body(data)
            .send()
            .await
            .map_err(|e| {
                // `without_url()` — reqwest's Display embeds the request URL, which here is
                // a LIVE presigned PUT (signature included); never log it.
                tracing::warn!("S3 upload transport error: {}", e.without_url());
                AppError::Internal("check-in photo upload failed".to_string())
            })?;
        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            tracing::warn!("S3 upload returned {status}: {body}");
            return Err(AppError::Internal(
                "check-in photo upload failed".to_string(),
            ));
        }
        Ok(())
    }

    /// Best-effort delete of `key` — compensation when the post-upload DB insert fails
    /// (e.g. a concurrent duplicate-hour race), so rejected check-ins don't accumulate
    /// orphaned objects. Booking EXTENSION over the chat original (chat never deletes).
    /// Errors are logged, never returned: an orphaned object is acceptable, failing the
    /// caller's (already-failed) request differently is not.
    pub async fn delete_best_effort(&self, key: &str) {
        let url = self.presign(&self.endpoint, "DELETE", key, UPLOAD_TTL_SECS, Utc::now());
        match self.http.delete(&url).send().await {
            // 404 = already gone — fine for a best-effort compensation.
            Ok(resp)
                if resp.status().is_success()
                    || resp.status() == reqwest::StatusCode::NOT_FOUND => {}
            Ok(resp) => {
                tracing::warn!(status = %resp.status(), key, "S3 best-effort delete failed (orphaned object)");
            }
            Err(e) => {
                tracing::warn!(
                    key,
                    "S3 best-effort delete transport error: {}",
                    e.without_url()
                );
            }
        }
    }

    /// A fresh presigned GET URL (TTL 1h) for `key`, signed against the PUBLIC endpoint so the
    /// client can hit it directly. Never exposes credentials/bucket beyond the signed URL.
    pub fn download_url(&self, key: &str) -> String {
        self.presign(
            &self.public_endpoint,
            "GET",
            key,
            DOWNLOAD_TTL_SECS,
            Utc::now(),
        )
    }

    /// Build an AWS SigV4 query-string presigned URL for `method` on `key`, signed for `base`'s
    /// host. Deterministic given `now` (so the signing path is unit-testable). Path-style.
    fn presign(
        &self,
        base: &str,
        method: &str,
        key: &str,
        expires: u64,
        now: DateTime<Utc>,
    ) -> String {
        let host = host_of(base);
        let amz_date = now.format("%Y%m%dT%H%M%SZ").to_string();
        let date = now.format("%Y%m%d").to_string();
        let scope = format!("{date}/{}/{SERVICE}/aws4_request", self.region);

        // Canonical URI (path-style): /{bucket}/{key} — '/' preserved, each component encoded.
        let canonical_uri = format!(
            "/{}/{}",
            uri_encode(&self.bucket, false),
            uri_encode(key, false)
        );

        // Canonical query — params sorted by key (already in alpha order below). Values are
        // uri-encoded (the '/' inside the credential becomes %2F).
        let credential = format!("{}/{scope}", self.access_key);
        let pairs = [
            ("X-Amz-Algorithm", ALGORITHM.to_string()),
            ("X-Amz-Credential", credential),
            ("X-Amz-Date", amz_date.clone()),
            ("X-Amz-Expires", expires.to_string()),
            ("X-Amz-SignedHeaders", "host".to_string()),
        ];
        let canonical_query = pairs
            .iter()
            .map(|(k, v)| format!("{}={}", uri_encode(k, true), uri_encode(v, true)))
            .collect::<Vec<_>>()
            .join("&");

        // Canonical request (host is the only signed header; payload is UNSIGNED).
        let canonical_request = format!(
            "{method}\n{canonical_uri}\n{canonical_query}\nhost:{host}\n\nhost\n{UNSIGNED_PAYLOAD}"
        );

        let string_to_sign = format!(
            "{ALGORITHM}\n{amz_date}\n{scope}\n{}",
            hex(&sha256(canonical_request.as_bytes()))
        );

        let signing_key = signing_key(&self.secret_key, &date, &self.region, SERVICE);
        let signature = hex(&hmac(&signing_key, string_to_sign.as_bytes()));

        format!("{base}{canonical_uri}?{canonical_query}&X-Amz-Signature={signature}")
    }
}

/// Extract `host[:port]` from a `scheme://host[:port][/...]` base URL (for the signed `host`
/// header). Defensive: returns the input minus scheme if no path follows.
fn host_of(base: &str) -> &str {
    let no_scheme = base
        .strip_prefix("https://")
        .or_else(|| base.strip_prefix("http://"))
        .unwrap_or(base);
    match no_scheme.find('/') {
        Some(i) => &no_scheme[..i],
        None => no_scheme,
    }
}

/// AWS `UriEncode`: unreserved (`A-Za-z0-9-._~`) pass through; `/` passes through when
/// `encode_slash` is false (canonical path); everything else is `%XX` (uppercase, per UTF-8 byte).
fn uri_encode(input: &str, encode_slash: bool) -> String {
    let mut out = String::with_capacity(input.len());
    for &b in input.as_bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                out.push(b as char)
            }
            b'/' if !encode_slash => out.push('/'),
            _ => {
                out.push('%');
                out.push(HEX[(b >> 4) as usize] as char);
                out.push(HEX[(b & 0xf) as usize] as char);
            }
        }
    }
    out
}

const HEX: &[u8; 16] = b"0123456789ABCDEF";

fn sha256(data: &[u8]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(data);
    h.finalize().into()
}

fn hmac(key: &[u8], msg: &[u8]) -> Vec<u8> {
    // SigV4 keys are always valid lengths for HMAC; `new_from_slice` only errors on impossible
    // key sizes, so an expect here is a true invariant (never the request path's fault).
    let mut mac = HmacSha256::new_from_slice(key).expect("HMAC accepts any key length");
    mac.update(msg);
    mac.finalize().into_bytes().to_vec()
}

/// SigV4 signing key: HMAC chain `"AWS4"+secret → date → region → service → "aws4_request"`.
fn signing_key(secret: &str, date: &str, region: &str, service: &str) -> Vec<u8> {
    let k_date = hmac(format!("AWS4{secret}").as_bytes(), date.as_bytes());
    let k_region = hmac(&k_date, region.as_bytes());
    let k_service = hmac(&k_region, service.as_bytes());
    hmac(&k_service, b"aws4_request")
}

/// Lowercase hex encoding.
fn hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        s.push(HEX[(b >> 4) as usize].to_ascii_lowercase() as char);
        s.push(HEX[(b & 0xf) as usize].to_ascii_lowercase() as char);
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn client() -> S3Client {
        S3Client::new(
            reqwest::Client::new(),
            "http://localhost:9000".to_string(),
            Some("https://cdn.pguard.app".to_string()),
            "pguard".to_string(),
            "us-east-1".to_string(),
            "AKIAEXAMPLE".to_string(),
            "secretkeyexample".to_string(),
        )
    }

    // ----- crypto known-answer tests (prove the SigV4 primitives) -----

    #[test]
    fn sha256_empty_known_answer() {
        // The canonical sha256("") test vector.
        assert_eq!(
            hex(&sha256(b"")),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
    }

    #[test]
    fn signing_key_matches_aws_documented_vector() {
        // AWS SigV4 docs "Examples of deriving a signing key" — the canonical known answer.
        let key = signing_key(
            "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            "20150830",
            "us-east-1",
            "iam",
        );
        assert_eq!(
            hex(&key),
            "c4afb1cc5771d871763a393e44b703571b55cc28424d1a5e86da6ed3c154a4b9"
        );
    }

    // ----- uri_encode (AWS rules) -----

    #[test]
    fn uri_encode_rules() {
        assert_eq!(uri_encode("abcXYZ09-._~", true), "abcXYZ09-._~"); // unreserved untouched
        assert_eq!(uri_encode("a/b", true), "a%2Fb"); // slash encoded in query
        assert_eq!(uri_encode("a/b", false), "a/b"); // slash preserved in path
        assert_eq!(uri_encode("a b", true), "a%20b"); // space
        assert_eq!(uri_encode("/", true), "%2F");
    }

    #[test]
    fn host_extraction() {
        assert_eq!(host_of("http://localhost:9000"), "localhost:9000");
        assert_eq!(host_of("https://cdn.pguard.app"), "cdn.pguard.app");
        assert_eq!(host_of("http://minio:9000/bucket/key"), "minio:9000");
    }

    // ----- presign structure + determinism -----

    #[test]
    fn presigned_url_has_required_sigv4_params() {
        let c = client();
        let now = Utc.with_ymd_and_hms(2026, 6, 10, 12, 0, 0).unwrap();
        let url = c.presign(
            &c.public_endpoint,
            "GET",
            "booking/abc/checkins/def.jpg",
            DOWNLOAD_TTL_SECS,
            now,
        );

        assert!(url.starts_with("https://cdn.pguard.app/pguard/booking/abc/checkins/def.jpg?"));
        assert!(url.contains("X-Amz-Algorithm=AWS4-HMAC-SHA256"));
        assert!(url.contains("X-Amz-Expires=3600"));
        assert!(url.contains("X-Amz-SignedHeaders=host"));
        // Credential's slashes are encoded (%2F), so it must contain the encoded scope.
        assert!(
            url.contains("X-Amz-Credential=AKIAEXAMPLE%2F20260610%2Fus-east-1%2Fs3%2Faws4_request")
        );
        assert!(url.contains("X-Amz-Date=20260610T120000Z"));
        // 64-hex-char signature appended last.
        let sig = url.rsplit("X-Amz-Signature=").next().unwrap();
        assert_eq!(sig.len(), 64, "signature is 64 lowercase hex chars");
        assert!(sig.chars().all(|ch| ch.is_ascii_hexdigit()));
    }

    #[test]
    fn presign_is_deterministic_for_fixed_time() {
        let c = client();
        let now = Utc.with_ymd_and_hms(2026, 6, 10, 12, 0, 0).unwrap();
        let a = c.presign(&c.endpoint, "GET", "booking/x/checkins/y.png", 3600, now);
        let b = c.presign(&c.endpoint, "GET", "booking/x/checkins/y.png", 3600, now);
        assert_eq!(a, b, "same inputs → identical signature");
    }

    #[test]
    fn presign_signs_for_the_target_host() {
        // GET signs/points at the public host; PUT (upload) at the internal host.
        let c = client();
        let now = Utc.with_ymd_and_hms(2026, 6, 10, 12, 0, 0).unwrap();
        let get = c.presign(
            &c.public_endpoint,
            "GET",
            "booking/x/checkins/y.png",
            3600,
            now,
        );
        let put = c.presign(&c.endpoint, "PUT", "booking/x/checkins/y.png", 300, now);
        assert!(get.starts_with("https://cdn.pguard.app/"));
        assert!(put.starts_with("http://localhost:9000/"));
        // Different host + method ⇒ different signature.
        let gsig = get.rsplit("X-Amz-Signature=").next().unwrap();
        let psig = put.rsplit("X-Amz-Signature=").next().unwrap();
        assert_ne!(gsig, psig);
    }

    #[test]
    fn download_url_uses_public_endpoint() {
        let c = client();
        let url = c.download_url("booking/abc/checkins/def.jpg");
        assert!(url.starts_with("https://cdn.pguard.app/pguard/booking/abc/checkins/def.jpg?"));
        assert!(
            !url.contains("localhost:9000"),
            "client URL must not leak the internal host"
        );
    }
}

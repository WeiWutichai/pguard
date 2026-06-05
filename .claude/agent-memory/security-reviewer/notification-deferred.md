# Deferred security follow-ups (surfaced during the notification slice review, 2026-06-04)

Notification slice (`feat/v2-scaffold-notification`) was **✅ cleared** — internal push is
service-JWT'd (closes v1 risk #9) and the event consumer replaces v1 cross-schema writes
(Issue C1). The items below are deliberate deferrals; re-raise them when the named phase lands.

- **Per-caller `sub` allowlist on `/internal/*` (Phase 3, when payment/identity mint tokens).**
  `ServiceCaller` (`packages/shared-rust/src/service_jwt.rs`) authenticates but does not
  authorize *which* service may call an endpoint. Today all internal services share one
  `SERVICE_JWT_SECRET`, so any valid token can push to any `user_id`. Once multiple services
  mint tokens, add a per-endpoint allowed-callers check (e.g. accept only `booking-service`).

- **jti revocation fails OPEN on Redis outage (revisit in the identity phase).**
  `auth.rs` does `redis.exists(...).unwrap_or(false)` — if Redis is down, a revoked token is
  treated as valid (force-revoke, v1 risk #1, silently degrades). Low impact for notification
  (no money/PII mutation); for identity/payment consider fail-closed or alert on Redis miss-rate.

- **`notification.processed_events` has no retention/TTL.** Idempotency ledger grows one row
  per event forever. Add a partition/prune job before it becomes a storage DoS (years out).

- **Rate limiting deferred to the gateway phase.** No app-layer limit on `POST /tokens` or
  `/notifications/send`; api-gateway is still a `/healthz` stub and there is no nginx config yet.
  Re-raise when the gateway/rate-limit work starts (v1 gaps #4/#5 patterns).

- **Observability:** OTLP export to the collector is not wired yet (only `tracing-subscriber`
  fmt). Spans now exist on the consumer (`handle_event`) + DB tx (`process_event`) carrying
  `correlation_id`; wire the OTLP exporter in `packages/observability` before Phase 2 so
  booking→NATS→notification traces reach Tempo.

# Phase 1 / KICKOFF §2.4 — Notification vertical slice (work spec)

> For Claude Code. Build the **notification** service as the first real v2 slice.
> Port from v1 (`../guard-dispatch/services/notification/`, read-only) and apply the
> v2 improvements below. Contract already exists: `contracts/openapi/notification.yaml`,
> `contracts/asyncapi/events.yaml`, `contracts/db/migrations/notification/0001_init.sql`.

## Goal

Decouple notifications (the core of Phase 1): other services **no longer** write the
notification schema directly (v1 Issue C1) nor call an unauthenticated `/internal/push`.
Instead notification **subscribes to `pguard.events.*`** and generates its own
notifications + FCM pushes, and any direct push path is **service-JWT authenticated**.

## Layering (per CLAUDE.md — enforce strictly)

```
services/notification/src/
├── main.rs      wiring only (router, state, NATS consumer spawn, OTel init)
├── api/         thin Axum handlers (transport only)
├── domain/      PURE logic, 100% unit-testable — event→notification mapping, dedupe keys
├── repo/        SQLx queries (the ONLY place that touches notification schema)
├── events/      NATS JetStream subscribe + (if needed) emit via outbox
└── models.rs    DTOs
```
`domain/` must have **no DB/HTTP imports**.

## Endpoints to port (from v1 routes)

Keep behaviour, move into `api/` + `repo/`:
- `POST /tokens` register FCM token · `DELETE /tokens` unregister
- `GET /notifications` (`?unread_only&limit&offset`) · `GET /notifications/unread-count`
- `PUT /notifications/read-all` · `PUT /notifications/{id}/read`
- `POST /notifications/send` (admin)
- **Route order:** register `unread-count` and `read-all` **before** `{id}/read` (Axum match order — v1 footgun).

## v2 improvements (the point of this slice)

1. **Service-JWT on the internal push path.** v1's `/internal/push` had **no auth**.
   Use `shared-rust::service_jwt::ServiceCaller` extractor to require a valid
   `sub="<svc>-service"`, `aud="pguard-internal"` token. Reject otherwise (401).
2. **Event-driven generation (replaces cross-schema writes).** Add a durable
   JetStream consumer subscribing to the topics in `events.yaml`. Map each event →
   a `notification_logs` row + FCM push. Port the v1 trigger set (each becomes an
   event consumer, not a direct INSERT by booking):
   - `booking.job_accepted` → customer "เจ้าหน้าที่ตอบรับแล้ว"
   - `booking.declined` → customer "เจ้าหน้าที่ปฏิเสธงาน"
   - `booking.guard_en_route` → customer "กำลังเดินทาง" · `booking.arrived` → "ถึงแล้ว"
   - `booking.completed` → guard "งานเสร็จสมบูรณ์"
   - `payment.completed` → guard "ชำระเงินสำเร็จ"
   - `rating.submitted` → guard "คะแนนรีวิวใหม่"
   - (tip/assigned/created map similarly — mirror v1's 10 trigger points)
3. **Idempotent consumer.** Use the event `event_id` as an idempotency key
   (unique constraint or dedupe table) so at-least-once delivery can't double-notify.
4. **Transactional outbox** for anything notification itself emits (likely none now —
   wire the pattern even if the table is empty, so later services reuse it).
5. **FCM config fail-fast** — port `FcmConfig::from_env()`; error on missing env, never
   default to `"not-set"`.
6. **OTel span** per request + per event-handler + per DB transaction.

## Don't

- ❌ No direct INSERT into another service's schema; ❌ no unauth internal endpoint;
- ❌ no `.unwrap()`/`.expect()` in the request or consumer path (startup-only);
- ❌ don't edit `../guard-dispatch/`; ❌ don't copy v1 files in — re-implement.

## Definition of Done

- `cargo build -p notification` + `cargo clippy -p notification -D warnings` clean
- Unit tests on `domain/` (event→notification mapping + idempotency key) — **real assertions**
- One integration-style test for the consumer dedupe (can use a test double for NATS)
- Handlers wired; `/internal/push` rejects missing/invalid service-JWT (test it)
- Update `PROGRESS.md`: tick §2.4 + add Completed-log row (what/files/verify)
- Don't commit unless asked

## v1 reference map (read-only)

- routes + handlers: `../guard-dispatch/services/notification/src/{main,handlers}.rs`
- FCM send: `.../src/fcm.rs` + `service::push_only/send_notification`
- the 10 trigger points: see `../guard-dispatch/CLAUDE.md` (booking `spawn_notification`)
- v2 rules: `CLAUDE.md` (this repo) Do/Don't + NATS topics + envelope

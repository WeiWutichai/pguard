# PHASE — web-admin `broadcast` screen (notification bulk-send)

> Build-ready spec. Promotes the `broadcast` screen from `ComingSoonPage` → real.
> Decisions locked by wei 2026-06-15:
> - **Audience source:** notification mints a service-JWT and calls **profile** to enumerate
>   `user_id`s per role (reuses profile's existing `/internal/*` service-JWT pattern). NOT a
>   local read-model, NOT token-only.
> - **Scope:** FULL design — audience picker + composer + **save-draft** + **schedule-later**
>   + sent/scheduled/draft **history** + audience **counts**.
>
> Recon verified against `main` (post-#71). All referenced patterns were read from the tree.

---

## 0. Why this shape

`notification` owns only `notification.fcm_tokens` (bare `user_id`, `device_type`) and
`notification.notification_logs` — **no role/user registry** (`migrations/notification/0001`).
So "all guards / all customers" must be resolved from **profile** (owns
`guard_profiles` + `customer_profiles`, both keyed by `user_id`). profile already exposes
service-JWT'd internals (`/internal/guards`, `/internal/users/{id}/export` — see
`services/profile/src/main.rs:106`), and `ServiceJwtConfig` carries an `encoding_key`
(`packages/shared-rust/src/config.rs:96`) so notification can MINT an outbound token via
`shared::service_jwt::encode_service_jwt("notification", &cfg.encoding_key, cfg.ttl_secs)`.

Per-recipient fan-out reuses the existing `repo::insert_log` + `deliver` (FCM) path
(`services/notification/src/api/mod.rs`). The `broadcasts` row is the campaign ledger.

---

## 1. profile-side — new internal endpoint (audience source)

**`GET /internal/profiles/recipients?audience=all|guards|customers`** — `ServiceCaller`-gated
(NOT public; the gateway already 404s `/internal/*`). Returns the `user_id`s for the audience
from profile's own tables.

- Handler: `api::internal_list_recipients::<S>` — mirror `internal_list_guards`
  (`services/profile/src/api/`), guarded by the `ServiceCaller` extractor.
- Repo: `repo::recipient_ids(db_read, audience)`:
  - `guards`    → `SELECT user_id FROM profile.guard_profiles`
  - `customers` → `SELECT user_id FROM profile.customer_profiles`
  - `all`       → `UNION` of both (distinct)
  - Use the **read pool** (`db_read`) — list read, replica-eligible (C5.3).
- Response DTO: `{ "audience": "guards", "count": 123, "user_ids": ["…uuid…"] }`.
- Route: add to `services/profile/src/main.rs` router next to the other `/internal/*` routes.
- **Note:** "guards" = rows in `guard_profiles` (every guard submits a profile to be approved);
  "customers" = rows in `customer_profiles` (auto-approve on first submit). Acceptable v2
  definition; documented here so it isn't mistaken for "all *approved*".
- Test (gated, hits PG): seed 1 guard + 1 customer profile, assert counts per audience; assert
  a missing/invalid service-JWT → 401 (reuse the notification `internal_push` guard tests shape).
- Contract: internal endpoints are NOT in the public OpenAPI (profile.yaml documents the edge
  surface only) — keep it out, like `/internal/guards`.

---

## 2. notification-side — broadcast endpoints + scheduler

### 2a. Outbound profile client (new module `src/profile_client.rs`)
Mint a service-JWT + GET profile's recipients. Reuse the booking→profile discovery caller as
the template (find it: `grep -rl encode_service_jwt services/` — booking discovery mints to call
`/internal/guards`). Needs a `PROFILE_INTERNAL_URL` env (default `http://profile:3002` in
compose; the gateway is NOT used for service-to-service). Add `http_client: reqwest::Client` to
`AppState` (notification already builds one for FCM in `main.rs` — store it in state instead of
only handing it to `FcmPusher`).

```rust
pub async fn fetch_recipients(http: &reqwest::Client, base: &str, cfg: &ServiceJwtConfig,
    audience: Audience) -> Result<Vec<Uuid>, AppError>
// mint encode_service_jwt("notification", &cfg.encoding_key, cfg.ttl_secs)
// GET {base}/internal/profiles/recipients?audience=… with Bearer; parse {user_ids}
```

### 2b. Models (`src/models.rs`)
- `Audience` enum (`all|guards|customers`) — serde snake_case, `as_db_str()` like
  `NotificationType` (DB enum cast pattern).
- `BroadcastStatus` enum (`draft|scheduled|sent`).
- `CreateBroadcastRequest { audience, title, body, notification_type?, send: SendMode }` where
  `SendMode = { now } | { draft } | { scheduled(at) }` (flatten or a `mode` + optional
  `scheduled_at`). Validate: `scheduled` ⇒ `scheduled_at` present and in the future.
- `BroadcastResponse` (`sqlx::FromRow`): id, audience, title, body, notification_type (text),
  status (text), scheduled_at?, recipient_count, created_by, created_at, sent_at?.
- `AudienceCountsResponse { all, guards, customers }`.

### 2c. Repo (`src/repo/` — new `broadcasts.rs` or extend `mod.rs`)
- `create_broadcast(db, created_by, req, status)` → row (status from SendMode).
- `list_broadcasts(db_read, limit, offset)` → newest-first ledger.
- `get_broadcast(db, id)`.
- `update_broadcast(db, id, fields)` — edit a **draft** only (guard `status='draft'`).
- `mark_sent(tx, id, recipient_count)` — set status='sent', sent_at=now().
- `claim_due_broadcasts(db)` — `SELECT … WHERE status='scheduled' AND scheduled_at<=now()
  FOR UPDATE SKIP LOCKED` (scheduler).
- `fan_out(state, broadcast)` — fetch recipients (2a) → for each: `insert_log` + `deliver`;
  return enqueued count. Insert logs in batches; push is best-effort (mirror `send_notification`).

### 2d. API (`src/api/mod.rs`) — all `AuthUser` + `role=="admin"` (same gate as `send_notification`)
- `POST   /admin/broadcasts`            → create. `now` ⇒ fan out immediately + mark_sent;
  `draft`/`scheduled` ⇒ persist only.
- `GET    /admin/broadcasts`            → list (history: drafts + scheduled + sent).
- `GET    /admin/broadcasts/{id}`       → one.
- `PUT    /admin/broadcasts/{id}`       → edit a draft (title/body/audience/schedule).
- `POST   /admin/broadcasts/{id}/send`  → send a draft/scheduled now.
- `GET    /admin/audience-counts`       → `{all,guards,customers}` (calls profile recipients,
  or a lighter profile count endpoint — counting via the recipients call is fine at v2 scale).

Role-gate 403 test for each (admin-only), mirroring this session's other admin endpoints.

### 2e. Scheduler (background task in `main.rs`)
Spawn alongside the NATS consumer: every ~30s, `claim_due_broadcasts` → `fan_out` → `mark_sent`
in a tx. This is state-changing work that owns its retry via the `status` ledger (NOT
fire-and-forget — CLAUDE.md). Log dropped/empty rounds.

### 2f. State (`src/state.rs`)
Add `http_client: reqwest::Client` + `profile_internal_url: String`. `service_jwt_config`
already present (currently decode-only; now also used to ENCODE — the field already holds
`encoding_key`).

---

## 3. api-gateway routing (`services/api-gateway/src/domain/routing.rs`)
Add two `RULES` entries → `Upstream::Notification` (already an upstream), `Tier::Api`:
- `prefix: "/admin/broadcasts"` (covers collection + `/{id}` + `/{id}/send` subpaths)
- `prefix: "/admin/audience-counts"`
Add routing tests mirroring `admin_calls_routes_to_calling` (assert upstream, fwd path,
`!public`, `Tier::Api`) + an `/internal` block test is already generic. `/admin/*` is NOT in
`PUBLIC_PATHS` → edge-protected automatically.

---

## 4. Contracts + codegen
- `contracts/openapi/notification.yaml`: add the 6 `/admin/broadcasts*` + `/admin/audience-counts`
  paths + schemas (Broadcast, CreateBroadcastRequest, AudienceCounts). bearerAuth. notification
  uses the shared `ApiResponse` envelope ({success,data}) — match the existing notification paths.
- `apps/web-admin/package.json` `gen:api`: **add `notification.yaml`** to the openapi-typescript
  list (notification is NOT currently generated for web-admin).
- `apps/web-admin/src/lib/api.ts`: add `notificationApi` (openapi-fetch client) like `callingApi`.
- Run `./tooling/codegen/generate.sh`; COMMIT regenerated TS (`apps/web-admin/src/api/generated/`)
  + Dart (`apps/mobile/lib/api/generated/`). The CI "Codegen stale-check" git-diffs these.

---

## 5. web-admin screen (`apps/web-admin/app/(dashboard)/broadcast/`)
**MANDATORY FIRST: read the real design** `redesign-pguard/project/pguard/<broadcast>.html`
(`ls redesign-pguard/project/pguard | grep -i broad`) before writing UI — build to the
generated CONTRACT, not the mockup, where they differ.
- Replace `page.tsx` (`ComingSoonPage`) with a real screen:
  - audience picker (all/guards/customers) showing live counts from `/admin/audience-counts`
  - composer (title, body, type) using `ui/` `Field/Input/Textarea/Button`
  - "send now" / "save draft" / "schedule" actions (a `Modal` for schedule datetime)
  - history `Table` of past broadcasts (audience chip, recipient_count via `fmtCappedCount`,
    status `Badge`, sent_at) with `Pagination`
- `copy.ts` for screen-local strings; add `broadcast.subtitle/empty/error` to the single-writer
  `src/lib/i18n.tsx` (TH + EN).
- All calls via `notificationApi` (generated client) + cookie/CSRF (`X-Requested-With`).
- e2e: add `tests/e2e/web/broadcast.spec.ts` (data-tolerant smoke, mirror `calls.spec.ts`).
  No `gap-pages.spec` to edit (all removed).

---

## 6. CI / env
- New `${VAR:?}` env? `PROFILE_INTERNAL_URL` has a code default (`http://profile:3002`) so no new
  required secret. If made required, add dummy to `ci.yml` + `.env.e2e` (rule in NEXT-SESSION).
- sqlx: new `query!` macros ⇒ `cargo sqlx prepare` to refresh the offline cache, commit `.sqlx`.
- `cargo fmt` + `cargo clippy -D warnings` + tests; `pnpm lint/typecheck/build`.

---

## 7. Execution order (single PR `feat/web-admin-broadcast`)
1. migration `0003_broadcasts.sql` (DONE — in tree)
2. profile internal recipients endpoint + gated test
3. notification: models → repo → profile_client → api → scheduler → main wiring + tests
4. gateway rules + routing tests
5. notification.yaml + codegen (TS+Dart) + web-admin gen:api/api.ts
6. broadcast screen + copy + i18n + e2e
7. `cargo sqlx prepare`, fmt, clippy, tests; pnpm checks
8. PROGRESS.md row + update `web-admin-keystone-screens` memory (17/22 real, 5 remaining)
9. branch, commit, push, PR, watch CI green (NO branch protection), merge manually

## 8. Out of scope (honest gaps → note, don't fake)
- per-broadcast read receipts / open-rate (no tracking)
- specific-user target picker (`adminSearchUsers`) — audience is role-level only this cut
- recurring schedules (one-shot `scheduled_at` only)

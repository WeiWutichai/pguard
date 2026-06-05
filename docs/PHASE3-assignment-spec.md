# Phase 3 — assignment lifecycle (finish booking) — work spec

> For Claude Code. **Not a new service** — finish the assignment lifecycle **inside the
> booking service** (service map: booking = requests + assignments + discovery). booking
> today has create/get/accept + `booking.completed`; the rest of the state machine is
> missing. Port semantics from v1 (read-only `../guard-dispatch/`). Don't merge.

## What exists vs missing (verified on disk)

- ✅ `/bookings` (create) · `/bookings/{id}` (get) · `/bookings/{id}/accept` · emits `booking.completed`, `job_accepted`
- ❌ missing transitions/endpoints: **decline · en_route · arrived · start · complete (review-completion) · cancel**, and their event emissions (asyncapi topics already exist).

## State machine (pure, in `domain/`)

```
pending_acceptance ──accept──► accepted ──en_route──► en_route ──arrived──► arrived
   │                   │                                                      │
   └──decline──►declined                                              start (work_started_at set)
   (request) ──cancel──► cancelled (from pre-arrival states)                  │
                                                              ──complete──► pending_completion
                                                customer review ──approve──► completed
                                                                ──reject──► back to arrived
```
- Mirror v1 semantics (incl. the v1 quirk that `start` sets `work_started_at` without
  leaving `arrived`, if you keep it — otherwise document the cleaner v2 transition).
- Illegal transitions → 409/400. 100% unit-testable, no IO imports.

## Endpoints to add (booking)

- `PUT /bookings/{id}/decline` (assigned guard) → status `declined`
- `PUT /bookings/{id}/status` (guard: `en_route`, `arrived`) — or discrete routes, your call
- `PUT /bookings/{id}/start` (guard) — set `work_started_at`
- `PUT /bookings/{id}/complete` (guard) → `pending_completion`
- `PUT /bookings/{id}/review-completion` (customer, `approve`|`reject`) — approve → `completed`
- `PUT /bookings/{id}/cancel` (customer/admin, pre-arrival only)
- Wire the customer-facing ones into api-gateway `/v1/...` so they're edge-reachable.

## Events (transactional outbox — same tx as the status write)

Emit on each transition: `booking.job_accepted` (exists), `booking.declined`,
`booking.guard_en_route`, `booking.arrived`, `booking.completed` (exists — keep its
`booked_hours` + `actual_seconds` payload that payment consumes), `booking.cancelled`.
notification consumes these for customer/guard pushes (already wired).

## Rules

- **Authz:** guard transitions (accept/decline/en_route/arrived/start/complete) require the
  caller to be the **assigned guard**; customer transitions (cancel/review-completion) require
  the **request owner**; admin may override. IDOR-check every one (no `_user: AuthUser`).
- `booking.completed` must stay idempotent-friendly for payment's consumer (don't change its shape).
- Per-service schema; no cross-service FK. No `.unwrap()` in request path. OTel span per request + tx.
- Update `contracts/openapi/booking.yaml` + `contracts/asyncapi/events.yaml` if payloads change.

## Definition of Done

- `cargo clippy --all-targets -D warnings` ✅ · `cargo test --workspace` ✅
- Domain tests: **every legal + illegal transition**; cancel allowed only pre-arrival; reject→arrived
- Authz tests: wrong-role / non-owner / non-assigned-guard rejected on each endpoint
- Integration (DB+NATS): each transition writes status + emits the right event via outbox;
  complete→`booking.completed` still drives payment finalization end-to-end
- Update `PROGRESS.md` (tick + Completed-log row) · run the 3 review agents, fix findings · push PR #2, don't merge

## v1 reference (read-only)

- `../guard-dispatch/services/booking/src/` — `accept_decline_assignment`, `update_assignment_status`,
  `start_job`, `review_completion`, `cancel_request`, and the `assignment_status` enum.
- v1 `CLAUDE.md` — assignment status transitions, the `started_at`/`work_started_at` quirk,
  the 10 notification trigger points, IDOR helper `is_guard_assigned`.

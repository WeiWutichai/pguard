# Phase 3 — rating service (work spec)

> For Claude Code. Build the **rating** service (currently a 34-line stub). Port from v1
> `../guard-dispatch/` (read-only) + apply v2 rules. Small, low-risk slice that closes
> more of the booking split. Don't edit `../guard-dispatch/`; don't merge.

## Scope

Reviews of guards by customers after a completed job, + admin moderation, + the rating
summary other services need for guard discovery.

## Layering (enforce)

`services/rating/src/` → `api/` (thin) · `domain/` (pure: validation, aggregation) ·
`repo/` (sqlx, owns the rating schema only) · `events/` (emit via outbox) · `models.rs`.

## Endpoints (port from v1)

- `POST /assignments/{id}/review` (customer) — submit a review **after the job is completed**.
  - Body: `overall_rating` (required, 1–5), optional `punctuality/professionalism/communication/appearance` (1–5), optional `review_text`.
  - **One review per assignment** — UNIQUE(assignment_id); second attempt → 409.
  - **Authoritative check (don't trust client):** read the assignment from booking via its
    `/internal/bookings/{id}` with **service-JWT** — verify the caller is the assignment's
    customer AND status is `completed`. Reject otherwise.
- `GET /guards/{id}/ratings` (public) — list visible reviews + summary (AVG overall, COUNT) — filter `is_visible = true`.
- `GET /admin/reviews` (admin) — list with filters (rating, visibility, search); stats computed on the **unfiltered** dataset (v1 rule).
- `PUT /admin/reviews/{id}/visibility` (admin) — toggle `is_visible`.
- `GET /internal/guards/{id}/rating-summary` (**service-JWT**) — AVG + COUNT of visible reviews, for booking's `available-guards` to consume. (Wiring booking→this is a noted follow-up, not required this slice.)

## v2 improvements / rules

- **Emit `pguard.events.rating.submitted`** through the **transactional outbox** (same tx as the INSERT). notification already consumes it → "คะแนนรีวิวใหม่" to the guard. Don't INSERT into notification schema directly.
- Per-service schema: new `rating` schema + migration under `contracts/db/migrations/rating/`. No cross-service FKs.
- Public discovery MUST filter `is_visible = true` (admin-hidden reviews never surface).
- Category ratings optional; only `overall_rating` required. CHECK 1..=5 on all.
- Domain holds validation + summary aggregation, pure + unit-tested. No `.unwrap()` in request path. OTel span per request + tx.
- Add `contracts/openapi/rating.yaml` (3.1) for the public + admin endpoints.

## Definition of Done

- `cargo clippy --all-targets -D warnings` ✅ · `cargo test --workspace` ✅ (new tests green)
- Unit tests (domain): rating range validation, one-per-assignment conflict, visibility filter in summary, summary AVG/COUNT math
- Integration (DB-gated): submit→`rating.submitted` row in outbox; admin visibility toggle hides from public summary
- Authz test: non-owner or non-completed assignment → rejected
- Update `PROGRESS.md` (tick + Completed-log row) · run the 3 review agents, fix findings · push to PR #2 (or follow-up branch), don't merge

## v1 reference (read-only)

- `../guard-dispatch/services/booking/src/` — `submit_review`, `list_admin_reviews`, `set_review_visibility`, and `list_available_guards` (the AVG/COUNT JOIN on `reviews.guard_reviews`).
- v1 `CLAUDE.md` — reviews table schema (migration 035 `is_visible`, UNIQUE assignment_id, category-optional) + admin reviews page rules (stats unfiltered, optimistic visibility toggle).
